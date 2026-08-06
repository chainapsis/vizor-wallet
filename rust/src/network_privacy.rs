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

use zcash_client_backend::tor::{Client as TorClient, Timeouts as TorTimeouts};

/// `TorTimeouts` only bounds connect, request and response-body phases, so
/// bootstrapping itself is unbounded: arti retries it 128 times with a growing
/// backoff, which never terminates on a network that blocks Tor. A cold first
/// bootstrap over a slow link legitimately takes tens of seconds, so the
/// deadline stays generous enough to let those finish.
const TOR_BOOTSTRAP_TIMEOUT: Duration = Duration::from_secs(3 * 60);
const TOR_BOOTSTRAP_TIMEOUT_MESSAGE: &str =
    "Tor could not connect. Check your internet connection and try again.";

const STATUS_DIRECT: u8 = 0;
const STATUS_BOOTSTRAPPING: u8 = 1;
const STATUS_READY: u8 = 2;
const STATUS_FAILED: u8 = 3;

static TOR_DESIRED: AtomicBool = AtomicBool::new(false);
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

pub async fn enable_tor(tor_directory: &Path) -> Result<NetworkPrivacyStatus, String> {
    TOR_DESIRED.store(true, Ordering::Release);

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
    let client = match await_tor_bootstrap(
        TOR_BOOTSTRAP_TIMEOUT,
        TorClient::create_with_timeouts(tor_directory, |_| {}, timeouts),
    )
    .await
    {
        Ok(client) => client,
        Err(error) => {
            set_tor_failed();
            return Err(error);
        }
    };

    if !is_tor_desired() {
        return Ok(NetworkPrivacyStatus::Direct);
    }

    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(client);
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

#[cfg(test)]
mod tests {
    use std::{
        task::{Context, Poll, Waker},
        time::Duration,
    };

    use super::{
        await_tor_bootstrap, cancel_direct_connections, init_lock, route_decision, DirectRouteIo,
        NetworkPrivacyStatus, RouteDecision, TOR_BOOTSTRAP_TIMEOUT_MESSAGE,
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
    fn direct_route_io_is_cancelled_when_tor_activation_advances_the_epoch() {
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

    #[tokio::test]
    async fn a_stalled_tor_bootstrap_releases_the_init_lock_for_the_next_attempt() {
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
