#!/bin/bash

# 颜色变量
yellow="\033[33m"
reset="\033[0m"

# 日志函数
log() {
    echo -e "[$(date +'%F %T')] ${yellow}$*${reset}"
}

# 检测系统架构
detect_architecture() {
    case "$(uname -m)" in
        x86_64)     echo "amd64" ;;
        aarch64)    echo "arm64" ;;
        armv7l)     echo "armv7" ;;
        armhf)      echo "armhf" ;;
        s390x)      echo "s390x" ;;
        i386|i686)  echo "386" ;;
        *)
            log "不支持的CPU架构: $(uname -m)"
            exit 1
            ;;
    esac
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
            log "AMD64 架构缺少指令集: $flag → 不支持 v3"
            return 1
        fi
    done

    log "检测到 AMD64 架构支持完整 v3 指令集"
    return 0
}

# 加载环境变量
load_env() {
    local env_file="/mssb/mssb.env"
    if [ -f "$env_file" ]; then
        # shellcheck source=/mssb/mssb.env
        source "$env_file"
        log "已加载环境变量文件 $env_file"
    else
        log "未找到环境变量文件 $env_file，使用默认配置"
        amd64v3_enabled="false"
        singbox_core_type="reF1nd"
    fi
}

# 智能检测 Sing-box 核心类型和版本
detect_singbox_info() {
    # 获取版本输出
    version_output=$(/usr/local/bin/sing-box version 2>/dev/null | head -n1)
    current_version=$(echo "$version_output" | awk '{print $3}' || echo "未知版本")

    # 优先从环境变量获取核心类型
    if [ -n "$singbox_core_type" ]; then
        core_type="sing-box-$singbox_core_type"
        detection_source="环境变量"
    elif [ -f "/mssb/.core_type" ]; then
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
    log "当前核心类型: $core_type (来源：$detection_source)"
}

# 安装 Sing-box 核心
singbox_install() {
    # 加载环境变量
    load_env
    
    # 获取当前核心类型
    detect_singbox_info

    arch=$(detect_architecture)
    
    # 根据核心类型和 v3 支持情况选择下载地址
    case "$core_type" in
        "sing-box-reF1nd")
            if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
                SING_BOX_URL="https://github.com/baozaodetudou/mssb/releases/download/sing-box-reF1nd/sing-box-reF1nd-dev-linux-amd64v3.tar.gz"
                log "使用 reF1nd佬 R核心 AMD64 v3 优化版本"
            else
                SING_BOX_URL="https://github.com/baozaodetudou/mssb/releases/download/sing-box-reF1nd/sing-box-reF1nd-dev-linux-${arch}.tar.gz"
                log "使用 reF1nd佬 R核心标准版本"
            fi
            ;;
        "sing-box-yelnoo")
            if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
                SING_BOX_URL="https://github.com/baozaodetudou/mssb/releases/download/sing-box-yelnoo/sing-box-yelnoo-dev-linux-amd64v3.tar.gz"
                log "使用 S佬Y核心 AMD64 v3 优化版本"
            else
                SING_BOX_URL="https://github.com/baozaodetudou/mssb/releases/download/sing-box-yelnoo/sing-box-yelnoo-dev-linux-${arch}.tar.gz"
                log "使用 S佬Y核心标准版本"
            fi
            ;;
        *)
            log "未知的核心类型：$core_type，退出更新"
            exit 1
            ;;
    esac

    log "开始下载 Sing-box 核心：$SING_BOX_URL"
    if ! wget -O /tmp/sing-box.tar.gz "$SING_BOX_URL"; then
        log "Sing-box 下载失败，请检查网络连接"
        exit 1
    fi

    log "Sing-box 下载完成，开始安装..."
    if ! tar -zxvf /tmp/sing-box.tar.gz -C /usr/local/bin; then
        log "解压 Sing-box 失败，请检查压缩包完整性"
        exit 1
    fi

    chmod +x /usr/local/bin/sing-box || log "警告：未能设置 Sing-box 执行权限"
    rm -f /tmp/sing-box.tar.gz
    
    # 显示安装完成的版本信息
    new_version=$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 | awk '{print $3}' || echo "未知版本")
    log "Sing-box 安装完成，版本：$new_version，临时文件已清理"
}

# 主体流程
main() {
    log "开始更新 Sing-box..."

    # 安装核心
    singbox_install

    # 更新 UI
    log "准备更新 UI..."
    mkdir -p /mssb/sing-box/ui/
    rm -rf /tmp/ui
    if git clone --depth=1 https://github.com/Zephyruso/zashboard.git -b gh-pages /tmp/ui; then
        cp -r /tmp/ui/* /mssb/sing-box/ui/
        log "UI 文件克隆并复制成功。"
    else
        log "UI 文件克隆失败，请检查 GitHub URL 或网络连接。"
        exit 1
    fi

    # 重启服务
    log "正在通过 Supervisor 重启 Sing-box 服务..."
    if supervisorctl restart sing-box && systemctl restart sing-box-router; then
        log "Sing-box 服务重启成功。"
    else
        log "Sing-box 服务重启失败，请检查 Supervisor 配置。"
        exit 1
    fi

    # 清理临时文件
    rm -rf /tmp/*
    log "Sing-box 更新完成，临时文件已清理。"
}

# 执行主函数
main
