#!/bin/bash

# 设置日志输出函数
log() {
    echo "[$(date)] $1"
}

# 更新系统和安装必要的软件
log "更新系统..."
if ! apt update && apt -y upgrade; then
    log "系统更新失败！退出脚本。"
    exit 1
fi

log "安装必要的软件包..."
if ! apt install -y supervisor inotify-tools curl git wget tar gawk sed cron unzip nano; then
    log "软件包安装失败！退出脚本。"
    exit 1
fi

# 检测系统架构
ARCH=""
case "$(uname -m)" in
    "aarch64")
        ARCH="arm64"
        log "检测到 CPU 架构为 arm64。"
        ;;
    "x86_64")
        ARCH="amd64"
        log "检测到 CPU 架构为 amd64。"
        ;;
    *)
        log "无法识别的 CPU 架构：$(uname -m)。脚本退出。"
        exit 1
        ;;
esac

# 下载并安装 MosDNS
log "开始下载 MosDNS..."
LATEST_MOSDNS_VERSION=$(curl -sL -o /dev/null -w %{url_effective} https://github.com/IrineSistiana/mosdns/releases/latest | awk -F '/' '{print $NF}')
MOSDNS_URL="https://github.com/IrineSistiana/mosdns/releases/download/${LATEST_MOSDNS_VERSION}/mosdns-linux-${ARCH}.zip"

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
else
    log "设置权限失败，请检查文件路径和权限设置。"
    exit 1
fi

# 下载并安装 Filebrowser
log "开始下载 Filebrowser..."
LATEST_FILEBROWSER_VERSION=$(curl -sL -o /dev/null -w %{url_effective} https://github.com/filebrowser/filebrowser/releases/latest | awk -F '/' '{print $NF}')
FILEBROWSER_URL="https://github.com/filebrowser/filebrowser/releases/download/${LATEST_FILEBROWSER_VERSION}/linux-${ARCH}-filebrowser.tar.gz"

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
else
    log "Filebrowser 设置权限失败，请检查文件路径和权限设置。"
    exit 1
fi

# 配置文件和脚本设置
log "复制配置文件..."
cp supervisord.conf /etc/supervisor/ || { log "复制 supervisord.conf 失败！退出脚本。"; exit 1; }
cp -r mssb / || { log "复制 mssb 目录失败！退出脚本。"; exit 1; }
cp -r watch / || { log "复制 watch 目录失败！退出脚本。"; exit 1; }

log "设置脚本可执行权限..."
chmod +x /watch/*.sh || { log "设置 /watch/*.sh 权限失败！退出脚本。"; exit 1; }

# 安装 Sing-Box
log "安装 Sing-Box..."
if ! bash kvm-install-sing-box-p.sh; then
    log "安装 Sing-Box 失败！退出脚本。"
    exit 1
fi

# 重启 Supervisor
log "重启 Supervisor..."
if ! supervisorctl reload; then
    log "重启 Supervisor 失败！"
    exit 1
fi

log "脚本执行完成。"