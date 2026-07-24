package com.keplr.vizor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Worker
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import org.json.JSONObject

internal data class IronwoodMigrationPreparationManifest(
    val network: String,
    val accountUuid: String,
    val dbPath: String,
    val lightwalletdUrl: String,
    val credentialHex: String,
    val saltBase64: String,
    val expectedRunId: String?,
) {
    val syncContext: String
        get() = "$dbPath\u0000$lightwalletdUrl\u0000$network"

    companion object {
        fun decode(encoded: String): IronwoodMigrationPreparationManifest {
            val json = JSONObject(encoded)
            require(json.keys().asSequence().toSet() == MANIFEST_FIELDS) {
                "Invalid migration manifest fields."
            }
            require(json.getInt("version") == MANIFEST_VERSION) {
                "Unsupported migration manifest version."
            }
            val expectedRunId = if (json.isNull("expectedRunId")) {
                null
            } else {
                json.getString("expectedRunId").requireNotBlank("expectedRunId")
            }
            return IronwoodMigrationPreparationManifest(
                network = json.getString("network").also {
                    require(it in SUPPORTED_NETWORKS) { "Unsupported network." }
                },
                accountUuid = json.getString("accountUuid").requireNotBlank("accountUuid"),
                dbPath = json.getString("dbPath").requireNotBlank("dbPath"),
                lightwalletdUrl =
                    json.getString("lightwalletdUrl").requireNotBlank("lightwalletdUrl"),
                credentialHex = json.getString("credentialHex").also {
                    require(CREDENTIAL.matches(it)) {
                        "Invalid migration credential."
                    }
                },
                saltBase64 = json.getString("saltBase64").also {
                    require(SALT.matches(it)) { "Invalid migration salt." }
                },
                expectedRunId = expectedRunId,
            )
        }

        private fun String.requireNotBlank(name: String): String = also {
            require(isNotBlank() && trim() == this) { "Invalid $name." }
        }

        private val SUPPORTED_NETWORKS = setOf("main", "test", "regtest")
        private val CREDENTIAL = Regex("^[0-9a-f]{64}$")
        private val SALT = Regex("^[A-Za-z0-9+/]{22}==$")
        private const val MANIFEST_VERSION = 1
        private val MANIFEST_FIELDS = setOf(
            "version",
            "network",
            "accountUuid",
            "dbPath",
            "lightwalletdUrl",
            "credentialHex",
            "saltBase64",
            "expectedRunId",
        )
    }
}

internal enum class IronwoodMigrationPreparationOutcome {
    COMPLETED,
    WAITING,
    BUSY,
    NEEDS_USER_ACTION,
    CANCELLED,
    RETRY,
}

/**
 * Executes one resumable preparation pass. WorkManager owns retry timing while
 * the Rust core owns cancellation and foreground-sync exclusion.
 */
internal class IronwoodMigrationPreparationRunner(
    private val native: IronwoodMigrationPreparationNative,
    private val isStopped: () -> Boolean = { false },
    private val onOperationStarted: () -> Unit = {},
    private val onOperationEnded: () -> Unit = {},
) {
    fun run(
        manifests: List<IronwoodMigrationPreparationManifest>,
        onSyncProgress: (IronwoodMigrationNativeSyncProgress) -> Unit = {},
    ): IronwoodMigrationPreparationOutcome {
        val active = manifests.filter { it.expectedRunId != null }
        if (active.isEmpty()) return IronwoodMigrationPreparationOutcome.COMPLETED
        if (!native.beginOperation()) return IronwoodMigrationPreparationOutcome.BUSY
        onOperationStarted()

        return try {
            runActive(active, onSyncProgress)
        } finally {
            try {
                onOperationEnded()
            } finally {
                native.endOperation()
            }
        }
    }

    private fun runActive(
        manifests: List<IronwoodMigrationPreparationManifest>,
        onSyncProgress: (IronwoodMigrationNativeSyncProgress) -> Unit,
    ): IronwoodMigrationPreparationOutcome {
        val syncedContexts = mutableSetOf<String>()
        var isWaiting = false
        for (manifest in manifests) {
            if (isStopped()) return IronwoodMigrationPreparationOutcome.CANCELLED
            val outcome = runManifest(manifest, syncedContexts, onSyncProgress)
            when (outcome) {
                IronwoodMigrationPreparationOutcome.COMPLETED -> Unit
                IronwoodMigrationPreparationOutcome.WAITING -> isWaiting = true
                else -> return outcome
            }
        }
        return if (isWaiting) {
            IronwoodMigrationPreparationOutcome.WAITING
        } else {
            IronwoodMigrationPreparationOutcome.COMPLETED
        }
    }

    private fun runManifest(
        manifest: IronwoodMigrationPreparationManifest,
        syncedContexts: MutableSet<String>,
        onSyncProgress: (IronwoodMigrationNativeSyncProgress) -> Unit,
    ): IronwoodMigrationPreparationOutcome {
        val runId = checkNotNull(manifest.expectedRunId)
        var progress = try {
            native.inspect(
                manifest.dbPath,
                manifest.network,
                manifest.accountUuid,
                runId,
            )
        } catch (error: IronwoodMigrationNativeException) {
            return error.toOutcome()
        }
        if (!progress.state.needsSync) return progress.state.toOutcome()
        if (isStopped()) return IronwoodMigrationPreparationOutcome.CANCELLED

        if (syncedContexts.add(manifest.syncContext)) {
            if (native.isSyncRunning()) return IronwoodMigrationPreparationOutcome.BUSY
            try {
                native.runSync(
                    manifest.dbPath,
                    manifest.lightwalletdUrl,
                    manifest.network,
                    onSyncProgress,
                )
            } catch (error: IronwoodMigrationNativeException) {
                return error.toOutcome()
            }
        }
        if (isStopped()) return IronwoodMigrationPreparationOutcome.CANCELLED

        if (
            progress.state ==
            IronwoodMigrationNativePreparationState.WAITING_FOR_PREPARED_NOTE_ANCHOR
        ) {
            progress = try {
                native.inspect(
                    manifest.dbPath,
                    manifest.network,
                    manifest.accountUuid,
                    runId,
                )
            } catch (error: IronwoodMigrationNativeException) {
                return error.toOutcome()
            }
        } else {
            val credential = manifest.credentialHex.toByteArray(Charsets.US_ASCII)
            progress = try {
                native.advance(
                    manifest.dbPath,
                    manifest.lightwalletdUrl,
                    manifest.network,
                    manifest.accountUuid,
                    runId,
                    credential,
                    manifest.saltBase64,
                )
            } catch (error: IronwoodMigrationNativeException) {
                return error.toOutcome()
            } finally {
                credential.fill(0)
            }
        }
        return progress.state.toOutcome()
    }

    private val IronwoodMigrationNativePreparationState.needsSync: Boolean
        get() =
            this ==
                IronwoodMigrationNativePreparationState
                    .WAITING_FOR_DENOMINATION_PREPARATION ||
                this ==
                IronwoodMigrationNativePreparationState
                    .WAITING_FOR_PREPARED_NOTE_ANCHOR

    private fun IronwoodMigrationNativePreparationState.toOutcome() = when (this) {
        IronwoodMigrationNativePreparationState.PROOF_READY,
        IronwoodMigrationNativePreparationState.INACTIVE,
        -> IronwoodMigrationPreparationOutcome.COMPLETED
        IronwoodMigrationNativePreparationState.WAITING_FOR_DENOMINATION_PREPARATION,
        IronwoodMigrationNativePreparationState.WAITING_FOR_PREPARED_NOTE_ANCHOR,
        -> IronwoodMigrationPreparationOutcome.WAITING
        IronwoodMigrationNativePreparationState.NEEDS_USER_ACTION ->
            IronwoodMigrationPreparationOutcome.NEEDS_USER_ACTION
        IronwoodMigrationNativePreparationState.CANCELLED ->
            IronwoodMigrationPreparationOutcome.CANCELLED
    }

    private fun IronwoodMigrationNativeException.toOutcome() = when (reason) {
        IronwoodMigrationNativeError.INVALID_CREDENTIAL,
        IronwoodMigrationNativeError.INVALID_ARGUMENT,
        IronwoodMigrationNativeError.INVALID_RESPONSE,
        -> IronwoodMigrationPreparationOutcome.NEEDS_USER_ACTION
        IronwoodMigrationNativeError.SYNC_ALREADY_RUNNING ->
            IronwoodMigrationPreparationOutcome.BUSY
        IronwoodMigrationNativeError.NO_ACTIVE_OPERATION,
        IronwoodMigrationNativeError.EXECUTION,
        IronwoodMigrationNativeError.CALLBACK,
        IronwoodMigrationNativeError.PANIC,
        -> if (isStopped()) {
            IronwoodMigrationPreparationOutcome.CANCELLED
        } else {
            IronwoodMigrationPreparationOutcome.RETRY
        }
    }
}

internal object IronwoodMigrationPreparationScheduler {
    const val UNIQUE_WORK_NAME = "ironwood-migration-preparation"
    const val WORK_TAG = "ironwood-migration-preparation"
    private const val RETRY_DELAY_MINUTES = 1L

    fun enqueue(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request(),
        )
    }

    fun enqueueContinuation(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            request(initialDelayMinutes = RETRY_DELAY_MINUTES),
        )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
    }

    internal fun request(initialDelayMinutes: Long = 0): OneTimeWorkRequest =
        OneTimeWorkRequestBuilder<IronwoodMigrationPreparationWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setBackoffCriteria(
                BackoffPolicy.LINEAR,
                RETRY_DELAY_MINUTES,
                TimeUnit.MINUTES,
            )
            .setInitialDelay(initialDelayMinutes, TimeUnit.MINUTES)
            .addTag(WORK_TAG)
            .build()
}

class IronwoodMigrationPreparationWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    @Volatile
    private var native: IronwoodMigrationPreparationNative? = null

    override fun doWork(): Result {
        val bridge = IronwoodMigrationNativeBridge()
        return try {
            setForegroundAsync(createForegroundInfo()).get()
            val manifests = IronwoodMigrationSecureStore(applicationContext)
                .readAllManifests()
                .map(IronwoodMigrationPreparationManifest::decode)
            val outcome = IronwoodMigrationPreparationRunner(
                native = bridge,
                isStopped = { isStopped },
                onOperationStarted = { native = bridge },
                onOperationEnded = { native = null },
            ).run(manifests)
            outcome.toWorkerResult()
        } catch (error: IllegalArgumentException) {
            Result.failure(workDataOf(OUTPUT_ERROR to (error.message ?: "Invalid manifest.")))
        } catch (error: Exception) {
            if (isStopped) {
                Result.failure()
            } else {
                Result.retry()
            }
        } finally {
            native = null
        }
    }

    override fun onStopped() {
        native?.cancelOperation()
        super.onStopped()
    }

    private fun IronwoodMigrationPreparationOutcome.toWorkerResult() = when (this) {
        IronwoodMigrationPreparationOutcome.COMPLETED -> Result.success()
        IronwoodMigrationPreparationOutcome.WAITING,
        IronwoodMigrationPreparationOutcome.BUSY,
        -> {
            // Expected confirmation waits and foreground-sync contention are
            // not failed attempts. Append fresh work so WorkManager backoff
            // does not grow without bound.
            IronwoodMigrationPreparationScheduler.enqueueContinuation(
                applicationContext,
            )
            Result.success()
        }
        IronwoodMigrationPreparationOutcome.RETRY -> Result.retry()
        IronwoodMigrationPreparationOutcome.NEEDS_USER_ACTION ->
            Result.failure(workDataOf(OUTPUT_ERROR to "needs_user_action"))
        IronwoodMigrationPreparationOutcome.CANCELLED -> Result.failure()
    }

    private fun createForegroundInfo(): ForegroundInfo {
        val manager = applicationContext.getSystemService(
            Service.NOTIFICATION_SERVICE,
        ) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Wallet migration",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val notification: Notification = NotificationCompat.Builder(
            applicationContext,
            NOTIFICATION_CHANNEL_ID,
        )
            .setSmallIcon(applicationContext.applicationInfo.icon)
            .setContentTitle("Preparing wallet migration")
            .setContentText("Vizor is securely preparing your wallet in the background.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .build()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private companion object {
        const val NOTIFICATION_CHANNEL_ID = "ironwood_migration_preparation"
        const val NOTIFICATION_ID = 318
        const val OUTPUT_ERROR = "error"
    }
}
