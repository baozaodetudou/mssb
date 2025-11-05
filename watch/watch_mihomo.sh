#!/bin/bash
# 延迟 60 秒
sleep 60
# 需要监听的目录
CONFIG_DIR="/mssb/mihomo"

# 使用 inotifywait 仅监听 config.yaml 的变动
while true; do
  inotifywait -e modify,create,delete -r $CONFIG_DIR --include 'config\.yaml$'
  echo "mihomo 配置文件发生变化，重启 mihomo 服务..."

  # 通过 supervisorctl 重启 mihomo 服务
  supervisorctl restart mihomo
done
