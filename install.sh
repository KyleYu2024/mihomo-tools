#!/bin/bash

# ==========================================
# Mihomo 一键部署脚本
# ==========================================

# 1. 自动获取脚本所在目录
# 无论你在哪运行，这里都会锁定到 /etc/mihomo-tools
SCRIPT_ROOT=$(dirname "$(readlink -f "$0")")

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 目标路径
INSTALL_DIR="/etc/mihomo-tools"
MIHOMO_DIR="/etc/mihomo"
SCRIPTS_DIR="${MIHOMO_DIR}/scripts"
BIN_PATH="/usr/bin/mihomo-cli"

echo -e "${GREEN}>>> 开始安装 Mihomo 管理工具...${NC}"
echo "资源目录锁定为: ${SCRIPT_ROOT}"

# 2. 安装系统依赖 (新增 iptables)
echo -e "${YELLOW}[1/6] 安装系统基础依赖...${NC}"
apt update -qq
# 关键：加上 iptables，否则网关无法初始化
apt install -y git curl tar gzip nano cron ca-certificates iptables > /dev/null 2>&1
echo "✅ 依赖安装完成。"

# 3. 部署/更新 脚本文件
echo -e "${YELLOW}[2/6] 部署脚本文件...${NC}"

mkdir -p "${SCRIPTS_DIR}"
mkdir -p "${MIHOMO_DIR}/data"

# 使用 SCRIPT_ROOT 绝对路径复制，不再依赖当前目录
cp -rf "${SCRIPT_ROOT}/scripts/"* "${SCRIPTS_DIR}/"
cp -f "${SCRIPT_ROOT}/main.sh" "${BIN_PATH}"

# 赋予权限
chmod +x "${BIN_PATH}"
chmod +x "${SCRIPTS_DIR}"/*.sh

echo "✅ 脚本已部署到 ${MIHOMO_DIR}"

# 4. 生成默认配置 (.env)
echo -e "${YELLOW}[3/6] 初始化环境配置...${NC}"
cat > "${MIHOMO_DIR}/.env" <<EOF
MIHOMO_PATH="/etc/mihomo"
DATA_PATH="/etc/mihomo/data"
SCRIPT_PATH="/etc/mihomo/scripts"
GH_PROXY="https://gh-proxy.com/"
SUB_URL=""
EOF
echo "✅ 配置文件 .env 已生成。"

# 5. 初始化网关网络 (TUN 前置)
echo -e "${YELLOW}[4/6] 初始化网关网络环境...${NC}"
bash "${SCRIPTS_DIR}/gateway_init.sh"

# 6. 下载资源 (Geo + 内核)
echo -e "${YELLOW}[5/6] 下载核心组件...${NC}"

echo "--> 正在下载 GeoIP/GeoSite..."
bash "${SCRIPTS_DIR}/update_geo.sh" > /dev/null

echo "--> 正在下载 Mihomo 内核 (Auto)..."
# 自动模式下载
bash "${SCRIPTS_DIR}/install_kernel.sh" "auto"

# 7. 注册 Systemd 服务
echo -e "${YELLOW}[6/6] 注册系统服务...${NC}"
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
systemctl daemon-reload
echo "✅ 服务已注册 (未启动)。"

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   Mihomo 全自动部署完成！ ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "下一步操作："
echo -e "1. 输入 ${YELLOW}mihomo-cli${NC} 打开菜单"
echo -e "2. 选择 [3] 配置与订阅 -> 填入你的机场链接"
echo -e "3. 选择 [2] 管理服务 -> 启动服务"
echo -e "============================================="
