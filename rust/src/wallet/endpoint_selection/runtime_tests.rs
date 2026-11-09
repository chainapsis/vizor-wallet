use super::tests::registry_test_lock;
use super::*;
use std::sync::{atomic::AtomicUsize, mpsc, Condvar};

/// Models an OS resolver that cannot observe cancellation once running.
#[derive(Clone, Default)]
struct ResolverGate(Arc<(Mutex<bool>, Condvar)>);

impl ResolverGate {
    fn spawn(&self, runtime: &tokio::runtime::Runtime, entered: mpsc::Sender<()>) {
        let gate = self.clone();
        runtime.spawn_blocking(move || {
            let _ = entered.send(());
            let (released, changed) = &*gate.0;
            let mut released = released.lock().unwrap();
            while !*released {
                released = changed.wait(released).unwrap();
            }
        });
    }

    fn release(&self) {
        let (released, changed) = &*self.0;
        *released.lock().unwrap() = true;
        changed.notify_all();
    }
}

// A failed assertion must never leave fake resolver threads stuck for the suite.
struct ReleaseOnDrop(ResolverGate);
impl Drop for ReleaseOnDrop {
    fn drop(&mut self) {
        self.0.release();
    }
}

pub(super) fn assert_selection_released(id: &str) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while SELECTIONS.lock().unwrap().active.contains_key(id) {
        assert!(Instant::now() < deadline, "selection {id} did not drain");
        std::thread::sleep(Duration::from_millis(1));
    }
}

#[test]
fn cancelled_result_returns_promptly_but_slot_tracks_the_blocked_resolver() {
    let _registry = registry_test_lock();
    let id = "owned-cancelled-resolver";
    begin_selection(id).unwrap();
    let lease = SelectionLease::claim(id, false).unwrap();
    let gate = ResolverGate::default();
    let _release = ReleaseOnDrop(gate.clone());
    let blocking = gate.clone();
    let (entered, started) = mpsc::channel();
    let start = Instant::now();
    let result = run_with_selection_runtime(lease, move |runtime, signal| {
        blocking.spawn(runtime, entered);
        started.recv_timeout(Duration::from_secs(5)).unwrap();
        signal.cancel();
        runtime.block_on(run_probe_batch(
            vec!["resolver-pending".into()],
            1,
            Duration::from_secs(5),
            Duration::from_secs(5),
            false,
            signal,
            || true,
            |_| std::future::pending::<Result<CandidateProbe, String>>(),
        ))
    });
    let elapsed = start.elapsed();
    let retained = SELECTIONS.lock().unwrap().active.contains_key(id);
    cancel_selection(id);
    let retained_after_cancel = SELECTIONS.lock().unwrap().active.contains_key(id);
    gate.release();
    assert_selection_released(id);
    assert!(matches!(result, Err(error) if error == CANCELLED));
    assert!(
        elapsed < Duration::from_secs(1),
        "caller waited for resolver cleanup: {elapsed:?}"
    );
    assert!(retained && retained_after_cancel);
}

#[test]
fn success_error_and_panic_keep_capacity_until_blocking_cleanup_finishes() {
    let _registry = registry_test_lock();
    for outcome in 0..3 {
        let id = format!("owned-result-{outcome}");
        begin_selection(&id).unwrap();
        let lease = SelectionLease::claim(&id, false).unwrap();
        let gate = ResolverGate::default();
        let _release = ReleaseOnDrop(gate.clone());
        let blocking = gate.clone();
        let (entered, started) = mpsc::channel();
        let result = run_with_selection_runtime(lease, move |runtime, _| {
            blocking.spawn(runtime, entered);
            started.recv_timeout(Duration::from_secs(5)).unwrap();
            match outcome {
                0 => Ok(42),
                1 => Err("probe fixture failed".to_owned()),
                _ => panic!("worker panic fixture"),
            }
        });
        let retained = SELECTIONS.lock().unwrap().active.contains_key(&id);
        gate.release();
        assert_selection_released(&id);
        assert!(retained);
        match outcome {
            0 => assert_eq!(result.unwrap(), 42),
            1 => assert_eq!(result.unwrap_err(), "probe fixture failed"),
            _ => assert_eq!(result.unwrap_err(), LOCAL_WORKER_FAILED),
        }
    }
}

#[test]
fn draining_selections_apply_backpressure_and_recover_after_resolvers_return() {
    let _registry = registry_test_lock();
    let gate = ResolverGate::default();
    let _release = ReleaseOnDrop(gate.clone());
    let ids: Vec<_> = (0..MAX_ACTIVE_SELECTIONS)
        .map(|i| format!("owned-capacity-{i}"))
        .collect();
    for id in &ids {
        begin_selection(id).unwrap();
        let lease = SelectionLease::claim(id, false).unwrap();
        let blocking = gate.clone();
        let (entered, started) = mpsc::channel();
        let result = run_with_selection_runtime::<()>(lease, move |runtime, signal| {
            blocking.spawn(runtime, entered);
            started.recv_timeout(Duration::from_secs(5)).unwrap();
            signal.cancel();
            Err(CANCELLED.to_owned())
        });
        assert_eq!(result.unwrap_err(), CANCELLED);
    }
    let retained = ids
        .iter()
        .all(|id| SELECTIONS.lock().unwrap().active.contains_key(id));
    let overflow = begin_selection("owned-capacity-overflow");
    for id in &ids {
        cancel_selection(id);
    }
    let still_full = begin_selection("owned-capacity-after-cancel");
    gate.release();
    for id in &ids {
        assert_selection_released(id);
    }
    assert!(retained);
    assert!(overflow.unwrap_err().contains("too many active selections"));
    assert!(still_full
        .unwrap_err()
        .contains("too many active selections"));
    let recovered = "owned-capacity-recovered";
    begin_selection(recovered).unwrap();
    assert_eq!(
        run_with_selection_runtime(SelectionLease::claim(recovered, false).unwrap(), |_, _| Ok(
            7
        ))
        .unwrap(),
        7
    );
    assert_selection_released(recovered);
}

#[test]
fn one_selection_has_a_fixed_blocking_thread_limit() {
    let _registry = registry_test_lock();
    let id = "owned-blocking-thread-cap";
    begin_selection(id).unwrap();
    let lease = SelectionLease::claim(id, false).unwrap();
    let gate = ResolverGate::default();
    let _release = ReleaseOnDrop(gate.clone());
    let blocking = gate.clone();
    let active = Arc::new(AtomicUsize::new(0));
    let peak = Arc::new(AtomicUsize::new(0));
    let work_active = active.clone();
    let work_peak = peak.clone();
    let (entered, started) = mpsc::channel();
    run_with_selection_runtime(lease, move |runtime, _| {
        assert_eq!(
            runtime.handle().runtime_flavor(),
            tokio::runtime::RuntimeFlavor::CurrentThread
        );
        for _ in 0..MAX_SELECTION_BLOCKING_THREADS + 3 {
            let gate = blocking.clone();
            let entered = entered.clone();
            let active = work_active.clone();
            let peak = work_peak.clone();
            runtime.spawn_blocking(move || {
                let count = active.fetch_add(1, Ordering::SeqCst) + 1;
                peak.fetch_max(count, Ordering::SeqCst);
                let _ = entered.send(());
                let (released, changed) = &*gate.0;
                let mut released = released.lock().unwrap();
                while !*released {
                    released = changed.wait(released).unwrap();
                }
                active.fetch_sub(1, Ordering::SeqCst);
            });
        }
        for _ in 0..MAX_SELECTION_BLOCKING_THREADS {
            started.recv_timeout(Duration::from_secs(5)).unwrap();
        }
        assert!(started.recv_timeout(Duration::from_millis(25)).is_err());
        Ok(())
    })
    .unwrap();
    let held_peak = peak.load(Ordering::SeqCst);
    gate.release();
    assert_selection_released(id);
    assert_eq!(active.load(Ordering::SeqCst), 0);
    assert_eq!(held_peak, MAX_SELECTION_BLOCKING_THREADS);
    assert!(peak.load(Ordering::SeqCst) <= MAX_SELECTION_BLOCKING_THREADS);
}

#[test]
fn cancellation_before_worker_dispatch_never_runs_the_work() {
    let _registry = registry_test_lock();
    let id = "owned-before-worker-start";
    begin_selection(id).unwrap();
    let lease = SelectionLease::claim(id, false).unwrap();
    lease.signal.cancel();
    let invoked = Arc::new(AtomicBool::new(false));
    let work_invoked = invoked.clone();
    let result = run_with_selection_runtime(lease, move |_, _| {
        work_invoked.store(true, Ordering::SeqCst);
        Ok(())
    });
    assert_selection_released(id);
    assert_eq!(result.unwrap_err(), CANCELLED);
    assert!(!invoked.load(Ordering::SeqCst));
}
