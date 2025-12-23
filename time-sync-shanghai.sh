#!/bin/bash
set -euo pipefail

# 定义颜色输出（增强可读性）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 重置颜色

# 检查是否为 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：必须以 root/管理员权限运行此脚本！${NC}"
        exit 1
    fi
}

# 识别系统发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        echo -e "${YELLOW}警告：无法识别系统发行版，尝试通用模式...${NC}"
        OS="unknown"
    fi
    echo -e "${GREEN}检测到系统：${OS}${NC}"
}

# 安装 ntpdate（适配不同包管理器）
install_ntpdate() {
    echo -e "\n${YELLOW}步骤1：安装 ntpdate 工具${NC}"
    case $OS in
        ubuntu|debian|linuxmint)
            apt update -y && apt install -y ntpdate
            ;;
        centos|rhel|fedora|rocky)
            dnf install -y ntpdate || yum install -y ntpdate
            ;;
        alpine)
            apk add --no-cache ntpdate
            ;;
        opensuse|sles)
            zypper install -y ntpdate
            ;;
        *)
            echo -e "${YELLOW}未识别系统，尝试手动安装 ntpdate...${NC}"
            # 通用 fallback：尝试找包管理器，无则跳过（后续用 timedatectl）
            if command -v apt &>/dev/null; then
                apt update -y && apt install -y ntpdate
            elif command -v dnf &>/dev/null; then
                dnf install -y ntpdate
            elif command -v yum &>/dev/null; then
                yum install -y ntpdate
            elif command -v apk &>/dev/null; then
                apk add --no-cache ntpdate
            else
                echo -e "${YELLOW}无可用包管理器，跳过 ntpdate 安装，使用系统自带工具${NC}"
            fi
            ;;
    esac
}

# 设置时区为上海
set_shanghai_timezone() {
    echo -e "\n${YELLOW}步骤2：设置时区为 Asia/Shanghai${NC}"
    # 兼容不同系统的时区配置方式
    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone Asia/Shanghai
    else
        # 老旧系统 fallback：直接链接时区文件
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    fi
    # 验证时区
    CURRENT_TZ=$(date +%Z)
    if [[ $CURRENT_TZ == "CST" || $CURRENT_TZ == "CST-8" ]]; then
        echo -e "${GREEN}时区设置成功！当前时区：$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone)${NC}"
    else
        echo -e "${YELLOW}时区设置完成，当前时区标识：${CURRENT_TZ}（CST/UTC+8 均为正常）${NC}"
    fi
}

# 同步上海时间（优先 ntpdate，失败则用国内 NTP 服务器兜底）
sync_time() {
    echo -e "\n${YELLOW}步骤3：同步上海时间（国内 NTP 服务器）${NC}"
    # 国内可靠 NTP 服务器列表（优先级从高到低）
    NTP_SERVERS=(
        "ntp.aliyun.com"
        "ntp1.aliyun.com"
        "time.ntsc.ac.cn"  # 中科院授时中心
        "time.tsinghua.edu.cn"
        "time.pku.edu.cn"
    )

    # 尝试 ntpdate 同步
    if command -v ntpdate &>/dev/null; then
        for server in "${NTP_SERVERS[@]}"; do
            echo -e "尝试同步服务器：${server}"
            if ntpdate -u "$server"; then
                echo -e "${GREEN}✅ 成功通过 ${server} 同步时间！${NC}"
                break
            else
                echo -e "${YELLOW}⚠️ ${server} 同步失败，尝试下一个...${NC}"
                continue
            fi
        done
    else
        # 无 ntpdate 时，用 chrony/timedatectl 兜底
        echo -e "${YELLOW}无 ntpdate，尝试用 systemd-timesyncd 同步${NC}"
        if command -v timedatectl &>/dev/null; then
            timedatectl set-ntp true
            sleep 5
            timedatectl show -p NTPSynchronized --value
        elif command -v chronyc &>/dev/null; then
            chronyc -a makestep
        else
            echo -e "${RED}❌ 无可用的时间同步工具，请手动安装 ntpdate/chrony！${NC}"
            exit 1
        fi
    fi

    # 将系统时间写入硬件时钟（防止重启失效）
    echo -e "\n${YELLOW}步骤4：写入硬件时钟${NC}"
    if command -v hwclock &>/dev/null; then
        hwclock --systohc
        echo -e "${GREEN}硬件时钟同步完成！${NC}"
    elif command -v clock &>/dev/null; then
        clock -w
        echo -e "${GREEN}硬件时钟同步完成！${NC}"
    else
        echo -e "${YELLOW}无硬件时钟工具，跳过写入（部分云服务器无需此步骤）${NC}"
    fi
}

# 验证最终结果
verify_result() {
    echo -e "\n${YELLOW}===== 最终验证结果 =====${NC}"
    echo -e "当前系统时间：${GREEN}$(date)${NC}"
    echo -e "时区详情：$(timedatectl 2>/dev/null | grep -E 'Time zone|NTP' || cat /etc/timezone)"
    echo -e "\n${GREEN}✅ 上海时间同步完成！${NC}"
}

# 主流程
main() {
    check_root
    detect_os
    install_ntpdate
    set_shanghai_timezone
    sync_time
    verify_result
}

# 执行主流程
main
