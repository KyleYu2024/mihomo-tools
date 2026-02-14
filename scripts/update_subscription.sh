#!/bin/bash
# update_subscription.sh - 订阅更新 (支持 Raw/Airport + 自动防回环注入 + 优雅通知)

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
mkdir -p "${MIHOMO_DIR}/providers"

# ==========================================
# 第一阶段：生成基础配置 (Raw 或 Airport)
# ==========================================

if [ "$CONFIG_MODE" == "raw" ]; then
    # --- Raw 模式 (配置托管) ---
    if [ -z "$SUB_URL_RAW" ]; then
        echo "❌ [配置托管] 未配置订阅链接，跳过。"
        exit 0
    fi
    echo "⬇️  [配置托管] 正在下载完整配置..."
    wget --no-check-certificate -O "$TEMP_NEW" "$SUB_URL_RAW" >/dev/null 2>&1
    
    if [ $? -ne 0 ] || [ ! -s "$TEMP_NEW" ]; then
        echo "❌ 下载失败。"
        bash "$NOTIFY_SCRIPT" "❌ 更新失败" "无法下载托管配置。"
        rm -f "$TEMP_NEW"
        exit 1
    fi
else
    # --- Airport 模式 (节点订阅) ---
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "❌ 模板文件缺失: $TEMPLATE_FILE"
        exit 1
    fi
    if [ -z "$SUB_URL_AIRPORT" ]; then
        echo "❌ [节点订阅] 未配置机场链接。"
        exit 0
    fi
    echo "🔨 [节点订阅] 正在构建配置文件..."
    export SUB_URL_AIRPORT
    
    python3 -c "
import sys, yaml, os
template_path = '$TEMPLATE_FILE'
output_path = '$TEMP_NEW'
urls_raw = os.environ.get('SUB_URL_AIRPORT', '').replace('|', '\n').replace('\\\\n', '\\n')

def load_yaml(path):
    if not os.path.exists(path): return {}
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f) or {}

try:
    config = load_yaml(template_path)
    url_list = [line.strip() for line in urls_raw.split('\n') if line.strip()]
    if not url_list:
        print('Error: No valid URLs found')
        sys.exit(1)

    providers = {}
    for index, url in enumerate(url_list):
        name = f'Airport_{index+1:02d}'
        providers[name] = {
            'type': 'http',
            'url': url,
            'interval': 86400,
            'path': f'./providers/airport_{index+1:02d}.yaml',
            'health-check': {'enable': True, 'interval': 600, 'url': 'https://www.gstatic.com/generate_204'}
        }
    config['proxy-providers'] = providers
    
    with open(output_path, 'w', encoding='utf-8') as f:
        yaml.dump(config, f, allow_unicode=True, sort_keys=False)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
"
    if [ $? -ne 0 ]; then
        echo "❌ 生成配置失败。"
        bash "$NOTIFY_SCRIPT" "❌ 生成失败" "YAML 处理错误。"
        rm -f "$TEMP_NEW"
        exit 1
    fi
fi

# ==========================================
# 第二阶段：通用补丁 (注入防回环规则与 TUN/DNS 开关)
# ==========================================

bash "${MIHOMO_DIR}/scripts/patch_config.sh" "$TEMP_NEW"

# ==========================================
# 第三阶段：校验、应用与通知
# ==========================================

if [ ! -s "$TEMP_NEW" ]; then
    rm -f "$TEMP_NEW"
    exit 1
fi

FILE_CHANGED=0
if [ -f "$CONFIG_FILE" ]; then
    if cmp -s "$TEMP_NEW" "$CONFIG_FILE"; then
        echo "✅ 配置无变更。"
        FILE_CHANGED=0
    else
        echo "⚠️  配置有变更。"
        FILE_CHANGED=1
    fi
else
    FILE_CHANGED=1
fi

if [ "$FILE_CHANGED" -eq 1 ]; then
    cp "$CONFIG_FILE" "${BACKUP_DIR}/config_$(date +%Y%m%d%H%M).yaml" 2>/dev/null
    mv "$TEMP_NEW" "$CONFIG_FILE"
    systemctl restart mihomo
    echo "🎉 更新完成并重启。"
    
    # --- 文案转换逻辑 ---
    if [ "$CONFIG_MODE" == "raw" ]; then
        MODE_NAME="配置托管"
    else
        MODE_NAME="节点订阅"
    fi
    
    bash "$NOTIFY_SCRIPT" "♻️ 订阅更新成功" "模式: ${MODE_NAME}"
else
    rm -f "$TEMP_NEW"
fi
