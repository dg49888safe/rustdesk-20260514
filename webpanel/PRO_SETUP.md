# RustDesk PRO 版本搭建指南

## 功能特性

### 基础功能
- ✅ 在线设备实时监控
- ✅ 设备ID显示和管理
- ✅ 真正在线状态检测（基于TCP连接和日志分析）
- ✅ 设备IP地址显示
- ✅ 注册时间和活跃状态统计
- ✅ 搜索和过滤功能
- ✅ 密码保护访问

### PRO 版本增强功能
- ✅ **实时在线设备ID列表** - 显示所有当前在线的设备ID
- ✅ **点击搜索功能** - 点击在线设备ID可直接搜索定位
- ✅ **多种在线检测算法** - TCP连接检测 + Docker日志分析
- ✅ **15秒自动刷新** - 实时更新在线状态
- ✅ **响应式界面** - 支持移动端访问
- ✅ **详细调试信息** - 便于问题排查

## 系统要求

- **操作系统**: Linux (推荐 Ubuntu 20.04+)
- **Python**: 3.8+
- **Docker**: 已安装并运行
- **权限**: sudo 权限（用于网络检测）

## 安装步骤

### 1. 下载代码
```bash
# 克隆仓库
git clone https://github.com/dg49888safe/rustdesk-20260514.git
cd rustdesk-20260514/webpanel

# 或者直接下载 webpanel 目录
wget https://github.com/dg49888safe/rustdesk-20260514/archive/main.zip
unzip main.zip
cd rustdesk-20260514-main/webpanel
```

### 2. 安装依赖
```bash
# 安装 Python 依赖
pip3 install flask

# 确保系统工具可用
sudo apt update
sudo apt install -y net-tools iproute2
```

### 3. 配置环境变量
```bash
# 复制配置模板
cp .env.example .env

# 编辑配置文件
nano .env
```

配置内容：
```bash
# 数据库路径（根据实际部署路径修改）
RUSTDESK_DB=/www/dk_project/dk_app/rustdesk/rustdesk_KNEL/data/db_v2.sqlite3

# 访问密码（建议修改）
PANEL_PASSWORD=admin888

# Docker 容器名称
CONTAINER_NAME=rustdesk_knel-rustdesk_KNEL-1

# HBBS 端口号
HBBS_PORT=21116

# 在线检测时间窗口（秒）
ONLINE_LOG_SECONDS=60

# 活跃天数判断
ACTIVE_DAYS=7

# 服务端口
PORT=5900
```

### 4. 启动服务
```bash
# 方法1: 直接启动
python3 app.py

# 方法2: 使用 systemd 服务（推荐）
sudo cp rustdesk-panel.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable rustdesk-panel
sudo systemctl start rustdesk-panel
```

### 5. 访问面板
打开浏览器访问：`http://你的服务器IP:5900`

默认密码：`admin888`（建议修改）

## 高级配置

### 反向代理配置（Nginx）
```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://127.0.0.1:5900;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### SSL 证书配置
```bash
# 使用 Let's Encrypt
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

### 防火墙配置
```bash
# 开放端口
sudo ufw allow 5900/tcp
sudo ufw reload
```

## API 接口

### 获取设备列表
```bash
curl "http://localhost:5900/api/devices?pwd=你的密码"
```

返回格式：
```json
{
    "total": 10,
    "online_count": 3,
    "offline_count": 7,
    "online_ids": ["123456789", "987654321", "456789123"],
    "server_time": "2026-05-18 17:30:00",
    "devices": [
        {
            "id": "123456789",
            "online": true,
            "last_seen": "2026-05-18 10:15:30",
            "age": "7小时前注册",
            "ip": "192.168.1.100",
            "note": ""
        }
    ]
}
```

### 获取统计信息
```bash
curl "http://localhost:5900/api/stats?pwd=你的密码"
```

### 调试信息
```bash
curl "http://localhost:5900/api/debug?pwd=你的密码"
```

## 故障排除

### 1. 数据库连接失败
- 检查 `RUSTDESK_DB` 路径是否正确
- 确认数据库文件存在且可读
- 检查文件权限

### 2. 在线检测不准确
- 检查 `CONTAINER_NAME` 是否正确
- 确认 Docker 服务正常运行
- 检查 `HBBS_PORT` 端口号

### 3. 无法访问面板
- 检查防火墙设置
- 确认端口未被占用
- 检查服务是否正常启动

### 4. 权限问题
```bash
# 给予执行权限
chmod +x start.sh
chmod +x app.py

# 检查日志
sudo journalctl -u rustdesk-panel -f
```

## 监控和维护

### 日志查看
```bash
# systemd 服务日志
sudo journalctl -u rustdesk-panel -f

# 应用日志
tail -f /var/log/rustdesk-panel.log
```

### 性能优化
- 定期清理旧日志
- 监控内存使用
- 数据库优化

### 备份策略
```bash
# 备份数据库
cp /path/to/db_v2.sqlite3 /backup/db_v2_$(date +%Y%m%d).sqlite3

# 备份配置
cp .env /backup/env_$(date +%Y%m%d)
```

## 安全建议

1. **修改默认密码** - 立即修改 `PANEL_PASSWORD`
2. **使用 HTTPS** - 配置 SSL 证书
3. **限制访问** - 使用防火墙限制访问IP
4. **定期更新** - 保持系统和依赖更新
5. **监控日志** - 定期检查访问日志

## 技术支持

- GitHub Issues: https://github.com/dg49888safe/rustdesk-20260514/issues
- 文档更新: 2026-05-18

## 版本历史

- **v1.0** - 基础设备管理功能
- **v1.1** - 添加在线检测功能
- **v1.2** - PRO版本：实时在线ID显示
- **v1.3** - 多种在线检测算法优化
