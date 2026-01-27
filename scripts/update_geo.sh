#!/bin/bash
# scripts/update_geo.sh
source /etc/mihomo/.env

GEOIP_URL="${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.dat"
GEOSITE_URL="${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

success=true
curl -L -s -o /etc/mihomo/geoip.dat "$GEOIP_URL" || success=false
curl -L -s -o /etc/mihomo/geosite.dat "$GEOSITE_URL" || success=false

if [ "$success" = false ]; then
    bash /etc/mihomo/scripts/notify.sh "❌ Geo 更新失败" "请检查网络环境或 GitHub 代理。"
else
    # 成功则静默，仅重启服务确保应用
    systemctl restart mihomo
fi
