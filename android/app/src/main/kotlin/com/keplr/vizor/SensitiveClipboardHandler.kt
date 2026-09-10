package com.keplr.vizor

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.SystemClock
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

internal class SensitiveClipboardHandler(private val context: Context) {
    private val clipboardManager =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var copyGeneration = 0L
    private var pendingExpiration: PendingExpiration? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "copyText" -> copyText(call, result)
            else -> result.notImplemented()
        }
    }

    fun retryExpiredClear() {
        val pending = pendingExpiration ?: return
        if (SystemClock.elapsedRealtime() >= pending.expiresAtElapsedRealtime) {
            clearIfExpired(pending.copyGeneration)
        }
    }

    private fun copyText(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val text = arguments?.get("text") as? String
        if (arguments == null || text == null) {
            result.error("bad_args", "Expected text argument.", null)
            return
        }

        val expirationSeconds =
            ((arguments["expirationSeconds"] as? Number)?.toLong() ?: DEFAULT_EXPIRATION_SECONDS)
                .coerceIn(1L, MAX_EXPIRATION_SECONDS)
        val token = UUID.randomUUID().toString()
        val clip = ClipData.newPlainText("", text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(SENSITIVE_CLIPBOARD_KEY, true)
                putString(COPY_TOKEN_KEY, token)
            }
        }
        clipboardManager.setPrimaryClip(clip)

        val generation = ++copyGeneration
        if (arguments["autoClear"] == false) {
            pendingExpiration = null
            result.success(null)
            return
        }
        val expirationMillis = expirationSeconds * 1_000L
        val expiresAt = SystemClock.elapsedRealtime() + expirationMillis
        pendingExpiration = PendingExpiration(
            token = token,
            copyGeneration = generation,
            expiresAtElapsedRealtime = expiresAt
        )
        mainHandler.postDelayed(
            { clearIfExpired(generation) },
            expirationMillis
        )
        result.success(null)
    }

    /**
     * Inspect metadata only: reading the body can show an Android clipboard-access
     * toast for text the user copied in another app. Metadata still requires focus
     * on Android 10+, so denied/null reads retain the token for a foreground retry.
     * MainActivity retries on resume and window focus (resume can precede focus).
     * No plaintext is retained by the expiration callback.
     */
    private fun clearIfExpired(generation: Long) {
        val pending = pendingExpiration ?: return
        if (pending.copyGeneration != generation) return
        if (SystemClock.elapsedRealtime() < pending.expiresAtElapsedRealtime) return
        // Nothing this read returned could be believed, so do not spend the
        // pending entry on it.
        if (!canReadClipboard()) return

        val description = try {
            clipboardManager.primaryClipDescription
        } catch (_: SecurityException) {
            return
        } ?: return // Empty and access-denied cannot be distinguished here.

        if (description.extras?.getString(COPY_TOKEN_KEY) == pending.token) {
            // Focus may have changed during the metadata read. Extras identify a
            // copy, not an authenticated owner; Android offers no atomic
            // compare-and-clear API, so this remains best-effort.
            if (!canReadClipboard()) return
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    clipboardManager.clearPrimaryClip()
                } else {
                    clipboardManager.setPrimaryClip(ClipData.newPlainText("", ""))
                }
            } catch (_: SecurityException) {
                return
            }
        }
        // A different/missing token means the clipboard was replaced. Retire
        // this expiry without touching the replacement, even if its text matches.
        if (pendingExpiration === pending) {
            pendingExpiration = null
        }
    }

    /**
     * Whether a clipboard read can mean anything right now.
     *
     * Android 10+ hands the clipboard only to the app whose window has focus.
     * Checking first keeps a background timer from consuming the pending entry
     * on a read that would come back null whatever the clipboard holds.
     */
    private fun canReadClipboard(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        val activity = context as? Activity ?: return true
        return activity.hasWindowFocus()
    }

    private data class PendingExpiration(
        val token: String,
        val copyGeneration: Long,
        val expiresAtElapsedRealtime: Long
    )

    companion object {
        const val CHANNEL = "com.zcash.wallet/sensitive_clipboard"
        private const val COPY_TOKEN_KEY = "com.keplr.vizor.extra.CLIPBOARD_COPY_TOKEN"
        private const val SENSITIVE_CLIPBOARD_KEY = "android.content.extra.IS_SENSITIVE"
        private const val DEFAULT_EXPIRATION_SECONDS = 60L
        private const val MAX_EXPIRATION_SECONDS = 24L * 60L * 60L
    }
}
