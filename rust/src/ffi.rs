//! C FFI interface for calling sync from Swift (iOS BGContinuedProcessingTask).

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::api::sync::{DESIRED_SYNC_MODE, SYNC_CANCEL, SYNC_RUNNING};
use crate::wallet::{keys, sync_engine};

/// Progress data passed to the C callback.
#[repr(C)]
pub struct CSyncProgress {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub is_complete: bool,
}

/// C callback type for progress updates.
pub type SyncProgressCallback = extern "C" fn(CSyncProgress);


/// Run full sync from C (Swift). Blocks until complete or cancelled.
/// Returns 0 on success, 1 on error.
#[no_mangle]
pub extern "C" fn zcash_run_full_sync(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    progress_callback: SyncProgressCallback,
) -> i32 {
    if SYNC_RUNNING.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() {
        return 3; // already running
    }

    DESIRED_SYNC_MODE.store(2, Ordering::SeqCst); // background mode

    let result = std::panic::catch_unwind(|| {
        let db_path = unsafe { CStr::from_ptr(db_path) }.to_str().unwrap_or("");
        let lightwalletd_url = unsafe { CStr::from_ptr(lightwalletd_url) }.to_str().unwrap_or("");
        let network_str = unsafe { CStr::from_ptr(network) }.to_str().unwrap_or("main");

        let network = match keys::parse_network(network_str) {
            Ok(n) => n,
            Err(_) => return 1,
        };

        let cancel = SYNC_CANCEL.clone();
        cancel.store(false, Ordering::Relaxed);

        let rt = match tokio::runtime::Runtime::new() {
            Ok(rt) => rt,
            Err(_) => return 1,
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
                        is_complete: progress.is_complete,
                    });
                },
            )
            .await
        });

        match result {
            Ok(()) => 0,
            Err(_) => 1,
        }
    });

    SYNC_RUNNING.store(false, Ordering::SeqCst);

    match result {
        Ok(code) => code,
        Err(_) => 2, // panic
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
