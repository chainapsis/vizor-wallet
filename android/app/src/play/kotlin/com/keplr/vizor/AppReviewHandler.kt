package com.keplr.vizor

import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import com.google.android.play.core.review.ReviewInfo
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AppReviewHandler(
    private val activity: FragmentActivity,
    private val manager: ReviewManager = ReviewManagerFactory.create(activity),
) {
    private var prepared: ReviewInfo? = null
    private var generation = 0

    private fun isForeground() = !activity.isFinishing && !activity.isDestroyed &&
        activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
        activity.hasWindowFocus()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                prepared = null
                val current = ++generation
                if (!isForeground()) {
                    result.success(false)
                    return
                }
                manager.requestReviewFlow().addOnCompleteListener { task ->
                    if (current != generation || !isForeground() || !task.isSuccessful) {
                        result.success(false)
                    } else {
                        prepared = task.result
                        result.success(true)
                    }
                }
            }
            "request" -> {
                val info = prepared
                prepared = null
                if (info == null || !isForeground()) {
                    result.success(false)
                    return
                }
                manager.launchReviewFlow(activity, info)
                // Completion cannot establish whether a prompt or review occurred.
                result.success(true)
            }
            "cancel" -> {
                generation++
                prepared = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.zcash.wallet/app_review"
    }
}
