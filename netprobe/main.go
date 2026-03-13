package main

import (
	"archive/zip"
	"bufio"
	"encoding/csv"
	"encoding/xml"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	xls "github.com/extrame/xls"
)

type table struct {
	Rows [][]string
}

type columnRole string

const (
	roleUnknown columnRole = "unknown"
	roleSrcIP   columnRole = "src_ip"
	roleSrcMap  columnRole = "src_map_ip"
	roleDstIP   columnRole = "dst_ip"
	roleDstMap  columnRole = "dst_map_ip"
	roleSrcPort columnRole = "src_port"
	roleDstPort columnRole = "dst_port"
	roleProto   columnRole = "proto"
)

type detectedColumns struct {
	srcIPCol    int
	srcMapCol   int
	dstIPCol    int
	dstMapCol   int
	dstPortCol  int
	protoCol    int
	headerRow   int
	fromHeaders bool
}

type targetAddr struct {
	IP    string
	Label string
}

type probeTask struct {
	SourceIP string
	TargetIP string
	TargetAs string
	Port     int
	Proto    string
}

type probeResult struct {
	Task    probeTask
	Success bool
	Err     error
}

var (
	ipRegex       = regexp.MustCompile(`(?:\d{1,3}\.){3}\d{1,3}`)
	portRegex     = regexp.MustCompile(`\b\d{1,5}\b`)
	splitterRegex = regexp.MustCompile(`[\s,，;；/\\|]+`)
)

func main() {
	input := flag.String("input", defaultInputPath(), "输入文件路径，支持 csv / xlsx(扩展名可为 .xls/.xlsx)")
	timeout := flag.Duration("timeout", 5*time.Second, "连接超时时间")
	workers := flag.Int("workers", 50, "并发探测协程数")
	output := flag.String("output", "", "输出txt文件路径，默认自动生成")
	flag.Parse()

	tbl, err := readTable(*input)
	if err != nil {
		fatalf("读取表格失败: %v", err)
	}
	if len(tbl.Rows) == 0 {
		fatalf("表格为空")
	}

	cols := detectColumns(tbl)
	printColumnDetection(cols)

	if cols.srcIPCol < 0 && cols.srcMapCol < 0 {
		fatalf("未识别到源IP列(或源IP映射列)，无法进行源端匹配")
	}
	if cols.dstIPCol < 0 && cols.dstMapCol < 0 {
		fatalf("未识别到目标IP列(或目标IP映射列)")
	}
	if cols.dstPortCol < 0 {
		fmt.Println("提示: 未明确识别到目标端口列，将尝试从目标IP相关单元格中提取端口")
	}
	if cols.protoCol < 0 {
		fmt.Println("提示: 未识别到协议类型列，默认按 TCP 探测")
	}

	localIPs := getLocalIPv4Set()
	if len(localIPs) == 0 {
		fatalf("未获取到本机IPv4地址")
	}

	outPath := *output
	if strings.TrimSpace(outPath) == "" {
		outPath = fmt.Sprintf("probe_result_%s.txt", time.Now().Format("20060102_150405"))
	}
	outFile, err := os.Create(outPath)
	if err != nil {
		fatalf("创建输出文件失败: %v", err)
	}
	defer outFile.Close()
	writer := bufio.NewWriter(outFile)
	defer writer.Flush()

	tasks := buildTasks(tbl, cols, localIPs)
	if len(tasks) == 0 {
		fatalf("没有可执行的探测任务: 可能本机IP未匹配任何源IP，或数据列为空")
	}

	results := runProbes(tasks, *timeout, max(1, *workers))

	succ := 0
	for _, r := range results {
		line := formatResultLine(r)
		fmt.Println(line)
		_, _ = writer.WriteString(line + "\n")
		if r.Success {
			succ++
		}
	}
	_ = writer.Flush()

	fmt.Printf("\n完成: 总任务=%d, 成功=%d, 失败=%d\n", len(results), succ, len(results)-succ)
	fmt.Printf("结果文件: %s\n", outPath)
}

func defaultInputPath() string {
	candidates := []string{"网络打通.xls", "打通网络.xls", "网络打通.xlsx", "打通网络.xlsx"}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return "打通网络.xls"
}

func readTable(path string) (table, error) {
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".csv":
		return readCSV(path)
	case ".xlsx":
		return readExcelLike(path)
	case ".xls":
		// 优先按老式 BIFF .xls 读取，失败再按 xlsx(zip) 兼容读取
		if t, err := readXLSBIFF(path); err == nil {
			return t, nil
		}
		return readExcelLike(path)
	default:
		// 兜底顺序：xlsx(zip) -> xls(BIFF) -> csv
		if t, err := readExcelLike(path); err == nil {
			return t, nil
		}
		if t, err := readXLSBIFF(path); err == nil {
			return t, nil
		}
		return readCSV(path)
	}
}

func readCSV(path string) (table, error) {
	f, err := os.Open(path)
	if err != nil {
		return table{}, err
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.FieldsPerRecord = -1
	rows, err := r.ReadAll()
	if err != nil {
		return table{}, err
	}
	normalizeRows(rows)
	return table{Rows: rows}, nil
}

func readExcelLike(path string) (table, error) {
	z, err := zip.OpenReader(path)
	if err != nil {
		return table{}, err
	}
	defer z.Close()

	shared, _ := readSharedStrings(z.File)
	sheets, err := listWorksheetFiles(z.File)
	if err != nil {
		return table{}, err
	}
	if len(sheets) == 0 {
		return table{}, errors.New("未找到工作表")
	}

	best := [][]string{}
	for _, sheetFile := range sheets {
		rows, err := readSheetRows(z.File, sheetFile, shared)
		if err != nil {
			continue
		}
		normalizeRows(rows)
		if scoreRows(rows) > scoreRows(best) {
			best = rows
		}
	}
	if len(best) == 0 {
		return table{}, errors.New("工作表无可用数据")
	}
	return table{Rows: best}, nil
}

func readXLSBIFF(path string) (table, error) {
	wb, err := xls.Open(path, "utf-8")
	if err != nil {
		return table{}, err
	}
	best := [][]string{}
	for i := 0; i < wb.NumSheets(); i++ {
		sheet := wb.GetSheet(i)
		if sheet == nil {
			continue
		}
		rows := make([][]string, 0, int(sheet.MaxRow)+1)
		for r := 0; r <= int(sheet.MaxRow); r++ {
			row := sheet.Row(r)
			if row == nil {
				rows = append(rows, []string{})
				continue
			}
			last := row.LastCol()
			arr := make([]string, last)
			for c := 0; c < last; c++ {
				arr[c] = row.Col(c)
			}
			rows = append(rows, arr)
		}
		normalizeRows(rows)
		if scoreRows(rows) > scoreRows(best) {
			best = rows
		}
	}
	if len(best) == 0 {
		return table{}, errors.New("xls工作表无可用数据")
	}
	return table{Rows: best}, nil
}

func scoreRows(rows [][]string) int {
	s := 0
	for _, r := range rows {
		nonEmpty := 0
		for _, c := range r {
			if strings.TrimSpace(c) != "" {
				nonEmpty++
			}
		}
		if nonEmpty >= 2 {
			s += nonEmpty
		}
	}
	return s
}

func normalizeRows(rows [][]string) {
	maxCols := 0
	for i := range rows {
		for j := range rows[i] {
			rows[i][j] = strings.TrimSpace(strings.ReplaceAll(rows[i][j], "\u00a0", " "))
		}
		if len(rows[i]) > maxCols {
			maxCols = len(rows[i])
		}
	}
	for i := range rows {
		if len(rows[i]) < maxCols {
			pad := make([]string, maxCols-len(rows[i]))
			rows[i] = append(rows[i], pad...)
		}
	}
}

type relsRelationships struct {
	XMLName xml.Name           `xml:"Relationships"`
	Rels    []relsRelationship `xml:"Relationship"`
}

type relsRelationship struct {
	ID     string `xml:"Id,attr"`
	Type   string `xml:"Type,attr"`
	Target string `xml:"Target,attr"`
}

type workbookXML struct {
	Sheets []workbookSheet `xml:"sheets>sheet"`
}

type workbookSheet struct {
	Name string `xml:"name,attr"`
	RID  string `xml:"id,attr"`
}

func listWorksheetFiles(files []*zip.File) ([]string, error) {
	wbData, err := readZipFile(files, "xl/workbook.xml")
	if err != nil {
		return nil, err
	}
	relsData, err := readZipFile(files, "xl/_rels/workbook.xml.rels")
	if err != nil {
		return nil, err
	}
	var wb workbookXML
	if err := xml.Unmarshal(wbData, &wb); err != nil {
		return nil, err
	}
	var rels relsRelationships
	if err := xml.Unmarshal(relsData, &rels); err != nil {
		return nil, err
	}
	ridToTarget := make(map[string]string)
	for _, r := range rels.Rels {
		target := strings.TrimPrefix(r.Target, "/")
		if !strings.HasPrefix(target, "xl/") {
			target = "xl/" + strings.TrimPrefix(target, "./")
		}
		ridToTarget[r.ID] = target
	}

	out := make([]string, 0, len(wb.Sheets))
	for _, s := range wb.Sheets {
		if tgt, ok := ridToTarget[s.RID]; ok {
			out = append(out, tgt)
		}
	}
	if len(out) > 0 {
		return out, nil
	}

	// 兜底：按文件名找 sheet*.xml
	for _, f := range files {
		if strings.HasPrefix(f.Name, "xl/worksheets/") && strings.HasSuffix(f.Name, ".xml") {
			out = append(out, f.Name)
		}
	}
	sort.Strings(out)
	return out, nil
}

func readSharedStrings(files []*zip.File) ([]string, error) {
	data, err := readZipFile(files, "xl/sharedStrings.xml")
	if err != nil {
		return nil, err
	}
	type si struct {
		T string `xml:"t"`
		R []struct {
			T string `xml:"t"`
		} `xml:"r"`
	}
	type sst struct {
		SI []si `xml:"si"`
	}
	var x sst
	if err := xml.Unmarshal(data, &x); err != nil {
		return nil, err
	}
	out := make([]string, 0, len(x.SI))
	for _, v := range x.SI {
		if v.T != "" {
			out = append(out, v.T)
			continue
		}
		var b strings.Builder
		for _, r := range v.R {
			b.WriteString(r.T)
		}
		out = append(out, b.String())
	}
	return out, nil
}

func readSheetRows(files []*zip.File, sheetPath string, shared []string) ([][]string, error) {
	data, err := readZipFile(files, sheetPath)
	if err != nil {
		return nil, err
	}
	type c struct {
		R  string `xml:"r,attr"`
		T  string `xml:"t,attr"`
		V  string `xml:"v"`
		IS struct {
			T string `xml:"t"`
		} `xml:"is"`
	}
	type row struct {
		R int `xml:"r,attr"`
		C []c `xml:"c"`
	}
	type worksheet struct {
		Rows []row `xml:"sheetData>row"`
	}
	var ws worksheet
	if err := xml.Unmarshal(data, &ws); err != nil {
		return nil, err
	}

	maxCol := 0
	for _, rw := range ws.Rows {
		for _, cell := range rw.C {
			col := cellRefToColIndex(cell.R)
			if col > maxCol {
				maxCol = col
			}
		}
	}
	if maxCol < 0 {
		maxCol = 0
	}

	rows := make([][]string, 0, len(ws.Rows))
	for _, rw := range ws.Rows {
		arr := make([]string, maxCol+1)
		for _, cell := range rw.C {
			col := cellRefToColIndex(cell.R)
			if col < 0 || col >= len(arr) {
				continue
			}
			arr[col] = decodeCellValue(cell, shared)
		}
		rows = append(rows, arr)
	}
	return rows, nil
}

func decodeCellValue(cell struct {
	R  string `xml:"r,attr"`
	T  string `xml:"t,attr"`
	V  string `xml:"v"`
	IS struct {
		T string `xml:"t"`
	} `xml:"is"`
}, shared []string) string {
	switch cell.T {
	case "s":
		i, err := strconv.Atoi(strings.TrimSpace(cell.V))
		if err == nil && i >= 0 && i < len(shared) {
			return shared[i]
		}
		return ""
	case "inlineStr":
		return cell.IS.T
	default:
		return cell.V
	}
}

func readZipFile(files []*zip.File, name string) ([]byte, error) {
	for _, f := range files {
		if f.Name == name {
			rc, err := f.Open()
			if err != nil {
				return nil, err
			}
			defer rc.Close()
			return io.ReadAll(rc)
		}
	}
	return nil, fmt.Errorf("zip entry not found: %s", name)
}

func cellRefToColIndex(ref string) int {
	if ref == "" {
		return -1
	}
	letters := make([]rune, 0, len(ref))
	for _, r := range ref {
		if r >= 'A' && r <= 'Z' {
			letters = append(letters, r)
		} else if r >= 'a' && r <= 'z' {
			letters = append(letters, r-'a'+'A')
		} else {
			break
		}
	}
	if len(letters) == 0 {
		return -1
	}
	col := 0
	for _, r := range letters {
		col = col*26 + int(r-'A'+1)
	}
	return col - 1
}

func detectColumns(t table) detectedColumns {
	res := detectedColumns{srcIPCol: -1, srcMapCol: -1, dstIPCol: -1, dstMapCol: -1, dstPortCol: -1, protoCol: -1, headerRow: -1}

	headerRow, matches := findBestHeaderRow(t.Rows)
	if headerRow >= 0 && matches > 0 {
		res.headerRow = headerRow
		res.fromHeaders = true
		headers := t.Rows[headerRow]
		for i, h := range headers {
			role := classifyHeader(h)
			switch role {
			case roleSrcIP:
				if res.srcIPCol < 0 {
					res.srcIPCol = i
				}
			case roleSrcMap:
				if res.srcMapCol < 0 {
					res.srcMapCol = i
				}
			case roleDstIP:
				if res.dstIPCol < 0 {
					res.dstIPCol = i
				}
			case roleDstMap:
				if res.dstMapCol < 0 {
					res.dstMapCol = i
				}
			case roleDstPort:
				if res.dstPortCol < 0 {
					res.dstPortCol = i
				}
			case roleProto:
				if res.protoCol < 0 {
					res.protoCol = i
				}
			}
		}
	}

	// 内容推断兜底
	if res.srcIPCol < 0 || res.dstIPCol < 0 || res.dstPortCol < 0 {
		inferByData(t.Rows, &res)
	}

	return res
}

func findBestHeaderRow(rows [][]string) (int, int) {
	bestRow, bestScore := -1, 0
	limit := min(len(rows), 15)
	for i := 0; i < limit; i++ {
		score := 0
		for _, c := range rows[i] {
			if classifyHeader(c) != roleUnknown {
				score++
			}
		}
		if score > bestScore {
			bestScore = score
			bestRow = i
		}
	}
	return bestRow, bestScore
}

func classifyHeader(header string) columnRole {
	n := normalizeHeader(header)
	if n == "" {
		return roleUnknown
	}

	if containsAny(n, []string{"源ip映射", "源映射", "源nat", "源地址映射", "源端映射"}) {
		return roleSrcMap
	}
	if containsAny(n, []string{"目标ip映射", "目标映射", "目的映射", "目标地址映射", "目标端映射"}) {
		return roleDstMap
	}
	if containsAny(n, []string{"源端口"}) {
		return roleSrcPort
	}
	if containsAny(n, []string{"目标端口", "目的端口"}) {
		return roleDstPort
	}
	if containsAny(n, []string{"协议类型", "协议", "protocol", "proto"}) {
		return roleProto
	}
	if containsAny(n, []string{"源ip", "源地址", "源主机", "来源ip"}) {
		return roleSrcIP
	}
	if containsAny(n, []string{"目标ip", "目的ip", "目标地址", "目的地址"}) {
		return roleDstIP
	}

	// 更泛化的端口字段，但优先避免把源端口判成目标端口
	if strings.Contains(n, "端口") && !strings.Contains(n, "源") {
		return roleDstPort
	}
	return roleUnknown
}

func normalizeHeader(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	rep := []string{" ", "\t", "\n", "\r", "（", "）", "(", ")", "：", ":", "_", "-"}
	for _, r := range rep {
		s = strings.ReplaceAll(s, r, "")
	}
	return s
}

func containsAny(s string, keys []string) bool {
	for _, k := range keys {
		if strings.Contains(s, k) {
			return true
		}
	}
	return false
}

type colStat struct {
	idx        int
	ipHits     int
	portHits   int
	nonEmpty   int
	headerRole columnRole
}

func inferByData(rows [][]string, res *detectedColumns) {
	if len(rows) == 0 {
		return
	}
	start := 0
	if res.headerRow >= 0 {
		start = res.headerRow + 1
	}
	colCount := len(rows[0])
	stats := make([]colStat, colCount)
	for i := 0; i < colCount; i++ {
		stats[i].idx = i
	}

	for r := start; r < len(rows); r++ {
		for c := 0; c < colCount; c++ {
			v := strings.TrimSpace(rows[r][c])
			if v == "" {
				continue
			}
			stats[c].nonEmpty++
			if len(extractIPs(v)) > 0 {
				stats[c].ipHits++
			}
			if len(extractPorts(v)) > 0 {
				stats[c].portHits++
			}
		}
	}

	ipCols := make([]colStat, 0)
	portCols := make([]colStat, 0)
	for _, st := range stats {
		if st.nonEmpty == 0 {
			continue
		}
		if float64(st.ipHits)/float64(st.nonEmpty) >= 0.3 {
			ipCols = append(ipCols, st)
		}
		if float64(st.portHits)/float64(st.nonEmpty) >= 0.3 {
			portCols = append(portCols, st)
		}
	}

	sort.Slice(ipCols, func(i, j int) bool {
		if ipCols[i].ipHits == ipCols[j].ipHits {
			return ipCols[i].idx < ipCols[j].idx
		}
		return ipCols[i].ipHits > ipCols[j].ipHits
	})
	sort.Slice(portCols, func(i, j int) bool {
		if portCols[i].portHits == portCols[j].portHits {
			return portCols[i].idx < portCols[j].idx
		}
		return portCols[i].portHits > portCols[j].portHits
	})

	if res.srcIPCol < 0 && len(ipCols) >= 1 {
		res.srcIPCol = ipCols[0].idx
	}
	if res.dstIPCol < 0 && len(ipCols) >= 2 {
		res.dstIPCol = ipCols[1].idx
	}
	if res.dstMapCol < 0 && len(ipCols) >= 3 {
		res.dstMapCol = ipCols[2].idx
	}
	if res.dstPortCol < 0 && len(portCols) >= 1 {
		res.dstPortCol = portCols[0].idx
	}
}

func printColumnDetection(c detectedColumns) {
	fmt.Printf("列识别: headerRow=%d, fromHeaders=%v, srcIP=%d, srcMap=%d, dstIP=%d, dstMap=%d, dstPort=%d, proto=%d\n",
		c.headerRow, c.fromHeaders, c.srcIPCol, c.srcMapCol, c.dstIPCol, c.dstMapCol, c.dstPortCol, c.protoCol)
}

func getLocalIPv4Set() map[string]struct{} {
	out := map[string]struct{}{}
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return out
	}
	for _, a := range addrs {
		ipnet, ok := a.(*net.IPNet)
		if !ok {
			continue
		}
		ip := ipnet.IP.To4()
		if ip == nil {
			continue
		}
		out[ip.String()] = struct{}{}
	}
	return out
}

func buildTasks(t table, cols detectedColumns, localIPs map[string]struct{}) []probeTask {
	startRow := 0
	if cols.headerRow >= 0 {
		startRow = cols.headerRow + 1
	}
	tasks := make([]probeTask, 0)
	seen := map[string]struct{}{}

	for r := startRow; r < len(t.Rows); r++ {
		row := t.Rows[r]

		srcPrimary := extractByCol(row, cols.srcIPCol, extractIPs)
		srcMap := extractByCol(row, cols.srcMapCol, extractIPs)
		srcIPs := srcPrimary
		if len(srcIPs) == 0 && len(srcMap) > 0 {
			srcIPs = srcMap
		}
		if len(srcIPs) == 0 {
			continue
		}

		matchedSrc := make([]string, 0)
		for _, ip := range srcIPs {
			if _, ok := localIPs[ip]; ok {
				matchedSrc = append(matchedSrc, ip)
			}
		}
		if len(matchedSrc) == 0 {
			continue
		}

		targets := make([]targetAddr, 0)
		for _, ip := range extractByCol(row, cols.dstIPCol, extractIPs) {
			targets = append(targets, targetAddr{IP: ip, Label: "目标IP"})
		}
		for _, ip := range extractByCol(row, cols.dstMapCol, extractIPs) {
			targets = append(targets, targetAddr{IP: ip, Label: "目标映射IP"})
		}
		if len(targets) == 0 {
			continue
		}

		ports := extractByCol(row, cols.dstPortCol, extractPorts)
		if len(ports) == 0 {
			fallback := strings.Join([]string{valueAt(row, cols.dstIPCol), valueAt(row, cols.dstMapCol)}, ",")
			ports = extractPorts(fallback)
		}
		if len(ports) == 0 {
			continue
		}
		protos := extractProtocols(valueAt(row, cols.protoCol))
		if len(protos) == 0 {
			protos = []string{"tcp"}
		}

		for _, src := range dedupeStrings(matchedSrc) {
			for _, tAddr := range dedupeTargets(targets) {
				for _, proto := range dedupeStrings(protos) {
					for _, p := range dedupeInts(ports) {
						k := fmt.Sprintf("%s|%s|%s|%s|%d", src, tAddr.Label, tAddr.IP, proto, p)
						if _, ok := seen[k]; ok {
							continue
						}
						seen[k] = struct{}{}
						tasks = append(tasks, probeTask{
							SourceIP: src,
							TargetIP: tAddr.IP,
							TargetAs: tAddr.Label,
							Port:     p,
							Proto:    proto,
						})
					}
				}
			}
		}
	}
	return tasks
}

func extractByCol[T any](row []string, col int, fn func(string) []T) []T {
	if col < 0 || col >= len(row) {
		return nil
	}
	return fn(row[col])
}

func valueAt(row []string, col int) string {
	if col < 0 || col >= len(row) {
		return ""
	}
	return row[col]
}

func extractIPs(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	result := make([]string, 0)

	for _, ip := range ipRegex.FindAllString(s, -1) {
		ip = strings.TrimSpace(ip)
		if isValidIPv4(ip) {
			result = append(result, ip)
		}
	}
	if len(result) > 0 {
		return dedupeStrings(result)
	}

	for _, tok := range splitterRegex.Split(s, -1) {
		tok = strings.TrimSpace(strings.Trim(tok, "[]()"))
		if tok == "" {
			continue
		}
		if h, _, err := net.SplitHostPort(tok); err == nil {
			tok = h
		}
		if isValidIPv4(tok) {
			result = append(result, tok)
		}
	}
	return dedupeStrings(result)
}

func extractPorts(s string) []int {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	out := make([]int, 0)
	for _, m := range portRegex.FindAllString(s, -1) {
		p, err := strconv.Atoi(m)
		if err != nil {
			continue
		}
		if p >= 1 && p <= 65535 {
			out = append(out, p)
		}
	}
	if len(out) > 0 {
		return dedupeInts(out)
	}
	for _, tok := range splitterRegex.Split(s, -1) {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		p, err := strconv.Atoi(tok)
		if err != nil {
			continue
		}
		if p >= 1 && p <= 65535 {
			out = append(out, p)
		}
	}
	return dedupeInts(out)
}

func extractProtocols(s string) []string {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" {
		return nil
	}
	tokens := splitterRegex.Split(s, -1)
	out := make([]string, 0, len(tokens))
	for _, tok := range tokens {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		switch tok {
		case "tcp", "udp":
			out = append(out, tok)
		case "any", "all", "tcpudp", "tcp/udp", "udp/tcp":
			out = append(out, "tcp", "udp")
		}
	}
	return dedupeStrings(out)
}

func localAddrForProtocol(network, sourceIP string) net.Addr {
	ip := net.ParseIP(sourceIP)
	if ip == nil {
		return nil
	}
	if network == "udp" {
		return &net.UDPAddr{IP: ip}
	}
	return &net.TCPAddr{IP: ip}
}

func isValidIPv4(ip string) bool {
	parsed := net.ParseIP(ip)
	return parsed != nil && parsed.To4() != nil
}

func dedupeStrings(in []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(in))
	for _, v := range in {
		v = strings.TrimSpace(v)
		if v == "" {
			continue
		}
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

func dedupeInts(in []int) []int {
	seen := map[int]struct{}{}
	out := make([]int, 0, len(in))
	for _, v := range in {
		if _, ok := seen[v]; ok {
			continue
		}
		seen[v] = struct{}{}
		out = append(out, v)
	}
	sort.Ints(out)
	return out
}

func dedupeTargets(in []targetAddr) []targetAddr {
	seen := map[string]struct{}{}
	out := make([]targetAddr, 0, len(in))
	for _, v := range in {
		k := v.Label + "|" + v.IP
		if _, ok := seen[k]; ok {
			continue
		}
		seen[k] = struct{}{}
		out = append(out, v)
	}
	return out
}

func runProbes(tasks []probeTask, timeout time.Duration, workers int) []probeResult {
	in := make(chan probeTask)
	out := make(chan probeResult)
	var wg sync.WaitGroup

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for t := range in {
				ok, err := probeOne(t, timeout)
				out <- probeResult{Task: t, Success: ok, Err: err}
			}
		}()
	}

	go func() {
		for _, t := range tasks {
			in <- t
		}
		close(in)
		wg.Wait()
		close(out)
	}()

	results := make([]probeResult, 0, len(tasks))
	for r := range out {
		results = append(results, r)
	}
	sort.Slice(results, func(i, j int) bool {
		a, b := results[i].Task, results[j].Task
		if a.SourceIP != b.SourceIP {
			return a.SourceIP < b.SourceIP
		}
		if a.TargetAs != b.TargetAs {
			return a.TargetAs < b.TargetAs
		}
		if a.TargetIP != b.TargetIP {
			return a.TargetIP < b.TargetIP
		}
		if a.Proto != b.Proto {
			return a.Proto < b.Proto
		}
		return a.Port < b.Port
	})
	return results
}

func probeOne(t probeTask, timeout time.Duration) (bool, error) {
	network := strings.ToLower(strings.TrimSpace(t.Proto))
	if network == "" {
		network = "tcp"
	}
	dialer := &net.Dialer{
		Timeout:   timeout,
		LocalAddr: localAddrForProtocol(network, t.SourceIP),
	}
	addr := net.JoinHostPort(t.TargetIP, strconv.Itoa(t.Port))
	conn, err := dialer.Dial(network, addr)
	if err != nil {
		return false, err
	}
	if network == "udp" {
		if _, err := conn.Write([]byte{0}); err != nil {
			_ = conn.Close()
			return false, err
		}
	}
	_ = conn.Close()
	return true, nil
}

func formatResultLine(r probeResult) string {
	status := "成功"
	if !r.Success {
		status = "失败"
	}
	base := fmt.Sprintf("%s - %s(%s) - %s/%d - %s", r.Task.SourceIP, r.Task.TargetIP, r.Task.TargetAs, strings.ToUpper(r.Task.Proto), r.Task.Port, status)
	if r.Err != nil {
		return base + " - " + r.Err.Error()
	}
	return base
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
