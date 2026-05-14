package com.carriez.flutter_hbb

import android.app.Application
import android.util.Log
import ffi.FFI

class MainApplication : Application() {
    companion object {
        private const val TAG = "MainApplication"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "App start")
        FFI.onAppStart(applicationContext)
        val prefs = getSharedPreferences(KEY_SHARED_PREFERENCES, MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_START_ON_BOOT_OPT, true).apply()
    }
}
