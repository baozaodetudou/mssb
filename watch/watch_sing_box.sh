#!/bin/bash
# 延迟 60 秒
sleep 60
# 需要监听的目录
CONFIG_DIR="/mssb/sing-box"

# 使用 inotifywait 仅监听 config.json 的变动
while true; do
  inotifywait -e modify,create,delete -r "$CONFIG_DIR" --include 'config\.json$'
  echo "Sing-box 配置文件发生变化，重启 Sing-box 服务..."

  # 通过 supervisorctl 重启 Sing-box 服务
  supervisorctl restart sing-box && systemctl restart sing-box-router
done
