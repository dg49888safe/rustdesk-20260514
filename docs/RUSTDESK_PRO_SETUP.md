# RustDesk 官方 PRO 版本搭建指南

## 系统要求

- **操作系统**: Ubuntu 22.04 LTS（推荐）
- **内存**: 最低 2GB，推荐 4GB+
- **存储**: 最低 10GB 可用空间
- **网络**: 公网 IP 或域名
- **域名**: 建议配置域名和 SSL 证书

## 搭建步骤

### 1. 服务器准备

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装必要工具
sudo apt install -y curl wget git docker.io docker-compose nginx certbot python3-certbot-nginx

# 启动 Docker
sudo systemctl start docker
sudo systemctl enable docker

# 添加用户到 docker 组（可选）
sudo usermod -aG docker $USER
```

### 2. 获取 RustDesk PRO

```bash
# 创建工作目录
mkdir -p /opt/rustdesk
cd /opt/rustdesk

# 下载官方 PRO 版本
wget https://github.com/rustdesk/rustdesk-server-pro/releases/latest/download/rustdesk-server-pro.tar.gz

# 解压
tar -xzf rustdesk-server-pro.tar.gz
cd rustdesk-server-pro
```

### 3. 配置环境变量

```bash
# 复制配置文件
cp .env.example .env

# 编辑配置
nano .env
```

配置内容示例：
```bash
# 基础配置
RUSTDESK_ID_SERVER=your-domain.com:21116
RUSTDESK_RELAY_SERVER=your-domain.com:21117

# 数据库配置
DB_URL=postgresql://rustdesk:password@localhost:5432/rustdesk
REDIS_URL=redis://localhost:6379

# 安全配置
SECRET_KEY=your-secret-key-here
API_KEY=your-api-key-here

# 管理员账户
ADMIN_EMAIL=admin@your-domain.com
ADMIN_PASSWORD=your-admin-password

# SSL 证书路径
SSL_CERT_PATH=/etc/letsencrypt/live/your-domain.com/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/your-domain.com/privkey.pem

# 其他配置
MAX_CONNECTIONS=1000
LOG_LEVEL=info
```

### 4. 配置域名和 SSL

```bash
# 配置 Nginx
sudo nano /etc/nginx/sites-available/rustdesk
```

Nginx 配置：
```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # SSL 配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # API 代理
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 管理面板
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
# 启用站点
sudo ln -s /etc/nginx/sites-available/rustdesk /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# 获取 SSL 证书
sudo certbot --nginx -d your-domain.com
```

### 5. 启动数据库

```bash
# 启动 PostgreSQL 和 Redis
docker-compose up -d postgres redis

# 等待数据库启动
sleep 10

# 初始化数据库
docker-compose exec -T postgres psql -U rustdesk -d rustdesk -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
```

### 6. 启动 RustDesk 服务

```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f
```

### 7. 初始化管理员账户

```bash
# 创建管理员账户
docker-compose exec rustdesk-server python manage.py createsuperuser

# 或者使用环境变量预设的管理员账户
```

## 验证安装

### 1. 检查服务状态
```bash
# 检查端口
netstat -tlnp | grep -E "(21116|21117|8080|3000)"

# 检查 Docker 容器
docker-compose ps
```

### 2. 访问管理面板
打开浏览器访问：`https://your-domain.com`

使用管理员账户登录。

### 3. 测试连接
- 配置客户端连接到 `your-domain.com`
- 验证 ID 服务器和 relay 服务器
- 测试远程连接功能

## 常用管理命令

### 服务管理
```bash
# 启动服务
docker-compose up -d

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 查看日志
docker-compose logs -f rustdesk-server

# 更新版本
docker-compose pull
docker-compose up -d
```

### 数据库管理
```bash
# 备份数据库
docker-compose exec postgres pg_dump -U rustdesk rustdesk > backup.sql

# 恢复数据库
docker-compose exec -T postgres psql -U rustdesk rustdesk < backup.sql

# 进入数据库
docker-compose exec postgres psql -U rustdesk rustdesk
```

## 配置文件说明

### docker-compose.yml
```yaml
version: '3.8'

services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: rustdesk
      POSTGRES_USER: rustdesk
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  rustdesk-server:
    image: rustdesk/rustdesk-server-pro:latest
    environment:
      - DB_URL=postgresql://rustdesk:password@postgres:5432/rustdesk
      - REDIS_URL=redis://redis:6379
    ports:
      - "21116:21116"  # ID 服务器
      - "21117:21117"  # Relay 服务器
      - "8080:8080"    # API 服务
    depends_on:
      - postgres
      - redis
    volumes:
      - ./data:/app/data
      - ./.env:/app/.env

  web-panel:
    image: rustdesk/rustdesk-web-pro:latest
    ports:
      - "3000:3000"
    environment:
      - API_URL=http://rustdesk-server:8080
    depends_on:
      - rustdesk-server

volumes:
  postgres_data:
```

## 防火墙配置

```bash
# 开放必要端口
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 21116/tcp   # RustDesk ID 服务器
sudo ufw allow 21117/tcp   # RustDesk Relay 服务器

# 启用防火墙
sudo ufw enable
```

## 监控和维护

### 日志监控
```bash
# 设置日志轮转
sudo nano /etc/logrotate.d/rustdesk
```

```
/opt/rustdesk/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
}
```

### 性能监控
```bash
# 安装监控工具
sudo apt install -y htop iotop

# 监控资源使用
htop
iotop
docker stats
```

### 自动备份
```bash
# 创建备份脚本
sudo nano /usr/local/bin/rustdesk-backup.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/opt/backups/rustdesk"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# 备份数据库
docker-compose exec -T postgres pg_dump -U rustdesk rustdesk > $BACKUP_DIR/db_$DATE.sql

# 备份配置文件
tar -czf $BACKUP_DIR/config_$DATE.tar.gz /opt/rustdesk/.env /opt/rustdesk/docker-compose.yml

# 清理旧备份（保留7天）
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
```

```bash
# 添加到 crontab
sudo crontab -e
```

```
0 2 * * * /usr/local/bin/rustdesk-backup.sh
```

## 故障排除

### 常见问题

1. **服务无法启动**
   ```bash
   # 检查端口占用
   sudo netstat -tlnp | grep -E "(21116|21117|8080|3000)"
   
   # 检查 Docker 日志
   docker-compose logs rustdesk-server
   ```

2. **数据库连接失败**
   ```bash
   # 检查数据库状态
   docker-compose exec postgres pg_isready
   
   # 检查连接
   docker-compose exec rustdesk-server python manage.py dbshell
   ```

3. **SSL 证书问题**
   ```bash
   # 检查证书
   sudo certbot certificates
   
   # 手动续期
   sudo certbot renew
   ```

4. **客户端连接失败**
   ```bash
   # 检查防火墙
   sudo ufw status
   
   # 检查端口开放
   telnet your-domain.com 21116
   telnet your-domain.com 21117
   ```

## 安全建议

1. **定期更新**
   ```bash
   # 更新系统
   sudo apt update && sudo apt upgrade -y
   
   # 更新 Docker 镜像
   docker-compose pull
   docker-compose up -d
   ```

2. **访问控制**
   - 使用强密码
   - 启用 2FA
   - 限制管理面板访问 IP

3. **数据加密**
   - 使用 HTTPS
   - 数据库连接加密
   - 备份文件加密

## 技术支持

- 官方文档: https://rustdesk.com/docs/
- GitHub: https://github.com/rustdesk/rustdesk-server-pro
- 社区: https://github.com/rustdesk/rustdesk/discussions
