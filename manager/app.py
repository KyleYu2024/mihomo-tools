from flask import Flask, render_template, request, jsonify
import subprocess
import os
import re

app = Flask(__name__)

# === 配置路径 ===
MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
ENV_FILE = f"{MIHOMO_DIR}/.env"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"

# === 辅助函数 ===

def run_cmd(cmd):
    """执行 Shell 命令并返回结果"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout + result.stderr
    except Exception as e:
        return False, str(e)

def read_env():
    """读取 .env 文件为字典"""
    env_data = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, val = line.strip().split('=', 1)
                    env_data[key] = val.strip('"')
    return env_data

def update_env(key, value):
    """更新 .env 文件中的特定键值"""
    lines = []
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, 'r') as f:
            lines = f.readlines()
    
    key_found = False
    new_lines = []
    for line in lines:
        if line.startswith(f"{key}="):
            new_lines.append(f'{key}="{value}"\n')
            key_found = True
        else:
            new_lines.append(line)
    
    if not key_found:
        new_lines.append(f'{key}="{value}"\n')
    
    with open(ENV_FILE, 'w') as f:
        f.writelines(new_lines)

# === 路由定义 ===

@app.route('/')
def index():
    return render_template('index.html')

# --- 1. 状态与控制 ---
@app.route('/api/status')
def get_status():
    service_active = subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0
    # 获取运行时间
    uptime = "未运行"
    if service_active:
        res = subprocess.run("systemctl status mihomo | grep 'Active:'", shell=True, capture_output=True, text=True)
        uptime = res.stdout.strip()
    return jsonify({"running": service_active, "uptime": uptime})

@app.route('/api/control', methods=['POST'])
def control_service():
    action = request.json.get('action')
    cmd_map = {
        'start': 'systemctl start mihomo',
        'stop': 'systemctl stop mihomo',
        'restart': 'systemctl restart mihomo',
        'net_init': f'bash {SCRIPT_DIR}/gateway_init.sh',
        'update_geo': f'bash {SCRIPT_DIR}/update_geo.sh',
        'update_kernel': f'bash {SCRIPT_DIR}/install_kernel.sh auto'
    }
    
    if action in cmd_map:
        success, msg = run_cmd(cmd_map[action])
        return jsonify({"success": success, "message": msg})
    return jsonify({"success": False, "message": "未知指令"})

# --- 2. 订阅与配置 ---
@app.route('/api/config', methods=['GET', 'POST'])
def handle_config():
    if request.method == 'GET':
        # 读取配置内容和当前订阅链接
        content = ""
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                content = f.read()
        env = read_env()
        return jsonify({"content": content, "sub_url": env.get('SUB_URL', '')})
    
    if request.method == 'POST':
        # 保存编辑器内容
        content = request.json.get('content')
        try:
            with open(CONFIG_FILE, 'w') as f:
                f.write(content)
            return jsonify({"success": True})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)})

@app.route('/api/update_sub', methods=['POST'])
def update_subscription():
    url = request.json.get('url')
    if not url:
        return jsonify({"success": False, "message": "链接不能为空"})
    
    # 1. 保存到 .env
    update_env('SUB_URL', url)
    
    # 2. 下载配置 (使用 curl 模拟)
    # 注意：这里简单的覆盖 config.yaml。如果需要复杂逻辑（保留User部分），建议扩充 shell 脚本处理
    cmd = f'curl -L -o {CONFIG_FILE} "{url}"'
    success, msg = run_cmd(cmd)
    
    if success:
        # 自动修补 external-ui
        run_cmd(f"echo '\nexternal-ui: ui' >> {CONFIG_FILE}")
        return jsonify({"success": True, "message": "订阅下载成功，已自动追加 UI 配置"})
    else:
        return jsonify({"success": False, "message": "下载失败: " + msg})

# --- 3. 自动化与通知 ---
@app.route('/api/settings', methods=['GET', 'POST'])
def handle_settings():
    if request.method == 'GET':
        env = read_env()
        # 检查 Crontab 状态
        cron_check = subprocess.run("crontab -l | grep 'update_geo.sh'", shell=True).returncode == 0
        return jsonify({
            "cron_enabled": cron_check,
            "notify_type": env.get('NOTIFY_TYPE', 'none'),
            "tg_token": env.get('TG_BOT_TOKEN', ''),
            "tg_id": env.get('TG_CHAT_ID', '')
        })

    if request.method == 'POST':
        data = request.json
        # 1. 保存通知设置
        update_env('NOTIFY_TYPE', data.get('notify_type'))
        update_env('TG_BOT_TOKEN', data.get('tg_token'))
        update_env('TG_CHAT_ID', data.get('tg_id'))
        
        # 2. 设置 Crontab (每天凌晨4点更新)
        cron_job = f"0 4 * * * bash {SCRIPT_DIR}/update_geo.sh >/dev/null 2>&1"
        if data.get('cron_enabled'):
            # 添加任务 (先清空相关旧任务)
            run_cmd(f"(crontab -l 2>/dev/null | grep -v 'update_geo.sh'; echo '{cron_job}') | crontab -")
        else:
            # 移除任务
            run_cmd("crontab -l 2>/dev/null | grep -v 'update_geo.sh' | crontab -")
            
        return jsonify({"success": True, "message": "设置已保存"})

# --- 4. 日志 ---
@app.route('/api/logs')
def get_logs():
    # 获取最后 100 行日志
    success, logs = run_cmd("journalctl -u mihomo -n 100 --no-pager")
    return jsonify({"logs": logs})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
