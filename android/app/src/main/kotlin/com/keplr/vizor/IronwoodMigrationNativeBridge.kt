package com.keplr.vizor

import androidx.annotation.Keep

internal enum class IronwoodMigrationNativePreparationState(val nativeValue: Long) {
    WAITING_FOR_DENOMINATION_PREPARATION(0),
    PROOF_READY(1),
    NEEDS_USER_ACTION(2),
    CANCELLED(3),
    INACTIVE(4),
    WAITING_FOR_PREPARED_NOTE_ANCHOR(5);

    companion object {
        fun fromNative(value: Long): IronwoodMigrationNativePreparationState =
            entries.firstOrNull { it.nativeValue == value }
                ?: throw IronwoodMigrationNativeException(
                    IronwoodMigrationNativeError.INVALID_RESPONSE,
                    "Unknown migration preparation state: $value",
                )
    }
}

internal data class IronwoodMigrationNativePreparationProgress(
    val state: IronwoodMigrationNativePreparationState,
    val confirmationCount: Long,
    val confirmationTarget: Long,
    val completedStageCount: Long,
    val totalStageCount: Long,
)

internal data class IronwoodMigrationNativeSyncProgress(
    val scannedHeight: Long,
    val chainTipHeight: Long,
    val percentage: Double,
    val displayTargetPercentage: Double,
    val displayTargetBlocks: Long,
    val isSyncing: Boolean,
    val isComplete: Boolean,
    val hasNewTx: Boolean,
)

internal enum class IronwoodMigrationNativeError(val nativeCode: Int) {
    NO_ACTIVE_OPERATION(1),
    SYNC_ALREADY_RUNNING(2),
    INVALID_CREDENTIAL(3),
    EXECUTION(4),
    CALLBACK(5),
    PANIC(6),
    INVALID_ARGUMENT(7),
    INVALID_RESPONSE(-1);

    companion object {
        fun fromNative(value: Int): IronwoodMigrationNativeError =
            entries.firstOrNull { it.nativeCode == value } ?: INVALID_RESPONSE
    }
}

internal class IronwoodMigrationNativeException(
    val reason: IronwoodMigrationNativeError,
    message: String,
) : Exception(message)

/**
 * JNI result envelope. The field layout is part of the Rust/Kotlin JNI ABI.
 */
@Keep
internal class IronwoodMigrationNativeCallResult(
    @JvmField val code: Int,
    @JvmField val message: String?,
    @JvmField val progress: LongArray?,
)

@Keep
internal fun interface IronwoodMigrationNativeSyncCallback {
    @Suppress("LongParameterList")
    fun onProgress(
        scannedHeight: Long,
        chainTipHeight: Long,
        percentage: Double,
        displayTargetPercentage: Double,
        displayTargetBlocks: Long,
        isSyncing: Boolean,
        isComplete: Boolean,
        hasNewTx: Boolean,
    )
}

internal interface IronwoodMigrationNativeBindings {
    fun nativeBeginOperation(): Boolean
    fun nativeEndOperation()
    fun nativeCancelOperation(): Boolean
    fun nativeIsSyncRunning(): Boolean

    fun nativeInspect(
        dbPath: String,
        network: String,
        accountUuid: String,
        expectedRunId: String,
    ): IronwoodMigrationNativeCallResult

    @Suppress("LongParameterList")
    fun nativeAdvance(
        dbPath: String,
        lightwalletdUrl: String,
        network: String,
        accountUuid: String,
        expectedRunId: String,
        credential: ByteArray,
        saltBase64: String,
    ): IronwoodMigrationNativeCallResult

    fun nativeRunSync(
        dbPath: String,
        lightwalletdUrl: String,
        network: String,
        callback: IronwoodMigrationNativeSyncCallback,
    ): IronwoodMigrationNativeCallResult
}

@Keep
internal object IronwoodMigrationJniBindings : IronwoodMigrationNativeBindings {
    init {
        System.loadLibrary("rust_lib_zcash_wallet")
    }

    external override fun nativeBeginOperation(): Boolean
    external override fun nativeEndOperation()
    external override fun nativeCancelOperation(): Boolean
    external override fun nativeIsSyncRunning(): Boolean

    external override fun nativeInspect(
        dbPath: String,
        network: String,
        accountUuid: String,
        expectedRunId: String,
    ): IronwoodMigrationNativeCallResult

    @Suppress("LongParameterList")
    external override fun nativeAdvance(
        dbPath: String,
        lightwalletdUrl: String,
        network: String,
        accountUuid: String,
        expectedRunId: String,
        credential: ByteArray,
        saltBase64: String,
    ): IronwoodMigrationNativeCallResult

    external override fun nativeRunSync(
        dbPath: String,
        lightwalletdUrl: String,
        network: String,
        callback: IronwoodMigrationNativeSyncCallback,
    ): IronwoodMigrationNativeCallResult
}

internal class IronwoodMigrationNativeBridge(
    private val bindings: IronwoodMigrationNativeBindings = IronwoodMigrationJniBindings,
) {
    fun beginOperation(): Boolean = bindings.nativeBeginOperation()

    fun endOperation() {
        bindings.nativeEndOperation()
    }

    fun cancelOperation(): Boolean = bindings.nativeCancelOperation()

    fun isSyncRunning(): Boolean = bindings.nativeIsSyncRunning()

    fun inspect(
        dbPath: String,
        network: String,
        accountUuid: String,
        expectedRunId: String,
    ): IronwoodMigrationNativePreparationProgress =
        decodeProgress(
            bindings.nativeInspect(dbPath, network, accountUuid, expectedRunId),
            "inspect",
        )

    @Suppress("LongParameterList")
    fun advance(
        dbPath: String,
        lightwalletdUrl: String,
        network: String,
        accountUuid: String,
        expectedRunId: String,
        credential: ByteArray,
        saltBase64: String,
    ): IronwoodMigrationNativePreparationProgress =
        decodeProgress(
            bindings.nativeAdvance(
                dbPath,
                lightwalletdUrl,
                network,
                accountUuid,
                expectedRunId,
                credential,
                saltBase64,
            ),
            "advance",
        )

    fun runSync(
        dbPath: String,
        lightwalletdUrl: String,
        network: String,
        onProgress: (IronwoodMigrationNativeSyncProgress) -> Unit,
    ) {
        val result = bindings.nativeRunSync(
            dbPath,
            lightwalletdUrl,
            network,
            IronwoodMigrationNativeSyncCallback {
                    scannedHeight,
                    chainTipHeight,
                    percentage,
                    displayTargetPercentage,
                    displayTargetBlocks,
                    isSyncing,
                    isComplete,
                    hasNewTx,
                ->
                onProgress(
                    IronwoodMigrationNativeSyncProgress(
                        scannedHeight = requireNonNegative(
                            scannedHeight,
                            "scannedHeight",
                        ),
                        chainTipHeight = requireNonNegative(
                            chainTipHeight,
                            "chainTipHeight",
                        ),
                        percentage = percentage,
                        displayTargetPercentage = displayTargetPercentage,
                        displayTargetBlocks = requireNonNegative(
                            displayTargetBlocks,
                            "displayTargetBlocks",
                        ),
                        isSyncing = isSyncing,
                        isComplete = isComplete,
                        hasNewTx = hasNewTx,
                    ),
                )
            },
        )
        requireSuccess(result, "sync")
        if (result.progress != null) {
            throw invalidResponse("sync returned unexpected preparation progress")
        }
    }

    private fun decodeProgress(
        result: IronwoodMigrationNativeCallResult,
        operation: String,
    ): IronwoodMigrationNativePreparationProgress {
        requireSuccess(result, operation)
        val values = result.progress
            ?: throw invalidResponse("$operation returned no preparation progress")
        if (values.size != PROGRESS_FIELD_COUNT) {
            throw invalidResponse(
                "$operation returned ${values.size} preparation progress fields",
            )
        }
        return IronwoodMigrationNativePreparationProgress(
            state = IronwoodMigrationNativePreparationState.fromNative(values[0]),
            confirmationCount = requireNonNegative(values[1], "confirmationCount"),
            confirmationTarget = requireNonNegative(values[2], "confirmationTarget"),
            completedStageCount = requireNonNegative(values[3], "completedStageCount"),
            totalStageCount = requireNonNegative(values[4], "totalStageCount"),
        )
    }

    private fun requireSuccess(
        result: IronwoodMigrationNativeCallResult,
        operation: String,
    ) {
        if (result.code == RESULT_SUCCESS) return
        val reason = IronwoodMigrationNativeError.fromNative(result.code)
        throw IronwoodMigrationNativeException(
            reason,
            result.message ?: "$operation failed with native code ${result.code}",
        )
    }

    private fun requireNonNegative(value: Long, name: String): Long {
        if (value < 0) {
            throw invalidResponse("$name is negative")
        }
        return value
    }

    private fun invalidResponse(message: String) = IronwoodMigrationNativeException(
        IronwoodMigrationNativeError.INVALID_RESPONSE,
        message,
    )

    private companion object {
        const val RESULT_SUCCESS = 0
        const val PROGRESS_FIELD_COUNT = 5
    }
}
