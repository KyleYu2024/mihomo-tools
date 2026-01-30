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
    echo "❌ 错误: 请使用 root 权限运行此脚本。"
    exit 1
fi

# ==========================================
# 1. 基础环境准备
# ==========================================
echo "📦 1. 安装/更新系统依赖..."
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

# 部署模板文件
if [ -d "${SCRIPT_ROOT}/templates" ]; then
    cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"
fi

# ==========================================
# 3. 下载/更新 Mihomo 内核
# ==========================================
echo "⬇️  3. 检查并下载 Mihomo 内核..."
# 只有当内核不存在，或者用户强制重装时才下载（这里为了稳妥，每次覆盖下载）
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

wget -O /tmp/mihomo.gz "$DOWNLOAD_URL"
if [ $? -eq 0 ]; then
    gzip -d -f /tmp/mihomo.gz
    mv /tmp/mihomo /usr/bin/mihomo-cli
    chmod +x /usr/bin/mihomo-cli
    echo "✅ 内核准备就绪"
else
    echo "⚠️  内核下载失败，如果本地已有内核可忽略，否则服务将无法启动。"
fi

# ==========================================
# 4. 下载/部署 UI 面板
# ==========================================
echo "⬇️  4. 部署 UI 面板..."
# 总是重新下载面板，防止面板文件损坏
rm -rf "${UI_DIR}/*"
wget -O /tmp/ui.zip "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    unzip -q -o /tmp/ui.zip -d /tmp/
    if [ -d "/tmp/zashboard-gh-pages" ]; then
        cp -r /tmp/zashboard-gh-pages/* "${UI_DIR}/"
        rm -rf /tmp/zashboard-gh-pages
    else
        cp -r /tmp/* "${UI_DIR}/" 2>/dev/null
    fi
    rm -f /tmp/ui.zip
    echo "✅ UI 面板部署完成"
else
    echo "⚠️  面板下载失败，Web 界面可能无法显示图表。"
fi

# ==========================================
# 5. 配置用户与环境 (核心逻辑修复)
# ==========================================
echo "🔑 5. 配置用户凭证..."

# 定义生成配置文件的函数
generate_config() {
    echo "------------------------------------------------"
    read -p "请设置 Web 面板用户名 (默认: admin): " WEB_USER
    WEB_USER=${WEB_USER:-admin}
    
    read -p "请设置 Web 面板密码 (默认: admin): " WEB_SECRET
    WEB_SECRET=${WEB_SECRET:-admin}
    
    read -p "请输入访问端口 (默认: 7838): " WEB_PORT
    WEB_PORT=${WEB_PORT:-7838}
    echo "------------------------------------------------"

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
    echo "✅ 配置文件已更新。"
}

# 逻辑判断
if [ -f "${ENV_FILE}" ]; then
    echo "检测到现有配置文件。"
    read -p "是否需要重置用户名和密码？[y/N]: " RESET_CHOICE
    if [[ "$RESET_CHOICE" =~ ^[Yy]$ ]]; then
        generate_config
    else
        echo "✅ 跳过配置，保留现有设置。"
    fi
else
    echo "检测到首次安装，开始初始化配置..."
    generate_config
fi

# ==========================================
# 6. 配置 Systemd 服务
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
# 显式指定 python3
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
    # 获取端口 (兼容 grep 写法)
    PORT=$(grep WEB_PORT "${ENV_FILE}" | cut -d '=' -f2 | tr -d '"')
    IP=$(hostname -I | awk '{print $1}')
    echo "==========================================="
    echo "🎉 安装成功！"
    echo "🌍 管理面板: http://${IP}:${PORT}"
    echo "==========================================="
else
    echo "❌ 服务启动失败！请运行 'systemctl status mihomo' 排查。"
    # 自动显示最后几行日志帮助排查
    journalctl -u mihomo -n 5 --no-pager
fi
