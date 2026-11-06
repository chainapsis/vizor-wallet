//! Bounded, cancellable measurement of public lightwalletd candidates.
//!
//! Each worker owns its runtime until all blocking work drains, even after its
//! result returns. Selection does not touch wallet state or send wallet identifiers.

use std::{
    collections::{HashMap, HashSet, VecDeque},
    future::Future,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, LazyLock, Mutex,
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use futures::{stream, StreamExt};
use tonic::Request;
use zcash_client_backend::proto::service::{ChainSpec, Empty};

use crate::{network_privacy, wallet::keys};

const COMPARISON_WINDOW: Duration = Duration::from_millis(250);
const ROUTE_CHECK_INTERVAL: Duration = Duration::from_millis(25);
const MAX_CANDIDATES: usize = 32;
const MAX_ACTIVE_SELECTIONS: usize = 16;
// Matches the maximum native probe concurrency, including timed-out lookups
// still running on this worker. Draining workers retain their selection slot.
const MAX_SELECTION_BLOCKING_THREADS: usize = 8;
const LOCAL_WORKER_FAILED: &str = "automatic endpoint selection: local worker failed";
const MAX_RECENT_IDS: usize = 64;
const RECENT_ID_LIFETIME: Duration = Duration::from_secs(60);
pub(crate) const CANCELLED: &str = "automatic endpoint selection: cancelled";
pub(crate) const ROUTE_BLOCKED: &str = "automatic endpoint selection: network privacy blocked";
const NO_HEALTHY_CANDIDATES: &str = "automatic endpoint selection: no healthy candidates";

#[derive(Debug)]
pub(crate) struct CandidateProbe {
    pub url: String,
    pub height: u64,
    pub latency_ms: u32,
    pub connect_ms: u32,
    pub rpc_ms: u32,
    pub observed_at_ms: u64,
}

#[derive(Default)]
struct CancellationSignal {
    cancelled: AtomicBool,
    changed: tokio::sync::Notify,
}

impl CancellationSignal {
    fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.changed.notify_waiters();
    }

    fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }

    async fn wait(&self) {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.is_cancelled() {
                return;
            }
            changed.await;
        }
    }
}

struct SelectionSlot {
    signal: Arc<CancellationSignal>,
    claimed: bool,
}

#[derive(Default)]
struct SelectionRegistry {
    active: HashMap<String, SelectionSlot>,
    // A synchronous cancellation can arrive before the FRB worker starts.
    // Keep bounded tombstones for that race, and recently finished
    // IDs so a late cancel does not turn a completed request into a tombstone.
    cancelled_before_start: VecDeque<(String, Instant)>,
    finished: VecDeque<(String, Instant)>,
}

impl SelectionRegistry {
    fn prune(&mut self) {
        let now = Instant::now();
        // A queued FRB call may be delayed arbitrarily by other native work.
        // Pending slots and pre-start cancellations never expire by time.
        while self
            .finished
            .front()
            .is_some_and(|(_, at)| now.duration_since(*at) > RECENT_ID_LIFETIME)
        {
            self.finished.pop_front();
        }
    }

    fn push_recent(queue: &mut VecDeque<(String, Instant)>, id: &str) {
        if !queue.iter().any(|(existing, _)| existing == id) {
            if queue.len() == MAX_RECENT_IDS {
                queue.pop_front();
            }
            queue.push_back((id.to_string(), Instant::now()));
        }
    }
}

static SELECTIONS: LazyLock<Mutex<SelectionRegistry>> =
    LazyLock::new(|| Mutex::new(SelectionRegistry::default()));

struct SelectionLease {
    id: String,
    signal: Arc<CancellationSignal>,
}

impl SelectionLease {
    #[cfg(test)]
    fn register(id: &str) -> Result<Self, String> {
        Self::claim(id, true)
    }

    fn claim(id: &str, allow_unreserved: bool) -> Result<Self, String> {
        if id.is_empty() || id.len() > 128 {
            return Err("automatic endpoint selection: invalid selection ID".to_string());
        }
        let mut registry = SELECTIONS
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        registry.prune();
        if let Some(slot) = registry.active.get_mut(id) {
            if slot.claimed {
                return Err("automatic endpoint selection: selection ID already used".to_string());
            }
            slot.claimed = true;
            return Ok(Self {
                id: id.to_string(),
                signal: slot.signal.clone(),
            });
        }
        if registry.finished.iter().any(|(existing, _)| existing == id) {
            return Err("automatic endpoint selection: selection ID already used".to_string());
        }
        if let Some(index) = registry
            .cancelled_before_start
            .iter()
            .position(|(existing, _)| existing == id)
        {
            registry.cancelled_before_start.remove(index);
            SelectionRegistry::push_recent(&mut registry.finished, id);
            return Err(CANCELLED.to_string());
        }
        if !allow_unreserved {
            return Err("automatic endpoint selection: selection was not reserved".to_string());
        }
        if registry.active.len() >= MAX_ACTIVE_SELECTIONS {
            return Err("automatic endpoint selection: too many active selections".to_string());
        }
        let signal = Arc::new(CancellationSignal::default());
        registry.active.insert(
            id.to_string(),
            SelectionSlot {
                signal: signal.clone(),
                claimed: true,
            },
        );
        Ok(Self {
            id: id.to_string(),
            signal,
        })
    }
}

impl Drop for SelectionLease {
    fn drop(&mut self) {
        let mut registry = SELECTIONS
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if registry
            .active
            .get(&self.id)
            .is_some_and(|slot| Arc::ptr_eq(&slot.signal, &self.signal))
        {
            registry.active.remove(&self.id);
            SelectionRegistry::push_recent(&mut registry.finished, &self.id);
        }
    }
}

/// Reserves bounded storage synchronously, before Dart dispatches its async
/// FRB call. Cancellation remains attached to this slot for as long as the
/// worker is queued, regardless of time or unrelated cancellation traffic.
pub(crate) fn begin_selection(id: &str) -> Result<(), String> {
    if id.is_empty() || id.len() > 128 {
        return Err("automatic endpoint selection: invalid selection ID".to_string());
    }
    let mut registry = SELECTIONS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    registry.prune();
    if registry.active.contains_key(id)
        || registry.finished.iter().any(|(existing, _)| existing == id)
    {
        return Err("automatic endpoint selection: selection ID already used".to_string());
    }
    if let Some(index) = registry
        .cancelled_before_start
        .iter()
        .position(|(existing, _)| existing == id)
    {
        registry.cancelled_before_start.remove(index);
        SelectionRegistry::push_recent(&mut registry.finished, id);
        return Err(CANCELLED.to_string());
    }
    if registry.active.len() >= MAX_ACTIVE_SELECTIONS {
        return Err("automatic endpoint selection: too many active selections".to_string());
    }
    registry.active.insert(
        id.to_string(),
        SelectionSlot {
            signal: Arc::new(CancellationSignal::default()),
            claimed: false,
        },
    );
    Ok(())
}

pub(crate) fn cancel_selection(id: &str) {
    if id.is_empty() || id.len() > 128 {
        return;
    }
    let signal = {
        let mut registry = SELECTIONS
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        registry.prune();
        if let Some(slot) = registry.active.get(id) {
            Some(slot.signal.clone())
        } else {
            if !registry.finished.iter().any(|(existing, _)| existing == id) {
                SelectionRegistry::push_recent(&mut registry.cancelled_before_start, id);
            }
            None
        }
    };
    if let Some(signal) = signal {
        signal.cancel();
    }
}

fn ready_route_revision() -> Result<u64, String> {
    let revision = network_privacy::route_revision();
    network_privacy::try_tor_client_for_route(false).map_err(|_| ROUTE_BLOCKED.to_string())?;
    if revision != network_privacy::route_revision() {
        return Err(ROUTE_BLOCKED.to_string());
    }
    Ok(revision)
}

pub(crate) fn probe_candidates(
    urls: Vec<String>,
    expected_network: &str,
    selection_id: &str,
    probe_timeout_ms: u32,
    total_timeout_ms: u32,
    max_concurrency: u32,
    wait_for_all: bool,
) -> Result<Vec<CandidateProbe>, String> {
    // Claim first, so invalid arguments also release a reservation rather than
    // leaving a pending slot forever. Production calls must reserve before
    // entering the FRB worker queue; an evicted legacy tombstone cannot start
    // an unreserved production request.
    let lease = SelectionLease::claim(selection_id, false)?;
    if lease.signal.is_cancelled() {
        return Err(CANCELLED.to_string());
    }
    keys::parse_network(expected_network)?;
    if urls.is_empty() || urls.len() > MAX_CANDIDATES || urls.iter().any(|url| url.len() > 2048) {
        return Err("automatic endpoint selection: invalid candidates".to_string());
    }
    let max_total_timeout_ms = if wait_for_all { 120_000 } else { 30_000 };
    if probe_timeout_ms == 0
        || total_timeout_ms == 0
        || total_timeout_ms > max_total_timeout_ms
        || max_concurrency == 0
    {
        return Err("automatic endpoint selection: invalid budget".to_string());
    }
    let mut seen = HashSet::new();
    let urls = urls
        .into_iter()
        .filter(|url| seen.insert(url.clone()))
        .collect();
    let route_revision = ready_route_revision()?;
    let expected_network = expected_network.to_owned();
    run_with_selection_runtime(lease, move |runtime, cancellation| {
        runtime.block_on(run_probe_batch(
            urls,
            max_concurrency.min(8) as usize,
            Duration::from_millis(u64::from(
                probe_timeout_ms.min(total_timeout_ms).min(30_000),
            )),
            Duration::from_millis(u64::from(total_timeout_ms)),
            wait_for_all,
            cancellation,
            || ready_route_revision().is_ok_and(|revision| revision == route_revision),
            |url| probe_candidate(url, &expected_network, cancellation, route_revision),
        ))
    })
}

/// Fast path for a recently chain-verified cached endpoint. Only the public
/// chain tip is requested; identity freshness is the caller's responsibility.
pub(crate) fn read_tip(
    url: String,
    expected_network: &str,
    selection_id: &str,
    timeout_ms: u32,
) -> Result<CandidateProbe, String> {
    let lease = SelectionLease::claim(selection_id, false)?;
    if lease.signal.is_cancelled() {
        return Err(CANCELLED.to_string());
    }
    keys::parse_network(expected_network)?;
    if url.is_empty() || url.len() > 2048 || timeout_ms == 0 || timeout_ms > 30_000 {
        return Err("automatic endpoint selection: invalid tip request".to_string());
    }
    let route_revision = ready_route_revision()?;
    let expected_network = expected_network.to_owned();
    run_with_selection_runtime(lease, move |runtime, cancellation| {
        runtime.block_on(async {
            let mut probes = run_probe_batch(
                vec![url],
                1,
                Duration::from_millis(u64::from(timeout_ms)),
                Duration::from_millis(u64::from(timeout_ms)),
                false,
                cancellation,
                || ready_route_revision().is_ok_and(|revision| revision == route_revision),
                |url| {
                    request_candidate_tip(
                        url,
                        &expected_network,
                        cancellation,
                        route_revision,
                        false,
                    )
                },
            )
            .await?;
            probes
                .pop()
                .ok_or_else(|| NO_HEALTHY_CANDIDATES.to_string())
        })
    })
}

fn run_with_selection_runtime<T: Send + 'static>(
    lease: SelectionLease,
    work: impl FnOnce(&tokio::runtime::Runtime, &CancellationSignal) -> Result<T, String>
        + Send
        + 'static,
) -> Result<T, String> {
    let (answer, receiver) = std::sync::mpsc::sync_channel(1);
    std::thread::Builder::new()
        .name("endpoint-selection".to_owned())
        .spawn(move || {
            // Public metadata probes are I/O-bound. One owning thread drives
            // their futures; the separate, explicitly bounded blocking pool
            // runs the OS resolver. No common wallet runtime is changed.
            let runtime = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .max_blocking_threads(MAX_SELECTION_BLOCKING_THREADS)
                .build()
            {
                Ok(runtime) => runtime,
                Err(error) => {
                    log::warn!("endpoint selection runtime setup failed: {error}");
                    let _ = answer.send(Err(LOCAL_WORKER_FAILED.to_owned()));
                    return;
                }
            };
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                if lease.signal.is_cancelled() {
                    Err(CANCELLED.to_owned())
                } else {
                    work(&runtime, &lease.signal)
                }
            }))
            .unwrap_or_else(|_| {
                log::error!("endpoint selection worker panicked");
                Err(LOCAL_WORKER_FAILED.to_owned())
            });
            // The caller never waits for an uninterruptible resolver to drain.
            // Capacity, however, is not free until Runtime::drop has joined it.
            let _ = answer.send(result);
            drop(runtime);
            drop(lease);
        })
        .map_err(|error| {
            log::warn!("endpoint selection worker setup failed: {error}");
            LOCAL_WORKER_FAILED.to_owned()
        })?;
    receiver
        .recv()
        .unwrap_or_else(|_| Err(LOCAL_WORKER_FAILED.to_owned()))
}

async fn probe_candidate(
    url: String,
    expected_network: &str,
    cancellation: &CancellationSignal,
    route_revision: u64,
) -> Result<CandidateProbe, String> {
    request_candidate_tip(url, expected_network, cancellation, route_revision, true).await
}

fn require_current_selection(
    cancellation: &CancellationSignal,
    route_revision: u64,
) -> Result<(), String> {
    if cancellation.is_cancelled() {
        return Err(CANCELLED.to_string());
    }
    if !ready_route_revision().is_ok_and(|revision| revision == route_revision) {
        return Err(ROUTE_BLOCKED.to_string());
    }
    Ok(())
}

async fn request_candidate_tip(
    url: String,
    expected_network: &str,
    cancellation: &CancellationSignal,
    route_revision: u64,
    verify_chain: bool,
) -> Result<CandidateProbe, String> {
    keys::parse_network(expected_network)?;
    require_current_selection(cancellation, route_revision)?;
    let started = Instant::now();
    let mut client =
        super::sync_engine::open_lwd_channel_with_cancel(&url, || cancellation.is_cancelled())
            .await
            .map_err(|error| error.to_string())?;
    let connected = Instant::now();
    require_current_selection(cancellation, route_revision)?;
    if verify_chain {
        let info = client
            .get_lightd_info(Request::new(Empty {}))
            .await
            .map_err(|error| error.to_string())?
            .into_inner();
        if info.chain_name != expected_network {
            return Err("automatic endpoint selection: wrong network".to_string());
        }
        require_current_selection(cancellation, route_revision)?;
    }
    let tip = client
        .get_latest_block(Request::new(ChainSpec {}))
        .await
        .map_err(|error| error.to_string())?
        .into_inner();
    let observed_at_ms = observation_time_ms();
    require_current_selection(cancellation, route_revision)?;
    let height = tip.height;
    Ok(CandidateProbe {
        url,
        height,
        latency_ms: millis(started.elapsed()),
        connect_ms: millis(connected.duration_since(started)),
        rpc_ms: millis(connected.elapsed()),
        observed_at_ms,
    })
}

fn observation_time_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(u128::from(u64::MAX)) as u64
}

fn millis(duration: Duration) -> u32 {
    duration.as_millis().min(u128::from(u32::MAX)) as u32
}

async fn run_probe_batch<F, Fut, R>(
    urls: Vec<String>,
    concurrency: usize,
    probe_timeout: Duration,
    total_timeout: Duration,
    wait_for_all: bool,
    cancellation: &CancellationSignal,
    route_is_current: R,
    probe: F,
) -> Result<Vec<CandidateProbe>, String>
where
    F: Fn(String) -> Fut,
    Fut: Future<Output = Result<CandidateProbe, String>>,
    R: Fn() -> bool,
{
    let mut probes = stream::iter(urls)
        .map(|url| {
            let candidate = probe(url);
            async move { tokio::time::timeout(probe_timeout, candidate).await }
        })
        .buffer_unordered(concurrency);
    let overall_deadline = tokio::time::Instant::now() + total_timeout;
    let mut finish_at = overall_deadline;
    let mut results = Vec::new();
    loop {
        // Cancellation and route changes win races with a response/deadline.
        if cancellation.is_cancelled() {
            return Err(CANCELLED.to_string());
        }
        if !route_is_current() {
            return Err(ROUTE_BLOCKED.to_string());
        }
        if tokio::time::Instant::now() >= finish_at {
            break;
        }
        tokio::select! {
            biased;
            _ = cancellation.wait() => return Err(CANCELLED.to_string()),
            _ = tokio::time::sleep_until(finish_at) => break,
            result = probes.next() => {
                match result {
                    Some(Ok(Ok(result)))
                        if (1..=u64::from(u32::MAX)).contains(&result.height) =>
                    {
                        if !wait_for_all && results.is_empty() {
                            finish_at = overall_deadline.min(tokio::time::Instant::now() + COMPARISON_WINDOW);
                        }
                        results.push(result);
                    }
                    Some(_) => {}
                    None => break,
                }
            }
            _ = tokio::time::sleep(ROUTE_CHECK_INTERVAL) => {}
        }
    }
    if cancellation.is_cancelled() {
        return Err(CANCELLED.to_string());
    }
    if !route_is_current() {
        return Err(ROUTE_BLOCKED.to_string());
    }
    if results.is_empty() {
        Err(NO_HEALTHY_CANDIDATES.to_string())
    } else {
        Ok(results)
    }
}

#[cfg(test)]
mod runtime_tests;

#[cfg(test)]
mod tests {
    use super::runtime_tests::assert_selection_released;
    use super::*;
    use std::sync::atomic::AtomicUsize;

    // These tests deliberately flood global cancellation storage. Keep them
    // isolated so a legacy unknown-ID tombstone test cannot be evicted by a
    // different test thread while it is between cancel and registration.
    static REGISTRY_TEST_LOCK: Mutex<()> = Mutex::new(());

    pub(super) fn registry_test_lock() -> std::sync::MutexGuard<'static, ()> {
        REGISTRY_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn result(url: String) -> CandidateProbe {
        CandidateProbe {
            url,
            height: 100,
            latency_ms: 10,
            connect_ms: 3,
            rpc_ms: 7,
            observed_at_ms: observation_time_ms(),
        }
    }

    #[tokio::test(start_paused = true)]
    async fn invalid_fast_tips_do_not_start_the_comparison_window_or_hide_queued_peers() {
        for invalid in [0, u64::from(u32::MAX) + 1, u64::MAX] {
            let signal = CancellationSignal::default();
            let started = tokio::time::Instant::now();
            let probes = run_probe_batch(
                vec!["invalid".into(), "healthy".into()],
                1,
                Duration::from_secs(2),
                Duration::from_secs(3),
                false,
                &signal,
                || true,
                |url| async move {
                    tokio::time::sleep(Duration::from_millis(if url == "invalid" {
                        10
                    } else {
                        500
                    }))
                    .await;
                    let mut sample = result(url.clone());
                    if url == "invalid" {
                        sample.height = invalid;
                    }
                    Ok(sample)
                },
            )
            .await
            .unwrap();
            assert_eq!(probes.len(), 1);
            assert_eq!(probes[0].url, "healthy");
            assert_eq!(started.elapsed(), Duration::from_millis(510));
        }
    }

    #[tokio::test(start_paused = true)]
    async fn invalid_only_tip_reads_and_complete_batches_have_no_healthy_candidates() {
        for wait_for_all in [false, true] {
            for invalid in [0, u64::from(u32::MAX) + 1] {
                let signal = CancellationSignal::default();
                let outcome = run_probe_batch(
                    vec!["invalid".into()],
                    1,
                    Duration::from_secs(1),
                    Duration::from_secs(2),
                    wait_for_all,
                    &signal,
                    || true,
                    |url| async move {
                        let mut sample = result(url);
                        sample.height = invalid;
                        Ok(sample)
                    },
                )
                .await
                .unwrap_err();
                assert_eq!(outcome, NO_HEALTHY_CANDIDATES);
            }
        }
    }

    #[tokio::test(start_paused = true)]
    async fn positive_u32_boundary_tips_are_accepted() {
        let signal = CancellationSignal::default();
        let probes = run_probe_batch(
            vec!["min".into(), "max".into()],
            2,
            Duration::from_secs(1),
            Duration::from_secs(2),
            false,
            &signal,
            || true,
            |url| async move {
                let mut sample = result(url.clone());
                sample.height = if url == "min" { 1 } else { u64::from(u32::MAX) };
                Ok(sample)
            },
        )
        .await
        .unwrap();
        assert_eq!(probes.len(), 2);
        assert!(probes.iter().any(|sample| sample.height == 1));
        assert!(probes
            .iter()
            .any(|sample| sample.height == u64::from(u32::MAX)));
    }

    #[tokio::test(start_paused = true)]
    async fn a_healthy_candidate_does_not_wait_for_slow_candidates_and_drops_their_futures() {
        let signal = CancellationSignal::default();
        let active = Arc::new(AtomicUsize::new(0));
        struct Active(Arc<AtomicUsize>);
        impl Drop for Active {
            fn drop(&mut self) {
                self.0.fetch_sub(1, Ordering::SeqCst);
            }
        }
        let started = tokio::time::Instant::now();
        let probes = run_probe_batch(
            vec!["slow".to_string(), "fast".to_string()],
            2,
            Duration::from_secs(10),
            Duration::from_secs(12),
            false,
            &signal,
            || true,
            |url| {
                let active = active.clone();
                async move {
                    active.fetch_add(1, Ordering::SeqCst);
                    let _active = Active(active);
                    tokio::time::sleep(if url == "fast" {
                        Duration::from_millis(20)
                    } else {
                        Duration::from_secs(10)
                    })
                    .await;
                    Ok(result(url))
                }
            },
        )
        .await
        .unwrap();
        assert_eq!(probes.len(), 1);
        assert_eq!(probes[0].url, "fast");
        assert_eq!(active.load(Ordering::SeqCst), 0);
        assert_eq!(started.elapsed(), Duration::from_millis(270));
    }

    #[tokio::test(start_paused = true)]
    async fn total_budget_and_concurrency_are_bounded_when_every_candidate_stalls() {
        let signal = CancellationSignal::default();
        let started_count = AtomicUsize::new(0);
        let started = tokio::time::Instant::now();
        let outcome = run_probe_batch(
            (0..20).map(|index| index.to_string()).collect(),
            3,
            Duration::from_secs(3),
            Duration::from_secs(5),
            false,
            &signal,
            || true,
            |_| {
                started_count.fetch_add(1, Ordering::SeqCst);
                std::future::pending::<Result<CandidateProbe, String>>()
            },
        )
        .await
        .unwrap_err();
        assert_eq!(outcome, NO_HEALTHY_CANDIDATES);
        assert_eq!(started.elapsed(), Duration::from_secs(5));
        assert_eq!(started_count.load(Ordering::SeqCst), 6);
    }

    #[tokio::test(start_paused = true)]
    async fn complete_comparison_reaches_faster_queued_candidates_without_charging_queue_time() {
        let signal = CancellationSignal::default();
        let started = tokio::time::Instant::now();
        let probes = run_probe_batch(
            vec![
                "first".to_string(),
                "second".to_string(),
                "tail".to_string(),
            ],
            1,
            Duration::from_secs(1),
            Duration::from_secs(4),
            true,
            &signal,
            || true,
            |url| async move {
                let started = tokio::time::Instant::now();
                tokio::time::sleep(Duration::from_millis(if url == "tail" { 10 } else { 500 }))
                    .await;
                let mut sample = result(url);
                sample.latency_ms = millis(started.elapsed());
                Ok(sample)
            },
        )
        .await
        .unwrap();
        assert_eq!(probes.len(), 3);
        assert_eq!(started.elapsed(), Duration::from_millis(1010));
        let fastest = probes
            .iter()
            .min_by_key(|sample| sample.latency_ms)
            .unwrap();
        assert_eq!(fastest.url, "tail");
        assert_eq!(fastest.latency_ms, 10);
    }

    #[tokio::test(start_paused = true)]
    async fn complete_comparison_gives_all_eight_tor_candidates_a_full_attempt() {
        let signal = CancellationSignal::default();
        let started_count = AtomicUsize::new(0);
        let started = tokio::time::Instant::now();
        let error = run_probe_batch(
            (0..8).map(|index| index.to_string()).collect(),
            2,
            Duration::from_secs(8),
            Duration::from_secs(34),
            true,
            &signal,
            || true,
            |_| {
                started_count.fetch_add(1, Ordering::SeqCst);
                std::future::pending::<Result<CandidateProbe, String>>()
            },
        )
        .await
        .unwrap_err();
        assert_eq!(error, NO_HEALTHY_CANDIDATES);
        assert_eq!(started_count.load(Ordering::SeqCst), 8);
        assert_eq!(started.elapsed(), Duration::from_secs(32));
    }

    #[tokio::test(start_paused = true)]
    async fn complete_comparison_still_honors_total_budget_after_a_success() {
        let signal = CancellationSignal::default();
        let started = tokio::time::Instant::now();
        let probes = run_probe_batch(
            vec!["fast".to_string(), "slow".to_string()],
            2,
            Duration::from_secs(8),
            Duration::from_secs(5),
            true,
            &signal,
            || true,
            |url| async move {
                if url == "slow" {
                    std::future::pending::<()>().await;
                }
                Ok(result(url))
            },
        )
        .await
        .unwrap();
        assert_eq!(probes.len(), 1);
        assert_eq!(probes[0].url, "fast");
        assert_eq!(started.elapsed(), Duration::from_secs(5));
    }

    #[tokio::test(start_paused = true)]
    async fn complete_comparison_discards_results_on_cancel_or_route_change() {
        for cancel in [false, true] {
            let signal = CancellationSignal::default();
            let current = AtomicBool::new(true);
            let stopped = AtomicBool::new(false);
            struct Active<'a>(&'a AtomicBool);
            impl Drop for Active<'_> {
                fn drop(&mut self) {
                    self.0.store(true, Ordering::Release);
                }
            }
            let stop = async {
                tokio::time::sleep(Duration::from_millis(50)).await;
                if cancel {
                    signal.cancel();
                } else {
                    current.store(false, Ordering::Release);
                }
            };
            let probe = run_probe_batch(
                vec!["fast".to_string(), "slow".to_string()],
                2,
                Duration::from_secs(8),
                Duration::from_secs(34),
                true,
                &signal,
                || current.load(Ordering::Acquire),
                |url| {
                    let stopped = &stopped;
                    async move {
                        if url == "slow" {
                            let _active = Active(stopped);
                            std::future::pending::<()>().await;
                        }
                        Ok(result(url))
                    }
                },
            );
            let (outcome, ()) = tokio::join!(probe, stop);
            assert_eq!(
                outcome.unwrap_err(),
                if cancel { CANCELLED } else { ROUTE_BLOCKED }
            );
            assert!(stopped.load(Ordering::Acquire));
        }
    }

    #[tokio::test]
    async fn only_complete_comparison_accepts_an_extended_but_bounded_total_budget() {
        let _registry = registry_test_lock();
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server =
            super::super::sync_engine::test_lwd::CapturingLwd::start_with(Vec::new(), 100, |_| {})
                .await;
        for (id, wait_for_all, budget) in [
            ("initial-extended-budget", false, 30_001),
            ("complete-over-budget", true, 120_001),
        ] {
            begin_selection(id).unwrap();
            let error = probe_candidates(
                vec![server.url.clone()],
                "main",
                id,
                8_000,
                budget,
                2,
                wait_for_all,
            )
            .unwrap_err();
            assert!(error.contains("invalid budget"));
            assert_selection_released(id);
        }
        assert!(server.requests().is_empty());
        let id = "complete-max-budget";
        begin_selection(id).unwrap();
        let url = server.url.clone();
        let probes = tokio::task::spawn_blocking(move || {
            probe_candidates(vec![url], "main", id, 8_000, 120_000, 2, true)
        })
        .await
        .unwrap()
        .unwrap();
        assert_eq!(probes.len(), 1);
        assert_selection_released(id);
        assert_eq!(server.count("/GetLightdInfo"), 1);
        assert_eq!(server.count("/GetLatestBlock"), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn cancellation_stops_active_work_and_is_scoped_to_its_selection() {
        let _registry = registry_test_lock();
        let first = SelectionLease::register("cancel-scoped-first").unwrap();
        let other = SelectionLease::register("cancel-scoped-other").unwrap();
        let cancel = async {
            tokio::time::sleep(Duration::from_millis(10)).await;
            cancel_selection("cancel-scoped-first");
        };
        let probe = run_probe_batch(
            vec!["slow".to_string()],
            1,
            Duration::from_secs(3),
            Duration::from_secs(5),
            false,
            &first.signal,
            || true,
            |_| std::future::pending::<Result<CandidateProbe, String>>(),
        );
        let (outcome, ()) = tokio::join!(probe, cancel);
        assert_eq!(outcome.unwrap_err(), CANCELLED);
        assert!(!other.signal.is_cancelled());
    }

    #[test]
    fn cancellation_before_worker_start_is_not_lost_and_late_cancellation_does_not_leak() {
        let _registry = registry_test_lock();
        cancel_selection("cancel-before-start");
        assert!(
            matches!(SelectionLease::register("cancel-before-start"), Err(error) if error == CANCELLED)
        );
        let completed = SelectionLease::register("cancel-after-end").unwrap();
        drop(completed);
        cancel_selection("cancel-after-end");
        let registry = SELECTIONS.lock().unwrap();
        assert!(!registry
            .cancelled_before_start
            .iter()
            .any(|(id, _)| id == "cancel-after-end"));
        assert!(!registry.active.contains_key("cancel-after-end"));
    }

    #[tokio::test(start_paused = true)]
    async fn a_route_change_discards_even_previously_successful_results() {
        let signal = CancellationSignal::default();
        let current = AtomicBool::new(true);
        let change = async {
            tokio::time::sleep(Duration::from_millis(50)).await;
            current.store(false, Ordering::Release);
        };
        let probe = run_probe_batch(
            vec!["fast".to_string(), "slow".to_string()],
            2,
            Duration::from_secs(3),
            Duration::from_secs(5),
            false,
            &signal,
            || current.load(Ordering::Acquire),
            |url| async move {
                if url == "slow" {
                    std::future::pending::<()>().await;
                }
                Ok(result(url))
            },
        );
        let (outcome, ()) = tokio::join!(probe, change);
        assert_eq!(outcome.unwrap_err(), ROUTE_BLOCKED);
    }

    #[tokio::test]
    async fn real_probe_uses_only_public_metadata_and_tip_on_the_same_channel() {
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start_with(
            Vec::new(),
            3_000_000,
            |_| {},
        )
        .await;
        let signal = CancellationSignal::default();
        let probe = probe_candidate(
            server.url.clone(),
            "main",
            &signal,
            ready_route_revision().unwrap(),
        )
        .await
        .unwrap();
        assert_eq!(probe.height, 3_000_000);
        let requests = server.requests();
        assert_eq!(requests.len(), 2);
        assert!(requests[0].ends_with("/GetLightdInfo"));
        assert!(requests[1].ends_with("/GetLatestBlock"));
        let cached = super::super::sync_engine::latest_block_for_transaction(
            &server.url,
            super::super::network::WalletNetwork::Main,
        )
        .await
        .unwrap();
        assert_eq!(cached.height, 3_000_000);
        assert_eq!(
            server.requests().len(),
            3,
            "candidate observation must not seed the transaction tip cache"
        );
        let reused = super::super::sync_engine::latest_block_for_transaction(
            &server.url,
            super::super::network::WalletNetwork::Main,
        )
        .await
        .unwrap();
        assert_eq!(reused.height, 3_000_000);
        assert_eq!(server.requests().len(), 3, "ordinary tip reads still cache");
    }

    async fn wait_for_tip_request(server: &super::super::sync_engine::test_lwd::CapturingLwd) {
        tokio::time::timeout(Duration::from_secs(2), async {
            while server.count("/GetLatestBlock") == 0 {
                tokio::time::sleep(Duration::from_millis(1)).await;
            }
        })
        .await
        .expect("tip request did not reach the local server");
    }

    #[tokio::test]
    async fn complete_batch_preserves_each_local_response_receipt_time() {
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let fast =
            super::super::sync_engine::test_lwd::CapturingLwd::start_with(Vec::new(), 100, |_| {})
                .await;
        let slow =
            super::super::sync_engine::test_lwd::CapturingLwd::start_with(Vec::new(), 100, |_| {})
                .await;
        let gate = slow.hold_responses("/GetLatestBlock");
        let first_completed = tokio::sync::Notify::new();
        let signal = CancellationSignal::default();
        let revision = ready_route_revision().unwrap();
        let probe = run_probe_batch(
            vec![fast.url.clone(), slow.url.clone()],
            2,
            Duration::from_secs(2),
            Duration::from_secs(3),
            true,
            &signal,
            || true,
            |url| {
                let is_fast = url == fast.url;
                let signal = &signal;
                let first_completed = &first_completed;
                async move {
                    let sample = probe_candidate(url, "main", signal, revision).await?;
                    if is_fast {
                        first_completed.notify_one();
                    }
                    Ok(sample)
                }
            },
        );
        let release = async {
            first_completed.notified().await;
            tokio::time::sleep(Duration::from_millis(20)).await;
            let released_at = observation_time_ms();
            gate.notify_one();
            released_at
        };
        let (samples, released_at) = tokio::join!(probe, release);
        let samples = samples.unwrap();
        assert_eq!(samples.len(), 2);
        assert!(
            samples
                .iter()
                .find(|sample| sample.url == fast.url)
                .unwrap()
                .observed_at_ms
                < released_at
        );
        assert!(
            samples
                .iter()
                .find(|sample| sample.url == slow.url)
                .unwrap()
                .observed_at_ms
                >= released_at
        );
    }

    #[tokio::test]
    async fn warm_tip_sends_one_latest_block_without_seeding_transaction_cache() {
        let _registry = registry_test_lock();
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start_with(
            Vec::new(),
            3_000_100,
            |_| {},
        )
        .await;
        let url = server.url.clone();
        let id = "warm-tip-one-rpc";
        begin_selection(id).unwrap();
        let requested_at = observation_time_ms();
        let probe = tokio::task::spawn_blocking(move || {
            crate::api::wallet::read_lightwalletd_tip(
                url,
                "main".to_string(),
                id.to_string(),
                1_000,
            )
        })
        .await
        .unwrap()
        .unwrap();
        assert_eq!(probe.url, server.url);
        assert_eq!(probe.height, 3_000_100);
        assert!(probe.observed_at_ms >= requested_at);
        assert!(probe.observed_at_ms <= observation_time_ms());
        assert_eq!(server.count("/GetLatestBlock"), 1);
        assert_eq!(server.count("/GetLightdInfo"), 0);
        assert_selection_released(id);
        let cached = super::super::sync_engine::latest_block_for_transaction(
            &server.url,
            super::super::network::WalletNetwork::Main,
        )
        .await
        .unwrap();
        assert_eq!(cached.height, 3_000_100);
        assert_eq!(
            server.requests().len(),
            2,
            "warm observation must not seed the transaction tip cache"
        );
    }

    #[tokio::test]
    async fn candidate_and_warm_observations_do_not_overwrite_an_existing_sync_tip() {
        let _registry = registry_test_lock();
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start_with(
            Vec::new(),
            3_000_200,
            |_| {},
        )
        .await;
        let network = super::super::network::WalletNetwork::Main;
        let existing = zcash_client_backend::proto::service::BlockId {
            height: 3_000_100,
            hash: vec![7; 32],
        };
        super::super::sync_engine::record_latest_block(&server.url, network, existing.clone());
        let signal = CancellationSignal::default();
        let probe = probe_candidate(
            server.url.clone(),
            "main",
            &signal,
            ready_route_revision().unwrap(),
        )
        .await
        .unwrap();
        assert_eq!(probe.height, 3_000_200);
        let retained =
            super::super::sync_engine::latest_block_for_transaction(&server.url, network)
                .await
                .unwrap();
        assert_eq!(retained, existing);
        assert_eq!(server.count("/GetLatestBlock"), 1);

        let id = "warm-tip-preserves-sync-cache";
        begin_selection(id).unwrap();
        let url = server.url.clone();
        let warm = tokio::task::spawn_blocking(move || read_tip(url, "main", id, 1_000))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(warm.height, 3_000_200);
        let retained =
            super::super::sync_engine::latest_block_for_transaction(&server.url, network)
                .await
                .unwrap();
        assert_eq!(retained, existing);
        assert_eq!(server.count("/GetLatestBlock"), 2);
    }

    #[tokio::test]
    async fn warm_tip_timeout_releases_its_claim_without_caching_a_late_reply() {
        let _registry = registry_test_lock();
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start_with(
            Vec::new(),
            3_000_200,
            |_| {},
        )
        .await;
        let gate = server.hold_responses("/GetLatestBlock");
        let url = server.url.clone();
        let id = "warm-tip-held-timeout";
        begin_selection(id).unwrap();
        let started = Instant::now();
        let error = tokio::time::timeout(
            Duration::from_secs(2),
            tokio::task::spawn_blocking(move || read_tip(url, "main", id, 100)),
        )
        .await
        .expect("warm tip exceeded its test guard")
        .unwrap()
        .unwrap_err();
        assert_eq!(error, NO_HEALTHY_CANDIDATES);
        assert!(started.elapsed() < Duration::from_secs(1));
        assert_selection_released(id);
        assert_eq!(server.count("/GetLatestBlock"), 1);
        gate.notify_waiters();
        gate.notify_one();
        let fresh = super::super::sync_engine::latest_block_for_transaction(
            &server.url,
            super::super::network::WalletNetwork::Main,
        )
        .await
        .unwrap();
        assert_eq!(fresh.height, 3_000_200);
        assert_eq!(
            server.count("/GetLatestBlock"),
            2,
            "a timed-out reply must not seed the tip cache"
        );
    }

    #[tokio::test]
    async fn warm_tip_cancellation_drops_active_rpc_and_releases_its_claim() {
        let _registry = registry_test_lock();
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start_with(
            Vec::new(),
            3_000_300,
            |_| {},
        )
        .await;
        let gate = server.hold_responses("/GetLatestBlock");
        let url = server.url.clone();
        let id = "warm-tip-cancel-active-rpc";
        begin_selection(id).unwrap();
        let worker = tokio::task::spawn_blocking(move || read_tip(url, "main", id, 5_000));
        wait_for_tip_request(&server).await;
        cancel_selection(id);
        let error = tokio::time::timeout(Duration::from_secs(2), worker)
            .await
            .expect("cancelled warm tip did not return")
            .unwrap()
            .unwrap_err();
        assert_eq!(error, CANCELLED);
        assert_selection_released(id);
        gate.notify_waiters();
        gate.notify_one();
        super::super::sync_engine::latest_block_for_transaction(
            &server.url,
            super::super::network::WalletNetwork::Main,
        )
        .await
        .unwrap();
        assert_eq!(
            server.count("/GetLatestBlock"),
            2,
            "cancelled work must not cache its late reply"
        );
        assert_eq!(server.count("/GetLightdInfo"), 0);
    }

    #[tokio::test]
    async fn warm_tip_route_change_drops_active_rpc_without_caching_its_reply() {
        let _registry = registry_test_lock();
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start_with(
            Vec::new(),
            3_000_400,
            |_| {},
        )
        .await;
        let gate = server.hold_responses("/GetLatestBlock");
        let url = server.url.clone();
        let id = "warm-tip-route-change";
        begin_selection(id).unwrap();
        let worker = tokio::task::spawn_blocking(move || read_tip(url, "main", id, 5_000));
        wait_for_tip_request(&server).await;
        network_privacy::begin_tor_enable();
        let error = tokio::time::timeout(Duration::from_secs(2), worker)
            .await
            .expect("route-changed warm tip did not return")
            .unwrap()
            .unwrap_err();
        assert_eq!(error, ROUTE_BLOCKED);
        assert_selection_released(id);
        network_privacy::disable_tor();
        gate.notify_waiters();
        gate.notify_one();
        super::super::sync_engine::latest_block_for_transaction(
            &server.url,
            super::super::network::WalletNetwork::Main,
        )
        .await
        .unwrap();
        assert_eq!(server.count("/GetLatestBlock"), 2);
    }

    #[test]
    fn warm_tip_pre_worker_cancel_and_invalid_arguments_release_the_claim() {
        let _registry = registry_test_lock();
        let id = "warm-tip-pre-worker-cancel";
        begin_selection(id).unwrap();
        cancel_selection(id);
        let error = read_tip("http://127.0.0.1:1".to_string(), "main", id, 50).unwrap_err();
        assert_eq!(error, CANCELLED);
        assert_selection_released(id);
        let id = "warm-tip-invalid-budget";
        begin_selection(id).unwrap();
        assert!(read_tip("http://127.0.0.1:1".to_string(), "main", id, 0)
            .unwrap_err()
            .contains("invalid tip request"));
        assert_selection_released(id);
    }

    #[tokio::test]
    async fn wrong_network_stops_before_requesting_the_tip() {
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start(Vec::new()).await;
        let signal = CancellationSignal::default();
        let error = probe_candidate(
            server.url.clone(),
            "test",
            &signal,
            ready_route_revision().unwrap(),
        )
        .await
        .unwrap_err();
        assert!(error.contains("wrong network"));
        assert_eq!(server.requests().len(), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn reserved_cancellation_survives_a_long_worker_queue_and_unrelated_cancellations() {
        let _registry = registry_test_lock();
        let id = "reserved-worker-queued-for-minutes";
        begin_selection(id).unwrap();
        cancel_selection(id);
        // Cancellation traffic can evict legacy unknown-ID tombstones, but a
        // production reservation remains an independently owned bounded slot.
        for index in 0..MAX_RECENT_IDS * 4 {
            cancel_selection(&format!("unrelated-queued-cancel-{index}"));
        }
        tokio::time::sleep(Duration::from_secs(10 * 60)).await;
        let error = probe_candidates(
            vec!["http://127.0.0.1:1".to_string()],
            "main",
            id,
            10,
            10,
            1,
            false,
        )
        .unwrap_err();
        assert_eq!(error, CANCELLED);
        assert_selection_released(id);
    }

    #[test]
    fn legacy_pre_start_cancellation_does_not_expire_while_its_worker_is_queued() {
        let _registry = registry_test_lock();
        let id = "legacy-worker-queued-past-expiry";
        SELECTIONS
            .lock()
            .unwrap()
            .cancelled_before_start
            .push_back((id.to_string(), Instant::now() - RECENT_ID_LIFETIME * 2));
        assert!(matches!(SelectionLease::register(id), Err(error) if error == CANCELLED));
    }

    #[test]
    fn a_reserved_slot_is_claimed_once_and_released_on_invalid_arguments() {
        let _registry = registry_test_lock();
        let id = "reserved-invalid-arguments";
        begin_selection(id).unwrap();
        let error = probe_candidates(Vec::new(), "main", id, 10, 10, 1, false).unwrap_err();
        assert!(error.contains("invalid candidates"));
        assert_selection_released(id);

        let id = "reserved-one-worker-only";
        begin_selection(id).unwrap();
        let first = SelectionLease::claim(id, false).unwrap();
        assert!(SelectionLease::claim(id, false).is_err());
        drop(first);
        assert!(SelectionLease::claim(id, false).is_err());
    }

    #[test]
    fn pending_reservations_apply_backpressure_until_their_workers_release_them() {
        let _registry = registry_test_lock();
        let ids: Vec<_> = (0..MAX_ACTIVE_SELECTIONS)
            .map(|index| format!("reserved-capacity-{index}"))
            .collect();
        for id in &ids {
            begin_selection(id).unwrap();
            cancel_selection(id);
        }
        assert!(begin_selection("reserved-capacity-overflow").is_err());
        for id in &ids {
            let worker = SelectionLease::claim(id, false).unwrap();
            assert!(worker.signal.is_cancelled());
            drop(worker);
        }
        begin_selection("reserved-capacity-after-drain").unwrap();
        drop(SelectionLease::claim("reserved-capacity-after-drain", false).unwrap());
    }

    #[test]
    fn unreserved_production_work_is_never_started() {
        let _registry = registry_test_lock();
        let error = probe_candidates(
            vec!["http://127.0.0.1:1".to_string()],
            "main",
            "not-reserved",
            10,
            10,
            1,
            false,
        )
        .unwrap_err();
        assert!(error.contains("not reserved"));
    }

    /// Manual loopback measurement of runtime-call overhead, without
    /// external network variance. Request-count assertions are deterministic.
    #[tokio::test]
    #[ignore = "manual loopback endpoint runtime overhead measurement"]
    async fn local_selection_runtime_overhead() {
        let _registry = registry_test_lock();
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let server = super::super::sync_engine::test_lwd::CapturingLwd::start_with(
            Vec::new(),
            3_000_000,
            |_| {},
        )
        .await;
        const SAMPLES: usize = 40;
        for cold in [false, true] {
            let mut times = Vec::new();
            for index in 0..SAMPLES + 5 {
                let url = server.url.clone();
                let id = format!("runtime-measure-{cold}-{index}");
                begin_selection(&id).unwrap();
                let elapsed = tokio::task::spawn_blocking(move || {
                    let start = Instant::now();
                    if cold {
                        probe_candidates(vec![url], "main", &id, 1_000, 1_000, 4, false).unwrap();
                    } else {
                        read_tip(url, "main", &id, 1_000).unwrap();
                    }
                    start.elapsed().as_micros()
                })
                .await
                .unwrap();
                if index >= 5 {
                    times.push(elapsed);
                }
            }
            times.sort();
            println!(
                "RUNTIME_OVERHEAD {} n={} median_us={} p95_us={}",
                if cold { "selection" } else { "warm" },
                SAMPLES,
                times[SAMPLES / 2],
                times[SAMPLES * 95 / 100]
            );
        }
        assert_eq!(server.count("/GetLightdInfo"), SAMPLES + 5);
        assert_eq!(server.count("/GetLatestBlock"), (SAMPLES + 5) * 2);
    }

    #[test]
    fn route_revision_detects_a_route_that_changed_away_and_back() {
        let _route = network_privacy::test_route_policy::lock_route_policy();
        let before = ready_route_revision().unwrap();
        network_privacy::begin_tor_enable();
        network_privacy::disable_tor();
        assert_ne!(ready_route_revision().unwrap(), before);
    }

    #[test]
    fn pre_start_cancellation_records_are_bounded() {
        let mut registry = SelectionRegistry::default();
        for index in 0..MAX_RECENT_IDS * 4 {
            SelectionRegistry::push_recent(
                &mut registry.cancelled_before_start,
                &index.to_string(),
            );
        }
        assert_eq!(registry.cancelled_before_start.len(), MAX_RECENT_IDS);
    }

    #[test]
    fn blocked_tor_is_not_measured_as_unhealthy_servers() {
        let _route = network_privacy::test_route_policy::lock_route_policy();
        network_privacy::begin_tor_enable();
        assert_eq!(ready_route_revision().unwrap_err(), ROUTE_BLOCKED);
    }
}
