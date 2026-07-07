//! C FFI interface for calling sync from Swift (iOS BGContinuedProcessingTask).

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::atomic::Ordering;

use crate::api::sync::{DESIRED_SYNC_MODE, SYNC_CANCEL, SYNC_RUNNING};
use crate::wallet::{keys, sync_engine};

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
        cancel.store(false, Ordering::Relaxed);

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

    SYNC_RUNNING.store(false, Ordering::SeqCst);

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

/// Check if a sync is currently running.
#[no_mangle]
pub extern "C" fn zcash_is_sync_running() -> bool {
    SYNC_RUNNING.load(Ordering::SeqCst)
}
