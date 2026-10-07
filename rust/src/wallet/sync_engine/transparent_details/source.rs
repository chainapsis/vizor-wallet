//! The two sources loop 4 chooses between, once per run.
//!
//! - [`PirSource`] (`PrivateRequired`): txid display PIR at
//!   [`DEFAULT_MAINNET_ORIGIN`]`/v1/txid/`, mainnet only, through wallet-pir's
//!   client over [`TxidPirHttp`]. It holds no lightwalletd client, so it
//!   cannot make a public request.
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
use std::time::Duration;

use tokio::runtime::Handle;
use tonic::transport::Channel;
use zakura_pir_transparent::{
    deferral, display_facts, map_sha256, TxidDisplayClient, TxidError, TxidLookup,
};
use zcash_client_backend::data_api::transparent_ledger::{
    TransparentDetailOutcome, TransparentDisplayFacts,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::{decode_enhancement_payload, TxidPirHttp};
use crate::wallet::sync_engine::transparent_ledger::pir::{origin_for, origin_override};
use crate::wallet::sync_engine::{watch_for_exit, TransparentLookupGate};

pub(crate) use crate::wallet::sync_engine::transparent_ledger::pir::DEFAULT_MAINNET_ORIGIN;

/// Abandons a lookup whose blocking task ignores its exit signal.
const LOOKUP_BACKSTOP: Duration = Duration::from_secs(60);
/// The age at which a run fetches the display map again before it reads its
/// work, so that work held for an older map learns of newer coverage.
pub(crate) const MAP_REFRESH_AGE: Duration = Duration::from_secs(10 * 60);

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
}

// ---- private ---------------------------------------------------------------

/// One client per origin for the whole process, so the init document, the
/// map, manifests, setups and the costly native profiles are derived once.
static CLIENTS: LazyLock<Mutex<HashMap<String, Arc<Mutex<TxidDisplayClient>>>>> =
    LazyLock::new(Default::default);

/// The process-wide client for `origin`.
pub(crate) fn client_for(origin: &str) -> Arc<Mutex<TxidDisplayClient>> {
    CLIENTS
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .entry(origin.to_owned())
        .or_insert_with(|| Arc::new(Mutex::new(TxidDisplayClient::new())))
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
    client: Arc<Mutex<TxidDisplayClient>>,
    #[cfg(test)]
    observer: Option<crate::wallet::sync_engine::enhancement::RequestObserver>,
}

impl PirSource {
    /// The source for the wallet at `db_path`; `None` off mainnet.
    pub(crate) fn new(db_path: &str, network: WalletNetwork) -> Option<Self> {
        let origin = txid_origin(network)?;
        // A test's fake service gets a client of its own, shared while its
        // seam is set.
        #[cfg(test)]
        let seam = test_seam::get(db_path);
        #[cfg(test)]
        let client = seam.as_ref().map_or_else(
            || Arc::new(Mutex::new(TxidDisplayClient::new())),
            |seam| seam.client.clone(),
        );
        #[cfg(not(test))]
        let client = client_for(&origin);
        let _ = db_path;
        Some(Self {
            origin,
            client,
            #[cfg(test)]
            observer: seam.map(|seam| seam.observer),
        })
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
        let Some(observer) = self.observer.clone() else {
            // No test reaches the live service by accident.
            return Err(DetailFailure::Deferred {
                outcome: TransparentDetailOutcome::Unavailable { retry_after: None },
                map_sha256: None,
            });
        };
        let request = BlockingLookup {
            origin: self.origin.clone(),
            client: self.client.clone(),
            txid: *txid.as_ref(),
            mined_height: u64::from(u32::from(mined_height)),
            handle: Handle::current(),
            cancel: Arc::new(AtomicBool::new(false)),
            #[cfg(test)]
            observer: Some(observer),
        };
        let (found, map) = run_blocking(request, should_exit).await?;
        match found {
            Ok(TxidLookup::Found { record, provenance }) => {
                match display_facts(&record, &provenance, mined_height) {
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

    fn map_sha256(&self) -> Option<[u8; 32]> {
        self.client
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .map_sha256()
            .and_then(map_sha256)
    }
}

/// Everything one private lookup needs on its blocking thread.
pub(crate) struct BlockingLookup {
    pub(crate) origin: String,
    pub(crate) client: Arc<Mutex<TxidDisplayClient>>,
    /// Protocol byte order.
    pub(crate) txid: [u8; 32],
    pub(crate) mined_height: u64,
    pub(crate) handle: Handle,
    pub(crate) cancel: Arc<AtomicBool>,
    /// Answers in place of the network; `None` reaches it.
    #[cfg(test)]
    pub(crate) observer: Option<crate::wallet::sync_engine::enhancement::RequestObserver>,
}

/// A lookup's result with the map digest the client holds afterwards.
pub(crate) type Looked = (Result<TxidLookup, TxidError>, Option<[u8; 32]>);

impl BlockingLookup {
    /// Runs the lookup on the calling thread, which must not be a runtime
    /// worker.
    pub(crate) fn run(self) -> Looked {
        let _runtime = self.handle.enter();
        let cancel = self.cancel.clone();
        let exit = move || cancel.load(Ordering::SeqCst);
        let http = match TxidPirHttp::new(&self.origin, &exit, self.handle.clone()) {
            Ok(http) => http,
            Err(_) => {
                return (
                    Err(TxidError::Transport(zakura_pir_transparent::TransportError(
                        "origin refused".to_owned(),
                    ))),
                    None,
                )
            }
        };
        #[cfg(test)]
        let http = match self.observer.clone() {
            Some(observer) => http.with_observer(observer),
            None => http,
        };
        let mut http = http;
        let mut client = self.client.lock().unwrap_or_else(PoisonError::into_inner);
        let found = client.lookup(&mut http, self.txid, self.mined_height, &exit);
        let map = client.map_sha256().and_then(map_sha256);
        (found, map)
    }
}

/// Runs `request` on a blocking thread until it returns or `should_exit`
/// holds; on exit, signals it and waits for it, so nothing outlives the call.
async fn run_blocking(
    request: BlockingLookup,
    should_exit: &(dyn Fn() -> bool + Sync),
) -> Result<Looked, DetailFailure> {
    let cancel = request.cancel.clone();
    let _cancel_on_drop = CancelOnDrop(cancel.clone());
    let mut task = tokio::task::spawn_blocking(move || request.run());
    let joined = tokio::select! {
        biased;
        _ = watch_for_exit(&should_exit) => {
            cancel.store(true, Ordering::SeqCst);
            tokio::time::timeout(LOOKUP_BACKSTOP, &mut task).await
        }
        joined = tokio::time::timeout(LOOKUP_BACKSTOP, &mut task) => joined,
    };
    if cancel.load(Ordering::SeqCst) || should_exit() {
        return Err(DetailFailure::Cancelled);
    }
    match joined {
        Ok(Ok(looked)) => Ok(looked),
        // The lookup panicked, or passed its backstop.
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
    pub(crate) fn new(client: CompactTxStreamerClient<Channel>, gate: TransparentLookupGate) -> Self {
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
}

/// Test seam: the request observer the private source of one wallet file
/// sends through, standing in for the network, and the client its sources
/// share, standing in for the process-wide client of the origin. A source
/// without a seam defers every lookup as unavailable without a request.
#[cfg(test)]
pub(crate) mod test_seam {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex, OnceLock, PoisonError};
    use std::time::Duration;

    use zakura_pir_transparent::TxidDisplayClient;

    use crate::wallet::sync_engine::enhancement::RequestObserver;

    /// What the private sources of one wallet file are built with.
    #[derive(Clone)]
    pub(crate) struct Seam {
        pub(crate) observer: RequestObserver,
        /// Shared by every source built while the seam is set, as sources
        /// share the process-wide client; a new seam is a restart.
        pub(crate) client: Arc<Mutex<TxidDisplayClient>>,
        /// The age at which a source fetches the map again.
        pub(crate) map_refresh_age: Duration,
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

    /// Private sources built for `db_path` send through `observer`, with one
    /// new client and the production map refresh age, until the guard drops.
    pub(crate) fn set(db_path: &str, observer: RequestObserver) -> SeamGuard {
        set_with_refresh_age(db_path, observer, super::MAP_REFRESH_AGE)
    }

    /// [`set`], with the map fetched again once it is `map_refresh_age` old.
    pub(crate) fn set_with_refresh_age(
        db_path: &str,
        observer: RequestObserver,
        map_refresh_age: Duration,
    ) -> SeamGuard {
        seams().lock().unwrap_or_else(PoisonError::into_inner).insert(
            db_path.to_owned(),
            Seam {
                observer,
                client: Arc::new(Mutex::new(TxidDisplayClient::new())),
                map_refresh_age,
            },
        );
        SeamGuard(db_path.to_owned())
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
