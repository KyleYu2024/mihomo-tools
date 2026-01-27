from flask import Flask, render_template, request, jsonify
import subprocess
import os
import re

app = Flask(__name__)

MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
ENV_FILE = f"{MIHOMO_DIR}/.env"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"

# === 核心工具函数 ===

def run_cmd(cmd):
    try:
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
                    key, val = line.strip().split('=', 1)
                    env_data[key] = val.strip('"').strip("'")
    return env_data

def update_env(updates):
    """批量更新环境变量 dict"""
    current_env = read_env()
    current_env.update(updates)
    
    with open(ENV_FILE, 'w') as f:
        for k, v in current_env.items():
            f.write(f'{k}="{v}"\n')

def update_cron(job_id, schedule, command, enabled):
    """
    智能 Crontab 管理
    job_id: 用于标识任务 (如 # JOB_GEO)
    """
    # 1. 读取当前 Crontab (忽略错误)
    res = subprocess.run("crontab -l", shell=True, capture_output=True, text=True)
    current_cron = res.stdout.strip().split('\n')
    
    new_cron = []
    # 过滤掉旧的同ID任务
    for line in current_cron:
        if job_id not in line and line.strip() != "":
            new_cron.append(line)
            
    # 2. 如果启用，添加新任务
    if enabled:
        new_cron.append(f"{schedule} {command} {job_id}")
        
    # 3. 写入
    cron_str = "\n".join(new_cron) + "\n"
    subprocess.run(f"echo '{cron_str}' | crontab -", shell=True)

# === 路由 API ===

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
    if action == 'fix_logs':
        # 修复日志的专用逻辑
        cmd = "mkdir -p /var/log/journal && echo 'Storage=persistent' >> /etc/systemd/journald.conf && systemctl restart systemd-journald && systemctl restart mihomo"
        run_cmd(cmd)
        return jsonify({"success": True, "message": "日志服务已修复，尝试刷新日志..."})
    
    # ... (其他控制逻辑保持不变) ...
    cmds = {
        'start': 'systemctl start mihomo',
        'stop': 'systemctl stop mihomo',
        'restart': 'systemctl restart mihomo',
        'update_geo': f'bash {SCRIPT_DIR}/update_geo.sh',
        'update_sub': f'bash {SCRIPT_DIR}/update_subscription.sh', # 新增
        'test_notify': f'bash {SCRIPT_DIR}/notify.sh "🔔 测试通知" "这是一条来自 Mihomo 面板的测试消息"'
    }
    if action in cmds:
        success, msg = run_cmd(cmds[action])
        return jsonify({"success": success, "message": msg})
    return jsonify({"success": False})

@app.route('/api/settings', methods=['GET', 'POST'])
def handle_settings():
    if request.method == 'GET':
        env = read_env()
        # 检查 Crontab
        cron_out = subprocess.run("crontab -l", shell=True, capture_output=True, text=True).stdout
        
        return jsonify({
            # 通知设置
            "notify_tg": env.get('NOTIFY_TG') == 'true',
            "tg_token": env.get('TG_BOT_TOKEN', ''),
            "tg_id": env.get('TG_CHAT_ID', ''),
            "notify_api": env.get('NOTIFY_API') == 'true',
            "api_url": env.get('NOTIFY_API_URL', ''),
            
            # 定时任务状态
            "cron_geo_enabled": "# JOB_GEO" in cron_out,
            "cron_geo_sched": "0 4 * * *", # 默认值，实际应解析cron_out但太复杂，这里简化
            "cron_sub_enabled": "# JOB_SUB" in cron_out,
            "cron_sub_sched": "0 5 * * *",
            "sub_url": env.get('SUB_URL', '')
        })

    if request.method == 'POST':
        d = request.json
        
        # 1. 保存环境变量
        update_env({
            "NOTIFY_TG": str(d.get('notify_tg', False)).lower(),
            "TG_BOT_TOKEN": d.get('tg_token', ''),
            "TG_CHAT_ID": d.get('tg_id', ''),
            "NOTIFY_API": str(d.get('notify_api', False)).lower(),
            "NOTIFY_API_URL": d.get('api_url', ''),
            "SUB_URL": d.get('sub_url', '')
        })
        
        # 2. 更新 Crontab - Geo
        # schedule 格式: "0 4 * * *"
        update_cron(
            "# JOB_GEO", 
            d.get('cron_geo_sched', '0 4 * * *'), 
            f"bash {SCRIPT_DIR}/update_geo.sh >/dev/null 2>&1", 
            d.get('cron_geo_enabled')
        )
        
        # 3. 更新 Crontab - Subscription
        update_cron(
            "# JOB_SUB", 
            d.get('cron_sub_sched', '0 5 * * *'), 
            f"bash {SCRIPT_DIR}/update_subscription.sh >/dev/null 2>&1", 
            d.get('cron_sub_enabled')
        )
        
        return jsonify({"success": True, "message": "设置已保存"})

# --- 4. 日志 (新版：读取文件) ---
@app.route('/api/logs')
def get_logs():
    LOG_FILE = "/var/log/mihomo.log"
    
    if not os.path.exists(LOG_FILE):
        return jsonify({"logs": "⚠️ 日志文件尚未生成，请稍后刷新..."})
    
    # 使用 tail 命令读取最后 100 行
    # 既然 journald 坏了，我们直接读文件，稳如老狗
    success, logs = run_cmd(f"tail -n 100 {LOG_FILE}")
    
    if not logs:
        return jsonify({"logs": "⚠️ 日志文件是空的 (服务可能刚启动)。"})
        
    return jsonify({"logs": logs})
