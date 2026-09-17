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
import com.ledger.devicemanagement.api.apdu.chunkApduPayload
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
    var onSigningProgress: ((String, String) -> Unit)? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var operation: DeviceRequest? = null
    private var closed = false
    private var discoveryGeneration = 0L
    private var discoveryJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null
    private var discoveryRequested = false
    private val discoveredDevices = mutableMapOf<String, DiscoveryDevice>()
    private var connectedDevice: ConnectedDevice? = null
    private var permissionResult: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("cancelled", "Ledger connection was closed.", null)
            return
        }
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
        if (closed) return
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
        if (closed) return
        closed = true
        stopDiscovery()
        eventSink = null
        permissionResult?.error("cancelled", "Ledger connection was closed.", null)
        permissionResult = null
        // Cleanup outlives this Activity, but no channel result does.
        disconnect(null)
        operation?.cancelResult()
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
        if (sdkJobs[dmk] != null) {
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
        discoveredDevices.clear()
        discoveryRequested = true
        if (eventSink != null) beginDiscovery()
        result.success(null)
    }

    private fun beginDiscovery() {
        if (sdkJobs[dmk] != null) {
            discoveryRequested = false
            emitError("unavailable", "A Ledger operation is already active.")
            return
        }
        val generation = ++discoveryGeneration
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                dmk.startDiscoveringDevices().collect { update ->
                    currentCoroutineContext().ensureActive()
                    if (generation != discoveryGeneration || closed) return@collect
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
            } catch (_: CancellationException) {
                // stopDiscovery owns invalidation and SDK shutdown.
            } catch (_: Exception) {
                if (generation == discoveryGeneration && !closed) {
                    emitError("unavailable", "Could not discover Ledger devices. Try again.")
                }
            }
        }
        discoveryJob = job
        sdkJobs[dmk] = job
        job.invokeOnCompletion {
            if (discoveryJob === job) discoveryJob = null
            if (sdkJobs[dmk] === job) sdkJobs.remove(dmk)
        }
        job.start()
    }

    private fun stopDiscovery() {
        discoveryGeneration++
        val wasDiscovering = discoveryJob != null || discoveryRequested
        discoveryJob?.cancel()
        discoveryRequested = false
        if (wasDiscovering) dmk.stopDiscoveringDevices()
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val deviceId = call.argument<String>("deviceId")
        if (deviceId.isNullOrBlank()) {
            result.error("disconnected", "The selected Ledger is no longer available.", null)
            return
        }
        launchOperation(result) { request ->
            val device = discoveredDevices[deviceId] ?: rediscoverDevice(deviceId)
            currentCoroutineContext().ensureActive()
            when (val connection = dmk.connectDevice(device)) {
                is ConnectionResult.Connected -> {
                    if (!request.pending) {
                        withContext(NonCancellable) { dmk.disconnectDevice(connection.device) }
                    } else {
                        currentCoroutineContext().ensureActive()
                        connectedDevice = connection.device
                        request.success(null)
                    }
                }
                is ConnectionResult.Disconnected -> connectionFailure(request, connection.failure)
            }
        }
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

    private class LedgerDiscoveryException(val code: String, message: String) : Exception(message)

    private fun disconnect(result: MethodChannel.Result?) {
        val previous = operation
        if (previous?.cleanup == true) {
            result?.error("unavailable", "A Ledger operation is already active.", null)
            return
        }
        previous?.cancel()
        stopDiscovery()
        val scan = discoveryJob
        val device = connectedDevice
        connectedDevice = null
        // Reserve the slot synchronously, including while the cancelled SDK
        // request drains. Cleanup itself cannot be cancelled by UI navigation.
        launchOperation(result, cleanup = true) { request ->
            previous?.job?.join()
            scan?.join()
            if (device != null) dmk.disconnectDevice(device)
            request.success(null)
        }
    }

    private fun currentApp(result: MethodChannel.Result) {
        launchOperation(result) { request ->
            val device = requireConnected(request) ?: return@launchOperation
            queryApp(device, request)
        }
    }

    private suspend fun queryApp(device: ConnectedDevice, request: DeviceRequest) {
        currentCoroutineContext().ensureActive()
        val app = dmk.executeCommand(device.uid, GetAppAndVersionCommand())
        currentCoroutineContext().ensureActive()
        when (app) {
            is DeviceOperationResult.Success -> request.success(app.value.asFlutterMap())
            is DeviceOperationResult.Failure -> operationFailure(request, app.reason)
        }
    }

    private fun openZcashApp(result: MethodChannel.Result) {
        launchOperation(result) { request ->
            val device = requireConnected(request) ?: return@launchOperation
            val terminal = dmk.executeDeviceAction(device.uid, OpenApplicationDeviceAction("Zcash"))
                .first { it is DeviceActionResult.Success || it is DeviceActionResult.Failure }
            currentCoroutineContext().ensureActive()
            when (terminal) {
                is DeviceActionResult.Failure -> operationFailure(request, terminal.reason)
                is DeviceActionResult.Success -> queryApp(device, request)
                is DeviceActionResult.IntermediateValue -> error("terminal flow predicate")
            }
        }
    }

    private fun exchangeUfvk(call: MethodCall, result: MethodChannel.Result) {
        val first = parseCommand(call.argument("first"), result) ?: return
        val continuation = parseCommand(call.argument("continuation"), result) ?: return
        launchOperation(result) { request ->
            val device = requireConnected(request) ?: return@launchOperation
            val responses = mutableListOf<ByteArray>()
            val firstResponse = exchange(device.uid, first, request) ?: return@launchOperation
            responses += firstResponse
            if (!firstResponse.hasSuccessStatus()) {
                request.success(responses.map { it.asUnsignedList() })
                return@launchOperation
            }
            if (firstResponse.size < 4) {
                request.success(responses.map { it.asUnsignedList() })
                return@launchOperation
            }
            val expectedPayloadLength = 2 + ((firstResponse[0].toInt() and 0xff) shl 8) +
                (firstResponse[1].toInt() and 0xff)
            if (expectedPayloadLength > MAX_UFVK_RESPONSE) {
                request.success(responses.map { it.asUnsignedList() })
                return@launchOperation
            }
            var payloadLength = firstResponse.size - 2
            while (payloadLength < expectedPayloadLength) {
                val response = exchange(device.uid, continuation, request) ?: return@launchOperation
                responses += response
                if (!response.hasSuccessStatus()) {
                    request.success(responses.map { it.asUnsignedList() })
                    return@launchOperation
                }
                if (response.size == APDU_STATUS_SIZE) {
                    request.success(responses.map { it.asUnsignedList() })
                    return@launchOperation
                }
                payloadLength += response.size - 2
            }
            request.success(responses.map { it.asUnsignedList() })
        }
    }

    private fun exchangeApdus(call: MethodCall, result: MethodChannel.Result) {
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
        val progressId = call.argument<String>("progressId")
        launchOperation(result) { request ->
            val device = requireConnected(request) ?: return@launchOperation
            fun report(phase: String) { progressId?.let { onSigningProgress?.invoke(it, phase) } }
            report("sending")
            val responses = mutableListOf<ByteArray>()
            for (command in commands) {
                currentCoroutineContext().ensureActive()
                val startsReview = (command.ins == 0x56 || command.ins == 0x58) && command.p2 == 1
                if (startsReview) report("reviewing")
                val response = exchange(device.uid, command, request) ?: return@launchOperation
                if (startsReview && response.hasSuccessStatus()) report("finishing")
                responses += response
                if (!response.hasSuccessStatus()) break
            }
            request.success(responses.map { it.asUnsignedList() })
        }
    }

    // Every device command uses this owner, not just signing APDUs. Completion
    // of a cancelled SDK job (not delivery of its cancellation result) releases
    // the slot. Main-thread confinement makes result delivery exactly-once.
    private fun launchOperation(
        result: MethodChannel.Result?,
        cleanup: Boolean = false,
        block: suspend (DeviceRequest) -> Unit,
    ) {
        val sdkJob = sdkJobs[dmk]
        if (!cleanup && (operation != null || (sdkJob != null && sdkJob !== discoveryJob))) {
            result?.error("unavailable", "A Ledger operation is already active.", null)
            return
        }
        stopDiscovery()
        val scan = discoveryJob
        val request = DeviceRequest(result, cleanup)
        val job = scope.launch(
            context = if (cleanup) NonCancellable else kotlin.coroutines.EmptyCoroutineContext,
            start = CoroutineStart.LAZY,
        ) {
            try {
                if (cleanup) sdkJob?.join()
                scan?.join()
                currentCoroutineContext().ensureActive()
                block(request)
            } catch (_: CancellationException) {
                request.cancelResult()
            } catch (error: LedgerDiscoveryException) {
                request.error(error.code, error.message, null)
            } catch (_: SecurityException) {
                request.error("permission_denied", "Bluetooth permission is required to connect to Ledger.", null)
            } catch (_: Exception) {
                request.error("unavailable", "Could not communicate with Ledger. Try again.", null)
            }
        }
        request.job = job
        operation = request
        sdkJobs[dmk] = job
        job.invokeOnCompletion {
            request.cancelResult() // Includes cancellation before dispatch.
            if (operation === request) operation = null
            if (sdkJobs[dmk] === job) sdkJobs.remove(dmk)
        }
        job.start()
    }

    private fun cancelSigning(result: MethodChannel.Result) {
        operation?.let { if (!it.cleanup) it.cancel() }
        result.success(null)
    }

    private class DeviceRequest(
        private var result: MethodChannel.Result?,
        val cleanup: Boolean,
    ) : MethodChannel.Result {
        lateinit var job: Job
        val pending: Boolean get() = result != null

        private fun takeResult(): MethodChannel.Result? = result.also { result = null }
        override fun success(value: Any?) { takeResult()?.success(value) }
        override fun error(code: String, message: String?, details: Any?) {
            takeResult()?.error(code, message, details)
        }
        override fun notImplemented() { takeResult()?.notImplemented() }
        fun cancelResult() { error("cancelled", "Ledger operation was cancelled.", null) }
        fun cancel() {
            cancelResult()
            job.cancel()
        }
    }

    private suspend fun exchange(
        uid: String,
        command: ApduCommand,
        request: DeviceRequest,
    ): ByteArray? {
        currentCoroutineContext().ensureActive()
        val operation = sendApdu(uid, command)
        currentCoroutineContext().ensureActive()
        return when (operation) {
            is DeviceOperationResult.Success -> operation.value
            is DeviceOperationResult.Failure -> {
                operationFailure(request, operation.reason)
                null
            }
        }
    }

    private suspend fun sendApdu(uid: String, command: ApduCommand): DeviceOperationResult<ByteArray> {
        val packet = apdu {
            classInstruction = command.cla.toByte()
            instructionMethod = command.ins.toByte()
            parameter1 = command.p1.toByte()
            parameter2 = command.p2.toByte()
            data = command.data
        }
        // DMK 0.0.4's UniqueApduPayload requires fewer than 255 data bytes.
        // Its chunk payload emits exactly one APDU for 255 bytes. Keep the
        // Rust plan's headers intact: P1/P2 describe the whole Zcash stream,
        // not the SDK's first/last chunk. parseCommand rejects larger inputs.
        val payload = if (command.data.size == 255) {
            chunkApduPayload { _, _ -> packet }
        } else {
            uniqueApduPayload(packet)
        }
        return dmk.sendApdu(uid, payload)
    }

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
        // DMK survives Activity recreation. A new handler must also wait for
        // the previous handler's non-cooperative command/cleanup to finish.
        // Accessed only on Main; entries are removed on actual job completion.
        private val sdkJobs = mutableMapOf<DeviceManagementKitApi, Job>()
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
