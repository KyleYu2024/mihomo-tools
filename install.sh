#!/bin/bash

# ==========================================
# Mihomo 一键部署脚本 (集成 Web 管理面板)
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

# 1. 安装系统依赖 (新增 python3-pip python3-flask)
echo -e "${YELLOW}[1/8] 安装依赖 (含 Python环境)...${NC}"
apt update -qq
apt install -y git curl tar gzip nano cron ca-certificates iptables unzip python3 python3-pip > /dev/null 2>&1
# 尝试安装 Flask (如果 apt 没有 flask，就用 pip)
if ! python3 -c "import flask" &> /dev/null; then
    echo "正在通过 pip 安装 Flask..."
    # 兼容不同系统的 pip 行为
    rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
    pip3 install flask > /dev/null 2>&1
fi
echo "✅ 依赖安装完成。"

# 2. 部署脚本文件
echo -e "${YELLOW}[2/8] 部署脚本文件...${NC}"
mkdir -p "${SCRIPTS_DIR}" "${MIHOMO_DIR}/data" "${UI_DIR}" "${MANAGER_DIR}/templates"

# 复制 Shell 脚本
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPTS_DIR}/"
cp -f "${SCRIPT_ROOT}/main.sh" "${BIN_PATH}"
chmod +x "${BIN_PATH}"
chmod +x "${SCRIPTS_DIR}"/*.sh

# 复制 Python 管理端 (假设你已经把上面提到的 manager 文件夹放到了 GitHub 仓库根目录)
if [ -d "${SCRIPT_ROOT}/manager" ]; then
    cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"
else
    echo -e "${RED}❌ 未找到 manager 目录！Web 管理端将无法启动。${NC}"
fi

echo "✅ 文件部署完成。"

# 3. 修复日志
echo -e "${YELLOW}[3/8] 优化系统日志...${NC}"
mkdir -p /var/log/journal
if ! grep -q "^Storage=persistent" /etc/systemd/journald.conf; then
    sed -i 's/^Storage=/#Storage=/' /etc/systemd/journald.conf
    echo "Storage=persistent" >> /etc/systemd/journald.conf
fi
systemctl restart systemd-journald >/dev/null 2>&1 || true
echo "✅ 日志配置完成。"

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
echo "--> 下载 Zashboard..."
UI_URL="https://gh-proxy.com/https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
curl -L -o /tmp/ui.zip "$UI_URL"
if [ $? -eq 0 ]; then
    rm -rf "${UI_DIR:?}"/*
    unzip -o -q /tmp/ui.zip -d /tmp/ui_extract
    cp -rf /tmp/ui_extract/*/* "${UI_DIR}/"
    rm -rf /tmp/ui.zip /tmp/ui_extract
else
    echo "❌ 面板下载失败。"
fi

# 7. 注册 Mihomo 服务
echo -e "${YELLOW}[7/8] 注册 Mihomo 服务...${NC}"
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
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 8. 注册 Web Manager 服务 (新功能)
echo -e "${YELLOW}[8/8] 注册 Web 管理端服务...${NC}"
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
systemctl enable mihomo-manager
systemctl restart mihomo-manager

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   ✅ 全栈安装完成！(Mihomo + Web Manager) ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "🔗 Web 管理地址:  http://<你的IP>:8080"
echo -e "🔗 Dashboard地址: http://<你的IP>:9090/ui"
echo -e "=============================================${NC}"
