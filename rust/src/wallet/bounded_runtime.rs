//! Runtimes for the long-running wallet tasks that Dart starts, whose
//! shutdown never waits for blocking work without bound.
//!
//! Dropping a tokio runtime waits for every task on its blocking pool, however
//! long. One sync step that ignored its cancellation, a stalled read or a
//! library call that takes no cancellation, would keep the sync's runtime, and
//! so `SYNC_RUNNING` and the progress stream, alive until the app restarted:
//! every queued start would wait forever, and account deletion, reset and the
//! privacy toggles would time out. A [`BoundedRuntime`] gives that work
//! [`CANCEL_GRACE`] and then abandons it on its thread.
//!
//! Abandoned work must therefore not write the wallet. Work that takes no
//! cancellation of its own (the transparent PIR pass, private account
//! discovery and txid display lookups) runs through [`run_detached`], on a
//! thread of its own rather than a runtime's blocking pool.

use std::future::Future;
use std::panic;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::wallet::sync_engine::watch_for_exit;

/// How long cancelled blocking work may take to return before it is
/// abandoned: a [`run_detached`] call once it is cancelled, and a
/// [`BoundedRuntime`]'s blocking tasks at shutdown.
pub(crate) const CANCEL_GRACE: Duration = Duration::from_secs(2);

/// A multi-thread runtime whose shutdown waits at most
/// [`CANCEL_GRACE`] for its blocking tasks, including when a panic
/// unwinds through it.
pub(crate) struct BoundedRuntime(Option<tokio::runtime::Runtime>);

impl BoundedRuntime {
    pub(crate) fn new() -> Result<Self, String> {
        tokio::runtime::Runtime::new()
            .map(|runtime| Self(Some(runtime)))
            .map_err(|e| format!("tokio: {e}"))
    }

    pub(crate) fn block_on<F: Future>(&self, future: F) -> F::Output {
        self.0
            .as_ref()
            .expect("the runtime lives until it is dropped")
            .block_on(future)
    }
}

impl Drop for BoundedRuntime {
    fn drop(&mut self) {
        if let Some(runtime) = self.0.take() {
            let started = Instant::now();
            runtime.shutdown_timeout(CANCEL_GRACE);
            if started.elapsed() >= CANCEL_GRACE {
                log::warn!("runtime: abandoned blocking work still running at shutdown");
            }
        }
    }
}

/// Clears a running flag when dropped, panics included.
struct Running<'a>(&'a AtomicBool);

impl Drop for Running<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

/// Runs `work` on a new [`BoundedRuntime`] while `running` is set, failing
/// with `busy` when it already is. `running` is cleared once the runtime has
/// shut down, whether `work` returns, fails or panics; a panic becomes an
/// error.
pub(crate) fn run_exclusive<T>(
    running: &AtomicBool,
    busy: &str,
    work: impl FnOnce(&BoundedRuntime) -> Result<T, String>,
) -> Result<T, String> {
    if running
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err(busy.to_owned());
    }
    let _running = Running(running);
    catch(panic::AssertUnwindSafe(|| {
        let runtime = BoundedRuntime::new()?;
        work(&runtime)
    }))
}

/// Runs `f`, turning a panic into an error.
pub(crate) fn catch<T>(
    f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe,
) -> Result<T, String> {
    panic::catch_unwind(f).unwrap_or_else(|e| {
        let msg = if let Some(s) = e.downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = e.downcast_ref::<String>() {
            s.clone()
        } else {
            "Unknown panic".to_string()
        };
        Err(format!("Rust panic: {msg}"))
    })
}

/// What became of a call [`run_detached`] ran.
#[derive(Debug)]
pub(crate) enum Detached<T> {
    /// The call returned this.
    Returned(T),
    /// Its thread could not be started, so the call never ran.
    NotStarted,
    /// The call panicked, or its runtime could not be built.
    Panicked,
    /// The call was cancelled and did not return within [`CANCEL_GRACE`]. It
    /// was abandoned, still running, and nothing it returns is read.
    Abandoned,
}

/// Runs `call` on a thread of its own, with a one-worker runtime of its own
/// for its I/O, until it returns or `should_exit` holds.
///
/// The call never runs on the caller's runtime or its blocking pool: a
/// runtime's shutdown waits for every blocking-pool task, so a call that
/// ignored its cancellation would hold the runtime that owns it (the sync's,
/// and every start queued behind it) until the app restarted. `call` gets its
/// own runtime's handle for its I/O, DNS lookups on that runtime's blocking
/// pool included.
///
/// `cancel` is the call's cancellation, which it polls between requests. It
/// is set once `should_exit` holds, and when the returned future is dropped
/// before the call returns, so a dropped caller stops the call at its next
/// request. Once cancelled, the call gets [`CANCEL_GRACE`] to return; one that
/// does not is [`Detached::Abandoned`], and whatever it owns (a companion's
/// lock, a read-only wallet handle) is released on its thread when it
/// returns. A call that returns leaves `cancel` as it was, so the caller can
/// tell whether cancellation raced the answer.
pub(crate) async fn run_detached<T: Send + 'static>(
    name: &str,
    cancel: Arc<AtomicBool>,
    should_exit: &(dyn Fn() -> bool + Sync),
    call: impl FnOnce(tokio::runtime::Handle) -> T + Send + 'static,
) -> Detached<T> {
    let mut on_drop = CancelOnDrop(Some(cancel.clone()));
    let (done, mut answer) = tokio::sync::oneshot::channel();
    let io_name = format!("{name}-io");
    let spawned = std::thread::Builder::new()
        .name(name.to_owned())
        .spawn(move || {
            let Ok(io) = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(1)
                .thread_name(io_name)
                .enable_all()
                .build()
            else {
                return;
            };
            // A send to an abandoning caller drops the answer here.
            let _ = done.send(call(io.handle().clone()));
            io.shutdown_background();
        });
    if spawned.is_err() {
        return Detached::NotStarted;
    }
    let joined = tokio::select! {
        biased;
        _ = watch_for_exit(&should_exit) => {
            cancel.store(true, Ordering::SeqCst);
            match tokio::time::timeout(CANCEL_GRACE, &mut answer).await {
                Ok(joined) => joined,
                Err(_) => return Detached::Abandoned,
            }
        }
        joined = &mut answer => joined,
    };
    on_drop.0 = None;
    match joined {
        Ok(value) => Detached::Returned(value),
        Err(_) => Detached::Panicked,
    }
}

/// Sets a call's cancellation when dropped, unless disarmed.
struct CancelOnDrop(Option<Arc<AtomicBool>>);

impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        if let Some(cancel) = &self.0 {
            cancel.store(true, Ordering::SeqCst);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::mpsc;

    use super::*;

    /// A blocking task that ignores every cancellation, as a stalled pass
    /// would, held until the returned sender is dropped or a minute passes.
    fn stuck(runtime: &BoundedRuntime) -> mpsc::Sender<()> {
        let (release, released) = mpsc::channel::<()>();
        runtime.block_on(async {
            drop(tokio::task::spawn_blocking(move || {
                let _ = released.recv_timeout(Duration::from_secs(60));
            }));
        });
        release
    }

    #[test]
    fn stuck_blocking_work_does_not_hold_the_task_open() {
        let running = AtomicBool::new(false);
        let (progress, events) = mpsc::channel();
        let mut release = None;
        let started = Instant::now();
        let result = run_exclusive(&running, "busy", |runtime| {
            assert!(running.load(Ordering::SeqCst));
            release = Some(stuck(runtime));
            progress.send("done").unwrap();
            // The stream's sender goes with the call, as the progress sink
            // does when the sync returns.
            drop(progress);
            Ok(7)
        });

        assert_eq!(result, Ok(7));
        let took = started.elapsed();
        assert!(
            took < CANCEL_GRACE + Duration::from_secs(3),
            "returned after {took:?}"
        );
        assert!(!running.load(Ordering::SeqCst));
        assert_eq!(events.recv(), Ok("done"));
        assert!(events.recv().is_err(), "the stream closed");
        // A queued start runs at once.
        assert_eq!(run_exclusive(&running, "busy", |_| Ok(8)), Ok(8));
        drop(release);
    }

    #[test]
    fn a_runtime_dropped_by_a_panic_does_not_wait_for_stuck_work() {
        let running = AtomicBool::new(false);
        let mut release = None;
        let started = Instant::now();
        let result: Result<(), String> = run_exclusive(&running, "busy", |runtime| {
            release = Some(stuck(runtime));
            panic!("sync step panicked");
        });

        assert_eq!(result, Err("Rust panic: sync step panicked".to_owned()));
        assert!(started.elapsed() < CANCEL_GRACE + Duration::from_secs(3));
        assert!(!running.load(Ordering::SeqCst));
        drop(release);
    }

    #[test]
    fn a_second_start_is_refused_while_one_runs() {
        let running = AtomicBool::new(false);
        let result = run_exclusive(&running, "outer busy", |_| {
            Ok(run_exclusive(&running, "Sync already running", |_| Ok(())))
        });
        assert_eq!(result, Ok(Err("Sync already running".to_owned())));
        assert!(!running.load(Ordering::SeqCst));
    }

    #[test]
    fn errors_clear_the_running_flag() {
        let running = AtomicBool::new(false);
        let result: Result<(), String> = run_exclusive(&running, "busy", |_| Err("failed".into()));
        assert_eq!(result, Err("failed".to_owned()));
        assert!(!running.load(Ordering::SeqCst));
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn a_detached_call_answers_on_its_own_runtime_and_keeps_cancel_unset() {
        let cancel = Arc::new(AtomicBool::new(false));
        let caller = tokio::runtime::Handle::current().id();
        let answer = run_detached("detached-test", cancel.clone(), &|| false, move |io| {
            assert_ne!(io.id(), caller, "the call has a runtime of its own");
            std::thread::current().name().map(str::to_owned)
        })
        .await;
        assert!(matches!(
            answer,
            Detached::Returned(Some(ref name)) if name == "detached-test"
        ));
        assert!(!cancel.load(Ordering::SeqCst));
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn exit_cancels_a_call_that_returns_within_the_grace() {
        let cancel = Arc::new(AtomicBool::new(false));
        let exit = AtomicBool::new(true);
        let polled = cancel.clone();
        let answer = run_detached(
            "detached-test",
            cancel.clone(),
            &|| exit.load(Ordering::SeqCst),
            move |_| {
                while !polled.load(Ordering::SeqCst) {
                    std::thread::sleep(Duration::from_millis(5));
                }
                7
            },
        )
        .await;
        assert!(matches!(answer, Detached::Returned(7)));
        assert!(cancel.load(Ordering::SeqCst), "the caller sees the race");
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn a_call_deaf_to_cancellation_is_abandoned_after_the_grace() {
        let cancel = Arc::new(AtomicBool::new(false));
        let (release, released) = mpsc::channel::<()>();
        let started = Instant::now();
        let answer = run_detached("detached-test", cancel.clone(), &|| true, move |_| {
            let _ = released.recv_timeout(Duration::from_secs(60));
        })
        .await;
        assert!(matches!(answer, Detached::Abandoned));
        assert!(started.elapsed() < CANCEL_GRACE + Duration::from_secs(2));
        assert!(cancel.load(Ordering::SeqCst));
        drop(release);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn a_dropped_caller_cancels_the_call() {
        let cancel = Arc::new(AtomicBool::new(false));
        let (entered, entering) = mpsc::channel::<()>();
        let polled = cancel.clone();
        let stay = || false;
        let call = run_detached("detached-test", cancel.clone(), &stay, move |_| {
            let _ = entered.send(());
            while !polled.load(Ordering::SeqCst) {
                std::thread::sleep(Duration::from_millis(5));
            }
        });
        tokio::select! {
            _ = call => panic!("the call returned before it was cancelled"),
            _ = async {
                while entering.try_recv().is_err() {
                    tokio::time::sleep(Duration::from_millis(5)).await;
                }
            } => {}
        }
        assert!(cancel.load(Ordering::SeqCst));
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn a_panicking_call_is_reported() {
        let cancel = Arc::new(AtomicBool::new(false));
        let answer: Detached<()> = run_detached("detached-test", cancel, &|| false, |_| {
            panic!("the call panicked")
        })
        .await;
        assert!(matches!(answer, Detached::Panicked));
    }
}
