#!/bin/bash

# ==========================================
# Mihomo Web UI 管理脚本
# ==========================================

# 引用环境变量
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

UI_DIR="/etc/mihomo/ui"
CONFIG_FILE="/etc/mihomo/config.yaml"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查 unzip
if ! command -v unzip &> /dev/null; then
    echo "正在安装 unzip..."
    apt update && apt install -y unzip > /dev/null 2>&1
fi

echo -e "${YELLOW}==========================================${NC}"
echo -e "${YELLOW}       Mihomo Web 面板切换工具       ${NC}"
echo -e "${YELLOW}==========================================${NC}"
echo "1. Zashboard  (推荐 - 极简美观，甚至能看股票)"
echo "2. MetaCubeXD (官方 - 功能最全，兼容性最好)"
echo "3. Yacd-Meta  (经典 - 轻量级，手机端适配好)"
echo "0. 返回主菜单"
echo "------------------------------------------"

read -p "请选择要安装的面板 [0-3]: " choice

case $choice in
    1)
        UI_NAME="Zashboard"
        UI_URL="${GH_PROXY}https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
        ;;
    2)
        UI_NAME="MetaCubeXD"
        UI_URL="${GH_PROXY}https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
        ;;
    3)
        UI_NAME="Yacd-Meta"
        UI_URL="${GH_PROXY}https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip"
        ;;
    0)
        exit 0
        ;;
    *)
        echo "无效选项"
        exit 1
        ;;
esac

echo -e "\n--> 正在清理旧面板文件..."
rm -rf "${UI_DIR:?}"/*

echo -e "--> 正在下载 ${UI_NAME}..."
curl -L -o /tmp/ui.zip "$UI_URL"

if [ $? -ne 0 ]; then
    echo "❌ 下载失败，请检查网络。"
    exit 1
fi

echo -e "--> 正在解压安装..."
unzip -o -q /tmp/ui.zip -d /tmp/ui_extract

# 智能移动：GitHub 的 zip 通常包了一层文件夹，我们需要里面的内容
# 这里的逻辑是将解压出的第一个文件夹里的内容移动到 UI_DIR
cp -rf /tmp/ui_extract/*/* "${UI_DIR}/"

# 清理垃圾
rm -rf /tmp/ui.zip /tmp/ui_extract

# ==================================================
# 关键步骤：检查 config.yaml 是否配置了 external-ui
# ==================================================
if [ -f "$CONFIG_FILE" ]; then
    if ! grep -q "external-ui" "$CONFIG_FILE"; then
        echo -e "${YELLOW}⚠️  检测到配置文件缺少 'external-ui' 设置，正在自动添加...${NC}"
        # 在文件末尾追加
        echo "" >> "$CONFIG_FILE"
        echo "external-ui: ui" >> "$CONFIG_FILE"
    else
        # 确保指向的是 ui 目录 (防止用户乱改)
        # 这里用 sed 强制修正 external-ui 为 ui
        sed -i 's/^external-ui:.*/external-ui: ui/' "$CONFIG_FILE"
    fi
fi

echo -e "${GREEN}✅ ${UI_NAME} 面板已安装成功！${NC}"
echo -e "请在浏览器访问: http://<你的IP>:9090/ui"
