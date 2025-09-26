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
    fi
}

# 安装 Mihomo 核心
mihomo_install() {
    # 加载环境变量
    load_env
    
    arch=$(detect_architecture)
    
    # 根据 v3 支持情况选择下载链接
    if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
        download_url="https://github.com/baozaodetudou/mssb/releases/download/mihomo/mihomo-meta-linux-amd64v3.tar.gz"
        log "使用 AMD64 v3 优化版本"
    else
        download_url="https://github.com/baozaodetudou/mssb/releases/download/mihomo/mihomo-meta-linux-${arch}.tar.gz"
        log "使用标准版本"
    fi
    
    log "开始下载 Mihomo 核心：$download_url"

    if ! wget -O /tmp/mihomo.tar.gz "$download_url"; then
        log "Mihomo 下载失败，请检查网络连接"
        exit 1
    fi

    log "Mihomo 下载完成，开始安装..."
    mkdir -p /usr/local/bin
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

# 主逻辑
log "开始更新 mihomo..."

# 设置核心名称（默认值）
core_name="mihomo"

# 安装核心
mihomo_install

# 更新 UI
log "准备更新 UI..."
mkdir -p /mssb/mihomo/ui/
rm -rf /tmp/ui
if git clone --depth=1 https://github.com/Zephyruso/zashboard.git -b gh-pages /tmp/ui; then
    cp -r /tmp/ui/* /mssb/mihomo/ui/
    log "UI 文件克隆并复制成功。"
else
    log "UI 文件克隆失败，请检查 GitHub URL 或网络连接。"
    echo "拉取源码失败，请手动下载源码并解压至 /mssb/${core_name}/ui"
    echo "地址: https://github.com/Zephyruso/zashboard.git"
    exit 1
fi

# 重启服务
log "正在通过 Supervisor 重启 mihomo 服务..."
if supervisorctl restart mihomo && systemctl restart mihomo-router; then
    log "mihomo 服务重启成功。"
else
    log "mihomo 服务重启失败，请检查 Supervisor 配置。"
    exit 1
fi

# 清理临时文件
rm -rf /tmp/*
