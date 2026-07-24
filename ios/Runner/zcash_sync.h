#ifndef ZCASH_SYNC_H
#define ZCASH_SYNC_H

#include <stdint.h>
#include <stdbool.h>

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
    uint8_t state;
    uint32_t confirmation_count;
    uint32_t confirmation_target;
    uint32_t completed_stage_count;
    uint32_t total_stage_count;
} CMigrationPreparationProgress;

int32_t zcash_inspect_migration_preparation(
    const char* db_path,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    CMigrationPreparationProgress* output
);

int32_t zcash_run_full_sync_for_migration_preparation(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    SyncProgressCallback progress_callback
);

/// Begin/end one serial migration preparation operation. The operation owns
/// its cancellation token across both sync and advance calls.
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

/// Cancel only the active migration preparation operation.
bool zcash_cancel_migration_preparation_sync(void);

/// Check if a sync is currently running.
bool zcash_is_sync_running(void);

#endif // ZCASH_SYNC_H
