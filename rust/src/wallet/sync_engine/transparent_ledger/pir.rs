//! Transparent PIR as the private recovery source .
//!
//! [`TransparentPirSource`] recovers one account per pass from the transparent
//! PIR service through the reference adapter `zakura_pir_client::transparent`, over the
//! wallet's routed HTTPS transport. It answers for mainnet only, from the
//! selected wallet PIR server ([`PirProduct::Transparent`]).
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
//! removes it in between. The companion's pass holds its `Ready` batch, and
//! the adapter's `settle_latest` applies its commits and acknowledges it only
//! once every one committed.
//!
//! A pass runs through [`run_detached`], on a thread and runtime of its own,
//! never the sync's runtime or its blocking pool. It reads the wallet through
//! a read-only handle for the chain view and stops at cancellation or
//! [`PASS_DEADLINE`], counted from the call. On cancellation the pass gets
//! [`CANCEL_GRACE`] to return; one that does not is abandoned, still holding
//! its read-only handle and its companion's lock until it returns, and
//! nothing it returns is read. A call dropped before the pass returns, as at
//! the coordinator's backstop, likewise stops it at its next request.
//! Logs carry variant and cause names and lag in blocks, never identifiers,
//! digests, scripts or adapter error text.

use std::cell::Cell;
use std::collections::{BTreeSet, HashMap};
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::runtime::Handle;
use zakura_pir_client::transparent::{
    Applied, ApplyFailure, Companion, CompanionDir, Interrupted, OpenError, PassError, PassReport,
    RecoveryError, TransparentHistoryRecoveryConfig, Trust, WalletChain, WriteGate,
};
use zcash_client_backend::data_api::{transparent_ledger::TransparentAddressWatchSet, WalletRead};
use zcash_client_sqlite::AccountUuid;

use super::{RecoverySource, SourceError, SourceRequest};
#[cfg(doc)]
use crate::wallet::bounded_runtime::CANCEL_GRACE;
use crate::wallet::bounded_runtime::{run_detached, Detached};
use crate::wallet::db::{
    open_wallet_db_readonly_with_timeout, with_wallet_db_write_lock, writers_waiting,
    WalletDatabase, READ_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::pir_config::{client_origin, PirProduct};
use crate::wallet::sync_engine::enhancement::RoutedExchange;

/// The origin tests name through their transport seam. It is the live
/// service the ignored live tests qualify against; every other test's
/// transport is a fake, so nothing reaches it. Runtime traffic goes only to
/// the selected server.
#[cfg(test)]
pub(crate) const TEST_ORIGIN: &str = "https://transparent-pir.valargroup.dev";

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
pub(super) const MAX_SHARDS: usize = 1_024;
/// Candidate events one pass may export.
const MAX_EVENTS: usize = 500_000;
/// Private queries one pass may send.
pub(super) const MAX_QUERIES: u64 = 256;
/// Private bytes, setup included, one pass may receive.
pub(super) const MAX_PRIVATE_BYTES: u64 = 96 << 20;
/// Bytes one successful response may carry.
pub(super) const MAX_RESPONSE_BYTES: usize = 8 << 20;

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
    /// Each companion this source opened, kept, with its lock, between
    /// passes. It holds its last pass's `Ready` batch until it is settled.
    parked: tokio::sync::Mutex<HashMap<AccountUuid, Companion>>,
    #[cfg(test)]
    transport: Option<test_transport::Seam>,
}

/// Why a pass failed, for logs. Adapter errors are reduced to their variant.
#[derive(Debug)]
enum PassFailure {
    Wallet,
    Companion,
    Transport,
    /// The watch set has no target to recover to.
    Untargeted,
    Pass(PassError),
}

impl PassFailure {
    fn name(&self) -> &'static str {
        match self {
            PassFailure::Wallet => "wallet unreadable",
            PassFailure::Companion => "companion unusable",
            PassFailure::Transport => "transport refused the origin",
            PassFailure::Untargeted => "no target",
            PassFailure::Pass(PassError::Outage) => "service unavailable",
            PassFailure::Pass(PassError::Invalid(_)) => "invalid",
            PassFailure::Pass(PassError::Failure(_)) => "failure",
            PassFailure::Pass(PassError::PublicationChanged) => "publication changed",
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
            origin: origin_for(network, source_origin(db_path)),
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
    /// [`PASS_DEADLINE`] passes. The adapter's pass retries a publication
    /// whose set identity changed once on the same companion. Only a `Ready`
    /// batch has commits; the parked companion holds it for
    /// [`apply`](Self::apply), and a later pass on the account supersedes an
    /// unsettled one.
    /// Cancellation waits up to [`CANCEL_GRACE`] for the pass, abandoning it
    /// after that, and returns [`SourceError::Cancelled`], discarding
    /// whatever it retrieved.
    async fn recover(&self, request: SourceRequest<'_>) -> Result<PassReport, SourceError> {
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
        let ran = run_detached("transparent-pir", cancel.clone(), should_exit, move |io| {
            let mut pass = pass;
            pass.handle = io;
            pass.run(held)
        })
        .await;
        let (held, result) = match ran {
            Detached::Returned(ran) => ran,
            Detached::Abandoned => {
                log::warn!("transparent PIR: abandoned a pass that ignored cancellation");
                return Err(SourceError::Cancelled);
            }
            Detached::NotStarted => {
                log::error!("transparent PIR: could not start a pass");
                return Err(SourceError::Failed);
            }
            Detached::Panicked => {
                log::error!("transparent PIR: pass panicked");
                return Err(SourceError::Failed);
            }
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
            // Nothing it retrieved may be settled.
            held.take_latest::<AccountUuid>();
            Err(SourceError::Cancelled)
        } else {
            match result {
                Ok(report) => {
                    let target = watch.target.map_or(0, |target| u32::from(target.height));
                    if report.publication_changed {
                        log::info!("transparent PIR: publication changed; retried once");
                    }
                    log::info!(
                        "transparent PIR: pass {:?}, {:?}, {} blocks behind",
                        report.state,
                        report.progress.outcome,
                        report.progress.behind(target.into())
                    );
                    Ok(report)
                }
                Err(failure) => Err(fail(Some(failure))),
            }
        };
        parked.insert(account, held);
        answer
    }

    /// Settles `account`'s last `Ready` batch through the adapter, under the
    /// companion's parked lock, which covers only local SQLite work. Each
    /// commit, and then the acknowledgment, takes the wallet write lock on its
    /// own ([`SettlementGate`]), so another wallet write waits at most one
    /// commit, and `should_exit` stops the batch between them.
    ///
    /// `Ok(None)` when no unsettled `Ready` batch is parked for the account.
    /// The batch is consumed either way: a refused or interrupted batch is
    /// replayed by the account's next pass.
    async fn apply(
        &self,
        account: AccountUuid,
        db: &mut WalletDatabase,
        trust: Trust,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Result<Option<Applied>, ApplyFailure> {
        let mut parked = self.parked.lock().await;
        let Some(companion) = parked.get_mut(&account) else {
            return Ok(None);
        };
        let mut gate = SettlementGate { should_exit };
        companion.settle_latest(db, trust, &mut gate)
    }
}

/// How long a settlement waits before checking again whether the writer it
/// stepped aside for has taken the lock.
const STEP_ASIDE_POLL: Duration = Duration::from_millis(2);

/// The longest a settlement steps aside before one commit, so writers that
/// keep arriving cannot stall recovery.
const STEP_ASIDE_MAX: Duration = Duration::from_millis(250);

/// Runs a settlement's wallet writes one at a time under the wallet write
/// lock. Before each, it stops the batch when `should_exit` holds, and steps
/// aside while another writer waits for the lock, for at most
/// [`STEP_ASIDE_MAX`], so a foreground write or a hardware broadcast
/// reservation gets in between two commits rather than after the batch.
pub(super) struct SettlementGate<'a> {
    pub(super) should_exit: &'a (dyn Fn() -> bool + Sync),
}

impl WriteGate for SettlementGate<'_> {
    fn write<T>(&mut self, write: impl FnOnce() -> T) -> Result<T, Interrupted> {
        let stepped_aside = Instant::now();
        loop {
            if (self.should_exit)() {
                return Err(Interrupted);
            }
            if !writers_waiting() || stepped_aside.elapsed() >= STEP_ASIDE_MAX {
                break;
            }
            std::thread::sleep(STEP_ASIDE_POLL);
        }
        Ok(with_wallet_db_write_lock(
            "sync_engine.transparent_ledger.apply",
            write,
        ))
    }
}

/// Logs a failed pass by variant and reports it: an outage of the service,
/// which no other account's pass would avoid, as unavailable, anything else
/// as failed.
fn fail(failure: Option<PassFailure>) -> SourceError {
    let name = failure.as_ref().map_or("unknown", PassFailure::name);
    log::warn!("transparent PIR: pass failed ({name})");
    match failure {
        Some(PassFailure::Pass(PassError::Outage)) => SourceError::Unavailable,
        _ => SourceError::Failed,
    }
}

/// Everything one pass needs on its blocking thread.
struct Pass {
    db_path: String,
    network: WalletNetwork,
    origin: String,
    account: AccountUuid,
    watch: TransparentAddressWatchSet<AccountUuid>,
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
    fn run(self, held: Option<Companion>) -> (Option<Companion>, Result<PassReport, PassFailure>) {
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
                Ok(companion) => companion,
                Err(failure) => return (None, Err(failure)),
            },
        };
        let result = self.recover(&db, &mut held);
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
        // The library reads the accounts only after listing the companions,
        // so one created for an account added meanwhile is never an orphan.
        let unreadable = Cell::new(false);
        let accounts = || match db.get_account_ids() {
            Ok(accounts) => Ok(accounts
                .into_iter()
                .map(|account| account.expose_uuid().to_string())
                .collect::<BTreeSet<_>>()),
            Err(_) => {
                unreadable.set(true);
                Err(io::Error::other("wallet accounts unreadable"))
            }
        };
        companion_dir(&self.db_path)
            .open(
                &self.account.expose_uuid().to_string(),
                recovery_config(self.account, &self.origin),
                accounts,
                &|| !self.exit(),
            )
            .map_err(|error| {
                if unreadable.get() {
                    return PassFailure::Wallet;
                }
                let name = match &error {
                    // The pass stopped while another handle held it.
                    OpenError::Busy if self.exit() => return PassFailure::Companion,
                    OpenError::Busy => "in use",
                    OpenError::Recovery(RecoveryError::Invalid(_)) => "invalid",
                    OpenError::Recovery(RecoveryError::Failure(_)) => "failure",
                    OpenError::Recovery(RecoveryError::PublicationChanged) => "publication changed",
                    OpenError::Account | OpenError::Io(_) => "unusable",
                };
                log::warn!("transparent PIR: companion refused ({name})");
                PassFailure::Companion
            })
    }

    /// One adapter pass over the routed transport. The adapter retries a
    /// changed publication set once on the same companion, whose store it has
    /// reset while keeping its catalog, which still records the revisions the
    /// wallet holds, so the companion is never recreated.
    fn recover(
        &self,
        db: &crate::wallet::db::WalletDatabase,
        companion: &mut Companion,
    ) -> Result<PassReport, PassFailure> {
        let target = self.watch.target.ok_or(PassFailure::Untargeted)?;
        let chain = WalletChain::new(db, target);
        let exit = || self.exit();
        let exchange = RoutedExchange::transparent(&self.origin, &exit, self.handle.clone())
            .map_err(|_| PassFailure::Transport)?;
        #[cfg(test)]
        let exchange = self.transport.attach(exchange);
        companion
            .pass(&self.watch, &chain, exchange, MAX_RESPONSE_BYTES, &exit)
            .map_err(PassFailure::Pass)
    }
}

/// The origin a source on `network` recovers from: `selected`, on mainnet
/// only. `None` makes every pass fail as unavailable; there is no default
/// service to fall back to.
pub(crate) fn origin_for(network: WalletNetwork, selected: Option<String>) -> Option<String> {
    selected.filter(|_| network == WalletNetwork::Main)
}

/// The selected server's origin for transparent PIR; `None` with no server
/// selected.
pub(crate) fn selected_origin() -> Option<String> {
    client_origin(PirProduct::Transparent)
}

/// The origin sources for the wallet at `db_path` recover from: the selected
/// server. A test names its origin explicitly through the transport seam it
/// sets for the path, which replaces the selection; a test without a seam
/// sees exactly what a release build sees.
pub(crate) fn source_origin(db_path: &str) -> Option<String> {
    #[cfg(test)]
    if let Some(seam) = test_transport::get(db_path) {
        return seam.origin;
    }
    let _ = db_path;
    selected_origin()
}

/// The adapter configuration for `account`'s companion.
pub(super) fn recovery_config(
    account: AccountUuid,
    origin: &str,
) -> TransparentHistoryRecoveryConfig {
    TransparentHistoryRecoveryConfig {
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
/// next sync start whether or not private queries are still on.
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
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex, OnceLock, PoisonError};

    use crate::wallet::sync_engine::enhancement::{RequestObserver, RoutedExchange};

    /// Every request reaches `observer`, which answers it; each pass counts
    /// the transport it built, always on the wallet's route. `origin` stands
    /// in for the selected server.
    #[derive(Clone)]
    pub(crate) struct Seam {
        pub(crate) observer: RequestObserver,
        pub(crate) origin: Option<String>,
        transports: Arc<AtomicUsize>,
    }

    impl Seam {
        /// How many transports passes built.
        pub(crate) fn transports(&self) -> usize {
            self.transports.load(Ordering::SeqCst)
        }

        pub(in crate::wallet::sync_engine::transparent_ledger) fn attach<'a>(
            &self,
            exchange: RoutedExchange<'a>,
        ) -> RoutedExchange<'a> {
            self.transports.fetch_add(1, Ordering::SeqCst);
            exchange.with_observer(self.observer.clone())
        }
    }

    fn seams() -> &'static Mutex<HashMap<String, Seam>> {
        static SEAMS: OnceLock<Mutex<HashMap<String, Seam>>> = OnceLock::new();
        SEAMS.get_or_init(Default::default)
    }

    pub(crate) fn get(db_path: &str) -> Option<Seam> {
        seams()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(db_path)
            .cloned()
    }

    /// Sources built for `db_path` recover from [`TEST_ORIGIN`] and send
    /// through `observer` until the guard drops.
    ///
    /// [`TEST_ORIGIN`]: super::TEST_ORIGIN
    pub(crate) fn set(db_path: &str, observer: RequestObserver) -> SeamGuard {
        set_origin(db_path, Some(super::TEST_ORIGIN.to_owned()), observer)
    }

    /// Like [`set`], with no server selected: sources for `db_path` have no
    /// origin, as in a release build before the user has a server.
    pub(crate) fn set_unserved(db_path: &str, observer: RequestObserver) -> SeamGuard {
        set_origin(db_path, None, observer)
    }

    fn set_origin(db_path: &str, origin: Option<String>, observer: RequestObserver) -> SeamGuard {
        let seam = Seam {
            observer,
            origin,
            transports: Default::default(),
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
