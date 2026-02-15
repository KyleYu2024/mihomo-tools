#!/bin/bash
# update_subscription.sh - 订阅更新 (下载完整配置文件并应用补丁)

MIHOMO_DIR="/etc/mihomo"
ENV_FILE="${MIHOMO_DIR}/.env"
CONFIG_FILE="${MIHOMO_DIR}/config.yaml"
BACKUP_DIR="${MIHOMO_DIR}/backup"
NOTIFY_SCRIPT="${MIHOMO_DIR}/scripts/notify.sh"
TEMP_NEW="/tmp/config_generated.yaml"

# 1. 加载环境变量
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

mkdir -p "$BACKUP_DIR"

if [ -z "$SUB_URL" ]; then
    echo "❌ 未配置订阅链接，跳过下载。"
    exit 0
fi

echo "⬇️  正在从链接下载完整配置文件..."
wget --no-check-certificate -O "$TEMP_NEW" "$SUB_URL" >/dev/null 2>&1

if [ $? -ne 0 ] || [ ! -s "$TEMP_NEW" ]; then
    echo "❌ 下载失败。"
    bash "$NOTIFY_SCRIPT" "❌ 订阅更新失败" "无法从链接下载配置文件，请检查网络或链接是否有效。"
    rm -f "$TEMP_NEW"
    exit 1
fi

# 2. 应用通用补丁 (注入防回环规则与 TUN/DNS 开关)
bash "${MIHOMO_DIR}/scripts/patch_config.sh" "$TEMP_NEW"

# 3. 校验、应用与通知
if [ ! -s "$TEMP_NEW" ]; then
    rm -f "$TEMP_NEW"
    exit 1
fi

FILE_CHANGED=0
if [ -f "$CONFIG_FILE" ]; then
    if cmp -s "$TEMP_NEW" "$CONFIG_FILE"; then
        echo "✅ 配置无变更。"
        FILE_CHANGED=0
    else
        echo "⚠️  配置有变更。"
        FILE_CHANGED=1
    fi
else
    FILE_CHANGED=1
fi

if [ "$FILE_CHANGED" -eq 1 ]; then
    cp "$CONFIG_FILE" "${BACKUP_DIR}/config_$(date +%Y%m%d%H%M).yaml" 2>/dev/null
    mv "$TEMP_NEW" "$CONFIG_FILE"
    systemctl restart mihomo
    echo "🎉 订阅配置已更新并应用。"
    bash "$NOTIFY_SCRIPT" "♻️ 订阅更新成功" "配置文件已根据订阅链接成功同步。"
else
    rm -f "$TEMP_NEW"
fi
