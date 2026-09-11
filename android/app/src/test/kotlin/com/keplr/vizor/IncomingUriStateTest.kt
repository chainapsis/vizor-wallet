package com.keplr.vizor

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Parcel
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 33], manifest = Config.NONE)
class IncomingUriStateTest {
    private val bitcoin = "bitcoin:1FsSia9rv4NeEwvJ2GvXrX7LyxYspbN2mo?amount=0.1&label=Alice"
    private val litecoin = "litecoin:LT2KVaAy1ppRuxRgrS5RNU3vBsy7RibPeA?amount=1"
    private val ethereum = "ethereum:0x1111111111111111111111111111111111111111@8453?value=1e15"
    private val erc20 = "ethereum:pay-0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913@8453/transfer?address=0x1111111111111111111111111111111111111111&uint256=25000001"
    private val solana = "solana:mvines9iiHiQTysrwkJjGf2gb9Ex9jXJX8ns3qwf2kN?amount=1&label=Alice"
    private val spl = "$solana&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    private val zcash = "zcash:urecipient?amount=1"
    private val transfers get() = listOf(bitcoin, litecoin, ethereum, erc20, solana, spl, zcash)
    private val secretLinks get() = listOf(
        "https://${BuildConfig.VIZOR_DEEPLINK_HOST}/payment-links/open#claim-secret",
        "solana:https://merchant.example/private-token",
        "solana:https%3A%2F%2Fmerchant.example%2Fpay%3Ftoken%3Dprivate-token",
        "$bitcoin&r=https%3A%2F%2Fmerchant.example%2Fprivate-token",
        "$ethereum#private-token",
    )

    @Test fun pendingColdStartTransfersSurviveSerializedStateAndReachDartOnce() {
        for (uri in transfers) {
            val original = MainActivity()
            launch(original, uri)
            val restored = restore(save(original))
            launch(restored, uri)
            deliver(restored, listOf(uri))
        }
    }

    @Test fun pendingWarmLinksSurviveTogetherAndKeepTheirOrder() {
        val original = MainActivity()
        launch(original, bitcoin)
        transfers.drop(1).forEach { capture(original, it) }
        val restored = restore(save(original))
        launch(restored, bitcoin)
        deliver(restored, transfers)
    }

    @Test fun deliveredLinksAreNotReplayedByTaskRestorationButCanBeRetapped() {
        val original = MainActivity()
        launch(original, bitcoin)
        capture(original, solana)
        deliver(original, listOf(bitcoin, solana))
        val state = save(original)
        for (uri in listOf(bitcoin, solana)) {
            val restored = restore(state)
            launch(restored, uri)
            val channel = ready(restored)
            invoke(restored, "flushPendingIncomingUris")
            verifyNoInteractions(channel)
            capture(restored, uri)
            verify(channel).invokeMethod("onUris", listOf(uri))
        }
    }

    @Test fun secretLinksStayInMemoryAndAreNotSavedOrReplayed() {
        for (uri in secretLinks) {
            val original = MainActivity()
            launch(original, uri)
            val state = save(original)
            assertEquals(emptyList<String>(), state.getStringArrayList("vizor.pendingIncomingUris"))
            // Saving does not prevent delivery while the original activity lives.
            deliver(original, listOf(uri))
            val restored = restore(state)
            launch(restored, uri)
            val channel = ready(restored)
            invoke(restored, "flushPendingIncomingUris")
            verifyNoInteractions(channel)
        }
    }

    @Test fun restoreAlsoFiltersSecretLinksFromSavedQueue() {
        val state = Bundle().apply {
            putStringArrayList("vizor.pendingIncomingUris", ArrayList(transfers + secretLinks))
        }
        deliver(restore(state), transfers)
    }

    @Test fun transferSchemesAreCaseInsensitiveAndUnknownParametersStayMemoryOnly() {
        for (uri in transfers) {
            val uppercase = uri.substringBefore(':').uppercase() + ":" + uri.substringAfter(':')
            val original = MainActivity()
            launch(original, uppercase)
            deliver(restore(save(original)), listOf(uppercase))
        }
        for (uri in listOf("$solana&request=https%3A%2F%2Fmerchant.example", "$ethereum&secret=token")) {
            val original = MainActivity()
            launch(original, uri)
            assertEquals(emptyList<String>(), save(original).getStringArrayList("vizor.pendingIncomingUris"))
        }
    }

    private fun launch(activity: MainActivity, uri: String) =
        invoke(activity, "captureLaunchIncomingUri", Intent(Intent.ACTION_VIEW, Uri.parse(uri)))

    private fun capture(activity: MainActivity, uri: String) =
        invoke(activity, "captureIncomingUri", Intent(Intent.ACTION_VIEW, Uri.parse(uri)), false)

    private fun save(activity: MainActivity): Bundle {
        val state = Bundle()
        invoke(activity, "saveIncomingUriState", state)
        // Exercise the system's serialized representation, not a shared Bundle.
        val parcel = Parcel.obtain()
        return try {
            parcel.writeBundle(state)
            parcel.setDataPosition(0)
            parcel.readBundle(MainActivity::class.java.classLoader)!!
        } finally {
            parcel.recycle()
        }
    }

    private fun restore(state: Bundle) = MainActivity().also {
        invoke(it, "restoreIncomingUriState", state)
    }

    private fun ready(activity: MainActivity): MethodChannel {
        val channel = mock(MethodChannel::class.java)
        for ((name, value) in listOf("incomingUriChannel" to channel, "incomingUriDartReady" to true)) {
            MainActivity::class.java.getDeclaredField(name).apply { isAccessible = true }.set(activity, value)
        }
        return channel
    }

    private fun deliver(activity: MainActivity, expected: List<String>) {
        val channel = ready(activity)
        invoke(activity, "flushPendingIncomingUris")
        invoke(activity, "flushPendingIncomingUris")
        verify(channel, times(1)).invokeMethod("onUris", expected)
        verifyNoMoreInteractions(channel)
    }

    private fun invoke(activity: MainActivity, name: String, vararg args: Any) {
        MainActivity::class.java.declaredMethods.single { it.name == name }.apply {
            isAccessible = true
        }.invoke(activity, *args)
    }
}
