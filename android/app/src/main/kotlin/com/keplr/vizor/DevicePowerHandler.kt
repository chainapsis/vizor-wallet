package com.keplr.vizor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel

/**
 * Emits `{thermal, lowPower}` on listen and whenever either changes, so sync
 * scans with less of the CPU as the device warms. `thermal` uses the iOS
 * `ProcessInfo.ThermalState` scale: 0 nominal, 1 fair, 2 serious, 3 critical.
 */
class DevicePowerHandler(private val context: Context) : EventChannel.StreamHandler {
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private var events: EventChannel.EventSink? = null
    private val thermalListener = PowerManager.OnThermalStatusChangedListener { send() }
    private val powerSaveReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = send()
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
        powerManager.addThermalStatusListener(context.mainExecutor, thermalListener)
        val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(powerSaveReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(powerSaveReceiver, filter)
        }
        send()
    }

    override fun onCancel(arguments: Any?) {
        if (events == null) return
        powerManager.removeThermalStatusListener(thermalListener)
        context.unregisterReceiver(powerSaveReceiver)
        events = null
    }

    private fun send() {
        events?.success(mapOf("thermal" to thermal(), "lowPower" to powerManager.isPowerSaveMode))
    }

    private fun thermal(): Int = when (powerManager.currentThermalStatus) {
        PowerManager.THERMAL_STATUS_NONE -> 0
        PowerManager.THERMAL_STATUS_LIGHT, PowerManager.THERMAL_STATUS_MODERATE -> 1
        PowerManager.THERMAL_STATUS_SEVERE -> 2
        else -> 3
    }
}
