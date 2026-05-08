//! C FFI interface for calling sync from Swift (iOS BGContinuedProcessingTask).

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::api::sync::{next_sync_run_id, DESIRED_SYNC_MODE, SYNC_CANCEL, SYNC_RUNNING};
use crate::wallet::{keys, sync_engine};

/// Semantic sync engine event passed to the C callback.
#[repr(C)]
pub struct CSyncEventV2 {
    /// 1=progress, 2=completed, 3=stopped.
    pub kind: u8,
    pub run_id: u64,
    pub sequence: u64,
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub percentage: f64,
    pub display_target_percentage: f64,
    pub display_target_blocks: u64,
    pub has_new_tx: bool,
    pub phase: *const c_char,
}

/// C callback type for sync engine events.
pub type SyncEventV2Callback = extern "C" fn(CSyncEventV2);

static PHASE_DOWNLOAD: &[u8] = b"download\0";
static PHASE_SCAN: &[u8] = b"scan\0";
static PHASE_ENHANCE: &[u8] = b"enhance\0";
static PHASE_EMPTY: &[u8] = b"\0";

fn phase_c_string(phase: &str) -> *const c_char {
    match phase {
        "download" => PHASE_DOWNLOAD.as_ptr().cast(),
        "scan" => PHASE_SCAN.as_ptr().cast(),
        "enhance" => PHASE_ENHANCE.as_ptr().cast(),
        _ => PHASE_EMPTY.as_ptr().cast(),
    }
}

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
    event_callback: SyncEventV2Callback,
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

        let run_id = next_sync_run_id();
        let sequence = AtomicU64::new(0);
        let result = rt.block_on(async {
            sync_engine::run_sync_inner(
                db_path,
                lightwalletd_url,
                network,
                cancel,
                2, // background mode
                &DESIRED_SYNC_MODE,
                |event| {
                    let seq = sequence.fetch_add(1, Ordering::SeqCst) + 1;
                    event_callback(CSyncEventV2 {
                        kind: event.kind,
                        run_id,
                        sequence: seq,
                        scanned_height: event.scanned_height,
                        chain_tip_height: event.chain_tip_height,
                        percentage: event.percentage,
                        display_target_percentage: event.display_target_percentage,
                        display_target_blocks: event.display_target_blocks,
                        has_new_tx: event.has_new_tx,
                        phase: phase_c_string(&event.phase),
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

// ======================== TX Tracking FFI ========================

/// Pending transaction info for C callers.
#[repr(C)]
pub struct CPendingTx {
    pub txid_hex: [u8; 65], // 64 hex chars + null terminator
    pub expiry_height: u64,
}

/// Get the number of pending (unmined, unexpired, locally-created) transactions.
/// Returns count on success, -1 on error.
#[no_mangle]
pub extern "C" fn zcash_get_pending_tx_count(db_path: *const c_char) -> i32 {
    let db_path = match unsafe { c_str_to_str(db_path) } {
        Some(s) => s,
        None => {
            log::error!("ffi: invalid or null db_path");
            return -1;
        }
    };
    match crate::wallet::sync::get_pending_transactions(db_path) {
        Ok(txs) => txs.len() as i32,
        Err(e) => {
            log::error!("ffi: get_pending_tx_count: {e}");
            -1
        }
    }
}

/// Fill buffer with pending transactions. Returns number written, -1 on error.
#[no_mangle]
pub extern "C" fn zcash_get_pending_txs(
    db_path: *const c_char,
    out_buf: *mut CPendingTx,
    buf_len: i32,
) -> i32 {
    let db_path = match unsafe { c_str_to_str(db_path) } {
        Some(s) => s,
        None => {
            log::error!("ffi: invalid or null db_path");
            return -1;
        }
    };
    if buf_len <= 0 {
        return 0;
    }
    if out_buf.is_null() {
        log::error!("ffi: null out_buf with buf_len={buf_len}");
        return -1;
    }

    let txs = match crate::wallet::sync::get_pending_transactions(db_path) {
        Ok(t) => t,
        Err(e) => {
            log::error!("ffi: get_pending_txs: {e}");
            return -1;
        }
    };

    let count = std::cmp::min(txs.len(), buf_len as usize);
    for (i, tx) in txs.iter().take(count).enumerate() {
        let mut hex_buf = [0u8; 65];
        let hex_bytes = tx.txid_hex.as_bytes();
        let copy_len = std::cmp::min(hex_bytes.len(), 64);
        hex_buf[..copy_len].copy_from_slice(&hex_bytes[..copy_len]);
        // null terminator already 0
        unsafe {
            (*out_buf.add(i)).txid_hex = hex_buf;
            (*out_buf.add(i)).expiry_height = tx.expiry_height;
        }
    }
    count as i32
}

/// Check if a transaction has been mined via lightwalletd gRPC.
/// Returns: >0 = mined height, 0 = still pending, -1 = error.
#[no_mangle]
pub extern "C" fn zcash_check_tx_status(
    lightwalletd_url: *const c_char,
    txid_hex: *const c_char,
) -> i64 {
    let url = match unsafe { c_str_to_str(lightwalletd_url) } {
        Some(s) => s,
        None => {
            log::error!("ffi: invalid or null lightwalletd_url");
            return -1;
        }
    };
    let hex_str = match unsafe { c_str_to_str(txid_hex) } {
        Some(s) => s,
        None => {
            log::error!("ffi: invalid or null txid_hex");
            return -1;
        }
    };
    let txid_bytes = match hex::decode(hex_str) {
        Ok(b) if b.len() == 32 => b,
        _ => {
            log::error!("ffi: bad txid hex");
            return -1;
        }
    };

    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            log::error!("ffi: tokio runtime failed: {e}");
            return -1;
        }
    };

    rt.block_on(crate::wallet::sync::check_tx_mined(url, &txid_bytes))
}
