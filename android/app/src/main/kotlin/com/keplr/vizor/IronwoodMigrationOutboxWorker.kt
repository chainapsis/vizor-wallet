package com.keplr.vizor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
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
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlin.math.min
import kotlin.random.Random

internal enum class IronwoodMigrationOutboxOutcome {
    NO_WORK,
    WAITING,
    ACCEPTED,
    NEEDS_USER_ACTION,
    RETRY,
    CANCELLED,
}

internal data class IronwoodMigrationOutboxRunResult(
    val outcome: IronwoodMigrationOutboxOutcome,
    val nextHeight: Long? = null,
    val observedHeight: Long? = null,
    val delayMs: Long? = null,
    val proofReadyBatchId: String? = null,
)

internal enum class IronwoodMigrationNotificationDelivery {
    DELIVERED,
    DISABLED,
    RETRY,
}

private data class IronwoodOutboxSubmission(
    val batchId: String,
    val itemId: String,
    val rawTransaction: ByteArray,
)

internal object IronwoodMigrationOutboxExecutionCoordinator {
    private val runLock = ReentrantLock()
    private val cancellationEpoch = AtomicLong()
    private val quiescing = AtomicBoolean()

    fun <T> tryRun(block: (isCancelled: () -> Boolean) -> T): T? {
        if (quiescing.get()) return null
        if (!runLock.tryLock()) return null
        val epoch = cancellationEpoch.get()
        if (quiescing.get()) {
            runLock.unlock()
            return null
        }
        return try {
            block { cancellationEpoch.get() != epoch }
        } finally {
            runLock.unlock()
        }
    }

    fun <T> runExclusive(block: () -> T): T = runLock.withLock(block)

    fun <T> runWhenAvailable(
        block: (isCancelled: () -> Boolean) -> T,
    ): T? {
        if (quiescing.get()) return null
        runLock.lock()
        return try {
            if (quiescing.get()) return null
            val epoch = cancellationEpoch.get()
            block {
                quiescing.get() || cancellationEpoch.get() != epoch
            }
        } finally {
            runLock.unlock()
        }
    }

    fun cancelAndDrain(block: () -> Unit) {
        quiescing.set(true)
        cancellationEpoch.incrementAndGet()
        try {
            runLock.withLock(block)
        } finally {
            quiescing.set(false)
        }
    }
}

internal class IronwoodMigrationOutboxRunner(
    private val repository: IronwoodMigrationOutboxRepository,
    private val transport: IronwoodMigrationOutboxTransport,
    private val isStopped: () -> Boolean = { false },
    private val clockMs: () -> Long = System::currentTimeMillis,
    private val random: Random = Random.Default,
) {
    fun runOnce(): IronwoodMigrationOutboxRunResult {
        return IronwoodMigrationOutboxExecutionCoordinator.tryRun { isCancelled ->
            runOnceLocked { isStopped() || isCancelled() }
        } ?: result(IronwoodMigrationOutboxOutcome.RETRY)
    }

    fun runOnceWaitingForActiveRun(): IronwoodMigrationOutboxRunResult =
        IronwoodMigrationOutboxExecutionCoordinator.runExclusive {
            runOnceLocked(isStopped)
        }

    private fun runOnceLocked(cancelled: () -> Boolean): IronwoodMigrationOutboxRunResult {
        if (cancelled()) return result(IronwoodMigrationOutboxOutcome.CANCELLED)
        var pendingProofReadyBatchId: String? = null
        val endpoint = repository.update { snapshot ->
            IronwoodOutboxState.recoverInterrupted(snapshot, clockMs())
            pendingProofReadyBatchId =
                IronwoodOutboxState.pendingProofReadyBatchId(snapshot)
            IronwoodOutboxState.nextEndpoint(snapshot)
        } ?: return result(
            IronwoodMigrationOutboxOutcome.NO_WORK,
            pendingProofReadyBatchId,
        )

        val remoteHeight = try {
            transport.latestBlockHeight(endpoint)
        } catch (_: IronwoodMigrationNativeException) {
            return if (cancelled()) {
                result(
                    IronwoodMigrationOutboxOutcome.CANCELLED,
                    pendingProofReadyBatchId,
                )
            } else {
                result(
                    IronwoodMigrationOutboxOutcome.RETRY,
                    pendingProofReadyBatchId,
                )
            }
        }
        if (cancelled()) {
            return result(
                IronwoodMigrationOutboxOutcome.CANCELLED,
                pendingProofReadyBatchId,
            )
        }

        var needsUserAction = false
        var proofReadyBatchId = pendingProofReadyBatchId
        var selectedBatchId: String? = null
        val submission = try {
            repository.update { snapshot ->
                val now = clockMs()
                needsUserAction = IronwoodOutboxState.expireAndMarkNoncanonical(
                    snapshot,
                    endpoint,
                    remoteHeight,
                    now,
                )
                val newlyProofReadyBatchId = IronwoodOutboxState.markProofReadyIfNeeded(
                    snapshot,
                    endpoint,
                    remoteHeight,
                )
                proofReadyBatchId = proofReadyBatchId ?: newlyProofReadyBatchId
                val selected = IronwoodOutboxState.selectDue(
                    snapshot,
                    endpoint,
                    remoteHeight,
                    now,
                )
                selected?.let { (batch, item) ->
                    selectedBatchId = batch.batchId
                    IronwoodOutboxState.validateReschedulingAfterAcceptance(
                        batch,
                        item.itemId,
                        remoteHeight,
                    )
                    IronwoodOutboxState.beginSubmission(item, now)
                    IronwoodOutboxSubmission(
                        batch.batchId,
                        item.itemId,
                        item.rawTransaction.copyOf(),
                    )
                }
            }
        } catch (_: IllegalArgumentException) {
            selectedBatchId?.let(::markNeedsUserActionNotificationPending)
            return result(
                IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION,
                proofReadyBatchId,
            )
        }
        if (submission == null) {
            if (needsUserAction) {
                return result(
                    IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION,
                    proofReadyBatchId,
                )
            }
            return waiting(endpoint, remoteHeight, proofReadyBatchId)
        }
        if (cancelled()) {
            recordUncertain(submission, "The outbox worker was stopped.")
            return result(
                IronwoodMigrationOutboxOutcome.CANCELLED,
                proofReadyBatchId,
            )
        }

        val response = try {
            transport.sendTransaction(endpoint, submission.rawTransaction)
        } catch (error: IronwoodMigrationNativeException) {
            recordUncertain(submission, error.message ?: "Transaction submission failed.")
            return if (cancelled()) {
                result(
                    IronwoodMigrationOutboxOutcome.CANCELLED,
                    proofReadyBatchId,
                )
            } else {
                result(
                    IronwoodMigrationOutboxOutcome.RETRY,
                    proofReadyBatchId,
                )
            }
        } finally {
            submission.rawTransaction.fill(0)
        }

        return try {
            repository.update { snapshot ->
                val batch = snapshot.batches.first { it.batchId == submission.batchId }
                val item = batch.items.first { it.itemId == submission.itemId }
                if (response.errorCode == 0 || isAcceptedEquivalent(response.errorMessage)) {
                    IronwoodOutboxState.recordAccepted(
                        snapshot = snapshot,
                        batch = batch,
                        item = item,
                        equivalent = response.errorCode != 0,
                        remoteHeight = remoteHeight,
                        responseCode = response.errorCode,
                        responseMessage = response.errorMessage,
                        nowMs = clockMs(),
                        random = random,
                    )
                    val next = IronwoodOutboxState.nextActionHeight(snapshot, endpoint)
                    var delay = IronwoodOutboxState.nextCheckDelayMs(remoteHeight, next)
                        ?: 0L.takeIf { IronwoodOutboxState.hasRunnableWork(snapshot) }
                    if (
                        delay != null &&
                        IronwoodOutboxState.hasDeliveryWorkForOtherEndpoint(
                            snapshot,
                            endpoint,
                        )
                    ) {
                        delay = min(delay, OTHER_ENDPOINT_CHECK_DELAY_MS)
                    }
                    IronwoodMigrationOutboxRunResult(
                        outcome = IronwoodMigrationOutboxOutcome.ACCEPTED,
                        nextHeight = next,
                        observedHeight = remoteHeight,
                        delayMs = delay,
                        proofReadyBatchId = proofReadyBatchId,
                    )
                } else {
                    IronwoodOutboxState.recordRejected(
                        snapshot,
                        batch,
                        item,
                        remoteHeight,
                        response.errorCode,
                        response.errorMessage,
                        clockMs(),
                    )
                    result(
                        IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION,
                        proofReadyBatchId,
                    )
                }
            }
        } catch (_: Exception) {
            markNeedsUserActionNotificationPending(submission.batchId)
            result(
                IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION,
                proofReadyBatchId,
            )
        }
    }

    private fun waiting(
        endpoint: String,
        remoteHeight: Long,
        proofReadyBatchId: String?,
    ): IronwoodMigrationOutboxRunResult {
        val snapshot = repository.read()
        val next = IronwoodOutboxState.nextActionHeight(snapshot, endpoint)
        var delay = IronwoodOutboxState.nextCheckDelayMs(remoteHeight, next)
            ?: 0L.takeIf { IronwoodOutboxState.hasRunnableWork(snapshot) }
        if (
            delay != null &&
            IronwoodOutboxState.hasDeliveryWorkForOtherEndpoint(snapshot, endpoint)
        ) {
            delay = min(delay, OTHER_ENDPOINT_CHECK_DELAY_MS)
        }
        return IronwoodMigrationOutboxRunResult(
            outcome = IronwoodMigrationOutboxOutcome.WAITING,
            nextHeight = next,
            observedHeight = remoteHeight,
            delayMs = delay,
            proofReadyBatchId = proofReadyBatchId,
        )
    }

    private fun recordUncertain(
        submission: IronwoodOutboxSubmission,
        message: String,
    ) {
        runCatching {
            repository.update { snapshot ->
                val item = snapshot.batches.first { it.batchId == submission.batchId }
                    .items.first { it.itemId == submission.itemId }
                IronwoodOutboxState.recordUncertain(item, message, clockMs())
            }
        }
    }

    private fun markNeedsUserActionNotificationPending(batchId: String) {
        runCatching {
            repository.update { snapshot ->
                IronwoodOutboxState.markNeedsUserActionNotificationPending(
                    snapshot,
                    batchId,
                )
            }
        }
    }

    private fun isAcceptedEquivalent(message: String): Boolean {
        val normalized = message.lowercase()
        return ACCEPTED_EQUIVALENT_MESSAGES.any(normalized::contains)
    }

    private fun result(
        outcome: IronwoodMigrationOutboxOutcome,
        proofReadyBatchId: String? = null,
    ) = IronwoodMigrationOutboxRunResult(
        outcome = outcome,
        proofReadyBatchId = proofReadyBatchId,
    )

    private companion object {
        const val OTHER_ENDPOINT_CHECK_DELAY_MS = 60_000L
        val ACCEPTED_EQUIVALENT_MESSAGES = listOf(
            "transaction was committed to the best chain",
            "already in mempool",
            "already have transaction",
            "transaction already in block chain",
            "transaction is already in state",
            "transaction already exists",
            "txn-already-known",
            "txn-already-in-mempool",
            "already known",
        )
    }
}

internal object IronwoodMigrationOutboxScheduler {
    const val UNIQUE_WORK_NAME = "ironwood-migration-outbox"
    const val WORK_TAG = "ironwood-migration-outbox"
    private const val RETRY_DELAY_MINUTES = 1L

    fun enqueue(context: Context, delayMs: Long = 0) {
        // A newly armed batch must supersede an older height-based wake-up;
        // otherwise KEEP can leave immediately due transactions behind a
        // continuation that was scheduled several minutes earlier. Waiting
        // for the execution coordinator ensures REPLACE cannot cancel a
        // transaction submission that is already in progress.
        IronwoodMigrationOutboxExecutionCoordinator.runExclusive {
            WorkManager.getInstance(context)
                .enqueueUniqueWork(
                    UNIQUE_WORK_NAME,
                    ExistingWorkPolicy.REPLACE,
                    request(delayMs),
                )
                .result
                .get()
        }
    }

    fun enqueueContinuation(context: Context, delayMs: Long) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            request(delayMs),
        )
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
    }

    internal fun request(delayMs: Long = 0): OneTimeWorkRequest =
        OneTimeWorkRequestBuilder<IronwoodMigrationOutboxWorker>()
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
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .addTag(WORK_TAG)
            .build()
}

class IronwoodMigrationOutboxWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
    override fun doWork(): Result = try {
        setForegroundAsync(createForegroundInfo()).get()
        val repository = IronwoodMigrationOutboxRepository(
            IronwoodMigrationSecureStore(applicationContext),
        )
        IronwoodMigrationOutboxExecutionCoordinator.runWhenAvailable { coordinatorCancelled ->
            val result = IronwoodMigrationOutboxRunner(
                repository = repository,
                transport = IronwoodMigrationOutboxNativeBridge(),
                isStopped = { isStopped },
            ).runOnce()
            processRunResult(
                repository = repository,
                result = result,
                cancelled = { isStopped || coordinatorCancelled() },
            )
        } ?: if (isStopped) Result.failure() else Result.retry()
    } catch (error: IllegalArgumentException) {
        Result.failure(workDataOf(OUTPUT_ERROR to (error.message ?: "Invalid outbox.")))
    } catch (error: IronwoodMigrationSecureStoreException) {
        Result.failure(
            workDataOf(
                OUTPUT_ERROR to
                    (error.message ?: "The migration outbox could not be opened."),
            ),
        )
    } catch (_: Exception) {
        if (isStopped) Result.failure() else Result.retry()
    }

    private fun processRunResult(
        repository: IronwoodMigrationOutboxRepository,
        result: IronwoodMigrationOutboxRunResult,
        cancelled: () -> Boolean,
    ): Result {
        if (cancelled() || result.outcome == IronwoodMigrationOutboxOutcome.CANCELLED) {
            return Result.failure()
        }
        val notificationDeliveries =
            mutableListOf<IronwoodMigrationNotificationDelivery>()
        if (!cancelled()) {
            result.proofReadyBatchId?.let { batchId ->
                notificationDeliveries +=
                    deliverProofReadyNotification(repository, batchId)
            }
            if (!cancelled()) {
                repository.read().let(
                    IronwoodOutboxState::pendingNeedsUserActionBatchId,
                )?.let { batchId ->
                    notificationDeliveries +=
                        deliverNeedsUserActionNotification(repository, batchId)
                }
            }
            if (!cancelled()) {
                repository.read().let(
                    IronwoodOutboxState::pendingBroadcastCompleteBatchId,
                )?.let { batchId ->
                    notificationDeliveries +=
                        deliverBroadcastCompleteNotification(repository, batchId)
                }
            }
        }
        if (cancelled()) return Result.failure()
        val currentSnapshot = repository.read()
        val hasRemainingDeliveryWork =
            IronwoodOutboxState.hasDeliveryWork(currentSnapshot)
        val hasPendingNotifications =
            IronwoodOutboxState.hasPendingNotifications(currentSnapshot)
        val notificationRetryRequired = notificationDeliveries.any {
            it == IronwoodMigrationNotificationDelivery.RETRY
        }
        val notificationsDisabled = notificationDeliveries.any {
            it == IronwoodMigrationNotificationDelivery.DISABLED
        }
        val continuationDelayMs = when {
            hasRemainingDeliveryWork &&
                result.outcome == IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION ->
                0L
            notificationRetryRequired ->
                NOTIFICATION_RETRY_DELAY_MS
            hasPendingNotifications && !notificationsDisabled -> 0L
            else -> result.delayMs
        }
        return when (result.outcome) {
            IronwoodMigrationOutboxOutcome.NO_WORK -> {
                continuationDelayMs?.let(::enqueueContinuation)
                Result.success()
            }
            IronwoodMigrationOutboxOutcome.WAITING,
            IronwoodMigrationOutboxOutcome.ACCEPTED,
            -> {
                continuationDelayMs?.let(::enqueueContinuation)
                Result.success()
            }
            IronwoodMigrationOutboxOutcome.NEEDS_USER_ACTION -> {
                continuationDelayMs?.let(::enqueueContinuation)
                if (continuationDelayMs == null) {
                    Result.failure(workDataOf(OUTPUT_ERROR to "needs_user_action"))
                } else {
                    Result.success(workDataOf(OUTPUT_ERROR to "needs_user_action"))
                }
            }
            IronwoodMigrationOutboxOutcome.RETRY -> Result.retry()
            IronwoodMigrationOutboxOutcome.CANCELLED -> Result.failure()
        }
    }

    private fun deliverProofReadyNotification(
        repository: IronwoodMigrationOutboxRepository,
        batchId: String,
    ): IronwoodMigrationNotificationDelivery {
        val delivery = IronwoodMigrationOutboxNotifier(applicationContext).notifyProofReady()
        if (delivery != IronwoodMigrationNotificationDelivery.DELIVERED) {
            return delivery
        }
        return runCatching {
            repository.update { snapshot ->
                IronwoodOutboxState.acknowledgeProofReadyNotification(snapshot, batchId)
            }
            IronwoodMigrationNotificationDelivery.DELIVERED
        }.getOrDefault(IronwoodMigrationNotificationDelivery.RETRY)
    }

    private fun deliverNeedsUserActionNotification(
        repository: IronwoodMigrationOutboxRepository,
        batchId: String,
    ): IronwoodMigrationNotificationDelivery {
        val delivery =
            IronwoodMigrationOutboxNotifier(applicationContext).notifyNeedsUserAction()
        if (delivery != IronwoodMigrationNotificationDelivery.DELIVERED) {
            return delivery
        }
        return runCatching {
            repository.update { snapshot ->
                IronwoodOutboxState.acknowledgeNeedsUserActionNotification(
                    snapshot,
                    batchId,
                )
            }
            IronwoodMigrationNotificationDelivery.DELIVERED
        }.getOrDefault(IronwoodMigrationNotificationDelivery.RETRY)
    }

    private fun deliverBroadcastCompleteNotification(
        repository: IronwoodMigrationOutboxRepository,
        batchId: String,
    ): IronwoodMigrationNotificationDelivery {
        val delivery =
            IronwoodMigrationOutboxNotifier(applicationContext).notifyBroadcastComplete()
        if (delivery != IronwoodMigrationNotificationDelivery.DELIVERED) {
            return delivery
        }
        return runCatching {
            repository.update { snapshot ->
                IronwoodOutboxState.acknowledgeBroadcastCompleteNotification(
                    snapshot,
                    batchId,
                )
            }
            IronwoodMigrationNotificationDelivery.DELIVERED
        }.getOrDefault(IronwoodMigrationNotificationDelivery.RETRY)
    }

    private fun enqueueContinuation(delayMs: Long) {
        IronwoodMigrationOutboxScheduler.enqueueContinuation(
            applicationContext,
            delayMs,
        )
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
            .setContentTitle("Completing wallet migration")
            .setContentText("Vizor is securely submitting a scheduled migration transaction.")
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
        const val NOTIFICATION_CHANNEL_ID = "ironwood_migration_outbox"
        const val NOTIFICATION_ID = 319
        const val OUTPUT_ERROR = "error"
        const val NOTIFICATION_RETRY_DELAY_MS = 10 * 60_000L
    }
}

internal class IronwoodMigrationOutboxNotifier(
    private val context: Context,
) {
    fun notifyProofReady(): IronwoodMigrationNotificationDelivery = notifyMigrationStatus(
        notificationId = PROOF_READY_NOTIFICATION_ID,
        title = "Wallet migration is ready to continue",
        body = "Open Vizor to continue securing your wallet.",
    )

    fun notifyNeedsUserAction(): IronwoodMigrationNotificationDelivery = notifyMigrationStatus(
        notificationId = NEEDS_USER_ACTION_NOTIFICATION_ID,
        title = "Ironwood migration needs attention",
        body = "Open Vizor to review and continue your migration.",
    )

    fun notifyBroadcastComplete(): IronwoodMigrationNotificationDelivery =
        notifyMigrationStatus(
            notificationId = BROADCAST_COMPLETE_NOTIFICATION_ID,
            title = "Migration transfers sent",
            body = "All scheduled transfers were submitted. Open Vizor to check the status.",
        )

    fun cancelAll() {
        NotificationManagerCompat.from(context).let { notifications ->
            notifications.cancel(PROOF_READY_NOTIFICATION_ID)
            notifications.cancel(NEEDS_USER_ACTION_NOTIFICATION_ID)
            notifications.cancel(BROADCAST_COMPLETE_NOTIFICATION_ID)
        }
    }

    private fun notifyMigrationStatus(
        notificationId: Int,
        title: String,
        body: String,
    ): IronwoodMigrationNotificationDelivery {
        val notifications = NotificationManagerCompat.from(context)
        if (!notifications.areNotificationsEnabled()) {
            return IronwoodMigrationNotificationDelivery.DISABLED
        }
        val manager = context.getSystemService(Service.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Wallet migration updates",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
            if (manager.getNotificationChannel(CHANNEL_ID).importance ==
                NotificationManager.IMPORTANCE_NONE
            ) {
                return IronwoodMigrationNotificationDelivery.DISABLED
            }
        }
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .build()
        return try {
            notifications.notify(notificationId, notification)
            IronwoodMigrationNotificationDelivery.DELIVERED
        } catch (_: SecurityException) {
            IronwoodMigrationNotificationDelivery.DISABLED
        } catch (_: RuntimeException) {
            IronwoodMigrationNotificationDelivery.RETRY
        }
    }

    private companion object {
        const val CHANNEL_ID = "ironwood_migration_updates"
        const val PROOF_READY_NOTIFICATION_ID = 320
        const val NEEDS_USER_ACTION_NOTIFICATION_ID = 321
        const val BROADCAST_COMPLETE_NOTIFICATION_ID = 322
    }
}
