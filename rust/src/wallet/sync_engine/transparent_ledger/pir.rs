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
//! account removes its companion with [`remove_companions`].
//!
//! One lock per companion path serializes every pass, acknowledgment and
//! removal on it across sources. A source parks each companion it opened with
//! that lock until the source is dropped, so a pass and its acknowledgment see
//! the same companion and nothing removes it in between.
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
    BatchState, Outcome, Progress, RecoveryBatch, RecoveryConfig, RecoveryError, ReferenceRecovery,
    WalletChain, SCHEMA,
};
use zcash_client_backend::data_api::{transparent_ledger::TransparentWatchSet, WalletRead};
use zcash_client_sqlite::AccountUuid;

use super::{Continuation, RecoverySource, SourceBatch, SourceError, SourceRequest};
use crate::wallet::db::{open_wallet_db_readonly_with_timeout, READ_DB_BUSY_TIMEOUT};
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
    /// The last pass's `Ready` batch until it is acknowledged. Its commits
    /// went to the coordinator; the adapter acknowledges from what it recorded.
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
    Transport,
    Invalid,
    Failure,
    PublicationChanged,
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
    /// retried once on the same companion. Commits come back only in a `Ready`
    /// batch, which [`acknowledge`](Self::acknowledge) settles once they are
    /// applied; a later pass on the account supersedes an unacknowledged one.
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
                Ok(mut batch) => {
                    let target = watch.target.map_or(0, |target| u32::from(target.height));
                    let next = continuation(batch.progress.outcome);
                    let behind = behind_by(target, batch.progress);
                    log::info!(
                        "transparent PIR: pass {:?}, {:?}, {behind} blocks behind",
                        batch.state,
                        batch.progress.outcome
                    );
                    Ok(match batch.state {
                        BatchState::Ready => {
                            let commits = std::mem::take(&mut batch.commits);
                            let retired = !batch.retired_revisions().is_empty();
                            held.batch = Some(batch);
                            SourceBatch::Ready {
                                commits,
                                retired,
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

    /// Settles `account`'s last `Ready` batch after every commit applied:
    /// as reconciled when every commit went through the trusted operation,
    /// otherwise as applied, which the adapter refuses for a batch with
    /// retired revisions.
    ///
    /// Runs on a blocking thread under the companion's parked lock. Fails when
    /// no unacknowledged `Ready` batch is parked for the account, or when the
    /// adapter refuses it.
    async fn acknowledge(&self, account: AccountUuid, reconciled: bool) -> Result<(), SourceError> {
        let mut parked = self.parked.lock().await;
        let Some(mut held) = parked.remove(&account) else {
            log::warn!("transparent PIR: nothing to acknowledge");
            return Err(SourceError::Failed);
        };
        let Some(batch) = held.batch.take() else {
            parked.insert(account, held);
            log::warn!("transparent PIR: nothing to acknowledge");
            return Err(SourceError::Failed);
        };
        let joined = tokio::task::spawn_blocking(move || {
            let acknowledged = if reconciled {
                held.companion.acknowledge_reconciled(&batch)
            } else {
                held.companion.acknowledge_applied(&batch)
            };
            (held, acknowledged)
        })
        .await;
        let Ok((held, acknowledged)) = joined else {
            log::error!("transparent PIR: acknowledgment panicked");
            return Err(SourceError::Failed);
        };
        parked.insert(account, held);
        acknowledged.map_err(|error| {
            log::warn!(
                "transparent PIR: acknowledgment refused ({})",
                PassFailure::from(&error).name()
            );
            SourceError::Failed
        })
    }
}

/// Sets a pass's cancellation flag when dropped.
struct CancelOnDrop(Arc<AtomicBool>);

impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        self.0.store(true, Ordering::SeqCst);
    }
}

/// Logs a failed pass by variant and reports it as failed.
fn fail(failure: Option<PassFailure>) -> SourceError {
    let name = failure.map_or("unknown", PassFailure::name);
    log::warn!("transparent PIR: pass failed ({name})");
    SourceError::Failed
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
        std::fs::create_dir_all(&dir).map_err(|_| PassFailure::Companion)?;
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
        ReferenceRecovery::open(path, recovery_config(self.account, &self.origin)).map_err(
            |error| {
                log::warn!(
                    "transparent PIR: companion refused ({})",
                    PassFailure::from(&error).name()
                );
                PassFailure::Companion
            },
        )
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
        result.map_err(|error| PassFailure::from(&error))
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
    if !(suffix.is_empty() || SIDECARS.contains(&suffix)) {
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

/// Deletes the companion file at `base` and its sidecars. Missing files are
/// not an error.
fn remove_files(base: &Path) -> io::Result<()> {
    for suffix in std::iter::once("").chain(SIDECARS) {
        let mut path = base.as_os_str().to_owned();
        path.push(suffix);
        match std::fs::remove_file(&path) {
            Err(error) if error.kind() != io::ErrorKind::NotFound => return Err(error),
            _ => {}
        }
    }
    Ok(())
}

/// Deletes every companion of the account `account_uuid` in the wallet at
/// `db_path`, with its sidecars.
///
/// Waits up to five seconds for a pass or a parked source holding one; account
/// deletion runs with sync paused, so a wait that times out is a failure, and
/// the companion is left for the next open to delete.
pub(crate) fn remove_companions(db_path: &str, account_uuid: &str) -> Result<(), String> {
    remove_account_companions(db_path, account_uuid, REMOVE_WAIT)
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
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
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
