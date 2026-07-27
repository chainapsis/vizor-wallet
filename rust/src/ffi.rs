//! C adapter for iOS Ironwood migration background work.
//!
//! The platform-neutral state mapping lives in `crate::migration_preparation`;
//! this module validates C inputs and converts native values. Confirmation
//! polling stays read-only; sync and denomination advancement remain owned by
//! the foreground FRB path.

use std::ffi::CStr;
use std::os::raw::c_char;

use crate::migration_preparation::{self, MigrationPreparationProgress};
use crate::wallet::keys;
use tonic::Code;

#[repr(C)]
pub struct CMigrationPreparationProgress {
    /// 0 waiting for denomination preparation, 1 proof can be created,
    /// 2 needs user action, 3 cancelled, 4 no matching active preparation,
    /// 5 waiting for the prepared-note anchor to become usable.
    pub state: u8,
    pub confirmation_count: u32,
    pub confirmation_target: u32,
    pub completed_stage_count: u32,
    pub total_stage_count: u32,
}

impl From<MigrationPreparationProgress> for CMigrationPreparationProgress {
    fn from(progress: MigrationPreparationProgress) -> Self {
        Self {
            state: progress.state as u8,
            confirmation_count: progress.confirmation_count,
            confirmation_target: progress.confirmation_target,
            completed_stage_count: progress.completed_stage_count,
            total_stage_count: progress.total_stage_count,
        }
    }
}

/// Read-only lightwalletd transaction state returned to Swift.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(C)]
pub struct CLightwalletdTransactionObservation {
    /// 0 not found, 1 mempool, 2 mined, 3 forked.
    pub state: u8,
    pub mined_height: u64,
}

impl CLightwalletdTransactionObservation {
    fn not_found() -> Self {
        Self {
            state: 0,
            mined_height: 0,
        }
    }
}

fn transaction_observation_from_height(height: u64) -> CLightwalletdTransactionObservation {
    match height {
        0 => CLightwalletdTransactionObservation {
            state: 1,
            mined_height: 0,
        },
        u64::MAX => CLightwalletdTransactionObservation {
            state: 3,
            mined_height: 0,
        },
        mined_height => CLightwalletdTransactionObservation {
            state: 2,
            mined_height,
        },
    }
}

/// Safely convert a C string pointer to a `&str`. Returns `None` if
/// the pointer is null, not valid UTF-8, or empty.
unsafe fn c_str_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    match CStr::from_ptr(ptr).to_str() {
        Ok(value) if !value.is_empty() => Some(value),
        _ => None,
    }
}

fn log_panic(context: &str, panic: Box<dyn std::any::Any + Send>) {
    let message = if let Some(message) = panic.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = panic.downcast_ref::<String>() {
        message.clone()
    } else {
        "Unknown".to_string()
    };
    log::error!("ffi: panic during {context}: {message}");
}

fn lightwalletd_runtime() -> Result<tokio::runtime::Runtime, String> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| format!("Create lightwalletd runtime: {error}"))
}

/// Fetch the lightwalletd chain tip through tonic. Unlike URLSession, this
/// supports both production HTTPS and plaintext HTTP/2 (h2c) regtest servers.
#[no_mangle]
pub extern "C" fn zcash_lightwalletd_latest_block_height(
    lightwalletd_url: *const c_char,
    output: *mut u64,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
            return 1;
        };
        let Some(output) = (unsafe { output.as_mut() }) else {
            return 1;
        };
        let runtime = match lightwalletd_runtime() {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: {error}");
                return 1;
            }
        };
        match runtime.block_on(async {
            let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await?;
            crate::wallet::sync_engine::get_latest_block(&mut client).await
        }) {
            Ok(block) => {
                *output = block.height;
                0
            }
            Err(error) => {
                log::error!("ffi: get lightwalletd latest block: {error}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("lightwalletd latest block", panic);
            2
        }
    }
}

/// Observe one transaction through tonic while preserving lightwalletd's
/// NotFound status and height sentinels.
#[no_mangle]
pub extern "C" fn zcash_lightwalletd_observe_transaction(
    lightwalletd_url: *const c_char,
    transaction_id: *const u8,
    transaction_id_len: usize,
    output: *mut CLightwalletdTransactionObservation,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
            return 1;
        };
        if transaction_id.is_null() || transaction_id_len != 32 {
            return 1;
        }
        let Some(output) = (unsafe { output.as_mut() }) else {
            return 1;
        };
        let transaction_id =
            unsafe { std::slice::from_raw_parts(transaction_id, transaction_id_len) }.to_vec();
        let runtime = match lightwalletd_runtime() {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: {error}");
                return 1;
            }
        };
        match runtime.block_on(async {
            let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
                .await
                .map_err(|error| tonic::Status::unavailable(error.to_string()))?;
            crate::wallet::sync_engine::get_transaction(&mut client, transaction_id).await
        }) {
            Ok(transaction) => {
                *output = transaction_observation_from_height(transaction.height);
                0
            }
            Err(error) if error.code() == Code::NotFound => {
                *output = CLightwalletdTransactionObservation::not_found();
                0
            }
            Err(error) => {
                log::error!("ffi: observe lightwalletd transaction: {error}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("lightwalletd transaction observation", panic);
            2
        }
    }
}

/// Submit one transaction through tonic. The error message is copied into the
/// caller-owned buffer and safely truncated if necessary.
#[no_mangle]
pub extern "C" fn zcash_lightwalletd_send_transaction(
    lightwalletd_url: *const c_char,
    raw_transaction: *const u8,
    raw_transaction_len: usize,
    response_error_code: *mut i32,
    response_error_message: *mut c_char,
    response_error_message_capacity: usize,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
            return 1;
        };
        if raw_transaction.is_null() || raw_transaction_len == 0 {
            return 1;
        }
        let Some(response_error_code) = (unsafe { response_error_code.as_mut() }) else {
            return 1;
        };
        if response_error_message.is_null() || response_error_message_capacity == 0 {
            return 1;
        }
        let raw_transaction =
            unsafe { std::slice::from_raw_parts(raw_transaction, raw_transaction_len) }.to_vec();
        let runtime = match lightwalletd_runtime() {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: {error}");
                return 1;
            }
        };
        match runtime.block_on(async {
            let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
                .await
                .map_err(|error| error.to_string())?;
            crate::wallet::sync_engine::send_transaction_with_status(&mut client, &raw_transaction)
                .await
                .map_err(|error| error.to_string())
        }) {
            Ok(response) => {
                *response_error_code = response.error_code;
                let bytes = response.error_message.as_bytes();
                let copied_len = bytes
                    .len()
                    .min(response_error_message_capacity.saturating_sub(1));
                unsafe {
                    std::ptr::copy_nonoverlapping(
                        bytes.as_ptr().cast::<c_char>(),
                        response_error_message,
                        copied_len,
                    );
                    *response_error_message.add(copied_len) = 0;
                }
                0
            }
            Err(error) => {
                log::error!("ffi: send lightwalletd transaction: {error}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("lightwalletd transaction submission", panic);
            2
        }
    }
}

/// Inspect local migration preparation state without syncing or loading a
/// signing credential. This lets iOS avoid presenting unrelated wallet sync as
/// migration preparation after the run has already advanced.
#[no_mangle]
pub extern "C" fn zcash_inspect_migration_preparation(
    db_path: *const c_char,
    network: *const c_char,
    account_uuid: *const c_char,
    expected_run_id: *const c_char,
    output: *mut CMigrationPreparationProgress,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        let Some(network_str) = (unsafe { c_str_to_str(network) }) else {
            return 1;
        };
        let Some(account_uuid) = (unsafe { c_str_to_str(account_uuid) }) else {
            return 1;
        };
        let Some(expected_run_id) = (unsafe { c_str_to_str(expected_run_id) }) else {
            return 1;
        };
        let Some(output) = (unsafe { output.as_mut() }) else {
            return 1;
        };
        let network = match keys::parse_network(network_str) {
            Ok(network) => network,
            Err(error) => {
                log::error!("ffi: parse migration preparation network: {error}");
                return 1;
            }
        };

        match migration_preparation::inspect(db_path, network, account_uuid, expected_run_id) {
            Ok(progress) => {
                *output = progress.into();
                0
            }
            Err(error) => {
                log::error!("ffi: inspect migration preparation: {error}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("migration preparation inspection", panic);
            2
        }
    }
}

/// Copies newline-delimited observable denomination txids into a caller-owned
/// buffer. Call with a null output first to obtain the required byte length,
/// including the trailing NUL.
#[no_mangle]
pub extern "C" fn zcash_list_migration_preparation_txids(
    db_path: *const c_char,
    network: *const c_char,
    account_uuid: *const c_char,
    expected_run_id: *const c_char,
    output: *mut c_char,
    output_capacity: usize,
    output_len: *mut usize,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        let Some(network_str) = (unsafe { c_str_to_str(network) }) else {
            return 1;
        };
        let Some(account_uuid) = (unsafe { c_str_to_str(account_uuid) }) else {
            return 1;
        };
        let Some(expected_run_id) = (unsafe { c_str_to_str(expected_run_id) }) else {
            return 1;
        };
        let Some(output_len) = (unsafe { output_len.as_mut() }) else {
            return 1;
        };
        let network = match keys::parse_network(network_str) {
            Ok(network) => network,
            Err(error) => {
                log::error!("ffi: parse migration preparation network: {error}");
                return 1;
            }
        };
        let txids = match migration_preparation::observable_transaction_ids(
            db_path,
            network,
            account_uuid,
            expected_run_id,
        ) {
            Ok(txids) => txids,
            Err(error) => {
                log::error!("ffi: list migration preparation txids: {error}");
                return 1;
            }
        };
        let payload = txids.join("\n");
        let required_len = payload.len().saturating_add(1);
        *output_len = required_len;
        if output.is_null() {
            return 0;
        }
        if output_capacity < required_len {
            return 3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(payload.as_ptr().cast::<c_char>(), output, payload.len());
            *output.add(payload.len()) = 0;
        }
        0
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("migration preparation txid listing", panic);
            2
        }
    }
}

#[no_mangle]
pub extern "C" fn zcash_inspect_migration_proof_readiness(
    db_path: *const c_char,
    network: *const c_char,
    account_uuid: *const c_char,
    expected_run_id: *const c_char,
    output: *mut bool,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        let Some(network_str) = (unsafe { c_str_to_str(network) }) else {
            return 1;
        };
        let Some(account_uuid) = (unsafe { c_str_to_str(account_uuid) }) else {
            return 1;
        };
        let Some(expected_run_id) = (unsafe { c_str_to_str(expected_run_id) }) else {
            return 1;
        };
        let Some(output) = (unsafe { output.as_mut() }) else {
            return 1;
        };
        let network = match keys::parse_network(network_str) {
            Ok(network) => network,
            Err(error) => {
                log::error!("ffi: parse migration proof-readiness network: {error}");
                return 1;
            }
        };

        match migration_preparation::inspect_proof_readiness(
            db_path,
            network,
            account_uuid,
            expected_run_id,
        ) {
            Ok(ready) => {
                *output = ready;
                0
            }
            Err(error) => {
                log::error!("ffi: inspect migration proof readiness: {error}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("migration proof readiness inspection", panic);
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transaction_observation_maps_lightwalletd_height_sentinels() {
        assert_eq!(
            transaction_observation_from_height(0),
            CLightwalletdTransactionObservation {
                state: 1,
                mined_height: 0,
            }
        );
        assert_eq!(
            transaction_observation_from_height(u64::MAX),
            CLightwalletdTransactionObservation {
                state: 3,
                mined_height: 0,
            }
        );
        assert_eq!(
            transaction_observation_from_height(501),
            CLightwalletdTransactionObservation {
                state: 2,
                mined_height: 501,
            }
        );
    }

    #[test]
    fn transaction_observation_represents_not_found_separately() {
        assert_eq!(
            CLightwalletdTransactionObservation::not_found(),
            CLightwalletdTransactionObservation {
                state: 0,
                mined_height: 0,
            }
        );
    }
}
