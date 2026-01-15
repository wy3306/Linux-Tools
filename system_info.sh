# ======================================================================
# Author:       魏姚
# Email:        qluogxbd@gmail.com
# Description:  系统巡检脚本
# Date:         2025-02-13
# Version:      1.0.7
# Notes:        脚本是在windows下编写的，直接复制或复制内容到在linux下运行可能存在问题
#               如果存在问题，请先安装 dos2unix 再运行dos2unix system_info.sh转换格式
#               yum install dos2unix -y （centos）
#               apt-get install dos2unix -y （ubuntu）
#
#               邮件API: http://info.weiyaonas.xyz/api/upload 域名有效期一年 2026-01-26 07:59:59 过期
#               到期后如果不能使用，请联系作者
#
#               本脚本适配centos、kylin、ubuntu系统
#               若在ubuntu系统下运行，请使用bash system_info.sh 运行 使用sh system_info.sh 运行可能会出现未知错误
# ======================================================================
echo "                    本脚本适配centos、kylin、ubuntu系统"
echo "若在ubuntu系统下运行,请使用bash system_info.sh 运行 使用sh system_info.sh 运行可能会出现未知错误"
echo "如果存在问题，请先安装 dos2unix 再 运行 dos2unix system_info.sh转换格式"
echo "======================================================================"
echo "======================================================================"
echo "======================================================================"
echo "====================== 正在生成系统巡检报告请稍等======================"
echo " "
echo " "
echo " "
# 日志文件路径
LOG_FILE="/opt/system_inspection_$(date +%F_%H-%M-%S).log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 系统类型检测
OS_TYPE=""
if [ -f /etc/os-release ]; then
    OS_TYPE=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
elif [ -f /etc/centos-release ]; then
    OS_TYPE="centos"
elif [ -f /etc/kylin-release ]; then
    OS_TYPE="kylin"
fi
# 系统版本变量
VERSION_ID=""
if [ -f /etc/os-release ]; then
# 使用 cut 命令将匹配到的行按 = 分割成两部分，并取第二部分（即版本号） 最后，使用 tr 命令删除结果中的双引号 ("), 以便得到干净的版本号
    VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
fi

# 虚拟化平台变量
VIRTUAL=""
hostnamectl|awk 'NR==6{print $NF}' &>/dev/null
if [ $? -eq 0 ]; then
    VIRTUAL=$(hostnamectl|awk 'NR==6{print $NF}')
else
    VIRTUAL="未使用虚拟化"
fi
# DNS 如果有多个DNS，显示在同一行
DNS=$(cat /etc/resolv.conf | grep "nameserver" | awk '{print $2}' | paste -sd "," -)

# 日志记录函数 # 利用tree -a 命令，将日志文件输出到终端并保存到日志文件中
log() {
    local level=$1
    local message=$2
    case $level in
        "INFO")  echo -e "[$(date +%T)] ${GREEN}[INFO]${NC} $message" >> $LOG_FILE 2>&1 ;;
        "WARN")  echo -e "[$(date +%T)] ${YELLOW}[WARN]${NC} $message" >> $LOG_FILE 2>&1 ;;
        "ERROR") echo -e "[$(date +%T)] ${RED}[ERROR]${NC} $message" >> $LOG_FILE 2>&1 ;;
        *)       echo "$message" | tee -a $LOG_FILE ;;
    esac
}

# 命令兼容性检查
check_command() {
    if ! command -v $1 &> /dev/null; then
        log "ERROR" "命令 $1 不存在，跳过相关检查"
        return 1
    fi
    return 0
}

# 获取外网ip
IPv4=""
get_public_ip(){
    ping -c1 -w1 ip.sb &>/dev/null
    if [ $? -eq 0 ]; then
        IPv4=$(curl -s ip.sb)
    else
        ping -c1 -w1 ipinfo.io &>/dev/null
        if [ $? -eq 0 ]; then
            IPv4=$(curl -s ipinfo.io | sed -n 's/.*ip": "\(.*\)",.*/\1/p')
        else
            IPv4="获取失败"
        fi
    fi
}

# 网络状态
NETWORK_STATUS=""
ping -c1 -w1 223.5.5.5 &>/dev/null
if [ $? -eq 0 ]; then
    NETWORK_STATUS="外网访问正常"
else
    NETWORK_STATUS="外网访问异常"
fi
# 邮件系统 发送日志文件
mail_sent(){
email=$1
if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    return 10
fi

filepath=$LOG_FILE
if [ ! -e "$filepath" ]; then
    echo "文件路径不存在"
    return 20
fi

# 打包目录或单文件处理
if [ -d "$filepath" ]; then
    tmpfile=$(mktemp)
    tar czf "$tmpfile" -C "$(dirname "$filepath")" "$(basename "$filepath")"
    curl -F "file=@$tmpfile" -F "email=$email" http://info.weiyaonas.xyz/api/upload &> /dev/null
    rm -f "$tmpfile"
    return 2
elif [ -f "$filepath" ]; then
    curl -F "file=@$filepath" -F "email=$email" http://info.weiyaonas.xyz/api/upload &> /dev/null
    return 2
fi
}

# 获取外网ip
get_public_ip

#------------------ 巡检开始 ------------------#
{
echo "====================== 系统巡检报告 ======================="
echo -e "\t\t生成时间: $(date '+%F %T')"
echo -e "\t\t操作系统: $([ -n "$OS_TYPE" ] && echo $OS_TYPE || echo "未知")"
echo -e "\t\t系统版本: $([ -n "$VERSION_ID" ] && echo $VERSION_ID || echo "未知")"
echo -e "\t\t主机名: $(hostname)"
echo -e "\t\t网络状态: $NETWORK_STATUS"
echo -e "\t\t外网IP: $IPv4"
echo -e "\t\tIP地址: $(hostname -I | awk '{print $1}')"
echo -e "\t\tDNS: $DNS"
echo -e "\t\t虚拟化平台: $VIRTUAL"
echo "=========================================================="
# [1] 系统资源
log INFO "==================== 系统资源 ===================="
log INFO "负载: $(uptime | awk -F'load average:' '{print $2}')"
log INFO "运行时长: $(uptime -p)"
log INFO "内存使用: $(free -h | awk '/Mem/{printf "内存使用: %s/%s (%.2f%%)\n", $3, $2, $3/$2*100}')"
log INFO "根分区使用率: $(df -hT / | awk 'NR==2{printf "根分区使用率: %s (%s/%s)\n", $6, $3, $2}')"

# [2] 服务状态 (适配不同系统)
log INFO "==================== 服务状态 ===================="
case $OS_TYPE in
    "centos"|"kylin")
        # 遍历所有需要巡检的服务
        services=("sshd" "crond" "nginx" "docker" "mysqld" "redis-server" "php-fpm")
        for srv in "${services[@]}"; do
            if systemctl is-active $srv &>/dev/null; then
                log INFO "服务 $srv 状态: $(systemctl is-active $srv)"
            else
                log WARN "服务 $srv 未运行"
            fi
        done
        ;;
    "ubuntu")
        services=("ssh" "cron" "apache2" "docker" "mysqld" "redis-server" "php-fpm")
        for srv in "${services[@]}"; do
            if service $srv status &>/dev/null; then
                log INFO "服务 $srv 状态: 运行中"
            else
                log WARN "服务 $srv 未运行"
            fi
        done
        ;;
esac

# [3] 安全审计
log INFO "==================== 安全审计 ===================="
# SSH 检查
sshd_config="/etc/ssh/sshd_config"
if [ -f $sshd_config ]; then
    grep -q "^PermitRootLogin no" $sshd_config && log INFO "SSH禁止root登录: 已配置" || log WARN "SSH允许root登录"
    grep -q "^PasswordAuthentication no" $sshd_config && log INFO "SSH密钥登录: 已配置" || log WARN "SSH允许密码登录"
else
    log WARN "未找到SSH配置文件"
fi
# 防火墙检查
case $OS_TYPE in
    "centos"|"kylin")
        log INFO "防火墙状态: $(systemctl status firewalld | grep "Active" | awk '{print $2}')"
        ;;
    "ubuntu")
        log INFO "防火墙状态: $(systemctl status ufw | grep "Active" | awk '{print $2}')"
        ;;
esac
# iptables 检查
iptables_status="未安装"
# 检查iptables 是否安装
iptables() {
    case $OS_TYPE in
        "centos"|"kylin")
            rpm -qa iptables &>/dev/null
            if [ $? -eq 0 ]; then
                iptables_status=$(systemctl status iptables | grep "Active" | awk '{print $2}') &>/dev/null
            fi
        ;;
        "ubuntu")
            dpkg -s iptables &>/dev/null
            if [ $? -eq 0 ]; then
                iptables_status=$(systemctl status iptables | grep "Active" | awk '{print $2}') &>/dev/null
            fi
        ;;
    esac
    log WARN "iptables 状态: $iptables_status"
}
iptables &>/dev/null

    
# 最近登录记录
log INFO "最近第一次登录记录: $(last -3|awk 'NR==1{print " 用户名: "$1 " 登录窗口: " $2 " 登录IP: " $3}')"
log INFO "最近第二次登录记录: $(last -3|awk 'NR==2{print " 用户名: "$1 " 登录窗口: " $2 " 登录IP: " $3}')"
log INFO "最近第三次登录记录: $(last -3|awk 'NR==3{print " 用户名: "$1 " 登录窗口: " $2 " 登录IP: " $3}')"



# 硬件信息
log INFO "==================== 硬件信息 ===================="
# cpu 型号 核心数 线程数 
log INFO "CPU型号: $(lscpu | grep "Model name" | awk '{print $3}')"
log INFO "CPU核心数: $(lscpu | grep "Core(s) per socket" | awk '{print $4}')"
log INFO "CPU线程数: $(lscpu | grep "Thread(s) per core" | awk '{print $4}')"

# 查看启动状态的网卡名称多个网卡显示在同一列中
log INFO "启动状态的网卡名称: $(ip link show | awk '/state UP/{print $2}' | paste -sd "," -)"


} > $LOG_FILE 2>&1

#------------------ 报告生成 ------------------#
cat $LOG_FILE
echo -e "\n${GREEN}巡检完成！报告已经保存到: $LOG_FILE${NC}"

# 询问用户是否需要将日志文件发送到用户邮箱 
read -p "是否需要将日志文件发送到邮箱？(y/n): " choice
if [ "$choice" == "y" ]; then
   while true; do
    read -p "请输入用户邮箱 |输入q直接退出: " email
    if [ "$email" == "q" ]; then
        break
    fi
    mail_sent $email
    rc=$?
    if [ $rc -eq 10 ]; then
        read -p "邮箱格式错误请重新输入: " email
        mail_sent $email
    elif [ $rc -eq 20 ]; then
        read -p "文件路径不存在请重新输入: " email
        mail_sent $email
    elif [ $rc -eq 2 ]; then
        echo "邮件发送成功，请注意查收邮箱"
        break 
    else
        echo "出现未知错误"
        break
    fi
   done
else
    echo "退出巡检"
fi