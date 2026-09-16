//! USB transport for the Ledger Zcash app on macOS, Windows, and Linux.
//!
//! Each operation opens a fresh HID session. This keeps app transitions and
//! user-approved key exports isolated from later device operations.

pub(crate) mod apdu;

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
mod transport;

use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    },
    thread,
    time::{Duration, Instant},
};

static LEDGER_OPERATION: Mutex<()> = Mutex::new(());
static LEDGER_OPERATION_STATE: OperationState = OperationState::new();
const LEDGER_OPERATION_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const APP_TRANSITION_TIMEOUT: Duration = Duration::from_secs(10);
const APP_TRANSITION_POLL_INTERVAL: Duration = Duration::from_millis(200);
const ZCASH_APP_NAME: &str = "Zcash";
const DASHBOARD_APP_NAMES: [&str; 3] = ["BOLOS", "OLOS", "OLOS\0"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceAppInfo {
    pub name: String,
    pub version: String,
}

struct OperationState {
    next: AtomicU64,
    active: AtomicU64,
    cancelled: AtomicU64,
}

impl OperationState {
    const fn new() -> Self {
        Self {
            next: AtomicU64::new(0),
            active: AtomicU64::new(0),
            cancelled: AtomicU64::new(0),
        }
    }

    fn begin(&self) -> u64 {
        let generation = self.next.fetch_add(1, Ordering::SeqCst).wrapping_add(1);
        assert_ne!(generation, 0, "Ledger operation generation exhausted");
        self.active.store(generation, Ordering::SeqCst);
        generation
    }

    fn finish(&self, generation: u64) {
        let _ = self
            .active
            .compare_exchange(generation, 0, Ordering::SeqCst, Ordering::SeqCst);
    }

    fn cancel_active(&self) {
        let generation = self.active.load(Ordering::SeqCst);
        if generation != 0 {
            self.cancelled.store(generation, Ordering::SeqCst);
        }
    }

    fn is_cancelled(&self, generation: u64) -> bool {
        self.cancelled.load(Ordering::SeqCst) == generation
    }
}

#[derive(Clone, Copy)]
pub(super) struct OperationContext {
    generation: u64,
    deadline: Instant,
}

impl OperationContext {
    pub(super) fn check(&self) -> Result<(), String> {
        classify_operation_state(
            LEDGER_OPERATION_STATE.is_cancelled(self.generation),
            Instant::now() >= self.deadline,
        )
    }

    pub(super) fn remaining(&self) -> Duration {
        self.deadline.saturating_duration_since(Instant::now())
    }
}

struct OperationGuard {
    _lock: std::sync::MutexGuard<'static, ()>,
    context: OperationContext,
}

impl OperationGuard {
    fn context(&self) -> OperationContext {
        self.context
    }
}

impl Drop for OperationGuard {
    fn drop(&mut self) {
        LEDGER_OPERATION_STATE.finish(self.context.generation);
    }
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
pub fn get_device_app() -> Result<DeviceAppInfo, String> {
    let operation = lock_operation()?;
    read_device_app(operation.context())
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn get_device_app() -> Result<DeviceAppInfo, String> {
    Err(unsupported_platform())
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
pub fn open_zcash_app() -> Result<DeviceAppInfo, String> {
    let operation = lock_operation()?;
    let context = operation.context();
    let current = read_device_app(context)?;
    if current.name == ZCASH_APP_NAME {
        return Ok(current);
    }

    if !is_dashboard_app(&current.name) {
        let transport = transport::LedgerTransport::connect(context)?;
        transport.close_app()?;
        drop(transport);
        wait_for_device_app(context, is_dashboard_app, "Ledger dashboard")?;
    }

    let transport = transport::LedgerTransport::connect(context)?;
    transport.open_app(ZCASH_APP_NAME)?;
    drop(transport);
    wait_for_device_app(context, |name| name == ZCASH_APP_NAME, "Zcash app")
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn open_zcash_app() -> Result<DeviceAppInfo, String> {
    Err(unsupported_platform())
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
fn read_device_app(context: OperationContext) -> Result<DeviceAppInfo, String> {
    let app = transport::LedgerTransport::connect(context)?.current_app()?;
    Ok(DeviceAppInfo {
        name: app.name,
        version: app.version,
    })
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
fn wait_for_device_app(
    context: OperationContext,
    matches: impl Fn(&str) -> bool,
    expected: &str,
) -> Result<DeviceAppInfo, String> {
    let deadline = Instant::now() + APP_TRANSITION_TIMEOUT;
    loop {
        context.check()?;
        let observation = match read_device_app(context) {
            Ok(app) if matches(&app.name) => return Ok(app),
            Ok(app) => format!("the device reported {} {}", app.name, app.version),
            Err(error) if is_terminal_app_transition_error(&error) => return Err(error),
            Err(error) => error,
        };
        if Instant::now() >= deadline {
            return Err(format!(
                "Ledger did not become ready in {expected} after switching apps: {observation}"
            ));
        }
        thread::sleep(APP_TRANSITION_POLL_INTERVAL);
    }
}

fn is_dashboard_app(name: &str) -> bool {
    DASHBOARD_APP_NAMES.contains(&name)
}

fn is_terminal_app_transition_error(error: &str) -> bool {
    error.contains("locked")
        || error.contains("PIN is not set")
        || error.contains("not installed")
        || error.contains("rejected")
        || error.contains("does not support this command")
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
pub fn get_ufvk(account_index: u32) -> Result<String, String> {
    let operation = lock_operation()?;
    transport::LedgerTransport::connect(operation.context())?.ufvk(account_index)
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn get_ufvk(_account_index: u32) -> Result<String, String> {
    Err(unsupported_platform())
}

/// Export account material and its USB product name from the same device session.
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
pub fn get_ufvk_with_device_model(account_index: u32) -> Result<(String, Option<String>), String> {
    let operation = lock_operation()?;
    let transport = transport::LedgerTransport::connect(operation.context())?;
    let model = transport.device_model().map(str::to_owned);
    let ufvk = transport.ufvk(account_index)?;
    Ok((ufvk, model))
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
pub fn get_ufvk_with_device_model(_account_index: u32) -> Result<(String, Option<String>), String> {
    Err(unsupported_platform())
}

pub fn cancel_operation() {
    LEDGER_OPERATION_STATE.cancel_active();
}

fn lock_operation() -> Result<OperationGuard, String> {
    let lock = LEDGER_OPERATION
        .lock()
        .map_err(|_| "Ledger operation lock was poisoned".to_string())?;
    let generation = LEDGER_OPERATION_STATE.begin();
    Ok(OperationGuard {
        _lock: lock,
        context: OperationContext {
            generation,
            deadline: Instant::now() + LEDGER_OPERATION_TIMEOUT,
        },
    })
}

fn classify_operation_state(cancelled: bool, timed_out: bool) -> Result<(), String> {
    if cancelled {
        Err("Ledger operation was cancelled. Retry when ready.".into())
    } else if timed_out {
        Err(
            "Ledger operation timed out waiting for the device. Reopen the Zcash app and retry."
                .into(),
        )
    } else {
        Ok(())
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
fn unsupported_platform() -> String {
    "Ledger USB is currently supported only on macOS, Windows, and Linux".into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancellation_targets_only_the_active_operation_generation() {
        let state = OperationState::new();
        let first = state.begin();
        state.cancel_active();
        assert!(state.is_cancelled(first));
        state.finish(first);

        let retry = state.begin();
        assert_ne!(retry, first);
        assert!(!state.is_cancelled(retry));
        state.cancel_active();
        assert!(state.is_cancelled(retry));
        state.finish(retry);
    }

    #[test]
    fn cancellation_with_no_active_operation_does_not_cancel_the_next_one() {
        let state = OperationState::new();
        state.cancel_active();
        let generation = state.begin();
        assert!(!state.is_cancelled(generation));
        state.finish(generation);
    }

    #[test]
    fn operation_abort_errors_prefer_cancellation_to_timeout() {
        assert_eq!(classify_operation_state(false, false), Ok(()));
        assert!(classify_operation_state(true, false)
            .unwrap_err()
            .contains("cancelled"));
        assert!(classify_operation_state(false, true)
            .unwrap_err()
            .contains("timed out"));
        assert!(classify_operation_state(true, true)
            .unwrap_err()
            .contains("cancelled"));
    }

    #[test]
    fn recognizes_dashboard_names_and_terminal_transition_errors() {
        for name in DASHBOARD_APP_NAMES {
            assert!(is_dashboard_app(name));
        }
        assert!(!is_dashboard_app("Zcash"));
        assert!(!is_terminal_app_transition_error("No Ledger device found"));
        assert!(!is_terminal_app_transition_error(
            "Ledger device is busy switching apps; retry shortly"
        ));
        assert!(is_terminal_app_transition_error("Ledger device is locked"));
        assert!(is_terminal_app_transition_error(
            "The Zcash app is not installed on this Ledger"
        ));
    }
}
