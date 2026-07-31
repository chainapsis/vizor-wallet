//! Scaling curve for the `get_wallet_summary` scan-progress queries.
//!
//! # What this answers
//!
//! `get_wallet_summary` spends roughly half its time in
//! `subtree_scan_progress` (`zcash_client_sqlite::wallet`), which runs one
//! full aggregate over `blocks` per shielded pool, each filtered by a
//! correlated `NOT EXISTS` against `scan_queue`. Profiling one wallet tells
//! you what that costs *on that wallet*. This harness instead measures the
//! cost as a function of the two inputs that vary between wallets:
//!
//!   * how many rows `blocks` holds (birthday age / sync depth), and
//!   * how many priority segments `scan_queue` is split into (fragmentation).
//!
//! The output is a table you can read a formula off. Given a user's two
//! counts you can then predict their progress latency without their DB —
//! and decide whether a reported latency is explainable by their dataset at
//! all, or whether it must be concurrency or device speed.
//!
//! It also reports fresh-connection vs reused-connection timings, which is
//! the measurement for whether per-call connection setup and a cold SQLite
//! page cache are material.
//!
//! # Running it
//!
//! Close the wallet app first — the source DB is copied byte-for-byte and
//! must not be mid-write.
//!
//! ```bash
//! VIZOR_SUMMARY_BENCH_DB=/path/to/zcash_wallet.db \
//!   cargo test --release --test summary_scaling -- --ignored --nocapture
//! ```
//!
//! Optional knobs (comma-separated):
//!
//! ```bash
//! VIZOR_SUMMARY_BENCH_BLOCKS=0,500000,1000000,2000000   # 0 = leave as-is
//! VIZOR_SUMMARY_BENCH_SEGMENTS=2,10,50,200
//! VIZOR_SUMMARY_BENCH_REPS=5
//! ```
//!
//! # What it is not
//!
//! The inflated rows are synthetic: plausible heights, monotonic tree sizes,
//! fixed output counts. That is sufficient for *timing* the progress
//! aggregates, which read only heights, output counts and queue ranges. It
//! is **not** a valid wallet — never point a correctness test at an inflated
//! DB, and never reuse one as a fixture.
//!
//! This covers the progress half of a summary only. The balance half (the
//! unspent-notes scan across all accounts) scales with accounts and notes
//! instead, and is measured in-app by the `debug-wallet-summary-timing`
//! feature.

use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

use rusqlite::Connection;

/// `ScanPriority::Scanned` as stored by `zcash_client_sqlite`. The progress
/// filter excludes any block inside a queue range with a *higher* priority.
const SCANNED_PRIORITY: i64 = 10;
/// `ScanPriority::Historic` — any value above `Scanned` makes the range count
/// as pending re-scan, which is what the `NOT EXISTS` filter has to reject.
const UNSCANNED_PRIORITY: i64 = 20;

/// One aggregate runs per pool, so a summary pays all three.
const POOL_OUTPUT_COUNT_COLS: [&str; 3] = [
    "sapling_output_count",
    "orchard_action_count",
    "ironwood_action_count",
];

/// Shape of the `blocks` table, read before and after inflation.
#[derive(Debug, Clone, Copy)]
struct BlockShape {
    rows: u64,
    min_height: u32,
    max_height: u32,
}

fn env_list(key: &str, default: &[u64]) -> Vec<u64> {
    match std::env::var(key) {
        Ok(raw) => raw
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(|s| {
                s.parse::<u64>()
                    .unwrap_or_else(|_| panic!("{key}: `{s}` is not a number"))
            })
            .collect(),
        Err(_) => default.to_vec(),
    }
}

fn block_shape(conn: &Connection) -> BlockShape {
    conn.query_row(
        "SELECT COUNT(*), IFNULL(MIN(height), 0), IFNULL(MAX(height), 0) FROM blocks",
        [],
        |row| {
            Ok(BlockShape {
                rows: row.get::<_, i64>(0)? as u64,
                min_height: row.get::<_, i64>(1)? as u32,
                max_height: row.get::<_, i64>(2)? as u32,
            })
        },
    )
    .expect("read blocks shape")
}

/// Copies the wallet DB (and any WAL sidecars) to `dest`.
///
/// A byte copy rather than `VACUUM INTO`: vacuuming defragments the file,
/// which would quietly make every measurement faster than the wallet it was
/// taken from. Requires that nothing is writing the source.
fn open_readonly(path: &Path) -> Connection {
    Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
        .expect("open DB read-only")
}

fn copy_db(source: &Path, dest: &Path) {
    fs::copy(source, dest).expect("copy wallet DB");
    for suffix in ["-wal", "-shm"] {
        let from = PathBuf::from(format!("{}{suffix}", source.display()));
        if from.exists() {
            let to = PathBuf::from(format!("{}{suffix}", dest.display()));
            fs::copy(&from, &to).expect("copy WAL sidecar");
        }
    }
}

/// Appends synthetic rows above the current tip until `blocks` holds
/// `target` rows.
///
/// Rows are appended *above* the tip rather than below the birthday because
/// the progress aggregates filter on `:start_height <= height`; rows below
/// the start height would be skipped and the scan would not grow.
///
/// Commitment tree sizes stay monotonically increasing so the shape matches
/// what the real queries expect to read, and each row carries a non-zero
/// output count so `SUM(...)` has real work to do.
fn inflate_blocks(conn: &mut Connection, target: u64) -> BlockShape {
    let shape = block_shape(conn);
    if target <= shape.rows {
        return shape;
    }
    let to_add = target - shape.rows;

    // Continue the tree sizes from the current tip so the column stays
    // monotonic; a missing value (empty wallet) just starts from zero.
    let (mut sapling_size, mut orchard_size, mut ironwood_size) = conn
        .query_row(
            "SELECT IFNULL(MAX(sapling_commitment_tree_size), 0),
                    IFNULL(MAX(orchard_commitment_tree_size), 0),
                    IFNULL(MAX(ironwood_commitment_tree_size), 0)
             FROM blocks",
            [],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .expect("read tree sizes");

    const OUTPUTS_PER_BLOCK: i64 = 2;
    let hash = vec![0u8; 32];
    let tree: Vec<u8> = Vec::new();

    let tx = conn.transaction().expect("begin inflate");
    {
        let mut stmt = tx
            .prepare(
                "INSERT INTO blocks (
                     height, hash, time, sapling_tree,
                     sapling_commitment_tree_size, orchard_commitment_tree_size,
                     sapling_output_count, orchard_action_count,
                     ironwood_commitment_tree_size, ironwood_action_count
                 ) VALUES (?1, ?2, 0, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            )
            .expect("prepare insert");
        for i in 1..=to_add {
            let height = shape.max_height as i64 + i as i64;
            sapling_size += OUTPUTS_PER_BLOCK;
            orchard_size += OUTPUTS_PER_BLOCK;
            ironwood_size += OUTPUTS_PER_BLOCK;
            stmt.execute(rusqlite::params![
                height,
                hash,
                tree,
                sapling_size,
                orchard_size,
                OUTPUTS_PER_BLOCK,
                OUTPUTS_PER_BLOCK,
                ironwood_size,
                OUTPUTS_PER_BLOCK,
            ])
            .expect("insert synthetic block");
        }
    }
    tx.commit().expect("commit inflate");

    block_shape(conn)
}

/// Replaces `scan_queue` with `segments` contiguous ranges spanning the whole
/// block range, alternating scanned/pending priority.
///
/// Alternating means roughly half the blocks fall inside a pending range and
/// must be rejected by the `NOT EXISTS` filter — the realistic fragmented
/// case, and the one where the correlated subquery does the most work.
fn set_scan_queue_segments(conn: &Connection, shape: BlockShape, segments: u64) {
    assert!(segments >= 1, "need at least one scan_queue segment");
    conn.execute("DELETE FROM scan_queue", [])
        .expect("clear scan_queue");

    let start = shape.min_height as u64;
    let end = shape.max_height as u64 + 1;
    let span = end.saturating_sub(start).max(segments);
    let step = span / segments;

    let mut stmt = conn
        .prepare("INSERT INTO scan_queue (block_range_start, block_range_end, priority) VALUES (?1, ?2, ?3)")
        .expect("prepare scan_queue insert");
    for i in 0..segments {
        let range_start = start + i * step;
        // The last segment absorbs any remainder so the ranges stay
        // contiguous and cover the full span.
        let range_end = if i + 1 == segments {
            end.max(range_start + 1)
        } else {
            range_start + step
        };
        let priority = if i % 2 == 0 {
            SCANNED_PRIORITY
        } else {
            UNSCANNED_PRIORITY
        };
        stmt.execute(rusqlite::params![
            range_start as i64,
            range_end as i64,
            priority
        ])
        .expect("insert scan_queue segment");
    }
}

/// The progress aggregate, copied from `subtree_scan_progress`.
///
/// Mirrored rather than called because the upstream function is private.
/// This is a timing harness, so a faithful copy of the SQL is sufficient;
/// it is deliberately not used for any correctness assertion.
fn progress_sql(output_count_col: &str) -> String {
    format!(
        "SELECT SUM({output_count_col})
         FROM blocks
         WHERE :start_height <= height
         AND NOT EXISTS (
             SELECT 1 FROM scan_queue
             WHERE block_range_start <= blocks.height
               AND blocks.height < block_range_end
               AND priority > :scanned_priority
         )"
    )
}

fn run_progress_query(conn: &Connection, sql: &str, start_height: u32) -> Duration {
    let started = Instant::now();
    let _: Option<i64> = conn
        .query_row(
            sql,
            rusqlite::named_params! {
                ":start_height": start_height,
                ":scanned_priority": SCANNED_PRIORITY,
            },
            |row| row.get::<_, Option<i64>>(0),
        )
        .expect("run progress query");
    started.elapsed()
}

fn median(mut values: Vec<Duration>) -> Duration {
    values.sort();
    values[values.len() / 2]
}

fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1_000.0
}

/// Total of all three pools — one summary pays every pool's aggregate.
fn measure_cell(db_path: &Path, shape: BlockShape, reps: usize) -> (f64, f64) {
    let start_height = shape.min_height;

    // Fresh connection per rep: the cost the app actually pays today, since
    // every read opens a new connection with an empty 2 MiB page cache.
    let mut cold = Vec::new();
    for _ in 0..reps {
        let conn = Connection::open(db_path).expect("open cold");
        let mut total = Duration::ZERO;
        for col in POOL_OUTPUT_COUNT_COLS {
            total += run_progress_query(&conn, &progress_sql(col), start_height);
        }
        cold.push(total);
    }

    // Reused connection: the cost if connections were pooled, or the page
    // cache were large enough to survive. The gap between the two is the
    // value of fixing connection handling.
    let conn = Connection::open(db_path).expect("open warm");
    let mut warm = Vec::new();
    for _ in 0..reps {
        let mut total = Duration::ZERO;
        for col in POOL_OUTPUT_COUNT_COLS {
            total += run_progress_query(&conn, &progress_sql(col), start_height);
        }
        warm.push(total);
    }

    (ms(median(cold)), ms(median(warm)))
}

#[test]
#[ignore = "requires a real wallet DB via VIZOR_SUMMARY_BENCH_DB"]
fn summary_progress_scaling_curve() {
    let source = std::env::var("VIZOR_SUMMARY_BENCH_DB")
        .expect("set VIZOR_SUMMARY_BENCH_DB to a wallet DB (app must be closed)");
    let source = PathBuf::from(source);
    assert!(source.exists(), "no such wallet DB: {}", source.display());

    let block_targets = env_list("VIZOR_SUMMARY_BENCH_BLOCKS", &[0, 500_000, 1_000_000, 2_000_000]);
    let segment_counts = env_list("VIZOR_SUMMARY_BENCH_SEGMENTS", &[2, 10, 50, 200]);
    let reps = env_list("VIZOR_SUMMARY_BENCH_REPS", &[5])[0] as usize;

    // The source is the user's live wallet: only ever opened read-only, and
    // every mutation happens on the temp copy.
    let baseline = block_shape(&open_readonly(&source));

    println!();
    println!("source: {}", source.display());
    println!(
        "baseline blocks: {} rows, heights {}..={}",
        baseline.rows, baseline.min_height, baseline.max_height
    );
    println!("reps per cell: {reps} (median reported)");
    println!();
    println!(
        "{:>10}  {:>9}  {:>12}  {:>12}  {:>9}",
        "blocks", "segments", "cold ms", "warm ms", "cold/warm"
    );
    println!("{}", "-".repeat(60));

    for &target in &block_targets {
        // A fresh copy per block target; segment variations reuse it, since
        // rewriting scan_queue is cheap and does not disturb `blocks`.
        let dir = tempfile::tempdir().expect("tempdir");
        let work = dir.path().join("bench_wallet.db");
        copy_db(&source, &work);

        let shape = {
            let mut conn = Connection::open(&work).expect("open work DB");
            if target == 0 {
                block_shape(&conn)
            } else {
                inflate_blocks(&mut conn, target)
            }
        };

        for &segments in &segment_counts {
            {
                let conn = Connection::open(&work).expect("open for queue rewrite");
                set_scan_queue_segments(&conn, shape, segments);
            }
            let (cold, warm) = measure_cell(&work, shape, reps);
            println!(
                "{:>10}  {:>9}  {:>12.1}  {:>12.1}  {:>8.2}x",
                shape.rows,
                segments,
                cold,
                warm,
                if warm > 0.0 { cold / warm } else { 0.0 }
            );
        }
    }

    println!();
    println!("cold = fresh connection per call (what the app does today)");
    println!("warm = reused connection (what pooling or a bigger page cache would buy)");
    println!("all three pools summed: one get_wallet_summary pays this much progress cost");
    println!();
}
