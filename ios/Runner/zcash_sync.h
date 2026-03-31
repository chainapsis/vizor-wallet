#ifndef ZCASH_SYNC_H
#define ZCASH_SYNC_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint64_t scanned_height;
    uint64_t chain_tip_height;
    double percentage;
    bool is_complete;
} CSyncProgress;

typedef void (*SyncProgressCallback)(CSyncProgress);

/// Run full sync. Blocks until complete or cancelled.
/// Returns 0 on success, 1 on error, 2 on panic.
int32_t zcash_run_full_sync(
    const char* db_path,
    const char* lightwalletd_url,
    const char* network,
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

#endif // ZCASH_SYNC_H
