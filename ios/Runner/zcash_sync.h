#ifndef ZCASH_SYNC_H
#define ZCASH_SYNC_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint64_t scanned_height;
    uint64_t chain_tip_height;
    double percentage;
    bool is_syncing;
    bool is_complete;
    bool has_new_tx;
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

// ======================== TX Tracking ========================

typedef struct {
    uint8_t txid_hex[65]; // 64 hex chars + null
    uint64_t expiry_height;
} CPendingTx;

/// Get number of pending (unmined, unexpired) transactions. Returns -1 on error.
int32_t zcash_get_pending_tx_count(const char* db_path);

/// Fill buffer with pending transactions. Returns count written, -1 on error.
int32_t zcash_get_pending_txs(const char* db_path, CPendingTx* out_buf, int32_t buf_len);

/// Check if a TX has been mined via lightwalletd gRPC.
/// Returns: >0 = mined height, 0 = pending, -1 = error.
int64_t zcash_check_tx_status(const char* lightwalletd_url, const char* txid_hex);

#endif // ZCASH_SYNC_H
