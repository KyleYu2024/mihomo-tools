#!/bin/bash
# scripts/update_subscription.sh

source /etc/mihomo/.env
CONFIG_FILE="/etc/mihomo/config.yaml"

if [ -z "$SUB_URL" ]; then
    bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "未配置订阅链接 (SUB_URL 为空)"
    exit 1
fi

# 下载到临时文件
if curl -L -s -o /tmp/config_tmp.yaml "$SUB_URL"; then
    # 简单校验
    if grep -q "proxies" /tmp/config_tmp.yaml || grep -q "proxy-providers" /tmp/config_tmp.yaml; then
        mv /tmp/config_tmp.yaml "$CONFIG_FILE"
        
        # 补全 UI 配置
        if ! grep -q "external-ui" "$CONFIG_FILE"; then
            echo -e "\nexternal-controller: '0.0.0.0:9090'\nexternal-ui: ui\nsecret: ''" >> "$CONFIG_FILE"
        fi
        
        systemctl restart mihomo
        bash /etc/mihomo/scripts/notify.sh "✅ 订阅更新成功" "配置文件已更新并重载服务。"
    else
        bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "下载的文件格式不正确。"
    fi
else
    bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "网络下载错误。"
fi
