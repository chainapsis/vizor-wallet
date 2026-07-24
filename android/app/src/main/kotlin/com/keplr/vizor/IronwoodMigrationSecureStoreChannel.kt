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
    context: Context,
    private val store: IronwoodMigrationSecureStore = IronwoodMigrationSecureStore(context),
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
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
                    val existing = store.readOutboxBatch(
                        incoming.network,
                        incoming.accountUuid,
                        incoming.batchId,
                    )?.let(::decodeIronwoodOutboxMap)
                    val merged = mergeOutboxBatch(existing, incoming.payload)
                    store.writeOutboxBatch(
                        incoming.network,
                        incoming.accountUuid,
                        incoming.batchId,
                        encodeIronwoodOutboxMap(merged),
                    )
                    incoming.digests
                }
            }
            "revokeAccount" -> {
                {
                    val arguments = arguments(call)
                    store.revokeAccount(
                        network(arguments),
                        string(arguments, "accountUuid"),
                    )
                    true
                }
            }
            "revokeAll" -> {
                {
                    store.revokeAll()
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

    fun close() {
        executor.shutdown()
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

    private fun mergeOutboxBatch(
        existing: Map<String, Any?>?,
        incoming: Map<String, Any?>,
    ): Map<String, Any?> {
        if (existing == null) return incoming
        for (key in listOf(
            "batchId",
            "network",
            "accountUuid",
            "runId",
            "timingMeanBlocks",
            "timingMaxBlocks",
        )) {
            if (existing[key] != incoming[key]) {
                throw IllegalArgumentException("Conflicting outbox batch.")
            }
        }

        val existingItems = listOfMaps(existing["items"], "items").toMutableList()
        val incomingItems = listOfMaps(incoming["items"], "items")
        for (incomingItem in incomingItems) {
            val incomingId = string(incomingItem, "itemId")
            val incomingTxid = string(incomingItem, "txidHex").lowercase()
            val incomingPart = nonNegativeLong(incomingItem, "partIndex")
            val matchingId = existingItems.firstOrNull {
                string(it, "itemId") == incomingId
            }
            if (matchingId != null) {
                if (!sameOutboxIdentity(matchingId, incomingItem)) {
                    throw IllegalArgumentException("Conflicting outbox item.")
                }
                continue
            }
            if (existingItems.any {
                    string(it, "txidHex").lowercase() == incomingTxid ||
                        nonNegativeLong(it, "partIndex") == incomingPart
                }) {
                throw IllegalArgumentException("Conflicting outbox item identity.")
            }
            existingItems += incomingItem
        }

        return LinkedHashMap(existing).apply {
            this["lightwalletdUrl"] = incoming["lightwalletdUrl"]
            this["nextProofHeight"] = incoming["nextProofHeight"]
            this["items"] = existingItems
        }
    }

    private fun sameOutboxIdentity(
        left: Map<String, Any?>,
        right: Map<String, Any?>,
    ): Boolean {
        for (key in listOf(
            "itemId",
            "partIndex",
            "txidHex",
            "anchorBoundaryHeight",
            "expiryHeight",
        )) {
            if (left[key] != right[key]) return false
        }
        val leftRaw = left["rawTransaction"] as? ByteArray ?: return false
        val rightRaw = right["rawTransaction"] as? ByteArray ?: return false
        return MessageDigest.isEqual(leftRaw, rightRaw)
    }

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
