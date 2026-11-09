use super::*;
use std::{
    sync::mpsc::{self, Receiver, Sender, TryRecvError},
    time::{Duration, Instant},
};

const WAIT: Duration = Duration::from_secs(5);

fn key(path: &str, account: u128) -> Key {
    Key {
        path: path.into(),
        network: WalletNetwork::Regtest,
        account: AccountUuid::from_uuid(uuid::Uuid::from_u128(account)),
    }
}

fn wallet() -> (tempfile::TempDir, String) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    rusqlite::Connection::open(&path)
        .unwrap()
        .execute_batch("CREATE TABLE lifecycle (value INTEGER); INSERT INTO lifecycle VALUES (1)")
        .unwrap();
    (dir, path)
}

fn entry(path: &str) -> Entry {
    Entry {
        conn: open_readonly_conn(path).unwrap(),
        file: same_file::Handle::from_path(path).unwrap(),
        snapshot: None,
    }
}

// Exercise the same lease/entry-lock scope as with_snapshot, while keeping a
// real SQLite read open until the test permits it to finish.
fn busy_read(
    cache: &HistoryCache,
    path: &str,
    started: Sender<Slot>,
    finish: Receiver<()>,
    panic_at_end: bool,
) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let lease = cache.slot(key(path, 1)).unwrap();
        let mut guard = lease.slot.entry.lock().unwrap();
        *guard = Some(entry(path));
        let tx = guard
            .as_ref()
            .unwrap()
            .conn
            .unchecked_transaction()
            .unwrap();
        assert_eq!(
            tx.query_row("SELECT value FROM lifecycle", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
        started.send(lease.slot.clone()).unwrap();
        finish.recv_timeout(WAIT).unwrap();
        assert!(!panic_at_end, "simulated query unwind");
    }));
    assert_eq!(result.is_err(), panic_at_end);
}

fn overflow_lru(cache: &HistoryCache, path: &str) {
    for account in 2..=5 {
        drop(cache.slot(key(path, account)).unwrap());
    }
    assert_eq!(cache.lock().active.len(), MAX_ACCOUNTS);
}

fn wait_for_drains(cache: &HistoryCache, path: &str, count: usize) {
    let deadline = Instant::now() + WAIT;
    while cache.lock().draining.get(path).copied().unwrap_or_default() != count {
        assert!(Instant::now() < deadline, "drain did not start");
        std::thread::yield_now();
    }
}

fn assert_busy_retirement_drains(clear: bool) {
    let (_dir, path) = wallet();
    let cache = HistoryCache::default();
    let (started_tx, started_rx) = mpsc::channel();
    let (finish_tx, finish_rx) = mpsc::channel();
    let (drained_tx, drained_rx) = mpsc::channel();
    std::thread::scope(|scope| {
        scope.spawn(|| busy_read(&cache, &path, started_tx, finish_rx, false));
        let slot = started_rx.recv_timeout(WAIT).unwrap();
        if clear {
            cache.clear();
        } else {
            overflow_lru(&cache, &path);
        }
        assert!(slot.retired.load(Ordering::Acquire));
        assert!(cache
            .lock()
            .retired
            .iter()
            .any(|(_, candidate)| Arc::ptr_eq(candidate, &slot)));

        scope.spawn(|| {
            cache.evict_db(&path);
            drained_tx.send(()).unwrap();
        });
        wait_for_drains(&cache, &path, 1);
        assert_eq!(drained_rx.try_recv(), Err(TryRecvError::Empty));
        // The DB being drained refuses new leases. Other DBs still work,
        // demonstrating that a blocked read does not hold the global lock.
        assert!(cache.slot(key(&path, 6)).is_err());
        drop(cache.slot(key("another-wallet.db", 1)).unwrap());
        finish_tx.send(()).unwrap();
        drained_rx.recv_timeout(WAIT).unwrap();
        assert!(slot.entry.lock().unwrap().is_none());
        assert!(cache.lock().retired.is_empty());
        std::fs::remove_file(&path).unwrap();
    });
}

#[test]
fn db_eviction_waits_for_lru_retired_reads() {
    assert_busy_retirement_drains(false);
}

#[test]
fn db_eviction_waits_for_clear_retired_reads() {
    assert_busy_retirement_drains(true);
}

#[test]
fn retired_read_closes_itself_without_a_reset() {
    for panic_at_end in [false, true] {
        let (_dir, path) = wallet();
        let cache = HistoryCache::default();
        let (started_tx, started_rx) = mpsc::channel();
        let (finish_tx, finish_rx) = mpsc::channel();
        std::thread::scope(|scope| {
            let reader =
                scope.spawn(|| busy_read(&cache, &path, started_tx, finish_rx, panic_at_end));
            let slot = started_rx.recv_timeout(WAIT).unwrap();
            cache.clear();
            finish_tx.send(()).unwrap();
            reader.join().unwrap();
            assert!(slot
                .entry
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .is_none());
            assert!(cache.lock().retired.is_empty());
            std::fs::remove_file(&path).unwrap();
        });
    }
}

#[test]
fn idle_handles_close_on_clear_and_lru_eviction() {
    for clear in [false, true] {
        let (_dir, path) = wallet();
        let cache = HistoryCache::default();
        let lease = cache.slot(key(&path, 1)).unwrap();
        let slot = lease.slot.clone();
        *slot.entry.lock().unwrap() = Some(entry(&path));
        drop(lease);
        assert!(slot.entry.lock().unwrap().is_some());
        if clear {
            cache.clear();
        } else {
            overflow_lru(&cache, &path);
        }
        assert!(slot.entry.lock().unwrap().is_none());
        assert!(cache.lock().retired.is_empty());
        // The old slot remains retired even if another caller still owns it.
        assert!(slot.retired.load(Ordering::Acquire));
        let next = cache.slot(key(&path, 1)).unwrap();
        assert!(!Arc::ptr_eq(&slot, &next.slot));
        drop(next);
        cache.evict_db(&path);
        std::fs::remove_file(&path).unwrap();
    }
}

#[test]
fn concurrent_db_drains_both_wait_for_the_retired_read() {
    let (_dir, path) = wallet();
    let cache = HistoryCache::default();
    let (started_tx, started_rx) = mpsc::channel();
    let (finish_tx, finish_rx) = mpsc::channel();
    let (drained_tx, drained_rx) = mpsc::channel();
    std::thread::scope(|scope| {
        scope.spawn(|| busy_read(&cache, &path, started_tx, finish_rx, false));
        let slot = started_rx.recv_timeout(WAIT).unwrap();
        for _ in 0..2 {
            let done = drained_tx.clone();
            let cache = &cache;
            let path = &path;
            scope.spawn(move || {
                cache.evict_db(path);
                done.send(()).unwrap();
            });
        }
        wait_for_drains(&cache, &path, 2);
        assert_eq!(drained_rx.try_recv(), Err(TryRecvError::Empty));
        finish_tx.send(()).unwrap();
        drained_rx.recv_timeout(WAIT).unwrap();
        drained_rx.recv_timeout(WAIT).unwrap();
        assert!(slot.entry.lock().unwrap().is_none());
        assert!(cache.lock().draining.is_empty());
        std::fs::remove_file(&path).unwrap();
    });
}

#[test]
fn eviction_retires_a_lease_before_it_opens_a_connection() {
    let (_dir, path) = wallet();
    let cache = HistoryCache::default();
    let lease = cache.slot(key(&path, 1)).unwrap();
    cache.evict_db(&path);
    let guard = lease.slot.entry.lock().unwrap();
    assert!(lease.slot.retired.load(Ordering::Acquire));
    assert!(guard.is_none());
    drop(guard);
    drop(lease);
    assert!(cache.lock().draining.is_empty());
    std::fs::remove_file(&path).unwrap();
}
