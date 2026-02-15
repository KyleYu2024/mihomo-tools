#!/bin/bash
# install.sh - v1.0.7 全量优化版
# 功能：增强进度条显示，消除安装焦虑，优化 Linux 兼容性

MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"
UI_DIR="${MIHOMO_DIR}/ui"
ENV_FILE="${MIHOMO_DIR}/.env"
SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)

if [ "$(id -u)" != "0" ]; then echo "❌ 必须使用 Root 权限"; exit 1; fi

# --- 进度条函数 ---
show_progress() {
    local current=$1
    local total=$2
    local step_name=$3
    local percent=$((current * 100 / total))
    local completed=$((percent / 2))
    local remaining=$((50 - completed))
    
    printf "\r\033[K" # 清除当前行
    printf "\033[32m[%-50s]\033[0m %d%% - %s" "$(printf "%${completed}s" | tr ' ' '#')" "$percent" "$step_name"
    if [ "$current" -eq "$total" ]; then printf "\n"; fi
}

# --- 动态加载动画 (用于后台耗时操作) ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

TOTAL_STEPS=8

# --- 步骤 1: 更新系统索引 ---
show_progress 1 $TOTAL_STEPS "正在同步软件包索引 (apt update)..."
apt update -qq > /dev/null 2>&1 &
spinner $!

# --- 步骤 2: 安装依赖 ---
show_progress 2 $TOTAL_STEPS "正在安装核心依赖 (python, iptables, wget)..."
apt install -y -qq curl wget tar gzip unzip python3 python3-pip python3-flask python3-yaml iptables dnsutils iproute2 > /dev/null 2>&1 &
spinner $!

# 停止旧服务
systemctl stop mihomo >/dev/null 2>&1
systemctl stop mihomo-manager >/dev/null 2>&1
rm -f /usr/bin/mihomo /usr/bin/mihomo-core

# --- 步骤 3: 部署文件 ---
show_progress 3 $TOTAL_STEPS "正在部署脚本与管理程序文件..."
mkdir -p "${MIHOMO_DIR}" "${SCRIPT_DIR}" "${MANAGER_DIR}" "${UI_DIR}" "${MIHOMO_DIR}/templates"
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPT_DIR}/" && chmod +x "${SCRIPT_DIR}"/*.sh
cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"
[ -d "${SCRIPT_ROOT}/templates" ] && cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"
if [ -f "${SCRIPT_ROOT}/main.sh" ]; then
    cp "${SCRIPT_ROOT}/main.sh" /usr/bin/mihomo && chmod +x /usr/bin/mihomo
fi

# --- 步骤 4: 下载内核 ---
show_progress 4 $TOTAL_STEPS "正在获取并下载最新 Mihomo 内核..."
LATEST_VER=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep "tag_name" | cut -d '"' -f 4)
LATEST_VER=${LATEST_VER:-v1.18.1}
ARCH=$(uname -m)
case $ARCH in
    x86_64) URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-amd64-${LATEST_VER}.gz" ;;
    aarch64) URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-arm64-${LATEST_VER}.gz" ;;
    *) echo "❌ 不支持的架构"; exit 1 ;;
esac
wget -q -O /tmp/mihomo.gz "$URL" &
spinner $!
gzip -d -f /tmp/mihomo.gz && mv /tmp/mihomo /usr/bin/mihomo-core && chmod +x /usr/bin/mihomo-core

# --- 步骤 5: 下载面板 ---
show_progress 5 $TOTAL_STEPS "正在下载 Zashboard 面板 UI..."
rm -rf "${UI_DIR}/*"
wget -q -O /tmp/ui.zip "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip" &
spinner $!
unzip -q -o /tmp/ui.zip -d /tmp/ && cp -r /tmp/zashboard-gh-pages/* "${UI_DIR}/" && rm -rf /tmp/ui*

# --- 步骤 6: 配置向导 (交互式) ---
show_progress 6 $TOTAL_STEPS "正在进入配置向导..."
echo -e "\n--------------------------------"
if [ -f "${ENV_FILE}" ]; then
    eval $(grep -E '^[A-Z_]+=' "${ENV_FILE}" | sed 's/^/export /') >/dev/null 2>&1
    CUR_USER=${WEB_USER:-admin}
    CUR_PORT=${WEB_PORT:-7838}
    echo "检测到现有配置: 用户=$CUR_USER, 端口=$CUR_PORT"
    read -p "是否保留现有配置？(Y/n) [默认: Y]: " KEEP
    KEEP=${KEEP:-Y}
else
    KEEP="n"
fi

if [[ "$KEEP" =~ ^[Nn]$ ]]; then
    read -p "设置 Web 登录用户名 [admin]: " IN_USER; WEB_USER=${IN_USER:-admin}
    read -p "设置 Web 登录密码 [admin]: " IN_PASS; WEB_SECRET=${IN_PASS:-admin}
    read -p "设置 Web 访问端口 [7838]: " IN_PORT; WEB_PORT=${IN_PORT:-7838}
else
    WEB_USER=${WEB_USER:-admin}
    WEB_SECRET=${WEB_SECRET:-admin}
    WEB_PORT=${WEB_PORT:-7838}
fi

# 写入配置
cat > "${ENV_FILE}" <<EOF
# === 基础配置 ===
WEB_USER="${WEB_USER}"
WEB_SECRET="${WEB_SECRET}"
WEB_PORT="${WEB_PORT}"
# === 订阅配置 ===
SUB_URL="${SUB_URL:-}"
LOCAL_CIDR="${LOCAL_CIDR:-}"
TUN_ENABLED="${TUN_ENABLED:-true}"
DNS_HIJACK_ENABLED="${DNS_HIJACK_ENABLED:-true}"
# === 通知配置 ===
NOTIFY_API="${NOTIFY_API:-false}"
NOTIFY_API_URL="${NOTIFY_API_URL:-}"
# === 定时任务配置 ===
CRON_SUB_ENABLED="${CRON_SUB_ENABLED:-false}"
CRON_SUB_SCHED="${CRON_SUB_SCHED:-0 5 * * *}"
CRON_GEO_ENABLED="${CRON_GEO_ENABLED:-false}"
CRON_GEO_SCHED="${CRON_GEO_SCHED:-0 4 * * *}"
EOF
echo "--------------------------------"

# --- 步骤 7: 注册系统服务 ---
show_progress 7 $TOTAL_STEPS "正在注册 Systemd 服务并优化日志配置..."
cat > /etc/systemd/system/mihomo-manager.service <<EOF
[Unit]
Description=Mihomo Web Manager
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /etc/mihomo/manager/app.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Core
After=network.target network-online.target nss-lookup.target
[Service]
Type=simple
User=root
WorkingDirectory=${MIHOMO_DIR}
ExecStartPre=/bin/bash ${SCRIPT_DIR}/gateway_init.sh
ExecStart=/usr/bin/mihomo-core -d ${MIHOMO_DIR}
Restart=always
RestartSec=5s
LogRateLimitIntervalSec=30s
LogRateLimitBurst=1000
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
[Install]
WantedBy=multi-user.target
EOF

# 限制 Systemd 日志总量
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/mihomo-limit.conf <<EOF
[Journal]
SystemMaxUse=128M
RuntimeMaxUse=64M
EOF
systemctl restart systemd-journald > /dev/null 2>&1
systemctl daemon-reload > /dev/null 2>&1
systemctl enable mihomo-manager mihomo > /dev/null 2>&1

# --- 步骤 8: 网络初始化与启动 ---
show_progress 8 $TOTAL_STEPS "正在执行网关网络初始化并下载 Geo 数据..."
if [ -f "${SCRIPT_DIR}/gateway_init.sh" ]; then
    bash "${SCRIPT_DIR}/gateway_init.sh" > /dev/null 2>&1
fi

# 显式下载 Geo 数据库，方便用户看到进度
if [ -f "${SCRIPT_DIR}/update_geo.sh" ]; then
    echo -e "\n🌍 正在初始化 Geo 数据库 (geoip/geosite)..."
    bash "${SCRIPT_DIR}/update_geo.sh"
fi

systemctl restart mihomo-manager mihomo > /dev/null 2>&1

IP=$(hostname -I | awk '{print $1}')
echo ""
echo "========================================"
echo "🎉 所有组件已部署完成！"
echo "Web 面板地址: http://${IP}:${WEB_PORT}"
echo "✅ 网络工具包 (iptables/dnsutils) 已就绪"
echo "✅ 系统日志与内核转发已完成优化"
echo "命令行菜单: 输入 'mihomo' 即可使用"
echo "========================================"
