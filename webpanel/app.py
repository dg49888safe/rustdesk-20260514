#!/usr/bin/env python3
"""
RustDesk 在线设备管理面板
数据目录: /www/dk_project/dk_app/rustdesk/rustdesk_KNEL/data/
"""

import sqlite3
import os
import time
import subprocess
import json
from datetime import datetime
from flask import Flask, jsonify, render_template_string, request
from functools import wraps

app = Flask(__name__)


@app.errorhandler(Exception)
def handle_exception(e):
    import traceback
    return jsonify({"error": str(e), "trace": traceback.format_exc()}), 500

# ── 配置 ──────────────────────────────────────────────
DB_PATH = os.environ.get(
    "RUSTDESK_DB",
    "/www/dk_project/dk_app/rustdesk/rustdesk_KNEL/data/db_v2.sqlite3"
)
PANEL_PASSWORD    = os.environ.get("PANEL_PASSWORD", "admin888")
CONTAINER_NAME    = os.environ.get("CONTAINER_NAME", "rustdesk_knel-rustdesk_KNEL-1")
HBBS_PORT         = int(os.environ.get("HBBS_PORT", "21116"))


def get_table_name(conn):
    """自动检测表名 peer 或 peers"""
    tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    if "peer" in tables:
        return "peer"
    if "peers" in tables:
        return "peers"
    return None


def get_columns(conn, table):
    """获取表的所有列名"""
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})").fetchall()]


def get_online_ips():
    """
    在宿主机直接用 ss/netstat 查询 hbbs 端口的已建立连接。
    hbbs 映射到宿主机端口 HBBS_PORT（默认21116），
    连接中的远端 IP 即为在线设备 IP。
    """
    ips = set()
    # 方案1: ss（Ubuntu 18+）
    for cmd in (
        ["ss", "-tn", "state", "established"],
        ["netstat", "-tn"],
    ):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if result.returncode != 0:
                continue
            for line in result.stdout.splitlines():
                if f":{HBBS_PORT}" not in line:
                    continue
                parts = line.split()
                for part in parts:
                    # 格式: 1.2.3.4:PORT 或 ::ffff:1.2.3.4:PORT
                    if ":" not in part:
                        continue
                    host = part.rsplit(":", 1)[0]
                    if host.startswith("::ffff:"):
                        host = host[7:]
                    host = host.strip("[]")
                    if host and "." in host:
                        segs = host.split(".")
                        if len(segs) == 4 and all(s.isdigit() for s in segs):
                            # 排除本机地址
                            if not host.startswith("127.") and host != "0.0.0.0":
                                ips.add(host)
            if ips:
                break
        except Exception:
            continue

    # 方案2: 读取 /proc/net/tcp 和 tcp6（内核级，无需工具）
    if not ips:
        ips = _get_ips_from_proc()

    return ips


def _get_ips_from_proc():
    """从 /proc/net/tcp6 读取已建立连接，解析在线IP"""
    ips = set()
    port_hex = format(HBBS_PORT, "04X")
    for path in ("/proc/net/tcp6", "/proc/net/tcp"):
        try:
            with open(path) as f:
                for line in f.readlines()[1:]:
                    parts = line.split()
                    if len(parts) < 4:
                        continue
                    # state 01 = ESTABLISHED
                    if parts[3] != "01":
                        continue
                    local = parts[1]
                    remote = parts[2]
                    local_port = local.split(":")[1] if ":" in local else ""
                    if local_port.upper() != port_hex:
                        continue
                    # 解析远端 IP（小端序 hex）
                    remote_hex = remote.split(":")[0]
                    if len(remote_hex) == 8:
                        # IPv4
                        b = bytes.fromhex(remote_hex)
                        ip = f"{b[3]}.{b[2]}.{b[1]}.{b[0]}"
                    elif len(remote_hex) == 32:
                        # IPv4-mapped IPv6: 后8位是IPv4
                        b = bytes.fromhex(remote_hex[24:32])
                        ip = f"{b[3]}.{b[2]}.{b[1]}.{b[0]}"
                    else:
                        continue
                    if not ip.startswith("127.") and ip != "0.0.0.0":
                        ips.add(ip)
        except Exception:
            continue
    return ips


def extract_ip(info_str):
    """从 info JSON 提取设备 IP"""
    if not info_str:
        return ""
    try:
        if isinstance(info_str, bytes):
            info_str = info_str.decode("utf-8", errors="ignore")
        d = json.loads(info_str)
        ip = d.get("ip", "")
        if ip.startswith("::ffff:"):
            ip = ip[7:]
        return ip
    except Exception:
        return ""


def safe_val(v):
    """将数据库值转为 JSON 安全类型"""
    if isinstance(v, bytes):
        try:
            return v.decode("utf-8", errors="ignore")
        except Exception:
            return ""
    if v is None:
        return ""
    return v
# ─────────────────────────────────────────────────────


def check_auth(password):
    return password == PANEL_PASSWORD


def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        pwd = request.args.get("pwd") or request.cookies.get("pwd")
        if not check_auth(pwd):
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated


def get_db():
    if not os.path.exists(DB_PATH):
        return None
    conn = sqlite3.connect(DB_PATH, timeout=5)
    conn.row_factory = sqlite3.Row
    return conn


@app.route("/")
def index():
    pwd = request.args.get("pwd", "")
    return render_template_string(HTML_TEMPLATE, panel_password=pwd)


@app.route("/api/devices")
@requires_auth
def api_devices():
    conn = get_db()
    if conn is None:
        return jsonify({"error": f"数据库不存在: {DB_PATH}", "devices": []})

    now_ts = int(time.time())
    online_cutoff = now_ts - ONLINE_TIMEOUT

    table = get_table_name(conn)
    if not table:
        conn.close()
        return jsonify({"error": "找不到 peer/peers 表", "devices": []})

    cols = get_columns(conn, table)
    has_info    = "info" in cols
    has_note    = "note" in cols
    has_created = "created_at" in cols

    try:
        order_col = "created_at" if has_created else "id"
        cur = conn.execute(f"SELECT * FROM {table} ORDER BY {order_col} DESC")
        rows = cur.fetchall()
    except Exception as e:
        conn.close()
        return jsonify({"error": str(e), "devices": []})

    conn.close()

    # 获取当前活跃连接IP（判断在线）
    online_ips = get_online_ips()

    devices = []
    online_count = 0

    for row in rows:
        row_dict = dict(row)
        dev_ip = extract_ip(row_dict.get("info", "")) if has_info else ""
        is_online = bool(dev_ip and dev_ip in online_ips)
        if is_online:
            online_count += 1

        last_seen = str(row_dict.get("created_at", "未知") or "未知")

        devices.append({
            "id":        safe_val(row_dict.get("id", "")),
            "online":    is_online,
            "last_seen": last_seen,
            "ip":        dev_ip,
            "note":      safe_val(row_dict.get("note", "")),
        })

    return jsonify({
        "total":        len(devices),
        "online_count": online_count,
        "offline_count": len(devices) - online_count,
        "server_time":  datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "devices":      devices,
    })


@app.route("/api/debug")
@requires_auth
def api_debug():
    """调试接口：查看数据库原始数据"""
    conn = get_db()
    if conn is None:
        return jsonify({"error": f"DB not found: {DB_PATH}"})
    tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    table = get_table_name(conn)
    raw = []
    cols = []
    if table:
        cols = get_columns(conn, table)
        rows = conn.execute(f"SELECT * FROM {table} LIMIT 5").fetchall()
        for r in rows:
            raw.append({k: safe_val(v) for k, v in dict(r).items()})
    conn.close()
    online_ips = get_online_ips()

    # 额外诊断：列出宿主机所有 ESTABLISHED 连接（前30条）
    diag_lines = []
    try:
        r = subprocess.run(["ss", "-tn", "state", "established"],
                           capture_output=True, text=True, timeout=5)
        diag_lines = r.stdout.splitlines()[:30]
    except Exception:
        pass

    # docker port 映射
    port_map = []
    try:
        for docker_bin in ("/usr/bin/docker", "/usr/local/bin/docker"):
            if os.path.exists(docker_bin):
                r = subprocess.run([docker_bin, "port", CONTAINER_NAME],
                                   capture_output=True, text=True, timeout=5)
                port_map = r.stdout.splitlines()
                break
    except Exception:
        pass

    return jsonify({"db_path": DB_PATH, "tables": tables, "columns": cols,
                    "sample": raw, "server_now": int(time.time()),
                    "container": CONTAINER_NAME, "hbbs_port": HBBS_PORT,
                    "online_ips_detected": list(online_ips),
                    "docker_port_map": port_map,
                    "ss_established_sample": diag_lines})


@app.route("/api/stats")
@requires_auth
def api_stats():
    conn = get_db()
    if conn is None:
        return jsonify({"error": "db not found"})
    now_ts = int(time.time())
    online_cutoff = now_ts - ONLINE_TIMEOUT
    table = get_table_name(conn)
    if not table:
        conn.close()
        return jsonify({"error": "找不到表"})
    try:
        total = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        online_ips = get_online_ips()
        cols = get_columns(conn, table)
        if "info" in cols and online_ips:
            rows = conn.execute(f"SELECT info FROM {table}").fetchall()
            online = sum(1 for r in rows if extract_ip(r[0]) in online_ips)
        else:
            online = len(online_ips)  # 粗略估算
    except Exception as e:
        conn.close()
        return jsonify({"error": str(e)})
    conn.close()
    return jsonify({"total": total, "online": online, "offline": total - online})


# ── HTML 模板 ──────────────────────────────────────────
HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RustDesk 在线设备管理</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #0f1117; color: #e0e0e0; }
  .header { background: linear-gradient(135deg, #1a1d2e, #252840); padding: 20px 30px;
            border-bottom: 1px solid #2d3050; display: flex; align-items: center; gap: 15px; }
  .header h1 { font-size: 22px; color: #7eb8f7; }
  .header .dot { width: 10px; height: 10px; border-radius: 50%; background: #4caf50;
                 box-shadow: 0 0 8px #4caf50; animation: pulse 2s infinite; }
  @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.4} }
  .stats { display: flex; gap: 15px; padding: 20px 30px; flex-wrap: wrap; }
  .stat-card { background: #1a1d2e; border: 1px solid #2d3050; border-radius: 10px;
               padding: 15px 25px; min-width: 150px; text-align: center; }
  .stat-card .num { font-size: 32px; font-weight: bold; }
  .stat-card .label { font-size: 13px; color: #888; margin-top: 4px; }
  .online-num { color: #4caf50; }
  .offline-num { color: #f44336; }
  .total-num { color: #7eb8f7; }
  .toolbar { padding: 0 30px 15px; display: flex; gap: 10px; align-items: center; }
  .toolbar input { background: #1a1d2e; border: 1px solid #2d3050; color: #e0e0e0;
                   padding: 8px 14px; border-radius: 6px; width: 250px; font-size: 14px; }
  .toolbar button { background: #3a4080; border: none; color: #fff; padding: 8px 18px;
                    border-radius: 6px; cursor: pointer; font-size: 14px; }
  .toolbar button:hover { background: #4a52a0; }
  .filter-btn { padding: 6px 14px; border-radius: 6px; border: 1px solid #2d3050;
                background: transparent; color: #888; cursor: pointer; font-size: 13px; }
  .filter-btn.active { background: #3a4080; color: #fff; border-color: #3a4080; }
  .table-wrap { padding: 0 30px 30px; overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  thead tr { background: #1a1d2e; }
  th { padding: 12px 15px; text-align: left; color: #888; font-weight: 500;
       border-bottom: 1px solid #2d3050; }
  td { padding: 11px 15px; border-bottom: 1px solid #1e2130; }
  tr:hover td { background: #1a1d2e; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; }
  .badge-online  { background: #1b3a1b; color: #4caf50; border: 1px solid #2d6b2d; }
  .badge-offline { background: #3a1b1b; color: #f44336; border: 1px solid #6b2d2d; }
  .device-id { font-family: monospace; font-size: 15px; color: #7eb8f7; font-weight: 600; }
  .uuid-text { font-family: monospace; font-size: 11px; color: #555; }
  .refresh-info { font-size: 12px; color: #555; margin-left: auto; }
  .login-overlay { position: fixed; inset: 0; background: #0f1117;
                   display: flex; align-items: center; justify-content: center; z-index: 999; }
  .login-box { background: #1a1d2e; border: 1px solid #2d3050; border-radius: 12px;
               padding: 40px; width: 320px; text-align: center; }
  .login-box h2 { color: #7eb8f7; margin-bottom: 20px; }
  .login-box input { width: 100%; background: #0f1117; border: 1px solid #2d3050; color: #e0e0e0;
                     padding: 10px 14px; border-radius: 6px; font-size: 15px; margin-bottom: 15px; }
  .login-box button { width: 100%; background: #3a4080; border: none; color: #fff;
                      padding: 11px; border-radius: 6px; font-size: 15px; cursor: pointer; }
  .login-box button:hover { background: #4a52a0; }
  .empty { text-align: center; padding: 40px; color: #555; }
  .copy-btn { background: none; border: none; color: #555; cursor: pointer; font-size: 13px; margin-left: 6px; }
  .copy-btn:hover { color: #7eb8f7; }
</style>
</head>
<body>

<div class="login-overlay" id="loginOverlay">
  <div class="login-box">
    <h2>🖥 RustDesk 管理面板</h2>
    <p style="color:#666;margin-bottom:20px;font-size:13px">请输入访问密码</p>
    <input type="password" id="loginPwd" placeholder="访问密码" onkeydown="if(event.key==='Enter')doLogin()">
    <button onclick="doLogin()">进入</button>
    <p id="loginErr" style="color:#f44336;margin-top:12px;font-size:13px"></p>
  </div>
</div>

<div id="mainPanel" style="display:none">
  <div class="header">
    <div class="dot"></div>
    <h1>RustDesk 在线设备管理</h1>
    <span class="refresh-info" id="lastRefresh">正在加载...</span>
  </div>

  <div class="stats">
    <div class="stat-card"><div class="num total-num" id="statTotal">-</div><div class="label">总设备数</div></div>
    <div class="stat-card"><div class="num online-num" id="statOnline">-</div><div class="label">当前在线</div></div>
    <div class="stat-card"><div class="num offline-num" id="statOffline">-</div><div class="label">离线设备</div></div>
  </div>

  <div class="toolbar">
    <input type="text" id="searchBox" placeholder="搜索设备ID..." oninput="renderTable()">
    <button class="filter-btn active" id="btnAll" onclick="setFilter('all')">全部</button>
    <button class="filter-btn" id="btnOnline" onclick="setFilter('online')">仅在线</button>
    <button class="filter-btn" id="btnOffline" onclick="setFilter('offline')">仅离线</button>
    <button onclick="loadData()" style="margin-left:auto">刷新</button>
  </div>

  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>#</th>
          <th>设备 ID</th>
          <th>状态</th>
          <th>设备 IP</th>
          <th>注册时间</th>
          <th>备注</th>
        </tr>
      </thead>
      <tbody id="tableBody"></tbody>
    </table>
    <div id="emptyTip" class="empty" style="display:none">暂无数据</div>
  </div>
</div>

<script>
let allDevices = [];
let currentFilter = 'all';
let currentPwd = '{{ panel_password }}';

function doLogin() {
  const pwd = document.getElementById('loginPwd').value || currentPwd;
  if (!pwd) { document.getElementById('loginErr').textContent = '请输入密码'; return; }
  currentPwd = pwd;
  fetch('/api/stats?pwd=' + encodeURIComponent(pwd))
    .then(r => {
      if (r.status === 401) throw new Error('密码错误');
      return r.json();
    })
    .then(() => {
      document.getElementById('loginOverlay').style.display = 'none';
      document.getElementById('mainPanel').style.display = 'block';
      loadData();
      setInterval(loadData, 15000);
    })
    .catch(e => { document.getElementById('loginErr').textContent = e.message; });
}

function loadData() {
  fetch('/api/devices?pwd=' + encodeURIComponent(currentPwd))
    .then(r => r.json())
    .then(data => {
      if (data.error && data.error === 'unauthorized') return;
      allDevices = data.devices || [];
      document.getElementById('statTotal').textContent   = data.total || 0;
      document.getElementById('statOnline').textContent  = data.online_count || 0;
      document.getElementById('statOffline').textContent = data.offline_count || 0;
      document.getElementById('lastRefresh').textContent = '最后刷新: ' + (data.server_time || '');
      renderTable();
    });
}

function setFilter(f) {
  currentFilter = f;
  ['btnAll','btnOnline','btnOffline'].forEach(id => document.getElementById(id).classList.remove('active'));
  document.getElementById('btn' + f.charAt(0).toUpperCase() + f.slice(1)).classList.add('active');
  renderTable();
}

function renderTable() {
  const search = document.getElementById('searchBox').value.toLowerCase();
  let list = allDevices.filter(d => {
    if (currentFilter === 'online'  && !d.online) return false;
    if (currentFilter === 'offline' &&  d.online) return false;
    if (search && !d.id.toLowerCase().includes(search)) return false;
    return true;
  });

  const tbody = document.getElementById('tableBody');
  const empty = document.getElementById('emptyTip');
  if (list.length === 0) {
    tbody.innerHTML = '';
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';

  tbody.innerHTML = list.map((d, i) => `
    <tr>
      <td style="color:#555">${i+1}</td>
      <td>
        <span class="device-id">${escHtml(d.id)}</span>
        <button class="copy-btn" onclick="copyText('${escHtml(d.id)}')" title="复制ID">📋</button>
      </td>
      <td><span class="badge ${d.online ? 'badge-online' : 'badge-offline'}">${d.online ? '● 在线' : '○ 离线'}</span></td>
      <td style="font-family:monospace;font-size:13px;color:#aaa">${escHtml(d.ip||'')}</td>
      <td>${escHtml(d.last_seen)}</td>
      <td style="color:#666">${escHtml(d.note)}</td>
    </tr>
  `).join('');
}

function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}
function copyText(t) {
  navigator.clipboard.writeText(t).then(() => alert('已复制: ' + t));
}

// 如果 URL 带了 pwd 参数，直接自动登录
if (currentPwd) {
  document.getElementById('loginPwd').value = currentPwd;
  doLogin();
}
</script>
</body>
</html>"""

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5900))
    print(f"RustDesk 管理面板启动: http://0.0.0.0:{port}")
    print(f"数据库路径: {DB_PATH}")
    print(f"访问密码: {PANEL_PASSWORD}")
    app.run(host="0.0.0.0", port=port, debug=False)
