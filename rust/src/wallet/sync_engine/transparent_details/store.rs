//! Durable state of transparent txid enhancement.
//!
//! A stand-in for the wallet-libraries operations the integration branch adds:
//! [`transparent_detail_work`], [`store_transparent_display`],
//! [`defer_transparent_detail`] and [`transparent_display_view`], with their
//! announced shapes. Until the wallet database owns these tables, the facts
//! and deferrals live in a companion SQLite file inside the wallet's
//! transparent recovery directory (`{db}.tpir/txid-details.sqlite`), which
//! wallet reset and orphan cleanup already delete and backups exclude. The
//! wallet database is only read here.
//!
//! Work is every mined transparent or mixed transaction of an account that
//! has no raw bytes: one whose transparent outputs or spends the wallet
//! recorded, publicly or through private recovery, while its payload never
//! arrived. Display facts are transaction facts; whether an output is the
//! account's own is decided when the view is read, from what the account
//! recorded.

use std::collections::BTreeSet;
use std::path::PathBuf;
use std::time::Duration;

use rusqlite::{params, Connection, OptionalExtension};
use transparent::address::TransparentAddress;
use transparent_events::FeeState;
use transparent_shard::txid::TransparentDisplayRecord;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BranchId;

use super::client::Provenance;
use crate::wallet::network::WalletNetwork;

/// The companion file, inside the wallet's `.tpir` directory.
pub(crate) const STORE_FILE: &str = "txid-details.sqlite";

/// Waits for a busy companion before failing.
const STORE_BUSY_TIMEOUT: Duration = Duration::from_secs(5);

/// Backoff after a transient failure: doubles from the first step to the cap.
const FIRST_RETRY: Duration = Duration::from_secs(60);
const RETRY_CAP: Duration = Duration::from_secs(60 * 60);
/// A height the publication does not cover is asked about again after this,
/// as the publication's window moves.
const NOT_COVERED_RETRY: Duration = Duration::from_secs(6 * 60 * 60);

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS display_facts (
    txid BLOB PRIMARY KEY CHECK (length(txid) = 32),
    record BLOB NOT NULL,
    coinbase INTEGER NOT NULL,
    fee_zat INTEGER,
    input_count INTEGER NOT NULL,
    shielded INTEGER NOT NULL,
    map_sha256 TEXT NOT NULL,
    shard_id INTEGER NOT NULL,
    manifest_digest TEXT NOT NULL,
    stored_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS display_outputs (
    txid BLOB NOT NULL REFERENCES display_facts(txid) ON DELETE CASCADE,
    output_index INTEGER NOT NULL,
    value_zat INTEGER NOT NULL,
    script BLOB NOT NULL,
    PRIMARY KEY (txid, output_index)
);
CREATE TABLE IF NOT EXISTS display_deferrals (
    txid BLOB PRIMARY KEY CHECK (length(txid) = 32),
    outcome INTEGER NOT NULL,
    attempts INTEGER NOT NULL,
    next_attempt INTEGER NOT NULL,
    map_sha256 TEXT,
    updated_at INTEGER NOT NULL
);
";

/// One transaction whose details a run may look up.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct DetailWork {
    /// Protocol byte order.
    pub(crate) txid: [u8; 32],
    pub(crate) mined_height: u64,
}

/// Why a lookup left a transaction without details.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum DeferOutcome {
    /// The service refused for capacity or was unreachable; retry after its
    /// delay or the backoff.
    Unavailable { retry_after: Option<Duration> },
    /// The lookup failed in a way a retry may not repeat.
    Failed,
    /// The private publication does not cover the transaction: no shard
    /// covers its height, the service has no display, or the covering shard
    /// holds no record of it.
    NotCovered,
}

impl DeferOutcome {
    fn code(self) -> i64 {
        match self {
            DeferOutcome::Unavailable { .. } => 0,
            DeferOutcome::Failed => 1,
            DeferOutcome::NotCovered => 2,
        }
    }
}

/// What storing a record came to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum StoreOutcome {
    Stored,
    /// The policy generation moved since the run began; nothing was stored.
    Superseded,
    /// Different facts are already stored for the transaction; they stay.
    Contradiction,
}

/// What the detail view shows for one transaction of one account.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum DisplayView {
    /// Every transparent output, in order.
    Available { outputs: Vec<ViewOutput> },
    /// No lookup has answered yet.
    Pending,
    /// The last lookup failed; a later run retries.
    Unavailable,
    /// The private publication does not cover the transaction.
    NotCovered,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ViewOutput {
    pub(crate) index: u32,
    pub(crate) value: u64,
    /// The encoded address of a P2PKH or P2SH script; `None` otherwise.
    pub(crate) address: Option<String>,
    /// Whether the account recorded this output as its own.
    pub(crate) own: bool,
}

/// The companion file of the wallet at `db_path`.
pub(crate) fn store_path(db_path: &str) -> PathBuf {
    crate::wallet::sync_engine::transparent_ledger::pir::companion_dir(db_path).join(STORE_FILE)
}

/// Opens (and creates) the companion of the wallet at `db_path`.
pub(crate) fn open_store(db_path: &str) -> Result<Connection, String> {
    let path = store_path(db_path);
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|error| format!("details store dir: {error}"))?;
    }
    let conn = Connection::open(&path).map_err(|error| format!("details store: {error}"))?;
    conn.busy_timeout(STORE_BUSY_TIMEOUT)
        .map_err(|error| format!("details store: {error}"))?;
    conn.execute_batch(&format!("PRAGMA foreign_keys = ON; {SCHEMA}"))
        .map_err(|error| format!("details store schema: {error}"))?;
    Ok(conn)
}

/// Opens the companion only if it exists, for readers.
fn open_store_if_present(db_path: &str) -> Result<Option<Connection>, String> {
    if !store_path(db_path).exists() {
        return Ok(None);
    }
    open_store(db_path).map(Some)
}

/// Candidate transparent or mixed transactions without raw bytes, mined, by
/// txid: `(txid, mined_height)`. Restricted to `account` when given.
const CANDIDATES: &str = "
    WITH involved(txid, mined_height, account_id) AS (
        SELECT t.txid, t.mined_height, o.account_id
        FROM transparent_received_outputs o
        JOIN transactions t ON t.id_tx = o.transaction_id
        UNION ALL
        SELECT t.txid, t.mined_height, o.account_id
        FROM transparent_received_output_spends s
        JOIN transparent_received_outputs o ON o.id = s.transparent_received_output_id
        JOIN transactions t ON t.id_tx = s.transaction_id
        UNION ALL
        SELECT r.txid, r.mined_height, r.account_id FROM tpir_receive_events r
        UNION ALL
        SELECT s.spending_txid, s.mined_height, s.account_id FROM tpir_spend_events s
    )
    SELECT i.txid, MAX(COALESCE(i.mined_height, t.mined_height))
    FROM involved i
    LEFT JOIN transactions t ON t.txid = i.txid
    WHERE length(i.txid) = 32
      AND (?1 IS NULL OR i.account_id = ?1)
      AND (?2 IS NULL OR i.txid = ?2)
      AND (t.raw IS NULL)
    GROUP BY i.txid";

/// The work a run may serve, best first: `prioritized` txids (in order),
/// then the rest by height, newest first, at most `limit`.
///
/// Skips transactions with stored facts, and those whose deferral is not yet
/// due, except that a prioritized transaction skips a transient backoff.
/// Unmined transactions have no placement and are never work.
pub(crate) fn transparent_detail_work(
    wallet: &Connection,
    store: &Connection,
    now: i64,
    limit: usize,
    prioritized: &[[u8; 32]],
) -> Result<Vec<DetailWork>, String> {
    let mut statement = wallet
        .prepare(CANDIDATES)
        .map_err(|error| format!("detail work: {error}"))?;
    let rows = statement
        .query_map(params![None::<i64>, None::<Vec<u8>>], |row| {
            Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, Option<i64>>(1)?))
        })
        .map_err(|error| format!("detail work: {error}"))?;
    let mut candidates = Vec::new();
    for row in rows {
        let (txid, height) = row.map_err(|error| format!("detail work: {error}"))?;
        let (Ok(txid), Some(height)) = (<[u8; 32]>::try_from(txid), height) else {
            continue;
        };
        if let Ok(mined_height) = u64::try_from(height) {
            candidates.push(DetailWork { txid, mined_height });
        }
    }
    let prioritized: Vec<[u8; 32]> = prioritized.to_vec();
    candidates.sort_by_key(|work| {
        let rank = prioritized
            .iter()
            .position(|txid| *txid == work.txid)
            .unwrap_or(usize::MAX);
        (rank, std::cmp::Reverse(work.mined_height))
    });
    let mut work = Vec::new();
    for candidate in candidates {
        if work.len() >= limit {
            break;
        }
        if has_facts(store, &candidate.txid)? {
            continue;
        }
        let deferral = deferral(store, &candidate.txid)?;
        let due = match deferral {
            None => true,
            Some((outcome, next_attempt)) => {
                next_attempt <= now
                    || (prioritized.contains(&candidate.txid)
                        && outcome != DeferOutcome::NotCovered.code())
            }
        };
        if due {
            work.push(candidate);
        }
    }
    Ok(work)
}

fn has_facts(store: &Connection, txid: &[u8; 32]) -> Result<bool, String> {
    store
        .query_row(
            "SELECT 1 FROM display_facts WHERE txid = ?1",
            [txid.as_slice()],
            |_| Ok(()),
        )
        .optional()
        .map(|found| found.is_some())
        .map_err(|error| format!("details store: {error}"))
}

/// `(outcome code, next attempt)` of the transaction's deferral.
fn deferral(store: &Connection, txid: &[u8; 32]) -> Result<Option<(i64, i64)>, String> {
    store
        .query_row(
            "SELECT outcome, next_attempt FROM display_deferrals WHERE txid = ?1",
            [txid.as_slice()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|error| format!("details store: {error}"))
}

/// Stores `record`'s facts unless the policy generation the run captured,
/// `expected_generation`, is no longer `current_generation`. Clears the
/// transaction's deferral.
pub(crate) fn store_transparent_display(
    store: &mut Connection,
    record: &TransparentDisplayRecord,
    provenance: &Provenance,
    expected_generation: u64,
    current_generation: u64,
    now: i64,
) -> Result<StoreOutcome, String> {
    if expected_generation != current_generation {
        return Ok(StoreOutcome::Superseded);
    }
    let encoded = record
        .encode()
        .map_err(|_| "details store: record does not encode".to_owned())?;
    let txid = record.txid.0;
    let tx = store
        .transaction()
        .map_err(|error| format!("details store: {error}"))?;
    let existing: Option<Vec<u8>> = tx
        .query_row(
            "SELECT record FROM display_facts WHERE txid = ?1",
            [txid.as_slice()],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| format!("details store: {error}"))?;
    if let Some(existing) = existing {
        return Ok(if existing == encoded {
            StoreOutcome::Stored
        } else {
            StoreOutcome::Contradiction
        });
    }
    let fee = match record.metadata.fee {
        FeeState::Exact(fee) => Some(i64::try_from(fee).unwrap_or(i64::MAX)),
        FeeState::Unknown | FeeState::NotApplicable => None,
    };
    tx.execute(
        "INSERT INTO display_facts (txid, record, coinbase, fee_zat, input_count, shielded,
             map_sha256, shard_id, manifest_digest, stored_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
        params![
            txid.as_slice(),
            encoded,
            record.coinbase,
            fee,
            record.metadata.transparent_input_count,
            record.metadata.has_shielded_components,
            provenance.map_sha256,
            i64::try_from(provenance.shard_id).unwrap_or(i64::MAX),
            provenance.manifest_digest,
            now,
        ],
    )
    .map_err(|error| format!("details store: {error}"))?;
    for (index, output) in record.outputs.iter().enumerate() {
        tx.execute(
            "INSERT INTO display_outputs (txid, output_index, value_zat, script)
             VALUES (?1, ?2, ?3, ?4)",
            params![
                txid.as_slice(),
                index as i64,
                i64::try_from(output.value).unwrap_or(i64::MAX),
                output.script,
            ],
        )
        .map_err(|error| format!("details store: {error}"))?;
    }
    tx.execute(
        "DELETE FROM display_deferrals WHERE txid = ?1",
        [txid.as_slice()],
    )
    .map_err(|error| format!("details store: {error}"))?;
    tx.commit()
        .map_err(|error| format!("details store: {error}"))?;
    Ok(StoreOutcome::Stored)
}

/// Records that a lookup of `txid` left it without details, and when to try
/// again.
pub(crate) fn defer_transparent_detail(
    store: &Connection,
    txid: &[u8; 32],
    outcome: DeferOutcome,
    map_sha256: Option<&str>,
    now: i64,
) -> Result<(), String> {
    let attempts: i64 = store
        .query_row(
            "SELECT attempts FROM display_deferrals WHERE txid = ?1",
            [txid.as_slice()],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| format!("details store: {error}"))?
        .unwrap_or(0)
        + 1;
    let wait = match outcome {
        DeferOutcome::NotCovered => NOT_COVERED_RETRY,
        DeferOutcome::Unavailable {
            retry_after: Some(delay),
        } => delay.clamp(Duration::from_secs(1), RETRY_CAP),
        DeferOutcome::Unavailable { retry_after: None } | DeferOutcome::Failed => {
            let doublings = u32::try_from(attempts - 1).unwrap_or(u32::MAX).min(6);
            (FIRST_RETRY * 2u32.pow(doublings)).min(RETRY_CAP)
        }
    };
    store
        .execute(
            "INSERT INTO display_deferrals (txid, outcome, attempts, next_attempt, map_sha256, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT (txid) DO UPDATE SET
                 outcome = excluded.outcome,
                 attempts = excluded.attempts,
                 next_attempt = excluded.next_attempt,
                 map_sha256 = excluded.map_sha256,
                 updated_at = excluded.updated_at",
            params![
                txid.as_slice(),
                outcome.code(),
                attempts,
                now.saturating_add(i64::try_from(wait.as_secs()).unwrap_or(i64::MAX)),
                map_sha256,
                now,
            ],
        )
        .map_err(|error| format!("details store: {error}"))?;
    Ok(())
}

/// The detail view of `txid` for the account `account_uuid` (its bytes), or
/// `None` when the transaction has no transparent part the account recorded.
///
/// A transaction with raw bytes shows their transparent outputs; one without
/// shows stored display facts, or its deferral, or pending.
pub(crate) fn transparent_display_view(
    wallet: &Connection,
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &[u8],
    txid: &[u8],
) -> Result<Option<DisplayView>, String> {
    let Some(account_id) = wallet
        .query_row(
            "SELECT id FROM accounts WHERE uuid = ?1",
            [account_uuid],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|error| format!("detail view: {error}"))?
    else {
        return Ok(None);
    };
    if !involves(wallet, account_id, txid)? {
        return Ok(None);
    }
    let own = own_outputs(wallet, account_id, txid)?;
    let view_output = |index: u32, value: u64, script: &[u8]| ViewOutput {
        index,
        value,
        address: script_address(network, script),
        own: own.contains(&index),
    };
    let raw: Option<Option<Vec<u8>>> = wallet
        .query_row(
            "SELECT raw FROM transactions WHERE txid = ?1",
            [txid],
            |row| row.get(0),
        )
        .optional()
        .map_err(|error| format!("detail view: {error}"))?;
    if let Some(Some(raw)) = raw {
        let tx = Transaction::read(&raw[..], BranchId::Sapling)
            .map_err(|error| format!("detail view: {error}"))?;
        let outputs = tx
            .transparent_bundle()
            .map(|bundle| {
                bundle
                    .vout
                    .iter()
                    .enumerate()
                    .map(|(index, out)| ViewOutput {
                        index: index as u32,
                        value: out.value().into_u64(),
                        address: out.recipient_address().map(|address| {
                            zcash_keys::encoding::encode_transparent_address_p(&network, &address)
                        }),
                        own: own.contains(&(index as u32)),
                    })
                    .collect()
            })
            .unwrap_or_default();
        return Ok(Some(DisplayView::Available { outputs }));
    }
    let Some(store) = open_store_if_present(db_path)? else {
        return Ok(Some(DisplayView::Pending));
    };
    let txid32: [u8; 32] = txid
        .try_into()
        .map_err(|_| "detail view: txid length".to_owned())?;
    if has_facts(&store, &txid32)? {
        let mut statement = store
            .prepare(
                "SELECT output_index, value_zat, script FROM display_outputs
                 WHERE txid = ?1 ORDER BY output_index",
            )
            .map_err(|error| format!("detail view: {error}"))?;
        let outputs = statement
            .query_map([txid], |row| {
                Ok((
                    row.get::<_, u32>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, Vec<u8>>(2)?,
                ))
            })
            .map_err(|error| format!("detail view: {error}"))?
            .map(|row| {
                row.map(|(index, value, script)| {
                    view_output(index, u64::try_from(value).unwrap_or(0), &script)
                })
                .map_err(|error| format!("detail view: {error}"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        return Ok(Some(DisplayView::Available { outputs }));
    }
    Ok(Some(match deferral(&store, &txid32)? {
        None => DisplayView::Pending,
        Some((code, _)) if code == DeferOutcome::NotCovered.code() => DisplayView::NotCovered,
        Some(_) => DisplayView::Unavailable,
    }))
}

/// Whether the account recorded a transparent output or spend of `txid`.
fn involves(wallet: &Connection, account_id: i64, txid: &[u8]) -> Result<bool, String> {
    wallet
        .query_row(
            "SELECT EXISTS (
                 SELECT 1 FROM transparent_received_outputs o
                 JOIN transactions t ON t.id_tx = o.transaction_id
                 WHERE t.txid = ?2 AND o.account_id = ?1
                 UNION ALL
                 SELECT 1 FROM transparent_received_output_spends s
                 JOIN transparent_received_outputs o ON o.id = s.transparent_received_output_id
                 JOIN transactions t ON t.id_tx = s.transaction_id
                 WHERE t.txid = ?2 AND o.account_id = ?1
                 UNION ALL
                 SELECT 1 FROM tpir_receive_events WHERE txid = ?2 AND account_id = ?1
                 UNION ALL
                 SELECT 1 FROM tpir_spend_events WHERE spending_txid = ?2 AND account_id = ?1
             )",
            params![account_id, txid],
            |row| row.get(0),
        )
        .map_err(|error| format!("detail view: {error}"))
}

/// Output indices of `txid` the account recorded as received.
fn own_outputs(wallet: &Connection, account_id: i64, txid: &[u8]) -> Result<BTreeSet<u32>, String> {
    let mut statement = wallet
        .prepare(
            "SELECT o.output_index FROM transparent_received_outputs o
             JOIN transactions t ON t.id_tx = o.transaction_id
             WHERE t.txid = ?2 AND o.account_id = ?1
             UNION
             SELECT output_index FROM tpir_receive_events WHERE txid = ?2 AND account_id = ?1",
        )
        .map_err(|error| format!("detail view: {error}"))?;
    let indices = statement
        .query_map(params![account_id, txid], |row| row.get::<_, u32>(0))
        .map_err(|error| format!("detail view: {error}"))?
        .collect::<Result<BTreeSet<_>, _>>()
        .map_err(|error| format!("detail view: {error}"))?;
    Ok(indices)
}

/// The address a P2PKH or P2SH locking script pays.
pub(crate) fn script_address(network: WalletNetwork, script: &[u8]) -> Option<String> {
    let address = match script {
        [0x76, 0xa9, 0x14, hash @ .., 0x88, 0xac] if hash.len() == 20 => {
            TransparentAddress::PublicKeyHash(hash.try_into().ok()?)
        }
        [0xa9, 0x14, hash @ .., 0x87] if hash.len() == 20 => {
            TransparentAddress::ScriptHash(hash.try_into().ok()?)
        }
        _ => return None,
    };
    Some(zcash_keys::encoding::encode_transparent_address_p(
        &network, &address,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scripts_encode_to_addresses_only_when_standard() {
        let script = hex::decode("76a9141634f5ff0b8f6603a17570436d6c12a91f4b1fed88ac").unwrap();
        assert_eq!(
            script_address(WalletNetwork::Main, &script).as_deref(),
            Some("t1Ku2KLyndDPsR32jwnrTMd3yvi9tfFP8ML")
        );
        assert_eq!(script_address(WalletNetwork::Main, &[0x6a, 0x01, 0x00]), None);
    }

    #[test]
    fn deferrals_back_off_and_respect_retry_after() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let store = open_store(&db_path).unwrap();
        let txid = [7u8; 32];
        let next = |store: &Connection| deferral(store, &txid).unwrap().unwrap().1;
        defer_transparent_detail(&store, &txid, DeferOutcome::Failed, None, 1_000).unwrap();
        assert_eq!(next(&store), 1_060);
        defer_transparent_detail(&store, &txid, DeferOutcome::Failed, None, 1_000).unwrap();
        assert_eq!(next(&store), 1_120);
        defer_transparent_detail(
            &store,
            &txid,
            DeferOutcome::Unavailable {
                retry_after: Some(Duration::from_secs(7)),
            },
            None,
            1_000,
        )
        .unwrap();
        assert_eq!(next(&store), 1_007);
        defer_transparent_detail(&store, &txid, DeferOutcome::NotCovered, Some("ab"), 1_000)
            .unwrap();
        assert_eq!(next(&store), 1_000 + 6 * 60 * 60);
    }
}
