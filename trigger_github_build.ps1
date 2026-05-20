# 触发 GitHub Actions 构建并下载 APK
# 需要 GitHub CLI (gh) 工具

Write-Host "=== 触发 GitHub Actions 自动构建 ===" -ForegroundColor Cyan

# 检查 gh 是否安装
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "安装 GitHub CLI..." -ForegroundColor Yellow
    winget install --id GitHub.cli
}

# 登录 GitHub
Write-Host "`n请确保已登录 GitHub:" -ForegroundColor Yellow
gh auth login

# 触发工作流
Write-Host "`n触发构建工作流..." -ForegroundColor Yellow
gh workflow run flutter-build.yml --repo dg49888safe/rustdesk-20260514

Write-Host "`n✅ 构建已触发！等待 10-15 分钟后，下载 APK:" -ForegroundColor Green
Write-Host "gh run download --repo dg49888safe/rustdesk-20260514" -ForegroundColor Cyan
