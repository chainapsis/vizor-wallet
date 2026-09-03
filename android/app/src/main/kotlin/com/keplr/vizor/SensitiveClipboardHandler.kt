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
        val clip = ClipData.newPlainText("", text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(SENSITIVE_CLIPBOARD_KEY, true)
            }
        }
        clipboardManager.setPrimaryClip(clip)

        val generation = ++copyGeneration
        val expirationMillis = expirationSeconds * 1_000L
        val expiresAt = SystemClock.elapsedRealtime() + expirationMillis
        pendingExpiration = PendingExpiration(
            text = text,
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
     * Retires the pending expiry, but only on evidence that the secret is gone.
     *
     * A clipboard read cannot always be trusted. From Android 10 the system
     * serves `getPrimaryClip()` only to the app that owns the focused window,
     * and it refuses by returning **null rather than throwing**. A null read
     * therefore cannot tell "the clipboard is empty" apart from "we are not
     * allowed to look", and the second reading means the secret is still on the
     * system clipboard where every installed app can read it.
     *
     * So the pending entry, and the plaintext it carries, is kept whenever the
     * answer is unknown -- no window focus, `SecurityException`, null clip --
     * and released only on proof that the secret is gone: a readable clip
     * holding something else, or one this method has just cleared. Keeping a
     * secret in this process a while longer is the cheap mistake; leaving it on
     * the system clipboard with nothing scheduled to remove it is not
     * recoverable.
     *
     * Every "keep" is a promise of a later retry, which is why MainActivity
     * calls [retryExpiredClear] from `onWindowFocusChanged` as well as
     * `onResume`: `onResume` runs before the window regains focus, so on its
     * own it would never see a readable clipboard.
     */
    private fun clearIfExpired(generation: Long) {
        val pending = pendingExpiration ?: return
        if (pending.copyGeneration != generation) return
        if (SystemClock.elapsedRealtime() < pending.expiresAtElapsedRealtime) return
        // Nothing this read returned could be believed, so do not spend the
        // pending entry on it.
        if (!canReadClipboard()) return

        val currentText = try {
            clipboardManager.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.text
                ?.toString()
        } catch (_: SecurityException) {
            return
        }
        // Focus can be lost between the check above and the read, and OEMs vary
        // in what they return when they refuse, so a null here is still
        // "unknown", not "empty".
        if (currentText == null) return

        if (currentText == pending.text) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboardManager.clearPrimaryClip()
            } else {
                clipboardManager.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }
        // Either the secret was just cleared or the clipboard readably holds
        // something else. Both mean it is off the clipboard, so the entry and
        // its plaintext can go.
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
        val text: String,
        val copyGeneration: Long,
        val expiresAtElapsedRealtime: Long
    )

    companion object {
        const val CHANNEL = "com.zcash.wallet/sensitive_clipboard"
        private const val SENSITIVE_CLIPBOARD_KEY = "android.content.extra.IS_SENSITIVE"
        private const val DEFAULT_EXPIRATION_SECONDS = 60L
        private const val MAX_EXPIRATION_SECONDS = 24L * 60L * 60L
    }
}
