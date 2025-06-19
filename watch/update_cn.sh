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
    # 如果代理变量非空，则设置 curl 命令使用代理
    if [ -n "$proxy" ]; then
        CURL_COMMAND="curl --progress-bar --show-error -x $proxy -o"
    else
        CURL_COMMAND="curl --progress-bar --show-error -o"
    fi
    # 下载到临时文件
    if $CURL_COMMAND "$temp_file" "$url"; then
        # 检查文件完整性
        if check_file_integrity "$temp_file"; then
            rm "$destination"
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
    proxy_list_url="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"
    gfw_list_url="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
    direct_list_url="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt"
    cn_ip_cidr_url="https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt"

    # 设置本地文件路径
    geosite_geolocation_noncn_file="/mssb/mosdns/rule/geosite_geolocation_noncn.txt"
    gfw_file="/mssb/mosdns/rule/gfw.txt"
    geosite_cn_file="/mssb/mosdns/rule/geosite_cn.txt"
    geoip_cn_file="/mssb/mosdns/rule/geoip_cn.txt"
    # 确保目录存在
    mkdir -p "$(dirname "$geosite_geolocation_noncn_file")"

    # 下载文件
    download_file "$proxy_list_url" "$geosite_geolocation_noncn_file" "代理列表" || exit 1
    download_file "$gfw_list_url" "$gfw_file" "GFW 列表" || exit 1
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
