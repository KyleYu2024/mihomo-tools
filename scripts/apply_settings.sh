#!/bin/bash
# apply_settings.sh - 应用 .env 中的全局开关到当前 config.yaml

MIHOMO_DIR="/etc/mihomo"
ENV_FILE="${MIHOMO_DIR}/.env"
CONFIG_FILE="${MIHOMO_DIR}/config.yaml"
TEMP_FILE="/tmp/config_apply.yaml"

if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

echo "⚙️  正在将全局开关应用到当前配置..."
bash "${MIHOMO_DIR}/scripts/patch_config.sh" "$CONFIG_FILE"

if [ $? -eq 0 ]; then
    systemctl restart mihomo
    echo "🎉 配置已更新并重启服务。"
else
    echo "❌ 应用失败。"
    exit 1
fi
