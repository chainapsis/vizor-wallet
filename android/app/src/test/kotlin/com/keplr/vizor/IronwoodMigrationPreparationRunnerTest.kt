package com.keplr.vizor

import androidx.work.NetworkType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IronwoodMigrationPreparationRunnerTest {
    @Test
    fun schedulerRequestRequiresNetworkAndUsesOneGlobalTag() {
        val request = IronwoodMigrationPreparationScheduler.request()

        assertEquals(
            NetworkType.CONNECTED,
            request.workSpec.constraints.requiredNetworkType,
        )
        assertTrue(request.tags.contains(IronwoodMigrationPreparationScheduler.WORK_TAG))
        assertEquals(0, request.workSpec.initialDelay)
    }

    @Test
    fun manifestDecoderRejectsUnexpectedFields() {
        val encoded = """
            {
              "version": 1,
              "network": "test",
              "accountUuid": "account",
              "dbPath": "/tmp/wallet.db",
              "lightwalletdUrl": "https://example.test",
              "credentialHex": "${"ab".repeat(32)}",
              "saltBase64": "AAAAAAAAAAAAAAAAAAAAAA==",
              "expectedRunId": "run",
              "unexpected": true
            }
        """.trimIndent()

        val error = org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            IronwoodMigrationPreparationManifest.decode(encoded)
        }

        assertEquals("Invalid migration manifest fields.", error.message)
    }

    @Test
    fun waitingPreparationSyncsAdvancesAndClearsCredentialBytes() {
        val native = FakeNative(
            inspectResults = ArrayDeque(listOf(progress(WAITING))),
            advanceResult = progress(PROOF_READY),
        )

        val outcome = IronwoodMigrationPreparationRunner(native).run(listOf(manifest()))

        assertEquals(IronwoodMigrationPreparationOutcome.COMPLETED, outcome)
        assertEquals(1, native.syncCalls)
        assertEquals(1, native.advanceCalls)
        assertTrue(native.credentialReference!!.all { it == 0.toByte() })
        assertEquals(1, native.endCalls)
    }

    @Test
    fun proofAnchorWaitOnlyReinspectsAfterSync() {
        val native = FakeNative(
            inspectResults = ArrayDeque(
                listOf(progress(WAITING_ANCHOR), progress(WAITING_ANCHOR)),
            ),
        )

        val outcome = IronwoodMigrationPreparationRunner(native).run(listOf(manifest()))

        assertEquals(IronwoodMigrationPreparationOutcome.WAITING, outcome)
        assertEquals(1, native.syncCalls)
        assertEquals(0, native.advanceCalls)
        assertEquals(2, native.inspectCalls)
    }

    @Test
    fun accountsSharingSyncContextSyncOnlyOnce() {
        val native = FakeNative(
            inspectResults = ArrayDeque(listOf(progress(WAITING), progress(WAITING))),
            advanceResult = progress(PROOF_READY),
        )

        val outcome = IronwoodMigrationPreparationRunner(native).run(
            listOf(manifest(accountUuid = "one"), manifest(accountUuid = "two")),
        )

        assertEquals(IronwoodMigrationPreparationOutcome.COMPLETED, outcome)
        assertEquals(1, native.syncCalls)
        assertEquals(2, native.advanceCalls)
    }

    @Test
    fun foregroundSyncContentionDefersWithoutAdvancing() {
        val native = FakeNative(
            inspectResults = ArrayDeque(listOf(progress(WAITING))),
            syncRunning = true,
        )

        val outcome = IronwoodMigrationPreparationRunner(native).run(listOf(manifest()))

        assertEquals(IronwoodMigrationPreparationOutcome.BUSY, outcome)
        assertEquals(0, native.syncCalls)
        assertEquals(0, native.advanceCalls)
        assertEquals(1, native.endCalls)
    }

    @Test
    fun preparationOperationContentionUsesFixedDelayOutcome() {
        val native = FakeNative(
            inspectResults = ArrayDeque(),
            beginOperationResult = false,
        )

        val outcome = IronwoodMigrationPreparationRunner(native).run(listOf(manifest()))

        assertEquals(IronwoodMigrationPreparationOutcome.BUSY, outcome)
        assertEquals(0, native.inspectCalls)
        assertEquals(0, native.endCalls)
    }

    @Test
    fun nativeSyncContentionUsesFixedDelayOutcome() {
        val native = FakeNative(
            inspectResults = ArrayDeque(listOf(progress(WAITING))),
            syncError = IronwoodMigrationNativeError.SYNC_ALREADY_RUNNING,
        )

        val outcome = IronwoodMigrationPreparationRunner(native).run(listOf(manifest()))

        assertEquals(IronwoodMigrationPreparationOutcome.BUSY, outcome)
        assertEquals(1, native.syncCalls)
        assertEquals(0, native.advanceCalls)
    }

    @Test
    fun cancellationEndsTheOwnedOperation() {
        val native = FakeNative(
            inspectResults = ArrayDeque(listOf(progress(WAITING))),
        )

        val outcome = IronwoodMigrationPreparationRunner(
            native = native,
            isStopped = { true },
        ).run(listOf(manifest()))

        assertEquals(IronwoodMigrationPreparationOutcome.CANCELLED, outcome)
        assertEquals(1, native.endCalls)
        assertFalse(native.operationActive)
    }

    private fun manifest(accountUuid: String = "account") =
        IronwoodMigrationPreparationManifest(
            network = "test",
            accountUuid = accountUuid,
            dbPath = "/tmp/wallet.db",
            lightwalletdUrl = "https://example.test",
            credentialHex = "ab".repeat(32),
            saltBase64 = "AAAAAAAAAAAAAAAAAAAAAA==",
            expectedRunId = "run",
        )

    private fun progress(
        state: IronwoodMigrationNativePreparationState,
    ) = IronwoodMigrationNativePreparationProgress(state, 0, 10, 0, 1)

    private class FakeNative(
        private val inspectResults:
            ArrayDeque<IronwoodMigrationNativePreparationProgress>,
        private val advanceResult: IronwoodMigrationNativePreparationProgress =
            IronwoodMigrationNativePreparationProgress(
                PROOF_READY,
                0,
                10,
                0,
                1,
            ),
        private val syncRunning: Boolean = false,
        private val beginOperationResult: Boolean = true,
        private val syncError: IronwoodMigrationNativeError? = null,
    ) : IronwoodMigrationPreparationNative {
        var operationActive = false
        var inspectCalls = 0
        var syncCalls = 0
        var advanceCalls = 0
        var endCalls = 0
        var credentialReference: ByteArray? = null

        override fun beginOperation(): Boolean {
            operationActive = beginOperationResult
            return beginOperationResult
        }

        override fun endOperation() {
            operationActive = false
            endCalls += 1
        }

        override fun cancelOperation(): Boolean = true

        override fun isSyncRunning(): Boolean = syncRunning

        override fun inspect(
            dbPath: String,
            network: String,
            accountUuid: String,
            expectedRunId: String,
        ): IronwoodMigrationNativePreparationProgress {
            inspectCalls += 1
            return inspectResults.removeFirst()
        }

        override fun advance(
            dbPath: String,
            lightwalletdUrl: String,
            network: String,
            accountUuid: String,
            expectedRunId: String,
            credential: ByteArray,
            saltBase64: String,
        ): IronwoodMigrationNativePreparationProgress {
            advanceCalls += 1
            credentialReference = credential
            return advanceResult
        }

        override fun runSync(
            dbPath: String,
            lightwalletdUrl: String,
            network: String,
            onProgress: (IronwoodMigrationNativeSyncProgress) -> Unit,
        ) {
            syncCalls += 1
            syncError?.let {
                throw IronwoodMigrationNativeException(it, "sync contention")
            }
        }
    }

    private companion object {
        val WAITING =
            IronwoodMigrationNativePreparationState.WAITING_FOR_DENOMINATION_PREPARATION
        val WAITING_ANCHOR =
            IronwoodMigrationNativePreparationState.WAITING_FOR_PREPARED_NOTE_ANCHOR
        val PROOF_READY = IronwoodMigrationNativePreparationState.PROOF_READY
    }
}
