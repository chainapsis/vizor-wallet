package com.keplr.vizor

import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Direct/F-Droid builds retain the bridge without loading the Play review SDK. */
class AppReviewHandler(@Suppress("UNUSED_PARAMETER") activity: FragmentActivity) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare", "request" -> result.success(false)
            "cancel" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "com.zcash.wallet/app_review"
    }
}
