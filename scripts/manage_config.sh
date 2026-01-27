#!/bin/bash

if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; else echo "错误：未找到 .env"; exit 1; fi

CONFIG_FILE="${MIHOMO_PATH}/config.yaml"
BACKUP_FILE="${MIHOMO_PATH}/config.yaml.bak"
TEMP_FILE="/tmp/mihomo_config_new.yaml"

# --- 核心：安全校验与应用 ---
apply_config() {
    local target_file=$1
    echo "正在校验配置文件有效性..."
    
    ${MIHOMO_PATH}/mihomo -t -d ${MIHOMO_PATH} -f "$target_file"
    
    if [ $? -eq 0 ]; then
        echo "✅ 配置校验通过！"
        if [ -f "$CONFIG_FILE" ]; then cp "$CONFIG_FILE" "$BACKUP_FILE"; fi
        cp "$target_file" "$CONFIG_FILE"
        
        curl -X PUT -H "Content-Type: application/json" -d '{"path": "'$CONFIG_FILE'"}' "http://127.0.0.1:9090/configs?force=true" -s > /dev/null
        systemctl restart mihomo
        echo "配置已应用并重启服务。"
        
        # --- 埋点：成功通知 ---
        bash ${SCRIPT_PATH}/notify.sh "Mihomo 通知" "配置/订阅 已成功更新并应用。"
    else
        echo "❌ 配置文件校验失败！更新已取消。"
        rm -f "$target_file"
        
        # --- 埋点：失败报警 (很重要！) ---
        bash ${SCRIPT_PATH}/notify.sh "Mihomo 错误" "新下载的配置校验失败！更新已被拦截，当前服务未受影响。"
        exit 1
    fi
}

# --- 保存订阅链接 ---
save_url_to_env() {
    local url=$1
    local env_file="/etc/mihomo/.env"
    if grep -q "^SUB_URL=" "$env_file"; then
        sed -i "s|^SUB_URL=.*|SUB_URL=\"$url\"|" "$env_file"
    else
        echo "" >> "$env_file"
        echo "SUB_URL=\"$url\"" >> "$env_file"
    fi
    echo "✅ 订阅链接已保存。"
}

# --- 下载逻辑 ---
update_from_url() {
    local url=$1
    if [ -z "$url" ]; then url=$SUB_URL; fi
    
    if [ -z "$url" ]; then
        echo "未检测到订阅链接。"
        read -p "请输入订阅链接: " input_url
        if [ -z "$input_url" ]; then echo "取消"; exit 1; fi
        url=$input_url
        read -p "是否保存此链接？(y/n): " save_choice
        if [ "$save_choice" == "y" ]; then save_url_to_env "$url"; fi
    fi
    
    echo "正在下载: $url"
    curl -L -o "$TEMP_FILE" "$url"
    if [ $? -ne 0 ]; then
        echo "❌ 下载失败。"
        # --- 埋点：下载失败通知 ---
        bash ${SCRIPT_PATH}/notify.sh "Mihomo 警告" "订阅文件下载失败，请检查网络或链接。"
        exit 1
    fi
    apply_config "$TEMP_FILE"
    rm -f "$TEMP_FILE"
}

edit_local() {
    if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi
    cp "$CONFIG_FILE" "$TEMP_FILE"
    if command -v nano >/dev/null 2>&1; then nano "$TEMP_FILE"; else vi "$TEMP_FILE"; fi
    read -p "是否应用修改？(y/n): " confirm
    if [ "$confirm" == "y" ]; then apply_config "$TEMP_FILE"; else echo "已丢弃"; rm -f "$TEMP_FILE"; fi
}

case "$1" in
    update) update_from_url "$2" ;;
    edit) edit_local ;;
    *) echo "用法: $0 {update [url] | edit}" ;;
esac
