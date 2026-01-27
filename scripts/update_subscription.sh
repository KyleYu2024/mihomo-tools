#!/bin/bash
# scripts/update_subscription.sh

source /etc/mihomo/.env
CONFIG_FILE="/etc/mihomo/config.yaml"
BACKUP_FILE="/etc/mihomo/config.yaml.bak"

# 1. 检查订阅链接
if [ -z "$SUB_URL" ]; then
    bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "未配置订阅链接 (SUB_URL 为空)"
    exit 1
fi

echo "正在下载订阅: $SUB_URL"

# 2. 下载到临时文件 (增加超时参数，防止卡死)
curl -L -s --connect-timeout 15 -m 30 -o /tmp/config_tmp.yaml "$SUB_URL"

# 3. 校验下载结果
if [ $? -ne 0 ]; then
    bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "网络下载超时或连接失败。"
    exit 1
fi

# 4. 校验文件内容 (必须包含 proxies 关键字)
if grep -q "proxies" /tmp/config_tmp.yaml || grep -q "proxy-providers" /tmp/config_tmp.yaml; then
    # 备份旧配置
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
    fi
    
    mv /tmp/config_tmp.yaml "$CONFIG_FILE"
    
    # === 关键修复：智能注入面板配置 ===
    # 很多机场订阅不包含 external-controller，导致覆盖后面板打不开
    # 这里我们强制把面板配置写进去
    if ! grep -q "external-controller" "$CONFIG_FILE"; then
        echo -e "\n# === 自动注入面板配置 ===" >> "$CONFIG_FILE"
        echo "external-controller: '0.0.0.0:9090'" >> "$CONFIG_FILE"
        echo "external-ui: ui" >> "$CONFIG_FILE"
        echo "secret: ''" >> "$CONFIG_FILE"
    else
        # 如果有 controller 但没有 ui 路径，尝试修正
        if ! grep -q "external-ui" "$CONFIG_FILE"; then
            sed -i '/external-controller/a external-ui: ui' "$CONFIG_FILE"
        fi
    fi
    
    # 5. 重启服务
    systemctl restart mihomo
    
    bash /etc/mihomo/scripts/notify.sh "✅ 订阅更新成功" "配置文件已覆盖，面板配置已自动修复。"
    echo "更新成功！"
else
    rm -f /tmp/config_tmp.yaml
    bash /etc/mihomo/scripts/notify.sh "❌ 订阅更新失败" "下载的文件格式不正确 (非 YAML 配置)。"
    exit 1
fi
