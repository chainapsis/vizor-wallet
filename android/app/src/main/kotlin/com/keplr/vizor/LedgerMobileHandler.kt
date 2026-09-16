package com.keplr.vizor

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.pm.PackageManager
import android.content.Intent
import android.provider.Settings
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

class LedgerMobileHandler(
    private val activity: Activity,
    private val dmk: DeviceManagementKitApi = LedgerDmkHolder.get(activity),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    private val hasPermission: (String) -> Boolean = {
        ActivityCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
    },
    private val requestPermissions: (Array<String>, Int) -> Unit = { permissions, requestCode ->
        ActivityCompat.requestPermissions(activity, permissions, requestCode)
    },
    private val isGattConnected: (String) -> Boolean = { uid ->
        activity.getSystemService(BluetoothManager::class.java)
            .getConnectedDevices(BluetoothProfile.GATT)
            .any { it.address == uid }
    },
    initialDiscoveredDevices: Map<String, DiscoveryDevice> = emptyMap(),
    initialConnectedDevice: ConnectedDevice? = null,
) : EventChannel.StreamHandler {
    private var discoveryJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null
    private var discoveryRequested = false
    private val discoveredDevices = initialDiscoveredDevices.toMutableMap()
    private var connectedDevice: ConnectedDevice? = initialConnectedDevice
    private var permissionResult: MethodChannel.Result? = null
    private var operationJob: Job? = null
    private var operationResult: MethodChannel.Result? = null
    private var operationGeneration = 0L
    private val connectionMutex = Mutex()
    private var connectionToClose: ConnectedDevice? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openBluetoothSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(true)
                } catch (_: android.content.ActivityNotFoundException) {
                    result.success(false)
                }
            }
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
        val exchangeToDrain = cancelOperation()
        permissionResult?.error("cancelled", "The Ledger permission request was cancelled.", null)
        permissionResult = null
        val device = connectionToClose ?: connectedDevice
        connectedDevice = null
        if (device == null) {
            scope.cancel()
            return
        }
        scope.launch(NonCancellable) {
            try {
                connectionMutex.withLock {
                    exchangeToDrain?.join()
                    closeConnection(device)
                }
            } catch (_: Exception) {
                // The Activity is already closing. Keep teardown best-effort;
                // a later handler still waits for DMK/GATT state before reuse.
            } finally {
                scope.cancel()
            }
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val missing = requiredPermissions().filterNot(hasPermission)
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("unavailable", "A Ledger permission request is already active.", null)
            return
        }
        permissionResult = result
        requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        if (!hasRequiredPermissions()) {
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
        if (!hasRequiredPermissions()) {
            result.error("permission_denied", "Bluetooth permission is required to connect to Ledger.", null)
            return
        }
        val deviceId = call.argument<String>("deviceId")
        val device = deviceId?.let(discoveredDevices::get)
        if (device == null) {
            result.error("disconnected", "The selected Ledger is no longer available.", null)
            return
        }
        val exchangeToDrain = cancelOperation()
        scope.launch { connectionMutex.withLock {
            try {
                exchangeToDrain?.join()
                val previousDevice = connectionToClose ?: connectedDevice
                if (previousDevice != null) {
                    connectedDevice = null
                    closeConnection(previousDevice)
                }
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
            // SDK session removal alone is not proof that Android closed GATT.
            while (isGattConnected(device.uid) ||
                dmk.getConnectedDevices().any { it.uid == device.uid }) {
                delay(50)
            }
        }
        connectionToClose = null
    }

    private fun disconnect(result: MethodChannel.Result) {
        val exchangeToDrain = cancelOperation()
        scope.launch { connectionMutex.withLock {
            exchangeToDrain?.join()
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
        startOperation(result) { generation ->
            when (val operation = dmk.executeCommand(device.uid, GetAppAndVersionCommand())) {
                is DeviceOperationResult.Success -> operation.value.asFlutterMap()
                is DeviceOperationResult.Failure -> {
                    finishOperationFailure(generation, operation.reason)
                    null
                }
            }
        }
    }

    private fun openZcashApp(result: MethodChannel.Result) {
        val device = requireConnected(result) ?: return
        startOperation(result) { generation ->
            val terminal = dmk.executeDeviceAction(device.uid, OpenApplicationDeviceAction("Zcash"))
                .first { it is DeviceActionResult.Success || it is DeviceActionResult.Failure }
            currentCoroutineContext().ensureActive()
            when (terminal) {
                is DeviceActionResult.Failure -> {
                    finishOperationFailure(generation, terminal.reason)
                    null
                }
                is DeviceActionResult.Success -> {
                    when (val app = dmk.executeCommand(device.uid, GetAppAndVersionCommand())) {
                        is DeviceOperationResult.Success -> app.value.asFlutterMap()
                        is DeviceOperationResult.Failure -> {
                            finishOperationFailure(generation, app.reason)
                            null
                        }
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
        startOperation(result) { generation ->
            val responses = mutableListOf<ByteArray>()
            val firstResponse = exchange(device.uid, first, generation) ?: return@startOperation null
            responses += firstResponse
            if (!firstResponse.hasSuccessStatus() || firstResponse.size < 4) {
                return@startOperation responses.map { it.asUnsignedList() }
            }
            val expectedPayloadLength = 2 + ((firstResponse[0].toInt() and 0xff) shl 8) +
                (firstResponse[1].toInt() and 0xff)
            if (expectedPayloadLength > MAX_UFVK_RESPONSE) {
                return@startOperation responses.map { it.asUnsignedList() }
            }
            var payloadLength = firstResponse.size - APDU_STATUS_SIZE
            while (payloadLength < expectedPayloadLength) {
                val response = exchange(device.uid, continuation, generation) ?: return@startOperation null
                responses += response
                if (!response.hasSuccessStatus() || response.size == APDU_STATUS_SIZE) {
                    return@startOperation responses.map { it.asUnsignedList() }
                }
                payloadLength += response.size - APDU_STATUS_SIZE
            }
            responses.map { it.asUnsignedList() }
        }
    }

    private fun startOperation(
        result: MethodChannel.Result,
        operation: suspend (Long) -> Any?,
    ) {
        if (operationJob != null) {
            result.error("unavailable", "A Ledger operation is already active.", null)
            return
        }
        val generation = ++operationGeneration
        operationResult = result
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                currentCoroutineContext().ensureActive()
                val value = operation(generation)
                currentCoroutineContext().ensureActive()
                if (value != null) {
                    finishOperationSuccess(generation, value)
                }
            } catch (_: CancellationException) {
                finishOperationCancelled(generation)
            } catch (_: Exception) {
                takeOperationResult(generation)?.error(
                    "unavailable", "Could not complete the Ledger operation. Reconnect and try again.", null,
                )
            } finally {
                if (operationJob === coroutineContext[Job]) operationJob = null
            }
        }
        operationJob = job
        job.start()
    }

    private fun cancelSigning(result: MethodChannel.Result) {
        cancelOperation()
        result.success(null)
    }

    private fun cancelOperation(): Job? {
        val job = operationJob
        val pending = operationResult
        if (pending != null) {
            operationGeneration++
            operationResult = null
            pending.error("cancelled", "The Ledger operation was cancelled.", null)
            job?.cancel()
        }
        return job
    }

    private fun finishOperationSuccess(generation: Long, value: Any) {
        val result = takeOperationResult(generation) ?: return
        result.success(value)
    }

    private fun finishOperationFailure(
        generation: Long,
        reason: DeviceOperationFailureReason,
    ) {
        val result = takeOperationResult(generation) ?: return
        operationFailure(result, reason)
    }

    private fun finishOperationCancelled(generation: Long) {
        val result = takeOperationResult(generation) ?: return
        result.error("cancelled", "The Ledger operation was cancelled.", null)
    }

    private fun takeOperationResult(generation: Long): MethodChannel.Result? {
        if (generation != operationGeneration) return null
        val result = operationResult ?: return null
        operationResult = null
        operationJob = null
        return result
    }

    private suspend fun exchange(
        uid: String,
        command: ApduCommand,
        generation: Long,
    ): ByteArray? {
        currentCoroutineContext().ensureActive()
        val operation = sendApdu(uid, command)
        currentCoroutineContext().ensureActive()
        return when (operation) {
            is DeviceOperationResult.Success -> operation.value
            is DeviceOperationResult.Failure -> {
                finishOperationFailure(generation, operation.reason)
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
        if (!hasRequiredPermissions()) {
            result.error("permission_denied", "Bluetooth permission was revoked. Allow it before reconnecting.", null)
            return null
        }
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

    private fun hasRequiredPermissions(): Boolean = requiredPermissions().all(hasPermission)

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
