#!/bin/bash
# RustDesk 在线设备管理面板启动脚本
# 放到服务器上运行: bash start.sh

set -e

PANEL_DIR="/www/dk_project/dk_app/rustdesk/webpanel"
DB_PATH="/www/dk_project/dk_app/rustdesk/rustdesk_KNEL/data/db_v2.sqlite3"
CONTAINER_NAME="rustdesk_knel-rustdesk_KNEL-1"
PORT=5900
PANEL_PASSWORD="admin888"   # ← 改成你想要的密码

echo "=== RustDesk 管理面板安装/启动 ==="

# 1. 安装 Python3 和 pip（如果没有）
if ! command -v python3 &>/dev/null; then
    apt-get update -qq && apt-get install -y python3 python3-pip
fi
if ! command -v pip3 &>/dev/null; then
    apt-get install -y python3-pip
fi

# 2. 创建目录，复制文件
mkdir -p "$PANEL_DIR"
cp app.py "$PANEL_DIR/"
cp requirements.txt "$PANEL_DIR/"

# 3. 安装依赖
pip3 install -q flask 2>/dev/null || pip3 install flask --break-system-packages -q

# 4. 停止旧进程
pkill -f "python3.*app.py" 2>/dev/null || true
sleep 1

# 5. 后台启动
export RUSTDESK_DB="$DB_PATH"
export PANEL_PASSWORD="$PANEL_PASSWORD"
export PORT="$PORT"

nohup python3 "$PANEL_DIR/app.py" > "$PANEL_DIR/panel.log" 2>&1 &
echo $! > "$PANEL_DIR/panel.pid"

sleep 2
if kill -0 $(cat "$PANEL_DIR/panel.pid") 2>/dev/null; then
    echo "✅ 面板启动成功！"
    echo "   本地访问: http://127.0.0.1:$PORT/?pwd=$PANEL_PASSWORD"
    echo "   日志文件: $PANEL_DIR/panel.log"
    echo ""
    echo "=== 宝塔反代配置 ==="
    echo "在宝塔 → 网站 → 添加站点（或现有站点）→ 反向代理"
    echo "  代理名称: rustdesk-panel"
    echo "  目标URL:  http://127.0.0.1:$PORT"
    echo "  然后访问: https://你的域名/?pwd=$PANEL_PASSWORD"
else
    echo "❌ 启动失败，查看日志:"
    cat "$PANEL_DIR/panel.log"
fi
