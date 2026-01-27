#!/bin/bash

# ==========================================
# Mihomo CLI 管理主程序 (v2.1 Pro)
# ==========================================

# 引用环境
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 路径
LOG_FILE="/var/log/mihomo.log"

# --- 辅助函数 ---
check_status() {
    if systemctl is-active --quiet mihomo; then
        echo -e "${GREEN}● 运行中${NC}"
    else
        echo -e "${RED}● 已停止${NC}"
    fi
}

get_version() {
    if [ -f "$MIHOMO_PATH/mihomo" ]; then
        $MIHOMO_PATH/mihomo -v | awk '{print $3}'
    else
        echo "未安装"
    fi
}

# --- 核心功能 ---

view_log() {
    echo "================================================="
    echo "正在打开 Mihomo 实时日志"
    echo "提示：按 Ctrl + C 可退出日志界面，返回主菜单"
    echo "================================================="
    
    # 智能判断日志模式
    if [ -f "$LOG_FILE" ]; then
        # 模式 A: 文件日志 (推荐)
        tail -f -n 50 "$LOG_FILE"
    else
        # 模式 B: Systemd Journal (兼容旧版)
        journalctl -u mihomo -f -n 50
    fi
}

# --- 菜单显示 ---
show_menu() {
    clear
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}    Mihomo 管理工具 (LXC 专用版)    ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e " 运行状态: $(check_status)    内核版本: $(get_version)"
    echo -e "${BLUE}-------------------------------------------${NC}"
    echo -e "1. 安装/更新 内核 (install_kernel)"
    echo -e "2. 管理服务 (启动/停止/重启/状态)"
    echo -e "3. 配置与订阅 (设置链接/手动更新)"
    echo -e "4. 查看实时日志 (Log File)"
    echo -e "5. 自动化任务 (看门狗/定时更新订阅)"
    echo -e "6. 更新 Geo 数据库 (geoip/geosite)"
    echo -e "7. 通知的配置与测试"
    echo -e "8. 初始化网关网络 (TUN模式前置)"
    echo -e "9. 切换 Web 面板 (Zashboard/Yacd)"
    echo -e "${RED}10. 卸载 Mihomo 工具箱${NC}"
    echo -e "0. 退出脚本"
    echo -e "${BLUE}===========================================${NC}"
}

# --- 主循环 ---
while true; do
    show_menu
    read -p "请输入选项 [0-10]: " choice
    case $choice in
        1)
            bash ${SCRIPT_PATH}/install_kernel.sh
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        2)
            echo -e "\n1. 启动  2. 停止  3. 重启  4. 状态"
            read -p "选择操作: " svc_opt
            case $svc_opt in
                1) systemctl start mihomo ;;
                2) systemctl stop mihomo ;;
                3) systemctl restart mihomo ;;
                4) systemctl status mihomo ;;
            esac
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        3)
            echo -e "\n1. 粘贴订阅链接并更新"
            echo -e "2. 手动编辑配置文件"
            read -p "选择: " cfg_opt
            if [ "$cfg_opt" == "1" ]; then
                read -p "请输入订阅链接: " url
                if [ -n "$url" ]; then
                    # 保存到 .env
                    if grep -q "SUB_URL=" /etc/mihomo/.env; then
                        sed -i "s|^SUB_URL=.*|SUB_URL=\"$url\"|" /etc/mihomo/.env
                    else
                        echo "SUB_URL=\"$url\"" >> /etc/mihomo/.env
                    fi
                    bash ${SCRIPT_PATH}/update_subscription.sh
                fi
            elif [ "$cfg_opt" == "2" ]; then
                nano /etc/mihomo/config.yaml
                read -p "是否重启服务以应用更改? (y/n): " rs
                [ "$rs" == "y" ] && systemctl restart mihomo
            fi
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        4)
            view_log
            ;;
        5)
            # 简单展示 crontab
            crontab -l
            echo -e "\n提示：请使用 Web 面板 (http://IP:8080) 配置定时任务更方便。"
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        6)
            bash ${SCRIPT_PATH}/update_geo.sh
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        7)
             bash ${SCRIPT_PATH}/notify.sh "测试通知" "这是一条测试消息"
             echo "已发送测试通知 (请确保 .env 中已配置通知参数)"
             read -n 1 -s -r -p "按任意键返回菜单..."
             ;;
        8)
            bash ${SCRIPT_PATH}/gateway_init.sh
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        9)
            if [ -f "${SCRIPT_PATH}/manage_ui.sh" ]; then
                bash ${SCRIPT_PATH}/manage_ui.sh
            else
                echo "未找到面板管理脚本。"
            fi
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        10)
            echo "正在卸载..."
            systemctl stop mihomo
            systemctl disable mihomo
            rm -rf /etc/mihomo /etc/mihomo-tools /usr/bin/mihomo-cli /etc/systemd/system/mihomo.service /var/log/mihomo.log
            systemctl daemon-reload
            echo "卸载完成。"
            exit 0
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效选项"
            sleep 1
            ;;
    esac
done
