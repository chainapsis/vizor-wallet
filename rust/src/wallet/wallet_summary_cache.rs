//! Process-wide coalescing cache for `WalletDb::get_wallet_summary`.
//!
//! Concurrent callers for the same `(db_path, network)` share one load by
//! holding a per-key mutex through the SQLite computation. Successful
//! results (including `None`) are retained until a wallet-DB write advances
//! the seqlock epoch in [`crate::wallet::db::with_wallet_db_write_lock`].
//! Errors are never cached.

use std::{
    collections::HashMap,
    path::Path,
    sync::{Arc, Mutex, OnceLock},
};

use zcash_client_backend::data_api::{wallet::ConfirmationsPolicy, WalletRead, WalletSummary};
use zcash_client_sqlite::AccountUuid;

use crate::wallet::{
    db::{open_wallet_db_for_read_with_timeout, wallet_db_write_epoch, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

type CachedSummary = Option<WalletSummary<AccountUuid>>;

#[derive(Clone, Eq, Hash, PartialEq)]
struct CacheKey {
    db_path: String,
    network: WalletNetwork,
}

struct CacheEntry {
    /// Epoch observed when this value was published. Must still match the
    /// live write epoch (and be even) for a hit.
    epoch: u64,
    summary: CachedSummary,
}

struct EntrySlot {
    cached: Option<CacheEntry>,
}

fn entry_map() -> &'static Mutex<HashMap<CacheKey, Arc<Mutex<EntrySlot>>>> {
    static MAP: OnceLock<Mutex<HashMap<CacheKey, Arc<Mutex<EntrySlot>>>>> = OnceLock::new();
    MAP.get_or_init(|| Mutex::new(HashMap::new()))
}

fn slot_for(key: CacheKey) -> Arc<Mutex<EntrySlot>> {
    let mut map = match entry_map().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    map.entry(key)
        .or_insert_with(|| Arc::new(Mutex::new(EntrySlot { cached: None })))
        .clone()
}

/// Drops every cached summary for a wallet DB, regardless of network.
///
/// Wallet reset replaces the randomized DB path, so retaining the old key
/// would otherwise keep its last account balances alive until process exit.
/// Account deletion also uses path-wide eviction so the next read rebuilds a
/// summary containing only the remaining accounts.
pub(crate) fn evict_db(db_path: &str) {
    let mut map = match entry_map().lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    map.retain(|key, _| key.db_path != db_path);
}

/// Cached `get_wallet_summary` for the default confirmation policy.
pub(crate) fn get_wallet_summary_cached(
    db_path: &str,
    network: WalletNetwork,
) -> Result<CachedSummary, String> {
    get_or_load_with(db_path, network, || {
        let db = open_wallet_db_for_read_with_timeout(db_path, network, READ_DB_BUSY_TIMEOUT)?;
        db.get_wallet_summary(ConfirmationsPolicy::default())
            .map_err(|e| format!("{e}"))
    })
}

/// Testable load path: production passes the real SQLite loader; unit tests
/// inject barriers, counters, and local epochs.
pub(crate) fn get_or_load_with<F>(
    db_path: &str,
    network: WalletNetwork,
    loader: F,
) -> Result<CachedSummary, String>
where
    F: FnOnce() -> Result<CachedSummary, String>,
{
    get_or_load_with_epoch(db_path, network, wallet_db_write_epoch, loader)
}

fn get_or_load_with_epoch<E, F>(
    db_path: &str,
    network: WalletNetwork,
    epoch_fn: E,
    loader: F,
) -> Result<CachedSummary, String>
where
    E: Fn() -> u64,
    F: FnOnce() -> Result<CachedSummary, String>,
{
    let key = CacheKey {
        db_path: db_path.to_string(),
        network,
    };
    let slot = slot_for(key);
    let mut entry = match slot.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if let Some(cached) = entry.cached.as_ref() {
        let current = epoch_fn();
        if current == cached.epoch && current % 2 == 0 && Path::new(db_path).exists() {
            return Ok(cached.summary.clone());
        }
        // Stale epoch, write in progress, or DB file replaced/deleted.
        entry.cached = None;
    }

    let epoch_before = epoch_fn();
    let loaded = match loader() {
        Ok(value) => value,
        Err(error) => {
            // Never cache errors — the next caller must retry.
            entry.cached = None;
            return Err(error);
        }
    };

    let epoch_after = epoch_fn();
    if epoch_before == epoch_after && epoch_before % 2 == 0 {
        entry.cached = Some(CacheEntry {
            epoch: epoch_before,
            summary: loaded.clone(),
        });
    } else {
        entry.cached = None;
    }

    Ok(loaded)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        collections::HashMap,
        sync::{
            atomic::{AtomicU64, AtomicUsize, Ordering},
            Barrier,
        },
        thread,
        time::Duration,
    };

    use zcash_client_backend::data_api::{Progress, Ratio, WalletSummary};
    use zcash_protocol::consensus::BlockHeight;

    use crate::wallet::db::with_wallet_db_write_lock;

    fn unique_path(label: &str) -> String {
        static COUNTER: AtomicUsize = AtomicUsize::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        format!(
            "/tmp/vizor-summary-cache-test-{}-{}-{label}",
            std::process::id(),
            n,
        )
    }

    fn touch_file(path: &str) {
        std::fs::write(path, b"placeholder").unwrap();
    }

    fn remove_file(path: &str) {
        let _ = std::fs::remove_file(path);
    }

    fn summary_with_tip(tip: u32) -> WalletSummary<AccountUuid> {
        WalletSummary::new(
            HashMap::new(),
            BlockHeight::from_u32(tip),
            BlockHeight::from_u32(tip),
            Progress::new(Ratio::new(0, 0), None),
            0,
            0,
            0,
        )
    }

    fn load_with_local_epoch<F>(
        db_path: &str,
        network: WalletNetwork,
        epoch: &AtomicU64,
        loader: F,
    ) -> Result<CachedSummary, String>
    where
        F: FnOnce() -> Result<CachedSummary, String>,
    {
        get_or_load_with_epoch(db_path, network, || epoch.load(Ordering::Acquire), loader)
    }

    #[test]
    fn concurrent_same_path_callers_share_one_load() {
        let path = unique_path("concurrent");
        touch_file(&path);
        let epoch = Arc::new(AtomicU64::new(0));
        let loads = Arc::new(AtomicUsize::new(0));
        let start = Arc::new(Barrier::new(4));
        let entered_load = Arc::new(Barrier::new(2));
        let finish_load = Arc::new(Barrier::new(2));

        let mut handles = Vec::new();
        for _ in 0..4 {
            let path = path.clone();
            let epoch = Arc::clone(&epoch);
            let loads = Arc::clone(&loads);
            let start = Arc::clone(&start);
            let entered_load = Arc::clone(&entered_load);
            let finish_load = Arc::clone(&finish_load);
            handles.push(thread::spawn(move || {
                start.wait();
                load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
                    // Only the first acquirer of the entry mutex runs this.
                    loads.fetch_add(1, Ordering::SeqCst);
                    entered_load.wait();
                    finish_load.wait();
                    Ok(Some(summary_with_tip(100)))
                })
            }));
        }

        entered_load.wait();
        thread::sleep(Duration::from_millis(50));
        finish_load.wait();

        let mut results = Vec::new();
        for handle in handles {
            results.push(handle.join().unwrap().unwrap());
        }

        assert_eq!(loads.load(Ordering::SeqCst), 1);
        for result in &results {
            assert_eq!(u32::from(result.as_ref().unwrap().chain_tip_height()), 100);
        }

        remove_file(&path);
    }

    #[test]
    fn sequential_same_path_calls_hit_cache() {
        let path = unique_path("sequential");
        touch_file(&path);
        let epoch = AtomicU64::new(0);
        let loads = AtomicUsize::new(0);

        let first = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(42)))
        })
        .unwrap();
        let second = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(99)))
        })
        .unwrap();

        assert_eq!(loads.load(Ordering::SeqCst), 1);
        assert_eq!(
            first.as_ref().unwrap().chain_tip_height(),
            second.as_ref().unwrap().chain_tip_height()
        );
        assert_eq!(u32::from(first.as_ref().unwrap().chain_tip_height()), 42);

        remove_file(&path);
    }

    #[test]
    fn different_paths_and_networks_do_not_coalesce() {
        let path_a = unique_path("path-a");
        let path_b = unique_path("path-b");
        touch_file(&path_a);
        touch_file(&path_b);
        let epoch = AtomicU64::new(0);
        let loads = AtomicUsize::new(0);

        let a = load_with_local_epoch(&path_a, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(1)))
        })
        .unwrap();
        let b = load_with_local_epoch(&path_b, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(2)))
        })
        .unwrap();
        let c = load_with_local_epoch(&path_a, WalletNetwork::Test, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(3)))
        })
        .unwrap();

        assert_eq!(loads.load(Ordering::SeqCst), 3);
        assert_eq!(u32::from(a.as_ref().unwrap().chain_tip_height()), 1);
        assert_eq!(u32::from(b.as_ref().unwrap().chain_tip_height()), 2);
        assert_eq!(u32::from(c.as_ref().unwrap().chain_tip_height()), 3);

        remove_file(&path_a);
        remove_file(&path_b);
    }

    #[test]
    fn summary_none_is_cacheable() {
        let path = unique_path("none");
        touch_file(&path);
        let epoch = AtomicU64::new(0);
        let loads = AtomicUsize::new(0);

        let first = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(None)
        })
        .unwrap();
        let second = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(1)))
        })
        .unwrap();

        assert_eq!(loads.load(Ordering::SeqCst), 1);
        assert!(first.is_none());
        assert!(second.is_none());

        remove_file(&path);
    }

    #[test]
    fn loader_error_is_not_cached() {
        let path = unique_path("error");
        touch_file(&path);
        let epoch = AtomicU64::new(0);
        let loads = AtomicUsize::new(0);

        let err = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Err("boom".to_string())
        });
        assert_eq!(err.unwrap_err(), "boom");

        let ok = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(7)))
        })
        .unwrap();

        assert_eq!(loads.load(Ordering::SeqCst), 2);
        assert_eq!(u32::from(ok.as_ref().unwrap().chain_tip_height()), 7);

        remove_file(&path);
    }

    #[test]
    fn missing_file_evicts_cached_entry() {
        let path = unique_path("missing");
        touch_file(&path);
        let epoch = AtomicU64::new(0);
        let loads = AtomicUsize::new(0);

        load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(5)))
        })
        .unwrap();
        assert_eq!(loads.load(Ordering::SeqCst), 1);

        remove_file(&path);

        let result = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Err("file gone".to_string())
        });
        assert_eq!(result.unwrap_err(), "file gone");
        assert_eq!(loads.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn explicit_db_eviction_removes_all_networks_and_preserves_other_paths() {
        let evicted_path = unique_path("explicit-evict");
        let retained_path = unique_path("explicit-retain");
        touch_file(&evicted_path);
        touch_file(&retained_path);
        let epoch = AtomicU64::new(0);
        let evicted_loads = AtomicUsize::new(0);
        let retained_loads = AtomicUsize::new(0);

        for network in [WalletNetwork::Main, WalletNetwork::Test] {
            load_with_local_epoch(&evicted_path, network, &epoch, || {
                evicted_loads.fetch_add(1, Ordering::SeqCst);
                Ok(Some(summary_with_tip(10)))
            })
            .unwrap();
        }
        load_with_local_epoch(&retained_path, WalletNetwork::Main, &epoch, || {
            retained_loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(20)))
        })
        .unwrap();

        evict_db(&evicted_path);

        for network in [WalletNetwork::Main, WalletNetwork::Test] {
            let summary = load_with_local_epoch(&evicted_path, network, &epoch, || {
                evicted_loads.fetch_add(1, Ordering::SeqCst);
                Ok(Some(summary_with_tip(11)))
            })
            .unwrap();
            assert_eq!(u32::from(summary.unwrap().chain_tip_height()), 11);
        }
        let retained = load_with_local_epoch(&retained_path, WalletNetwork::Main, &epoch, || {
            retained_loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(21)))
        })
        .unwrap();

        assert_eq!(evicted_loads.load(Ordering::SeqCst), 4);
        assert_eq!(retained_loads.load(Ordering::SeqCst), 1);
        assert_eq!(u32::from(retained.unwrap().chain_tip_height()), 20);

        remove_file(&evicted_path);
        remove_file(&retained_path);
    }

    #[test]
    fn write_overlapping_read_cannot_publish_stale_result() {
        let path = unique_path("stale");
        touch_file(&path);
        let epoch = Arc::new(AtomicU64::new(0));
        let loads = Arc::new(AtomicUsize::new(0));
        let entered = Arc::new(Barrier::new(2));
        let release_loader = Arc::new(Barrier::new(2));

        let path_reader = path.clone();
        let epoch_reader = Arc::clone(&epoch);
        let loads_reader = Arc::clone(&loads);
        let entered_reader = Arc::clone(&entered);
        let release_reader = Arc::clone(&release_loader);
        let reader = thread::spawn(move || {
            load_with_local_epoch(&path_reader, WalletNetwork::Main, &epoch_reader, || {
                loads_reader.fetch_add(1, Ordering::SeqCst);
                entered_reader.wait();
                // Simulate a write overlapping the load: bump the local
                // epoch odd then even before the loader finishes.
                epoch_reader.fetch_add(1, Ordering::AcqRel);
                epoch_reader.fetch_add(1, Ordering::AcqRel);
                release_reader.wait();
                Ok(Some(summary_with_tip(1)))
            })
        });

        entered.wait();
        release_loader.wait();

        let stale_result = reader.join().unwrap().unwrap();
        assert_eq!(
            u32::from(stale_result.as_ref().unwrap().chain_tip_height()),
            1
        );

        // The stale load must not have been published. A follow-up read
        // reloads and observes the post-write value.
        let fresh = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(2)))
        })
        .unwrap();
        assert_eq!(loads.load(Ordering::SeqCst), 2);
        assert_eq!(u32::from(fresh.as_ref().unwrap().chain_tip_height()), 2);

        remove_file(&path);
    }

    #[test]
    fn successful_write_invalidates_cached_summary() {
        let path = unique_path("invalidate");
        touch_file(&path);
        let epoch = AtomicU64::new(0);
        let loads = AtomicUsize::new(0);

        load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(10)))
        })
        .unwrap();
        assert_eq!(loads.load(Ordering::SeqCst), 1);

        epoch.fetch_add(1, Ordering::AcqRel);
        epoch.fetch_add(1, Ordering::AcqRel);

        let after = load_with_local_epoch(&path, WalletNetwork::Main, &epoch, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(11)))
        })
        .unwrap();
        assert_eq!(loads.load(Ordering::SeqCst), 2);
        assert_eq!(u32::from(after.as_ref().unwrap().chain_tip_height()), 11);

        remove_file(&path);
    }

    #[test]
    fn real_write_lock_epoch_invalidates_production_cache_path() {
        let path = unique_path("real-epoch");
        touch_file(&path);
        let loads = AtomicUsize::new(0);

        // Use the production epoch source so a real write-lock cycle is what
        // invalidates the published entry.
        get_or_load_with(&path, WalletNetwork::Main, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(10)))
        })
        .unwrap();

        with_wallet_db_write_lock("test.real_epoch_write", || {});

        get_or_load_with(&path, WalletNetwork::Main, || {
            loads.fetch_add(1, Ordering::SeqCst);
            Ok(Some(summary_with_tip(11)))
        })
        .unwrap();

        // Parallel tests may also bump the global epoch, so require at least
        // one invalidation reload rather than an exact count.
        assert!(loads.load(Ordering::SeqCst) >= 2);

        remove_file(&path);
    }

    #[test]
    fn real_wallet_write_forces_summary_reload() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let phrase = crate::wallet::keys::generate_mnemonic();
        let seed = crate::wallet::keys::mnemonic_to_seed(&phrase).unwrap();

        crate::wallet::keys::init_db_and_create_account(
            db_path,
            WalletNetwork::Regtest,
            &seed,
            Some(1_000),
            "test",
        )
        .unwrap();
        crate::wallet::sync::update_chain_tip(db_path, WalletNetwork::Regtest, 1_100).unwrap();

        let loads = AtomicUsize::new(0);
        let epoch_before = wallet_db_write_epoch();
        let first = get_or_load_with(db_path, WalletNetwork::Regtest, || {
            loads.fetch_add(1, Ordering::SeqCst);
            let db = open_wallet_db_for_read_with_timeout(
                db_path,
                WalletNetwork::Regtest,
                READ_DB_BUSY_TIMEOUT,
            )?;
            db.get_wallet_summary(ConfirmationsPolicy::default())
                .map_err(|e| format!("{e}"))
        })
        .unwrap();
        let second = get_or_load_with(db_path, WalletNetwork::Regtest, || {
            loads.fetch_add(1, Ordering::SeqCst);
            let db = open_wallet_db_for_read_with_timeout(
                db_path,
                WalletNetwork::Regtest,
                READ_DB_BUSY_TIMEOUT,
            )?;
            db.get_wallet_summary(ConfirmationsPolicy::default())
                .map_err(|e| format!("{e}"))
        })
        .unwrap();
        // Fresh wallets can still return Ok(None) from get_wallet_summary
        // before any blocks are scanned; the important property is that the
        // successful None (or Some) was cached across the second call.
        assert_eq!(first, second);
        // This test reads the real global write epoch, so a parallel suite
        // writing between these two loads legitimately invalidates the cache.
        // The reload assertions below absorb that as a lower bound, but a
        // cache *hit* cannot be expressed that way -- so only assert it when
        // no write intervened.
        if epoch_before == wallet_db_write_epoch() && epoch_before % 2 == 0 {
            assert_eq!(loads.load(Ordering::SeqCst), 1);
        }

        crate::wallet::sync::update_chain_tip(db_path, WalletNetwork::Regtest, 1_200).unwrap();

        let third = get_or_load_with(db_path, WalletNetwork::Regtest, || {
            loads.fetch_add(1, Ordering::SeqCst);
            let db = open_wallet_db_for_read_with_timeout(
                db_path,
                WalletNetwork::Regtest,
                READ_DB_BUSY_TIMEOUT,
            )?;
            db.get_wallet_summary(ConfirmationsPolicy::default())
                .map_err(|e| format!("{e}"))
        })
        .unwrap();
        assert!(loads.load(Ordering::SeqCst) >= 2);
        let _ = third;
    }
}
