#!/bin/bash

# RustDesk PRO Web 端自动安装脚本
# 适用于 Ubuntu 22.04 LTS
# 使用方法: sudo bash install_rustdesk_pro.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo bash $0"
        exit 1
    fi
}

# 获取用户输入
get_user_input() {
    echo -e "${BLUE}=== RustDesk PRO Web 端安装配置 ===${NC}"
    echo
    
    # 域名配置
    read -p "请输入域名 (例如: rustdesk.example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        log_error "域名不能为空"
        exit 1
    fi
    
    # 管理员邮箱
    read -p "请输入管理员邮箱: " ADMIN_EMAIL
    if [[ -z "$ADMIN_EMAIL" ]]; then
        log_error "管理员邮箱不能为空"
        exit 1
    fi
    
    # 管理员密码
    read -s -p "请输入管理员密码: " ADMIN_PASSWORD
    echo
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        log_error "管理员密码不能为空"
        exit 1
    fi
    
    # 数据库密码
    read -s -p "请输入数据库密码 (默认: rustdesk123): " DB_PASSWORD
    echo
    if [[ -z "$DB_PASSWORD" ]]; then
        DB_PASSWORD="rustdesk123"
    fi
    
    # API 密钥
    read -p "请输入 API 密钥 (留空自动生成): " API_KEY
    if [[ -z "$API_KEY" ]]; then
        API_KEY=$(openssl rand -hex 32)
    fi
    
    # 密钥
    read -p "请输入 SECRET_KEY (留空自动生成): " SECRET_KEY
    if [[ -z "$SECRET_KEY" ]]; then
        SECRET_KEY=$(openssl rand -hex 32)
    fi
    
    echo
    log_info "配置信息:"
    echo "  域名: $DOMAIN"
    echo "  管理员邮箱: $ADMIN_EMAIL"
    echo "  数据库密码: $DB_PASSWORD"
    echo "  API 密钥: $API_KEY"
    echo "  SECRET_KEY: $SECRET_KEY"
    echo
    read -p "确认配置? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_error "安装已取消"
        exit 1
    fi
}

# 系统更新
update_system() {
    log_info "更新系统包..."
    apt update && apt upgrade -y
    log_success "系统更新完成"
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."
    
    # 基础工具
    apt install -y curl wget git unzip software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release
    
    # Docker
    if ! command -v docker &> /dev/null; then
        log_info "安装 Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io
        systemctl enable docker
        systemctl start docker
    else
        log_info "Docker 已安装"
    fi
    
    # Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_info "安装 Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        log_info "Docker Compose 已安装"
    fi
    
    # Nginx 和 Certbot
    apt install -y nginx certbot python3-certbot-nginx
    
    # 其他工具
    apt install -y htop iotop net-tools postgresql-client
    
    log_success "依赖安装完成"
}

# 创建工作目录
create_workdir() {
    WORKDIR="/opt/rustdesk"
    log_info "创建工作目录: $WORKDIR"
    mkdir -p $WORKDIR
    cd $WORKDIR
}

# 下载 RustDesk PRO
download_rustdesk() {
    log_info "下载 RustDesk PRO..."
    
    # 获取最新版本
    LATEST_VERSION=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server-pro/releases/latest | grep 'tag_name' | cut -d '"' -f 4)
    if [[ -z "$LATEST_VERSION" ]]; then
        LATEST_VERSION="latest"
    fi
    
    log_info "下载版本: $LATEST_VERSION"
    wget -O rustdesk-server-pro.tar.gz "https://github.com/rustdesk/rustdesk-server-pro/releases/download/$LATEST_VERSION/rustdesk-server-pro.tar.gz"
    
    # 解压
    tar -xzf rustdesk-server-pro.tar.gz
    cd rustdesk-server-pro
    
    log_success "RustDesk PRO 下载完成"
}

# 创建配置文件
create_config() {
    log_info "创建配置文件..."
    
    cat > .env << EOF
# 基础配置
RUSTDESK_ID_SERVER=${DOMAIN}:21116
RUSTDESK_RELAY_SERVER=${DOMAIN}:21117

# 数据库配置
DB_URL=postgresql://rustdesk:${DB_PASSWORD}@postgres:5432/rustdesk
REDIS_URL=redis://redis:6379

# 安全配置
SECRET_KEY=${SECRET_KEY}
API_KEY=${API_KEY}

# 管理员账户
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# SSL 证书路径
SSL_CERT_PATH=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/${DOMAIN}/privkey.pem

# 其他配置
MAX_CONNECTIONS=1000
LOG_LEVEL=info
ENVIRONMENT=production

# Web 面板配置
WEB_PANEL_PORT=3000
API_PORT=8080
EOF

    log_success "配置文件创建完成"
}

# 创建 Docker Compose 文件
create_docker_compose() {
    log_info "创建 Docker Compose 配置..."
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  postgres:
    image: postgres:14
    container_name: rustdesk-postgres
    environment:
      POSTGRES_DB: rustdesk
      POSTGRES_USER: rustdesk
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped
    networks:
      - rustdesk-network

  redis:
    image: redis:7-alpine
    container_name: rustdesk-redis
    ports:
      - "6379:6379"
    restart: unless-stopped
    networks:
      - rustdesk-network

  rustdesk-server:
    image: rustdesk/rustdesk-server-pro:latest
    container_name: rustdesk-server
    environment:
      - DB_URL=postgresql://rustdesk:${DB_PASSWORD}@postgres:5432/rustdesk
      - REDIS_URL=redis://redis:6379
      - SECRET_KEY=${SECRET_KEY}
      - API_KEY=${API_KEY}
      - ADMIN_EMAIL=${ADMIN_EMAIL}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
      - MAX_CONNECTIONS=1000
      - LOG_LEVEL=info
      - ENVIRONMENT=production
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
    restart: unless-stopped
    networks:
      - rustdesk-network

  web-panel:
    image: rustdesk/rustdesk-web-pro:latest
    container_name: rustdesk-web
    environment:
      - API_URL=http://rustdesk-server:8080
      - API_KEY=${API_KEY}
    ports:
      - "3000:3000"
    depends_on:
      - rustdesk-server
    restart: unless-stopped
    networks:
      - rustdesk-network

volumes:
  postgres_data:

networks:
  rustdesk-network:
    driver: bridge
EOF

    log_success "Docker Compose 配置创建完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    # 检查 ufw 状态
    if command -v ufw &> /dev/null; then
        # 允许 SSH
        ufw allow ssh
        
        # 允许 HTTP/HTTPS
        ufw allow 80/tcp
        ufw allow 443/tcp
        
        # 允许 RustDesk 端口
        ufw allow 21116/tcp
        ufw allow 21117/tcp
        
        # 启用防火墙
        ufw --force enable
        
        log_success "防火墙配置完成"
    else
        log_warning "UFW 未安装，跳过防火墙配置"
    fi
}

# 获取 SSL 证书
get_ssl_certificate() {
    log_info "获取 SSL 证书..."
    
    # 配置 Nginx (临时配置用于 certbot)
    cat > /etc/nginx/sites-available/rustdesk-temp << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location / {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
EOF
    
    # 启用临时站点
    ln -sf /etc/nginx/sites-available/rustdesk-temp /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试 Nginx 配置
    nginx -t
    systemctl reload nginx
    
    # 获取证书
    certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email ${ADMIN_EMAIL} --redirect
    
    # 删除临时配置
    rm -f /etc/nginx/sites-available/rustdesk-temp
    
    log_success "SSL 证书获取完成"
}

# 配置 Nginx
configure_nginx() {
    log_info "配置 Nginx..."
    
    cat > /etc/nginx/sites-available/rustdesk << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    # SSL 配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # API 代理
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 管理面板
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    # 启用站点
    ln -sf /etc/nginx/sites-available/rustdesk /etc/nginx/sites-enabled/
    
    # 测试配置
    nginx -t
    systemctl reload nginx
    
    log_success "Nginx 配置完成"
}

# 启动服务
start_services() {
    log_info "启动 RustDesk 服务..."
    
    # 创建数据目录
    mkdir -p data
    
    # 启动数据库
    docker-compose up -d postgres redis
    
    # 等待数据库启动
    log_info "等待数据库启动..."
    sleep 15
    
    # 检查数据库连接
    while ! docker-compose exec -T postgres pg_isready -U rustdesk; do
        log_info "等待 PostgreSQL 启动..."
        sleep 5
    done
    
    # 初始化数据库
    docker-compose exec -T postgres psql -U rustdesk -d rustdesk -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";" || true
    
    # 启动所有服务
    docker-compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 检查服务状态
    if docker-compose ps | grep -q "Up"; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败"
        docker-compose logs
        exit 1
    fi
}

# 创建管理脚本
create_management_scripts() {
    log_info "创建管理脚本..."
    
    # 启动脚本
    cat > /usr/local/bin/rustdesk-start << 'EOF'
#!/bin/bash
cd /opt/rustdesk/rustdesk-server-pro
docker-compose up -d
echo "RustDesk 服务已启动"
EOF
    
    # 停止脚本
    cat > /usr/local/bin/rustdesk-stop << 'EOF'
#!/bin/bash
cd /opt/rustdesk/rustdesk-server-pro
docker-compose down
echo "RustDesk 服务已停止"
EOF
    
    # 重启脚本
    cat > /usr/local/bin/rustdesk-restart << 'EOF'
#!/bin/bash
cd /opt/rustdesk/rustdesk-server-pro
docker-compose restart
echo "RustDesk 服务已重启"
EOF
    
    # 状态脚本
    cat > /usr/local/bin/rustdesk-status << 'EOF'
#!/bin/bash
cd /opt/rustdesk/rustdesk-server-pro
docker-compose ps
EOF
    
    # 日志脚本
    cat > /usr/local/bin/rustdesk-logs << 'EOF'
#!/bin/bash
cd /opt/rustdesk/rustdesk-server-pro
docker-compose logs -f
EOF
    
    # 设置执行权限
    chmod +x /usr/local/bin/rustdesk-*
    
    log_success "管理脚本创建完成"
}

# 创建备份脚本
create_backup_script() {
    log_info "创建备份脚本..."
    
    cat > /usr/local/bin/rustdesk-backup << EOF
#!/bin/bash

BACKUP_DIR="/opt/backups/rustdesk"
DATE=\$(date +%Y%m%d_%H%M%S)

mkdir -p \$BACKUP_DIR

# 备份数据库
cd /opt/rustdesk/rustdesk-server-pro
docker-compose exec -T postgres pg_dump -U rustdesk rustdesk > \$BACKUP_DIR/db_\$DATE.sql

# 备份配置文件
tar -czf \$BACKUP_DIR/config_\$DATE.tar.gz .env docker-compose.yml

# 清理旧备份（保留7天）
find \$BACKUP_DIR -name "*.sql" -mtime +7 -delete
find \$BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "备份完成: \$DATE"
EOF
    
    chmod +x /usr/local/bin/rustdesk-backup
    
    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/rustdesk-backup") | crontab -
    
    log_success "备份脚本创建完成"
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查端口
    if netstat -tlnp | grep -q ":21116\|:21117\|:8080\|:3000"; then
        log_success "端口检查通过"
    else
        log_warning "部分端口未监听"
    fi
    
    # 检查服务
    if docker-compose ps | grep -q "Up"; then
        log_success "服务状态正常"
    else
        log_error "服务状态异常"
        docker-compose ps
    fi
    
    # 检查 SSL 证书
    if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        log_success "SSL 证书正常"
    else
        log_warning "SSL 证书可能有问题"
    fi
}

# 显示安装结果
show_result() {
    echo
    echo -e "${GREEN}=== RustDesk PRO Web 端安装完成 ===${NC}"
    echo
    echo -e "${BLUE}访问信息:${NC}"
    echo "  Web 管理面板: https://$DOMAIN"
    echo "  管理员邮箱: $ADMIN_EMAIL"
    echo "  管理员密码: $ADMIN_PASSWORD"
    echo
    echo -e "${BLUE}服务配置:${NC}"
    echo "  ID 服务器: $DOMAIN:21116"
    echo "  Relay 服务器: $DOMAIN:21117"
    echo "  API 服务: $DOMAIN:8080"
    echo
    echo -e "${BLUE}管理命令:${NC}"
    echo "  启动服务: rustdesk-start"
    echo "  停止服务: rustdesk-stop"
    echo "  重启服务: rustdesk-restart"
    echo "  查看状态: rustdesk-status"
    echo "  查看日志: rustdesk-logs"
    echo "  备份数据: rustdesk-backup"
    echo
    echo -e "${BLUE}工作目录:${NC}"
    echo "  /opt/rustdesk/rustdesk-server-pro"
    echo
    echo -e "${BLUE}注意事项:${NC}"
    echo "  1. 请确保域名已正确解析到此服务器"
    echo "  2. 防火墙已开放必要端口"
    echo "  3. SSL 证书已自动配置"
    echo "  4. 数据库已初始化"
    echo "  5. 备份任务已设置 (每天凌晨2点)"
    echo
    echo -e "${GREEN}安装成功！请访问 https://$DOMAIN 开始使用${NC}"
}

# 主函数
main() {
    log_info "开始安装 RustDesk PRO Web 端..."
    
    check_root
    get_user_input
    update_system
    install_dependencies
    create_workdir
    download_rustdesk
    create_config
    create_docker_compose
    configure_firewall
    get_ssl_certificate
    configure_nginx
    start_services
    create_management_scripts
    create_backup_script
    verify_installation
    show_result
    
    log_success "安装完成！"
}

# 运行主函数
main "$@"
