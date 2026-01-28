from flask import Flask, render_template, request, jsonify, Response, redirect, session, render_template_string
from functools import wraps
from datetime import timedelta
import subprocess
import os

app = Flask(__name__)

# === 配置 Session ===
# 设置密钥 (用于签名 Cookie)，这里简单使用固定字符串，保证重启服务后登录不失效
# 你也可以在 .env 里配置 SECRET_KEY="xxx"
app.secret_key = "mihomo-manager-secret-key-permanent"
# 设置 Session 有效期为 1 年
app.permanent_session_lifetime = timedelta(days=365)

MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
ENV_FILE = f"{MIHOMO_DIR}/.env"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"

# === 嵌入式登录页面 HTML (免去上传新文件的麻烦) ===
LOGIN_PAGE_HTML = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Mihomo 登录</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background: #f4f6f9; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .login-card { width: 100%; max-width: 400px; padding: 2rem; background: #fff; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.05); }
        .btn-primary { width: 100%; padding: 10px; font-weight: bold; }
        .logo { width: 60px; height: 60px; margin-bottom: 1rem; border-radius: 12px; }
        @media (prefers-color-scheme: dark) {
            body { background: #121212; color: #eee; }
            .login-card { background: #1e1e1e; box-shadow: none; border: 1px solid #333; }
            .form-control { background: #2b2b2b; border-color: #333; color: #eee; }
        }
    </style>
</head>
<body>
    <div class="login-card text-center">
        <img src="/static/logo.png" alt="Logo" class="logo">
        <h4 class="mb-4 fw-bold">Mihomo Manager</h4>
        <form method="POST">
            <div class="mb-3 text-start">
                <label class="form-label text-muted small">用户名</label>
                <input type="text" name="username" class="form-control" placeholder="默认 admin" required>
            </div>
            <div class="mb-4 text-start">
                <label class="form-label text-muted small">密码</label>
                <input type="password" name="password" class="form-control" placeholder="默认 admin" required>
            </div>
            <button type="submit" class="btn btn-primary">登 录</button>
            {% if error %}
            <div class="mt-3 text-danger small">{{ error }}</div>
            {% endif %}
        </form>
    </div>
</body>
</html>
"""

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
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        parts = line.split('=', 1)
                        if len(parts) == 2:
                            env_data[parts[0].strip()] = parts[1].strip().strip('"').strip("'")
        except:
            pass
    return env_data

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
    except Exception as e:
        print(f"Cron Error: {e}")

def is_true(val):
    return str(val).lower() == 'true'

# --- 鉴权逻辑 (Cookie Session 版) ---

def check_creds(username, password):
    env = read_env()
    valid_user = env.get('WEB_USER', 'admin')
    valid_pass = env.get('WEB_SECRET', 'admin')
    return username == valid_user and password == valid_pass

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        # 检查 Session 是否存在
        if not session.get('logged_in'):
            # 如果是 API 请求，返回 401
            if request.path.startswith('/api'):
                return jsonify({"error": "Unauthorized"}), 401
            # 如果是页面请求，跳转登录页
            return redirect('/login')
        return f(*args, **kwargs)
    return decorated

# --- 路由 ---

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        user = request.form.get('username')
        pwd = request.form.get('password')
        if check_creds(user, pwd):
            session.permanent = True  # 开启永久会话 (365天)
            session['logged_in'] = True
            return redirect('/')
        else:
            return render_template_string(LOGIN_PAGE_HTML, error="用户名或密码错误")
    
    # 如果已经登录，直接跳首页
    if session.get('logged_in'):
        return redirect('/')
        
    return render_template_string(LOGIN_PAGE_HTML)

@app.route('/logout')
def logout():
    session.pop('logged_in', None)
    return redirect('/login')

@app.route('/')
@login_required
def index():
    return render_template('index.html')

@app.route('/api/status')
@login_required
def get_status():
    service_active = subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0
    return jsonify({"running": service_active})

@app.route('/api/control', methods=['POST'])
@login_required
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
        'test_notify': f'bash {SCRIPT_DIR}/notify.sh "🔔 通知测试" "恭喜！如果你收到这条消息，说明通知配置正确。"'
    }
    if action in cmds:
        success, msg = run_cmd(cmds[action])
        return jsonify({"success": success, "message": msg})
    return jsonify({"success": False, "message": "未知指令"})

@app.route('/api/config', methods=['GET', 'POST'])
@login_required
def handle_config():
    if request.method == 'GET':
        content = ""
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    content = f.read()
            except: pass
        env = read_env()
        return jsonify({"content": content, "sub_url": env.get('SUB_URL', '')})
    if request.method == 'POST':
        content = request.json.get('content')
        try:
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                f.write(content)
            return jsonify({"success": True, "message": "配置已保存"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)})

@app.route('/api/settings', methods=['GET', 'POST'])
@login_required
def handle_settings():
    if request.method == 'GET':
        env = read_env()
        return jsonify({
            "web_user": env.get('WEB_USER', 'admin'),
            "notify_tg": env.get('NOTIFY_TG') == 'true',
            "tg_token": env.get('TG_BOT_TOKEN', ''),
            "tg_id": env.get('TG_CHAT_ID', ''),
            "notify_api": env.get('NOTIFY_API') == 'true',
            "api_url": env.get('NOTIFY_API_URL', ''),
            "sub_url": env.get('SUB_URL', ''),
            "cron_sub_enabled": env.get('CRON_SUB_ENABLED') == 'true',
            "cron_sub_sched": env.get('CRON_SUB_SCHED', '0 5 * * *'), 
            "cron_geo_enabled": env.get('CRON_GEO_ENABLED') == 'true',
            "cron_geo_sched": env.get('CRON_GEO_SCHED', '0 4 * * *')
        })

    if request.method == 'POST':
        d = request.json
        updates = {
            "NOTIFY_TG": str(is_true(d.get('notify_tg'))).lower(),
            "TG_BOT_TOKEN": d.get('tg_token', ''),
            "TG_CHAT_ID": d.get('tg_id', ''),
            "NOTIFY_API": str(is_true(d.get('notify_api'))).lower(),
            "NOTIFY_API_URL": d.get('api_url', ''),
            "SUB_URL": d.get('sub_url', ''),
            "CRON_SUB_ENABLED": str(is_true(d.get('cron_sub_enabled'))).lower(),
            "CRON_SUB_SCHED": d.get('cron_sub_sched', '0 5 * * *'),
            "CRON_GEO_ENABLED": str(is_true(d.get('cron_geo_enabled'))).lower(),
            "CRON_GEO_SCHED": d.get('cron_geo_sched', '0 4 * * *')
        }
        
        lines = []
        if os.path.exists(ENV_FILE):
            with open(ENV_FILE, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        new_lines = []
        updated_keys = set()
        for line in lines:
            if '=' in line and not line.strip().startswith('#'):
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
        with open(ENV_FILE, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)

        update_cron("# JOB_SUB", updates['CRON_SUB_SCHED'], f"bash {SCRIPT_DIR}/update_subscription.sh >/dev/null 2>&1", updates['CRON_SUB_ENABLED'] == 'true')
        update_cron("# JOB_GEO", updates['CRON_GEO_SCHED'], f"bash {SCRIPT_DIR}/update_geo.sh >/dev/null 2>&1", updates['CRON_GEO_ENABLED'] == 'true')

        return jsonify({"success": True, "message": "配置已保存"})

@app.route('/api/logs')
@login_required
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
