package com.sp3cooperative.sagana

import android.content.Context
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes a human-readable device name to Dart without requiring an external
 * native plugin dependency.
 */
class DeviceInfoChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.sp3cooperative.sagana/device_info")

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceName" -> result.success(resolveDeviceName())
            else -> result.notImplemented()
        }
    }

    private fun resolveDeviceName(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            val userDefined = runCatching {
                Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
            }.getOrNull()?.trim()
            if (!userDefined.isNullOrEmpty()) return userDefined
        }

        val manufacturer = (Build.MANUFACTURER ?: "").trim()
        val model = (Build.MODEL ?: "").trim()
        if (manufacturer.isEmpty() && model.isEmpty()) return "Android device"
        if (manufacturer.isEmpty()) return model
        if (model.isEmpty()) return capitalize(manufacturer)

        val lowerModel = model.lowercase()
        val lowerMaker = manufacturer.lowercase()
        return if (lowerModel.startsWith(lowerMaker)) {
            model
        } else {
            "${capitalize(manufacturer)} $model"
        }
    }

    private fun capitalize(value: String): String {
        if (value.isEmpty()) return value
        return value.replaceFirstChar { ch ->
            if (ch.isLowerCase()) ch.titlecase() else ch.toString()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
