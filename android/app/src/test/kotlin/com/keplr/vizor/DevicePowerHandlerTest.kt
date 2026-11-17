package com.keplr.vizor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 33], manifest = Config.NONE)
class DevicePowerHandlerTest {
    private lateinit var context: Context
    private lateinit var powerManager: PowerManager
    private lateinit var handler: DevicePowerHandler
    private val sent = mutableListOf<Map<*, *>>()
    private var status = PowerManager.THERMAL_STATUS_NONE
    private var lowPower = false

    @Before fun setUp() {
        powerManager = mock(PowerManager::class.java)
        context = mock(Context::class.java)
        `when`(context.getSystemService(Context.POWER_SERVICE)).thenReturn(powerManager)
        `when`(powerManager.currentThermalStatus).thenAnswer { status }
        `when`(powerManager.isPowerSaveMode).thenAnswer { lowPower }
        handler = DevicePowerHandler(context)
    }

    private fun listen() {
        val sink = mock(EventChannel.EventSink::class.java)
        doAnswer { sent.add(it.getArgument(0)); null }.`when`(sink).success(any())
        handler.onListen(null, sink)
    }

    private fun thermalListener(): PowerManager.OnThermalStatusChangedListener {
        val listener = ArgumentCaptor.forClass(PowerManager.OnThermalStatusChangedListener::class.java)
        verify(powerManager).addThermalStatusListener(any(), listener.capture())
        return listener.value
    }

    private fun powerSaveReceiver(): BroadcastReceiver {
        val receiver = ArgumentCaptor.forClass(BroadcastReceiver::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            verify(context).registerReceiver(receiver.capture(), any(), anyInt())
        } else {
            verify(context).registerReceiver(receiver.capture(), any())
        }
        return receiver.value
    }

    @Test fun mapsTheThermalStatusOntoTheIosScale() {
        listen()
        assertEquals(mapOf("thermal" to 0, "lowPower" to false), sent.single())

        val listener = thermalListener()
        for ((next, expected) in listOf(
            PowerManager.THERMAL_STATUS_LIGHT to 1,
            PowerManager.THERMAL_STATUS_MODERATE to 1,
            PowerManager.THERMAL_STATUS_SEVERE to 2,
            PowerManager.THERMAL_STATUS_CRITICAL to 3,
            PowerManager.THERMAL_STATUS_EMERGENCY to 3,
            PowerManager.THERMAL_STATUS_SHUTDOWN to 3,
            PowerManager.THERMAL_STATUS_NONE to 0,
        )) {
            status = next
            listener.onThermalStatusChanged(next)
            assertEquals(expected, sent.last()["thermal"])
        }
    }

    @Test fun sendsPowerSavingChangesOnly() {
        listen()
        val receiver = powerSaveReceiver()
        val intent = Intent(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)

        receiver.onReceive(context, intent)
        assertEquals(1, sent.size)

        lowPower = true
        receiver.onReceive(context, intent)
        assertEquals(mapOf("thermal" to 0, "lowPower" to true), sent.last())
        assertEquals(2, sent.size)
    }

    @Test fun cancellingUnregistersOnce() {
        listen()
        val listener = thermalListener()
        val receiver = powerSaveReceiver()

        handler.onCancel(null)
        handler.onCancel(null)
        verify(powerManager, times(1)).removeThermalStatusListener(listener)
        verify(context, times(1)).unregisterReceiver(receiver)
    }
}
