#!/bin/bash

# 1. 导入环境
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件！"
    exit 1
fi

# 定义任务标识，方便脚本识别哪些任务是我们加的，方便删除
JOB_ID="# MIHOMO_AUTOMATION"

# 2. 添加任务函数
add_cron() {
    local schedule=$1
    local script=$2
    local comment=$3
    
    # 先检查是否已经存在
    crontab -l 2>/dev/null | grep -F "$script" > /dev/null
    if [ $? -eq 0 ]; then
        echo "⚠️  任务已存在，跳过: $comment"
    else
        # 追加任务到 crontab
        (crontab -l 2>/dev/null; echo "$schedule /bin/bash $script $JOB_ID - $comment") | crontab -
        echo "✅ 已添加任务: $comment ($schedule)"
    fi
}

# 3. 清理任务函数
remove_cron() {
    # 删除所有包含 JOB_ID 的行
    crontab -l 2>/dev/null | grep -v "$JOB_ID" | crontab -
    echo "🗑️  已清理所有 Mihomo 相关的定时任务。"
}

# 4. 菜单交互
echo "==================================="
echo "   Mihomo 自动化任务管理"
echo "==================================="
echo "1. 开启 [故障自愈] (每5分钟检查一次)"
echo "2. 开启 [Geo 自动更新] (每天凌晨4点)"
echo "3. 开启 [订阅自动更新] (每天凌晨5点)"
echo "4. 清空所有自动任务"
echo "0. 返回"
echo "==================================="
read -p "请选择: " choice

case $choice in
    1)
        # 每5分钟运行一次 watchdog
        add_cron "*/5 * * * *" "${SCRIPT_PATH}/watchdog.sh" "故障自愈看门狗"
        ;;
    2)
        # 每天 04:00 运行 update_geo
        add_cron "0 4 * * *" "${SCRIPT_PATH}/update_geo.sh" "Geo数据库更新"
        ;;
    3)
        # 每天 05:00 运行 manage_config (需传入 update 参数)
        # 注意：这里需要确保 manage_config.sh 知道默认 URL，或者在此处指定
        add_cron "0 5 * * *" "${SCRIPT_PATH}/manage_config.sh update" "订阅配置更新"
        ;;
    4)
        remove_cron
        ;;
    0)
        exit 0
        ;;
    *)
        echo "无效选项"
        ;;
esac
