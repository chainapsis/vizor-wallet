package com.keplr.vizor

import android.app.Activity
import com.ledger.devicemanagement.DeviceManagementKitApi
import com.ledger.devicemanagement.api.DeviceOperationResult
import com.ledger.devicemanagement.api.connection.ConnectedDevice
import com.ledger.devicemanagement.api.device.LedgerDevice
import com.ledger.devicemanagement.api.discovery.ConnectivityType
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import kotlin.coroutines.Continuation
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mock

class LedgerMobileHandlerTest {
    @Test
    fun cancelledUfvkDrainsWithoutContinuationOrDuplicateResult() {
        for (lateResponse in listOf(bytes(0, 3, 117, 0x90, 0), bytes(0x69, 0x85))) {
            val sdk = PendingLedgerSdk()
            val handler = handler(sdk)
            val original = reply(handler, ufvkCall())
            assertEquals(1, sdk.commands)
            assertEquals(0, original.completions)

            val cancelled = reply(handler, MethodCall("cancelSigning", null))
            assertEquals(1, cancelled.completions)
            assertEquals("cancelled", original.error)
            assertEquals(1, original.completions)
            assertEquals("unavailable", reply(handler, ufvkCall()).error)
            assertEquals("unavailable", reply(handler, signingCall()).error)
            assertEquals(1, sdk.commands)

            // This SDK double intentionally does not react to Job cancellation.
            sdk.complete(lateResponse)
            assertEquals(1, original.completions)
            assertEquals(1, sdk.commands)
            sdk.responses.add(bytes(0, 1, 117, 0x90, 0))
            val fresh = reply(handler, ufvkCall())
            assertNull(fresh.error)
            assertEquals(1, fresh.completions)
            assertEquals(listOf(listOf(0, 1, 117, 0x90, 0)), fresh.value)
            assertEquals(2, sdk.commands)
            handler.close()
        }
    }

    @Test
    fun normalUfvkChunksAndSigningStillComplete() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)
        sdk.responses.add(bytes(0, 3, 117, 0x90, 0))
        sdk.responses.add(bytes(102, 118, 0x90, 0))
        val ufvk = reply(handler, ufvkCall())
        assertEquals(listOf(listOf(0, 3, 117, 0x90, 0), listOf(102, 118, 0x90, 0)), ufvk.value)
        assertEquals(1, ufvk.completions)
        sdk.responses.add(bytes(0x90, 0))
        sdk.responses.add(bytes(0x69, 0x85))
        val signing = reply(handler, signingCall())
        assertEquals(listOf(listOf(0x90, 0), listOf(0x69, 0x85)), signing.value)
        assertEquals(1, signing.completions)
        assertEquals(4, sdk.commands)
        handler.close()
    }

    @Test
    fun cancelledSigningAlsoBlocksUfvkUntilItsResponseDrains() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)
        val original = reply(handler, signingCall())
        reply(handler, MethodCall("cancelSigning", null))
        assertEquals("cancelled", original.error)
        assertEquals("unavailable", reply(handler, ufvkCall()).error)
        sdk.complete(bytes(0x90, 0))
        assertEquals(1, sdk.commands)
        assertEquals(1, original.completions)
        sdk.responses.add(bytes(0, 1, 117, 0x90, 0))
        assertNull(reply(handler, ufvkCall()).error)
        handler.close()
    }

    @Test
    fun closeCompletesPendingUfvkOnlyOnce() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)
        val original = reply(handler, ufvkCall())
        handler.close()
        assertEquals("cancelled", original.error)
        sdk.complete(bytes(0, 3, 117, 0x90, 0))
        assertEquals(1, original.completions)
        assertEquals(1, sdk.commands)
    }

    private fun handler(sdk: PendingLedgerSdk) = LedgerMobileHandler(
        mock(Activity::class.java), sdk.api, CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
    )

    private fun reply(handler: LedgerMobileHandler, call: MethodCall): Reply =
        Reply().also { handler.handle(call, it) }

    private fun command(p1: Int = 0) = mapOf(
        "cla" to 0xe0, "ins" to 0x50, "p1" to p1, "p2" to 0, "data" to emptyList<Int>(),
    )
    private fun ufvkCall() = MethodCall("exchangeUfvk", mapOf(
        "first" to command(), "continuation" to command(0x80),
    ))
    private fun signingCall() = MethodCall("exchangeApdus", mapOf(
        "commands" to listOf(command(), command(1)),
    ))

    private class Reply : MethodChannel.Result {
        var completions = 0
        var value: Any? = null
        var error: String? = null
        override fun success(result: Any?) { completions++; value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            completions++
            error = errorCode
        }
        override fun notImplemented() { fail("Unexpected method") }
    }

    // Test the real handler against the official DMK interface without Android
    // radio, a Flutter engine, a Ledger, or arbitrary coroutine delays.
    private class PendingLedgerSdk {
        var commands = 0
        val responses = ArrayDeque<ByteArray>()
        private var pending: Continuation<DeviceOperationResult<ByteArray>>? = null
        private val device = ConnectedDevice(
            "test-ledger", "Test Ledger", LedgerDevice.NanoX, ConnectivityType.Bluetooth(-50),
        )
        val api = Proxy.newProxyInstance(
            DeviceManagementKitApi::class.java.classLoader,
            arrayOf(DeviceManagementKitApi::class.java),
        ) { _, method, args ->
            when (method.name) {
                "getConnectedDevices" -> listOf(device)
                "stopDiscoveringDevices" -> Unit
                "sendApdu" -> {
                    commands++
                    if (responses.isNotEmpty()) {
                        DeviceOperationResult.Success(responses.removeFirst())
                    } else {
                        check(pending == null)
                        @Suppress("UNCHECKED_CAST")
                        val continuation = args.last() as Continuation<DeviceOperationResult<ByteArray>>
                        pending = continuation
                        COROUTINE_SUSPENDED
                    }
                }
                else -> error("Unexpected SDK call: ${method.name}")
            }
        } as DeviceManagementKitApi

        fun complete(response: ByteArray) {
            val continuation = checkNotNull(pending)
            pending = null
            continuation.resume(DeviceOperationResult.Success(response))
        }
    }

    companion object {
        private fun bytes(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    }
}
