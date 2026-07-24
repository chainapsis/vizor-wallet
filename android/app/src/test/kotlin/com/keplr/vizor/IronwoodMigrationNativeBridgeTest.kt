package com.keplr.vizor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class IronwoodMigrationNativeBridgeTest {
    @Test
    fun preparationProgressIsDecodedFromNativeEnvelope() {
        val bindings = FakeBindings().apply {
            inspectResult = IronwoodMigrationNativeCallResult(
                0,
                null,
                longArrayOf(5, 2, 10, 3, 4),
            )
        }

        val progress = IronwoodMigrationNativeBridge(bindings).inspect(
            "/tmp/wallet.db",
            "test",
            "account-1",
            "run-1",
        )

        assertEquals(
            IronwoodMigrationNativePreparationState.WAITING_FOR_PREPARED_NOTE_ANCHOR,
            progress.state,
        )
        assertEquals(2, progress.confirmationCount)
        assertEquals(10, progress.confirmationTarget)
        assertEquals(3, progress.completedStageCount)
        assertEquals(4, progress.totalStageCount)
    }

    @Test
    fun nativeErrorCodesRemainTyped() {
        val bindings = FakeBindings().apply {
            inspectResult = IronwoodMigrationNativeCallResult(
                2,
                "Another wallet sync is already running",
                null,
            )
        }

        val error = assertThrows(IronwoodMigrationNativeException::class.java) {
            IronwoodMigrationNativeBridge(bindings).inspect(
                "/tmp/wallet.db",
                "test",
                "account-1",
                "run-1",
            )
        }

        assertEquals(IronwoodMigrationNativeError.SYNC_ALREADY_RUNNING, error.reason)
    }

    @Test
    fun malformedNativeProgressFailsClosed() {
        val bindings = FakeBindings().apply {
            inspectResult = IronwoodMigrationNativeCallResult(
                0,
                null,
                longArrayOf(1, -1, 0, 0, 0),
            )
        }

        val error = assertThrows(IronwoodMigrationNativeException::class.java) {
            IronwoodMigrationNativeBridge(bindings).inspect(
                "/tmp/wallet.db",
                "test",
                "account-1",
                "run-1",
            )
        }

        assertEquals(IronwoodMigrationNativeError.INVALID_RESPONSE, error.reason)
    }

    @Test
    fun syncProgressIsForwardedAndValidated() {
        val bindings = FakeBindings()
        var progress: IronwoodMigrationNativeSyncProgress? = null

        IronwoodMigrationNativeBridge(bindings).runSync(
            "/tmp/wallet.db",
            "https://lwd.example:443",
            "test",
        ) {
            progress = it
        }

        assertEquals(100L, progress?.scannedHeight)
        assertEquals(120L, progress?.chainTipHeight)
        assertEquals(0.5, progress?.percentage)
        assertTrue(progress?.isSyncing == true)
        assertFalse(progress?.isComplete == true)
        assertTrue(progress?.hasNewTx == true)
    }

    private class FakeBindings : IronwoodMigrationNativeBindings {
        var inspectResult = IronwoodMigrationNativeCallResult(
            0,
            null,
            longArrayOf(4, 0, 0, 0, 0),
        )

        override fun nativeBeginOperation(): Boolean = true

        override fun nativeEndOperation() = Unit

        override fun nativeCancelOperation(): Boolean = true

        override fun nativeIsSyncRunning(): Boolean = false

        override fun nativeInspect(
            dbPath: String,
            network: String,
            accountUuid: String,
            expectedRunId: String,
        ): IronwoodMigrationNativeCallResult = inspectResult

        override fun nativeAdvance(
            dbPath: String,
            lightwalletdUrl: String,
            network: String,
            accountUuid: String,
            expectedRunId: String,
            credential: ByteArray,
            saltBase64: String,
        ): IronwoodMigrationNativeCallResult = inspectResult

        override fun nativeRunSync(
            dbPath: String,
            lightwalletdUrl: String,
            network: String,
            callback: IronwoodMigrationNativeSyncCallback,
        ): IronwoodMigrationNativeCallResult {
            callback.onProgress(
                100,
                120,
                0.5,
                0.75,
                20,
                true,
                false,
                true,
            )
            return IronwoodMigrationNativeCallResult(0, null, null)
        }
    }
}
