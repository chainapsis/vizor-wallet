package com.keplr.vizor

import java.security.MessageDigest
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

internal class IronwoodOutboxConflictException(
    message: String = "Conflicting outbox batch.",
) : IllegalArgumentException(message)

internal enum class IronwoodOutboxItemStatus {
    STAGED,
    ARMED,
    SUBMITTING,
    ACCEPTED_AWAITING_RECONCILIATION,
    REJECTED_AWAITING_RECONCILIATION,
    EXPIRED_AWAITING_RECONCILIATION,
    NEEDS_RESIGN_AWAITING_RECONCILIATION,
}

internal data class IronwoodOutboxItem(
    val itemId: String,
    val partIndex: Long,
    val txidHex: String,
    val rawTransaction: ByteArray,
    val payloadDigestHex: String,
    val anchorBoundaryHeight: Long,
    var scheduledHeight: Long,
    var scheduleStartHeight: Long,
    val expiryHeight: Long,
    var status: IronwoodOutboxItemStatus = IronwoodOutboxItemStatus.STAGED,
    var attemptCount: Int = 0,
    var attemptId: String? = null,
    var attemptStartedAtMs: Long? = null,
    var nextAttemptAtMs: Long? = null,
    var lastError: String? = null,
)

internal data class IronwoodOutboxBatch(
    val batchId: String,
    val network: String,
    val accountUuid: String,
    val runId: String,
    var lightwalletdUrl: String,
    val timingMeanBlocks: Long,
    val timingMaxBlocks: Long,
    val createdAtMs: Long,
    var armedAtMs: Long? = null,
    var nextProofHeight: Long? = null,
    var proofReadyObservedHeight: Long? = null,
    var proofReadyNotificationAcknowledged: Boolean = false,
    var proofReadyHeightNoticeObservedHeight: Long? = null,
    var proofReadyHeightNoticeAcknowledged: Boolean = false,
    var needsUserActionNotificationPending: Boolean = false,
    var broadcastCompletePending: Boolean = false,
    val items: MutableList<IronwoodOutboxItem>,
) {
    val scopeKey: String get() = "$network:$accountUuid"

    val awaitsProofReadyHeightNotice: Boolean
        get() =
            nextProofHeight != null &&
                proofReadyObservedHeight == null &&
                proofReadyHeightNoticeObservedHeight == null
}

internal data class IronwoodOutboxScheduleUpdate(
    val itemId: String,
    val scheduledHeight: Long,
    val scheduleStartHeight: Long,
)

internal data class IronwoodOutboxReceipt(
    val receiptId: String,
    val batchId: String,
    val itemId: String,
    val network: String,
    val accountUuid: String,
    val runId: String,
    val txidHex: String,
    val outcome: String,
    val remoteHeight: Long,
    val responseCode: Int?,
    val responseMessage: String?,
    val recordedAtMs: Long,
    val scheduleUpdates: List<IronwoodOutboxScheduleUpdate>,
    val rawTransaction: ByteArray?,
)

internal data class IronwoodOutboxSnapshot(
    val batches: MutableList<IronwoodOutboxBatch> = mutableListOf(),
    val receipts: MutableList<IronwoodOutboxReceipt> = mutableListOf(),
    var lastAttemptedScopeKey: String? = null,
    var lastInspectedEndpoint: String? = null,
)

internal class IronwoodMigrationOutboxRepository(
    private val store: IronwoodMigrationSecureStore,
) {
    fun <T> update(block: (IronwoodOutboxSnapshot) -> T): T {
        var result: T? = null
        store.updateOutboxSnapshot { encoded ->
            val snapshot = encoded?.let(IronwoodOutboxCodec::decode)
                ?: IronwoodOutboxSnapshot()
            result = block(snapshot)
            IronwoodOutboxCodec.encode(snapshot)
        }
        @Suppress("UNCHECKED_CAST")
        return result as T
    }

    fun read(): IronwoodOutboxSnapshot =
        store.readOutboxSnapshot()?.let(IronwoodOutboxCodec::decode)
            ?: IronwoodOutboxSnapshot()
}

internal object IronwoodOutboxState {
    fun hasBatch(
        snapshot: IronwoodOutboxSnapshot,
        batchId: String,
        network: String,
        accountUuid: String,
        runId: String,
        expectedTxids: Set<String>,
        requiredTxids: Set<String>,
    ): Boolean {
        val batch = snapshot.batches.firstOrNull { it.batchId == batchId }
            ?: return false
        if (
            batch.network != network ||
            batch.accountUuid != accountUuid ||
            batch.runId != runId ||
            expectedTxids.isEmpty() ||
            requiredTxids.isEmpty() ||
            batch.items.isEmpty() ||
            batch.items.any { it.txidHex !in expectedTxids } ||
            requiredTxids.any { required ->
                batch.items.none { it.txidHex == required }
            }
        ) {
            throw IronwoodOutboxConflictException()
        }
        return true
    }

    fun discardBatch(
        snapshot: IronwoodOutboxSnapshot,
        batchId: String,
    ): Boolean {
        val batchIndex = snapshot.batches.indexOfFirst { it.batchId == batchId }
        if (batchIndex < 0) return false
        val batch = snapshot.batches[batchIndex]
        if (
            batch.items.any {
                it.status == IronwoodOutboxItemStatus.SUBMITTING ||
                    it.attemptCount > 0
            } ||
            snapshot.receipts.any { it.batchId == batchId }
        ) {
            throw IronwoodOutboxConflictException()
        }
        snapshot.batches.removeAt(batchIndex)
        return true
    }

    fun recoverInterrupted(snapshot: IronwoodOutboxSnapshot, nowMs: Long) {
        snapshot.batches.flatMap { it.items }
            .filter { it.status == IronwoodOutboxItemStatus.SUBMITTING }
            .forEach { item ->
                item.status = IronwoodOutboxItemStatus.ARMED
                item.attemptCount += 1
                item.nextAttemptAtMs = nowMs + retryDelayMs(item.attemptCount)
                item.lastError = "The previous submission outcome is unknown."
                item.attemptId = null
                item.attemptStartedAtMs = null
            }
    }

    fun nextEndpoint(snapshot: IronwoodOutboxSnapshot): String? {
        val endpoints = snapshot.batches
            .filter { batch ->
                batch.armedAtMs != null &&
                    (
                        batch.items.any { it.status == IronwoodOutboxItemStatus.ARMED } ||
                            batch.awaitsProofReadyHeightNotice
                    )
            }
            .map { it.lightwalletdUrl }
            .distinct()
            .sorted()
        if (endpoints.isEmpty()) return null
        val lastIndex = endpoints.indexOf(snapshot.lastInspectedEndpoint)
        return endpoints[if (lastIndex < 0) 0 else (lastIndex + 1) % endpoints.size]
            .also { snapshot.lastInspectedEndpoint = it }
    }

    fun expireAndMarkNoncanonical(
        snapshot: IronwoodOutboxSnapshot,
        endpoint: String,
        remoteHeight: Long,
        nowMs: Long,
    ): String? {
        val canonicalExpiry = canonicalExpiryHeight(remoteHeight)
        var needsUserActionAccountUuid: String? = null
        snapshot.batches.filter { it.lightwalletdUrl == endpoint }.forEach { batch ->
            var terminal = false
            batch.items.filter { it.status == IronwoodOutboxItemStatus.ARMED }.forEach { item ->
                val outcome = when {
                    remoteHeight >= item.expiryHeight -> "expired"
                    item.scheduledHeight <= remoteHeight &&
                        canonicalExpiry != null &&
                        item.expiryHeight != canonicalExpiry -> "needsResign"
                    else -> null
                } ?: return@forEach
                item.status = if (outcome == "expired") {
                    IronwoodOutboxItemStatus.EXPIRED_AWAITING_RECONCILIATION
                } else {
                    IronwoodOutboxItemStatus.NEEDS_RESIGN_AWAITING_RECONCILIATION
                }
                snapshot.receipts += receipt(
                    batch = batch,
                    item = item,
                    outcome = outcome,
                    remoteHeight = remoteHeight,
                    responseCode = null,
                    responseMessage = if (outcome == "needsResign") {
                        "Broadcast height crossed a ZIP 318 expiry boundary."
                    } else {
                        null
                    },
                    nowMs = nowMs,
                )
                batch.needsUserActionNotificationPending = true
                terminal = true
                needsUserActionAccountUuid =
                    needsUserActionAccountUuid ?: batch.accountUuid
            }
            if (terminal) {
                batch.armedAtMs = null
                batch.nextProofHeight = null
            }
        }
        return needsUserActionAccountUuid
    }

    fun markUnverifiedProofReadyNoticeIfNeeded(
        snapshot: IronwoodOutboxSnapshot,
        endpoint: String,
        remoteHeight: Long,
    ): String? {
        val batch = snapshot.batches.filter {
            it.lightwalletdUrl == endpoint &&
                it.armedAtMs != null &&
                it.proofReadyObservedHeight == null &&
                it.proofReadyHeightNoticeObservedHeight == null &&
                it.nextProofHeight != null &&
                it.nextProofHeight!! <= remoteHeight
        }.minWithOrNull(compareBy<IronwoodOutboxBatch> { it.nextProofHeight }.thenBy { it.batchId })
            ?: return null
        batch.proofReadyHeightNoticeObservedHeight = remoteHeight
        return batch.batchId
    }

    fun pendingUnverifiedProofReadyBatchId(snapshot: IronwoodOutboxSnapshot): String? =
        snapshot.batches.filter {
            it.proofReadyHeightNoticeObservedHeight != null &&
                !it.proofReadyHeightNoticeAcknowledged &&
                it.proofReadyObservedHeight == null
        }.minByOrNull { it.batchId }?.batchId

    fun acknowledgeUnverifiedProofReadyNotification(
        snapshot: IronwoodOutboxSnapshot,
        batchId: String,
    ): Boolean {
        val batch = snapshot.batches.firstOrNull { it.batchId == batchId }
            ?: return false
        if (batch.proofReadyHeightNoticeObservedHeight == null) return false
        batch.proofReadyHeightNoticeAcknowledged = true
        return true
    }

    fun recordVerifiedProofReadiness(
        snapshot: IronwoodOutboxSnapshot,
        network: String,
        accountUuid: String,
        runId: String,
        observedHeight: Long? = null,
    ): Boolean {
        val batch = snapshot.batches.filter {
            it.network == network &&
                it.accountUuid == accountUuid &&
                it.runId == runId &&
                it.armedAtMs != null &&
                it.nextProofHeight != null
        }.minWithOrNull(compareBy<IronwoodOutboxBatch> { it.nextProofHeight }.thenBy { it.batchId })
            ?: return false
        if (batch.proofReadyObservedHeight == null) {
            batch.proofReadyObservedHeight = max(
                observedHeight ?: 0,
                batch.nextProofHeight ?: 0,
            )
            batch.proofReadyNotificationAcknowledged = false
        }
        batch.proofReadyHeightNoticeAcknowledged = true
        return true
    }

    fun pendingProofReadyBatchId(snapshot: IronwoodOutboxSnapshot): String? =
        snapshot.batches.filter {
            it.proofReadyObservedHeight != null &&
                !it.proofReadyNotificationAcknowledged
        }.minByOrNull { it.batchId }?.batchId

    fun acknowledgeProofReadyNotification(
        snapshot: IronwoodOutboxSnapshot,
        batchId: String,
    ): Boolean {
        val batch = snapshot.batches.firstOrNull { it.batchId == batchId }
            ?: return false
        if (batch.proofReadyObservedHeight == null) return false
        batch.proofReadyNotificationAcknowledged = true
        return true
    }

    fun pendingNeedsUserActionBatchId(snapshot: IronwoodOutboxSnapshot): String? =
        snapshot.batches.filter {
            it.needsUserActionNotificationPending
        }.minByOrNull { it.batchId }?.batchId

    fun markNeedsUserActionNotificationPending(
        snapshot: IronwoodOutboxSnapshot,
        batchId: String,
    ) {
        snapshot.batches.firstOrNull { it.batchId == batchId }
            ?.needsUserActionNotificationPending = true
    }

    fun acknowledgeNeedsUserActionNotification(
        snapshot: IronwoodOutboxSnapshot,
        batchId: String,
    ): Boolean {
        val batch = snapshot.batches.firstOrNull { it.batchId == batchId }
            ?: return false
        if (!batch.needsUserActionNotificationPending) return false
        batch.needsUserActionNotificationPending = false
        return true
    }

    fun pendingBroadcastCompleteBatchId(snapshot: IronwoodOutboxSnapshot): String? =
        snapshot.batches.filter {
            it.broadcastCompletePending
        }.minByOrNull { it.batchId }?.batchId

    fun acknowledgeBroadcastCompleteNotification(
        snapshot: IronwoodOutboxSnapshot,
        batchId: String,
    ): Boolean {
        val batch = snapshot.batches.firstOrNull { it.batchId == batchId }
            ?: return false
        if (!batch.broadcastCompletePending) return false
        batch.broadcastCompletePending = false
        if (batch.items.isEmpty() && batch.nextProofHeight == null) {
            snapshot.batches.remove(batch)
        }
        return true
    }

    fun selectDue(
        snapshot: IronwoodOutboxSnapshot,
        endpoint: String,
        remoteHeight: Long,
        nowMs: Long,
    ): Pair<IronwoodOutboxBatch, IronwoodOutboxItem>? {
        val candidates = snapshot.batches.filter { batch ->
            batch.lightwalletdUrl == endpoint &&
                batch.armedAtMs != null &&
                batch.items.any { it.isDue(remoteHeight, nowMs) }
        }
        if (candidates.isEmpty()) return null
        val scopes = candidates.map { it.scopeKey }.distinct().sorted()
        val lastIndex = scopes.indexOf(snapshot.lastAttemptedScopeKey)
        val selectedScope = scopes[if (lastIndex < 0) 0 else (lastIndex + 1) % scopes.size]
        val batch = candidates.first { it.scopeKey == selectedScope }
        val item = batch.items.filter { it.isDue(remoteHeight, nowMs) }
            .minWith(compareBy<IronwoodOutboxItem> { it.scheduledHeight }.thenBy { it.txidHex })
        snapshot.lastAttemptedScopeKey = selectedScope
        return batch to item
    }

    fun beginSubmission(item: IronwoodOutboxItem, nowMs: Long) {
        check(item.status == IronwoodOutboxItemStatus.ARMED)
        item.status = IronwoodOutboxItemStatus.SUBMITTING
        item.attemptId = UUID.randomUUID().toString()
        item.attemptStartedAtMs = nowMs
    }

    fun validateReschedulingAfterAcceptance(
        batch: IronwoodOutboxBatch,
        excludingItemId: String,
        remoteHeight: Long,
    ) {
        var nextHeight = remoteHeight
        batch.items.filter {
            it.itemId != excludingItemId &&
                it.status == IronwoodOutboxItemStatus.ARMED &&
                it.scheduledHeight <= remoteHeight
        }.map { it.expiryHeight }.sorted().forEach { expiryHeight ->
            nextHeight = Math.addExact(nextHeight, 1)
            require(nextHeight < expiryHeight) { "Invalid outbox rescheduling window." }
        }
    }

    fun recordUncertain(item: IronwoodOutboxItem, message: String, nowMs: Long) {
        check(item.status == IronwoodOutboxItemStatus.SUBMITTING)
        item.status = IronwoodOutboxItemStatus.ARMED
        item.attemptCount += 1
        item.nextAttemptAtMs = nowMs + retryDelayMs(item.attemptCount)
        item.lastError = message
        item.attemptId = null
        item.attemptStartedAtMs = null
    }

    fun recordAccepted(
        snapshot: IronwoodOutboxSnapshot,
        batch: IronwoodOutboxBatch,
        item: IronwoodOutboxItem,
        equivalent: Boolean,
        remoteHeight: Long,
        responseCode: Int,
        responseMessage: String,
        nowMs: Long,
        random: Random,
    ) {
        check(item.status == IronwoodOutboxItemStatus.SUBMITTING)
        item.status = IronwoodOutboxItemStatus.ACCEPTED_AWAITING_RECONCILIATION
        item.attemptId = null
        item.attemptStartedAtMs = null
        item.nextAttemptAtMs = null
        val updates = rescheduleOverdue(batch, item.itemId, remoteHeight, random)
        snapshot.receipts += receipt(
            batch = batch,
            item = item,
            outcome = if (equivalent) "acceptedEquivalent" else "accepted",
            remoteHeight = remoteHeight,
            responseCode = responseCode,
            responseMessage = responseMessage,
            scheduleUpdates = updates,
            rawTransaction = item.rawTransaction,
            nowMs = nowMs,
        )
        if (
            batch.nextProofHeight == null &&
            batch.items.isNotEmpty() &&
            batch.items.all {
                it.status == IronwoodOutboxItemStatus.ACCEPTED_AWAITING_RECONCILIATION
            }
        ) {
            batch.broadcastCompletePending = true
        }
    }

    fun recordRejected(
        snapshot: IronwoodOutboxSnapshot,
        batch: IronwoodOutboxBatch,
        item: IronwoodOutboxItem,
        remoteHeight: Long,
        responseCode: Int,
        responseMessage: String,
        nowMs: Long,
    ) {
        check(item.status == IronwoodOutboxItemStatus.SUBMITTING)
        item.status = IronwoodOutboxItemStatus.REJECTED_AWAITING_RECONCILIATION
        item.attemptId = null
        item.attemptStartedAtMs = null
        item.nextAttemptAtMs = null
        batch.armedAtMs = null
        batch.nextProofHeight = null
        batch.needsUserActionNotificationPending = true
        snapshot.receipts += receipt(
            batch = batch,
            item = item,
            outcome = "rejected",
            remoteHeight = remoteHeight,
            responseCode = responseCode,
            responseMessage = responseMessage,
            nowMs = nowMs,
        )
    }

    fun nextActionHeight(snapshot: IronwoodOutboxSnapshot, endpoint: String): Long? =
        snapshot.batches.filter { it.lightwalletdUrl == endpoint }
            .flatMap { batch ->
                buildList {
                    addAll(
                        batch.items.filter { it.status == IronwoodOutboxItemStatus.ARMED }
                            .map { it.scheduledHeight },
                    )
                    if (
                        batch.armedAtMs != null &&
                        batch.awaitsProofReadyHeightNotice
                    ) {
                        batch.nextProofHeight?.let(::add)
                    }
                }
            }
            .minOrNull()

    fun nextActionAccountUuid(
        snapshot: IronwoodOutboxSnapshot,
        endpoint: String,
        height: Long,
    ): String? = snapshot.batches.filter { batch ->
        if (batch.lightwalletdUrl != endpoint) return@filter false
        val hasTransaction = batch.items.any {
            it.status == IronwoodOutboxItemStatus.ARMED &&
                it.scheduledHeight == height
        }
        val hasProof = batch.armedAtMs != null &&
            batch.awaitsProofReadyHeightNotice &&
            batch.nextProofHeight == height
        hasTransaction || hasProof
    }.minByOrNull { it.batchId }?.accountUuid

    fun hasDeliveryWork(snapshot: IronwoodOutboxSnapshot): Boolean =
        snapshot.batches.any { batch ->
            batch.armedAtMs != null &&
                (
                    batch.items.any { it.status == IronwoodOutboxItemStatus.ARMED } ||
                        batch.awaitsProofReadyHeightNotice
                )
        }

    fun hasDeliveryWorkForOtherEndpoint(
        snapshot: IronwoodOutboxSnapshot,
        endpoint: String,
    ): Boolean =
        snapshot.batches.any { batch ->
            batch.lightwalletdUrl != endpoint &&
                batch.armedAtMs != null &&
                (
                    batch.items.any { it.status == IronwoodOutboxItemStatus.ARMED } ||
                        batch.awaitsProofReadyHeightNotice
                )
        }

    fun hasRunnableWork(snapshot: IronwoodOutboxSnapshot): Boolean =
        hasDeliveryWork(snapshot) ||
            hasPendingNotifications(snapshot)

    fun hasPendingNotifications(snapshot: IronwoodOutboxSnapshot): Boolean =
        snapshot.batches.any {
            it.needsUserActionNotificationPending ||
                it.broadcastCompletePending ||
                (
                    it.proofReadyObservedHeight != null &&
                        !it.proofReadyNotificationAcknowledged
                    ) ||
                (
                    it.proofReadyHeightNoticeObservedHeight != null &&
                        !it.proofReadyHeightNoticeAcknowledged &&
                        it.proofReadyObservedHeight == null
                    )
        }

    fun acknowledgeReceipts(
        snapshot: IronwoodOutboxSnapshot,
        receiptIds: Set<String>,
    ) {
        val acknowledged = snapshot.receipts.filter { it.receiptId in receiptIds }
        val acknowledgedItems = acknowledged.map { it.itemId }.toSet()
        val terminalBatches = acknowledged.filter {
            it.outcome in setOf("rejected", "expired", "needsResign")
        }.map { it.batchId }.toSet()
        snapshot.receipts.removeAll { it.receiptId in receiptIds }
        snapshot.batches.forEach { batch ->
            batch.items.removeAll { it.itemId in acknowledgedItems }
        }
        snapshot.batches.removeAll { batch ->
            (
                batch.items.isEmpty() &&
                    batch.nextProofHeight == null &&
                    !batch.broadcastCompletePending
                ) ||
                (
                    batch.batchId in terminalBatches &&
                        snapshot.receipts.none { it.batchId == batch.batchId }
                    )
        }
    }

    fun canonicalExpiryHeight(height: Long): Long? {
        if (height < 0) return null
        val modulus = 34_560L
        val boundary = height - height % modulus
        return try {
            Math.addExact(boundary, Math.multiplyExact(modulus, 2))
        } catch (_: ArithmeticException) {
            null
        }
    }

    fun retryDelayMs(attemptCount: Int): Long = when (attemptCount) {
        0, 1 -> 60_000
        2 -> 5 * 60_000
        3 -> 15 * 60_000
        else -> 60 * 60_000
    }

    fun nextCheckDelayMs(remoteHeight: Long, nextHeight: Long?): Long? {
        nextHeight ?: return null
        if (nextHeight <= remoteHeight) return 60_000
        val estimated = Math.multiplyExact(nextHeight - remoteHeight, 75_000L)
        return min(10 * 60_000L, max(60_000L, estimated - 10 * 60_000L))
    }

    private fun IronwoodOutboxItem.isDue(remoteHeight: Long, nowMs: Long): Boolean =
        status == IronwoodOutboxItemStatus.ARMED &&
            scheduledHeight <= remoteHeight &&
            remoteHeight < expiryHeight &&
            (nextAttemptAtMs == null || nextAttemptAtMs!! <= nowMs)

    private fun rescheduleOverdue(
        batch: IronwoodOutboxBatch,
        excludingItemId: String,
        remoteHeight: Long,
        random: Random,
    ): List<IronwoodOutboxScheduleUpdate> {
        val overdue = batch.items.filter {
            it.itemId != excludingItemId &&
                it.status == IronwoodOutboxItemStatus.ARMED &&
                it.scheduledHeight <= remoteHeight
        }.shuffled(random).sortedBy { it.expiryHeight }
        var elapsed = 0L
        return overdue.mapIndexed { index, item ->
            val remaining = overdue.size - index - 1L
            val latest = item.expiryHeight - remaining - 1
            val current = Math.addExact(remoteHeight, elapsed)
            require(latest > current) { "Invalid outbox rescheduling window." }
            val boundedMax = min(batch.timingMaxBlocks, latest - current)
            elapsed = Math.addExact(
                elapsed,
                sampleDelay(batch.timingMeanBlocks, boundedMax, random),
            )
            item.scheduledHeight = Math.addExact(remoteHeight, elapsed)
            item.scheduleStartHeight = remoteHeight
            IronwoodOutboxScheduleUpdate(
                item.itemId,
                item.scheduledHeight,
                item.scheduleStartHeight,
            )
        }
    }

    private fun sampleDelay(mean: Long, maximum: Long, random: Random): Long {
        require(mean > 0 && maximum > 0)
        val lowerBound = exp(-maximum.toDouble() / mean.toDouble())
        val uniform = lowerBound + (1 - lowerBound) * random.nextDouble()
        return min(maximum, max(1, ceil(-ln(uniform) * mean).toLong()))
    }

    private fun receipt(
        batch: IronwoodOutboxBatch,
        item: IronwoodOutboxItem,
        outcome: String,
        remoteHeight: Long,
        responseCode: Int?,
        responseMessage: String?,
        scheduleUpdates: List<IronwoodOutboxScheduleUpdate> = emptyList(),
        rawTransaction: ByteArray? = null,
        nowMs: Long,
    ) = IronwoodOutboxReceipt(
        receiptId = "${batch.batchId}:${item.itemId}:$outcome",
        batchId = batch.batchId,
        itemId = item.itemId,
        network = batch.network,
        accountUuid = batch.accountUuid,
        runId = batch.runId,
        txidHex = item.txidHex,
        outcome = outcome,
        remoteHeight = remoteHeight,
        responseCode = responseCode,
        responseMessage = responseMessage,
        recordedAtMs = nowMs,
        scheduleUpdates = scheduleUpdates,
        rawTransaction = rawTransaction,
    )
}

internal object IronwoodOutboxCodec {
    fun encode(snapshot: IronwoodOutboxSnapshot): ByteArray =
        encodeIronwoodOutboxMap(
            mapOf(
                "version" to 1,
                "batches" to snapshot.batches.map(::encodeBatch),
                "receipts" to snapshot.receipts.map(::encodeReceipt),
                "lastAttemptedScopeKey" to snapshot.lastAttemptedScopeKey,
                "lastInspectedEndpoint" to snapshot.lastInspectedEndpoint,
            ),
        )

    fun decode(encoded: ByteArray): IronwoodOutboxSnapshot {
        val root = decodeIronwoodOutboxMap(encoded)
        require(number(root, "version") == 1L) { "Unsupported outbox snapshot." }
        return IronwoodOutboxSnapshot(
            batches = maps(root["batches"]).map(::decodeBatch).toMutableList(),
            receipts = maps(root["receipts"]).map(::decodeReceipt).toMutableList(),
            lastAttemptedScopeKey = root["lastAttemptedScopeKey"] as? String,
            lastInspectedEndpoint = root["lastInspectedEndpoint"] as? String,
        )
    }

    private fun encodeBatch(batch: IronwoodOutboxBatch) = mapOf(
        "batchId" to batch.batchId,
        "network" to batch.network,
        "accountUuid" to batch.accountUuid,
        "runId" to batch.runId,
        "lightwalletdUrl" to batch.lightwalletdUrl,
        "timingMeanBlocks" to batch.timingMeanBlocks,
        "timingMaxBlocks" to batch.timingMaxBlocks,
        "createdAtMs" to batch.createdAtMs,
        "armedAtMs" to batch.armedAtMs,
        "nextProofHeight" to batch.nextProofHeight,
        "proofReadyObservedHeight" to batch.proofReadyObservedHeight,
        "proofReadyNotificationAcknowledged" to
            batch.proofReadyNotificationAcknowledged,
        "proofReadyHeightNoticeObservedHeight" to
            batch.proofReadyHeightNoticeObservedHeight,
        "proofReadyHeightNoticeAcknowledged" to
            batch.proofReadyHeightNoticeAcknowledged,
        "needsUserActionNotificationPending" to
            batch.needsUserActionNotificationPending,
        "broadcastCompletePending" to batch.broadcastCompletePending,
        "items" to batch.items.map(::encodeItem),
    )

    private fun encodeItem(item: IronwoodOutboxItem) = mapOf(
        "itemId" to item.itemId,
        "partIndex" to item.partIndex,
        "txidHex" to item.txidHex,
        "rawTransaction" to item.rawTransaction,
        "payloadDigestHex" to item.payloadDigestHex,
        "anchorBoundaryHeight" to item.anchorBoundaryHeight,
        "scheduledHeight" to item.scheduledHeight,
        "scheduleStartHeight" to item.scheduleStartHeight,
        "expiryHeight" to item.expiryHeight,
        "status" to item.status.name,
        "attemptCount" to item.attemptCount,
        "attemptId" to item.attemptId,
        "attemptStartedAtMs" to item.attemptStartedAtMs,
        "nextAttemptAtMs" to item.nextAttemptAtMs,
        "lastError" to item.lastError,
    )

    private fun encodeReceipt(receipt: IronwoodOutboxReceipt) = mapOf(
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

    private fun decodeBatch(value: Map<String, Any?>) = IronwoodOutboxBatch(
        batchId = text(value, "batchId"),
        network = text(value, "network"),
        accountUuid = text(value, "accountUuid"),
        runId = text(value, "runId"),
        lightwalletdUrl = text(value, "lightwalletdUrl"),
        timingMeanBlocks = number(value, "timingMeanBlocks"),
        timingMaxBlocks = number(value, "timingMaxBlocks"),
        createdAtMs = number(value, "createdAtMs"),
        armedAtMs = optionalNumber(value, "armedAtMs"),
        nextProofHeight = optionalNumber(value, "nextProofHeight"),
        proofReadyObservedHeight = optionalNumber(value, "proofReadyObservedHeight"),
        proofReadyNotificationAcknowledged =
            value["proofReadyNotificationAcknowledged"] as? Boolean ?: false,
        proofReadyHeightNoticeObservedHeight =
            optionalNumber(value, "proofReadyHeightNoticeObservedHeight"),
        proofReadyHeightNoticeAcknowledged =
            value["proofReadyHeightNoticeAcknowledged"] as? Boolean ?: false,
        needsUserActionNotificationPending =
            value["needsUserActionNotificationPending"] as? Boolean ?: false,
        broadcastCompletePending = value["broadcastCompletePending"] as? Boolean ?: false,
        items = maps(value["items"]).map(::decodeItem).toMutableList(),
    )

    private fun decodeItem(value: Map<String, Any?>): IronwoodOutboxItem {
        val raw = value["rawTransaction"] as? ByteArray
            ?: throw IllegalArgumentException("Invalid outbox transaction.")
        val digest = sha256Hex(raw)
        require(digest == text(value, "payloadDigestHex")) {
            "Outbox transaction digest mismatch."
        }
        return IronwoodOutboxItem(
            itemId = text(value, "itemId"),
            partIndex = number(value, "partIndex"),
            txidHex = text(value, "txidHex"),
            rawTransaction = raw,
            payloadDigestHex = digest,
            anchorBoundaryHeight = number(value, "anchorBoundaryHeight"),
            scheduledHeight = number(value, "scheduledHeight"),
            scheduleStartHeight = number(value, "scheduleStartHeight"),
            expiryHeight = number(value, "expiryHeight"),
            status = IronwoodOutboxItemStatus.valueOf(text(value, "status")),
            attemptCount = number(value, "attemptCount").toInt(),
            attemptId = value["attemptId"] as? String,
            attemptStartedAtMs = optionalNumber(value, "attemptStartedAtMs"),
            nextAttemptAtMs = optionalNumber(value, "nextAttemptAtMs"),
            lastError = value["lastError"] as? String,
        )
    }

    private fun decodeReceipt(value: Map<String, Any?>) = IronwoodOutboxReceipt(
        receiptId = text(value, "receiptId"),
        batchId = text(value, "batchId"),
        itemId = text(value, "itemId"),
        network = text(value, "network"),
        accountUuid = text(value, "accountUuid"),
        runId = text(value, "runId"),
        txidHex = text(value, "txidHex"),
        outcome = text(value, "outcome"),
        remoteHeight = number(value, "remoteHeight"),
        responseCode = optionalNumber(value, "responseCode")?.toInt(),
        responseMessage = value["responseMessage"] as? String,
        recordedAtMs = number(value, "recordedAtMs"),
        scheduleUpdates = maps(value["scheduleUpdates"]).map {
            IronwoodOutboxScheduleUpdate(
                text(it, "itemId"),
                number(it, "scheduledHeight"),
                number(it, "scheduleStartHeight"),
            )
        },
        rawTransaction = value["rawTransaction"] as? ByteArray,
    )

    private fun maps(value: Any?): List<Map<String, Any?>> =
        (value as? List<*>)?.map { entry ->
            val map = entry as? Map<*, *>
                ?: throw IllegalArgumentException("Invalid outbox list.")
            require(map.keys.all { it is String }) { "Invalid outbox map." }
            @Suppress("UNCHECKED_CAST")
            map as Map<String, Any?>
        } ?: throw IllegalArgumentException("Invalid outbox list.")

    private fun text(value: Map<String, Any?>, key: String): String =
        value[key] as? String ?: throw IllegalArgumentException("Invalid outbox $key.")

    private fun number(value: Map<String, Any?>, key: String): Long =
        (value[key] as? Number)?.toLong()
            ?: throw IllegalArgumentException("Invalid outbox $key.")

    private fun optionalNumber(value: Map<String, Any?>, key: String): Long? =
        (value[key] as? Number)?.toLong()

    private fun sha256Hex(value: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(value)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
}
