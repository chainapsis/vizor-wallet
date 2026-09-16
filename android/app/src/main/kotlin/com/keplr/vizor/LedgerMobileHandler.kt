package com.keplr.vizor

import android.Manifest
import android.app.Activity
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
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.launch

class LedgerMobileHandler(
    private val activity: Activity,
    private val dmk: DeviceManagementKitApi = LedgerDmkHolder.get(activity),
) : EventChannel.StreamHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var connectionJob: Job? = null
    private var connectionResult: MethodChannel.Result? = null
    private var discoveryJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null
    private var discoveryRequested = false
    private val discoveredDevices = mutableMapOf<String, DiscoveryDevice>()
    private var connectedDevice: ConnectedDevice? = null
    private var permissionResult: MethodChannel.Result? = null
    private var signingJob: Job? = null
    private var signingResult: MethodChannel.Result? = null
    private var signingGeneration = 0L

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
        cancelConnection()
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
        if (connectionJob != null || signingJob != null) {
            result.error("unavailable", "A Ledger operation is already active.", null)
            return
        }
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
        if (deviceId.isNullOrBlank()) {
            result.error("disconnected", "The selected Ledger is no longer available.", null)
            return
        }
        if (connectionJob != null || signingJob != null) {
            result.error("unavailable", "A Ledger operation is already active.", null)
            return
        }
        // The onboarding scan is optional: a fresh handler must also be able to
        // connect using only the ID persisted with the account.
        stopDiscovery()
        connectionResult = result
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val device = discoveredDevices[deviceId] ?: rediscoverDevice(deviceId)
                currentCoroutineContext().ensureActive()
                when (val connection = dmk.connectDevice(device)) {
                    is ConnectionResult.Connected -> {
                        if (connectionResult == null) {
                            withContext(NonCancellable) { dmk.disconnectDevice(connection.device) }
                        } else {
                            connectedDevice = connection.device
                            takeConnectionResult()?.success(null)
                        }
                    }
                    is ConnectionResult.Disconnected -> {
                        takeConnectionResult()?.let { connectionFailure(it, connection.failure) }
                    }
                }
            } catch (_: CancellationException) {
                takeConnectionResult()?.error("cancelled", "Ledger connection was cancelled.", null)
            } catch (error: LedgerDiscoveryException) {
                takeConnectionResult()?.error(error.code, error.message, null)
            } catch (_: SecurityException) {
                takeConnectionResult()?.error(
                    "permission_denied", "Bluetooth permission is required to connect to Ledger.", null,
                )
            } catch (_: Exception) {
                takeConnectionResult()?.error("unavailable", "Could not connect to Ledger. Try again.", null)
            }
        }
        connectionJob = job
        job.invokeOnCompletion { if (connectionJob === job) connectionJob = null }
        job.start()
    }

    private suspend fun rediscoverDevice(deviceId: String): DiscoveryDevice {
        try {
            return withTimeoutOrNull(15_000L) {
                dmk.startDiscoveringDevices().mapNotNull { update ->
                    when (update) {
                        is DiscoveryResult.DevicesDiscovered -> update.devices.firstOrNull {
                            it.uid == deviceId && it.connectivityType is ConnectivityType.Bluetooth &&
                                it.ledgerDevice.bleInformation != null
                        }
                        DiscoveryResult.Ended -> throw LedgerDiscoveryException(
                            "disconnected", "The selected Ledger is no longer available.",
                        )
                        DiscoveryResult.Failure.BluetoothDisabled -> throw LedgerDiscoveryException(
                            "bluetooth_off", "Turn on Bluetooth to connect to Ledger.",
                        )
                        DiscoveryResult.Failure.BluetoothPermissionNotGranted -> throw LedgerDiscoveryException(
                            "permission_denied", "Bluetooth permission is required to connect to Ledger.",
                        )
                        DiscoveryResult.Failure.LocationDisabled -> throw LedgerDiscoveryException(
                            "permission_denied", "Location must be enabled for Bluetooth discovery on this Android version.",
                        )
                        DiscoveryResult.Failure.BluetoothBleNotSupported -> throw LedgerDiscoveryException(
                            "unavailable", "This Android device does not support Bluetooth LE.",
                        )
                        is DiscoveryResult.Failure.Unknown -> throw LedgerDiscoveryException(
                            "unavailable", update.message,
                        )
                    }
                }.first().also { discoveredDevices[it.uid] = it }
            } ?: throw LedgerDiscoveryException(
                "disconnected", "Could not find the saved Ledger. Turn it on and try again.",
            )
        } finally {
            dmk.stopDiscoveringDevices()
        }
    }

    private fun takeConnectionResult(): MethodChannel.Result? {
        val result = connectionResult
        connectionResult = null
        return result
    }

    private fun cancelConnection() {
        takeConnectionResult()?.error("cancelled", "Ledger connection was cancelled.", null)
        connectionJob?.cancel()
    }

    private class LedgerDiscoveryException(val code: String, message: String) : Exception(message)

    private fun disconnect(result: MethodChannel.Result) {
        cancelConnection()
        cancelSigningOperation()
        val device = connectedDevice
        connectedDevice = null
        if (device == null) {
            result.success(null)
            return
        }
        scope.launch {
            dmk.disconnectDevice(device)
            result.success(null)
        }
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
        launchExchange(result) { generation ->
            val responses = mutableListOf<ByteArray>()
            val firstResponse = exchange(device.uid, first, generation) ?: return@launchExchange
            responses += firstResponse
            if (!firstResponse.hasSuccessStatus()) {
                finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
                return@launchExchange
            }
            if (firstResponse.size < 4) {
                finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
                return@launchExchange
            }
            val expectedPayloadLength = 2 + ((firstResponse[0].toInt() and 0xff) shl 8) +
                (firstResponse[1].toInt() and 0xff)
            if (expectedPayloadLength > MAX_UFVK_RESPONSE) {
                finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
                return@launchExchange
            }
            var payloadLength = firstResponse.size - 2
            while (payloadLength < expectedPayloadLength) {
                val response = exchange(device.uid, continuation, generation) ?: return@launchExchange
                responses += response
                if (!response.hasSuccessStatus()) {
                    finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
                    return@launchExchange
                }
                if (response.size == APDU_STATUS_SIZE) {
                    finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
                    return@launchExchange
                }
                payloadLength += response.size - 2
            }
            finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
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
        launchExchange(result) { generation ->
            val responses = mutableListOf<ByteArray>()
            for (command in commands) {
                val response = exchange(device.uid, command, generation) ?: return@launchExchange
                responses += response
                if (!response.hasSuccessStatus()) break
            }
            finishSigningSuccess(generation, responses.map { it.asUnsignedList() })
        }
    }

    // UFVK export and signing share one APDU owner, including while a cancelled
    // SDK callback is still draining. Only job completion releases this slot.
    private fun launchExchange(result: MethodChannel.Result, block: suspend (Long) -> Unit) {
        if (signingJob != null || connectionJob != null) {
            result.error("unavailable", "A Ledger operation is already active.", null)
            return
        }
        val generation = ++signingGeneration
        signingResult = result
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                block(generation)
            } catch (_: CancellationException) {
                finishSigningCancelled(generation)
            } catch (_: Exception) {
                takeSigningResult(generation)?.error(
                    "unavailable", "Could not exchange data with Ledger. Try again.", null,
                )
            }
        }
        signingJob = job
        job.invokeOnCompletion {
            // Also runs if cancellation happened before the coroutine started.
            if (signingJob === job) {
                finishSigningCancelled(generation)
                signingJob = null
            }
        }
        job.start()
    }

    private fun cancelSigning(result: MethodChannel.Result) {
        cancelConnection()
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
                finishSigningFailure(generation, operation.reason)
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
