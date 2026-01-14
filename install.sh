#!/bin/bash

# 定义颜色变量
green_text="\033[32m"
yellow="\033[33m"
reset="\033[0m"
red='\033[1;31m'

# 获取本机 IP
local_ip=$(hostname -I | awk '{print $1}')

# 日志输出函数
log() {
    echo -e "[$(date +"%F %T")] $1"
}

# 系统更新和安装必要软件
update_system() {
    # 检查必要软件包是否已安装
    local packages=("supervisor" "inotify-tools" "curl" "git" "wget" "tar" "gawk" "sed" "cron" "unzip" "nano" "nftables")
    local all_installed=true

    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "ii  $pkg "; then
            all_installed=false
            log "未安装软件包: $pkg"
            break
        fi
    done

    if $all_installed; then
        log "所有必要软件包已安装，跳过系统更新和软件包安装"
        return 0
    fi

    # 如果有软件包未安装，则更新系统并安装
    log "开始更新系统..."
    if ! apt update; then
        log "${red}系统更新失败，退出！${reset}"
        exit 1
    fi

    log "安装必要的软件包..."
    if ! apt install -y supervisor inotify-tools curl git wget tar gawk sed cron unzip nano nftables; then
        log "${red}软件包安装失败，退出！${reset}"
        exit 1
    fi
}

# 设置时区（在 LXC/容器环境自动降级）
set_timezone() {
    local TZ_REGION="Asia/Shanghai"
    log "设置时区为${TZ_REGION}"

    # 在容器里一般没有完整的 systemd/DBus，先检测再决定是否回退
    if command -v timedatectl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
        # dbus 非必须，但如果在就尝试
        if systemctl is-active dbus >/dev/null 2>&1 || systemctl start dbus >/dev/null 2>&1; then
            if timeout 15s timedatectl set-timezone "${TZ_REGION}"; then
                log "时区设置成功（timedatectl）"
                return 0
            else
                log "${yellow}timedatectl 设置失败，回退到文件链接方式${reset}"
            fi
        else
            log "${yellow}DBus 未运行或无法启动，回退到文件链接方式${reset}"
        fi
    else
        log "${yellow}未检测到可用的 systemd/timedatectl 环境，使用文件链接方式${reset}"
    fi

    # 回退：直接链接 /etc/localtime + /etc/timezone
    if [ -f "/usr/share/zoneinfo/${TZ_REGION}" ]; then
        ln -sf "/usr/share/zoneinfo/${TZ_REGION}" /etc/localtime
        echo "${TZ_REGION}" > /etc/timezone 2>/dev/null || true
        log "时区设置成功（/etc/localtime 链接方式，适配 LXC）"
        return 0
    else
        log "${red}找不到时区文件 /usr/share/zoneinfo/${TZ_REGION}${reset}"
        # 在 LXC 中不要阻断安装流程
        return 0
    fi
}


# 打印横线
print_separator() {
    echo -e "${green_text}───────────────────────────────────────────────────${reset}"
}

# 打印程序安装状态
check_programs() {
    local programs=("sing-box" "mosdns" "mihomo" "filebrowser")
    echo -e "\n${yellow}检测本机安装情况 (本地IP: ${local_ip})...${reset}"
    print_separator
    printf "${green_text}%-15s %-10s\n${reset}" "程序" "状态"
    print_separator

    for program in "${programs[@]}"; do
        if [ -x "/usr/local/bin/$program" ]; then
            printf "${green_text}%-15s ✔ %-8s${reset}\n" "$program" "已安装"
        else
            printf "${red}%-15s ✘ %-8s${reset}\n" "$program" "未安装"
        fi
    done
    print_separator
}

# 检查 Supervisor 管理的服务状态
check_supervisor_services() {
    echo -e "\n${yellow}检查服务状态...${reset}"
    print_separator
    # Supervisor 状态缓存，避免多次调用
    SUPERVISOR_STATUS=$(command -v supervisorctl &>/dev/null && supervisorctl status || echo "not_found")


    if [[ "$SUPERVISOR_STATUS" == "not_found" ]]; then
        echo -e "${red}警告：未检测到 Supervisor，无法检查服务状态。${reset}"
        echo -e "${yellow}请安装并配置 Supervisor。${reset}"
        print_separator
        echo -e "${yellow}当前代理模式检测：未检测到 MosDNS 或核心代理服务${reset}"
        print_separator
        return
    fi

    printf "${green_text}%-20s %-15s %-15s\n${reset}" "服务名称" "类型" "状态"
    print_separator

    local core_programs=("sing-box" "mihomo" "mosdns")
    local watch_services=("watch_sing_box" "watch_mihomo" "watch_mosdns")

    for program in "${core_programs[@]}"; do
        local type="未知"
        [[ "$program" == "mosdns" ]] && type="DNS服务"
        [[ "$program" == "sing-box" || "$program" == "mihomo" ]] && type="路由服务"

        if echo "$SUPERVISOR_STATUS" | grep -qE "^${program}\s+RUNNING"; then
            printf "${green_text}%-20s %-15s %-15s${reset}\n" "$program" "$type" "运行中 ✅"
        else
            printf "${red}%-20s %-15s %-15s${reset}\n" "$program" "$type" "未运行 ❌"
        fi
    done

    for watch in "${watch_services[@]}"; do
        if echo "$SUPERVISOR_STATUS" | grep -qE "^${watch}\s+RUNNING"; then
            printf "${green_text}%-20s %-15s %-15s${reset}\n" "$watch" "监听服务" "运行中 ✅"
        else
            printf "${red}%-20s %-15s %-15s${reset}\n" "$watch" "监听服务" "未运行 ❌"
        fi
    done
}

# 检查 systemd 服务状态
check_systemd_services() {
    echo -e "\n${yellow}检查系统转发服务状态...${reset}"
    print_separator
    printf "${green_text}%-20s %-15s %-15s\n${reset}" "服务名称" "类型" "状态"
    print_separator

    local services=("nftables" "sing-box-router" "mihomo-router")

    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            printf "${green_text}%-20s %-15s %-15s${reset}\n" "$service" "系统服务" "运行中 ✅"
        else
            printf "${red}%-20s %-15s %-15s${reset}\n" "$service" "系统服务" "未运行 ❌"
        fi
    done
    print_separator
}

# 检测当前代理模式
detect_proxy_mode() {
    echo -e "\n${yellow}当前代理模式检测：${reset}"
    # Supervisor 状态缓存，避免多次调用
    SUPERVISOR_STATUS=$(command -v supervisorctl &>/dev/null && supervisorctl status || echo "not_found")

    local mosdns_running=false
    local singbox_active=false
    local mihomo_active=false

    if echo "$SUPERVISOR_STATUS" | grep -qE "^mosdns\s+RUNNING"; then
        mosdns_running=true
    fi

    if echo "$SUPERVISOR_STATUS" | grep -qE "^sing-box\s+RUNNING" && \
       echo "$SUPERVISOR_STATUS" | grep -qE "^watch_sing_box\s+RUNNING" && \
       systemctl is-active sing-box-router &>/dev/null; then
        singbox_active=true
    fi

    if echo "$SUPERVISOR_STATUS" | grep -qE "^mihomo\s+RUNNING" && \
       echo "$SUPERVISOR_STATUS" | grep -qE "^watch_mihomo\s+RUNNING" && \
       systemctl is-active mihomo-router &>/dev/null; then
        mihomo_active=true
    fi

    if $mosdns_running; then
        if $singbox_active; then
            echo -e "${green_text}✓ 当前模式：MosDNS + Sing-box${reset}"
        elif $mihomo_active; then
            echo -e "${green_text}✓ 当前模式：MosDNS + Mihomo${reset}"
        else
            echo -e "${yellow}ℹ️ MosDNS 正在运行，但未检测到完整的路由组件${reset}"
        fi
    else
        if $singbox_active || $mihomo_active; then
            echo -e "${red}✗ MosDNS 未运行，代理服务可能异常${reset}"
        else
            echo -e "${yellow}ℹ️ 未检测到 MosDNS 或任何核心代理服务正在运行${reset}"
        fi
    fi
    print_separator
}

# 主函数
display_system_status() {
#    check_programs
    check_supervisor_services
    check_systemd_services
    detect_proxy_mode
}

# 检测系统 CPU 架构，并返回标准格式（适用于多数构建/下载脚本）
detect_architecture() {
    case "$(uname -m)" in
        x86_64)     echo "amd64" ;;    # 64 位 x86 架构
        aarch64)    echo "arm64" ;;    # 64 位 ARM 架构
        armv7l)     echo "armv7" ;;    # 32 位 ARM 架构（常见于树莓派）
        armhf)      echo "armhf" ;;    # ARM 硬浮点
        s390x)      echo "s390x" ;;    # IBM 架构
        i386|i686)  echo "386" ;;      # 32 位 x86 架构
        *)
            echo -e "${yellow}不支持的CPU架构: $(uname -m)${reset}"
            exit 1
            ;;
    esac
}

# 检测是否在容器/非完整 systemd 环境
is_container_env() {
    # 1) 明确容器标识
    if grep -qE '(lxc|container)' /proc/1/environ 2>/dev/null; then
        return 0
    fi
    if grep -qE '(?:^|/)docker(?:/|$)|(?:^|/)lxc(?:/|$)' /proc/1/cgroup 2>/dev/null; then
        return 0
    fi
    # 2) 没有完整的 systemd
    if ! pidof systemd >/dev/null 2>&1; then
        return 0
    fi
    # 3) systemd 运行但不可用管理（某些 LXC）
    if ! systemctl is-system-running >/dev/null 2>&1; then
        return 0
    fi
    return 1
}


# 检查 AMD64 架构是否支持 v3 指令集 (x86-64-v3)
check_amd64_v3_support() {
    local arch
    arch=$(detect_architecture)

    # 只有 AMD64 架构才需要检查 v3 支持
    if [ "$arch" != "amd64" ]; then
        return 1
    fi

    # v3 要求的指令集
    local required_flags=("sse4_2" "avx" "avx2" "bmi1" "bmi2" "fma" "abm")

    # 获取 CPU flags
    local cpu_flags
    cpu_flags=$(grep -m1 -o -E 'sse4_2|avx2|avx|bmi1|bmi2|fma|abm' /proc/cpuinfo | sort -u)

    # 检查每一个必须的指令集
    for flag in "${required_flags[@]}"; do
        if ! grep -qw "$flag" <<< "$cpu_flags"; then
            log "${red}AMD64 架构缺少指令集: $flag → 不支持 v3${reset}"
            return 1
        fi
    done

    log "${green_text}检测到 AMD64 架构支持完整 v3 指令集${reset}"
    return 0
}

# 检查CPU指令集和v3支持的详细函数
check_cpu_instructions() {
    echo -e "\n${green_text}=== CPU指令集和v3支持检查 ===${reset}"
    
    # 显示系统基本信息
    echo -e "\n${yellow}系统信息：${reset}"
    echo -e "操作系统: $(uname -s)"
    echo -e "内核版本: $(uname -r)"
    echo -e "CPU架构: $(uname -m)"
    echo -e "检测到的架构: $(detect_architecture)"
    
    # 检查是否为Linux系统
    if [ ! -f "/proc/cpuinfo" ]; then
        echo -e "\n${red}错误：此功能仅支持Linux系统${reset}"
        echo -e "${yellow}当前系统无法读取 /proc/cpuinfo 文件${reset}"
        return 1
    fi
    
    # 显示CPU基本信息
    echo -e "\n${yellow}CPU信息：${reset}"
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')
    local cpu_cores=$(grep -c "processor" /proc/cpuinfo)
    local cpu_family=$(grep "cpu family" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')
    local cpu_model_num=$(grep "model" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')
    
    echo -e "CPU型号: ${green_text}$cpu_model${reset}"
    echo -e "CPU核心数: ${green_text}$cpu_cores${reset}"
    echo -e "CPU系列: ${green_text}$cpu_family${reset}"
    echo -e "CPU型号编号: ${green_text}$cpu_model_num${reset}"
    
    # 检查指令集支持
    echo -e "\n${yellow}指令集支持检查：${reset}"
    
    # 基础指令集
    local basic_instructions=("sse" "sse2" "sse3" "ssse3" "sse4_1" "sse4_2" "avx" "avx2" "avx512f")
    local advanced_instructions=("bmi1" "bmi2" "fma" "abm" "popcnt" "aes" "pclmulqdq")
    
    echo -e "\n${green_text}基础指令集：${reset}"
    for instruction in "${basic_instructions[@]}"; do
        if grep -q "$instruction" /proc/cpuinfo; then
            echo -e "  ✓ $instruction: ${green_text}支持${reset}"
        else
            echo -e "  ✗ $instruction: ${red}不支持${reset}"
        fi
    done
    
    echo -e "\n${green_text}高级指令集：${reset}"
    for instruction in "${advanced_instructions[@]}"; do
        if grep -q "$instruction" /proc/cpuinfo; then
            echo -e "  ✓ $instruction: ${green_text}支持${reset}"
        else
            echo -e "  ✗ $instruction: ${red}不支持${reset}"
        fi
    done
    
    # 检查v3支持
    echo -e "\n${yellow}AMD64 v3支持检查：${reset}"
    if check_amd64_v3_support; then
        echo -e "${green_text}✓ 系统完全支持 AMD64 v3 指令集${reset}"
        echo -e "${green_text}  可以使用v3优化的二进制文件以获得更好性能${reset}"
    else
        echo -e "${red}✗ 系统不支持完整的 AMD64 v3 指令集${reset}"
        echo -e "${yellow}  将使用标准版本的二进制文件${reset}"
    fi
    
    # 显示当前配置
    echo -e "\n${yellow}当前配置：${reset}"
    if [ -f "/mssb/mssb.env" ]; then
        if grep -q "^amd64v3_enabled=" /mssb/mssb.env; then
            local current_setting=$(grep "^amd64v3_enabled=" /mssb/mssb.env | cut -d= -f2)
            echo -e "AMD64 v3优化设置: ${green_text}$current_setting${reset}"
        else
            echo -e "AMD64 v3优化设置: ${yellow}未配置${reset}"
        fi
    else
        echo -e "AMD64 v3优化设置: ${yellow}配置文件不存在${reset}"
    fi
    
    # 显示所有CPU flags
    echo -e "\n${yellow}所有CPU特性标志：${reset}"
    local all_flags=$(grep "flags" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')
    echo -e "${green_text}$all_flags${reset}"
    
    echo -e "\n${green_text}检查完成！${reset}"
}

# 安装mosdns
install_mosdns() {
    # 检查是否已安装 MosDNS
    if [ -f "/usr/local/bin/mosdns" ]; then
        log "检测到已安装的 MosDNS"

        # 获取当前版本信息
        current_version=$(/usr/local/bin/mosdns version 2>/dev/null | head -n1 | awk '{print $2}' || echo "未知版本")
        log "当前安装的版本：$current_version"
        if [ "$install_update_mode_mosdns" = "n" ]; then
            log "跳过 MosDNS 下载，使用现有版本：$current_version"
            return 0
        else
            log "选择更新 MosDNS 到最新版本"
        fi
    fi

    # 下载并安装 MosDNS
    log "开始下载 MosDNS..."
    arch=$(detect_architecture)
    log "系统架构是：$arch"
    #  LATEST_MOSDNS_VERSION=$(curl -sL -o /dev/null -w %{url_effective} https://github.com/IrineSistiana/mosdns/releases/latest | awk -F '/' '{print $NF}')
    #  MOSDNS_URL="https://github.com/IrineSistiana/mosdns/releases/download/${LATEST_MOSDNS_VERSION}/mosdns-linux-$arch.zip"
    # https://github.com/baozaodetudou/mssb/releases/download/mosdns/mosdns-linux-amd64.zip
    # https://github.com/baozaodetudou/mssb/releases/download/mosdns/mosdns-linux-amd64-v3.zip
    if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
        MOSDNS_URL="https://github.com/baozaodetudou/mssb/releases/download/mosdns/mosdns-linux-amd64-v3.zip"
    else
        MOSDNS_URL="https://github.com/baozaodetudou/mssb/releases/download/mosdns/mosdns-linux-$arch.zip"
    fi

    log "从 $MOSDNS_URL 下载 MosDNS..."
    if curl -L -o /tmp/mosdns.zip "$MOSDNS_URL"; then
        log "MosDNS 下载成功。"
    else
        log "MosDNS 下载失败，请检查网络连接或 URL 是否正确。"
        exit 1
    fi

    log "解压 MosDNS..."
    if unzip -o /tmp/mosdns.zip -d /usr/local/bin; then
        log "MosDNS 解压成功。"
    else
        log "MosDNS 解压失败，请检查压缩包是否正确。"
        exit 1
    fi

    log "设置 MosDNS 可执行权限..."
    if chmod +x /usr/local/bin/mosdns; then
        log "设置权限成功。"

        # 显示安装完成的版本信息
        new_version=$(/usr/local/bin/mosdns version 2>/dev/null | head -n1 | awk '{print $2}' || echo "未知版本")
        log "MosDNS 安装完成，版本：$new_version"
    else
        log "设置权限失败，请检查文件路径和权限设置。"
        exit 1
    fi

    # 清理临时文件
    rm -f /tmp/mosdns.zip
}

# 安装filebrower
install_filebrower() {
    # 检查是否已安装 Filebrowser
    if [ -f "/usr/local/bin/filebrowser" ]; then
        log "检测到已安装的 Filebrowser"

        # 获取当前版本信息
        current_version=$(/usr/local/bin/filebrowser version 2>/dev/null | head -n1 | awk '{print $3}' || echo "未知版本")
        log "当前安装的版本：$current_version"
        if [ "$install_update_mode_filebrowser" = "n" ]; then
            log "跳过 Filebrowser 下载，使用现有版本：$current_version"
            return 0
        else
            log "选择更新 Filebrowser 到最新版本"
        fi
    fi

    # 下载并安装 Filebrowser
    log "开始下载 Filebrowser..."
    arch=$(detect_architecture)
    log "系统架构是：$arch"
    LATEST_FILEBROWSER_VERSION=$(curl -sL -o /dev/null -w %{url_effective} https://github.com/filebrowser/filebrowser/releases/latest | awk -F '/' '{print $NF}')
    FILEBROWSER_URL="https://github.com/filebrowser/filebrowser/releases/download/${LATEST_FILEBROWSER_VERSION}/linux-$arch-filebrowser.tar.gz"

    log "从 $FILEBROWSER_URL 下载 Filebrowser..."
    if curl -L --fail -o /tmp/filebrowser.tar.gz "$FILEBROWSER_URL"; then
        log "Filebrowser 下载成功。"
    else
        log "Filebrowser 下载失败，请检查网络连接或 URL 是否正确。"
        exit 1
    fi

    log "解压 Filebrowser..."
    if tar -zxvf /tmp/filebrowser.tar.gz -C /usr/local/bin; then
        log "Filebrowser 解压成功。"
    else
        log "Filebrowser 解压失败，请检查压缩包是否正确。"
        exit 1
    fi

    log "设置 Filebrowser 可执行权限..."
    if chmod +x /usr/local/bin/filebrowser; then
        log "Filebrowser 设置权限成功。"

        # 显示安装完成的版本信息
        new_version=$(/usr/local/bin/filebrowser version 2>/dev/null | head -n1 | awk '{print $3}' || echo "未知版本")
        log "Filebrowser 安装完成，版本：$new_version"
    else
        log "Filebrowser 设置权限失败，请检查文件路径和权限设置。"
        exit 1
    fi

    # 清理临时文件
    rm -f /tmp/filebrowser.tar.gz
}

# 安装mihomo
install_mihomo() {
    # 检查是否已安装 Mihomo
    if [ -f "/usr/local/bin/mihomo" ]; then
        log "检测到已安装的 Mihomo"

        # 获取当前版本信息
        current_version=$(/usr/local/bin/mihomo -v 2>/dev/null | head -n1 | awk '{print $2}' || echo "未知版本")
        log "当前安装的版本：$current_version"
        if [ "$install_update_mode_mihomo" = "n" ]; then
            log "跳过 Mihomo 下载，使用现有版本：$current_version"
            return 0
        else
            log "选择更新 Mihomo 到最新版本"
        fi
    fi

    # 下载并安装 Mihomo
    arch=$(detect_architecture)
    # https://github.com/baozaodetudou/mssb/releases/download/mihomo/mihomo-meta-linux-amd64.tar.gz
    # https://github.com/baozaodetudou/mssb/releases/download/mihomo/mihomo-alpha-linux-amd64v3.tar.gz
    if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
        download_url="https://github.com/baozaodetudou/mssb/releases/download/mihomo/mihomo-meta-linux-amd64v3.tar.gz"
    else
        download_url="https://github.com/baozaodetudou/mssb/releases/download/mihomo/mihomo-meta-linux-${arch}.tar.gz"
    fi
    log "开始下载 Mihomo 核心..."

    if ! wget -O /tmp/mihomo.tar.gz "$download_url"; then
        log "Mihomo 下载失败，请检查网络连接"
        exit 1
    fi

    log "Mihomo 下载完成，开始安装"
    tar -zxvf /tmp/mihomo.tar.gz -C /usr/local/bin > /dev/null 2>&1 || {
        log "解压 Mihomo 失败，请检查压缩包完整性"
        exit 1
    }

    chmod +x /usr/local/bin/mihomo || log "警告：未能设置 Mihomo 执行权限"
    rm -f /tmp/mihomo.tar.gz

    # 显示安装完成的版本信息
    new_version=$(/usr/local/bin/mihomo -v 2>/dev/null | head -n1 | awk '{print $2}' || echo "未知版本")
    log "Mihomo 安装完成，版本：$new_version，临时文件已清理"
}

# 检测ui是否存在
check_ui() {
    if [ -z "$core_name" ]; then
        echo -e "${red}未检测到核心程序名（core_name），请先设置 core_name${reset}"
        return 1
    fi

    ui_path="/mssb/${core_name}/ui"

    if [ -d "$ui_path" ]; then
        # 选择是否更新
        if [ "$update_ui_mode" = "y" ]; then
            echo "正在更新 UI..."
            git_ui
        else
            echo "已取消 UI 更新。"
        fi
    else
        echo "未检测到 UI，首次安装 WEBUI..."
        git_ui
    fi
}

# 下载UI源码
git_ui(){
    local ui_path="/mssb/${core_name}/ui"
    local temp_ui_path="/tmp/zashboard-ui-$$"

    echo "正在下载 UI 源码到临时目录..."

    # 先下载到临时目录
    if git clone --depth=1 https://github.com/Zephyruso/zashboard.git -b gh-pages "$temp_ui_path"; then
        echo -e "UI 源码下载${green_text}成功${reset}，正在替换..."

        # 直接覆盖复制新UI到目标位置(如果目录存在则覆盖)
        if [ -d "$ui_path" ]; then
            echo "覆盖现有 UI..."
            # 使用 cp -rf 强制覆盖
            if cp -rf "$temp_ui_path/." "$ui_path/"; then
                echo -e "UI 更新${green_text}成功${reset}。"
                # 清理临时文件
                rm -rf "$temp_ui_path" 2>/dev/null
                echo "临时文件已清理"
            else
                echo -e "${red}UI 复制失败${reset}"
                echo "请检查磁盘空间和权限"
                # 复制失败也清理临时文件
                rm -rf "$temp_ui_path" 2>/dev/null
                return 1
            fi
        else
            # 目录不存在,直接复制整个目录
            if cp -r "$temp_ui_path" "$ui_path"; then
                echo -e "UI 安装${green_text}成功${reset}。"
                # 清理临时文件
                rm -rf "$temp_ui_path" 2>/dev/null
                echo "临时文件已清理"
            else
                echo -e "${red}UI 复制失败${reset}"
                echo "请检查磁盘空间和权限"
                # 复制失败也清理临时文件
                rm -rf "$temp_ui_path" 2>/dev/null
                return 1
            fi
        fi
    else
        echo -e "${red}UI 源码下载失败${reset}，保持现有 UI 不变"
        echo "请检查网络连接或手动下载源码并解压至 $ui_path"
        echo "下载地址: https://github.com/Zephyruso/zashboard.git"

        # 清理可能存在的临时文件
        rm -rf "$temp_ui_path" 2>/dev/null
    fi
}

# 检查dns 53是否被占用
check_resolved(){
    if [ -f /etc/systemd/resolved.conf ]; then
        # 检测是否有未注释的 DNSStubListener 行
        dns_stub_listener=$(grep "^DNSStubListener=" /etc/systemd/resolved.conf)
        if [ -z "$dns_stub_listener" ]; then
            # 如果没有找到未注释的 DNSStubListener 行，检查是否有被注释的 DNSStubListener
            commented_dns_stub_listener=$(grep "^#DNSStubListener=" /etc/systemd/resolved.conf)
            if [ -n "$commented_dns_stub_listener" ]; then
                # 如果找到被注释的 DNSStubListener，取消注释并改为 no
                sed -i 's/^#DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
                systemctl restart systemd-resolved.service
                echo -e "${green_text}53端口占用已解除${reset}"
            else
                echo -e "${yellow}未找到53端口占用配置，无需操作${reset}"
            fi
        elif [ "$dns_stub_listener" = "DNSStubListener=yes" ]; then
            # 如果找到 DNSStubListener=yes，则修改为 no
            sed -i 's/^DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
            systemctl restart systemd-resolved.service
            echo -e "${green_text}53端口占用已解除${reset}"
        elif [ "$dns_stub_listener" = "DNSStubListener=no" ]; then
            # 如果 DNSStubListener 已为 no，提示用户无需修改
            echo -e "${yellow}53端口未被占用，无需操作${reset}"
        fi
    else
        echo -e "${yellow} /etc/systemd/resolved.conf 不存在，无需操作${reset}"
    fi
}

# tproxy转发服务安装
install_tproxy() {
    check_resolved
    sleep 1
    echo -e "${yellow}配置tproxy${reset}"
    sleep 1
    echo -e "${yellow}创建系统转发${reset}"
    # 判断是否已存在 net.ipv4.ip_forward=1
    if ! grep -q '^net.ipv4.ip_forward=1$' /etc/sysctl.conf; then
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    fi

    # 判断是否已存在 net.ipv6.conf.all.forwarding = 1
#    if ! grep -q '^net.ipv6.conf.all.forwarding = 1$' /etc/sysctl.conf; then
#        echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
#    fi
    sleep 1
    echo -e "${green_text}系统转发创建完成${reset}"
    sleep 1
    echo -e "${yellow}开始创建nftables tproxy转发${reset}"
    apt install nftables -y
    # 写入tproxy rule
    # 判断文件是否存在"$core_name" = "sing-box"
    if [ ! -f "/etc/systemd/system/${core_name}-router.service" ]; then
    cat <<EOF > "/etc/systemd/system/${core_name}-router.service"
[Unit]
Description=${core_name} TProxy Rules
After=network.target
Wants=network.target

[Service]
User=root
Type=oneshot
RemainAfterExit=yes
# there must be spaces before and after semicolons
ExecStart=/sbin/ip rule add fwmark 1 table 100 ; /sbin/ip route add local default dev lo table 100 ; /sbin/ip -6 rule add fwmark 1 table 101 ; /sbin/ip -6 route add local ::/0 dev lo table 101
ExecStop=/sbin/ip rule del fwmark 1 table 100 ; /sbin/ip route del local default dev lo table 100 ; /sbin/ip -6 rule del fwmark 1 table 101 ; /sbin/ip -6 route del local ::/0 dev lo table 101

[Install]
WantedBy=multi-user.target
EOF
    echo "${core_name}-router 服务创建完成"
    else
    echo "警告：${core_name}-router 服务文件已存在，无需创建"
    fi
    ################################写入nftables################################
    # 获取脚本所在目录的绝对路径
    cd "$(dirname "$0")"
    local nft_template="./nft/nft-tproxy-redirect.conf"

    # 检查模板文件是否存在
    if [ ! -f "$nft_template" ]; then
        log "错误：nftables 模板文件 $nft_template 不存在！"
        return 1
    fi
    rm /etc/nftables.conf
    # 复制并替换模板中的网卡名
    if cp "$nft_template" "/etc/nftables.conf"; then
        log "成功复制 nftables 模板文件"
        # 替换模板中的网卡名
        if sed -i "s/eth0/${selected_interface}/g" "/etc/nftables.conf"; then
            log "成功替换网卡名为: $selected_interface"
        else
            log "警告：替换网卡名失败，请手动检查 /etc/nftables.conf"
        fi
        # 判断 /etc/nftables.conf 文件中是否包含 $dns，如果没有则将默认的 221.130.33.60 替换为 $dns
        # 设置默认 DNS 地址为 119.29.29.29，如果未指定 dns_addr
        local dns="${dns_addr:-119.29.29.29}"

        # 如果 /etc/nftables.conf 中已包含该 DNS 地址，跳过替换
        if grep -q "$dns" "/etc/nftables.conf"; then
            log "nftables 配置文件中已存在 DNS 地址 $dns，无需替换"
        else
            # 校验是否是合法的 IPv4 格式
            if [[ $dns =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                # 尝试将旧的 DNS 地址替换为新的
                if sed -i "s/221\.130\.33\.60/${dns}/g" "/etc/nftables.conf"; then
                    log "已将默认 DNS 地址 221.130.33.60 替换为: $dns"
                else
                    log "⚠️ 警告：替换 nftables 配置文件中的 DNS 地址失败，请手动检查 /etc/nftables.conf"
                fi
            else
                log "❌ 错误：无效的 DNS 地址格式: $dns"
            fi
        fi

    else
        log "错误：复制 nftables 模板文件失败！"
        return 1
    fi

    echo -e "${green_text}nftables规则写入完成${reset}"
    sleep 1

    # 检查 nft 命令路径
    local nft_cmd=""
    if command -v nft &>/dev/null; then
        nft_cmd="nft"
    elif [ -x "/usr/sbin/nft" ]; then
        nft_cmd="/usr/sbin/nft"
    else
        log "错误：找不到 nft 命令！"
        return 1
    fi
    log "使用 nft 命令：$nft_cmd"

    # 验证配置文件语法
    # 验证并加载 nftables 规则
    if $nft_cmd -c -f /etc/nftables.conf; then
        log "nftables 配置文件语法检查通过"

        log "清空 nftables 规则"
        $nft_cmd flush ruleset || log "警告：清空 nftables 规则失败，继续执行"
        sleep 1

        log "加载新规则"
        if $nft_cmd -f /etc/nftables.conf; then
            log "成功加载新的 nftables 规则"
        else
            log "错误：加载 nftables 规则失败！"
            return 1
        fi
        sleep 1

        # 在容器内不启用 nftables.service
        if is_container_env; then
            log "检测到 LXC/容器环境：跳过启用 nftables.service，仅保持已加载规则"
        else
            if systemctl enable --now nftables; then
                log "成功启用 nftables 服务"
            else
                log "警告：启用 nftables 服务失败（可能是受限环境），但规则已加载"
            fi
        fi
	    else
	        log "错误：nftables 配置文件语法检查失败！"
	        return 1
	    fi
	    if [ "$core_name" = "sing-box" ]; then
	      # 启用 sing-box-router，禁用 mihomo-router
	      systemctl disable --now mihomo-router &>/dev/null
	      rm -f /etc/systemd/system/mihomo-router.service
      systemctl enable --now sing-box-router || { log "启用相关服务 失败！"; }
    elif [ "$core_name" = "mihomo" ]; then
      # 启用 mihomo-router，禁用 sing-box-router
      systemctl disable --now sing-box-router &>/dev/null
      rm -f /etc/systemd/system/sing-box-router.service
      systemctl enable --now mihomo-router || { log "启用相关服务 失败！"; }
    else
      log "未识别的 core_name: $core_name，跳过 启用相关服务。"
    fi
}

# 网卡检测或者手动输入
check_interfaces() {
    echo -e "\n${green_text}=== 网卡选择 ===${reset}"
    ip_map=()
    ip_interfaces=()
    # 只查找UP且有IPv4的en/eth开头的物理网卡
    while read -r iface; do
        if [[ $iface =~ ^(en|eth).* ]]; then
            # 判断是否UP
            state=$(ip -o link show "$iface" | grep -o 'state [A-Z]*' | awk '{print $2}')
            if [[ $state == "UP" ]]; then
                # 查找IPv4
                ip_addr=$(ip addr show "$iface" | awk '/inet /{print $2}' | cut -d/ -f1)
                if [ -n "$ip_addr" ]; then
                    ip_map+=("$iface:$ip_addr")
                    ip_interfaces+=("$iface")
                fi
            fi
        fi
    done < <(ip -o link show | awk -F': ' '{print $2}')

    count=${#ip_interfaces[@]}
    if [ "$count" -eq 0 ]; then
        echo -e "${red}未检测到UP且有IP的物理网卡，请手动输入网卡名称。${reset}"
        read -p "请自行输入您的网卡名称: " selected_interface
        log "您输入的网卡名称是: $selected_interface"
    elif [ "$count" -eq 1 ]; then
        iface="${ip_interfaces[0]}"
        ip_addr=$(echo "${ip_map[0]}" | cut -d: -f2)
        echo "检测到唯一UP且有IP的物理网卡: $iface, IP: $ip_addr"
        read -p "是否使用该网卡？(y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            selected_interface="$iface"
            log "您选择的网卡是: $selected_interface"
        else
            read -p "请自行输入您的网卡名称: " selected_interface
            log "您输入的网卡名称是: $selected_interface"
        fi
    else
        echo -e "${yellow}检测到多个UP且有IP的物理网卡，无法自动判断，请手动输入。${reset}"
        for item in "${ip_map[@]}"; do
            iface="${item%%:*}"
            ip="${item#*:}"
            echo "网卡: $iface, IP: $ip"
        done
        read -p "请自行输入您的网卡名称: " selected_interface
        log "您输入的网卡名称是: $selected_interface"
    fi
}

# 函数：检查并复制文件夹
check_and_copy_folder() {
    local folder_name=$1
    if [ -d "/mssb/$folder_name" ]; then
        log "/mssb/$folder_name 文件夹已存在，跳过替换。"
    else
        cp -r "mssb/$folder_name" "/mssb/" || { log "复制 mssb/$folder_name 目录失败！退出脚本。"; exit 1; }
        log "成功复制 mssb/$folder_name 目录到 /mssb/"
    fi
}

# mosdns配置文件复制
mosdns_configure_files() {
    echo -e "\n${green_text}=== MosDNS 配置设置 ===${reset}"
    forward_local_yaml="/mssb/mosdns/sub_config/forward_local.yaml"
    echo -e "\n${yellow}=== 运营商 DNS 配置 ===${reset}"
    # 直接用 env 变量
    local dns="${dns_addr:-119.29.29.29}"
    # 校验格式
    if [[ $dns =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        sed -i "s/addr: \"114.114.114.114\"/addr: \"$dns\"/" "$forward_local_yaml"
        log "已更新运营商 DNS 地址为：$dns"
    else
        log "env 里的 DNS 地址格式不正确，将使用默认值 114.114.114.114"
        #sed -i "s/addr: \"114.114.114.114\"/addr: \"119.29.29.29\"/" "$forward_local_yaml"
    fi

    # 恢复 rule 目录
    if [ -d "/mssb/mosdns.bak/rule" ]; then
        mkdir -p /mssb/mosdns/rule
        cp -r /mssb/mosdns.bak/rule/* /mssb/mosdns/rule/ 2>/dev/null
        log "已恢复规则 /mssb/mosdns/rule 目录（如有同名文件已覆盖）"
    else
        log "/mssb/mosdns.bak/rule 目录不存在，无需恢复规则目录"
    fi

    # 恢复 client_ip.txt
    if [ -f "/mssb/mosdns.bak/client_ip.txt" ]; then
        cp /mssb/mosdns.bak/client_ip.txt /mssb/mosdns/
        log "已恢复规则 /mssb/mosdns/client_ip.txt 文件"
    else
        if [ -n "$client_ip_list" ]; then
            mkdir -p /mssb/mosdns
            echo "$client_ip_list" | tr ' ' '\n' > /mssb/mosdns/client_ip.txt
            log "已根据设置变量写入代理设备列表: $client_ip_list"
        else
            log "未设置代理设备列表，未写入 /mssb/mosdns/client_ip.txt 文件"
        fi
    fi
    if [ -d "/mssb/mosdns.bak" ]; then
      rm -rf /mssb/mosdns.bak
    fi
}

copy_fb_folder() {
    log "复制 mssb/fb 目录..."
    check_and_copy_folder "fb"
}

copy_mosdns_folder() {
    if [ -d "/mssb/mosdns" ]; then
        log "/mssb/mosdns 文件夹已存在，先备份再替换替换成功删除备份。"
        mv /mssb/mosdns /mssb/mosdns.bak
        if cp -r "mssb/mosdns" "/mssb/" 2>/dev/null; then
            log "成功复制 mssb/mosdns 目录到 /mssb/"
        else
            log "警告：复制 mssb/mosdns 目录失败，恢复备份"
            mv /mssb/mosdns.bak /mssb/mosdns
        fi
        log "已更新 /mssb/mosdns 目录（原目录暂时备份/mssb/mosdns.bak）"
    else
        if cp -r "mssb/mosdns" "/mssb/" 2>/dev/null; then
            log "成功复制 mssb/mosdns 目录到 /mssb/"
        else
            log "警告：复制 mssb/mosdns 目录失败，将尝试继续执行"
        fi
    fi
    #chmod -R 777 /mssb/mosdns/webinfo
}

init_filebrowser_db() {
    if [ ! -f "/mssb/fb/fb.db" ]; then
        log "Filebrowser 数据库不存在，创建默认数据库..."
        filebrowser -c /mssb/fb/fb.json -d /mssb/fb/fb.db &
        FB_PID=$!
        sleep 1
        kill $FB_PID 2>/dev/null
        wait $FB_PID 2>/dev/null
    fi
}

choose_filebrowser_login() {
    echo -e "\n${green_text}=== Filebrowser 配置设置 ===${reset}"
    # 直接用环境变量 fb_login_mode
    if [ "$fb_login_mode" = "noauth" ]; then
        log "正在配置 Filebrowser 为无密码登录模式..."
        filebrowser config set --auth.method=noauth -c /mssb/fb/fb.json -d /mssb/fb/fb.db
        log "Filebrowser 已配置为无密码登录模式"
    else
        filebrowser config set --auth.method=json -c /mssb/fb/fb.json -d /mssb/fb/fb.db
        if [ -n "$fb_pass" ]; then
            log "使用自定义的密码登录模式...密码$fb_pass"
            filebrowser users update admin --password "$fb_pass" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
        else
            log "使用默认的密码登录模式...密码admin123456789QAQ"
            filebrowser users update admin --password "admin123456789QAQ" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
        fi
        log "Filebrowser 已配置为密码登录模式"
    fi
}

copy_supervisor_conf() {
    log "复制supervisor配置文件..."
    if [ "$core_name" = "sing-box" ]; then
        cp run_mssb/supervisord.conf /etc/supervisor/ || {
            log "复制 supervisord.conf 失败！退出脚本。"
            exit 1
        }
    elif [ "$core_name" = "mihomo" ]; then
        cp run_msmo/supervisord.conf /etc/supervisor/ || {
            log "复制 supervisord.conf 失败！退出脚本。"
            exit 1
        }
    else
        log "未识别的 core_name: $core_name，跳过复制 supervisor 配置文件。"
    fi
}

choose_supervisor_auth() {
    echo -e "\n${green_text}=== Supervisor 管理配置设置 ===${reset}"
    # 直接用环境变量 supervisor_user 和 supervisor_pass
    if [ -n "$supervisor_user" ] && [ -n "$supervisor_pass" ]; then
        sed -i "s/^username=.*/username=$supervisor_user/" /etc/supervisor/supervisord.conf
        sed -i "s/^password=.*/password=$supervisor_pass/" /etc/supervisor/supervisord.conf
        log "已设置 Supervisor 用户名和密码: $supervisor_user/******"
    else
        sed -i "s/^username=.*/username=/" /etc/supervisor/supervisord.conf
        sed -i "s/^password=.*/password=/" /etc/supervisor/supervisord.conf
        log "已清除 Supervisor 用户名和密码设置（允许无密码登录）"
    fi
}

copy_watch_and_set_permission() {
    cp -rf watch / || {
        log "复制 watch 目录失败！退出脚本。"
        exit 1
    }
    log "设置脚本可执行权限..."
    chmod +x /watch/*.sh || {
        log "设置 /watch/*.sh 权限失败！退出脚本。"
        exit 1
    }
}

cp_config_files() {
    copy_fb_folder
    copy_mosdns_folder
    mosdns_configure_files
    init_filebrowser_db
    choose_filebrowser_login
    copy_supervisor_conf
    choose_supervisor_auth
    copy_watch_and_set_permission
}

# singbox配置文件复制
singbox_configure_files() {
    # 复制 mssb/sing-box 目录
    if [ -d "/mssb/sing-box" ]; then
            rm -rf /mssb/sing-box
    fi
    log "复制 mssb/sing-box 目录..."
    check_and_copy_folder "sing-box"

    # 直接使用环境变量 singbox_core_type
    if [ "$singbox_core_type" = "reF1nd" ]; then
        log "检测到 R核心，复制 sing-box-r.json 配置文件"
        if [ -f "/mssb/sing-box/sing-box-r.json" ]; then
            cp /mssb/sing-box/sing-box-r.json /mssb/sing-box/config.json
            log "已复制 sing-box-r.json 为 config.json"
        else
            log "警告：找不到 sing-box-r.json 文件"
        fi
    elif [ "$singbox_core_type" = "yelnoo" ]; then
        log "检测到 Y核心，复制 sing-box-y.json 配置文件"
        if [ -f "/mssb/sing-box/sing-box-y.json" ]; then
            cp /mssb/sing-box/sing-box-y.json /mssb/sing-box/config.json
            log "已复制 sing-box-y.json 为 config.json"
        else
            log "警告：找不到 sing-box-y.json 文件"
        fi
    else
        log "未知核心类型：$singbox_core_type，使用默认配置文件"
    fi
}

# mihomo配置文件复制
mihomo_configure_files() {
    # 复制 mssb/mihomo 目录
    # 判断 /mssb/mihomo 是否存在，存在则备份ui文件夹后删除
    if [ -d "/mssb/mihomo" ]; then
        # 如果存在ui文件夹，先备份
        if [ -d "/mssb/mihomo/ui" ]; then
            log "备份 ui 文件夹..."
            mv /mssb/mihomo/ui /tmp/mihomo_ui_backup
        fi
        rm -rf /mssb/mihomo
    fi
    log "复制 mssb/mihomo 目录..."
    check_and_copy_folder "mihomo"
    # 恢复ui文件夹
    if [ -d "/tmp/mihomo_ui_backup" ]; then
        log "恢复 ui 文件夹..."
        mv /tmp/mihomo_ui_backup /mssb/mihomo/ui
    fi
}

# 服务启动和重载
reload_service() {
    log "重启 Supervisor..."
    if ! supervisorctl stop all; then
        log "停止 Supervisor 失败！"
        exit 1
    fi
    log "Supervisor 停止成功。"
    sleep 2

    if ! supervisorctl reload; then
        log "重启 Supervisor 失败！"
        exit 1
    fi
    log "Supervisor 重启成功。"
    sleep 2

    # 根据 core_name 重启 systemd 服务
    if [ "$core_name" = "sing-box" ]; then
        # 确保 mihomo-router 服务被禁用和停止
        systemctl stop mihomo-router 2>/dev/null
        systemctl disable mihomo-router 2>/dev/null
        rm -f /etc/systemd/system/mihomo-router.service

        # 启动 sing-box-router
        systemctl daemon-reload
        systemctl enable --now sing-box-router || { log "启用 sing-box-router 服务失败！"; exit 1; }
        log "已重启 sing-box-router 服务。"
    elif [ "$core_name" = "mihomo" ]; then
        # 确保 sing-box-router 服务被禁用和停止
        systemctl stop sing-box-router 2>/dev/null
        systemctl disable sing-box-router 2>/dev/null
        rm -f /etc/systemd/system/sing-box-router.service

        # 启动 mihomo-router
        systemctl daemon-reload
        systemctl enable --now mihomo-router || { log "启用 mihomo-router 服务失败！"; exit 1; }
        log "已重启 mihomo-router 服务。"
    else
        log "未识别的 core_name: $core_name，跳过 systemd 服务重启。"
    fi
}

# 添加任务到 crontab
add_cron_jobs() {
    echo -e "\n${green_text}=== 定时更新任务设置 ===${reset}"

    # 先清除所有相关的定时任务
    (crontab -l | grep -v -e "# update_mosdns" -e "# update_sb" -e "# update_cn" -e "# update_mihomo") | crontab -
    log "已清除所有相关定时任务"

    cron_jobs=()

    # 根据环境变量决定是否添加任务
    if [[ "$enable_mosdns_cron" =~ ^[Yy]$ ]]; then
        cron_jobs+=("0 4 * * 1 /watch/update_mosdns.sh # update_mosdns")
    fi
    if [[ "$enable_core_cron" =~ ^[Yy]$ ]]; then
        if [ "$core_name" = "sing-box" ]; then
            cron_jobs+=("10 4 * * 1 /watch/update_sb.sh # update_sb")
        elif [ "$core_name" = "mihomo" ]; then
            cron_jobs+=("10 4 * * 1 /watch/update_mihomo.sh # update_mihomo")
        fi
    fi

    # 如果没有选择任何更新任务
    if [ ${#cron_jobs[@]} -eq 0 ]; then
        log "未选择任何更新任务，跳过定时任务设置。"
        return
    fi

    # 添加选中的定时任务
    for job in "${cron_jobs[@]}"; do
        if (crontab -l | grep -q -F "$job"); then
            log "定时任务已存在：$job"
        else
            (crontab -l; echo "$job") | crontab -
            log "定时任务已成功添加：$job"
        fi
    done
}

# 停止所有服务
stop_all_services() {
    log "正在停止所有服务..."

    # 停止 supervisor 管理的服务
    if command -v supervisorctl &>/dev/null; then
        supervisorctl stop all 2>/dev/null || true
    fi

    # 停止并禁用 sing-box-router
    if systemctl is-active sing-box-router &>/dev/null; then
        systemctl stop sing-box-router
        systemctl disable sing-box-router
    fi

    # 停止并禁用 mihomo-router
    if systemctl is-active mihomo-router &>/dev/null; then
        systemctl stop mihomo-router
        systemctl disable mihomo-router
    fi

    # 停止并禁用 nftables
    if systemctl is-active nftables &>/dev/null; then
        systemctl stop nftables
        systemctl disable nftables
    fi

    systemctl daemon-reload
    log "所有服务已停止。"
}

# 检查并设置本地 DNS
check_and_set_local_dns() {
    # 优先使用dns_after_install变量
    if [ -n "$dns_after_install" ]; then
        echo "nameserver $dns_after_install" > /etc/resolv.conf
        echo -e "${green_text}已设置 DNS 为 $dns_after_install${reset}"
        return
    fi
    # 获取当前 DNS 设置
    current_dns=$(cat /etc/resolv.conf | grep -E "^nameserver" | head -n 1 | awk '{print $2}')

    if [ "$current_dns" != "$local_ip" ]; then
        echo -e "\n${yellow}提示：当前 DNS 设置不是本地 IP ($local_ip)${reset}"
        echo -e "${yellow}建议将 DNS 设置为本地 IP 以使用 MosDNS 服务${reset}"
        echo -e "${green_text}请选择操作：${reset}"
        echo -e "1) 设置为本地 IP ($local_ip)"
        echo -e "2) 保持当前设置 ($current_dns)"
        echo -e "${green_text}-------------------------------------------------${reset}"
        read -p "请输入选项 (1/2): " dns_choice

        case $dns_choice in
            1)
                echo "nameserver $local_ip" > /etc/resolv.conf
                echo -e "${green_text}已设置 DNS 为本地 IP ($local_ip)${reset}"
                ;;
            2)
                echo -e "${yellow}保持当前 DNS 设置 ($current_dns)${reset}"
                ;;
            *)
                echo -e "${red}无效选项，将保持当前设置${reset}"
                ;;
        esac
    else
        echo -e "${green_text}当前 DNS 已设置为本地 IP ($local_ip)${reset}"
    fi
}

# 启动所有服务
start_all_services() {
    log "正在启动所有服务..."

    # 检查并启动 nftables
    if [ -f "/etc/nftables.conf" ]; then
        local nft_cmd=""
        if command -v nft &>/dev/null; then
            nft_cmd="nft"
        elif [ -x "/usr/sbin/nft" ]; then
            nft_cmd="/usr/sbin/nft"
        else
            log "错误：找不到 nft 命令，跳过 nftables 加载"
        fi

        if [ -n "$nft_cmd" ]; then
            cp /etc/nftables.conf /etc/nftables.conf.bak
            if $nft_cmd -c -f /etc/nftables.conf; then
                $nft_cmd flush ruleset
                sleep 1
                $nft_cmd -f /etc/nftables.conf
                if is_container_env; then
                    log "容器环境：已加载规则，跳过启用 nftables.service"
                else
                    systemctl enable --now nftables || log "nftables 服务启动失败"
                fi
            else
                log "nftables 配置有语法错误，已取消加载"
                cp /etc/nftables.conf.bak /etc/nftables.conf
            fi
        fi
	    fi

	    # 检查并启动对应的路由服务
	    if [ -f "/etc/systemd/system/sing-box-router.service" ]; then
	        systemctl enable --now sing-box-router || log "sing-box-router 服务启动失败"
    elif [ -f "/etc/systemd/system/mihomo-router.service" ]; then
        systemctl enable --now mihomo-router || log "mihomo-router 服务启动失败"
    fi

    # 启动 supervisor 管理的服务
    if command -v supervisorctl &>/dev/null; then
        supervisorctl start all || log "supervisor 服务启动失败"
    fi

    log "所有服务启动完成。"
}

# 卸载所有服务
uninstall_all_services() {
    log "正在卸载所有服务..."

    # 停止所有服务
    stop_all_services
    # 获取当前版本和核心类型信息
    detect_singbox_info

    # 删除服务文件
    rm -f /etc/systemd/system/sing-box-router.service
    rm -f /etc/systemd/system/mihomo-router.service
    rm -f /etc/nftables.conf

    # 删除程序文件
    rm -f /usr/local/bin/mosdns
    rm -f /usr/local/bin/sing-box
    rm -f /usr/local/bin/mihomo
    rm -f /usr/local/bin/filebrowser

    # 删除配置目录（保留备份目录和mssb.env）
    find /mssb -mindepth 1 -maxdepth 1 -not -name "backup" -not -name "mssb.env" -exec rm -rf {} +
    log "/mssb/mssb.env 环境变量文件已保留，如需彻底清理请手动删除。"

    # 删除 supervisor 配置
    rm -f /etc/supervisor/supervisord.conf

    # 卸载 supervisor
    if command -v apt-get &>/dev/null; then
        apt-get remove -y supervisor >/dev/null 2>&1
        apt-get purge -y supervisor >/dev/null 2>&1
    fi

    # 清理定时任务
    log "清理定时任务..."
    (crontab -l | grep -v -e "# update_mosdns" -e "# update_sb" -e "# update_cn" -e "# update_mihomo") | crontab -

    systemctl daemon-reload
    log "所有服务已卸载完成。配置文件已备份到 $backup_dir 目录"
    log "卸载的核心类型：$core_type"

    # 卸载后恢复DNS
    if [ -n "$dns_after_uninstall" ]; then
        echo "nameserver $dns_after_uninstall" > /etc/resolv.conf
        log "卸载后已恢复 DNS 为 $dns_after_uninstall"
    fi
}

# 智能检测 Sing-box 核心类型和版本
detect_singbox_info() {
    # 获取版本输出
    version_output=$(/usr/local/bin/sing-box version 2>/dev/null | head -n1)
    current_version=$(echo "$version_output" | awk '{print $3}' || echo "未知版本")
    log "当前安装的版本: $current_version"
    log "当前核心类型: $singbox_core_type (来源：/mssb/mssb.env)"
}

# reF1nd佬 R核心安装函数
singbox_r_install() {
    # 检查是否已安装 Sing-box
    if [ -f "/usr/local/bin/sing-box" ]; then
        log "检测到已安装的 Sing-box"

        # 获取当前版本和核心类型信息
        detect_singbox_info
        if [ "$install_update_mode_singbox" = "n" ]; then
            log "跳过 Sing-box reF1nd R核心 下载，使用现有版本"
            return 0
        else
            log "选择更新 Sing-box reF1nd R核心 到最新版本"
        fi
    fi

    # 下载并安装 reF1nd R核心
    arch=$(detect_architecture)
    # https://github.com/baozaodetudou/mssb/releases/download/sing-box-reF1nd/sing-box-reF1nd-dev-linux-amd64.tar.gz
    # https://github.com/baozaodetudou/mssb/releases/download/sing-box-reF1nd/sing-box-reF1nd-dev-linux-amd64v3.tar.gz
    if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
        download_url="https://github.com/baozaodetudou/mssb/releases/download/sing-box-reF1nd/sing-box-reF1nd-dev-linux-amd64v3.tar.gz"
    else
        download_url="https://github.com/baozaodetudou/mssb/releases/download/sing-box-reF1nd/sing-box-reF1nd-dev-linux-${arch}.tar.gz"
    fi
    

    log "开始下载 reF1nd佬 R核心..."
    if ! wget -O sing-box.tar.gz "$download_url"; then
        error_log "下载失败，请检查网络连接"
        exit 1
    fi

    log "下载完成，开始安装"
    tar -zxvf sing-box.tar.gz > /dev/null 2>&1
    mv sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -f sing-box.tar.gz

    # 显示安装完成的版本信息
    new_version=$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 | awk '{print $3}' || echo "未知版本")
    log "Sing-box reF1nd R核心 安装完成，版本：$new_version"
}

# Y核安装函数
singbox_y_install() {
    # 检查是否已安装 Sing-box
    if [ -f "/usr/local/bin/sing-box" ]; then
        log "检测到已安装的 Sing-box"

        # 获取当前版本和核心类型信息
        detect_singbox_info
        if [ "$install_update_mode_singbox" = "n" ]; then
            log "跳过 Sing-box S佬Y核心 下载，使用现有版本"
            return 0
        else
            log "选择更新 Sing-box S佬Y核心 到最新版本"
        fi
    fi

    # 下载并安装 S佬Y核心
    arch=$(detect_architecture)
    # https://github.com/baozaodetudou/mssb/releases/download/sing-box-yelnoo/sing-box-yelnoo-dev-linux-amd64.tar.gz
    # https://github.com/baozaodetudou/mssb/releases/download/sing-box-yelnoo/sing-box-yelnoo-dev-linux-amd64v3.tar.gz
    if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
        download_url="https://github.com/baozaodetudou/mssb/releases/download/sing-box-yelnoo/sing-box-yelnoo-dev-linux-amd64v3.tar.gz"
    else
        download_url="https://github.com/baozaodetudou/mssb/releases/download/sing-box-yelnoo/sing-box-yelnoo-dev-linux-${arch}.tar.gz"
    fi

    log "开始下载 S佬Y核心..."
    if ! wget -O sing-box.tar.gz "$download_url"; then
        error_log "下载失败，请检查网络连接"
        exit 1
    fi

    log "下载完成，开始安装"
    tar -zxvf sing-box.tar.gz > /dev/null 2>&1
    mv sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    rm -f sing-box.tar.gz

    # 显示安装完成的版本信息
    new_version=$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 | awk '{print $3}' || echo "未知版本")
    log "Sing-box S佬Y核心 安装完成，版本：$new_version"
}

# 修改 Supervisor 配置
modify_supervisor_config() {
    echo -e "\n${green_text}请选择 Supervisor 管理界面配置方式：${reset}"
    echo -e "${green_text}1) 使用默认配置（用户名：mssb，密码：mssb123..）${reset}"
    echo -e "${green_text}2) 自定义用户名和密码${reset}"
    echo -e "${green_text}3) 不设置用户名密码${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "请输入选项 (1/2/3): " supervisor_choice

    case $supervisor_choice in
        1)
            # 使用默认配置
            supervisor_username="mssb"
            supervisor_password="mssb123.."
            ;;
        2)
            # 自定义用户名和密码
            read -p "请输入用户名: " supervisor_username
            read -p "请输入密码: " supervisor_password
            ;;
        3)
            # 不设置用户名密码
            supervisor_username=""
            supervisor_password=""
            ;;
        *)
            echo -e "${red}无效的选项${reset}"
            return 1
            ;;
    esac

    # 更新 Supervisor 配置
    if [ -f "/etc/supervisor/supervisord.conf" ]; then
        if [ -n "$supervisor_username" ] && [ -n "$supervisor_password" ]; then
            sed -i "s/^username=.*/username=$supervisor_username/" /etc/supervisor/supervisord.conf
            sed -i "s/^password=.*/password=$supervisor_password/" /etc/supervisor/supervisord.conf
        else
            sed -i "s/^username=.*/username=/" /etc/supervisor/supervisord.conf
            sed -i "s/^password=.*/password=/" /etc/supervisor/supervisord.conf
        fi
        systemctl restart supervisor.service
        supervisorctl reload
        echo -e "${green_text}Supervisor 配置已更新${reset}"
    else
        echo -e "${red}Supervisor 配置文件不存在${reset}"
        return 1
    fi

    # 同步到env文件
    local env_file="/mssb/mssb.env"
    if [ -f "$env_file" ]; then
        if grep -q "^supervisor_user=" "$env_file" 2>/dev/null; then
            sed -i "s|^supervisor_user=.*|supervisor_user=$supervisor_username|" "$env_file"
        else
            echo "supervisor_user=$supervisor_username" >> "$env_file"
        fi
        if grep -q "^supervisor_pass=" "$env_file" 2>/dev/null; then
            sed -i "s|^supervisor_pass=.*|supervisor_pass=$supervisor_password|" "$env_file"
        else
            echo "supervisor_pass=$supervisor_password" >> "$env_file"
        fi
    fi
}

# 修改 Filebrowser 配置
modify_filebrowser_config() {
    echo -e "\n${green_text}请选择 Filebrowser 登录方式：${reset}"
    echo -e "${green_text}1) 使用密码登录${reset}"
    echo -e "${green_text}2) 禁用密码登录${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "请输入选项 (1/2): " fb_choice

    local fb_login_mode_new="auth"
    case $fb_choice in
        1)
            fb_login_mode_new="auth"
            # 使用密码登录
            if [ -f "/mssb/fb/fb.db" ]; then
                echo -e "\n${green_text}请选择密码设置方式：${reset}"
                echo -e "${green_text}1) 使用默认密码（admin123456789QAQ）${reset}"
                echo -e "${green_text}2) 自定义密码（密码长度不能小于16位不然会设置失败,就得打开supervisor查看日志获取）${reset}"
                echo -e "${green_text}-------------------------------------------------${reset}"
                read -p "请输入选项 (1/2): " password_choice

                supervisorctl stop filebrowser
                filebrowser config set --auth.method=json -c /mssb/fb/fb.json -d /mssb/fb/fb.db

                case $password_choice in
                    1)
                        # 使用默认密码
                        filebrowser users update admin --password "admin123456789QAQ" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                        echo -e "${green_text}Filebrowser 已设置为使用默认密码（admin/admin123456789QAQ）${reset}"
                        ;;
                    2)
                        # 自定义密码
                        read -p "请输入新密码（密码长度不能小于16位不然会设置失败,就得打开supervisor查看日志获取）（输入时可见）: " new_password
                        if [ -n "$new_password" ]; then
                            filebrowser users update admin --password "$new_password" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                            echo -e "${green_text}Filebrowser 密码已更新${reset}"
                        else
                            echo -e "${red}密码不能为空，将使用默认密码${reset}"
                            filebrowser users update admin --password "admin123456789QAQ" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                        fi
                        ;;
                    *)
                        echo -e "${red}无效的选项，将使用默认密码${reset}"
                        filebrowser users update admin --password "admin123456789QAQ" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                        ;;
                esac

                supervisorctl start filebrowser
            else
                echo -e "${red}Filebrowser 配置文件不存在${reset}"
                return 1
            fi
            ;;
        2)
            fb_login_mode_new="noauth"
            # 禁用密码登录
            if [ -f "/mssb/fb/fb.db" ]; then
                supervisorctl stop filebrowser
                filebrowser config set --auth.method=noauth -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                supervisorctl start filebrowser
                echo -e "${green_text}Filebrowser 已禁用密码登录${reset}"
            else
                echo -e "${red}Filebrowser 配置文件不存在${reset}"
                return 1
            fi
            ;;
        *)
            echo -e "${red}无效的选项${reset}"
            return 1
            ;;
    esac

    # 同步到env文件
    local env_file="/mssb/mssb.env"
    if [ -f "$env_file" ]; then
        if grep -q "^fb_login_mode=" "$env_file" 2>/dev/null; then
            sed -i "s|^fb_login_mode=.*|fb_login_mode=$fb_login_mode_new|" "$env_file"
        else
            echo "fb_login_mode=$fb_login_mode_new" >> "$env_file"
        fi
    fi
}

# 修改服务配置
modify_service_config() {
    echo -e "\n${green_text}请选择要修改的配置(成功后会更新env文件)：${reset}"
    echo -e "${green_text}1) 修改 Supervisor 管理界面配置${reset}"
    echo -e "${green_text}2) 修改 Filebrowser 登录方式${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "请输入选项 (1/2): " config_choice

    case $config_choice in
        1)
            modify_supervisor_config
            ;;
        2)
            modify_filebrowser_config
            ;;
        *)
            echo -e "${red}无效的选项${reset}"
            return 1
            ;;
    esac
}

# 检查 DNS 设置
uninstall_dns_settings() {
    if [ -n "$dns_after_uninstall" ]; then
        echo "nameserver $dns_after_uninstall" > /etc/resolv.conf
        echo -e "${green_text}已恢复 DNS 为 $dns_after_uninstall${reset}"
    else
        echo -e "${yellow}未设置卸载后DNS恢复变量，未做更改${reset}"
    fi
}

# ========== yq自动安装和mihomo订阅编辑函数 ==========
install_latest_yq() {
    # 如果已存在且可用则跳过
    if command -v yq >/dev/null 2>&1; then
        echo "yq 已存在，版本: $(yq --version)"
        return 0
    fi
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="arm" ;;
        *) echo "不支持的架构: $arch"; return 1 ;;
    esac
    os=$(uname | tr '[:upper:]' '[:lower:]')
    yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_${os}_${arch}"
    echo "正在下载 yq: $yq_url"
    curl -L "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
    if yq --version >/dev/null 2>&1; then
        echo "yq 安装成功，版本: $(yq --version)"
    else
        echo "yq 安装失败"
        return 1
    fi
}

edit_mihomo_proxy_providers() {
    local config_file="/mssb/mihomo/config.yaml"
    local providers=("$@")
    echo "[yq] 开始清空 proxy-providers..."
    yq -i 'del(.proxy-providers) | .proxy-providers = {}' "$config_file"
    local idx=0
    # 检查 yq 是否支持 --no-escape
    yq --no-escape '.' /dev/null 2>/dev/null
    local yq_no_escape=$?
    for item in "${providers[@]}"; do
        if [[ "$item" == *"|"* ]]; then
            tag="${item%%|*}"
            url="${item#*|}"
        else
            idx=$((idx+1))
            tag="✈️机场${idx}"
            url="$item"
        fi
        echo "[yq] 正在写入 tag: $tag, url: $url"
        if [ $yq_no_escape -eq 0 ]; then
            yq -i --no-escape ".proxy-providers.\"$tag\".url = \"$url\"" "$config_file"
            yq -i --no-escape ".proxy-providers.\"$tag\".type = \"http\"" "$config_file"
            yq -i --no-escape ".proxy-providers.\"$tag\".interval = 3600" "$config_file"
            yq -i --no-escape ".proxy-providers.\"$tag\".health-check.enable = true" "$config_file"
            yq -i --no-escape ".proxy-providers.\"$tag\".health-check.url = \"http://detectportal.firefox.com/success.txt\"" "$config_file"
            yq -i --no-escape ".proxy-providers.\"$tag\".health-check.interval = 120" "$config_file"
            yq -i --no-escape ".proxy-providers.\"$tag\".path = \"./proxy_providers/${tag}.yaml\"" "$config_file"
        else
            yq -i ".proxy-providers.\"$tag\".url = \"$url\"" "$config_file"
            yq -i ".proxy-providers.\"$tag\".type = \"http\"" "$config_file"
            yq -i ".proxy-providers.\"$tag\".interval = 3600" "$config_file"
            yq -i ".proxy-providers.\"$tag\".health-check.enable = true" "$config_file"
            yq -i ".proxy-providers.\"$tag\".health-check.url = \"http://detectportal.firefox.com/success.txt\"" "$config_file"
            yq -i ".proxy-providers.\"$tag\".health-check.interval = 120" "$config_file"
            yq -i ".proxy-providers.\"$tag\".path = \"./proxy_providers/${tag}.yaml\"" "$config_file"
        fi
        echo "[yq] 已写入 $tag 到 proxy-providers"
    done
    echo "[yq] 已全部更新 $config_file 的 proxy-providers 部分"
}
# ========== END yq自动安装和mihomo订阅编辑函数 ==========

# 格式化路由规则并提示
format_route_rules() {
    echo -e "\n${yellow}请在主路由中添加以下路由规则：${reset}"

    # 主路由 DNS 设置
    echo -e "${green_text}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${green_text}│ 主路由 DNS 设置                               │${reset}"
    echo -e "${green_text}├───────────────────────────────────────────────┤${reset}"
    printf "${green_text}│ %-15s  %-29s   │${reset}\n" "DNS 服务器:" "$local_ip"
    echo -e "${green_text}└───────────────────────────────────────────────┘${reset}"

    # MosDNS 和 Mihomo fakeip 路由
    echo -e "${green_text}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${green_text}│ MosDNS 和 Mihomo fakeip 路由                  │${reset}"
    echo -e "${green_text}├───────────────────────┬───────────────────────┤${reset}"
    printf "${green_text}│ %-21s     │ %-21s   │${reset}\n" "目标地址" "网关"
    echo -e "${green_text}├───────────────────────┼───────────────────────┤${reset}"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "28.0.0.0/8" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "8.8.8.8/32" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "1.1.1.1/32" "$local_ip"
    echo -e "${green_text}└───────────────────────┴───────────────────────┘${reset}"

    # Telegram 路由
    echo -e "${green_text}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${green_text}│ Telegram 路由                                 │${reset}"
    echo -e "${green_text}├───────────────────────┬───────────────────────┤${reset}"
    printf "${green_text}│ %-21s     │ %-21s   │${reset}\n" "目标地址" "网关"
    echo -e "${green_text}├───────────────────────┼───────────────────────┤${reset}"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "149.154.160.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "149.154.164.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "149.154.172.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "91.108.4.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "91.108.20.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "91.108.56.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "91.108.8.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "95.161.64.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "91.108.12.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "91.108.16.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "67.198.55.0/24" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "109.239.140.0/24" "$local_ip"
    echo -e "${green_text}└───────────────────────┴───────────────────────┘${reset}"

    # Netflix 路由
    echo -e "${green_text}┌───────────────────────────────────────────────┐${reset}"
    echo -e "${green_text}│ Netflix 路由                                  │${reset}"
    echo -e "${green_text}├───────────────────────┬───────────────────────┤${reset}"
    printf "${green_text}│ %-21s     │ %-21s   │${reset}\n" "目标地址" "网关"
    echo -e "${green_text}├───────────────────────┼───────────────────────┤${reset}"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "207.45.72.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "208.75.76.0/22" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "210.0.153.0/24" "$local_ip"
    printf "${green_text}│ %-21s │ %-21s │${reset}\n" "185.76.151.0/24" "$local_ip"
    echo -e "${green_text}└───────────────────────┴───────────────────────┘${reset}"

    echo -e "\n${yellow}注意：${reset}"
    echo -e "1. 主路由的 DNS 服务器必须设置为本机 IP：$local_ip"
    echo -e "2. 添加路由后，相关服务将自动通过本机代理"
    echo -e "${green_text}-------------------------------------------------${reset}"
    echo -e "${green_text} routeros 具体可以参考: https://github.com/baozaodetudou/mssb/blob/main/docs/fakeip.md ${reset}"
}

# 扫描局域网设备并配置代理设备列表
scan_lan_devices() {
    echo -e "\n${green_text}=== 局域网设备扫描 ===${reset}"
    echo -e "此功能将扫描局域网中的设备，让您选择需要代理的设备"
    echo -e "${yellow}注意：此操作会清空并重写 client_ip${reset}"
    echo -e "${green_text}------------------------${reset}"

    # 检查必要工具
    if ! command -v arp-scan &> /dev/null; then
        log "正在安装 arp-scan 工具..."
        apt update && apt install -y arp-scan
        if ! command -v arp-scan &> /dev/null; then
            log "arp-scan 安装失败，无法进行设备扫描"
            scanned_ip_list=""
            return 1
        fi
    fi

    # 获取当前使用的网络接口
    local interface
    if [ -n "$selected_interface" ]; then
        interface="$selected_interface"
    else
        interface=$(ip route | grep default | awk '{print $5}' | head -n1)
        if [ -z "$interface" ]; then
            log "无法自动检测网络接口"
            scanned_ip_list=""
            return 1
        fi
    fi

    log "使用网络接口：$interface"

    # 扫描局域网设备
    echo -e "${yellow}🔍 正在扫描局域网设备，请稍等...${reset}"
    local raw_result
    raw_result=$(arp-scan --interface="$interface" --localnet 2>/dev/null | grep -E "^([0-9]{1,3}\.){3}[0-9]{1,3}")

    if [ -z "$raw_result" ]; then
        log "未找到设备"
        scanned_ip_list=""
        return 1
    fi

    # 解析设备
    local devices=()
    local device_ips=()
    while IFS= read -r line; do
        devices+=("$line")
        device_ips+=("$(echo "$line" | awk '{print $1}')")
    done < <(echo "$raw_result")

    # 显示设备列表
    echo ""
    echo -e "${green_text}📋 发现的局域网设备：${reset}"
    echo -e "${green_text}┌─────┬─────────────────┬───────────────────┬──────────────────────────────────────────────────┐${reset}"
    echo -e "${green_text}│ 编号│ IP地址          │ MAC地址           │ 设备描述                                         │${reset}"
    echo -e "${green_text}├─────┼─────────────────┼───────────────────┼──────────────────────────────────────────────────┤${reset}"
    for i in "${!devices[@]}"; do
        local ip=$(echo "${devices[$i]}" | awk '{print $1}')
        local mac=$(echo "${devices[$i]}" | awk '{print $2}')
        local desc=$(echo "${devices[$i]}" | awk '{for(j=3;j<=NF;j++) printf "%s ", $j; print ""}' | sed 's/[()]//g' | sed 's/^ *//;s/ *$//')

        # 如果描述为空，显示Unknown
        if [ -z "$desc" ]; then
            desc="Unknown"
        fi

        # 限制描述长度，增加到48个字符
        if [ ${#desc} -gt 48 ]; then
            desc="${desc:0:45}..."
        fi

        printf "${green_text}│ %3d │ %-15s │ %-17s │ %-48s │${reset}\n" "$((i+1))" "$ip" "$mac" "$desc"
    done
    echo -e "${green_text}└─────┴─────────────────┴───────────────────┴──────────────────────────────────────────────────┘${reset}"
    # 用户选择设备
    echo ""
    echo -e "${yellow}请输入要添加到代理列表的设备编号（如 1,3,5）：${reset}"
    read -p "编号: " selected_ids

    scanned_ip_list=""
    IFS=',' read -ra ids <<< "$selected_ids"
    for id in "${ids[@]}"; do
        # 去除空格
        id=$(echo "$id" | tr -d ' ')
        idx=$((id-1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#device_ips[@]}" ]; then
            scanned_ip_list="$scanned_ip_list ${device_ips[$idx]}"
        fi
    done
    scanned_ip_list=$(echo "$scanned_ip_list" | xargs) # 去除首尾空格
    log "最终选择的设备IP: $scanned_ip_list"

    # 覆盖写入env（仅当文件已存在时才写入）
    env_file="/mssb/mssb.env"
    if [ -f "$env_file" ]; then
        if grep -q "^client_ip_list=" "$env_file" 2>/dev/null; then
            sed -i "s|^client_ip_list=.*|client_ip_list=\"$scanned_ip_list\"|" "$env_file"
        else
            echo "client_ip_list=\"$scanned_ip_list\"" >> "$env_file"
        fi
    fi

    # 覆盖写入txt（仅当文件已存在时才写入）
    if [ -f /mssb/mosdns/client_ip.txt ]; then
        echo "$scanned_ip_list" | tr ' ' '\n' > /mssb/mosdns/client_ip.txt
        log "已覆盖写入代理设备列表到 $env_file 和 /mssb/mosdns/client_ip.txt"
    else
        log "已覆盖写入代理设备列表到 $env_file，未写入 /mssb/mosdns/client_ip.txt（文件不存在）"
    fi
    return 0
}

# 创建全局 mssb 命令
create_mssb_command() {
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    local script_path="$script_dir/install.sh"

    # 创建 mssb 命令脚本
    cat > /usr/local/bin/mssb << EOF
#!/bin/bash
# MSSB 全局命令
# 自动切换到脚本目录并执行 install.sh

SCRIPT_DIR="$script_dir"
SCRIPT_PATH="$script_path"

# 检查脚本是否存在
if [ ! -f "\$SCRIPT_PATH" ]; then
    echo -e "\033[31m错误：找不到 install.sh 脚本文件\033[0m"
    echo "预期位置：\$SCRIPT_PATH"
    echo "请确保脚本文件存在或重新安装 MSSB"
    exit 1
fi

# 切换到脚本目录并执行
echo -e "\033[32m正在启动 MSSB 管理脚本...\033[0m"
echo "脚本位置：\$SCRIPT_DIR"
cd "\$SCRIPT_DIR" || {
    echo -e "\033[31m错误：无法切换到脚本目录\033[0m"
    exit 1
}

# 执行脚本并传递所有参数
bash "\$SCRIPT_PATH" "\$@"
EOF

    # 设置执行权限
    chmod +x /usr/local/bin/mssb

    if [ $? -eq 0 ]; then
        echo -e "${green_text}✅ 全局命令 'mssb' 创建成功！${reset}"
        echo -e "${green_text}现在您可以在任意位置输入 'mssb' 来运行此脚本${reset}"
        echo -e "${yellow}脚本目录：$script_dir${reset}"
    else
        echo -e "${red}❌ 创建全局命令失败，请检查权限${reset}"
        return 1
    fi
}

# 删除全局 mssb 命令
remove_mssb_command() {
    if [ -f "/usr/local/bin/mssb" ]; then
        rm -f /usr/local/bin/mssb
        if [ $? -eq 0 ]; then
            echo -e "${green_text}✅ 全局命令 'mssb' 删除成功！${reset}"
        else
            echo -e "${red}❌ 删除全局命令失败，请检查权限${reset}"
            return 1
        fi
    else
        echo -e "${yellow}⚠️  全局命令 'mssb' 不存在${reset}"
    fi
}

# 更新项目
update_project() {
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    echo -e "${green_text}正在更新项目...${reset}"
    echo "项目目录：$script_dir"

    cd "$script_dir" || {
        echo -e "${red}❌ 无法切换到项目目录${reset}"
        return 1
    }

    # 先记录当前 HEAD
    local old_head=$(git rev-parse HEAD)
    git pull
    local pull_status=$?
    local new_head=$(git rev-parse HEAD)

    if [ $pull_status -eq 0 ]; then
        if [ "$old_head" != "$new_head" ]; then
            echo -e "${green_text}✅ 项目有更新，正在重启脚本...${reset}"
            # 检查并赋予可执行权限
            if [ ! -x "$0" ]; then
                chmod +x "$0"
            fi
            exec "$0" "$@"
        else
            echo -e "${yellow}项目已是最新，无需重启脚本${reset}"
        fi
    else
        echo -e "${red}❌ 项目更新失败${reset}"
        return 1
    fi
}

# 更新内核版本菜单
update_cores_menu() {
    echo -e "\n${green_text}=== 更新内核版本 ===${reset}"

    # 检测已安装的程序
    local mosdns_installed=false
    local singbox_installed=false
    local mihomo_installed=false

    # 检查执行文件是否存在
    if [ -f "/usr/local/bin/mosdns" ]; then
        mosdns_installed=true
    fi

    if [ -f "/usr/local/bin/sing-box" ]; then
        singbox_installed=true
    fi

    if [ -f "/usr/local/bin/mihomo" ]; then
        mihomo_installed=true
    fi

    # 显示已安装的程序状态
    echo -e "${yellow}检测到已安装的程序：${reset}"
    echo -e "  - MosDNS: $([ $mosdns_installed = true ] && echo '✅ 已安装' || echo '❌ 未安装')"
    echo -e "  - Sing-box: $([ $singbox_installed = true ] && echo '✅ 已安装' || echo '❌ 未安装')"
    echo -e "  - Mihomo: $([ $mihomo_installed = true ] && echo '✅ 已安装' || echo '❌ 未安装')"

    # 检查是否有程序可以更新
    if ! $mosdns_installed && ! $singbox_installed && ! $mihomo_installed; then
        echo -e "\n${red}❌ 未检测到任何已安装的程序${reset}"
        echo -e "${yellow}请先安装程序后再使用更新功能${reset}"
        echo -e "可以使用主菜单选项1进行安装"
        return 1
    fi

    # 显示更新选项菜单
    echo -e "\n${yellow}请选择要更新的组件：${reset}"

    if $mosdns_installed; then
        echo -e "1. 更新 MosDNS"
        echo -e "4. 更新 CN域名数据"
    fi

    if $singbox_installed; then
        echo -e "2. 更新 Sing-box"
    fi

    if $mihomo_installed; then
        echo -e "3. 更新 Mihomo"
    fi

    echo -e "5. 更新所有已安装的组件"
    echo -e "0. 返回主菜单"
    echo -e "${green_text}------------------------${reset}"

    read -p "请选择更新选项 (0-5): " update_choice

    case "$update_choice" in
        1)
            if $mosdns_installed; then
                echo -e "${green_text}正在更新 MosDNS...${reset}"
                /watch/update_mosdns.sh
            else
                echo -e "${red}MosDNS 未安装，无法更新${reset}"
            fi
            ;;
        2)
            if $singbox_installed; then
                echo -e "${green_text}正在更新 Sing-box...${reset}"
                /watch/update_sb.sh
            else
                echo -e "${red}Sing-box 未安装，无法更新${reset}"
            fi
            ;;
        3)
            if $mihomo_installed; then
                echo -e "${green_text}正在更新 Mihomo...${reset}"
                /watch/update_mihomo.sh
            else
                echo -e "${red}Mihomo 未安装，无法更新${reset}"
            fi
            ;;
        5)
            echo -e "${green_text}正在更新所有已安装的组件...${reset}"
            if $mosdns_installed; then
                echo -e "${green_text}更新 MosDNS...${reset}"
                /watch/update_mosdns.sh
            fi
            if $singbox_installed; then
                echo -e "${green_text}更新 Sing-box...${reset}"
                /watch/update_sb.sh
            fi
            if $mihomo_installed; then
                echo -e "${green_text}更新 Mihomo...${reset}"
                /watch/update_mihomo.sh
            fi
            ;;
        0)
            echo -e "${yellow}返回主菜单${reset}"
            return 0
            ;;
        *)
            echo -e "${red}无效选择，返回主菜单${reset}"
            return 0
            ;;
    esac

    echo -e "${green_text}✅ 更新操作完成${reset}"
}

# 显示服务信息
display_service_info() {
    echo -e "${green_text}-------------------------------------------------${reset}"
        echo -e "${green_text}🎉 服务web访问路径：${reset}"
        echo -e "🌐 Mosdns 统计界面：${green_text}http://${local_ip}:9099/graphic${reset}"
        echo
        echo -e "📦 Supervisor 管理界面：${green_text}http://${local_ip}:9001${reset}"
        echo
        echo -e "🗂️  文件管理服务 Filebrowser：${green_text}http://${local_ip}:8080${reset}"
        echo
        echo -e "🕸️  Sing-box/Mihomo 面板 UI：${green_text}http://${local_ip}:9090/ui${reset}"
        echo -e "${green_text}-------------------------------------------------${reset}"
}

# 安装更新主服务
install_update_server() {
    update_system
    set_timezone

    echo -e "${green_text}-------------------------------------------------${reset}"
    log "请注意：本脚本支持 Debian/Ubuntu，安装前请确保系统未安装其他代理软件。参考：https://github.com/herozmy/StoreHouse/tree/latest"
    echo -e "当前机器地址:${green_text}${local_ip}${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"
    echo

    # 自动选择方案
    if [ "$core_name" = "sing-box" ]; then
        install_filebrower
        install_mosdns
        if [ "$singbox_core_type" = "yelnoo" ]; then
            singbox_y_install
        else
            singbox_r_install
        fi
        cp_config_files
        singbox_configure_files
        # 自动写入订阅链接
        if [ -n "$sub_urls" ]; then
            cd "$(dirname "$0")"
            # 判断是否有tag|url格式
            if echo "$sub_urls" | grep -q '|'; then
                python3 update_sub.py -v "$sub_urls"
            else
                # 没有tag，自动生成tag
                new_sub_urls=""
                index=1
                for url in $sub_urls; do
                    new_sub_urls+="✈️机场${index}|${url} "
                    index=$((index+1))
                done
                python3 update_sub.py -v "${new_sub_urls% }"
            fi
            log "订阅链接处理完成"
        fi
    else
        install_filebrower
        install_latest_yq
        install_mosdns
        install_mihomo
        cp_config_files
        mihomo_configure_files
        # 自动写入订阅链接
        if [ -n "$sub_urls" ]; then
            read -ra arr <<< "$sub_urls"
            edit_mihomo_proxy_providers "${arr[@]}"
            log "已写入订阅到 proxy-providers"
        fi

        log "准备写入 interface-name: $selected_interface 到 /mssb/mihomo/config.yaml"
        sed -i "s|^\s*interface-name:\s*eth0|interface-name: $selected_interface|" /mssb/mihomo/config.yaml
        if grep -q "interface-name: $selected_interface" /mssb/mihomo/config.yaml; then
            log "interface-name 已成功替换为: $selected_interface"
        else
            log "interface-name 替换失败，当前内容如下："
            grep interface-name /mssb/mihomo/config.yaml || log "未找到 interface-name 行"
        fi

        # 新增：icon_header替换逻辑
        if [ -n "$icon_header" ]; then
            if [[ "$icon_header" =~ ^https?:// ]]; then
                log "检测到icon_header，正在替换icon地址..."
                sed -i "s|https://raw.githubusercontent.com/Koolson/Qure/refs/heads/master/IconSet/Color|$icon_header|g" /mssb/mihomo/config.yaml
                log "icon地址已替换为: $icon_header"
            else
                log "icon_header格式不正确，必须以http://或https://开头，已跳过替换。"
            fi
        else
            log "未设置icon_header或格式不兼容，仅支持https://github.com/baozaodetudou/icons项目搭建的"
        fi
    fi
    check_ui
    install_tproxy
    reload_service

    # 定时任务自动化
    add_cron_jobs

    # 自动写入代理设备列表
    if [ -n "$client_ip_list" ]; then
        mkdir -p /mssb/mosdns
        echo "$client_ip_list" | tr ' ' '\n' > /mssb/mosdns/client_ip.txt
        log "已写入代理设备列表: $client_ip_list"
    fi

    # 检查并设置本地 DNS
    check_and_set_local_dns
    #check_ui
    sleep 1
    check_ui
    sleep 1
    supervisorctl restart all
    # 显示路由规则提示
    format_route_rules

    echo -e "${green_text}-------------------------------------------------${reset}"
    echo -e "${green_text}🎉 安装成功！以下是服务信息：${reset}"
    echo -e "🌐 Mosdns 统计界面：${green_text}http://${local_ip}:9099/graphic${reset}"
    echo
    echo -e "📦 Supervisor 管理界面：${green_text}http://${local_ip}:9001${reset}"
    echo -e "   - 用户名：${supervisor_user}"
    echo -e "   - 密码：${supervisor_pass}"
    echo
    echo -e "🗂️  文件管理服务 Filebrowser：${green_text}http://${local_ip}:8080${reset}"
    if [ "$fb_login_mode" = "noauth" ]; then
        echo -e "   - 无需登录"
    else
        echo -e "   - 用户名：admin"
        echo -e "   - 密码：admin123456789QAQ 或者自己手动设置，如不对请打开supervisor查看日志获取"
    fi
    echo
    echo -e "🕸️  Sing-box/Mihomo 面板 UI：${green_text}http://${local_ip}:9090/ui${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"

    # 创建全局 mssb 命令
    echo -e "\n${green_text}正在创建全局 mssb 命令...${reset}"
    create_mssb_command

    log "脚本执行完成。"
}

# ========== 环境变量管理函数 ==========
load_or_init_env() {
    local env_file="/mssb/mssb.env"
    mkdir -p /mssb
    if [ -f "$env_file" ]; then
        echo "检测到已有配置文件 $env_file"
        read -p "是否直接使用已有配置？(y/n): " use_env
        if [ "$use_env" = "y" ]; then
            source "$env_file"
            return
        fi
    else
        # 检查是否有备份
        local latest_backup=$(ls -t /mssb/backup/mssb.env.* 2>/dev/null | head -n1)
        if [ -n "$latest_backup" ]; then
            echo "未检测到当前配置，但发现有备份：$latest_backup"
            read -p "是否恢复该备份？(y/n): " restore_env_choice
            if [ "$restore_env_choice" = "y" ]; then
                cp "$latest_backup" "$env_file"
                source "$env_file"
                return
            fi
        fi
    fi
    # AMD64 v3 支持检测和配置
    echo -e "\n${green_text}=== AMD64 v3 指令集支持检测 ===${reset}"
    if check_amd64_v3_support; then
        echo -e "${green_text}✓ 检测到系统支持 AMD64 v3 指令集${reset}"
        echo -e "${yellow}启用 v3 优化可以提升性能，但需要较新的 CPU 支持${reset}"
        read -p "是否启用 AMD64 v3 优化？(y/n, 默认y): " enable_amd64v3
        enable_amd64v3=${enable_amd64v3:-y}
        if [ "$enable_amd64v3" = "y" ]; then
            amd64v3_enabled="true"
            echo -e "${green_text}✓ 已启用 AMD64 v3 优化${reset}"
        else
            amd64v3_enabled="false"
            echo -e "${yellow}已禁用 AMD64 v3 优化${reset}"
        fi
    else
        echo -e "${red}✗ 系统不支持 AMD64 v3 指令集，将使用标准版本${reset}"
        amd64v3_enabled="false"
    fi

    # 检查并选择网卡
    check_interfaces
    log "您选择的网卡是: $selected_interface"

    read -p "请选择安装方案 (1-Sing-box, 2-Mihomo): " core_choice
    if [ "$core_choice" = "1" ]; then
        core_name="sing-box"
        read -p "请选择Sing-box核心 (1-风佬R核心, 2-S佬Y核心): " sb_core
        singbox_core_type=$([ "$sb_core" = "1" ] && echo "reF1nd" || echo "yelnoo")
    else
        core_name="mihomo"
        singbox_core_type=""
    fi
    echo -e "\n${yellow}=== 运营商 DNS 配置 ===${reset}"
    echo -e "默认已设置第一、第二解析为阿里公共 DNS：${green_text}223.5.5.5${reset}"
    echo -e "当前第三解析配置的运营商 DNS 为：${green_text}114.114.114.114${reset}"
    echo -e "建议修改为您所在运营商的 DNS 服务器地址，否则可能影响解析速度"
    echo -e "常见运营商 DNS：可以参考 https://ipw.cn/doc/else/dns.html"
    echo -e "  阿里：223.5.5.5, 223.6.6.6"
    echo -e "  腾讯：119.29.29.29, 119.28.28.28"
    echo -e "${green_text}------------------------${reset}"
    read -p "请输入运营商DNS地址（默认119.29.29.29）: " dns_addr
    dns_addr=${dns_addr:-119.29.29.29}
    read -p "Supervisor用户名（留空不需要登录）: " supervisor_user
    # 不再设置默认值
    read -p "Supervisor密码（留空不需要登录）: " supervisor_pass
    # 不再设置默认值
    read -p "Filebrowser登录方式（1-密码(admin/admin123456789QAQ) 2-免密，默认1）: " fb_login
    fb_login_mode=$([ "$fb_login" = "2" ] && echo "noauth" || echo "auth")
    if [ "$fb_login_mode" = "auth" ]; then
        read -p "请输入Filebrowser密码【不输入默认为admin123456789QAQ 】（必须16位以上,不然会失败，然后自动生成密码需要打开supervisor查看日志获取）: " fb_pass
        fb_pass=${fb_pass:-admin123456789QAQ}
    fi

    # 订阅链接
    echo -e "${yellow}机场订阅支持两种格式：${reset}"
    echo -e "  1. 只输入订阅链接（多个用空格分隔）：https://a.com https://b.com"
    echo -e "  2. 输入tag和链接（多个用空格分隔）：机场A|https://a.com 机场B|https://b.com"
    echo -e "     （tag可自定义，显示在面板上）"
    read -p "请输入订阅链接: " sub_urls

    # 新增icon_header字段
    echo -e "\n${green_text}=== 图标本地化设置（可选） ===${reset}"
    echo -e "如需本地化图标加速，可先参考 https://github.com/baozaodetudou/icons 部署本地服务"
    echo -e "格式示例：http://baidu.com:5000/images/header（留空则不替换, 后边不要带/）"
    read -p "请输入icon_header（留空默认不替换）: " icon_header
    icon_header=${icon_header:-}

    # 定时任务细分
    read -p "是否启用 MosDNS 自动更新？(y/n, 默认y): " enable_mosdns_cron
    enable_mosdns_cron=${enable_mosdns_cron:-y}
    read -p "是否启用singbo/mihomo核心自动更新？(y/n, 默认y): " enable_core_cron
    enable_core_cron=${enable_core_cron:-y}

    # 代理设备列表配置
    echo -e "\n${green_text}=== Mosdns代理设备列表配置 ===${reset}"
    echo -e "1. 扫描局域网设备并选择"
    echo -e "2. 手动输入（多个用空格分隔）"
    echo -e "${green_text}------------------------${reset}"
    read -p "请选择代理设备配置方式 (1/2): " device_choice
    if [ "$device_choice" = "1" ]; then
        scan_lan_devices
        # scan_lan_devices 会将结果写入全局变量 scanned_ip_list
        client_ip_list="$scanned_ip_list"
    else
        read -p "请输入需要代理的设备IP（多个用空格分隔）: " client_ip_list
    fi

    # 安装/更新模式（分功能）
    read -p "安装/更新 Sing-box 时是否自动更新？(y/n, 默认y): " install_update_mode_singbox
    install_update_mode_singbox=${install_update_mode_singbox:-y}
    read -p "安装/更新 MosDNS 时是否自动更新？(y/n, 默认y): " install_update_mode_mosdns
    install_update_mode_mosdns=${install_update_mode_mosdns:-y}
    read -p "安装/更新 Filebrowser 时是否自动更新？(y/n, 默认y): " install_update_mode_filebrowser
    install_update_mode_filebrowser=${install_update_mode_filebrowser:-y}
    read -p "安装/更新 Mihomo 时是否自动更新？(y/n, 默认y): " install_update_mode_mihomo
    install_update_mode_mihomo=${install_update_mode_mihomo:-y}

    # UI自动更新模式
    read -p "UI 是否自动更新？(y/n, 默认y): " update_ui_mode
    update_ui_mode=${update_ui_mode:-y}

    # DNS设置
    read -p "安装完成后本机DNS设置为（默认127.0.0.1）: " dns_after_install
    dns_after_install=${dns_after_install:-127.0.0.1}
    read -p "卸载后本机DNS恢复为（默认223.5.5.5）: " dns_after_uninstall
    dns_after_uninstall=${dns_after_uninstall:-223.5.5.5}

    # 保存到env文件（带注释）
    cat > "$env_file" <<EOF
# 是否启用AMD64 v3优化（true/false）
amd64v3_enabled=$amd64v3_enabled
# 选中的物理网卡
selected_interface=$selected_interface
# 代理核心名称（sing-box或mihomo）
core_name=$core_name
# sing-box核心类型（reF1nd或yelnoo）
singbox_core_type=$singbox_core_type
# 运营商DNS地址
dns_addr=$dns_addr
# Supervisor用户名
supervisor_user=$supervisor_user
# Supervisor密码
supervisor_pass=$supervisor_pass
# Filebrowser登录方式（auth=密码，noauth=免密）
fb_login_mode=$fb_login_mode
# 机场订阅链接
sub_urls="$sub_urls"
# 是否启用MosDNS自动更新（y/n）
enable_mosdns_cron=$enable_mosdns_cron
# 是否启用核心自动更新（y/n）
enable_core_cron=$enable_core_cron
# 需要代理的设备IP列表
client_ip_list="$client_ip_list"
# 安装/更新Sing-box时是否自动更新（y/n）
install_update_mode_singbox=$install_update_mode_singbox
# 安装/更新MosDNS时是否自动更新（y/n）
install_update_mode_mosdns=$install_update_mode_mosdns
# 安装/更新Filebrowser时是否自动更新（y/n）
install_update_mode_filebrowser=$install_update_mode_filebrowser
# 安装/更新Mihomo时是否自动更新（y/n）
install_update_mode_mihomo=$install_update_mode_mihomo
# UI是否自动更新（y/n）
update_ui_mode=$update_ui_mode
# 安装完成后本机DNS设置
dns_after_install=$dns_after_install
# 卸载后本机DNS恢复
dns_after_uninstall=$dns_after_uninstall
# 用来替换mihomo配置文件里icon的请求，默认为空，提示页面可以安装https://github.com/baozaodetudou/icons进行本地化访问
icon_header=$icon_header
EOF
    source "$env_file"
}

source_env() {
    local env_file="/mssb/mssb.env"
    if [ -f "$env_file" ]; then
        source "$env_file"
        log "已加载环境变量文件 $env_file"
    else
        log "未找到环境变量文件 $env_file，选择1进行安装的时候会首次初始化。"
    fi
}

backup_env() {
    echo -e "${green_text}备份env到/mssb/backup ${reset}"
    # 备份env文件
    mkdir -p /mssb/backup
    cp /mssb/mssb.env /mssb/backup/mssb.env.$(date +%Y%m%d-%H%M%S)
    # 只保留最近7份备份
    local backups=( $(ls -1t /mssb/backup/mssb.env.* 2>/dev/null) )
    local count=${#backups[@]}
    if [ $count -gt 7 ]; then
        for ((i=7; i<$count; i++)); do
            rm -f "${backups[$i]}"
        done
    fi
    echo -e "${green_text}-------------------------------------------------${reset}"
}
# ========== END 环境变量管理 ==========

# ========== 主流程重构 ==========
main() {
    source_env
    # 主菜单
    echo -e "${green_text}------------------------⚠️注意：请使用 root 用户安装！！！-------------------------${reset}"
    echo -e "${green_text}⚠️注意：本脚本支持 Debian/Ubuntu，安装前请确保系统未安装其他代理软件。${reset}"
    echo -e "${green_text}使用前详细阅读 https://github.com/baozaodetudou/mssb/blob/main/README.md ${reset}"
    echo -e "${green_text}脚本参考: https://github.com/herozmy/StoreHouse/tree/latest ${reset}"
    echo -e "${red}⚠️注意：服务管理请使用脚本管理，不要单独停用某个服务会导致转发失败cpu暴涨 ${reset}"
    echo -e "当前机器地址:${green_text}${local_ip}${reset}"
    echo -e "${green_text}请选择操作：${reset}"
    echo -e "${green_text}1) 安装/更新代理转发服务${reset}"
    echo -e "${red}2) 停止所有转发服务${reset}"
    echo -e "${red}3) 停止所有服务并卸载 + 删除所有相关文件（重要文件自动备份）${reset}"
    echo -e "${green_text}4) 启用所有服务${reset}"
    echo -e "${green_text}5) 修改服务配置${reset}"
    echo -e "${green_text}6) 备份自定义的设置${reset}"
    echo -e "${green_text}7) 扫描局域网设备并配置mosdns代理列表${reset}"
    echo -e "${green_text}8) 显示服务信息${reset}"
    echo -e "${green_text}9) 显示路由规则提示${reset}"
    echo -e "${green_text}10) 创建全局 mssb 命令${reset}"
    echo -e "${red}11) 删除全局 mssb 命令${reset}"
    echo -e "${green_text}12) 更新项目${reset}"
    echo -e "${green_text}13) 更新内核版本(mosdns/singbox/mihomo)${reset}"
    echo -e "${green_text}14) 检查CPU指令集和v3支持${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "请输入选项 (1/2/3/4/5/6/7/8/9/10/11/12/13/14/00): " main_choice

    case "$main_choice" in
        2)
            stop_all_services
            # 检查 DNS 设置
            uninstall_dns_settings
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        3)
            uninstall_all_services
            # 检查 DNS 设置
            uninstall_dns_settings
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        4)
            start_all_services
            # 检查并设置本地 DNS
            check_and_set_local_dns
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        5)
            # 修改服务配置
            modify_service_config
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        6)
            # 备份所有重要文件
            backup_env
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        7)
            echo -e "${green_text}扫描局域网设备并配置代理列表${reset}"
            # 扫描局域网设备
            scan_lan_devices
            echo -e "${green_text}-------------------------------------------------${reset}"
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        8)
            echo -e "${green_text}显示服务信息${reset}"
            display_system_status
            display_service_info
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        9)
            echo -e "${green_text}显示路由规则提示${reset}"
            format_route_rules
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        10)
            echo -e "${green_text}创建全局 mssb 命令${reset}"
            create_mssb_command
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        11)
            echo -e "${red}删除全局 mssb 命令${reset}"
            remove_mssb_command
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        12)
            echo -e "${green_text}更新项目${reset}"
            update_project
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        13)
            echo -e "${green_text}手动更新内核版本(mosdns/singbox/mihomo)${reset}"
            update_cores_menu
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        14)
            echo -e "${green_text}检查CPU指令集和v3支持${reset}"
            check_cpu_instructions
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        00)
            echo -e "${green_text}退出程序${reset}"
            exit 0
            ;;
        1)
            echo -e "${green_text}✅ 继续安装/更新代理服务...${reset}"
            # 备份env
            backup_env
            # 加载/初始化环境变量
            load_or_init_env
            # 开始安装
            install_update_server
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        *)
            echo -e "${red}无效选项，请重新选择或输入 00 或者 快捷键Ctrl+C 退出${reset}"
            main
            ;;
    esac

}
# 版本提示
echo -e "${yellow}=================================================${reset}"
echo -e "${yellow}⚠️ 重要提示：${reset}"
echo -e "${yellow}2025.6.23 之前的是 v1 版本，现在是 v2 版本。${reset}"
echo -e "${yellow}如果你当前使用的是 v1 版本，建议使用3先停止并删除/mssb文件后重新安装本脚本。${reset}"
echo -e "${yellow}=================================================${reset}"
update_project
main
