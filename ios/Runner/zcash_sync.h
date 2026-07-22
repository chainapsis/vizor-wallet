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

/// Run full sync. Blocks until complete or cancelled.
/// Returns 0 on success, 1 on error, 2 on panic.
int32_t zcash_run_full_sync(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    SyncProgressCallback progress_callback
);

int32_t zcash_run_full_sync_for_migration_preparation(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    SyncProgressCallback progress_callback
);

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

/// Cancel a running sync.
void zcash_cancel_sync(void);

/// Cancel only if migration preparation owns the running sync.
bool zcash_cancel_migration_preparation_sync(void);

/// Get the current desired sync mode (0=none, 1=foreground, 2=background).
uint8_t zcash_get_sync_mode(void);

/// Set the desired sync mode (0=none, 1=foreground, 2=background).
void zcash_set_sync_mode(uint8_t mode);

/// Check if a sync is currently running.
bool zcash_is_sync_running(void);

#endif // ZCASH_SYNC_H
