package com.sp3cooperative.sagana

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.Executors

/** Requests legacy permission only after a Download tap; never starts a share intent. */
class ReportDownloadsChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.sp3cooperative.sagana/downloads")
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingResult: MethodChannel.Result? = null
    private var pendingSource: File? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "saveReport") {
                result.notImplemented()
            } else if (pendingResult != null) {
                result.error("busy", "A download is already in progress.", null)
            } else {
                val path = call.argument<String>("sourcePath")
                if (path.isNullOrBlank()) {
                    result.error("file_missing", "No report file was supplied.", null)
                } else {
                    pendingResult = result
                    pendingSource = File(path)
                    if (Build.VERSION.SDK_INT in 23..28 &&
                        activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        activity.requestPermissions(
                            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), PERMISSION_REQUEST,
                        )
                    } else {
                        save()
                    }
                }
            }
        }
    }

    fun onPermissionResult(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            save()
        } else {
            finishError("permission_denied")
        }
        return true
    }

    private fun save() {
        val source = pendingSource ?: return
        // Streams run off the UI thread, including large multi-page reports.
        executor.execute {
            try {
                val name = ReportDownloadsStore(activity.applicationContext).save(source)
                activity.runOnUiThread {
                    val result = takeResult()
                    result?.success(name)
                }
            } catch (error: Exception) {
                val code = when (error) {
                    is FileNotFoundException -> "file_missing"
                    is SecurityException -> "permission_denied"
                    else -> "save_failed"
                }
                activity.runOnUiThread { finishError(code) }
            }
        }
    }

    private fun takeResult(): MethodChannel.Result? {
        val result = pendingResult
        pendingResult = null
        pendingSource = null
        return result
    }

    private fun finishError(code: String) {
        takeResult()?.error(code, "The report could not be saved to Downloads.", null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        finishError("cancelled")
        executor.shutdown()
    }

    companion object {
        private const val PERMISSION_REQUEST = 47031
    }
}
