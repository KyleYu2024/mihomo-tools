#!/bin/bash

# 1. 导入基础环境
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件！"
    exit 1
fi

# 确保数据目录存在
mkdir -p "$DATA_PATH"

# 定义下载源 (使用 MetaCubeX 的轻量版规则，兼容性最好)
# 拼接 GH_PROXY 以加速下载
BASE_URL="${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"

# 定义需要下载的文件列表
FILES=(
    "geoip.dat|geoip-lite.dat"
    "geosite.dat|geosite.dat"
    "country.mmdb|country-lite.mmdb"
)

echo "正在准备更新 Geo 数据库..."

# 2. 下载函数
download_file() {
    local target_name=$1
    local source_name=$2
    local url="${BASE_URL}/${source_name}"
    local temp_file="/tmp/${target_name}"

    echo "⬇️  正在下载: ${target_name} ..."
    curl -L -o "$temp_file" "$url"

    # 简单校验：检查文件是否下载成功且不为空
    if [ -s "$temp_file" ]; then
        mv "$temp_file" "${DATA_PATH}/${target_name}"
        echo "✅ ${target_name} 更新成功。"
    else
        echo "❌ ${target_name} 下载失败或文件为空！跳过覆盖。"
        rm -f "$temp_file"
    fi
}

# 3. 循环下载
for item in "${FILES[@]}"; do
    # 解析 "保存文件名|下载源文件名"
    TARGET_NAME=${item%%|*}
    SOURCE_NAME=${item##*|}
    download_file "$TARGET_NAME" "$SOURCE_NAME"
done

# 4. 重启生效
# Geo 文件更新后，虽然可以通过 API 热加载，但为了 100% 稳妥（防止内存映射问题），建议重启服务
echo "-----------------------------------"
echo "数据库更新完毕，正在重启服务以应用更改..."
systemctl restart mihomo
systemctl status mihomo | grep Active
echo "完成！"
