#!/bin/bash

# 1. 导入基础环境
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    exit 0
fi

# 2. 检查是否配置了通知地址
if [ -z "$NOTIFY_URL" ]; then
    # 没配置就不发，也不报错，静默退出
    exit 0
fi

# 3. 获取参数
# 用法: bash notify.sh "标题" "内容"
TITLE="$1"
CONTENT="$2"
TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 内容追加时间戳，更清晰
FULL_CONTENT="[${TIME}] ${CONTENT}"

# 4. 发送 Webhook (POST JSON)
# 注意：这里简单的处理了 JSON 格式，如果内容里有双引号可能会导致 JSON 格式错误
# 但为了保持轻量（不依赖 jq），暂时这样处理，日常使用足够
curl -s -o /dev/null -X POST \
     -H "Content-Type: application/json" \
     -d "{\"title\": \"${TITLE}\", \"content\": \"${FULL_CONTENT}\"}" \
     "${NOTIFY_URL}"

# 仅供调试用，实际运行静默
# echo "通知已发送: $TITLE"
