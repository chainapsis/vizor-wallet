package com.keplr.vizor

import android.os.Looper
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.android.gms.tasks.Tasks
import com.google.android.play.core.review.ReviewInfo
import com.google.android.play.core.review.ReviewManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class AppReviewHandlerTest {
    private lateinit var activity: FragmentActivity
    private lateinit var manager: ReviewManager
    private lateinit var handler: AppReviewHandler
    private lateinit var info: ReviewInfo
    private var focused = true

    @Before fun setUp() {
        activity = mock(FragmentActivity::class.java)
        val lifecycle = mock(Lifecycle::class.java)
        `when`(activity.lifecycle).thenReturn(lifecycle)
        `when`(lifecycle.currentState).thenReturn(Lifecycle.State.RESUMED)
        `when`(activity.hasWindowFocus()).thenAnswer { focused }
        manager = mock(ReviewManager::class.java)
        info = mock(ReviewInfo::class.java)
        `when`(manager.requestReviewFlow()).thenReturn(Tasks.forResult(info))
        `when`(manager.launchReviewFlow(activity, info)).thenReturn(Tasks.forResult(null))
        handler = AppReviewHandler(activity, manager)
    }

    private fun call(method: String): MethodChannel.Result {
        val result = mock(MethodChannel.Result::class.java)
        handler.handle(MethodCall(method, null), result)
        shadowOf(Looper.getMainLooper()).idle()
        return result
    }

    @Test fun preparesThenDispatchesOnlyOnceWithoutWaitingForRatingOutcome() {
        verify(call("prepare")).success(true)
        verify(call("request")).success(true)
        verify(call("request")).success(false)
        verify(manager, times(1)).launchReviewFlow(activity, info)
    }

    @Test fun foregroundIsCheckedAgainAfterAsynchronousPreparation() {
        val pending = TaskCompletionSource<ReviewInfo>()
        `when`(manager.requestReviewFlow()).thenReturn(pending.task)
        val result = call("prepare")
        focused = false
        pending.setResult(info)
        shadowOf(Looper.getMainLooper()).idle()
        verify(result).success(false)
        verify(call("request")).success(false)
        verify(manager, never()).launchReviewFlow(activity, info)
    }

    @Test fun cancellationInvalidatesAnInFlightPreparation() {
        val pending = TaskCompletionSource<ReviewInfo>()
        `when`(manager.requestReviewFlow()).thenReturn(pending.task)
        val result = call("prepare")
        call("cancel")
        pending.setResult(info)
        shadowOf(Looper.getMainLooper()).idle()
        verify(result).success(false)
        verify(call("request")).success(false)
        verify(manager, never()).launchReviewFlow(activity, info)
    }

    @Test fun lossOfFocusBetweenPrepareAndRequestDoesNotLaunch() {
        call("prepare")
        focused = false
        verify(call("request")).success(false)
        verify(manager, never()).launchReviewFlow(activity, info)
    }

    @Test fun failedPreparationIsNotAnAttempt() {
        `when`(manager.requestReviewFlow()).thenReturn(Tasks.forException(Exception("No Play Store")))
        verify(call("prepare")).success(false)
        verify(call("request")).success(false)
        verify(manager, never()).launchReviewFlow(activity, info)
    }

    @Test fun aBackgroundActivityCannotEvenPrepare() {
        focused = false
        verify(call("prepare")).success(false)
        verify(manager, never()).requestReviewFlow()
    }
}
