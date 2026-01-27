from flask import Flask, render_template, request, jsonify
import subprocess
import os

app = Flask(__name__)

MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
ENV_FILE = f"{MIHOMO_DIR}/.env"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"

def run_cmd(cmd):
    try:
        # 增加 sudo 兼容性，确保以 root 权限运行
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout + result.stderr
    except Exception as e:
        return False, str(e)

def read_env():
    env_data = {}
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE, 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    parts = line.strip().split('=', 1)
                    if len(parts) == 2:
                        env_data[parts[0]] = parts[1].strip('"').strip("'")
    return env_data

def update_cron(job_id, schedule, command, enabled):
    """Crontab 管理函数"""
    try:
        # 1. 读取当前 Crontab
        res = subprocess.run("crontab -l", shell=True, capture_output=True, text=True)
        current_cron = res.stdout.strip().split('\n')
        
        new_cron = []
        # 过滤掉包含 job_id 的旧任务
        for line in current_cron:
            if job_id not in line and line.strip() != "":
                new_cron.append(line)
                
        # 2. 如果启用，添加新任务
        if enabled:
            # 确保日志输出被丢弃，防止 exim4 发邮件报错
            new_cron.append(f"{schedule} {command} {job_id}")
            
        # 3. 写入新的 Crontab
        cron_str = "\n".join(new_cron) + "\n"
        subprocess.run(f"echo '{cron_str}' | crontab -", shell=True)
    except Exception as e:
        print(f"Cron Error: {e}")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    service_active = subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0
    return jsonify({"running": service_active})

@app.route('/api/control', methods=['POST'])
def control_service():
    action = request.json.get('action')
    
    cmds = {
        'start': 'systemctl start mihomo',
        'stop': 'systemctl stop mihomo',
        'restart': 'systemctl restart mihomo',
        'update_geo': f'bash {SCRIPT_DIR}/update_geo.sh',
        'update_sub': f'bash {SCRIPT_DIR}/update_subscription.sh',
        'net_init': f'bash {SCRIPT_DIR}/gateway_init.sh',
        'fix_logs': 'systemctl restart mihomo',
        # 通知测试：强制先 source 环境文件
        'test_notify': f'bash {SCRIPT_DIR}/notify.sh "🔔 通知测试" "恭喜！如果你收到这条消息，说明通知配置正确。"'
    }
    
    if action in cmds:
        success, msg = run_cmd(cmds[action])
        return jsonify({"success": success, "message": msg})
    return jsonify({"success": False, "message": "未知指令"})

@app.route('/api/config', methods=['GET', 'POST'])
def handle_config():
    if request.method == 'GET':
        content = ""
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                content = f.read()
        env = read_env()
        return jsonify({"content": content, "sub_url": env.get('SUB_URL', '')})
        
    if request.method == 'POST':
        content = request.json.get('content')
        try:
            with open(CONFIG_FILE, 'w') as f:
                f.write(content)
            return jsonify({"success": True, "message": "配置已保存"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)})

@app.route('/api/settings', methods=['GET', 'POST'])
def handle_settings():
    if request.method == 'GET':
        env = read_env()
        cron_out = subprocess.run("crontab -l", shell=True, capture_output=True, text=True).stdout
        return jsonify({
            # 通知
            "notify_tg": env.get('NOTIFY_TG') == 'true',
            "tg_token": env.get('TG_BOT_TOKEN', ''),
            "tg_id": env.get('TG_CHAT_ID', ''),
            "notify_api": env.get('NOTIFY_API') == 'true',
            "api_url": env.get('NOTIFY_API_URL', ''),
            # 订阅 & 任务
            "sub_url": env.get('SUB_URL', ''),
            "cron_sub_enabled": "# JOB_SUB" in cron_out,
            "cron_sub_sched": "0 5 * * *", # 这里没法从cron反解析，只能给默认值或前端缓存，简化处理
            "cron_geo_enabled": "# JOB_GEO" in cron_out,
            "cron_geo_sched": "0 4 * * *"
        })

    if request.method == 'POST':
        d = request.json
        
        # 1. 更新 .env
        updates = {
            "NOTIFY_TG": str(d.get('notify_tg', False)).lower(),
            "TG_BOT_TOKEN": d.get('tg_token', ''),
            "TG_CHAT_ID": d.get('tg_id', ''),
            "NOTIFY_API": str(d.get('notify_api', False)).lower(),
            "NOTIFY_API_URL": d.get('api_url', ''),
            "SUB_URL": d.get('sub_url', '')
        }
        
        lines = []
        if os.path.exists(ENV_FILE):
            with open(ENV_FILE, 'r') as f:
                lines = f.readlines()
        
        new_lines = []
        updated_keys = set()
        for line in lines:
            if '=' in line:
                key = line.split('=')[0].strip()
                if key in updates:
                    new_lines.append(f'{key}="{updates[key]}"\n')
                    updated_keys.add(key)
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)
        
        for k, v in updates.items():
            if k not in updated_keys:
                new_lines.append(f'{k}="{v}"\n')
                
        with open(ENV_FILE, 'w') as f:
            f.writelines(new_lines)

        # 2. 更新 Crontab (找回的功能!)
        # 订阅更新任务
        update_cron(
            "# JOB_SUB", 
            d.get('cron_sub_sched', '0 5 * * *'), 
            f"bash {SCRIPT_DIR}/update_subscription.sh >/dev/null 2>&1", 
            d.get('cron_sub_enabled')
        )
        
        # Geo 更新任务
        update_cron(
            "# JOB_GEO", 
            d.get('cron_geo_sched', '0 4 * * *'), 
            f"bash {SCRIPT_DIR}/update_geo.sh >/dev/null 2>&1", 
            d.get('cron_geo_enabled')
        )

        return jsonify({"success": True, "message": "所有设置已保存 (Crontab 已更新)"})

@app.route('/api/logs')
def get_logs():
    LOG_FILE = "/var/log/mihomo.log"
    if not os.path.exists(LOG_FILE):
        return jsonify({"logs": "⚠️ 日志文件尚未生成..."})
    try:
        success, logs = run_cmd(f"tail -n 100 {LOG_FILE}")
        return jsonify({"logs": logs if logs else "日志为空"})
    except:
        return jsonify({"logs": "读取失败"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
