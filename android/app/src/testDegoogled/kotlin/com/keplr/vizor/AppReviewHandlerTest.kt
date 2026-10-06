package com.keplr.vizor

import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class AppReviewHandlerTest {
    @Test fun googlePlayReviewSdkIsAbsentFromTheClasspath() {
        assertThrows(ClassNotFoundException::class.java) {
            Class.forName("com.google.android.play.core.review.ReviewManager")
        }
    }

    @Test fun cannotPrepareOrRequestEvenWhenCalledDirectly() {
        val activity = mock(FragmentActivity::class.java)
        val handler = AppReviewHandler(activity)
        for (method in listOf("prepare", "request", "prepare", "request")) {
            val result = mock(MethodChannel.Result::class.java)
            handler.handle(MethodCall(method, null), result)
            verify(result).success(false)
        }
        verifyNoInteractions(activity)
    }

    @Test fun supportsCancellationAndRejectsUnknownMethods() {
        val handler = AppReviewHandler(mock(FragmentActivity::class.java))
        val cancelled = mock(MethodChannel.Result::class.java)
        handler.handle(MethodCall("cancel", null), cancelled)
        verify(cancelled).success(null)
        val unknown = mock(MethodChannel.Result::class.java)
        handler.handle(MethodCall("unknown", null), unknown)
        verify(unknown).notImplemented()
    }
}
