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
get_status() {
    if systemctl is-active --quiet mihomo; then
        echo -e "${GREEN}● 运行中${NC}"
    else
        echo -e "${RED}● 已停止${NC}"
    fi
}

get_version() {
    if [ -f "${MIHOMO_PATH}/mihomo" ]; then
        # 获取版本号 (例如 v1.18.1)
        ${MIHOMO_PATH}/mihomo -v | head -n 1 | awk '{print $3}'
    else
        echo "未安装"
    fi
}

show_menu() {
    clear
    # 动态获取状态
    local status=$(get_status)
    local version=$(get_version)
    
    echo -e "${GREEN}===========================================${NC}"
    echo -e "${GREEN}   Mihomo 模块化管理工具 (2026 Pro版)   ${NC}"
    echo -e "${GREEN}===========================================${NC}"
    echo -e " 状态: ${status}    内核版本: ${GREEN}${version}${NC}"
    echo -e "${GREEN}-------------------------------------------${NC}"
    echo -e "1. 安装/更新 内核 (install_kernel)"
    echo -e "2. 管理服务 (启动/停止/重启)"
    echo -e "3. 配置与订阅 (设置链接/手动更新)"
    echo -e "4. 查看实时日志 (view_log)"
    echo -e "5. 自动化任务 (看门狗/定时更新订阅)"
    echo -e "6. 更新 Geo 数据库 (geoip/geosite)"
    echo -e "0. 退出脚本"
    echo -e "${GREEN}===========================================${NC}"
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
            # --- 积木 2：服务管理 ---
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
            # --- 积木 3：配置管理 ---
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
            # --- 积木 5：查看日志 ---
            bash ${SCRIPT_PATH}/view_log.sh
            # 日志查看结束后（用户按Ctrl+C），不需要暂停，直接回菜单更流畅
            ;;
        5)
            # --- 积木 6：自动化管理 ---
            bash ${SCRIPT_PATH}/cron_manager.sh
            read -n 1 -s -r -p "按任意键返回菜单..."
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
