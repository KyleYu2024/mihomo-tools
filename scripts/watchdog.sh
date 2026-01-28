#!/bin/bash
# scripts/watchdog.sh

# 1. 导入环境
if [ -f "/etc/mihomo/.env" ]; then 
    source /etc/mihomo/.env
else 
    # 找不到环境文件时不执行，防止误判
    exit 1
fi

# 变量定义
LOG_FILE="${MIHOMO_PATH}/watchdog.log"
# 境外检测目标 (测试代理连通性)
TEST_URL_GLOBAL="https://www.google.com/generate_204"
# 国内检测目标 (测试物理网络连通性)
TEST_URL_CN="https://www.baidu.com"
# 内存阈值 (百分比)
MEM_THRESHOLD=90

# 记录日志函数
log_msg() {
    echo "$(date "+%Y-%m-%d %H:%M:%S") $1" >> "$LOG_FILE"
}

check_and_fix() {
    # ==========================================
    # A. 进程守护 (优先级最高)
    # ==========================================
    if ! systemctl is-active --quiet mihomo; then
        log_msg "[进程异常] 检测到服务未运行，正在尝试启动..."
        systemctl start mihomo
        bash "${SCRIPT_PATH}/notify.sh" "Mihomo 进程报警" "检测到进程异常退出，已尝试自动拉起服务。"
        # 刚启动完，跳过后续网络检查，给它一点时间初始化
        return 
    fi

    # ==========================================
    # B. 内存守护
    # ==========================================
    # 使用 free 获取内存占用百分比
    MEM_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)
    
    if [ "$MEM_USAGE" -gt "$MEM_THRESHOLD" ]; then
        log_msg "[内存预警] 当前占用 ${MEM_USAGE}%"
        # 仅通知，不自动重启 (除非 OOM 导致进程挂掉，由 A 处理)
        bash "${SCRIPT_PATH}/notify.sh" "⚠️ 系统内存预警" "当前系统内存占用已达 ${MEM_USAGE}%，请关注系统负载。"
    fi

    # ==========================================
    # C. 网络双重守护 (核心优化)
    # ==========================================
    # 第一步：检测境外连通性 (Google)
    # --max-time 10: 10秒超时
    # --retry 1: 失败重试1次，防止偶发抖动
    if ! curl -I -s --max-time 10 --retry 1 "$TEST_URL_GLOBAL" > /dev/null; then
        
        # Google 连不上了，进行第二步：检测国内连通性 (Baidu)
        # 用来判断是 "Mihomo 挂了" 还是 "宽带断了"
        if curl -I -s --max-time 5 --retry 1 "$TEST_URL_CN" > /dev/null; then
            
            # 场景 1: 百度能连，Google 连不上 -> 代理服务异常
            log_msg "[网络异常] 物理网络正常，但无法连接境外目标。正在重启 Mihomo..."
            
            systemctl restart mihomo
            
            # 发送通知
            bash "${SCRIPT_PATH}/notify.sh" "Mihomo 网络修复" "检测到境外连接中断（国内网络正常），已执行服务重启以尝试修复。"
            
        else
            
            # 场景 2: 百度也连不上 -> 物理断网
            log_msg "[网络忽略] 检测到物理网络中断 (国内目标无法访问)。跳过重启，等待网络恢复。"
            
            # 这里不发送通知，或者可以设置一个标志位防止每5分钟发一次通知轰炸
            # 保持安静，直到网络恢复
        fi
    fi
}

# 执行检查
check_and_fix
