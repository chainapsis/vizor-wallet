#ifndef ZCASH_SYNC_H
#define ZCASH_SYNC_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint8_t state;
    uint32_t confirmation_count;
    uint32_t confirmation_target;
    uint32_t completed_stage_count;
    uint32_t total_stage_count;
} CMigrationPreparationProgress;

typedef struct {
    /// 0 not found, 1 mempool, 2 mined, 3 forked.
    uint8_t state;
    uint64_t mined_height;
} CLightwalletdTransactionObservation;

#define ZCASH_LIGHTWALLETD_RESULT_CANCELLED 3

void* zcash_lightwalletd_cancellation_create(void);
void zcash_lightwalletd_cancellation_cancel(void* cancellation);
void zcash_lightwalletd_cancellation_destroy(void* cancellation);

int32_t zcash_lightwalletd_latest_block_height(
    const char* lightwalletd_url,
    uint64_t* output,
    void* cancellation
);

/// Public lookups are authorized against the wallet at db_path under the
/// private queries preference. Returns ZCASH_STATUS_RESULT_INCONCLUSIVE when
/// the wallet cannot be read, and ZCASH_STATUS_RESULT_UNSUPPORTED when the
/// preference or the wallet's policy withholds the lookup. Both send nothing
/// and leave output untouched.
int32_t zcash_lightwalletd_observe_transaction(
    const char* lightwalletd_url,
    const char* db_path,
    const char* network,
    bool private_preference,
    const uint8_t* transaction_id,
    uintptr_t transaction_id_len,
    CLightwalletdTransactionObservation* output,
    void* cancellation
);

#define ZCASH_STATUS_RESULT_UNSUPPORTED 5
#define ZCASH_STATUS_RESULT_INCONCLUSIVE 4


int32_t zcash_lightwalletd_send_transaction(
    const char* lightwalletd_url,
    const uint8_t* raw_transaction,
    uintptr_t raw_transaction_len,
    int32_t* response_error_code,
    char* response_error_message,
    uintptr_t response_error_message_capacity,
    void* cancellation
);

int32_t zcash_inspect_migration_preparation(
    const char* db_path,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    CMigrationPreparationProgress* output
);

/// Copies newline-delimited observable denomination transaction IDs.
/// Call once with output=NULL to obtain the required length including NUL.
int32_t zcash_list_migration_preparation_txids(
    const char* db_path,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    char* output,
    uintptr_t output_capacity,
    uintptr_t* output_len
);

/// NU7 activation height for network ("main", "test", "regtest"), or 0 when
/// it is unscheduled or the network is unknown.
uint64_t zcash_nu7_activation_height(const char* network);

/// Whether the iOS outbox holds a migration part signed for target_height at
/// remote_height on network, as the foreground judges it. A target of 0 (a
/// part saved by an older build) is held by the tip alone.
bool zcash_migration_broadcast_held(const char* network, uint64_t target_height,
                                    uint64_t remote_height);

/// ZIP 318 canonical expiry for a part scheduled at height, or 0.
uint64_t zcash_zip318_canonical_expiry_height(const char* network, uint64_t height);

/// Blocks per ZIP 318 reference block at height: 1 before NU7, 3 from it.
uint64_t zcash_zip318_blocks_per_reference_block(const char* network, uint64_t height);

int32_t zcash_inspect_migration_proof_readiness(
    const char* db_path,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    bool* output
);

#endif // ZCASH_SYNC_H
