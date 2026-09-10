package com.keplr.vizor

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 29, 33], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class SensitiveClipboardHandlerTest {
    private lateinit var clipboard: ClipboardManager
    private lateinit var activity: Activity
    private lateinit var handler: SensitiveClipboardHandler
    private var current: ClipData? = null
    private var focused = true
    private var denyRead = false
    private var nullRead = false
    private var denyClear = false
    private var loseFocusOnRead = false

    @Before fun setUp() {
        clipboard = mock(ClipboardManager::class.java)
        activity = mock(Activity::class.java)
        `when`(activity.getSystemService(Context.CLIPBOARD_SERVICE)).thenReturn(clipboard)
        `when`(activity.hasWindowFocus()).thenAnswer { focused }
        doAnswer { current = it.getArgument(0); null }
            .`when`(clipboard).setPrimaryClip(any(ClipData::class.java))
        `when`(clipboard.primaryClipDescription).thenAnswer {
            if (denyRead) throw SecurityException("Denied")
            if (loseFocusOnRead) focused = false
            if (nullRead) null else current?.description
        }
        if (Build.VERSION.SDK_INT >= 28) {
            doAnswer {
                if (denyClear) throw SecurityException("Denied")
                current = null
                null
            }.`when`(clipboard).clearPrimaryClip()
        }
        handler = SensitiveClipboardHandler(activity)
    }

    @After fun neverReadsClipboardBody() {
        verify(clipboard, never()).primaryClip
    }

    private fun copy(text: String = "secret", seconds: Int = 60) {
        val result = mock(MethodChannel.Result::class.java)
        handler.handle(MethodCall("copyText", mapOf(
            "text" to text, "expirationSeconds" to seconds
        )), result)
        verify(result).success(null)
    }

    private fun advance(seconds: Long) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(seconds))
    }

    private fun assertCleared() {
        if (Build.VERSION.SDK_INT >= 28) assertNull(current)
        else assertEquals("", current!!.getItemAt(0).text)
    }

    @Test fun nonExpiringCopyKeepsSensitiveFlagAndCancelsEarlierExpiry() {
        copy()
        val result = mock(MethodChannel.Result::class.java)
        handler.handle(MethodCall("copyText", mapOf(
            "text" to "secret", "autoClear" to false
        )), result)
        verify(result).success(null)
        assertTrue(current!!.description.extras!!.getBoolean("android.content.extra.IS_SENSITIVE"))
        val giftLink = current
        advance(120)
        handler.retryExpiredClear()
        assertSame(giftLink, current)
        verify(clipboard, never()).primaryClipDescription

        copy("mnemonic")
        advance(60)
        assertCleared()
    }

    @Test fun expiresOnlyAfterDeadlineAndMarksSensitive() {
        copy()
        assertTrue(current!!.description.extras!!.getBoolean("android.content.extra.IS_SENSITIVE"))
        advance(59)
        assertEquals("secret", current!!.getItemAt(0).text)
        advance(1)
        assertCleared()
    }

    @Test fun preservesIndependentlyCopiedIdenticalText() {
        copy()
        val replacement = ClipData.newPlainText("", "secret")
        current = replacement
        advance(60)
        assertSame(replacement, current)
    }

    @Test fun retiresExpiryAfterKnownReplacement() {
        copy()
        val original = current
        val replacement = ClipData.newPlainText("", "other app text")
        current = replacement
        advance(60)
        assertSame(replacement, current)
        current = original
        handler.retryExpiredClear()
        assertSame(original, current)
    }

    @Test fun olderTimerCannotClearNewCopyEvenWithIdenticalText() {
        copy()
        advance(30)
        copy()
        val second = current
        advance(30)
        assertSame(second, current)
        advance(30)
        assertCleared()
    }

    @Test fun tokenFromAnotherHandlerDoesNotMatch() {
        copy()
        advance(30)
        val secondHandler = SensitiveClipboardHandler(activity)
        secondHandler.handle(MethodCall("copyText", mapOf("text" to "secret")),
            mock(MethodChannel.Result::class.java))
        val second = current
        advance(30)
        assertSame(second, current)
        advance(30)
        assertCleared()
    }

    @Test fun deniedAndNullMetadataCanRetryOnFocusReturn() {
        copy()
        val original = current
        denyRead = true
        advance(60)
        assertSame(original, current)
        denyRead = false
        nullRead = true
        handler.retryExpiredClear()
        assertSame(original, current)
        nullRead = false
        handler.retryExpiredClear()
        assertCleared()
    }

    @Test fun focusRequiredOnAndroid10AndLater() {
        copy()
        focused = false
        advance(60)
        if (Build.VERSION.SDK_INT >= 29) {
            verify(clipboard, never()).primaryClipDescription
            assertNotNull(current)
            focused = true
            handler.retryExpiredClear()
        }
        assertCleared()
    }

    @Test fun preservesOtherAppCopyOnForegroundRetry() {
        if (Build.VERSION.SDK_INT < 29) return
        copy()
        focused = false
        val replacement = ClipData.newPlainText("", "other app text")
        current = replacement
        advance(60)
        focused = true
        handler.retryExpiredClear()
        assertSame(replacement, current)
    }

    @Test fun foregroundRetryUsesElapsedDeadlineWithoutWaitingForTimer() {
        copy()
        ShadowSystemClock.advanceBy(Duration.ofSeconds(61))
        handler.retryExpiredClear()
        assertCleared()
    }

    @Test fun focusLossDuringReadDefersClear() {
        copy()
        loseFocusOnRead = true
        advance(60)
        if (Build.VERSION.SDK_INT >= 29) {
            assertNotNull(current)
            loseFocusOnRead = false
            focused = true
            handler.retryExpiredClear()
        }
        assertCleared()
    }

    @Test fun deniedClearRetainsExpiryForRetry() {
        if (Build.VERSION.SDK_INT < 28) return
        copy()
        denyClear = true
        advance(60)
        assertNotNull(current)
        denyClear = false
        handler.retryExpiredClear()
        assertCleared()
    }
}
