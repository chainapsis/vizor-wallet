//! Transparent PIR as the private recovery source (development flag).
//!
//! [`TransparentPirSource`] recovers one account per pass from the transparent
//! PIR service through the reference adapter `zakura_pir_transparent`, over the
//! wallet's routed HTTPS transport. It answers for mainnet only, from
//! [`DEFAULT_MAINNET_ORIGIN`]; debug builds honor `VIZOR_TRANSPARENT_PIR_URL`.
//! Every commit it returns comes from that origin, which is what lets the
//! coordinator qualify it (the trusted-indexer decision).
//!
//! Each account has its own companion database,
//! `{db}.tpir/{uuid}-{tag}.sqlite`, where the tag binds the origin and the
//! adapter's shard schema. A companion holds the adapter's retrieval cache and
//! revision catalog, never wallet state, so losing one costs a re-download:
//! revision identities are derived from the publication, and a recreated
//! companion derives the ones the wallet already holds. Companions are created
//! on an account's first pass; opening one deletes the account's companions for
//! other origins or schemas and those of deleted accounts, and deleting an
//! account removes its companion with [`remove_companions`]. Every sync start
//! deletes those of deleted accounts with [`remove_orphan_companions`], so a
//! removal that failed converges.
//!
//! A companion is rebuilt only when it is confirmed unusable and
//! reconstructible: SQLite reports it is not a database or is corrupt, or it
//! is in the earlier format the adapter asks to recreate. The rebuild runs
//! under the companion's path lock, at most once per companion per process,
//! and keeps every catalog row the damaged file still yields, so the
//! catalog's reconciliation records survive. A busy, locked or unreadable
//! companion, one bound to another identity, a publication change or any
//! other refusal is never deleted or reset. A regular file or symlink where the
//! companion directory belongs is never touched: the run is unavailable.
//!
//! A pass that fails because the service cannot be reached or is not serving
//! is [`SourceError::Unavailable`], which ends the whole run, rather than a
//! failure of that account.
//!
//! One lock per companion path serializes every pass, settlement and removal
//! on it across sources. A source parks each companion it opened with that
//! lock until the source is dropped, so a pass and its settlement see the same
//! companion and nothing removes it in between. Settlement hands the parked
//! batch, unopened, to the adapter's `apply_and_acknowledge`, which applies
//! its commits and acknowledges it only once every one committed.
//!
//! A pass runs on a blocking thread, over a read-only wallet handle for the
//! chain view, and stops at cancellation or [`PASS_DEADLINE`], counted from
//! the call. On cancellation the async side waits for it, so no companion or
//! wallet handle outlives a cancelled pass; a call dropped before the pass
//! returns, as at the coordinator's backstop, stops it at its next request.
//! Logs carry variant and cause names and lag in blocks, never identifiers,
//! digests, scripts or adapter error text.

use std::collections::{BTreeSet, HashMap};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex, PoisonError};
use std::time::{Duration, Instant};

use sha2::{Digest, Sha256};
use tokio::runtime::Handle;
use tokio::sync::OwnedMutexGuard;
use zakura_pir_transparent::{
    ApplyError, ApplyFailure, ApplyStats, BatchState, Outcome, Progress, RecoveryBatch,
    RecoveryConfig, RecoveryError, ReferenceRecovery, Trust, WalletChain, SCHEMA,
};
use zcash_client_backend::data_api::{transparent_ledger::TransparentWatchSet, WalletRead};
use zcash_client_sqlite::AccountUuid;

use super::{
    commit_refusal, Continuation, RecoverySource, Refusal, Settlement, SourceBatch, SourceError,
    SourceRequest,
};
use crate::wallet::db::{
    open_wallet_db_readonly_with_timeout, with_wallet_db_write_lock, WalletDatabase,
    READ_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::TransparentPirHttp;
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

/// Wait before asking again about a publication that ends below the target.
const BEHIND_RETRY: Duration = Duration::from_secs(10);
/// Wait before asking again a service that refused for capacity.
const OVERLOADED_RETRY: Duration = Duration::from_secs(30);

/// How long account deletion waits for a companion another pass holds.
const REMOVE_WAIT: Duration = Duration::from_secs(5);

/// Sidecar suffixes SQLite may leave beside a companion file.
const SIDECARS: [&str; 3] = ["-wal", "-shm", "-journal"];

/// The file a companion rebuild builds its replacement in, beside the
/// companion. It belongs to the companion, so listing and removal include it.
const REBUILD_SUFFIXES: [&str; 1] = [".rebuild"];

/// Every name suffix of a companion's files: the database, its sidecars, and
/// a rebuild's files with theirs.
fn companion_suffixes() -> impl Iterator<Item = String> {
    std::iter::once("")
        .chain(REBUILD_SUFFIXES)
        .flat_map(|stem| {
            std::iter::once("")
                .chain(SIDECARS)
                .map(move |sidecar| format!("{stem}{sidecar}"))
        })
}

/// One lock per companion path. Entries nobody holds or awaits are dropped as
/// others are added.
static COMPANION_LOCKS: LazyLock<Mutex<HashMap<PathBuf, Arc<tokio::sync::Mutex<()>>>>> =
    LazyLock::new(Default::default);

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

/// A companion this source opened, kept with its path lock between passes.
struct Parked {
    companion: ReferenceRecovery,
    /// The last pass's `Ready` batch until it is settled. Nothing outside the
    /// adapter reads or changes its commits.
    batch: Option<RecoveryBatch<AccountUuid>>,
    _lock: OwnedMutexGuard<()>,
}

/// The companion a pass runs on: one this source parked, or the lock for one
/// it has yet to open.
enum Slot {
    Parked(Box<Parked>),
    Locked {
        path: PathBuf,
        lock: OwnedMutexGuard<()>,
    },
}

/// Why a pass failed, for logs. Adapter errors are reduced to their variant.
#[derive(Clone, Copy, Debug)]
enum PassFailure {
    Wallet,
    Companion,
    /// The companion directory cannot be created or used, for every account.
    CompanionDirectory,
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
            PassFailure::CompanionDirectory => "companion directory unusable",
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
    /// Cancellation waits for the blocking work and returns
    /// [`SourceError::Cancelled`], discarding whatever it retrieved.
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
        let slot = match parked.remove(&account) {
            Some(held) => Slot::Parked(Box::new(held)),
            None => {
                let path = companion_path(&self.db_path, account, &origin);
                let lock = companion_lock(&path);
                tokio::select! {
                    biased;
                    _ = watch_for_exit(&should_exit) => return Err(SourceError::Cancelled),
                    lock = lock.lock_owned() => Slot::Locked { path, lock },
                }
            }
        };
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
        let mut task = tokio::task::spawn_blocking(move || pass.run(slot));
        let joined = tokio::select! {
            biased;
            _ = watch_for_exit(&should_exit) => {
                cancel.store(true, Ordering::SeqCst);
                (&mut task).await
            }
            joined = &mut task => joined,
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
                    let progress = batch.progress();
                    let next = continuation(progress.outcome);
                    let behind = behind_by(target, progress);
                    log::info!(
                        "transparent PIR: pass {:?}, {:?}, {behind} blocks behind",
                        batch.state(),
                        progress.outcome
                    );
                    Ok(match batch.state() {
                        BatchState::Ready => {
                            held.batch = Some(batch);
                            SourceBatch::Ready {
                                next,
                                behind_by: behind,
                            }
                        }
                        BatchState::Pending => SourceBatch::Pending { next },
                        BatchState::Withdrawn(cause) => SourceBatch::Withdrawn(cause),
                    })
                }
                Err(failure) => Err(fail(Some(failure))),
            }
        };
        parked.insert(account, held);
        answer
    }

    /// Settles `account`'s last `Ready` batch through the adapter, under the
    /// companion's parked lock and the wallet write lock, which cover only
    /// local SQLite work.
    ///
    /// Refuses, as [`Refusal::Skip`], when no unsettled `Ready` batch is
    /// parked for the account. The batch is consumed either way: a refused
    /// batch is replayed by the account's next pass.
    async fn apply(
        &self,
        account: AccountUuid,
        db: &mut WalletDatabase,
        trust: Trust,
    ) -> Settlement {
        let nothing = || {
            log::warn!("transparent PIR: nothing to settle");
            Settlement::Refused {
                stats: ApplyStats::default(),
                refusal: Refusal::Skip,
            }
        };
        let mut parked = self.parked.lock().await;
        let Some(held) = parked.get_mut(&account) else {
            return nothing();
        };
        let Some(batch) = held.batch.take() else {
            return nothing();
        };
        let companion = &mut held.companion;
        let settled = with_wallet_db_write_lock("sync_engine.transparent_ledger.apply", || {
            companion.apply_and_acknowledge(batch, db, trust)
        });
        match settled {
            Ok(applied) => Settlement::Acknowledged(applied.stats),
            Err(failure) => settlement(failure),
        }
    }
}

/// How the coordinator acts on a batch the adapter did not acknowledge.
/// Logs carry the variant only: nested errors can quote wallet history.
fn settlement(failure: ApplyFailure) -> Settlement {
    let ApplyFailure { error, stats, .. } = failure;
    let refusal = match error {
        ApplyError::Rejected { rejection, .. } => commit_refusal(&rejection),
        ApplyError::PolicyChanged => Refusal::Stale,
        ApplyError::NotEnabled => Refusal::NotEnabled,
        ApplyError::Unreconciled => Refusal::Unreconciled,
        ApplyError::Acknowledge(_) => {
            log::warn!("transparent PIR: acknowledgment failed after every commit applied");
            Refusal::Skip
        }
        ApplyError::NotReady(_) | ApplyError::StaleReceipt => {
            log::warn!("transparent PIR: the parked batch is not settleable");
            Refusal::Skip
        }
        error @ (ApplyError::OuterTransaction | ApplyError::Wallet(_)) => {
            return Settlement::Failed {
                stats,
                error: error.to_string(),
            };
        }
    };
    Settlement::Refused { stats, refusal }
}

/// Sets a pass's cancellation flag when dropped.
struct CancelOnDrop(Arc<AtomicBool>);

impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

/// Logs a failed pass by variant and reports it: an outage of the service or
/// of the companion directory, which no other account's pass would avoid, as
/// unavailable, anything else as failed.
fn fail(failure: Option<PassFailure>) -> SourceError {
    let name = failure.map_or("unknown", PassFailure::name);
    log::warn!("transparent PIR: pass failed ({name})");
    match failure {
        Some(PassFailure::Outage | PassFailure::CompanionDirectory) => SourceError::Unavailable,
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
    /// Runs the pass and returns the companion to park, with its lock: none
    /// when it could not be opened.
    fn run(
        self,
        slot: Slot,
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
            Err(_) => {
                let held = match slot {
                    Slot::Parked(held) => Some(*held),
                    Slot::Locked { .. } => None,
                };
                return (held, Err(PassFailure::Wallet));
            }
        };
        let mut held = match slot {
            Slot::Parked(held) => *held,
            Slot::Locked { path, lock } => match self.open(&db, &path) {
                Ok(companion) => Parked {
                    companion,
                    batch: None,
                    _lock: lock,
                },
                Err(failure) => return (None, Err(failure)),
            },
        };
        // The adapter honors only its latest pass's acknowledgment.
        held.batch = None;
        let result = self.recover(&db, &mut held.companion);
        (Some(held), result)
    }

    /// Opens the companion at `path`, first deleting the account's companions
    /// for other origins or schemas and those of accounts the wallet no longer
    /// has. A companion another pass holds is left for a later open.
    fn open(
        &self,
        db: &impl WalletRead<AccountId = AccountUuid>,
        path: &Path,
    ) -> Result<ReferenceRecovery, PassFailure> {
        let accounts: BTreeSet<_> = db
            .get_account_ids()
            .map_err(|_| PassFailure::Wallet)?
            .into_iter()
            .map(|account| account.expose_uuid())
            .collect();
        let dir = companion_dir(&self.db_path);
        prepare_companion_dir(&dir)?;
        let owner = self.account.expose_uuid();
        for (account, base) in companions(&dir).map_err(|_| PassFailure::Companion)? {
            if base != path && (account == owner || !accounts.contains(&account)) {
                if let Ok(_lock) = companion_lock(&base).try_lock_owned() {
                    if remove_files(&base).is_err() {
                        log::warn!("transparent PIR: could not delete a stale companion");
                    }
                }
            }
        }
        let config = recovery_config(self.account, &self.origin);
        match ReferenceRecovery::open(path, config.clone()) {
            Ok(companion) => Ok(companion),
            Err(error) => {
                log::warn!(
                    "transparent PIR: companion refused ({})",
                    PassFailure::from(&error).name()
                );
                // Only a storage failure SQLite confirms as corruption, or the
                // earlier format the adapter asks to recreate, is rebuilt:
                // never an identity, format or publication refusal.
                let rebuild = match &error {
                    RecoveryError::Failure(_)
                        if companion_health(path) == CompanionHealth::Corrupt =>
                    {
                        Rebuild::Corrupt
                    }
                    RecoveryError::Invalid(message) if message == LEGACY_FORMAT => Rebuild::Legacy,
                    _ => return Err(PassFailure::Companion),
                };
                if !first_rebuild(path) {
                    return Err(PassFailure::Companion);
                }
                log::warn!("transparent PIR: rebuilding an unusable companion once");
                rebuild_companion(path, config, rebuild).map_err(|error| {
                    log::warn!(
                        "transparent PIR: companion rebuild failed ({})",
                        error.name()
                    );
                    PassFailure::Companion
                })
            }
        }
    }

    /// One adapter pass, retried once on the same companion if the
    /// publication's set identity changed. The adapter has then reset the
    /// companion's store and kept its catalog, which still records the
    /// revisions the wallet holds, so the companion is never recreated.
    fn recover(
        &self,
        db: &crate::wallet::db::WalletDatabase,
        companion: &mut ReferenceRecovery,
    ) -> Result<RecoveryBatch<AccountUuid>, PassFailure> {
        let target = self.watch.target.ok_or(PassFailure::Invalid)?;
        let chain = WalletChain::new(db, target);
        let exit = || self.cancel.load(Ordering::SeqCst) || (self.clock)() >= self.deadline;
        let http =
            TransparentPirHttp::new(&self.origin, &exit, self.handle.clone(), MAX_RESPONSE_BYTES)
                .map_err(|_| PassFailure::Transport)?;
        #[cfg(test)]
        let http = self.transport.attach(http);
        let mut http = http;
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

/// When to ask again after a pass that stopped with `outcome`.
pub(super) fn continuation(outcome: Outcome) -> Continuation {
    match outcome {
        Outcome::Complete => Continuation::Complete,
        Outcome::More => Continuation::More,
        Outcome::Behind => Continuation::RetryAfter(BEHIND_RETRY),
        Outcome::Overloaded => Continuation::RetryAfter(OVERLOADED_RETRY),
        Outcome::Stalled => Continuation::Stalled,
    }
}

/// Blocks between `target` and the height `progress` covered through.
pub(super) fn behind_by(target: u32, progress: Progress) -> u32 {
    u32::try_from(u64::from(target).saturating_sub(progress.covered_through)).unwrap_or(u32::MAX)
}

/// The directory holding the companions of the wallet at `db_path`.
pub(crate) fn companion_dir(db_path: &str) -> PathBuf {
    PathBuf::from(format!("{db_path}{COMPANION_DIR_SUFFIX}"))
}

/// `account`'s companion for `origin` under the adapter's schema.
pub(super) fn companion_path(db_path: &str, account: AccountUuid, origin: &str) -> PathBuf {
    companion_dir(db_path).join(format!(
        "{}-{}.sqlite",
        account.expose_uuid(),
        binding_tag(origin)
    ))
}

/// Sixteen hex digits of `sha256(origin || 0 || SCHEMA)`: another origin or
/// schema names another companion rather than failing the open.
fn binding_tag(origin: &str) -> String {
    let digest = Sha256::new()
        .chain_update(origin.as_bytes())
        .chain_update([0])
        .chain_update(SCHEMA.as_bytes())
        .finalize();
    hex::encode(&digest[..8])
}

/// The companions in `dir`, by owning account and companion file path. Each
/// companion is listed once, whether its file or only a sidecar remains.
fn companions(dir: &Path) -> io::Result<BTreeSet<(uuid::Uuid, PathBuf)>> {
    let mut found = BTreeSet::new();
    for entry in std::fs::read_dir(dir)? {
        let name = entry?.file_name();
        if let Some((account, base)) = name.to_str().and_then(companion_name) {
            found.insert((account, dir.join(base)));
        }
    }
    Ok(found)
}

/// The owning account and companion file name of `name`, a companion file or
/// one of its sidecars: `{uuid}-{16 hex}.sqlite`, then an optional sidecar
/// suffix. Anything else in the directory is not a companion.
fn companion_name(name: &str) -> Option<(uuid::Uuid, &str)> {
    const UUID: usize = 36;
    const TAG: usize = 16;
    const EXTENSION: &str = ".sqlite";
    let base = UUID + 1 + TAG + EXTENSION.len();
    let (file, suffix) = (name.get(..base)?, name.get(base..)?);
    if !companion_suffixes().any(|known| known == suffix) {
        return None;
    }
    let account = uuid::Uuid::try_parse(file.get(..UUID)?).ok()?;
    let tag = file
        .get(UUID..)?
        .strip_prefix('-')?
        .strip_suffix(EXTENSION)?;
    tag.bytes()
        .all(|byte| byte.is_ascii_hexdigit())
        .then_some((account, file))
}

/// The lock serializing every pass, acknowledgment and removal on `path`.
fn companion_lock(path: &Path) -> Arc<tokio::sync::Mutex<()>> {
    let mut locks = COMPANION_LOCKS
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    locks.retain(|_, lock| Arc::strong_count(lock) > 1);
    locks.entry(path.to_owned()).or_default().clone()
}

/// The adapter's refusal of a companion in the earlier format, which it asks
/// to recreate.
const LEGACY_FORMAT: &str = "companion format v1; recreate";

/// What a companion file is before it is opened.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompanionHealth {
    /// No file yet, or one SQLite reads.
    Usable,
    /// SQLite reports the file is not a database, or its integrity check fails.
    Corrupt,
    /// Busy, locked, unreadable or otherwise not classified: never rebuilt.
    Unknown,
}

/// Classifies the companion file at `path` from a read-only connection, so a
/// busy or unreadable one is never mistaken for corruption.
fn companion_health(path: &Path) -> CompanionHealth {
    use rusqlite::{ErrorCode, OpenFlags};
    if !path.exists() {
        return CompanionHealth::Usable;
    }
    let corrupt = |error: &rusqlite::Error| {
        matches!(
            error.sqlite_error_code(),
            Some(ErrorCode::NotADatabase | ErrorCode::DatabaseCorrupt)
        )
    };
    let conn = match rusqlite::Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    ) {
        Ok(conn) => conn,
        Err(error) if corrupt(&error) => return CompanionHealth::Corrupt,
        Err(_) => return CompanionHealth::Unknown,
    };
    match conn.query_row("PRAGMA quick_check", [], |row| row.get::<_, String>(0)) {
        Ok(result) if result == "ok" => CompanionHealth::Usable,
        Ok(_) => CompanionHealth::Corrupt,
        Err(error) if corrupt(&error) => CompanionHealth::Corrupt,
        Err(_) => CompanionHealth::Unknown,
    }
}

/// Companions this process has rebuilt; each is rebuilt at most once.
static REBUILT: LazyLock<Mutex<BTreeSet<PathBuf>>> = LazyLock::new(Default::default);

/// Whether `path` has not been rebuilt by this process yet, recording that it
/// is now.
fn first_rebuild(path: &Path) -> bool {
    REBUILT
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .insert(path.to_owned())
}

/// Which unusable companion is rebuilt.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Rebuild {
    /// SQLite confirms corruption. Its binding and whole catalog must still
    /// be readable, so its identity is checked and its reconciliation
    /// records carried over.
    Corrupt,
    /// The earlier format, which the adapter refuses and asks to recreate.
    /// Its catalog has no records this format can use.
    Legacy,
}

/// Why rebuilding a companion failed. In each case the damaged companion is
/// kept as it was.
#[derive(Debug)]
enum RebuildError {
    /// The replacement could not be built or validated.
    Replacement,
    /// The damaged companion's binding or catalog could not be read whole,
    /// or its catalog does not fit the replacement: reconstruction cannot be
    /// shown safe.
    Unsalvageable,
    /// The damaged companion is bound to another account, origin or schema.
    Foreign,
    /// The validated replacement could not take the damaged one's place.
    Swap,
}

impl RebuildError {
    fn name(&self) -> &'static str {
        match self {
            RebuildError::Replacement => "the replacement could not be built",
            RebuildError::Unsalvageable => "its binding or catalog cannot be carried over",
            RebuildError::Foreign => "it is bound to another identity",
            RebuildError::Swap => "the replacement could not take its place",
        }
    }
}

/// A damaged companion's catalog rows, with their column names.
type SalvagedCatalog = (Vec<String>, Vec<Vec<rusqlite::types::Value>>);

/// Replaces the unusable companion at `path`, under its held path lock.
///
/// The replacement is built beside it, at `{path}.rebuild`, and takes the
/// damaged companion's place, by one atomic rename, only once it is complete:
/// its binding equals the damaged one's, every catalog row of a corrupt
/// companion is restored into it, and the adapter opens it. Until then the
/// damaged companion is untouched, and any doubt keeps it.
fn rebuild_companion(
    path: &Path,
    config: RecoveryConfig,
    rebuild: Rebuild,
) -> Result<ReferenceRecovery, RebuildError> {
    let staging = sibling(path, ".rebuild");
    remove_database(&staging).map_err(|_| RebuildError::Replacement)?;
    let built = (|| {
        drop(
            ReferenceRecovery::open(&staging, config.clone())
                .map_err(|_| RebuildError::Replacement)?,
        );
        let expected = read_binding(&staging).ok_or(RebuildError::Replacement)?;
        match (read_binding(path), rebuild) {
            (Some(binding), _) if binding == expected => {}
            (Some(_), _) => return Err(RebuildError::Foreign),
            // The earlier format may predate the binding row.
            (None, Rebuild::Legacy) => {}
            (None, Rebuild::Corrupt) => return Err(RebuildError::Unsalvageable),
        }
        if rebuild == Rebuild::Corrupt {
            let (columns, rows) = salvage_catalog(path).ok_or(RebuildError::Unsalvageable)?;
            restore_catalog(&staging, &columns, &rows)?;
        }
        drop(
            ReferenceRecovery::open(&staging, config.clone())
                .map_err(|_| RebuildError::Replacement)?,
        );
        Ok(())
    })();
    if let Err(error) = built {
        let _ = remove_database(&staging);
        return Err(error);
    }
    swap_in(path, &staging, |from, to| std::fs::rename(from, to))?;
    ReferenceRecovery::open(path, config).map_err(|_| RebuildError::Swap)
}

/// Puts the validated replacement at `staging` in the place of the damaged
/// companion at `path` with one atomic rename over it, so a crash leaves
/// either the original or the replacement, never neither. Refused, keeping
/// both, while either has SQLite sidecars: a write-ahead log or journal may
/// hold the original's committed data, which a rename of the main file alone
/// would separate from it.
fn swap_in(
    path: &Path,
    staging: &Path,
    rename: impl Fn(&Path, &Path) -> io::Result<()>,
) -> Result<(), RebuildError> {
    let has_sidecars = |base: &Path| SIDECARS.iter().any(|suffix| sibling(base, suffix).exists());
    if has_sidecars(path) || has_sidecars(staging) {
        let _ = remove_database(staging);
        return Err(RebuildError::Unsalvageable);
    }
    rename(staging, path).map_err(|_| RebuildError::Swap)
}

/// `base` with `suffix` appended to its file name.
fn sibling(base: &Path, suffix: &str) -> PathBuf {
    let mut path = base.as_os_str().to_owned();
    path.push(suffix);
    path.into()
}

/// A read-only connection to the companion file at `path`.
fn read_only(path: &Path) -> Option<rusqlite::Connection> {
    use rusqlite::OpenFlags;
    rusqlite::Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .ok()
}

/// The account, origin and schema binding the companion at `path` records,
/// when it can be read.
fn read_binding(path: &Path) -> Option<Vec<u8>> {
    read_only(path)?
        .query_row(
            "SELECT value FROM pir_bridge_binding WHERE key = 'account-source'",
            [],
            |row| row.get(0),
        )
        .ok()
}

/// Every catalog row of the companion at `path`, with the column names, when
/// the whole catalog can be read. Nothing otherwise.
fn salvage_catalog(path: &Path) -> Option<SalvagedCatalog> {
    let conn = read_only(path)?;
    let mut statement = conn.prepare("SELECT * FROM pir_bridge_catalog").ok()?;
    let columns: Vec<String> = statement
        .column_names()
        .into_iter()
        .map(str::to_owned)
        .collect();
    let rows = statement
        .query_map([], |row| {
            (0..columns.len())
                .map(|index| row.get::<_, rusqlite::types::Value>(index))
                .collect::<Result<Vec<_>, _>>()
        })
        .ok()?
        .collect::<Result<Vec<_>, _>>()
        .ok()?;
    Some((columns, rows))
}

/// Restores salvaged catalog rows into the new companion at `path`, in one
/// transaction, and checks that every row arrived. A catalog whose columns
/// differ from the new companion's cannot be carried over.
fn restore_catalog(
    path: &Path,
    columns: &[String],
    rows: &[Vec<rusqlite::types::Value>],
) -> Result<(), RebuildError> {
    let restore = || -> rusqlite::Result<Result<(), RebuildError>> {
        let mut conn = rusqlite::Connection::open(path)?;
        let current: Vec<String> = conn
            .prepare("SELECT * FROM pir_bridge_catalog")?
            .column_names()
            .into_iter()
            .map(str::to_owned)
            .collect();
        if current != columns {
            return Ok(Err(RebuildError::Unsalvageable));
        }
        let tx = conn.transaction()?;
        {
            let placeholders = vec!["?"; columns.len()].join(", ");
            let mut insert = tx.prepare(&format!(
                "INSERT INTO pir_bridge_catalog VALUES ({placeholders})"
            ))?;
            for row in rows {
                insert.execute(rusqlite::params_from_iter(row))?;
            }
        }
        let restored: i64 = tx.query_row("SELECT COUNT(*) FROM pir_bridge_catalog", [], |row| {
            row.get(0)
        })?;
        if usize::try_from(restored).ok() != Some(rows.len()) {
            return Ok(Err(RebuildError::Unsalvageable));
        }
        tx.commit()?;
        Ok(Ok(()))
    };
    restore().unwrap_or(Err(RebuildError::Unsalvageable))
}

/// Makes `dir` a directory for companions. Anything else already at that
/// path, such as a regular file, is left exactly as it is, outside every
/// lifecycle this module owns, and the directory is unusable for every
/// account: the run stops as unavailable until it is removed. Nothing inside
/// an existing directory is touched here.
fn prepare_companion_dir(dir: &Path) -> Result<(), PassFailure> {
    match std::fs::symlink_metadata(dir) {
        Ok(meta) if meta.is_dir() => Ok(()),
        Ok(_) => {
            log::warn!(
                "transparent PIR: something other than a directory holds the companion path"
            );
            Err(PassFailure::CompanionDirectory)
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            std::fs::create_dir_all(dir).map_err(|_| PassFailure::CompanionDirectory)
        }
        Err(_) => Err(PassFailure::CompanionDirectory),
    }
}

/// Whether listing the companion directory failed only because there is no
/// directory: nothing to sweep or remove.
fn no_companions(error: &io::Error) -> bool {
    matches!(
        error.kind(),
        io::ErrorKind::NotFound | io::ErrorKind::NotADirectory
    )
}

/// Deletes the companion file at `base` and its sidecars. Missing files are
/// not an error.
fn remove_files(base: &Path) -> io::Result<()> {
    for suffix in companion_suffixes() {
        remove_file(&sibling(base, &suffix))?;
    }
    Ok(())
}

/// Deletes the SQLite file at `path` and its sidecars only.
fn remove_database(path: &Path) -> io::Result<()> {
    for suffix in std::iter::once("").chain(SIDECARS) {
        remove_file(&sibling(path, suffix))?;
    }
    Ok(())
}

/// Deletes `path`; a missing file is not an error.
fn remove_file(path: &Path) -> io::Result<()> {
    match std::fs::remove_file(path) {
        Err(error) if error.kind() != io::ErrorKind::NotFound => Err(error),
        _ => Ok(()),
    }
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

/// Deletes the companions, with their sidecars, of accounts the wallet at
/// `db_path` no longer has, so a removal that failed after an account was
/// deleted converges at the next sync start whether or not private recovery is
/// still selected.
///
/// Companions are listed before the accounts are read, so one created for an
/// account added meanwhile is never mistaken for an orphan. A companion whose
/// lock is held is left for a later sweep. Attempts every orphan and then
/// returns the first failure; an unreadable account list deletes nothing.
pub(crate) fn remove_orphan_companions(db_path: &str) -> Result<(), String> {
    let found = match companions(&companion_dir(db_path)) {
        Ok(found) => found,
        // Nothing to sweep; the next pass moves a file in its place aside.
        Err(error) if no_companions(&error) => return Ok(()),
        Err(error) => {
            return Err(format!(
                "Failed to list transparent PIR companions: {error}"
            ))
        }
    };
    if found.is_empty() {
        return Ok(());
    }
    let accounts = crate::wallet::keys::list_account_uuids_from_db(db_path)?
        .iter()
        .map(|account| uuid::Uuid::try_parse(account))
        .collect::<Result<BTreeSet<_>, _>>()
        .map_err(|error| format!("Invalid account UUID: {error}"))?;
    let mut first_error = None;
    for (_, base) in found
        .into_iter()
        .filter(|(owner, _)| !accounts.contains(owner))
    {
        let Ok(_lock) = companion_lock(&base).try_lock_owned() else {
            continue;
        };
        if let Err(error) = remove_files(&base) {
            first_error.get_or_insert_with(|| {
                format!("Failed to remove an orphan transparent PIR companion: {error}")
            });
        }
    }
    first_error.map_or(Ok(()), Err)
}

/// [`remove_companions`], waiting at most `wait` for each companion's lock.
pub(super) fn remove_account_companions(
    db_path: &str,
    account_uuid: &str,
    wait: Duration,
) -> Result<(), String> {
    let account = uuid::Uuid::try_parse(account_uuid)
        .map_err(|error| format!("Invalid account UUID: {error}"))?;
    let found = match companions(&companion_dir(db_path)) {
        Ok(found) => found,
        Err(error) if no_companions(&error) => return Ok(()),
        Err(error) => {
            return Err(format!(
                "Failed to list transparent PIR companions: {error}"
            ))
        }
    };
    for (_, base) in found.into_iter().filter(|(owner, _)| *owner == account) {
        let _lock = lock_within(&companion_lock(&base), wait)
            .ok_or_else(|| "A transparent PIR companion is in use".to_owned())?;
        remove_files(&base)
            .map_err(|error| format!("Failed to remove a transparent PIR companion: {error}"))?;
    }
    Ok(())
}

/// Takes `lock` from synchronous code, waiting at most `wait`.
fn lock_within(lock: &Arc<tokio::sync::Mutex<()>>, wait: Duration) -> Option<OwnedMutexGuard<()>> {
    let deadline = Instant::now() + wait;
    loop {
        if let Ok(guard) = lock.clone().try_lock_owned() {
            return Some(guard);
        }
        if Instant::now() >= deadline {
            return None;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[cfg(test)]
mod rebuild_tests {
    use super::*;

    fn write(path: &Path, bytes: &[u8]) {
        std::fs::write(path, bytes).unwrap();
    }

    /// A failed rename leaves the original as it was; a successful one leaves
    /// only the replacement.
    #[test]
    fn the_replacement_takes_the_place_of_the_original_atomically() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("companion.sqlite");
        write(&path, b"original");
        let staging = sibling(&path, ".rebuild");
        write(&staging, b"replacement");
        assert!(matches!(
            swap_in(&path, &staging, |_, _| Err(io::Error::other("injected"))),
            Err(RebuildError::Swap)
        ));
        assert_eq!(std::fs::read(&path).unwrap(), b"original");

        swap_in(&path, &staging, |from, to| std::fs::rename(from, to)).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"replacement");
        assert!(!staging.exists());
    }

    /// While the original or the replacement has a write-ahead log or
    /// journal, the swap is refused and the original kept with its sidecars.
    #[test]
    fn a_companion_with_sidecars_is_never_swapped() {
        for (owner, sidecar) in [
            ("original", "-wal"),
            ("original", "-journal"),
            ("staging", "-wal"),
        ] {
            let dir = tempfile::tempdir().unwrap();
            let path = dir.path().join("companion.sqlite");
            write(&path, b"original");
            let staging = sibling(&path, ".rebuild");
            write(&staging, b"replacement");
            let base = if owner == "original" { &path } else { &staging };
            write(&sibling(base, sidecar), b"log");
            assert!(matches!(
                swap_in(&path, &staging, |from, to| std::fs::rename(from, to)),
                Err(RebuildError::Unsalvageable)
            ));
            assert_eq!(std::fs::read(&path).unwrap(), b"original");
            if owner == "original" {
                assert_eq!(std::fs::read(sibling(&path, sidecar)).unwrap(), b"log");
            }
        }
    }

    /// Even a dangling sidecar name must prevent replacement: absence of its
    /// target is not proof that the sidecar can be ignored.
    #[cfg(unix)]
    #[test]
    fn a_dangling_sidecar_is_never_ignored() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("companion.sqlite");
        write(&path, b"original");
        let staging = sibling(&path, ".rebuild");
        write(&staging, b"replacement");
        let sidecar = sibling(&path, "-wal");
        std::os::unix::fs::symlink(dir.path().join("missing"), &sidecar).unwrap();
        assert!(matches!(
            swap_in(&path, &staging, |from, to| std::fs::rename(from, to)),
            Err(RebuildError::Unsalvageable)
        ));
        assert_eq!(std::fs::read(&path).unwrap(), b"original");
        assert!(std::fs::symlink_metadata(sidecar)
            .unwrap()
            .file_type()
            .is_symlink());
    }

    /// A failed metadata lookup must stop before rename. Here a regular file
    /// in a parent component makes the lookup fail rather than report absence.
    #[test]
    fn uncertain_sidecar_metadata_stops_before_rename() {
        let dir = tempfile::tempdir().unwrap();
        let parent = dir.path().join("not-a-directory");
        write(&parent, b"kept");
        let path = parent.join("companion.sqlite");
        let staging = dir.path().join("replacement.sqlite");
        write(&staging, b"replacement");
        assert!(matches!(
            swap_in(&path, &staging, |_, _| panic!(
                "metadata failure reached rename"
            )),
            Err(RebuildError::Unsalvageable)
        ));
        assert_eq!(std::fs::read(&parent).unwrap(), b"kept");
    }

    /// A rebuild's replacement belongs to its companion: listed with it, and
    /// removed with it.
    #[test]
    fn rebuild_files_share_their_companions_lifecycle() {
        let account = uuid::Uuid::new_v4();
        let base = format!("{account}-{}.sqlite", "0".repeat(16));
        for suffix in [".rebuild", ".rebuild-wal", ".rebuild-shm"] {
            assert_eq!(
                companion_name(&format!("{base}{suffix}")),
                Some((account, base.as_str()))
            );
        }
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(&base);
        for suffix in ["", "-wal", ".rebuild", ".rebuild-journal"] {
            write(&sibling(&path, suffix), b"x");
        }
        remove_files(&path).unwrap();
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
    }
}

/// Test seam: the transport a source for one wallet file sends through,
/// standing in for the network. Keyed by path, so parallel tests on other
/// wallets are unaffected. A source whose wallet has none is unavailable.
#[cfg(test)]
pub(crate) mod test_transport {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex, OnceLock, PoisonError};

    use crate::wallet::sync_engine::enhancement::{
        RequestObserver, RoutePolicy, TransparentPirHttp,
    };

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
            http: TransparentPirHttp<'a, F>,
        ) -> TransparentPirHttp<'a, F> {
            self.routes
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .push(http.route_policy());
            http.with_observer(self.observer.clone())
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
