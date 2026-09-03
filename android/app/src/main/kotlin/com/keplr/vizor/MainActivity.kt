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
    private lateinit var sensitiveClipboardHandler: SensitiveClipboardHandler
    private var incomingUriChannel: MethodChannel? = null
    private val pendingIncomingUris = mutableListOf<String>()
    private var incomingUriDartReady = false
    private val consumedIncomingUris = ArrayList<String>()

    /**
     * The link this activity record was created with, kept outside
     * [consumedIncomingUris] so the bound can never evict it.
     *
     * A task restore recreates the activity from its creating intent, so the
     * cold-start link is exactly the one most likely to be replayed — and, once
     * the user has opened enough later links, it is also the oldest entry in an
     * LRU that evicts from the front. Pinning it separately keeps the bound for
     * the onNewIntent links, which are re-deliverable by design.
     */
    private var launchIncomingUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Restored before super.onCreate: on a recreated activity super
        // re-attaches the Flutter fragment, which already runs
        // configureFlutterEngine and the capture guard below.
        consumedIncomingUris.clear()
        savedInstanceState?.getStringArrayList(KEY_CONSUMED_INCOMING_URIS)?.let {
            consumedIncomingUris.addAll(it)
        }
        launchIncomingUri = savedInstanceState?.getString(KEY_LAUNCH_INCOMING_URI)
        // Links captured but not yet handed to Dart when the activity was
        // saved. A link is recorded as consumed at capture, so without this the
        // restore would recognise the creating intent as already delivered and
        // skip it, while the in-memory queue that still held it is gone —
        // a cold-start link opened just before the app was backgrounded would
        // simply disappear.
        pendingIncomingUris.clear()
        savedInstanceState?.getStringArrayList(KEY_PENDING_INCOMING_URIS)?.let {
            pendingIncomingUris.addAll(it)
        }
        super.onCreate(savedInstanceState)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        // Survives process death, so the recreated activity knows which of the
        // task's VIEW intents were already delivered.
        outState.putStringArrayList(KEY_CONSUMED_INCOMING_URIS, ArrayList(consumedIncomingUris))
        outState.putString(KEY_LAUNCH_INCOMING_URI, launchIncomingUri)
        // Undelivered links travel with the consumed record they were already
        // added to, so restoring one cannot lose the other.
        outState.putStringArrayList(KEY_PENDING_INCOMING_URIS, ArrayList(pendingIncomingUris))
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
        sensitiveClipboardHandler = SensitiveClipboardHandler(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SensitiveClipboardHandler.CHANNEL
        ).setMethodCallHandler { call, result ->
            sensitiveClipboardHandler.handle(call, result)
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

        incomingUriChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INCOMING_URI_CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingUris" -> {
                        val uris = pendingIncomingUris.toList()
                        pendingIncomingUris.clear()
                        result.success(uris)
                    }
                    "ready" -> {
                        incomingUriDartReady = true
                        flushPendingIncomingUris()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // A link that cold-starts Vizor arrives as the launch intent. Restoring
        // the task after the process was killed recreates the activity with a
        // VIEW intent (NEW_TASK only, no LAUNCHED_FROM_HISTORY), which replayed
        // the link. Saved state keeps every consumed URI, not just the last one,
        // because after cold-starting on link A and receiving link B through
        // onNewIntent the restore may hand back either A or B, and both were
        // already delivered. The launch link is checked against its own pinned
        // field as well, because the bounded set can evict it.
        val incomingLaunchUri = intent?.dataString
        if (incomingLaunchUri == null ||
            (incomingLaunchUri != launchIncomingUri &&
                !consumedIncomingUris.contains(incomingLaunchUri))
        ) {
            captureIncomingUri(intent, isLaunchIntent = true)
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

    override fun onResume() {
        super.onResume()
        if (::sensitiveClipboardHandler.isInitialized) {
            sensitiveClipboardHandler.retryExpiredClear()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop launchMode: a link tapped while Vizor is already running is
        // delivered here instead of through a fresh launch intent.
        setIntent(intent)
        // No consumed-URI check here: tapping the same link again is a
        // deliberate user action and must be delivered again. captureIncomingUri
        // still records the URI into the consumed set; setIntent() only rewrites
        // this process's copy, so a restore after process death may hand back
        // either this intent or the one that created the activity record.
        captureIncomingUri(intent)
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

    /**
     * Whether [data] is a link this app takes in: a ZIP-321 `zcash:` payment
     * link, or a verified HTTPS link on the deeplink host with no userinfo and
     * no explicit port. One predicate for both kinds, so the two intent-filters
     * in the manifest and this capture never disagree about what is accepted.
     */
    private fun acceptsIncomingUri(data: Uri): Boolean {
        val scheme = data.scheme ?: return false
        if ("zcash".equals(scheme, ignoreCase = true)) return true
        return "https".equals(scheme, ignoreCase = true) &&
            DEEPLINK_HOST.equals(data.host, ignoreCase = true) &&
            data.userInfo == null &&
            data.port == -1
    }

    private fun captureIncomingUri(intent: Intent?, isLaunchIntent: Boolean = false) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val data = intent.data ?: return
        if (!acceptsIncomingUri(data)) return
        val rawUri = intent.dataString ?: data.toString()
        if (rawUri.length > MAX_INCOMING_URI_BYTES) return
        if (rawUri.toByteArray(Charsets.UTF_8).size > MAX_INCOMING_URI_BYTES) return
        if (rawUri in pendingIncomingUris) return
        if (pendingIncomingUris.size >= MAX_PENDING_INCOMING_URIS) return
        // Recorded only once the link is actually queued: a link the caps
        // refused was never delivered, so a restore must stay free to replay
        // it. The creating intent is what a restore hands back, so it is
        // pinned rather than added to the set the bound trims.
        if (isLaunchIntent) {
            launchIncomingUri = rawUri
        } else {
            rememberConsumedIncomingUri(rawUri)
        }
        pendingIncomingUris.add(rawUri)
        flushPendingIncomingUris()
    }

    /**
     * Newest last, deduped, bounded so a long-lived task's saved state stays
     * small. Only onNewIntent links live here; the launch link is pinned in
     * [launchIncomingUri], because it is the oldest entry and the one a restore
     * replays, so trimming from the front would drop exactly the wrong one.
     */
    private fun rememberConsumedIncomingUri(uri: String) {
        consumedIncomingUris.remove(uri)
        consumedIncomingUris.add(uri)
        while (consumedIncomingUris.size > MAX_CONSUMED_INCOMING_URIS) {
            consumedIncomingUris.removeAt(0)
        }
    }

    private fun flushPendingIncomingUris() {
        if (!incomingUriDartReady || pendingIncomingUris.isEmpty()) return
        val channel = incomingUriChannel ?: return
        val uris = pendingIncomingUris.toList()
        pendingIncomingUris.clear()
        channel.invokeMethod("onUris", uris)
    }

    companion object {
        private const val CAMERA_PERMISSION_CHANNEL = "com.zcash.wallet/camera_permission"
        private const val HAPTICS_CHANNEL = "com.zcash.wallet/haptics"
        private const val PRIVACY_SHIELD_CHANNEL = "com.zcash.wallet/privacy_shield"
        private const val SCREEN_AWAKE_CHANNEL = "com.zcash.wallet/screen_awake"
        private const val INCOMING_URI_CHANNEL = "com.zcash.wallet/payment_uri"
        private val DEEPLINK_HOST = BuildConfig.VIZOR_DEEPLINK_HOST
        private const val MAX_INCOMING_URI_BYTES = 16 * 1024
        private const val MAX_PENDING_INCOMING_URIS = 16
        private const val KEY_CONSUMED_INCOMING_URIS = "vizor.consumedIncomingUris"
        private const val KEY_LAUNCH_INCOMING_URI = "vizor.launchIncomingUri"
        private const val KEY_PENDING_INCOMING_URIS = "vizor.pendingIncomingUris"
        private const val MAX_CONSUMED_INCOMING_URIS = 8
    }
}
