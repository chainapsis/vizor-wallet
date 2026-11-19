package com.keplr.vizor

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Looper
import android.os.ParcelFileDescriptor
import org.robolectric.RuntimeEnvironment
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.time.Duration
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.LooperMode

/**
 * The copy pipeline behind the share sheet, driven through the channel the
 * Dart side uses: a provider that answers, one that stalls inside its open
 * and ignores cancellation (what a hostile sender can do), and one that
 * honours it. The deadline, the stuck-worker replacement and close() are
 * the paths a device run never exercises on purpose.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 33], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SharedPaymentHandlerTest {
    private lateinit var context: Context
    private lateinit var handler: SharedPaymentHandler
    private lateinit var dartHandler: BinaryMessenger.BinaryMessageHandler
    private val codec = StandardMethodCodec.INSTANCE

    @Before fun setUp() {
        context = RuntimeEnvironment.getApplication()
        ImageProvider.reset(context)
        Robolectric.buildContentProvider(ImageProvider::class.java).create(AUTHORITY)
        val messenger = mock(BinaryMessenger::class.java)
        handler = SharedPaymentHandler()
        handler.attach(messenger, context)
        val captor = ArgumentCaptor.forClass(BinaryMessenger.BinaryMessageHandler::class.java)
        verify(messenger).setMessageHandler(eq(SharedPaymentHandler.CHANNEL), captor.capture())
        dartHandler = captor.value
    }

    @After fun tearDown() {
        ImageProvider.release()
        handler.close()
        // Stalled opens return once released; the process-wide count must be
        // back to zero before the next test, which shares it.
        repeat(250) { if (SharedPaymentHandler.stuckWorkerCount == 0) return; Thread.sleep(20) }
        assertEquals("stuck workers back", 0, SharedPaymentHandler.stuckWorkerCount)
    }

    /** A call from Dart, decoded the way the engine would deliver its reply. */
    private fun call(method: String): Any? {
        val message = codec.encodeMethodCall(MethodCall(method, null)).also { it.flip() }
        var result: Any? = null
        dartHandler.onMessage(message) { reply: ByteBuffer? -> result = codec.decodeEnvelope(reply!!.also { it.flip() }) }
        return result
    }

    @Suppress("UNCHECKED_CAST")
    private fun takePending(): List<Map<String, Any>> = call("takePending") as List<Map<String, Any>>

    /** Runs the main looper until [done], giving the copy thread up to five seconds. */
    private fun awaitMain(done: () -> Boolean) {
        repeat(250) {
            shadowOf(Looper.getMainLooper()).idle()
            if (done()) return
            Thread.sleep(20)
        }
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun image(name: String) = SharedPaymentHandler.Share.Image(Uri.parse("content://$AUTHORITY/$name"))

    private fun copies(): List<File> = File(context.cacheDir, "shared_payment").listFiles()?.toList().orEmpty()

    @Test fun `text and capture numbers go to Dart ahead of an image still being copied`() {
        assertTrue(handler.capture(image("stall"), seq = 1))
        assertTrue(handler.capture(SharedPaymentHandler.Share.Text("pay me"), seq = 2))
        handler.noteLink(seq = 3)

        val delivered = takePending()

        assertEquals(listOf("captured", "text", "captured"), delivered.map { it["type"] })
        assertEquals(listOf(1L, 2L, 3L), delivered.map { it["seq"] })
        assertEquals("pay me", delivered[1]["text"])
        assertTrue("the image waits for its copy", takePending().isEmpty())
    }

    @Test fun `a good image is copied into the cache and delivered with its path`() {
        assertTrue(handler.capture(image("good"), seq = 1))

        val delivered = mutableListOf<Map<String, Any>>()
        awaitMain { delivered.addAll(takePending()); delivered.any { it["type"] == "image" } }

        val image = delivered.single { it["type"] == "image" }
        assertEquals(1L, image["seq"])
        val path = image["path"] as String
        assertTrue(File(path).isFile)
        // This activity's own folder under the share cache.
        assertEquals(File(context.cacheDir, "shared_payment"), File(path).parentFile.parentFile)
    }

    @Test fun `an image whose provider stalls is answered unreadable at the deadline and the next image is still copied`() {
        assertTrue(handler.capture(image("stall"), seq = 1))
        awaitMain { ImageProvider.stalledOpens == 1 }

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(15_000))

        val afterDeadline = takePending()
        assertEquals(listOf("captured", "image"), afterDeadline.map { it["type"] })
        assertNull("no copy to deliver", afterDeadline[1]["path"])
        assertEquals(1L, afterDeadline[1]["seq"])

        // The stuck worker was written off: the next copy runs on a fresh one.
        assertTrue(handler.capture(image("good"), seq = 2))
        val delivered = mutableListOf<Map<String, Any>>()
        awaitMain { delivered.addAll(takePending()); delivered.any { it["type"] == "image" } }
        val image = delivered.single { it["type"] == "image" }
        assertEquals(2L, image["seq"])
        assertTrue(File(image["path"] as String).isFile)
    }

    @Test fun `a provider that honours cancellation is cut off at the deadline`() {
        assertTrue(handler.capture(image("cancellable"), seq = 1))
        awaitMain { ImageProvider.cancellableOpens == 1 }

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(15_000))

        assertTrue("the open saw the cancel", ImageProvider.cancelled.await(5, TimeUnit.SECONDS))
        val delivered = takePending()
        assertEquals("image", delivered.last()["type"])
        assertNull(delivered.last()["path"])
    }

    @Test fun `close deletes the copies Dart never took, and the ones it took but had not deleted`() {
        assertTrue(handler.capture(image("good"), seq = 1))
        awaitMain { copies().isNotEmpty() }
        assertEquals(1, copies().size)
        handler.close()
        assertTrue("an untaken copy is gone", copies().isEmpty())

        handler = SharedPaymentHandler().also { it.attach(mock(BinaryMessenger::class.java), context) }
        assertTrue(handler.capture(image("good"), seq = 2))
        awaitMain { copies().isNotEmpty() }
        // Dart took it (the engine then died before deleting it).
        val taken = mutableListOf<Map<String, Any>>()
        awaitMain { taken.addAll(takePendingVia(handler)); taken.any { it["type"] == "image" } }
        assertEquals(1, copies().size)
        handler.close()
        assertTrue("a taken copy is gone too", copies().isEmpty())
    }

    @Test fun `a worker whose open returns after being written off gives its slot back`() {
        // A cooperative provider that is slow to unwind: written off at the
        // deadline, then back, and the count goes back down with it.
        assertTrue(handler.capture(image("cancellable"), seq = 1))
        awaitMain { ImageProvider.cancellableOpens == 1 }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(15_000))
        assertTrue(ImageProvider.cancelled.await(5, TimeUnit.SECONDS))
        awaitMain { ImageProvider.cancellableReturned && SharedPaymentHandler.stuckWorkerCount == 0 }
        assertEquals(0, SharedPaymentHandler.stuckWorkerCount)

        // One outright stall is written off and replaced, and a copy still
        // runs behind it; a slot kept by the recovered worker would have put
        // the process at its budget here.
        assertTrue(handler.capture(image("stall"), seq = 2))
        awaitMain { ImageProvider.stalledOpens == 1 }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(15_000))
        assertEquals(1, SharedPaymentHandler.stuckWorkerCount)
        assertTrue(handler.capture(image("good"), seq = 3))
        val delivered = mutableListOf<Map<String, Any>>()
        awaitMain { delivered.addAll(takePending()); delivered.any { it["type"] == "image" && it["path"] != null } }
        assertTrue("copied on a fresh worker", delivered.any { it["type"] == "image" && it["path"] != null })
    }

    @Test fun `only so many images wait for a copy, and only so many texts wait for Dart`() {
        repeat(4) { assertTrue(handler.capture(image("stall"), seq = it + 1L)) }
        assertFalse("the fifth image is refused", handler.capture(image("stall"), seq = 5))
        repeat(4) { assertTrue(handler.capture(SharedPaymentHandler.Share.Text("t$it"), seq = 6L + it)) }
        assertFalse("the fifth text is refused", handler.capture(SharedPaymentHandler.Share.Text("t4"), seq = 10))
        handler.noteLink(seq = 11)
        assertEquals(listOf("captured", "captured", "captured", "captured", "text", "text", "text", "text", "captured"), takePending().map { it["type"] })
        assertTrue("taken, there is room again", handler.capture(SharedPaymentHandler.Share.Text("t5"), seq = 12))
    }

    @Test fun `a worker left caught in an open when the activity closes counts, and past the budget no copy starts`() {
        // Two activities each close on a worker stuck inside a provider's open.
        repeat(2) {
            assertTrue(handler.capture(image("stall"), seq = it + 1L))
            awaitMain { ImageProvider.stalledOpens == it + 1 }
            handler.close()
            handler = SharedPaymentHandler().also { h -> h.attach(mock(BinaryMessenger::class.java), context) }
        }
        assertEquals(2, SharedPaymentHandler.stuckWorkerCount)

        // The next image is answered at once rather than risk a third thread.
        val messenger = mock(BinaryMessenger::class.java)
        handler = SharedPaymentHandler().also { it.attach(messenger, context) }
        val captor = ArgumentCaptor.forClass(BinaryMessenger.BinaryMessageHandler::class.java)
        verify(messenger).setMessageHandler(eq(SharedPaymentHandler.CHANNEL), captor.capture())
        dartHandler = captor.value
        assertTrue(handler.capture(image("good"), seq = 3))
        val delivered = takePending()
        assertEquals(listOf("captured", "image"), delivered.map { it["type"] })
        assertNull("not copied", delivered[1]["path"])
        assertEquals(2, ImageProvider.stalledOpens)

        // Once the stalled opens return, copies start again.
        ImageProvider.release()
        awaitMain { SharedPaymentHandler.stuckWorkerCount == 0 }
        assertTrue(handler.capture(image("good"), seq = 4))
        val copied = mutableListOf<Map<String, Any>>()
        awaitMain { copied.addAll(takePending()); copied.any { it["type"] == "image" && it["path"] != null } }
        assertTrue(copied.any { it["type"] == "image" && it["path"] != null })
    }

    /** [takePending] through [other]'s own channel handler. */
    @Suppress("UNCHECKED_CAST")
    private fun takePendingVia(other: SharedPaymentHandler): List<Map<String, Any>> {
        val messenger = mock(BinaryMessenger::class.java)
        other.attach(messenger, context)
        val captor = ArgumentCaptor.forClass(BinaryMessenger.BinaryMessageHandler::class.java)
        verify(messenger).setMessageHandler(eq(SharedPaymentHandler.CHANNEL), captor.capture())
        val message = codec.encodeMethodCall(MethodCall("takePending", null)).also { it.flip() }
        var result: Any? = null
        captor.value.onMessage(message) { reply: ByteBuffer? -> result = codec.decodeEnvelope(reply!!.also { it.flip() }) }
        return result as List<Map<String, Any>>
    }

    companion object {
        private const val AUTHORITY = "com.keplr.vizor.test.images"
    }
}

/**
 * The sender's side of a share: a provider the handler opens with the grant
 * it was given. The signal reaches a provider only through the typed open,
 * which is the one DocumentsProvider overrides; the framework's default drops
 * it before openAssetFile.
 */
class ImageProvider : ContentProvider() {
    override fun onCreate() = true

    override fun openTypedAssetFile(uri: Uri, mimeTypeFilter: String, opts: Bundle?, signal: CancellationSignal?): AssetFileDescriptor? =
        openAssetFile(uri, "r", signal)

    override fun openAssetFile(uri: Uri, mode: String, signal: CancellationSignal?): AssetFileDescriptor? =
        when (uri.lastPathSegment) {
            // Never returns, ignores the signal and shrugs off interruption,
            // like a binder call into a sender that means to stall.
            "stall" -> {
                stalledOpens++
                while (stall.count > 0) {
                    try {
                        stall.await()
                    } catch (_: InterruptedException) {
                        // A stalled binder call does not notice an interrupt.
                    }
                }
                null
            }
            // Blocks until cancelled, then returns the way a cooperative provider does.
            "cancellable" -> {
                cancellableOpens++
                val woken = CountDownLatch(1)
                signal?.setOnCancelListener { cancelled.countDown(); woken.countDown() }
                if (signal?.isCanceled == true) woken.countDown()
                woken.await()
                cancellableReturned = true
                signal?.throwIfCanceled()
                null
            }
            else -> AssetFileDescriptor(
                ParcelFileDescriptor.open(png, ParcelFileDescriptor.MODE_READ_ONLY),
                0,
                AssetFileDescriptor.UNKNOWN_LENGTH,
            )
        }

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = "image/png"
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?) = 0

    companion object {
        lateinit var png: File
        @Volatile var stall = CountDownLatch(1)
        @Volatile var cancelled = CountDownLatch(1)
        @Volatile var stalledOpens = 0
        @Volatile var cancellableOpens = 0
        @Volatile var cancellableReturned = false

        fun reset(context: Context) {
            release()
            stall = CountDownLatch(1)
            cancelled = CountDownLatch(1)
            stalledOpens = 0
            cancellableOpens = 0
            cancellableReturned = false
            png = File(context.cacheDir, "shared.png")
            FileOutputStream(png).use { Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, it) }
        }

        /** Lets a stalled open return, so its thread does not outlive the test. */
        fun release() {
            stall.countDown()
        }
    }
}
