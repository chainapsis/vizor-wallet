//! C FFI interface for iOS Ironwood migration background work.

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};

use crate::api::sync::SYNC_RUNNING;
use crate::wallet::{keys, sync, sync_engine};

struct MigrationPreparationControl {
    cancel: Arc<AtomicBool>,
    desired_sync_mode: AtomicU8,
}

impl MigrationPreparationControl {
    fn new() -> Self {
        Self {
            cancel: Arc::new(AtomicBool::new(false)),
            desired_sync_mode: AtomicU8::new(2),
        }
    }

    fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
        self.desired_sync_mode.store(0, Ordering::SeqCst);
    }
}

struct MigrationPreparationOperation {
    active: Mutex<Option<Arc<MigrationPreparationControl>>>,
}

impl MigrationPreparationOperation {
    const fn new() -> Self {
        Self {
            active: Mutex::new(None),
        }
    }

    fn begin(&self) -> bool {
        let mut active = self
            .active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if active.is_some() {
            return false;
        }
        *active = Some(Arc::new(MigrationPreparationControl::new()));
        true
    }

    fn cancel(&self) -> bool {
        let active = self
            .active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let Some(control) = active.as_ref() else {
            return false;
        };
        control.cancel();
        true
    }

    fn end(&self) {
        let control = self
            .active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take();
        if let Some(control) = control {
            control.cancel();
        }
    }

    fn control(&self) -> Option<Arc<MigrationPreparationControl>> {
        self.active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .as_ref()
            .cloned()
    }
}

static MIGRATION_PREPARATION_OPERATION: MigrationPreparationOperation =
    MigrationPreparationOperation::new();

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
    let Some(control) = MIGRATION_PREPARATION_OPERATION.control() else {
        log::warn!("ffi: migration preparation sync has no active operation");
        return 4;
    };
    if SYNC_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        log::warn!("ffi: migration preparation sync already running");
        return 3;
    }
    let code = run_migration_preparation_sync_after_acquire(
        db_path,
        lightwalletd_url,
        network,
        progress_callback,
        control.cancel.clone(),
        &control.desired_sync_mode,
    );
    SYNC_RUNNING.store(false, Ordering::SeqCst);
    code
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
    scanned_height: u32,
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
        "ready_to_migrate" if status.signed_child_pczt_count > 0 => {
            match status.next_action_height {
                Some(height) if height <= scanned_height => 1,
                Some(_) => 5,
                None => 2,
            }
        }
        "broadcast_scheduled" | "broadcasting" | "waiting_migration_confirmations" | "complete" => {
            4
        }
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
        let scanned_height = match sync::get_sync_progress(db_path, network).and_then(|progress| {
            u32::try_from(progress.scanned_height)
                .map_err(|_| "Migration scanned height exceeds u32".to_string())
        }) {
            Ok(height) => height,
            Err(error) => {
                log::error!("ffi: inspect migration preparation height: {error}");
                return 1;
            }
        };
        fill_migration_preparation_progress(output, &status, scanned_height);
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
        let Some(control) = MIGRATION_PREPARATION_OPERATION.control() else {
            log::error!("ffi: migration preparation advance has no active operation");
            return 1;
        };
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
            control.cancel.as_ref(),
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
        let scanned_height = match sync::get_sync_progress(db_path, network).and_then(|progress| {
            u32::try_from(progress.scanned_height)
                .map_err(|_| "Migration scanned height exceeds u32".to_string())
        }) {
            Ok(height) => height,
            Err(error) => {
                log::error!("ffi: inspect migration preparation height: {error}");
                return 1;
            }
        };
        fill_migration_preparation_progress(output, &status, scanned_height);
        if control.cancel.load(Ordering::SeqCst) {
            output.state = 3;
        }
        0
    });
    match result {
        Ok(code) => code,
        Err(_) => 2,
    }
}

fn run_migration_preparation_sync_after_acquire(
    db_path: *const c_char,
    lightwalletd_url: *const c_char,
    network: *const c_char,
    progress_callback: SyncProgressCallback,
    cancel: Arc<AtomicBool>,
    desired_mode: &AtomicU8,
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
                2,
                desired_mode,
                false,
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

/// Begin one migration preparation operation spanning every sync and advance
/// call made by the Swift task.
#[no_mangle]
pub extern "C" fn zcash_begin_migration_preparation_operation() -> bool {
    MIGRATION_PREPARATION_OPERATION.begin()
}

/// End the current migration preparation operation after its serial Swift work
/// has returned.
#[no_mangle]
pub extern "C" fn zcash_end_migration_preparation_operation() {
    MIGRATION_PREPARATION_OPERATION.end();
}

/// Cancel the active migration preparation operation without touching the
/// foreground sync cancellation token.
#[no_mangle]
pub extern "C" fn zcash_cancel_migration_preparation_sync() -> bool {
    MIGRATION_PREPARATION_OPERATION.cancel()
}

/// Check if a sync is currently running.
#[no_mangle]
pub extern "C" fn zcash_is_sync_running() -> bool {
    SYNC_RUNNING.load(Ordering::SeqCst)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migration_preparation_operation_owns_cancel_across_sync_and_advance() {
        let operation = MigrationPreparationOperation::new();
        assert!(operation.begin());
        assert!(!operation.begin());

        let sync_control = operation.control().unwrap();
        let advance_control = operation.control().unwrap();
        assert!(Arc::ptr_eq(&sync_control, &advance_control));
        assert!(!sync_control.cancel.load(Ordering::Relaxed));
        assert_eq!(sync_control.desired_sync_mode.load(Ordering::SeqCst), 2);

        let unrelated_sync_cancel = AtomicBool::new(false);
        unrelated_sync_cancel.store(true, Ordering::Relaxed);
        assert!(!sync_control.cancel.load(Ordering::Relaxed));

        assert!(operation.cancel());
        assert!(sync_control.cancel.load(Ordering::Relaxed));
        assert!(advance_control.cancel.load(Ordering::Relaxed));
        assert_eq!(sync_control.desired_sync_mode.load(Ordering::SeqCst), 0);

        operation.end();
        assert!(operation.control().is_none());
        assert!(!operation.cancel());

        assert!(operation.begin());
        let next_control = operation.control().unwrap();
        assert!(!Arc::ptr_eq(&sync_control, &next_control));
        assert!(!next_control.cancel.load(Ordering::Relaxed));
        operation.end();
    }
}
