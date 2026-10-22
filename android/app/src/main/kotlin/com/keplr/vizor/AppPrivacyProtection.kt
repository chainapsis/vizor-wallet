package com.keplr.vizor

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import kotlin.math.max
import kotlin.math.roundToInt

/** Native lifecycle owner for solid secret screens and blurred ordinary screens. */
internal class AppPrivacyProtection(
    private val activity: Activity,
    private val capturePreview: () -> Bitmap? = { null },
    private val afterFrame: (View, () -> Unit) -> Unit = { view, complete ->
        if (view.isHardwareAccelerated) {
            view.viewTreeObserver.registerFrameCommitCallback { complete() }
            view.invalidate()
        }
    },
) {
    private var resumed = false
    private var windowFocused = false
    private var sensitiveContentVisible = false
    private var solidBackground = true // Until Flutter's first policy arrives.
    private var cover: FrameLayout? = null
    private var preview: Bitmap? = null
    private var hiddenContent: View? = null
    private var previousVisibility = View.VISIBLE
    private var blurCommitted = false
    private var generation = 0
    private var recentsEnabled: Boolean? = null

    fun onCreate() {
        setRecentsEnabled(false)
        updateSecureFlag()
    }

    fun onResume() {
        resumed = true
        windowFocused = activity.hasWindowFocus()
        updateProtection()
    }

    fun onPause() {
        resumed = false
        windowFocused = false
        updateProtection()
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        // Live recents can keep the Activity resumed; protect at focus loss.
        windowFocused = hasFocus
        updateProtection()
    }

    private val interactive: Boolean get() = resumed && windowFocused

    private fun updateProtection() {
        if (interactive) {
            generation++
            // Secure first if needed, before restoring any original pixels.
            blurCommitted = false
            updateSecureFlag()
            setRecentsEnabled(false)
            hiddenContent?.visibility = previousVisibility
            hiddenContent = null
            removeCover()
        } else if (cover == null) {
            showCover()
        } else if (solidBackground || sensitiveContentVisible) {
            // Never downgrade a solid cover while inactive, even if Dart drops
            // a scope during background routing or auto-lock.
            makeSolid()
        }
    }

    private fun showCover() {
        blurCommitted = false
        updateSecureFlag()
        setRecentsEnabled(false)
        val decor = activity.window.decorView as ViewGroup
        val content = activity.findViewById<View>(android.R.id.content)
        val bitmap = if (!solidBackground && !sensitiveContentVisible) {
            try {
                capturePreview()?.let { source ->
                    try { blurredPreview(source) } finally { source.recycle() }
                }
            } catch (_: Exception) { null }
              catch (_: OutOfMemoryError) { null }
        } else null
        preview = bitmap
        val privacyCover = FrameLayout(activity).apply {
            setBackgroundColor(Color.rgb(20, 24, 24))
            isClickable = true
            isFocusable = true
            contentDescription = "Sensitive content hidden"
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            if (bitmap != null) {
                addView(ImageView(context).apply {
                    setImageBitmap(bitmap)
                    scaleType = ImageView.ScaleType.FIT_XY
                }, FrameLayout.LayoutParams(-1, -1))
            }
            val iconSize = (50 * resources.displayMetrics.density).toInt()
            addView(ImageView(context).apply {
                setImageResource(android.R.drawable.ic_lock_lock)
                setColorFilter(Color.WHITE)
            }, FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER))
        }
        decor.addView(privacyCover, ViewGroup.LayoutParams(-1, -1))
        cover = privacyCover
        // SurfaceView pixels are composed separately from Android Views. Hide
        // the entire content subtree, rather than trusting an overlay alone.
        hiddenContent = content
        previousVisibility = content.visibility
        content.visibility = View.INVISIBLE
        val currentGeneration = ++generation
        if (bitmap != null) {
            // Only a submitted opaque cover with the source subtree hidden may
            // be captured by recents. Until then keep FLAG_SECURE (solid fallback).
            afterFrame(decor) {
                activity.runOnUiThread {
                    if (generation == currentGeneration && !interactive &&
                        cover === privacyCover && !solidBackground &&
                        !sensitiveContentVisible && content.visibility == View.INVISIBLE
                    ) {
                        blurCommitted = true
                        updateSecureFlag()
                        setRecentsEnabled(true)
                    }
                }
            }
        }
    }

    private fun makeSolid() {
        generation++
        blurCommitted = false
        updateSecureFlag()
        setRecentsEnabled(false)
        cover?.let { current ->
            if (preview != null) current.removeViewAt(0)
        }
        // RenderThread may still reference the last ImageView display list.
        // Drop the tiny blurred bitmap and let GC retire it safely.
        preview = null
    }

    private fun removeCover() {
        cover?.let { (it.parent as? ViewGroup)?.removeView(it) }
        cover = null
        // RenderThread may still reference the last ImageView display list.
        // Drop the tiny blurred bitmap and let GC retire it safely.
        preview = null
    }

    fun setSolidBackground(solid: Boolean) {
        solidBackground = solid
        if (!interactive && solid) makeSolid()
    }

    fun setSensitiveContentVisible(visible: Boolean) {
        sensitiveContentVisible = visible
        if (!interactive && visible) makeSolid() else updateSecureFlag()
    }

    fun close() {
        generation++
        hiddenContent?.visibility = previousVisibility
        hiddenContent = null
        removeCover()
    }

    private fun updateSecureFlag() {
        if (sensitiveContentVisible || (!interactive && !blurCommitted)) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun setRecentsEnabled(enabled: Boolean) {
        if (recentsEnabled == enabled) return
        recentsEnabled = enabled
        if (Build.VERSION.SDK_INT >= 33) activity.setRecentsScreenshotEnabled(enabled)
    }

    companion object {
        /** Discard text/QR detail before three box-blur passes. Never persisted. */
        internal fun blurredPreview(source: Bitmap): Bitmap {
            val width = 24
            val height = max(1, (width * source.height.toFloat() / source.width).roundToInt())
            val result = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            Canvas(result).drawBitmap(source, null, Rect(0, 0, width, height),
                Paint(Paint.FILTER_BITMAP_FLAG))
            var pixels = IntArray(width * height)
            result.getPixels(pixels, 0, width, 0, 0, width, height)
            repeat(3) {
                val next = IntArray(pixels.size)
                for (y in 0 until height) for (x in 0 until width) {
                    var r = 0; var g = 0; var b = 0; var count = 0
                    for (dy in -2..2) for (dx in -2..2) {
                        val color = pixels[(y + dy).coerceIn(0, height - 1) * width +
                            (x + dx).coerceIn(0, width - 1)]
                        r += Color.red(color); g += Color.green(color); b += Color.blue(color)
                        count++
                    }
                    next[y * width + x] = Color.rgb(r / count, g / count, b / count)
                }
                pixels = next
            }
            for (i in pixels.indices) {
                val color = pixels[i]
                pixels[i] = Color.rgb((Color.red(color) * .75f + 20 * .25f).toInt(),
                    (Color.green(color) * .75f + 24 * .25f).toInt(),
                    (Color.blue(color) * .75f + 24 * .25f).toInt())
            }
            result.setPixels(pixels, 0, width, 0, 0, width, height)
            return result
        }
    }
}
