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
/// Refused at the route chokepoint when nothing in this process has said which
/// route it is on.
///
/// The desired route lives in process memory and defaults to direct, so an
/// entry point that never declares would otherwise reach lightwalletd over
/// clearnet on a Tor-configured wallet — silently, and only in the lane that
/// forgot. Declaring is one call ([`mark_tor_desired`], [`mark_direct_route`],
/// [`begin_tor_enable`], [`enable_tor`] or [`disable_tor`]); not declaring is
/// now an error every caller sees rather than a leak nobody does.
const ROUTE_NOT_DECLARED_MESSAGE: &str = "Network route has not been declared for this process";

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
/// Monotonic milliseconds, from [`process_uptime_ms`], until which a background
/// pass needs the client awake. Zero means no pass holds one.
static BACKGROUND_WAKE_UNTIL_MS: AtomicU64 = AtomicU64::new(0);
static PROCESS_START: OnceLock<std::time::Instant> = OnceLock::new();
/// Serialises reading the intent and applying a mode to the client, so a pass
/// whose wake lapses cannot overwrite an intent that changed a moment earlier.
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
    ROUTE_DECIDED.store(true, Ordering::Release);
    // The route and the status are written inside the slot lock, the way
    // `disable_tor`, `install_bootstrapped_client` and `set_tor_failed` write
    // them.
    //
    // This is strict alignment with those three, not a fix: no interleaving
    // that actually diverges was constructed for the enable direction, which
    // only ever tightens the policy. What it buys is one rule about where these
    // two atomics may be written instead of three paths that follow it and one
    // that does not, so the next reader does not have to re-derive whether this
    // one is safe. The lock order is the same one the siblings take — slot
    // first, then the waker map — and nothing reached while holding the waker
    // map takes the slot, so there is no inversion to introduce.
    let mut slot = client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let wakers = {
        let mut wakers = direct_io_wakers()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        TOR_DESIRED.store(true, Ordering::Release);
        TOR_STATUS.store(STATUS_BOOTSTRAPPING, Ordering::Release);
        DIRECT_ROUTE_EPOCH.fetch_add(1, Ordering::AcqRel);
        wakers.drain().map(|(_, waker)| waker).collect::<Vec<_>>()
    };
    *slot = None;
    drop(slot);
    // Woken with both locks released. A woken lease re-reads the route and
    // aborts itself without touching either, but waking underneath them would
    // hand a scheduler the opportunity to run that on this thread.
    for waker in wakers {
        waker.wake();
    }
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

/// Adopts a persisted *direct* preference in a process where the Dart layer has
/// not run yet — the mirror of [`mark_tor_desired`].
///
/// Direct is where the atomics start, so this writes nothing but the decision
/// itself. That is the whole point: without it, "nobody has said yet" and "the
/// user chose direct" are the same state, and [`route_decision`] cannot refuse
/// the first while allowing the second. A background entry point that reaches
/// lightwalletd on a direct-route wallet calls this, and one that forgets is
/// refused instead of quietly reaching clearnet on a wallet whose route it
/// never read.
///
/// Stale in the same way its sibling is — the caller read the preference from
/// storage — so a process that has already decided its own route keeps it, and
/// this never turns a live Tor route direct.
pub fn mark_direct_route() {
    if ROUTE_DECIDED
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return;
    }
    log::info!("network privacy: direct route adopted from the saved preference");
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

fn process_uptime_ms() -> u64 {
    PROCESS_START
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_millis()
        .min(u128::from(u64::MAX)) as u64
}

/// How long a background pass's wake survives without being renewed.
///
/// A pass renews it every time it brings Tor up, and the confirmation tracker
/// does that once per polling round, so this only has to outlast one round with
/// slack. What it actually bounds is the other direction: how long a client
/// keeps padding its guard connection after the last pass stopped asking for
/// anything.
const BACKGROUND_WAKE_LEASE: Duration = Duration::from_secs(2 * 60);

fn background_wake_is_held() -> bool {
    let until = BACKGROUND_WAKE_UNTIL_MS.load(Ordering::Acquire);
    until != 0 && process_uptime_ms() < until
}

/// The mode the client should be in, from the app's intent and whether a
/// background pass currently needs it awake.
///
/// The pass masks the intent rather than overwriting it. There is consequently
/// nothing for a pass to restore, and no end-of-pass call for any of its exits
/// to forget: the mask lapses on its own, and a foreground entry that clears the
/// intent while a pass is still running wins immediately, so a pass can never
/// put a client to sleep underneath an app that wants it awake.
fn dormant_mode_for(app_intent_dormant: bool, background_wake_held: bool) -> DormantMode {
    if app_intent_dormant && !background_wake_held {
        DormantMode::Soft
    } else {
        DormantMode::Normal
    }
}

/// The mode a client is put into as it is installed, so it never lands awake in
/// a backgrounded process that is not about to use it. Applying `Soft` to a
/// client that has just finished bootstrapping is safe: arti lifts it back to
/// `Normal` on the next use.
fn pending_dormant_mode() -> DormantMode {
    dormant_mode_for(
        TOR_DORMANT.load(Ordering::Acquire),
        background_wake_is_held(),
    )
}

/// Marks the client as needed by a background pass for the next lease window,
/// and arranges for that to lapse without anything having to say so.
///
/// Renewing rather than extending: a later hold always wins, and the release
/// belongs to whichever hold set the deadline that is still current when it
/// fires.
fn hold_background_wake() {
    let deadline = process_uptime_ms().saturating_add(BACKGROUND_WAKE_LEASE.as_millis() as u64);
    {
        let _guard = dormant_apply_lock();
        BACKGROUND_WAKE_UNTIL_MS.fetch_max(deadline, Ordering::AcqRel);
        apply_dormant_mode_locked();
    }
    schedule_background_wake_release(deadline);
}

/// Waits out one lease and hands the client back to the app's intent.
///
/// A process with no runtime here simply has no timer; the lease still lapses by
/// time, so the next thing to read the mode computes the released value. What is
/// lost in that case is only the moment the client is put back to sleep, not
/// whether it is.
fn schedule_background_wake_release(deadline: u64) {
    let Ok(handle) = tokio::runtime::Handle::try_current() else {
        return;
    };
    handle.spawn(async move {
        loop {
            let current = BACKGROUND_WAKE_UNTIL_MS.load(Ordering::Acquire);
            // Released already, or a later hold owns the release now.
            if current == 0 || current > deadline {
                return;
            }
            let now = process_uptime_ms();
            if now < current {
                tokio::time::sleep(Duration::from_millis(current - now)).await;
                continue;
            }
            let _guard = dormant_apply_lock();
            if BACKGROUND_WAKE_UNTIL_MS
                .compare_exchange(current, 0, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
            {
                apply_dormant_mode_locked();
            }
            return;
        }
    });
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
    // known.
    //
    // Held rather than written. The intent belongs to the app lifecycle, and a
    // pass that overwrote it would leave the client awake for as long as the
    // process lived: `onHide` has already run by the time a pass starts, or
    // never runs at all on a cold background launch, and the next foreground
    // callback asks for awake too. So nothing would ask for sleep again on
    // exactly the battery or metered route the caller's gate exists to protect.
    hold_background_wake();
    bootstrap_tor(tor_directory, BACKGROUND_TOR_BOOTSTRAP_TIMEOUT).await
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
        //
        // Adopting the pending mode here too is what keeps a request made
        // mid-bootstrap from being overtaken by the client it was waiting for.
        let mut slot = client_slot()
            .write()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if !is_tor_desired() {
            return Ok(NetworkPrivacyStatus::Direct);
        }
        client.set_dormant(pending_dormant_mode());
        *slot = Some(client);
        TOR_STATUS.store(STATUS_READY, Ordering::Release);
    }
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
    route_decided: bool,
    tor_desired: bool,
    tor_status: NetworkPrivacyStatus,
    has_client: bool,
    isolated: bool,
) -> Result<RouteDecision, &'static str> {
    // Direct is a decision, not a default. Every Rust lightwalletd connection
    // funnels through here, and the entry points that reach it from outside
    // Dart — the C background calls, and anything added beside them — carry
    // their contract to declare in a header comment and in their callers. A
    // lane that forgets fails here, loudly and on its first connection, instead
    // of reaching lightwalletd over clearnet on a Tor-configured wallet with
    // nothing failing to compile and no test going red.
    if !route_decided {
        return Err(ROUTE_NOT_DECLARED_MESSAGE);
    }
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

fn is_route_decided() -> bool {
    ROUTE_DECIDED.load(Ordering::Acquire)
}

pub(crate) fn tor_client_for_route(isolated: bool) -> Result<Option<TorClient>, String> {
    let client = client_slot()
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    match route_decision(
        is_route_decided(),
        is_tor_desired(),
        status(),
        client.is_some(),
        isolated,
    ) {
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
            // A lease outlives the test that took it, and it masks the intent
            // every later test reads.
            super::BACKGROUND_WAKE_UNTIL_MS.store(0, Ordering::Release);
            // The intent the lease masks leaks the same way, and one process
            // runs every test in this crate: a test that asks for dormancy and
            // returns leaves process-wide dormancy intent set for all of them,
            // so any later assertion about the mode is decided by test order.
            // Restored here rather than by each test's last line, because the
            // guard is what owns handing the process back in its default state
            // — including for a test that fails or panics before its own reset.
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
        sync::atomic::Ordering,
        task::{Context, Poll, Waker},
        time::Duration,
    };

    use super::{
        await_tor_bootstrap, bootstrap_tor, cancel_direct_connections, client_slot, disable_tor,
        dormant_mode_for, enable_tor_for_background_work, init_lock, install_bootstrapped_client,
        is_route_decided, is_tor_desired, mark_direct_route, mark_tor_desired, pending_dormant_mode,
        route_decision, set_tor_dormant, set_tor_failed, status,
        test_route_policy::lock_route_policy, tor_client_for_route, DirectRouteIo, DormantMode,
        NetworkPrivacyStatus, RouteDecision, TorClient, BACKGROUND_TOR_BOOTSTRAP_TIMEOUT,
        BACKGROUND_WAKE_UNTIL_MS, ROUTE_NOT_DECLARED_MESSAGE, STATUS_READY, TOR_BOOTSTRAP_TIMEOUT,
        TOR_BOOTSTRAP_TIMEOUT_MESSAGE, TOR_STATUS,
    };

    /// Ends whatever lease is outstanding, the way waiting out the lease would.
    fn lapse_background_wake() {
        BACKGROUND_WAKE_UNTIL_MS.store(0, Ordering::Release);
    }

    #[test]
    fn a_background_pass_masks_the_app_dormancy_intent_without_replacing_it() {
        assert_eq!(dormant_mode_for(true, false), DormantMode::Soft);
        assert_eq!(dormant_mode_for(true, true), DormantMode::Normal);
        assert_eq!(dormant_mode_for(false, false), DormantMode::Normal);
        // A pass must never put a client to sleep underneath an app that has
        // asked for it awake.
        assert_eq!(dormant_mode_for(false, true), DormantMode::Normal);
    }

    #[tokio::test]
    async fn a_lapsed_background_wake_returns_the_client_to_the_app_intent() {
        let _policy = lock_route_policy();
        let temp = tempfile::tempdir().unwrap();
        set_tor_dormant(true);

        let _ = enable_tor_for_background_work(&unusable_tor_directory(&temp)).await;
        assert_eq!(pending_dormant_mode(), DormantMode::Normal);

        lapse_background_wake();

        // The intent the app left behind is still the one in force, so nothing
        // had to be restored and no exit had to remember to restore it.
        assert_eq!(pending_dormant_mode(), DormantMode::Soft);
    }

    #[tokio::test]
    async fn a_foreground_entry_during_a_pass_wins_over_the_passes_wake() {
        let _policy = lock_route_policy();
        let temp = tempfile::tempdir().unwrap();
        set_tor_dormant(true);
        let _ = enable_tor_for_background_work(&unusable_tor_directory(&temp)).await;

        // The app comes to the foreground while the pass is still holding.
        set_tor_dormant(false);
        assert_eq!(pending_dormant_mode(), DormantMode::Normal);

        lapse_background_wake();

        assert_eq!(pending_dormant_mode(), DormantMode::Normal);
    }

    #[test]
    fn direct_route_does_not_require_a_tor_client() {
        assert_eq!(
            route_decision(true, false, NetworkPrivacyStatus::Direct, false, false),
            Ok(RouteDecision::Direct)
        );
    }

    #[test]
    fn an_undeclared_route_is_refused_instead_of_resolving_to_a_direct_connection() {
        let _policy = lock_route_policy();
        // The state a process starts in, and the one a background wake into a
        // cold process is still in until something declares.
        assert!(!is_route_decided());

        assert_eq!(
            route_decision(false, false, NetworkPrivacyStatus::Direct, false, false),
            Err(ROUTE_NOT_DECLARED_MESSAGE)
        );
        // The chokepoint every Rust lightwalletd connection funnels through:
        // an entry point that never declared must not get a transport out of it.
        assert!(
            tor_client_for_route(false).is_err(),
            "an undeclared route resolved to a direct connection"
        );
        assert!(
            tor_client_for_route(true).is_err(),
            "an undeclared route resolved to a direct connection"
        );
    }

    #[test]
    fn a_declared_direct_route_still_connects_directly() {
        let _policy = lock_route_policy();

        mark_direct_route();

        assert!(is_route_decided());
        assert!(!is_tor_desired());
        assert!(matches!(tor_client_for_route(false), Ok(None)));
        assert!(matches!(tor_client_for_route(true), Ok(None)));
    }

    #[test]
    fn marking_a_stale_direct_preference_leaves_a_process_that_chose_tor_alone() {
        let _policy = lock_route_policy();
        mark_tor_desired();

        mark_direct_route();

        assert!(is_tor_desired());
        assert_eq!(status(), NetworkPrivacyStatus::Bootstrapping);
        assert!(tor_client_for_route(false).is_err());
    }

    #[test]
    fn tor_bootstrap_and_failure_are_fail_closed() {
        assert_eq!(
            route_decision(true, true, NetworkPrivacyStatus::Bootstrapping, false, false),
            Err("Tor is still connecting")
        );
        assert_eq!(
            route_decision(true, true, NetworkPrivacyStatus::Failed, false, false),
            Err("Tor connection failed")
        );
    }

    #[test]
    fn ready_tor_selects_shared_or_isolated_routes() {
        assert_eq!(
            route_decision(true, true, NetworkPrivacyStatus::Ready, true, false),
            Ok(RouteDecision::TorShared)
        );
        assert_eq!(
            route_decision(true, true, NetworkPrivacyStatus::Ready, true, true),
            Ok(RouteDecision::TorIsolated)
        );
    }

    #[test]
    fn ready_status_without_a_client_is_still_fail_closed() {
        assert_eq!(
            route_decision(true, true, NetworkPrivacyStatus::Ready, false, false),
            Err("Tor is enabled but unavailable")
        );
    }

    #[test]
    fn marking_a_persisted_tor_route_refuses_instead_of_going_direct() {
        let _policy = lock_route_policy();
        // Undeclared going in: this is the cold background process the mark
        // exists for, so the contrast below is with a refusal, not with a
        // direct connection.
        assert_eq!(
            route_decision(is_route_decided(), is_tor_desired(), status(), false, false),
            Err(ROUTE_NOT_DECLARED_MESSAGE)
        );

        mark_tor_desired();

        assert!(is_tor_desired());
        assert_eq!(
            route_decision(is_route_decided(), is_tor_desired(), status(), false, false),
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

    #[test]
    fn a_route_that_went_direct_keeps_its_status_when_a_bootstrap_fails() {
        let _policy = lock_route_policy();
        mark_tor_desired();
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
            route_decision(is_route_decided(), is_tor_desired(), status(), false, false),
            Ok(RouteDecision::Direct)
        );
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

    /// The lease and the dormancy intent are both process-wide, and `cargo
    /// test` runs the whole crate in one process. A test that asks for
    /// dormancy and returns is the ordinary case — the guard is what hands the
    /// process back, so no test has to end with a reset line it could forget or
    /// fail before reaching.
    #[test]
    fn the_route_policy_guard_hands_back_the_default_dormancy_intent() {
        {
            let _policy = lock_route_policy();
            set_tor_dormant(true);
            assert_eq!(pending_dormant_mode(), DormantMode::Soft);
        }

        let _policy = lock_route_policy();

        assert_eq!(
            pending_dormant_mode(),
            DormantMode::Normal,
            "a test's dormancy intent outlived its route-policy guard"
        );
    }

    #[tokio::test]
    async fn a_bootstrap_waiting_on_another_bootstrap_is_bounded_by_its_own_deadline() {
        let _policy = lock_route_policy();
        let temp = tempfile::tempdir().unwrap();
        mark_tor_desired();

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
