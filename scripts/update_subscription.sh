#!/bin/bash
# update_subscription.sh - 订阅更新 (支持 Raw 直连 和 Airport 模板注入)

MIHOMO_DIR="/etc/mihomo"
ENV_FILE="${MIHOMO_DIR}/.env"
CONFIG_FILE="${MIHOMO_DIR}/config.yaml"
TEMPLATE_FILE="${MIHOMO_DIR}/templates/default.yaml"
BACKUP_DIR="${MIHOMO_DIR}/backup"
NOTIFY_SCRIPT="${MIHOMO_DIR}/scripts/notify.sh"
TEMP_NEW="/tmp/config_generated.yaml"

# 1. 加载环境变量
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

mkdir -p "$BACKUP_DIR"
mkdir -p "${MIHOMO_DIR}/providers" # 确保 provider 目录存在

# --------------------------------------------------------
# 模式 A: Raw 直连模式 (拉取完整配置)
# --------------------------------------------------------
if [ "$CONFIG_MODE" == "raw" ]; then
    if [ -z "$SUB_URL_RAW" ]; then
        echo "❌ [Raw模式] 未配置订阅链接，跳过。"
        exit 0
    fi
    
    echo "⬇️  [Raw模式] 正在下载完整配置..."
    wget --no-check-certificate -O "$TEMP_NEW" "$SUB_URL_RAW" >/dev/null 2>&1
    
    if [ $? -ne 0 ] || [ ! -s "$TEMP_NEW" ]; then
        echo "❌ 下载失败。"
        bash "$NOTIFY_SCRIPT" "❌ 更新失败" "无法下载 Raw 配置文件。"
        rm -f "$TEMP_NEW"
        exit 1
    fi

# --------------------------------------------------------
# 模式 B: Airport 机场模式 (注入模板)
# --------------------------------------------------------
else
    # 默认 fallback 到 airport 模式
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "❌ 模板文件缺失: $TEMPLATE_FILE"
        exit 1
    fi
    
    # 将 .env 里的转义换行符还原，处理多行 URL
    # 如果 SUB_URL_AIRPORT 为空，提示
    if [ -z "$SUB_URL_AIRPORT" ]; then
        echo "❌ [Airport模式] 未配置机场链接。"
        exit 0
    fi
    
    echo "🔨 [Airport模式] 正在生成配置文件..."
    
    # 使用 Python 动态注入 Proxy Providers
    python3 -c "
import sys, yaml, os

template_path = '$TEMPLATE_FILE'
output_path = '$TEMP_NEW'
# 从环境变量读取，并还原换行符
urls_raw = os.environ.get('SUB_URL_AIRPORT', '').replace('\\\\n', '\\n')

def load_yaml(path):
    if not os.path.exists(path): return {}
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f) or {}

try:
    # 1. 加载模板
    config = load_yaml(template_path)
    
    # 2. 解析 URL 列表 (按行分割，忽略空行)
    url_list = [line.strip() for line in urls_raw.split('\n') if line.strip()]
    
    if not url_list:
        print('Error: No valid URLs found')
        sys.exit(1)

    # 3. 动态生成 proxy-providers
    # 模板里可能有默认的 provider，先清空或覆盖
    providers = {}
    
    for index, url in enumerate(url_list):
        # 生成 provider 名称: Airport_01, Airport_02...
        name = f'Airport_{index+1:02d}'
        providers[name] = {
            'type': 'http',
            'url': url,
            'interval': 86400,
            'path': f'./providers/airport_{index+1:02d}.yaml',
            'health-check': {
                'enable': True,
                'interval': 600,
                'url': 'https://www.gstatic.com/generate_204'
            }
        }
    
    # 注入到配置对象中
    config['proxy-providers'] = providers
    
    # 4. 写入新文件
    with open(output_path, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, sort_keys=False)

except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
"
    
    if [ $? -ne 0 ]; then
        echo "❌ 生成配置失败。"
        bash "$NOTIFY_SCRIPT" "❌ 生成失败" "YAML 处理错误，请检查模板。"
        rm -f "$TEMP_NEW"
        exit 1
    fi
fi

# --------------------------------------------------------
# 通用步骤: 校验与应用
# --------------------------------------------------------

# 简单校验
if [ ! -s "$TEMP_NEW" ]; then
    echo "❌ 生成的文件为空。"
    rm -f "$TEMP_NEW"
    exit 1
fi

# 比对差异
FILE_CHANGED=0
if [ -f "$CONFIG_FILE" ]; then
    if cmp -s "$TEMP_NEW" "$CONFIG_FILE"; then
        echo "✅ 配置无变更。"
    else
        echo "⚠️  配置有变更。"
        FILE_CHANGED=1
    fi
else
    FILE_CHANGED=1
fi

# 应用更新
if [ "$FILE_CHANGED" -eq 1 ]; then
    cp "$CONFIG_FILE" "${BACKUP_DIR}/config_$(date +%Y%m%d%H%M).yaml" 2>/dev/null
    mv "$TEMP_NEW" "$CONFIG_FILE"
    systemctl restart mihomo
    
    echo "🎉 更新完成并重启。"
    # 这里的通知会由 cron 触发，或者手动触发
    bash "$NOTIFY_SCRIPT" "♻️ 订阅更新成功" "模式: ${CONFIG_MODE:-airport}"
else
    rm -f "$TEMP_NEW"
fi
