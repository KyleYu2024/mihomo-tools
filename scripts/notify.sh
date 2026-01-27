#!/bin/bash
# scripts/notify.sh

# 1. 引入环境变量
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

TITLE="$1"
CONTENT="$2"
# 获取当前时间 (例如: 2026-01-27 12:30:59)
TIME_STR=$(date "+%Y-%m-%d %H:%M:%S")

# --- 发送逻辑 ---

# 1. Telegram (HTML 格式)
if [[ "$NOTIFY_TG" == "true" && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    # 构造消息内容，强制在最后换两行并加上时间
    # %0A 是 URL 编码的换行符
    FULL_TEXT="<b>${TITLE}</b>%0A${CONTENT}%0A%0A📅 ${TIME_STR}"
    
    curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="${FULL_TEXT}" \
        -d parse_mode="HTML"
fi

# 2. Webhook API (JSON 格式)
if [[ "$NOTIFY_API" == "true" && -n "$NOTIFY_API_URL" ]]; then
    # 构造内容: 内容 + 换行 + 时间
    # 为了 JSON 安全，我们手动拼接
    COMBINED_MSG="${CONTENT}\n📅 ${TIME_STR}"
    
    # JSON 转义 (处理引号和换行)
    # 这里的 sed 逻辑是将双引号转义，确保 JSON 格式合法
    SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
    SAFE_MSG=$(echo "$COMBINED_MSG" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')

    curl -s -o /dev/null -X POST \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"${SAFE_TITLE}\", \"message\": \"${SAFE_MSG}\"}" \
        "$NOTIFY_API_URL"
fi
