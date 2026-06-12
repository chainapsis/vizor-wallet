package com.keplr.vizor

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: BiometricPrompt requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HAPTICS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "error" -> result.success(performErrorHaptic())
                else -> result.notImplemented()
            }
        }

        val biometricUnlockHandler = BiometricUnlockHandler(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BiometricUnlockHandler.CHANNEL
        ).setMethodCallHandler { call, result ->
            biometricUnlockHandler.handle(call, result)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAMERA_PERMISSION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSettings" -> result.success(openAppSettings())
                else -> result.notImplemented()
            }
        }
    }

    /** REJECT is the platform's error haptic; older APIs report
     *  unhandled so Dart falls back to its own pattern. */
    private fun performErrorHaptic(): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) {
            return false
        }
        return window.decorView.performHapticFeedback(
            android.view.HapticFeedbackConstants.REJECT
        )
    }

    private fun openAppSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        private const val CAMERA_PERMISSION_CHANNEL = "com.zcash.wallet/camera_permission"
        private const val HAPTICS_CHANNEL = "com.zcash.wallet/haptics"
    }
}
