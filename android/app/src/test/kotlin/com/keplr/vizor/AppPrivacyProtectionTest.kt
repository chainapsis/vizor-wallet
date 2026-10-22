package com.keplr.vizor

import android.app.Activity
import android.os.Build
import android.graphics.Bitmap
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 32, 33, 34], manifest = Config.NONE)
class AppPrivacyProtectionTest {
    private lateinit var activity: Activity
    private lateinit var protection: AppPrivacyProtection

    @Before fun setUp() {
        activity = spy(Robolectric.buildActivity(Activity::class.java).setup().get())
        if (Build.VERSION.SDK_INT >= 33) {
            doNothing().`when`(activity).setRecentsScreenshotEnabled(anyBoolean())
        }
        protection = AppPrivacyProtection(activity)
        protection.onCreate()
        resumeFocused()
    }

    private fun resumeFocused() {
        protection.onResume()
        protection.onWindowFocusChanged(true)
    }

    private fun isSecure() = activity.window.attributes.flags and
        WindowManager.LayoutParams.FLAG_SECURE != 0

    private fun coverCount(): Int {
        val decor = activity.window.decorView as ViewGroup
        return (0 until decor.childCount).count {
            decor.getChildAt(it).contentDescription == "Sensitive content hidden"
        }
    }

    @Test fun ordinaryForegroundAllowsCapture() {
        assertFalse(isSecure())
        assertEquals(0, coverCount())
        if (Build.VERSION.SDK_INT >= 33) {
            verify(activity).setRecentsScreenshotEnabled(false)
        }
    }

    @Test fun everyBackgroundScreenIsCoveredAndLiveRecentsAreSecure() {
        protection.onPause()
        assertEquals(1, coverCount())
        assertTrue(isSecure())
        protection.onPause()
        assertEquals(1, coverCount())
        resumeFocused()
        assertEquals(0, coverCount())
        assertFalse(isSecure())
    }

    @Test fun sensitiveCaptureExclusionSurvivesResume() {
        protection.setSensitiveContentVisible(true)
        assertTrue(isSecure())
        protection.onPause()
        resumeFocused()
        assertTrue(isSecure())
        assertEquals(0, coverCount())
        protection.setSensitiveContentVisible(false)
        assertFalse(isSecure())
    }

    @Test fun removingSensitiveScreenInBackgroundCannotReleaseRecentsProtection() {
        protection.setSensitiveContentVisible(true)
        protection.onPause()
        protection.setSensitiveContentVisible(false)
        assertTrue(isSecure())
        assertEquals(1, coverCount())
        resumeFocused()
        assertFalse(isSecure())
    }

    @Test fun sensitiveScreenCanBecomeVisibleWhileBackgrounded() {
        protection.onPause()
        protection.setSensitiveContentVisible(true)
        resumeFocused()
        assertTrue(isSecure())
        assertEquals(0, coverCount())
    }

    @Test fun liveRecentsFocusLossIsProtectedWithoutWaitingForPause() {
        protection.onWindowFocusChanged(false)
        assertTrue(isSecure())
        assertEquals(1, coverCount())
        protection.setSensitiveContentVisible(false)
        assertTrue(isSecure())
        protection.onWindowFocusChanged(true)
        assertFalse(isSecure())
        assertEquals(0, coverCount())
    }

    @Test fun resumeBeforeFocusCannotUncoverTheWindow() {
        protection.onPause()
        protection.onResume()
        assertTrue(isSecure())
        assertEquals(1, coverCount())
        protection.setSensitiveContentVisible(true)
        protection.onWindowFocusChanged(true)
        assertTrue(isSecure())
        assertEquals(0, coverCount())
    }

    private fun blurProtection(commit: ((() -> Unit) -> Unit)): AppPrivacyProtection =
        AppPrivacyProtection(activity, capturePreview = {
            Bitmap.createBitmap(240, 480, Bitmap.Config.ARGB_8888).apply {
                eraseColor(Color.MAGENTA)
            }
        }, afterFrame = { _, callback -> commit(callback) }).also {
            protection.close()
            protection = it
            it.onCreate()
            resumeFocused()
            it.setSolidBackground(false)
        }

    @Test fun blurCannotReleaseCaptureUntilCoverCommitsAndOriginalIsHidden() {
        var committed: (() -> Unit)? = null
        blurProtection { committed = it }
        protection.onWindowFocusChanged(false)
        assertTrue(isSecure())
        assertEquals(View.INVISIBLE, activity.findViewById<View>(android.R.id.content).visibility)
        committed!!()
        assertFalse(isSecure())
        if (Build.VERSION.SDK_INT >= 33) verify(activity).setRecentsScreenshotEnabled(true)
        protection.onPause()
        assertFalse(isSecure())
        resumeFocused()
        assertEquals(View.VISIBLE, activity.findViewById<View>(android.R.id.content).visibility)
        assertEquals(0, coverCount())
    }

    @Test fun staleFrameCommitCannotReleaseSensitiveProtectionOrSurviveResume() {
        var committed: (() -> Unit)? = null
        blurProtection { committed = it }
        protection.onWindowFocusChanged(false)
        protection.setSolidBackground(true)
        committed!!()
        assertTrue(isSecure())
        protection.setSolidBackground(false)
        assertTrue(isSecure()) // Solid is latched until foreground.
        resumeFocused()
        committed!!()
        protection.setSensitiveContentVisible(true)
        protection.onWindowFocusChanged(false)
        assertTrue(isSecure())
    }

    @Test fun accessibilityCoverHidesAndRestoresTheSameContentForBlurAndSolid() {
        for (solid in listOf(false, true)) {
            blurProtection { it() }
            protection.setSolidBackground(solid)
            val label = TextView(activity).apply {
                text = "Test wallet balance"
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            }
            activity.setContentView(label)
            val content = activity.findViewById<ViewGroup>(android.R.id.content)
            protection.onWindowFocusChanged(false)
            val decor = activity.window.decorView as ViewGroup
            val cover = (0 until decor.childCount).map { decor.getChildAt(it) }
                .single { it.contentDescription == "Sensitive content hidden" }
            assertEquals(View.INVISIBLE, content.visibility)
            assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, cover.importantForAccessibility)
            assertTrue(cover.isClickable)
            assertTrue(cover.isFocusable)
            assertSame(label, content.getChildAt(0))
            val coveredElements = ArrayList<View>()
            decor.addChildrenForAccessibility(coveredElements)
            assertTrue(coveredElements.contains(cover))
            assertFalse(coveredElements.contains(label))
            resumeFocused()
            assertEquals(View.VISIBLE, content.visibility)
            assertEquals(0, coverCount())
            assertSame(label, content.getChildAt(0))
            assertEquals("Test wallet balance", label.text.toString())
            val restoredElements = ArrayList<View>()
            decor.addChildrenForAccessibility(restoredElements)
            assertTrue(restoredElements.contains(label))
            protection.onPause()
            protection.close()
            assertEquals(View.VISIBLE, content.visibility)
            assertEquals(0, coverCount())
        }
    }

    @Test fun secretScreensNeverRequestAPreviewEvenWhenTheSecretIsHidden() {
        var requests = 0
        protection.close()
        protection = AppPrivacyProtection(activity, capturePreview = { requests++; null })
        protection.onCreate()
        resumeFocused()
        protection.setSolidBackground(true)
        protection.onPause()
        assertEquals(0, requests)
        assertTrue(isSecure())
    }

    @Test fun missingPreviewFailsClosedAndBlurOutputIsSmallAndOpaque() {
        protection.setSolidBackground(false)
        protection.onPause()
        assertTrue(isSecure())
        val source = Bitmap.createBitmap(1080, 2400, Bitmap.Config.ARGB_8888)
        val result = AppPrivacyProtection.blurredPreview(source)
        assertEquals(24, result.width)
        assertEquals(53, result.height)
        assertEquals(255, Color.alpha(result.getPixel(12, 26)))
        result.recycle()
        source.recycle()
    }
    @Test fun readbackMemoryFailureKeepsAnOpaqueCover() {
        protection.close()
        protection = AppPrivacyProtection(activity, capturePreview = {
            throw OutOfMemoryError("simulated readback allocation failure")
        })
        protection.onCreate()
        resumeFocused()
        protection.setSolidBackground(false)
        protection.onWindowFocusChanged(false)
        assertTrue(isSecure())
        assertEquals(1, coverCount())
    }
}
