//! C FFI interface for calling sync from Swift (iOS BGContinuedProcessingTask).

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

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

/// Global cancel flag for C FFI sync.
static C_CANCEL: std::sync::LazyLock<Arc<AtomicBool>> =
    std::sync::LazyLock::new(|| Arc::new(AtomicBool::new(false)));

/// Run full sync from C (Swift). Blocks until complete or cancelled.
/// Returns 0 on success, 1 on error.
#[no_mangle]
pub extern "C" fn zcash_run_full_sync(
    db_path: *const c_char,
    cache_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    progress_callback: SyncProgressCallback,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let db_path = unsafe { CStr::from_ptr(db_path) }.to_str().unwrap_or("");
        let cache_path = unsafe { CStr::from_ptr(cache_path) }.to_str().unwrap_or("");
        let lightwalletd_url = unsafe { CStr::from_ptr(lightwalletd_url) }.to_str().unwrap_or("");
        let network_str = unsafe { CStr::from_ptr(network) }.to_str().unwrap_or("main");

        let network = match keys::parse_network(network_str) {
            Ok(n) => n,
            Err(_) => return 1,
        };

        let cancel = C_CANCEL.clone();
        cancel.store(false, Ordering::Relaxed);

        let rt = match tokio::runtime::Runtime::new() {
            Ok(rt) => rt,
            Err(_) => return 1,
        };

        let result = rt.block_on(async {
            sync_engine::run_sync_inner(
                db_path,
                cache_path,
                lightwalletd_url,
                network,
                cancel,
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

    match result {
        Ok(code) => code,
        Err(_) => 2, // panic
    }
}

/// Cancel a running C FFI sync.
#[no_mangle]
pub extern "C" fn zcash_cancel_sync() {
    C_CANCEL.store(true, Ordering::Relaxed);
}
