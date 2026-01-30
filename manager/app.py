from flask import Flask, render_template, request, jsonify, Response, redirect, session
from functools import wraps
from datetime import timedelta
import subprocess
import os

app = Flask(__name__)
app.secret_key = "mihomo-manager-secret"
app.permanent_session_lifetime = timedelta(days=365)

MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
ENV_FILE = f"{MIHOMO_DIR}/.env"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"
LOG_FILE = "/var/log/mihomo.log"

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout + result.stderr
    except Exception as e:
        return False, str(e)

def read_env():
    env_data = {}
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE, 'r', encoding='utf-8') as f:
                for line in f:
                    if '=' in line and not line.strip().startswith('#'):
                        parts = line.strip().split('=', 1)
                        if len(parts) == 2:
                            env_data[parts[0].strip()] = parts[1].strip().strip('"').strip("'")
        except: pass
    return env_data

def check_creds(username, password):
    env = read_env()
    valid_user = os.environ.get('WEB_USER') or env.get('WEB_USER', 'admin')
    valid_pass = os.environ.get('WEB_SECRET') or env.get('WEB_SECRET', 'admin')
    return username == valid_user and password == valid_pass

def update_cron(job_id, schedule, command, enabled):
    try:
        res = subprocess.run("crontab -l", shell=True, capture_output=True, text=True)
        current_cron = res.stdout.strip().split('\n') if res.stdout else []
        new_cron = []
        for line in current_cron:
            if job_id not in line and line.strip() != "":
                new_cron.append(line)
        if enabled:
            new_cron.append(f"{schedule} {command} {job_id}")
        cron_str = "\n".join(new_cron) + "\n"
        subprocess.run(f"echo '{cron_str}' | crontab -", shell=True)
    except: pass

def is_true(val): return str(val).lower() == 'true'

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            if request.path.startswith('/api'): return jsonify({"error": "Unauthorized"}), 401
            return redirect('/login')
        return f(*args, **kwargs)
    return decorated

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if check_creds(request.form.get('username'), request.form.get('password')):
            session['logged_in'] = True; session.permanent = True
            return redirect('/')
        return render_template('login.html', error="用户名或密码错误")
    return redirect('/') if session.get('logged_in') else render_template('login.html')

@app.route('/logout')
def logout(): session.pop('logged_in', None); return redirect('/login')

@app.route('/')
def index(): return render_template('index.html') if session.get('logged_in') else redirect('/login')

@app.route('/api/status')
@login_required
def get_status():
    return jsonify({"running": subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0})

@app.route('/api/control', methods=['POST'])
@login_required
def control_service():
    action = request.json.get('action')
    cmds = {
        'start': 'systemctl start mihomo',
        'stop': 'systemctl stop mihomo',
        'restart': 'systemctl restart mihomo',
        'fix_logs': 'systemctl restart mihomo',
        'update_sub': f'bash {SCRIPT_DIR}/update_subscription.sh',
        'update_geo': f'bash {SCRIPT_DIR}/update_geo.sh',
        'net_init': f'bash {SCRIPT_DIR}/gateway_init.sh',
        'test_notify': f'bash {SCRIPT_DIR}/notify.sh "测试" "Web端测试消息"'
    }
    if action in cmds:
        s, m = run_cmd(cmds[action])
        return jsonify({"success": s, "message": m})
    return jsonify({"success": False, "message": "未知指令"})

@app.route('/api/config', methods=['GET', 'POST'])
@login_required
def handle_config():
    if request.method == 'GET':
        c = ""
        if os.path.exists(CONFIG_FILE):
            try: with open(CONFIG_FILE,'r', encoding='utf-8') as f: c = f.read()
            except: pass
        return jsonify({"content": c})
    if request.method == 'POST':
        try:
            with open(CONFIG_FILE,'w', encoding='utf-8') as f: f.write(request.json.get('content'))
            return jsonify({"success": True, "message": "配置已保存"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)})

@app.route('/api/logs')
@login_required
def get_logs():
    if not os.path.exists(LOG_FILE): return jsonify({"logs": "日志未生成"})
    s, l = run_cmd(f"tail -n 100 {LOG_FILE}")
    return jsonify({"logs": l if l else "暂无日志"})

@app.route('/api/settings', methods=['GET', 'POST'])
@login_required
def handle_settings():
    if request.method == 'GET':
        e = read_env()
        # 将换行符还原，供前端 Textarea 显示
        sub_url_airport = e.get('SUB_URL_AIRPORT', '').replace('\\n', '\n')
        
        return jsonify({
            "web_user": e.get('WEB_USER'),
            
            # 模式: 'raw' 或 'airport'
            "config_mode": e.get('CONFIG_MODE', 'airport'),
            
            # 链接
            "sub_url_raw": e.get('SUB_URL_RAW', ''),
            "sub_url_airport": sub_url_airport,
            
            # 通知 (全字段返回防 undefined)
            "notify_tg": e.get('NOTIFY_TG') == 'true',
            "tg_token": e.get('TG_BOT_TOKEN', ''),
            "tg_bot_token": e.get('TG_BOT_TOKEN', ''),
            "tg_id": e.get('TG_CHAT_ID', ''),
            "tg_chat_id": e.get('TG_CHAT_ID', ''),
            "notify_api": e.get('NOTIFY_API') == 'true',
            "api_url": e.get('NOTIFY_API_URL', ''),
            "notify_api_url": e.get('NOTIFY_API_URL', ''),
            
            # 其他
            "local_cidr": e.get('LOCAL_CIDR', ''),
            "cron_sub_enabled": e.get('CRON_SUB_ENABLED') == 'true',
            "cron_sub_sched": e.get('CRON_SUB_SCHED', '0 5 * * *'), 
            "cron_sub_schedule": e.get('CRON_SUB_SCHED', '0 5 * * *'),
            "cron_geo_enabled": e.get('CRON_GEO_ENABLED') == 'true',
            "cron_geo_sched": e.get('CRON_GEO_SCHED', '0 4 * * *'),
            "cron_geo_schedule": e.get('CRON_GEO_SCHED', '0 4 * * *')
        })

    if request.method == 'POST':
        d = request.json
        mode = d.get('config_mode', 'airport')
        
        # 处理多行 URL，转义换行符
        raw_airport = d.get('sub_url_airport', '')
        if isinstance(raw_airport, list): raw_airport = "\n".join(raw_airport)
        escaped_airport = raw_airport.replace('\n', '\\n')

        # 兼容 key
        tg_token = d.get('tg_token') or d.get('tg_bot_token') or ''
        tg_id = d.get('tg_id') or d.get('tg_chat_id') or ''
        api_url = d.get('api_url') or d.get('notify_api_url') or ''
        cron_sub = d.get('cron_sub_sched') or d.get('cron_sub_schedule') or '0 5 * * *'
        cron_geo = d.get('cron_geo_sched') or d.get('cron_geo_schedule') or '0 4 * * *'

        updates = {
            "CONFIG_MODE": mode,
            "SUB_URL_RAW": d.get('sub_url_raw', ''),
            "SUB_URL_AIRPORT": escaped_airport,
            
            "NOTIFY_TG": str(is_true(d.get('notify_tg'))).lower(),
            "TG_BOT_TOKEN": tg_token,
            "TG_CHAT_ID": tg_id,
            
            "NOTIFY_API": str(is_true(d.get('notify_api'))).lower(),
            "NOTIFY_API_URL": api_url,
            
            "LOCAL_CIDR": d.get('local_cidr', ''),
            
            "CRON_SUB_ENABLED": str(is_true(d.get('cron_sub_enabled'))).lower(),
            "CRON_SUB_SCHED": cron_sub,
            
            "CRON_GEO_ENABLED": str(is_true(d.get('cron_geo_enabled'))).lower(),
            "CRON_GEO_SCHED": cron_geo
        }
        
        # 写入 .env
        lines = []
        if os.path.exists(ENV_FILE):
            with open(ENV_FILE,'r', encoding='utf-8') as f: lines = f.readlines()
        with open(ENV_FILE, 'w') as f:
            keys = set()
            for line in lines:
                if '=' in line and not line.strip().startswith('#'):
                    k = line.split('=')[0].strip()
                    if k in updates:
                        f.write(f'{k}="{updates[k]}"\n')
                        keys.add(k)
                    else: f.write(line)
                else: f.write(line)
            for k,v in updates.items():
                if k not in keys: f.write(f'{k}="{v}"\n')
        
        update_cron("# JOB_SUB", updates['CRON_SUB_SCHED'], f"bash {SCRIPT_DIR}/update_subscription.sh >/dev/null 2>&1", updates['CRON_SUB_ENABLED'] == 'true')
        update_cron("# JOB_GEO", updates['CRON_GEO_SCHED'], f"bash {SCRIPT_DIR}/update_geo.sh >/dev/null 2>&1", updates['CRON_GEO_ENABLED'] == 'true')
        
        return jsonify({"success": True, "message": "配置已成功保存！"})

if __name__ == '__main__':
    env = read_env()
    try: port = int(env.get('WEB_PORT', 7838))
    except: port = 7838
    app.run(host='0.0.0.0', port=port)
