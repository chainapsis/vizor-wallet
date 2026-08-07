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

/// Submits one signed transaction to lightwalletd.
///
/// On a Tor route the submission gets a circuit of its own, so no exit sees it
/// alongside this wallet's chain queries or alongside another submission. That
/// costs a circuit build on a route that is already bootstrapped and nothing on
/// the direct route, where this behaves exactly like the query calls above.
///
/// One call is one circuit, so a caller with several transactions to send pays
/// per transaction. That cost is the point and must not be optimised away by
/// putting several transactions behind one circuit, which hands an exit exactly
/// the linkage this buys.
///
/// Returns 0 with the server's SendResponse copied out — its error code into
/// `response_error_code`, its message into `response_error_message`, truncated
/// to capacity and always NUL-terminated. Returns 1 for a bad argument or a
/// transport failure, ZCASH_LIGHTWALLETD_RESULT_CANCELLED when the cancellation
/// fired, and 2 on a panic. Only 0 means lightwalletd answered; the answer may
/// still be a rejection, which lives in `response_error_code`.
int32_t zcash_lightwalletd_send_transaction(
    const char* lightwalletd_url,
    const uint8_t* raw_transaction,
    uintptr_t raw_transaction_len,
    int32_t* response_error_code,
    char* response_error_message,
    uintptr_t response_error_message_capacity,
    void* cancellation
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

/// Tor is up and the caller may do network work over it.
#define ZCASH_NETWORK_PRIVACY_TOR_READY 0
/// Tor is not up. The route stays Tor-desired and fail-closed, so the caller
/// must do no network work and must defer to the foreground.
#define ZCASH_NETWORK_PRIVACY_TOR_NOT_READY 1
/// The call panicked. Also not ready.
#define ZCASH_NETWORK_PRIVACY_TOR_PANICKED 2

/// Brings Tor up for a background pass and blocks until it is usable or has
/// failed, so that pass can do its network work on the user's chosen route
/// instead of waiting for the foreground.
///
/// Call this only once the pass has established that the device is on external
/// power and the link is unmetered. A cold bootstrap costs 8.45 MB down,
/// 744 KB up and 23.7 s and leaves a 46.3 MB cache behind; the client then pads
/// its guard connection continuously while awake, roughly 500 B/s against
/// 27 B/s dormant. A warm one costs 0.64 s and no bytes. Those are costs for a
/// charger and an unmetered link, not for a battery and a cellular one. A pass
/// that cannot show both conditions calls zcash_network_privacy_mark_tor_desired
/// instead and defers.
///
/// The bootstrap carries its own deadline, far shorter than the foreground's,
/// because a background execution window can be withdrawn at any moment and the
/// bootstrap exists so that work can follow it. This call blocks for up to that
/// deadline, so run it off the main thread.
///
/// `tor_directory` is the Tor data directory and is created if it is missing.
/// It is Application Support + "/tor", matching what the foreground passes.
///
/// There is no matching call to end a pass. Keeping the client awake for the
/// work that follows is a time-bounded hold that lapses on its own, and it
/// masks the app lifecycle's dormancy setting rather than replacing it, so a
/// foreground entry during a pass still wins and no exit — including one taken
/// before any network work, and including the process being suspended — can
/// leave the client awake by failing to say something.
///
/// Returns ZCASH_NETWORK_PRIVACY_TOR_READY when Tor is up;
/// ZCASH_NETWORK_PRIVACY_TOR_NOT_READY for every other outcome — a bad argument,
/// a bootstrap failure, the deadline expiring, or a process that had already
/// chosen the direct route — in which case the caller must do no network work
/// and must defer to the foreground; and ZCASH_NETWORK_PRIVACY_TOR_PANICKED on a
/// panic, which is likewise not ready. Every non-ready outcome leaves the route
/// Tor-desired and fail-closed, never direct, so a caller that ignores the
/// answer is blocked rather than leaked onto clearnet.
int32_t zcash_network_privacy_enable_tor_for_background_work(
    const char* tor_directory
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

#endif // ZCASH_SYNC_H
