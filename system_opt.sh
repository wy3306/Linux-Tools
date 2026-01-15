# ======================================================================
# Author:       魏姚
# Email:        qluogxbd@gmail.com
# Description:  系统优化脚本
# Date:         2025-02-15
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

#脚本版本号
VERSION_NUMBER="1.0.3"

echo "                  当前脚本版本号：$VERSION_NUMBER"
echo "              本脚本适配centos8,7,6、kylin、ubuntu系统"
echo "若在ubuntu系统下运行,请使用bash system_info.sh 运行 使用sh system_info.sh 运行可能会出现未知错误"
echo "如果脚本运行直接报错，请先安装 dos2unix 再 运行 dos2unix system_info.sh转换格式后运行"
echo "======================================================================"
echo "======================================================================"
echo "======================================================================"
echo " "



# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 手动设置系统优化状态 0 自动 1 手动
MANUAL_OPT=0
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


# 用户输入监测 如果输入不是单个数字或者不是数字，则提示输入错误
check_input(){
    if ! [[ "$1" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}输入错误，请输入数字${NC}"
        return 1
    fi
    return 0
}
# 用户输入监测 可以用字母或者下划线_开头但不能以数字开头，不能超过15个字符
check_input_string(){
    if [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,14}$ ]]; then
        if [ ${#1} -le 15 ]; then
            return 0
        else
            echo -e "${RED}输入的字符串不能超过15个字符${NC}"
            return 1
        fi
    fi
    return 1
}

# 网络检查
check_network(){
ping -c1 -w1 223.5.5.5 &>/dev/null
if [ $? -eq 0 ]; then
    echo "外网访问正常"
    return 0
else
    echo "外网访问异常"
    return 1
fi

}

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

# 检查网关
check_gateway(){
    # 判断用户输入的网关是否符合要求
    if ! [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 测试网关是否可以访问
        ping -c1 -w1 $1 &>/dev/null
        if [ $? -ne 0 ]; then
            echo "输入的网关不可访问 是否忽略该设置？(y/n):"
            read -p "请输入您的选择: " ignore_gateway
            if [ "$ignore_gateway" = "y" ]; then
                return 0
            else
                return 1
            fi
        fi
    fi
    return 0
}

# 检查子网掩码
check_netmask(){
    # 判断用户输入的子网掩码是否符合要求
    if ! [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    return 0
}

# 检查DNS服务器
check_dns_server(){
    # 判断用户输入的DNS服务器是否符合要求
    if ! [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 测试DNS服务器是否可以访问
        ping -c1 -w1 $1 &>/dev/null
        if [ $? -ne 0 ]; then
            read -p "输入的DNS服务器不可访问 是否忽略该设置？(y/n):  " ignore_dns_server
            if [ "$ignore_dns_server" = "y" ]; then
                return 0
            else
                return 1
            fi
        fi
    fi
    return 0
}

# 检查IP地址
check_ip_address(){
    # 判断用户输入的ip地址是否符合要求
    if [[ "$1" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# 修改 /etc/sysconfig/network-scripts/ifcfg-$network_name 文件
set_cetnos_network_config(){
    if  [ ! -f /etc/sysconfig/network-scripts/ifcfg-$network_name ]; then
        echo "ifcfg-$network_name文件不存在"
        return 1
    fi
mv /etc/sysconfig/network-scripts/ifcfg-$network_name /etc/sysconfig/network-scripts/ifcfg-$network_name.backup && echo "备份ifcfg-$network_name文件成功"
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$network_name
DEVICE=$network_name
ONBOOT=yes
BOOTPROTO=static
IPADDR=$ip_address
NETMASK=$netmask
GATEWAY=$gateway
DNS1=$dns_server1
DNS2=$dns_server2
EOF
echo "设置ifcfg-$network_name文件成功"
return 0
}

# 设置ubuntu系统网络配置
set_ubuntu_network_config(){
    if [ ! -f /etc/netplan/01-netcfg.yaml ]; then
        echo "01-netcfg.yaml文件不存在"
        return 1
    fi
    mv /etc/netplan/01-netcfg.yaml /etc/netplan/01-netcfg.yaml.backup && echo "备份01-netcfg.yaml文件成功"      
cat <<EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    $network_name:
      dhcp4: false
      dhcp6: false
      addresses:
        - $ip_address/$netmask
      gateway4: $gateway
      nameservers:
        addresses:
          - $dns_server1
          - $dns_server2
EOF
echo "设置01-netcfg.yaml文件成功"
return 0
}

# 修改IP为静态IP，并设置网关，子网掩码，DNS服务器（可以设置两个）,修改网卡开机自启动
set_static_ip(){
    #显示当前系统所有网卡的名字
    # 获取网卡名字
    network_name_list=($(ip link show|awk -F ": " '/ens/{print $2}'))
    # 输出网卡名字
    echo "当前系统网卡的名称: ${network_name_list[@]}"
    # 判断用户输入的网卡名称是否在网络名字列表中
    while true
    do  
        # 让用户输入网卡名字
        read -p "请输入您要修改的网卡名称 | 输入q 退出脚本: " network_name
        if [ "$network_name" = "q" ]; then
            echo "已退出脚本"
            exit 0
        fi
        if [[ ! " ${network_name_list[@]} " =~ " ${network_name} " ]]; then
            echo "输入的网卡名称不存在 请重新输入"
            echo "当前系统网卡的名称: ${network_name_list[@]}"
        else
            break
        fi
    done
# 让用户输入网卡的ip地址
    while true
    do
        read -p "请输入您要修改的网卡的ip地址 | 格式: 192.168.1.1/24 | 输入q 退出脚本: " ip_address
        if [ "$ip_address" = "q" ]; then
            echo "已退出脚本"
            exit 0
        fi
        check_ip_address $ip_address
        if [ $? -ne 0 ]; then
            echo -e "${RED}输入的ip地址不符合要求,请重新输入${NC}"
        else
            break
        fi
    done
# 让用户输入网关，子网掩码，DNS服务器
    while true
    do
        read -p "请输入您要修改的网关 | 格式:192.168.1.1 | 输入q 退出脚本: " gateway
        if [ "$gateway" = "q" ]; then
            echo "已退出脚本"
            exit 0
        fi
        check_gateway $gateway
        if [ $? -ne 0 ]; then
            echo -e "${RED}输入的网关不可访问或不符合要求,请重新输入${NC}"
        else
            break
        fi
    done
    # 让用户输入子网掩码
    while true
    do
        read -p "请输入您要修改的子网掩码 | 格式: 255.255.255.0 | 输入q 退出脚本: " netmask
        if [ "$netmask" = "q" ]; then
            echo "已退出脚本"
            exit 0
        fi
        check_netmask $netmask
        if [ $? -ne 0 ]; then
            echo -e "${RED}输入的子网掩码不符合要求,请重新输入${NC}"
        else
            break
        fi
    done
    # 让用户输入DNS1服务器
    while true
    do
        read -p "请输入您要修改的DNS1服务器 | 格式: 192.168.1.1 | 输入q 退出脚本: " dns_server1
        if [ "$dns_server1" = "q" ]; then
            echo "已退出脚本"
            exit 0
        fi
        check_dns_server $dns_server1
        if [ $? -ne 0 ]; then
            echo -e "${RED}输入的DNS服务器不符合要求或不可访问,请重新输入${NC}"
        else
            break
        fi
    done
    while true
    do
        read -p "请输入您要修改的DNS2服务器 | 格式: 192.168.1.1 | 输入q 退出脚本: " dns_server2
        if [ "$dns_server2" = "q" ]; then
            echo "已退出脚本"
            exit 0
        fi
        check_dns_server $dns_server2
        if [ $? -ne 0 ]; then
            echo -e "${RED}输入的DNS服务器不符合要求或不可访问,请重新输入${NC}"
        else
            break
        fi
    done
    # 设置网络配置
  case $OS_TYPE in
    "centos"|"kylin")
        set_cetnos_network_config
        ;;
    "ubuntu")
        set_ubuntu_network_config
        ;;
  esac
  echo -e "${GREEN}设置网络配置成功${NC}"
  return 0
}

# 主机名设置函数，默认为"localhost@new" 如果用户输入其他主机名，则设置为输入的主机名
set_hostname(){
    # 判断是否为手动设置
    if [ $MANUAL_OPT -eq 1 ]; then
        while true
        do
            read -p "请输入您的主机名:" hostname
            # 如果输入为空，则设置主机名默认主机名
            if [ -z "$hostname" ]; then
                hostnamectl set-hostname "localhost@new"
                break
            fi
            # 如果输入不为空，则设置主机名为输入的主机名 如果输入的字符串不符合要求，则提示输入错误
            check_input_string $hostname
            if [ $? -ne 0 ]; then
                echo -e "${RED}输入的主机名不符合要求,请重新输入${NC}"
            else
                hostnamectl set-hostname $hostname
                echo -e "${GREEN}设置主机名成功${NC}"
                break
            fi
        done
    else
        hostnamectl set-hostname "localhost@new"
        echo -e "${GREEN}设置默认主机名成功${NC}"
    fi
}

# 关闭SELinux
set_selinux(){
    setenforce 0 && echo -e "${GREEN}关闭SELinux成功${NC}"
    sed -ir 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config && echo -e "${GREEN}关闭SELinux成功${NC}"
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

# 修改SSH配置
set_ssh(){
    
    # 询问用户是否需要修改SSH端口
    # 如果需要修改，则询问用户输入新的端口，如果不需要修改，则跳过该设置
    if [ $MANUAL_OPT -eq 1 ]; then
        # 询问用户是否需要修改SSH端口
        read -p "是否需要修改SSH端口？(y/n): " modify_ssh_port


        if [ "$modify_ssh_port" = "y" ]; then
            while true
            do
                read -p "请输入您要修改的SSH端口: " ssh_port
                # 判断用户输入的端口是否符合要求 用户输入必须是大于1024小于65535的数字
                if ! [[ "$ssh_port" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}输入错误，请输入大于1024小于65535的数字${NC}"
                elif [ $ssh_port -lt 1024 ] || [ $ssh_port -gt 65535 ]; then
                    echo -e "${RED}输入错误，请输入大于1024小于65535的数字${NC}"
                else
                    # 查看 /etc/ssh/sshd_config 文件中是否存在以Port开头的行 如果存在则将该行修改为 Port $ssh_port，否则添加
                    grep -q "^Port" /etc/ssh/sshd_config &>/dev/null
                    if [ $? -eq 0 ]; then
                        sed -ir "s/^Port .*/Port $ssh_port/" /etc/ssh/sshd_config && echo -e "${GREEN}修改SSH端口成功${NC}"
                        # 重启ssh服务
                        systemctl restart sshd && echo -e "${GREEN}重启ssh服务成功${NC}"
                        echo -e "${YELLOW}请使用新端口 $ssh_port 连接SSH${NC}"
                    else
                        echo "Port $ssh_port" >> /etc/ssh/sshd_config && echo -e "${GREEN}添加SSH端口成功${NC}"
                        # 重启ssh服务
                        systemctl restart sshd && echo -e "${GREEN}重启ssh服务成功${NC}"
                        echo -e "${YELLOW}请使用新端口 $ssh_port 连接SSH${NC}"
                    fi
                    break
                fi
            done
        else
            echo -e "${RED}跳过SSH端口设置${NC}"
        fi
    else
        echo -e "${RED}跳过SSH端口设置${NC}"
    fi
    
    # 禁止ssh使用DNS
    sed -i 's/#UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config &>/dev/null
    echo -e "${GREEN}禁止ssh使用DNS成功${NC}"
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
        ;;
    "ubuntu")
        cp /etc/apt/sources.list  /tmp/sources.list
        echo "deb https://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
            deb-src https://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse

            deb https://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
            deb-src https://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse

            deb https://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
            deb-src https://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse

            # deb https://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse
            # deb-src https://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse

            deb https://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
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
    echo -e "${YELLOW}正在安装系统常用软件 vim net-tools wget ntpdate lrzsz dos2unix unzip tree screen${NC}"
    case $OS_TYPE in
        "centos"|"kylin")
            yum install -y vim net-tools wget ntpdate lrzsz dos2unix unzip tree screen && echo -e "${GREEN}安装系统常用软件成功${NC}"
            ;;
        "ubuntu")
            apt-get install -y vim net-tools wget ntpdate lrzsz dos2unix unzip tree screen && echo -e "${GREEN}安装系统常用软件成功${NC}"
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

# 其他优化
other_optimize() {
    echo "alias net-pf-10 off" >> /etc/modprobe.conf 
    # 禁止ipv6
    echo "alias ipv6 off" >> /etc/modprobe.conf && echo -e "${GREEN}禁止ipv6成功${NC}"
    # 禁止icmp
    # echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all && echo -e "${GREEN}禁止icmp成功${NC}"
}

# 执行默认所有优化
all_optimize(){
    echo -e "${YELLOW}正在执行默认所有优化${NC}"
    set_selinux
    echo -e "${YELLOW}======================================================${NC}"
    set_firewall
    echo -e "${YELLOW}======================================================${NC}"
    set_ssh
    echo -e "${YELLOW}======================================================${NC}"
    set_yum_repo
    echo -e "${YELLOW}======================================================${NC}"
    set_epel_repo
    echo -e "${YELLOW}======================================================${NC}"
    install_system_base_software
    echo -e "${YELLOW}======================================================${NC}"
    set_timezone
    echo -e "${YELLOW}======================================================${NC}"
    set_locale
    echo -e "${YELLOW}======================================================${NC}"
    set_ntp_server
    echo -e "${YELLOW}======================================================${NC}"
    sysctl_optimize
    echo -e "${YELLOW}======================================================${NC}"
    other_optimize
    echo -e "${YELLOW}======================================================${NC}"
    clean_old_database_file
    echo -e "${YELLOW}======================================================${NC}"
    echo ""
    echo ""
    echo ""
    echo ""
    
    echo -e "${GREEN}################### 所有优化完成 ! ######################${NC}"
    echo ""
    echo ""
    echo ""
    echo ""
}

# 系统优化菜单
menu(){
echo -e "${YELLOW}########################################################${NC}"
echo -e "${YELLOW}#################### 系统优化选项 #######################${NC}"
echo -e "${PURPLE}   [ 0 ]    设置静态网卡配置${NC}" 
echo -e "${PURPLE}   [ 1 ]    设置主机名${NC}"
echo -e "${BLUE}   [ 2 ]    执行默认优化${NC}"
echo -e "${BLUE}   [ 3 ]    关闭SELinux${NC}"
echo -e "${BLUE}   [ 4 ]    关闭防火墙${NC}"
echo -e "${BLUE}   [ 5 ]    优化SSH配置${NC}"   
echo -e "${BLUE}   [ 6 ]    设置yum源${NC}"
echo -e "${BLUE}   [ 7 ]    设置epel源${NC}"
echo -e "${BLUE}   [ 8 ]    安装系统常用软件${NC}"
echo -e "${BLUE}   [ 9 ]    设置时区${NC}"
echo -e "${BLUE}   [ 10 ]    设置系统字符集${NC}"
echo -e "${BLUE}   [ 12 ]   设置NTP时间同步服务器${NC}"
echo -e "${BLUE}   [ 13 ]   系统内核优化${NC}"
echo -e "${CYAN}   [ 14 ]    安装系统拓展软件 ${NC}"
echo -e "${CYAN}   [ 15 ]   其他优化${NC}"
echo -e "${CYAN}   [ 16 ]   清理旧数据库文件${NC}"
echo -e "${RED}   [ 17 ]   退出脚本${NC}"
echo -e "${YELLOW}########################################################${NC}"
}


# 脚本主程序
while true
do
    menu
    while true
    do
        read -p "请输入您的选择: " choice
        check_input $choice
        if [ $? -ne 0 ]; then
            clear && menu
            echo "您的输入错误，请重新输入"
        else
            break
        fi
    done

    #根据用户输入的选择，执行相应的操作
    case $choice in
        0)
            set_static_ip
            ;;
        1)
            MANUAL_OPT=1
            set_hostname
            MANUAL_OPT=0
            ;;
        2)
            all_optimize
            ;;
        3)
            set_selinux
            ;;
        4)
            set_firewall
            ;;
        5)
            MANUAL_OPT=1
            set_ssh
            MANUAL_OPT=0
            ;;
        6)
            MANUAL_OPT=1
            set_yum_repo
            MANUAL_OPT=0
            ;;
        7)
            MANUAL_OPT=1
            set_epel_repo
            MANUAL_OPT=0
            ;;
        8)
            install_system_base_software
            ;;
        9)
            set_timezone
            ;;
        10)
            set_locale
            ;;
        12)
            set_ntp_server
            ;;
        13)
            sysctl_optimize
            ;;
        14)
            echo "安装系统拓展软件 软件数量较多 请耐心等待"
            install_system_other_software
            ;;
        15)
            other_optimize
            ;;
        16)
            clean_old_database_file
            ;;
        17)
            echo "脚本已退出"
            exit 0
            ;;  
    esac
done
