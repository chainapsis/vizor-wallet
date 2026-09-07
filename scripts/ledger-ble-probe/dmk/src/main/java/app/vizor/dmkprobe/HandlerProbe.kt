package app.vizor.dmkprobe

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.bluetooth.BluetoothManager
import com.keplr.vizor.LedgerMobileHandler
import io.flutter.plugin.common.*
import kotlinx.coroutines.*

/** Runs the unchanged production handler; only Flutter channel endpoints are fixtures. */
class HandlerProbe : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private class Reply : MethodChannel.Result {
        val done = CompletableDeferred<Any?>()
        var completions = 0
        override fun success(result: Any?) { completions++; done.complete(result) }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            completions++; done.complete("ERROR:$errorCode:$errorMessage")
        }
        override fun notImplemented() { error("not_implemented", null, null) }
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val handler = LedgerMobileHandler(this)
        fun log(value: String) = Log.i("VizorDmkProbe", value)
        fun traceName(id: String) {
            if (!intent.getBooleanExtra("traceNames", false)) return
            val remote = getSystemService(BluetoothManager::class.java).adapter.getRemoteDevice(id)
            scope.launch {
                var previous: String? = "<unobserved>"
                repeat(80) {
                    val name = remote.name
                    if (name != previous) log("NAME $id ${previous ?: "null"} -> ${name ?: "null"}")
                    previous = name
                    delay(25)
                }
            }
        }
        fun start(method: String, args: Map<String, Any?>? = null): Reply = Reply().also {
            handler.handle(MethodCall(method, args), it)
        }
        fun args(ins: Int) = mapOf("commands" to listOf(mapOf(
            "cla" to 0xe0, "ins" to ins, "p1" to 0, "p2" to 0, "data" to emptyList<Int>())))
        scope.launch {
            try {
                withTimeout(45000) {
                    var peer = CompletableDeferred<String>()
                    handler.onListen(null, object : EventChannel.EventSink {
                        override fun success(event: Any?) {
                            val devices = (event as? Map<*, *>)?.get("devices") as? List<*> ?: return
                            for (item in devices) {
                                val device = item as? Map<*, *> ?: continue
                                if (device["name"] == "DMKProbe") peer.complete(device["id"] as String)
                            }
                        }
                    })
                    suspend fun connectWithRecovery(id: String) {
                        var currentId = id
                        repeat(3) { attempt ->
                            val connected = start("connect", mapOf("deviceId" to currentId)).done.await()
                            if (connected == null) return
                            log("OBSERVED handled connection failure: $connected")
                            check(connected.toString().startsWith("ERROR:disconnected:Could not finish connecting")) {
                                "Unexpected connection/cleanup failure: $connected"
                            }
                            check(attempt < 2) { "Recovery exhausted" }
                            // This explicitly simulates a user trying again, not product auto-retry.
                            delay(4000)
                            peer = CompletableDeferred()
                            check(start("startDiscovery").done.await() == null)
                            currentId = peer.await()
                            delay(500)
                        }
                    }
                    check(start("startDiscovery").done.await() == null)
                    val id = peer.await()
                    traceName(id)
                    // Let the emulator populate BluetoothDevice.name after scan discovery.
                    delay(500)
                    connectWithRecovery(id)
                    log("PASS production handler discovery/connect")
                    check(start("exchangeApdus", args(0xf1)).done.await() == listOf(listOf(1, 144, 0)))
                    log("PASS production handler normal APDU")
                    val waitMs = intent.getLongExtra("waitMs", 100)
                    log("CONFIG reconnect waitMs=$waitMs")
                    val pending = start("exchangeApdus", args(0xf2))
                    delay(300)
                    check(start("cancelSigning").done.await() == null)
                    check(pending.done.await().toString().startsWith("ERROR:cancelled:"))
                    val closing = start("disconnect")
                    if (!closing.done.isCompleted) {
                        val blocked = start("exchangeApdus", args(0xf1)).done.await()
                        check(blocked.toString().startsWith("ERROR:disconnected:Your Ledger connection is not ready"))
                        log("PASS APDU blocked during connection cleanup")
                    }
                    check(closing.done.await() == null)
                    // Give the SDK map time to remove the logical session. This is a probe
                    // control, not a proposed fix or the product's UFVK guard.
                    delay(waitMs)
                    var reconnectId = id
                    if (intent.getBooleanExtra("rediscover", false)) {
                        peer = CompletableDeferred()
                        check(start("startDiscovery").done.await() == null)
                        reconnectId = peer.await()
                        delay(500)
                        log("PASS rediscovery before reconnect")
                    }
                    traceName(reconnectId)
                    connectWithRecovery(reconnectId)
                    val fresh = start("exchangeApdus", args(0xf3)).done.await()
                    check(pending.completions == 1) { "Cancelled callback completed again" }
                    log("PASS cancelled callback completed exactly once")
                    check(fresh == listOf(listOf(3, 144, 0))) { "STALE handler response: $fresh" }
                    log("PASS ALL production handler scenarios; no Flutter engine or signing")
                }
            } catch (error: Throwable) {
                log("FAIL ${error.javaClass.simpleName}: ${error.message}")
            } finally {
                start("disconnect").done.await()
                handler.close()
            }
        }
    }
}
