//! The two sources loop 4 chooses between, once per run.
//!
//! - [`PirSource`] (`PrivateRequired`): txid display PIR at
//!   the selected wallet PIR server's `/transparent/v1/txid/`, mainnet only, through the
//!   process's [`TxidDisplayService`] for the origin over a [`RoutedExchange`].
//!   It holds no lightwalletd client, so it cannot make a public request.
//! - [`GateSource`] (every other policy): lightwalletd `GetTransaction`
//!   through the [`TransparentLookupGate`], which re-checks the durable
//!   policy before each request.
//!
//! Both answer one transaction at a time and carry no txid into any error or
//! log line.

use std::collections::HashMap;
use std::future::Future;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex, PoisonError};

use tokio::runtime::Handle;
use tonic::transport::Channel;
use zakura_pir_client::transparent::{
    DetailAnswer, DisplayLookup, HttpExchange, MapCheck, MapChecked, TransportError,
    TxidDisplayService, TxidError,
};
use zcash_client_backend::data_api::transparent_ledger::TransparentDetailOutcome;
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BlockHeight;

#[cfg(doc)]
use crate::wallet::bounded_runtime::CANCEL_GRACE;
use crate::wallet::bounded_runtime::{run_detached, Detached};
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::{decode_enhancement_payload, RoutedExchange};
use crate::wallet::sync_engine::transparent_ledger::pir::{origin_for, selected_origin};
use crate::wallet::sync_engine::{watch_for_exit, TransparentLookupGate};

#[cfg(test)]
pub(crate) use crate::wallet::sync_engine::transparent_ledger::pir::TEST_ORIGIN;

/// A transaction lightwalletd returned, decoded.
#[derive(Debug)]
pub(crate) struct PublicTransaction {
    pub(crate) transaction: Box<Transaction>,
    pub(crate) mined_height: Option<BlockHeight>,
}

/// What a lookup found, for the run to record: the private service's result,
/// a public transaction or the outcome to defer it with, or a cancellation
/// (by the sync's exit or the run's budget), which records nothing.
pub(crate) type Answer = DetailAnswer<PublicTransaction>;

/// The source's authority is gone: a policy transition withheld the request.
/// The run ends.
#[derive(Debug)]
pub(crate) struct Withheld;

/// One transaction's details, from whichever source the run chose.
pub(crate) trait DetailSource {
    /// Looks up `txid` mined at `mined_height`. Stops at `should_exit`,
    /// answering [`DetailAnswer::Cancelled`].
    fn lookup(
        &mut self,
        txid: TxId,
        mined_height: BlockHeight,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> impl Future<Output = Result<Answer, Withheld>> + Send;

    /// The gate a public answer is committed under; `None` for the private
    /// source.
    fn gate(&self) -> Option<&TransparentLookupGate>;

    /// The display service the run lists its work under and checks the map
    /// with; `None` for the public source, which never checks a map.
    fn service(&self) -> Option<Arc<TxidDisplayService>>;

    /// Fetches the display map `check` asks for. `None` when the fetch was
    /// stopped or could not start: the run lists nothing more.
    fn check_map(
        &mut self,
        check: MapCheck,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> impl Future<Output = Option<MapChecked>> + Send;
}

// ---- private ---------------------------------------------------------------

/// One service per origin for the whole process, so the init document, the
/// map, manifests, setups and the costly native profiles are derived once,
/// and the last map check is remembered across sync runs.
static SERVICES: LazyLock<Mutex<HashMap<String, Arc<TxidDisplayService>>>> =
    LazyLock::new(Default::default);

/// Drops every service but the one for `keep`, so nothing derived from a
/// previously selected server outlives the switch.
pub(crate) fn retain_service_for(keep: Option<&str>) {
    SERVICES
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .retain(|origin, _| Some(origin.as_str()) == keep);
}

/// The process-wide service for `origin`.
pub(crate) fn service_for(origin: &str) -> Arc<TxidDisplayService> {
    SERVICES
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .entry(origin.to_owned())
        .or_default()
        .clone()
}

/// The txid display origin for `network`: the selected wallet PIR server.
/// `None` off mainnet or with no server selected.
pub(crate) fn txid_origin(network: WalletNetwork) -> Option<String> {
    origin_for(network, selected_origin())
}

/// Private lookups through txid display PIR.
pub(crate) struct PirSource {
    origin: String,
    service: Arc<TxidDisplayService>,
    #[cfg(test)]
    observer: Option<crate::wallet::sync_engine::enhancement::RequestObserver>,
}

impl PirSource {
    /// The source for the wallet at `db_path`; `None` off mainnet.
    pub(crate) fn new(db_path: &str, network: WalletNetwork) -> Option<Self> {
        // A test names its origin through its seam, which replaces the
        // selection; without one it sees what a release build sees.
        #[cfg(test)]
        let seam = test_seam::get(db_path);
        #[cfg(test)]
        let origin = match &seam {
            Some(seam) => origin_for(network, seam.origin.clone()),
            None => txid_origin(network),
        }?;
        #[cfg(not(test))]
        let origin = txid_origin(network)?;
        // A test's fake service gets a service of its own, shared while its
        // seam is set.
        #[cfg(test)]
        let service = seam
            .as_ref()
            .map_or_else(Default::default, |seam| seam.service.clone());
        #[cfg(not(test))]
        let service = service_for(&origin);
        let _ = db_path;
        Some(Self {
            origin,
            service,
            #[cfg(test)]
            observer: seam.map(|seam| seam.observer),
        })
    }

    /// A blocking request for `txid` mined at `mined_height`.
    fn request(&self, txid: [u8; 32], mined_height: u64) -> BlockingLookup {
        BlockingLookup {
            origin: self.origin.clone(),
            service: self.service.clone(),
            txid,
            mined_height,
            handle: Handle::current(),
            cancel: Arc::new(AtomicBool::new(false)),
            #[cfg(test)]
            observer: self.observer.clone(),
        }
    }
}

impl DetailSource for PirSource {
    async fn lookup(
        &mut self,
        txid: TxId,
        mined_height: BlockHeight,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Result<Answer, Withheld> {
        #[cfg(test)]
        if self.observer.is_none() {
            // No test reaches the live service by accident.
            return Ok(DetailAnswer::Display(Box::new(unanswered(
                TxidError::Unavailable { retry_after: None },
            ))));
        }
        let request = self.request(*txid.as_ref(), u64::from(u32::from(mined_height)));
        let looked = run_blocking(request, should_exit, BlockingLookup::run).await;
        Ok(match looked {
            Ok(found) => DetailAnswer::Display(Box::new(found)),
            Err(Unanswered::Cancelled) => DetailAnswer::Cancelled,
            Err(Unanswered::NotStarted) => {
                DetailAnswer::Display(Box::new(unanswered(TxidError::Unavailable {
                    retry_after: None,
                })))
            }
            // The lookup panicked: an unusable answer.
            Err(Unanswered::Panicked) => {
                DetailAnswer::Public(Err(TransparentDetailOutcome::Protocol))
            }
        })
    }

    fn gate(&self) -> Option<&TransparentLookupGate> {
        None
    }

    fn service(&self) -> Option<Arc<TxidDisplayService>> {
        Some(self.service.clone())
    }

    async fn check_map(
        &mut self,
        check: MapCheck,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Option<MapChecked> {
        #[cfg(test)]
        self.observer.as_ref()?;
        let request = self.request([0; 32], 0);
        run_blocking(request, should_exit, move |request| {
            request.check_map(check)
        })
        .await
        .ok()
        .flatten()
    }
}

/// Everything one private lookup needs on its blocking thread.
pub(crate) struct BlockingLookup {
    pub(crate) origin: String,
    pub(crate) service: Arc<TxidDisplayService>,
    /// Protocol byte order.
    pub(crate) txid: [u8; 32],
    pub(crate) mined_height: u64,
    pub(crate) handle: Handle,
    pub(crate) cancel: Arc<AtomicBool>,
    /// Answers in place of the network; `None` reaches it.
    #[cfg(test)]
    pub(crate) observer: Option<crate::wallet::sync_engine::enhancement::RequestObserver>,
}

impl BlockingLookup {
    /// Runs the lookup on the calling thread, which must not be a runtime
    /// worker.
    pub(crate) fn run(self) -> DisplayLookup {
        self.with_exchange(|service, exchange, exit| {
            Ok(service.lookup(&exchange, self.txid, self.mined_height, exit))
        })
        .unwrap_or_else(unanswered)
    }

    /// Fetches the display map `check` asks for; `None` when the origin is
    /// refused.
    fn check_map(self, check: MapCheck) -> Option<MapChecked> {
        self.with_exchange(|service, exchange, exit| Ok(check.fetch(service, &exchange, exit)))
            .ok()
    }

    /// Runs `call` with the service and an exchange bound to this request's
    /// cancellation.
    fn with_exchange<T>(
        &self,
        call: impl FnOnce(
            &TxidDisplayService,
            &dyn HttpExchange,
            &dyn Fn() -> bool,
        ) -> Result<T, TxidError>,
    ) -> Result<T, TxidError> {
        let _runtime = self.handle.enter();
        let exit = || self.cancel.load(Ordering::SeqCst);
        let Ok(exchange) = RoutedExchange::txid(&self.origin, &exit, self.handle.clone()) else {
            return Err(TxidError::Transport(TransportError(
                "origin refused".to_owned(),
            )));
        };
        #[cfg(test)]
        let exchange = match self.observer.clone() {
            Some(observer) => exchange.with_observer(observer),
            None => exchange,
        };
        call(&self.service, &exchange, &exit)
    }
}

/// A lookup that failed before the service answered, so under no map.
fn unanswered(error: TxidError) -> DisplayLookup {
    DisplayLookup {
        found: Err(error),
        map_sha256: None,
    }
}

/// Why a blocking call on a request returned nothing.
enum Unanswered {
    /// The sync's exit or the run's budget stopped it, including a failure
    /// the cancellation itself caused.
    Cancelled,
    /// Its thread could not be started.
    NotStarted,
    /// It panicked.
    Panicked,
}

/// Runs `call` on `request` off the runtime until it returns or
/// `should_exit` holds.
///
/// The call runs through [`run_detached`], with the request's `handle`
/// replaced by the call's own runtime. `should_exit` (the sync's exit or the
/// run's budget) cancels it, and it gets [`CANCEL_GRACE`] to return; a call
/// that does not is abandoned, still running, and nothing it returns later is
/// read, so it stores nothing. A call that returns once cancelled is
/// cancelled too: its transport reports the cancellation as a failure. It may
/// keep the client until it returns; later requests wait for it only while
/// they are wanted.
async fn run_blocking<T: Send + 'static>(
    request: BlockingLookup,
    should_exit: &(dyn Fn() -> bool + Sync),
    call: impl FnOnce(BlockingLookup) -> T + Send + 'static,
) -> Result<T, Unanswered> {
    let cancel = request.cancel.clone();
    let ran = run_detached("txid-display", cancel.clone(), should_exit, move |io| {
        let mut request = request;
        request.handle = io;
        call(request)
    })
    .await;
    if matches!(ran, Detached::NotStarted) {
        return Err(Unanswered::NotStarted);
    }
    if cancel.load(Ordering::SeqCst) || should_exit() {
        return Err(Unanswered::Cancelled);
    }
    match ran {
        Detached::Returned(result) => Ok(result),
        _ => Err(Unanswered::Panicked),
    }
}

// ---- public ------------------------------------------------------------------

/// Public lookups through the transparent lookup gate.
pub(crate) struct GateSource {
    client: CompactTxStreamerClient<Channel>,
    gate: TransparentLookupGate,
}

impl GateSource {
    pub(crate) fn new(
        client: CompactTxStreamerClient<Channel>,
        gate: TransparentLookupGate,
    ) -> Self {
        Self { client, gate }
    }
}

impl DetailSource for GateSource {
    async fn lookup(
        &mut self,
        txid: TxId,
        _mined_height: BlockHeight,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Result<Answer, Withheld> {
        if should_exit() {
            return Ok(DetailAnswer::Cancelled);
        }
        let response = tokio::select! {
            biased;
            _ = watch_for_exit(&should_exit) => return Ok(DetailAnswer::Cancelled),
            response = self.gate.transaction(&mut self.client, txid) => response,
        };
        if should_exit() {
            return Ok(DetailAnswer::Cancelled);
        }
        let failed = |outcome| Ok(DetailAnswer::Public(Err(outcome)));
        let unavailable = TransparentDetailOutcome::Unavailable { retry_after: None };
        match response {
            Err(_) => failed(unavailable),
            Ok(None) => Err(Withheld),
            // Lightwalletd does not have this transaction: an answer about it,
            // not an outage, so the run's remaining lookups proceed.
            Ok(Some(Err(status))) if status.code() == tonic::Code::NotFound => {
                failed(TransparentDetailOutcome::Absent)
            }
            Ok(Some(Err(_))) => failed(unavailable),
            Ok(Some(Ok(raw))) => match decode_enhancement_payload(&raw, txid) {
                Ok((transaction, mined_height)) => {
                    Ok(DetailAnswer::Public(Ok(PublicTransaction {
                        transaction: Box::new(transaction),
                        mined_height,
                    })))
                }
                Err(_) => failed(TransparentDetailOutcome::Protocol),
            },
        }
    }

    fn gate(&self) -> Option<&TransparentLookupGate> {
        Some(&self.gate)
    }

    fn service(&self) -> Option<Arc<TxidDisplayService>> {
        None
    }

    /// Never asked: a run without a service checks no map.
    async fn check_map(
        &mut self,
        _check: MapCheck,
        _should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Option<MapChecked> {
        None
    }
}

/// Test seam: the request observer the private source of one wallet file
/// sends through, standing in for the network, and the service its sources
/// share, standing in for the process-wide service of the origin. Without a
/// seam a source takes the selected server, as in a release build, so with
/// none selected there is no private source.
#[cfg(test)]
pub(crate) mod test_seam {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex, OnceLock, PoisonError};

    use zakura_pir_client::transparent::TxidDisplayService;

    use crate::wallet::sync_engine::enhancement::RequestObserver;

    /// What the private sources of one wallet file are built with.
    #[derive(Clone)]
    pub(crate) struct Seam {
        pub(crate) observer: RequestObserver,
        /// Stands in for the selected server.
        pub(crate) origin: Option<String>,
        /// Shared by every source built while the seam is set, as sources
        /// share the process-wide service; a new seam is a restart.
        pub(crate) service: Arc<TxidDisplayService>,
    }

    fn seams() -> &'static Mutex<HashMap<String, Seam>> {
        static SEAMS: OnceLock<Mutex<HashMap<String, Seam>>> = OnceLock::new();
        SEAMS.get_or_init(Default::default)
    }

    pub(super) fn get(db_path: &str) -> Option<Seam> {
        seams()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(db_path)
            .cloned()
    }

    /// Private sources built for `db_path` look up at [`TEST_ORIGIN`]
    /// through `observer`, sharing one new service, until the guard drops.
    ///
    /// [`TEST_ORIGIN`]: super::TEST_ORIGIN
    pub(crate) fn set(db_path: &str, observer: RequestObserver) -> SeamGuard {
        set_origin(db_path, Some(super::TEST_ORIGIN.to_owned()), observer)
    }

    /// Like [`set`], with no server selected.
    pub(crate) fn set_unserved(db_path: &str, observer: RequestObserver) -> SeamGuard {
        set_origin(db_path, None, observer)
    }

    fn set_origin(db_path: &str, origin: Option<String>, observer: RequestObserver) -> SeamGuard {
        seams()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(
                db_path.to_owned(),
                Seam {
                    observer,
                    origin,
                    service: Default::default(),
                },
            );
        SeamGuard(db_path.to_owned())
    }

    /// The service the sources of `db_path` share while its seam is set.
    pub(crate) fn service(db_path: &str) -> Arc<TxidDisplayService> {
        get(db_path).expect("a seam is set").service
    }

    pub(crate) struct SeamGuard(String);

    impl Drop for SeamGuard {
        fn drop(&mut self) {
            seams()
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .remove(&self.0);
        }
    }
}
