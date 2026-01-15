# ======================================================================
# Author:       魏姚
# Email:        qluogxbd@gmail.com
# Description:  MySQL 二进制安装脚本
# Date:         2023-02-19
# Version:      1.0.3
# Notes:        脚本是在windows下编写的，直接复制或复制内容到在linux下运行可能存在问题
#               如果存在问题，请先安装 dos2unix 再运行dos2unix system_info.sh转换格式
#               yum install dos2unix -y （centos）
#               apt-get install dos2unix -y （ubuntu）
#               本脚本适配centos、kylin、ubuntu系统
#               若在ubuntu系统下运行，请使用bash system_info.sh 运行 使用sh system_info.sh 运行可能会出现未知错误
#               转载请注明出处，谢谢
# ======================================================================
# 别乱动下面注释位置，如果将下面的提示移动到其他位置，在sh无法显示的时候，可能无法显示提示信息
# 别乱动下面注释位置，如果将下面的提示移动到其他位置，在sh无法显示的时候，可能无法显示提示信息

# v1.0.3 版本说明
# 修复glibc版本小于2.12时，无法下载mysql二进制安装包的问题

#脚本版本号
VERSION_NUMBER="1.0.3"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 脚本说明

echo -e "${YELLOW}                    当前脚本版本号：$VERSION_NUMBER${NC}"
echo -e "${YELLOW}本脚本适配centos7.x、kylin V10 sp3、ubuntu系统${NC}"
echo -e "${YELLOW}若在ubuntu系统下运行,请使用bash system_info.sh 运行 使用sh system_info.sh 运行可能会出现未知错误${NC}"
echo -e "${YELLOW}如果脚本运行直接报错，请先安装 dos2unix 再 运行 dos2unix system_info.sh转换格式后运行${NC}"
echo -e "${YELLOW}如果系统中存在mariadb mysql 旧文件，脚本会自动清理${NC}"
echo -e "${YELLOW}如果系统中没有MySQL二进制安装包，系统将默认从官网安装mysql 8.0.36 文件大小约1.2G 请保证网络畅通${NC}"
echo -e "${YELLOW}请将MySQL二进制安装包放在/opt目录下，其路径可以存放但扫描需要时间${NC}"
echo -e "${YELLOW}默认数据库Data目录为/data/3306/data${NC}"
echo -e "${YELLOW}默认数据库安装路径为/usr/local/mysql（软链接）${NC}"
echo -e "${YELLOW}默认mysql启动用户为mysql${NC}"
echo -e "${YELLOW}======================================================================${NC}"
echo -e "${YELLOW}======================================================================${NC}"
echo -e "${YELLOW}======================================================================${NC}"
echo -e "${YELLOW}======================================================================${NC}"
echo " "


# 系统类型检测
OS_TYPE=""
if [ -f /etc/os-release ]; then
    OS_TYPE=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
elif [ -f /etc/centos-release ]; then
    OS_TYPE="centos"
elif [ -f /etc/kylin-release ]; then
    OS_TYPE="kylin"
fi

# 系统版本检测
VERSION_ID=""
if [ -f /etc/os-release ]; then
    VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
fi

# 清理旧数据库文件 mariadb mysql
clean_old_database_file(){
    case $OS_TYPE in
        "centos"|"kylin")
            yum remove -y `rpm -qa|grep mariadb` &>/dev/null
            yum remove -y `rpm -qa|grep mysql` &>/dev/null
            find / -name "mariadb" -o -name "mysql" | xargs rm -rf &>/dev/null
            ;;
        "ubuntu")
            apt-get remove -y `dpkg -l|grep mariadb` &>/dev/null
            apt-get remove -y `dpkg -l|grep mysql` &>/dev/null
            find / -name "mariadb" -o -name "mysql" | xargs rm -rf &>/dev/null
            ;;
    esac
    echo -e "${GREEN}清理旧数据库文件成功${NC}"
}

# 关闭SELinux
set_selinux(){
    setenforce 0 && echo -e "${GREEN}临时关闭SELinux成功${NC}"
    sed -ir 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config && echo -e "${GREEN}永久关闭SELinux成功${NC}"
}

# 关闭防火墙
set_firewall(){
    case $OS_TYPE in
        "centos"|"kylin")
            systemctl stop firewalld && systemctl disable firewalld && echo -e "${GREEN}关闭防火墙成功${NC}"
            ;;
        "ubuntu")
            ufw disable && echo -e "${GREEN}关闭防火墙成功${NC}"
            ;;
    esac
}

# yum仓库
set_yum_repo() {
case $OS_TYPE in
    "centos")
        mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup && echo -e "${GREEN}备份yum仓库成功${NC}"
        if [ $VERSION_ID -eq 8 ]; then
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo &>/dev/null && echo -e "${GREEN}设置yum仓库成功${NC}"
        elif [ $VERSION_ID -eq 7 ]; then
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo &>/dev/null && echo -e "${GREEN}设置yum仓库成功${NC}"
        elif [ $VERSION_ID -eq 6 ]; then
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-6.10.repo &>/dev/null && echo -e "${GREEN}设置yum仓库成功${NC}"
        else
            echo -e "${RED}当前脚本不支持 $OS_TYPE " " $VERSION_ID 系统${NC}"
        fi
        yum clean all && echo -e "${GREEN}清理yum缓存成功${NC}"
        yum install wget -y && echo -e "${GREEN}安装wget成功${NC}"
        ;;
    "ubuntu")
        cp /etc/apt/sources.list  /tmp/sources.list
        echo "deb https://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse \
            deb-src https://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse \

            deb https://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse \
            deb-src https://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse \

            deb https://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse \
            deb-src https://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse \

            # deb https://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse \
            # deb-src https://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse \

            deb https://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse \
            deb-src https://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse " > /etc/apt/sources.list && echo -e "${GREEN}设置apt仓库成功${NC}"  

            apt-cache policy
             
            apt update && echo -e "${GREEN}更新apt仓库成功${NC}"
        ;;
    esac
}

# epel 仓库设置函数
set_epel_repo(){
    # 备份epel仓库  
    if [ -f /etc/yum.repos.d/epel.repo ]; then
        mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.backup && echo -e "${GREEN}备份epel仓库成功${NC}"
    fi
    # 备份epel-testing仓库
    if [ -f /etc/yum.repos.d/epel-testing.repo ]; then
        mv /etc/yum.repos.d/epel-testing.repo /etc/yum.repos.d/epel-testing.repo.backup && echo -e "${GREEN}备份epel-testing仓库成功${NC}"
    fi
    # 设置epel仓库
    case $OS_TYPE in
        "centos")
            if [ $VERSION_ID -eq 8 ]; then
                yum install -y https://mirrors.aliyun.com/epel/epel-release-latest-8.noarch.rpm &>/dev/null 
                sed -i 's|^#baseurl=https://download.example/pub|baseurl=https://mirrors.aliyun.com|' /etc/yum.repos.d/epel* && sed -i 's|^metalink|#metalink|' /etc/yum.repos.d/epel* && echo -e "${GREEN}设置epel仓库成功${NC}"
            elif [ $VERSION_ID -eq 7 ]; then
                wget -O /etc/yum.repos.d/epel.repo https://mirrors.aliyun.com/repo/epel-7.repo && echo -e "${GREEN}设置epel仓库成功${NC}"
            elif [ $VERSION_ID -eq 6 ]; then
                wget -O /etc/yum.repos.d/epel.repo https://mirrors.aliyun.com/repo/epel-archive-6.repo && echo -e "${GREEN}设置epel仓库成功${NC}"
            else
                echo -e "${RED}当前脚本不支持 $OS_TYPE $VERSION_ID 系统${NC}"
            fi
            ;;  
        "kylin")
            wget -O /etc/yum.repos.d/epel.repo https://mirrors.aliyun.com/repo/epel-7.repo && echo -e "${GREEN}设置epel仓库成功${NC}"
            ;;
    esac
}

# 安装系统常用软件
install_system_base_software(){
    echo -e "${YELLOW}正在安装系统常用软件 vim net-tools ntpdate lrzsz dos2unix unzip tree screen${NC}"
    case $OS_TYPE in
        "centos"|"kylin")
            yum install -y vim net-tools ntpdate lrzsz dos2unix unzip tree screen libaio-devel && echo -e "${GREEN}安装系统常用软件成功${NC}"
            ;;
        "ubuntu")
            apt-get install -y vim net-tools ntpdate lrzsz dos2unix unzip tree screen libaio-devel && echo -e "${GREEN}安装系统常用软件成功${NC}"
            ;;
    esac
}

# 安装系统拓展软件
install_system_other_software(){
    case $OS_TYPE in
        "centos"|"kylin")
            yum install -y vim-enhanced iproute util-linux-ng gcc-c++ make cmake libxml2-devel openssl-devel \
		    screen git mailx  dstat xinetd rsync bind-utils ncurses-devel autoconf automake zlib* fiex* libxml* \
		    gcc man perl-Net-SSLeay perl-IO-Socket-SSL libmcrypt* libtool-ltdl-devel* \
		    dstat tcpdump telnet salt-minion iptables-services bind-utils mtr python-devel && echo -e "${GREEN}安装系统拓展软件成功${NC}"
            ;;
        "ubuntu")
            apt-get install -y vim-enhanced iproute util-linux-ng gcc-c++ make cmake libxml2-devel openssl-devel \
		    screen git mailx  dstat xinetd rsync bind-utils ncurses-devel autoconf automake zlib* fiex* libxml* \
		    gcc man perl-Net-SSLeay perl-IO-Socket-SSL libmcrypt* libtool-ltdl-devel* \
		    dstat tcpdump telnet salt-minion iptables-services bind-utils mtr python-devel && echo -e "${GREEN}安装系统拓展软件成功${NC}"
            ;;
    esac
}

# 设置时区
set_timezone(){
    timedatectl set-timezone Asia/Shanghai && echo -e "${GREEN}设置时区成功${NC}"
}

# 设置系统字符集
set_locale(){
    LANG=en_US.UTF-8
    echo "LANG=en_US.UTF-8" >> /etc/locale.conf && echo -e "${GREEN}设置系统字符集成功${NC}"
}

# 修改NTP时间同步服务器为阿里云，并设置时间同步任务
set_ntp_server(){
    echo -e "${YELLOW}正在设置NTP时间同步服务器为阿里云，并设置时间同步任务${NC}"
    # 检查ntp.aliyun.com,ntp1.aliyun.com,ntp2.aliyun.com,ntp3.aliyun.com,ntp4.aliyun.com是否可用 将可以访问的ntp服务器作为ntp_ip变量值
    # 如果都不可用，则提示用户输入ntp服务器 如果有可用的直接使用不再执行循环
    ntp_server_list=("ntp.aliyun.com" "ntp1.aliyun.com" "ntp2.aliyun.com" "ntp3.aliyun.com" "ntp4.aliyun.com")
    ntp_ip=""
    for ntp_server in ${ntp_server_list[@]}; do
        ping -c1 -w1 $ntp_server &>/dev/null
        if [ $? -eq 0 ]; then
            ntp_ip=$ntp_server
            break
        fi
    done
    if [ -z "$ntp_ip" ]; then
        # 询问用是否需要手动设置ntp服务器，如果不需要直接就跳过该设置
        read -p "是否需要手动设置ntp服务器？(y/n):" manual_set
        if [ "$manual_set" = "y" ]; then    
            read -p "请输入ntp服务器: " ntp_ip
        else
            echo -e "${RED}未设置ntp服务器${NC}"
        fi
    fi

    case $OS_TYPE in    
        "centos")
            ntpdate $ntp_ip &>/dev/null && echo -e "${GREEN}设置时间同步任务成功${NC}"
            echo "*/5 * * * * root /usr/sbin/ntpdate $ntp_ip &>/dev/null" >> /etc/crontab && echo -e "${GREEN}设置时间同步任务成功${NC}"
            clock -w && echo -e "${GREEN}设置硬件时间成功${NC}"
            ;;
        "ubuntu")
            sed -i 's|^NTP=.*|NTP=$ntp_ip|' /etc/systemd/timesyncd.conf && echo -e "${GREEN}设置时间同步任务成功${NC}"
            systemctl restart systemd-timesyncd && echo -e "${GREEN}设置时间同步任务成功${NC}"
            clock -w && echo -e "${GREEN}设置硬件时间成功${NC}"
            ;;
    esac
}


# 优化系统内核参数
sysctl_optimize() {
    echo -e "${YELLOW}正在优化系统内核参数${NC}"
    sed -i 's/net.ipv4.tcp_syncookies.*$/net.ipv4.tcp_syncookies = 1/g' /etc/sysctl.conf &>/dev/null
    cat >> /etc/sysctl.conf << EOF
net.ipv4.tcp_max_syn_backlog = 65536
net.core.netdev_max_backlog =  32768
net.core.somaxconn = 32768
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_tw_recycle = 1
#net.ipv4.tcp_tw_len = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mem = 94500000 915000000 927000000
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.ip_local_port_range = 1024  65535
EOF
    sysctl -p &>/dev/null && echo -e "${GREEN}优化系统内核参数成功${NC}"
}

# 关闭kdump
kill_kdump(){
    sed 's#crashkernel=1024M.high##g' /boot/grub2/grub.cfg && echo -e "${GREEN}关闭kdump成功${NC}"
}
# 卸载tmp挂载
umount_tmp(){
    umount /tmp
    systemctl mask tmp.mount && echo -e "${GREEN}临时关闭tmp挂载成功${NC}"
}
# 下载mysql二进制安装包
download_mysql_binary(){
    echo -e "正在前往官网下载mysql二进制安装包"
    # 查看当前系统glibc版本
    glibc_version=`ldd --version |awk 'NR==1{print $4}'`
    result=$(echo "$glibc_version > 2.11" | bc)
    
    # 根据glibc版本下载对应的mysql二进制安装包
    if [ $result -eq 1 ]; then
        # 询问用户是否需要前往官网下载mysql二进制安装包按n退出程序按y
        read -p "是否需要前往官网下载mysql二进制安装包？(y/n):" download_mysql_binary_flag
        if [ "$download_mysql_binary_flag" = "y" ]; then
            wget -p /opt https://downloads.mysql.com/archives/get/p/23/file/mysql-8.0.36-linux-glibc2.12-x86_64.tar && echo -e "${GREEN}下载mysql二进制安装包成功${NC}"
        else
            echo -e "${RED}未下载mysql二进制安装包${NC}"
            exit 1
        fi
    else
        echo -e "${RED}当前系统glibc版本小于2.12，无法下载mysql二进制安装包,请去官网手动下载放到/opt目录下${NC}"
        exit 1
    fi
    return 0
}

#判断系统中是否有mysql二进制安装包
check_mysql_binary(){
    # 默认路径为/opt目录下查找mysql*.tar或mysql*.xz文件
    mysql_path=$(find /opt -name "mysql*.tar" -o -name "mysql*.gz")
    if test -n "${mysql_path}"; then
        echo "find 的 mysql安装包路径为：${mysql_path}"
        return 0
    else
        echo -e "${RED}未在默认路径找到mysql安装包${NC}"
        echo -e "正在前往系统中查找mysql安装包"
        # 在系统中查找mysql*.tar或mysql*.xz文件
        mysql_path=$(find / -maxdepth 3 -name "mysql*.tar" -o -name "mysql*.xz")
        if test -n "${mysql_path}"; then
            echo "find 的 mysql安装包路径为：${mysql_path}"
            return 0
        else
            echo -e "${RED}未在系统中找到mysql安装包${NC}"
            return 1
        fi

    fi
}
#安装数据库
install_mysql(){
    # 判断系统中是否有mysql二进制安装包

    check_mysql_binary
    if [ $? -eq 1 ]; then
        download_mysql_binary
    fi
    # 判断 /usr/local/mysql 是否存在
    if [ -L "/usr/local/mysql" ]; then
        echo -e "${RED}/usr/local/mysql 已存在，请先备份数据${NC}"
        exit 1
    fi
    # 解压mysql安装包
    echo -e "${YELLOW}正在解压mysql安装包${NC}"
    echo -e "${YELLOW}解压路径为：/usr/local${mysql_path}${NC}"
    # 检查mysql 解压包是否已经存在
    mysql_test=`find /usr/local/ -name "mysql*x86_64"`
    if [ -n "${mysql_test}" ]; then
        echo -e "${YELLOW}MySQL解压包已存在${NC}"
    else
        tar -xvf ${mysql_path} -C /usr/local/ && echo -e "${GREEN}解压mysql安装包成功${NC}"
    fi

    # 获取解压后的mysql的文件夹目录
    mysql_dir=`find /usr/local/ -name "mysql*x86_64"`
    # 创建软链接
    if [ -L "/usr/local/mysql" ]; then
        echo -e "${YELLOW}/usr/local/mysql 已存在${NC}"
    elif [ -d "${mysql_dir}" ]; then
        cd /usr/local && ln -s ${mysql_dir} mysql && echo -e "${GREEN}创建软链接成功${NC}"
    else
        echo -e "${RED}${mysql_dir} 不存在${NC}"
        exit 1
    fi

    # 设置mysql环境变量
    grep -q 'export PATH="$PATH:/usr/local/mysql/bin"' /etc/profile
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}mysql环境变量已存在${NC}"
        source /etc/profile
    else
        echo 'export PATH="$PATH:/usr/local/mysql/bin"' >> /etc/profile && source /etc/profile && echo -e "${GREEN}设置mysql环境变量成功${NC}"
    fi

    # 设置mysql服务
    echo -e "${YELLOW}正在设置mysql服务${NC}"
    # 创建mysql用户
    if id mysql &>/dev/null; then
        echo -e "${YELLOW}mysql用户已存在${NC}"
    else
        useradd -M -s /sbin/nologin mysql && echo -e "${GREEN}创建mysql用户成功${NC}"
    fi

    # 创建mysql数据目录
    if [ -d "/data/3306/data" ]; then
        echo -e "${GREEN}/data/3306/data 已存在${NC}"
    else
        mkdir -p /data/3306/data && chown mysql.mysql /data/3306/data && echo -e "${GREEN}创建mysql数据目录成功${NC}"
    fi

    # 检查mysql是否安装成功
    mysql -V && echo -e "${GREEN}mysql安装成功${NC}"
    
}

# mysql 初始化
mysql_init(){
    echo -e "${YELLOW}正在初始化mysql${NC}"
    # 检查/data/3306/data 是否为空
    if [ -z "$(ls -A /data/3306/data)" ]; then
        # 初始化mysql
        mysqld --initialize-insecure --user=mysql --datadir=/data/3306/data  --basedir=/usr/local/mysql && echo -e "${GREEN}mysql初始化成功${NC}"
        echo -e "${YELLOW}mysql不安全初始化成功，请进入数据库后使用 ALTER USER 'root'@'localhost' IDENTIFIED BY '123456'; 设置密码${NC}"
    else
        echo -e "${RED}/data/3306/data 不为空，请先备份数据${NC}"
        exit 1
    fi
    
}

#编写mysql.service
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
User=mysql
Group=mysql
ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf
LimitNOFILE=5000
LimitNPROC=10000
EOF


systemctl daemon-reload && echo -e "${GREEN}编写mysql.service成功${NC}"
systemctl enable mysql && echo -e "${GREEN}设置mysql开机自启动成功${NC}"

}

# 编写 my.cnf
write_my_cnf(){
cat > /etc/my.cnf << EOF
[mysql]
socket=/tmp/mysql.sock
[mysqld]
user=mysql
basedir=/usr/local/mysql
datadir=/data/3306/data
socket=/tmp/mysql.sock
EOF
echo -e "${GREEN}编写my.cnf成功${NC}"

}
# 执行系统优化
system_optimize(){
    # 关闭SELinux
    set_selinux
    # 关闭防火墙
    set_firewall
    # 设置yum仓库
    if [ $OS_TYPE = "centos" ]; then
        set_yum_repo
    fi
    # epel 仓库设置
    set_epel_repo
    # 安装系统常用软件
    install_system_base_software
    # 设置时区
    set_timezone
    # 设置系统字符集
    set_locale
    # 设置NTP时间同步服务器
    set_ntp_server
    # 清理旧数据文件
    clean_old_database_file
    # 优化系统内核参数
    sysctl_optimize
    # 关闭kdump
    if [ $OS_TYPE = "kylin" ]; then
        kill_kdump
        umount_tmp
    fi       
}

# 主函数
main(){
    # 询问用户是否需要执行系统优化输入n跳过系统优化
    read -p "是否需要执行系统优化？(y/n):" system_optimize_flag
    if [ "$system_optimize_flag" = "y" ]; then
        system_optimize
    fi

    # 询问用户是否需要安装mysql 输入q退出
    echo -e "${YELLOW}本地安装MySQL 需要将MySQL安装包放在/opt目录下,其路径可以存放但扫描需要时间${NC}"
    echo -e "${YELLOW}如果本机没有MySQL安装包会自动从官网下载MySQL 8.0.36 文件大小约1.2G 请保证网络畅通${NC}"
    read -p "是否需要安装mysql？ y:安装 q:退出" install_mysql_flag
    if [ "$install_mysql_flag" = "q" ]; then
        exit 0
    fi
    if [ "$install_mysql_flag" = "y" ]; then
        # 安装mysql
        install_mysql
        # mysql 初始化
        mysql_init
        # 编写 my.cnf
        write_my_cnf
        # 编写mysql.service
        if [ -f "/usr/lib/systemd/system/mysql.service" ]; then
            echo -e "${YELLOW}mysql.service已存在${NC}"
        else
            write_mysql_service
        fi
         # 启动mysql
         systemctl restart mysql && echo -e "${GREEN}启动mysql成功${NC}"
    fi
}

main
