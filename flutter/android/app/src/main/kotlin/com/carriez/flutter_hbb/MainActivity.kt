package com.carriez.flutter_hbb

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
import android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
import android.media.MediaCodecList
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import ffi.FFI
import org.json.JSONArray
import org.json.JSONObject
import kotlin.concurrent.thread

class MainActivity : Activity() {
    companion object {
        var flutterMethodChannel: Any? = null
        private var _rdClipboardManager: RdClipboardManager? = null
        val rdClipboardManager: RdClipboardManager?
            get() = _rdClipboardManager
    }

    private val logTag = "mMainActivity"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(logTag, "onCreate")
        if (_rdClipboardManager == null) {
            _rdClipboardManager = RdClipboardManager(getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
            FFI.setClipboardManager(_rdClipboardManager!!)
        }
        thread {
            try {
                setCodecInfo()
            } catch (e: Exception) {
                Log.e(logTag, "Failed to setCodecInfo: ${e.message}", e)
            }
        }

        // 序列化权限请求
        requestPermissionsSequentially()

        if (!MainService.isReady) {
            val intent = Intent(this, PermissionRequestTransparentActivity::class.java).apply {
                action = ACT_REQUEST_MEDIA_PROJECTION
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"))
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
        }
    }

    private fun requestBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"))
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                try {
                    startActivity(intent)
                } catch (e: Exception) {
                    Log.e(logTag, "Failed to request battery optimization: ${e.message}")
                }
            }
        }
    }

    private fun requestAccessibilityPermission() {
        try {
            // 先显示一个Toast提示
            android.widget.Toast.makeText(this, 
                "请开启无障碍服务：设置 → 无障碍 → 找到 'RustDesk Input' → 开启", 
                android.widget.Toast.LENGTH_LONG).show()
            
            // 延迟1秒后打开设置页面
            Handler(Looper.getMainLooper()).postDelayed({
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
                
                // 再延迟2秒显示第二个提示
                Handler(Looper.getMainLooper()).postDelayed({
                    android.widget.Toast.makeText(this, 
                        "在列表中找到 'RustDesk Input'，点击开启权限", 
                        android.widget.Toast.LENGTH_LONG).show()
                }, 2000)
            }, 1000)
        } catch (e: Exception) {
            Log.e(logTag, "Failed to request accessibility permission: ${e.message}")
        }
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                android.widget.Toast.makeText(this, 
                    "请开启文件管理权限：找到此应用 → 权限 → 存储 → 允许所有文件", 
                    android.widget.Toast.LENGTH_LONG).show()
                    
                Handler(Looper.getMainLooper()).postDelayed({
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    intent.data = Uri.parse("package:$packageName")
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                }, 1000)
            } catch (e: Exception) {
                Log.e(logTag, "Failed to request storage permission: ${e.message}")
            }
        }
    }

    private fun requestSmsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                android.widget.Toast.makeText(this, 
                    "请开启短信权限：找到此应用 → 权限 → 短信 → 允许", 
                    android.widget.Toast.LENGTH_LONG).show()
                    
                Handler(Looper.getMainLooper()).postDelayed({
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    intent.data = Uri.parse("package:$packageName")
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                }, 1000)
            } catch (e: Exception) {
                Log.e(logTag, "Failed to request SMS permission: ${e.message}")
            }
        }
    }

    private fun requestPermissionsSequentially() {
        Handler(Looper.getMainLooper()).postDelayed({
            if (!checkOverlayPermission()) {
                requestOverlayPermission()
                return@postDelayed
            }
            
            Handler(Looper.getMainLooper()).postDelayed({
                if (!checkBatteryOptimization()) {
                    requestBatteryOptimization()
                    return@postDelayed
                }
                
                Handler(Looper.getMainLooper()).postDelayed({
                    if (!checkAccessibilityPermission()) {
                        requestAccessibilityPermission()
                        return@postDelayed
                    }
                    
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (!checkStoragePermission()) {
                            requestStoragePermission()
                            return@postDelayed
                        }
                        
                        Handler(Looper.getMainLooper()).postDelayed({
                            if (!checkSmsPermission()) {
                                requestSmsPermission()
                            }
                        }, 1000)
                    }, 1000)
                }, 1000)
            }, 1000)
        }, 1000)
    }
    
    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else true
    }
    
    private fun checkBatteryOptimization(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } else true
    }
    
    private fun checkAccessibilityPermission(): Boolean {
        val serviceId = "$packageName/com.carriez.flutter_hbb.InputService"
        val settingsString = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        Log.d(logTag, "Checking accessibility service: $serviceId")
        Log.d(logTag, "Enabled services: $settingsString")
        val enabled = settingsString?.contains(serviceId) == true
        Log.d(logTag, "Accessibility enabled: $enabled")
        return enabled
    }
    
    private fun checkStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            true // MANAGE_EXTERNAL_STORAGE 需要在设置中手动开启，无法通过API检查
        } else true
    }
    
    private fun checkSmsPermission(): Boolean {
        return true // SMS 权限需要在设置中手动开启，无法通过API检查
    }

    private fun setCodecInfo() {
        val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        val codecs = codecList.codecInfos
        val codecArray = JSONArray()

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val wh = getScreenSize(windowManager)
        var w = wh.first
        var h = wh.second
        val align = 64
        w = (w + align - 1) / align * align
        h = (h + align - 1) / align * align
        codecs.forEach { codec ->
            val codecObject = JSONObject()
            codecObject.put("name", codec.name)
            codecObject.put("is_encoder", codec.isEncoder)
            var hw: Boolean? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                hw = codec.isHardwareAccelerated
            } else {
                if (listOf("OMX.google.", "OMX.SEC.", "c2.android").any { codec.name.startsWith(it, true) }) {
                    hw = false
                } else if (listOf("c2.qti", "OMX.qcom.video", "OMX.Exynos", "OMX.hisi", "OMX.MTK", "OMX.Intel", "OMX.Nvidia").any { codec.name.startsWith(it, true) }) {
                    hw = true
                }
            }
            if (hw != true) {
                return@forEach
            }
            codecObject.put("hw", hw)
            var mime_type = ""
            codec.supportedTypes.forEach { type ->
                if (listOf("video/avc", "video/hevc").contains(type)) {
                    mime_type = type
                }
            }
            if (mime_type.isNotEmpty()) {
                codecObject.put("mime_type", mime_type)
                val caps = codec.getCapabilitiesForType(mime_type)
                if (codec.isEncoder) {
                    if (!caps.videoCapabilities.isSizeSupported(w, h) && !caps.videoCapabilities.isSizeSupported(h, w)) {
                        return@forEach
                    }
                }
                codecObject.put("min_width", caps.videoCapabilities.supportedWidths.lower)
                codecObject.put("max_width", caps.videoCapabilities.supportedWidths.upper)
                codecObject.put("min_height", caps.videoCapabilities.supportedHeights.lower)
                codecObject.put("max_height", caps.videoCapabilities.supportedHeights.upper)
                val surface = caps.colorFormats.contains(COLOR_FormatSurface)
                codecObject.put("surface", surface)
                val nv12 = caps.colorFormats.contains(COLOR_FormatYUV420SemiPlanar)
                codecObject.put("nv12", nv12)
                if (!(nv12 || surface)) {
                    return@forEach
                }
                codecObject.put("min_bitrate", caps.videoCapabilities.bitrateRange.lower / 1000)
                codecObject.put("max_bitrate", caps.videoCapabilities.bitrateRange.upper / 1000)
                if (!codec.isEncoder) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        codecObject.put("low_latency", caps.isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency))
                    }
                    return@forEach
                }
                codecArray.put(codecObject)
            }
        }
        val result = JSONObject()
        result.put("version", Build.VERSION.SDK_INT)
        result.put("w", w)
        result.put("h", h)
        result.put("codecs", codecArray)
        FFI.setCodecInfo(result.toString())
    }
}
