#!/bin/bash

# 1. 导入环境
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件！"
    exit 1
fi

ENV_FILE="/etc/mihomo/.env"

# 2. 保存函数
save_notify_url() {
    local url=$1
    # 如果 .env 里已经有 NOTIFY_URL，就替换这一行
    if grep -q "^NOTIFY_URL=" "$ENV_FILE"; then
        # 使用 | 作为分隔符，防止 URL 里的斜杠干扰
        sed -i "s|^NOTIFY_URL=.*|NOTIFY_URL=\"$url\"|" "$ENV_FILE"
    else
        # 如果没有，就追加到最后
        echo "" >> "$ENV_FILE"
        echo "NOTIFY_URL=\"$url\"" >> "$ENV_FILE"
    fi
    # 刷新变量
    source "$ENV_FILE"
    echo "✅ 通知地址已保存！"
}

# 3. 交互菜单
echo "==================================="
echo "       通知接口配置"
echo "==================================="
echo "当前地址: ${NOTIFY_URL:-未设置}"
echo "-----------------------------------"
echo "1. 设置/修改 通知地址"
echo "2. 发送测试消息"
echo "3. 清空通知地址 (关闭通知)"
echo "0. 返回主菜单"
echo "==================================="
read -p "请选择: " choice

case $choice in
    1)
        read -p "请输入新的通知接口 URL: " input_url
        if [ -z "$input_url" ]; then
            echo "输入为空，取消操作。"
        else
            save_notify_url "$input_url"
            
            # 顺便问一句要不要测试
            read -p "设置完成，是否立即发送一条测试消息？(y/n): " test_choice
            if [ "$test_choice" == "y" ]; then
                bash ${SCRIPT_PATH}/notify.sh "测试" "这是一条来自 Mihomo 的测试消息"
            fi
        fi
        ;;
    2)
        if [ -z "$NOTIFY_URL" ]; then
            echo "❌ 错误：尚未设置地址，请先选择 [1] 进行设置。"
        else
            echo "正在发送测试消息..."
            bash ${SCRIPT_PATH}/notify.sh "测试" "这是一条手动触发的测试消息"
            echo "发送指令已执行，请检查接收端。"
        fi
        ;;
    3)
        # 清空逻辑
        sed -i "s|^NOTIFY_URL=.*|NOTIFY_URL=\"\"|" "$ENV_FILE"
        echo "通知地址已清空，通知功能已关闭。"
        ;;
    0)
        exit 0
        ;;
    *)
        echo "无效选项"
        ;;
esac
