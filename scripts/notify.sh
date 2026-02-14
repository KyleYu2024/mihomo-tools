#!/bin/bash
# scripts/notify.sh

# 1. 引入环境变量
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

TITLE="$1"
CONTENT="$2"
# 获取当前时间
TIME_STR=$(TZ=Asia/Shanghai date "+%Y-%m-%d %H:%M:%S")

# --- 发送逻辑 ---

# 1. Telegram (保持不变)
if [[ "$NOTIFY_TG" == "true" && -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    FULL_TEXT="<b>${TITLE}</b>%0A${CONTENT}%0A%0A📅 ${TIME_STR}"
    curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="${FULL_TEXT}" \
        -d parse_mode="HTML"
fi

# 2. Webhook API (修复版)
if [[ "$NOTIFY_API" == "true" && -n "$NOTIFY_API_URL" ]]; then
    # 构造正文: 内容 + 换行 + 时间
    COMBINED_MSG="${CONTENT}\n\n📅 ${TIME_STR}"
    
    # JSON 转义 (处理引号和换行)
    SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')
    # 处理正文中的换行和引号
    SAFE_MSG=$(echo "$COMBINED_MSG" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')

    # 【核心修改】将 key 从 "message" 改为 "content" 以匹配您的模板
    curl -s -o /dev/null -X POST \
        -H "Content-Type: application/json" \
        -d "{\"title\": \"${SAFE_TITLE}\", \"content\": \"${SAFE_MSG}\"}" \
        "$NOTIFY_API_URL"
fi
