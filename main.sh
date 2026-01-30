#!/bin/bash
# main.sh - Mihomo 命令行管理工具 (v2.2 Pro)
# 安装路径: /usr/bin/mihomo

MIHOMO_DIR="/etc/mihomo"
SCRIPT_DIR="${MIHOMO_DIR}/scripts"
ENV_FILE="${MIHOMO_DIR}/.env"
LOG_FILE="/var/log/mihomo.log"

SVC_CORE="mihomo.service"
SVC_MANAGER="mihomo-manager.service"
CORE_BIN="/usr/bin/mihomo-core"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

check_status() {
    if systemctl is-active --quiet $SVC_CORE; then c="${GREEN}运行中${NC}"; else c="${RED}已停止${NC}"; fi
    if systemctl is-active --quiet $SVC_MANAGER; then m="${GREEN}运行中${NC}"; else m="${RED}已停止${NC}"; fi
    echo -e "内核: ${c} | 面板: ${m}"
}

get_version() {
    if [ -f "$CORE_BIN" ]; then $CORE_BIN -v | head -n 1 | awk '{print $3}'; else echo "未安装"; fi
}

view_log() {
    echo "打开日志... (Ctrl+C 退出)"
    [ -f "$LOG_FILE" ] && tail -f -n 50 "$LOG_FILE" || echo -e "${YELLOW}日志不存在${NC}"
}

# === 核心修复：自动更新到最新版 ===
update_kernel() {
    echo "🔍 正在检查 GitHub 最新版本..."
    
    # 动态获取 tag
    LATEST_VER=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep "tag_name" | cut -d '"' -f 4)
    
    if [ -z "$LATEST_VER" ]; then
        echo -e "${RED}⚠️  无法连接 GitHub API，尝试使用保底版本 v1.18.1${NC}"
        LATEST_VER="v1.18.1"
    else
        echo -e "${GREEN}✅ 发现最新版本: ${LATEST_VER}${NC}"
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64) URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-amd64-${LATEST_VER}.gz" ;;
        aarch64) URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VER}/mihomo-linux-arm64-${LATEST_VER}.gz" ;;
        *) echo "不支持架构: $ARCH"; return ;;
    esac
    
    echo "⬇️  正在下载..."
    wget -O /tmp/mihomo.gz "$URL"
    if [ $? -eq 0 ]; then
        echo "🛑 停止服务..."
        systemctl stop $SVC_CORE
        gzip -d -f /tmp/mihomo.gz
        mv /tmp/mihomo "$CORE_BIN"
        chmod +x "$CORE_BIN"
        systemctl start $SVC_CORE
        echo -e "${GREEN}🎉 更新成功！当前版本: $(get_version)${NC}"
    else
        echo -e "${RED}❌ 下载失败，请检查网络连通性${NC}"
    fi
}

manage_sub() {
    echo -e "\n1. 粘贴订阅链接  2. 编辑 config.yaml"
    read -p "选择: " opt
    if [ "$opt" == "1" ]; then
        read -p "链接: " url
        [ -n "$url" ] && sed -i "s|^SUB_URL=.*|SUB_URL=\"$url\"|" "$ENV_FILE" && bash "${SCRIPT_DIR}/update_subscription.sh" && systemctl restart $SVC_CORE && echo "✅ 已更新"
    elif [ "$opt" == "2" ]; then
        nano /etc/mihomo/config.yaml && read -p "重启生效? (y/n): " r && [ "$r" == "y" ] && systemctl restart $SVC_CORE
    fi
}

show_info() {
    IP=$(hostname -I | awk '{print $1}')
    echo -e "\n${BLUE}=== 面板信息 ===${NC}"
    echo -e "地址: http://${IP}:${WEB_PORT:-7838}"
    echo -e "用户: ${WEB_USER}"
    echo -e "密码: ${WEB_SECRET}"
    echo -e "${BLUE}===============${NC}"
}

show_menu() {
    clear
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}       Mihomo 管理工具 (v2.2 Pro)          ${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo -e " 运行状态: $(check_status)"
    echo -e " 内核版本: $(get_version)"
    echo -e "${BLUE}-------------------------------------------${NC}"
    echo -e " 1. 更新/修复 Mihomo 内核 (Update Core)"
    echo -e " 2. 服务管理 (启动/停止/重启)"
    echo -e " 3. 配置与订阅 (设置链接/手动配置)"
    echo -e " 4. 查看实时日志"
    echo -e " 5. 自动化任务 (Crontab)"
    echo -e " 6. 更新 Geo 数据库"
    echo -e " 7. 通知的配置与测试"
    echo -e " 8. 初始化网关网络 (Tun)"
    echo -e " 9. 查看面板信息"
    echo -e "${RED}10. 卸载 Mihomo 工具箱${NC}"
    echo -e " 0. 退出脚本"
    echo -e "${BLUE}===========================================${NC}"
}

case $1 in
    start) systemctl start $SVC_MANAGER $SVC_CORE; exit ;;
    stop) systemctl stop $SVC_MANAGER $SVC_CORE; exit ;;
    restart) systemctl restart $SVC_MANAGER $SVC_CORE; exit ;;
    log) view_log; exit ;;
esac

while true; do
    show_menu
    read -p "请输入选项 [0-10]: " c
    case $c in
        1) update_kernel; read -n 1 -s -r -p "按键返回..." ;;
        2) 
            echo "1.启动 2.停止 3.重启"
            read -p "选择: " s
            case $s in
                1) systemctl start $SVC_MANAGER $SVC_CORE ;;
                2) systemctl stop $SVC_MANAGER $SVC_CORE ;;
                3) systemctl restart $SVC_MANAGER $SVC_CORE ;;
            esac
            sleep 1 ;;
        3) manage_sub; read -n 1 -s -r -p "按键返回..." ;;
        4) view_log ;;
        5) crontab -l | grep "mihomo"; read -n 1 -s -r -p "按键返回..." ;;
        6) bash "${SCRIPT_DIR}/update_geo.sh"; read -n 1 -s -r -p "按键返回..." ;;
        7) bash "${SCRIPT_DIR}/notify.sh" "测试" "CLI消息"; read -n 1 -s -r -p "按键返回..." ;;
        8) bash "${SCRIPT_DIR}/gateway_init.sh"; read -n 1 -s -r -p "按键返回..." ;;
        9) show_info; read -n 1 -s -r -p "按键返回..." ;;
        10) 
            read -p "确认卸载? (y/n): " ack
            if [ "$ack" == "y" ]; then
                systemctl stop $SVC_MANAGER $SVC_CORE
                systemctl disable $SVC_MANAGER $SVC_CORE
                rm -rf /etc/mihomo /etc/mihomo-tools /usr/bin/mihomo /usr/bin/mihomo-core /etc/systemd/system/mihomo*
                systemctl daemon-reload
                echo "已卸载"; exit 0
            fi ;;
        0) exit 0 ;;
        *) echo "无效选项"; sleep 1 ;;
    esac
done
