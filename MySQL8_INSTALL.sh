#!/bin/bash


#定义基础变量参数

# 当前主机IP和主机名
IPAddress='192.168.3.27'
HostName=$(hostname)
# 另一条主机IP和主机名
IPAddress2='192.168.3.28'
HostName2='weiyao'
# server_id
serverId='1'
# MySQL 版本
MysqlVersion='5.7.44'
# 下载的 mysql 二进制包位置
mysql_path='/root/'
# mysql 启动用户
mysql_user='service'
# 如果server_id 为1 则 auto_increment=1
# 如果server_id 为2 则 auto_increment=2
auto_incre=''
if [ "$serverId" == "1" ]; then
    auto_incre=1
elif [ "$serverId" == "2" ]; then
    auto_incre=2
fi
# 定义mysql root密码
MysqlRootPassword='123456'

# 生成随机密码
make_password() {
# 定义字符集
lowercase="abcdefghijklmnopqrstuvwxyz"
uppercase="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
digits="0123456789"
special="!@#$%^&*()-_=+"

# 确保每种字符至少有一个
password=$(printf "%s" "$(echo "$lowercase" | fold -w1 | shuf -n1)" \
                    "$(echo "$uppercase" | fold -w1 | shuf -n1)" \
                    "$(echo "$digits" | fold -w1 | shuf -n1)" \
                    "$(echo "$special" | fold -w1 | shuf -n1)")

# 生成剩余的字符
all_chars="${lowercase}${uppercase}${digits}${special}"
remaining_length=$((10 - ${#password}))
for ((i=1; i<=remaining_length; i++)); do
    password="${password}$(echo "$all_chars" | fold -w1 | shuf -n1)"
done

# 打乱密码顺序
MysqlRootPassword=$(echo "$password" | fold -w1 | shuf | tr -d '\n')
}

# 安装mysql 依赖
install_depend() {
    yum install -y  dos2unix numactl gcc gcc-c++ ncurses-devel bison cmake perl-DBI perl-DBD-MySQL libevent \
    libevent-devel boost-program-options readline-devel libev libev-devel libev-source perl-TermReadKey openssl-devel \
}

# 清理原有mysql
clean_old_mysql() {
    # 清理原有mysql
    rpm -qa|grep mariadb |xargs -i yum -y remove
    rpm -qa|grep mysql |xargs -i yum -y remove
}
# 检查用户是否存在
check_user() {
    if id $mysql_user >/dev/null 2>&1; then
        echo "用户 $mysql_user 已存在"
    else
        echo "用户 $mysql_user 不存在"
        # 创建用户
        groupadd -g3306 service
        useradd -g service -u3306 $mysql_user
    fi
}

# 系统优化部分

# 修改登录限制
modify_login_limit() {

cp /etc/pam.d/login /etc/pam.d/login.bak

cat >> /etc/pam.d/login <<EOF
session    optional     pam_limits.so
session    required     pam_limits.so
EOF

ulimit -n 65536  
ulimit -u 65536  
ulimit -l unlimited

}

# 修改 unlimit 参数
modify_unlimit() {
cp /etc/security/limits.conf /etc/security/limits.conf.bak
sed -i s/*/#*/ /etc/security/limits.conf
cat >> /etc/security/limits.conf <<EOF
*                soft    nofile          65536      
*                hard    nofile          65536 
*                soft    nproc           65536      
*                hard    nproc           65536 
*                soft    memlock         unlimited  
*                hard    memlock         unlimited
EOF
#查看 /etc/security/limits.d/下 某个数字-nproc.conf为后缀的文件
nproc_filename=`ls /etc/security/limits.d/ | grep nproc.conf`
sed -i s/*/#*/ /etc/security/limits.d/$nproc_filename 
sed -i s/root/#root/ /etc/security/limits.d/$nproc_filename
}

# 修改 hosts 文件
modify_hosts() {
cat >> /etc/hosts <<EOF
$IPAddress $HostName 
$IPAddress2 $HostName2
EOF
}

# 关闭防火墙和 selinux
disable_firewalld() {
systemctl stop firewalld.service
systemctl disable firewalld.service
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
sed -i 's/SELINUXTYPE=targeted/\#SELINUXTYPE=targeted /g' /etc/selinux/config
setenforce 0
getenforce  
}

# 系统内核参数优化
Optimize_kernel() {
cat >> /etc/sysctl.conf  <<EOF

#shmmax=memory*1024*1024*1024*90%
#shmall=shmmax/getconf PAGESIZE
#kernel.shmmax = 7730941132                       
#kernel.shmall = 1887436                          
#kernel.shmmni = 4096                              
kernel.sem = 1250 320000 100 256                 
net.ipv4.tcp_syncookies = 1                       
net.ipv4.tcp_tw_reuse = 1                         
net.ipv4.tcp_tw_recycle = 1                       
net.ipv4.tcp_keepalive_time = 300                 
net.ipv4.tcp_keepalive_intvl = 30                 
net.ipv4.tcp_keepalive_probes = 3                 
net.ipv4.tcp_fin_timeout = 30                     
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_mem = 94500000 915000000 927000000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.ip_local_port_range = 9000 65500         
net.core.somaxconn = 65536                       
net.core.netdev_max_backlog = 65536              
net.core.rmem_default = 262144                    
net.core.rmem_max = 4194304                       
net.core.wmem_default = 8388608                    
net.core.wmem_max = 20971520                       
fs.file-max = 6815744                             
fs.aio-max-nr = 4194304
vm.min_free_kbytes = 51200
vm.dirty_background_ratio = 10                    
vm.dirty_ratio = 20                               
vm.zone_reclaim_mode = 0                          
net.ipv4.ip_local_port_ range = 20000 65535
vm.swappiness = 1
EOF

sysctl -p
echo 0 > /proc/sys/vm/zone_reclaim_mode
}
# 优化IO调度
optimize_IO() {
echo deadline > /sys/block/sda/queue/scheduler
echo "echo deadline > /sys/block/sda/queue/scheduler" >> /etc/rc.local
}

#创建目录
makedir() {
mkdir -p /data/src
mkdir -p /data/mysql/binlog/3306
mkdir -p /data/mysql/data/3306
mkdir -p /data/mysql/redo/3306
mkdir -p /data/mysql/undo/3306
mkdir -p /data/mysql/tmp
}
#判断系统中是否有mysql二进制安装包  默认路径为/opt目录下查找mysql*.tar或mysql*.xz文件
check_mysql_binary(){
    # 默认路径为/root/目录下查找mysql*.tar或mysql*.xz文件
    mysql_path=$(find /root -name "mysql*.tar" -o -name "mysql*.gz")
    if test -n "${mysql_path}"; then
        echo "mysql安装包路径为：${mysql_path}"
        return 0
    else
        echo -e "${RED}未在默认路径找到mysql安装包${NC}"
        echo -e "正在前往系统中查找mysql安装包"
        # 在系统中查找mysql*.tar或mysql*.xz文件
        mysql_path=$(find / -maxdepth 3 -name "mysql*.tar" -o -name "mysql*.gz")
        if test -n "${mysql_path}"; then
            echo "find 的 mysql安装包路径为：${mysql_path}"
            return 0
        else
            echo -e "${RED}未在系统中找到mysql安装包${NC}"
            return 1
        fi

    fi
}
# 记录mysql安装包中的版本号
get_mysql_version() {
    # 获取mysql安装包中的版本号
    MysqlVersion=$(echo $mysql_path | grep mysql | awk -F '-' '{print $2}' | awk -F '.' '{print $1"."$2}')
}

# 根据系统配置动态生成mysql配置文件 /etc/my.cnf
create_mysql_conf() {
# innodb_buffer_pool_size   --根据实际内存调整，一般置主机内存的75%左右 向下取整数
innodb_buffer_pool=`free -g | grep Mem | awk '{printf "%dG", int($2*0.75)}'`
# 备份my.cnf文件
mv /etc/my.cnf /etc/my.cnf.bak
# 如果是5.7版本
if [ "$MysqlVersion" == "5.7" ]; then
cat >> /etc/my.cnf <<EOF  
[client]
port = 3306
socket = /data/mysql/data/3306/mysql.sock

[mysqld]
user = $mysql_user
server_id=$serverId
basedir = /usr/local/mysql
datadir = /data/mysql/data/3306
character_sets_dir = /usr/local/mysql/share/charsets
plugin_dir = /usr/local/mysql/lib/plugin
port = 3306
socket = /data/mysql/data/3306/mysql.sock
pid_file = /data/mysql/data/3306/mysqld.pid
tmpdir = /data/mysql/tmp
character_set_server = utf8
autocommit = 1
transaction_isolation = READ-COMMITTED
lower_case_table_names = 1
auto_increment_offset = 1
auto_increment_increment = $auto_incre

# connection #
interactive_timeout = 1800
wait_timeout = 1800
lock_wait_timeout = 1800
skip_name_resolve = 1
max_connections = 8000
max_connect_errors = 1000

# log settings #
log_error = mysqld.log
slow_query_log = 1
slow_query_log_file = slow.log
log_queries_not_using_indexes = 1
log_slow_admin_statements = 1
log_slow_slave_statements = 1
log_throttle_queries_not_using_indexes = 10
expire_logs_days = 7
long_query_time = 2
min_examined_row_limit = 100
binlog_rows_query_log_events = 1
log_slave_updates = 1
log_timestamps = system


default_storage_engine = INNODB
innodb_data_file_path = ibdata1:1024M:autoextend
innodb_temp_data_file_path = ibtmp1:512M:autoextend:max:30720M 
innodb_undo_tablespaces = 4
innodb_undo_directory = /data/mysql/undo/3306
innodb_log_group_home_dir= /data/mysql/redo/3306
innodb_log_file_size = 1G
innodb_log_files_in_group = 5
innodb_flush_log_at_trx_commit = 1
innodb_lock_wait_timeout = 600
innodb_file_per_table = TRUE
innodb_flush_method = O_DIRECT
innodb_buffer_pool_size = $innodb_buffer_pool
innodb_buffer_pool_instances = 8
innodb_log_buffer_size = 16M
innodb_read_io_threads = 24
innodb_write_io_threads = 24


key_buffer_size = 256M
max_allowed_packet = 8M
table_open_cache = 4096
sort_buffer_size = 8M
read_buffer_size = 8M
read_rnd_buffer_size = 32M
myisam_sort_buffer_size = 64M
join_buffer_size = 2M
thread_cache_size = 32
EOF

else
cat >> /etc/my.cnf <<EOF

[client]
port = 3306
socket = /data/mysql/data/3306/mysql.sock

[mysqld]
user = $mysql_user
server_id=$serverId
basedir = /usr/local/mysql
datadir = /data/mysql/data/3306
character_sets_dir = /usr/local/mysql/share/charsets
plugin_dir = /usr/local/mysql/lib/plugin
port = 3306
socket = /data/mysql/data/3306/mysql.sock
pid_file = /data/mysql/data/3306/mysqld.pid
tmpdir = /data/mysql/tmp
character_set_server = utf8
autocommit = 1
transaction_isolation = READ-COMMITTED
lower_case_table_names = 1
auto_increment_offset = 1    # for mutil master
auto_increment_increment = $auto_incre

# connection #
interactive_timeout = 1800
wait_timeout = 1800
lock_wait_timeout = 1800
skip_name_resolve = 1
max_connections = 8000
max_connect_errors = 1000

# log settings #
log_error = mysqld.log
slow_query_log = 1
slow_query_log_file = slow.log
log_queries_not_using_indexes = 1
log_slow_admin_statements = 1
log_slow_slave_statements = 1
log_throttle_queries_not_using_indexes = 10
expire_logs_days = 7
long_query_time = 2
min_examined_row_limit = 100
binlog_rows_query_log_events = 1
log_slave_updates = 1
log_timestamps = system


default_storage_engine = INNODB
innodb_data_file_path = ibdata1:1024M:autoextend
innodb_temp_data_file_path = ibtmp1:512M:autoextend:max:30720M 
innodb_undo_tablespaces = 4
innodb_undo_directory = /data/mysql/undo/3306
innodb_log_group_home_dir= /data/mysql/redo/3306
innodb_redo_log_capacity = 5G
innodb_flush_log_at_trx_commit = 1
innodb_lock_wait_timeout = 600
innodb_file_per_table = TRUE
innodb_flush_method = O_DIRECT
innodb_buffer_pool_size = $innodb_buffer_pool
innodb_buffer_pool_instances = 8
innodb_log_buffer_size = 16M
innodb_read_io_threads = 24
innodb_write_io_threads = 24


key_buffer_size = 256M
max_allowed_packet = 8M
table_open_cache = 4096
sort_buffer_size = 8M
read_buffer_size = 8M
read_rnd_buffer_size = 32M
myisam_sort_buffer_size = 64M
join_buffer_size = 2M
thread_cache_size = 32
EOF
fi
}

# 安装mysql
install_mysql() {
    # 将mysql安装包解压到 /data/src 目录下
    tar -zxvf $mysql_path -C /data/src/
    # 获取mysql安装目录
    mysql_dir=$(ls /data/src/ | grep mysql)
    # 创建软链接
    ln -s /data/src/$mysql_dir /usr/local/mysql
    # 修改文件权限
    chown -R root:$mysql_user /usr/local/mysql
    chown -R $mysql_user:service /data/mysql
    # 配置mysql环境变量
    echo 'PATH=$PATH:$HOME/bin:/usr/local/mysql/bin/' >> /home/$mysql_user/.bashrc
    echo 'PATH=$PATH:$HOME/bin:/usr/local/mysql/bin/' >> ~/.bashrc
    # 加载环境变量
    source ~/.bashrc
    # 初始化mysql数据库
    /usr/local/mysql/bin/mysqld --initialize-insecure --user=$mysql_user --basedir=/usr/local/mysql --datadir=/data/mysql/data/3306
}

# 编写systemd服务
write_mysql_service(){
cat << EOF > /usr/lib/systemd/system/mysql.service
[Unit]
Description=MySQL Server
Documentation=man:mysqld(8)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=$mysql_user
ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf
LimitNOFILE=5000
LimitNPROC=10000
EOF
systemctl daemon-reload && systemctl enable mysql
}

# 启动mysql
start_mysql(){
systemctl start mysql
}
# 设置mysql密码
set_mysql_password(){
    make_password
    # 将mysql密码写入文件
    echo $MysqlRootPassword > /root/.mysql_root_password
    # 设置mysql密码 
    echo "$MysqlRootPassword" 
    # 很关键，可以刷新mysql sokcet 不然无法连接
    systemctl restart mysql
    sleep 5
    mysql -uroot -P3306 -hlocalhost -e  "set password='$MysqlRootPassword';"
}

main(){
    # 安装mysql 依赖
    install_depend
    # 清理原有mysql
    clean_old_mysql
    # 检查用户是否存在
    check_user
    # 修改登录限制
    modify_login_limit
    # 修改 unlimit 参数
    modify_unlimit
    # 修改 hosts 文件
    modify_hosts
    # 关闭防火墙和 selinux
    disable_firewalld
    # 系统内核参数优化
    Optimize_kernel
    # 优化IO调度
    optimize_IO
    #创建目录
    makedir
    #判断系统中是否有mysql二进制安装包
    check_mysql_binary
    # 记录mysql安装包中的版本号
    get_mysql_version
    # 根据系统配置动态生成mysql配置文件 /etc/my.cnf
    create_mysql_conf
    # 安装mysql
    install_mysql
    # 编写systemd服务
    write_mysql_service
    # 启动mysql
    start_mysql
    # 设置mysql密码
    echo "设置mysql密码"
    set_mysql_password

}
main
