# RustDesk 在线设备管理面板

轻量 Web 面板，实时显示 RustDesk 服务器上的在线设备 ID。

## 部署步骤（VPS 服务器上操作）

### 第一步：上传文件到服务器

将 `app.py`、`requirements.txt`、`start.sh` 上传到服务器任意目录，例如：
```
/www/dk_project/dk_app/rustdesk/webpanel/
```

### 第二步：修改密码（可选）

编辑 `start.sh`，修改这行：
```bash
PANEL_PASSWORD="admin888"   # ← 改成你的密码
```

### 第三步：运行启动脚本

```bash
cd /www/dk_project/dk_app/rustdesk/webpanel/
bash start.sh
```

### 第四步：宝塔配置反向代理

1. 宝塔 → **网站** → 选择你的域名 → **反向代理** → 添加
2. 填写：
   - 代理名称：`rustdesk-panel`
   - 目标 URL：`http://127.0.0.1:5900`
3. 保存

### 第五步：访问面板

浏览器打开：`https://你的域名/rdpanel/?pwd=admin888`

---

## 界面功能

- 实时显示所有设备 ID 及在线/离线状态
- 总设备数 / 在线数 / 离线数统计
- 搜索设备 ID
- 按在线/离线过滤
- 点击图标一键复制设备 ID
- 每 15 秒自动刷新
- 密码保护

## 数据库路径

默认读取：`/www/dk_project/dk_app/rustdesk/rustdesk_KNEL/data/db_v2.sqlite3`

如需修改，设置环境变量：
```bash
export RUSTDESK_DB="/你的路径/db_v2.sqlite3"
```
