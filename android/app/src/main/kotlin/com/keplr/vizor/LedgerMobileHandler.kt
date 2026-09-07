package com.keplr.vizor

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import com.ledger.devicemanagement.DeviceManagementKitApi
import com.ledger.devicemanagement.api.DeviceOperationFailureReason
import com.ledger.devicemanagement.api.DeviceOperationResult
import com.ledger.devicemanagement.api.apdu.apdu
import com.ledger.devicemanagement.api.apdu.uniqueApduPayload
import com.ledger.devicemanagement.api.command.getappandversion.AppAndVersion
import com.ledger.devicemanagement.api.command.getappandversion.GetAppAndVersionCommand
import com.ledger.devicemanagement.api.connection.ConnectedDevice
import com.ledger.devicemanagement.api.connection.ConnectionResult
import com.ledger.devicemanagement.api.deviceaction.DeviceActionResult
import com.ledger.devicemanagement.api.deviceaction.openapp.OpenApplicationDeviceAction
import com.ledger.devicemanagement.api.discovery.ConnectivityType
import com.ledger.devicemanagement.api.discovery.DiscoveryDevice
import com.ledger.devicemanagement.api.discovery.DiscoveryResult
import com.ledger.devicemanagement.deviceManagementKit
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class LedgerMobileHandler(private val activity: Activity) : EventChannel.StreamHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val dmk: DeviceManagementKitApi = LedgerDmkHolder.get(activity)
    private var discoveryJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null
    private var discoveryRequested = false
    private val discoveredDevices = mutableMapOf<String, DiscoveryDevice>()
    private var connectedDevice: ConnectedDevice? = null
    private var permissionResult: MethodChannel.Result? = null
    private var signingJob: Job? = null
    private var signingResult: MethodChannel.Result? = null
    private var signingGeneration = 0L
    private val connectionMutex = Mutex()
    private var connectionToClose: ConnectedDevice? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestPermissions(result)
            "startDiscovery" -> startDiscovery(result)
            "stopDiscovery" -> {
                stopDiscovery()
                result.success(null)
            }
            "connect" -> connect(call, result)
            "disconnect" -> disconnect(result)
            "currentApp" -> currentApp(result)
            "openZcashApp" -> openZcashApp(result)
            "exchangeUfvk" -> exchangeUfvk(call, result)
            "exchangeApdus" -> exchangeApdus(call, result)
            "cancelSigning" -> cancelSigning(result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        if (discoveryRequested && discoveryJob == null) beginDiscovery()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopDiscovery()
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(granted)
        permissionResult = null
        return true
    }

    fun close() {
        stopDiscovery()
        cancelSigningOperation()
        scope.cancel()
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            ActivityCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("unavailable", "A Ledger permission request is already active.", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), PERMISSION_REQUEST)
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        if (requiredPermissions().any {
                ActivityCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
            }
        ) {
            result.error("permission_denied", "Bluetooth permission is required to find Ledger devices.", null)
            return
        }
        if (!dmk.isBluetoothBleSupported()) {
            result.error("unavailable", "This Android device does not support Bluetooth LE.", null)
            return
        }
        discoveryJob?.cancel()
        discoveredDevices.clear()
        discoveryRequested = true
        if (eventSink != null) beginDiscovery()
        result.success(null)
    }

    private fun beginDiscovery() {
        discoveryJob?.cancel()
        discoveryJob = scope.launch {
            dmk.startDiscoveringDevices().collect { update ->
                when (update) {
                    is DiscoveryResult.DevicesDiscovered -> {
                        update.devices
                            .filter { it.connectivityType is ConnectivityType.Bluetooth }
                            .filter { it.ledgerDevice.bleInformation != null }
                            .forEach { discoveredDevices[it.uid] = it }
                        emit(
                            mapOf(
                                "type" to "devices",
                                "devices" to discoveredDevices.values.map {
                                    mapOf("id" to it.uid, "name" to it.name, "model" to it.ledgerDevice.name)
                                },
                            ),
                        )
                    }
                    DiscoveryResult.Ended -> emit(mapOf("type" to "ended"))
                    DiscoveryResult.Failure.BluetoothDisabled -> emitError(
                        "bluetooth_off",
                        "Turn on Bluetooth to find Ledger devices.",
                    )
                    DiscoveryResult.Failure.BluetoothPermissionNotGranted -> emitError(
                        "permission_denied",
                        "Bluetooth permission is required to find Ledger devices.",
                    )
                    DiscoveryResult.Failure.LocationDisabled -> emitError(
                        "permission_denied",
                        "Location must be enabled for Bluetooth discovery on this Android version.",
                    )
                    DiscoveryResult.Failure.BluetoothBleNotSupported -> emitError(
                        "unavailable",
                        "This Android device does not support Bluetooth LE.",
                    )
                    is DiscoveryResult.Failure.Unknown -> emitError("unavailable", update.message)
                }
            }
        }
    }

    private fun stopDiscovery() {
        discoveryJob?.cancel()
        discoveryJob = null
        discoveryRequested = false
        dmk.stopDiscoveringDevices()
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId")
        val device = deviceId?.let(discoveredDevices::get)
        if (device == null) {
            result.error("disconnected", "The selected Ledger is no longer available.", null)
            return
        }
        scope.launch { connectionMutex.withLock {
            try {
                connectionToClose?.let { closeConnection(it) }
                when (val connection = dmk.connectDevice(device)) {
                    is ConnectionResult.Connected -> {
                        connectedDevice = connection.device
                        stopDiscovery()
                        result.success(null)
                    }
                    is ConnectionResult.Disconnected -> connectionFailure(result, connection.failure)
                }
            } catch (error: Exception) {
                // DMK 0.0.4 can throw after opening GATT but before returning a
                // ConnectedDevice (BluetoothDevice.name is nullable). Its public
                // disconnect API routes by uid/connectivity, so request closure of that
                // attempted connection even though no session was returned.
                connectedDevice = null
                discoveredDevices.remove(device.uid)
                val attempted = connectionToClose ?: ConnectedDevice(
                    uid = device.uid, name = device.name,
                    ledgerDevice = device.ledgerDevice,
                    connectivityType = device.connectivityType,
                )
                connectionToClose = attempted
                val cleanupRequested = withContext(NonCancellable) {
                    try {
                        closeConnection(attempted)
                        true
                    } catch (_: Exception) {
                        false
                    }
                }
                result.error(
                    if (error is CancellationException) "cancelled" else "disconnected",
                    if (cleanupRequested) {
                        "Could not finish connecting to your Ledger. Search for your Ledger again and reconnect."
                    } else {
                        "Could not close the previous Ledger connection. Turn Bluetooth off and on on your Ledger, then search again."
                    },
                    null,
                )
                if (error is CancellationException) throw error
            }
        } }
    }

    private suspend fun closeConnection(device: ConnectedDevice) {
        connectionToClose = device
        withTimeout(5000) {
            dmk.disconnectDevice(device)
            val manager = activity.getSystemService(BluetoothManager::class.java)
            // SDK session removal alone is not proof that Android closed GATT.
            while (manager.getConnectedDevices(BluetoothProfile.GATT).any { it.address == device.uid } ||
                dmk.getConnectedDevices().any { it.uid == device.uid }) {
                delay(50)
            }
        }
        connectionToClose = null
    }

    private fun disconnect(result: MethodChannel.Result) {
        cancelSigningOperation()
        scope.launch { connectionMutex.withLock {
            val device = connectionToClose ?: connectedDevice
            connectedDevice = null
            try {
                if (device != null) closeConnection(device)
                result.success(null)
            } catch (error: Exception) {
                result.error("disconnected", "Your Ledger connection is still closing. Turn Bluetooth off and on on your Ledger, then reconnect.", null)
                if (error is CancellationException) throw error
            }
        } }
    }

    private fun currentApp(result: MethodChannel.Result) {
        val device = requireConnected(result) ?: return
        scope.launch {
            when (val operation = dmk.executeCommand(device.uid, GetAppAndVersionCommand())) {
                is DeviceOperationResult.Success -> result.success(operation.value.asFlutterMap())
                is DeviceOperationResult.Failure -> operationFailure(result, operation.reason)
            }
        }
    }

    private fun openZcashApp(result: MethodChannel.Result) {
        val device = requireConnected(result) ?: return
        scope.launch {
            val terminal = dmk.executeDeviceAction(device.uid, OpenApplicationDeviceAction("Zcash"))
                .first { it is DeviceActionResult.Success || it is DeviceActionResult.Failure }
            when (terminal) {
                is DeviceActionResult.Failure -> operationFailure(result, terminal.reason)
                is DeviceActionResult.Success -> {
                    when (val app = dmk.executeCommand(device.uid, GetAppAndVersionCommand())) {
                        is DeviceOperationResult.Success -> result.success(app.value.asFlutterMap())
                        is DeviceOperationResult.Failure -> operationFailure(result, app.reason)
                    }
                }
                is DeviceActionResult.IntermediateValue -> error("terminal flow predicate")
            }
        }
    }

    private fun exchangeUfvk(call: MethodCall, result: MethodChannel.Result) {
        val device = requireConnected(result) ?: return
        val first = parseCommand(call.argument("first"), result) ?: return
        val continuation = parseCommand(call.argument("continuation"), result) ?: return
        scope.launch {
            val responses = mutableListOf<ByteArray>()
            val firstResponse = exchange(device.uid, first, result) ?: return@launch
            responses += firstResponse
            if (!firstResponse.hasSuccessStatus()) {
                result.success(responses.map { it.asUnsignedList() })
                return@launch
            }
            if (firstResponse.size < 4) {
                result.success(responses.map { it.asUnsignedList() })
                return@launch
            }
            val expectedPayloadLength = 2 + ((firstResponse[0].toInt() and 0xff) shl 8) +
                (firstResponse[1].toInt() and 0xff)
            if (expectedPayloadLength > MAX_UFVK_RESPONSE) {
                result.success(responses.map { it.asUnsignedList() })
                return@launch
            }
            var payloadLength = firstResponse.size - 2
            while (payloadLength < expectedPayloadLength) {
                val response = exchange(device.uid, continuation, result) ?: return@launch
                responses += response
                if (!response.hasSuccessStatus()) {
                    result.success(responses.map { it.asUnsignedList() })
                    return@launch
                }
                if (response.size == APDU_STATUS_SIZE) {
                    result.success(responses.map { it.asUnsignedList() })
                    return@launch
                }
                payloadLength += response.size - 2
            }
            result.success(responses.map { it.asUnsignedList() })
        }
    }

    private fun exchangeApdus(call: MethodCall, result: MethodChannel.Result) {
        val device = requireConnected(result) ?: return
        val values = call.argument<List<*>>("commands")
        if (values.isNullOrEmpty()) {
            result.error("unavailable", "Ledger signing APDU list is empty or invalid.", null)
            return
        }
        val commands = mutableListOf<ApduCommand>()
        for (value in values) {
            val command = parseCommand(value as? Map<*, *>, result) ?: return
            commands += command
        }
        if (signingJob != null) {
            result.error("unavailable", "A Ledger signing operation is already active.", null)
            return
        }

        val generation = ++signingGeneration
        signingResult = result
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val responses = mutableListOf<ByteArray>()
                for (command in commands) {
                    currentCoroutineContext().ensureActive()
                    when (val operation = sendApdu(device.uid, command)) {
                        is DeviceOperationResult.Success -> {
                            currentCoroutineContext().ensureActive()
                            responses += operation.value
                            if (!operation.value.hasSuccessStatus()) break
                        }
                        is DeviceOperationResult.Failure -> {
                            finishSigningFailure(generation, operation.reason)
                            return@launch
                        }
                    }
                }
                finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
            } catch (_: CancellationException) {
                finishSigningCancelled(generation)
            } finally {
                if (signingJob === coroutineContext[Job]) signingJob = null
            }
        }
        signingJob = job
        job.start()
    }

    private fun cancelSigning(result: MethodChannel.Result) {
        cancelSigningOperation()
        result.success(null)
    }

    private fun cancelSigningOperation() {
        val pending = signingResult ?: return
        signingGeneration++
        signingResult = null
        val job = signingJob
        pending.error("cancelled", "Ledger signing was cancelled.", null)
        job?.cancel()
    }

    private fun finishSigningSuccess(generation: Long, value: Any) {
        val result = takeSigningResult(generation) ?: return
        result.success(value)
    }

    private fun finishSigningFailure(
        generation: Long,
        reason: DeviceOperationFailureReason,
    ) {
        val result = takeSigningResult(generation) ?: return
        operationFailure(result, reason)
    }

    private fun finishSigningCancelled(generation: Long) {
        val result = takeSigningResult(generation) ?: return
        result.error("cancelled", "Ledger signing was cancelled.", null)
    }

    private fun takeSigningResult(generation: Long): MethodChannel.Result? {
        if (generation != signingGeneration) return null
        val result = signingResult ?: return null
        signingResult = null
        signingJob = null
        return result
    }

    private suspend fun exchange(
        uid: String,
        command: ApduCommand,
        result: MethodChannel.Result,
    ): ByteArray? {
        val operation = sendApdu(uid, command)
        return when (operation) {
            is DeviceOperationResult.Success -> operation.value
            is DeviceOperationResult.Failure -> {
                operationFailure(result, operation.reason)
                null
            }
        }
    }

    private suspend fun sendApdu(uid: String, command: ApduCommand) =
        dmk.sendApdu(
            uid,
            uniqueApduPayload(
                apdu {
                    classInstruction = command.cla.toByte()
                    instructionMethod = command.ins.toByte()
                    parameter1 = command.p1.toByte()
                    parameter2 = command.p2.toByte()
                    data = command.data
                },
            ),
        )

    private fun ByteArray.hasSuccessStatus(): Boolean =
        size >= 2 && this[size - 2] == 0x90.toByte() && last() == 0.toByte()

    private fun ByteArray.asUnsignedList(): List<Int> = map { it.toInt() and 0xff }

    private fun requireConnected(result: MethodChannel.Result): ConnectedDevice? {
        if (connectionMutex.isLocked || connectionToClose != null) {
            result.error("disconnected", "Your Ledger connection is not ready. Reconnect before trying again.", null)
            return null
        }
        if (connectedDevice == null) {
            connectedDevice = dmk.getConnectedDevices().singleOrNull()
        }
        return connectedDevice ?: run {
            result.error("disconnected", "Select and connect a Ledger first.", null)
            null
        }
    }

    private fun connectionFailure(result: MethodChannel.Result, failure: ConnectionResult.Failure) {
        when (failure) {
            ConnectionResult.Failure.PairingFailed -> result.error(
                "pairing_rejected",
                "Ledger Bluetooth pairing was rejected or failed.",
                null,
            )
            ConnectionResult.Failure.PermissionNotGranted -> result.error(
                "permission_denied",
                "Bluetooth permission is required to connect to Ledger.",
                null,
            )
            ConnectionResult.Failure.DeviceConnectivityBluetoothDisabled -> result.error(
                "bluetooth_off",
                "Turn on Bluetooth to connect to Ledger.",
                null,
            )
            else -> result.error("disconnected", "Could not connect to the selected Ledger: $failure", null)
        }
    }

    private fun operationFailure(result: MethodChannel.Result, reason: DeviceOperationFailureReason) {
        when (reason) {
            DeviceOperationFailureReason.DeviceLocked -> result.error(
                "locked",
                "Unlock your Ledger and reopen the Zcash app.",
                null,
            )
            DeviceOperationFailureReason.DeviceDisconnected,
            DeviceOperationFailureReason.DeviceNotFound,
            DeviceOperationFailureReason.NoResponse,
            -> result.error("disconnected", "The Ledger disconnected. Reconnect and try again.", null)
            else -> result.error("unavailable", "Ledger operation failed: $reason", null)
        }
    }

    private fun parseCommand(value: Map<*, *>?, result: MethodChannel.Result): ApduCommand? {
        val cla = value?.get("cla") as? Int
        val ins = value?.get("ins") as? Int
        val p1 = value?.get("p1") as? Int
        val p2 = value?.get("p2") as? Int
        val data = when (val raw = value?.get("data")) {
            is ByteArray -> raw
            is List<*> -> if (raw.all { it is Number }) {
                raw.map { (it as Number).toByte() }.toByteArray()
            } else {
                null
            }
            else -> null
        }
        if (
            cla == null || cla !in 0..255 ||
            ins == null || ins !in 0..255 ||
            p1 == null || p1 !in 0..255 ||
            p2 == null || p2 !in 0..255 ||
            data == null || data.size > 255
        ) {
            result.error("unavailable", "Ledger APDU arguments are invalid.", null)
            return null
        }
        return ApduCommand(cla, ins, p1, p2, data)
    }

    private fun emit(value: Map<String, Any?>) {
        eventSink?.success(value)
    }

    private fun emitError(code: String, message: String) {
        emit(mapOf("type" to "error", "code" to code, "message" to message))
    }

    private fun requiredPermissions(): List<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        listOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun AppAndVersion.asFlutterMap(): Map<String, String> =
        mapOf("name" to appName, "version" to appVersion)

    private data class ApduCommand(
        val cla: Int,
        val ins: Int,
        val p1: Int,
        val p2: Int,
        val data: ByteArray,
    )

    companion object {
        const val METHOD_CHANNEL = "com.zcash.wallet/ledger_mobile"
        const val EVENT_CHANNEL = "com.zcash.wallet/ledger_mobile/discovery"
        private const val PERMISSION_REQUEST = 0x4c45
        private const val APDU_STATUS_SIZE = 2
        private const val MAX_UFVK_RESPONSE = 8 * 1024
    }
}

private object LedgerDmkHolder {
    private var instance: DeviceManagementKitApi? = null

    @Synchronized
    fun get(activity: Activity): DeviceManagementKitApi {
        return instance ?: deviceManagementKit {
            context = activity.applicationContext
            enableLog = activity.applicationInfo.flags and
                android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
        }.also { instance = it }
    }
}
