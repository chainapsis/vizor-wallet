package com.keplr.vizor

import android.app.Activity
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
        override fun success(result: Any?) { completions++ }
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

}
