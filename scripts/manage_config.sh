#!/bin/bash

# 1. 导入基础环境
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件！"
    exit 1
fi

CONFIG_FILE="${MIHOMO_PATH}/config.yaml"
BACKUP_FILE="${MIHOMO_PATH}/config.yaml.bak"
TEMP_FILE="/tmp/mihomo_config_new.yaml"

# 2. 核心函数：安全校验与应用
# 这是“防爆”的关键：只有校验通过，才会去动真正的配置文件
apply_config() {
    local target_file=$1
    echo "正在校验配置文件有效性..."
    
    # 使用 mihomo 内核自带的测试功能 (-t)
    ${MIHOMO_PATH}/mihomo -t -d ${MIHOMO_PATH} -f "$target_file"
    
    if [ $? -eq 0 ]; then
        echo "✅ 配置校验通过！"
        
        # 自动备份旧配置（如果存在）
        if [ -f "$CONFIG_FILE" ]; then
            cp "$CONFIG_FILE" "$BACKUP_FILE"
            echo "旧配置已备份至: $BACKUP_FILE"
        fi
        
        # 覆盖新配置
        cp "$target_file" "$CONFIG_FILE"
        
        # 尝试热重载 (如果不重启服务也能生效)
        # 如果是 HTTP API 变更，建议完全重启；这里默认尝试重载
        curl -X PUT -H "Content-Type: application/json" -d '{"path": "'$CONFIG_FILE'"}' "http://127.0.0.1:9090/configs?force=true" -s > /dev/null
        
        # 为了保险，如果是订阅更新，建议重启一次服务确保所有组件生效
        systemctl restart mihomo
        echo "配置已应用并重启服务。"
    else
        echo "❌ 配置文件校验失败！"
        echo "为了保障稳定性，本次更新已被拦截，当前运行的配置未受影响。"
        rm -f "$target_file"
        exit 1
    fi
}

# 3. 从 URL 更新 (Sub-Store / 机场链接)
update_from_url() {
    # 优先检查传入参数，如果没有则检查环境变量
    local url=$1
    if [ -z "$url" ]; then
        url=$SUB_URL
    fi
    
    if [ -z "$url" ]; then
        echo "错误：未设置订阅链接！"
        echo "请在 .env 文件中设置 SUB_URL，或作为参数传入。"
        exit 1
    fi
    
    echo "正在从订阅链接下载配置..."
    echo "地址: $url"
    
    # 下载到临时文件
    curl -L -o "$TEMP_FILE" "$url"
    
    if [ $? -ne 0 ]; then
        echo "❌ 下载失败，请检查网络或代理设置。"
        exit 1
    fi
    
    # 走统一的校验流程
    apply_config "$TEMP_FILE"
    # 清理临时文件
    rm -f "$TEMP_FILE"
}

# 4. 本地编辑模式
edit_local() {
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
    fi
    
    # 复制一份出来编辑，防止用户编辑到一半保存导致 syntax error 崩掉服务
    cp "$CONFIG_FILE" "$TEMP_FILE"
    
    # 优先使用 nano，没有则使用 vi
    if command -v nano >/dev/null 2>&1; then
        nano "$TEMP_FILE"
    else
        vi "$TEMP_FILE"
    fi
    
    # 用户退出编辑器后，进行校验
    read -p "是否应用修改？(y/n): " confirm
    if [ "$confirm" == "y" ]; then
        apply_config "$TEMP_FILE"
    else
        echo "修改已丢弃。"
    fi
    rm -f "$TEMP_FILE"
}

# 5. 指令分发
case "$1" in
    update)
        update_from_url "$2"
        ;;
    edit)
        edit_local
        ;;
    *)
        echo "用法: $0 {update [url] | edit}"
        ;;
esac
