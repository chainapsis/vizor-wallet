package com.keplr.vizor

import android.content.Context
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel
import java.time.Duration
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 33], manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
class DevicePowerHandlerTest {
    private lateinit var powerManager: PowerManager
    private lateinit var handler: DevicePowerHandler
    private val sent = mutableListOf<Map<*, *>>()
    private var status = PowerManager.THERMAL_STATUS_NONE
    private var headroom = 0.5f
    private var lowPower = false

    @Before fun setUp() {
        powerManager = mock(PowerManager::class.java)
        val context = mock(Context::class.java)
        `when`(context.getSystemService(Context.POWER_SERVICE)).thenReturn(powerManager)
        `when`(powerManager.currentThermalStatus).thenAnswer { status }
        `when`(powerManager.getThermalHeadroom(anyInt())).thenAnswer { headroom }
        `when`(powerManager.isPowerSaveMode).thenAnswer { lowPower }
        handler = DevicePowerHandler(context)
    }

    private fun listen() {
        val sink = mock(EventChannel.EventSink::class.java)
        doAnswer { sent.add(it.getArgument(0)); null }.`when`(sink).success(any())
        handler.onListen(null, sink)
    }

    private fun advance(seconds: Long) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(seconds))
    }

    private fun thermal() = sent.last()["thermal"]

    @Test fun headroomWarmsTheStateWhileTheStatusStaysNone() {
        listen()
        assertEquals(mapOf("thermal" to 0, "lowPower" to false), sent.single())

        headroom = 0.9f
        advance(10)
        assertEquals(1, thermal())

        // 1.0 is the severe threshold; headroom never reports critical.
        headroom = 1.4f
        advance(10)
        assertEquals(2, thermal())

        headroom = 0.4f
        advance(10)
        assertEquals(0, thermal())
    }

    @Test fun theWarmerOfStatusAndHeadroomWins() {
        status = PowerManager.THERMAL_STATUS_LIGHT
        headroom = 1.02f
        listen()
        assertEquals(2, thermal())

        status = PowerManager.THERMAL_STATUS_CRITICAL
        advance(10)
        assertEquals(3, thermal())

        status = PowerManager.THERMAL_STATUS_SEVERE
        headroom = 0.2f
        advance(10)
        assertEquals(2, thermal())
    }

    @Test fun anUnreadableHeadroomLeavesTheStatus() {
        status = PowerManager.THERMAL_STATUS_MODERATE
        headroom = Float.NaN
        listen()
        assertEquals(1, thermal())
    }

    @Test fun statusChangesReuseTheLastHeadroomReading() {
        headroom = 0.9f
        listen()
        val listener = ArgumentCaptor.forClass(PowerManager.OnThermalStatusChangedListener::class.java)
        verify(powerManager).addThermalStatusListener(any(), listener.capture())

        // A second read this soon would return NaN on a device.
        headroom = Float.NaN
        status = PowerManager.THERMAL_STATUS_SEVERE
        listener.value.onThermalStatusChanged(status)
        assertEquals(2, thermal())
        status = PowerManager.THERMAL_STATUS_NONE
        listener.value.onThermalStatusChanged(status)
        assertEquals(1, thermal())
        verify(powerManager, times(1)).getThermalHeadroom(anyInt())
    }

    @Test fun pollsEveryTenSecondsAndSendsOnlyChanges() {
        listen()
        advance(30)
        verify(powerManager, times(4)).getThermalHeadroom(0)
        assertEquals(1, sent.size)

        lowPower = true
        advance(10)
        assertEquals(mapOf("thermal" to 0, "lowPower" to true), sent.last())
        assertEquals(2, sent.size)
    }

    @Test fun cancellingStopsThePoll() {
        listen()
        handler.onCancel(null)
        headroom = 1.2f
        advance(30)
        verify(powerManager, times(1)).getThermalHeadroom(anyInt())
        assertEquals(1, sent.size)
    }
}
