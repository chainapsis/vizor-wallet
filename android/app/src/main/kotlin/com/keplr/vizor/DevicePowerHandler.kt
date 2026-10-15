package com.keplr.vizor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel

/**
 * Emits `{thermal, lowPower}` on listen and whenever either changes, so sync
 * scans with less of the CPU as the device warms. `thermal` uses the iOS
 * `ProcessInfo.ThermalState` scale: 0 nominal, 1 fair, 2 serious, 3 critical.
 *
 * Some devices report `THERMAL_STATUS_NONE` while they throttle, so the
 * thermal headroom is polled as well and the warmer of the two readings wins.
 */
class DevicePowerHandler(private val context: Context) : EventChannel.StreamHandler {
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var sent: Map<String, Any>? = null
    // Only the poll reads the headroom: reading it again too soon returns NaN.
    private var headroom = Float.NaN
    private val thermalListener = PowerManager.OnThermalStatusChangedListener { send() }
    private val powerSaveReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = send()
    }
    private val pollHeadroom = object : Runnable {
        override fun run() {
            headroom = powerManager.getThermalHeadroom(0)
            send()
            mainHandler.postDelayed(this, HEADROOM_POLL_MILLIS)
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
        sent = null
        powerManager.addThermalStatusListener(context.mainExecutor, thermalListener)
        val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(powerSaveReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(powerSaveReceiver, filter)
        }
        pollHeadroom.run()
    }

    override fun onCancel(arguments: Any?) {
        if (events == null) return
        mainHandler.removeCallbacks(pollHeadroom)
        powerManager.removeThermalStatusListener(thermalListener)
        context.unregisterReceiver(powerSaveReceiver)
        events = null
    }

    /** Sends the power state when it differs from the last one sent. */
    private fun send() {
        val power = mapOf("thermal" to thermal(), "lowPower" to powerManager.isPowerSaveMode)
        if (power == sent) return
        sent = power
        events?.success(power)
    }

    private fun thermal(): Int {
        val fromStatus = when (powerManager.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> 0
            PowerManager.THERMAL_STATUS_LIGHT, PowerManager.THERMAL_STATUS_MODERATE -> 1
            PowerManager.THERMAL_STATUS_SEVERE -> 2
            else -> 3
        }
        // 1.0 is where the device throttles at THERMAL_STATUS_SEVERE. Above
        // 0.85 the ADPF guide expects light throttling. Headroom has no level
        // past severe, and NaN (unsupported, or no reading) leaves the status.
        val fromHeadroom = when {
            headroom >= 1f -> 2
            headroom > 0.85f -> 1
            else -> 0
        }
        return maxOf(fromStatus, fromHeadroom)
    }

    private companion object {
        // The ADPF guide asks for at most one headroom read every 10 seconds.
        const val HEADROOM_POLL_MILLIS = 10_000L
    }
}
