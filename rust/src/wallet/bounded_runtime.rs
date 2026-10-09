//! Runtimes for the long-running wallet tasks that Dart starts, whose
//! shutdown never waits for blocking work without bound.
//!
//! Dropping a tokio runtime waits for every task on its blocking pool, however
//! long. One sync step that ignored its cancellation, a stalled read or a
//! library call that takes no cancellation, would keep the sync's runtime, and
//! so `SYNC_RUNNING` and the progress stream, alive until the app restarted:
//! every queued start would wait forever, and account deletion, reset and the
//! privacy toggles would time out. A [`BoundedRuntime`] gives that work
//! [`RUNTIME_SHUTDOWN_GRACE`] and then abandons it on its thread.
//!
//! Abandoned work must therefore not write the wallet. The sync's only such
//! work is the transparent PIR pass, which reads the wallet through a
//! read-only handle and runs on a thread of its own anyway.

use std::future::Future;
use std::panic;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

/// How long a finished task waits for blocking work it spawned before
/// abandoning it.
pub(crate) const RUNTIME_SHUTDOWN_GRACE: Duration = Duration::from_secs(2);

/// A multi-thread runtime whose shutdown waits at most
/// [`RUNTIME_SHUTDOWN_GRACE`] for its blocking tasks, including when a panic
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
            runtime.shutdown_timeout(RUNTIME_SHUTDOWN_GRACE);
            if started.elapsed() >= RUNTIME_SHUTDOWN_GRACE {
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
            took < RUNTIME_SHUTDOWN_GRACE + Duration::from_secs(3),
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
        assert!(started.elapsed() < RUNTIME_SHUTDOWN_GRACE + Duration::from_secs(3));
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
}
