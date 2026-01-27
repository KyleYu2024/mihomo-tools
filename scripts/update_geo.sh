#!/bin/bash
# scripts/update_geo.sh

# 1. 加载配置
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

DATA_DIR="${DATA_PATH}"
GH_PROXY="${GH_PROXY:-https://gh-proxy.com/}"
NOTIFY_SCRIPT="/etc/mihomo/scripts/notify.sh"

mkdir -p "$DATA_DIR"

# 定义下载函数，带重试和错误检测
download_file() {
    local url="$1"
    local dest="$2"
    echo "正在下载: $(basename "$dest")..."
    # --fail 遇到 404 等错误返回失败代码
    # --retry 3 失败重试 3 次
    curl -L --fail --retry 3 --connect-timeout 15 -o "$dest" "$url"
    return $?
}

# --- 核心下载流程 ---
ERR=0
download_file "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat" "${DATA_DIR}/geoip.dat" || ERR=1
download_file "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat" "${DATA_DIR}/geosite.dat" || ERR=1
download_file "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" "${DATA_DIR}/Country.mmdb" || ERR=1

# --- 结果判断 ---
if [ $ERR -eq 0 ]; then
    echo "✅ Geo 数据库下载完成。"
    
    # 尝试重启服务
    if systemctl is-active --quiet mihomo.service; then
        echo "🔄 正在重启 Mihomo 以应用更改..."
        systemctl restart mihomo
        if [ $? -ne 0 ]; then
             # 重启失败了，需要通知
             bash "$NOTIFY_SCRIPT" "⚠️ Mihomo 重启失败" "Geo 文件已更新，但在重启服务时遇到错误。"
        else
             # 【关键】成功了，什么都不做 (静默)
             echo "✅ 服务重启成功。更新结束。"
        fi
    fi
else
    echo "❌ 下载过程中出现错误。"
    # 【关键】失败了，发送通知
    bash "$NOTIFY_SCRIPT" "❌ Geo 更新失败" "下载 GeoIP/GeoSite 数据库时出现网络错误，请检查连接。"
    exit 1
fi
