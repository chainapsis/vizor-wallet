//! C FFI interface for calling sync from Swift (iOS BGContinuedProcessingTask).

use std::ffi::CStr;
use std::os::raw::c_char;
use std::slice;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use zeroize::Zeroizing;

use crate::api::sync::{DESIRED_SYNC_MODE, SYNC_CANCEL, SYNC_RUNNING};
use crate::wallet::{keys, sync, sync_engine};

static BACKGROUND_MIGRATION_RUNNING: AtomicBool = AtomicBool::new(false);
static BACKGROUND_MIGRATION_CANCEL: AtomicBool = AtomicBool::new(false);
static BACKGROUND_MIGRATION_CANCEL_EPOCH: AtomicU64 = AtomicU64::new(0);

#[repr(C)]
pub struct CBackgroundMigrationResult {
    pub action: u8,
    pub cancelled: bool,
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub next_scheduled_height: u64,
    pub broadcasted_count: u32,
}

impl Default for CBackgroundMigrationResult {
    fn default() -> Self {
        Self {
            action: sync::BackgroundMigrationAction::NeedsUserAction as u8,
            cancelled: false,
            scanned_height: 0,
            chain_tip_height: 0,
            next_scheduled_height: 0,
            broadcasted_count: 0,
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

/// Run a migration-owned sync without racing foreground mode handoff.
///
/// Returns 5 when the owning BGTask was cancelled before sync acquisition.
#[no_mangle]
pub extern "C" fn zcash_run_full_sync_for_migration(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    expected_cancel_epoch: u64,
    progress_callback: SyncProgressCallback,
) -> i32 {
    if SYNC_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        log::warn!("ffi: migration sync could not acquire sync ownership");
        return 3;
    }

    let previous_mode = DESIRED_SYNC_MODE.swap(2, Ordering::SeqCst);
    SYNC_CANCEL.store(false, Ordering::SeqCst);
    if BACKGROUND_MIGRATION_CANCEL_EPOCH.load(Ordering::SeqCst) != expected_cancel_epoch {
        let _ = DESIRED_SYNC_MODE.compare_exchange(
            2,
            previous_mode,
            Ordering::SeqCst,
            Ordering::SeqCst,
        );
        SYNC_RUNNING.store(false, Ordering::SeqCst);
        return 5;
    }

    let code = run_full_sync_after_acquire(
        db_path,
        lightwalletd_url,
        network,
        progress_callback,
        false,
        false,
    );
    let interrupted = SYNC_CANCEL.load(Ordering::SeqCst)
        || DESIRED_SYNC_MODE.load(Ordering::SeqCst) != 2
        || BACKGROUND_MIGRATION_CANCEL_EPOCH.load(Ordering::SeqCst) != expected_cancel_epoch;
    let _ =
        DESIRED_SYNC_MODE.compare_exchange(2, previous_mode, Ordering::SeqCst, Ordering::SeqCst);
    SYNC_RUNNING.store(false, Ordering::SeqCst);
    if code == 0 && interrupted {
        5
    } else {
        code
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

/// Inspect an authorized Ironwood migration without syncing or broadcasting.
///
/// Returns 0 on success, 1 on validation/execution error, 2 on panic, and 3
/// when another background migration operation is already running.
#[no_mangle]
pub extern "C" fn zcash_inspect_background_migration(
    db_path: *const c_char,
    network: *const c_char,
    account_uuid: *const c_char,
    expected_run_id: *const c_char,
    output: *mut CBackgroundMigrationResult,
) -> i32 {
    if BACKGROUND_MIGRATION_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return 3;
    }
    let result = std::panic::catch_unwind(|| {
        let output = match unsafe { output.as_mut() } {
            Some(output) => output,
            None => {
                log::error!("ffi: background migration inspection output is null");
                return 1;
            }
        };
        *output = CBackgroundMigrationResult::default();

        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        let Some(network_name) = (unsafe { c_str_to_str(network) }) else {
            return 1;
        };
        let Some(account_uuid) = (unsafe { c_str_to_str(account_uuid) }) else {
            return 1;
        };
        let Some(expected_run_id) = (unsafe { c_str_to_str(expected_run_id) }) else {
            return 1;
        };
        let network = match keys::parse_network(network_name) {
            Ok(network) => network,
            Err(error) => {
                log::error!("ffi: parse background migration inspection network: {error}");
                return 1;
            }
        };
        let inspection = match sync::inspect_background_migration(
            db_path,
            network,
            account_uuid,
            expected_run_id,
        ) {
            Ok(inspection) => inspection,
            Err(error) => {
                log::error!("ffi: background migration inspection failed: {error}");
                return 1;
            }
        };
        fill_background_migration_output(output, &inspection, false, 0);
        0
    });

    BACKGROUND_MIGRATION_RUNNING.store(false, Ordering::SeqCst);
    match result {
        Ok(code) => code,
        Err(_) => {
            log::error!("ffi: panic during background migration inspection");
            2
        }
    }
}

/// Advance only the already-authorized Ironwood migration run.
///
/// Returns 0 on success, 1 on validation/execution error, 2 on panic, and 3
/// when another background migration cycle is already running.
#[no_mangle]
pub extern "C" fn zcash_run_background_migration_cycle(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    account_uuid: *const c_char,
    expected_run_id: *const c_char,
    credential: *const u8,
    credential_len: usize,
    salt_base64: *const c_char,
    expected_cancel_epoch: u64,
    output: *mut CBackgroundMigrationResult,
) -> i32 {
    if BACKGROUND_MIGRATION_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return 3;
    }
    let result = std::panic::catch_unwind(|| {
        let output = match unsafe { output.as_mut() } {
            Some(output) => output,
            None => {
                log::error!("ffi: background migration output is null");
                return 1;
            }
        };
        *output = CBackgroundMigrationResult::default();
        BACKGROUND_MIGRATION_CANCEL.store(false, Ordering::SeqCst);
        if BACKGROUND_MIGRATION_CANCEL_EPOCH.load(Ordering::SeqCst) != expected_cancel_epoch {
            output.cancelled = true;
            return 0;
        }

        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
            return 1;
        };
        let Some(network_name) = (unsafe { c_str_to_str(network) }) else {
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
        if credential.is_null() || credential_len != 64 {
            log::error!("ffi: background migration credential must be 64 bytes");
            return 1;
        }
        let credential = unsafe { slice::from_raw_parts(credential, credential_len) };
        if !credential.iter().all(u8::is_ascii_hexdigit) {
            log::error!("ffi: background migration credential is not hexadecimal");
            return 1;
        }
        let credential = Zeroizing::new(credential.to_vec());
        let network = match keys::parse_network(network_name) {
            Ok(network) => network,
            Err(error) => {
                log::error!("ffi: parse background migration network: {error}");
                return 1;
            }
        };
        let runtime = match tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: background migration runtime: {error}");
                return 1;
            }
        };
        let cycle = match runtime.block_on(sync::run_background_migration_cycle(
            db_path,
            lightwalletd_url,
            network,
            account_uuid,
            expected_run_id,
            credential,
            salt_base64,
            &BACKGROUND_MIGRATION_CANCEL,
        )) {
            Ok(cycle) => cycle,
            Err(error) => {
                log::error!("ffi: background migration cycle failed: {error}");
                return 1;
            }
        };

        fill_background_migration_output(
            output,
            &cycle.inspection,
            cycle.cancelled,
            cycle.broadcasted_count,
        );
        0
    });

    BACKGROUND_MIGRATION_RUNNING.store(false, Ordering::SeqCst);
    match result {
        Ok(code) => code,
        Err(_) => {
            log::error!("ffi: panic during background migration cycle");
            2
        }
    }
}

fn fill_background_migration_output(
    output: &mut CBackgroundMigrationResult,
    inspection: &sync::BackgroundMigrationInspection,
    cancelled: bool,
    broadcasted_count: u32,
) {
    output.action = inspection.action as u8;
    output.cancelled = cancelled;
    output.scanned_height = inspection.scanned_height;
    output.chain_tip_height = inspection.chain_tip_height;
    output.next_scheduled_height = inspection
        .next_scheduled_height
        .map(u64::from)
        .unwrap_or_default();
    output.broadcasted_count = broadcasted_count;
}

#[no_mangle]
pub extern "C" fn zcash_cancel_background_migration() {
    BACKGROUND_MIGRATION_CANCEL_EPOCH.fetch_add(1, Ordering::SeqCst);
    BACKGROUND_MIGRATION_CANCEL.store(true, Ordering::SeqCst);
    SYNC_CANCEL.store(true, Ordering::SeqCst);
}

#[no_mangle]
pub extern "C" fn zcash_background_migration_cancellation_epoch() -> u64 {
    BACKGROUND_MIGRATION_CANCEL_EPOCH.load(Ordering::SeqCst)
}

#[no_mangle]
pub extern "C" fn zcash_is_background_migration_running() -> bool {
    BACKGROUND_MIGRATION_RUNNING.load(Ordering::SeqCst)
}

/// Check if a sync is currently running.
#[no_mangle]
pub extern "C" fn zcash_is_sync_running() -> bool {
    SYNC_RUNNING.load(Ordering::SeqCst)
}
