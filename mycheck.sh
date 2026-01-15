#!/bin/bash
# ======================================================================
# Author:       魏姚
# Email:        xuanchengweiyao@hostmail.com
# Description:  MySQL 巡检脚本
# Date:         2025-04-29
# Version:      1.0.4
# Notes:        MySQL巡检脚本，支持系统信息、MySQL基本信息、连接信息、配置检查、性能检查、数据库基本检查、安全检查、错误日志检查、备份检查和慢查询日志检查
# Update Log:
#   2025-04-27: 新增MySQL错误日志检查功能，支持检查错误日志是否存在、错误日志大小和统计各个错误代码出现的次数。
#   2025-04-27: 新增MySQL慢查询日志检查功能，支持检查是否开启慢查询日志、慢查询日志位置、文件大小和慢查询数量。
#   2025-04-27: 新增MySQL备份检查功能，支持Xtrabackup和Mysqldump两种备份方式的检查。
#   2025-04-26: 修复了MySQL连接方式的选择问题，现在可以通过IP和端口或本地socket连接MySQL。
#   2025-04-26: 修复了在Ubuntu系统下运行时可能出现的未知错误。
# ======================================================================

#版本号
VERSION_NUMBER="1.0.4"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 输出文件路径
REPORT_FILE="/tmp/report.log"
# 输出临时文件路径
TEMP_FILE="/tmp/temp.log"

# 脚本说明
echo -e "${YELLOW}                         当前脚本版本号：$VERSION_NUMBER${NC}"
echo -e "${YELLOW}本脚本适配centos7.x、kylin V10 sp3、ubuntu系统${NC}"
echo -e "${YELLOW}脚本默认使用root用户连接MySQL，若需要使用其他用户连接，请在脚本中修改mysql_user和mysql_password变量${NC}"
echo -e "${YELLOW}若在ubuntu系统下运行,请使用bash mycheck.sh 运行 使用sh mychechk.sh 运行可能会出现未知错误${NC}"
echo -e "${YELLOW}如果脚本运行直接报错，请先安装 dos2unix 再 运行 dos2unix mycheck.sh转换格式后运行${NC}"
echo -e "${YELLOW}====================注意脚本检查密码以明文运行请数据安全=========================${NC}"
echo -e "${YELLOW}===============在生产环境使用请先仔细阅读脚本是否存在安全隐患======================${NC}"
echo -e "${YELLOW}===============在生产环境使用请先仔细阅读脚本是否存在安全隐患======================${NC}"
echo -e "${YELLOW}===============在生产环境使用请先仔细阅读脚本是否存在安全隐患======================${NC}"
echo -e "${YELLOW}===============在生产环境使用请先仔细阅读脚本是否存在安全隐患======================${NC}"
echo -e "${YELLOW}===============在生产环境使用请先仔细阅读脚本是否存在安全隐患======================${NC}"
echo -e "${YELLOW}===========================================================================${NC}"
echo " "

# 检查是否以root用户运行
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}Error: 请使用root用户运行此脚本${NC}"
   exit 1
fi

# 检查是否安装了MySQL
if ! command -v mysql > /dev/null; then
    echo -e "${RED}Error: MySQL未安装，或命令没有加入环境变量，请先安装MySQL。${NC}"
    exit 1
fi

# 检查是否安装了bc
if ! command -v bc > /dev/null; then
    echo -e "${YELLOW}Warning: bc 未安装，正在安装...${NC}"
    if [ -f /etc/debian_sources.list ] || [ -f /etc/apt/sources.list ]; then
        apt-get update && apt-get install -y bc
    elif [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
        yum install -y bc
    else
        echo -e "${RED}Error: 无法确定包管理器，请手动安装bc${NC}"
        exit 1
    fi
fi

# 需要连接的数据库账户和密码
mysql_user="root"
mysql_password=""
mysql_host="localhost"
mysql_port="3306"
mysql_socket=""
connection_type=""

# 检查操作系统类型和版本
OS_TYPE=""
if [ -f /etc/os-release ]; then
    OS_TYPE=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
elif [ -f /etc/centos-release ]; then
    OS_TYPE="centos"
elif [ -f /etc/kylin-release ]; then
    OS_TYPE="kylin"
fi

# 选择MySQL连接方式
echo -e "${CYAN}请选择MySQL连接方式:${NC}"
echo -e "1) 通过IP和端口连接"
echo -e "2) 通过本地socket连接"
read -p "请输入选择 [1/2]: " connection_choice

if [ "$connection_choice" = "1" ]; then
    connection_type="tcp"
    read -p "请输入MySQL主机地址 [默认: localhost]: " input_host
    mysql_host=${input_host:-localhost}
    
    read -p "请输入MySQL端口 [默认: 3306]: " input_port
    mysql_port=${input_port:-3306}
    
    read -p "请输入MySQL用户名 [默认: root]: " input_user
    mysql_user=${input_user:-root}
    
    read -p "请输入MySQL密码: " mysql_password
    
    # 测试MySQL连接
    if ! mysql -h$mysql_host -P$mysql_port -u$mysql_user -p$mysql_password -e "SELECT 1" >/dev/null 2>&1; then
        echo -e "${RED}Error: 无法连接到MySQL，请检查连接信息${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}MySQL连接成功，使用TCP/IP连接 $mysql_host:$mysql_port${NC}"
    mysql_connect_cmd="-h$mysql_host -P$mysql_port -u$mysql_user -p$mysql_password"
    
elif [ "$connection_choice" = "2" ]; then
    connection_type="socket"
    # 尝试查找默认socket路径
    default_socket=$(mysql --help | grep -o "socket.*" | head -n 1 | awk '{print $2}')
    
    read -p "请输入MySQL socket路径 [默认: $default_socket]: " input_socket
    mysql_socket=${input_socket:-$default_socket}
    
    read -p "请输入MySQL用户名 [默认: root]: " input_user
    mysql_user=${input_user:-root}
    
    read -p "请输入MySQL密码: " mysql_password
    
    # 测试MySQL连接
    if ! mysql -S$mysql_socket -u$mysql_user -p$mysql_password -e "SELECT 1" >/dev/null 2>&1; then
        echo -e "${RED}Error: 无法连接到MySQL，请检查连接信息${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}MySQL连接成功，使用Socket连接 $mysql_socket${NC}"
    mysql_connect_cmd="-S$mysql_socket -u$mysql_user -p$mysql_password"
    
else
    echo -e "${RED}Error: 无效的选择，退出脚本${NC}"
    exit 1
fi

if [ -n "$OS_TYPE" ] && [ "$OS_TYPE" = "ubuntu" ]; then
    mysql_password=$(echo $mysql_password | sed 's/\r//')
fi

# 备份检查功能
echo -e "${CYAN}是否需要检查MySQL备份? [y/n]:${NC}"
read -p "" check_backup_choice
if [ "$check_backup_choice" = "y" ] || [ "$check_backup_choice" = "Y" ]; then
    echo -e "${CYAN}请选择备份方式:${NC}"
    echo -e "1) Xtrabackup"
    echo -e "2) Mysqldump"
    read -p "请输入选择 [1/2]: " backup_type_choice
    
    read -p "请输入备份文件路径: " backup_path
    
    # 检查备份文件是否存在
    check_backup_status="失败"
    if [ -d "$backup_path" ] || [ -f "$backup_path" ]; then
        if [ "$backup_type_choice" = "1" ]; then
            # 检查xtrabackup备份
            if [ -f "$backup_path/xtrabackup_checkpoints" ]; then
                check_backup_status="成功"
                backup_info=$(cat "$backup_path/xtrabackup_checkpoints")
            elif [ -f "$backup_path" ] && grep -q "xtrabackup" "$backup_path"; then
                check_backup_status="成功"
                backup_info="备份文件存在"
            fi
        elif [ "$backup_type_choice" = "2" ]; then
            # 检查mysqldump备份
            if [ -f "$backup_path" ] && (file "$backup_path" | grep -q "text" || grep -q "CREATE TABLE" "$backup_path"); then
                check_backup_status="成功"
                backup_info="备份文件大小: $(du -h "$backup_path" | awk '{print $1}')"
                backup_date="备份文件日期: $(stat -c %y "$backup_path" | cut -d. -f1)"
            elif [ -d "$backup_path" ] && ls "$backup_path"/*.sql 1>/dev/null 2>&1; then
                check_backup_status="成功"
                backup_info="备份目录中包含SQL文件"
                newest_file=$(find "$backup_path" -name "*.sql" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -f2- -d" ")
                backup_date="最新备份文件日期: $(stat -c %y "$newest_file" | cut -d. -f1)"
            fi
        fi
    fi
    
    BACKUP_TYPE=$([ "$backup_type_choice" = "1" ] && echo "Xtrabackup" || echo "Mysqldump")
    BACKUP_PATH=$backup_path
    BACKUP_STATUS=$check_backup_status
    BACKUP_INFO=${backup_info:-"无法获取备份信息"}
    BACKUP_DATE=${backup_date:-"无法获取备份日期"}
    
    echo -e "${GREEN}备份检查完成${NC}"
fi

echo -e "${GREEN}MySQL连接成功，开始巡检...${NC}"

# 1. 系统相关信息
# ----------------------------------------------------------------------------


# 检查操作系统版本号
VERSION_ID=""
if [ -f /etc/os-release ]; then
    VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
fi

# 获取当前系统时间
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# 获取系统IP地址
SYSTEM_IP=$(hostname -I | awk '{print $1}')

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
get_public_ip

# 获取系统负载
SYSTEM_LOAD=$(uptime | awk '{print $10,$11,$12}')

# 获取CPU使用情况
CPU_INFO=$(lscpu | grep "Model name" | awk '{print $3,$4,$5,$6}')
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')

# 获取系统总内存大小
TOTAL_MEMORY=$(free -h | grep Mem | awk '{print $2}')

# 获取系统剩余内存大小
FREE_MEMORY=$(free -h | grep Mem | awk '{print $4}')

# 获取系统交换分区使用情况
SWAP_INFO=$(free -h | grep Swap | awk '{print $2,$3}')

# 获取根目录磁盘总量大小
ROOT_DISK_TOTAL=$(df -h | grep "/$" | awk '{print $2}')

# 获取根目录磁盘使用总量
ROOT_DISK_USED=$(df -h | grep "/$" | awk '{print $3}')

# 获取根目录磁盘使用率
ROOT_DISK_USAGE=$(df -h | grep "/$" | awk '{print $5}')

# 2. MySQL 服务基本信息
# -----------------------------------------------------------------------------------------

# 获取 MySQL服务状态
MYSQL_STATUS=$(systemctl status mysql 2>/dev/null | grep 'active (running)' | awk '{print $3}')
if [ -z "$MYSQL_STATUS" ]; then
    MYSQL_STATUS=$(service mysql status 2>/dev/null | grep 'running' | wc -l)
    if [ "$MYSQL_STATUS" -gt 0 ]; then
        MYSQL_STATUS="running"
    else
        MYSQL_STATUS="stopped"
    fi
fi

# 获取 MySQL版本信息
MYSQL_VERSION=$(mysql $mysql_connect_cmd -e "SELECT VERSION();" | awk 'NR==2{print $1}')

# 获取MySQL 端口信息
if [ "$connection_type" = "tcp" ]; then
    MYSQL_PORT=$mysql_port
else
    MYSQL_PORT=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'port';" | awk 'NR==2{print $2}')
fi

# 获取MySQL 配置文件路径
MYSQL_CONFIG=$(find /etc -name my.cnf 2>/dev/null | head -n 1)
if [ -z "$MYSQL_CONFIG" ]; then
    MYSQL_CONFIG=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'datadir';" | awk 'NR==2{print $2}' | sed 's/\/data\//\/my.cnf/')
fi

# 获取MySQL binlog文件位置
MYSQL_BINLOG_DIR=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_bin_basename';" | awk 'NR==2{print $2}' | xargs dirname 2>/dev/null)
if [ -z "$MYSQL_BINLOG_DIR" ]; then
    MYSQL_BINLOG_DIR=$(grep -i "log[-_]bin" $MYSQL_CONFIG 2>/dev/null | grep -v "#" | awk -F '=' '{print $2}' | sed 's/ //g')
fi

# 获取MySQL 错误日志文件位置
MYSQL_ERROR_LOG=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_error';" | awk 'NR==2{print $2}')
if [ -z "$MYSQL_ERROR_LOG" ] || [ "$MYSQL_ERROR_LOG" = "stderr" ]; then
    MYSQL_ERROR_LOG=$(grep -i "log[-_]error" $MYSQL_CONFIG 2>/dev/null | grep -v "#" | awk -F '=' '{print $2}' | sed 's/ //g')
    if [ -z "$MYSQL_ERROR_LOG" ] || [ "$MYSQL_ERROR_LOG" = "stderr" ]; then
        MYSQL_ERROR_LOG="stderr (标准错误输出)"
    fi
fi

# 获取MySQL 数据目录位置
MYSQL_DATADIR=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'datadir';" | awk 'NR==2{print $2}')
if [ -z "$MYSQL_DATADIR" ]; then
    MYSQL_DATADIR=$(grep ^datadir $MYSQL_CONFIG 2>/dev/null | awk -F '=' '{print $2}' | sed 's/ //g')
fi

# 查看 datadir 目录大小
MYSQL_DATADIR_SIZE=$(du -sh $MYSQL_DATADIR 2>/dev/null | awk '{print $1}')



# 3. MySQL 连接与会话信息
# -------------------------------------------------------------------------

# 获取 Aborted_clients 客户端已成功建立，但中途异常断开的连接的次数
MYSQL_ABORTED_CLIENTS=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Aborted_clients';" | awk 'NR==2{print $2}')

# 获取 Aborted_connects 由于权限问题而被拒绝的连接次数
MYSQL_ABORTED_CONNECTS=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Aborted_connects';" | awk 'NR==2{print $2}')

# 获取 Threads_connected 当前打开的连接数
MYSQL_THREADS_CONNECTED=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';" | awk 'NR==2{print $2}')

# 获取 Max_used_connections 同时存在的最大连接数
MYSQL_MAX_USED_CONNECTIONS=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Max_used_connections';" | awk 'NR==2{print $2}')

# 获取 Threads_running 正在运行的线程数
MYSQL_THREADS_RUNNING=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Threads_running';" | awk 'NR==2{print $2}')

# 4. MySQL 配置检查
# -------------------------------------------------------------------------

# 检查双一设置
SYNC_BINLOG=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'sync_binlog';" | awk 'NR==2{print $2}')
INNODB_FLUSH_LOG=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';" | awk 'NR==2{print $2}')

# 检查只读权限是否关闭
TX_READ_ONLY=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'tx_read_only';" | awk 'NR==2{print $2}')
TRANSACTION_READ_ONLY=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'transaction_read_only';" | awk 'NR==2{print $2}')
INNODB_READ_ONLY=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'innodb_read_only';" | awk 'NR==2{print $2}')
READ_ONLY=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'read_only';" | awk 'NR==2{print $2}')
SUPER_READ_ONLY=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'super_read_only';" | awk 'NR==2{print $2}')

# 检查binlog格式是否为row
BINLOG_FORMAT=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'binlog_format';" | awk 'NR==2{print $2}')

# 检查server端字符集是否为utf8
CHARACTER_SET_SERVER=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'character_set_server';" | awk 'NR==2{print $2}')

# 检查默认的密码认证插件是否为mysql_native_password
DEFAULT_AUTH_PLUGIN=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'default_authentication_plugin';" | awk 'NR==2{print $2}')

# 检查默认存储引擎及临时表的存储引擎是否为innodb
DEFAULT_STORAGE_ENGINE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'default_storage_engine';" | awk 'NR==2{print $2}')
DEFAULT_TMP_STORAGE_ENGINE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'default_tmp_storage_engine';" | awk 'NR==2{print $2}')
INTERNAL_TMP_DISK_STORAGE_ENGINE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'internal_tmp_disk_storage_engine';" | awk 'NR==2{print $2}')

# 检查innodb脏页刷盘方式是否为O_DIRECT
INNODB_FLUSH_METHOD=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'innodb_flush_method';" | awk 'NR==2{print $2}')

# 检查是否开启了死锁检测
INNODB_DEADLOCK_DETECT=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'innodb_deadlock_detect';" | awk 'NR==2{print $2}')

# 检查查询缓存是否关闭
QUERY_CACHE_TYPE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'query_cache_type';" | awk 'NR==2{print $2}')

# 检查与从库中继日志相关的参数
RELAY_LOG_PURGE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'relay_log_purge';" | awk 'NR==2{print $2}')
RELAY_LOG_RECOVERY=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'relay_log_recovery';" | awk 'NR==2{print $2}')

# 检查当前事务隔离级别
TRANSACTION_ISOLATION=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'transaction_isolation';" | awk 'NR==2{print $2}')
TX_ISOLATION=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'tx_isolation';" | awk 'NR==2{print $2}')

# 检查当前数据库的时区
SYSTEM_TIME_ZONE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'system_time_zone';" | awk 'NR==2{print $2}')
TIME_ZONE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'time_zone';" | awk 'NR==2{print $2}')

# 检查是否开启了主键索引和唯一索引的重复行校验
UNIQUE_CHECKS=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'unique_checks';" | awk 'NR==2{print $2}')

# 5. MySQL 性能检查
# -------------------------------------------------------------------------

# 检测binlog落盘时使用磁盘的利用率
BINLOG_CACHE_DISK_USE=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Binlog_cache_disk_use';" | awk 'NR==2{print $2}')
BINLOG_CACHE_USE=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Binlog_cache_use';" | awk 'NR==2{print $2}')
if [ "$BINLOG_CACHE_USE" -gt 0 ]; then
    BINLOG_DISK_USAGE_RATE=$(echo "scale=2; $BINLOG_CACHE_DISK_USE / $BINLOG_CACHE_USE * 100" | bc)
else
    BINLOG_DISK_USAGE_RATE="0"
fi

# 历史最大连接数占最大连接数限制的百分比
MAX_CONNECTIONS=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'max_connections';" | awk 'NR==2{print $2}')
HISTORY_CONNECTION_MAX_USAGE_RATE=$(echo "scale=2; $MYSQL_MAX_USED_CONNECTIONS / $MAX_CONNECTIONS * 100" | bc)

# 创建临时磁盘表使用率
CREATED_TMP_DISK_TABLES=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';" | awk 'NR==2{print $2}')
CREATED_TMP_TABLES=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Created_tmp_tables';" | awk 'NR==2{print $2}')
if [ "$CREATED_TMP_TABLES" -gt 0 ]; then
    TMP_DISK_TABLE_USAGE_RATE=$(echo "scale=2; $CREATED_TMP_DISK_TABLES / $CREATED_TMP_TABLES * 100" | bc)
else
    TMP_DISK_TABLE_USAGE_RATE="0"
fi

# 创建临时磁盘文件使用率
CREATED_TMP_FILES=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Created_tmp_files';" | awk 'NR==2{print $2}')
if [ "$CREATED_TMP_TABLES" -gt 0 ]; then
    TMP_DISK_FILE_USAGE_RATE=$(echo "scale=2; $CREATED_TMP_FILES / $CREATED_TMP_TABLES * 100" | bc)
else
    TMP_DISK_FILE_USAGE_RATE="0"
fi

# innodb buffer pool使用率
INNODB_BUFFER_POOL_PAGES_TOTAL=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_total';" | awk 'NR==2{print $2}')
INNODB_BUFFER_POOL_PAGES_FREE=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_free';" | awk 'NR==2{print $2}')
if [ "$INNODB_BUFFER_POOL_PAGES_TOTAL" -gt 0 ]; then
    INNODB_BUFFER_POOL_USAGE_RATE=$(echo "scale=2; ($INNODB_BUFFER_POOL_PAGES_TOTAL - $INNODB_BUFFER_POOL_PAGES_FREE) / $INNODB_BUFFER_POOL_PAGES_TOTAL * 100" | bc)
else
    INNODB_BUFFER_POOL_USAGE_RATE="0"
fi

# 当前innodb buffer pool中脏页比例
INNODB_BUFFER_POOL_PAGES_DIRTY=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_dirty';" | awk 'NR==2{print $2}')
if [ "$INNODB_BUFFER_POOL_PAGES_TOTAL" -gt 0 ]; then
    INNODB_BUFFER_POOL_DIRTY_RATE=$(echo "scale=2; $INNODB_BUFFER_POOL_PAGES_DIRTY / $INNODB_BUFFER_POOL_PAGES_TOTAL * 100" | bc)
else
    INNODB_BUFFER_POOL_DIRTY_RATE="0"
fi

# 当前innodb buffer pool命中率
INNODB_BUFFER_POOL_READ_REQUESTS=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests';" | awk 'NR==2{print $2}')
INNODB_BUFFER_POOL_READS=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';" | awk 'NR==2{print $2}')
if [ "$INNODB_BUFFER_POOL_READ_REQUESTS" -gt 0 ]; then
    INNODB_BUFFER_POOL_HIT_RATE=$(echo "scale=2; (1 - $INNODB_BUFFER_POOL_READS / $INNODB_BUFFER_POOL_READ_REQUESTS) * 100" | bc)
else
    INNODB_BUFFER_POOL_HIT_RATE="0"
fi

# 数据库文件句柄使用率
OPEN_FILES_LIMIT=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'open_files_limit';" | awk 'NR==2{print $2}')
OPEN_FILES=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Open_files';" | awk 'NR==2{print $2}')
if [ "$OPEN_FILES_LIMIT" -gt 0 ]; then
    OPEN_FILE_USAGE_RATE=$(echo "scale=2; $OPEN_FILES / $OPEN_FILES_LIMIT * 100" | bc)
else
    OPEN_FILE_USAGE_RATE="0"
fi

# 数据库表缓存率
TABLE_OPEN_CACHE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'table_open_cache';" | awk 'NR==2{print $2}')
OPEN_TABLES=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Open_tables';" | awk 'NR==2{print $2}')
if [ "$TABLE_OPEN_CACHE" -gt 0 ]; then
    OPEN_TABLE_CACHE_USAGE_RATE=$(echo "scale=2; $OPEN_TABLES / $TABLE_OPEN_CACHE * 100" | bc)
else
    OPEN_TABLE_CACHE_USAGE_RATE="0"
fi

# 数据库表缓存溢出率
TABLE_OPEN_CACHE_OVERFLOWS=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Table_open_cache_overflows';" | awk 'NR==2{print $2}')
if [ "$OPEN_TABLES" -gt 0 ]; then
    OPEN_TABLE_CACHE_OVERFLOWS_USAGE_RATE=$(echo "scale=2; $TABLE_OPEN_CACHE_OVERFLOWS / $OPEN_TABLES * 100" | bc)
else
    OPEN_TABLE_CACHE_OVERFLOWS_USAGE_RATE="0"
fi

# 数据库全表扫描占比率
SELECT_SCAN=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Select_scan';" | awk 'NR==2{print $2}')
SELECT_RANGE=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Select_range';" | awk 'NR==2{print $2}')
if [ "$SELECT_SCAN" -gt 0 ] || [ "$SELECT_RANGE" -gt 0 ]; then
    SELECT_SCAN_USAGE_RATE=$(echo "scale=2; $SELECT_SCAN / ($SELECT_SCAN + $SELECT_RANGE) * 100" | bc)
else
    SELECT_SCAN_USAGE_RATE="0"
fi

# 数据库join语句全表扫描占比率
SELECT_FULL_JOIN=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Select_full_join';" | awk 'NR==2{print $2}')
SELECT_RANGE_CHECK=$(mysql $mysql_connect_cmd -e "SHOW GLOBAL STATUS LIKE 'Select_range_check';" | awk 'NR==2{print $2}')
if [ "$SELECT_FULL_JOIN" -gt 0 ] || [ "$SELECT_RANGE_CHECK" -gt 0 ]; then
    SELECT_FULL_JOIN_SCAN_USAGE_RATE=$(echo "scale=2; $SELECT_FULL_JOIN / ($SELECT_FULL_JOIN + $SELECT_RANGE_CHECK) * 100" | bc)
else
    SELECT_FULL_JOIN_SCAN_USAGE_RATE="0"
fi

# 6. 数据库基本检查
# -------------------------------------------------------------------------

# 检查表字符集（输出非utf8或utf8mb4的表）
TABLE_CHARSET_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT CONCAT(table_schema, '.', table_name) AS table_name, table_collation 
FROM information_schema.tables 
WHERE table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') 
AND table_collation NOT LIKE 'utf8%' AND table_collation NOT LIKE 'utf8mb4%';" | awk 'NR>1')

# 检查引擎不是innodb的表
TABLE_ENGINE_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT CONCAT(table_schema, '.', table_name) AS table_name, engine 
FROM information_schema.tables 
WHERE table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') 
AND engine != 'InnoDB';" | awk 'NR>1')

# 检查表是否有外键关联
TABLE_FOREIGN_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT CONCAT(table_schema, '.', table_name) AS table_name, constraint_name 
FROM information_schema.table_constraints 
WHERE constraint_type = 'FOREIGN KEY' 
AND table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys');" | awk 'NR>1')

# 检查表是否有自增主键
TABLE_NO_PRIMARY_KEY_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT CONCAT(t.table_schema, '.', t.table_name) AS table_name 
FROM information_schema.tables t 
LEFT JOIN (
    SELECT table_schema, table_name 
    FROM information_schema.statistics 
    WHERE index_name = 'PRIMARY'
) i ON t.table_schema = i.table_schema AND t.table_name = i.table_name 
WHERE t.table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') 
AND t.table_type = 'BASE TABLE' 
AND i.table_name IS NULL;" | awk 'NR>1')

# 检查主键自增列是否为bigint
TABLE_AUTO_INCREMENT_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT CONCAT(t.table_schema, '.', t.table_name) AS table_name, c.column_name, c.data_type 
FROM information_schema.tables t 
JOIN information_schema.columns c ON t.table_schema = c.table_schema AND t.table_name = c.table_name 
WHERE t.table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') 
AND c.extra LIKE '%auto_increment%' 
AND c.data_type != 'bigint';" | awk 'NR>1')

# 检查表是否有索引
TABLE_NO_INDEX_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT CONCAT(t.table_schema, '.', t.table_name) AS table_name 
FROM information_schema.tables t 
LEFT JOIN (
    SELECT DISTINCT table_schema, table_name 
    FROM information_schema.statistics
) i ON t.table_schema = i.table_schema AND t.table_name = i.table_name 
WHERE t.table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') 
AND t.table_type = 'BASE TABLE' 
AND i.table_name IS NULL;" | awk 'NR>1')

# 7. 安全检查
# -------------------------------------------------------------------------

# 检查是否有匿名用户
ANONYMOUS_USER_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT user, host FROM mysql.user WHERE user = '';" | awk 'NR>1')

# 检查是否有空密码用户
EMPTY_PASSWORD_USER_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT user, host FROM mysql.user WHERE authentication_string = '';" | awk 'NR>1')

# 检查是否有远程root用户
REMOTE_ROOT_USER_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT user, host FROM mysql.user WHERE user = 'root' AND host NOT IN ('localhost', '127.0.0.1', '::1');" | awk 'NR>1')

# 检查是否有通配符host的用户
WILDCARD_HOST_USER_CHECK=$(mysql $mysql_connect_cmd -e "
SELECT user, host FROM mysql.user WHERE host = '%';" | awk 'NR>1')

# 检查是否开启了general_log
GENERAL_LOG_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'general_log';" | awk 'NR==2{print $2}')

# 检查是否开启了skip_name_resolve
SKIP_NAME_RESOLVE_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'skip_name_resolve';" | awk 'NR==2{print $2}')

# 检查是否开启了local_infile
LOCAL_INFILE_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'local_infile';" | awk 'NR==2{print $2}')

# 检查是否开启了secure_file_priv
SECURE_FILE_PRIV_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'secure_file_priv';" | awk 'NR==2{print $2}')

# 检查是否开启了symbolic_links
SYMBOLIC_LINKS_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'have_symlink';" | awk 'NR==2{print $2}')

# 检查是否开启了automatic_sp_privileges
AUTOMATIC_SP_PRIVILEGES_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'automatic_sp_privileges';" | awk 'NR==2{print $2}')

# 检查是否开启了old_passwords
OLD_PASSWORDS_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'old_passwords';" | awk 'NR==2{print $2}')

# 检查是否开启了log_bin_trust_function_creators
LOG_BIN_TRUST_FUNCTION_CREATORS_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_bin_trust_function_creators';" | awk 'NR==2{print $2}')

# 检查是否开启了log_error_verbosity
LOG_ERROR_VERBOSITY_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_error_verbosity';" | awk 'NR==2{print $2}')

# 检查是否开启了log_warnings
LOG_WARNINGS_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_warnings';" | awk 'NR==2{print $2}')

# 检查是否开启了log_error_services
LOG_ERROR_SERVICES_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_error_services';" | awk 'NR==2{print $2}')

# 检查是否开启了log_error_suppression_list
LOG_ERROR_SUPPRESSION_LIST_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_error_suppression_list';" | awk 'NR==2{print $2}')

# 检查是否开启了log_error_verbosity
LOG_ERROR_VERBOSITY_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_error_verbosity';" | awk 'NR==2{print $2}')

# 检查是否开启了log_slow_admin_statements
LOG_SLOW_ADMIN_STATEMENTS_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_slow_admin_statements';" | awk 'NR==2{print $2}')

# 检查是否开启了log_slow_slave_statements
LOG_SLOW_SLAVE_STATEMENTS_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_slow_slave_statements';" | awk 'NR==2{print $2}')

# 检查是否开启了log_throttle_queries_not_using_indexes
LOG_THROTTLE_QUERIES_NOT_USING_INDEXES_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_throttle_queries_not_using_indexes';" | awk 'NR==2{print $2}')

# 检查是否开启了log_timestamps
LOG_TIMESTAMPS_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'log_timestamps';" | awk 'NR==2{print $2}')

# 8. 错误日志检查
# -------------------------------------------------------------------------

# 在脚本开始部分添加时间范围选择
echo -e "${CYAN}请选择巡检时间范围:${NC}"
echo -e "1) 最近一天"
echo -e "2) 最近一周"
read -p "请输入选择 [1/2]: " time_range_choice

# 根据选择设置时间范围
if [ "$time_range_choice" = "1" ]; then
    TIME_RANGE="1 day"
    TIME_RANGE_DAYS=1
elif [ "$time_range_choice" = "2" ]; then
    TIME_RANGE="7 days"
    TIME_RANGE_DAYS=7
else
    echo -e "${RED}Error: 无效的选择，默认使用最近一天${NC}"
    TIME_RANGE="1 day"
    TIME_RANGE_DAYS=1
fi

# 修改错误日志检查部分
if [ -n "$MYSQL_ERROR_LOG" ] && [ "$MYSQL_ERROR_LOG" != "stderr (标准错误输出)" ] && [ -f "$MYSQL_ERROR_LOG" ]; then
    # 获取错误日志文件大小
    ERROR_LOG_SIZE=$(du -h "$MYSQL_ERROR_LOG" 2>/dev/null | awk '{print $1}')
    
    # 使用find命令查找指定时间范围内的错误日志文件
    ERROR_LOG_FILES=$(find "$(dirname "$MYSQL_ERROR_LOG")" -name "$(basename "$MYSQL_ERROR_LOG")*" -type f -mtime -$TIME_RANGE_DAYS)
    
    # 统计错误代码出现次数
    ERROR_CODE_COUNT=""
    for log_file in $ERROR_LOG_FILES; do
        # 使用正则表达式匹配完整的错误代码格式 [ERROR] [MY-XXXXXX]
        ERROR_CODE_COUNT="$ERROR_CODE_COUNT\n$(grep -E -o "\[ERROR\][[:space:]]*\[MY-[0-9]+\]" "$log_file" 2>/dev/null)"
    done
    
    # 如果没有找到错误代码，尝试其他可能的格式
    if [ -z "$ERROR_CODE_COUNT" ]; then
        for log_file in $ERROR_LOG_FILES; do
            # 尝试匹配其他可能的错误代码格式
            ERROR_CODE_COUNT="$ERROR_CODE_COUNT\n$(grep -E -o "ERROR[[:space:]]*\[MY-[0-9]+\]|\[ERROR\][[:space:]]*MY-[0-9]+" "$log_file" 2>/dev/null)"
        done
    fi
    
    if [ -n "$ERROR_CODE_COUNT" ]; then
        ERROR_CODE_COUNT=$(echo -e "$ERROR_CODE_COUNT" | sort | uniq -c | sort -nr)
    else
        ERROR_CODE_COUNT="未发现错误代码"
    fi
else
    ERROR_LOG_SIZE="未找到文件或无法访问"
    ERROR_CODE_COUNT="无法统计"
fi

# 9. 慢查询日志检查
# -------------------------------------------------------------------------

# 检查是否开启了慢查询日志
SLOW_QUERY_LOG_CHECK=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'slow_query_log';" | awk 'NR==2{print $2}')

# 获取慢查询日志文件位置
SLOW_QUERY_LOG_FILE=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'slow_query_log_file';" | awk 'NR==2{print $2}')

# 获取慢查询日志文件大小
if [ -n "$SLOW_QUERY_LOG_FILE" ] && [ -f "$SLOW_QUERY_LOG_FILE" ]; then
    SLOW_QUERY_LOG_FILE_SIZE=$(du -h "$SLOW_QUERY_LOG_FILE" 2>/dev/null | awk '{print $1}')

    # 使用find命令查找指定时间范围内的慢查询日志文件
    SLOW_QUERY_LOG_FILES=$(find "$(dirname "$SLOW_QUERY_LOG_FILE")" -name "$(basename "$SLOW_QUERY_LOG_FILE")*" -type f -mtime -$TIME_RANGE_DAYS)
    
    # 统计慢查询数量
    SLOW_QUERIES_COUNTER=0
    for log_file in $SLOW_QUERY_LOG_FILES; do
        SLOW_QUERIES_COUNTER=$((SLOW_QUERIES_COUNTER + $(grep -c "# Time:" "$log_file" 2>/dev/null)))
    done
    
    if [ -z "$SLOW_QUERIES_COUNTER" ]; then
        SLOW_QUERIES_COUNTER="0"
    fi
else
    SLOW_QUERY_LOG_FILE_SIZE="未找到文件或无法访问"
    SLOW_QUERIES_COUNTER="0"
fi

# 获取慢查询时间阈值
LONG_QUERY_TIME=$(mysql $mysql_connect_cmd -e "SHOW VARIABLES LIKE 'long_query_time';" | awk 'NR==2{print $2}')


# 输出巡检报告
# -------------------------------------------------------------------------
{
echo -e "${BLUE}===========================================================================${NC}"
echo -e "${BLUE}                          MySQL 巡检报告                                   ${NC}"
echo -e "${BLUE}===========================================================================${NC}"
echo -e "${BLUE}报告生成时间: $CURRENT_TIME${NC}"
echo -e "${BLUE}===========================================================================${NC}"
echo " "

echo -e "${CYAN}1. 系统相关信息${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "操作系统类型: ${OS_TYPE}"
echo -e "操作系统版本: ${VERSION_ID}"
echo -e "系统当前时间: ${CURRENT_TIME}"
echo -e "系统IP地址: ${SYSTEM_IP}"
echo -e "系统外网IP: ${IPv4}"
echo -e "系统负载: ${SYSTEM_LOAD}"
echo -e "CPU型号: ${CPU_INFO}"
echo -e "CPU使用率: ${CPU_USAGE}%"
echo -e "系统总内存: ${TOTAL_MEMORY}"
echo -e "系统剩余内存: ${FREE_MEMORY}"
echo -e "交换分区使用情况: ${SWAP_INFO}"
echo -e "根目录磁盘总量: ${ROOT_DISK_TOTAL}"
echo -e "根目录磁盘使用量: ${ROOT_DISK_USED}"
echo -e "根目录磁盘使用率: ${ROOT_DISK_USAGE}"
echo " "

echo -e "${CYAN}2. MySQL 服务基本信息${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "MySQL服务状态: ${MYSQL_STATUS}"
echo -e "MySQL版本信息: ${MYSQL_VERSION}"
echo -e "MySQL端口信息: ${MYSQL_PORT}"
echo -e "MySQL配置文件路径: ${MYSQL_CONFIG}"
echo -e "MySQL binlog文件位置: ${MYSQL_BINLOG_DIR}"
echo -e "MySQL错误日志文件位置: ${MYSQL_ERROR_LOG}"
echo -e "MySQL数据目录位置: ${MYSQL_DATADIR}"
echo -e "MySQL数据目录大小: ${MYSQL_DATADIR_SIZE}"
echo " "

echo -e "${CYAN}3. MySQL 连接与会话信息${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "客户端异常断开连接次数: ${MYSQL_ABORTED_CLIENTS}"
echo -e "因权限问题被拒绝的连接次数: ${MYSQL_ABORTED_CONNECTS}"
echo -e "当前打开的连接数: ${MYSQL_THREADS_CONNECTED}"
echo -e "历史最大连接数: ${MYSQL_MAX_USED_CONNECTIONS}"
echo -e "当前正在运行的线程数: ${MYSQL_THREADS_RUNNING}"
echo " "

echo -e "${CYAN}4. MySQL 配置检查${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "双一设置:"
echo -e "  sync_binlog: ${SYNC_BINLOG} $([ "$SYNC_BINLOG" = "1" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "  innodb_flush_log_at_trx_commit: ${INNODB_FLUSH_LOG} $([ "$INNODB_FLUSH_LOG" = "1" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo " "

echo -e "只读权限检查:"
echo -e "  tx_read_only: ${TX_READ_ONLY} $([ "$TX_READ_ONLY" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "  transaction_read_only: ${TRANSACTION_READ_ONLY} $([ "$TRANSACTION_READ_ONLY" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "  innodb_read_only: ${INNODB_READ_ONLY} $([ "$INNODB_READ_ONLY" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "  read_only: ${READ_ONLY} $([ "$READ_ONLY" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "  super_read_only: ${SUPER_READ_ONLY} $([ "$SUPER_READ_ONLY" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo " "

echo -e "binlog格式: ${BINLOG_FORMAT} $([ "$BINLOG_FORMAT" = "ROW" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "server端字符集: ${CHARACTER_SET_SERVER} $([ "$CHARACTER_SET_SERVER" = "utf8" ] || [ "$CHARACTER_SET_SERVER" = "utf8mb4" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "默认密码认证插件: ${DEFAULT_AUTH_PLUGIN} $([ "$DEFAULT_AUTH_PLUGIN" = "mysql_native_password" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo " "

echo -e "存储引擎设置:"
echo -e "  默认存储引擎: ${DEFAULT_STORAGE_ENGINE} $([ "$DEFAULT_STORAGE_ENGINE" = "InnoDB" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "  默认临时表存储引擎: ${DEFAULT_TMP_STORAGE_ENGINE} $([ "$DEFAULT_TMP_STORAGE_ENGINE" = "InnoDB" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "  内部临时磁盘存储引擎: ${INTERNAL_TMP_DISK_STORAGE_ENGINE} $([ "$INTERNAL_TMP_DISK_STORAGE_ENGINE" = "InnoDB" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo " "

echo -e "InnoDB脏页刷盘方式: ${INNODB_FLUSH_METHOD} $([ "$INNODB_FLUSH_METHOD" = "O_DIRECT" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "死锁检测: ${INNODB_DEADLOCK_DETECT} $([ "$INNODB_DEADLOCK_DETECT" = "ON" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "查询缓存: ${QUERY_CACHE_TYPE} $([ "$QUERY_CACHE_TYPE" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo " "

echo -e "从库中继日志相关参数:"
echo -e "  relay_log_purge: ${RELAY_LOG_PURGE} $([ "$RELAY_LOG_PURGE" = "ON" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "  relay_log_recovery: ${RELAY_LOG_RECOVERY} $([ "$RELAY_LOG_RECOVERY" = "ON" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo " "

echo -e "事务隔离级别:"
echo -e "  transaction_isolation: ${TRANSACTION_ISOLATION} $([ "$TRANSACTION_ISOLATION" = "REPEATABLE-READ" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "  tx_isolation: ${TX_ISOLATION} $([ "$TX_ISOLATION" = "REPEATABLE-READ" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo " "

echo -e "时区设置:"
echo -e "  system_time_zone: ${SYSTEM_TIME_ZONE}"
echo -e "  time_zone: ${TIME_ZONE} $([ "$TIME_ZONE" = "SYSTEM" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo " "

echo -e "主键索引和唯一索引重复行校验: ${UNIQUE_CHECKS} $([ "$UNIQUE_CHECKS" = "ON" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo " "

echo -e "${CYAN}5. MySQL 性能检查${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "binlog落盘时使用磁盘的利用率: ${BINLOG_DISK_USAGE_RATE}% $([ $(echo "$BINLOG_DISK_USAGE_RATE < 10" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "历史最大连接数占最大连接数限制的百分比: ${HISTORY_CONNECTION_MAX_USAGE_RATE}% $([ $(echo "$HISTORY_CONNECTION_MAX_USAGE_RATE < 80" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "创建临时磁盘表使用率: ${TMP_DISK_TABLE_USAGE_RATE}% $([ $(echo "$TMP_DISK_TABLE_USAGE_RATE < 25" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "创建临时磁盘文件使用率: ${TMP_DISK_FILE_USAGE_RATE}% $([ $(echo "$TMP_DISK_FILE_USAGE_RATE < 25" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "innodb buffer pool使用率: ${INNODB_BUFFER_POOL_USAGE_RATE}% $([ $(echo "$INNODB_BUFFER_POOL_USAGE_RATE < 90" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "当前innodb buffer pool中脏页比例: ${INNODB_BUFFER_POOL_DIRTY_RATE}% $([ $(echo "$INNODB_BUFFER_POOL_DIRTY_RATE < 75" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "当前innodb buffer pool命中率: ${INNODB_BUFFER_POOL_HIT_RATE}% $([ $(echo "$INNODB_BUFFER_POOL_HIT_RATE > 95" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "数据库文件句柄使用率: ${OPEN_FILE_USAGE_RATE}% $([ $(echo "$OPEN_FILE_USAGE_RATE < 75" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "数据库表缓存率: ${OPEN_TABLE_CACHE_USAGE_RATE}% $([ $(echo "$OPEN_TABLE_CACHE_USAGE_RATE < 80" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "数据库表缓存溢出率: ${OPEN_TABLE_CACHE_OVERFLOWS_USAGE_RATE}% $([ $(echo "$OPEN_TABLE_CACHE_OVERFLOWS_USAGE_RATE < 10" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "数据库全表扫描占比率: ${SELECT_SCAN_USAGE_RATE}% $([ $(echo "$SELECT_SCAN_USAGE_RATE < 10" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "数据库join语句全表扫描占比率: ${SELECT_FULL_JOIN_SCAN_USAGE_RATE}% $([ $(echo "$SELECT_FULL_JOIN_SCAN_USAGE_RATE < 10" | bc) -eq 1 ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo " "

echo -e "${CYAN}6. 数据库基本检查${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "非utf8或utf8mb4字符集的表:"
if [ -z "$TABLE_CHARSET_CHECK" ]; then
    echo -e "${GREEN}未发现非utf8或utf8mb4字符集的表${NC}"
else
    echo -e "${RED}发现非utf8或utf8mb4字符集的表:${NC}"
    echo "$TABLE_CHARSET_CHECK"
fi
echo " "

echo -e "非InnoDB引擎的表:"
if [ -z "$TABLE_ENGINE_CHECK" ]; then
    echo -e "${GREEN}未发现非InnoDB引擎的表${NC}"
else
    echo -e "${RED}发现非InnoDB引擎的表:${NC}"
    echo "$TABLE_ENGINE_CHECK"
fi
echo " "

echo -e "有外键关联的表:"
if [ -z "$TABLE_FOREIGN_CHECK" ]; then
    echo -e "${GREEN}未发现有外键关联的表${NC}"
else
    echo -e "${YELLOW}发现有外键关联的表:${NC}"
    echo "$TABLE_FOREIGN_CHECK"
fi
echo " "

echo -e "无主键的表:"
if [ -z "$TABLE_NO_PRIMARY_KEY_CHECK" ]; then
    echo -e "${GREEN}未发现无主键的表${NC}"
else
    echo -e "${RED}发现无主键的表:${NC}"
    echo "$TABLE_NO_PRIMARY_KEY_CHECK"
fi
echo " "

echo -e "主键自增列非bigint的表:"
if [ -z "$TABLE_AUTO_INCREMENT_CHECK" ]; then
    echo -e "${GREEN}未发现主键自增列非bigint的表${NC}"
else
    echo -e "${RED}发现主键自增列非bigint的表:${NC}"
    echo "$TABLE_AUTO_INCREMENT_CHECK"
fi
echo " "

echo -e "无索引的表:"
if [ -z "$TABLE_NO_INDEX_CHECK" ]; then
    echo -e "${GREEN}未发现无索引的表${NC}"
else
    echo -e "${RED}发现无索引的表:${NC}"
    echo "$TABLE_NO_INDEX_CHECK"
fi
echo " "

echo -e "${CYAN}7. 安全检查${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "匿名用户检查:"
if [ -z "$ANONYMOUS_USER_CHECK" ]; then
    echo -e "${GREEN}未发现匿名用户${NC}"
else
    echo -e "${RED}发现匿名用户:${NC}"
    echo "$ANONYMOUS_USER_CHECK"
fi
echo " "

echo -e "空密码用户检查:"
if [ -z "$EMPTY_PASSWORD_USER_CHECK" ]; then
    echo -e "${GREEN}未发现空密码用户${NC}"
else
    echo -e "${RED}发现空密码用户:${NC}"
    echo "$EMPTY_PASSWORD_USER_CHECK"
fi
echo " "

echo -e "远程root用户检查:"
if [ -z "$REMOTE_ROOT_USER_CHECK" ]; then
    echo -e "${GREEN}未发现远程root用户${NC}"
else
    echo -e "${RED}发现远程root用户:${NC}"
    echo "$REMOTE_ROOT_USER_CHECK"
fi
echo " "

echo -e "通配符host的用户检查:"
if [ -z "$WILDCARD_HOST_USER_CHECK" ]; then
    echo -e "${GREEN}未发现通配符host的用户${NC}"
else
    echo -e "${YELLOW}发现通配符host的用户:${NC}"
    echo "$WILDCARD_HOST_USER_CHECK"
fi
echo " "

echo -e "general_log: ${GENERAL_LOG_CHECK} $([ "$GENERAL_LOG_CHECK" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
echo -e "skip_name_resolve: ${SKIP_NAME_RESOLVE_CHECK} $([ "$SKIP_NAME_RESOLVE_CHECK" = "ON" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "local_infile: ${LOCAL_INFILE_CHECK} $([ "$LOCAL_INFILE_CHECK" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "secure_file_priv: ${SECURE_FILE_PRIV_CHECK} $([ -n "$SECURE_FILE_PRIV_CHECK" ] && [ "$SECURE_FILE_PRIV_CHECK" != "NULL" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "symbolic_links: ${SYMBOLIC_LINKS_CHECK} $([ "$SYMBOLIC_LINKS_CHECK" = "DISABLED" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "automatic_sp_privileges: ${AUTOMATIC_SP_PRIVILEGES_CHECK} $([ "$AUTOMATIC_SP_PRIVILEGES_CHECK" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "old_passwords: ${OLD_PASSWORDS_CHECK} $([ "$OLD_PASSWORDS_CHECK" = "0" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "log_bin_trust_function_creators: ${LOG_BIN_TRUST_FUNCTION_CREATORS_CHECK} $([ "$LOG_BIN_TRUST_FUNCTION_CREATORS_CHECK" = "OFF" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "log_error_verbosity: ${LOG_ERROR_VERBOSITY_CHECK} $([ "$LOG_ERROR_VERBOSITY_CHECK" = "3" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "log_warnings: ${LOG_WARNINGS_CHECK} $([ "$LOG_WARNINGS_CHECK" = "2" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "log_error_services: ${LOG_ERROR_SERVICES_CHECK}"
echo -e "log_error_suppression_list: ${LOG_ERROR_SUPPRESSION_LIST_CHECK}"
echo -e "log_slow_admin_statements: ${LOG_SLOW_ADMIN_STATEMENTS_CHECK} $([ "$LOG_SLOW_ADMIN_STATEMENTS_CHECK" = "ON" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "log_slow_slave_statements: ${LOG_SLOW_SLAVE_STATEMENTS_CHECK} $([ "$LOG_SLOW_SLAVE_STATEMENTS_CHECK" = "ON" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo -e "log_throttle_queries_not_using_indexes: ${LOG_THROTTLE_QUERIES_NOT_USING_INDEXES_CHECK}"
echo -e "log_timestamps: ${LOG_TIMESTAMPS_CHECK} $([ "$LOG_TIMESTAMPS_CHECK" = "UTC" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${YELLOW}[警告]${NC}")"
echo " "

echo -e "${CYAN}8. 错误日志检查 (最近 $TIME_RANGE)${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "错误日志文件位置: ${MYSQL_ERROR_LOG}"
echo -e "错误日志文件大小: ${ERROR_LOG_SIZE}"
echo -e "错误代码统计 (最近 $TIME_RANGE):"
if [ "$ERROR_CODE_COUNT" != "未发现错误代码" ] && [ "$ERROR_CODE_COUNT" != "无法统计" ]; then
    echo "$ERROR_CODE_COUNT" | while read count code; do
        echo -e "  ${count} 次: ${code}"
    done
else
    echo -e "  ${ERROR_CODE_COUNT}"
fi
echo " "

echo -e "${CYAN}9. 慢查询日志检查 (最近 $TIME_RANGE)${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
echo -e "是否开启慢查询日志: ${SLOW_QUERY_LOG_CHECK} $([ "$SLOW_QUERY_LOG_CHECK" = "ON" ] && echo -e "${GREEN}[已开启]${NC}" || echo -e "${YELLOW}[未开启]${NC}")"
echo -e "慢查询时间阈值: ${LONG_QUERY_TIME}秒"
echo -e "慢查询日志文件位置: ${SLOW_QUERY_LOG_FILE}"
echo -e "慢查询日志文件大小: ${SLOW_QUERY_LOG_FILE_SIZE}"
echo -e "慢查询日志统计数量 (最近 $TIME_RANGE): ${SLOW_QUERIES_COUNTER}"
echo " "

# 添加备份检查部分
if [ "$check_backup_choice" = "y" ] || [ "$check_backup_choice" = "Y" ]; then
    echo -e "${CYAN}10. 备份检查${NC}"
    echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
    echo -e "备份类型: ${BACKUP_TYPE}"
    echo -e "备份路径: ${BACKUP_PATH}"
    echo -e "备份状态: ${BACKUP_STATUS} $([ "$BACKUP_STATUS" = "成功" ] && echo -e "${GREEN}[正常]${NC}" || echo -e "${RED}[异常]${NC}")"
    if [ "$BACKUP_STATUS" = "成功" ]; then
        echo -e "备份信息: ${BACKUP_INFO}"
        if [ -n "$BACKUP_DATE" ]; then
            echo -e "${BACKUP_DATE}"
        fi
    fi
    echo " "
fi

echo -e "${BLUE}===========================================================================${NC}"
echo -e "${BLUE}                          巡检报告结束                                     ${NC}"
echo -e "${BLUE}===========================================================================${NC}"
} | tee $TEMP_FILE

# 过滤报告内容中的特殊字符
cat "$TEMP_FILE" | sed 's/\x1B\[[0-9;]*[mK]//g' > "$REPORT_FILE"

# 清理临时文件
rm -f "$TEMP_FILE"
# 保存报告到文件
echo "MySQL巡检报告已保存到 $REPORT_FILE"