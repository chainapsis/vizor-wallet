package com.keplr.vizor

import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec
import kotlin.random.Random
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class IronwoodMigrationOutboxTest {
    private lateinit var directory: java.io.File
    private lateinit var repository: IronwoodMigrationOutboxRepository

    @Before
    fun setUp() {
        directory = Files.createTempDirectory("ironwood-outbox").toFile()
        repository = IronwoodMigrationOutboxRepository(
            IronwoodMigrationSecureStore(
                keyProvider = TestKeyProvider(),
                directory = directory,
            ),
        )
    }

    @After
    fun tearDown() {
        directory.deleteRecursively()
    }

    @Test
    fun interruptedSubmissionIsRecoveredBeforeNetworkInspection() {
        val item = item(
            status = IronwoodOutboxItemStatus.SUBMITTING,
            expiryHeight = 69_120,
        )
        repository.update { it.batches += batch(item) }

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 50),
            clockMs = { 1_000 },
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.WAITING, result.outcome)
        assertEquals("account-1", result.transportAccountUuid)
        val recovered = repository.read().batches.single().items.single()
        assertEquals(IronwoodOutboxItemStatus.ARMED, recovered.status)
        assertEquals(1, recovered.attemptCount)
        assertEquals(61_000L, recovered.nextAttemptAtMs)
    }

    @Test
    fun dueTransactionWithDifferentCanonicalExpiryRequiresResigning() {
        repository.update {
            it.batches += batch(
                item(
                    scheduledHeight = 100,
                    expiryHeight = 34_560,
                ),
            )
        }

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 100),
            clockMs = { 2_000 },
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION, result.outcome)
        assertEquals("account-1", result.transportAccountUuid)
        val snapshot = repository.read()
        assertEquals(
            IronwoodOutboxItemStatus.NEEDS_RESIGN_AWAITING_RECONCILIATION,
            snapshot.batches.single().items.single().status,
        )
        assertEquals("needsResign", snapshot.receipts.single().outcome)
        assertEquals(
            "batch-1",
            IronwoodOutboxState.pendingNeedsUserActionBatchId(snapshot),
        )
        assertTrue(IronwoodOutboxState.hasRunnableWork(snapshot))

        repository.update {
            assertTrue(
                IronwoodOutboxState.acknowledgeNeedsUserActionNotification(
                    it,
                    "batch-1",
                ),
            )
        }
        assertNull(
            IronwoodOutboxState.pendingNeedsUserActionBatchId(repository.read()),
        )
    }

    @Test
    fun hasBatchRequiresEveryScheduledTransaction() {
        val batch = batch(item(expiryHeight = 69_120))
        val snapshot = IronwoodOutboxSnapshot(batches = mutableListOf(batch))
        val expectedTxids = batch.items.map { it.txidHex }.toSet()

        assertTrue(
            IronwoodOutboxState.hasBatch(
                snapshot = snapshot,
                batchId = batch.batchId,
                network = batch.network,
                accountUuid = batch.accountUuid,
                runId = batch.runId,
                expectedTxids = expectedTxids,
                requiredTxids = expectedTxids,
            ),
        )
        org.junit.Assert.assertThrows(IronwoodOutboxConflictException::class.java) {
            IronwoodOutboxState.hasBatch(
                snapshot = snapshot,
                batchId = batch.batchId,
                network = batch.network,
                accountUuid = batch.accountUuid,
                runId = batch.runId,
                expectedTxids = expectedTxids + "missing-txid",
                requiredTxids = setOf("missing-txid"),
            )
        }
    }

    @Test
    fun discardBatchRemovesOnlyTheIdleRecord() {
        val discarded = batch(
            item(expiryHeight = 69_120),
            batchId = "batch-1",
        )
        val preserved = batch(
            item(expiryHeight = 69_120),
            batchId = "batch-2",
        )
        val snapshot = IronwoodOutboxSnapshot(
            batches = mutableListOf(discarded, preserved),
        )

        assertTrue(IronwoodOutboxState.discardBatch(snapshot, discarded.batchId))
        assertEquals(listOf(preserved.batchId), snapshot.batches.map { it.batchId })
        assertTrue(!IronwoodOutboxState.discardBatch(snapshot, discarded.batchId))
    }

    @Test
    fun discardBatchRefusesDeliveryState() {
        val submitting = item(
            expiryHeight = 69_120,
            status = IronwoodOutboxItemStatus.SUBMITTING,
        )
        val attempted = item(expiryHeight = 69_120).apply {
            attemptCount = 1
        }

        listOf(submitting, attempted).forEach { item ->
            val batch = batch(item)
            val snapshot = IronwoodOutboxSnapshot(
                batches = mutableListOf(batch),
            )

            org.junit.Assert.assertThrows(IronwoodOutboxConflictException::class.java) {
                IronwoodOutboxState.discardBatch(snapshot, batch.batchId)
            }
            assertEquals(listOf(batch.batchId), snapshot.batches.map { it.batchId })
        }
    }

    @Test
    fun acceptedSubmissionCreatesReceiptWithRawTransaction() {
        val raw = byteArrayOf(1, 2, 3)
        repository.update {
            it.batches += batch(
                item(
                    raw = raw,
                    scheduledHeight = 100,
                    expiryHeight = 69_120,
                ),
            )
        }
        val transport = FakeTransport(height = 100)

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = transport,
            clockMs = { 3_000 },
            random = Random(7),
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.ACCEPTED, result.outcome)
        assertArrayEquals(raw, transport.sent.single())
        val snapshot = repository.read()
        assertEquals(
            IronwoodOutboxItemStatus.ACCEPTED_AWAITING_RECONCILIATION,
            snapshot.batches.single().items.single().status,
        )
        assertEquals("accepted", snapshot.receipts.single().outcome)
        assertArrayEquals(raw, snapshot.receipts.single().rawTransaction)
        assertTrue(snapshot.batches.single().broadcastCompletePending)
    }

    @Test
    fun uncertainSubmissionReturnsToArmedWithBackoff() {
        repository.update {
            it.batches += batch(item(scheduledHeight = 100, expiryHeight = 69_120))
        }

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(
                height = 100,
                sendError = IronwoodMigrationNativeException(
                    IronwoodMigrationNativeError.EXECUTION,
                    "network lost",
                ),
            ),
            clockMs = { 5_000 },
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.RETRY, result.outcome)
        val item = repository.read().batches.single().items.single()
        assertEquals(IronwoodOutboxItemStatus.ARMED, item.status)
        assertEquals(1, item.attemptCount)
        assertEquals(65_000L, item.nextAttemptAtMs)
        assertEquals("network lost", item.lastError)
    }

    @Test
    fun heightNoticeDoesNotRetireVerifiedProofReadiness() {
        repository.update {
            it.batches += batch(
                item = null,
                nextProofHeight = 120,
            )
        }

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 120),
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.WAITING, result.outcome)
        assertEquals("batch-1", result.proofReadyBatchId)
        assertEquals(false, result.proofReadyVerified)
        assertNull(result.nextHeight)
        assertNull(repository.read().batches.single().proofReadyObservedHeight)
        assertEquals(
            120L,
            repository.read().batches.single().proofReadyHeightNoticeObservedHeight,
        )

        val pending = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 120),
        ).runOnce()
        assertEquals(IronwoodMigrationOutboxOutcome.NO_WORK, pending.outcome)
        assertEquals("batch-1", pending.proofReadyBatchId)
        assertEquals(false, pending.proofReadyVerified)
        assertTrue(IronwoodOutboxState.hasRunnableWork(repository.read()))

        repository.update {
            assertTrue(
                IronwoodOutboxState.acknowledgeUnverifiedProofReadyNotification(
                    it,
                    "batch-1",
                ),
            )
        }
        val heightNoticeAcknowledged = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 120),
        ).runOnce()
        assertEquals(
            IronwoodMigrationOutboxOutcome.NO_WORK,
            heightNoticeAcknowledged.outcome,
        )
        assertNull(heightNoticeAcknowledged.proofReadyBatchId)
        assertTrue(!IronwoodOutboxState.hasRunnableWork(repository.read()))

        repository.update {
            assertTrue(
                IronwoodOutboxState.recordVerifiedProofReadiness(
                    snapshot = it,
                    network = "test",
                    accountUuid = "account-1",
                    runId = "run-1",
                    observedHeight = 121,
                ),
            )
        }
        val verified = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 121),
        ).runOnce()
        assertEquals(IronwoodMigrationOutboxOutcome.NO_WORK, verified.outcome)
        assertEquals("batch-1", verified.proofReadyBatchId)
        assertEquals(true, verified.proofReadyVerified)
        assertTrue(IronwoodOutboxState.hasRunnableWork(repository.read()))

        repository.update {
            assertTrue(
                IronwoodOutboxState.acknowledgeProofReadyNotification(
                    it,
                    "batch-1",
                ),
            )
        }
        assertTrue(!IronwoodOutboxState.hasRunnableWork(repository.read()))
        repository.update {
            assertTrue(
                IronwoodOutboxState.recordVerifiedProofReadiness(
                    snapshot = it,
                    network = "test",
                    accountUuid = "account-1",
                    runId = "run-1",
                    observedHeight = 122,
                ),
            )
        }
        assertNull(
            IronwoodOutboxState.pendingProofReadyBatchId(repository.read()),
        )
    }

    @Test
    fun terminalReceiptDoesNotAbandonAnotherDueSubmission() {
        repository.update {
            it.batches += batch(
                item(
                    scheduledHeight = 100,
                    expiryHeight = 34_560,
                ),
                batchId = "terminal",
                accountUuid = "account-1",
            )
            it.batches += batch(
                item(
                    scheduledHeight = 100,
                    expiryHeight = 69_120,
                ),
                batchId = "sendable",
                accountUuid = "account-2",
            )
        }

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 100),
            clockMs = { 2_000 },
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.ACCEPTED, result.outcome)
        val snapshot = repository.read()
        assertEquals("needsResign", snapshot.receipts.first { it.batchId == "terminal" }.outcome)
        assertEquals("accepted", snapshot.receipts.first { it.batchId == "sendable" }.outcome)
    }

    @Test
    fun finalItemForOneEndpointContinuesWorkOnAnotherEndpoint() {
        repository.update {
            it.batches += batch(
                item(scheduledHeight = 100, expiryHeight = 69_120),
                batchId = "first",
                accountUuid = "account-1",
                endpoint = "https://a.example",
            )
            it.batches += batch(
                item(scheduledHeight = 200, expiryHeight = 69_120),
                batchId = "second",
                accountUuid = "account-2",
                endpoint = "https://b.example",
            )
        }

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 100),
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.ACCEPTED, result.outcome)
        assertEquals(0L, result.delayMs)
        assertEquals(
            IronwoodOutboxItemStatus.ARMED,
            repository.read().batches.first { it.batchId == "second" }.items.single().status,
        )
    }

    @Test
    fun acceptedItemChecksAnotherEndpointBeforeItsOwnFutureWork() {
        repository.update {
            it.batches += batch(
                item(scheduledHeight = 100, expiryHeight = 69_120),
                batchId = "accepted",
                accountUuid = "account-1",
                endpoint = "https://a.example",
            )
            it.batches += batch(
                item(scheduledHeight = 1_000, expiryHeight = 69_120),
                batchId = "future",
                accountUuid = "account-1",
                endpoint = "https://a.example",
            )
            it.batches += batch(
                item(scheduledHeight = 100, expiryHeight = 69_120),
                batchId = "other-due",
                accountUuid = "account-2",
                endpoint = "https://b.example",
            )
        }

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = FakeTransport(height = 100),
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.ACCEPTED, result.outcome)
        assertEquals(60_000L, result.delayMs)
    }

    @Test
    fun waitingEndpointChecksAnotherEndpointWithinOneMinute() {
        repository.update {
            it.batches += batch(
                item(scheduledHeight = 1_000, expiryHeight = 69_120),
                batchId = "future",
                accountUuid = "account-1",
                endpoint = "https://a.example",
            )
            it.batches += batch(
                item(scheduledHeight = 100, expiryHeight = 69_120),
                batchId = "due",
                accountUuid = "account-2",
                endpoint = "https://b.example",
            )
        }
        val transport = FakeTransport(height = 100)

        val result = IronwoodMigrationOutboxRunner(
            repository = repository,
            transport = transport,
        ).runOnce()

        assertEquals(IronwoodMigrationOutboxOutcome.WAITING, result.outcome)
        assertEquals(60_000L, result.delayMs)
        assertTrue(transport.sent.isEmpty())
    }

    @Test
    fun acknowledgingLastReceiptPreservesPendingCompletion() {
        val accepted = item(
            expiryHeight = 69_120,
            status = IronwoodOutboxItemStatus.ACCEPTED_AWAITING_RECONCILIATION,
        )
        val batch = batch(accepted).copy(broadcastCompletePending = true)
        val receipt = IronwoodOutboxReceipt(
            receiptId = "receipt-1",
            batchId = batch.batchId,
            itemId = accepted.itemId,
            network = batch.network,
            accountUuid = batch.accountUuid,
            runId = batch.runId,
            txidHex = accepted.txidHex,
            outcome = "accepted",
            remoteHeight = 100,
            responseCode = 0,
            responseMessage = "",
            recordedAtMs = 0,
            scheduleUpdates = emptyList(),
            rawTransaction = accepted.rawTransaction,
        )
        val snapshot = IronwoodOutboxSnapshot(
            batches = mutableListOf(batch),
            receipts = mutableListOf(receipt),
        )

        IronwoodOutboxState.acknowledgeReceipts(snapshot, setOf(receipt.receiptId))

        assertTrue(snapshot.receipts.isEmpty())
        assertTrue(snapshot.batches.single().items.isEmpty())
        assertTrue(snapshot.batches.single().broadcastCompletePending)

        assertTrue(
            IronwoodOutboxState.acknowledgeBroadcastCompleteNotification(
                snapshot,
                batch.batchId,
            ),
        )
        assertTrue(snapshot.batches.isEmpty())
        assertTrue(!IronwoodOutboxState.hasRunnableWork(snapshot))
    }

    @Test
    fun cancellationEpochIsVisibleBeforeDrainCompletes() {
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val drained = CountDownLatch(1)
        var cancellationObserved = false
        val runner = Thread {
            IronwoodMigrationOutboxExecutionCoordinator.tryRun { isCancelled ->
                started.countDown()
                release.await(5, TimeUnit.SECONDS)
                cancellationObserved = isCancelled()
            }
        }.apply { start() }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        val canceller = Thread {
            IronwoodMigrationOutboxExecutionCoordinator.cancelAndDrain {
                drained.countDown()
            }
        }.apply { start() }

        assertTrue(!drained.await(100, TimeUnit.MILLISECONDS))
        release.countDown()
        runner.join(5_000)
        canceller.join(5_000)

        assertTrue(cancellationObserved)
        assertEquals(0L, drained.count)
    }

    @Test
    fun exclusiveMutationWaitsForActiveRun() {
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val mutationCompleted = CountDownLatch(1)
        val runner = Thread {
            IronwoodMigrationOutboxExecutionCoordinator.tryRun {
                started.countDown()
                release.await(5, TimeUnit.SECONDS)
            }
        }.apply { start() }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        val mutator = Thread {
            IronwoodMigrationOutboxExecutionCoordinator.runExclusive {
                mutationCompleted.countDown()
            }
        }.apply { start() }

        assertTrue(!mutationCompleted.await(100, TimeUnit.MILLISECONDS))
        release.countDown()
        runner.join(5_000)
        mutator.join(5_000)

        assertEquals(0L, mutationCompleted.count)
    }

    @Test
    fun blockingWorkerEntryWaitsForExclusiveMutation() {
        val mutationStarted = CountDownLatch(1)
        val releaseMutation = CountDownLatch(1)
        val workerCompleted = CountDownLatch(1)
        val mutation = Thread {
            IronwoodMigrationOutboxExecutionCoordinator.runExclusive {
                mutationStarted.countDown()
                releaseMutation.await(5, TimeUnit.SECONDS)
            }
        }.apply { start() }
        assertTrue(mutationStarted.await(5, TimeUnit.SECONDS))
        val worker = Thread {
            IronwoodMigrationOutboxExecutionCoordinator.runWhenAvailable {
                workerCompleted.countDown()
            }
        }.apply { start() }

        assertTrue(!workerCompleted.await(100, TimeUnit.MILLISECONDS))
        releaseMutation.countDown()
        mutation.join(5_000)
        worker.join(5_000)

        assertEquals(0L, workerCompleted.count)
    }

    @Test
    fun foregroundRunWaitsForActiveWorkerInsteadOfReturningRetry() {
        repository.update {
            it.batches += batch(item(scheduledHeight = 100, expiryHeight = 69_120))
        }
        val workerStarted = CountDownLatch(1)
        val releaseWorker = CountDownLatch(1)
        val foregroundCompleted = CountDownLatch(1)
        val foregroundResult =
            AtomicReference<IronwoodMigrationOutboxRunResult>()
        val worker = Thread {
            IronwoodMigrationOutboxExecutionCoordinator.tryRun {
                workerStarted.countDown()
                releaseWorker.await(5, TimeUnit.SECONDS)
            }
        }.apply { start() }
        assertTrue(workerStarted.await(5, TimeUnit.SECONDS))
        val foreground = Thread {
            foregroundResult.set(
                IronwoodMigrationOutboxRunner(
                    repository = repository,
                    transport = FakeTransport(height = 100),
                ).runOnceWaitingForActiveRun(),
            )
            foregroundCompleted.countDown()
        }.apply { start() }

        assertTrue(!foregroundCompleted.await(100, TimeUnit.MILLISECONDS))
        releaseWorker.countDown()
        worker.join(5_000)
        foreground.join(5_000)

        assertEquals(0L, foregroundCompleted.count)
        assertEquals(
            IronwoodMigrationOutboxOutcome.ACCEPTED,
            foregroundResult.get().outcome,
        )
    }

    @Test
    fun foregroundRunDoesNotSubmitWhileMutationIsQuiesced() {
        repository.update {
            it.batches += batch(item(scheduledHeight = 100, expiryHeight = 69_120))
        }
        val transport = FakeTransport(height = 100)
        IronwoodMigrationOutboxExecutionCoordinator.quiesceAndDrain()

        val result = try {
            IronwoodMigrationOutboxRunner(
                repository = repository,
                transport = transport,
            ).runOnceWaitingForActiveRun()
        } finally {
            IronwoodMigrationOutboxExecutionCoordinator.resume()
        }

        assertEquals(IronwoodMigrationOutboxOutcome.RETRY, result.outcome)
        assertTrue(transport.sent.isEmpty())
    }

    private fun batch(
        item: IronwoodOutboxItem?,
        nextProofHeight: Long? = null,
        batchId: String = "batch-1",
        accountUuid: String = "account-1",
        endpoint: String = "https://lightwalletd.example",
    ) = IronwoodOutboxBatch(
        batchId = batchId,
        network = "test",
        accountUuid = accountUuid,
        runId = "run-1",
        lightwalletdUrl = endpoint,
        timingMeanBlocks = 10,
        timingMaxBlocks = 20,
        createdAtMs = 0,
        armedAtMs = 1,
        nextProofHeight = nextProofHeight,
        items = item?.let { mutableListOf(it) } ?: mutableListOf(),
    )

    private fun item(
        raw: ByteArray = byteArrayOf(1, 2, 3),
        scheduledHeight: Long = 100,
        expiryHeight: Long,
        status: IronwoodOutboxItemStatus = IronwoodOutboxItemStatus.ARMED,
    ) = IronwoodOutboxItem(
        itemId = "item-1",
        partIndex = 0,
        txidHex = "abcd",
        rawTransaction = raw,
        payloadDigestHex = java.security.MessageDigest.getInstance("SHA-256")
            .digest(raw)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) },
        anchorBoundaryHeight = 0,
        scheduledHeight = scheduledHeight,
        scheduleStartHeight = 0,
        expiryHeight = expiryHeight,
        status = status,
    )

    private class FakeTransport(
        private val height: Long,
        private val sendError: IronwoodMigrationNativeException? = null,
    ) : IronwoodMigrationOutboxTransport {
        val sent = mutableListOf<ByteArray>()

        override fun latestBlockHeight(lightwalletdUrl: String): Long = height

        override fun sendTransaction(
            lightwalletdUrl: String,
            rawTransaction: ByteArray,
        ): IronwoodMigrationSendResponse {
            sendError?.let { throw it }
            sent += rawTransaction.copyOf()
            return IronwoodMigrationSendResponse(0, "")
        }
    }

    private class TestKeyProvider : IronwoodMigrationKeyProvider {
        private val key = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")
        override fun getOrCreate(): SecretKey = key
        override fun delete() = Unit
    }
}
