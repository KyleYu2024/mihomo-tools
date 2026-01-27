#!/bin/bash

# ==========================================
# Mihomo 一键部署脚本
# ==========================================

SCRIPT_ROOT=$(dirname "$(readlink -f "$0")")

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 路径
INSTALL_DIR="/etc/mihomo-tools"
MIHOMO_DIR="/etc/mihomo"
SCRIPTS_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"
UI_DIR="${MIHOMO_DIR}/ui"
BIN_PATH="/usr/bin/mihomo-cli"

echo -e "${GREEN}>>> 开始安装 Mihomo + Web Manager...${NC}"

# 1. 安装系统依赖 (含 Python/Flask)
echo -e "${YELLOW}[1/8] 安装依赖...${NC}"
apt update -qq
apt install -y git curl tar gzip nano cron ca-certificates iptables unzip python3 python3-pip > /dev/null 2>&1
# 尝试安装 Flask
if ! python3 -c "import flask" &> /dev/null; then
    echo "正在安装 Flask..."
    rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
    pip3 install flask > /dev/null 2>&1
fi
echo "✅ 依赖安装完成。"

# 2. 部署文件
echo -e "${YELLOW}[2/8] 部署文件...${NC}"
mkdir -p "${SCRIPTS_DIR}" "${MIHOMO_DIR}/data" "${UI_DIR}" "${MANAGER_DIR}/templates"

# 复制脚本和主程序
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPTS_DIR}/"
cp -f "${SCRIPT_ROOT}/main.sh" "${BIN_PATH}"
chmod +x "${BIN_PATH}"
chmod +x "${SCRIPTS_DIR}"/*.sh

# 复制 Web 管理端
if [ -d "${SCRIPT_ROOT}/manager" ]; then
    cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"
else
    echo -e "${RED}❌ 未找到 manager 目录！Web 面板可能无法启动。${NC}"
fi
echo "✅ 文件部署完成。"

# 3. 日志配置 (文件日志模式 - 解决 LXC 问题)
echo -e "${YELLOW}[3/8] 配置日志系统...${NC}"
touch /var/log/mihomo.log
chmod 666 /var/log/mihomo.log
echo "✅ 日志已切换为文件模式。"

# 4. 生成 .env
echo -e "${YELLOW}[4/8] 生成环境变量...${NC}"
cat > "${MIHOMO_DIR}/.env" <<EOF
MIHOMO_PATH="/etc/mihomo"
DATA_PATH="/etc/mihomo/data"
SCRIPT_PATH="/etc/mihomo/scripts"
GH_PROXY="https://gh-proxy.com/"
EOF

# 5. 初始化网关
echo -e "${YELLOW}[5/8] 初始化网关网络...${NC}"
bash "${SCRIPTS_DIR}/gateway_init.sh"

# 6. 下载资源
echo -e "${YELLOW}[6/8] 下载核心组件...${NC}"
echo "--> 更新 Geo..."
bash "${SCRIPTS_DIR}/update_geo.sh" > /dev/null
echo "--> 安装内核..."
bash "${SCRIPTS_DIR}/install_kernel.sh" "auto"
echo "--> 下载 WebUI (Zashboard)..."
UI_URL="https://gh-proxy.com/https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
curl -L -o /tmp/ui.zip "$UI_URL"
if [ $? -eq 0 ]; then
    rm -rf "${UI_DIR:?}"/*
    unzip -o -q /tmp/ui.zip -d /tmp/ui_extract
    cp -rf /tmp/ui_extract/*/* "${UI_DIR}/"
    rm -rf /tmp/ui.zip /tmp/ui_extract
fi

# 7. 注册 Mihomo 服务 (文件日志版)
echo -e "${YELLOW}[7/8] 注册系统服务...${NC}"
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${MIHOMO_DIR}
ExecStartPre=/bin/bash ${SCRIPTS_DIR}/gateway_init.sh
ExecStart=${MIHOMO_DIR}/mihomo -d ${MIHOMO_DIR}
# === 关键：日志直写文件 ===
StandardOutput=append:/var/log/mihomo.log
StandardError=append:/var/log/mihomo.log
# ========================
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 8. 注册 Web Manager 服务
cat > /etc/systemd/system/mihomo-manager.service <<EOF
[Unit]
Description=Mihomo Web Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${MANAGER_DIR}
ExecStart=/usr/bin/python3 ${MANAGER_DIR}/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mihomo mihomo-manager
systemctl restart mihomo-manager

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   ✅ 安装完成！Web 面板: http://IP:8080 ${NC}"
echo -e "${GREEN}        zashboard 面板: http://IP:9090/ui ${NC}"
echo -e "${GREEN}=============================================${NC}"
