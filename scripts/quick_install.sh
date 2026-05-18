#!/bin/bash

# RustDesk PRO 快速安装脚本
# Ubuntu 22.04 LTS
# 使用方法: sudo bash quick_install.sh your-domain.com admin@example.com

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# 参数检查
if [[ $# -lt 2 ]]; then
    echo "使用方法: sudo bash $0 <域名> <管理员邮箱>"
    echo "示例: sudo bash $0 rustdesk.example.com admin@example.com"
    exit 1
fi

DOMAIN="$1"
ADMIN_EMAIL="$2"
DB_PASSWORD="rustdesk123"
ADMIN_PASSWORD="admin123"
API_KEY=$(openssl rand -hex 16)
SECRET_KEY=$(openssl rand -hex 16)

echo -e "${BLUE}=== RustDesk PRO 快速安装 ===${NC}"
echo "域名: $DOMAIN"
echo "管理员邮箱: $ADMIN_EMAIL"
echo

# 更新系统
echo "更新系统..."
apt update && apt upgrade -y

# 安装 Docker
if ! command -v docker &> /dev/null; then
    echo "安装 Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# 安装 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# 安装 Nginx 和 Certbot
echo "安装 Nginx 和 Certbot..."
apt install -y nginx certbot python3-certbot-nginx

# 创建工作目录
mkdir -p /opt/rustdesk
cd /opt/rustdesk

# 下载 RustDesk PRO
echo "下载 RustDesk PRO..."
wget -O rustdesk-server-pro.tar.gz "https://github.com/rustdesk/rustdesk-server-pro/releases/latest/download/rustdesk-server-pro.tar.gz"
tar -xzf rustdesk-server-pro.tar.gz
cd rustdesk-server-pro

# 创建配置文件
echo "创建配置文件..."
cat > .env << EOF
RUSTDESK_ID_SERVER=${DOMAIN}:21116
RUSTDESK_RELAY_SERVER=${DOMAIN}:21117
DB_URL=postgresql://rustdesk:${DB_PASSWORD}@postgres:5432/rustdesk
REDIS_URL=redis://redis:6379
SECRET_KEY=${SECRET_KEY}
API_KEY=${API_KEY}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
SSL_CERT_PATH=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
MAX_CONNECTIONS=1000
LOG_LEVEL=info
EOF

# 创建 Docker Compose 文件
echo "创建 Docker Compose 配置..."
cat > docker-compose.yml << EOF
version: '3.8'

services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: rustdesk
      POSTGRES_USER: rustdesk
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    restart: unless-stopped

  rustdesk-server:
    image: rustdesk/rustdesk-server-pro:latest
    environment:
      - DB_URL=postgresql://rustdesk:${DB_PASSWORD}@postgres:5432/rustdesk
      - REDIS_URL=redis://redis:6379
      - SECRET_KEY=${SECRET_KEY}
      - API_KEY=${API_KEY}
      - ADMIN_EMAIL=${ADMIN_EMAIL}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
    ports:
      - "21116:21116"
      - "21117:21117"
      - "8080:8080"
    depends_on:
      - postgres
      - redis
    restart: unless-stopped

  web-panel:
    image: rustdesk/rustdesk-web-pro:latest
    environment:
      - API_URL=http://rustdesk-server:8080
      - API_KEY=${API_KEY}
    ports:
      - "3000:3000"
    depends_on:
      - rustdesk-server
    restart: unless-stopped

volumes:
  postgres_data:
EOF

# 配置防火墙
echo "配置防火墙..."
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 21116/tcp
ufw allow 21117/tcp
ufw --force enable

# 获取 SSL 证书
echo "获取 SSL 证书..."
systemctl start nginx
certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email ${ADMIN_EMAIL} --redirect

# 配置 Nginx
echo "配置 Nginx..."
cat > /etc/nginx/sites-available/rustdesk << EOF
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}
EOF

ln -sf /etc/nginx/sites-available/rustdesk /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# 启动服务
echo "启动服务..."
mkdir -p data
docker-compose up -d

# 等待服务启动
echo "等待服务启动..."
sleep 30

# 创建管理脚本
echo "创建管理脚本..."
cat > /usr/local/bin/rustdesk << 'EOF'
#!/bin/bash
cd /opt/rustdesk/rustdesk-server-pro
case "$1" in
    start) docker-compose up -d ;;
    stop) docker-compose down ;;
    restart) docker-compose restart ;;
    status) docker-compose ps ;;
    logs) docker-compose logs -f ;;
    *) echo "用法: rustdesk {start|stop|restart|status|logs}" ;;
esac
EOF
chmod +x /usr/local/bin/rustdesk

# 显示结果
echo
echo -e "${GREEN}=== 安装完成 ===${NC}"
echo "Web 管理面板: https://$DOMAIN"
echo "管理员邮箱: $ADMIN_EMAIL"
echo "管理员密码: $ADMIN_PASSWORD"
echo "ID 服务器: $DOMAIN:21116"
echo "Relay 服务器: $DOMAIN:21117"
echo
echo "管理命令:"
echo "  rustdesk start   # 启动服务"
echo "  rustdesk stop    # 停止服务"
echo "  rustdesk restart # 重启服务"
echo "  rustdesk status  # 查看状态"
echo "  rustdesk logs    # 查看日志"
echo
echo -e "${GREEN}安装成功！请访问 https://$DOMAIN${NC}"
