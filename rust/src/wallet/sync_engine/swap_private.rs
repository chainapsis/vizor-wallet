//! Bounded Receiver PIR work, independent of the ordinary sync task.
//! Network requests never own a database handle. The library fences every committed
//! response by account generation, history revision and local chain identity.
use super::enhancement::transport::{RoutedHttpError, RoutedTransport};
use crate::wallet::{
    db::{
        open_existing_wallet_db_with_timeout, open_existing_wallet_raw_conn_with_timeout,
        with_wallet_db_write_lock, WalletDatabase, WALLET_DB_BUSY_TIMEOUT,
    },
    network::WalletNetwork,
    one_time_ivk,
    pir_config::{client_origin, process_selection, PirProduct},
};
use rusqlite::OptionalExtension;
use std::{
    collections::HashSet,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Mutex,
    },
    time::Duration,
};
use zakura_one_time_ivk::KeyId;
use zakura_pir_client::receiver::{
    blocks::{Head, Range, MAX_RANGE_BLOCKS},
    inventory::Inventory,
    lookup_with, native, session, shards,
    transport::{DescriptorStore, Inventories, InventoryClient, Transport},
    Pace, DIRECTORY_ROWS, MAINNET_GENESIS,
};
use zcash_client_backend::data_api::{
    one_time_ivk::restore::{
        DiscoveryWork, FilterOutcome, FilterSpan, RecoveryStatus, RecoveryToken,
    },
    transparent_ledger::ChainPoint,
    WalletRead as _,
};
use zcash_client_sqlite::AccountUuid;
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

static RUNNING: AtomicBool = AtomicBool::new(false);
static CANCEL: AtomicU64 = AtomicU64::new(0);
/// Whether the last round's filter work ran past its deadline, leaving lookups no time.
/// The next round skips filters, so essential work gets its turn.
static FILTERS_OVERRAN: AtomicBool = AtomicBool::new(false);

/// Cancels the current bounded worker without deleting its durable queue.
pub(crate) fn cancel_recovery() {
    CANCEL.fetch_add(1, Ordering::SeqCst);
}

/// Why a recovery round stopped early. Durable work stays pending either way.
#[derive(Debug)]
pub(crate) enum RecoveryError {
    /// The receiver service speaks a format this app does not support. Every software
    /// account recorded it (see `require_one_time_upgrade`).
    UpgradeRequired,
    /// A history check could not start because the wallet has not scanned the
    /// receiver service's latest publication yet. It can start once sync catches up.
    NotCaughtUp,
    /// A history check could not start because the receiver service's latest
    /// publication ends below this wallet's birthday, as it does for a fresh wallet. It
    /// can start once the service publishes past the birthday.
    ReceiverBehind,
    /// Any other failure, as display text.
    Other(String),
    /// A history check failed after it started its jobs, which later rounds keep running.
    Started(Box<RecoveryError>),
}

impl From<String> for RecoveryError {
    /// Any failure other than an upgrade, as display text.
    fn from(message: String) -> Self {
        Self::Other(message)
    }
}

impl From<&str> for RecoveryError {
    /// Any failure other than an upgrade, as display text.
    fn from(message: &str) -> Self {
        Self::Other(message.into())
    }
}

impl std::fmt::Display for RecoveryError {
    /// The text the app shows for this failure.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UpgradeRequired => f.write_str("The swap recovery service needs a newer app."),
            Self::NotCaughtUp => f.write_str(
                "Swap history check has not started. Wait for wallet sync to catch up and try again.",
            ),
            Self::ReceiverBehind => f.write_str(
                "The swap recovery service hasn't caught up with this wallet yet. Try again in a few minutes.",
            ),
            Self::Other(message) => f.write_str(message),
            Self::Started(error) => error.fmt(f),
        }
    }
}

/// Why work a round left can't run yet (see [`Round::wait`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Wait {
    /// No private query server is selected.
    Server,
    /// The wallet hasn't scanned the receiver's latest publication, or sees another
    /// block at its end.
    Sync,
    /// The receiver hasn't published far enough yet: past the wallet birthday, or past
    /// a block a queued lookup needs.
    Publication,
    /// A failed lookup is waiting out its retry delay.
    Backoff,
}

/// What one finished round did (see `api::one_time_ivk::SwapRecoveryRound`).
#[derive(Debug, Default)]
pub(crate) struct Round {
    /// Whether the round recorded a lookup page, which can credit or queue a payment, or
    /// settle an address.
    pub(crate) changed: bool,
    /// Whether the round accepted a receiver inventory, so the service speaks a format
    /// this app supports.
    pub(crate) checked: bool,
    /// Whether work is left that another round can run right away, such as lookups or
    /// filters this round's time or step limit didn't reach.
    pub(crate) more: bool,
    /// Why work is left that no round can run yet, if any. Never set with `more`.
    pub(crate) wait: Option<Wait>,
    /// Whether found payments wait for ordinary sync, or a rescan it queued, to admit
    /// them, as one over a stretch the scan didn't cover for spends does.
    pub(crate) awaiting_admission: bool,
    /// Sealed-shard filter traversals. Screening the round's due lookups together
    /// keeps this to one per filter, plus any for addresses exposed mid-round.
    pub(super) filter_traversals: u64,
}

/// What one filter step did (see [`filter_step`] and
/// `api::one_time_ivk::SwapFilterStep`).
#[derive(Debug, Default)]
pub(crate) struct Step {
    /// Whether filter work is left that only a round can finish: a filter request failed,
    /// the gap to the scanned tip is more than one range, the head serves another history
    /// revision, or an account needs a complete check or a range from its own marker.
    pub(crate) needs_round: bool,
}

/// Releases worker admission even when the future is cancelled or times out.
struct Running;
impl Running {
    /// Takes the worker admission a round and a filter step share, or fails while either
    /// runs.
    fn admit() -> Result<Self, &'static str> {
        RUNNING
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map(|_| Self)
            .map_err(|_| "A swap recovery check is already running.")
    }
}
impl Drop for Running {
    /// Allows the next independent check after this worker has stopped.
    fn drop(&mut self) {
        RUNNING.store(false, Ordering::SeqCst);
    }
}

/// The receiver directory uses the same Tor-aware transport as Vizor's other private
/// services.
struct SwapTransport<'a, F> {
    http: RoutedTransport<'a, F>,
}
impl<'a, F> SwapTransport<'a, F> {
    /// A transport that stops when `should_exit` does.
    fn new(should_exit: &'a F) -> Self {
        Self {
            http: RoutedTransport::new(should_exit),
        }
    }
}
/// Maps a receiver directory failure: a session conflict means its publication changed,
/// and anything else, including overload (HTTP 429), is a retryable transport failure.
/// Only a failure in transit is retried within the round (see [`in_transit`]).
fn receiver_error(error: RoutedHttpError) -> session::Error {
    match error {
        error if error.is_session_conflict() => session::Error::Revision,
        RoutedHttpError::HttpStatus(status) => session::Error::Transport(format!("HTTP {status}")),
        RoutedHttpError::Cancelled => session::Error::Transport("Cancelled".into()),
        RoutedHttpError::Failed(error) => session::Error::Transport(error.to_string()),
    }
}
impl<F: Fn() -> bool> Transport for SwapTransport<'_, F> {
    /// A bounded public read over the wallet's route.
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, session::Error> {
        self.http
            .bytes(
                http::Method::GET,
                url,
                vec![],
                limit,
                STALL_TIMEOUT,
                REQUEST_LIMIT,
            )
            .await
            .map_err(receiver_error)
    }
    /// A bounded encrypted query over the wallet's route.
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, session::Error> {
        self.http
            .bytes(
                http::Method::POST,
                url,
                body,
                limit,
                STALL_TIMEOUT,
                REQUEST_LIMIT,
            )
            .await
            .map_err(receiver_error)
    }
}

/// Whether `error` is a receiver request that failed in transit, such as a broken Tor
/// circuit, a failed connection or a timeout, which a second attempt may avoid. An
/// HTTP status answer or a cancellation, as [`receiver_error`] words them, is not.
fn in_transit(error: &session::Error) -> bool {
    matches!(error, session::Error::Transport(message)
        if !message.starts_with("HTTP ") && message != "Cancelled" && message != TIME_UP)
}

/// Records one lookup step reads, so an address with a long history in one segment is
/// credited a few records at a time over a slow transport. Each resumed step reads the
/// directory entry again, one extra directory query.
const STEP_RECORDS: std::num::NonZeroUsize = std::num::NonZeroUsize::new(4).unwrap();

/// The error of a request [`Gated`] refused because the round's time is up.
const TIME_UP: &str = "Receiver round time is up";

/// Whether `error` is a request refused because the round's time is up (see [`Gated`]).
fn time_up(error: &session::Error) -> bool {
    matches!(error, session::Error::Transport(message) if message == TIME_UP)
}

/// A round's receiver transport, which starts no request once `deadline` has passed.
/// A request already sent goes on (see [`ROUND_DEADLINE`]).
struct Gated<'a, T> {
    inner: &'a T,
    deadline: tokio::time::Instant,
}

impl<T> Gated<'_, T> {
    /// Refuses a new request once the round's time is up.
    fn admit(&self) -> Result<(), session::Error> {
        if tokio::time::Instant::now() >= self.deadline {
            return Err(session::Error::Transport(TIME_UP.into()));
        }
        Ok(())
    }
}

impl<T: Transport> Transport for Gated<'_, T> {
    /// Sends the read if the round's time isn't up.
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, session::Error> {
        self.admit()?;
        self.inner.get(url, limit).await
    }

    /// Sends the query if the round's time isn't up.
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, session::Error> {
        self.admit()?;
        self.inner.post(url, body, limit).await
    }
}

/// Runs the receiver step `step`, and runs it once more if it failed in transit (see
/// [`in_transit`]) while the round started at `generation` is still current. Each run
/// builds its own requests, so a repeated PIR query is a fresh encryption rather than the
/// same bytes on a new circuit. A second run the round's time no longer admits returns
/// the first failure.
async fn retried<R, F: std::future::Future<Output = Result<R, session::Error>>>(
    generation: u64,
    step: impl Fn() -> F,
) -> Result<R, session::Error> {
    match step().await {
        Err(error) if in_transit(&error) && CANCEL.load(Ordering::SeqCst) == generation => {
            log::debug!("Retrying a receiver request that failed in transit: {error}");
            match step().await {
                Err(retry) if time_up(&retry) => Err(error),
                result => result,
            }
        }
        result => result,
    }
}

/// How long one round may start new receiver requests (see [`Gated`]) and lookup steps
/// (see [`drain`]). Budgets end only between requests: one already sent finishes, or
/// fails once it stalls (see [`STALL_TIMEOUT`]), so a slow transfer that is still
/// arriving over Tor isn't cut off. A lookup step already started finishes too, since
/// it's recorded whole or not at all. Durable work left at the deadline resumes in the
/// next round.
const ROUND_DEADLINE: Duration = Duration::from_secs(120);

/// How long a receiver request may go without its headers or the next part of its body
/// before it counts as stalled and fails.
const STALL_TIMEOUT: Duration = Duration::from_secs(30);

/// The most time one receiver request may take while it keeps arriving. Receiver
/// responses are a few megabytes at most, so this only stops a server that trickles
/// bytes forever.
const REQUEST_LIMIT: Duration = Duration::from_secs(600);

/// The most time one round spends on all its optional filter downloads together (see
/// [`FilterBudget`]).
const FILTER_BUDGET: Duration = Duration::from_secs(40);

/// The route the library fetches sealed-shard filters from (see `InventoryClient::filter`).
const SHARD_FILTER_ROUTE: &str = "/receiver/v1/shard-filters/";

/// The time one round may start optional filter requests: the rolling block-filter head
/// and batches, and sealed-shard filters. Filters only save PIR work, and they are
/// fetched one at a time, per account and per shard, so many of them could otherwise
/// fill the round before any PIR work commits. No filter request starts once this
/// deadline passes or one failed in transit, as a stalled one does, this round. A
/// request already sent finishes, and one that ends past the round's deadline, whether it
/// succeeded or failed, makes the next round skip filters (see [`FILTERS_OVERRAN`]).
struct FilterBudget {
    deadline: tokio::time::Instant,
    round_end: tokio::time::Instant,
    stalled: AtomicBool,
}

impl FilterBudget {
    /// A budget for a round ending at `deadline`: [`FILTER_BUDGET`] at most, and never
    /// more than a third of the time left, so the rest stays for PIR.
    fn new(deadline: tokio::time::Instant) -> Self {
        let now = tokio::time::Instant::now();
        Self {
            deadline: now + FILTER_BUDGET.min(deadline.saturating_duration_since(now) / 3),
            round_end: deadline,
            stalled: AtomicBool::new(false),
        }
    }

    /// Runs the optional filter request `request` to its end. Refuses it without a
    /// request once the budget is spent or a filter failed in transit, and marks one
    /// that fails in transit (see [`in_transit`]) as stalled.
    async fn run<R>(
        &self,
        request: impl std::future::Future<Output = Result<R, session::Error>>,
    ) -> Result<R, String> {
        if tokio::time::Instant::now() >= self.deadline || self.stalled.load(Ordering::SeqCst) {
            return Err("Receiver filters unavailable this round.".into());
        }
        let result = request.await;
        if tokio::time::Instant::now() >= self.round_end {
            FILTERS_OVERRAN.store(true, Ordering::SeqCst);
        }
        result.map_err(|error| {
            if in_transit(&error) {
                self.stalled.store(true, Ordering::SeqCst);
            }
            error.to_string()
        })
    }
}

/// One round's lookup transport. The library retries a sealed-shard filter download on
/// every later step, so each one draws on the round's [`FilterBudget`], and a filter that
/// failed is refused for the rest of the round without another request. Other requests
/// pass through unchanged.
struct RoundTransport<'a, T> {
    inner: &'a T,
    budget: &'a FilterBudget,
    failed: Mutex<HashSet<String>>,
}

impl<'a, T> RoundTransport<'a, T> {
    /// A fresh round over `inner` whose filters draw on `budget`.
    fn new(inner: &'a T, budget: &'a FilterBudget) -> Self {
        Self {
            inner,
            budget,
            failed: Mutex::new(HashSet::new()),
        }
    }
}

impl<T: Transport> Transport for RoundTransport<'_, T> {
    /// Bounds and remembers sealed-shard filter downloads, and passes other reads through.
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, session::Error> {
        if !url.contains(SHARD_FILTER_ROUTE) {
            return self.inner.get(url, limit).await;
        }
        if self.failed.lock().unwrap().contains(url) {
            return Err(session::Error::Transport(
                "Receiver filter unavailable this round.".into(),
            ));
        }
        let result = self.budget.run(self.inner.get(url, limit)).await;
        if result.is_err() {
            self.failed.lock().unwrap().insert(url.to_owned());
        }
        result.map_err(session::Error::Transport)
    }

    /// Passes encrypted queries through unchanged.
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, session::Error> {
        self.inner.post(url, body, limit).await
    }
}

/// Verified inventory descriptors kept in the wallet database, so a capture downloads
/// only chunks that can have changed. Losing the row only costs a full capture. Like
/// [`wallet`], it never creates a database and writes nothing after a cancellation, so
/// a capture still in flight cannot recreate a wallet a reset deleted.
pub(super) struct DescriptorTable<'a> {
    path: &'a str,
    generation: u64,
}

impl<'a> DescriptorTable<'a> {
    /// The store of the wallet at `path`, for the worker started at `generation`.
    pub(super) fn new(path: &'a str, generation: u64) -> Self {
        Self { path, generation }
    }
}

impl DescriptorStore for DescriptorTable<'_> {
    /// Reads the saved descriptors. A missing table or unreadable row is no cache.
    fn load(&self) -> Option<Vec<u8>> {
        let conn =
            open_existing_wallet_raw_conn_with_timeout(self.path, WALLET_DB_BUSY_TIMEOUT).ok()?;
        conn.query_row(
            "SELECT descriptors FROM ext_vizor_receiver_inventory WHERE id = 0",
            [],
            |r| r.get(0),
        )
        .optional()
        .ok()
        .flatten()
    }

    /// Replaces the saved descriptors. A failed save is dropped, as the store allows.
    fn save(&self, value: &[u8]) {
        let saved = with_wallet_db_write_lock("swap.inventory", || {
            if CANCEL.load(Ordering::SeqCst) != self.generation {
                return Err("Swap recovery was cancelled.".to_string());
            }
            let conn =
                open_existing_wallet_raw_conn_with_timeout(self.path, WALLET_DB_BUSY_TIMEOUT)?;
            conn.execute_batch(
                "CREATE TABLE IF NOT EXISTS ext_vizor_receiver_inventory (
                    id INTEGER PRIMARY KEY CHECK (id = 0),
                    descriptors BLOB NOT NULL
                )",
            )
            .and_then(|()| {
                conn.execute(
                    "INSERT INTO ext_vizor_receiver_inventory (id, descriptors) VALUES (0, ?1)
                     ON CONFLICT(id) DO UPDATE SET descriptors = excluded.descriptors",
                    [value],
                )
            })
            .map_err(|e| e.to_string())
        });
        if let Err(error) = saved {
            log::debug!("Receiver inventory cache not saved: {error}");
        }
    }
}

/// Forgets every software account's Receiver history when `origin` isn't the server it
/// came from, then records `origin`, so a payment an earlier server left out is read again
/// from this one (see `reset_one_time_history`). The saved inventory descriptors go too.
/// The first server a wallet uses is recorded without a reset.
fn adopt_server(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    origin: &str,
) -> Result<(), String> {
    with_wallet_db_write_lock("swap.server", || {
        if CANCEL.load(Ordering::SeqCst) != generation {
            return Err("Swap recovery was cancelled.".into());
        }
        let conn = open_existing_wallet_raw_conn_with_timeout(path, WALLET_DB_BUSY_TIMEOUT)?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS ext_vizor_receiver_server (
                id INTEGER PRIMARY KEY CHECK (id = 0),
                origin TEXT NOT NULL
            )",
        )
        .map_err(|e| e.to_string())?;
        let recorded: Option<String> = conn
            .query_row(
                "SELECT origin FROM ext_vizor_receiver_server WHERE id = 0",
                [],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        if recorded.as_deref() == Some(origin) {
            return Ok(());
        }
        if recorded.is_some() {
            let mut db =
                open_existing_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
            let accounts = one_time_ivk::software_accounts(&db)?;
            forget_history(&mut db, &accounts, false)?;
            conn.execute_batch("DROP TABLE IF EXISTS ext_vizor_receiver_inventory")
                .map_err(|e| e.to_string())?;
        }
        conn.execute(
            "INSERT INTO ext_vizor_receiver_server (id, origin) VALUES (0, ?1)
             ON CONFLICT(id) DO UPDATE SET origin = excluded.origin",
            [origin],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    })
}

/// Forgets `accounts`' Receiver history (see `reset_one_time_history`), so every watched
/// address is read again from its history start. With `resume`, an account whose history
/// check is unfinished keeps its history, since that check reset it when it started and
/// resumes where it stopped.
fn forget_history(
    db: &mut WalletDatabase,
    accounts: &[AccountUuid],
    resume: bool,
) -> Result<(), String> {
    for &account in accounts {
        if resume {
            let state = db
                .one_time_recovery(account, one_time_ivk::now()?, None)
                .map_err(|e| e.to_string())?;
            if state
                .manual
                .is_some_and(|m| !(m.refunds_done && m.next >= m.receive_end))
            {
                continue;
            }
        }
        db.reset_one_time_history(account)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Opens an existing wallet only for a short read/commit. A reset cannot recreate it.
fn wallet<T>(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    action: impl FnOnce(&mut WalletDatabase) -> Result<T, String>,
) -> Result<T, String> {
    with_wallet_db_write_lock("swap.recovery", || {
        if CANCEL.load(Ordering::SeqCst) != generation {
            return Err("Swap recovery was cancelled.".into());
        }
        let mut db = open_existing_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
        action(&mut db)
    })
}

/// Reads `account`'s current recovery state through [`wallet`], listing the due lookups
/// an inventory ending at `end` can answer.
fn recovery_state(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    account: AccountUuid,
    end: BlockHeight,
) -> Result<RecoveryStatus, String> {
    wallet(path, network, generation, |db| {
        db.one_time_recovery(account, one_time_ivk::now()?, Some(end))
            .map_err(|e| e.to_string())
    })
}

/// Whether downloading sealed shards' filters costs less than reading those shards
/// blind for `lookups` addresses, both in bytes. Reading a shard blind costs each
/// segment's directory setup and choice object once, and one directory query and
/// response per address. Filters cost their bytes plus those same directory reads for the
/// false positives expected at one in [`shards::M`] per address and shard. A true match
/// costs the same directory and companion reads either way, so it is left out: this is
/// the best case for filters, which suits the small lookup counts it is applied to.
fn shard_filters_cheaper(inventory: &Inventory, lookups: usize) -> bool {
    if lookups == 0 {
        return false;
    }
    let query = (native::query_bytes(DIRECTORY_ROWS) + native::response_bytes()) as f64;
    let lookups = lookups as f64;
    let (mut filters, mut blind) = (0f64, 0f64);
    for shard in inventory.shards() {
        let Some(filter) = &shard.filter else {
            continue;
        };
        let setups: f64 = shard
            .segments
            .iter()
            .map(|s| (native::public_bytes() + s.directory.manifest.choice.bytes as usize) as f64)
            .sum();
        let queries = shard.segments.len() as f64 * query;
        blind += setups + lookups * queries;
        filters += filter.bytes as f64 + lookups / shards::M as f64 * (setups + queries);
    }
    filters > 0.0 && filters < blind
}

/// Runs one bounded round over the accounts in the set (see `one_time_ivk::in_set`),
/// `active`'s work first, or with `manual`, a history check's round over every software
/// account. The caller schedules it separately from block sync. A timeout leaves durable
/// work pending and cannot be mistaken for an empty history.
pub(crate) async fn recover(
    path: &str,
    network: WalletNetwork,
    manual: bool,
    active: Option<AccountUuid>,
) -> Result<Round, RecoveryError> {
    if !one_time_ivk::supported(network) {
        return Ok(Round::default());
    }
    let _running = Running::admit()?;
    let generation = CANCEL.load(Ordering::SeqCst);
    // Read the server generation first: a switch racing the origin capture also stops
    // this round, so the old server never answers for the new one.
    let selection = process_selection();
    let server = selection.generation();
    // Without a server an automatic round waits, as it does for an inventory it can't
    // accept yet, and runs once one is selected. A history check reports it.
    let Some(origin) = client_origin(PirProduct::Receiver) else {
        return match manual {
            true => Err("No private query server is selected.".into()),
            false => with_admission(
                path,
                network,
                generation,
                Round {
                    wait: Some(Wait::Server),
                    ..Round::default()
                },
            ),
        };
    };
    let stop = || {
        CANCEL.load(Ordering::SeqCst) != generation
            || selection.generation() != server
            || crate::wallet::sync::proposal_locks::is_shutting_down()
    };
    adopt_server(path, network, generation, &origin)?;
    let transport = SwapTransport::new(&stop);
    let deadline = tokio::time::Instant::now() + ROUND_DEADLINE;
    let round = recover_with_transport(
        path,
        network,
        manual,
        active,
        &origin,
        &transport,
        &DescriptorTable::new(path, generation),
        generation,
        deadline,
    )
    .await?;
    log::debug!(
        "Swap recovery round finished with {} filter traversals",
        round.filter_traversals
    );
    Ok(round)
}

/// Records that the receiver service needs a newer client on every account in `accounts`.
fn require_upgrade(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    accounts: &[AccountUuid],
) -> RecoveryError {
    for account in accounts {
        if let Err(error) = wallet(path, network, generation, |db| {
            db.require_one_time_upgrade(*account)
                .map_err(|e| e.to_string())
        }) {
            return error.into();
        }
    }
    RecoveryError::UpgradeRequired
}

/// Captures the current inventory, reusing durable descriptors, and accepts it only when
/// its end is a block this wallet scanned. The inner error says why the wallet cannot
/// match that end yet: sync is behind the end, the service is behind the wallet
/// birthday, or the two disagree on the block there. Each can clear on a later round.
async fn capture<T: Transport, S: DescriptorStore>(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    origin: &str,
    transport: &T,
    store: &S,
) -> Result<Result<Inventory, RecoveryError>, session::Error> {
    let head = retried(generation, || {
        Inventories::head(origin, transport, &MAINNET_GENESIS)
    })
    .await?;
    let end = BlockHeight::from(head.end_height);
    let (local, birthday) = wallet(path, network, generation, |db| {
        Ok((
            db.block_metadata(end).map_err(|e| e.to_string())?,
            db.get_wallet_birthday().map_err(|e| e.to_string())?,
        ))
    })
    .map_err(session::Error::Transport)?;
    let local = match local {
        Some(block) if block.block_hash().0 == head.end_hash => block,
        Some(_) => {
            return Ok(Err(
                "The swap recovery service and this wallet see different recent blocks. Try again in a few minutes.".into(),
            ))
        }
        // The wallet stores no block below its birthday, so only the service can close
        // this gap.
        None if birthday.is_some_and(|birthday| end < birthday) => {
            return Ok(Err(RecoveryError::ReceiverBehind))
        }
        None => return Ok(Err(RecoveryError::NotCaughtUp)),
    };
    let inventory = retried(generation, || {
        Inventories::capture_cached(origin, transport, head.clone(), store)
    })
    .await?;
    let required_start = network
        .activation_height(NetworkUpgrade::Nu6_3)
        .ok_or(session::Error::Malformed)?;
    inventory.accept(
        &MAINNET_GENESIS,
        required_start.into(),
        local.block_height().into(),
        &local.block_hash().0,
    )?;
    Ok(Ok(inventory))
}

/// [`round_with_transport`], with a failure after a history check started its jobs
/// wrapped in [`RecoveryError::Started`].
#[allow(clippy::too_many_arguments)]
async fn recover_with_transport<T: Transport, S: DescriptorStore>(
    path: &str,
    network: WalletNetwork,
    manual: bool,
    active: Option<AccountUuid>,
    origin: &str,
    transport: &T,
    store: &S,
    generation: u64,
    deadline: tokio::time::Instant,
) -> Result<Round, RecoveryError> {
    let mut started = false;
    let round = round_with_transport(
        path,
        network,
        manual,
        active,
        origin,
        transport,
        store,
        generation,
        deadline,
        &mut started,
    );
    round.await.map_err(|error| match started {
        true => RecoveryError::Started(Box::new(error)),
        false => error,
    })
}

/// Captures one inventory and shares it and its filters across accounts, while each
/// account keeps its own queue, progress and time budget. `active` goes first, so its
/// work gets the first slice of the round. Sets `started` once a history check started
/// its jobs.
#[allow(clippy::too_many_arguments)]
async fn round_with_transport<T: Transport, S: DescriptorStore>(
    path: &str,
    network: WalletNetwork,
    manual: bool,
    active: Option<AccountUuid>,
    origin: &str,
    transport: &T,
    store: &S,
    generation: u64,
    deadline: tokio::time::Instant,
    started: &mut bool,
) -> Result<Round, RecoveryError> {
    // Lookup steps use `transport` itself, so a step already started finishes.
    let gated = &Gated {
        inner: transport,
        deadline,
    };
    let mut accounts = wallet(path, network, generation, |db| {
        one_time_ivk::enable_recovery(db, manual)
    })?;
    if accounts.is_empty() {
        return with_admission(path, network, generation, Round::default());
    }
    if let Some(i) = accounts.iter().position(|a| Some(*a) == active) {
        accounts[..=i].rotate_right(1);
    }
    let mut round = Round::default();
    let inventory = match capture(path, network, generation, origin, gated, store).await {
        Ok(Ok(inventory)) => inventory,
        Ok(Err(waiting)) if manual => return Err(waiting),
        Ok(Err(waiting)) => {
            round.wait = Some(match waiting {
                RecoveryError::ReceiverBehind => Wait::Publication,
                _ => Wait::Sync,
            });
            return with_admission(path, network, generation, round);
        }
        Err(session::Error::Unsupported) => {
            return Err(require_upgrade(path, network, generation, &accounts))
        }
        Err(error) => return Err(error.to_string().into()),
    };
    round.checked = true;
    let publication = zakura_pir_client::receiver::publication(&inventory);
    // A history check starts every account's job or none. A refusal means an account
    // can't accept this publication, as after a rewind, which a later check can. A new
    // check reads every address again from its history start, not trusting earlier
    // answers, so it can find a payment one of them left out.
    if manual
        && wallet(path, network, generation, |db| {
            forget_history(db, &accounts, true)?;
            db.check_one_time_history_for(&accounts, publication)
                .map_err(|e| e.to_string())
        })?
        .is_some()
    {
        return Err(RecoveryError::NotCaughtUp);
    }
    *started = manual;
    let filter_budget = FilterBudget::new(deadline);
    // Filters that overran the last round wait for this one's lookups.
    let skip_filters = FILTERS_OVERRAN.swap(false, Ordering::SeqCst);
    let head = if skip_filters {
        None
    } else {
        filter_budget
            .run(Inventories::block_head(origin, gated, &MAINNET_GENESIS))
            .await
            .ok()
    };
    let end = publication.end.height;
    // An account that can't accept this publication yet, filter work left for a later
    // round, and filter ranges that wait to be checkable.
    let (mut behind, mut filters_left, mut filters_waiting) = (false, skip_filters, false);
    let mut failure = None;
    let mut ready = Vec::new();
    for account in accounts {
        match wallet(path, network, generation, |db| {
            db.begin_one_time_recovery(account, publication, false)
                .map_err(|e| e.to_string())
        }) {
            Ok(true) => ready.push(account),
            Ok(false) => {
                behind = true;
                failure = failure.or(manual.then_some(RecoveryError::NotCaughtUp));
            }
            Err(error) => {
                failure.get_or_insert(error.into());
                if CANCEL.load(Ordering::SeqCst) != generation {
                    return Err(failure.expect("recorded"));
                }
            }
        }
    }
    if !skip_filters {
        let (mut accounts, scanned) =
            wallet(path, network, generation, |db| filter_accounts(db, &ready))?;
        accounts.retain(|a| a.state.enabled);
        let coverage = read_filters(
            path,
            network,
            generation,
            origin,
            gated,
            Some(&filter_budget),
            head.as_ref(),
            scanned,
            &accounts,
        )
        .await?;
        for (account, coverage) in accounts.iter().zip(coverage) {
            match coverage {
                Coverage::Filters { left, waiting } => {
                    filters_left |= left;
                    filters_waiting |= waiting;
                }
                Coverage::Complete => wallet(path, network, generation, |db| {
                    db.begin_one_time_recovery(account.id, publication, true)
                        .map(|_| ())
                        .map_err(|e| e.to_string())
                })?,
            }
        }
    }
    let mut due = Vec::new();
    for account in &ready {
        due.extend(recovery_state(path, network, generation, *account, end)?.lookups);
    }
    let filters = !skip_filters && shard_filters_cheaper(&inventory, due.len());
    let client = InventoryClient::new(
        origin,
        RoundTransport::new(transport, &filter_budget),
        inventory,
        filters,
    );
    // Every account's due lookups share one traversal of each sealed shard's filter.
    zakura_pir_client::receiver::screen(&client, &due).await;
    // Only accounts with runnable work share the round's time, so idle ones don't shorten
    // a slow lookup's slice. An unreadable state counts as work, and drain reports it.
    let busy: Vec<_> = ready
        .iter()
        .filter(|account| runnable(path, network, generation, **account, end).unwrap_or(true))
        .collect();
    let account_count = busy.len();
    for (index, account) in busy.into_iter().enumerate() {
        // Include a spare slice for commit/loop overhead. An account starts no step after
        // its slice, so a slow earlier account cannot spend the time reserved for later
        // ones, while a step it already started finishes.
        let now = tokio::time::Instant::now();
        let until = now
            + deadline
                .saturating_duration_since(now)
                .div_f64((account_count - index + 1) as f64);
        match drain(path, network, generation, &client, *account, end, until).await {
            Ok(changed) => round.changed |= changed,
            Err(RecoveryError::UpgradeRequired) => {
                return Err(require_upgrade(path, network, generation, &ready));
            }
            Err(error) => {
                failure.get_or_insert(error);
                if CANCEL.load(Ordering::SeqCst) != generation {
                    break;
                }
            }
        }
    }
    round.filter_traversals = client.filter_traversals();
    if let Some(failure) = failure {
        return Err(failure);
    }
    let (more, wait) = leftover(path, network, generation, &ready, end)?;
    round.more = more || filters_left;
    // A range that can't be checked against the wallet's chain yet can be once sync
    // moves on.
    if !round.more {
        round.wait = wait.or((behind || filters_waiting).then_some(Wait::Sync));
    }
    with_admission(path, network, generation, round)
}

/// `round` with whether found payments await admission as it ended (see
/// `one_time_ivk::recovery_status`).
fn with_admission(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    mut round: Round,
) -> Result<Round, RecoveryError> {
    round.awaiting_admission = wallet(path, network, generation, |db| {
        one_time_ivk::recovery_status(db).map(|status| status.awaiting_admission)
    })?;
    Ok(round)
}

/// Whether `accounts` have work a round can run right now against an inventory ending
/// at `end`, and otherwise why their queued lookups wait: a retry delay goes before a
/// later publication.
fn leftover(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    accounts: &[AccountUuid],
    end: BlockHeight,
) -> Result<(bool, Option<Wait>), RecoveryError> {
    let mut wait = None;
    for account in accounts {
        let state = recovery_state(path, network, generation, *account, end)?;
        if !state.lookups.is_empty() {
            return Ok((true, None));
        }
        if state.waits_for_retry {
            wait = Some(Wait::Backoff);
        } else if state.waits_for_publication {
            wait = wait.or(Some(Wait::Publication));
        }
    }
    Ok((false, wait))
}

/// Whether `account` has a due lookup that the inventory ending at `end` can answer, or
/// `None` if its state can't be read.
fn runnable(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    account: AccountUuid,
    end: BlockHeight,
) -> Option<bool> {
    recovery_state(path, network, generation, account, end)
        .ok()
        .map(|state| !state.lookups.is_empty())
}

/// Records `account`'s due lookup steps against the captured inventory, which ends at
/// `end`, until none is due or `until`. A step reads at most [`STEP_RECORDS`] records,
/// runs once more if it failed in transit (see [`retried`]), and is recorded whole or not
/// at all. A lookup that needs several steps, as one over many segments or with more
/// records than one step reads, keeps going under this inventory, since a cursor resumes
/// only under the inventory it was read from. A failed step ends the call: it defers the
/// lookup, never recording it as empty, unless the request was lost in transit or the
/// publication changed, which leaves it due. A step the library doesn't accept because it
/// went stale ends the call too. No step starts after `until`, while one already started
/// finishes, past the round's deadline if it must. Returns whether the library accepted
/// any lookup page (see [`Round::changed`]).
async fn drain<T: Transport>(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    client: &InventoryClient<T>,
    account: AccountUuid,
    end: BlockHeight,
    until: tokio::time::Instant,
) -> Result<bool, RecoveryError> {
    let mut changed = false;
    while tokio::time::Instant::now() < until {
        // A hit above this inventory's end waits for a later publication.
        let state = recovery_state(path, network, generation, account, end)?;
        let Some(work) = state.lookups.first() else {
            break;
        };
        let pace = || Pace {
            records: STEP_RECORDS,
        };
        match retried(generation, || lookup_with(client, work, pace())).await {
            Ok(page) => {
                let accepted = wallet(path, network, generation, |db| {
                    db.record_one_time_lookup(account, work, &page, one_time_ivk::now()?)
                        .map_err(|e| e.to_string())
                })?;
                changed |= accepted;
                if !accepted {
                    break;
                }
            }
            Err(session::Error::Unsupported) => return Err(RecoveryError::UpgradeRequired),
            Err(error) => {
                // A request lost in transit or a changed publication leaves the lookup due
                // for the next round, whose hold paces the retry, so an outage doesn't
                // back the key off for hours. Any other failure backs it off.
                let transient = in_transit(&error) || matches!(error, session::Error::Revision);
                wallet(path, network, generation, |db| {
                    if transient {
                        return Ok(());
                    }
                    db.defer_one_time_lookup(account, work, one_time_ivk::now()?)
                        .map_err(|e| e.to_string())
                })?;
                return Err(error.to_string().into());
            }
        }
    }
    Ok(changed)
}

/// What filters did for one account (see [`read_filters`]).
#[derive(Clone, Copy)]
enum Coverage {
    /// Filters can't continue the account's marker, so it needs a complete check.
    Complete,
    /// Filters covered what they could. `left` says filter work is left for the next
    /// round, and `waiting` that the range waits to be checkable against the wallet's
    /// chain.
    Filters { left: bool, waiting: bool },
}

/// Where filters from `head` continue `state`'s marker, or `None` when the account needs
/// a complete check instead: it has no marker, the head serves another history revision,
/// or the marker is below the head's window.
fn filter_start(state: &RecoveryStatus, head: &Head) -> Option<u32> {
    let start = u32::from(state.filter_frontier?.height) + 1;
    (head.revision == state.token.history_revision && start >= head.first).then_some(start)
}

/// An account's recovery state and watched receivers, read before its filters are.
struct FilterAccount {
    id: AccountUuid,
    state: RecoveryStatus,
    token: RecoveryToken,
    receivers: Vec<DiscoveryWork>,
}

/// Reads `accounts`' filter state, and the wallet's fully scanned height.
fn filter_accounts(
    db: &mut WalletDatabase,
    accounts: &[AccountUuid],
) -> Result<(Vec<FilterAccount>, u32), String> {
    let now = one_time_ivk::now()?;
    let mut read = Vec::new();
    for &id in accounts {
        let state = db
            .one_time_recovery(id, now, None)
            .map_err(|e| e.to_string())?;
        let (token, receivers) = db.one_time_receivers(id).map_err(|e| e.to_string())?;
        read.push(FilterAccount {
            id,
            state,
            token,
            receivers,
        });
    }
    let scanned = db
        .block_fully_scanned()
        .map_err(|e| e.to_string())?
        .map_or(0, |b| u32::from(b.block_height()));
    Ok((read, scanned))
}

/// Continues each of `accounts`' markers with filters from `head`, through the lower of
/// the head's tip and the wallet's fully scanned height `scanned`, reading one range per
/// distinct marker and committing it for every account at that marker. `budget`, when
/// given, bounds the downloads. Returns what filters did for each account, in order: an
/// account they can't continue (see [`filter_start`]), whose range failed to download, or
/// with no head at all needs a complete check. Only a wallet failure is an error.
#[allow(clippy::too_many_arguments)]
async fn read_filters<T: Transport>(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    origin: &str,
    transport: &T,
    budget: Option<&FilterBudget>,
    head: Option<&Head>,
    scanned: u32,
    accounts: &[FilterAccount],
) -> Result<Vec<Coverage>, String> {
    let Some(head) = head else {
        return Ok(vec![Coverage::Complete; accounts.len()]);
    };
    let to = head.tip.height.min(scanned);
    let filters = |left, waiting| Coverage::Filters { left, waiting };
    let starts: Vec<_> = accounts
        .iter()
        .map(|a| filter_start(&a.state, head))
        .collect();
    let mut coverage: Vec<_> = starts
        .iter()
        .map(|start| start.map_or(Coverage::Complete, |_| filters(false, false)))
        .collect();
    let froms: std::collections::BTreeSet<_> =
        starts.iter().flatten().filter(|s| **s <= to).collect();
    for &from in froms {
        let limit = (to - from + 1).min(MAX_RANGE_BLOCKS);
        let request = Inventories::block_range(origin, transport, head, from, limit);
        let range = match budget {
            Some(budget) => budget.run(request).await,
            None => request.await.map_err(|e| e.to_string()),
        };
        if let Err(error) = &range {
            log::debug!("Receiver filters unavailable, checking completely: {error}");
        }
        for (i, account) in accounts.iter().enumerate() {
            if starts[i] != Some(from) {
                continue;
            }
            let Ok(range) = &range else {
                coverage[i] = Coverage::Complete;
                continue;
            };
            let (span, hits) = filter_span(head, range, &account.receivers);
            coverage[i] = match wallet(path, network, generation, |db| {
                db.record_one_time_filter_span(account.id, account.token, &span, &hits)
                    .map_err(|e| e.to_string())
            })? {
                // A short range leaves the rest for the next round.
                FilterOutcome::Committed => filters(range.end().height < to, false),
                // The wallet can't check the range's end yet. A round after more sync
                // commits it.
                FilterOutcome::Wait => filters(false, true),
                // Work recorded since the read changed the account's receivers. The next
                // step reads again from the marker.
                FilterOutcome::Stale => filters(false, false),
                // A correction cleared the marker, or the service and the wallet disagree
                // on a block.
                FilterOutcome::Restart | FilterOutcome::Mismatch => Coverage::Complete,
            };
        }
    }
    Ok(coverage)
}

/// `range` as a filter span from `head`, with the height and key of each of `receivers`
/// it matches.
fn filter_span(
    head: &Head,
    range: &Range,
    receivers: &[DiscoveryWork],
) -> (FilterSpan, Vec<(BlockHeight, KeyId)>) {
    let bytes: Vec<_> = receivers.iter().map(|r| r.receiver).collect();
    let hits = range
        .matches(&MAINNET_GENESIS, &bytes)
        .into_iter()
        .map(|(height, i)| (BlockHeight::from(height), receivers[i].key))
        .collect();
    let end = range.end();
    let span = FilterSpan {
        revision: head.revision,
        from: BlockHeight::from(range.from()),
        parent: BlockHash(range.parent()),
        end: ChainPoint {
            height: end.height.into(),
            hash: BlockHash(end.hash),
        },
    };
    (span, hits)
}

/// Runs one filter step, the filter part of a round alone, under the round's admission
/// (see [`step_with_transport`]). Without a server it does nothing, as a round waits.
pub(crate) async fn filter_step(path: &str, network: WalletNetwork) -> Result<Step, String> {
    if !one_time_ivk::supported(network) {
        return Ok(Step::default());
    }
    let _running = Running::admit()?;
    let generation = CANCEL.load(Ordering::SeqCst);
    let selection = process_selection();
    let server = selection.generation();
    let Some(origin) = client_origin(PirProduct::Receiver) else {
        return Ok(Step::default());
    };
    let stop = || {
        CANCEL.load(Ordering::SeqCst) != generation
            || selection.generation() != server
            || crate::wallet::sync::proposal_locks::is_shutting_down()
    };
    adopt_server(path, network, generation, &origin)?;
    let transport = SwapTransport::new(&stop);
    step_with_transport(path, network, &origin, &transport, generation).await
}

/// Reads the filter head and continues the marker of every account in the set (see
/// `one_time_ivk::in_set`) as a round does (see [`read_filters`]), with no request when
/// the set is empty. It captures no inventory and runs no lookup. An account that needs
/// a complete check, or filter work the step left, owes a round (see
/// [`Step::needs_round`]), as does a failed head. A hit queues its lookup, which makes a
/// round due (see `RecoveryStatus::round_due`). Only a cancellation or a wallet failure is
/// an error.
async fn step_with_transport<T: Transport>(
    path: &str,
    network: WalletNetwork,
    origin: &str,
    transport: &T,
    generation: u64,
) -> Result<Step, String> {
    let (accounts, scanned) = wallet(path, network, generation, |db| {
        let accounts = one_time_ivk::enable_recovery(db, false)?;
        filter_accounts(db, &accounts)
    })?;
    if accounts.is_empty() {
        return Ok(Step::default());
    }
    let head = Inventories::block_head(origin, transport, &MAINNET_GENESIS)
        .await
        .inspect_err(|error| log::debug!("Receiver filters unavailable, owing a round: {error}"))
        .ok();
    let coverage = read_filters(
        path,
        network,
        generation,
        origin,
        transport,
        None,
        head.as_ref(),
        scanned,
        &accounts,
    )
    .await?;
    if CANCEL.load(Ordering::SeqCst) != generation {
        return Err("Swap recovery was cancelled.".into());
    }
    let needs_round = coverage
        .iter()
        .any(|c| matches!(c, Coverage::Complete | Coverage::Filters { left: true, .. }));
    Ok(Step { needs_round })
}

#[cfg(test)]
mod tests;
