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
/// The same bootstrap started from a background pass, where nobody is watching
/// and the execution window can be withdrawn at any moment.
///
/// A cold bootstrap measured 23.7 s on a fast link, so the deadline has to sit
/// well above that figure and not at it: the link here is only known to be
/// unmetered, not fast, and this bootstrap runs on the single-threaded FFI
/// runtime rather than the app's. Sixty seconds is roughly two and a half times
/// the measured cost — enough headroom for a slower link, while still leaving
/// the rest of the window for the work the bootstrap exists to enable, and
/// leaving a pass that gives up here time to defer cleanly instead of being
/// killed mid-bootstrap. Spending three minutes on it would consume most windows
/// whole and produce nothing.
const BACKGROUND_TOR_BOOTSTRAP_TIMEOUT: Duration = Duration::from_secs(60);
const TOR_BOOTSTRAP_TIMEOUT_MESSAGE: &str =
    "Tor could not connect. Check your internet connection and try again.";

const STATUS_DIRECT: u8 = 0;
const STATUS_BOOTSTRAPPING: u8 = 1;
const STATUS_READY: u8 = 2;
const STATUS_FAILED: u8 = 3;

static TOR_DESIRED: AtomicBool = AtomicBool::new(false);
/// Set as soon as anything in this process decides the route. A preference read
/// from outside Dart is only a fallback for a process that has not decided yet,
/// so it must never overwrite a decision that has already been made.
static ROUTE_DECIDED: AtomicBool = AtomicBool::new(false);
/// The dormancy asked for, kept whether or not a client exists yet. A request
/// that arrives mid-bootstrap has nothing to apply to, and neither the app
/// lifecycle callbacks nor a background pass about to do work repeat themselves.
static TOR_DORMANT: AtomicBool = AtomicBool::new(false);
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
    ROUTE_DECIDED.store(true, Ordering::Release);
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

/// Adopts a persisted Tor preference in a process where the Dart layer has not
/// run yet.
///
/// The desired route lives in process memory, so a background wake into a cold
/// process starts in direct mode and would route wallet traffic over clearnet
/// without ever asking the user. Marking makes that process fail closed: it
/// never bootstraps Tor by itself, so a pass that only marks can do no network
/// work and has to defer to the foreground. A pass that has established it can
/// afford a bootstrap calls [`enable_tor_for_background_work`] instead, which
/// marks first and then brings a client up.
///
/// The caller reads the preference from storage, so its answer can already be
/// stale by the time it arrives here — the user may have picked direct in the
/// meantime. A process that has decided its own route is therefore left alone;
/// otherwise a stale read could strand a deliberately-direct session in
/// fail-closed mode with nothing left to bootstrap it.
pub fn mark_tor_desired() {
    if ROUTE_DECIDED
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return;
    }
    begin_tor_enable();
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
/// Arti keeps guard connections and directory tasks running; on mobile that
/// costs battery in the background and, on iOS, does work in a state the OS
/// will kill. This never forces a bootstrap, but a request made while one is
/// still running is not lost either: a cold bootstrap takes tens of seconds,
/// long enough for the app to be backgrounded inside it, and neither the
/// lifecycle callbacks nor [`enable_tor_for_background_work`] repeat themselves
/// once it finishes.
pub fn set_tor_dormant(dormant: bool) {
    TOR_DORMANT.store(dormant, Ordering::Release);
    let slot = client_slot()
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(client) = slot.as_ref() else {
        return;
    };
    client.set_dormant(pending_dormant_mode());
    log::info!("network privacy: Tor dormant={dormant}");
}

/// The mode a client is put into as it is installed, so it never lands awake in
/// a backgrounded process that is not about to use it — the one background
/// caller that is says so by clearing the intent first. Applying `Soft` to a
/// client that has just finished bootstrapping is safe: arti lifts it back to
/// `Normal` on the next use.
fn pending_dormant_mode() -> DormantMode {
    if TOR_DORMANT.load(Ordering::Acquire) {
        DormantMode::Soft
    } else {
        DormantMode::Normal
    }
}

pub async fn enable_tor(tor_directory: &Path) -> Result<NetworkPrivacyStatus, String> {
    ROUTE_DECIDED.store(true, Ordering::Release);
    TOR_DESIRED.store(true, Ordering::Release);
    bootstrap_tor(tor_directory, TOR_BOOTSTRAP_TIMEOUT).await
}

/// Brings Tor up inside a background pass that has already established it can
/// afford one.
///
/// A cold bootstrap costs 8.45 MB down, 744 KB up and 23.7 s, and leaves a
/// 46.3 MB cache behind; a warm one costs 0.64 s and no bytes. The client then
/// pads its guard connection continuously for as long as it is awake — measured
/// at roughly 500 B/s, against 27 B/s dormant. That is affordable on external
/// power over an unmetered link and is not affordable on battery or on a metered
/// one, and only the caller can see power and metering state, so the caller
/// decides and this is reached only once that decision says yes.
///
/// The fail-closed mark comes first, so a pass refused below still cannot reach
/// the network directly. A process that has already decided its own route keeps
/// it: the caller's persisted read can be stale, and moving a session the user
/// deliberately put on the direct route onto Tor is not this function's call to
/// make. It reports `Direct` in that case, and the caller treats everything that
/// is not `Ready` alike — no network work, defer to the foreground.
pub async fn enable_tor_for_background_work(
    tor_directory: &Path,
) -> Result<NetworkPrivacyStatus, String> {
    mark_tor_desired();
    if !is_tor_desired() {
        return Ok(NetworkPrivacyStatus::Direct);
    }
    // The dormancy intent is process-wide and is applied to a client as that
    // client is installed, so a client bootstrapped here would come up asleep in
    // a process the app has already backgrounded, and a client the app put to
    // sleep on its way out would stay asleep. Neither suits a pass that is about
    // to do work, and this call is the point at which "about to do work" is
    // known. Waking costs a circuit build, which is why the app does not do this
    // speculatively; here the work is certain. The app's lifecycle owns the
    // intent again from its next foreground entry.
    set_tor_dormant(false);
    bootstrap_tor(tor_directory, BACKGROUND_TOR_BOOTSTRAP_TIMEOUT).await
}

async fn bootstrap_tor(
    tor_directory: &Path,
    deadline: Duration,
) -> Result<NetworkPrivacyStatus, String> {
    let _init_guard = init_lock().lock().await;
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
    // Returning here drops `_init_guard`, so a bootstrap that ran out of time
    // does not block the next enable attempt.
    install_bootstrapped_client(
        deadline,
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

    if !is_tor_desired() {
        return Ok(NetworkPrivacyStatus::Direct);
    }

    {
        // Adopting the pending mode under the install lock is what keeps a
        // request made mid-bootstrap from being overtaken by the client that
        // request was waiting for.
        let mut slot = client_slot()
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        client.set_dormant(pending_dormant_mode());
        *slot = Some(client);
    }
    TOR_STATUS.store(STATUS_READY, Ordering::Release);
    log::info!("network privacy: Tor is ready");
    Ok(NetworkPrivacyStatus::Ready)
}

async fn await_tor_bootstrap<T, E: Display>(
    deadline: Duration,
    bootstrap: impl Future<Output = Result<T, E>>,
) -> Result<T, String> {
    match tokio::time::timeout(deadline, bootstrap).await {
        Ok(Ok(client)) => Ok(client),
        Ok(Err(error)) => Err(format!("Bootstrap Tor: {error}")),
        Err(_) => Err(TOR_BOOTSTRAP_TIMEOUT_MESSAGE.to_string()),
    }
}

pub fn disable_tor() {
    ROUTE_DECIDED.store(true, Ordering::Release);
    TOR_DESIRED.store(false, Ordering::Release);
    TOR_STATUS.store(STATUS_DIRECT, Ordering::Release);
    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
    log::info!("network privacy: direct route enabled");
}

fn set_tor_failed() {
    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
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
            super::ROUTE_DECIDED.store(false, Ordering::Release);
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
        sync::atomic::Ordering,
        task::{Context, Poll, Waker},
        time::Duration,
    };

    use super::{
        await_tor_bootstrap, cancel_direct_connections, client_slot, disable_tor,
        enable_tor_for_background_work, init_lock, install_bootstrapped_client, is_tor_desired,
        mark_tor_desired, pending_dormant_mode, route_decision, set_tor_dormant, status,
        test_route_policy::lock_route_policy, tor_client_for_route, DirectRouteIo, DormantMode,
        NetworkPrivacyStatus, RouteDecision, TorClient, BACKGROUND_TOR_BOOTSTRAP_TIMEOUT,
        STATUS_READY, TOR_BOOTSTRAP_TIMEOUT, TOR_BOOTSTRAP_TIMEOUT_MESSAGE, TOR_STATUS,
    };

    #[test]
    fn direct_route_does_not_require_a_tor_client() {
        assert_eq!(
            route_decision(false, NetworkPrivacyStatus::Direct, false, false),
            Ok(RouteDecision::Direct)
        );
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
    fn marking_a_persisted_tor_route_refuses_instead_of_going_direct() {
        let _policy = lock_route_policy();
        assert_eq!(
            route_decision(is_tor_desired(), status(), false, false),
            Ok(RouteDecision::Direct)
        );

        mark_tor_desired();

        assert!(is_tor_desired());
        assert_eq!(
            route_decision(is_tor_desired(), status(), false, false),
            Err("Tor is still connecting")
        );
        assert!(tor_client_for_route(false).is_err());
    }

    #[test]
    fn marking_a_persisted_tor_route_does_not_bootstrap_a_client() {
        let _policy = lock_route_policy();

        mark_tor_desired();

        assert_eq!(status(), NetworkPrivacyStatus::Bootstrapping);
        assert!(client_slot()
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .is_none());
    }

    #[test]
    fn marking_a_persisted_tor_route_leaves_a_connected_process_alone() {
        let _policy = lock_route_policy();
        mark_tor_desired();
        TOR_STATUS.store(STATUS_READY, Ordering::Release);

        mark_tor_desired();

        assert_eq!(status(), NetworkPrivacyStatus::Ready);
    }

    #[test]
    fn marking_a_stale_tor_preference_leaves_a_process_that_chose_direct_alone() {
        let _policy = lock_route_policy();
        disable_tor();

        mark_tor_desired();

        assert!(!is_tor_desired());
        assert_eq!(status(), NetworkPrivacyStatus::Direct);
        assert!(matches!(tor_client_for_route(false), Ok(None)));
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
    fn the_background_bootstrap_deadline_outlasts_a_cold_bootstrap_without_eating_the_window() {
        // A cold bootstrap measured 23.7 s on a fast link, so a deadline at or
        // below that figure would refuse bootstraps that were going to succeed.
        assert!(BACKGROUND_TOR_BOOTSTRAP_TIMEOUT > Duration::from_secs(24));
        // And a background execution window is not the foreground's patience:
        // spending the foreground deadline here would consume most windows
        // whole and leave no time for the work the bootstrap is for.
        assert!(BACKGROUND_TOR_BOOTSTRAP_TIMEOUT < TOR_BOOTSTRAP_TIMEOUT);
    }

    #[tokio::test]
    async fn a_bootstrap_that_runs_out_of_time_stays_fail_closed() {
        let _policy = lock_route_policy();
        mark_tor_desired();

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
    async fn a_background_enable_marks_the_route_before_it_can_fail() {
        let _policy = lock_route_policy();
        let temp = tempfile::tempdir().unwrap();

        let result = enable_tor_for_background_work(&unusable_tor_directory(&temp)).await;

        assert!(result.is_err());
        assert!(is_tor_desired());
        assert_eq!(status(), NetworkPrivacyStatus::Failed);
        assert!(tor_client_for_route(false).is_err());
    }

    #[tokio::test]
    async fn a_background_enable_leaves_a_process_that_chose_direct_alone() {
        let _policy = lock_route_policy();
        disable_tor();
        set_tor_dormant(true);
        let temp = tempfile::tempdir().unwrap();

        let result = enable_tor_for_background_work(&unusable_tor_directory(&temp)).await;

        assert_eq!(result, Ok(NetworkPrivacyStatus::Direct));
        assert!(!is_tor_desired());
        assert_eq!(status(), NetworkPrivacyStatus::Direct);
        assert!(matches!(tor_client_for_route(false), Ok(None)));
        // Nothing here is about to do work on a Tor route, so the intent the
        // app's own lifecycle left behind is not this call's to overwrite.
        assert_eq!(pending_dormant_mode(), DormantMode::Soft);
        set_tor_dormant(false);
    }

    #[tokio::test]
    async fn a_background_enable_wakes_a_route_the_app_put_to_sleep() {
        let _policy = lock_route_policy();
        let temp = tempfile::tempdir().unwrap();
        set_tor_dormant(true);
        assert_eq!(pending_dormant_mode(), DormantMode::Soft);

        let _ = enable_tor_for_background_work(&unusable_tor_directory(&temp)).await;

        assert_eq!(pending_dormant_mode(), DormantMode::Normal);
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
