#!/bin/bash
# 防抖时间（秒）
DEBOUNCE_TIME=6
CONFIG_DIR="/mssb/mosdns"
LAST_RESTART=0

echo "$(date '+%Y-%m-%d %H:%M:%S') 启动 MosDNS 配置文件监控..."

while read -r EVENT FILE; do
  case "$FILE" in
    "$CONFIG_DIR"/config.yaml|"$CONFIG_DIR"/config.yml|"$CONFIG_DIR"/sub_config/*.yaml|"$CONFIG_DIR"/sub_config/*.yml)
      CURRENT_TIME=$(date +%s)
      if (( CURRENT_TIME - LAST_RESTART >= DEBOUNCE_TIME )); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') 有效变更: [$EVENT] $FILE"

        if supervisorctl restart mosdns; then
          LAST_RESTART=$CURRENT_TIME
          echo "$(date '+%Y-%m-%d %H:%M:%S') 重启成功 ✅，下次可重启时间: $(date -d @"$((LAST_RESTART + DEBOUNCE_TIME))" '+%Y-%m-%d %H:%M:%S')"
        else
          echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ 重启失败，当前状态:"
          supervisorctl status mosdns
        fi
      else
        echo "$(date '+%Y-%m-%d %H:%M:%S') 防抖忽略: [$EVENT] $FILE"
      fi
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
