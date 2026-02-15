#!/bin/bash
# update_geo.sh - Geo 数据库更新 (完全静默)

MIHOMO_DIR="/etc/mihomo"
GEO_DIR="${MIHOMO_DIR}"
ENV_FILE="${MIHOMO_DIR}/.env"

if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

echo "⬇️  开始更新 Geo 数据库..."

GEOIP_URL="https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
GEOSITE_URL="https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

# GeoIP
echo "正在下载 GeoIP 数据库..."
wget --no-check-certificate --show-progress -O "${GEO_DIR}/geoip.dat.new" "$GEOIP_URL"
if [ $? -eq 0 ] && [ -s "${GEO_DIR}/geoip.dat.new" ]; then
    mv "${GEO_DIR}/geoip.dat.new" "${GEO_DIR}/geoip.dat"
    echo "✅ GeoIP 更新成功"
else
    echo "❌ GeoIP 更新失败"
    rm -f "${GEO_DIR}/geoip.dat.new"
fi

# GeoSite
echo "正在下载 GeoSite 数据库..."
wget --no-check-certificate --show-progress -O "${GEO_DIR}/geosite.dat.new" "$GEOSITE_URL"
if [ $? -eq 0 ] && [ -s "${GEO_DIR}/geosite.dat.new" ]; then
    mv "${GEO_DIR}/geosite.dat.new" "${GEO_DIR}/geosite.dat"
    echo "✅ GeoSite 更新成功"
else
    echo "❌ GeoSite 更新失败"
    rm -f "${GEO_DIR}/geosite.dat.new"
fi

# 即使更新了也不重启，或者重启但不通知
systemctl restart mihomo
echo "🏁 Geo 更新任务结束 (静默模式)"
