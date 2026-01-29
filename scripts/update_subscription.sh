#!/bin/bash
# scripts/update_subscription.sh

# 1. 环境准备
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

CONFIG_FILE="/etc/mihomo/config.yaml"
NOTIFY_SCRIPT="/etc/mihomo/scripts/notify.sh"

# 如果没有订阅链接，直接退出
if [ -z "$SUB_URL" ]; then 
    echo "未配置 SUB_URL，跳过更新。"
    exit 0
fi

TEMP_FILE="/tmp/config_tmp.yaml"

# 2. 下载订阅
echo "正在下载订阅: $SUB_URL"
if curl -L -s --fail --retry 3 --connect-timeout 15 -o "$TEMP_FILE" "$SUB_URL"; then
    
    # 简单校验文件合法性 (是否包含 proxies 关键字)
    if grep -q "proxies" "$TEMP_FILE" || grep -q "proxy-providers" "$TEMP_FILE"; then
        
        # 3. MD5 对比 (核心去重逻辑)
        OLD_MD5=$(md5sum "$CONFIG_FILE" 2>/dev/null | awk '{print $1}')
        NEW_MD5=$(md5sum "$TEMP_FILE" | awk '{print $1}')

        if [ "$OLD_MD5" == "$NEW_MD5" ]; then
            echo "✅ 订阅内容未变更，无需更新。"
            rm -f "$TEMP_FILE"
            # 【关键】直接退出，不发送通知，也不重启
            exit 0
        fi

        # 4. 内容有变动，执行更新
        echo "🔄 检测到订阅更新，正在应用..."

        # =======================================================
        # 【升级版】 动态防回环混入 (Web UI 配置优先)
        # =======================================================
        if [ -n "$LOCAL_CIDR" ]; then
            echo "🔧 检测到本地网段设置: $LOCAL_CIDR"
            
            if grep -q "^rules:" "$TEMP_FILE"; then
                echo "➡️  正在注入 DIRECT 规则..."
                # 动态注入配置的网段
                sed -i "/^rules:/a \  - IP-CIDR,${LOCAL_CIDR},DIRECT,no-resolve" "$TEMP_FILE"
            fi
        else
            echo "⏩ 未配置本地网段 (LOCAL_CIDR)，跳过防回环注入。"
        fi
        # =======================================================

        mv "$TEMP_FILE" "$CONFIG_FILE"
        
        # 补充 UI 配置 (防止纯订阅覆盖了 WebUI 配置)
        if ! grep -q "external-controller" "$CONFIG_FILE"; then
            echo -e "\nexternal-controller: '0.0.0.0:9090'\nexternal-ui: ui\nsecret: ''" >> "$CONFIG_FILE"
        fi
        
        # 5. 重启并通知
        systemctl restart mihomo
        if [ $? -eq 0 ]; then
            bash "$NOTIFY_SCRIPT" "✅ 订阅更新成功" "检测到配置变动，已自动应用并重载服务。"
        else
            bash "$NOTIFY_SCRIPT" "⚠️ 订阅更新异常" "配置文件已更新，但服务重启失败。"
        fi
    else
        echo "❌ 下载的文件格式不正确 (未找到 proxies 字段)。"
        rm -f "$TEMP_FILE"
        # 下载了错误的文件，选择不通知或发送警告
        # bash "$NOTIFY_SCRIPT" "❌ 订阅校验失败" "下载的文件似乎不是有效的 Mihomo 配置。"
    fi
else
    echo "❌ 订阅下载失败 (网络错误)。"
    bash "$NOTIFY_SCRIPT" "❌ 订阅更新失败" "无法连接到订阅服务器，请检查网络。"
fi
