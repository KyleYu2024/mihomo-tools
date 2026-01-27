#!/bin/bash
# scripts/notify.sh

# 引入环境变量
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

TITLE="$1"
CONTENT="$2"
# 获取完整日期时间 (例如: 2026-01-27 12:30:59)
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# --- 发送逻辑 ---

# 1. Telegram (HTML 格式)
if [[ "$NOTIFY_TG" == "true" && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    # 构造消息结构:
    # 标题 (加粗)
    # 内容
    # 📅 YYYY-MM-DD HH:MM:SS (移到了最后)
    TG_MSG="<b>${TITLE}</b>%0A${CONTENT}%0A%0A📅 ${CURRENT_TIME}"
    
    curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="${TG_MSG}" \
        -d parse_mode="HTML"
fi

# 2. Webhook API (JSON 格式)
if [[ "$NOTIFY_API" == "true" && -n "$NOTIFY_API_URL" ]]; then
    # 构造内容: 内容 [时间]
    API_MSG="${CONTENT} [${CURRENT_TIME}]"
    
    # JSON 转义处理
    SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
    SAFE_MSG=$(echo "$API_MSG" | sed 's/"/\\"/g')

    curl -s -o /dev/null -X POST \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"${SAFE_TITLE}\", \"message\": \"${SAFE_MSG}\"}" \
        "$NOTIFY_API_URL"
fi
