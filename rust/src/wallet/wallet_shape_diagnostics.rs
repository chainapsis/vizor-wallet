//! One-shot wallet-shape dump for field diagnosis of summary latency.
//!
//! Timing alone is not comparable between machines: a 2-second summary on a
//! user's phone and a 165ms summary on a developer's laptop can be the same
//! query over wildly different row counts, or the same row counts on
//! different hardware. This logs the *inputs* that determine summary cost, so
//! a report from the field can be placed on the scaling curve produced by
//! `rust/tests/summary_scaling.rs` instead of guessed at.
//!
//! The two numbers that matter most are the `blocks` row count and the
//! `scan_queue` split by priority — those are what `subtree_scan_progress`
//! scans and filters on, and they vary by orders of magnitude between
//! wallets. Everything else here is context for the balance half of the
//! summary, which scales with accounts and notes instead.
//!
//! Emission is deliberately rare: once per process, plus once per slow load
//! above [`SLOW_LOAD_LOG_THRESHOLD_MS`] and then rate-limited. It is wired
//! into the summary cache's load path so it needs no FRB surface and no Dart
//! change — it ships with whatever build carries the cache.
//!
//! Read-only throughout. This must never repair, migrate, or write to the
//! wallet DB; a diagnostic that mutates the thing it is measuring is worse
//! than no diagnostic.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use crate::wallet::db::open_readonly_conn_with_timeout;

/// A load slower than this is worth a shape dump even if one was already
/// emitted, because it is the case we are trying to explain.
const SLOW_LOAD_LOG_THRESHOLD_MS: f64 = 500.0;

/// Minimum number of loads between two slow-path dumps, so a persistently
/// slow wallet logs its shape occasionally rather than on every miss.
const SLOW_LOG_EVERY_N_LOADS: u64 = 25;

static SHAPE_LOGGED: AtomicBool = AtomicBool::new(false);
static LOADS_SINCE_SLOW_LOG: AtomicU64 = AtomicU64::new(0);

/// Counters for the cache's own effectiveness, reported alongside the shape.
///
/// A shape is only actionable together with a hit rate: 250ms per miss is
/// irrelevant at 92% hits and severe at 40%, and the required hit rate rises
/// with miss cost.
static HITS: AtomicU64 = AtomicU64::new(0);
static LOADS: AtomicU64 = AtomicU64::new(0);
static STORES: AtomicU64 = AtomicU64::new(0);
static STALE_DISCARDS: AtomicU64 = AtomicU64::new(0);

pub(crate) fn record_hit() {
    HITS.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn record_store() {
    STORES.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn record_stale_discard() {
    STALE_DISCARDS.fetch_add(1, Ordering::Relaxed);
}

/// Formats the cache counters. Kept separate from the shape dump so the
/// ratio can also be logged on its own.
fn cache_stats_line() -> String {
    let hits = HITS.load(Ordering::Relaxed);
    let loads = LOADS.load(Ordering::Relaxed);
    let requests = hits + loads;
    let hit_pct = if requests > 0 {
        (hits as f64 / requests as f64) * 100.0
    } else {
        0.0
    };
    format!(
        "requests={requests} hits={hits} ({hit_pct:.1}%) loads={loads} \
         stores={} stale_discards={}",
        STORES.load(Ordering::Relaxed),
        STALE_DISCARDS.load(Ordering::Relaxed),
    )
}

fn scalar_i64(conn: &rusqlite::Connection, sql: &str) -> Option<i64> {
    conn.query_row(sql, [], |row| row.get::<_, Option<i64>>(0))
        .ok()
        .flatten()
}

/// `scan_queue` rows grouped by priority, as `"10:3 20:47"`.
///
/// The count of rows with priority above `Scanned` (10) is the fragmentation
/// term: each one widens the correlated `NOT EXISTS` that the progress
/// aggregate evaluates per block row.
fn scan_queue_by_priority(conn: &rusqlite::Connection) -> String {
    let Ok(mut stmt) = conn.prepare(
        "SELECT priority, COUNT(*) FROM scan_queue GROUP BY priority ORDER BY priority",
    ) else {
        return "unavailable".to_string();
    };
    let Ok(rows) = stmt.query_map([], |row| {
        Ok(format!(
            "{}:{}",
            row.get::<_, i64>(0)?,
            row.get::<_, i64>(1)?
        ))
    }) else {
        return "unavailable".to_string();
    };
    let parts: Vec<String> = rows.filter_map(Result::ok).collect();
    if parts.is_empty() {
        "none".to_string()
    } else {
        parts.join(" ")
    }
}

/// Emits the shape dump unconditionally. Prefer [`maybe_log_wallet_shape`].
pub(crate) fn log_wallet_shape(db_path: &str, reason: &str) {
    // Read-only, fail-fast: a diagnostic must never block a user-facing read
    // behind a busy timeout, and must never be the reason a wallet is opened
    // writable.
    let conn = match open_readonly_conn_with_timeout(db_path, None) {
        Ok(conn) => conn,
        Err(error) => {
            log::warn!("wallet shape ({reason}): could not open read-only: {error}");
            return;
        }
    };

    let blocks = scalar_i64(&conn, "SELECT COUNT(*) FROM blocks").unwrap_or(-1);
    let min_height = scalar_i64(&conn, "SELECT MIN(height) FROM blocks").unwrap_or(-1);
    let max_height = scalar_i64(&conn, "SELECT MAX(height) FROM blocks").unwrap_or(-1);
    let accounts = scalar_i64(&conn, "SELECT COUNT(*) FROM accounts").unwrap_or(-1);
    let queue_rows = scalar_i64(&conn, "SELECT COUNT(*) FROM scan_queue").unwrap_or(-1);
    let queue_by_priority = scan_queue_by_priority(&conn);

    // Per-pool note counts drive the balance half of the summary. A missing
    // table (older schema, pool not yet activated) reports -1 rather than
    // failing the dump.
    let sapling_notes =
        scalar_i64(&conn, "SELECT COUNT(*) FROM sapling_received_notes").unwrap_or(-1);
    let orchard_notes =
        scalar_i64(&conn, "SELECT COUNT(*) FROM orchard_received_notes").unwrap_or(-1);
    let ironwood_notes =
        scalar_i64(&conn, "SELECT COUNT(*) FROM ironwood_received_notes").unwrap_or(-1);
    let transactions = scalar_i64(&conn, "SELECT COUNT(*) FROM transactions").unwrap_or(-1);

    // `librustzcash` never runs ANALYZE, so `sqlite_stat1` is normally
    // absent and the planner works from default row-count guesses. Whether
    // it is present at all is worth knowing before blaming the query.
    let has_stat1 = scalar_i64(
        &conn,
        "SELECT COUNT(*) FROM sqlite_master WHERE name = 'sqlite_stat1'",
    )
    .unwrap_or(0)
        > 0;
    let page_size = scalar_i64(&conn, "PRAGMA page_size").unwrap_or(-1);
    let page_count = scalar_i64(&conn, "PRAGMA page_count").unwrap_or(-1);
    let db_mib = if page_size > 0 && page_count > 0 {
        (page_size as f64 * page_count as f64) / (1024.0 * 1024.0)
    } else {
        -1.0
    };

    log::info!(
        "wallet shape ({reason}): blocks={blocks} heights={min_height}..={max_height} \
         scan_queue={queue_rows} by_priority=[{queue_by_priority}] accounts={accounts} \
         txs={transactions} notes=[sapling={sapling_notes} orchard={orchard_notes} \
         ironwood={ironwood_notes}] db_mib={db_mib:.1} page_size={page_size} \
         sqlite_stat1={has_stat1} | cache: {}",
        cache_stats_line()
    );
}

/// Logs the shape once per process, and again after a slow load.
///
/// `elapsed_ms` is the duration of the summary computation that just
/// finished. Call this only on the load path — a cache hit did no SQLite
/// work and has nothing to explain.
pub(crate) fn maybe_log_wallet_shape(db_path: &str, elapsed_ms: f64) {
    LOADS.fetch_add(1, Ordering::Relaxed);

    if !SHAPE_LOGGED.swap(true, Ordering::Relaxed) {
        LOADS_SINCE_SLOW_LOG.store(0, Ordering::Relaxed);
        spawn_shape_dump(db_path, "first load".to_string());
        return;
    }

    if elapsed_ms < SLOW_LOAD_LOG_THRESHOLD_MS {
        return;
    }

    // Rate-limit: a wallet that is slow on every miss should say so
    // periodically, not on every miss.
    let since = LOADS_SINCE_SLOW_LOG.fetch_add(1, Ordering::Relaxed) + 1;
    if since >= SLOW_LOG_EVERY_N_LOADS {
        LOADS_SINCE_SLOW_LOG.store(0, Ordering::Relaxed);
        spawn_shape_dump(db_path, format!("slow load {elapsed_ms:.0}ms"));
    }
}

/// Runs the dump off the calling thread.
///
/// The counting queries are themselves full scans — `COUNT(*)` over a
/// multi-million-row `blocks` table is precisely the work whose cost we are
/// investigating — so charging them to a caller that is already waiting on a
/// slow summary would make the diagnostic part of the problem. Rate limiting
/// keeps this to a handful of short-lived threads per session.
fn spawn_shape_dump(db_path: &str, reason: String) {
    let db_path = db_path.to_string();
    std::thread::Builder::new()
        .name("wallet-shape-diag".into())
        .spawn(move || log_wallet_shape(&db_path, &reason))
        .map(|_| ())
        .unwrap_or_else(|error| {
            log::warn!("wallet shape: could not spawn diagnostic thread: {error}");
        });
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The dump must survive a DB that has none of the tables it asks about,
    /// because it runs on whatever the field build finds — including a
    /// partially migrated or unexpected schema.
    #[test]
    fn shape_dump_tolerates_missing_tables() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("empty.db");
        let path = path.to_str().unwrap();
        rusqlite::Connection::open(path).unwrap();

        // Must not panic: every scalar falls back rather than unwrapping.
        log_wallet_shape(path, "test");
    }

    #[test]
    fn shape_dump_tolerates_missing_file() {
        log_wallet_shape("/nonexistent/path/to/wallet.db", "test");
    }

    #[test]
    fn scan_queue_grouping_reports_priorities() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("queue.db");
        let conn = rusqlite::Connection::open(&path).unwrap();
        conn.execute(
            "CREATE TABLE scan_queue (block_range_start INTEGER, block_range_end INTEGER, priority INTEGER)",
            [],
        )
        .unwrap();
        for (start, end, priority) in [(0, 10, 10), (10, 20, 10), (20, 30, 20)] {
            conn.execute(
                "INSERT INTO scan_queue VALUES (?1, ?2, ?3)",
                rusqlite::params![start, end, priority],
            )
            .unwrap();
        }

        assert_eq!(scan_queue_by_priority(&conn), "10:2 20:1");
    }

    #[test]
    fn cache_stats_line_reports_hit_rate() {
        HITS.store(9, Ordering::Relaxed);
        LOADS.store(1, Ordering::Relaxed);
        let line = cache_stats_line();
        assert!(line.contains("requests=10"), "{line}");
        assert!(line.contains("(90.0%)"), "{line}");
    }
}
