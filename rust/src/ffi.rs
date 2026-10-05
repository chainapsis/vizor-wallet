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
use std::time::Duration;

use crate::migration_preparation::{self, MigrationPreparationProgress};
use crate::wallet::db::{open_wallet_db_readonly_with_timeout, READ_DB_BUSY_TIMEOUT};
use crate::wallet::keys;
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::{status, EnhancementPolicy};
use crate::wallet::sync_engine::{SyncError, TransparentLookupGate};
use crate::wallet::transaction_data::TransactionObservation;
use zakura_transaction_status::{
    lightwalletd::LightwalletdSource, DisabledSource, StatusError, StatusMode, StatusReader,
    StatusRequest,
};
use zcash_client_backend::data_api::status::{
    PublicTransactionStatusRequest, TransactionStatusRead, TransactionStatusWork,
};
use zcash_primitives::transaction::TxId;

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

impl From<TransactionObservation> for CLightwalletdTransactionObservation {
    fn from(observation: TransactionObservation) -> Self {
        match observation {
            TransactionObservation::NotFound => Self::not_found(),
            TransactionObservation::Mempool => Self {
                state: 1,
                mined_height: 0,
            },
            TransactionObservation::Forked => Self {
                state: 3,
                mined_height: 0,
            },
            TransactionObservation::Mined(height) => Self {
                state: 2,
                mined_height: u64::from(u32::from(height)),
            },
        }
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

fn lightwalletd_runtime() -> Result<tokio::runtime::Runtime, String> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| format!("Create lightwalletd runtime: {error}"))
}

const LIGHTWALLETD_RESULT_CANCELLED: i32 = 3;
/// No observation was made and none was sent; a later attempt may conclude.
const STATUS_RESULT_INCONCLUSIVE: i32 = 4;
/// The lookup is not authorized through this ABI. Nothing was sent.
const STATUS_RESULT_UNSUPPORTED: i32 = 5;
const LIGHTWALLETD_CANCELLATION_POLL_INTERVAL: Duration = Duration::from_millis(25);

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
        let runtime = match lightwalletd_runtime() {
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
                let mut client = crate::wallet::sync_engine::open_background_direct_lwd_channel(
                    lightwalletd_url,
                )
                .await?;
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

/// Observe one transaction through public lightwalletd and return only status
/// across the C ABI.
///
/// The request discloses the txid, so it is authorized like every other public
/// transparent lookup: against the wallet at `db_path`, opened read-only with
/// a durable `PrivateRequired` adopted, then re-checked by
/// [`TransparentLookupGate`] as it is sent.
///
/// Returns 0 with `output` set, 1 for invalid arguments or a failed lookup,
/// 2 after a panic, and 3 when cancelled. Otherwise it sends no request and
/// leaves `output` untouched:
/// - [`STATUS_RESULT_INCONCLUSIVE`] when the wallet cannot be read; retry later.
/// - [`STATUS_RESULT_UNSUPPORTED`] when the wallet withholds public lookups or
///   routes this transaction's status privately.
#[no_mangle]
pub extern "C" fn zcash_lightwalletd_observe_transaction(
    lightwalletd_url: *const c_char,
    db_path: *const c_char,
    network: *const c_char,
    transaction_id: *const u8,
    transaction_id_len: usize,
    output: *mut CLightwalletdTransactionObservation,
    cancellation: *const CLightwalletdCancellation,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(lightwalletd_url) = (unsafe { c_str_to_str(lightwalletd_url) }) else {
            return 1;
        };
        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        let Some(network) = (unsafe { c_str_to_str(network) }).and_then(WalletNetwork::from_str)
        else {
            return 1;
        };
        if transaction_id.is_null() || transaction_id_len != 32 {
            return 1;
        }
        let Some(output) = (unsafe { output.as_mut() }) else {
            return 1;
        };
        let transaction_id = TxId::from_bytes(
            unsafe { std::slice::from_raw_parts(transaction_id, transaction_id_len) }
                .try_into()
                .expect("validated txid length"),
        );
        observe_public_transaction(
            lightwalletd_url,
            db_path,
            network,
            EnhancementPolicy::current(network),
            transaction_id,
            output,
            unsafe { cancellation.as_ref() },
        )
    });

    match result {
        Ok(code) => code,
        Err(panic) => {
            log_panic("lightwalletd transaction observation", panic);
            2
        }
    }
}

/// [`zcash_lightwalletd_observe_transaction`] under an explicit `policy`, so
/// tests select one without the process-wide preference.
fn observe_public_transaction(
    lightwalletd_url: &str,
    db_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    txid: TxId,
    output: &mut CLightwalletdTransactionObservation,
    cancellation: Option<&CLightwalletdCancellation>,
) -> i32 {
    let (gate, request) = match authorize_public_observation(db_path, network, policy, txid) {
        Ok(Some(authorized)) => authorized,
        Ok(None) => return STATUS_RESULT_UNSUPPORTED,
        Err(_) => return STATUS_RESULT_INCONCLUSIVE,
    };
    #[cfg(test)]
    test_hooks::authorized();
    let runtime = match lightwalletd_runtime() {
        Ok(runtime) => runtime,
        Err(error) => {
            log::error!("ffi: {error}");
            return 1;
        }
    };
    let cancelled = || cancellation.is_some_and(|token| token.cancelled.load(Ordering::Acquire));
    let observed = runtime.block_on(await_lightwalletd_request_or_cancellation(
        cancellation,
        async {
            let public_source = status::gated(
                LightwalletdSource::new(
                    || async {
                        crate::wallet::sync_engine::open_background_direct_lwd_channel(
                            lightwalletd_url,
                        )
                        .await
                        .map_err(|_| StatusError::Unavailable)
                    },
                    &cancelled,
                ),
                gate.clone(),
            );
            let mut reader = StatusReader::new(
                StatusMode::PublicLightwalletd,
                public_source,
                DisabledSource,
            );
            reader
                .observe(StatusRequest {
                    txid: request.txid(),
                    coverage: zakura_pir_status::LocalCoverageContext::default(),
                })
                .await
                .map(TransactionObservation::from)
        },
    ));
    match observed {
        Err(()) => LIGHTWALLETD_RESULT_CANCELLED,
        Ok(Ok(transaction)) => {
            *output = transaction.into();
            0
        }
        // The gated source reports a withheld request as `Cancelled`: a
        // policy transition landed after authorization.
        Ok(Err(StatusError::Cancelled)) if !cancelled() && !gate.permits().unwrap_or(false) => {
            STATUS_RESULT_UNSUPPORTED
        }
        Ok(Err(StatusError::Cancelled)) => LIGHTWALLETD_RESULT_CANCELLED,
        // The gate could not read the policy, so it withheld the request.
        Ok(Err(StatusError::LocalStorage)) => STATUS_RESULT_INCONCLUSIVE,
        Ok(Err(error)) => {
            log::error!("ffi: observe lightwalletd transaction: {error}");
            1
        }
    }
}

/// Authorizes one public status lookup of `txid` for the wallet at `db_path`
/// under `policy`, returning the gate that re-checks it at dispatch.
///
/// `None` refuses it: the wallet withholds public lookups, or routes this
/// transaction's status privately. An error means the wallet could not be
/// read. Neither sends anything.
fn authorize_public_observation(
    db_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    txid: TxId,
) -> Result<Option<(TransparentLookupGate, PublicTransactionStatusRequest)>, SyncError> {
    // The opener adopts a durable `PrivateRequired`, and so does
    // `configure_db` after selecting the captured mode.
    let mut db = open_wallet_db_readonly_with_timeout(db_path, network, READ_DB_BUSY_TIMEOUT)
        .map_err(SyncError::db)?;
    policy.configure_db(&mut db);
    let lookups = policy.public_transparent_lookups(&db)?;
    if !lookups.is_allowed() {
        return Ok(None);
    }
    let TransactionStatusWork::Public(request) = db
        .transaction_status_work_for(txid)
        .map_err(|error| SyncError::db(format!("transaction_status_work_for: {error}")))?
    else {
        return Ok(None);
    };
    let gate = TransparentLookupGate::for_wallet(lookups, db_path, network)?;
    Ok(Some((gate, request)))
}

/// Test seam: runs a hook on the calling thread after a public observation is
/// authorized and before it is dispatched, so a test can land a policy
/// transition between the two.
#[cfg(test)]
mod test_hooks {
    use std::cell::RefCell;

    thread_local! {
        static AFTER_AUTHORIZATION: RefCell<Option<Box<dyn FnOnce()>>> = RefCell::new(None);
    }

    /// Runs `hook` after the next authorization on this thread.
    pub(super) fn after_authorization(hook: impl FnOnce() + 'static) {
        AFTER_AUTHORIZATION.with(|slot| *slot.borrow_mut() = Some(Box::new(hook)));
    }

    pub(super) fn authorized() {
        if let Some(hook) = AFTER_AUTHORIZATION.with(|slot| slot.borrow_mut().take()) {
            hook();
        }
    }
}

#[no_mangle]
pub extern "C" fn zcash_status_pir_is_enabled(
    network: *const c_char,
    private_preference: bool,
) -> bool {
    let Some(network) = (unsafe { c_str_to_str(network) }) else {
        return false;
    };
    let Some(network) = crate::wallet::network::WalletNetwork::from_str(network) else {
        return false;
    };
    crate::wallet::sync_engine::enhancement::EnhancementPolicy::for_preference(
        network,
        private_preference,
    )
    .status_mode()
        == zcash_client_backend::data_api::status::TransactionStatusMode::Private
}

/// Legacy ABI cannot carry network/policy/coverage context. It never performs a lookup.
#[no_mangle]
pub extern "C" fn zcash_status_pir_observe_transaction(
    _db_path: *const c_char,
    _transaction_id: *const u8,
    _transaction_id_len: usize,
    _output: *mut CLightwalletdTransactionObservation,
    _cancellation: *const CLightwalletdCancellation,
) -> i32 {
    STATUS_RESULT_UNSUPPORTED
}

/// Private status ABI with explicit policy and decision horizon. Inclusion evidence is read
/// from the wallet. Unsupported/inconclusive results leave `output` untouched.
#[no_mangle]
pub extern "C" fn zcash_status_pir_observe_transaction_v2(
    db_path: *const c_char,
    transaction_id: *const u8,
    transaction_id_len: usize,
    network: *const c_char,
    private_preference: bool,
    has_required_through: bool,
    required_through: u32,
    output: *mut CLightwalletdTransactionObservation,
    cancellation: *const CLightwalletdCancellation,
) -> i32 {
    let result = std::panic::catch_unwind(|| {
        let Some(db_path) = (unsafe { c_str_to_str(db_path) }) else {
            return 1;
        };
        if transaction_id.is_null() || transaction_id_len != 32 {
            return 1;
        }
        let Some(output) = (unsafe { output.as_mut() }) else {
            return 1;
        };
        use zcash_client_backend::data_api::status::{
            TransactionStatusMode, TransactionStatusRead,
        };
        let Some(network) = (unsafe { c_str_to_str(network) })
            .and_then(crate::wallet::network::WalletNetwork::from_str)
        else {
            return 1;
        };
        let policy = crate::wallet::sync_engine::enhancement::EnhancementPolicy::for_preference(
            network,
            private_preference,
        );
        if policy.status_mode() != TransactionStatusMode::Private {
            return STATUS_RESULT_UNSUPPORTED;
        }
        let txid = TxId::from_bytes(
            unsafe { std::slice::from_raw_parts(transaction_id, 32) }
                .try_into()
                .expect("validated txid length"),
        );
        let mut db = match crate::wallet::db::open_wallet_db_readonly_with_timeout(
            db_path,
            network,
            crate::wallet::db::READ_DB_BUSY_TIMEOUT,
        ) {
            Ok(db) => db,
            Err(_) => return 1,
        };
        policy.configure_db(&mut db);
        let work = match db.transaction_status_work_for(txid) {
            Ok(work) => work,
            Err(_) => return 1,
        };
        let runtime = match lightwalletd_runtime() {
            Ok(runtime) => runtime,
            Err(_) => return 1,
        };
        let cancellation = unsafe { cancellation.as_ref() };
        match runtime.block_on(await_lightwalletd_request_or_cancellation(
            cancellation,
            async {
                let cancelled =
                    || cancellation.is_some_and(|token| token.cancelled.load(Ordering::Acquire));
                let private_source =
                    crate::wallet::sync_engine::enhancement::status::PrivateStatusSource::new(
                        db_path, network, &cancelled, true,
                    );
                let mut reader =
                    crate::wallet::sync_engine::enhancement::status::RoutedStatusReader::new(
                        DisabledSource,
                        private_source,
                    );
                reader
                    .observe(work, has_required_through.then_some(required_through))
                    .await
                    .map(TransactionObservation::from)
            },
        )) {
            Err(()) | Ok(Err(zakura_transaction_status::StatusError::Cancelled)) => {
                LIGHTWALLETD_RESULT_CANCELLED
            }
            Ok(Ok(observation)) => {
                *output = observation.into();
                0
            }
            Ok(Err(zakura_transaction_status::StatusError::CoverageIncomplete)) => {
                STATUS_RESULT_INCONCLUSIVE
            }
            Ok(Err(error)) => {
                log::warn!("ffi: private status lookup: {error}");
                1
            }
        }
    });
    result.unwrap_or_else(|panic| {
        log_panic("private status", panic);
        2
    })
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
        let runtime = match lightwalletd_runtime() {
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
                let mut client = crate::wallet::sync_engine::open_background_direct_lwd_channel(
                    lightwalletd_url,
                )
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
    fn status_abi_policy_and_result_codes_are_unambiguous() {
        let main = std::ffi::CString::new("main").unwrap();
        let test = std::ffi::CString::new("test").unwrap();
        assert!(zcash_status_pir_is_enabled(main.as_ptr(), true));
        assert!(!zcash_status_pir_is_enabled(main.as_ptr(), false));
        assert!(!zcash_status_pir_is_enabled(test.as_ptr(), true));
        assert_ne!(STATUS_RESULT_INCONCLUSIVE, LIGHTWALLETD_RESULT_CANCELLED);
        assert_ne!(STATUS_RESULT_UNSUPPORTED, LIGHTWALLETD_RESULT_CANCELLED);
        assert_eq!(
            zcash_status_pir_observe_transaction(
                std::ptr::null(),
                std::ptr::null(),
                0,
                std::ptr::null_mut(),
                std::ptr::null()
            ),
            STATUS_RESULT_UNSUPPORTED
        );
        let path = std::ffi::CString::new("unused").unwrap();
        let mut output = CLightwalletdTransactionObservation {
            state: 99,
            mined_height: 99,
        };
        assert_eq!(
            zcash_status_pir_observe_transaction_v2(
                path.as_ptr(),
                [0u8; 32].as_ptr(),
                32,
                test.as_ptr(),
                true,
                true,
                10,
                &mut output,
                std::ptr::null()
            ),
            STATUS_RESULT_UNSUPPORTED
        );
        assert_eq!(output.state, 99);
    }

    #[test]
    fn transaction_observation_preserves_c_abi_states() {
        assert_eq!(
            CLightwalletdTransactionObservation::from(TransactionObservation::Mempool),
            CLightwalletdTransactionObservation {
                state: 1,
                mined_height: 0,
            }
        );
        assert_eq!(
            CLightwalletdTransactionObservation::from(TransactionObservation::Forked),
            CLightwalletdTransactionObservation {
                state: 3,
                mined_height: 0,
            }
        );
        assert_eq!(
            CLightwalletdTransactionObservation::from(TransactionObservation::Mined(
                zcash_protocol::consensus::BlockHeight::from_u32(501)
            )),
            CLightwalletdTransactionObservation {
                state: 2,
                mined_height: 501,
            }
        );
    }

    #[test]
    fn transaction_observation_represents_not_found_separately() {
        assert_eq!(
            CLightwalletdTransactionObservation::from(TransactionObservation::NotFound),
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

            let runtime = lightwalletd_runtime().unwrap();
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

    mod public_observe {
        use std::ffi::CString;

        use zcash_client_backend::data_api::transparent_ledger::{
            TransparentLedgerMode, TransparentLedgerWrite,
        };

        use super::*;
        use crate::wallet::db::{open_wallet_db_with_timeout, SYNC_DB_BUSY_TIMEOUT};
        use crate::wallet::sync_engine::test_lwd::CapturingLwd;

        const TXID: [u8; 32] = [7; 32];
        const UNTOUCHED: CLightwalletdTransactionObservation =
            CLightwalletdTransactionObservation {
                state: 99,
                mined_height: 99,
            };

        fn wallet(network: WalletNetwork) -> (tempfile::TempDir, String) {
            let dir = tempfile::tempdir().unwrap();
            let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
            let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
            let birthday = (network == WalletNetwork::Regtest).then_some(100);
            keys::init_db_and_create_account(&path, network, &seed, birthday, "ffi").unwrap();
            (dir, path)
        }

        /// Applies `mode` through another connection, as a flag build or a
        /// settings transition would.
        fn apply(path: &str, mode: TransparentLedgerMode) {
            open_wallet_db_with_timeout(path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
                .unwrap()
                .apply_transparent_policy(mode)
                .unwrap();
        }

        /// Calls the C entry point as Swift does; `None` passes a null pointer.
        fn observe_c(
            url: &str,
            db_path: Option<&str>,
            network: Option<&str>,
        ) -> (i32, CLightwalletdTransactionObservation) {
            let url = CString::new(url).unwrap();
            let db_path = db_path.map(|path| CString::new(path).unwrap());
            let network = network.map(|network| CString::new(network).unwrap());
            let mut output = UNTOUCHED;
            let code = zcash_lightwalletd_observe_transaction(
                url.as_ptr(),
                db_path
                    .as_ref()
                    .map_or(std::ptr::null(), |path| path.as_ptr()),
                network
                    .as_ref()
                    .map_or(std::ptr::null(), |network| network.as_ptr()),
                TXID.as_ptr(),
                TXID.len(),
                &mut output,
                std::ptr::null(),
            );
            (code, output)
        }

        /// [`observe_c`] on a blocking thread: the ABI runs its own runtime,
        /// and the test runtime keeps serving the capturing lightwalletd.
        async fn observe(
            url: &str,
            db_path: Option<&str>,
            network: Option<&str>,
        ) -> (i32, CLightwalletdTransactionObservation) {
            let url = url.to_owned();
            let db_path = db_path.map(str::to_owned);
            let network = network.map(str::to_owned);
            tokio::task::spawn_blocking(move || {
                observe_c(&url, db_path.as_deref(), network.as_deref())
            })
            .await
            .unwrap()
        }

        #[tokio::test]
        async fn public_observe_refuses_wallets_under_private_policy() {
            let lwd = CapturingLwd::start(Vec::new()).await;

            // A durable `PrivateRequired` withholds lookups whatever this build
            // selects: the handle adopts it.
            let (_dir, path) = wallet(WalletNetwork::Regtest);
            apply(&path, TransparentLedgerMode::PrivateRequired);
            assert_eq!(
                observe(&lwd.url, Some(&path), Some("regtest")).await,
                (STATUS_RESULT_UNSUPPORTED, UNTOUCHED)
            );

            // A private preference on mainnet routes the status work privately,
            // and the public ABI refuses it while lookups are still allowed.
            #[cfg(not(ironwood_masquerade))]
            {
                let (_main_dir, main_path) = wallet(WalletNetwork::Main);
                let url = lwd.url.clone();
                let refused = tokio::task::spawn_blocking(move || {
                    let mut output = UNTOUCHED;
                    let code = observe_public_transaction(
                        &url,
                        &main_path,
                        WalletNetwork::Main,
                        EnhancementPolicy::for_inputs(WalletNetwork::Main, true, false),
                        TxId::from_bytes(TXID),
                        &mut output,
                        None,
                    );
                    (code, output)
                })
                .await
                .unwrap();
                assert_eq!(refused, (STATUS_RESULT_UNSUPPORTED, UNTOUCHED));
            }

            assert!(
                lwd.requests().is_empty(),
                "a refusal sends nothing: {:?}",
                lwd.requests()
            );
        }

        #[tokio::test]
        async fn public_observe_serves_public_wallets_through_the_gate() {
            let lwd = CapturingLwd::start(Vec::new()).await;
            let (_dir, path) = wallet(WalletNetwork::Regtest);
            // The capturing lightwalletd answers every lookup "not found".
            let served = (0, CLightwalletdTransactionObservation::not_found());
            assert_eq!(
                observe(&lwd.url, Some(&path), Some("regtest")).await,
                served
            );
            assert_eq!(lwd.count("/GetTransaction"), 1);

            // A transition that lands after authorization, as a toggle racing
            // the call would, is caught as the request is dispatched. Even one
            // that keeps public authority revokes the captured generation.
            let (url, wallet_path) = (lwd.url.clone(), path.clone());
            let raced = tokio::task::spawn_blocking(move || {
                let transition_path = wallet_path.clone();
                test_hooks::after_authorization(move || {
                    apply(&transition_path, TransparentLedgerMode::PrivateShadow)
                });
                observe_c(&url, Some(&wallet_path), Some("regtest"))
            })
            .await
            .unwrap();
            assert_eq!(raced, (STATUS_RESULT_UNSUPPORTED, UNTOUCHED));
            assert_eq!(lwd.requests().len(), 1, "a withheld request is not sent");

            // A fresh call is authorized under the new generation.
            assert_eq!(
                observe(&lwd.url, Some(&path), Some("regtest")).await,
                served
            );
            assert_eq!(lwd.count("/GetTransaction"), 2);
        }

        #[tokio::test]
        async fn public_observe_needs_wallet_context() {
            let lwd = CapturingLwd::start(Vec::new()).await;
            let (_dir, path) = wallet(WalletNetwork::Regtest);
            for (db_path, network) in [
                (None, Some("regtest")),
                (Some(""), Some("regtest")),
                (Some(path.as_str()), None),
                (Some(path.as_str()), Some("")),
                (Some(path.as_str()), Some("mainnet")),
            ] {
                assert_eq!(
                    observe(&lwd.url, db_path, network).await,
                    (1, UNTOUCHED),
                    "db_path {db_path:?}, network {network:?}"
                );
            }
            assert!(lwd.requests().is_empty());
        }

        #[tokio::test]
        async fn an_unopenable_wallet_is_inconclusive() {
            let lwd = CapturingLwd::start(Vec::new()).await;
            let dir = tempfile::tempdir().unwrap();
            let missing = dir.path().join("missing.db");
            // A database without wallet tables fails its policy read.
            let not_a_wallet = dir.path().join("other.db");
            rusqlite::Connection::open(&not_a_wallet)
                .unwrap()
                .execute_batch("CREATE TABLE unrelated (id INTEGER)")
                .unwrap();

            for path in [&missing, &not_a_wallet] {
                assert_eq!(
                    observe(&lwd.url, path.to_str(), Some("regtest")).await,
                    (STATUS_RESULT_INCONCLUSIVE, UNTOUCHED),
                    "{}",
                    path.display()
                );
            }
            assert!(!missing.exists(), "a read-only open creates nothing");
            assert!(lwd.requests().is_empty());
        }
    }
}
