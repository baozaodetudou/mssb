#!/bin/bash
# 延迟 60 秒
sleep 60
# 需要监听的目录
CONFIG_DIR="/mssb/sing-box"

# 使用 inotifywait 监听 config.json，忽略指定子目录
while read -r EVENT FILE; do
  case "$FILE" in
    "$CONFIG_DIR"/config.json)
      echo "Sing-box 配置文件发生变化，重启 Sing-box 服务..."
      supervisorctl restart sing-box && systemctl restart sing-box-router
      ;;
    *)
      continue
      ;;
  esac
done < <(
  inotifywait -q -m -e modify,create,delete,move -r "$CONFIG_DIR" \
    --exclude '/(adguard|gen|genblank|rule|srs|unpack|webinfo)(/|$)' \
    --format '%e %w%f'
)
