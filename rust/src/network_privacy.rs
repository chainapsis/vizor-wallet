//! Process-wide network privacy policy.
//!
//! The desired route is changed before Tor bootstrapping begins. Every
//! policy-aware network client therefore fails closed while Tor is starting or
//! after bootstrap failure instead of silently using a direct connection.

use std::{
    collections::HashMap,
    fmt::Display,
    future::Future,
    io,
    path::Path,
    pin::Pin,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicU8, AtomicUsize, Ordering},
        Mutex, OnceLock, RwLock,
    },
    task::{Context, Poll, Waker},
    time::Duration,
};

use zcash_client_backend::tor::{Client as TorClient, DormantMode, Timeouts as TorTimeouts};

/// `TorTimeouts` only bounds connect, request and response-body phases, so
/// bootstrapping itself is unbounded: arti retries it 128 times with a growing
/// backoff, which never terminates on a network that blocks Tor. A cold first
/// bootstrap over a slow link legitimately takes tens of seconds, so the
/// deadline stays generous enough to let those finish. A user watching the
/// route switch can also see it working and give up themselves, which a
/// background pass cannot.
const TOR_BOOTSTRAP_TIMEOUT: Duration = Duration::from_secs(3 * 60);
const TOR_BOOTSTRAP_TIMEOUT_MESSAGE: &str =
    "Tor could not connect. Check your internet connection and try again.";

const STATUS_DIRECT: u8 = 0;
const STATUS_BOOTSTRAPPING: u8 = 1;
const STATUS_READY: u8 = 2;
const STATUS_FAILED: u8 = 3;

static TOR_DESIRED: AtomicBool = AtomicBool::new(false);
/// The dormancy asked for, kept whether or not a client exists yet. A request
/// that arrives mid-bootstrap has nothing to apply to, and the app lifecycle
/// callbacks do not repeat themselves once it finishes.
static TOR_DORMANT: AtomicBool = AtomicBool::new(false);
/// Serialises reading the intent and applying a mode to the client, so two
/// lifecycle callbacks racing cannot apply a mode from a different moment than
/// the intent they read.
static DORMANT_APPLY_LOCK: Mutex<()> = Mutex::new(());
static TOR_STATUS: AtomicU8 = AtomicU8::new(STATUS_DIRECT);
static TOR_CLIENT: OnceLock<RwLock<Option<TorClient>>> = OnceLock::new();
static TOR_INIT_LOCK: OnceLock<tokio::sync::Mutex<()>> = OnceLock::new();
static DIRECT_ROUTE_EPOCH: AtomicU64 = AtomicU64::new(0);
static NEXT_DIRECT_IO_ID: AtomicU64 = AtomicU64::new(1);
static ACTIVE_DIRECT_IO: AtomicUsize = AtomicUsize::new(0);
static DIRECT_IO_WAKERS: OnceLock<Mutex<HashMap<u64, Waker>>> = OnceLock::new();
static DIRECT_IO_DRAINED: OnceLock<tokio::sync::Notify> = OnceLock::new();

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NetworkPrivacyStatus {
    Direct,
    Bootstrapping,
    Ready,
    Failed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RouteDecision {
    Direct,
    TorShared,
    TorIsolated,
}

fn client_slot() -> &'static RwLock<Option<TorClient>> {
    TOR_CLIENT.get_or_init(|| RwLock::new(None))
}

fn init_lock() -> &'static tokio::sync::Mutex<()> {
    TOR_INIT_LOCK.get_or_init(|| tokio::sync::Mutex::new(()))
}

pub fn is_tor_desired() -> bool {
    TOR_DESIRED.load(Ordering::Acquire)
}

pub fn status() -> NetworkPrivacyStatus {
    match TOR_STATUS.load(Ordering::Acquire) {
        STATUS_BOOTSTRAPPING => NetworkPrivacyStatus::Bootstrapping,
        STATUS_READY => NetworkPrivacyStatus::Ready,
        STATUS_FAILED => NetworkPrivacyStatus::Failed,
        _ => NetworkPrivacyStatus::Direct,
    }
}

/// Immediately changes the process policy to fail-closed Tor mode without
/// waiting for the previous transport to stop or for Tor to bootstrap.
/// Runtime toggles call this synchronously before their first `await`, so no
/// new policy-aware request can race onto clearnet during teardown.
pub fn begin_tor_enable() {
    let wakers = {
        let mut wakers = direct_io_wakers()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        TOR_DESIRED.store(true, Ordering::Release);
        TOR_STATUS.store(STATUS_BOOTSTRAPPING, Ordering::Release);
        DIRECT_ROUTE_EPOCH.fetch_add(1, Ordering::AcqRel);
        wakers.drain().map(|(_, waker)| waker).collect::<Vec<_>>()
    };
    for waker in wakers {
        waker.wake();
    }
    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
    log::info!("network privacy: Tor requested; direct requests blocked");
}

#[cfg(test)]
fn cancel_direct_connections() {
    let wakers = {
        let mut wakers = direct_io_wakers()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        DIRECT_ROUTE_EPOCH.fetch_add(1, Ordering::AcqRel);
        wakers.drain().map(|(_, waker)| waker).collect::<Vec<_>>()
    };
    for waker in wakers {
        waker.wake();
    }
}

fn direct_io_wakers() -> &'static Mutex<HashMap<u64, Waker>> {
    DIRECT_IO_WAKERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn direct_io_drained() -> &'static tokio::sync::Notify {
    DIRECT_IO_DRAINED.get_or_init(tokio::sync::Notify::new)
}

pub(crate) async fn wait_for_direct_connections_to_close(timeout: Duration) -> Result<(), String> {
    tokio::time::timeout(timeout, async {
        loop {
            let notified = direct_io_drained().notified();
            if ACTIVE_DIRECT_IO.load(Ordering::Acquire) == 0 {
                return;
            }
            notified.await;
        }
    })
    .await
    .map_err(|_| "Timed out waiting for direct network connections to stop".to_string())
}

pub(crate) struct DirectRouteLease {
    id: u64,
    epoch: u64,
}

impl DirectRouteLease {
    pub(crate) fn new() -> Self {
        ACTIVE_DIRECT_IO.fetch_add(1, Ordering::AcqRel);
        Self {
            id: NEXT_DIRECT_IO_ID.fetch_add(1, Ordering::Relaxed),
            epoch: DIRECT_ROUTE_EPOCH.load(Ordering::Acquire),
        }
    }

    pub(crate) fn poll<R, E>(
        &self,
        cx: &mut Context<'_>,
        poll_inner: impl FnOnce(&mut Context<'_>) -> Poll<Result<R, E>>,
    ) -> Poll<Result<R, E>>
    where
        E: From<io::Error>,
    {
        let mut wakers = direct_io_wakers()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if is_tor_desired() || self.epoch != DIRECT_ROUTE_EPOCH.load(Ordering::Acquire) {
            return Poll::Ready(Err(io::Error::new(
                io::ErrorKind::ConnectionAborted,
                "direct connection cancelled by Tor activation",
            )
            .into()));
        }
        wakers.insert(self.id, cx.waker().clone());
        let result = poll_inner(cx);
        drop(wakers);
        result
    }

    pub(crate) fn into_io<T>(self, inner: T) -> DirectRouteIo<T> {
        DirectRouteIo { inner, route: self }
    }
}

impl Drop for DirectRouteLease {
    fn drop(&mut self) {
        direct_io_wakers()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .remove(&self.id);
        if ACTIVE_DIRECT_IO.fetch_sub(1, Ordering::AcqRel) == 1 {
            direct_io_drained().notify_waiters();
        }
    }
}

pub(crate) struct DirectRouteIo<T> {
    inner: T,
    route: DirectRouteLease,
}

impl<T> DirectRouteIo<T> {
    #[cfg(test)]
    fn new(inner: T) -> Self {
        DirectRouteLease::new().into_io(inner)
    }

    #[cfg(test)]
    pub(crate) fn inner(&self) -> &T {
        &self.inner
    }
}

impl<T: hyper::rt::Read + Unpin> hyper::rt::Read for DirectRouteIo<T> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: hyper::rt::ReadBufCursor<'_>,
    ) -> Poll<Result<(), io::Error>> {
        let this = self.as_mut().get_mut();
        this.route
            .poll(cx, |cx| Pin::new(&mut this.inner).poll_read(cx, buf))
    }
}

impl<T: hyper::rt::Write + Unpin> hyper::rt::Write for DirectRouteIo<T> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<Result<usize, io::Error>> {
        let this = self.as_mut().get_mut();
        this.route
            .poll(cx, |cx| Pin::new(&mut this.inner).poll_write(cx, buf))
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), io::Error>> {
        let this = self.as_mut().get_mut();
        this.route
            .poll(cx, |cx| Pin::new(&mut this.inner).poll_flush(cx))
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Result<(), io::Error>> {
        let this = self.as_mut().get_mut();
        this.route
            .poll(cx, |cx| Pin::new(&mut this.inner).poll_shutdown(cx))
    }

    fn is_write_vectored(&self) -> bool {
        self.inner.is_write_vectored()
    }

    fn poll_write_vectored(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        bufs: &[io::IoSlice<'_>],
    ) -> Poll<Result<usize, io::Error>> {
        let this = self.as_mut().get_mut();
        this.route.poll(cx, |cx| {
            Pin::new(&mut this.inner).poll_write_vectored(cx, bufs)
        })
    }
}

/// Puts a Tor client to sleep, or wakes it up.
///
/// Arti keeps guard connections and directory tasks running; an idle client
/// pads its guard connection continuously — measured at roughly 500 B/s,
/// against 27 B/s dormant. On mobile that costs battery in a state the OS will
/// kill the app for, so the app asks for sleep on its way out and for
/// wakefulness on every foreground entry. This never forces a bootstrap, but a
/// request made while one is still running is not lost either: the intent is
/// process-wide, and a client picks it up as it is installed.
pub fn set_tor_dormant(dormant: bool) {
    {
        let _guard = dormant_apply_lock();
        TOR_DORMANT.store(dormant, Ordering::Release);
        apply_dormant_mode_locked();
    }
    log::info!("network privacy: Tor dormant={dormant}");
}

fn dormant_apply_lock() -> std::sync::MutexGuard<'static, ()> {
    DORMANT_APPLY_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The mode a client is put into as it is installed, so it never lands awake in
/// a process the app has already backgrounded. Applying `Soft` to a client that
/// has just finished bootstrapping is safe: arti lifts it back to `Normal` on
/// the next use.
fn pending_dormant_mode() -> DormantMode {
    if TOR_DORMANT.load(Ordering::Acquire) {
        DormantMode::Soft
    } else {
        DormantMode::Normal
    }
}

/// Pushes the mode the current state implies onto the installed client.
/// Caller holds [`DORMANT_APPLY_LOCK`], so the value read and the value applied
/// cannot come from different moments.
fn apply_dormant_mode_locked() {
    let mode = pending_dormant_mode();
    let slot = client_slot()
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(client) = slot.as_ref() {
        client.set_dormant(mode);
    }
}

pub async fn enable_tor(tor_directory: &Path) -> Result<NetworkPrivacyStatus, String> {
    TOR_DESIRED.store(true, Ordering::Release);
    bootstrap_tor(tor_directory, TOR_BOOTSTRAP_TIMEOUT).await
}

async fn bootstrap_tor(
    tor_directory: &Path,
    deadline: Duration,
) -> Result<NetworkPrivacyStatus, String> {
    // The deadline covers the wait for the init lock as well as the bootstrap
    // it guards, so it bounds the call the caller actually made.
    //
    // Two enables can be in flight at once — a foreground toggle and a
    // background pass — and the holder may be spending the foreground's three
    // minutes on a network that blocks Tor. A waiter that started its own timer
    // only after acquiring would sit there for the holder's deadline and then
    // its own on top. For a background pass that is the whole execution
    // opportunity spent inside one blocking call: it holds no cancellation
    // handle the OS expiration handler can reach, and every re-arm path lives
    // on the far side of it, so the window ends with nothing armed.
    let started = std::time::Instant::now();
    let Ok(_init_guard) = tokio::time::timeout(deadline, init_lock().lock()).await else {
        // Nothing is published here. Whichever bootstrap holds the lock owns the
        // status, and this call only reports that it could not get Tor up inside
        // its budget. The route stays Tor-desired either way, so every
        // policy-aware client keeps refusing — running out of patience is not a
        // reason to reach the network another way.
        return Err(TOR_BOOTSTRAP_TIMEOUT_MESSAGE.to_string());
    };
    if !is_tor_desired() {
        return Ok(NetworkPrivacyStatus::Direct);
    }
    if status() == NetworkPrivacyStatus::Ready
        && client_slot()
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .is_some()
    {
        return Ok(NetworkPrivacyStatus::Ready);
    }
    TOR_STATUS.store(STATUS_BOOTSTRAPPING, Ordering::Release);

    if let Err(error) = tokio::fs::create_dir_all(tor_directory).await {
        set_tor_failed();
        return Err(format!("Create Tor data directory: {error}"));
    }

    // Proving parameters and desktop updates can be tens or hundreds of
    // megabytes. Keep connect/header deadlines strict, while allowing a Tor
    // body that is actively streaming enough time to complete. Small app API
    // responses retain their own shorter body deadline.
    let timeouts = TorTimeouts::default().with_response_body(Duration::from_secs(2 * 60 * 60));
    // What is left of the budget after the wait, so waiting and bootstrapping
    // cannot add up to more than the caller asked for. Bounding the bootstrap
    // separately rather than wrapping the whole body in one timer is what keeps
    // a failure published: a timer that fired out here would drop
    // `install_bootstrapped_client` mid-await and skip the `set_tor_failed` it
    // exists to perform, leaving the status Bootstrapping with nothing running.
    let remaining = deadline.saturating_sub(started.elapsed());
    // Returning here drops `_init_guard`, so a bootstrap that ran out of time
    // does not block the next enable attempt.
    install_bootstrapped_client(
        remaining,
        TorClient::create_with_timeouts(
            tor_directory,
            // Arti refuses a data directory other users could reach. On desktop
            // those POSIX mode bits are the real boundary, so the check stays
            // on. On mobile the app sandbox is the boundary, and the pinned
            // fs-mistrust already knows it: on iOS and Android it compiles out
            // the owner check and stops forbidding the group bits, which is the
            // group-writable container ancestor that used to reject the
            // directory outright. What it still rejects there — a world-
            // writable ancestor, or arti's own 0o700 directories opened up — a
            // sandboxed container is not expected to have, so this bypass is
            // probably redundant. Dropping it needs evidence from a real
            // device, because a rejected directory fails the bootstrap from
            // inside fail-closed mode: every request blocked, Tor never Ready.
            |permissions| {
                #[cfg(any(target_os = "ios", target_os = "android"))]
                permissions.dangerously_trust_everyone();
                #[cfg(not(any(target_os = "ios", target_os = "android")))]
                let _ = permissions;
            },
            timeouts,
        ),
    )
    .await
}

/// Waits out one bootstrap attempt and publishes its outcome.
///
/// Running out of time is not a reason to reach the network another way: the
/// route stays Tor and the status becomes `Failed`, so every policy-aware client
/// keeps refusing until something bootstraps successfully.
async fn install_bootstrapped_client<E: Display>(
    deadline: Duration,
    bootstrap: impl Future<Output = Result<TorClient, E>>,
) -> Result<NetworkPrivacyStatus, String> {
    let client = match await_tor_bootstrap(deadline, bootstrap).await {
        Ok(client) => client,
        Err(error) => {
            set_tor_failed();
            return Err(error);
        }
    };

    {
        // The route is read and the client published under one lock, because
        // `disable_tor` takes the same one: a switch to direct that lands
        // between a check outside and the store would otherwise leave the
        // status Ready with the route direct, and an orphaned client awake and
        // padding behind it.
        let mut slot = client_slot()
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if !is_tor_desired() {
            return Ok(NetworkPrivacyStatus::Direct);
        }
        // Adopting the pending mode here is what keeps a sleep asked for
        // mid-bootstrap from being overtaken by the client it was waiting for.
        client.set_dormant(pending_dormant_mode());
        *slot = Some(client);
        TOR_STATUS.store(STATUS_READY, Ordering::Release);
    }
    log::info!("network privacy: Tor is ready");
    Ok(NetworkPrivacyStatus::Ready)
}

/// How often a running bootstrap checks whether the route it is for still
/// exists. Short enough that the abandon is not itself a wait, long enough to
/// cost nothing over the minutes a blocked bootstrap can take.
const BOOTSTRAP_ROUTE_POLL_INTERVAL: Duration = Duration::from_millis(250);
const BOOTSTRAP_ABANDONED_MESSAGE: &str = "Tor was turned off while it was connecting";

/// Waits out one bootstrap, and stops waiting if the route it is for goes away.
///
/// Clearing the client slot does not reach the `TorClient` future already
/// running here, so a user who turned Tor off left arti bootstrapping — talking
/// to directory authorities for up to the full deadline, on a route they had
/// just switched off, while holding the init lock a re-enable would have to
/// wait behind. Nothing wrong was ever published, because the publish re-reads
/// the route under the slot lock; what was wrong is that the work continued at
/// all.
///
/// Dropping the future is what cancels it, so the abandon is the return itself.
/// Polling rather than signalling: registering for a notification has a window
/// between the registration and the check that a route change can fall into,
/// and a quarter-second poll over a bootstrap measured in tens of seconds costs
/// less than closing that window would.
async fn await_tor_bootstrap<T, E: Display>(
    deadline: Duration,
    bootstrap: impl Future<Output = Result<T, E>>,
) -> Result<T, String> {
    tokio::pin!(bootstrap);
    let expires_at = tokio::time::Instant::now() + deadline;
    loop {
        tokio::select! {
            result = &mut bootstrap => {
                return match result {
                    Ok(client) => Ok(client),
                    Err(error) => Err(format!("Bootstrap Tor: {error}")),
                }
            }
            _ = tokio::time::sleep_until(expires_at) => {
                return Err(TOR_BOOTSTRAP_TIMEOUT_MESSAGE.to_string())
            }
            _ = tokio::time::sleep(BOOTSTRAP_ROUTE_POLL_INTERVAL) => {
                if !is_tor_desired() {
                    return Err(BOOTSTRAP_ABANDONED_MESSAGE.to_string());
                }
            }
        }
    }
}

pub fn disable_tor() {
    // Under the same lock a finishing bootstrap publishes through, so the two
    // cannot interleave into a Ready status on a direct route.
    let mut slot = client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    TOR_DESIRED.store(false, Ordering::Release);
    TOR_STATUS.store(STATUS_DIRECT, Ordering::Release);
    *slot = None;
    drop(slot);
    log::info!("network privacy: direct route enabled");
}

fn set_tor_failed() {
    let mut slot = client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    *slot = None;
    // Same lock as the publish and the disable: a route that went direct while
    // this bootstrap was failing keeps its own status.
    if is_tor_desired() {
        TOR_STATUS.store(STATUS_FAILED, Ordering::Release);
    }
}

fn route_decision(
    tor_desired: bool,
    tor_status: NetworkPrivacyStatus,
    has_client: bool,
    isolated: bool,
) -> Result<RouteDecision, &'static str> {
    if !tor_desired {
        return Ok(RouteDecision::Direct);
    }
    if tor_status != NetworkPrivacyStatus::Ready || !has_client {
        return Err(match tor_status {
            NetworkPrivacyStatus::Bootstrapping => "Tor is still connecting",
            NetworkPrivacyStatus::Failed => "Tor connection failed",
            _ => "Tor is enabled but unavailable",
        });
    }
    Ok(if isolated {
        RouteDecision::TorIsolated
    } else {
        RouteDecision::TorShared
    })
}

pub(crate) fn tor_client_for_route(isolated: bool) -> Result<Option<TorClient>, String> {
    let client = client_slot()
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    match route_decision(is_tor_desired(), status(), client.is_some(), isolated) {
        Ok(RouteDecision::Direct) => Ok(None),
        Ok(RouteDecision::TorShared) => Ok(client),
        Ok(RouteDecision::TorIsolated) => Ok(client.map(|client| client.isolated_client())),
        Err(error) => Err(error.to_string()),
    }
}

/// Serialises the tests that touch the process-wide route policy.
///
/// `cargo test` shares one process across threads, so this has to be reachable
/// from every module whose tests read the policy — not just the ones that write
/// it. A direct-route lease consults the desired route on every poll, so a test
/// that merely opens a direct connection fails if a route test is mid-flight.
#[cfg(test)]
pub(crate) mod test_route_policy {
    use std::sync::{atomic::Ordering, Mutex, MutexGuard};

    static ROUTE_POLICY: Mutex<()> = Mutex::new(());

    pub(crate) struct RoutePolicyGuard {
        _lock: MutexGuard<'static, ()>,
    }

    impl Drop for RoutePolicyGuard {
        /// Hands the process back in its default state. The direct-route epoch
        /// only ever moves forward and each lease compares against the value it
        /// captured, so it needs no restoring.
        fn drop(&mut self) {
            super::disable_tor();
            // The intent is process-wide and one process runs every test in
            // this crate: a test that asks for dormancy and returns would
            // otherwise decide later assertions by execution order.
            super::TOR_DORMANT.store(false, Ordering::Release);
        }
    }

    pub(crate) fn lock_route_policy() -> RoutePolicyGuard {
        RoutePolicyGuard {
            _lock: ROUTE_POLICY
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner()),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        task::{Context, Poll, Waker},
        time::Duration,
    };

    use super::{
        await_tor_bootstrap, begin_tor_enable, bootstrap_tor, cancel_direct_connections,
        client_slot, disable_tor, init_lock, install_bootstrapped_client, is_tor_desired,
        pending_dormant_mode, route_decision, set_tor_dormant, set_tor_failed, status,
        test_route_policy::lock_route_policy, tor_client_for_route, DirectRouteIo, DormantMode,
        NetworkPrivacyStatus, RouteDecision, TorClient, BOOTSTRAP_ABANDONED_MESSAGE,
        TOR_BOOTSTRAP_TIMEOUT_MESSAGE,
    };

    #[test]
    fn direct_route_does_not_require_a_tor_client() {
        assert_eq!(
            route_decision(false, NetworkPrivacyStatus::Direct, false, false),
            Ok(RouteDecision::Direct)
        );
    }

    #[tokio::test]
    async fn a_bootstrap_stops_when_the_route_it_is_for_goes_away() {
        let _policy = lock_route_policy();
        begin_tor_enable();

        let switching_to_direct = tokio::spawn(async {
            tokio::time::sleep(Duration::from_millis(300)).await;
            disable_tor();
        });
        let result = await_tor_bootstrap(
            Duration::from_secs(5),
            std::future::pending::<Result<(), String>>(),
        )
        .await;
        switching_to_direct.await.expect("the disable task");

        assert_eq!(result.unwrap_err(), BOOTSTRAP_ABANDONED_MESSAGE);
    }

    #[test]
    fn tor_bootstrap_and_failure_are_fail_closed() {
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Bootstrapping, false, false),
            Err("Tor is still connecting")
        );
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Failed, false, false),
            Err("Tor connection failed")
        );
    }

    #[test]
    fn ready_tor_selects_shared_or_isolated_routes() {
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Ready, true, false),
            Ok(RouteDecision::TorShared)
        );
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Ready, true, true),
            Ok(RouteDecision::TorIsolated)
        );
    }

    #[test]
    fn ready_status_without_a_client_is_still_fail_closed() {
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Ready, false, false),
            Err("Tor is enabled but unavailable")
        );
    }

    #[test]
    fn a_dormancy_request_made_before_the_client_exists_is_applied_to_it() {
        let _policy = lock_route_policy();
        assert!(client_slot()
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .is_none());

        set_tor_dormant(true);
        assert_eq!(pending_dormant_mode(), DormantMode::Soft);

        set_tor_dormant(false);
        assert_eq!(pending_dormant_mode(), DormantMode::Normal);
    }

    /// A test's dormancy intent must not outlive its route-policy guard.
    #[test]
    fn the_route_policy_guard_hands_back_the_default_dormancy_intent() {
        {
            let _policy = lock_route_policy();
            set_tor_dormant(true);
            assert_eq!(pending_dormant_mode(), DormantMode::Soft);
        }

        let _policy = lock_route_policy();

        assert_eq!(pending_dormant_mode(), DormantMode::Normal);
    }

    #[test]
    fn direct_route_io_is_cancelled_when_tor_activation_advances_the_epoch() {
        let _policy = lock_route_policy();
        let io = DirectRouteIo::new(());
        let waker = Waker::noop();
        let mut context = Context::from_waker(waker);
        assert!(io
            .route
            .poll(&mut context, |_| {
                Poll::<Result<(), std::io::Error>>::Pending
            })
            .is_pending());

        cancel_direct_connections();

        let Poll::Ready(Err(error)) = io.route.poll(&mut context, |_| {
            Poll::<Result<(), std::io::Error>>::Pending
        }) else {
            panic!("cancelled direct route remained pending");
        };
        assert_eq!(error.kind(), std::io::ErrorKind::ConnectionAborted);
    }

    #[tokio::test]
    async fn a_stalled_tor_bootstrap_fails_instead_of_retrying_forever() {
        let result = await_tor_bootstrap(
            Duration::from_millis(1),
            std::future::pending::<Result<(), String>>(),
        )
        .await;

        assert_eq!(result.unwrap_err(), TOR_BOOTSTRAP_TIMEOUT_MESSAGE);
    }

    /// A path that already exists as a file, so a bootstrap started against it
    /// fails at its first filesystem step. No test may reach a real bootstrap:
    /// that is network work, and on a blocked network it does not terminate.
    fn unusable_tor_directory(temp: &tempfile::TempDir) -> std::path::PathBuf {
        let path = temp.path().join("tor");
        std::fs::write(&path, b"").unwrap();
        path
    }

    #[test]
    fn a_route_that_went_direct_keeps_its_status_when_a_bootstrap_fails() {
        let _policy = lock_route_policy();
        begin_tor_enable();
        disable_tor();

        assert_eq!(status(), NetworkPrivacyStatus::Direct);
        assert!(client_slot()
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .is_none());

        // A bootstrap started before the switch reports its failure afterwards.
        // The route is direct now, so the failure is not this route's to
        // publish — a Failed status here would block requests the user asked to
        // send directly.
        set_tor_failed();

        assert_eq!(status(), NetworkPrivacyStatus::Direct);
        assert_eq!(
            route_decision(is_tor_desired(), status(), false, false),
            Ok(RouteDecision::Direct)
        );
    }

    #[tokio::test]
    async fn a_bootstrap_that_runs_out_of_time_stays_fail_closed() {
        let _policy = lock_route_policy();
        begin_tor_enable();

        let result = install_bootstrapped_client(
            Duration::from_millis(1),
            std::future::pending::<Result<TorClient, String>>(),
        )
        .await;

        assert_eq!(result.unwrap_err(), TOR_BOOTSTRAP_TIMEOUT_MESSAGE);
        assert!(is_tor_desired());
        assert_eq!(status(), NetworkPrivacyStatus::Failed);
        assert!(tor_client_for_route(false).is_err());
    }

    #[tokio::test]
    async fn a_bootstrap_waiting_on_another_bootstrap_is_bounded_by_its_own_deadline() {
        let _policy = lock_route_policy();
        let temp = tempfile::tempdir().unwrap();
        begin_tor_enable();

        // A bootstrap already in flight, of the kind a foreground enable starts:
        // it holds the init lock for far longer than the waiter's whole budget.
        let (acquired_tx, acquired_rx) = tokio::sync::oneshot::channel();
        let holder = tokio::spawn(async move {
            let _init_guard = init_lock().lock().await;
            let _ = acquired_tx.send(());
            tokio::time::sleep(Duration::from_secs(10)).await;
        });
        acquired_rx.await.unwrap();

        let started = std::time::Instant::now();
        let result = bootstrap_tor(&unusable_tor_directory(&temp), Duration::from_millis(100)).await;
        let waited = started.elapsed();

        holder.abort();
        let _ = holder.await;

        // The deadline covers the wait, not just the bootstrap on its far side.
        // A background pass has one execution opportunity and no cancellation
        // handle reaching into this call, so parking here for the holder's
        // deadline spends the window with nothing armed.
        assert!(
            waited < Duration::from_secs(5),
            "a waiting bootstrap ignored its own deadline: waited {waited:?}"
        );
        assert_eq!(result.unwrap_err(), TOR_BOOTSTRAP_TIMEOUT_MESSAGE);
        // Running out of time is still not a reason to reach the network another
        // way: the route stays Tor and every policy-aware client keeps refusing.
        assert!(is_tor_desired());
        assert!(tor_client_for_route(false).is_err());
    }

    #[tokio::test]
    async fn a_stalled_tor_bootstrap_releases_the_init_lock_for_the_next_attempt() {
        // The route-policy lock covers the init lock too: the background enable
        // tests reach it through a real `bootstrap_tor`, and this test reads it
        // as a global, so an unserialised run sees the other test's guard and
        // reports it as a leak.
        let _policy = lock_route_policy();
        let result = {
            let _init_guard = init_lock().lock().await;
            await_tor_bootstrap(
                Duration::from_millis(1),
                std::future::pending::<Result<(), String>>(),
            )
            .await
        };

        assert!(result.is_err());
        assert!(
            init_lock().try_lock().is_ok(),
            "a timed-out Tor bootstrap kept the init lock"
        );
    }
}
