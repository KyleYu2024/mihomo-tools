#!/bin/bash

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${RED}⚠️  警告：即将执行卸载操作！${NC}"
echo "此操作将："
echo "1. 停止并删除 Mihomo 系统服务"
echo "2. 删除管理脚本工具 (mihomo-cli)"
echo "3. 删除源代码目录"

read -p "确认卸载吗？(y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "已取消。"
    exit 0
fi

echo "--------------------------------"

# 1. 停止服务
echo "正在停止服务..."
systemctl stop mihomo 2>/dev/null
systemctl disable mihomo 2>/dev/null
rm -f /etc/systemd/system/mihomo.service
systemctl daemon-reload

# 2. 删除脚本和软链接
echo "正在清理脚本文件..."
rm -f /usr/bin/mihomo-cli
rm -rf /etc/mihomo-tools

# 3. 询问是否删除数据
echo -e "${YELLOW}❓ 是否同时删除配置文件和数据？(/etc/mihomo)${NC}"
echo -e "${RED}注意：删除后，你的订阅、节点、Geo数据库将全部丢失！${NC}"
read -p "输入 'del' 确认删除数据，直接回车保留: " del_data

if [[ "$del_data" == "del" ]]; then
    echo "正在清除所有数据..."
    rm -rf /etc/mihomo
    echo "✅ 数据已清除。"
else
    echo "✅ 数据目录 (/etc/mihomo) 已保留。"
fi

echo "--------------------------------"
echo -e "${GREEN}卸载完成！江湖路远，有缘再见。👋${NC}"
