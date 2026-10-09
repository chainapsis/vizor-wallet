//! Transparent PIR as the private recovery source .
//!
//! [`TransparentPirSource`] recovers one account per pass from the transparent
//! PIR service through the reference adapter `zakura_pir_transparent`, over the
//! wallet's routed HTTPS transport. It answers for mainnet only, from
//! [`DEFAULT_MAINNET_ORIGIN`]; debug builds honor `VIZOR_TRANSPARENT_PIR_URL`.
//! Every commit it returns comes from that origin, which is what lets the
//! coordinator qualify it (the trusted-indexer decision).
//!
//! Each account has its own companion database in the wallet's
//! [`CompanionDir`], `{db}.tpir`. A companion holds the adapter's retrieval
//! cache and revision catalog, never wallet balances. Revision identities are
//! derived from the publication, but the catalog also records what was
//! exported and lets the adapter detect a contradictory publication. The
//! library names companions, binds each to its origin and schema, prunes those
//! of other origins and of deleted accounts when it opens one, and holds an
//! operating system lock on an open companion, so no other handle, in this
//! process or another, opens or deletes it meanwhile. Deleting an account
//! removes its companions with [`remove_companions`]; every sync start deletes
//! those of deleted accounts with [`remove_orphan_companions`], so a removal
//! that failed converges.
//!
//! A pass that fails because the service cannot be reached or is not serving
//! is [`SourceError::Unavailable`], which ends the whole run, rather than a
//! failure of that account.
//!
//! A source parks each companion it opened, with its lock, until the source is
//! dropped, so a pass and its settlement see the same companion and nothing
//! removes it in between. Settlement hands the parked batch, unopened, to the
//! adapter's `apply_and_acknowledge`, which applies its commits and
//! acknowledges it only once every one committed.
//!
//! A pass runs on a thread and runtime of its own, never the sync's runtime
//! or its blocking pool: a runtime's shutdown waits for every blocking-pool
//! task, so a pass that ignored its cancellation would hold the sync, and
//! every start queued behind it, until the app restarted. It reads the wallet
//! through a read-only handle for the chain view and stops at cancellation or
//! [`PASS_DEADLINE`], counted from the call. On cancellation the pass gets
//! [`CANCEL_GRACE`] to return; one that does not is abandoned, still holding
//! its read-only handle and its companion's lock until it returns, and
//! nothing it returns is read. A call dropped before the pass returns, as at
//! the coordinator's backstop, likewise stops it at its next request.
//! Logs carry variant and cause names and lag in blocks, never identifiers,
//! digests, scripts or adapter error text.

use std::collections::{BTreeSet, HashMap};
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::runtime::Handle;
use zakura_pir_transparent::{
    Applied, ApplyFailure, BatchState, Companion, CompanionDir, OpenError, RecoveryBatch,
    RecoveryConfig, RecoveryError, TransparentPirHttp, Trust, WalletChain,
};
use zcash_client_backend::data_api::{transparent_ledger::TransparentWatchSet, WalletRead};
use zcash_client_sqlite::AccountUuid;

use super::{RecoverySource, SourceBatch, SourceError, SourceRequest};
use crate::wallet::db::{
    open_wallet_db_readonly_with_timeout, with_wallet_db_write_lock, WalletDatabase,
    READ_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::RoutedExchange;
use crate::wallet::sync_engine::watch_for_exit;

/// The transparent PIR service mainnet wallets recover from.
pub(crate) const DEFAULT_MAINNET_ORIGIN: &str = "https://transparent-pir.valargroup.dev";

/// Replaces the origin in debug builds only. A release build always uses
/// [`DEFAULT_MAINNET_ORIGIN`].
const ORIGIN_ENV: &str = "VIZOR_TRANSPARENT_PIR_URL";

/// The caller-chosen source identity every companion binds.
const SOURCE: &[u8] = b"vizor/transparent-pir/v1";

/// Appended to the wallet path to name its companion directory.
pub(crate) const COMPANION_DIR_SUFFIX: &str = ".tpir";

/// Wall-clock bound on one pass, from the call, a companion-lock wait and a
/// publication-change retry included. Requests stop at it, and the pass fails.
pub(crate) const PASS_DEADLINE: Duration = Duration::from_secs(90);

/// Watched scripts one pass may cover.
const MAX_SCRIPTS: usize = 10_000;
/// Shard-map entries one pass may read.
const MAX_SHARDS: usize = 1_024;
/// Candidate events one pass may export.
const MAX_EVENTS: usize = 500_000;
/// Private queries one pass may send.
const MAX_QUERIES: u64 = 256;
/// Private bytes, setup included, one pass may receive.
const MAX_PRIVATE_BYTES: u64 = 96 << 20;
/// Bytes one successful response may carry.
const MAX_RESPONSE_BYTES: usize = 8 << 20;

/// How long a cancelled pass may take to return before it is abandoned.
pub(crate) const CANCEL_GRACE: Duration = Duration::from_secs(2);

/// How long account deletion waits for a companion another pass holds.
pub(crate) const REMOVE_WAIT: Duration = Duration::from_secs(5);

/// Private transparent recovery from the transparent PIR service, one
/// companion per account.
///
/// Built per run. Passes and acknowledgments on one source run one at a time;
/// the coordinator visits one account at a time anyway.
pub(crate) struct TransparentPirSource {
    db_path: String,
    network: WalletNetwork,
    /// `None` off mainnet: every pass is unavailable and sends nothing.
    origin: Option<String>,
    clock: fn() -> Instant,
    parked: tokio::sync::Mutex<HashMap<AccountUuid, Parked>>,
    #[cfg(test)]
    transport: Option<test_transport::Seam>,
}

/// A companion this source opened, kept, with its lock, between passes.
struct Parked {
    companion: Companion,
    /// The last pass's `Ready` batch until it is settled. Nothing outside the
    /// adapter reads or changes its commits.
    batch: Option<RecoveryBatch<AccountUuid>>,
}

/// Why a pass failed, for logs. Adapter errors are reduced to their variant.
#[derive(Clone, Copy, Debug)]
enum PassFailure {
    Wallet,
    Companion,
    Transport,
    Invalid,
    Failure,
    PublicationChanged,
    /// The service could not be reached or was not serving.
    Outage,
}

impl PassFailure {
    fn name(self) -> &'static str {
        match self {
            PassFailure::Wallet => "wallet unreadable",
            PassFailure::Companion => "companion unusable",
            PassFailure::Transport => "transport refused the origin",
            PassFailure::Invalid => "invalid",
            PassFailure::Failure => "failure",
            PassFailure::PublicationChanged => "publication changed",
            PassFailure::Outage => "service unavailable",
        }
    }
}

impl From<&RecoveryError> for PassFailure {
    fn from(error: &RecoveryError) -> Self {
        match error {
            RecoveryError::Invalid(_) => PassFailure::Invalid,
            RecoveryError::Failure(_) => PassFailure::Failure,
            RecoveryError::PublicationChanged => PassFailure::PublicationChanged,
        }
    }
}

impl TransparentPirSource {
    /// The source for the wallet at `db_path`. Off mainnet it has no origin,
    /// and every pass is [`SourceError::Unavailable`].
    pub(crate) fn new(db_path: &str, network: WalletNetwork) -> Self {
        Self {
            db_path: db_path.to_owned(),
            network,
            origin: origin_for(network, origin_override(|name| std::env::var(name).ok())),
            clock: Instant::now,
            parked: Default::default(),
            #[cfg(test)]
            transport: test_transport::get(db_path),
        }
    }

    /// Replaces the clock the pass deadline is measured on.
    #[cfg(test)]
    pub(crate) fn with_clock(mut self, clock: fn() -> Instant) -> Self {
        self.clock = clock;
        self
    }
}

impl RecoverySource for TransparentPirSource {
    /// Every commit comes from the configured origin: the trusted-indexer
    /// decision.
    fn trusted(&self) -> bool {
        true
    }

    /// One pass over the request's account from its watch set.
    ///
    /// Opens the account's companion on its first pass, then retrieves on a
    /// blocking thread until the adapter returns, `should_exit` holds, or
    /// [`PASS_DEADLINE`] passes. A publication whose set identity changed is
    /// retried once on the same companion. Only a `Ready` batch has commits;
    /// it stays parked for [`apply`](Self::apply), and a later pass on the
    /// account supersedes an unsettled one.
    /// Cancellation waits up to [`CANCEL_GRACE`] for the pass, abandoning it
    /// after that, and returns [`SourceError::Cancelled`], discarding
    /// whatever it retrieved.
    async fn recover(&self, request: SourceRequest<'_>) -> Result<SourceBatch, SourceError> {
        let SourceRequest {
            account,
            watch,
            should_exit,
        } = request;
        let Some(origin) = self.origin.clone() else {
            return Err(SourceError::Unavailable);
        };
        #[cfg(test)]
        let Some(transport) = self.transport.clone() else {
            // No test reaches the live service by accident.
            return Err(SourceError::Unavailable);
        };
        if should_exit() {
            return Err(SourceError::Cancelled);
        }
        // Counted before any wait, so the pass always ends before the
        // coordinator's backstop abandons the call.
        let deadline = (self.clock)() + PASS_DEADLINE;
        let mut parked = self.parked.lock().await;
        let held = parked.remove(&account);
        let cancel = Arc::new(AtomicBool::new(false));
        // A dropped call stops the pass at its next request instead of leaving
        // it running detached.
        let _cancel_on_drop = CancelOnDrop(cancel.clone());
        let pass = Pass {
            db_path: self.db_path.clone(),
            network: self.network,
            origin,
            account,
            watch: watch.clone(),
            handle: Handle::current(),
            cancel: cancel.clone(),
            clock: self.clock,
            deadline,
            #[cfg(test)]
            transport,
        };
        let (done, mut answer) = tokio::sync::oneshot::channel();
        let spawned = std::thread::Builder::new()
            .name("transparent-pir".to_owned())
            .spawn(move || {
                // The pass's I/O, DNS lookups on a blocking pool among it, runs
                // on this runtime, so an abandoned pass never holds the sync's.
                let Ok(io) = tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(1)
                    .thread_name("transparent-pir-io")
                    .enable_all()
                    .build()
                else {
                    return;
                };
                let mut pass = pass;
                pass.handle = io.handle().clone();
                // A send to an abandoning caller drops the companion here,
                // releasing its lock.
                let _ = done.send(pass.run(held));
                io.shutdown_background();
            });
        if spawned.is_err() {
            log::error!("transparent PIR: could not start a pass");
            return Err(SourceError::Failed);
        }
        let joined = tokio::select! {
            biased;
            _ = watch_for_exit(&should_exit) => {
                cancel.store(true, Ordering::SeqCst);
                match tokio::time::timeout(CANCEL_GRACE, &mut answer).await {
                    Ok(joined) => joined,
                    Err(_) => {
                        log::warn!("transparent PIR: abandoned a pass that ignored cancellation");
                        return Err(SourceError::Cancelled);
                    }
                }
            }
            joined = &mut answer => joined,
        };
        let Ok((held, result)) = joined else {
            log::error!("transparent PIR: pass panicked");
            return Err(SourceError::Failed);
        };
        // A pass that raced cancellation is discarded whole. Revisions it
        // marked exported stay marked, as after a crash before applying.
        let cancelled = cancel.load(Ordering::SeqCst) || should_exit();
        let Some(mut held) = held else {
            return Err(if cancelled {
                SourceError::Cancelled
            } else {
                fail(result.err())
            });
        };
        let answer = if cancelled {
            Err(SourceError::Cancelled)
        } else {
            match result {
                Ok(batch) => {
                    let target = watch.target.map_or(0, |target| u32::from(target.height));
                    let (state, progress) = (batch.state(), batch.progress());
                    log::info!(
                        "transparent PIR: pass {state:?}, {:?}, {} blocks behind",
                        progress.outcome,
                        progress.behind(target.into())
                    );
                    if state == BatchState::Ready {
                        held.batch = Some(batch);
                    }
                    Ok(SourceBatch { state, progress })
                }
                Err(failure) => Err(fail(Some(failure))),
            }
        };
        parked.insert(account, held);
        answer
    }

    /// Settles `account`'s last `Ready` batch through the adapter, under the
    /// companion's parked lock and the wallet write lock, which cover only
    /// local SQLite work. The write lock spans the whole batch, as the adapter
    /// asks: other wallet writes wait until every commit and the
    /// acknowledgment are done.
    ///
    /// `None` when no unsettled `Ready` batch is parked for the account. The
    /// batch is consumed either way: a refused batch is replayed by the
    /// account's next pass.
    async fn apply(
        &self,
        account: AccountUuid,
        db: &mut WalletDatabase,
        trust: Trust,
    ) -> Option<Result<Applied, ApplyFailure>> {
        let mut parked = self.parked.lock().await;
        let held = parked.get_mut(&account)?;
        let batch = held.batch.take()?;
        let companion = &mut held.companion;
        Some(with_wallet_db_write_lock(
            "sync_engine.transparent_ledger.apply",
            || companion.apply_and_acknowledge(batch, db, trust),
        ))
    }
}

/// Sets a pass's cancellation flag when dropped.
struct CancelOnDrop(Arc<AtomicBool>);

impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

/// Logs a failed pass by variant and reports it: an outage of the service,
/// which no other account's pass would avoid, as unavailable, anything else
/// as failed.
fn fail(failure: Option<PassFailure>) -> SourceError {
    let name = failure.map_or("unknown", PassFailure::name);
    log::warn!("transparent PIR: pass failed ({name})");
    match failure {
        Some(PassFailure::Outage) => SourceError::Unavailable,
        _ => SourceError::Failed,
    }
}

/// Everything one pass needs on its blocking thread.
struct Pass {
    db_path: String,
    network: WalletNetwork,
    origin: String,
    account: AccountUuid,
    watch: TransparentWatchSet<AccountUuid>,
    handle: Handle,
    cancel: Arc<AtomicBool>,
    clock: fn() -> Instant,
    deadline: Instant,
    #[cfg(test)]
    transport: test_transport::Seam,
}

impl Pass {
    /// Whether the pass is stopping: cancelled, or past its deadline.
    fn exit(&self) -> bool {
        self.cancel.load(Ordering::SeqCst) || (self.clock)() >= self.deadline
    }

    /// Runs the pass on `held`, the companion this source parked for the
    /// account, or one it opens, and returns the companion to park: none when
    /// it could not be opened.
    fn run(
        self,
        held: Option<Parked>,
    ) -> (
        Option<Parked>,
        Result<RecoveryBatch<AccountUuid>, PassFailure>,
    ) {
        let _runtime = self.handle.enter();
        let db = match open_wallet_db_readonly_with_timeout(
            &self.db_path,
            self.network,
            READ_DB_BUSY_TIMEOUT,
        ) {
            Ok(db) => db,
            Err(_) => return (held, Err(PassFailure::Wallet)),
        };
        let mut held = match held {
            Some(held) => held,
            None => match self.open(&db) {
                Ok(companion) => Parked {
                    companion,
                    batch: None,
                },
                Err(failure) => return (None, Err(failure)),
            },
        };
        // The adapter honors only its latest pass's acknowledgment.
        held.batch = None;
        let result = self.recover(&db, &mut held.companion);
        (Some(held), result)
    }

    /// Opens the account's companion, waiting for one another handle holds
    /// until the pass stops. The library first deletes the account's
    /// companions for other origins or schemas and those of accounts the
    /// wallet no longer has.
    fn open(
        &self,
        db: &impl WalletRead<AccountId = AccountUuid>,
    ) -> Result<Companion, PassFailure> {
        let accounts: BTreeSet<_> = db
            .get_account_ids()
            .map_err(|_| PassFailure::Wallet)?
            .into_iter()
            .map(|account| account.expose_uuid().to_string())
            .collect();
        companion_dir(&self.db_path)
            .open(
                &self.account.expose_uuid().to_string(),
                recovery_config(self.account, &self.origin),
                &accounts,
                &|| !self.exit(),
            )
            .map_err(|error| {
                let name = match &error {
                    OpenError::Recovery(error) => PassFailure::from(error).name(),
                    OpenError::Busy => "in use",
                    OpenError::Account | OpenError::Io(_) => "unusable",
                };
                log::warn!("transparent PIR: companion refused ({name})");
                PassFailure::Companion
            })
    }

    /// One adapter pass, retried once on the same companion if the
    /// publication's set identity changed. The adapter has then reset the
    /// companion's store and kept its catalog, which still records the
    /// revisions the wallet holds, so the companion is never recreated.
    fn recover(
        &self,
        db: &crate::wallet::db::WalletDatabase,
        companion: &mut Companion,
    ) -> Result<RecoveryBatch<AccountUuid>, PassFailure> {
        let target = self.watch.target.ok_or(PassFailure::Invalid)?;
        let chain = WalletChain::new(db, target);
        let exit = || self.exit();
        let exchange = RoutedExchange::transparent(&self.origin, &exit, self.handle.clone())
            .map_err(|_| PassFailure::Transport)?;
        #[cfg(test)]
        let exchange = self.transport.attach(exchange);
        let mut http = TransparentPirHttp::new(exchange, MAX_RESPONSE_BYTES);
        let mut attempt = || {
            let (mut filters, mut shards) = http.split();
            companion.recover(&self.watch, &chain, &mut filters, &mut shards)
        };
        let result = match attempt() {
            Err(RecoveryError::PublicationChanged) if !exit() => {
                log::info!("transparent PIR: publication changed; retrying once");
                attempt()
            }
            result => result,
        };
        result.map_err(|error| match error {
            RecoveryError::Failure(_) if http.outage() => PassFailure::Outage,
            error => PassFailure::from(&error),
        })
    }
}

/// The origin a source on `network` recovers from: `configured` or the
/// default service, on mainnet only.
pub(crate) fn origin_for(network: WalletNetwork, configured: Option<String>) -> Option<String> {
    (network == WalletNetwork::Main)
        .then(|| configured.unwrap_or_else(|| DEFAULT_MAINNET_ORIGIN.to_owned()))
}

/// The configured origin override, read with `read`, in debug builds only.
pub(crate) fn origin_override(read: impl FnOnce(&str) -> Option<String>) -> Option<String> {
    if cfg!(debug_assertions) {
        read(ORIGIN_ENV)
    } else {
        None
    }
}

/// The adapter configuration for `account`'s companion.
pub(super) fn recovery_config(account: AccountUuid, origin: &str) -> RecoveryConfig {
    RecoveryConfig {
        source: SOURCE.to_vec(),
        account_binding: account.expose_uuid().as_bytes().to_vec(),
        origin: origin.to_owned(),
        scripts: MAX_SCRIPTS,
        shards: MAX_SHARDS,
        events: MAX_EVENTS,
        queries: MAX_QUERIES,
        private_bytes: MAX_PRIVATE_BYTES,
    }
}

/// The companion directory of the wallet at `db_path`.
pub(crate) fn companion_dir(db_path: &str) -> CompanionDir {
    CompanionDir::new(format!("{db_path}{COMPANION_DIR_SUFFIX}"))
}

/// Deletes every companion of the account `account_uuid` in the wallet at
/// `db_path`, with its sidecars.
///
/// Waits up to five seconds for a pass or a parked source holding one; account
/// deletion runs with sync paused, so a wait that times out is a failure, and
/// the companion is left for [`remove_orphan_companions`] at the next sync
/// start.
pub(crate) fn remove_companions(db_path: &str, account_uuid: &str) -> Result<(), String> {
    remove_account_companions(db_path, account_uuid, REMOVE_WAIT)
}

/// Deletes the companions of accounts the wallet at `db_path` no longer has,
/// so a removal that failed after an account was deleted converges at the
/// next sync start whether or not private recovery is still selected.
///
/// A companion in use is left for a later sweep, and an unreadable account
/// list deletes nothing; see [`CompanionDir::retain`].
pub(crate) fn remove_orphan_companions(db_path: &str) -> Result<(), String> {
    companion_dir(db_path)
        .retain(|| {
            crate::wallet::keys::list_account_uuids_from_db(db_path)
                .map_err(io::Error::other)?
                .iter()
                .map(|account| uuid::Uuid::try_parse(account).map(|uuid| uuid.to_string()))
                .collect::<Result<_, _>>()
                .map_err(io::Error::other)
        })
        .map_err(|error| format!("Failed to remove orphan transparent PIR companions: {error}"))
}

/// Deletes every companion of the wallet at `db_path`, with its sidecars,
/// waiting at most `wait` in all for those another handle holds.
///
/// Forgetting private ledger facts calls this first and forgets nothing
/// unless it succeeds: a companion records which revisions the wallet holds,
/// and one that outlived the facts would make a later private run skip them.
/// A companion still locked, as by an abandoned pass, fails the call and is
/// left for the next attempt.
pub(crate) fn remove_all_companions(db_path: &str, wait: Duration) -> Result<(), String> {
    companion_dir(db_path)
        .clear(wait)
        .map_err(|error| match error.kind() {
            io::ErrorKind::WouldBlock => "A transparent PIR companion is in use".to_owned(),
            _ => format!("Failed to remove a transparent PIR companion: {error}"),
        })
}

/// [`remove_companions`], waiting at most `wait` for each companion's lock.
pub(super) fn remove_account_companions(
    db_path: &str,
    account_uuid: &str,
    wait: Duration,
) -> Result<(), String> {
    let account = uuid::Uuid::try_parse(account_uuid)
        .map_err(|error| format!("Invalid account UUID: {error}"))?;
    companion_dir(db_path)
        .remove(&account.to_string(), wait)
        .map_err(|error| match error.kind() {
            io::ErrorKind::WouldBlock => "A transparent PIR companion is in use".to_owned(),
            _ => format!("Failed to remove a transparent PIR companion: {error}"),
        })
}

/// Test seam: the transport a source for one wallet file sends through,
/// standing in for the network. Keyed by path, so parallel tests on other
/// wallets are unaffected. A source whose wallet has none is unavailable.
#[cfg(test)]
pub(crate) mod test_transport {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex, OnceLock, PoisonError};

    use crate::wallet::sync_engine::enhancement::{RequestObserver, RoutePolicy, RoutedExchange};

    /// Every request reaches `observer`, which answers it; each pass records
    /// the route policy of the transport it built.
    #[derive(Clone)]
    pub(crate) struct Seam {
        pub(crate) observer: RequestObserver,
        routes: Arc<Mutex<Vec<RoutePolicy>>>,
    }

    impl Seam {
        /// The route policy of each pass's transport, in order.
        pub(crate) fn routes(&self) -> Vec<RoutePolicy> {
            self.routes
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .clone()
        }

        pub(super) fn attach<'a, F: Fn() -> bool>(
            &self,
            exchange: RoutedExchange<'a, F>,
        ) -> RoutedExchange<'a, F> {
            self.routes
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .push(exchange.route_policy());
            exchange.with_observer(self.observer.clone())
        }
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

    /// Sources built for `db_path` send through `observer` until the guard
    /// drops.
    pub(crate) fn set(db_path: &str, observer: RequestObserver) -> SeamGuard {
        let seam = Seam {
            observer,
            routes: Default::default(),
        };
        seams()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(db_path.to_owned(), seam.clone());
        SeamGuard {
            db_path: db_path.to_owned(),
            seam,
        }
    }

    pub(crate) struct SeamGuard {
        db_path: String,
        pub(crate) seam: Seam,
    }

    impl Drop for SeamGuard {
        fn drop(&mut self) {
            seams()
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .remove(&self.db_path);
        }
    }
}
