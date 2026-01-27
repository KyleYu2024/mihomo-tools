#!/bin/bash
# scripts/watchdog.sh

# 1. 导入环境
if [ -f "/etc/mihomo/.env" ]; then 
    source /etc/mihomo/.env
else 
    exit 1
fi

# 变量定义 (如果没有从 .env 读到，则使用默认值)
LOG_FILE="${MIHOMO_PATH}/watchdog.log"
TEST_URL="https://www.google.com/generate_204"
MEM_THRESHOLD=90

# --- 检查函数 ---

check_and_fix() {
    # A. 进程守护：如果进程没了，直接拉起来
    if ! systemctl is-active --quiet mihomo; then
        echo "$(date): [进程异常] 检测到进程丢失，正在尝试启动..." >> "$LOG_FILE"
        systemctl start mihomo
        # 发送通知
        bash "${SCRIPT_PATH}/notify.sh" "Mihomo 进程报警" "检测到进程异常退出，已尝试自动重启服务。"
        return # 进程刚重启，跳过后续检查，等下一分钟再扫
    fi

    # B. 内存守护：如果占用过高，发送预警通知
    # 使用 free 命令计算百分比
    MEM_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
    if [ "$MEM_USAGE" -gt "$MEM_THRESHOLD" ]; then
        echo "$(date): [内存预警] 当前占用 ${MEM_USAGE}%" >> "$LOG_FILE"
        bash "${SCRIPT_PATH}/notify.sh" "⚠️ 系统内存预警" "当前系统内存占用已达 ${MEM_USAGE}%，可能影响 Mihomo 运行稳定性。"
    fi

    # C. 网络守护：如果连不上网，重启服务
    # --max-time 10 防止 curl 卡死
    # -I 仅获取头部，节省流量
    if ! curl -I -s --max-time 10 "$TEST_URL" > /dev/null; then
        echo "$(date): [网络异常] 连通性检测失败，正在重启服务..." >> "$LOG_FILE"
        systemctl restart mihomo
        # 发送通知
        bash "${SCRIPT_PATH}/notify.sh" "Mihomo 网络重连" "检测到网络连接断开，已执行服务重启以尝试修复连接。"
    fi
}

# 执行检查
check_and_fix
