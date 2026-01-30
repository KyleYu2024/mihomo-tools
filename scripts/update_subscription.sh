#!/bin/bash
# scripts/update_subscription.sh

if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

CONFIG_FILE="/etc/mihomo/config.yaml"
TEMPLATE_FILE="/etc/mihomo/templates/default.yaml"
MERGED_PROVIDER="/etc/mihomo/providers/merged.yaml"
NOTIFY_SCRIPT="/etc/mihomo/scripts/notify.sh"
TEMP_FILE="/tmp/config_tmp.yaml"

# 默认模式为 expert
CONFIG_MODE=${CONFIG_MODE:-expert}

if [ -z "$SUB_URL" ]; then 
    echo "未配置 SUB_URL，跳过更新。"
    exit 0
fi

echo "🚀 开始更新订阅 (模式: $CONFIG_MODE)..."

# =======================================================
# 路径 A: 模板模式 (小白模式 - 多机场合并)
# =======================================================
if [ "$CONFIG_MODE" == "template" ]; then
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "❌ 错误: 找不到模板文件 $TEMPLATE_FILE"
        bash "$NOTIFY_SCRIPT" "❌ 更新失败" "找不到预置模板文件。"
        exit 1
    fi
    
    echo "📄 1. 准备基础模板..."
    cp "$TEMPLATE_FILE" "$TEMP_FILE"
    
    # 将 | 替换为空格，生成 URL 列表
    URL_LIST=$(echo "$SUB_URL" | tr '|' ' ')
    
    echo "⬇️ 2. 下载并合并订阅..."
    
    # 临时目录存放所有下载的 yaml
    DOWNLOAD_DIR="/tmp/mihomo_subs"
    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"
    
    count=0
    for url in $URL_LIST; do
        if [ -n "$url" ]; then
            count=$((count+1))
            echo "   -> 下载第 $count 个订阅: $url"
            curl -L -s --fail --retry 3 --connect-timeout 10 -o "$DOWNLOAD_DIR/sub_$count.yaml" "$url" || echo "      ⚠️ 下载失败: $url"
        fi
    done
    
    # 使用 Python 脚本合并所有 YAML 中的 proxies 节点
    # 依赖: python3-yaml (已在 install.sh 中安装)
    cat > /tmp/merge_proxies.py <<EOF
import sys, yaml, os

files = sys.argv[1:]
all_proxies = []
seen_names = set()

for f_path in files:
    try:
        if not os.path.exists(f_path): continue
        with open(f_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
            if data and isinstance(data, dict) and 'proxies' in data and isinstance(data['proxies'], list):
                for p in data['proxies']:
                    if isinstance(p, dict) and 'name' in p:
                        # 简单重名处理
                        name = p['name']
                        original_name = name
                        counter = 1
                        while name in seen_names:
                            name = f"{original_name}_{counter}"
                            counter += 1
                        p['name'] = name
                        seen_names.add(name)
                        all_proxies.append(p)
    except Exception as e:
        sys.stderr.write(f"Error parsing {f_path}: {e}\n")

# 输出合并后的 YAML
print(yaml.dump({'proxies': all_proxies}, allow_unicode=True))
EOF
    
    # 执行合并
    if [ $count -gt 0 ]; then
        python3 /tmp/merge_proxies.py "$DOWNLOAD_DIR"/sub_*.yaml > "$MERGED_PROVIDER"
        echo "✅ 3. 已合并节点到 $MERGED_PROVIDER"
    else
        echo "❌ 未下载到任何有效订阅。"
        exit 1
    fi
    
    # 修改模板中的 provider 配置，指向本地文件
    # 1. 移除 url 字段
    sed -i '/url: "TEMPLATE_AIRPORT_URL"/d' "$TEMP_FILE"
    # 2. 修改 type 为 file
    sed -i 's/type: http/type: file/' "$TEMP_FILE"
    # 3. 在 type: file 下面插入 path
    sed -i '/type: file/a \    path: "/etc/mihomo/providers/merged.yaml"' "$TEMP_FILE"
    
    echo "✅ 配置生成完成。"

# =======================================================
# 路径 B: 专家模式 (默认 - 下载完整配置)
# =======================================================
else
    # 还原 URL 中的 | 为换行符（如果有），专家模式通常只有一个链接，但也可能误填多个
    # 这里取第一个链接
    REAL_URL=$(echo "$SUB_URL" | cut -d '|' -f 1)
    
    echo "⬇️ 正在下载完整配置文件: $REAL_URL"
    if curl -L -s --fail --retry 3 --connect-timeout 15 -o "$TEMP_FILE" "$REAL_URL"; then
        if ! grep -q "proxies" "$TEMP_FILE" && ! grep -q "proxy-providers" "$TEMP_FILE"; then
             echo "❌ 下载的文件格式不正确。"
             rm -f "$TEMP_FILE"
             exit 1
        fi
        
        OLD_MD5=$(md5sum "$CONFIG_FILE" 2>/dev/null | awk '{print $1}')
        NEW_MD5=$(md5sum "$TEMP_FILE" | awk '{print $1}')
        if [ "$OLD_MD5" == "$NEW_MD5" ]; then
            echo "✅ 订阅内容未变更，无需更新。"
            rm -f "$TEMP_FILE"
            exit 0
        fi
    else
        echo "❌ 订阅下载失败。"
        bash "$NOTIFY_SCRIPT" "❌ 订阅更新失败" "无法连接到订阅服务器。"
        exit 1
    fi
fi

# =======================================================
# 公共逻辑: 注入防回环 & 应用配置
# =======================================================

if [ -n "$LOCAL_CIDR" ]; then
    echo "🔧 [通用] 检测到本地网段设置: $LOCAL_CIDR"
    if grep -q "^rules:" "$TEMP_FILE"; then
        echo "➡️  正在注入 DIRECT 规则..."
        sed -i "/^rules:/a \  - IP-CIDR,${LOCAL_CIDR},DIRECT,no-resolve" "$TEMP_FILE"
    fi
fi

if ! grep -q "external-controller" "$TEMP_FILE"; then
    echo -e "\nexternal-controller: '0.0.0.0:9090'\nexternal-ui: ui\nsecret: ''" >> "$TEMP_FILE"
fi

mv "$TEMP_FILE" "$CONFIG_FILE"
echo "🔄 正在重启 Mihomo..."
systemctl restart mihomo

if [ $? -eq 0 ]; then
    bash "$NOTIFY_SCRIPT" "✅ 配置更新成功" "模式: $CONFIG_MODE - 已应用并重载服务。"
else
    bash "$NOTIFY_SCRIPT" "⚠️ 配置更新异常" "配置文件已更新，但服务重启失败。"
fi
