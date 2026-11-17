package com.keplr.vizor

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel

/**
 * Emits how far the screen faces the floor while Dart listens: gravity along
 * the screen's normal, -1 with the screen straight up and 1 straight down
 * (iOS's sign, so Dart reads both platforms alike). Dart turns a quick flip
 * screen-down into hiding amounts (flip to hide), and listens only while the
 * app is visible and unlocked. Needs no permission.
 *
 * Uses the gravity sensor, which separates gravity from the hand's own
 * movement, and falls back to the accelerometer on devices without one.
 */
class ScreenFacingHandler(context: Context) :
    EventChannel.StreamHandler,
    SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val sensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY)
        ?: sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private var events: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
        val sensor = sensor ?: return
        // About 16 readings a second, delivered on the main thread.
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        if (events == null) return
        sensorManager.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        // Android reports +g on z with the screen up; Dart takes iOS's sign.
        val facing = (-event.values[2] / SensorManager.GRAVITY_EARTH).coerceIn(-1f, 1f)
        events?.success(facing.toDouble())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
