//! C adapter for iOS Ironwood migration background work.
//!
//! The platform-neutral execution and state machine live in
//! `crate::migration_preparation`; this module only validates C inputs,
//! converts native values, and preserves the existing iOS ABI.

use std::ffi::CStr;
use std::os::raw::c_char;

use crate::migration_preparation::{self, MigrationPreparationError, MigrationPreparationProgress};
use crate::wallet::keys;

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

/// Progress data passed to the C callback.
#[repr(C)]
pub struct CSyncProgress {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub display_target_percentage: f64,
    pub display_target_blocks: u64,
    pub is_syncing: bool,
    pub is_complete: bool,
    pub has_new_tx: bool,
}

/// C callback type for progress updates.
pub type SyncProgressCallback = extern "C" fn(CSyncProgress);

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

unsafe fn credential_bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if ptr.is_null() || len == 0 {
        return None;
    }
    Some(std::slice::from_raw_parts(ptr, len))
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

/// Run one sync pass for an active migration preparation task. Pending wallet
/// transactions are not resubmitted here; denomination advancement owns the
/// preparation broadcasts explicitly.
#[no_mangle]
pub extern "C" fn zcash_run_full_sync_for_migration_preparation(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    progress_callback: SyncProgressCallback,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            log::error!("ffi: invalid or null db_path");
            return 1;
        };
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
            log::error!("ffi: invalid or null lightwalletd_url");
            return 1;
        };
        let Some(network_str) = (unsafe { c_str_to_str(network) }) else {
            log::error!("ffi: invalid or null network string");
            return 1;
        };
        let network = match keys::parse_network(network_str) {
            Ok(network) => network,
            Err(error) => {
                log::error!("ffi: parse migration preparation network: {error}");
                return 1;
            }
        };

        match migration_preparation::run_sync(db_path, lightwalletd_url, network, |progress| {
            progress_callback(CSyncProgress {
                scanned_height: progress.scanned_height,
                chain_tip_height: progress.chain_tip_height,
                percentage: progress.percentage,
                display_target_percentage: progress.display_target_percentage,
                display_target_blocks: progress.display_target_blocks,
                is_syncing: progress.is_syncing,
                is_complete: progress.is_complete,
                has_new_tx: progress.has_new_tx,
            });
        }) {
            Ok(()) => 0,
            Err(MigrationPreparationError::NoActiveOperation) => {
                log::warn!("ffi: migration preparation sync has no active operation");
                4
            }
            Err(MigrationPreparationError::SyncAlreadyRunning) => {
                log::warn!("ffi: migration preparation sync already running");
                3
            }
            Err(error) => {
                log::error!("ffi: migration preparation sync failed: {error}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("migration preparation sync", panic);
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

/// Advance denomination preparation once and stop before child proof creation.
/// Returns 0 on success, 1 on validation/execution error, and 2 on panic.
#[no_mangle]
pub extern "C" fn zcash_advance_migration_preparation(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    account_uuid: *const c_char,
    expected_run_id: *const c_char,
    credential: *const u8,
    credential_len: usize,
    salt_base64: *const c_char,
    output: *mut CMigrationPreparationProgress,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
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
        let Some(salt_base64) = (unsafe { c_str_to_str(salt_base64) }) else {
            return 1;
        };
        let Some(credential) = (unsafe { credential_bytes(credential, credential_len) }) else {
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

        match migration_preparation::advance(
            db_path,
            lightwalletd_url,
            network,
            account_uuid,
            expected_run_id,
            zeroize::Zeroizing::new(credential.to_vec()),
            salt_base64,
        ) {
            Ok(progress) => {
                *output = progress.into();
                0
            }
            Err(error) => {
                log::error!("ffi: advance migration preparation: {error}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("migration preparation advancement", panic);
            2
        }
    }
}

/// Begin one migration preparation operation spanning every sync and advance
/// call made by the Swift task.
#[no_mangle]
pub extern "C" fn zcash_begin_migration_preparation_operation() -> bool {
    migration_preparation::begin_operation()
}

/// End the current migration preparation operation after its serial Swift work
/// has returned.
#[no_mangle]
pub extern "C" fn zcash_end_migration_preparation_operation() {
    migration_preparation::end_operation();
}

/// Cancel the active migration preparation operation without touching the
/// foreground sync cancellation token.
#[no_mangle]
pub extern "C" fn zcash_cancel_migration_preparation_sync() -> bool {
    migration_preparation::cancel_operation()
}

/// Check if a sync is currently running.
#[no_mangle]
pub extern "C" fn zcash_is_sync_running() -> bool {
    migration_preparation::is_sync_running()
}
