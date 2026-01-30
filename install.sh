#!/bin/bash
# install.sh - Mihomo 一键安装脚本 (最终修复版)

MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"
ENV_FILE="${MIHOMO_DIR}/.env"

SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)

# 检查 Root
if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 权限运行此脚本。"
    exit 1
fi

# 1. 安装依赖
echo "📦 1. 安装系统依赖..."
apt update
# 确保安装 python3-yaml 用于多机场合并
apt install -y curl wget tar gzip unzip python3 python3-pip python3-flask python3-yaml

# 2. 停止旧服务
if systemctl is-active --quiet mihomo; then
    echo "🛑 停止旧服务..."
    systemctl stop mihomo
fi

# 3. 创建目录结构
echo "📂 2. 创建/修复目录..."
mkdir -p "${MIHOMO_DIR}"
mkdir -p "${SCRIPT_DIR}"
mkdir -p "${MANAGER_DIR}"
mkdir -p "${MIHOMO_DIR}/templates"
mkdir -p "${MIHOMO_DIR}/providers"
mkdir -p "${MIHOMO_DIR}/data"

# 4. 复制文件
echo "📥 3. 部署核心文件..."
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPT_DIR}/"
chmod +x "${SCRIPT_DIR}"/*.sh

echo "📥 部署 Web 管理器..."
cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"

echo "📄 部署配置模板..."
if [ -d "${SCRIPT_ROOT}/templates" ]; then
    cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"
else
    echo "⚠️  警告: templates 文件夹缺失，请检查仓库完整性。"
fi

# 5. CLI 工具
if [ -f "${SCRIPT_ROOT}/main.sh" ]; then
    cp "${SCRIPT_ROOT}/main.sh" /usr/bin/mihomo-cli
    chmod +x /usr/bin/mihomo-cli
fi

# 6. 【关键修复】生成配置文件 (.env)
echo "🔑 4. 配置用户凭证..."
if [ -f "${ENV_FILE}" ]; then
    echo "✅ 检测到现有配置文件，跳过设置。"
else
    echo "------------------------------------------------"
    read -p "请设置 Web 面板用户名 (默认: admin): " WEB_USER
    WEB_USER=${WEB_USER:-admin}
    
    read -p "请设置 Web 面板密码 (默认: admin): " WEB_SECRET
    WEB_SECRET=${WEB_SECRET:-admin}
    
    read -p "请输入访问端口 (默认: 7838): " WEB_PORT
    WEB_PORT=${WEB_PORT:-7838}
    echo "------------------------------------------------"

    # 写入 .env 文件
    cat > "${ENV_FILE}" <<EOF
WEB_USER="${WEB_USER}"
WEB_SECRET="${WEB_SECRET}"
WEB_PORT="${WEB_PORT}"
NOTIFY_TG=false
TG_BOT_TOKEN=
TG_CHAT_ID=
NOTIFY_API=false
NOTIFY_API_URL=
SUB_URL=
CONFIG_MODE=expert
EOF
    echo "✅ 配置文件已生成: ${ENV_FILE}"
fi

# 7. 【关键修复】配置 Systemd 服务
echo "⚙️ 5. 配置系统服务 (修复启动路径)..."
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/mihomo
# 修复核心：显式指定 python3 解释器路径
ExecStart=/usr/bin/python3 /etc/mihomo/manager/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 8. 启动服务
echo "🚀 6. 启动服务..."
systemctl daemon-reload
systemctl enable mihomo
systemctl restart mihomo

# 9. 检查状态
sleep 2
if systemctl is-active --quiet mihomo; then
    IP=$(hostname -I | awk '{print $1}')
    PORT=$(grep WEB_PORT "${ENV_FILE}" | cut -d '=' -f2 | tr -d '"')
    echo "==========================================="
    echo "🎉 安装成功！服务运行正常。"
    echo "🌍 访问地址: http://${IP}:${PORT}"
    echo "==========================================="
else
    echo "❌ 服务启动失败！请运行 'systemctl status mihomo' 查看原因。"
fi
