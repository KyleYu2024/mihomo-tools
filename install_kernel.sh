#!/bin/bash

# 1. 导入基础环境配置 (我们的“大脑”)
# 这里的路径必须和你在服务器上的路径一致
if [ -f "/etc/mihomo/.env" ]; then
    source /etc/mihomo/.env
else
    echo "错误：未找到 .env 配置文件，请先创建！"
    exit 1
fi

# 2. 自动检测系统架构
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)  MIHOMO_ARCH="amd64" ;;
    aarch64) MIHOMO_ARCH="arm64" ;;
    *)       echo "暂不支持的架构: ${ARCH}"; exit 1 ;;
esac

echo "检测到系统架构为: ${MIHOMO_ARCH}"

# 3. 构造下载链接
# 这里我们下载 Meta 核心的稳定版
DOWNLOAD_URL="${GH_PROXY}https://github.com/MetaCubeX/mihomo/releases/download/v1.18.9/mihomo-linux-${MIHOMO_ARCH}-v1.18.9.gz"

echo "正在下载 Mihomo 内核..."
# 下载并解压到目标路径
curl -L ${DOWNLOAD_URL} | gunzip > ${MIHOMO_PATH}/mihomo

# 4. 赋予执行权限
chmod +x ${MIHOMO_PATH}/mihomo

echo "内核安装完成！位置: ${MIHOMO_PATH}/mihomo"
${MIHOMO_PATH}/mihomo -v
