package com.keplr.vizor

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Intent
import android.os.Looper
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], manifest = Config.NONE)
class LedgerKeyMissingObserverTest {
    @Test fun replacementMissingDeviceAndStopCannotLeakEvidence() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        shadowOf(activity.application).grantPermissions(Manifest.permission.BLUETOOTH_CONNECT)
        val observer = LedgerKeyMissingObserver(activity)
        val first = "AA:BB:CC:DD:EE:01"
        val second = "AA:BB:CC:DD:EE:02"
        val events = mutableListOf<String>()
        fun emit(address: String?) {
            val intent = Intent(BluetoothDevice.ACTION_KEY_MISSING)
            if (address != null) intent.putExtra(BluetoothDevice.EXTRA_DEVICE,
                BluetoothAdapter.getDefaultAdapter().getRemoteDevice(address))
            activity.sendBroadcast(intent)
            shadowOf(Looper.getMainLooper()).idle()
        }
        observer.start(first) { events += "first" }
        observer.start(second) { events += "second" }
        emit(null)
        emit(first)
        assertEquals(emptyList<String>(), events)
        emit(second)
        assertEquals(listOf("second"), events)
        observer.stop()
        observer.stop()
        emit(second)
        assertEquals(listOf("second"), events)
        activity.finish()
    }

    @Test @Config(sdk = [35]) fun android15DoesNotObserveKeyMissing() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        shadowOf(activity.application).grantPermissions(Manifest.permission.BLUETOOTH_CONNECT)
        val observer = LedgerKeyMissingObserver(activity)
        var events = 0
        observer.start("AA:BB:CC:DD:EE:01") { events++ }
        activity.sendBroadcast(Intent("android.bluetooth.device.action.KEY_MISSING")
            .putExtra(BluetoothDevice.EXTRA_DEVICE,
                BluetoothAdapter.getDefaultAdapter().getRemoteDevice("AA:BB:CC:DD:EE:01")))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(0, events)
        observer.stop()
        activity.finish()
    }
}
