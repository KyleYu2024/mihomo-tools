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
# 定义虚拟环境路径
VENV_DIR="${INSTALL_DIR}/venv"
PYTHON_BIN="${VENV_DIR}/bin/python3"
PIP_BIN="${VENV_DIR}/bin/pip"

echo -e "${GREEN}>>> 开始安装 Mihomo + Web Manager...${NC}"

# 1. 安装系统依赖 (新增 python3-venv)
echo -e "${YELLOW}[1/8] 安装依赖...${NC}"
apt update -qq
# 注意：这里增加了 python3-venv
apt install -y git curl tar gzip nano cron ca-certificates iptables unzip python3 python3-pip python3-venv > /dev/null 2>&1
echo "✅ 系统基础依赖安装完成。"

# 2. 初始化 Python 虚拟环境 (这是核心改动)
echo -e "${YELLOW}[2/8] 配置 Python 虚拟环境...${NC}"
mkdir -p "${INSTALL_DIR}"

if [ ! -d "${VENV_DIR}" ]; then
    echo "--> 正在创建虚拟环境..."
    python3 -m venv "${VENV_DIR}"
fi

# 在虚拟环境中安装 Flask
echo "--> 正在安装 Python 依赖 (Flask)..."
"${PIP_BIN}" install flask > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Python 环境配置完成。"
else
    echo -e "${RED}❌ Python 依赖安装失败，请检查网络或源。${NC}"
    # 虽然失败但不退出，尝试继续，但 Web 面板可能无法启动
fi

# 3. 部署文件
echo -e "${YELLOW}[3/8] 部署文件...${NC}"
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

# 4. 日志配置
echo -e "${YELLOW}[4/8] 配置日志系统...${NC}"
touch /var/log/mihomo.log
chmod 666 /var/log/mihomo.log
echo "✅ 日志已切换为文件模式。"

# 5. 生成 .env (智能防覆盖)
echo -e "${YELLOW}[5/8] 检查配置环境...${NC}"
if [ -f "${MIHOMO_DIR}/.env" ]; then
    echo "✅ 检测到配置文件 (.env) 已存在，跳过初始化，保留您的原有配置。"
else
    echo "--> 生成默认 .env..."
    cat > "${MIHOMO_DIR}/.env" <<EOF
MIHOMO_PATH="/etc/mihomo"
DATA_PATH="/etc/mihomo/data"
SCRIPT_PATH="/etc/mihomo/scripts"
GH_PROXY="https://gh-proxy.com/"
EOF
fi

# 6. 初始化网关
echo -e "${YELLOW}[6/8] 初始化网关网络...${NC}"
bash "${SCRIPTS_DIR}/gateway_init.sh"

# 7. 下载资源
echo -e "${YELLOW}[7/8] 下载核心组件...${NC}"
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

# 8. 注册服务 (关键修改：使用虚拟环境的 Python)
echo -e "${YELLOW}[8/8] 注册系统服务...${NC}"

# 8.1 Mihomo 主服务
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
StandardOutput=append:/var/log/mihomo.log
StandardError=append:/var/log/mihomo.log
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 8.2 Web Manager 服务 (指向 venv python)
cat > /etc/systemd/system/mihomo-manager.service <<EOF
[Unit]
Description=Mihomo Web Manager
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${MANAGER_DIR}
# 修改点：使用虚拟环境中的 python3 绝对路径
ExecStart=${PYTHON_BIN} ${MANAGER_DIR}/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mihomo mihomo-manager
systemctl restart mihomo-manager

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   ✅ 安装完成！Web 面板: http://IP:8080 ${NC}"
echo -e "${GREEN}          zashboard 面板: http://IP:9090/ui ${NC}"
echo -e "${GREEN}=============================================${NC}"
