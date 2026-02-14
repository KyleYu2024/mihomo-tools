#!/bin/bash

# ==========================================
# Mihomo 网关网络初始化脚本 (智能持久化版)
# ==========================================

# 1. 环境加载
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi
# 兜底路径 (防止 .env 不存在或变量缺失)
SCRIPT_PATH="${SCRIPT_PATH:-/etc/mihomo/scripts}"
CURRENT_SCRIPT="${SCRIPT_PATH}/gateway_init.sh"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 模式: check (静默保活) / init (首次运行/强制)
MODE="$1"

log() {
    # 只有非 check 模式才输出日志，避免 cron 邮件轰炸
    if [ "$MODE" != "check" ]; then
        echo -e "$1"
    fi
}

# 2. 自动识别网卡 (增强版自适应)
# --------------------------------------
# 优先检测默认路由出口，这通常是通往互联网的物理网卡
detect_interface() {
    # 方法1: 通过 ip route get 探测 (最准确)
    local iface=$(ip route get 223.5.5.5 2>/dev/null | awk '/dev/ {print $5; exit}')
    
    # 方法2: 如果方法1失败，尝试获取默认路由网卡
    if [ -z "$iface" ]; then
        iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n 1)
    fi
    
    # 方法3: 兜底 eth0
    if [ -z "$iface" ]; then
        iface="eth0"
    fi
    
    echo "$iface"
}

# 获取并导出物理网卡名称，供 patch_config.sh 使用
export PHYSICAL_IFACE=$(detect_interface)
if [ -n "$PHYSICAL_IFACE" ]; then
    # 将探测到的网卡写入 .env 以便持久化和供其他脚本使用 (如果是首次或发生变化)
    if ! grep -q "^PHYSICAL_IFACE=" "$ENV_FILE" 2>/dev/null; then
        echo "PHYSICAL_IFACE=\"$PHYSICAL_IFACE\"" >> "$ENV_FILE"
    else
        # 更新 .env 中的值 (如果不同)
        sed -i "s|^PHYSICAL_IFACE=.*|PHYSICAL_IFACE=\"$PHYSICAL_IFACE\"|" "$ENV_FILE"
    fi
fi
IFACE="$PHYSICAL_IFACE" # 兼容旧变量名

log "🌐 检测到物理出口网卡: ${GREEN}${IFACE}${NC}"

# ==========================================
# 核心功能：规则检测与应用
# ==========================================
apply_rules() {
    local changed=0

    # 0. 日志自动清理 (防止撑爆硬盘)
    # --------------------------------------
    local log_file="/var/log/mihomo.log"
    if [ -f "$log_file" ]; then
        local log_size=$(du -m "$log_file" | cut -f1)
        if [ "$log_size" -gt 10 ]; then
            log "🧹 日志文件过大 (${log_size}MB)，正在清理..."
            # 仅保留最后 5000 行
            local temp_log=$(tail -n 5000 "$log_file")
            echo "$temp_log" > "$log_file"
            log "✅ 日志已缩减。"
        fi
    fi

    # 0.1 确保 TUN 设备就绪
    # --------------------------------------
    if [ ! -c "/dev/net/tun" ]; then
        log "⚠️  TUN 设备缺失，正在尝试修复..."
        mkdir -p /dev/net
        if [ ! -c "/dev/net/tun" ]; then
            mknod /dev/net/tun c 10 200 2>/dev/null
        fi
        modprobe tun 2>/dev/null
        if [ ! -c "/dev/net/tun" ]; then
            log "❌ 无法创建 TUN 设备，TUN 模式可能不可用。"
        else
            log "✅ TUN 设备已就绪。"
            changed=1
        fi
    fi

    # A. 开启内核转发
    # --------------------------------------
    # 读取当前状态
    local ip_fwd=$(sysctl -n net.ipv4.ip_forward)
    if [ "$ip_fwd" != "1" ]; then
        sysctl -w net.ipv4.ip_forward=1 > /dev/null
        echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-mihomo-gateway.conf
        log "✅ 内核转发已开启"
        changed=1
    fi

    # B. 基础防火墙策略 (FORWARD)
    # --------------------------------------
    # 确保 FORWARD 链策略是 ACCEPT (关键！)
    # 注意：我们不再暴力 Flush 所有规则，以免误伤 Docker
    # 而是检测是否允许转发
    iptables -C FORWARD -j ACCEPT 2>/dev/null
    if [ $? -ne 0 ]; then
        # 如果没有 ACCEPT 规则，或者策略不是 ACCEPT，强制插队一条
        # (这里为了稳妥，我们直接设置默认策略，这是网关最需要的)
        iptables -P FORWARD ACCEPT
        log "✅ FORWARD 默认策略已设为 ACCEPT"
        changed=1
    fi

    # C. NAT 伪装 (Masquerade)
    # --------------------------------------
    # 检查是否已有针对该出口网卡的 MASQUERADE 规则
    iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null
    if [ $? -ne 0 ]; then
        iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
        log "✅ NAT 伪装规则已添加 -> $IFACE"
        changed=1
    fi

    # D. 关闭反向路径过滤 (RP_Filter)
    # --------------------------------------
    # 这个一般重启后会重置，所以每次都刷一遍比较保险
    local rp_changed=0
    for i in /proc/sys/net/ipv4/conf/*/rp_filter; do
        if [ "$(cat "$i")" != "0" ]; then
            echo 0 > "$i"
            rp_changed=1
        fi
    done
    if [ $rp_changed -eq 1 ]; then
        log "✅ 路径过滤限制已放宽 (RP_Filter)"
        changed=1
    fi

    # 结果反馈
    if [ $changed -eq 1 ]; then
        log "${GREEN}>>> 网关规则已修复/初始化完成。${NC}"
    else
        log "${GREEN}>>> 网关规则正常，无需变更。${NC}"
    fi
}

# ==========================================
# 自动持久化 (Auto-Persistence)
# ==========================================
ensure_cron() {
    # 检查 Crontab 中是否已有本脚本
    # 这里的 grep 查找 "gateway_init.sh check"
    if ! crontab -l 2>/dev/null | grep -qF "gateway_init.sh check"; then
        log "${YELLOW}正在添加自动保活任务 (Crontab)...${NC}"
        
        # 添加每分钟执行一次 check
        (crontab -l 2>/dev/null; echo "*/1 * * * * /bin/bash ${CURRENT_SCRIPT} check >/dev/null 2>&1") | crontab -
        
        log "✅ 保活任务已添加。即使防火墙被重置，1分钟内将自动恢复。"
    fi
}

# ==========================================
# 主流程
# ==========================================

apply_rules

# 仅在非 check 模式下(即手动执行或服务启动时)检查 cron
# 避免 cron 任务自己无限递归检查自己
if [ "$MODE" != "check" ]; then
    ensure_cron
fi
