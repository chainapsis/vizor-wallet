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
};
use rusqlite::OptionalExtension;
use std::{
    collections::{btree_map::Entry, BTreeMap, HashSet},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Mutex,
    },
    time::Duration,
};
use zakura_pir_client::receiver::{
    blocks::{Batch, Head},
    inventory::Inventory,
    lookup, native, session,
    transport::{DescriptorStore, Inventories, InventoryClient, Transport},
    witness, MAINNET_GENESIS,
};
use zcash_client_backend::data_api::{
    one_time_ivk::restore::{DiscoveryWork, RecoveryToken},
    transparent_ledger::ChainPoint,
    WalletRead as _,
};
use zcash_client_sqlite::AccountUuid;
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

static RUNNING: AtomicBool = AtomicBool::new(false);
static CANCEL: AtomicU64 = AtomicU64::new(0);

/// Cancels the current bounded worker without deleting its durable queue.
pub(crate) fn cancel_recovery() {
    CANCEL.fetch_add(1, Ordering::SeqCst);
}

/// Why a recovery round stopped early. Durable work stays pending either way.
#[derive(Debug)]
pub(crate) enum RecoveryError {
    /// The receiver service speaks a format this app does not support. Every active
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
        }
    }
}

/// What one finished round did, for logs and tests.
#[derive(Debug, Default)]
pub(super) struct Round {
    /// Whether any account had recovery work (see `one_time_ivk::has_recovery_work`).
    /// Without it, the round only read the wallet.
    pub(super) active: bool,
    /// Sealed-shard filter traversals. Screening the round's due lookups together
    /// keeps this to one per filter, plus any for addresses exposed mid-round.
    pub(super) filter_traversals: u64,
}

/// Releases worker admission even when the future is cancelled or times out.
struct Running;
impl Drop for Running {
    /// Allows the next independent check after this worker has stopped.
    fn drop(&mut self) {
        RUNNING.store(false, Ordering::SeqCst);
    }
}

const DEFAULT_RECEIVER_ORIGIN: &str = "https://receiver-pir.valargroup.dev";

/// Selects the normal service or an explicit debug-only test endpoint.
fn receiver_origin() -> String {
    #[cfg(debug_assertions)]
    if let Ok(origin) = std::env::var("VIZOR_RECEIVER_PIR_URL") {
        return origin;
    }
    DEFAULT_RECEIVER_ORIGIN.into()
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
            .bytes(http::Method::GET, url, vec![], limit)
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
            .bytes(http::Method::POST, url, body, limit)
            .await
            .map_err(receiver_error)
    }
}

/// How long one optional sealed-shard filter download may take. A filter only saves PIR
/// work, so a slow one is abandoned well inside the 45 second round budget.
const SHARD_FILTER_TIMEOUT: Duration = Duration::from_secs(5);

/// How long one optional rolling block-filter request may take.
const BLOCK_FILTER_TIMEOUT: Duration = Duration::from_secs(2);

/// The most time one round spends on all its optional filter downloads together (see
/// [`FilterBudget`]).
const FILTER_BUDGET: Duration = Duration::from_secs(10);

/// The route the library fetches sealed-shard filters from (see `InventoryClient::filter`).
const SHARD_FILTER_ROUTE: &str = "/v1/receiver/shard-filters/";

/// The time one round may spend on optional filters: the rolling block-filter head and
/// batches, and sealed-shard filters. Filters only save PIR work, and they are fetched
/// one at a time, per account and per shard, so many waits that each stay within their
/// own timeout could otherwise fill the round before any PIR work commits. Every filter
/// wait draws on this one deadline, and once it passes or a filter request stalls, no
/// further filter is requested this round.
struct FilterBudget {
    deadline: tokio::time::Instant,
    stalled: AtomicBool,
}

impl FilterBudget {
    /// A budget for a round ending at `deadline`: [`FILTER_BUDGET`] at most, and never
    /// more than a third of the time left, so the rest stays for PIR.
    fn new(deadline: tokio::time::Instant) -> Self {
        let now = tokio::time::Instant::now();
        Self {
            deadline: now + FILTER_BUDGET.min(deadline.saturating_duration_since(now) / 3),
            stalled: AtomicBool::new(false),
        }
    }

    /// Runs the optional filter request `request` for at most `cap`, or what is left of
    /// the budget if that is less. Refuses it without a request once the budget is spent
    /// or a filter stalled, and marks a request that runs out of time as stalled.
    async fn run<R, E: std::fmt::Display>(
        &self,
        cap: Duration,
        request: impl std::future::Future<Output = Result<R, E>>,
    ) -> Result<R, String> {
        let left = self
            .deadline
            .saturating_duration_since(tokio::time::Instant::now());
        if left.is_zero() || self.stalled.load(Ordering::SeqCst) {
            return Err("Receiver filters unavailable this round.".into());
        }
        match tokio::time::timeout(cap.min(left), request).await {
            Ok(result) => result.map_err(|e| e.to_string()),
            Err(_) => {
                self.stalled.store(true, Ordering::SeqCst);
                Err("Receiver filter request timed out.".into())
            }
        }
    }
}

/// One round's lookup transport. Sealed-shard filters are optional: the library reads a
/// shard over PIR when its filter cannot be fetched, but retries the download on every
/// later step. So each filter download draws on the round's [`FilterBudget`], and a
/// filter that failed is refused for the rest of the round without another request.
/// Other requests pass through unchanged.
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
        let result = self
            .budget
            .run(SHARD_FILTER_TIMEOUT, self.inner.get(url, limit))
            .await;
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

/// Compares estimated remaining filter bodies with the actual unfinished address set.
/// Setup is needed only when a route expects lookups. Witness reads and enhancement are
/// required by either route and are not avoided by choosing direct queries.
fn filters_cheaper(
    blocks: u32,
    sample_bytes: usize,
    matches: usize,
    addresses: usize,
    setup: usize,
    query: usize,
) -> bool {
    let filter_bytes = u128::from(blocks) * sample_bytes as u128;
    let likely_queries = (u128::from(blocks) * matches as u128).min(addresses as u128);
    let filtered = filter_bytes
        + likely_queries * query as u128
        + if likely_queries > 0 { setup as u128 } else { 0 };
    let direct = addresses as u128 * query as u128 + if addresses > 0 { setup as u128 } else { 0 };
    filtered < direct
}

/// The payment setup and per-address query bytes of reading every segment of the shards
/// that end after `after`, which is what one blind direct lookup from there reads. The
/// recent tier is always read, even when the inventory ends before `after`.
fn direct_cost(inventory: &Inventory, after: u32) -> Result<(usize, usize), String> {
    let shards = inventory.shards();
    let first = shards
        .partition_point(|s| s.end_height <= after)
        .min(shards.len().saturating_sub(1));
    let (mut setup, mut query) = (0, 0);
    for shard in &shards[first..] {
        for segment in &shard.segments {
            let rows = segment.payments.directory.rows;
            setup += native::public_bytes(rows).map_err(|e| e.to_string())?;
            query += native::query_bytes(rows)
                .and_then(|n| native::response_bytes(rows).map(|m| n + m))
                .map_err(|e| e.to_string())?;
        }
    }
    Ok((setup, query))
}

/// Whether downloading sealed shards' filters costs less than reading those shards
/// blind for `lookups` addresses. A filter that matches still needs PIR, so this is the
/// best case for filters, which suits the small lookup counts it is applied to.
fn shard_filters_cheaper(inventory: &Inventory, lookups: usize) -> bool {
    let (mut filters, mut blind) = (0u128, 0u128);
    for shard in inventory.shards() {
        let Some(filter) = &shard.filter else {
            continue;
        };
        filters += u128::from(filter.bytes);
        for segment in &shard.segments {
            let rows = segment.payments.directory.rows;
            let bytes = native::query_bytes(rows)
                .and_then(|n| native::response_bytes(rows).map(|m| n + m))
                .unwrap_or(0);
            blind += bytes as u128 * lookups as u128;
        }
    }
    filters > 0 && filters < blind
}

/// Runs one bounded account round. The caller schedules it separately from block sync.
/// A timeout leaves durable work pending and cannot be mistaken for an empty history.
/// Returns whether any account had recovery work, so the caller can stop scheduling
/// rounds while the feature is off and nothing is due.
pub(crate) async fn recover(
    path: &str,
    network: WalletNetwork,
    manual: Option<Option<u64>>,
) -> Result<bool, RecoveryError> {
    if !one_time_ivk::supported(network) {
        return Ok(false);
    }
    if RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err("A swap recovery check is already running.".into());
    }
    let _running = Running;
    let generation = CANCEL.load(Ordering::SeqCst);
    let stop = || {
        CANCEL.load(Ordering::SeqCst) != generation
            || crate::wallet::sync::proposal_locks::is_shutting_down()
    };
    let transport = SwapTransport::new(&stop);
    let deadline = tokio::time::Instant::now() + Duration::from_secs(45);
    let round = tokio::time::timeout_at(
        deadline,
        recover_with_transport(
            path,
            network,
            manual,
            &receiver_origin(),
            &transport,
            &DescriptorTable::new(path, generation),
            generation,
            deadline,
        ),
    )
    .await
    .map_err(|_| {
        RecoveryError::from("Swap recovery is still pending. It will continue on the next check.")
    })??;
    log::debug!(
        "Swap recovery round finished with {} filter traversals",
        round.filter_traversals
    );
    Ok(round.active)
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
    let head = Inventories::head(origin, transport, &MAINNET_GENESIS).await?;
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
    let inventory = Inventories::capture_cached(origin, transport, head, store).await?;
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

/// Captures one inventory and shares it and its filters across accounts, while each
/// account keeps its own queue, progress and time budget.
#[allow(clippy::too_many_arguments)]
async fn recover_with_transport<T: Transport, S: DescriptorStore>(
    path: &str,
    network: WalletNetwork,
    manual: Option<Option<u64>>,
    origin: &str,
    transport: &T,
    store: &S,
    generation: u64,
    deadline: tokio::time::Instant,
) -> Result<Round, RecoveryError> {
    // With the feature off and nothing due, take no write lock and write nothing.
    if manual.is_none() && one_time_ivk::idle_while_off(path, network)? {
        return Ok(Round::default());
    }
    let accounts = wallet(path, network, generation, |db| {
        one_time_ivk::reconcile_enabled(db, network)?;
        one_time_ivk::software_accounts(db)
    })?;
    let mut active = Vec::new();
    let mut discovery_enabled = false;
    for account in accounts {
        let state = wallet(path, network, generation, |db| {
            db.one_time_recovery(account, one_time_ivk::now()?)
                .map_err(|e| e.to_string())
        })?;
        if one_time_ivk::has_recovery_work(&state) {
            discovery_enabled |= state.enabled;
            active.push(account);
        }
    }
    if active.is_empty() {
        return Ok(Round::default());
    }
    let inventory = match capture(path, network, generation, origin, transport, store).await {
        Ok(Ok(inventory)) => inventory,
        Ok(Err(waiting)) if manual.is_some() => return Err(waiting),
        Ok(Err(_)) => {
            return Ok(Round {
                active: true,
                ..Round::default()
            })
        }
        Err(session::Error::Unsupported) => {
            return Err(require_upgrade(path, network, generation, &active))
        }
        Err(error) => return Err(error.to_string().into()),
    };
    let publication = zakura_pir_client::receiver::publication(&inventory);
    let filter_budget = FilterBudget::new(deadline);
    let head = if discovery_enabled {
        filter_budget
            .run(
                BLOCK_FILTER_TIMEOUT,
                Inventories::block_head(origin, transport, &MAINNET_GENESIS),
            )
            .await
            .ok()
    } else {
        None
    };
    let mut batches = BTreeMap::new();
    let mut failure = None;
    let mut ready = Vec::new();
    let mut due = Vec::new();
    for account in active {
        let result: Result<(), RecoveryError> = async {
            let accepted_locally = wallet(path, network, generation, |db| {
                db.begin_one_time_recovery(account, publication, false)
                    .map_err(|e| e.to_string())
            })?;
            if !accepted_locally {
                return if manual.is_some() {
                    Err(RecoveryError::NotCaughtUp)
                } else {
                    Ok(())
                };
            }
            if let Some(bound) = manual {
                wallet(path, network, generation, |db| {
                    db.check_one_time_history(account, publication, bound)
                        .map(|_| ())
                        .map_err(|e| e.to_string())
                })?;
            }
            let (state, (token, receivers), count, scanned) =
                wallet(path, network, generation, |db| {
                    Ok((
                        db.one_time_recovery(account, one_time_ivk::now()?)
                            .map_err(|e| e.to_string())?,
                        db.one_time_receivers(account).map_err(|e| e.to_string())?,
                        db.one_time_direct_query_count(account)
                            .map_err(|e| e.to_string())?,
                        db.block_fully_scanned()
                            .map_err(|e| e.to_string())?
                            .map(|b| b.block_height()),
                    ))
                })?;
            if state.enabled {
                let frontier = state.filter_frontier.map(|f| u32::from(f.height));
                let range = head.as_ref().and_then(|head| {
                    let from = frontier?.checked_add(1)?;
                    let to = head.tip.height.min(u32::from(scanned?));
                    (head.revision == token.history_revision && from >= head.first && from <= to)
                        .then_some((head, from, to))
                });
                let mut direct = frontier.is_none()
                    || head.as_ref().is_none_or(|h| {
                        h.revision != token.history_revision
                            || frontier.is_some_and(|f| f.saturating_add(1) < h.first)
                    });
                if let Some((head, from, to)) = range {
                    let (setup, query) = direct_cost(&inventory, from - 1)?;
                    let filtered: Result<bool, String> = async {
                        // Sample bytes are shared by accounts and committed even when direct
                        // queries win. A positive on a completed address must not be lost.
                        let sample = match batches.entry((from, 1)) {
                            Entry::Occupied(cached) => cached.into_mut(),
                            Entry::Vacant(slot) => slot.insert(
                                filter_batch(origin, transport, &filter_budget, head, from, 1)
                                    .await?,
                            ),
                        };
                        let receiver_bytes: Vec<_> = receivers.iter().map(|r| r.receiver).collect();
                        let matches = sample
                            .matches(0, &receiver_bytes)
                            .map_err(|e| e.to_string())?
                            .into_iter()
                            .filter(|hit| *hit)
                            .count();
                        let cost = sample.encode().map_err(|e| e.to_string())?.len();
                        wallet(path, network, generation, |db| {
                            apply_filters(db, account, token, head.revision, sample, &receivers)
                        })?;
                        if !filters_cheaper(to - from + 1, cost, matches, count, setup, query) {
                            return Ok(false);
                        }
                        if from < to {
                            let next = from + 1;
                            let limit = (to - from).min(256);
                            let batch = match batches.entry((next, limit)) {
                                Entry::Occupied(cached) => cached.into_mut(),
                                Entry::Vacant(slot) => slot.insert(
                                    filter_batch(
                                        origin,
                                        transport,
                                        &filter_budget,
                                        head,
                                        next,
                                        limit,
                                    )
                                    .await?,
                                ),
                            };
                            wallet(path, network, generation, |db| {
                                apply_filters(db, account, token, head.revision, batch, &receivers)
                            })?;
                        }
                        Ok(true)
                    }
                    .await;
                    direct = match filtered {
                        Ok(used_filters) => !used_filters,
                        Err(error) => {
                            log::debug!(
                                "Receiver filters unavailable, retaining pending work: {error}"
                            );
                            true
                        }
                    };
                }
                if direct {
                    wallet(path, network, generation, |db| {
                        db.begin_one_time_recovery(account, publication, true)
                            .map(|_| ())
                            .map_err(|e| e.to_string())
                    })?;
                }
            }
            due.extend(wallet(path, network, generation, |db| {
                db.one_time_recovery(account, one_time_ivk::now()?)
                    .map(|state| state.lookups)
                    .map_err(|e| e.to_string())
            })?);
            ready.push(account);
            Ok(())
        }
        .await;
        if let Err(error) = result {
            failure.get_or_insert(error);
            if CANCEL.load(Ordering::SeqCst) != generation {
                return Err(failure.expect("recorded"));
            }
        }
    }
    let filters = shard_filters_cheaper(&inventory, due.len());
    let client = InventoryClient::new(
        origin,
        RoundTransport::new(transport, &filter_budget),
        inventory,
        filters,
    );
    // Every account's due lookups share one traversal of each sealed shard's filter.
    zakura_pir_client::receiver::screen(&client, &due).await;
    let account_count = ready.len();
    for (index, account) in ready.iter().enumerate() {
        // Include a spare slice for commit/loop overhead. A slow earlier account
        // cannot spend the time reserved for later accounts.
        let account_budget = deadline
            .saturating_duration_since(tokio::time::Instant::now())
            .div_f64((account_count - index + 1) as f64);
        let result = tokio::time::timeout(
            account_budget,
            drain(path, network, generation, &client, *account),
        )
        .await
        .unwrap_or_else(|_| Err("Swap account recovery remains pending.".into()));
        match result {
            Ok(()) => {}
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
    failure.map_or(
        Ok(Round {
            active: true,
            filter_traversals: client.filter_traversals(),
        }),
        Err,
    )
}

/// Settles a bounded number of `account`'s due lookups and witness reads against the
/// captured inventory. A failed lookup is deferred, never recorded as empty.
async fn drain<T: Transport>(
    path: &str,
    network: WalletNetwork,
    generation: u64,
    client: &InventoryClient<T>,
    account: AccountUuid,
) -> Result<(), RecoveryError> {
    let end = zakura_pir_client::receiver::publication(client.inventory())
        .end
        .height;
    for _ in 0..16 {
        let state = wallet(path, network, generation, |db| {
            db.one_time_recovery(account, one_time_ivk::now()?)
                .map_err(|e| e.to_string())
        })?;
        // A hit above this inventory's end waits for a later publication.
        if let Some(work) = state.lookups.iter().find(|work| work.through <= end) {
            match lookup(client, work).await {
                Ok(page) => {
                    wallet(path, network, generation, |db| {
                        db.record_one_time_lookup(account, work, &page, one_time_ivk::now()?)
                            .map(|_| ())
                            .map_err(|e| e.to_string())
                    })?;
                }
                Err(session::Error::Unsupported) => return Err(RecoveryError::UpgradeRequired),
                Err(error) => {
                    wallet(path, network, generation, |db| {
                        db.defer_one_time_lookup(account, work, one_time_ivk::now()?)
                            .map_err(|e| e.to_string())
                    })?;
                    return Err(error.to_string().into());
                }
            }
        } else if let Some(request) = state.witnesses.first() {
            match witness(client, request).await {
                Ok(answer) => {
                    wallet(path, network, generation, |db| {
                        db.record_one_time_witness(
                            account,
                            state.token,
                            *request,
                            &answer,
                            one_time_ivk::now()?,
                        )
                        .map(|_| ())
                        .map_err(|e| e.to_string())
                    })?;
                }
                // The payment's session was replaced, so its ordinal no longer applies.
                Err(session::Error::Revision) => {
                    wallet(path, network, generation, |db| {
                        db.refresh_one_time_witness(account, state.token, *request)
                            .map(|_| ())
                            .map_err(|e| e.to_string())
                    })?;
                }
                Err(session::Error::Unsupported) => return Err(RecoveryError::UpgradeRequired),
                Err(error) => return Err(error.to_string().into()),
            }
        } else {
            break;
        }
    }
    Ok(())
}

/// Commits all matched keys with their contiguous canonical blocks, including old paid keys.
fn apply_filters(
    db: &mut WalletDatabase,
    account: AccountUuid,
    token: RecoveryToken,
    revision: u64,
    batch: &Batch,
    receivers: &[DiscoveryWork],
) -> Result<(), String> {
    let receiver_bytes: Vec<_> = receivers.iter().map(|r| r.receiver).collect();
    let mut hits = Vec::new();
    let mut blocks = Vec::new();
    for (i, filter) in batch.filters().iter().enumerate() {
        blocks.push(ChainPoint {
            height: filter.block().height.into(),
            hash: BlockHash(filter.block().hash),
        });
        for (receiver, hit) in receivers.iter().zip(
            batch
                .matches(i, &receiver_bytes)
                .map_err(|e| e.to_string())?,
        ) {
            if hit && !hits.contains(&receiver.key) {
                hits.push(receiver.key);
            }
        }
    }
    if !db
        .record_one_time_filters(account, token, revision, &blocks, &hits)
        .map_err(|e| e.to_string())?
    {
        return Err(
            "Receiver filters no longer match the wallet's chain or recovery state.".into(),
        );
    }
    Ok(())
}

/// Fetches rolling block filters `from` for `limit` blocks, drawing on the round's
/// optional filter `budget` (see [`FilterBudget`]), so an outage leaves time for direct
/// PIR work.
async fn filter_batch<T: Transport>(
    origin: &str,
    transport: &T,
    budget: &FilterBudget,
    head: &Head,
    from: u32,
    limit: u32,
) -> Result<Batch, String> {
    budget
        .run(
            BLOCK_FILTER_TIMEOUT,
            Inventories::block_batch(origin, transport, head, from, limit),
        )
        .await
}

#[cfg(test)]
mod tests;
