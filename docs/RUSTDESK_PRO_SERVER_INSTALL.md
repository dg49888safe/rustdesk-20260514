# RustDesk PRO 服务端安装教程（Ubuntu 22.04）

## 已验证可用 - 2026-05-20

---

## 系统要求

- Ubuntu 22.04 LTS
- 2GB+ 内存
- 公网 IP 或域名
- 宝塔面板（可选，用于反向代理）

---

## 一、安装 Docker 和 Docker Compose

```bash
# 安装 Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker

# 安装 Docker Compose
apt install -y docker-compose

# 验证安装
docker --version
docker-compose --version
```

---

## 二、部署 RustDesk PRO 服务端

```bash
# 创建工作目录
mkdir -p /opt/rustdesk-pro && cd /opt/rustdesk-pro

# 创建 docker-compose.yml（自动获取本机IP）
YOUR_IP=$(curl -s ifconfig.me)
echo "本机IP: $YOUR_IP"

cat > docker-compose.yml << EOF
version: '3.8'
services:
  hbbs:
    image: rustdesk/rustdesk-server-pro:latest
    command: hbbs
    ports:
      - "21114:21114"
      - "21115:21115"
      - "21116:21116"
      - "21116:21116/udp"
    volumes:
      - ./data:/root
    restart: unless-stopped
    depends_on:
      - hbbr

  hbbr:
    image: rustdesk/rustdesk-server-pro:latest
    command: hbbr
    ports:
      - "21117:21117"
    volumes:
      - ./data:/root
    restart: unless-stopped
EOF

# 启动服务
docker-compose up -d

# 等待启动
sleep 10

# 查看状态（hbbs 和 hbbr 都应为 Up）
docker-compose ps
```

---

## 三、开放防火墙端口

```bash
ufw allow 21114/tcp
ufw allow 21115/tcp
ufw allow 21116/tcp
ufw allow 21116/udp
ufw allow 21117/tcp
ufw reload
```

---

## 四、验证服务运行

```bash
# 查看容器状态
docker-compose ps

# 测试 Web 面板端口
curl http://127.0.0.1:21114

# 查看服务密钥（客户端配置需要用到）
cat /opt/rustdesk-pro/data/*.pub
```

成功标志：
- `hbbs` → `Up`
- `hbbr` → `Up`
- `curl http://127.0.0.1:21114` 返回 HTML 内容

---

## 五、宝塔面板反向代理配置

1. 宝塔面板 → **网站** → 添加站点
   - 域名填写你的域名
   
2. 站点设置 → **反向代理** → 添加反向代理
   ```
   代理名称: rustdesk
   目标URL: http://127.0.0.1:21114
   发送域名: 127.0.0.1
   开启代理: ✅
   ```

3. 访问 Web 管理面板：
   ```
   http://你的域名
   ```

---

## 六、登录 Web 管理面板

默认账号：
```
用户名: admin
密码:   test1234
```

> ⚠️ **首次登录后立即修改密码！**

---

## 七、常用管理命令

```bash
# 进入工作目录
cd /opt/rustdesk-pro

# 启动服务
docker-compose up -d

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 查看状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 更新到最新版本
docker-compose pull
docker-compose up -d
```

---

## 八、客户端配置

在 RustDesk 客户端设置：
- **ID 服务器**: `你的服务器域名或IP`
- **Relay 服务器**: `你的服务器域名或IP`
- **Key**: 执行 `cat /opt/rustdesk-pro/data/*.pub` 获取

---

## 九、Android 客户端固定配置

修改 `src/flutter_ffi.rs`：

```rust
config::Config::set_option("custom-rendezvous-server".into(), "你的域名:21116".into());
config::Config::set_option("relay-server".into(), "你的域名:21117".into());
config::Config::set_option("key".into(), "你的公钥".into());
config::Config::set_permanent_password("612345");
```

---

## 十、故障排除

### hbbs 容器 Exit 0
```bash
# 查看日志
docker-compose logs hbbs

# 重启
docker-compose restart hbbs
```

### 21114 端口无法访问
```bash
# 检查端口监听
netstat -tlnp | grep 21114

# 检查防火墙
ufw status
```

### docker-compose 命令找不到
```bash
apt install -y docker-compose
```

### 端口被旧服务占用
```bash
# 查找占用进程
lsof -i :21117

# 停止旧容器
docker ps -a | grep rustdesk
docker rm -f <容器ID>
```

---

## 版本信息

- 安装日期：2026-05-20
- 镜像版本：`rustdesk/rustdesk-server-pro:latest`
- 测试环境：Ubuntu 22.04 LTS + 宝塔面板
- Web 面板端口：21114
- 验证状态：✅ 已验证可用
