package com.sp3cooperative.sagana

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var downloads: ReportDownloadsChannel? = null
    private var deviceInfo: DeviceInfoChannel? = null

    // High-importance channel so phone notifications show on the lock screen and
    // pop up over other apps. Must match PushNotificationService.androidChannelId.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "sagana_notifications",
            "SAGANA notifications",
            NotificationManager.IMPORTANCE_HIGH,
        )
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        downloads = ReportDownloadsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        deviceInfo = DeviceInfoChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (downloads?.onPermissionResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        downloads?.dispose()
        downloads = null
        deviceInfo?.dispose()
        deviceInfo = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
