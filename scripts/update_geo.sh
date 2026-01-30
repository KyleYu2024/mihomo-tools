#!/bin/bash
# update_geo.sh - Geo 数据库更新 (完全静默)

MIHOMO_DIR="/etc/mihomo"
GEO_DIR="${MIHOMO_DIR}" # mihomo 默认在运行目录查找
ENV_FILE="${MIHOMO_DIR}/.env"

# 加载环境变量
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

echo "⬇️  开始更新 Geo 数据库..."

# 定义下载链接 (使用 MetaCubeX 的源)
GEOIP_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
GEOSITE_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

# 下载 GeoIP
wget --no-check-certificate -O "${GEO_DIR}/geoip.dat.new" "$GEOIP_URL" >/dev/null 2>&1
if [ $? -eq 0 ] && [ -s "${GEO_DIR}/geoip.dat.new" ]; then
    mv "${GEO_DIR}/geoip.dat.new" "${GEO_DIR}/geoip.dat"
    echo "✅ GeoIP 更新成功"
else
    echo "❌ GeoIP 更新失败"
    rm -f "${GEO_DIR}/geoip.dat.new"
fi

# 下载 GeoSite
wget --no-check-certificate -O "${GEO_DIR}/geosite.dat.new" "$GEOSITE_URL" >/dev/null 2>&1
if [ $? -eq 0 ] && [ -s "${GEO_DIR}/geosite.dat.new" ]; then
    mv "${GEO_DIR}/geosite.dat.new" "${GEO_DIR}/geosite.dat"
    echo "✅ GeoSite 更新成功"
else
    echo "❌ GeoSite 更新失败"
    rm -f "${GEO_DIR}/geosite.dat.new"
fi

# 重启以加载新库
systemctl restart mihomo

echo "🏁 Geo 更新任务结束 (静默模式)"
# ⚠️ 此脚本不发送任何通知
