#!/bin/bash
# install.sh - Mihomo 一键安装脚本

MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"
UI_DIR="${MIHOMO_DIR}/ui"
ENV_FILE="${MIHOMO_DIR}/.env"

SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)

# 检查 Root
if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 权限运行此脚本。"
    exit 1
fi

# ==========================================
# 1. 基础环境准备
# ==========================================
echo "📦 1. 安装系统依赖..."
apt update
apt install -y curl wget tar gzip unzip python3 python3-pip python3-flask python3-yaml

# 停止旧服务
if systemctl is-active --quiet mihomo; then
    echo "🛑 停止旧服务..."
    systemctl stop mihomo
fi

# ==========================================
# 2. 部署核心文件 (Python 管理器)
# ==========================================
echo "📂 2. 部署管理程序..."
mkdir -p "${MIHOMO_DIR}" "${SCRIPT_DIR}" "${MANAGER_DIR}" "${UI_DIR}"
mkdir -p "${MIHOMO_DIR}/templates" "${MIHOMO_DIR}/providers" "${MIHOMO_DIR}/data"

# 复制脚本和管理器代码
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPT_DIR}/"
chmod +x "${SCRIPT_DIR}"/*.sh
cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"

# 部署模板文件 (重要)
if [ -d "${SCRIPT_ROOT}/templates" ]; then
    echo "📄 部署配置模板..."
    cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"
else
    echo "⚠️  警告: templates 文件夹缺失，请检查仓库完整性。"
fi

# ==========================================
# 3. 下载/更新 Mihomo 内核 (自动判断架构)
# ==========================================
echo "⬇️  3. 下载 Mihomo 内核..."
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-amd64-v1.18.1.gz"
        ;;
    aarch64)
        DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-arm64-v1.18.1.gz"
        ;;
    *)
        echo "❌ 不支持的架构: $ARCH"
        exit 1
        ;;
esac

# 下载并解压
wget -O /tmp/mihomo.gz "$DOWNLOAD_URL"
if [ $? -eq 0 ]; then
    gzip -d -f /tmp/mihomo.gz
    mv /tmp/mihomo /usr/bin/mihomo-cli
    chmod +x /usr/bin/mihomo-cli
    echo "✅ 内核安装成功: $(/usr/bin/mihomo-cli -v)"
else
    echo "❌ 内核下载失败，请检查网络。"
fi

# ==========================================
# 4. 下载/部署 UI 面板 (Zashboard)
# ==========================================
echo "⬇️  4. 部署 UI 面板..."
# 为了防止旧文件残留，先清空
rm -rf "${UI_DIR}/*"
wget -O /tmp/ui.zip "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"

if [ $? -eq 0 ]; then
    unzip -q -o /tmp/ui.zip -d /tmp/
    # 移动解压后的文件到 ui 目录 (注意 zip 里的文件夹名)
    if [ -d "/tmp/zashboard-gh-pages" ]; then
        cp -r /tmp/zashboard-gh-pages/* "${UI_DIR}/"
        rm -rf /tmp/zashboard-gh-pages
    else
        # 备用方案：有些 zip 解压后直接是文件
        cp -r /tmp/* "${UI_DIR}/" 2>/dev/null
    fi
    rm -f /tmp/ui.zip
    echo "✅ UI 面板部署完成"
else
    echo "❌ 面板下载失败，请检查网络。"
fi

# ==========================================
# 5. 配置用户与环境
# ==========================================
echo "🔑 5. 配置用户凭证..."
if [ -f "${ENV_FILE}" ]; then
    echo "✅ 检测到现有配置文件，保留原设置。"
else
    echo "------------------------------------------------"
    read -p "请设置 Web 面板用户名 (默认: admin): " WEB_USER
    WEB_USER=${WEB_USER:-admin}
    
    read -p "请设置 Web 面板密码 (默认: admin): " WEB_SECRET
    WEB_SECRET=${WEB_SECRET:-admin}
    
    read -p "请输入访问端口 (默认: 7838): " WEB_PORT
    WEB_PORT=${WEB_PORT:-7838}
    echo "------------------------------------------------"

    # 生成 .env
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
    echo "✅ 配置文件已生成。"
fi

# ==========================================
# 6. 配置 Systemd 服务 (修复启动路径)
# ==========================================
echo "⚙️ 6. 配置系统服务..."
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/mihomo
# 核心修复：显式指定 python3 解释器
ExecStart=/usr/bin/python3 /etc/mihomo/manager/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# 7. 启动与验证
# ==========================================
echo "🚀 7. 启动服务..."
systemctl daemon-reload
systemctl enable mihomo
systemctl restart mihomo

sleep 2
if systemctl is-active --quiet mihomo; then
    IP=$(hostname -I | awk '{print $1}')
    PORT=$(grep WEB_PORT "${ENV_FILE}" | cut -d '=' -f2 | tr -d '"')
    echo "==========================================="
    echo "🎉 安装成功！所有组件已就绪。"
    echo "🌍 管理面板: http://${IP}:${PORT}"
    echo "   默认用户: ${WEB_USER}"
    echo "   默认密码: ${WEB_SECRET}"
    echo "==========================================="
else
    echo "❌ 服务启动失败！请运行 'systemctl status mihomo' 查看详细错误。"
fi
