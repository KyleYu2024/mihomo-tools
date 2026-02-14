#!/bin/bash

# ==========================================
# Mihomo 一键卸载脚本 (完整版)
# ==========================================

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${RED}⚠️  警告：即将执行卸载操作！${NC}"
echo "此操作将执行以下清理："
echo "1. 停止并删除系统服务 (Mihomo Core + Web Manager)"
echo "2. 删除程序文件、管理脚本及 Python 虚拟环境"
echo "3. 清理所有相关的 Crontab 自动任务 (保活/更新)"

read -p "确认卸载吗？(y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "已取消。"
    exit 0
fi

echo "--------------------------------"

# 1. 停止并禁用服务
echo -e "${YELLOW}[1/4] 停止系统服务...${NC}"
# 同时停止主服务和管理端服务
systemctl stop mihomo mihomo-manager 2>/dev/null
systemctl disable mihomo mihomo-manager 2>/dev/null

# 删除服务文件
rm -f /etc/systemd/system/mihomo.service
rm -f /etc/systemd/system/mihomo-manager.service
systemctl daemon-reload
echo "✅ 服务已移除。"

# 2. 清理 Crontab 任务 (核心新增)
echo -e "${YELLOW}[2/4] 清理自动化任务...${NC}"
# 逻辑：列出当前任务 -> 过滤掉含 gateway_init 的(保活任务) -> 过滤掉含 MIHOMO_AUTOMATION 的(更新任务) -> 写回
crontab -l 2>/dev/null | grep -v "gateway_init.sh" | grep -v "MIHOMO_AUTOMATION" | crontab -
echo "✅ Crontab 任务已清理。"

# 3. 删除文件
echo -e "${YELLOW}[3/4] 删除程序文件...${NC}"
rm -f /usr/bin/mihomo-cli
# 这里会连带删除 venv 目录，因为它在 tools 里面
rm -rf /etc/mihomo-tools
echo "✅ 脚本、虚拟环境及 CLI 工具已删除。"

# 4. 询问是否删除数据
echo -e "${YELLOW}[4/4] 数据清理选项${NC}"
echo -e "${YELLOW}❓ 是否同时删除配置文件和数据？(/etc/mihomo)${NC}"
echo -e "${RED}注意：删除后，你的订阅、节点、Geo数据库将全部丢失！${NC}"
read -p "输入 'del' 确认删除数据，直接回车保留: " del_data

if [[ "$del_data" == "del" ]]; then
    echo "正在清除所有数据..."
    rm -rf /etc/mihomo
    echo "✅ 数据目录已清除。"
else
    echo "✅ 数据目录 (/etc/mihomo) 已保留。"
fi

echo "--------------------------------"
echo -e "${GREEN}卸载完成！系统已恢复干净。👋${NC}"
