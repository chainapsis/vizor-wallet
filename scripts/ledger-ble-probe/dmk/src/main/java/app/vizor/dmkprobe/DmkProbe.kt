package app.vizor.dmkprobe

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.ledger.devicemanagement.deviceManagementKit
import com.ledger.devicemanagement.api.DeviceOperationResult
import com.ledger.devicemanagement.api.apdu.apdu
import com.ledger.devicemanagement.api.apdu.uniqueApduPayload
import com.ledger.devicemanagement.api.command.getappandversion.GetAppAndVersionCommand
import com.ledger.devicemanagement.api.connection.ConnectionResult
import com.ledger.devicemanagement.api.discovery.DiscoveryResult
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first

/** Official, unmodified DMK over emulated BLE. Responses are synthetic, not signatures. */
class DmkProbe : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val dmk = deviceManagementKit { context = applicationContext; enableLog = true }
        fun log(message: String) = Log.i("VizorDmkProbe", message)
        scope.launch {
            try {
                withTimeout(45000) {
                    val discovery = dmk.startDiscoveringDevices().first { result ->
                        result is DiscoveryResult.DevicesDiscovered && result.devices.any { it.name == "DMKProbe" }
                    } as DiscoveryResult.DevicesDiscovered
                    val peer = discovery.devices.first { it.name == "DMKProbe" }
                    dmk.stopDiscoveringDevices()
                    log("PASS SDK discovery ${peer.ledgerDevice.name}")
                    var connected = dmk.connectDevice(peer) as? ConnectionResult.Connected
                        ?: error("SDK connection failed")
                    log("PASS SDK connect and MTU handshake")
                    val info = dmk.executeCommand(connected.device.uid, GetAppAndVersionCommand())
                    check(info is DeviceOperationResult.Success && info.value.appName == "Zcash") { "App info: $info" }
                    log("PASS SDK GetAppAndVersion $info")
                    suspend fun send(ins: Int): ByteArray {
                        val result = dmk.sendApdu(connected!!.device.uid, uniqueApduPayload(apdu {
                            classInstruction = 0xe0.toByte()
                            instructionMethod = ins.toByte()
                            parameter1 = 0; parameter2 = 0; data = byteArrayOf()
                        }))
                        check(result is DeviceOperationResult.Success) { "APDU failed: $result" }
                        return result.value
                    }
                    check(send(0xf1).contentEquals(byteArrayOf(1, 0x90.toByte(), 0)))
                    log("PASS SDK normal framed APDU")
                    check(send(0xf2).contentEquals(byteArrayOf(2, 0x90.toByte(), 0)))
                    log("PASS SDK delayed framed APDU")
                    val pending = async { send(0xf2) }
                    delay(300)
                    pending.cancelAndJoin()
                    log("PASS caller cancellation returned")
                    withTimeout(5000) { dmk.disconnectDevice(connected!!.device) }
                    log("PASS SDK disconnect returned")
                    val immediate = dmk.connectDevice(peer)
                    log("OBSERVED immediate reconnect: $immediate")
                    connected = if (immediate is ConnectionResult.Connected) immediate else {
                        withTimeout(5000) {
                            dmk.observeConnectedDevices().first { devices -> devices.none { it.uid == peer.uid } }
                        }
                        log("PASS SDK observed previous session removed")
                        val retry = dmk.connectDevice(peer)
                        retry as? ConnectionResult.Connected ?: error("SDK reconnect after session removal: $retry")
                    }
                    log("PASS SDK reconnect")
                    // Hold this response beyond the old delayed response to detect misbinding.
                    val fresh = send(0xf3)
                    check(fresh.contentEquals(byteArrayOf(3, 0x90.toByte(), 0))) {
                        "STALE response bound to new APDU: ${fresh.joinToString { "%02x".format(it) }}"
                    }
                    log("PASS SDK fresh request did not consume old response")
                    dmk.disconnectDevice(connected!!.device)
                    log("PASS ALL SDK scenarios; synthetic peer, no signing or broadcast")
                }
            } catch (error: Throwable) {
                log("FAIL ${error.javaClass.simpleName}: ${error.message}")
            } finally {
                dmk.destroy()
            }
        }
    }
}
