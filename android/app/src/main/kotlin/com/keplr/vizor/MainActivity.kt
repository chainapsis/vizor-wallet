package com.keplr.vizor

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: BiometricPrompt requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private lateinit var deviceOwnerAuthHandler: DeviceOwnerAuthHandler
    private var paymentUriChannel: MethodChannel? = null
    private val pendingPaymentUris = mutableListOf<String>()
    private var paymentUriDartReady = false

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
        deviceOwnerAuthHandler = DeviceOwnerAuthHandler(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DeviceOwnerAuthHandler.CHANNEL
        ).setMethodCallHandler { call, result ->
            deviceOwnerAuthHandler.handle(call, result)
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRIVACY_SHIELD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSensitiveContentVisible" -> {
                    val visible = (call.arguments as? Map<*, *>)?.get("visible") as? Boolean
                    if (visible == null) {
                        result.error("bad_args", "Expected visible argument.", null)
                    } else {
                        setSensitiveContentVisible(visible)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        paymentUriChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PAYMENT_URI_CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingUris" -> {
                        val uris = pendingPaymentUris.toList()
                        pendingPaymentUris.clear()
                        result.success(uris)
                    }
                    "ready" -> {
                        paymentUriDartReady = true
                        flushPendingPaymentUris()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // A zcash: link that cold-starts Vizor arrives as the launch intent.
        capturePaymentUri(intent)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (
            ::deviceOwnerAuthHandler.isInitialized &&
            deviceOwnerAuthHandler.onActivityResult(requestCode, resultCode)
        ) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
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

    private fun setSensitiveContentVisible(visible: Boolean) {
        if (visible) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop launchMode: a zcash: link tapped while Vizor is already
        // running is delivered here instead of through a fresh launch intent.
        setIntent(intent)
        capturePaymentUri(intent)
    }

    private fun capturePaymentUri(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        val data = intent.data ?: return
        if (!"zcash".equals(data.scheme, ignoreCase = true)) return
        pendingPaymentUris.add(intent.dataString ?: data.toString())
        flushPendingPaymentUris()
    }

    private fun flushPendingPaymentUris() {
        if (!paymentUriDartReady || pendingPaymentUris.isEmpty()) return
        val channel = paymentUriChannel ?: return
        val uris = pendingPaymentUris.toList()
        pendingPaymentUris.clear()
        channel.invokeMethod("onUris", uris)
    }

    companion object {
        private const val CAMERA_PERMISSION_CHANNEL = "com.zcash.wallet/camera_permission"
        private const val HAPTICS_CHANNEL = "com.zcash.wallet/haptics"
        private const val PRIVACY_SHIELD_CHANNEL = "com.zcash.wallet/privacy_shield"
        private const val PAYMENT_URI_CHANNEL = "com.zcash.wallet/payment_uri"
    }
}
