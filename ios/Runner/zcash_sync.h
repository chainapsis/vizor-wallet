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
    uint8_t action;
    bool cancelled;
    uint64_t scanned_height;
    uint64_t chain_tip_height;
    uint64_t next_scheduled_height;
    uint32_t broadcasted_count;
} CBackgroundMigrationResult;

/// Run full sync. Blocks until complete or cancelled.
/// Returns 0 on success, 1 on error, 2 on panic.
int32_t zcash_run_full_sync(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    SyncProgressCallback progress_callback
);

/// Acquire sync ownership and run with background mode for one migration wake.
/// Returns 5 when the wake was cancelled before sync started.
int32_t zcash_run_full_sync_for_migration(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    uint64_t expected_cancel_epoch,
    SyncProgressCallback progress_callback
);

/// Cancel a running sync.
void zcash_cancel_sync(void);

/// Get the current desired sync mode (0=none, 1=foreground, 2=background).
uint8_t zcash_get_sync_mode(void);

/// Set the desired sync mode (0=none, 1=foreground, 2=background).
void zcash_set_sync_mode(uint8_t mode);

/// Check if a sync is currently running.
bool zcash_is_sync_running(void);

/// Inspect an authorized Ironwood migration without syncing or broadcasting.
int32_t zcash_inspect_background_migration(
    const char* db_path,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    CBackgroundMigrationResult* output
);

/// Advance one bounded step of an already-authorized Ironwood migration.
/// Returns 0 on success, 1 on validation/execution error, 2 on panic, and 3
/// when another migration cycle is already running.
int32_t zcash_run_background_migration_cycle(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    const uint8_t* credential,
    uintptr_t credential_len,
    const char* salt_base64,
    uint64_t expected_cancel_epoch,
    CBackgroundMigrationResult* output
);

void zcash_cancel_background_migration(void);
uint64_t zcash_background_migration_cancellation_epoch(void);
bool zcash_is_background_migration_running(void);

#endif // ZCASH_SYNC_H
