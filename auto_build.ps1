# RustDesk Android APK 全自动构建脚本
# 使用方法: PowerShell -ExecutionPolicy Bypass -File auto_build.ps1

$ErrorActionPreference = "Stop"
Write-Host "=== RustDesk Android APK 自动构建脚本 ===" -ForegroundColor Cyan

# 1. 检查环境
Write-Host "`n[1/6] 检查环境..." -ForegroundColor Yellow
$flutterVersion = & flutter --version 2>&1 | Select-Object -First 1
Write-Host "Flutter: $flutterVersion"

# 2. 清理
Write-Host "`n[2/6] 清理旧构建..." -ForegroundColor Yellow
flutter clean
if (Test-Path "android/app/build") { Remove-Item "android/app/build" -Recurse -Force }

# 3. 获取依赖
Write-Host "`n[3/6] 获取 Flutter 依赖..." -ForegroundColor Yellow
flutter pub get

# 4. 生成 Bridge（如果需要）
if (-not (Test-Path "lib/generated_bridge.dart")) {
    Write-Host "`n[4/6] 生成 FFI Bridge..." -ForegroundColor Yellow
    cargo install flutter_rust_bridge_codegen --version 1.80.1 --force
    flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./lib/generated_bridge.dart
} else {
    Write-Host "`n[4/6] Bridge 已存在，跳过生成" -ForegroundColor Green
}

# 5. 构建 APK（使用 Debug 签名避免配置问题）
Write-Host "`n[5/6] 构建 APK（Debug 模式，避免签名问题）..." -ForegroundColor Yellow
flutter build apk --debug --no-shrink

# 6. 检查结果
Write-Host "`n[6/6] 检查结果..." -ForegroundColor Yellow
$apkPath = "build/app/outputs/flutter-apk/app-debug.apk"
if (Test-Path $apkPath) {
    $apk = Get-ChildItem $apkPath
    Write-Host "`n✅ APK 构建成功!" -ForegroundColor Green
    Write-Host "文件名: $($apk.Name)"
    Write-Host "大小: $([math]::Round($apk.Length/1MB, 2)) MB"
    Write-Host "路径: $($apk.FullName)"
    Write-Host "`n安装到手机:" -ForegroundColor Cyan
    Write-Host "adb install `"$($apk.FullName)`""
} else {
    Write-Host "`n❌ APK 未找到，构建可能失败" -ForegroundColor Red
    exit 1
}
