package com.keplr.vizor

import android.app.Activity
import com.ledger.devicemanagement.DeviceManagementKitApi
import com.ledger.devicemanagement.api.DeviceOperationResult
import com.ledger.devicemanagement.api.command.getappandversion.AppAndVersion
import com.ledger.devicemanagement.api.connection.ConnectedDevice
import com.ledger.devicemanagement.api.connection.ConnectionResult
import com.ledger.devicemanagement.api.device.LedgerDevice
import com.ledger.devicemanagement.api.discovery.ConnectivityType
import com.ledger.devicemanagement.api.discovery.DiscoveryDevice
import com.ledger.devicemanagement.api.deviceaction.DeviceActionResult
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import kotlin.coroutines.Continuation
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.flow
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
    fun cancelledCurrentAppRetainsTheOperationSlotUntilCallbackDrains() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)
        val original = reply(handler, MethodCall("currentApp", null))

        assertEquals(1, sdk.appCommands)
        assertEquals("unavailable", reply(handler, MethodCall("currentApp", null)).error)
        reply(handler, MethodCall("cancelSigning", null))

        assertEquals("cancelled", original.error)
        assertEquals("unavailable", reply(handler, MethodCall("currentApp", null)).error)
        assertEquals(1, sdk.appCommands)

        sdk.completeApp()
        val fresh = reply(handler, MethodCall("currentApp", null))
        sdk.completeApp()

        assertEquals(mapOf("name" to "Zcash", "version" to "3.9.3"), fresh.value)
        assertEquals(2, sdk.appCommands)
        assertEquals(1, original.completions)
        handler.close()
    }

    @Test
    fun cancelledOpenAppDrainsBeforeDisconnecting() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)
        val original = reply(handler, MethodCall("openZcashApp", null))

        assertEquals(1, sdk.openActions)
        reply(handler, MethodCall("cancelSigning", null))
        val disconnect = reply(handler, MethodCall("disconnect", null))

        assertEquals("cancelled", original.error)
        assertEquals(0, disconnect.completions)
        assertTrue(sdk.connectionCalls.isEmpty())

        sdk.completeOpen()

        assertEquals(1, disconnect.completions)
        assertEquals(listOf("disconnect"), sdk.connectionCalls)
        assertEquals(0, sdk.appCommands)
        assertEquals(1, original.completions)
        handler.close()
    }

    @Test
    fun normalUfvkChunksComplete() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)
        sdk.responses.add(bytes(0, 3, 117, 0x90, 0))
        sdk.responses.add(bytes(102, 118, 0x90, 0))
        val ufvk = reply(handler, ufvkCall())
        assertEquals(listOf(listOf(0, 3, 117, 0x90, 0), listOf(102, 118, 0x90, 0)), ufvk.value)
        assertEquals(1, ufvk.completions)
        assertEquals(2, sdk.commands)
        handler.close()
    }

    @Test
    fun rejectedUfvkResponseKeepsUnsignedFlutterBytes() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)
        sdk.responses.add(bytes(0x69, 0x85))

        val ufvk = reply(handler, ufvkCall())

        assertEquals(listOf(listOf(0x69, 0x85)), ufvk.value)
        assertEquals(1, ufvk.completions)
        assertEquals(1, sdk.commands)
        handler.close()
    }

    @Test
    fun permissionDenialCompletesThePendingRequest() {
        val sdk = PendingLedgerSdk()
        var requested = false
        val handler = handler(
            sdk,
            hasPermission = { false },
            requestPermissions = { permissions, _ -> requested = permissions.isNotEmpty() },
        )
        val request = reply(handler, MethodCall("requestPermissions", null))
        assertTrue(requested)
        assertEquals(0, request.completions)

        assertTrue(handler.onRequestPermissionsResult(0x4c45, intArrayOf(-1)))
        assertEquals(false, request.value)
        assertEquals(1, request.completions)
        handler.close()
    }

    @Test
    fun revokedPermissionBlocksAnExistingConnectionBeforeSdkUse() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk, hasPermission = { false })

        val app = reply(handler, MethodCall("currentApp", null))

        assertEquals("permission_denied", app.error)
        assertEquals(0, sdk.commands)
        handler.close()
    }

    @Test
    fun disconnectFinishesBeforeReconnectStarts() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk, discovered = mapOf(sdk.discovery.uid to sdk.discovery))

        val disconnect = reply(handler, MethodCall("disconnect", null))
        val connect = reply(
            handler,
            MethodCall("connect", mapOf("deviceId" to sdk.discovery.uid)),
        )

        assertNull(disconnect.error)
        assertNull(connect.error)
        assertEquals(listOf("disconnect", "connect"), sdk.connectionCalls)
        handler.close()
    }

    @Test
    fun disconnectAndReconnectWaitForCancelledApduCallbackToDrain() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk, discovered = mapOf(sdk.discovery.uid to sdk.discovery))
        val original = reply(handler, ufvkCall())

        val disconnect = reply(handler, MethodCall("disconnect", null))
        val reconnect = reply(
            handler,
            MethodCall("connect", mapOf("deviceId" to sdk.discovery.uid)),
        )

        assertEquals("cancelled", original.error)
        assertEquals(0, disconnect.completions)
        assertEquals(0, reconnect.completions)
        assertTrue(sdk.connectionCalls.isEmpty())

        // The SDK callback ignores coroutine cancellation. Neither teardown
        // nor reuse may enter DMK until that callback actually returns.
        sdk.complete(bytes(0, 3, 117, 0x90, 0))

        assertEquals(1, original.completions)
        assertEquals(1, disconnect.completions)
        assertEquals(1, reconnect.completions)
        assertEquals(listOf("disconnect", "connect"), sdk.connectionCalls)
        handler.close()
    }

    @Test
    fun connectClosesExistingDeviceBeforeOpeningSelectedDevice() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk, discovered = mapOf(sdk.discovery.uid to sdk.discovery))

        val connect = reply(
            handler,
            MethodCall("connect", mapOf("deviceId" to sdk.discovery.uid)),
        )

        assertNull(connect.error)
        assertEquals(1, connect.completions)
        assertEquals(listOf("disconnect", "connect"), sdk.connectionCalls)
        handler.close()
    }

    @Test
    fun nullableDeviceNameFailureRequestsGattTeardownBeforeReuse() {
        val sdk = PendingLedgerSdk().apply { connectError = NullPointerException("name") }
        val handler = handler(sdk, discovered = mapOf(sdk.discovery.uid to sdk.discovery))

        val connect = reply(
            handler,
            MethodCall("connect", mapOf("deviceId" to sdk.discovery.uid)),
        )

        assertEquals("disconnected", connect.error)
        assertEquals(listOf("disconnect", "connect", "disconnect"), sdk.connectionCalls)
        handler.close()
    }

    @Test
    fun closeDisconnectsTheGattSessionOnce() {
        val sdk = PendingLedgerSdk()
        val handler = handler(sdk)

        handler.close()

        assertEquals(listOf("disconnect"), sdk.connectionCalls)
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

    @Test
    fun closeDrainsPendingConnectAndDisconnectsItsLateSession() {
        val sdk = PendingLedgerSdk().apply { connectPending = true }
        val lifecycle = LedgerConnectionLifecycle(sdk.device)
        val handler = handler(
            sdk,
            discovered = mapOf(sdk.discovery.uid to sdk.discovery),
            connectionLifecycle = lifecycle,
        )
        val connect = reply(
            handler,
            MethodCall("connect", mapOf("deviceId" to sdk.discovery.uid)),
        )

        assertEquals(listOf("disconnect", "connect"), sdk.connectionCalls)
        handler.close()
        assertEquals(0, connect.completions)

        sdk.completeConnect()

        assertEquals("cancelled", connect.error)
        assertEquals(1, connect.completions)
        assertEquals(listOf("disconnect", "connect", "disconnect"), sdk.connectionCalls)
        assertFalse(lifecycle.isTeardownPending)
    }

    @Test
    fun replacementHandlerCannotUseSharedSessionUntilCloseDrains() {
        val sdk = PendingLedgerSdk()
        val lifecycle = LedgerConnectionLifecycle(sdk.device)
        val oldHandler = handler(sdk, connectionLifecycle = lifecycle)
        val pending = reply(oldHandler, MethodCall("currentApp", null))
        oldHandler.close()
        val replacement = handler(
            sdk,
            discovered = mapOf(sdk.discovery.uid to sdk.discovery),
            connectionLifecycle = lifecycle,
        )

        val blocked = reply(
            replacement,
            MethodCall("connect", mapOf("deviceId" to sdk.discovery.uid)),
        )
        assertEquals("unavailable", blocked.error)
        assertEquals(listOf<String>(), sdk.connectionCalls)

        sdk.completeApp()
        assertEquals("cancelled", pending.error)
        assertEquals(listOf("disconnect"), sdk.connectionCalls)

        val reconnect = reply(
            replacement,
            MethodCall("connect", mapOf("deviceId" to sdk.discovery.uid)),
        )
        assertNull(reconnect.error)
        assertEquals(1, reconnect.completions)
        assertEquals(listOf("disconnect", "connect"), sdk.connectionCalls)
        replacement.close()
    }

    private fun handler(
        sdk: PendingLedgerSdk,
        hasPermission: (String) -> Boolean = { true },
        requestPermissions: (Array<String>, Int) -> Unit = { _, _ -> },
        discovered: Map<String, DiscoveryDevice> = emptyMap(),
        connectionLifecycle: LedgerConnectionLifecycle = LedgerConnectionLifecycle(sdk.device),
    ) = LedgerMobileHandler(
        activity = mock(Activity::class.java),
        dmk = sdk.api,
        connectionLifecycle = connectionLifecycle,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        hasPermission = hasPermission,
        requestPermissions = requestPermissions,
        isGattConnected = { false },
        initialDiscoveredDevices = discovered,
        initialConnectedDevice = sdk.device,
    )

    private fun reply(handler: LedgerMobileHandler, call: MethodCall): Reply =
        Reply().also { handler.handle(call, it) }

    private fun command(p1: Int = 0) = mapOf(
        "cla" to 0xe0, "ins" to 0x50, "p1" to p1, "p2" to 0, "data" to emptyList<Int>(),
    )
    private fun ufvkCall() = MethodCall("exchangeUfvk", mapOf(
        "first" to command(), "continuation" to command(0x80),
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
        var appCommands = 0
        var openActions = 0
        var connectPending = false
        val connectionCalls = mutableListOf<String>()
        var connectError: Exception? = null
        val responses = ArrayDeque<ByteArray>()
        private var pending: Continuation<DeviceOperationResult<ByteArray>>? = null
        private var pendingApp: Continuation<DeviceOperationResult<AppAndVersion>>? = null
        private var pendingOpen: Continuation<DeviceActionResult<Unit>>? = null
        private var pendingConnect: Continuation<ConnectionResult>? = null
        val device = ConnectedDevice(
            "test-ledger", "Test Ledger", LedgerDevice.NanoX, ConnectivityType.Bluetooth(-50),
        )
        val discovery = DiscoveryDevice(
            device.uid, device.name, device.ledgerDevice, device.connectivityType,
        )
        private var connected = true
        val api = Proxy.newProxyInstance(
            DeviceManagementKitApi::class.java.classLoader,
            arrayOf(DeviceManagementKitApi::class.java),
        ) { _, method, args ->
            when (method.name) {
                "getConnectedDevices" -> if (connected) listOf(device) else emptyList<ConnectedDevice>()
                "stopDiscoveringDevices" -> Unit
                "disconnectDevice" -> {
                    connectionCalls += "disconnect"
                    connected = false
                    Unit
                }
                "connectDevice" -> {
                    connectionCalls += "connect"
                    connectError?.let { throw it }
                    if (connectPending) {
                        check(pendingConnect == null)
                        @Suppress("UNCHECKED_CAST")
                        val continuation = args.last() as Continuation<ConnectionResult>
                        pendingConnect = continuation
                        COROUTINE_SUSPENDED
                    } else {
                        connected = true
                        ConnectionResult.Connected(device)
                    }
                }
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
                "executeCommand" -> {
                    appCommands++
                    check(pendingApp == null)
                    @Suppress("UNCHECKED_CAST")
                    val continuation = args.last() as Continuation<DeviceOperationResult<AppAndVersion>>
                    pendingApp = continuation
                    COROUTINE_SUSPENDED
                }
                "executeDeviceAction" -> flow {
                    openActions++
                    val terminal = suspendCoroutine<DeviceActionResult<Unit>> { continuation ->
                        check(pendingOpen == null)
                        pendingOpen = continuation
                    }
                    emit(terminal)
                }
                else -> error("Unexpected SDK call: ${method.name}")
            }
        } as DeviceManagementKitApi

        fun complete(response: ByteArray) {
            val continuation = checkNotNull(pending)
            pending = null
            continuation.resume(DeviceOperationResult.Success(response))
        }

        fun completeApp() {
            val continuation = checkNotNull(pendingApp)
            pendingApp = null
            continuation.resume(DeviceOperationResult.Success(AppAndVersion("Zcash", "3.9.3")))
        }

        fun completeOpen() {
            val continuation = checkNotNull(pendingOpen)
            pendingOpen = null
            continuation.resume(DeviceActionResult.Success(Unit))
        }

        fun completeConnect() {
            val continuation = checkNotNull(pendingConnect)
            pendingConnect = null
            connected = true
            continuation.resume(ConnectionResult.Connected(device))
        }
    }

    companion object {
        private fun bytes(vararg values: Int) = values.map { it.toByte() }.toByteArray()
    }
}
