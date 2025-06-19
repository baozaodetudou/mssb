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
    echo "[$(date +"%F %T")] $1"
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

# 设置时区
set_timezone() {
    log "设置时区为Asia/Shanghai"
    if ! timedatectl set-timezone Asia/Shanghai; then
        log "${red}时区设置失败！退出脚本！${reset}"
        exit 1
    fi
    log "时区设置成功"
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

# 安装mosdns
install_mosdns() {
    # 检查是否已安装 MosDNS
    if [ -f "/usr/local/bin/mosdns" ]; then
        log "检测到已安装的 MosDNS"

        # 获取当前版本信息
        current_version=$(/usr/local/bin/mosdns version 2>/dev/null | head -n1 | awk '{print $2}' || echo "未知版本")
        log "当前安装的版本：$current_version"

        echo -e "\n${green_text}=== MosDNS 安装选项 ===${reset}"
        echo -e "1. 跳过下载，使用现有版本"
        echo -e "2. 下载最新版本并更新"
        echo -e "${green_text}------------------------${reset}"

        read -p "请选择操作 (1/2): " mosdns_choice

        case "$mosdns_choice" in
            1)
                log "跳过 MosDNS 下载，使用现有版本：$current_version"
                return 0
                ;;
            2)
                log "选择更新 MosDNS 到最新版本"
                ;;
            *)
                log "无效选择，默认跳过下载使用现有版本"
                return 0
                ;;
        esac
    fi

    # 下载并安装 MosDNS
    log "开始下载 MosDNS..."
    arch=$(detect_architecture)
    log "系统架构是：$arch"
#  LATEST_MOSDNS_VERSION=$(curl -sL -o /dev/null -w %{url_effective} https://github.com/IrineSistiana/mosdns/releases/latest | awk -F '/' '{print $NF}')
#  MOSDNS_URL="https://github.com/IrineSistiana/mosdns/releases/download/${LATEST_MOSDNS_VERSION}/mosdns-linux-$arch.zip"
    MOSDNS_URL="https://github.com/herozmy/StoreHouse/releases/download/mosdns/mosdns-linux-$arch.zip"

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

        echo -e "\n${green_text}=== Filebrowser 安装选项 ===${reset}"
        echo -e "1. 跳过下载，使用现有版本"
        echo -e "2. 下载最新版本并更新"
        echo -e "${green_text}------------------------${reset}"

        read -p "请选择操作 (1/2): " filebrowser_choice

        case "$filebrowser_choice" in
            1)
                log "跳过 Filebrowser 下载，使用现有版本：$current_version"
                return 0
                ;;
            2)
                log "选择更新 Filebrowser 到最新版本"
                ;;
            *)
                log "无效选择，默认跳过下载使用现有版本"
                return 0
                ;;
        esac
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

# 自动检查并恢复配置文件（无用户交互）
auto_restore_config() {
    local config_type=$1
    local config_path=$2
    local backup_dir="/mssb/backup"

    if [ -d "$backup_dir" ]; then
        case "$config_type" in
            "sing-box")
                # 获取当前核心类型
                detect_singbox_info

                # 根据核心类型选择对应的备份文件
                if [[ "$core_type" == "sing-box-reF1nd" ]]; then
                    latest_backup=$(ls -t "$backup_dir"/sing-box-r-config-*.json 2>/dev/null | head -n1)
                else
                    latest_backup=$(ls -t "$backup_dir"/sing-box-y-config-*.json 2>/dev/null | head -n1)
                fi

                if [ -n "$latest_backup" ]; then
                    log "发现 sing-box 的备份配置文件：$latest_backup"
                    mkdir -p "$(dirname "$config_path")"
                    cp "$latest_backup" "$config_path"
                    log "sing-box 配置文件已从备份自动恢复"
                    return 0
                fi
                ;;
            "mihomo")
                latest_backup=$(ls -t "$backup_dir"/mihomo-config-*.yaml 2>/dev/null | head -n1)

                if [ -n "$latest_backup" ]; then
                    log "发现 mihomo 的备份配置文件：$latest_backup"
                    mkdir -p "$(dirname "$config_path")"
                    cp "$latest_backup" "$config_path"
                    log "mihomo 配置文件已从备份自动恢复"
                    return 0
                fi
                ;;
            "mosdns")
                # mosdns 需要恢复多个文件
                local mosdns_dir="/mssb/mosdns"
                local restored_count=0

                # 恢复 client_ip.txt
                latest_backup=$(ls -t "$backup_dir"/mosdns-client_ip-*.txt 2>/dev/null | head -n1)
                if [ -n "$latest_backup" ]; then
                    mkdir -p "$mosdns_dir"
                    cp "$latest_backup" "$mosdns_dir/client_ip.txt"
                    log "已恢复 mosdns client_ip.txt"
                    ((restored_count++))
                fi

                # 恢复 mywhitelist.txt
                latest_backup=$(ls -t "$backup_dir"/mosdns-mywhitelist-*.txt 2>/dev/null | head -n1)
                if [ -n "$latest_backup" ]; then
                    mkdir -p "$mosdns_dir"
                    cp "$latest_backup" "$mosdns_dir/mywhitelist.txt"
                    log "已恢复 mosdns mywhitelist.txt"
                    ((restored_count++))
                fi

                if [ $restored_count -gt 0 ]; then
                    log "mosdns 配置文件已从备份自动恢复（共恢复 $restored_count 个文件）"
                    return 0
                fi
                ;;
        esac
    fi
    return 1
}

# 备份配置文件
backup_config() {
    local config_type=$1
    local config_path=$2
    local backup_dir="/mssb/backup"

    # 创建备份目录
    mkdir -p "$backup_dir"

    case "$config_type" in
        "sing-box")
            # 检查配置文件是否存在
            if [ ! -f "$config_path" ]; then
                log "sing-box 配置文件不存在，跳过备份"
                return 1
            fi

            # 获取当前核心类型
            detect_singbox_info

            if [[ "$core_type" == "sing-box-reF1nd" ]]; then
                backup_file="$backup_dir/sing-box-r-config-$(date +%Y%m%d-%H%M%S).json"
            else
                backup_file="$backup_dir/sing-box-y-config-$(date +%Y%m%d-%H%M%S).json"
            fi

            # 执行备份
            if cp "$config_path" "$backup_file"; then
                log "sing-box 配置文件已备份到：$backup_file"
                return 0
            else
                log "sing-box 配置文件备份失败"
                return 1
            fi
            ;;
        "mihomo")
            # 检查配置文件是否存在
            if [ ! -f "$config_path" ]; then
                log "mihomo 配置文件不存在，跳过备份"
                return 1
            fi

            backup_file="$backup_dir/mihomo-config-$(date +%Y%m%d-%H%M%S).yaml"

            # 执行备份
            if cp "$config_path" "$backup_file"; then
                log "mihomo 配置文件已备份到：$backup_file"
                return 0
            else
                log "mihomo 配置文件备份失败"
                return 1
            fi
            ;;
        "mosdns")
            # mosdns 需要备份多个文件
            local mosdns_dir="/mssb/mosdns"
            local timestamp=$(date +%Y%m%d-%H%M%S)
            local backup_count=0
            # 备份 client_ip.txt
            if [ -f "$mosdns_dir/client_ip.txt" ]; then
                backup_file="$backup_dir/mosdns-client_ip-$timestamp.txt"
                if cp "$mosdns_dir/client_ip.txt" "$backup_file"; then
                    log "mosdns client_ip.txt 已备份到：$backup_file"
                    ((backup_count++))
                fi
            fi

            # 备份 mywhitelist.txt
            if [ -f "$mosdns_dir/mywhitelist.txt" ]; then
                backup_file="$backup_dir/mosdns-mywhitelist-$timestamp.txt"
                if cp "$mosdns_dir/mywhitelist.txt" "$backup_file"; then
                    log "mosdns mywhitelist.txt 已备份到：$backup_file"
                    ((backup_count++))
                fi
            fi

            if [ $backup_count -gt 0 ]; then
                log "mosdns 配置文件备份完成（共备份 $backup_count 个文件）"
                return 0
            else
                log "mosdns 没有配置文件需要备份"
                return 1
            fi
            ;;
        *)
            log "未知的配置类型：$config_type"
            return 1
            ;;
    esac
}

# 备份所有重要文件
backup_all_config() {
    backup_config "sing-box" "/mssb/sing-box/config.json"
    backup_config "mihomo" "/mssb/mihomo/config.yaml"
    backup_config "mosdns" ""
}

# 检查并恢复配置文件（保留原有交互功能，用于其他地方）
check_and_restore_config() {
    local config_type=$1
    local config_path=$2
    local backup_dir="/mssb/backup"

    if [ -d "$backup_dir" ]; then
        case "$config_type" in
            "sing-box")
                # 获取当前版本和核心类型信息
                detect_singbox_info

                # 根据核心类型选择对应的备份文件
                if [[ "$core_type" == "sing-box-reF1nd" ]]; then
                    latest_backup=$(ls -t "$backup_dir"/sing-box-r-config-*.json 2>/dev/null | head -n1)
                else
                    latest_backup=$(ls -t "$backup_dir"/sing-box-y-config-*.json 2>/dev/null | head -n1)
                fi
                if [ -n "$latest_backup" ]; then
                    echo -e "${green_text}发现 sing-box 的备份配置文件：${reset}"
                    echo -e "备份文件：$latest_backup"
                    read -p "是否恢复此备份？(y/n): " restore_choice
                    if [ "$restore_choice" = "y" ]; then
                        mkdir -p "$(dirname "$config_path")"
                        cp "$latest_backup" "$config_path"
                        log "sing-box 配置文件已从备份恢复"
                        return 0
                    fi
                fi
                ;;
            "mihomo")
                latest_backup=$(ls -t "$backup_dir"/mihomo-config-*.yaml 2>/dev/null | head -n1)
                if [ -n "$latest_backup" ]; then
                    echo -e "${green_text}发现 mihomo 的备份配置文件：${reset}"
                    echo -e "备份文件：$latest_backup"
                    read -p "是否恢复此备份？(y/n): " restore_choice
                    if [ "$restore_choice" = "y" ]; then
                        mkdir -p "$(dirname "$config_path")"
                        cp "$latest_backup" "$config_path"
                        log "mihomo 配置文件已从备份恢复"
                        return 0
                    fi
                fi
                ;;
            "mosdns")
                # mosdns 需要检查多个备份文件
                local mosdns_dir="/mssb/mosdns"
                local proxy_backup=$(ls -t "$backup_dir"/mosdns-client_ip-*.txt 2>/dev/null | head -n1)
                local whitelist_backup=$(ls -t "$backup_dir"/mosdns-mywhitelist-*.txt 2>/dev/null | head -n1)

                if [ -n "$proxy_backup" ] || [ -n "$whitelist_backup" ]; then
                    echo -e "${green_text}发现 mosdns 的备份配置文件：${reset}"
                    [ -n "$proxy_backup" ] && echo -e "client_ip.txt: $proxy_backup"
                    [ -n "$whitelist_backup" ] && echo -e "mywhitelist.txt: $whitelist_backup"

                    read -p "是否恢复这些备份？(y/n): " restore_choice
                    if [ "$restore_choice" = "y" ]; then
                        mkdir -p "$mosdns_dir"
                        local restored_count=0

                        if [ -n "$proxy_backup" ]; then
                            cp "$proxy_backup" "$mosdns_dir/client_ip.txt"
                            log "已恢复 mosdns client_ip.txt"
                            ((restored_count++))
                        fi

                        if [ -n "$whitelist_backup" ]; then
                            cp "$whitelist_backup" "$mosdns_dir/mywhitelist.txt"
                            log "已恢复 mosdns mywhitelist.txt"
                            ((restored_count++))
                        fi

                        log "mosdns 配置文件已从备份恢复（共恢复 $restored_count 个文件）"
                        return 0
                    fi
                fi
                ;;
        esac

        # 对于 sing-box 和 mihomo 的单文件恢复
        if [ "$config_type" != "mosdns" ] && [ -n "$latest_backup" ]; then
            echo -e "${green_text}发现 $config_type 的备份配置文件：${reset}"
            echo -e "备份文件：$latest_backup"
            read -p "是否恢复此备份？(y/n): " restore_choice
            if [ "$restore_choice" = "y" ]; then
                mkdir -p "$(dirname "$config_path")"
                cp "$latest_backup" "$config_path"
                log "$config_type 配置文件已从备份恢复"
                return 0
            fi
        fi
    fi
    return 1
}

# singbox用户自定义设置（用于配置设置）
singbox_customize_settings() {
    echo -e "\n${green_text}=== Sing-box 配置设置 ===${reset}"
    echo -e "1. 检查是否有备份配置"
    echo -e "2. 生成新配置"
    echo -e "3. 手动配置"
    echo -e "${green_text}------------------------${reset}"
    
    read -p "请选择配置方式 (1/2/3): " config_choice

    case "$config_choice" in
        1)
            echo -e "${yellow}正在检查备份配置...${reset}"
            if check_and_restore_config "sing-box" "/mssb/sing-box/config.json"; then
                return
            else
                echo -e "${red}未找到备份配置，请选择其他配置方式${reset}"
                singbox_customize_settings
                return
            fi
            ;;
        2)
            echo -e "\n${green_text}=== 生成新配置 ===${reset}"
            echo -e "此选项将根据订阅链接自动生成配置"
            echo -e "注意："
            echo -e "1. 需要提供有效的订阅链接"
            echo -e "2. 多个订阅链接请用空格分隔"
            echo -e "3. 输入 q 可返回上一步"
            echo -e "${green_text}------------------------${reset}"
            
            while true; do
                read -p "请输入订阅链接（多个用空格分隔，输入 q 退出）： " suburls

                if [[ "$suburls" == "q" ]]; then
                    log "已取消自动生成配置，请手动编辑 /mssb/sing-box/config.json"
                    break
                fi

                valid=true
                for url in $suburls; do
                    if [[ $url != http* ]]; then
                        echo -e "${red}❌ 无效的订阅链接：$url（应以 http 开头）${reset}"
                        valid=false
                        break
                    fi
                done

                if [ "$valid" = true ]; then
                    echo -e "${green_text}✅ 已设置订阅链接地址：$suburls${reset}"
                    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                    cd "$script_dir"
                    python3 update_sub.py -v "$suburls"
                    log "订阅链接处理完成"
                    break
                else
                    log "部分订阅链接不符合要求，请重新输入"
                fi
            done
            ;;
        3)
            echo -e "\n${yellow}请手动编辑 /mssb/sing-box/config.json${reset}"
            echo -e "配置文件位置：/mssb/sing-box/config.json"
            echo -e "编辑完成后请确保配置正确"
            ;;
        *)
            echo -e "${red}无效选择，请重新选择${reset}"
            singbox_customize_settings
            ;;
    esac
}

# 安装mihomo
install_mihomo() {
    # 检查是否已安装 Mihomo
    if [ -f "/usr/local/bin/mihomo" ]; then
        log "检测到已安装的 Mihomo"

        # 获取当前版本信息
        current_version=$(/usr/local/bin/mihomo -v 2>/dev/null | head -n1 | awk '{print $2}' || echo "未知版本")
        log "当前安装的版本：$current_version"

        echo -e "\n${green_text}=== Mihomo 安装选项 ===${reset}"
        echo -e "1. 跳过下载，使用现有版本"
        echo -e "2. 下载最新版本并更新"
        echo -e "${green_text}------------------------${reset}"

        read -p "请选择操作 (1/2): " mihomo_choice

        case "$mihomo_choice" in
            1)
                log "跳过 Mihomo 下载，使用现有版本：$current_version"
                return 0
                ;;
            2)
                log "选择更新 Mihomo 到最新版本"
                ;;
            *)
                log "无效选择，默认跳过下载使用现有版本"
                return 0
                ;;
        esac
    fi

    # 下载并安装 Mihomo
    arch=$(detect_architecture)
    download_url="https://github.com/herozmy/StoreHouse/releases/download/mihomo/mihomo-meta-linux-${arch}.tar.gz"
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

# mihomo用户自定义设置
mihomo_customize_settings() {
    echo -e "\n${green_text}=== Mihomo 配置设置 ===${reset}"
    echo -e "1. 检查是否有备份配置"
    echo -e "2. 生成新配置"
    echo -e "3. 手动配置"
    echo -e "${green_text}------------------------${reset}"
    
    read -p "请选择配置方式 (1/2/3): " config_choice
    
    case "$config_choice" in
        1)
            echo -e "${yellow}正在检查备份配置...${reset}"
            if check_and_restore_config "mihomo" "/mssb/mihomo/config.yaml"; then
                return
            else
                echo -e "${red}未找到备份配置，请选择其他配置方式${reset}"
                mihomo_customize_settings
                return
            fi
            ;;
        2)
            echo -e "\n${green_text}=== 生成新配置 ===${reset}"
            echo -e "此选项将根据订阅链接自动生成配置"
            echo -e "注意："
            echo -e "1. 需要提供有效的订阅链接"
            echo -e "2. mihomo模式暂时只支持单个订阅链接"
            echo -e "3. 输入 q 可返回上一步"
            echo -e "${green_text}------------------------${reset}"
            
            while true; do
                read -p "请输入订阅链接（输入 q 返回上一步）: " suburl
                if [[ "$suburl" == "q" ]]; then
                    log "已取消自动生成配置，请手动编辑 /mssb/mihomo/config.yaml"
                    break
                elif [[ -n "$suburl" ]]; then
                    if [[ $suburl != http* ]]; then
                        echo -e "${red}❌ 无效的订阅链接：$suburl（应以 http 开头）${reset}"
                        continue
                    fi
                    escaped_url=$(printf '%s\n' "$suburl" | sed 's/[&/\]/\\&/g')
                    sed -i "s|url: '机场订阅'|url: '$escaped_url'|" /mssb/mihomo/config.yaml
                    sed -i "s|interface-name: eth0|interface-name: $selected_interface|" /mssb/mihomo/config.yaml
                    echo -e "${green_text}✅ 订阅链接已写入${reset}"
                    break
                else
                    echo -e "${red}订阅链接不能为空，请重新输入或输入 q 退出${reset}"
                fi
            done
            ;;
        3)
            echo -e "\n${yellow}请手动编辑 /mssb/mihomo/config.yaml${reset}"
            echo -e "配置文件位置：/mssb/mihomo/config.yaml"
            echo -e "编辑完成后请确保配置正确"
            ;;
        *)
            echo -e "${red}无效选择，请重新选择${reset}"
            mihomo_customize_settings
            ;;
    esac
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
      read -p "检测到已有 UI，是否更新？(y/n): " update_ui
      if [[ "$update_ui" == "y" || "$update_ui" == "Y" ]]; then
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

        # 下载成功，删除现有UI（如果存在）
        if [ -d "$ui_path" ]; then
            echo "删除现有 UI..."
            rm -rf "$ui_path"
        fi

        # 创建目标目录
        mkdir -p "$(dirname "$ui_path")"

        # 移动新UI到目标位置
        if mv "$temp_ui_path" "$ui_path"; then
            echo -e "UI 更新${green_text}成功${reset}。"
        else
            echo -e "${red}UI 替换失败${reset}"
            echo "请检查磁盘空间和权限"
        fi

        # 清理临时文件
        rm -rf "$temp_ui_path" 2>/dev/null
    else
        echo -e "${red}UI 源码下载失败${reset}，保持现有 UI 不变"
        echo "请检查网络连接或手动下载源码并解压至 $ui_path"
        echo "下载地址: https://github.com/Zephyruso/zashboard.git"

        # 清理可能存在的临时文件
        rm -rf "$temp_ui_path" 2>/dev/null
        return 1
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
    check_interfaces
    # 根据核心类型选择不同的防火墙模板
    local nft_template=""
    if [ "$core_name" == "mihomo" ]; then
        nft_template="ntf/nft-tproxy.conf"
    else
        nft_template="ntf/nft-tproxy-redirect.conf"
    fi

    # 复制并替换模板中的网卡名
    cp "$nft_template" "/etc/nftables.conf"
    sed -i "s/eth0/${selected_interface}/g" "/etc/nftables.conf"

    echo -e "${green_text}nftables规则写入完成${reset}"
    sleep 1
    echo "清空 nftalbes 规则"
    nft flush ruleset
    sleep 1
    echo "新规则生效"
    sleep 1
    nft -f /etc/nftables.conf
    echo "启用相关服务"
    systemctl enable --now nftables
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
    interfaces=$(ip -o link show | awk -F': ' '{print $2}')
    # 输出物理网卡名称
    for interface in $interfaces; do
        if [[ $interface =~ ^(en|eth).* ]]; then
            interface_name=$(echo "$interface" | awk -F'@' '{print $1}')
            echo "您的网卡是：$interface_name"
        fi
    done
    read -p "脚本自行检测的是否是您要的网卡？(y/n): " confirm_interface
    if [ "$confirm_interface" = "y" ]; then
        selected_interface="$interface_name"
        log "您选择的网卡是: $selected_interface"
    elif [ "$confirm_interface" = "n" ]; then
        read -p "请自行输入您的网卡名称: " selected_interface
        log "您输入的网卡名称是: $selected_interface"
    else
        log "默认y继续进行"
        selected_interface="$interface_name"
        log "您选择的网卡是: $selected_interface"
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
    log "开始处理 mosdns 配置文件..."
    #CONFIG_YAML="/mssb/mosdns/config.yaml"
    forward_local_yaml="/mssb/mosdns/sub_config/forward_local.yaml"
    echo -e "\n${yellow}=== 运营商 DNS 配置 ===${reset}"
    echo -e "默认已设置第一、第二解析为阿里公共 DNS：${green_text}223.5.5.5${reset}"
    echo -e "当前第三解析配置的运营商 DNS 为：${green_text}221.130.33.60${reset}"
    echo -e "建议修改为您所在运营商的 DNS 服务器地址，否则可能影响解析速度"
    echo -e "常见运营商 DNS：可以参考 https://ipw.cn/doc/else/dns.html"
    echo -e "  阿里：223.5.5.5, 223.6.6.6"
    echo -e "  腾讯：119.29.29.29, 119.28.28.28"
    echo -e "${green_text}------------------------${reset}"

    read -p "请输入您的运营商 DNS 地址（直接回车使用腾讯作为第三解析 119.29.29.29）：" dns_addr
    if [ -n "$dns_addr" ]; then
        # 验证输入的 IP 地址格式
        if [[ $dns_addr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # 替换配置文件中的 DNS 地址
            sed -i "s/addr: \"221.130.33.60\"/addr: \"$dns_addr\"/" "$forward_local_yaml"
            log "已更新运营商 DNS 地址为：$dns_addr"
        else
            log "输入的 DNS 地址格式不正确，将使用默认值 119.29.29.29"
            sed -i "s/addr: \"221.130.33.60\"/addr: \"119.29.29.29\"/" "$forward_local_yaml"
        fi
    else
        log "使用默认 DNS 地址：119.29.29.29"
        sed -i "s/addr: \"221.130.33.60\"/addr: \"119.29.29.29\"/" "$forward_local_yaml"
    fi
}

# 复制 mssb/mosdns fb 配置文件
cp_config_files() {
    log "复制 mssb/fb 目录..."
    check_and_copy_folder "fb"

    # 复制 mssb/mosdns 目录
    if [ -d "/mssb/mosdns" ]; then
        log "/mssb/mosdns 文件夹已存在，保留 client_ip.txt 和 mywhitelist.txt，替换其他文件。"
        # 备份需要保留的文件
        if [ -f "/mssb/mosdns/client_ip.txt" ]; then
            cp "/mssb/mosdns/client_ip.txt" "/tmp/client_ip.txt.bak"
        fi
        if [ -f "/mssb/mosdns/mywhitelist.txt" ]; then
            cp "/mssb/mosdns/mywhitelist.txt" "/tmp/mywhitelist.txt.bak"
        fi

        # 删除目标目录中的所有内容（除了备份的文件）
        find /mssb/mosdns -mindepth 1 -not -path "/mssb/mosdns/client_ip.txt" -not -path "/mssb/mosdns/mywhitelist.txt" -exec rm -rf {} \; 2>/dev/null || log "清理 /mssb/mosdns 目录时出现警告，继续执行..."

        # 复制新的文件
        if cp -r mssb/mosdns/* /mssb/mosdns/ 2>/dev/null; then
            log "成功复制 mssb/mosdns 目录内容"
        else
            log "警告：复制 mssb/mosdns 目录内容时出现错误，部分文件可能未成功复制"
        fi

        # 恢复备份的文件（如果备份文件存在）
        if [ -f "/tmp/client_ip.txt.bak" ]; then
            cp "/tmp/client_ip.txt.bak" "/mssb/mosdns/client_ip.txt" || log "警告：恢复 client_ip.txt 失败"
            rm "/tmp/client_ip.txt.bak" 2>/dev/null
        fi
        if [ -f "/tmp/mywhitelist.txt.bak" ]; then
            cp "/tmp/mywhitelist.txt.bak" "/mssb/mosdns/mywhitelist.txt" || log "警告：恢复 mywhitelist.txt 失败"
            rm "/tmp/mywhitelist.txt.bak" 2>/dev/null
        fi

        log "已更新 /mssb/mosdns 目录（保留了 client_ip.txt 和 mywhitelist.txt）"
    else
        if cp -r "mssb/mosdns" "/mssb/" 2>/dev/null; then
            log "成功复制 mssb/mosdns 目录到 /mssb/"
        else
            log "警告：复制 mssb/mosdns 目录失败，将尝试继续执行"
        fi
    fi

    # 检查并恢复 mosdns 配置
    echo -e "\n${green_text}=== MosDNS 配置设置 ===${reset}"
    echo -e "1. 检查是否有备份配置"
    echo -e "2. 使用默认配置"
    echo -e "${green_text}------------------------${reset}"

    read -p "请选择配置方式 (1/2): " mosdns_choice
    
    case "$mosdns_choice" in
        1)
            # 检查是否有备份配置
            if check_and_restore_config "mosdns" ""; then
                log "已从备份恢复 mosdns 配置"
                mosdns_configure_files
            else
                log "未找到 mosdns 备份，将使用默认配置"
                mosdns_configure_files
            fi
            ;;
        2)
            log "使用默认 MosDNS 配置..."
            mosdns_configure_files
            ;;
        *)
            echo -e "${red}无效选择，将使用默认配置${reset}"
            mosdns_configure_files
            ;;
    esac

    # Filebrowser 配置设置
    if [ ! -f "/mssb/fb/fb.db" ]; then
        log "Filebrowser 数据库不存在，创建默认数据库..."
        # 启动 filebrowser 到后台
        filebrowser -c /mssb/fb/fb.json -d /mssb/fb/fb.db &
        # 记录进程 PID
        FB_PID=$!
        # 等待 2 秒让它初始化数据库
        sleep 1
        # 杀掉进程
        kill $FB_PID 2>/dev/null
        # 确保进程被杀死
        wait $FB_PID 2>/dev/null
    fi

    echo -e "\n${green_text}=== Filebrowser 配置设置 ===${reset}"
    echo -e "1. 启用密码登录（默认， 默认用户密码安装完提示，进入后可自行修改）"
    echo -e "2. 禁用密码登录（无需登录即可访问）"
    echo -e "${green_text}------------------------${reset}"
    
    read -p "请选择 Filebrowser 登录方式 (1/2): " fb_choice
    
    case "$fb_choice" in
        2)
            log "正在配置 Filebrowser 为无密码登录模式..."
            filebrowser config set --auth.method=noauth -c /mssb/fb/fb.json -d /mssb/fb/fb.db
            log "Filebrowser 已配置为无密码登录模式"
            ;;
        *)
            log "使用默认的密码登录模式..."
            filebrowser config set --auth.method=json -c /mssb/fb/fb.json -d /mssb/fb/fb.db
            log "Filebrowser 已配置为密码登录模式"
            ;;
    esac

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

    # Supervisor 配置设置
    echo -e "\n${green_text}=== Supervisor 管理配置设置 ===${reset}"
    echo -e "1. 使用默认用户名密码（mssb/mssb123..）"
    echo -e "2. 自定义用户名密码"
    echo -e "3. 不设置用户名密码"
    echo -e "${green_text}------------------------${reset}"
    
    read -p "请选择 Supervisor 管理配置方式 (1/2/3): " supervisor_choice
    
    case "$supervisor_choice" in
        2)
            read -p "请输入用户名: " supervisor_username
            read -p "请输入密码: " supervisor_password
            
            if [ -n "$supervisor_username" ] && [ -n "$supervisor_password" ]; then
                sed -i "s/^username=.*/username=$supervisor_username/" /etc/supervisor/supervisord.conf
                sed -i "s/^password=.*/password=$supervisor_password/" /etc/supervisor/supervisord.conf
                log "已设置自定义 Supervisor 用户名和密码"
            else
                log "用户名或密码为空，将使用默认设置"
                sed -i "s/^username=.*/username=mssb/" /etc/supervisor/supervisord.conf
                sed -i "s/^password=.*/password=mssb123../" /etc/supervisor/supervisord.conf
            fi
            ;;
        3)
            sed -i "s/^username=.*/username=/" /etc/supervisor/supervisord.conf
            sed -i "s/^password=.*/password=/" /etc/supervisor/supervisord.conf
            log "已清除 Supervisor 用户名和密码设置"
            ;;
        *)
            sed -i "s/^username=.*/username=mssb/" /etc/supervisor/supervisord.conf
            sed -i "s/^password=.*/password=mssb123../" /etc/supervisor/supervisord.conf
            log "已设置默认 Supervisor 用户名和密码"
            ;;
    esac

    cp -r watch / || {
        log "复制 watch 目录失败！退出脚本。"
        exit 1
    }

    log "设置脚本可执行权限..."
    chmod +x /watch/*.sh || {
        log "设置 /watch/*.sh 权限失败！退出脚本。"
        exit 1
    }
}

# singbox配置文件复制
singbox_configure_files() {
    # 复制 mssb/sing-box 目录
    log "复制 mssb/sing-box 目录..."
    check_and_copy_folder "sing-box"
    # 获取当前核心类型
    detect_singbox_info

    # 根据核心类型复制对应的配置文件
    if [ "$core_type" == "sing-box-reF1nd" ]; then
        log "检测到 R核心，复制 sing-box-r.json 配置文件"
        if [ -f "/mssb/sing-box/sing-box-r.json" ]; then
            cp /mssb/sing-box/sing-box-r.json /mssb/sing-box/config.json
            log "已复制 sing-box-r.json 为 config.json"
        else
            log "警告：找不到 sing-box-r.json 文件"
        fi
    elif [ "$core_type" = "sing-box-yelnoo" ]; then
        log "检测到 Y核心，复制 y.json 配置文件"
        if [ -f "/mssb/sing-box/sing-box-y.json" ]; then
            cp /mssb/sing-box/sing-box-y.json /mssb/sing-box/config.json
            log "已复制 sing-box-y.json 为 config.json"
        else
            log "警告：找不到 sing-box-y.json 文件"
        fi
    else
        log "未知核心类型：$core_type，使用默认配置文件"
    fi
}

# mihomo配置文件复制
mihomo_configure_files() {
    # 复制 mssb/mihomo 目录
    log "复制 mssb/mihomo 目录..."
    check_and_copy_folder "mihomo"
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
    
    # 询问是否更新 MosDNS
    read -p "是否启用 MosDNS 自动更新？(y/n) [默认: y]: " update_mosdns
    update_mosdns=${update_mosdns:-y}
    
    # 询问是否更新 CN 域名数据
    read -p "是否启用 MosDNS CN 域名数据自动更新？(y/n) [默认: y]: " update_cn
    update_cn=${update_cn:-y}
    
    # 根据核心类型询问相应的更新选项
    if [ "$core_name" = "sing-box" ]; then
        read -p "是否启用 Sing-box 自动更新？(y/n) [默认: y]: " update_core
        update_core=${update_core:-y}
        
        cron_jobs=()
        
        # 根据用户选择添加任务
        if [[ "$update_mosdns" =~ ^[Yy]$ ]]; then
            cron_jobs+=("0 4 * * 1 /watch/update_mosdns.sh # update_mosdns")
        fi
        
        if [[ "$update_cn" =~ ^[Yy]$ ]]; then
            cron_jobs+=("15 4 * * 1 /watch/update_cn.sh # update_cn")
        fi
        
        if [[ "$update_core" =~ ^[Yy]$ ]]; then
            cron_jobs+=("10 4 * * 1 /watch/update_sb.sh # update_sb")
        fi
        
    elif [ "$core_name" = "mihomo" ]; then
        read -p "是否启用 Mihomo 自动更新？(y/n) [默认: y]: " update_core
        update_core=${update_core:-y}
        
        cron_jobs=()
        
        # 根据用户选择添加任务
        if [[ "$update_mosdns" =~ ^[Yy]$ ]]; then
            cron_jobs+=("0 4 * * 1 /watch/update_mosdns.sh # update_mosdns")
        fi
        
        if [[ "$update_cn" =~ ^[Yy]$ ]]; then
            cron_jobs+=("15 4 * * 1 /watch/update_cn.sh # update_cn")
        fi
        
        if [[ "$update_core" =~ ^[Yy]$ ]]; then
            cron_jobs+=("10 4 * * 1 /watch/update_mihomo.sh # update_mihomo")
        fi
    else
        log "未识别的 core_name（$core_name），跳过定时任务设置。"
        return
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
        # 备份当前配置
        cp /etc/nftables.conf /etc/nftables.conf.bak
        
        # 检查配置语法
        if nft -c -f /etc/nftables.conf; then
            nft flush ruleset
            sleep 1
            nft -f /etc/nftables.conf
            systemctl enable --now nftables || log "nftables 服务启动失败"
        else
            log "nftables 配置有语法错误，已取消加载"
            cp /etc/nftables.conf.bak /etc/nftables.conf
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
    # 备份所有重要文件
    backup_all_config
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
    
    # 删除配置目录（保留备份目录）
    find /mssb -mindepth 1 -maxdepth 1 -not -name "backup" -exec rm -rf {} +
    
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
}

# 智能检测 Sing-box 核心类型和版本
detect_singbox_info() {
    # 获取版本输出
    version_output=$(/usr/local/bin/sing-box version 2>/dev/null | head -n1)
    current_version=$(echo "$version_output" | awk '{print $3}' || echo "未知版本")

    # 优先从文件获取核心类型，如果文件不存在则从命令输出智能识别
    if [ -f "/mssb/.core_type" ]; then
        core_type=$(cat "/mssb/.core_type")
        detection_source="类型文件/mssb/.core_type"
    else
        # 从版本输出中智能识别核心类型
        if echo "$version_output" | grep -q "reF1nd"; then
            core_type="sing-box-reF1nd"
            detection_source="版本识别"
        else
            # 如果没有特殊标识，可能是Y核心或其他版本
            core_type="sing-box-yelnoo"
            detection_source="推测可能是Y核心或其他版本"
        fi
    fi

    # 输出检测结果
    log "当前安装的版本: $current_version"
    log "当前安装的版本: (核心类型：$core_type，来源：$detection_source)"
}

# 记录 Sing-box 核心版本
record_singbox_core() {
    local core_type=$1
    mkdir -p "/mssb"
    echo "$core_type" > /mssb/.core_type
    log "已记录 Sing-box 核心类型：$core_type 在/mssb/.core_type 文件不可删除"
}

# reF1nd佬 R核心安装函数
singbox_r_install() {
    # 检查是否已安装 Sing-box
    if [ -f "/usr/local/bin/sing-box" ]; then
        log "检测到已安装的 Sing-box"

        # 获取当前版本和核心类型信息
        detect_singbox_info

        echo -e "\n${green_text}=== Sing-box reF1nd R核心 安装选项 ===${reset}"
        echo -e "1. 跳过下载，使用现有版本"
        echo -e "2. 下载最新版本并更新"
        echo -e "${green_text}------------------------${reset}"

        read -p "请选择操作 (1/2): " singbox_r_choice

        case "$singbox_r_choice" in
            1)
                log "跳过 Sing-box reF1nd R核心 下载，使用现有版本"
                # 确保记录正确的核心类型
                record_singbox_core "sing-box-reF1nd"
                return 0
                ;;
            2)
                log "选择更新 Sing-box reF1nd R核心 到最新版本"
                ;;
            *)
                log "无效选择，默认跳过下载使用现有版本"
                record_singbox_core "sing-box-reF1nd"
                return 0
                ;;
        esac
    fi

    # 下载并安装 reF1nd R核心
    arch=$(detect_architecture)
    download_url="https://github.com/herozmy/StoreHouse/releases/download/sing-box-reF1nd/sing-box-reF1nd-dev-linux-${arch}.tar.gz"

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

    # 记录核心类型
    record_singbox_core "sing-box-reF1nd"

    # 显示安装完成的版本信息
    new_version=$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 | awk '{print $3}' || echo "未知版本")
    log "Sing-box reF1nd R核心 安装完成，版本：$new_version"
}

# S核安装函数
singbox_s_install() {
    # 检查是否已安装 Sing-box
    if [ -f "/usr/local/bin/sing-box" ]; then
        log "检测到已安装的 Sing-box"

        # 获取当前版本和核心类型信息
        detect_singbox_info

        echo -e "\n${green_text}=== Sing-box S佬Y核心 安装选项 ===${reset}"
        echo -e "1. 跳过下载，使用现有版本"
        echo -e "2. 下载最新版本并更新"
        echo -e "${green_text}------------------------${reset}"

        read -p "请选择操作 (1/2): " singbox_s_choice

        case "$singbox_s_choice" in
            1)
                log "跳过 Sing-box S佬Y核心 下载，使用现有版本"
                # 确保记录正确的核心类型
                record_singbox_core "sing-box-yelnoo"
                return 0
                ;;
            2)
                log "选择更新 Sing-box S佬Y核心 到最新版本"
                ;;
            *)
                log "无效选择，默认跳过下载使用现有版本"
                record_singbox_core "sing-box-yelnoo"
                return 0
                ;;
        esac
    fi

    # 下载并安装 S佬Y核心
    arch=$(detect_architecture)
    download_url="https://github.com/herozmy/StoreHouse/releases/download/sing-box-yelnoo/sing-box-yelnoo-linux-${arch}.tar.gz"

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

    # 记录核心类型
    record_singbox_core "sing-box-yelnoo"

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
}

# 修改 Filebrowser 配置
modify_filebrowser_config() {
    echo -e "\n${green_text}请选择 Filebrowser 登录方式：${reset}"
    echo -e "${green_text}1) 使用密码登录${reset}"
    echo -e "${green_text}2) 禁用密码登录${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "请输入选项 (1/2): " fb_choice

    case $fb_choice in
        1)
            # 使用密码登录
            if [ -f "/mssb/fb/fb.db" ]; then
                echo -e "\n${green_text}请选择密码设置方式：${reset}"
                echo -e "${green_text}1) 使用默认密码（admin/admin）${reset}"
                echo -e "${green_text}2) 自定义密码${reset}"
                echo -e "${green_text}-------------------------------------------------${reset}"
                read -p "请输入选项 (1/2): " password_choice

                supervisorctl stop filebrowser
                filebrowser config set --auth.method=json -c /mssb/fb/fb.json -d /mssb/fb/fb.db

                case $password_choice in
                    1)
                        # 使用默认密码
                        filebrowser users update admin --password "admin" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                        echo -e "${green_text}Filebrowser 已设置为使用默认密码（admin/admin）${reset}"
                        ;;
                    2)
                        # 自定义密码
                        read -p "请输入新密码（输入时可见）: " new_password
                        if [ -n "$new_password" ]; then
                            filebrowser users update admin --password "$new_password" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                            echo -e "${green_text}Filebrowser 密码已更新${reset}"
                        else
                            echo -e "${red}密码不能为空，将使用默认密码${reset}"
                            filebrowser users update admin --password "admin" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                        fi
                        ;;
                    *)
                        echo -e "${red}无效的选项，将使用默认密码${reset}"
                        filebrowser users update admin --password "admin" -c /mssb/fb/fb.json -d /mssb/fb/fb.db
                        ;;
                esac

                supervisorctl start filebrowser
            else
                echo -e "${red}Filebrowser 配置文件不存在${reset}"
                return 1
            fi
            ;;
        2)
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
}

# 修改服务配置
modify_service_config() {
    echo -e "\n${green_text}请选择要修改的配置：${reset}"
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
check_dns_settings() {
    # 获取当前 DNS 设置
    current_dns=$(cat /etc/resolv.conf | grep -E "^nameserver" | head -n 1 | awk '{print $2}')
    
    if [ "$current_dns" = "$local_ip" ]; then
        echo -e "\n${yellow}警告：检测到当前 DNS 设置为本地 IP ($local_ip)${reset}"
        echo -e "${yellow}建议在停止服务前修改 DNS 设置，否则可能导致无法访问网络${reset}"
        echo -e "${green_text}请选择操作：${reset}"
        echo -e "1) 使用阿里 DNS (223.5.5.5)"
        echo -e "2) 使用腾讯 DNS (119.29.29.29)"
        echo -e "3) 自定义 DNS"
        echo -e "4) 保持当前设置"
        echo -e "${green_text}-------------------------------------------------${reset}"
        read -p "请输入选项 (1/2/3/4): " dns_choice

        case $dns_choice in
            1)
                echo "nameserver 223.5.5.5" > /etc/resolv.conf
                echo -e "${green_text}已设置 DNS 为 223.5.5.5${reset}"
                ;;
            2)
                echo "nameserver 119.29.29.29" > /etc/resolv.conf
                echo -e "${green_text}已设置 DNS 为 119.29.29.29${reset}"
                ;;
            3)
                read -p "请输入自定义 DNS 地址: " custom_dns
                if [[ $custom_dns =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    echo "nameserver $custom_dns" > /etc/resolv.conf
                    echo -e "${green_text}已设置 DNS 为 $custom_dns${reset}"
                else
                    echo -e "${red}无效的 DNS 地址格式，将使用默认的阿里 DNS${reset}"
                    echo "nameserver 223.5.5.5" > /etc/resolv.conf
                fi
                ;;
            4)
                echo -e "${yellow}保持当前 DNS 设置 ($current_dns)${reset}"
                ;;
            *)
                echo -e "${red}无效选项，将使用默认的阿里 DNS${reset}"
                echo "nameserver 223.5.5.5" > /etc/resolv.conf
                ;;
        esac
    fi
}

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
    echo -e "${yellow}注意：此操作会清空并重写 /mssb/mosdns/client_ip.txt 文件${reset}"
    echo -e "${green_text}------------------------${reset}"

    read -p "是否继续扫描局域网设备？(y/n): " scan_choice
    if [[ "$scan_choice" != "y" && "$scan_choice" != "Y" ]]; then
        log "已取消局域网设备扫描"
        return 0
    fi

    # 检查必要工具
    if ! command -v arp-scan &> /dev/null; then
        log "正在安装 arp-scan 工具..."
        apt update && apt install -y arp-scan
        if ! command -v arp-scan &> /dev/null; then
            log "arp-scan 安装失败，无法进行设备扫描"
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
            log "无法自动检测网络接口，请手动指定"
            read -p "请输入网络接口名称（如 eth0, ens18）: " interface
        fi
    fi

    log "使用网络接口：$interface"

    # 扫描局域网设备
    echo -e "${yellow}🔍 正在扫描局域网设备，请稍等...${reset}"
    local raw_result
    raw_result=$(arp-scan --interface="$interface" --localnet 2>/dev/null | grep -E "^([0-9]{1,3}\.){3}[0-9]{1,3}")

    if [ -z "$raw_result" ]; then
        log "⚠️ 未找到设备，请检查网络接口或网络连接"
        return 1
    fi

    # 保存完整设备信息到数组
    local devices=()
    local device_ips=()
    while IFS= read -r line; do
        devices+=("$line")
        # 提取IP地址用于后续处理
        local ip=$(echo "$line" | awk '{print $1}')
        device_ips+=("$ip")
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
    echo -e "${yellow}提示：可以选择多个设备，用英文逗号分隔（如 1,3,5）${reset}"
    read -p "👉 请输入要添加到代理列表的设备编号： " selected_ids

    if [ -z "$selected_ids" ]; then
        log "未选择任何设备，操作已取消"
        return 0
    fi

    # 创建输出目录
    mkdir -p "/mssb/mosdns"
    local output_file="/mssb/mosdns/client_ip.txt"

    # 清空输出文件
    > "$output_file"

    # 处理选择结果
    local valid_count=0
    IFS=',' read -ra ids <<< "$selected_ids"
    for id in "${ids[@]}"; do
        # 去除空格
        id=$(echo "$id" | tr -d ' ')
        local idx=$((id-1))

        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#device_ips[@]}" ]; then
            local ip="${device_ips[$idx]}"
            echo "$ip" >> "$output_file"
            log "已添加设备 IP：$ip"
            ((valid_count++))
        else
            log "⚠️ 无效编号: $id，跳过"
        fi
    done

    if [ $valid_count -gt 0 ]; then
        echo ""
        echo -e "${green_text}✅ 已将 $valid_count 个设备的IP地址写入 $output_file${reset}"
        echo -e "${green_text}当前代理设备列表：${reset}"
        cat "$output_file" | while read -r ip; do
            echo -e "  📱 $ip"
        done
    else
        log "未成功添加任何设备"
        return 1
    fi
}

# 创建全局 mssb 命令
create_mssb_command() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo -e "${green_text}正在更新项目...${reset}"
    echo "项目目录：$script_dir"

    cd "$script_dir" || {
        echo -e "${red}❌ 无法切换到项目目录${reset}"
        return 1
    }

    git pull

    if [ $? -eq 0 ]; then
        echo -e "${green_text}✅ 项目更新成功！${reset}"
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
        4)
            echo -e "${green_text}正在更新 CN域名数据...${reset}"
            /watch/update_cn.sh
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
            echo -e "${green_text}更新 CN域名数据...${reset}"
            /watch/update_cn.sh
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
        echo -e "🗂️  文件管理服务 Filebrowser：${green_text}http://${local_ip}:8088${reset}"
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
    echo -e "${green_text}备份所有重要文件到/mssb/backup ${reset}"
    # 备份所有重要文件
    backup_all_config
    echo -e "${green_text}-------------------------------------------------${reset}"
    echo

    echo -e "${green_text}请选择安装方案：${reset}"
    echo "1) 方案1：Sing-box(魔改内核支持订阅) + MosDNS"
    echo "2) 方案2：Mihomo(原生就支持订阅) + MosDNS"
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "请输入选项 (1/2): " choice
    case "$choice" in
        1)
            core_name="sing-box"
            log "你选择了方案1：Sing-box (支持订阅) + MosDNS"

            # 显示 Sing-box 核心版本选择
            echo -e "\n${green_text}请选择 Sing-box 核心版本：${reset}"
            echo -e "${yellow}1. Sing-box reF1nd佬 R核心${reset} <支持订阅> ${green_text}推荐${reset}"
            echo -e "${yellow}2. Sing-box S佬Y核心${reset} <支持订阅> ${green_text}推荐${reset}"
            echo -e "${yellow}说明: Sing-box Puer喵佬核心${reset} <支持订阅> ${green_text}停更不再支持${reset}"
            echo -e "${yellow}说明: Sing-box 曦灵X核心${reset} <支持订阅> ${green_text}停更不在支持${reset}"
            echo -e "${green_text}-------------------------------------------------${reset}"
            read -p "请输入选项 (1/2): " singbox_choice
            install_filebrower
            install_mosdns
            case "$singbox_choice" in
                1)
                    log "你选择了 Sing-box reF1nd佬 R核心"
                    singbox_r_install
                    ;;
                2)
                    log "你选择了 Sing-box S佬Y核心"
                    singbox_s_install
                    ;;
                *)
                    log "无效选项，将使用默认的 reF1nd佬 R核心"
                    singbox_r_install
                    ;;
            esac
            cp_config_files
            singbox_configure_files
            singbox_customize_settings
            check_ui
            install_tproxy
            reload_service
            ;;
        2)
            core_name="mihomo"
            log "你选择了方案2：Mihomo + MosDNS"
            install_filebrower
            install_mosdns
            install_mihomo
            cp_config_files
            mihomo_configure_files
            check_ui
            install_tproxy
            mihomo_customize_settings
            reload_service
            ;;
        *)
            log "无效选项，退出安装。"
            exit 1
            ;;
    esac

    echo
    echo -e "${green_text}-------------------------------------------------${reset}"
    echo "是否添加以下定时更新任务？每周一凌晨执行："
    echo "- 4:00 更新 MosDNS"
    if [ "$core_name" = "sing-box" ]; then
        echo "- 4:10 更新 Sing-box"
        echo "- 4:15 更新 CN 域名数据"
    else
        echo "- 4:10 更新 Mihomo"
        echo "- 4:15 更新 CN 域名数据"
    fi
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "是否添加定时任务？(y/n): " enable_cron
    if [[ "$enable_cron" == "y" || "$enable_cron" == "Y" ]]; then
        add_cron_jobs
    else
        log "用户选择不添加定时任务。"
    fi

    # 检查并设置本地 DNS
    check_and_set_local_dns

    # 显示路由规则提示
    format_route_rules

    echo -e "${green_text}-------------------------------------------------${reset}"
    echo -e "${green_text}🎉 安装成功！以下是服务信息：${reset}"
    echo -e "🌐 Mosdns 统计界面：${green_text}http://${local_ip}:9099/graphic${reset}"
    echo
    echo -e "📦 Supervisor 管理界面：${green_text}http://${local_ip}:9001${reset}"
    if [ "$supervisor_choice" = "3" ]; then
        echo -e "   - 无需登录"
    elif [ "$supervisor_choice" = "2" ] && [ -n "$supervisor_username" ] && [ -n "$supervisor_password" ]; then
        echo -e "   - 用户名：$supervisor_username"
        echo -e "   - 密码：$supervisor_password"
    else
        echo -e "   - 用户名：mssb"
        echo -e "   - 密码：mssb123.."
    fi
    echo
    echo -e "🗂️  文件管理服务 Filebrowser：${green_text}http://${local_ip}:8088${reset}"
    if [ "$fb_choice" = "2" ]; then
        echo -e "   - 无需登录"
    else
        echo -e "   - 用户名：admin"
        echo -e "   - 密码：admin"
    fi
    echo
    echo -e "🕸️  Sing-box/Mihomo 面板 UI：${green_text}http://${local_ip}:9090/ui${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"

    # 代理设备列表配置
    echo -e "\n${green_text}=== Mosdns代理设备列表配置 ===${reset}"
    echo -e "1. 扫描局域网设备并选择"
    echo -e "2. 跳过配置（使用现有或默认列表）"
    echo -e "${green_text}------------------------${reset}"

    read -p "请选择代理设备配置方式 (1/2): " device_choice

    case "$device_choice" in
        1)
            scan_lan_devices
            ;;
        2)
            log "跳过代理设备列表配置，使用现有配置"
            ;;
        *)
            log "无效选择，跳过代理设备列表配置"
            ;;
    esac

    # 创建全局 mssb 命令
    echo -e "\n${green_text}正在创建全局 mssb 命令...${reset}"
    create_mssb_command

    log "脚本执行完成。"
}

# 主函数
main() {
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
    echo -e "${green_text}6) 备份所有重要文件${reset}"
    echo -e "${green_text}7) 扫描局域网设备并配置mosdns代理列表${reset}"
    echo -e "${green_text}8) 显示服务信息${reset}"
    echo -e "${green_text}9) 显示路由规则提示${reset}"
    echo -e "${green_text}10) 创建全局 mssb 命令${reset}"
    echo -e "${red}11) 删除全局 mssb 命令${reset}"
    echo -e "${green_text}12) 更新项目${reset}"
    echo -e "${green_text}13) 更新内核版本(mosdns/singbox/mihomo)${reset}"
    echo -e "${green_text}-------------------------------------------------${reset}"
    read -p "请输入选项 (1/2/3/4/5/6/7/8/9/10/11/12/13/00): " main_choice

    case "$main_choice" in
        2)
            stop_all_services
            # 检查 DNS 设置
            check_dns_settings
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        3)
            uninstall_all_services
            # 检查 DNS 设置
            check_dns_settings
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
            echo -e "${green_text}备份所有重要文件到/mssb/backup ${reset}"
            # 备份所有重要文件
            backup_all_config
            echo -e "${green_text}-------------------------------------------------${reset}"
            echo -e "\n${yellow}(按键 Ctrl + C 终止运行脚本, 键入任意值返回主菜单)${reset}"
            read -n 1
            main
            ;;
        7)
            echo -e "${green_text}扫描局域网设备并配置代理列表${reset}"
            # 检查网络接口
            check_interfaces
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
            echo -e "${green_text}更新内核版本(mosdns/singbox/mihomo)${reset}"
            update_cores_menu
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


main
