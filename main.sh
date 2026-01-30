#!/bin/bash
# main.sh - Mihomo 命令行管理工具 (融合优化版)
# 安装路径: /usr/bin/mihomo

# ==========================================
# 环境变量与路径
# ==========================================
MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
ENV_FILE="${MIHOMO_DIR}/.env"
LOG_FILE="/var/log/mihomo.log"

# 双服务定义
SVC_CORE="mihomo.service"
SVC_MANAGER="mihomo-manager.service"

# 核心二进制 (新架构)
CORE_BIN="/usr/bin/mihomo-core"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 加载环境变量
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

# ==========================================
# 核心功能函数
# ==========================================

check_status() {
    # 同时检查两个服务
    if systemctl is-active --quiet $SVC_CORE; then
        c_status="${GREEN}运行中${NC}"
    else
        c_status="${RED}已停止${NC}"
    fi
    
    if systemctl is-active --quiet $SVC_MANAGER; then
        m_status="${GREEN}运行中${NC}"
    else
        m_status="${RED}已停止${NC}"
    fi
    echo -e "内核: ${c_status} | 面板: ${m_status}"
}

get_version() {
    if [ -f "$CORE_BIN" ]; then
        # 适配 mihomo-core
        $CORE_BIN -v | head -n 1 | awk '{print $3}'
    else
        echo "未安装"
    fi
}

view_log() {
    echo "================================================="
    echo "正在打开 Mihomo 实时日志 (/var/log/mihomo.log)"
    echo "提示：按 Ctrl + C 退出"
    echo "================================================="
    if [ -f "$LOG_FILE" ]; then
        tail -f -n 50 "$LOG_FILE"
    else
        echo -e "${YELLOW}⚠️ 日志文件不存在，请先启动服务。${NC}"
    fi
}

update_kernel() {
    echo "正在检查并更新内核..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-amd64-v1.18.1.gz" ;;
        aarch64) URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.18.1/mihomo-linux-arm64-v1.18.1.gz" ;;
        *) echo "不支持的架构: $ARCH"; return ;;
    esac

    wget -O /tmp/mihomo.gz "$URL"
    if [ $? -eq 0 ]; then
        systemctl stop $SVC_CORE
        gzip -d -f /tmp/mihomo.gz
        # 【关键】更新到 mihomo-core，不覆盖菜单脚本
        mv /tmp/mihomo "$CORE_BIN"
        chmod +x "$CORE_BIN"
        echo -e "${GREEN}✅ 内核更新成功！${NC}"
        systemctl start $SVC_CORE
    else
        echo -e "${RED}❌ 下载失败${NC}"
    fi
}

manage_subscription() {
    echo -e "\n1. 粘贴/修改 订阅链接"
    echo -e "2. 手动编辑 config.yaml"
    read -p "请选择: " sub_opt
    
    if [ "$sub_opt" == "1" ]; then
        read -p "请输入订阅链接: " url
        if [ -n "$url" ]; then
            # 智能更新 .env
            if grep -q "SUB_URL=" "$ENV_FILE"; then
                sed -i "s|^SUB_URL=.*|SUB_URL=\"$url\"|" "$ENV_FILE"
            else
                echo "SUB_URL=\"$url\"" >> "$ENV_FILE"
            fi
            echo "正在更新订阅..."
            bash "${SCRIPT_DIR}/update_subscription.sh"
            systemctl restart $SVC_CORE
            echo -e "${GREEN}✅ 订阅已更新并重启内核${NC}"
        fi
    elif [ "$sub_opt" == "2" ]; then
        nano /etc/mihomo/config.yaml
        read -p "是否重启生效？(y/n): " need_rs
        [ "$need_rs" == "y" ] && systemctl restart $SVC_CORE
    fi
}

show_panel_info() {
    IP=$(hostname -I | awk '{print $1}')
    PORT=${WEB_PORT:-7838} # 从 env 读取，默认 7838
    echo -e "\n${BLUE}=== 面板信息 ===${NC}"
    echo -e "地址: http://${IP}:${PORT}"
    echo -e "用户: ${WEB_USER}"
    echo -e "密码: ${WEB_SECRET}"
    echo -e "${BLUE}===============${NC}"
}

# ==========================================
# 菜单界面
# ==========================================
show_menu() {
    clear
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}       Mihomo 管理工具 (v2.0 Pro)          ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e " 运行状态: $(check_status)"
    echo -e " 内核版本: $(get_version)"
    echo -e "${BLUE}-------------------------------------------${NC}"
    echo -e "1. 更新/修复 Mihomo 内核"
    echo -e "2. 服务管理 (启动/停止/重启)"
    echo -e "3. 配置与订阅 (粘贴链接/修改配置)"
    echo -e "4. 查看实时日志 (Logs)"
    echo -e "5. 查看面板信息 (账号/端口)"
    echo -e "6. 更多工具 (Geo/Notify/Network)"
    echo -e "${RED}0. 卸载工具箱${NC}"
    echo -e "${BLUE}===========================================${NC}"
}

# 支持命令行直接调用 (例如: mihomo log)
if [ -n "$1" ]; then
    case $1 in
        start) systemctl start $SVC_MANAGER $SVC_CORE ;;
        stop) systemctl stop $SVC_MANAGER $SVC_CORE ;;
        restart) systemctl restart $SVC_MANAGER $SVC_CORE ;;
        log|logs) view_log ;;
        status) check_status ;;
        info) show_panel_info ;;
    esac
    exit 0
fi

# 主循环
while true; do
    show_menu
    read -p "请输入选项 [0-6]: " choice
    case $choice in
        1)
            update_kernel
            read -n 1 -s -r -p "按任意键返回..."
            ;;
        2)
            echo -e "\n1. 启动全部  2. 停止全部  3. 重启全部"
            read -p "选择: " svc_choice
            case $svc_choice in
                1) systemctl start $SVC_MANAGER $SVC_CORE ;;
                2) systemctl stop $SVC_MANAGER $SVC_CORE ;;
                3) systemctl restart $SVC_MANAGER $SVC_CORE ;;
            esac
            echo -e "${GREEN}操作已执行${NC}"
            sleep 1
            ;;
        3)
            manage_subscription
            read -n 1 -s -r -p "按任意键返回..."
            ;;
        4)
            view_log
            ;;
        5)
            show_panel_info
            read -n 1 -s -r -p "按任意键返回..."
            ;;
        6)
            echo -e "\n1. 更新 Geo 数据库"
            echo -e "2. 发送测试通知"
            echo -e "3. 初始化网关网络 (Tun)"
            read -p "选择工具: " tool_opt
            case $tool_opt in
                1) bash "${SCRIPT_DIR}/update_geo.sh" ;;
                2) bash "${SCRIPT_DIR}/notify.sh" "手动测试" "来自命令行的消息" ;;
                3) bash "${SCRIPT_DIR}/gateway_init.sh" ;;
            esac
            read -n 1 -s -r -p "按任意键返回..."
            ;;
        0)
            echo "正在卸载..."
            systemctl stop $SVC_MANAGER $SVC_CORE
            systemctl disable $SVC_MANAGER $SVC_CORE
            rm -rf /etc/mihomo /etc/mihomo-tools /usr/bin/mihomo /usr/bin/mihomo-core /etc/systemd/system/mihomo*
            systemctl daemon-reload
            echo "卸载完成。"
            exit 0
            ;;
        *)
            echo "无效选项"
            sleep 1
            ;;
    esac
done
