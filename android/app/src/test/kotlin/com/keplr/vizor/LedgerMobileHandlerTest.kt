package com.keplr.vizor

import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowLog
import io.flutter.plugin.common.EventChannel
import com.ledger.devicemanagement.api.command.Command
import com.ledger.devicemanagement.api.command.getappandversion.AppAndVersion
import com.ledger.devicemanagement.api.deviceaction.DeviceAction
import com.ledger.devicemanagement.api.deviceaction.DeviceActionResult
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import com.ledger.devicemanagement.api.DeviceOperationResult
import com.ledger.devicemanagement.api.DeviceOperationFailureReason
import com.ledger.devicemanagement.api.apdu.ApduPayload
import com.ledger.devicemanagement.DeviceManagementKitApi
import com.ledger.devicemanagement.api.connection.ConnectedDevice
import com.ledger.devicemanagement.api.connection.ConnectionResult
import com.ledger.devicemanagement.api.device.LedgerDevice
import com.ledger.devicemanagement.api.discovery.ConnectivityType
import com.ledger.devicemanagement.api.discovery.DiscoveryDevice
import com.ledger.devicemanagement.api.discovery.DiscoveryResult
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class LedgerMobileHandlerTest {
    private val dispatcher = StandardTestDispatcher()
    private val dmk = mock(DeviceManagementKitApi::class.java)
    private lateinit var handler: LedgerMobileHandler
    private val saved = DiscoveryDevice("saved-id", "Ledger", LedgerDevice.NanoX, ConnectivityType.Bluetooth(-50))
    private val connected = mock(ConnectedDevice::class.java)

    @Before fun setUp() {
        Dispatchers.setMain(dispatcher)
        handler = LedgerMobileHandler(mock(Activity::class.java), dmk)
    }

    @After fun tearDown() {
        handler.close()
        dispatcher.scheduler.runCurrent()
        Dispatchers.resetMain()
    }

    private class Result : MethodChannel.Result {
        var completions = 0
        var error: String? = null
        var value: Any? = null
        override fun success(result: Any?) { completions++; value = result }
        override fun error(code: String, message: String?, details: Any?) {
            completions++
            error = code
        }
        override fun notImplemented() { fail("Unexpected method") }
    }

    private fun call(method: String, id: String = saved.uid): Result = Result().also {
        handler.handle(MethodCall(method, mapOf("deviceId" to id)), it)
    }

    @Test fun freshHandlerRediscoversOnlyTheSavedBluetoothDevice() = runTest(dispatcher) {
        val other = saved.copy(uid = "another-id")
        val usb = saved.copy(connectivityType = ConnectivityType.Usb)
        `when`(dmk.startDiscoveringDevices()).thenReturn(flowOf(
            DiscoveryResult.DevicesDiscovered(listOf(other, usb)),
            DiscoveryResult.DevicesDiscovered(listOf(saved)),
        ))
        `when`(dmk.connectDevice(saved)).thenReturn(ConnectionResult.Connected(connected))
        val result = call("connect")
        runCurrent()
        assertEquals(1, result.completions)
        assertNull(result.error)
        verify(dmk).connectDevice(saved)
        verify(dmk, never()).connectDevice(other)
        verify(dmk, never()).connectDevice(usb)
        verify(dmk, atLeastOnce()).stopDiscoveringDevices()

        // A same-session reconnect retains the fast path without another scan.
        call("disconnect")
        runCurrent()
        val retry = call("connect")
        runCurrent()
        assertNull(retry.error)
        assertEquals(1, retry.completions)
        verify(dmk, times(1)).startDiscoveringDevices()
    }

    @Test fun absentSavedDeviceTimesOutAndStopsDiscovery() = runTest(dispatcher) {
        var stopped = false
        `when`(dmk.startDiscoveringDevices()).thenReturn(flow {
            try {
                emit(DiscoveryResult.DevicesDiscovered(listOf(saved.copy(uid = "other"))))
                awaitCancellation()
            } finally { stopped = true }
        })
        val result = call("connect")
        runCurrent()
        advanceTimeBy(15_000)
        runCurrent()
        assertEquals("disconnected", result.error)
        assertEquals(1, result.completions)
        assertTrue(stopped)
        verify(dmk, never()).connectDevice(saved)
    }

    @Test fun discoveryFailuresPreserveTheirActionableErrorCodes() = runTest(dispatcher) {
        val cases = listOf(
            DiscoveryResult.Failure.BluetoothDisabled to "bluetooth_off",
            DiscoveryResult.Failure.BluetoothPermissionNotGranted to "permission_denied",
            DiscoveryResult.Failure.LocationDisabled to "permission_denied",
            DiscoveryResult.Failure.BluetoothBleNotSupported to "unavailable",
            DiscoveryResult.Failure.Unknown("failure") to "unavailable",
            DiscoveryResult.Ended to "disconnected",
        )
        for ((failure, code) in cases) {
            `when`(dmk.startDiscoveringDevices()).thenReturn(flowOf(failure))
            val result = call("connect")
            runCurrent()
            assertEquals(code, result.error)
            assertEquals(1, result.completions)
        }
    }

    @Test fun cancellationDisconnectAndCloseStopRediscoveryWithoutConnecting() = runTest(dispatcher) {
        for (action in listOf("cancelSigning", "disconnect", "close")) {
            var stopped = false
            `when`(dmk.startDiscoveringDevices()).thenReturn(flow {
                try { awaitCancellation() } finally { stopped = true }
            })
            val result = call("connect")
            runCurrent()
            if (action == "close") handler.close() else call(action)
            runCurrent()
            advanceTimeBy(15_000)
            runCurrent()
            assertEquals("cancelled", result.error)
            assertEquals(1, result.completions)
            assertTrue(stopped)
        }
        verify(dmk, never()).connectDevice(saved)
    }

    @Test fun concurrentConnectAndDiscoveryCannotReplacePendingReconnect() = runTest(dispatcher) {
        `when`(dmk.startDiscoveringDevices()).thenReturn(flow { awaitCancellation() })
        val first = call("connect")
        runCurrent()
        val second = call("connect", "other")
        val discovery = call("startDiscovery")
        assertEquals("unavailable", second.error)
        assertEquals("unavailable", discovery.error)
        assertEquals(0, first.completions)
        call("cancelSigning")
        runCurrent()
        assertEquals("cancelled", first.error)
        verify(dmk, times(1)).startDiscoveringDevices()
    }
    @Test fun cancelBeforeCoroutineStartsAllowsRetry() = runTest(dispatcher) {
        `when`(dmk.startDiscoveringDevices()).thenReturn(flowOf(DiscoveryResult.Ended))
        val first = call("connect")
        call("cancelSigning")
        runCurrent()
        val second = call("connect")
        runCurrent()
        assertEquals("cancelled", first.error)
        assertEquals(1, first.completions)
        assertEquals("disconnected", second.error)
        assertEquals(1, second.completions)
    }

    @Test fun lateConnectionAfterCancellationIsDisconnectedAndCannotSucceed() = runTest(dispatcher) {
        var pending: Continuation<ConnectionResult>? = null
        `when`(dmk.startDiscoveringDevices()).thenReturn(flowOf(
            DiscoveryResult.DevicesDiscovered(listOf(saved)),
        ))
        // Emulate a native callback that does not cooperate with cancellation.
        val sdk = object : DeviceManagementKitApi by dmk {
            override suspend fun connectDevice(device: DiscoveryDevice): ConnectionResult =
                suspendCoroutine { pending = it }
        }
        handler.close()
        handler = LedgerMobileHandler(mock(Activity::class.java), sdk)
        val result = call("connect")
        runCurrent()
        assertNotNull(pending)
        call("cancelSigning")
        val overlapping = call("connect")
        assertEquals("unavailable", overlapping.error)
        pending!!.resume(ConnectionResult.Connected(connected))
        runCurrent()
        assertEquals("cancelled", result.error)
        assertEquals(1, result.completions)
        verify(dmk).disconnectDevice(connected)
    }

    private fun exchangeCall(method: String = "exchangeUfvk"): Result {
        val command = mapOf("cla" to 0x85, "ins" to 0x10, "p1" to 0, "p2" to 0, "data" to emptyList<Int>())
        val args = if (method == "exchangeUfvk") mapOf("first" to command, "continuation" to command)
            else mapOf("commands" to listOf(command, command))
        return Result().also { handler.handle(MethodCall(method, args), it) }
    }

    private fun useExchange(block: suspend (ApduPayload) -> DeviceOperationResult<ByteArray>) {
        handler.close()
        `when`(connected.uid).thenReturn("connected-id")
        `when`(dmk.getConnectedDevices()).thenReturn(listOf(connected))
        val sdk = object : DeviceManagementKitApi by dmk {
            override suspend fun sendApdu(uid: String, apdu: ApduPayload): DeviceOperationResult<ByteArray> = block(apdu)
        }
        handler = LedgerMobileHandler(mock(Activity::class.java), sdk)
    }

    private fun signingCommand(size: Int) = mapOf(
        "cla" to 0xe0, "ins" to 0x58, "p1" to 0x80, "p2" to 0,
        "data" to ByteArray(size) { it.toByte() },
    )

    @Test fun signingPayloadBoundariesPreserveOneApduAndResponsePerCommand() = runTest(dispatcher) {
        val sizes = listOf(0, 254, 255)
        val sent = mutableListOf<ByteArray>()
        useExchange { payload ->
            // Exercise the actual SDK payload, as its transport loop does.
            sent += payload.rawApdu()
            assertFalse("One Rust command must not produce extra APDUs", payload.containsOtherData())
            DeviceOperationResult.Success(byteArrayOf(0x90.toByte(), 0))
        }
        val result = Result()
        handler.handle(MethodCall("exchangeApdus", mapOf("commands" to sizes.map(::signingCommand))), result)
        runCurrent()
        assertNull(result.error)
        assertEquals(1, result.completions)
        assertEquals(sizes.size, sent.size)
        for ((index, size) in sizes.withIndex()) {
            assertArrayEquals(
                byteArrayOf(0xe0.toByte(), 0x58, 0x80.toByte(), 0, size.toByte()) + ByteArray(size) { it.toByte() },
                sent[index],
            )
        }
        assertEquals(List(sizes.size) { listOf(0x90, 0) }, result.value)
    }

    @Test fun oversizedSigningCommandIsRejectedBeforeAnySdkSend() = runTest(dispatcher) {
        var sends = 0
        useExchange { sends++; DeviceOperationResult.Success(byteArrayOf(0x90.toByte(), 0)) }
        val result = Result()
        handler.handle(MethodCall("exchangeApdus", mapOf(
            "commands" to listOf(signingCommand(254), signingCommand(256)),
        )), result)
        runCurrent()
        assertEquals("unavailable", result.error)
        assertEquals(1, result.completions)
        assertEquals(0, sends)
    }

    @Test fun fullSizeSigningStatusFailureStopsBeforeNextCommand() = runTest(dispatcher) {
        var sends = 0
        useExchange { payload ->
            sends++
            assertEquals(260, payload.rawApdu().size)
            assertFalse(payload.containsOtherData())
            DeviceOperationResult.Success(byteArrayOf(0x69, 0x85.toByte()))
        }
        val result = Result()
        handler.handle(MethodCall("exchangeApdus", mapOf(
            "commands" to listOf(signingCommand(255), signingCommand(0)),
        )), result)
        runCurrent()
        assertNull(result.error)
        assertEquals(listOf(listOf(0x69, 0x85)), result.value)
        assertEquals(1, sends)
        assertEquals(1, result.completions)
    }

    @Test fun ufvkCancellationDisconnectAndCloseCancelThePendingChannelOnce() = runTest(dispatcher) {
        for (action in listOf("cancelSigning", "disconnect", "close")) {
            var stopped = false
            useExchange { try { awaitCancellation() } finally { stopped = true } }
            val result = exchangeCall()
            runCurrent()
            if (action == "close") handler.close() else call(action)
            runCurrent()
            assertTrue(stopped)
            assertEquals("cancelled", result.error)
            assertEquals(1, result.completions)
        }
    }

    @Test fun cancellingBeforeExchangeDispatchReleasesSlotForBothKinds() = runTest(dispatcher) {
        for (method in listOf("exchangeUfvk", "exchangeApdus")) {
            var sends = 0
            useExchange { sends++; DeviceOperationResult.Success(byteArrayOf(0x90.toByte(), 0)) }
            val cancelled = exchangeCall(method)
            call("cancelSigning")
            runCurrent()
            assertEquals(0, sends)
            assertEquals("cancelled", cancelled.error)
            assertEquals(1, cancelled.completions)
            val retry = exchangeCall(method)
            runCurrent()
            assertNull(retry.error)
            assertEquals(1, retry.completions)
        }
    }

    @Test fun lateUfvkReplyCannotCompleteOrContinueAndBlocksOverlapUntilDrained() = runTest(dispatcher) {
        var pending: Continuation<DeviceOperationResult<ByteArray>>? = null
        var sends = 0
        useExchange {
            sends++
            suspendCoroutine { pending = it }
        }
        val first = exchangeCall()
        runCurrent()
        assertNotNull(pending)
        assertEquals("unavailable", exchangeCall().error)
        assertEquals("unavailable", exchangeCall("exchangeApdus").error)
        call("cancelSigning")
        assertEquals("unavailable", call("connect").error)
        assertEquals("unavailable", call("startDiscovery").error)
        assertEquals("unavailable", exchangeCall().error)
        // The payload length requires a continuation if the stale reply is accepted.
        pending!!.resume(DeviceOperationResult.Success(byteArrayOf(0, 4, 0x90.toByte(), 0)))
        runCurrent()
        assertEquals(1, sends)
        assertEquals("cancelled", first.error)
        assertEquals(1, first.completions)
        val retry = exchangeCall()
        runCurrent()
        pending!!.resume(DeviceOperationResult.Success(byteArrayOf(0x90.toByte(), 0)))
        runCurrent()
        assertEquals(2, sends)
        assertNull(retry.error)
        assertEquals(1, retry.completions)
    }

    @Test fun cancellationDuringUfvkContinuationStopsFurtherChunks() = runTest(dispatcher) {
        var sends = 0
        var stopped = false
        useExchange {
            sends++
            if (sends == 1) DeviceOperationResult.Success(byteArrayOf(0, 4, 0x90.toByte(), 0))
            else try { awaitCancellation() } finally { stopped = true }
        }
        val result = exchangeCall()
        runCurrent()
        assertEquals(2, sends)
        call("cancelSigning")
        runCurrent()
        assertTrue(stopped)
        assertEquals(2, sends)
        assertEquals("cancelled", result.error)
        assertEquals(1, result.completions)
    }

    @Test fun ufvkChunksAndDeviceErrorsPreserveTheirResponses() = runTest(dispatcher) {
        var sends = 0
        useExchange {
            sends++
            DeviceOperationResult.Success(if (sends == 1) byteArrayOf(0, 2, 0x90.toByte(), 0)
                else byteArrayOf(1, 2, 0x90.toByte(), 0))
        }
        val result = exchangeCall()
        runCurrent()
        assertEquals(listOf(listOf(0, 2, 144, 0), listOf(1, 2, 144, 0)), result.value)
        assertEquals(1, result.completions)
        useExchange { DeviceOperationResult.Failure(DeviceOperationFailureReason.DeviceLocked) }
        val failure = exchangeCall()
        runCurrent()
        assertEquals("locked", failure.error)
        assertEquals(1, failure.completions)
    }

    @Test fun thrownSdkErrorReleasesExchangeSlotAndCompletesChannel() = runTest(dispatcher) {
        var failOnce = true
        useExchange {
            if (failOnce) { failOnce = false; throw IllegalStateException("SDK failure") }
            DeviceOperationResult.Success(byteArrayOf(0x90.toByte(), 0))
        }
        val result = exchangeCall()
        runCurrent()
        assertEquals("unavailable", result.error)
        assertEquals(1, result.completions)
        val diagnostics = ShadowLog.getLogsForTag("VizorLedger").joinToString("\n") { it.msg }
        assertTrue(diagnostics.contains("exception stage=sendApdu apdu=1"))
        assertTrue(diagnostics.contains("exceptionType=java.lang.IllegalStateException"))
        assertTrue(diagnostics.contains("LedgerMobileHandlerTest"))
        // Exception messages can embed sensitive SDK payloads.
        assertFalse(diagnostics.contains("SDK failure"))
        val retry = exchangeCall()
        runCurrent()
        assertNull(retry.error)
        assertEquals(1, retry.completions)
    }

    @Test fun signingBlocksUfvkAndPreservesApduStatusFailure() = runTest(dispatcher) {
        useExchange { awaitCancellation() }
        val signing = exchangeCall("exchangeApdus")
        runCurrent()
        assertEquals("unavailable", exchangeCall().error)
        call("cancelSigning")
        runCurrent()
        assertEquals("cancelled", signing.error)
        assertEquals(1, signing.completions)

        for (method in listOf("exchangeUfvk", "exchangeApdus")) {
            var sends = 0
            useExchange {
                sends++
                DeviceOperationResult.Success(byteArrayOf(0x69, 0x85.toByte()))
            }
            val rejected = exchangeCall(method)
            runCurrent()
            assertEquals(1, sends)
            assertNull(rejected.error)
            assertEquals(listOf(listOf(105, 133)), rejected.value)
            assertEquals(1, rejected.completions)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun useReadiness(
        query: suspend () -> DeviceOperationResult<AppAndVersion> = {
            DeviceOperationResult.Success(AppAndVersion("Zcash", "3.9.2"))
        },
        open: () -> Flow<DeviceActionResult<Unit>> = { flowOf(DeviceActionResult.Success(Unit)) },
        disconnect: suspend () -> Unit = {},
    ) {
        handler.close()
        dispatcher.scheduler.runCurrent()
        `when`(connected.uid).thenReturn("connected-id")
        `when`(dmk.getConnectedDevices()).thenReturn(listOf(connected))
        val sdk = object : DeviceManagementKitApi by dmk {
            override suspend fun <T> executeCommand(
                deviceUid: String, command: Command<T>,
            ): DeviceOperationResult<T> = query() as DeviceOperationResult<T>
            override fun <T> executeDeviceAction(
                deviceUid: String, deviceAction: DeviceAction<T>,
            ): Flow<DeviceActionResult<T>> = open() as Flow<DeviceActionResult<T>>
            override suspend fun disconnectDevice(device: ConnectedDevice) = disconnect()
        }
        handler = LedgerMobileHandler(mock(Activity::class.java), sdk)
    }

    @Test fun readinessCancellationMatrixCompletesEachResultOnceAndAllowsRetry() = runTest(dispatcher) {
        for (method in listOf("currentApp", "openZcashApp")) {
            for (action in listOf("cancelSigning", "disconnect", "close")) {
                for (dispatch in listOf(false, true)) {
                    var calls = 0
                    useReadiness(
                        query = { calls++; awaitCancellation() },
                        open = { flow { calls++; awaitCancellation() } },
                    )
                    val pending = call(method)
                    if (dispatch) runCurrent()
                    if (action == "close") handler.close() else call(action)
                    runCurrent()
                    assertEquals(if (dispatch) 1 else 0, calls)
                    assertEquals("cancelled", pending.error)
                    assertEquals(1, pending.completions)
                    if (action != "close") {
                        val retry = call(method)
                        runCurrent()
                        assertEquals(0, retry.completions)
                        call("cancelSigning")
                        runCurrent()
                        assertEquals(1, retry.completions)
                    } else {
                        assertEquals("cancelled", call(method).error)
                    }
                }
            }
        }
    }

    @Test fun readinessOwnsTheDeviceAgainstEveryOtherCommandUntilDrain() = runTest(dispatcher) {
        for (method in listOf("currentApp", "openZcashApp")) {
            var pending: Continuation<DeviceOperationResult<AppAndVersion>>? = null
            useReadiness(query = { suspendCoroutine { pending = it } })
            val first = call(method)
            runCurrent()
            assertNotNull(pending)
            for (cancel in listOf(false, true)) {
                if (cancel) call("cancelSigning")
                for (other in listOf("connect", "currentApp", "openZcashApp", "startDiscovery")) {
                    assertEquals("$method blocks $other", "unavailable", call(other).error)
                }
                assertEquals("unavailable", exchangeCall().error)
                assertEquals("unavailable", exchangeCall("exchangeApdus").error)
            }
            pending!!.resume(DeviceOperationResult.Success(AppAndVersion("Zcash", "3.9.2")))
            runCurrent()
            assertEquals("cancelled", first.error)
            assertEquals(1, first.completions)
            val retry = call(method)
            runCurrent()
            pending!!.resume(DeviceOperationResult.Success(AppAndVersion("Zcash", "3.9.2")))
            runCurrent()
            assertEquals(mapOf("name" to "Zcash", "version" to "3.9.2"), retry.value)
            assertEquals(1, retry.completions)
        }
    }

    @Test fun apduAndConnectionOwnersAlsoBlockReadiness() = runTest(dispatcher) {
        useExchange { awaitCancellation() }
        exchangeCall()
        runCurrent()
        assertEquals("unavailable", call("currentApp").error)
        assertEquals("unavailable", call("openZcashApp").error)
        call("cancelSigning")
        runCurrent()
        `when`(dmk.startDiscoveringDevices()).thenReturn(flow { awaitCancellation() })
        call("connect")
        runCurrent()
        assertEquals("unavailable", call("currentApp").error)
        assertEquals("unavailable", call("openZcashApp").error)
    }

    @Test fun cancelledAppApprovalCannotStartTheVersionQuery() = runTest(dispatcher) {
        var queries = 0
        useReadiness(
            query = { queries++; DeviceOperationResult.Success(AppAndVersion("Zcash", "3.9.2")) },
            open = { flow {
                call("cancelSigning")
                emit(DeviceActionResult.Success(Unit))
            } },
        )
        val result = call("openZcashApp")
        runCurrent()
        assertEquals(0, queries)
        assertEquals("cancelled", result.error)
        assertEquals(1, result.completions)
    }

    @Test fun readinessErrorsAndEmptyAppActionAlwaysSettleAndReleaseTheSlot() = runTest(dispatcher) {
        for (method in listOf("currentApp", "openZcashApp")) {
            var failOnce = true
            useReadiness(query = {
                if (failOnce) { failOnce = false; throw IllegalStateException("SDK failure") }
                DeviceOperationResult.Failure(DeviceOperationFailureReason.DeviceLocked)
            })
            val thrown = call(method)
            runCurrent()
            assertEquals("unavailable", thrown.error)
            assertEquals(1, thrown.completions)
            val locked = call(method)
            runCurrent()
            assertEquals("locked", locked.error)
            assertEquals(1, locked.completions)
        }
        useReadiness(open = { emptyFlow() })
        val empty = call("openZcashApp")
        runCurrent()
        assertEquals("unavailable", empty.error)
        assertEquals(1, empty.completions)
        val retry = call("currentApp")
        runCurrent()
        assertNull(retry.error)
        assertEquals(1, retry.completions)
    }

    @Test fun disconnectDrainsOldCommandAndBlocksNewWorkThroughNativeCleanup() = runTest(dispatcher) {
        var query: Continuation<DeviceOperationResult<AppAndVersion>>? = null
        var cleanup: Continuation<Unit>? = null
        useReadiness(
            query = { suspendCoroutine { query = it } },
            disconnect = { suspendCoroutine { cleanup = it } },
        )
        val abandoned = call("currentApp")
        runCurrent()
        val disconnect = call("disconnect")
        runCurrent()
        assertNull(cleanup)
        assertEquals("cancelled", abandoned.error)
        assertEquals("unavailable", call("connect").error)
        query!!.resume(DeviceOperationResult.Success(AppAndVersion("Zcash", "3.9.2")))
        runCurrent()
        assertNotNull(cleanup)
        assertEquals("unavailable", call("currentApp").error)
        assertEquals("unavailable", call("disconnect").error)
        call("cancelSigning") // Cleanup must continue even after another UI cancel.
        assertEquals(0, disconnect.completions)
        handler.close()
        assertEquals("cancelled", disconnect.error)
        assertEquals(1, disconnect.completions)
        cleanup!!.resume(Unit)
        runCurrent()
        assertEquals(1, disconnect.completions)
        assertEquals(1, abandoned.completions)
    }

    @Test fun disconnectFailureCompletesItsResultAndAllowsRetry() = runTest(dispatcher) {
        useReadiness(disconnect = { throw IllegalStateException("disconnect failed") })
        call("currentApp")
        runCurrent()
        val disconnect = call("disconnect")
        runCurrent()
        assertEquals("unavailable", disconnect.error)
        assertEquals(1, disconnect.completions)
        val retry = call("currentApp")
        runCurrent()
        assertNull(retry.error)
        assertEquals(1, retry.completions)
    }

    @Test fun closeCompletesPermissionRequestAndIgnoresLateGrant() = runTest(dispatcher) {
        handler.close()
        runCurrent()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        handler = LedgerMobileHandler(activity, dmk)
        val result = call("requestPermissions")
        assertEquals(0, result.completions)
        handler.close()
        assertEquals("cancelled", result.error)
        assertEquals(1, result.completions)
        handler.onRequestPermissionsResult(0x4c45, intArrayOf(PackageManager.PERMISSION_GRANTED))
        assertEquals(1, result.completions)
        activity.finish()
    }

    @Test fun stoppedDiscoveryDrainsBeforeReconnectAndCannotPublishToNewListener() = runTest(dispatcher) {
        handler.close()
        runCurrent()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        shadowOf(activity.application).grantPermissions(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        `when`(dmk.isBluetoothBleSupported()).thenReturn(true)
        var drain: Continuation<Unit>? = null
        var scans = 0
        `when`(dmk.startDiscoveringDevices()).thenAnswer {
            scans++
            if (scans == 1) flow {
                suspendCoroutine<Unit> { drain = it }
                emit(DiscoveryResult.DevicesDiscovered(listOf(saved.copy(uid = "stale"))))
            } else flowOf(DiscoveryResult.DevicesDiscovered(listOf(saved)))
        }
        `when`(dmk.connectDevice(saved)).thenReturn(ConnectionResult.Connected(connected))
        handler = LedgerMobileHandler(activity, dmk)
        val oldSink = mock(EventChannel.EventSink::class.java)
        val newSink = mock(EventChannel.EventSink::class.java)
        handler.onListen(null, oldSink)
        assertNull(call("startDiscovery").error)
        runCurrent()
        handler.onCancel(null)
        handler.onListen(null, newSink)
        val connection = call("connect")
        runCurrent()
        assertEquals(1, scans)
        drain!!.resume(Unit)
        runCurrent()
        assertEquals(2, scans)
        verifyNoInteractions(oldSink, newSink)
        assertNull(connection.error)
        assertEquals(1, connection.completions)
        activity.finish()
    }

    @Test fun recreatedHandlerCannotBypassOldSdkCleanup() = runTest(dispatcher) {
        var pending: Continuation<ConnectionResult>? = null
        `when`(dmk.startDiscoveringDevices()).thenReturn(flowOf(DiscoveryResult.DevicesDiscovered(listOf(saved))))
        val sdk = object : DeviceManagementKitApi by dmk {
            override suspend fun connectDevice(device: DiscoveryDevice): ConnectionResult =
                suspendCoroutine { pending = it }
        }
        handler.close()
        runCurrent()
        handler = LedgerMobileHandler(mock(Activity::class.java), sdk)
        val old = call("connect")
        runCurrent()
        handler.close()
        handler = LedgerMobileHandler(mock(Activity::class.java), sdk)
        assertEquals("unavailable", call("connect").error)
        assertEquals("unavailable", call("currentApp").error)
        pending!!.resume(ConnectionResult.Connected(connected))
        runCurrent()
        assertEquals("cancelled", old.error)
        assertEquals(1, old.completions)
        verify(dmk).disconnectDevice(connected)
        val retry = call("connect")
        runCurrent()
        pending!!.resume(ConnectionResult.Connected(connected))
        runCurrent()
        assertNull(retry.error)
        assertEquals(1, retry.completions)
    }

}
