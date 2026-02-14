#!/bin/bash

# 1. 导入基础环境配置
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件！"
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/mihomo.service"

# 2. 自动生成 Systemd 服务文件逻辑
generate_service() {
    echo "正在生成 Systemd 服务文件..."
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Mihomo Daemon, A rule-based tunnel in Go.
After=network.target network-online.target nss-lookup.target

[Service]
Type=simple
User=root
WorkingDirectory=${MIHOMO_PATH}
# --- 新增：启动前强制初始化网关网络 ---
ExecStartPre=/bin/bash ${SCRIPT_PATH}/gateway_init.sh
# -----------------------------------
ExecStart=${MIHOMO_PATH}/mihomo -d ${MIHOMO_PATH}
# 稳定性核心：崩溃后 5 秒自动重启
Restart=always
RestartSec=5s
# 赋予网络管理权限
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo "服务文件生成完毕。"
}

# 3. 执行动作
case "$1" in
    start)
        if [ ! -f "$SERVICE_FILE" ]; then generate_service; fi
        systemctl start mihomo
        echo "Mihomo 已启动。"
        ;;
    stop)
        systemctl stop mihomo
        echo "Mihomo 已停止。"
        ;;
    restart)
        if [ ! -f "$SERVICE_FILE" ]; then generate_service; fi
        # 重启前先校验配置 (假设 config.yaml 已存在)
        if [ -f "${MIHOMO_PATH}/config.yaml" ]; then
            ${MIHOMO_PATH}/mihomo -t -d ${MIHOMO_PATH} > /dev/null
            if [ $? -ne 0 ]; then
                echo "配置校验失败，取消重启！"
                exit 1
            fi
        fi
        systemctl restart mihomo
        echo "Mihomo 已重启。"
        ;;
    status)
        systemctl status mihomo
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
