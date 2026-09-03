package com.keplr.vizor

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

internal class SensitiveClipboardHandler(context: Context) {
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

    private fun clearIfExpired(generation: Long) {
        val pending = pendingExpiration ?: return
        if (pending.copyGeneration != generation) return
        if (SystemClock.elapsedRealtime() < pending.expiresAtElapsedRealtime) return

        val currentText = try {
            clipboardManager.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.text
                ?.toString()
        } catch (_: SecurityException) {
            // Android can deny clipboard reads while Vizor is in the background.
            // Keep the pending expiration so onResume can retry it.
            return
        }
        if (currentText == null) return

        if (currentText == pending.text) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboardManager.clearPrimaryClip()
            } else {
                clipboardManager.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }
        if (pendingExpiration === pending) {
            pendingExpiration = null
        }
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
