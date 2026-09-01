package com.keplr.vizor

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.HapticFeedbackConstants
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
    private var consumedPaymentUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Restored before super.onCreate: on a recreated activity super
        // re-attaches the Flutter fragment, which already runs
        // configureFlutterEngine and the capture guard below.
        consumedPaymentUri = savedInstanceState?.getString(KEY_CONSUMED_PAYMENT_URI)
        super.onCreate(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // Survives process death, so the recreated activity knows the task's
        // stored VIEW intent was already delivered.
        outState.putString(KEY_CONSUMED_PAYMENT_URI, consumedPaymentUri)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HAPTICS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "error" -> result.success(performErrorHaptic())
                "sendSuccess" -> result.success(performSendSuccessHaptic())
                "sendFailure" -> result.success(performSendFailureHaptic())
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_AWAKE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
                    if (enabled == null) {
                        result.error("bad_args", "Expected enabled argument.", null)
                    } else {
                        setScreenAwakeEnabled(enabled)
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
        // Restoring the task after the process was killed recreates the activity
        // with that same VIEW intent (NEW_TASK only, no LAUNCHED_FROM_HISTORY),
        // which replayed the link; saved state says it was already delivered.
        val restoredPaymentUri = consumedPaymentUri
        if (restoredPaymentUri == null || restoredPaymentUri != intent?.dataString) {
            capturePaymentUri(intent)
        }
    }

    /** REJECT is the platform's error haptic; older APIs report
     *  unhandled so Dart falls back to its own pattern. */
    private fun performErrorHaptic(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        return window.decorView.performHapticFeedback(
            HapticFeedbackConstants.REJECT
        )
    }

    private fun performSendSuccessHaptic(): Boolean {
        val feedbackConstant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.CONFIRM
        } else {
            HapticFeedbackConstants.VIRTUAL_KEY
        }
        return window.decorView.performHapticFeedback(feedbackConstant)
    }

    private fun performSendFailureHaptic(): Boolean {
        val feedbackConstant = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.REJECT
        } else {
            HapticFeedbackConstants.LONG_PRESS
        }
        return window.decorView.performHapticFeedback(feedbackConstant)
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

    private fun setScreenAwakeEnabled(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop launchMode: a zcash: link tapped while Vizor is already
        // running is delivered here instead of through a fresh launch intent.
        setIntent(intent)
        // No consumed-URI check here: tapping the same link again is a
        // deliberate user action and must be delivered again. capturePaymentUri
        // still refreshes the fingerprint to the link consumed last; setIntent()
        // only rewrites this process's copy, so a restore after process death is
        // assumed to hand back the intent that created the activity record.
        capturePaymentUri(intent)
    }

    private fun capturePaymentUri(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val data = intent.data ?: return
        if (!"zcash".equals(data.scheme, ignoreCase = true)) return
        consumedPaymentUri = intent.dataString
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
        private const val SCREEN_AWAKE_CHANNEL = "com.zcash.wallet/screen_awake"
        private const val PAYMENT_URI_CHANNEL = "com.zcash.wallet/payment_uri"
        private const val KEY_CONSUMED_PAYMENT_URI = "vizor.consumedPaymentUri"
    }
}
