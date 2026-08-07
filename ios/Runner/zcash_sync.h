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

int32_t zcash_lightwalletd_observe_transaction(
    const char* lightwalletd_url,
    const uint8_t* transaction_id,
    uintptr_t transaction_id_len,
    CLightwalletdTransactionObservation* output,
    void* cancellation
);

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

int32_t zcash_inspect_migration_proof_readiness(
    const char* db_path,
    const char* network,
    const char* account_uuid,
    const char* expected_run_id,
    bool* output
);

/// Declares that the user's persisted network route is Tor, so this process
/// refuses to reach the network directly.
///
/// The desired route lives in process memory and defaults to direct, so a
/// background launch in which Dart never ran would otherwise send lightwalletd
/// traffic over clearnet. The caller must have read the persisted preference
/// itself and must call this before the first network call of the pass. It
/// never bootstraps Tor, so a pass that only calls this can do no network work
/// and defers to the foreground. The process then stays fail-closed for the
/// rest of its lifetime; only the foreground route toggle returns it to direct.
/// Returns 0 on success.
int32_t zcash_network_privacy_mark_tor_desired(void);

/// Declares that the user's persisted network route is direct — the mirror of
/// zcash_network_privacy_mark_tor_desired, and just as mandatory.
///
/// "Nobody has declared yet" and "the user chose direct" are deliberately
/// different states in Rust. The first is refused wherever a route is resolved,
/// so a background entry point that never read the preference cannot reach
/// lightwalletd at all instead of quietly reaching it over clearnet on a
/// Tor-configured wallet. A pass whose saved route is direct therefore declares
/// it, exactly as a Tor pass does, or its own network calls fail closed.
///
/// Writes nothing but the decision, touches no filesystem, never bootstraps,
/// and is ignored once this process has decided its own route, so it can never
/// turn a live Tor route direct. Returns 0 on success.
int32_t zcash_network_privacy_mark_direct_route(void);

#endif // ZCASH_SYNC_H
