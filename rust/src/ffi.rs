//! C adapter for iOS Ironwood migration background work.
//!
//! The platform-neutral state mapping lives in `crate::migration_preparation`;
//! this module validates C inputs and converts native values. Confirmation
//! polling stays read-only; sync and denomination advancement remain owned by
//! the foreground FRB path.

use std::ffi::CStr;
use std::future::Future;
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use std::time::Duration;

use crate::migration_preparation::{self, MigrationPreparationProgress};
use crate::network_privacy::NetworkPrivacyStatus;
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

static FFI_RUNTIME: OnceLock<Result<tokio::runtime::Runtime, String>> = OnceLock::new();

/// The runtime every C entry point runs its async work on.
///
/// It has to outlive the calls: a Tor client is created here and kept in a
/// process-wide slot, but arti's directory, guard and circuit tasks run on
/// whatever runtime created it. A per-call runtime would take them down as it
/// dropped, leaving a client that looks installed and cannot carry traffic.
/// Multi-threaded because separate native threads block on it concurrently.
fn ffi_runtime() -> Result<&'static tokio::runtime::Runtime, String> {
    FFI_RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .map_err(|error| format!("Create FFI runtime: {error}"))
        })
        .as_ref()
        .map_err(|error| error.clone())
}

const LIGHTWALLETD_RESULT_CANCELLED: i32 = 3;
const LIGHTWALLETD_CANCELLATION_POLL_INTERVAL: Duration = Duration::from_millis(25);

/// Tor is up and the caller may do network work over it.
const NETWORK_PRIVACY_TOR_READY: i32 = 0;
/// Tor is not up. The route stays Tor-desired and fail-closed, so the caller
/// does no network work and defers to the foreground.
const NETWORK_PRIVACY_TOR_NOT_READY: i32 = 1;
/// Matches the panic code the other entry points return; also not ready.
const NETWORK_PRIVACY_TOR_PANICKED: i32 = 2;

#[repr(C)]
pub struct CLightwalletdCancellation {
    cancelled: AtomicBool,
}

#[no_mangle]
pub extern "C" fn zcash_lightwalletd_cancellation_create() -> *mut CLightwalletdCancellation {
    Box::into_raw(Box::new(CLightwalletdCancellation {
        cancelled: AtomicBool::new(false),
    }))
}

#[no_mangle]
pub extern "C" fn zcash_lightwalletd_cancellation_cancel(
    cancellation: *mut CLightwalletdCancellation,
) {
    if let Some(cancellation) = unsafe { cancellation.as_ref() } {
        cancellation.cancelled.store(true, Ordering::Release);
    }
}

#[no_mangle]
pub extern "C" fn zcash_lightwalletd_cancellation_destroy(
    cancellation: *mut CLightwalletdCancellation,
) {
    if !cancellation.is_null() {
        drop(unsafe { Box::from_raw(cancellation) });
    }
}

async fn await_lightwalletd_request_or_cancellation<F>(
    cancellation: Option<&CLightwalletdCancellation>,
    future: F,
) -> Result<F::Output, ()>
where
    F: Future,
{
    let Some(cancellation) = cancellation else {
        return Ok(future.await);
    };
    if cancellation.cancelled.load(Ordering::Acquire) {
        return Err(());
    }

    tokio::pin!(future);
    loop {
        tokio::select! {
            output = &mut future => {
                return if cancellation.cancelled.load(Ordering::Acquire) {
                    Err(())
                } else {
                    Ok(output)
                };
            }
            _ = tokio::time::sleep(LIGHTWALLETD_CANCELLATION_POLL_INTERVAL) => {
                if cancellation.cancelled.load(Ordering::Acquire) {
                    return Err(());
                }
            }
        }
    }
}

/// Fetch the lightwalletd chain tip through tonic. Unlike URLSession, this
/// supports both production HTTPS and plaintext HTTP/2 (h2c) regtest servers.
#[no_mangle]
pub extern "C" fn zcash_lightwalletd_latest_block_height(
    lightwalletd_url: *const c_char,
    output: *mut u64,
    cancellation: *const CLightwalletdCancellation,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
            return 1;
        };
        let Some(output) = (unsafe { output.as_mut() }) else {
            return 1;
        };
        let runtime = match ffi_runtime() {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: {error}");
                return 1;
            }
        };
        let cancellation = unsafe { cancellation.as_ref() };
        match runtime.block_on(await_lightwalletd_request_or_cancellation(
            cancellation,
            async {
                let mut client =
                    crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await?;
                crate::wallet::sync_engine::get_latest_block(&mut client).await
            },
        )) {
            Err(()) => LIGHTWALLETD_RESULT_CANCELLED,
            Ok(Ok(block)) => {
                *output = block.height;
                0
            }
            Ok(Err(error)) => {
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
    cancellation: *const CLightwalletdCancellation,
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
        let runtime = match ffi_runtime() {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: {error}");
                return 1;
            }
        };
        let cancellation = unsafe { cancellation.as_ref() };
        match runtime.block_on(await_lightwalletd_request_or_cancellation(
            cancellation,
            async {
                let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
                    .await
                    .map_err(|error| tonic::Status::unavailable(error.to_string()))?;
                crate::wallet::sync_engine::get_transaction(&mut client, transaction_id).await
            },
        )) {
            Err(()) => LIGHTWALLETD_RESULT_CANCELLED,
            Ok(Ok(transaction)) => {
                *output = transaction_observation_from_height(transaction.height);
                0
            }
            Ok(Err(error)) if error.code() == Code::NotFound => {
                *output = CLightwalletdTransactionObservation::not_found();
                0
            }
            Ok(Err(error)) => {
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
    cancellation: *const CLightwalletdCancellation,
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
        let runtime = match ffi_runtime() {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: {error}");
                return 1;
            }
        };
        let cancellation = unsafe { cancellation.as_ref() };
        match runtime.block_on(await_lightwalletd_request_or_cancellation(
            cancellation,
            async {
                let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
                    .await
                    .map_err(|error| error.to_string())?;
                crate::wallet::sync_engine::send_transaction_with_status(
                    &mut client,
                    &raw_transaction,
                )
                .await
                .map_err(|error| error.to_string())
            },
        )) {
            Err(()) => LIGHTWALLETD_RESULT_CANCELLED,
            Ok(Ok(response)) => {
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
            Ok(Err(error)) => {
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

/// Adopt the user's persisted Tor preference before any background network
/// call. The desired route is process-local and defaults to direct, so a
/// background wake into a cold process would otherwise reach lightwalletd over
/// clearnet. The caller must have read the persisted preference itself; this
/// only makes the process fail closed, and returns without bootstrapping Tor or
/// touching the filesystem.
///
/// This is the whole of what a pass that cannot afford a bootstrap does about
/// the route: it marks, does no network work, and leaves the run to the
/// foreground. A pass that can afford one calls
/// [`zcash_network_privacy_enable_tor_for_background_work`], which marks too.
///
/// A preference read outside Dart can be stale, so this is ignored once the
/// process has decided its own route, and reports success either way — the
/// caller refuses its network pass on a persisted Tor route regardless.
#[no_mangle]
pub extern "C" fn zcash_network_privacy_mark_tor_desired() -> i32 {
    let result = std::panic::catch_unwind(|| {
        crate::network_privacy::mark_tor_desired();
        0
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("network privacy Tor declaration", panic);
            2
        }
    }
}

/// Bring Tor up for a background pass and block until it is usable or has
/// failed, so that pass can do its network work on the user's chosen route
/// without waiting for the foreground.
///
/// Call this only once the pass has established that the device is on external
/// power and the link is unmetered. A cold bootstrap costs 8.45 MB down,
/// 744 KB up and 23.7 s and leaves a 46.3 MB cache; the client then pads its
/// guard connection continuously while awake, roughly 500 B/s against 27 B/s
/// dormant. A warm one costs 0.64 s and no bytes. Those are charger-and-Wi-Fi
/// costs, not battery-and-cellular ones. A pass that cannot show both
/// conditions calls [`zcash_network_privacy_mark_tor_desired`] and defers.
///
/// `tor_directory` is the Tor data directory, created if it does not exist.
///
/// Returns `NETWORK_PRIVACY_TOR_READY` (0) when Tor is up and the caller may do
/// network work over it; `NETWORK_PRIVACY_TOR_NOT_READY` (1) when it is not, for
/// any reason at all — bad argument, bootstrap failure, the bootstrap deadline
/// expiring, or a process that had already chosen the direct route — in which
/// case the caller must do no network work and defer to the foreground; and
/// `NETWORK_PRIVACY_TOR_PANICKED` (2) for a panic, which the caller treats as
/// not ready. The route is left Tor-desired and fail-closed in every non-ready
/// case, so a caller that ignores the answer is blocked rather than leaked.
#[no_mangle]
pub extern "C" fn zcash_network_privacy_enable_tor_for_background_work(
    tor_directory: *const c_char,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        // Before the argument is even looked at: a bad path is still a pass
        // whose persisted route is Tor, and it must not fall through to
        // clearnet on its way out of here.
        crate::network_privacy::mark_tor_desired();
        let Some(tor_directory) = (unsafe { c_str_to_str(tor_directory) }) else {
            return NETWORK_PRIVACY_TOR_NOT_READY;
        };
        let runtime = match ffi_runtime() {
            Ok(runtime) => runtime,
            Err(error) => {
                log::error!("ffi: {error}");
                return NETWORK_PRIVACY_TOR_NOT_READY;
            }
        };
        match runtime.block_on(crate::network_privacy::enable_tor_for_background_work(
            std::path::Path::new(tor_directory),
        )) {
            Ok(NetworkPrivacyStatus::Ready) => NETWORK_PRIVACY_TOR_READY,
            Ok(status) => {
                log::info!("ffi: background Tor enable declined: {status:?}");
                NETWORK_PRIVACY_TOR_NOT_READY
            }
            Err(error) => {
                log::error!("ffi: background Tor enable: {error}");
                NETWORK_PRIVACY_TOR_NOT_READY
            }
        }
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("network privacy background Tor enable", panic);
            NETWORK_PRIVACY_TOR_PANICKED
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

        match migration_preparation::inspect_read_only(
            db_path,
            network,
            account_uuid,
            expected_run_id,
        ) {
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

    #[test]
    fn lightwalletd_cancellation_interrupts_an_in_flight_request() {
        let cancellation = CLightwalletdCancellation {
            cancelled: AtomicBool::new(false),
        };
        std::thread::scope(|scope| {
            scope.spawn(|| {
                std::thread::sleep(Duration::from_millis(10));
                cancellation.cancelled.store(true, Ordering::Release);
            });

            let runtime = ffi_runtime().unwrap();
            let started = std::time::Instant::now();
            let result = runtime.block_on(await_lightwalletd_request_or_cancellation(
                Some(&cancellation),
                std::future::pending::<()>(),
            ));
            assert_eq!(result, Err(()));
            assert!(started.elapsed() < Duration::from_secs(1));
        });
    }

    #[test]
    fn lightwalletd_cancellation_handle_lifecycle_sets_the_flag() {
        let cancellation = zcash_lightwalletd_cancellation_create();
        assert!(!cancellation.is_null());
        assert!(!unsafe { &*cancellation }.cancelled.load(Ordering::Acquire));

        zcash_lightwalletd_cancellation_cancel(cancellation);
        assert!(unsafe { &*cancellation }.cancelled.load(Ordering::Acquire));

        zcash_lightwalletd_cancellation_destroy(cancellation);
    }
}
