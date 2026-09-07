package app.vizor.dmkprobe

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.keplr.vizor.LedgerMobileHandler
import io.flutter.plugin.common.*
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONArray
import java.net.ServerSocket
import java.net.InetAddress

/** Loopback-only, short-lived test bridge. Never packaged in Vizor. */
class BridgeProbe : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val handler = LedgerMobileHandler(this)
        var discovered = CompletableDeferred<String>()
        handler.onListen(null, object : EventChannel.EventSink {
            override fun success(event: Any?) {
                val devices = (event as? Map<*, *>)?.get("devices") as? List<*> ?: return
                for (item in devices) {
                    val peer = item as? Map<*, *> ?: continue
                    if (peer["name"] == "DMKProbe") discovered.complete(peer["id"] as String)
                }
            }
        })
        suspend fun invoke(method: String, args: Map<String, Any?>? = null): Any? {
            val result = CompletableDeferred<Any?>()
            handler.handle(MethodCall(method, args), object : MethodChannel.Result {
                override fun success(value: Any?) { result.complete(value) }
                override fun error(code: String, message: String?, details: Any?) {
                    result.complete(mapOf("error" to code, "message" to message))
                }
                override fun notImplemented() { error("unimplemented", null, null) }
            })
            return result.await()
        }
        val server = ServerSocket(18765, 8, InetAddress.getByName("127.0.0.1"))
        server.soTimeout = 1000
        scope.launch(Dispatchers.IO) {
            val deadline = System.nanoTime() + 180_000_000_000L
            Log.i("VizorDmkProbe", "READY bridge 127.0.0.1:18765 for 180s")
            try {
                while (System.nanoTime() < deadline) {
                    val socket = try { server.accept() } catch (_: java.net.SocketTimeoutException) { continue }
                    launch {
                        socket.use {
                            socket.soTimeout = 15000
                            try {
                                val request = JSONObject(socket.getInputStream().bufferedReader().readLine())
                                val method = request.getString("method")
                                val value = withContext(Dispatchers.Main) {
                                    withTimeout(15000) {
                                        if (method == "probeDiscover") {
                                            discovered = CompletableDeferred()
                                            val started = invoke("startDiscovery")
                                            check(started == null) { "$started" }
                                            val id = discovered.await()
                                            delay(500)
                                            mapOf("id" to id, "name" to "DMKProbe", "model" to "Nano X")
                                        } else {
                                            require(method in setOf("connect", "disconnect", "exchangeApdus", "cancelSigning"))
                                            @Suppress("UNCHECKED_CAST")
                                            invoke(method, decode(request.opt("arguments")) as? Map<String, Any?>)
                                        }
                                    }
                                }
                                socket.getOutputStream().write((JSONObject(mapOf("value" to (value ?: JSONObject.NULL))).toString() + "\n").toByteArray())
                            } catch (error: Exception) {
                                socket.getOutputStream().write((JSONObject(mapOf("value" to mapOf("error" to "probe", "message" to error.toString()))).toString() + "\n").toByteArray())
                            }
                        }
                    }
                }
            } finally {
                server.close()
                withContext(Dispatchers.Main) { invoke("disconnect"); handler.close() }
            }
        }
    }

    private fun decode(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { decode(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { decode(value.get(it)) }
        else -> value
    }
}
