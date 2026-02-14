#!/bin/bash
# patch_config.sh - 应用 .env 中的全局开关到指定的 YAML 文件

TARGET_FILE="$1"
if [ -z "$TARGET_FILE" ] || [ ! -f "$TARGET_FILE" ]; then
    echo "用法: $0 <config_file>"
    exit 1
fi

if [ -f "/etc/mihomo/.env" ]; then source /etc/mihomo/.env; fi

export TUN_ENABLED="${TUN_ENABLED:-true}"
export DNS_HIJACK_ENABLED="${DNS_HIJACK_ENABLED:-true}"
export LOCAL_CIDR="${LOCAL_CIDR}"

# 如果环境变量中没有物理网卡信息，尝试现场探测
if [ -z "$PHYSICAL_IFACE" ]; then
    PHYSICAL_IFACE=$(ip route get 223.5.5.5 2>/dev/null | awk '/dev/ {print $5; exit}')
    if [ -z "$PHYSICAL_IFACE" ]; then
        PHYSICAL_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n 1)
    fi
fi
export PHYSICAL_IFACE="${PHYSICAL_IFACE}"

python3 -c "
import sys, yaml, os

config_path = '$TARGET_FILE'
tun_enabled = os.environ.get('TUN_ENABLED', 'true').lower() == 'true'
dns_hijack_enabled = os.environ.get('DNS_HIJACK_ENABLED', 'true').lower() == 'true'
local_cidr = os.environ.get('LOCAL_CIDR', '').strip()
physical_iface = os.environ.get('PHYSICAL_IFACE', '').strip()

def load_yaml(path):
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f) or {}

def save_yaml(data, path):
    with open(path, 'w', encoding='utf-8') as f:
        yaml.dump(data, f, allow_unicode=True, sort_keys=False)

try:
    config = load_yaml(config_path)

    # 1. TUN 设置
    if 'tun' not in config or not isinstance(config['tun'], dict):
        config['tun'] = {}
    config['tun']['enable'] = tun_enabled
    
    # 【关键修复】显式指定物理网卡，避免 auto-detect 报错
    if physical_iface:
        config['tun']['device'] = 'mihomo-tun' # 固定 TUN 设备名
        config['tun']['auto-detect-interface'] = False # 关闭自动检测
        config['interface-name'] = physical_iface # 绑定物理出口
        print(f'✅ 已绑定物理网卡: {physical_iface}')
    else:
        # 如果没探测到，保持原样或默认开启自动
        config['tun']['auto-detect-interface'] = True

    if dns_hijack_enabled:
        config['tun']['dns-hijack'] = ['any:53', 'tcp://any:53']
    else:
        config['tun']['dns-hijack'] = []

    # 2. DNS 设置 (监听端口)
    if 'dns' not in config or not isinstance(config['dns'], dict):
        config['dns'] = {}
    
    # 强制开启 DNS 模块，否则无法处理解析请求
    config['dns']['enable'] = True
    
    if dns_hijack_enabled:
        config['dns']['listen'] = '0.0.0.0:53'
    else:
        # 如果关闭劫持，则监听 1053 端口，供 MosDNS 转发
        config['dns']['listen'] = '0.0.0.0:1053'

    # 3. 防回环规则 (基础补丁)
    if 'rules' not in config or config['rules'] is None:
        config['rules'] = []

    if local_cidr:
        loop_rule = f'IP-CIDR,{local_cidr},DIRECT,no-resolve'
        # 移除旧的同类规则
        config['rules'] = [r for r in config['rules'] if not (isinstance(r, str) and 'IP-CIDR' in r and 'DIRECT' in r and 'no-resolve' in r)]
        # 插入到第一位
        config['rules'].insert(0, loop_rule)

    save_yaml(config, config_path)
    print(f'✅ 已应用全局开关到 {config_path}')
except Exception as e:
    print(f'❌ 补丁应用失败: {e}')
    sys.exit(1)
"
