#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#====================================================
#	System Required: CentOS,Debian/Ubuntu,OracleLinux
#	Author: Kinoko
#====================================================

sh_ver="1.2.9"

Green_font_prefix="\033[32m"
Red_font_prefix="\033[31m"
Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Green_font_prefix}[注意]${Font_color_suffix}"

# 更新脚本
update_shell() {
    echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
    sh_new_ver=$(wget -qO- "https://oss.amogu.cn/linux/tool/toolx.sh" | grep 'sh_ver="' | awk -F "=" '{print $NF}' | sed 's/\"//g' | head -1)
    [[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败 !" && start_menu
    if [ ${sh_new_ver} != ${sh_ver} ]; then
        echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
        read -p "(默认: y):" yn
        [[ -z "${yn}" ]] && yn="y"
        if [[ ${yn} == [Yy] ]]; then
            wget -N "https://oss.amogu.cn/linux/tool/toolx.sh" && chmod +x toolx.sh && ./toolx.sh
            echo -e "脚本已更新为最新版本[ ${sh_new_ver} ] !"
        else
            echo && echo "	已取消..." && echo
        fi
    else
        echo -e "当前已是最新版本[ ${sh_new_ver} ] !"
        sleep 2s && ./toolx.sh
    fi
}

# 系统软件包升级
update_software() {
    case "${release}" in
    centos)
        yum update -y
        yum clean all && yum makecache
        ;;
    debian | ubuntu)
        apt-get update && apt-get dist-upgrade -y
        apt-get autoremove -y && apt-get autoclean && apt-get remove -y && apt-get clean
        ;;
    *)
        echo "不支持的操作系统版本: ${release}" >&2
        exit 1
        ;;
    esac

    # Docker系统清理
    docker rmi $(docker images -aq) || true
    docker system prune -f
    docker ps -a
}

# 清理系统历史内核
clean_kernel() {
    if [[ "${release}" == "centos" || "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        detele_kernel_head
        detele_kernel
        renew_grub
        echo -e "${Tip} ${Red_font_prefix}请检查上面是否有内核信息，无内核千万别重启${Font_color_suffix}"
        echo -e "${Tip} ${Red_font_prefix}rescue不是正常内核，要排除这个${Font_color_suffix}"
        check_kernel
        stty erase '^H' && read -p "需要重启VPS后，才能应用修改，是否现在重启 ? [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Yy] ]]; then
            echo -e "${Info} VPS 重启中..."
            reboot
        fi
    else
        echo -e "${Error} 您的系统发行版本暂不支持此功能 !" && exit 1
    fi
}

# 回程路由测试
check_backtrace() {
    if [[ "${bit}" == "x86_64" ]]; then
        wget -O backtrace.tar.gz https://github.com/zhanghanyun/backtrace/releases/latest/download/backtrace-linux-amd64.tar.gz
    else
        wget -O backtrace.tar.gz https://github.com/zhanghanyun/backtrace/releases/latest/download/backtrace-linux-arm64.tar.gz
    fi
    tar -xf backtrace.tar.gz && rm -f backtrace.tar.gz && chmod +x backtrace && ./backtrace && rm -f backtrace
}

# Netflix解锁检测
check_netflix() {
    if [[ "${bit}" == "x86_64" ]]; then
        wget -O nf https://github.com/sjlleo/netflix-verify/releases/download/v3.1.0/nf_linux_amd64
    else
        wget -O nf https://github.com/sjlleo/netflix-verify/releases/download/v3.1.0/nf_linux_arm64
    fi
    chmod +x nf && ./nf && rm -f nf
}

# 安装Docker
install_docker() {
    echo "检查 Docker 是否已安装..."
    if command -v docker &>/dev/null; then
        echo "Docker 已安装！"
        return
    fi

    echo "检测到 Docker 未安装。"

    if [[ "${release}" == "centos" ]]; then
        # 卸载旧版本的 Docker
        yum remove -y docker \
            docker-client \
            docker-client-latest \
            docker-common \
            docker-latest \
            docker-latest-logrotate \
            docker-logrotate \
            docker-selinux \
            docker-engine-selinux \
            docker-engine

        # 安装所需的软件包
        yum install -y yum-utils net-tools

        # 添加 Docker 仓库
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum clean all
        yum makecache

        # 安装 Docker
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        # 卸载旧版本的 Docker
        apt-get remove -y docker \
            docker-engine \
            docker.io

        # 安装所需的软件包
        apt-get update
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # 添加 Docker 仓库密钥
        curl -fsSL https://download.docker.com/linux/${release}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # 添加 Docker 仓库
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${release} $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

        # 安装 Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose
    else
        echo "您的系统发行版本不受支持！"
        exit 1
    fi

    # 启用并启动 Docker 服务
    systemctl enable docker --now

    # 配置 Docker 设置
    tee /etc/docker/daemon.json <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "1"
    },
    "storage-driver": "overlay2"
}
EOF

    # 重新加载 systemd 配置并重启 Docker
    systemctl daemon-reload
    systemctl restart docker

    # 验证 Docker 安装
    docker version
    docker-compose version
}

# 清理脚本运行残留
clean_tempfile() {
    rm -rf 1
    rm -rf /root/.abench
    rm -rf /root/.config/ookla
}

# 开始菜单
start_menu() {
    clear
    echo && echo -e " Linux管理 一键脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix} from fairysen.com
 ${Green_font_prefix}0.${Font_color_suffix} 升级脚本
 ${Green_font_prefix}1.${Font_color_suffix} 软件升级          ${Green_font_prefix}2.${Font_color_suffix} 清理内核
 ${Green_font_prefix}3.${Font_color_suffix} 网络测速          ${Green_font_prefix}4.${Font_color_suffix} 回程路由测试
 ${Green_font_prefix}5.${Font_color_suffix} 硬件信息查看      ${Green_font_prefix}6.${Font_color_suffix} 流媒体全面检测
 ${Green_font_prefix}7.${Font_color_suffix} Netflix 解锁检测
 ${Green_font_prefix}8.${Font_color_suffix} 安装 BBR 加速     ${Green_font_prefix}9.${Font_color_suffix} 安装 Ehco 转发
 ${Green_font_prefix}10.${Font_color_suffix} 安装 Gost 转发   ${Green_font_prefix}11.${Font_color_suffix} 安装 Realm 转发
 ${Green_font_prefix}12.${Font_color_suffix} 安装 Docker 环境
 ${Green_font_prefix}99.${Font_color_suffix} 退出脚本
————————————————————————————————————————————————————————————————" &&
        check_status
    get_system_info
    echo -e " 系统信息: ${Font_color_suffix}$opsy ${Green_font_prefix}$virtual${Font_color_suffix} $arch ${Green_font_prefix}$kern${Font_color_suffix} "
    echo -e " 当前拥塞控制算法为: ${Green_font_prefix}${net_congestion_control}${Font_color_suffix} 当前队列算法为: ${Green_font_prefix}${net_qdisc}${Font_color_suffix} "

    read -p " 请输入数字 :" num
    case "$num" in
    0)
        update_shell
        ;;
    1)
        update_software
        ;;
    2)
        clean_kernel
        ;;
    3)
        curl -sSL bench.sh | bash
        ;;
    4)
        check_backtrace
        ;;
    5)
        bash <(curl -Ls git.io/ceshi)
        ;;
    6)
        bash <(curl -Ls check.unlock.media) -M 4
        ;;
    7)
        check_netflix
        ;;
    8)
        wget --no-check-certificate -O tcpx.sh https://github.000060000.xyz/tcpx.sh && chmod +x tcpx.sh && ./tcpx.sh
        ;;
    9)
        wget -O ehco.sh https://raw.githubusercontent.com/owogo/EasyEhco/main/ehco.sh && chmod +x ehco.sh && ./ehco.sh
        ;;
    10)
        wget -O gost.sh https://raw.githubusercontent.com/KANIKIG/Multi-EasyGost/master/gost.sh && chmod +x gost.sh && ./gost.sh
        ;;
    11)
        wget -O realm.sh https://git.io/realm.sh && chmod +x realm.sh && ./realm.sh
        ;;
    12)
        install_docker
        ;;
    99)
        exit 1
        ;;
    *)
        clear
        echo -e "${Error}:请输入正确数字 [0-99]"
        sleep 5s
        start_menu
        ;;
    esac
}

###########################################
############ Start: 系统检测组件 ###########
###########################################
# 检查系统
check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi

    _exists() {
        local cmd="$1"
        if eval type type >/dev/null 2>&1; then
            eval type "$cmd" >/dev/null 2>&1
        elif command >/dev/null 2>&1; then
            command -v "$cmd" >/dev/null 2>&1
        else
            which "$cmd" >/dev/null 2>&1
        fi
        local rt=$?
        return ${rt}
    }

    get_opsy() {
        [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
        [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
        [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
    }

    get_system_info() {
        opsy=$(get_opsy)
        arch=$(uname -m)
        kern=$(uname -r)
        virt_check
    }

    virt_check() {
        if [ -f "/usr/bin/systemd-detect-virt" ]; then
            Var_VirtType="$(/usr/bin/systemd-detect-virt)"
            # 虚拟机检测
            if [ "${Var_VirtType}" = "qemu" ]; then
                virtual="QEMU"
            elif [ "${Var_VirtType}" = "kvm" ]; then
                virtual="KVM"
            elif [ "${Var_VirtType}" = "zvm" ]; then
                virtual="S390 Z/VM"
            elif [ "${Var_VirtType}" = "vmware" ]; then
                virtual="VMware"
            elif [ "${Var_VirtType}" = "microsoft" ]; then
                virtual="Microsoft Hyper-V"
            elif [ "${Var_VirtType}" = "xen" ]; then
                virtual="Xen Hypervisor"
            elif [ "${Var_VirtType}" = "bochs" ]; then
                virtual="BOCHS"
            elif [ "${Var_VirtType}" = "uml" ]; then
                virtual="User-mode Linux"
            elif [ "${Var_VirtType}" = "parallels" ]; then
                virtual="Parallels"
            elif [ "${Var_VirtType}" = "bhyve" ]; then
                virtual="FreeBSD Hypervisor"
            # 容器虚拟化检测
            elif [ "${Var_VirtType}" = "openvz" ]; then
                virtual="OpenVZ"
            elif [ "${Var_VirtType}" = "lxc" ]; then
                virtual="LXC"
            elif [ "${Var_VirtType}" = "lxc-libvirt" ]; then
                virtual="LXC (libvirt)"
            elif [ "${Var_VirtType}" = "systemd-nspawn" ]; then
                virtual="Systemd nspawn"
            elif [ "${Var_VirtType}" = "docker" ]; then
                virtual="Docker"
            elif [ "${Var_VirtType}" = "rkt" ]; then
                virtual="RKT"
            # 特殊处理
            elif [ -c "/dev/lxss" ]; then # 处理WSL虚拟化
                Var_VirtType="wsl"
                virtual="Windows Subsystem for Linux (WSL)"
            # 未匹配到任何结果, 或者非虚拟机
            elif [ "${Var_VirtType}" = "none" ]; then
                Var_VirtType="dedicated"
                virtual="None"
                local Var_BIOSVendor
                Var_BIOSVendor="$(dmidecode -s bios-vendor)"
                if [ "${Var_BIOSVendor}" = "SeaBIOS" ]; then
                    Var_VirtType="Unknown"
                    virtual="Unknown with SeaBIOS BIOS"
                else
                    Var_VirtType="dedicated"
                    virtual="Dedicated with ${Var_BIOSVendor} BIOS"
                fi
            fi
        elif [ ! -f "/usr/sbin/virt-what" ]; then
            Var_VirtType="Unknown"
            virtual="[Error: virt-what not found !]"
        elif [ -f "/.dockerenv" ]; then # 处理Docker虚拟化
            Var_VirtType="docker"
            virtual="Docker"
        elif [ -c "/dev/lxss" ]; then # 处理WSL虚拟化
            Var_VirtType="wsl"
            virtual="Windows Subsystem for Linux (WSL)"
        else # 正常判断流程
            Var_VirtType="$(virt-what | xargs)"
            local Var_VirtTypeCount
            Var_VirtTypeCount="$(echo $Var_VirtTypeCount | wc -l)"
            if [ "${Var_VirtTypeCount}" -gt "1" ]; then # 处理嵌套虚拟化
                virtual="echo ${Var_VirtType}"
                Var_VirtType="$(echo ${Var_VirtType} | head -n1)"                        # 使用检测到的第一种虚拟化继续做判断
            elif [ "${Var_VirtTypeCount}" -eq "1" ] && [ "${Var_VirtType}" != "" ]; then # 只有一种虚拟化
                virtual="${Var_VirtType}"
            else
                local Var_BIOSVendor
                Var_BIOSVendor="$(dmidecode -s bios-vendor)"
                if [ "${Var_BIOSVendor}" = "SeaBIOS" ]; then
                    Var_VirtType="Unknown"
                    virtual="Unknown with SeaBIOS BIOS"
                else
                    Var_VirtType="dedicated"
                    virtual="Dedicated with ${Var_BIOSVendor} BIOS"
                fi
            fi
        fi
    }

    # 检查依赖
    if [[ "${release}" == "centos" ]]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime # 修改时区
        if (yum list installed ca-certificates | grep '202'); then
            echo 'CA证书检查OK'
        else
            echo 'CA证书检查不通过，处理中'
            yum install ca-certificates -y
            update-ca-trust force-enable
        fi
        if ! type curl >/dev/null 2>&1; then
            echo 'curl 未安装，安装中...'
            yum install curl -y
        else
            echo 'curl 已安装，继续'
        fi

        if ! type wget >/dev/null 2>&1; then
            echo 'wget 未安装，安装中...'
            yum install wget -y
        else
            echo 'wget 已安装，继续'
        fi

        if ! type dmidecode >/dev/null 2>&1; then
            echo 'dmidecode 未安装，安装中...'
            yum install dmidecode -y
        else
            echo 'dmidecode 已安装，继续'
        fi

        if ! type sudo >/dev/null 2>&1; then
            echo 'sudo 未安装，安装中...'
            yum install sudo -y
        else
            echo 'sudo 已安装，继续'
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        echo "Asia/Shanghai" >/etc/timezone
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime # 修改时区
        if (apt list --installed | grep 'ca-certificates' | grep '202'); then
            echo 'CA证书检查OK'
        else
            echo 'CA证书检查不通过，处理中'
            apt-get update || apt-get --allow-releaseinfo-change update && apt-get install ca-certificates -y
            update-ca-certificates
        fi
        if ! type curl >/dev/null 2>&1; then
            echo 'curl 未安装，安装中...'
            apt-get update || apt-get --allow-releaseinfo-change update && apt-get install curl -y
        else
            echo 'curl 已安装，继续'
        fi

        if ! type wget >/dev/null 2>&1; then
            echo 'wget 未安装，安装中...'
            apt-get update || apt-get --allow-releaseinfo-change update && apt-get install wget -y
        else
            echo 'wget 已安装，继续'
        fi

        if ! type dmidecode >/dev/null 2>&1; then
            echo 'dmidecode 未安装，安装中...'
            apt-get update || apt-get --allow-releaseinfo-change update && apt-get install dmidecode -y
        else
            echo 'dmidecode 已安装，继续'
        fi

        if ! type sudo >/dev/null 2>&1; then
            echo 'sudo 未安装，安装中...'
            apt-get update || apt-get --allow-releaseinfo-change update && apt-get install sudo -y
        else
            echo 'sudo 已安装，继续'
        fi
    fi
}

# 检查Linux版本
check_version() {
    if [[ -s /etc/redhat-release ]]; then
        version=$(grep -oE "[0-9.]+" /etc/redhat-release | cut -d . -f 1)
    else
        version=$(grep -oE "[0-9.]+" /etc/issue | cut -d . -f 1)
    fi
    bit=$(uname -m)
}

# 检查系统当前状态
check_status() {
    kernel_version=$(uname -r | awk -F "-" '{print $1}')
    kernel_version_full=$(uname -r)
    net_congestion_control=$(cat /proc/sys/net/ipv4/tcp_congestion_control | awk '{print $1}')
    net_qdisc=$(cat /proc/sys/net/core/default_qdisc | awk '{print $1}')
}
###########################################
############ End: 系统检测组件 #############
###########################################

###########################################
########### Start: 内核管理组件 ############
###########################################
# 删除多余内核
detele_kernel() {
    if [[ "${release}" == "centos" ]]; then
        rpm_total=$(rpm -qa | grep kernel | grep -v "${kernel_version_full}" | grep -v "noarch" | wc -l)
        if [[ ${rpm_total} -gt 1 ]]; then
            echo "检测到 ${rpm_total} 个其他内核，开始卸载..."
            for ((index = 1; index <= ${rpm_total}; index++)); do
                rpm_del=$(rpm -qa | grep kernel | grep -v "${kernel_version_full}" | grep -v "noarch" | head -${index})
                echo "开始卸载 ${rpm_del} 内核..."
                rpm --nodeps -e "${rpm_del}"
                echo "卸载 ${rpm_del} 内核卸载完成，继续..."
            done
            echo "内核卸载完毕，继续..."
        else
            echo "检测到内核数量不正确，请检查！"
            return 1
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        deb_total=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "${kernel_version_full}" | wc -l)
        if [[ ${deb_total} -gt 1 ]]; then
            echo "检测到 ${deb_total} 个其他内核，开始卸载..."
            for ((index = 1; index <= ${deb_total}; index++)); do
                deb_del=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "${kernel_version_full}" | head -${index})
                echo "开始卸载 ${deb_del} 内核..."
                apt-get purge -y "${deb_del}"
                echo "卸载 ${deb_del} 内核卸载完成，继续..."
            done
            apt-get autoremove -y
            echo "内核卸载完毕，继续..."
        else
            echo "检测到内核数量不正确，请检查！"
            return 1
        fi
    fi
}

delete_kernel_head() {
    if [[ "${release}" == "centos" ]]; then
        rpm_list=($(rpm -qa | grep kernel-headers | grep -v "${kernel_version_full}" | grep -v "noarch"))
        rpm_total=${#rpm_list[@]}
        if ((rpm_total > 1)); then
            echo -e "检测到 ${rpm_total} 个其余head内核，开始卸载..."
            for rpm_del in "${rpm_list[@]}"; do
                echo -e "开始卸载 ${rpm_del} headers内核..."
                rpm --nodeps -e "${rpm_del}"
                echo -e "卸载 ${rpm_del} 内核卸载完成，继续..."
            done
            echo -e "内核卸载完毕，继续..."
        else
            echo -e "检测到内核数量不正确，请检查！" && exit 1
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        deb_list=($(dpkg -l | grep linux-headers | awk '{print $2}' | grep -v "${kernel_version_full}"))
        deb_total=${#deb_list[@]}
        if ((deb_total > 1)); then
            echo -e "检测到 ${deb_total} 个其余head内核，开始卸载..."
            for deb_del in "${deb_list[@]}"; do
                echo -e "开始卸载 ${deb_del} headers内核..."
                apt-get purge -y "${deb_del}"
                echo -e "卸载 ${deb_del} 内核卸载完成，继续..."
            done
            apt-get autoremove -y
            echo -e "内核卸载完毕，继续..."
        else
            echo -e "检测到内核数量不正确，请检查！" && exit 1
        fi
    fi
}

# 更新引导
renew_grub() {
    if [[ "${release}" == "centos" ]]; then
        if [[ ${version} == "7" ]]; then
            if [ -f "/boot/grub2/grub.cfg" ]; then
                grub2-mkconfig -o /boot/grub2/grub.cfg
                grub2-set-default 0
            elif [ -f "/boot/efi/EFI/centos/grub.cfg" ]; then
                grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
                grub2-set-default 0
            elif [ -f "/boot/efi/EFI/redhat/grub.cfg" ]; then
                grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
                grub2-set-default 0
            else
                echo -e "${Error} grub.cfg 找不到，请检查."
                exit
            fi
        elif [[ ${version} == "8" ]]; then
            if [ -f "/boot/grub2/grub.cfg" ]; then
                grub2-mkconfig -o /boot/grub2/grub.cfg
                grub2-set-default 0
            elif [ -f "/boot/efi/EFI/centos/grub.cfg" ]; then
                grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
                grub2-set-default 0
            elif [ -f "/boot/efi/EFI/redhat/grub.cfg" ]; then
                grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
                grub2-set-default 0
            else
                echo -e "${Error} grub.cfg 找不到，请检查."
                exit
            fi
            grubby --info=ALL | awk -F= '$1=="kernel" {print i++ " : " $2}'
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        if _exists "update-grub"; then
            update-grub
        else
            /usr/sbin/update-grub
        fi
    fi
}

# 简单的检查内核
check_kernel() {
    echo -e "${Tip} 鉴于1次人工检查有人不看，下面是2次脚本简易检查内核，开始匹配 /boot/vmlinuz-* 文件"
    ls /boot/vmlinuz-* -I rescue -1 || return 1
    if [ $? -eq 1 ]; then
        echo -e "${Error} 没有匹配到 /boot/vmlinuz-* 文件，很有可能没有内核，谨慎重启！"
        exit
    fi
}
###########################################
##############End: 内核管理组件#############
###########################################

check_sys
check_version
[[ ${release} != "debian" ]] && [[ ${release} != "ubuntu" ]] && [[ ${release} != "centos" ]] && echo -e "${Error} 本脚本不支持当前系统 ${release} !" && exit 1
clean_tempfile
start_menu
