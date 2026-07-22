//! C FFI interface for calling sync from Swift (iOS BGContinuedProcessingTask).

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::api::sync::{DESIRED_SYNC_MODE, SYNC_CANCEL, SYNC_RUNNING};
use crate::wallet::{keys, sync, sync_engine};

static MIGRATION_PREPARATION_SYNC_RUNNING: AtomicBool = AtomicBool::new(false);

#[repr(C)]
pub struct CMigrationPreparationProgress {
    /// 0 waiting, 1 ready for migration, 2 needs user action, 3 cancelled,
    /// 4 no matching active preparation.
    pub state: u8,
    pub confirmation_count: u32,
    pub confirmation_target: u32,
    pub completed_stage_count: u32,
    pub total_stage_count: u32,
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
        Ok(s) if !s.is_empty() => Some(s),
        _ => None,
    }
}

/// Run full sync from C (Swift). Blocks until complete or cancelled.
/// Returns 0 on success, 1 on error, 2 on panic, 3 on already running, 4 on mode conflict.
#[no_mangle]
pub extern "C" fn zcash_run_full_sync(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    progress_callback: SyncProgressCallback,
) -> i32 {
    if SYNC_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        log::warn!("ffi: sync already running");
        return 3;
    }

    // Don't force mode — Dart/Swift caller should have set it before calling.
    // If mode is 0 (stop requested), bail out immediately.
    if DESIRED_SYNC_MODE.load(Ordering::SeqCst) != 2 {
        log::warn!(
            "ffi: mode is not background ({}), aborting",
            DESIRED_SYNC_MODE.load(Ordering::SeqCst)
        );
        SYNC_RUNNING.store(false, Ordering::SeqCst);
        return 4;
    }

    let code = run_full_sync_after_acquire(
        db_path,
        lightwalletd_url,
        network,
        progress_callback,
        true,
        true,
    );
    SYNC_RUNNING.store(false, Ordering::SeqCst);
    code
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
    if SYNC_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        log::warn!("ffi: migration preparation sync already running");
        return 3;
    }
    MIGRATION_PREPARATION_SYNC_RUNNING.store(true, Ordering::SeqCst);
    // Claim the mode only after acquiring the single-sync guard. Setting mode
    // before this point cancels an in-flight foreground sync and can make that
    // interrupted run report success without advancing the scan watermark.
    let previous_mode = DESIRED_SYNC_MODE.swap(2, Ordering::SeqCst);
    let code = run_full_sync_after_acquire(
        db_path,
        lightwalletd_url,
        network,
        progress_callback,
        true,
        false,
    );
    let mode_after_sync = DESIRED_SYNC_MODE.load(Ordering::SeqCst);
    if mode_after_sync == 2 {
        let _ = DESIRED_SYNC_MODE.compare_exchange(
            2,
            previous_mode,
            Ordering::SeqCst,
            Ordering::SeqCst,
        );
    }
    MIGRATION_PREPARATION_SYNC_RUNNING.store(false, Ordering::SeqCst);
    SYNC_RUNNING.store(false, Ordering::SeqCst);
    if code == 0 && mode_after_sync != 2 {
        log::warn!("ffi: migration preparation sync lost mode ownership");
        4
    } else {
        code
    }
}

unsafe fn credential_bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if ptr.is_null() || len == 0 {
        return None;
    }
    Some(std::slice::from_raw_parts(ptr, len))
}

fn fill_migration_preparation_progress(
    output: &mut CMigrationPreparationProgress,
    status: &sync::MigrationStatus,
) {
    if status.active_run_id.is_none() {
        output.state = 4;
        output.confirmation_count = 0;
        output.confirmation_target = 0;
        output.completed_stage_count = 0;
        output.total_stage_count = 0;
        return;
    }
    output.state = match status.phase.as_str() {
        "waiting_denom_confirmations" => 0,
        "ready_to_migrate"
        | "broadcast_scheduled"
        | "broadcasting"
        | "waiting_migration_confirmations"
        | "complete" => 1,
        _ => 2,
    };
    output.confirmation_count = status.denomination_confirmation_count;
    output.confirmation_target = status.denomination_confirmation_target;
    output.completed_stage_count = status.denomination_split_completed_count;
    output.total_stage_count = status.denomination_split_total_count;
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
        let status = match sync::migration_status(db_path, network, account_uuid, 0, 0, 0, 0) {
            Ok(status) => status,
            Err(error) => {
                log::error!("ffi: inspect migration preparation: {error}");
                return 1;
            }
        };
        if status.active_run_id.as_deref() != Some(expected_run_id) {
            output.state = 4;
            output.confirmation_count = 0;
            output.confirmation_target = 0;
            output.completed_stage_count = 0;
            output.total_stage_count = 0;
            return 0;
        }
        fill_migration_preparation_progress(output, &status);
        0
    });
    match result {
        Ok(code) => code,
        Err(_) => 2,
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
        if credential.len() != 64 || !credential.iter().all(u8::is_ascii_hexdigit) {
            log::error!("ffi: migration preparation credential must be 64 hexadecimal bytes");
            return 1;
        }
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
        let runtime = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: migration preparation runtime: {error}");
                return 1;
            }
        };
        let advance = runtime.block_on(sync::advance_orchard_migration_preparation_for_run(
            db_path,
            lightwalletd_url,
            network,
            account_uuid,
            expected_run_id,
            zeroize::Zeroizing::new(credential.to_vec()),
            salt_base64,
            SYNC_CANCEL.as_ref(),
        ));
        if let Err(error) = advance {
            log::error!("ffi: advance migration preparation: {error}");
            return 1;
        }
        let status = match sync::migration_status(db_path, network, account_uuid, 0, 0, 0, 0) {
            Ok(status) => status,
            Err(error) => {
                log::error!("ffi: inspect migration preparation: {error}");
                return 1;
            }
        };
        if status
            .active_run_id
            .as_deref()
            .is_some_and(|id| id != expected_run_id)
        {
            return 1;
        }
        fill_migration_preparation_progress(output, &status);
        if SYNC_CANCEL.load(Ordering::SeqCst) {
            output.state = 3;
        }
        0
    });
    match result {
        Ok(code) => code,
        Err(_) => 2,
    }
}

fn run_full_sync_after_acquire(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    progress_callback: SyncProgressCallback,
    reset_cancel: bool,
    allow_resubmit: bool,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let db_path = match unsafe { c_str_to_str(db_path) } {
            Some(s) => s,
            None => {
                log::error!("ffi: invalid or null db_path");
                return 1;
            }
        };
        let lightwalletd_url = match unsafe { c_str_to_str(lightwalletd_url) } {
            Some(s) => s,
            None => {
                log::error!("ffi: invalid or null lightwalletd_url");
                return 1;
            }
        };
        let network_str = match unsafe { c_str_to_str(network) } {
            Some(s) => s,
            None => {
                log::error!("ffi: invalid or null network string");
                return 1;
            }
        };

        let network = match keys::parse_network(network_str) {
            Ok(n) => n,
            Err(e) => {
                log::error!("ffi: parse_network failed: {e}");
                return 1;
            }
        };

        let cancel = SYNC_CANCEL.clone();
        if reset_cancel {
            cancel.store(false, Ordering::Relaxed);
        }

        // current_thread runtime — inherits .utility QoS from iOS dispatch queue
        let rt = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(rt) => rt,
            Err(e) => {
                log::error!("ffi: tokio runtime failed: {e}");
                return 1;
            }
        };

        let result = rt.block_on(async {
            sync_engine::run_sync_inner(
                db_path,
                lightwalletd_url,
                network,
                cancel,
                2, // background mode
                &DESIRED_SYNC_MODE,
                allow_resubmit,
                |progress| {
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
                },
            )
            .await
        });

        match result {
            Ok(()) => 0,
            Err(e) => {
                log::error!("ffi: sync failed: {e}");
                1
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown".to_string()
            };
            log::error!("ffi: panic during sync: {msg}");
            2
        }
    }
}

/// Cancel a running sync (shared flag with FRB path).
#[no_mangle]
pub extern "C" fn zcash_cancel_sync() {
    SYNC_CANCEL.store(true, Ordering::Relaxed);
}

/// Cancel only when the active sync is owned by migration preparation.
/// Returns false while another foreground/background sync owns the shared
/// engine, so an expiring preparation task cannot interrupt that work.
#[no_mangle]
pub extern "C" fn zcash_cancel_migration_preparation_sync() -> bool {
    if !MIGRATION_PREPARATION_SYNC_RUNNING.load(Ordering::SeqCst) {
        return false;
    }
    SYNC_CANCEL.store(true, Ordering::Relaxed);
    true
}

/// Get the current desired sync mode (0=none, 1=foreground, 2=background).
#[no_mangle]
pub extern "C" fn zcash_get_sync_mode() -> u8 {
    DESIRED_SYNC_MODE.load(Ordering::SeqCst)
}

/// Set the desired sync mode (0=none, 1=foreground, 2=background).
#[no_mangle]
pub extern "C" fn zcash_set_sync_mode(mode: u8) {
    DESIRED_SYNC_MODE.store(mode, Ordering::SeqCst);
}

/// Check if a sync is currently running.
#[no_mangle]
pub extern "C" fn zcash_is_sync_running() -> bool {
    SYNC_RUNNING.load(Ordering::SeqCst)
}
