#!/bin/bash

# 1. 加载配置
if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

DATA_DIR="${DATA_PATH}"
GH_PROXY="${GH_PROXY:-https://gh-proxy.com/}"

mkdir -p "$DATA_DIR"

echo "正在下载 GeoIP..."
curl -L -o "${DATA_DIR}/geoip.dat" "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"

echo "正在下载 GeoSite..."
curl -L -o "${DATA_DIR}/geosite.dat" "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

echo "正在下载 Country.mmdb..."
curl -L -o "${DATA_DIR}/Country.mmdb" "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"

echo "✅ Geo 数据库更新完成。"

# ==========================================
# 修复：只有服务存在且运行时，才尝试重启
# ==========================================
if systemctl is-active --quiet mihomo.service; then
    echo "🔄 正在重启 Mihomo 以应用更改..."
    systemctl restart mihomo
else
    echo "ℹ️ 服务未运行，跳过重启。"
fi
if [ $? -eq 0 ]; then
    bash /etc/mihomo/scripts/notify.sh "✅ Geo 数据库更新完成" "IP 和 域名库已更新到最新。"
else
    bash /etc/mihomo/scripts/notify.sh "❌ Geo 更新失败" "下载过程中出现错误。"
fi
