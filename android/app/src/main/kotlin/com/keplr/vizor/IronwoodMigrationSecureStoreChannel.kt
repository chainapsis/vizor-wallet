package com.keplr.vizor

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal class IronwoodMigrationSecureStoreChannel(
    private val context: Context,
    private val store: IronwoodMigrationSecureStore = IronwoodMigrationSecureStore(context),
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
    private val outboxRepository = IronwoodMigrationOutboxRepository(store)

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        val action: () -> Any? = when (call.method) {
            "stageCredentialManifest" -> {
                {
                    val arguments = arguments(call)
                    val network = network(arguments)
                    val accountUuid = string(arguments, "accountUuid")
                    val manifestJson = string(arguments, "manifestJson")
                    validateManifest(manifestJson, network, accountUuid)
                    store.writeManifest(network, accountUuid, manifestJson)
                    true
                }
            }
            "readCredentialManifest" -> {
                {
                    val arguments = arguments(call)
                    store.readManifest(
                        network(arguments),
                        string(arguments, "accountUuid"),
                    )
                }
            }
            "deleteCredentialManifest" -> {
                {
                    val arguments = arguments(call)
                    store.deleteManifest(
                        network(arguments),
                        string(arguments, "accountUuid"),
                    )
                    true
                }
            }
            "stageOutboxBatch" -> {
                {
                    val incoming = validateOutboxBatch(arguments(call))
                    outboxRepository.update { snapshot -> stage(snapshot, incoming) }
                    incoming.digests
                }
            }
            "armOutboxBatch" -> {
                {
                    val arguments = arguments(call)
                    val batchId = string(arguments, "batchId")
                    val expectedDigests = stringStringMap(
                        arguments["expectedDigests"],
                        "expectedDigests",
                    )
                    outboxRepository.update { snapshot ->
                        val batch = snapshot.batches.firstOrNull { it.batchId == batchId }
                            ?: throw IllegalArgumentException("Outbox batch not found.")
                        if (
                            expectedDigests.isEmpty() &&
                            batch.nextProofHeight == null
                        ) {
                            throw IllegalArgumentException("Invalid outbox arm request.")
                        }
                        if (expectedDigests.any { (itemId, digest) ->
                                batch.items.none {
                                    it.itemId == itemId &&
                                        it.payloadDigestHex == digest
                                }
                            }) {
                            throw IllegalArgumentException("Invalid outbox arm request.")
                        }
                        batch.armedAtMs = batch.armedAtMs ?: System.currentTimeMillis()
                        batch.items.filter {
                            it.itemId in expectedDigests &&
                                it.status == IronwoodOutboxItemStatus.STAGED
                        }.forEach { it.status = IronwoodOutboxItemStatus.ARMED }
                    }
                    scheduleOutbox()
                    true
                }
            }
            "recoverOutboxBatch" -> {
                {
                    val arguments = arguments(call)
                    val batchId = string(arguments, "batchId")
                    val expectedTxids = stringList(
                        arguments["expectedTxids"],
                        "expectedTxids",
                    ).map(String::lowercase).toSet()
                    val recovered = IronwoodMigrationOutboxExecutionCoordinator.runExclusive {
                        outboxRepository.update { snapshot ->
                            val batch = snapshot.batches.firstOrNull { it.batchId == batchId }
                                ?: return@update false
                            if (
                                batch.network != network(arguments) ||
                                batch.accountUuid != string(arguments, "accountUuid") ||
                                batch.runId != string(arguments, "runId") ||
                                expectedTxids.isEmpty() ||
                                batch.items.isEmpty() ||
                                batch.items.any { it.txidHex !in expectedTxids }
                            ) {
                                throw IllegalArgumentException("Conflicting outbox batch.")
                            }
                            batch.lightwalletdUrl = string(arguments, "lightwalletdUrl")
                            val now = System.currentTimeMillis()
                            batch.items.forEach { item ->
                                when (item.status) {
                                    IronwoodOutboxItemStatus.SUBMITTING -> {
                                        item.status = IronwoodOutboxItemStatus.ARMED
                                        item.attemptCount += 1
                                        item.nextAttemptAtMs = now +
                                            IronwoodOutboxState.retryDelayMs(item.attemptCount)
                                        item.lastError =
                                            "The previous submission outcome is unknown."
                                        item.attemptId = null
                                        item.attemptStartedAtMs = null
                                    }
                                    IronwoodOutboxItemStatus.STAGED ->
                                        item.status = IronwoodOutboxItemStatus.ARMED
                                    else -> Unit
                                }
                            }
                            if (batch.items.any {
                                    it.status == IronwoodOutboxItemStatus.ARMED
                                }) {
                                batch.armedAtMs = batch.armedAtMs ?: now
                            }
                            true
                        }
                    }
                    if (recovered) scheduleOutbox()
                    recovered
                }
            }
            "listOutboxReceipts" -> {
                {
                    outboxRepository.read().receipts.map(::receiptMap)
                }
            }
            "ackOutboxReceipts" -> {
                {
                    val receiptIds = stringList(
                        arguments(call)["receiptIds"],
                        "receiptIds",
                    ).toSet()
                    outboxRepository.update { snapshot ->
                        IronwoodOutboxState.acknowledgeReceipts(snapshot, receiptIds)
                    }
                    null
                }
            }
            "runOutboxOnceNow" -> {
                {
                    IronwoodMigrationOutboxRunner(
                        repository = outboxRepository,
                        transport = IronwoodMigrationOutboxNativeBridge(),
                    ).runOnceWaitingForActiveRun().toChannelMap()
                }
            }
            "revokeAccount" -> {
                {
                    val arguments = arguments(call)
                    val network = network(arguments)
                    val accountUuid = string(arguments, "accountUuid")
                    IronwoodMigrationOutboxScheduler.cancel(context)
                    var hasRemainingWork = false
                    IronwoodMigrationOutboxExecutionCoordinator.cancelAndDrain {
                        hasRemainingWork = outboxRepository.update { snapshot ->
                            val batchIds = snapshot.batches.filter {
                                it.network == network && it.accountUuid == accountUuid
                            }.map { it.batchId }.toSet()
                            snapshot.batches.removeAll { it.batchId in batchIds }
                            snapshot.receipts.removeAll { it.batchId in batchIds }
                            if (snapshot.lastAttemptedScopeKey == "$network:$accountUuid") {
                                snapshot.lastAttemptedScopeKey = null
                            }
                            IronwoodOutboxState.hasRunnableWork(snapshot)
                        }
                        store.revokeAccount(network, accountUuid)
                    }
                    if (hasRemainingWork) {
                        IronwoodMigrationOutboxScheduler.enqueueContinuation(context, 0)
                    }
                    true
                }
            }
            "revokeAll" -> {
                {
                    IronwoodMigrationOutboxScheduler.cancel(context)
                    IronwoodMigrationOutboxExecutionCoordinator.cancelAndDrain {
                        store.revokeAll()
                    }
                    IronwoodMigrationOutboxNotifier(context).cancelAll()
                    true
                }
            }
            else -> return false
        }

        executor.execute {
            try {
                val value = action()
                mainHandler.post { result.success(value) }
            } catch (error: IllegalArgumentException) {
                mainHandler.post {
                    result.error("invalid_arguments", error.message, null)
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("ironwood_secure_store_error", error.message, null)
                }
            }
        }
        return true
    }

    private fun scheduleOutbox() {
        IronwoodMigrationOutboxScheduler.enqueue(context)
    }

    fun close() {
        executor.shutdown()
    }

    fun resumePendingNotifications() {
        executor.execute {
            runCatching {
                if (
                    outboxRepository.read().let(
                        IronwoodOutboxState::hasPendingNotifications,
                    )
                ) {
                    scheduleOutbox()
                }
            }
        }
    }

    private fun validateManifest(
        manifestJson: String,
        expectedNetwork: String,
        expectedAccountUuid: String,
    ) {
        val manifest = try {
            JSONObject(manifestJson)
        } catch (error: Exception) {
            throw IllegalArgumentException("Invalid Ironwood migration manifest.", error)
        }
        val exactKeys = setOf(
            "version",
            "network",
            "accountUuid",
            "dbPath",
            "lightwalletdUrl",
            "credentialHex",
            "saltBase64",
            "expectedRunId",
        )
        if (manifest.keys().asSequence().toSet() != exactKeys) {
            throw IllegalArgumentException("Invalid Ironwood migration manifest fields.")
        }
        val version = manifest.get("version")
        val network = manifest.get("network")
        val accountUuid = manifest.get("accountUuid")
        val dbPath = manifest.get("dbPath")
        val lightwalletdUrl = manifest.get("lightwalletdUrl")
        val credentialHex = manifest.get("credentialHex")
        val saltBase64 = manifest.get("saltBase64")
        val expectedRunId = manifest.get("expectedRunId")
        if (
            version !is Int ||
            version != 1 ||
            network !is String ||
            network != expectedNetwork ||
            accountUuid !is String ||
            accountUuid != expectedAccountUuid ||
            dbPath !is String ||
            dbPath.isBlank() ||
            lightwalletdUrl !is String ||
            lightwalletdUrl.isBlank() ||
            credentialHex !is String ||
            !LOWERCASE_CREDENTIAL.matches(credentialHex) ||
            saltBase64 !is String ||
            !CANONICAL_SALT.matches(saltBase64) ||
            (
                expectedRunId !== JSONObject.NULL &&
                    (expectedRunId !is String || expectedRunId.isBlank())
                )
        ) {
            throw IllegalArgumentException("Invalid Ironwood migration manifest values.")
        }
        val salt = try {
            Base64.decode(saltBase64, Base64.DEFAULT)
        } catch (error: IllegalArgumentException) {
            throw IllegalArgumentException("Invalid Ironwood migration salt.", error)
        }
        if (
            salt.size != 16 ||
            Base64.encodeToString(salt, Base64.NO_WRAP) != saltBase64
        ) {
            throw IllegalArgumentException("Invalid Ironwood migration salt.")
        }
    }

    private data class ValidatedOutboxBatch(
        val network: String,
        val accountUuid: String,
        val batchId: String,
        val payload: Map<String, Any?>,
        val digests: Map<String, String>,
    )

    private fun validateOutboxBatch(arguments: Map<String, Any?>): ValidatedOutboxBatch {
        val batchId = string(arguments, "batchId")
        val network = network(arguments)
        val accountUuid = string(arguments, "accountUuid")
        string(arguments, "runId")
        string(arguments, "lightwalletdUrl")
        val timingMean = positiveLong(arguments, "timingMeanBlocks")
        val timingMax = positiveLong(arguments, "timingMaxBlocks")
        if (timingMean > timingMax) {
            throw IllegalArgumentException("Invalid outbox timing policy.")
        }
        nonNegativeLong(arguments, "createdAtMs")
        optionalNonNegativeLong(arguments, "nextProofHeight")
        val items = arguments["items"] as? List<*>
            ?: throw IllegalArgumentException("Missing items.")
        if (items.isEmpty() && arguments["nextProofHeight"] == null) {
            throw IllegalArgumentException("Outbox batch has no work.")
        }

        val itemIds = mutableSetOf<String>()
        val txids = mutableSetOf<String>()
        val partIndexes = mutableSetOf<Long>()
        val digests = linkedMapOf<String, String>()
        items.forEach { rawItem ->
            val item = stringMap(rawItem, "items")
            val itemId = string(item, "itemId")
            val txid = string(item, "txidHex").lowercase()
            val partIndex = nonNegativeLong(item, "partIndex")
            val rawTransaction = item["rawTransaction"] as? ByteArray
                ?: throw IllegalArgumentException("Invalid rawTransaction.")
            val scheduledHeight = nonNegativeLong(item, "scheduledHeight")
            val expiryHeight = nonNegativeLong(item, "expiryHeight")
            nonNegativeLong(item, "anchorBoundaryHeight")
            nonNegativeLong(item, "scheduleStartHeight")
            if (
                rawTransaction.isEmpty() ||
                scheduledHeight >= expiryHeight ||
                !itemIds.add(itemId) ||
                !txids.add(txid) ||
                !partIndexes.add(partIndex)
            ) {
                throw IllegalArgumentException("Invalid outbox item.")
            }
            digests[itemId] = sha256Hex(rawTransaction)
        }

        @Suppress("UNCHECKED_CAST")
        return ValidatedOutboxBatch(
            network = network,
            accountUuid = accountUuid,
            batchId = batchId,
            payload = LinkedHashMap(arguments),
            digests = digests,
        )
    }

    private fun stage(
        snapshot: IronwoodOutboxSnapshot,
        incoming: ValidatedOutboxBatch,
    ) {
        val payload = incoming.payload
        val incomingItems = listOfMaps(payload["items"], "items").map { item ->
            val rawTransaction = item["rawTransaction"] as ByteArray
            IronwoodOutboxItem(
                itemId = string(item, "itemId"),
                partIndex = nonNegativeLong(item, "partIndex"),
                txidHex = string(item, "txidHex").lowercase(),
                rawTransaction = rawTransaction.copyOf(),
                payloadDigestHex = sha256Hex(rawTransaction),
                anchorBoundaryHeight = nonNegativeLong(item, "anchorBoundaryHeight"),
                scheduledHeight = nonNegativeLong(item, "scheduledHeight"),
                scheduleStartHeight = nonNegativeLong(item, "scheduleStartHeight"),
                expiryHeight = nonNegativeLong(item, "expiryHeight"),
            )
        }
        val existing = snapshot.batches.firstOrNull { it.batchId == incoming.batchId }
        if (existing == null) {
            snapshot.batches += IronwoodOutboxBatch(
                batchId = incoming.batchId,
                network = incoming.network,
                accountUuid = incoming.accountUuid,
                runId = string(payload, "runId"),
                lightwalletdUrl = string(payload, "lightwalletdUrl"),
                timingMeanBlocks = positiveLong(payload, "timingMeanBlocks"),
                timingMaxBlocks = positiveLong(payload, "timingMaxBlocks"),
                createdAtMs = nonNegativeLong(payload, "createdAtMs"),
                nextProofHeight = optionalNonNegativeLong(payload, "nextProofHeight"),
                items = incomingItems.toMutableList(),
            )
            return
        }
        if (
            existing.network != incoming.network ||
            existing.accountUuid != incoming.accountUuid ||
            existing.runId != string(payload, "runId") ||
            existing.timingMeanBlocks != positiveLong(payload, "timingMeanBlocks") ||
            existing.timingMaxBlocks != positiveLong(payload, "timingMaxBlocks")
        ) {
            throw IllegalArgumentException("Conflicting outbox batch.")
        }
        val endpoint = string(payload, "lightwalletdUrl")
        if (
            existing.lightwalletdUrl != endpoint &&
            existing.items.any { it.status == IronwoodOutboxItemStatus.SUBMITTING }
        ) {
            throw IllegalArgumentException("Conflicting outbox batch.")
        }
        existing.lightwalletdUrl = endpoint
        var addedItem = false
        incomingItems.forEach { item ->
            val sameId = existing.items.firstOrNull { it.itemId == item.itemId }
            if (sameId != null) {
                if (
                    sameId.partIndex != item.partIndex ||
                    sameId.txidHex != item.txidHex ||
                    sameId.payloadDigestHex != item.payloadDigestHex ||
                    sameId.anchorBoundaryHeight != item.anchorBoundaryHeight ||
                    sameId.expiryHeight != item.expiryHeight
                ) {
                    throw IllegalArgumentException("Conflicting outbox item.")
                }
            } else {
                if (existing.items.any {
                        it.txidHex == item.txidHex || it.partIndex == item.partIndex
                    }) {
                    throw IllegalArgumentException("Conflicting outbox item identity.")
                }
                existing.items += item
                addedItem = true
            }
        }
        val nextProofHeight = optionalNonNegativeLong(payload, "nextProofHeight")
        val proofHeightChanged = existing.nextProofHeight != nextProofHeight
        if (proofHeightChanged) {
            existing.nextProofHeight = nextProofHeight
            existing.proofReadyObservedHeight = null
            existing.proofReadyNotificationAcknowledged = false
        }
        if (addedItem || proofHeightChanged) {
            existing.broadcastCompletePending = false
        }
    }

    private fun receiptMap(receipt: IronwoodOutboxReceipt): Map<String, Any?> = mapOf(
        "receiptId" to receipt.receiptId,
        "batchId" to receipt.batchId,
        "itemId" to receipt.itemId,
        "network" to receipt.network,
        "accountUuid" to receipt.accountUuid,
        "runId" to receipt.runId,
        "txidHex" to receipt.txidHex,
        "outcome" to receipt.outcome,
        "remoteHeight" to receipt.remoteHeight,
        "responseCode" to receipt.responseCode,
        "responseMessage" to receipt.responseMessage,
        "recordedAtMs" to receipt.recordedAtMs,
        "scheduleUpdates" to receipt.scheduleUpdates.map {
            mapOf(
                "itemId" to it.itemId,
                "scheduledHeight" to it.scheduledHeight,
                "scheduleStartHeight" to it.scheduleStartHeight,
            )
        },
        "rawTransaction" to receipt.rawTransaction,
    )

    private fun IronwoodMigrationOutboxRunResult.toChannelMap(): Map<String, Any?> =
        mapOf(
            "outcome" to when (outcome) {
                IronwoodMigrationOutboxOutcome.NO_WORK -> "noWork"
                IronwoodMigrationOutboxOutcome.WAITING -> "waiting"
                IronwoodMigrationOutboxOutcome.ACCEPTED -> "accepted"
                IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION -> "needsUserAction"
                IronwoodMigrationOutboxOutcome.RETRY -> "temporarilyUnavailable"
                IronwoodMigrationOutboxOutcome.CANCELLED -> "cancelled"
            },
            "nextHeight" to nextHeight,
            "observedHeight" to observedHeight,
            "delaySeconds" to delayMs?.div(1_000.0),
        )

    private fun arguments(call: MethodCall): Map<String, Any?> =
        stringMap(call.arguments, "arguments")

    private fun stringMap(value: Any?, name: String): Map<String, Any?> {
        val raw = value as? Map<*, *>
            ?: throw IllegalArgumentException("Invalid $name.")
        if (raw.keys.any { it !is String }) {
            throw IllegalArgumentException("Invalid $name keys.")
        }
        @Suppress("UNCHECKED_CAST")
        return raw as Map<String, Any?>
    }

    private fun listOfMaps(value: Any?, name: String): List<Map<String, Any?>> {
        val raw = value as? List<*> ?: throw IllegalArgumentException("Invalid $name.")
        return raw.map { stringMap(it, name) }
    }

    private fun stringStringMap(value: Any?, name: String): Map<String, String> {
        val raw = value as? Map<*, *> ?: throw IllegalArgumentException("Invalid $name.")
        if (raw.any { it.key !is String || it.value !is String }) {
            throw IllegalArgumentException("Invalid $name.")
        }
        @Suppress("UNCHECKED_CAST")
        return raw as Map<String, String>
    }

    private fun stringList(value: Any?, name: String): List<String> {
        val raw = value as? List<*> ?: throw IllegalArgumentException("Invalid $name.")
        if (raw.any { it !is String || it.isBlank() }) {
            throw IllegalArgumentException("Invalid $name.")
        }
        @Suppress("UNCHECKED_CAST")
        return raw as List<String>
    }

    private fun network(arguments: Map<String, Any?>): String =
        string(arguments, "network").also {
            if (it !in SUPPORTED_NETWORKS) {
                throw IllegalArgumentException("Unsupported network.")
            }
        }

    private fun string(arguments: Map<String, Any?>, key: String): String {
        val value = arguments[key] as? String
            ?: throw IllegalArgumentException("Missing $key.")
        if (value.isBlank() || value.trim() != value) {
            throw IllegalArgumentException("Invalid $key.")
        }
        return value
    }

    private fun positiveLong(arguments: Map<String, Any?>, key: String): Long =
        nonNegativeLong(arguments, key).also {
            if (it == 0L) throw IllegalArgumentException("Invalid $key.")
        }

    private fun nonNegativeLong(arguments: Map<String, Any?>, key: String): Long {
        val value = (arguments[key] as? Number)?.toLong()
            ?: throw IllegalArgumentException("Missing $key.")
        if (value < 0) throw IllegalArgumentException("Invalid $key.")
        return value
    }

    private fun optionalNonNegativeLong(
        arguments: Map<String, Any?>,
        key: String,
    ): Long? {
        val value = arguments[key] ?: return null
        if (value !is Number || value.toLong() < 0) {
            throw IllegalArgumentException("Invalid $key.")
        }
        return value.toLong()
    }

    private fun sha256Hex(value: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value)
            .joinToString(separator = "") { byte ->
                "%02x".format(byte.toInt() and 0xff)
            }

    private companion object {
        val SUPPORTED_NETWORKS = setOf("main", "test", "regtest")
        val LOWERCASE_CREDENTIAL = Regex("^[0-9a-f]{64}$")
        val CANONICAL_SALT = Regex("^[A-Za-z0-9+/]{22}==$")
    }
}

internal fun encodeIronwoodOutboxMap(value: Map<String, Any?>): ByteArray {
    val buffer = StandardMessageCodec.INSTANCE.encodeMessage(value)
        ?: throw IronwoodMigrationSecureStoreException("Failed to encode outbox batch.")
    buffer.flip()
    return ByteArray(buffer.remaining()).also(buffer::get)
}

internal fun decodeIronwoodOutboxMap(value: ByteArray): Map<String, Any?> {
    val decoded = StandardMessageCodec.INSTANCE.decodeMessage(ByteBuffer.wrap(value))
    val raw = decoded as? Map<*, *>
        ?: throw IllegalArgumentException("Invalid storedOutboxBatch.")
    if (raw.keys.any { it !is String }) {
        throw IllegalArgumentException("Invalid storedOutboxBatch keys.")
    }
    @Suppress("UNCHECKED_CAST")
    return raw as Map<String, Any?>
}
