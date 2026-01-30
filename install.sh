#!/bin/bash
# install.sh - Mihomo Tools 一键安装脚本
# 架构：双服务 (Web管理器 + Mihomo内核)

# === 全局变量 ===
MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
MANAGER_DIR="${MIHOMO_DIR}/manager"
UI_DIR="${MIHOMO_DIR}/ui"
ENV_FILE="${MIHOMO_DIR}/.env"

SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)

# 检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo "❌ 必须使用 Root 权限运行此脚本"
    exit 1
fi

# ==========================================
# 1. 环境清理与依赖安装
# ==========================================
echo "📦 1. 准备环境..."
apt update
apt install -y curl wget tar gzip unzip python3 python3-pip python3-flask python3-yaml

# 停止旧服务（防止冲突）
systemctl stop mihomo >/dev/null 2>&1
systemctl stop mihomo-manager >/dev/null 2>&1
systemctl disable mihomo >/dev/null 2>&1
systemctl disable mihomo-manager >/dev/null 2>&1

# 清理残留进程
pkill -9 -f app.py
pkill -9 -f mihomo-cli

# ==========================================
# 2. 部署文件资源
# ==========================================
echo "📂 2. 部署程序文件..."
mkdir -p "${MIHOMO_DIR}" "${SCRIPT_DIR}" "${MANAGER_DIR}" "${UI_DIR}"
mkdir -p "${MIHOMO_DIR}/templates" "${MIHOMO_DIR}/providers" "${MIHOMO_DIR}/data"

# 复制脚本与代码
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPT_DIR}/"
chmod +x "${SCRIPT_DIR}"/*.sh
cp -rf "${SCRIPT_ROOT}/manager/"* "${MANAGER_DIR}/"

# 部署模板
if [ -d "${SCRIPT_ROOT}/templates" ]; then
    cp -rf "${SCRIPT_ROOT}/templates/"* "${MIHOMO_DIR}/templates/"
fi

# ==========================================
# 3. 下载核心与面板
# ==========================================
echo "⬇️  3. 检查核心组件..."

# 3.1 下载内核
ARCH=$(uname -m)
case $ARCH in
    x86_64) DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-amd64-v1.18.1.gz" ;;
    aarch64) DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-arm64-v1.18.1.gz" ;;
    *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 强制覆盖下载内核，确保版本一致
wget -O /tmp/mihomo.gz "$DOWNLOAD_URL" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    gzip -d -f /tmp/mihomo.gz
    mv /tmp/mihomo /usr/bin/mihomo-cli
    chmod +x /usr/bin/mihomo-cli
    echo "✅ Mihomo 内核已更新"
else
    echo "⚠️  内核下载失败，如果本地已有内核可忽略"
fi

# 3.2 下载面板
rm -rf "${UI_DIR}/*"
wget -O /tmp/ui.zip "https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    unzip -q -o /tmp/ui.zip -d /tmp/
    # 兼容解压目录结构
    if [ -d "/tmp/zashboard-gh-pages" ]; then
        cp -r /tmp/zashboard-gh-pages/* "${UI_DIR}/"
    else
        cp -r /tmp/* "${UI_DIR}/" 2>/dev/null
    fi
    rm -rf /tmp/ui.zip /tmp/zashboard-gh-pages
    echo "✅ UI 面板已更新"
else
    echo "⚠️  面板下载失败"
fi

# ==========================================
# 4. 用户配置向导
# ==========================================
echo "🔑 4. 配置账户与端口..."

# 默认值
DEFAULT_USER="admin"
DEFAULT_PASS="admin"
DEFAULT_PORT="7838"

# 读取旧配置
if [ -f "${ENV_FILE}" ]; then
    OLD_USER=$(grep WEB_USER "${ENV_FILE}" | cut -d '=' -f2 | tr -d '"')
    OLD_PASS=$(grep WEB_SECRET "${ENV_FILE}" | cut -d '=' -f2 | tr -d '"')
    OLD_PORT=$(grep WEB_PORT "${ENV_FILE}" | cut -d '=' -f2 | tr -d '"')
    
    [ ! -z "$OLD_USER" ] && DEFAULT_USER=$OLD_USER
    [ ! -z "$OLD_PASS" ] && DEFAULT_PASS=$OLD_PASS
    [ ! -z "$OLD_PORT" ] && DEFAULT_PORT=$OLD_PORT
    
    echo "检测到现有配置: 用户=$DEFAULT_USER, 端口=$DEFAULT_PORT"
    read -p "是否保留现有配置？(Y/n): " KEEP_CONF
    KEEP_CONF=${KEEP_CONF:-Y}
else
    KEEP_CONF="n"
fi

if [[ "$KEEP_CONF" =~ ^[Nn]$ ]]; then
    read -p "请输入用户名 [默认: admin]: " IN_USER
    WEB_USER=${IN_USER:-admin}
    
    read -p "请输入密码 [默认: admin]: " IN_PASS
    WEB_SECRET=${IN_PASS:-admin}
    
    read -p "请输入端口 [默认: 7838]: " IN_PORT
    WEB_PORT=${IN_PORT:-7838}
else
    WEB_USER=$DEFAULT_USER
    WEB_SECRET=$DEFAULT_PASS
    WEB_PORT=$DEFAULT_PORT
fi

# 生成/更新配置文件
cat > "${ENV_FILE}" <<EOF
WEB_USER="${WEB_USER}"
WEB_SECRET="${WEB_SECRET}"
WEB_PORT="${WEB_PORT}"
# 系统默认参数
SUB_URL=
CONFIG_MODE=expert
EOF

# ==========================================
# 5. 配置 Systemd 双服务
# ==========================================
echo "⚙️ 5. 注册系统服务..."

# 5.1 Web 管理器服务 (mihomo-manager)
cat > /etc/systemd/system/mihomo-manager.service <<EOF
[Unit]
Description=Mihomo Web Manager
After=network.target

[Service]
Type=simple
User=root
# 显式指定 python3 路径
ExecStart=/usr/bin/python3 /etc/mihomo/manager/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 5.2 Mihomo 内核服务 (mihomo)
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=Mihomo Core (Proxy)
After=network.target

[Service]
Type=simple
User=root
# 启动内核，并重定向日志到文件，供Web端读取
ExecStart=/bin/bash -c "/usr/bin/mihomo-cli -d /etc/mihomo > /var/log/mihomo.log 2>&1"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# 6. 启动验证
# ==========================================
echo "🚀 6. 启动服务..."
systemctl daemon-reload
systemctl enable mihomo-manager
systemctl enable mihomo

# 重启双服务
systemctl restart mihomo-manager
systemctl restart mihomo

sleep 2
# 检查端口监听
if ss -tulpn | grep -q ":${WEB_PORT} "; then
    IP=$(hostname -I | awk '{print $1}')
    echo "==========================================="
    echo "🎉 安装成功！"
    echo "🌍 管理面板: http://${IP}:${WEB_PORT}"
    echo "🔑 账户: ${WEB_USER} / ${WEB_SECRET}"
    echo "==========================================="
else
    echo "❌ 启动异常，请检查端口 ${WEB_PORT} 是否被占用或查看 'systemctl status mihomo-manager'"
fi
