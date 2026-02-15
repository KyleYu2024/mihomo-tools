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

def is_true(val):
    return str(val).lower() == 'true'

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
            session['logged_in'] = True
            session.permanent = True
            return redirect('/')
        return render_template('login.html', error="用户名或密码错误")
    
    if session.get('logged_in'):
        return redirect('/')
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.pop('logged_in', None)
    return redirect('/login')

@app.route('/')
def index():
    if session.get('logged_in'):
        return render_template('index.html')
    return redirect('/login')

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
            try:
                with open(CONFIG_FILE,'r', encoding='utf-8') as f:
                    c = f.read()
            except:
                pass
        return jsonify({"content": c})
    if request.method == 'POST':
        try:
            with open(CONFIG_FILE,'w', encoding='utf-8') as f:
                f.write(request.json.get('content'))
            return jsonify({"success": True, "message": "配置已保存"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)})

@app.route('/api/logs')
@login_required
def get_logs():
    # 从 systemd journal 读取最新 100 行日志
    s, l = run_cmd("journalctl -u mihomo -n 100 --no-pager")
    return jsonify({"logs": l if l else "暂无日志"})

@app.route('/api/settings', methods=['GET', 'POST'])
@login_required
def handle_settings():
    if request.method == 'GET':
        e = read_env()
        return jsonify({
            "web_user": e.get('WEB_USER'),
            "web_port": e.get('WEB_PORT', '7838'),
            
            "sub_url": e.get('SUB_URL', ''),
            
            # 仅 Webhook
            "notify_api": e.get('NOTIFY_API') == 'true',
            "api_url": e.get('NOTIFY_API_URL', ''),
            "notify_api_url": e.get('NOTIFY_API_URL', ''),
            
            "local_cidr": e.get('LOCAL_CIDR', ''),
            "cron_sub_enabled": e.get('CRON_SUB_ENABLED') == 'true',
            "cron_sub_sched": e.get('CRON_SUB_SCHED', '0 5 * * *'), 
            "cron_sub_schedule": e.get('CRON_SUB_SCHED', '0 5 * * *'),
            "cron_geo_enabled": e.get('CRON_GEO_ENABLED') == 'true',
            "cron_geo_sched": e.get('CRON_GEO_SCHED', '0 4 * * *'),
            "cron_geo_schedule": e.get('CRON_GEO_SCHED', '0 4 * * *'),
            
            "tun_enabled": e.get('TUN_ENABLED', 'true') == 'true',
            "dns_hijack": e.get('DNS_HIJACK_ENABLED', 'true') == 'true'
        })

    if request.method == 'POST':
        d = request.json
        api_url = d.get('api_url') or d.get('notify_api_url') or ''
        cron_sub = d.get('cron_sub_sched') or d.get('cron_sub_schedule') or '0 5 * * *'
        cron_geo = d.get('cron_geo_sched') or d.get('cron_geo_schedule') or '0 4 * * *'

        updates = {
            "SUB_URL": d.get('sub_url', ''),
            
            # 仅更新 API 配置
            "NOTIFY_API": str(is_true(d.get('notify_api'))).lower(),
            "NOTIFY_API_URL": api_url,
            
            "LOCAL_CIDR": d.get('local_cidr', ''),
            
            "CRON_SUB_ENABLED": str(is_true(d.get('cron_sub_enabled'))).lower(),
            "CRON_SUB_SCHED": cron_sub,
            
            "CRON_GEO_ENABLED": str(is_true(d.get('cron_geo_enabled'))).lower(),
            "CRON_GEO_SCHED": cron_geo,

            "TUN_ENABLED": str(is_true(d.get('tun_enabled'))).lower(),
            "DNS_HIJACK_ENABLED": str(is_true(d.get('dns_hijack'))).lower()
        }
        
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
        
        # 应用设置到 config.yaml
        run_cmd(f"bash {SCRIPT_DIR}/apply_settings.sh")

        return jsonify({"success": True, "message": "配置已成功保存并应用！"})

if __name__ == '__main__':
    env = read_env()
    try:
        port = int(env.get('WEB_PORT', 7838))
    except:
        port = 7838
    app.run(host='0.0.0.0', port=port)
