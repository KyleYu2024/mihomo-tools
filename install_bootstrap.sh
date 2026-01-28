#!/bin/bash

# ==========================================
# Mihomo Tools 引导安装脚本
# ==========================================

# 1. 定义仓库地址 (请修改这里为你的仓库地址 !!!)
# ------------------------------------------------
REPO_URL="https://github.com/你的用户名/你的仓库名.git"
# ------------------------------------------------

# 安装目录
TARGET_DIR="/etc/mihomo-tools"
# GitHub 代理 (国内加速)
PROXY_URL="https://gh-proxy.com/"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> 正在准备安装环境...${NC}"

# 2. 检查并安装 Git (解决新 LXC 没有 git 的问题)
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}检测到系统未安装 Git，正在自动安装...${NC}"
    # 尝试更新源并安装
    apt update -qq && apt install -y git -qq
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}错误：Git 安装失败，请手动执行 'apt update && apt install git' 后重试。${NC}"
        exit 1
    fi
else
    echo "Git 已安装。"
fi

# 3. 克隆代码 (带加速 & 安全检查)
if [ -d "$TARGET_DIR" ]; then
    echo -e "${YELLOW}检测到目录 $TARGET_DIR 已存在。${NC}"
    echo "正在进入目录并尝试更新..."
    cd "$TARGET_DIR"
    
    # 尝试拉取更新
    git pull
    if [ $? -ne 0 ]; then
        echo -e "${RED}更新失败，建议手动备份后删除该目录重新安装。${NC}"
        # 这里不强制退出，继续尝试运行 install.sh，也许本地文件是好的
    fi
else
    echo -e "${YELLOW}正在从 GitHub 克隆源码 (使用加速镜像)...${NC}"
    # 拼接代理地址
    CLONE_URL="${PROXY_URL}${REPO_URL}"
    
    git clone "$CLONE_URL" "$TARGET_DIR"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}克隆失败！请检查网络或仓库地址。${NC}"
        exit 1
    fi
fi

# 4. 执行安装脚本
cd "$TARGET_DIR"
if [ -f "install.sh" ]; then
    chmod +x install.sh
    bash install.sh
else
    echo -e "${RED}错误：未找到 install.sh，文件可能已损坏。${NC}"
    exit 1
fi
