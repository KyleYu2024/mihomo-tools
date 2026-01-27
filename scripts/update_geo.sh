#!/bin/bash

if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; else echo "错误：未找到 .env"; exit 1; fi

mkdir -p "$DATA_PATH"
BASE_URL="${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"
FILES=("geoip.dat|geoip-lite.dat" "geosite.dat|geosite.dat" "country.mmdb|country-lite.mmdb")

echo "正在准备更新 Geo 数据库..."

download_file() {
    local target_name=$1
    local source_name=$2
    local url="${BASE_URL}/${source_name}"
    local temp_file="/tmp/${target_name}"

    echo "⬇️  正在下载: ${target_name} ..."
    curl -L -o "$temp_file" "$url"

    if [ -s "$temp_file" ]; then
        mv "$temp_file" "${DATA_PATH}/${target_name}"
        echo "✅ ${target_name} 更新成功。"
    else
        echo "❌ ${target_name} 下载失败！"
        rm -f "$temp_file"
    fi
}

for item in "${FILES[@]}"; do
    TARGET_NAME=${item%%|*}
    SOURCE_NAME=${item##*|}
    download_file "$TARGET_NAME" "$SOURCE_NAME"
done

echo "-----------------------------------"
echo "数据库更新完毕，正在重启服务..."
systemctl restart mihomo
echo "完成！"

# --- 埋点：更新完成通知 ---
bash ${SCRIPT_PATH}/notify.sh "Mihomo 通知" "GeoIP/Geosite 数据库已自动更新完成，服务已重启。"
