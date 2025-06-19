#!/bin/bash

# 定义颜色变量
green_text="\033[32m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

# 日志函数
log() {
    echo -e "[$(date +'%F %T')] ${yellow}$*${reset}"
}

# 错误日志函数
error_log() {
    echo -e "[$(date +'%F %T')] ${red}错误: $*${reset}"
}

# 成功日志函数
success_log() {
    echo -e "[$(date +'%F %T')] ${green_text}成功: $*${reset}"
}

# 检查文件完整性
check_file_integrity() {
    local file=$1
    if [ ! -s "$file" ]; then
        error_log "文件 $file 为空或不存在"
        return 1
    fi
    return 0
}

# 下载文件函数
download_file() {
    local url=$1
    local destination=$2
    local description=$3
    local temp_file="${destination}.tmp"

    log "正在更新 ${description}..."
    # 下载到临时文件
    if [ -n "$proxy" ]; then
        # 使用代理下载
        if wget --progress=bar:force --show-progress -e use_proxy=yes -e http_proxy="$proxy" -e https_proxy="$proxy" -O "$temp_file" "$url"; then
            download_success=true
        else
            download_success=false
        fi
    else
        # 不使用代理下载
        if wget --progress=bar:force --show-progress -O "$temp_file" "$url"; then
            download_success=true
        else
            download_success=false
        fi
    fi

    if [ "$download_success" = true ]; then
        # 检查文件完整性
        if check_file_integrity "$temp_file"; then
            rm -f "$destination"
            # 如果下载成功且文件完整，则移动到目标位置
            mv "$temp_file" "$destination"
            success_log "${description} 更新成功"
            return 0
        else
            rm -f "$temp_file"
            error_log "${description} 下载的文件无效"
            return 1
        fi
    else
        rm -f "$temp_file"
        error_log "${description} 更新失败，请检查网络连接或 URL 是否正确"
        return 1
    fi
}

# 主函数
main() {
    log "开始更新 CN 规则文件..."

    # 设置需要下载的文件 URL
    # https://github.com/MetaCubeX/meta-rules-dat/blob/sing/geo/geosite/cn.srs
    # https://github.com/MetaCubeX/meta-rules-dat/blob/sing/geo/geosite/geolocation-!cn.srs
    # https://github.com/MetaCubeX/meta-rules-dat/blob/sing/geo/geoip/cn.srs
    proxy_list_url="https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/sing/geo/geosite/geolocation-!cn.srs"
    direct_list_url="https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/sing/geo/geosite/cn.srs"
    cn_ip_cidr_url="https://github.com/MetaCubeX/meta-rules-dat/raw/refs/heads/sing/geo/geoip/cn.srs"

    # 设置本地文件路径
    geosite_geolocation_noncn_file="/mssb/mosdns/unpack/geolocation-!cn.srs"
    geosite_cn_file="/mssb/mosdns/unpack/geosite-cn.srs"
    geoip_cn_file="/mssb/mosdns/unpack/geoip-cn.srs"
    # 确保目录存在
    mkdir -p "$(dirname "$geosite_geolocation_noncn_file")"

    # 下载文件
    download_file "$proxy_list_url" "$geosite_geolocation_noncn_file" "代理列表" || exit 1
    download_file "$direct_list_url" "$geosite_cn_file" "直连列表" || exit 1
    download_file "$cn_ip_cidr_url" "$geoip_cn_file" "CN IP CIDR" || exit 1
    # 重启 MosDNS 服务
    log "正在通过 Supervisor 重启 MosDNS 服务..."
    if supervisorctl restart mosdns; then
        success_log "MosDNS 服务重启成功"
    else
        error_log "MosDNS 服务重启失败，请检查 Supervisor 配置"
        exit 1
    fi

    success_log "CN 规则更新和重启流程成功完成"
}

# 执行主函数
main
