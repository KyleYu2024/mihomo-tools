#!/bin/bash

# 1. 导入基础环境 (保持队形)
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件！"
    exit 1
fi

# 2. 检查服务是否存在
if ! systemctl list-units --full -all | grep -Fq "mihomo.service"; then
    echo "错误：Mihomo 服务尚未安装或未加载！"
    echo "请先执行 [安装内核] 和 [启动服务]。"
    exit 1
fi

echo "================================================="
echo "正在打开 Mihomo 实时日志"
echo "提示：按 Ctrl + C 可退出日志界面，返回主菜单"
echo "================================================="
sleep 1

# 3. 核心命令
# -u mihomo: 指定服务
# -f: 实时跟随 (Follow)
# -n 100: 先显示最近的 100 行
# --no-pager: 防止日志过长时进入less模式，直接输出
journalctl -u mihomo -f -n 100 --no-pager
