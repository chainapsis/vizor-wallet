//! The two sources loop 4 chooses between, once per run.
//!
//! - [`PirSource`] (`PrivateRequired`): txid display PIR at
//!   [`DEFAULT_MAINNET_ORIGIN`](crate::wallet::sync_engine::transparent_ledger::pir::DEFAULT_MAINNET_ORIGIN)`/v1/txid/`, mainnet only, through the
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
use std::time::{Duration, SystemTime};

use tokio::runtime::Handle;
use tonic::transport::Channel;
use zakura_pir_transparent::{
    deferral, display_facts, HttpExchange, TransportError, TxidDisplayService, TxidError,
    TxidLookup,
};
use zcash_client_backend::data_api::transparent_ledger::{
    TransparentDetailOutcome, TransparentDisplayFacts,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::{decode_enhancement_payload, RoutedExchange};
use crate::wallet::sync_engine::transparent_ledger::pir::{origin_for, origin_override};
use crate::wallet::sync_engine::{watch_for_exit, TransparentLookupGate};

#[cfg(test)]
pub(crate) use crate::wallet::sync_engine::transparent_ledger::pir::DEFAULT_MAINNET_ORIGIN;

/// Abandons a lookup or map fetch that has not returned, without an exit.
const LOOKUP_BACKSTOP: Duration = Duration::from_secs(60);
/// How long a run waits, once it exits or its budget is spent, for the
/// lookup or map fetch it cancelled to return before abandoning it.
pub(crate) const CANCEL_GRACE: Duration = Duration::from_secs(2);

/// What a lookup found.
#[derive(Debug)]
pub(crate) enum DetailAnswer {
    /// Display facts from the private publication, for the wallet to
    /// validate and store.
    Facts(Box<TransparentDisplayFacts>),
    /// The whole transaction, from lightwalletd.
    Raw {
        transaction: Box<Transaction>,
        mined_height: Option<BlockHeight>,
    },
}

/// Why a lookup found nothing to store. Carries no txid or service text.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DetailFailure {
    /// The lookup completed without storable facts; the wallet schedules the
    /// next attempt from `outcome`. `map_sha256` names the display map the
    /// lookup used.
    Deferred {
        outcome: TransparentDetailOutcome,
        map_sha256: Option<[u8; 32]>,
    },
    /// The source's authority is gone: a policy transition withheld the
    /// request. The run ends.
    Withheld,
    /// The run or its budget stopped the lookup.
    Cancelled,
}

/// One transaction's details, from whichever source the run chose.
pub(crate) trait DetailSource {
    /// Looks up `txid` mined at `mined_height`. Stops at `should_exit`.
    fn lookup(
        &mut self,
        txid: TxId,
        mined_height: BlockHeight,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> impl Future<Output = Result<DetailAnswer, DetailFailure>> + Send;

    /// The gate a public answer is committed under; `None` for the private
    /// source.
    fn gate(&self) -> Option<&TransparentLookupGate>;

    /// The display map the source last used, which releases work held by an
    /// older one.
    fn map_sha256(&self) -> Option<[u8; 32]>;

    /// Last attempted publication-map check, shared across sync runs.
    fn map_checked_at(&self) -> Option<SystemTime> {
        None
    }

    /// Records the attempt before awaiting it, including failed or cancelled checks.
    fn map_check_started(&mut self, _now: SystemTime) {}

    /// Fetches the source's display map afresh and returns its hash; `None`
    /// for a source without one, or when the fetch failed or was stopped.
    fn refresh_map(
        &mut self,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> impl Future<Output = Option<[u8; 32]>> + Send;
}

// ---- private ---------------------------------------------------------------

/// One service per origin for the whole process, so the init document, the
/// map, manifests, setups and the costly native profiles are derived once,
/// and the last map check is remembered across sync runs.
static SERVICES: LazyLock<Mutex<HashMap<String, Arc<TxidDisplayService>>>> =
    LazyLock::new(Default::default);

/// The process-wide service for `origin`.
pub(crate) fn service_for(origin: &str) -> Arc<TxidDisplayService> {
    SERVICES
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .entry(origin.to_owned())
        .or_default()
        .clone()
}

/// The txid display origin for `network`: the transparent PIR origin, with
/// the same debug-build override. `None` off mainnet.
pub(crate) fn txid_origin(network: WalletNetwork) -> Option<String> {
    origin_for(network, origin_override(|name| std::env::var(name).ok()))
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
        let origin = txid_origin(network)?;
        // A test's fake service gets a service of its own, shared while its
        // seam is set.
        #[cfg(test)]
        let seam = test_seam::get(db_path);
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
    ) -> Result<DetailAnswer, DetailFailure> {
        #[cfg(test)]
        if self.observer.is_none() {
            // No test reaches the live service by accident.
            return Err(DetailFailure::Deferred {
                outcome: TransparentDetailOutcome::Unavailable { retry_after: None },
                map_sha256: None,
            });
        }
        let request = self.request(*txid.as_ref(), u64::from(u32::from(mined_height)));
        let (found, map) = run_blocking(request, should_exit).await?;
        match found {
            Ok(TxidLookup::Found { entry, provenance }) => {
                match display_facts(txid, &entry, &provenance, mined_height) {
                    Ok(facts) => Ok(DetailAnswer::Facts(Box::new(facts))),
                    Err(_) => Err(DetailFailure::Deferred {
                        outcome: TransparentDetailOutcome::Protocol,
                        map_sha256: map,
                    }),
                }
            }
            Err(TxidError::Cancelled) => Err(DetailFailure::Cancelled),
            // The transport reports cancellation as a transport failure.
            Err(TxidError::Transport(_)) if should_exit() => Err(DetailFailure::Cancelled),
            lookup => Err(DetailFailure::Deferred {
                outcome: deferral(&lookup)
                    .unwrap_or(TransparentDetailOutcome::Unavailable { retry_after: None }),
                map_sha256: map,
            }),
        }
    }

    fn gate(&self) -> Option<&TransparentLookupGate> {
        None
    }

    /// Read without waiting, even while a request (perhaps one abandoned at
    /// its backstop) holds the client.
    fn map_sha256(&self) -> Option<[u8; 32]> {
        self.service.map_sha256()
    }

    fn map_checked_at(&self) -> Option<SystemTime> {
        self.service.map_checked_at()
    }

    fn map_check_started(&mut self, now: SystemTime) {
        self.service.map_check_started(now);
    }

    async fn refresh_map(&mut self, should_exit: &(dyn Fn() -> bool + Sync)) -> Option<[u8; 32]> {
        #[cfg(test)]
        self.observer.as_ref()?;
        let request = self.request([0; 32], 0);
        run_blocking_with(request, should_exit, BlockingLookup::refresh_map)
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

/// A lookup's result with the map digest the service holds afterwards.
pub(crate) type Looked = (Result<TxidLookup, TxidError>, Option<[u8; 32]>);

impl BlockingLookup {
    /// Runs the lookup on the calling thread, which must not be a runtime
    /// worker.
    pub(crate) fn run(self) -> Looked {
        let found = self.with_exchange(|service, exchange, exit| {
            service.lookup(&exchange, self.txid, self.mined_height, exit)
        });
        (found, self.service.map_sha256())
    }

    /// Fetches the display map now; the hash, or `None` on any failure.
    pub(crate) fn refresh_map(self) -> Option<[u8; 32]> {
        self.with_exchange(|service, exchange, exit| service.refresh_map(&exchange, exit))
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

/// Runs `request` off the runtime until it returns or `should_exit` holds;
/// see [`run_blocking_with`] for what happens to a request that outlives it.
async fn run_blocking(
    request: BlockingLookup,
    should_exit: &(dyn Fn() -> bool + Sync),
) -> Result<Looked, DetailFailure> {
    run_blocking_with(request, should_exit, BlockingLookup::run).await
}

/// [`run_blocking`] for any blocking call on the request.
///
/// The call runs on a thread of its own, with a runtime of its own for its
/// I/O, never the caller's runtime or its blocking pool: a runtime's
/// shutdown waits for every blocking-pool task, so a call that ignored its
/// cancellation would hold the sync that owns the runtime. The request's
/// `handle` is replaced by that runtime's. On
/// exit the call's cancellation is set and the call gets [`CANCEL_GRACE`] to
/// return; a call that does not is abandoned, still running, and nothing it
/// returns later is read, so it stores nothing. It may keep the client until
/// it returns; later requests wait for it only while they are wanted.
async fn run_blocking_with<T: Send + 'static>(
    request: BlockingLookup,
    should_exit: &(dyn Fn() -> bool + Sync),
    call: fn(BlockingLookup) -> T,
) -> Result<T, DetailFailure> {
    let cancel = request.cancel.clone();
    let _cancel_on_drop = CancelOnDrop(cancel.clone());
    let (done, mut answer) = tokio::sync::oneshot::channel();
    let spawned = std::thread::Builder::new()
        .name("txid-display".to_owned())
        .spawn(move || {
            // The request's I/O (DNS lookups on its blocking pool among it)
            // runs on a runtime of its own, never the sync's: an abandoned
            // request must not hold the sync's runtime shutdown.
            let Ok(io) = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(1)
                .thread_name("txid-display-io")
                .enable_all()
                .build()
            else {
                return;
            };
            let mut request = request;
            request.handle = io.handle().clone();
            let _ = done.send(call(request));
            io.shutdown_background();
        });
    if spawned.is_err() {
        return Err(DetailFailure::Deferred {
            outcome: TransparentDetailOutcome::Unavailable { retry_after: None },
            map_sha256: None,
        });
    }
    let joined = tokio::select! {
        biased;
        _ = watch_for_exit(&should_exit) => {
            cancel.store(true, Ordering::SeqCst);
            tokio::time::timeout(CANCEL_GRACE, &mut answer).await
        }
        joined = tokio::time::timeout(LOOKUP_BACKSTOP, &mut answer) => joined,
    };
    if cancel.load(Ordering::SeqCst) || should_exit() {
        return Err(DetailFailure::Cancelled);
    }
    match joined {
        Ok(Ok(result)) => Ok(result),
        // The call panicked, or passed its backstop.
        Ok(Err(_)) | Err(_) => {
            cancel.store(true, Ordering::SeqCst);
            Err(DetailFailure::Deferred {
                outcome: TransparentDetailOutcome::Protocol,
                map_sha256: None,
            })
        }
    }
}

/// Sets a lookup's cancellation flag when dropped.
struct CancelOnDrop(Arc<AtomicBool>);

impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
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
    ) -> Result<DetailAnswer, DetailFailure> {
        if should_exit() {
            return Err(DetailFailure::Cancelled);
        }
        let response = tokio::select! {
            biased;
            _ = watch_for_exit(&should_exit) => return Err(DetailFailure::Cancelled),
            response = self.gate.transaction(&mut self.client, txid) => response,
        };
        if should_exit() {
            return Err(DetailFailure::Cancelled);
        }
        let unavailable = Err(DetailFailure::Deferred {
            outcome: TransparentDetailOutcome::Unavailable { retry_after: None },
            map_sha256: None,
        });
        match response {
            Err(_) => unavailable,
            Ok(None) => Err(DetailFailure::Withheld),
            // Lightwalletd does not have this transaction: an answer about it,
            // not an outage, so the run's remaining lookups proceed.
            Ok(Some(Err(status))) if status.code() == tonic::Code::NotFound => {
                Err(DetailFailure::Deferred {
                    outcome: TransparentDetailOutcome::Absent,
                    map_sha256: None,
                })
            }
            Ok(Some(Err(_))) => unavailable,
            Ok(Some(Ok(raw))) => match decode_enhancement_payload(&raw, txid) {
                Ok((transaction, mined_height)) => Ok(DetailAnswer::Raw {
                    transaction: Box::new(transaction),
                    mined_height,
                }),
                Err(_) => Err(DetailFailure::Deferred {
                    outcome: TransparentDetailOutcome::Protocol,
                    map_sha256: None,
                }),
            },
        }
    }

    fn gate(&self) -> Option<&TransparentLookupGate> {
        Some(&self.gate)
    }

    fn map_sha256(&self) -> Option<[u8; 32]> {
        None
    }

    async fn refresh_map(&mut self, _should_exit: &(dyn Fn() -> bool + Sync)) -> Option<[u8; 32]> {
        None
    }
}

/// Test seam: the request observer the private source of one wallet file
/// sends through, standing in for the network, and the service its sources
/// share, standing in for the process-wide service of the origin. A source
/// without a seam defers every lookup as unavailable without a request.
#[cfg(test)]
pub(crate) mod test_seam {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex, OnceLock, PoisonError};

    use zakura_pir_transparent::TxidDisplayService;

    use crate::wallet::sync_engine::enhancement::RequestObserver;

    /// What the private sources of one wallet file are built with.
    #[derive(Clone)]
    pub(crate) struct Seam {
        pub(crate) observer: RequestObserver,
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

    /// Private sources built for `db_path` send through `observer`, sharing
    /// one new service, until the guard drops.
    pub(crate) fn set(db_path: &str, observer: RequestObserver) -> SeamGuard {
        seams()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(
                db_path.to_owned(),
                Seam {
                    observer,
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
