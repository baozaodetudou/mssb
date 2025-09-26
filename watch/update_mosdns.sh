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

# 安装 MosDNS 核心
mosdns_install() {
    # 加载环境变量
    load_env
    
    arch=$(detect_architecture)
    
    # 根据 v3 支持情况选择下载链接
    if [ "$amd64v3_enabled" = "true" ] && check_amd64_v3_support; then
        MOSDNS_URL="https://github.com/baozaodetudou/mssb/releases/download/mosdns/mosdns-linux-amd64-v3.zip"
        log "使用 AMD64 v3 优化版本"
    else
        MOSDNS_URL="https://github.com/baozaodetudou/mssb/releases/download/mosdns/mosdns-linux-${arch}.zip"
        log "使用标准版本"
    fi
    
    log "开始下载 MosDNS 核心：$MOSDNS_URL"

    if ! curl -L -o /tmp/mosdns.zip "$MOSDNS_URL"; then
        log "MosDNS 下载失败，请检查网络连接"
        exit 1
    fi

    log "MosDNS 下载完成，开始安装..."
    if ! unzip -o /tmp/mosdns.zip -d /usr/local/bin; then
        log "解压 MosDNS 失败，请检查压缩包完整性"
        exit 1
    fi

    chmod +x /usr/local/bin/mosdns || log "警告：未能设置 MosDNS 执行权限"
    rm -f /tmp/mosdns.zip
    
    # 显示安装完成的版本信息
    new_version=$(/usr/local/bin/mosdns version 2>/dev/null | head -n1 | awk '{print $2}' || echo "未知版本")
    log "MosDNS 安装完成，版本：$new_version，临时文件已清理"
}

# 主逻辑
log "开始更新 MosDNS..."

# 安装核心
mosdns_install

# 重启 MosDNS 服务
log "正在通过 Supervisor 重启 MosDNS 服务..."
if supervisorctl restart mosdns; then
    log "MosDNS 服务重启成功。"
else
    log "MosDNS 服务重启失败，请检查 Supervisor 配置。"
    exit 1
fi

# 清理临时文件
rm -rf /tmp/*

log "MosDNS 更新并重启成功。"
