from flask import Flask, render_template, request, jsonify, Response, redirect, session
from functools import wraps
from datetime import timedelta
import subprocess
import os

app = Flask(__name__)

# === 配置 Session ===
# 生产环境建议修改此密钥
app.secret_key = "mihomo-manager-secret-key-permanent"
app.permanent_session_lifetime = timedelta(days=365)

# === 全局路径定义 ===
MIHOMO_DIR = "/etc/mihomo"
SCRIPT_DIR = "/etc/mihomo/scripts"
ENV_FILE = f"{MIHOMO_DIR}/.env"
CONFIG_FILE = f"{MIHOMO_DIR}/config.yaml"
LOG_FILE = "/var/log/mihomo.log"

# === 工具函数 ===

def run_cmd(cmd):
    """执行 Shell 命令并返回结果"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout + result.stderr
    except Exception as e:
        return False, str(e)

def read_env():
    """读取 .env 文件配置"""
    env_data = {}
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        parts = line.split('=', 1)
                        if len(parts) == 2:
                            # 去除引号和空格
                            env_data[parts[0].strip()] = parts[1].strip().strip('"').strip("'")
        except:
            pass
    return env_data

def update_cron(job_id, schedule, command, enabled):
    """管理 Crontab 定时任务"""
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
    """辅助判断布尔值"""
    return str(val).lower() == 'true'

def check_creds(username, password):
    """验证用户名密码"""
    file_env = read_env()
    # 优先读取环境变量，其次读取文件，默认 admin
    valid_user = os.environ.get('WEB_USER') or file_env.get('WEB_USER', 'admin')
    valid_pass = os.environ.get('WEB_SECRET') or file_env.get('WEB_SECRET', 'admin')
    return username == valid_user and password == valid_pass

# === 鉴权装饰器 ===
def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            if request.path.startswith('/api'):
                return jsonify({"error": "Unauthorized"}), 401
            return redirect('/login')
        return f(*args, **kwargs)
    return decorated

# === 路由定义 ===

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        user = request.form.get('username')
        pwd = request.form.get('password')
        if check_creds(user, pwd):
            session.permanent = True
            session['logged_in'] = True
            return redirect('/')
        else:
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
    if not session.get('logged_in'):
        return render_template('login.html')
    return render_template('index.html')

@app.route('/api/status')
@login_required
def get_status():
    # 检查 mihomo 内核服务状态
    service_active = subprocess.run("systemctl is-active mihomo", shell=True).returncode == 0
    return jsonify({"running": service_active})

@app.route('/api/control', methods=['POST'])
@login_required
def control_service():
    action = request.json.get('action')
    # 指令映射
    cmds = {
        'start': 'systemctl start mihomo',
        'stop': 'systemctl stop mihomo',
        'restart': 'systemctl restart mihomo',
        'update_geo': f'bash {SCRIPT_DIR}/update_geo.sh',
        'update_sub': f'bash {SCRIPT_DIR}/update_subscription.sh',
        'net_init': f'bash {SCRIPT_DIR}/gateway_init.sh',
        'fix_logs': 'systemctl restart mihomo', # 实际上重启服务即可刷新日志
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
            # 保存配置后通常不需要重启，除非修改了监听端口等核心配置
            # 但为了生效订阅更改，通常用户会手动点击重启
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
            
            # 双模式相关
            "config_mode": env.get('CONFIG_MODE', 'expert'),
            "sub_url_expert": env.get('SUB_URL_EXPERT', ''),
            "sub_url_template": env.get('SUB_URL_TEMPLATE', ''),
            
            "local_cidr": env.get('LOCAL_CIDR', ''),
            "cron_sub_enabled": env.get('CRON_SUB_ENABLED') == 'true',
            "cron_sub_sched": env.get('CRON_SUB_SCHED', '0 5 * * *'), 
            "cron_geo_enabled": env.get('CRON_GEO_ENABLED') == 'true',
            "cron_geo_sched": env.get('CRON_GEO_SCHED', '0 4 * * *')
        })

    if request.method == 'POST':
        d = request.json
        
        # 处理双模式逻辑
        mode = d.get('config_mode', 'expert')
        url_expert = d.get('sub_url_expert', '')
        url_template = d.get('sub_url_template', '')
        
        # 决定生效的 SUB_URL
        active_url = url_expert if mode == 'expert' else url_template

        updates = {
            "NOTIFY_TG": str(is_true(d.get('notify_tg'))).lower(),
            "TG_BOT_TOKEN": d.get('tg_token', ''),
            "TG_CHAT_ID": d.get('tg_id', ''),
            "NOTIFY_API": str(is_true(d.get('notify_api'))).lower(),
            "NOTIFY_API_URL": d.get('api_url', ''),
            
            "CONFIG_MODE": mode,
            "SUB_URL_EXPERT": url_expert,
            "SUB_URL_TEMPLATE": url_template,
            "SUB_URL": active_url,  # 这里的更新对 backend 脚本至关重要
            
            "LOCAL_CIDR": d.get('local_cidr', ''),
            "CRON_SUB_ENABLED": str(is_true(d.get('cron_sub_enabled'))).lower(),
            "CRON_SUB_SCHED": d.get('cron_sub_sched', '0 5 * * *'),
            "CRON_GEO_ENABLED": str(is_true(d.get('cron_geo_enabled'))).lower(),
            "CRON_GEO_SCHED": d.get('cron_geo_sched', '0 4 * * *')
        }
        
        # 更新 .env 文件 (只更新变动或新增的 key)
        lines = []
        if os.path.exists(ENV_FILE):
            with open(ENV_FILE, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        
        new_lines = []
        updated_keys = set()
        
        for line in lines:
            line_stripped = line.strip()
            if '=' in line_stripped and not line_stripped.startswith('#'):
                key = line_stripped.split('=')[0].strip()
                if key in updates:
                    new_lines.append(f'{key}="{updates[key]}"\n')
                    updated_keys.add(key)
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)
        
        # 追加新 key
        for k, v in updates.items():
            if k not in updated_keys:
                new_lines.append(f'{k}="{v}"\n')
        
        with open(ENV_FILE, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)

        # 更新 Crontab
        update_cron("# JOB_SUB", updates['CRON_SUB_SCHED'], f"bash {SCRIPT_DIR}/update_subscription.sh >/dev/null 2>&1", updates['CRON_SUB_ENABLED'] == 'true')
        update_cron("# JOB_GEO", updates['CRON_GEO_SCHED'], f"bash {SCRIPT_DIR}/update_geo.sh >/dev/null 2>&1", updates['CRON_GEO_ENABLED'] == 'true')

        return jsonify({"success": True, "message": "配置已保存"})

@app.route('/api/logs')
@login_required
def get_logs():
    if not os.path.exists(LOG_FILE):
        return jsonify({"logs": "⚠️ 日志文件尚未生成，请确保 Mihomo 内核已启动..."})
    try:
        # 读取最后 100 行
        success, logs = run_cmd(f"tail -n 100 {LOG_FILE}")
        return jsonify({"logs": logs if logs else "日志为空"})
    except:
        return jsonify({"logs": "读取失败"})

if __name__ == '__main__':
    # 动态读取端口配置，默认为 7838
    env = read_env()
    try:
        port = int(env.get('WEB_PORT', 7838))
    except ValueError:
        port = 7838
    
    # 启动 Flask
    app.run(host='0.0.0.0', port=port)
