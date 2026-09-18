package com.keplr.vizor

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.content.ContextCompat

/** Observes OS evidence only; DMK remains the sole owner of the GATT connection. */
internal class LedgerKeyMissingObserver(private val context: Context) {
    private var receiver: BroadcastReceiver? = null

    fun start(address: String, onKeyMissing: () -> Unit) {
        stop()
        if (Build.VERSION.SDK_INT < 36) return
        val next = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (receiver !== this || intent.action != BluetoothDevice.ACTION_KEY_MISSING) return
                val device = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    ?: return
                try {
                    if (device.address.equals(address, ignoreCase = true)) onKeyMissing()
                } catch (_: SecurityException) {
                    // Permission revocation is handled by the normal access recovery flow.
                }
            }
        }
        // Bluetooth broadcasts originate from a privileged process with a separate UID.
        // KEY_MISSING is a protected system broadcast; accept no other action.
        ContextCompat.registerReceiver(
            context, next, IntentFilter(BluetoothDevice.ACTION_KEY_MISSING),
            Manifest.permission.BLUETOOTH_CONNECT, null, ContextCompat.RECEIVER_EXPORTED,
        )
        receiver = next
    }

    fun stop() {
        val previous = receiver ?: return
        receiver = null
        context.unregisterReceiver(previous)
    }
}
