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
    uint64_t scanned_height;
    uint64_t chain_tip_height;
    double percentage;
    double display_target_percentage;
    uint64_t display_target_blocks;
    bool is_syncing;
    bool is_complete;
    bool has_new_tx;
} CSyncProgress;

typedef void (*SyncProgressCallback)(CSyncProgress);

typedef struct {
    /// 0 not found, 1 mempool, 2 mined, 3 forked.
    uint8_t state;
    uint64_t mined_height;
} CLightwalletdTransactionObservation;

int32_t zcash_lightwalletd_latest_block_height(
    const char* lightwalletd_url,
    uint64_t* output
);

int32_t zcash_lightwalletd_observe_transaction(
    const char* lightwalletd_url,
    const uint8_t* transaction_id,
    uintptr_t transaction_id_len,
    CLightwalletdTransactionObservation* output
);

int32_t zcash_lightwalletd_send_transaction(
    const char* lightwalletd_url,
    const uint8_t* raw_transaction,
    uintptr_t raw_transaction_len,
    int32_t* response_error_code,
    char* response_error_message,
    uintptr_t response_error_message_capacity
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

int32_t zcash_inspect_migration_proof_readiness(
    const char* db_path,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    bool* output
);

int32_t zcash_run_full_sync_for_migration_preparation(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    SyncProgressCallback progress_callback
);

bool zcash_begin_migration_preparation_operation(void);
void zcash_end_migration_preparation_operation(void);

int32_t zcash_advance_migration_preparation(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    const uint8_t* credential,
    uintptr_t credential_len,
    const char* salt_base64,
    CMigrationPreparationProgress* output
);

bool zcash_cancel_migration_preparation_sync(void);
bool zcash_is_sync_running(void);

#endif // ZCASH_SYNC_H
