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
    const uint8_t* routing_transaction_id,
    uintptr_t routing_transaction_id_len,
    const uint8_t* transaction_id,
    uintptr_t transaction_id_len,
    CLightwalletdTransactionObservation* output,
    bool managed_submission_routing,
    void* cancellation
);

int32_t zcash_lightwalletd_send_transaction(
    const char* lightwalletd_url,
    const uint8_t* transaction_id,
    uintptr_t transaction_id_len,
    const uint8_t* raw_transaction,
    uintptr_t raw_transaction_len,
    int32_t* response_error_code,
    char* response_error_message,
    uintptr_t response_error_message_capacity,
    bool* response_accepted,
    bool managed_submission_routing,
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

#endif // ZCASH_SYNC_H
