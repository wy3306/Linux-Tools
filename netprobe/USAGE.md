# netprobe 使用说明

## 1. 二进制文件

当前目录 `dist/` 下已生成：

- `netprobe-linux-amd64`（Linux x86_64）
- `netprobe-linux-arm64`（Linux ARM64）
- `netprobe-linux-amd64.tar.gz`
- `netprobe-linux-arm64.tar.gz`

## 2. 运行方式

先加执行权限：

```bash
chmod +x ./netprobe-linux-amd64
# 或
chmod +x ./netprobe-linux-arm64
```

执行命令：

```bash
./netprobe-linux-amd64 -input 打通网络.xls -timeout 5s -workers 20 -output result.txt
```

参数说明：

- `-input`：输入表格路径，支持 `csv/xlsx`（扩展名为 `.xls` 但内容是 xlsx zip 也可解析）
- `-timeout`：连接超时，默认 `5s`
- `-workers`：并发探测协程数，默认 `50`
- `-output`：结果输出文件（txt），默认自动生成 `probe_result_时间戳.txt`

## 3. 表格识别规则

程序会优先根据列名识别：

- 源 IP：如 `源IP/源ip/源地址`
- 源映射地址：如 `源IP映射地址`
- 目标 IP：如 `目标IP/目标ip/目的IP`
- 目标映射地址：如 `目标IP映射地址`
- 目标端口：如 `目标端口`
- 协议类型：`协议类型`

若列名不固定，会按内容特征兜底识别（IP 格式、端口数字格式）。

## 4. 协议类型规则

当存在 `协议类型` 列时，按行决定探测协议：

- `TCP` -> TCP 探测
- `UDP` -> UDP 探测
- `TCP/UDP` 或 `TCP,UDP` -> 同时探测 TCP 和 UDP
- 空值或未识别 -> 默认 TCP

## 5. 探测逻辑

- 逐行处理表格
- 仅对“本机 IP 匹配该行源 IP（或源 IP 为空时匹配源映射地址）”的行执行探测
- 对匹配行执行笛卡尔积：
  - `(目标IP + 目标映射IP)` × `(目标端口列表)` × `(协议列表)`
- 每条结果同时输出到终端和 txt 文件

输出格式：

```text
源IP - 目标IP(目标IP/目标映射IP) - 协议/端口 - 成功|失败
```

## 6. 常见问题

1) 提示“没有可执行的探测任务”
- 一般是本机 IP 没有匹配上表格源 IP；或该行目标/端口为空。

2) UDP 成功是否代表应用一定可用
- UDP 探测基于 UDP 发包可达性，不等价于上层业务协议可用性。
