#!/bin/bash
# install.sh - Mihomo Tools 一键安装脚本
# 特性：自动获取最新内核 + 双服务架构 + 友好交互提示

MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"
UI_DIR="${MIHOMO_DIR}/ui"
ENV_FILE="${MIHOMO_DIR}/.env"
SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)

if [ "$(id -u)" != "0" ]; then echo "❌ 必须使用 Root 权限"; exit 1; fi

echo "📦 1. 准备环境..."
apt update && apt install -y curl wget tar gzip unzip python3 python3-pip python3-flask python3-yaml

# 停止旧服务
systemctl stop mihomo >/dev/null 2>&1
systemctl stop mihomo-manager >/dev/null 2>&1
rm -f /usr/bin/mihomo /usr/bin/mihomo-cli

echo "📂 2. 部署文件..."
mkdir -p "${MIHOMO_DIR}" "${SCRIPT_DIR}" "${MANAGER_DIR}" "${UI_DIR}" "${MIHOMO_DIR}/templates"
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPT_DIR}/" && chmod +x "${SCRIPT_DIR}"/*.sh
cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"
[ -d "${SCRIPT_ROOT}/templates" ] && cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"

# === 安装核心组件 ===
echo "⬇️  3. 安装核心组件..."

# 3.1 安装菜单
if [ -f "${SCRIPT_ROOT}/main.sh" ]; then
    cp "${SCRIPT_ROOT}/main.sh" /usr/bin/mihomo
    chmod +x /usr/bin/mihomo
    echo "✅ 管理菜单已安装 (命令: mihomo)"
fi

# 3.2 智能下载最新内核
echo "正在检查最新版本..."
LATEST_VER=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep "tag_name" | cut -d '"' -f 4)
if [ -z "$LATEST_VER" ]; then
    LATEST_VER="v1.18.1" # 获取失败时的保底版本
    echo "⚠️ 获取最新版本失败，将使用稳定版: $LATEST_VER"
else
    echo "✅ 发现最新版本: $LATEST_VER"
fi

ARCH=$(uname -m)
case $ARCH in
    x86_64) URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-amd64-${LATEST_VER}.gz" ;;
    aarch64) URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-arm64-${LATEST_VER}.gz" ;;
    *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

wget -O /tmp/mihomo.gz "$URL" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    gzip -d -f /tmp/mihomo.gz
    mv /tmp/mihomo /usr/bin/mihomo-core
    chmod +x /usr/bin/mihomo-core
    echo "✅ 内核安装完成 ($LATEST_VER)"
else
    echo "❌ 内核下载失败，请检查网络"
fi

# 3.3 下载面板
rm -rf "${UI_DIR}/*"
wget -O /tmp/ui.zip "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip" >/dev/null 2>&1 && unzip -q -o /tmp/ui.zip -d /tmp/ && cp -r /tmp/zashboard-gh-pages/* "${UI_DIR}/" && rm -rf /tmp/ui*

# === 配置向导 (优化交互提示) ===
echo "🔑 4. 配置账户..."
DEFAULT_USER="admin"; DEFAULT_PASS="admin"; DEFAULT_PORT="7838"

if [ -f "${ENV_FILE}" ]; then
    # 如果已有配置文件，尝试保留
    source "${ENV_FILE}"
    CUR_USER=${WEB_USER:-admin}
    CUR_PASS=${WEB_SECRET:-admin}
    CUR_PORT=${WEB_PORT:-7838}
    
    echo "检测到现有配置: 用户=$CUR_USER, 端口=$CUR_PORT"
    read -p "是否保留现有配置？(Y/n) [默认: Y]: " KEEP
    KEEP=${KEEP:-Y}
else
    KEEP="n"
fi

if [[ "$KEEP" =~ ^[Nn]$ ]]; then
    # === 重新输入配置 ===
    read -p "请输入面板用户名 [默认: admin]: " IN_USER
    WEB_USER=${IN_USER:-admin}
    
    read -p "请输入面板密码 [默认: admin]: " IN_PASS
    WEB_SECRET=${IN_PASS:-admin}
    
    # 【这里增加了明确的提示】
    read -p "请输入面板端口 [默认: 7838]: " IN_PORT
    WEB_PORT=${IN_PORT:-7838}
else
    # === 使用旧配置 ===
    WEB_USER=${WEB_USER:-$DEFAULT_USER}
    WEB_SECRET=${WEB_SECRET:-$DEFAULT_PASS}
    WEB_PORT=${WEB_PORT:-$DEFAULT_PORT}
fi

# 写入配置
cat > "${ENV_FILE}" <<EOF
WEB_USER="${WEB_USER}"
WEB_SECRET="${WEB_SECRET}"
WEB_PORT="${WEB_PORT}"
SUB_URL=${SUB_URL:-}
SUB_URL_RAW=${SUB_URL_RAW:-}
SUB_URL_AIRPORT=${SUB_URL_AIRPORT:-}
CONFIG_MODE=${CONFIG_MODE:-airport}
EOF

# === 注册服务 ===
echo "⚙️ 5. 注册服务..."
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
After=network.target
[Service]
Type=simple
User=root
ExecStart=/bin/bash -c "/usr/bin/mihomo-core -d /etc/mihomo > /var/log/mihomo.log 2>&1"
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mihomo-manager mihomo
systemctl restart mihomo-manager mihomo

# 获取本机 IP 用于提示
IP=$(hostname -I | awk '{print $1}')
echo "========================================"
echo "🎉 安装完成！当前内核: $LATEST_VER"
echo "Web 面板地址: http://${IP}:${WEB_PORT}"
echo "用户名: ${WEB_USER}"
echo "密  码: ${WEB_SECRET}"
echo "----------------------------------------"
echo "命令行菜单: 输入 'mihomo' 即可使用"
echo "========================================"
