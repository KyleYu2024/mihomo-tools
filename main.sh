#!/bin/bash

# 1. 导入基础环境配置
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 /etc/mihomo/.env 配置文件！"
    exit 1
fi

# 2. 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 3. 权限检查
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请以 root 权限运行此脚本${NC}"
    exit 1
fi

# 4. 主菜单函数
show_menu() {
    clear
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}    Mihomo 模块化管理工具 (2026版)   ${NC}"
    echo -e "${GREEN}====================================${NC}"
    echo -e "1. 安装/更新 内核 (install_kernel)"
    echo -e "2. 管理服务 (启动/停止/重启/状态)"
    echo -e "3. 更新配置 (Sub-Store/本地/URL)"
    echo -e "4. 查看实时日志 - [待开发]"
    echo -e "5. 设置自动更新与自修复 - [待开发]"
    echo -e "6. 更新 Geo 数据库 (geoip/geosite)"
    echo -e "0. 退出脚本"
    echo -e "${GREEN}====================================${NC}"
    read -p "请输入选项 [0-6]: " choice
}

# 5. 逻辑分发
while true; do
    show_menu
    case $choice in
        1)
            # --- 积木 1：内核安装 ---
            bash ${SCRIPT_PATH}/install_kernel.sh
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        2)
            # --- 积木 2：服务管理 (已点亮) ---
            echo -e "\n${GREEN}[服务管理]${NC}"
            echo "1. 启动 | 2. 停止 | 3. 重启 | 4. 状态"
            read -p "请选择动作: " svc_action
            case $svc_action in
                1) bash ${SCRIPT_PATH}/service_ctl.sh start ;;
                2) bash ${SCRIPT_PATH}/service_ctl.sh stop ;;
                3) bash ${SCRIPT_PATH}/service_ctl.sh restart ;;
                4) bash ${SCRIPT_PATH}/service_ctl.sh status ;;
                *) echo "无效指令" ;;
            esac
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        3)
            # --- 积木 3：配置管理 (已点亮) ---
            echo -e "\n${GREEN}[配置管理]${NC}"
            echo "1. 从 Sub-Store/URL 更新配置 (读取 .env)"
            echo "2. 手动输入 URL 更新"
            echo "3. 本地编辑配置 (安全模式)"
            read -p "请选择: " cfg_action
            case $cfg_action in
                1) bash ${SCRIPT_PATH}/manage_config.sh update ;;
                2)
                    read -p "请输入订阅链接: " manual_url
                    bash ${SCRIPT_PATH}/manage_config.sh update "$manual_url"
                    ;;
                3) bash ${SCRIPT_PATH}/manage_config.sh edit ;;
                *) echo "无效指令" ;;
            esac
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        4)
            echo "功能 [查看日志] 尚未开发..."
            sleep 1
            ;;
        5)
            echo "功能 [自动更新] 尚未开发..."
            sleep 1
            ;;
        6)
            # --- 积木 4：Geo 更新 (对应你改的数字 6) ---
            bash ${SCRIPT_PATH}/update_geo.sh
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择${NC}"
            sleep 1
            ;;
    esac
done
