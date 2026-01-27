#!/bin/bash
# scripts/update_subscription.sh
source /etc/mihomo/.env
CONFIG_FILE="/etc/mihomo/config.yaml"

if [ -z "$SUB_URL" ]; then exit 1; fi

TEMP_FILE="/tmp/config_tmp.yaml"
if curl -L -s --connect-timeout 15 -o "$TEMP_FILE" "$SUB_URL"; then
    if grep -q "proxies" "$TEMP_FILE" || grep -q "proxy-providers" "$TEMP_FILE"; then
        # MD5 对比
        OLD_MD5=$(md5sum "$CONFIG_FILE" 2>/dev/null | awk '{print $1}')
        NEW_MD5=$(md5sum "$TEMP_FILE" | awk '{print $1}')

        if [ "$OLD_MD5" == "$NEW_MD5" ]; then
            rm -f "$TEMP_FILE"
            exit 0
        fi

        mv "$TEMP_FILE" "$CONFIG_FILE"
        # 注入 UI 配置
        if ! grep -q "external-controller" "$CONFIG_FILE"; then
            echo -e "\nexternal-controller: '0.0.0.0:9090'\nexternal-ui: ui\nsecret: ''" >> "$CONFIG_FILE"
        fi
        
        systemctl restart mihomo
        bash /etc/mihomo/scripts/notify.sh "✅ 订阅更新成功" "检测到配置变动，已自动重载服务。"
    fi
fi
