package com.keplr.vizor

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import androidx.annotation.VisibleForTesting
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * Takes in what another app shares to Vizor through the system share sheet:
 * text that may hold a Zcash address or a `zcash:` payment link, or an image
 * of a payment QR code. Dart decides what the content is and routes it through
 * the same intake a tapped link goes through; this side only reads the intent
 * and queues it.
 *
 * Same handshake as the payment-URI channel: shares queue until Dart calls
 * `ready`, and `takePending` drains what was queued before that. The queue is
 * memory only. Shared text is whatever the sender selected, which can include
 * a Gift Card link and its mnemonic, so none of it is written to saved state.
 * A share that has not reached Dart when the process dies is lost and the
 * user shares again, the same answer an undelivered https link gets.
 *
 * An image is read while the sender's URI grant is good, at capture, and
 * written to this app's cache scaled down to at most [MAX_IMAGE_PIXELS]: the
 * QR reader on the Dart side decodes the whole file into memory, and the
 * sender chose the file. Dart deletes the copy once it has read it. The queue
 * keeps the image's place from the moment it is accepted, so shares reach
 * Dart in the order they arrived and a sender cannot queue more copies than
 * will ever be delivered.
 *
 * Ordering against the other channel: the activity numbers everything it
 * takes in, links and shares alike. Text is delivered at once with its
 * number; an image's number is announced at once and its payload follows
 * when its copy is written, behind any image ahead of it; a link's number is
 * announced here too. Dart orders a share against the links on the other
 * channel, and against a reset, by those numbers, with no clock involved.
 */
internal class SharedPaymentHandler {
    // The application context, given at attach. A copy that outlives the
    // activity must not keep the activity alive through this handler.
    private lateinit var context: Context
    private val mainHandler = Handler(Looper.getMainLooper())
    // One copy at a time, on one thread: each copy holds up to
    // [MAX_IMAGE_BYTES] of file and a bitmap of [MAX_IMAGE_PIXELS], which is
    // memory a phone cannot hold four of. A copy past its deadline is cut off
    // (see [Queued.abandon]), so the thread is free again for the next share.
    // The one thing that cannot be cut off is a provider's open that never
    // returns; a worker caught in one is replaced, see [replaceStuckWorker].
    private var imageExecutor = newImageExecutor()
    /** Images waiting for their copy, in arrival order. */
    private val pending = mutableListOf<Queued>()
    // This activity's own folder under the cache, swept whole on close, so a
    // copy already handed to Dart cannot outlive the activity if the engine
    // goes away before Dart deletes it.
    private val instanceDir = UUID.randomUUID().toString()
    /** Delivered ahead of the images: text, and the capture numbers of images and links. */
    private val immediate = mutableListOf<Map<String, Any>>()
    private var channel: MethodChannel? = null
    private var dartReady = false
    private var closed = false

    /** What a share intent carries. [key] is the one string the replay guard digests. */
    sealed class Share(val key: String) {
        class Text(val text: String) : Share(text)
        class Image(val uri: Uri) : Share(uri.toString())
    }

    /**
     * A queued share, numbered by the activity's intake sequence. An image
     * holds its place with no payload until its copy is written, or until its
     * deadline settles it; the copy thread reads the field to skip work nobody
     * is waiting for.
     */
    private class Queued(val seq: Long) {
        @Volatile var payload: Map<String, Any>? = null
        /** Cancels the provider's open while it is in progress. */
        val cancel = CancellationSignal()
        /** True while the worker is inside the provider's open, which is the one call that cannot be cut off. */
        @Volatile var opening = false
        /**
         * Flipped once, by whichever comes first: the deadline writing the
         * worker off, or the worker's open returning. The loser of that race
         * is the one that settles the slot, see [replaceStuckWorker].
         */
        val settled = AtomicBoolean(false)
        /** The provider's descriptor from the moment the open returns until the read is done. */
        @Volatile var descriptor: Closeable? = null

        /**
         * Cuts the copy off: a cancelled open returns, and closing the
         * descriptor from another thread makes a blocked read fail on Android.
         * Nothing waits on the result; the thread is simply free again sooner.
         */
        fun abandon() {
            cancel.cancel()
            runCatching { descriptor?.close() }
        }
    }

    /** Installs the channel and, once per process, clears image copies an earlier process never read. */
    fun attach(messenger: BinaryMessenger, context: Context) {
        this.context = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(::handle) }
        if (!cacheCleared) {
            cacheCleared = true
            imageExecutor.execute { File(this.context.cacheDir, IMAGE_DIR).deleteRecursively() }
        }
    }

    /** The share [intent] carries, or null for an intent that is not a share this app takes. */
    fun parse(intent: Intent): Share? {
        if (intent.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        return when {
            type.startsWith("image/") -> imageUri(intent)?.let(Share::Image)
            type.startsWith("text/") -> sharedText(intent)?.let(Share::Text)
            else -> null
        }
    }

    /** Queues [share] for Dart as capture number [seq]. Returns false when there is no room. */
    fun capture(share: Share, seq: Long): Boolean {
        when (share) {
            is Share.Text -> {
                // Bounded while Dart is not ready, like the image queue: text
                // is the one payload a sender can make large.
                if (immediate.count { it["type"] == "text" } >= MAX_PENDING) return false
                // Nothing to wait for, so it does not wait behind an image
                // either: Dart places it by number against whatever is still
                // being copied.
                deliverNow(mapOf("type" to "text", "text" to share.text, "seq" to seq))
            }
            is Share.Image -> {
                if (pending.size >= MAX_PENDING) return false
                // The payload comes only once the copy is written; the number
                // goes now, so Dart can place the image against anything that
                // arrives in the meantime, a link or a reset.
                announce(seq)
                if (stuckWorkers.get() >= MAX_STUCK_WORKERS) {
                    // The process already keeps as many threads caught in
                    // a provider's open as it will; this image is answered
                    // as unreadable rather than risk one more.
                    deliverNow(mapOf("type" to "image", "seq" to seq))
                } else {
                    copyImage(share.uri, seq)
                }
            }
        }
        return true
    }

    /** A link was queued on the other channel as capture number [seq]. */
    fun noteLink(seq: Long) = announce(seq)

    private fun announce(seq: Long) = deliverNow(mapOf("type" to "captured", "seq" to seq))

    private fun deliverNow(payload: Map<String, Any>) {
        immediate.add(payload)
        flush()
    }

    /**
     * Stops delivering. This activity's copies are deleted now, the ones Dart
     * took but had not deleted yet included, one still being written is cut
     * off and deleted when it lands, and the channel is let go so a copy that
     * outlives this activity holds no engine: a Gift Card QR among them must
     * not sit in the cache for the rest of the process.
     */
    fun close() {
        closed = true
        for (queued in pending) {
            queued.abandon()
            // A worker caught in a provider's open stays caught after this
            // activity is gone, and counts like one the deadline wrote off.
            if (queued.opening) writeOff(queued)
        }
        pending.clear()
        immediate.clear()
        channel?.setMethodCallHandler(null)
        channel = null
        // Copies not yet started are dropped; the one in progress deletes its
        // file when it lands, see copyImage.
        imageExecutor.shutdownNow()
        imageDir().deleteRecursively()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePending" -> result.success(takeReady())
            "ready" -> {
                dartReady = true
                flush()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun copyImage(uri: Uri, seq: Long) {
        val queued = Queued(seq)
        pending.add(queued)
        val task = Runnable {
            // Settled while it waited behind an earlier copy: the provider's
            // return must not cost every share since then a decode.
            if (queued.payload != null) return@Runnable
            // runCatching takes Throwable, so a decoder that runs out of
            // memory, or a copy cut off by its deadline, ends as an image
            // Dart is told it could not read.
            val path = try {
                runCatching { writeScaledCopy(uri, queued) }.getOrNull()
            } finally {
                // The open returned. If the deadline wrote this worker off
                // first, that is a thread this process has back now.
                if (!queued.settled.compareAndSet(false, true)) stuckWorkers.decrementAndGet()
            }
            mainHandler.post {
                if (closed || queued.payload != null) {
                    path?.let { File(it).delete() }
                } else {
                    settle(queued, path)
                }
            }
        }
        // A copy that has not landed by the deadline is settled as unreadable
        // and cut off, so a provider that never answers costs that share its
        // image, not the images behind it, and the thread is free for the
        // next one. Posted now rather than when the copy starts, so that
        // every image is answered within one deadline whatever is stuck ahead
        // of it; a slow copy behind another slow one pays for that.
        mainHandler.postDelayed({
            if (closed || queued.payload != null) return@postDelayed
            settle(queued, path = null)
            queued.abandon()
            // Not started yet: out of the queue, so a run of expired copies
            // cannot pile up behind a slow one. Inside the provider's open:
            // nothing can cut that off, so the worker is written off and the
            // copies behind it get a fresh one.
            if (!imageExecutor.remove(task) && queued.opening && writeOff(queued)) replaceWorker()
        }, COPY_DEADLINE_MS)
        imageExecutor.execute(task)
    }

    /**
     * Charges a worker caught in a provider's open to the process-wide count
     * of such threads; it is left to return in its own time. The write-off
     * and the open's return race, so [Queued.settled] decides: a worker whose
     * open returned first is charged nothing and this returns false; one
     * written off here returns its slot when its open does. A sender could
     * stall a provider on purpose, so the count gates what the process will
     * add: past [MAX_STUCK_WORKERS], no copy is started, see [capture], and
     * no worker is replaced, see [replaceWorker]; text does not go through
     * this queue at all.
     */
    private fun writeOff(queued: Queued): Boolean {
        if (!queued.settled.compareAndSet(false, true)) return false
        stuckWorkers.incrementAndGet()
        return true
    }

    /** A fresh worker for the copies waiting behind a written-off one, while the stuck ones are within budget. */
    private fun replaceWorker() {
        if (stuckWorkers.get() > MAX_STUCK_WORKERS) return
        val waiting = imageExecutor.shutdownNow()
        imageExecutor = newImageExecutor()
        waiting.forEach(imageExecutor::execute)
    }

    private fun settle(queued: Queued, path: String?) {
        queued.payload = buildMap {
            put("type", "image")
            if (path != null) put("path", path)
            put("seq", queued.seq)
        }
        flush()
    }

    /**
     * Everything Dart can take now: what was delivered ahead of the queue
     * since the last take, then the images that are ready, in arrival order,
     * up to the first one whose copy is still being written.
     */
    private fun takeReady(): List<Map<String, Any>> {
        val now = immediate.toList()
        immediate.clear()
        val ready = pending.takeWhile { it.payload != null }
        pending.subList(0, ready.size).clear()
        return now + ready.mapNotNull { it.payload }
    }

    private fun flush() {
        if (!dartReady) return
        val channel = channel ?: return
        val payloads = takeReady()
        if (payloads.isNotEmpty()) channel.invokeMethod("onShared", payloads)
    }

    /**
     * The shared text, or null when there is nothing worth sending: blank
     * text, an extra that is not text, or more than [MAX_TEXT_LENGTH]
     * characters, which no payment share comes anywhere near.
     */
    private fun sharedText(intent: Intent): String? {
        // Styled text arrives as a CharSequence rather than a String, and an
        // exported entry point has to survive an extra it cannot unparcel.
        val text = runCatching { intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() }
            .getOrNull() ?: return null
        return text.takeIf { it.isNotBlank() && it.length <= MAX_TEXT_LENGTH }
    }

    /**
     * The shared image's URI, from the stream extra or, for a sender that only
     * fills the clip, from the clip. Only a content provider's URI is opened: a
     * `file:` URI could point into this app's own private storage.
     */
    private fun imageUri(intent: Intent): Uri? {
        val uri = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            } ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
        }.getOrNull()
        return uri?.takeIf { it.scheme == ContentResolver.SCHEME_CONTENT }
    }

    private fun writeScaledCopy(uri: Uri, queued: Queued): String {
        // One bounded read, and both decodes work on those same bytes. Opening
        // the stream twice would let a provider serve a small image to the
        // bounds pass and a huge one to the decode. The open takes the
        // cancellation signal, and the descriptor is published the moment the
        // open returns, before the stream is built (which can itself block,
        // skipping to the asset's offset), so the deadline can close it and a
        // provider that stalls does not keep this thread.
        queued.opening = true
        val descriptor = try {
            context.contentResolver.openAssetFileDescriptor(uri, "r", queued.cancel)
        } finally {
            queued.opening = false
        } ?: throw IOException("Shared image could not be opened")
        val bytes = descriptor.use {
            queued.descriptor = descriptor
            try {
                queued.cancel.throwIfCanceled()
                descriptor.createInputStream().use { it.readUpTo(MAX_IMAGE_BYTES) }
            } finally {
                queued.descriptor = null
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight)
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            ?: throw IOException("Shared image could not be decoded")
        // The QR reader takes ARGB_8888 only. A 16-bit or wide-gamut image decodes
        // to a half-float bitmap whatever the preferred config says, and would be
        // written back as one.
        val bitmap = if (decoded.config == Bitmap.Config.ARGB_8888) {
            decoded
        } else {
            decoded.copy(Bitmap.Config.ARGB_8888, false).also { decoded.recycle() }
                ?: throw IOException("Shared image could not be converted")
        }
        val file = File(imageDir().apply { mkdirs() }, "${UUID.randomUUID()}.png")
        try {
            val written = file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            if (!written) throw IOException("Shared image could not be written")
        } catch (failure: Throwable) {
            // Nothing else will: a partial file is this copy's to delete, and
            // it could hold a Gift Card QR.
            file.delete()
            throw failure
        } finally {
            bitmap.recycle()
        }
        return file.path
    }

    private fun imageDir() = File(File(context.cacheDir, IMAGE_DIR), instanceDir)

    /** The whole stream, or an exception once it exceeds [limit] bytes: the sender chooses the size. */
    private fun InputStream.readUpTo(limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = read(buffer)
            if (read < 0) return out.toByteArray()
            if (out.size() + read > limit) throw IOException("Shared image is over $limit bytes")
            out.write(buffer, 0, read)
        }
    }

    companion object {
        const val CHANNEL = "com.zcash.wallet/shared_payment"
        private const val IMAGE_DIR = "shared_payment"

        /** Memory bound only; Dart tells the user what it could not use. */
        private const val MAX_TEXT_LENGTH = 64 * 1024

        /** Images waiting for a copy. Shares are deliberate actions seconds apart; this only stops a runaway sender. */
        private const val MAX_PENDING = 4

        /** Well above any photo a share sheet sends; a decode needs the whole file in memory. */
        private const val MAX_IMAGE_BYTES = 24 * 1024 * 1024

        /** 2048 x 2048: a 16 MB bitmap, on which a QR code is still readable. */
        private const val MAX_IMAGE_PIXELS = 2048L * 2048L

        /** Well above a photo from a cloud-backed provider on a slow link. A copy past it is answered as unreadable and cut off. */
        private const val COPY_DEADLINE_MS = 15_000L

        /** Workers caught in a provider's open and not back yet, process-wide; see [writeOff]. */
        private const val MAX_STUCK_WORKERS = 2
        private val stuckWorkers = AtomicInteger()

        @VisibleForTesting
        internal val stuckWorkerCount: Int get() = stuckWorkers.get()

        /** One thread, with a queue the deadline can take an expired copy out of. */
        private fun newImageExecutor() = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS, LinkedBlockingQueue())

        /**
         * Once per process: a later activity must not wipe a copy an earlier
         * one is still writing for a Dart side that is about to read it.
         */
        private var cacheCleared = false

        /** The smallest power of two that brings a [width] x [height] image under [MAX_IMAGE_PIXELS]. */
        private fun sampleSizeFor(width: Int, height: Int): Int {
            var sampleSize = 1
            while (width.toLong() / sampleSize * (height.toLong() / sampleSize) > MAX_IMAGE_PIXELS) {
                sampleSize *= 2
            }
            return sampleSize
        }
    }
}
