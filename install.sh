#!/bin/bash

# ==========================================
# Mihomo 一键部署脚本 (交互密码版)
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
ENV_FILE="${MIHOMO_DIR}/.env"

echo -e "${GREEN}>>> 开始安装 Mihomo + Web Manager...${NC}"

# 1. 安装系统依赖
echo -e "${YELLOW}[1/8] 安装依赖...${NC}"
apt update -qq
apt install -y git curl tar gzip nano cron ca-certificates iptables unzip python3 python3-pip > /dev/null 2>&1
if ! python3 -c "import flask" &> /dev/null; then
    echo "正在安装 Flask..."
    rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
    pip3 install flask > /dev/null 2>&1
fi
echo "✅ 依赖安装完成。"

# 2. 部署文件
echo -e "${YELLOW}[2/8] 部署文件...${NC}"
mkdir -p "${SCRIPTS_DIR}" "${MIHOMO_DIR}/data" "${UI_DIR}" "${MANAGER_DIR}/templates"

cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPTS_DIR}/"
cp -f "${SCRIPT_ROOT}/main.sh" "${BIN_PATH}"
chmod +x "${BIN_PATH}"
chmod +x "${SCRIPTS_DIR}"/*.sh

if [ -d "${SCRIPT_ROOT}/manager" ]; then
    cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"
else
    echo -e "${RED}❌ 未找到 manager 目录！Web 面板可能无法启动。${NC}"
fi
echo "✅ 文件部署完成。"

# 3. 日志配置
echo -e "${YELLOW}[3/8] 配置日志系统...${NC}"
touch /var/log/mihomo.log
chmod 666 /var/log/mihomo.log
echo "✅ 日志已切换为文件模式。"

# 4. 生成 .env (基础配置)
echo -e "${YELLOW}[4/8] 检查配置环境...${NC}"
if [ ! -f "$ENV_FILE" ]; then
    echo "--> 生成默认 .env..."
    cat > "$ENV_FILE" <<EOF
MIHOMO_PATH="/etc/mihomo"
DATA_PATH="/etc/mihomo/data"
SCRIPT_PATH="/etc/mihomo/scripts"
GH_PROXY="https://gh-proxy.com/"
EOF
else
    echo "✅ 保留现有配置。"
fi

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

# 7. 注册服务
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
StandardOutput=append:/var/log/mihomo.log
StandardError=append:/var/log/mihomo.log
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

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

# ==========================================
# 新增：交互式密码设置函数
# ==========================================
setup_auth() {
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}      🔐  Web 面板安全设置向导      ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    
    # 检测是否已存在密码
    local has_auth=0
    if grep -q "WEB_SECRET=" "$ENV_FILE"; then
        has_auth=1
        echo -e "${YELLOW}检测到已存在登录配置。${NC}"
        read -p "是否重置用户名和密码？(y/n) [n]: " reset_choice
        if [[ "$reset_choice" != "y" ]]; then
            echo "--> 跳过密码设置，使用现有账号。"
            return
        fi
    fi
    
    echo -e "请设置登录 Web 面板的账号密码。"
    
    # 1. 输入用户名
    read -p "请输入用户名 (默认: admin): " input_user
    local user=${input_user:-admin}
    
    # 2. 输入密码 (循环直到匹配)
    local pass=""
    while true; do
        echo -n "请输入密码: "
        read -s pass1
        echo ""
        
        if [ -z "$pass1" ]; then
            echo -e "${RED}❌ 密码不能为空！请重试。${NC}"
            continue
        fi
        
        echo -n "请再次输入以确认: "
        read -s pass2
        echo ""
        
        if [ "$pass1" == "$pass2" ]; then
            pass="$pass1"
            break
        else
            echo -e "${RED}❌ 两次输入的密码不一致，请重试。${NC}"
        fi
    done
    
    # 3. 写入 .env
    # 辅助函数：如果存在则替换，不存在则追加
    update_env() {
        local key=$1
        local val=$2
        if grep -q "^${key}=" "$ENV_FILE"; then
            sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$ENV_FILE"
        else
            echo "${key}=\"${val}\"" >> "$ENV_FILE"
        fi
    }
    
    update_env "WEB_USER" "$user"
    update_env "WEB_SECRET" "$pass"
    
    echo -e "${GREEN}✅ 账号密码已保存 (用户: $user)${NC}"
}

# 执行密码设置
setup_auth

# 重启服务以应用最新的密码
echo -e "${YELLOW}正在启动服务...${NC}"
systemctl restart mihomo-manager

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   ✅ 安装全部完成！${NC}"
echo -e "${GREEN}   Web 面板: http://IP:7838 ${NC}"
echo -e "${GREEN}=============================================${NC}"
