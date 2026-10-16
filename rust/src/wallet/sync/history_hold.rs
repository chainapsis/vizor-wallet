//! Holds notes whose spends may sit in history that is not scanned yet.
//!
//! Zakura marks a note `witness_stabilized` once its own shard is scanned and
//! settled below the highest scanned block, and a stabilized note is always
//! spendable. During a first restore the chain tip and the newest pool's
//! history are scanned first, and older history then ascends from the
//! birthday, so notes found there stabilize while the history above them,
//! where they may already have been spent, is still unscanned. On a
//! full-history restore that gap spans the slow 2022-23 spam window. Spending
//! such a note fails at broadcast and shows a balance higher than the real
//! one.
//!
//! A note is held while it could be spent above its mined height in a range
//! that is still pending:
//! - for an account whose history is not fully scanned yet, any pending
//!   range above the note counts, chain tip ranges included. A restore's
//!   tip range starts at the last completed shard of the pool that lags
//!   most (Sapling on mainnet), which can be weeks below the tip, and is
//!   scanned upward in batches: an Orchard note there stabilizes while its
//!   spend higher in the same range is unscanned. New blocks arriving
//!   during a restore hold the account's notes until they are scanned;
//! - for any account, a note whose recorded spend was un-mined by a rewind
//!   and has expired counts too, because Zakura then treats it as unspent.
//!   Here any pending range counts that could hold the spend, one starting
//!   no later than the spend's expiry height.
//!
//! Notes already spent by a mined transaction are never selectable, so they
//! are not held. Only DBs that the wallet sync runs on are swept.
//!
//! Holding uses Zakura's owner-scoped output locks, so every input selector
//! and the balance summary exclude held notes. Locks carry a rolling expiry a
//! few days of blocks ahead and are renewed by each sweep, so an app that
//! stops sweeping (a rollback or downgrade) releases them on its own. The
//! Vizor ledger lists what this owner locked, so release never depends on
//! reading Zakura's lock columns.

use std::collections::BTreeSet;

use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use zcash_client_backend::{
    data_api::{OutputLockStore, WalletRead},
    wallet::{LockOwner, OutputRef},
};
use zcash_primitives::transaction::{builder::DEFAULT_TX_EXPIRY_DELTA, TxId};
use zcash_protocol::{consensus::BlockHeight, PoolType};

use crate::wallet::db::{
    open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, WalletDatabase,
    WALLET_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;

const LEDGER_TABLE: &str = "vizor_history_hold";
const VERIFIED_TABLE: &str = "vizor_history_verified";
const POLICY_VERSION_KEY: &str = "history_hold_policy_version";
const POLICY_VERSION: u32 = 1;
/// Lock lifetime past the chain tip. Each sweep renews it; without sweeps
/// the locks lapse after about two and a half days of blocks.
const LOCK_LEAD_BLOCKS: u32 = 2_880;
/// Zakura's `ScanPriority::Scanned` code. Higher codes are pending work.
const SCANNED_PRIORITY: i64 = 10;
/// Zakura's `ScanPriority::ChainTip` code. Pending codes below it (Historic,
/// OpenAdjacent, FoundNote) are first-pass history; ChainTip and Verify cover
/// the tip.
const CHAIN_TIP_PRIORITY: i64 = 50;
/// Notes at or below ZIP 317's marginal fee are uneconomic and never counted
/// as spendable or locked by Zakura.
pub(super) const MARGINAL_FEE_ZATS: i64 = 5_000;

const POOLS: [Pool; 3] = [
    Pool {
        code: 2,
        pool: PoolType::SAPLING,
        prefix: "sapling",
        index_column: "output_index",
    },
    Pool {
        code: 3,
        pool: PoolType::ORCHARD,
        prefix: "orchard",
        index_column: "action_index",
    },
    Pool {
        code: 4,
        pool: PoolType::IRONWOOD,
        prefix: "ironwood",
        index_column: "action_index",
    },
];

#[derive(Clone, Copy)]
struct Pool {
    code: i64,
    pool: PoolType,
    prefix: &'static str,
    index_column: &'static str,
}

fn pool_for_code(code: i64) -> Option<Pool> {
    POOLS.iter().copied().find(|pool| pool.code == code)
}

/// Owner token of every hold lock.
pub(super) fn hold_owner() -> LockOwner {
    LockOwner::new(Sha256::digest(b"vizor-history-hold-v1").into())
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct SweepOutcome {
    pub held: usize,
    /// The held set gained or lost a note, so balances should be re-read.
    pub changed: bool,
}

pub(crate) fn ensure_tables(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "CREATE TABLE IF NOT EXISTS {LEDGER_TABLE} (
             pool INTEGER NOT NULL,
             txid BLOB NOT NULL,
             output_index INTEGER NOT NULL,
             PRIMARY KEY (pool, txid, output_index)
         );
         CREATE TABLE IF NOT EXISTS {VERIFIED_TABLE} (
             account_uuid BLOB PRIMARY KEY NOT NULL
         );
         CREATE TABLE IF NOT EXISTS ext_vizor_sync_meta (
             key TEXT PRIMARY KEY NOT NULL,
             value TEXT NOT NULL
         );"
    ))
    .map_err(|e| format!("create history hold tables: {e}"))
}

/// Whether the wallet sync engine has run on this DB; only it records a sync
/// start. Gift Card claim wallets scan up to their funding and watch later
/// blocks through nullifiers, so their pending ranges never close; their own
/// observer tracks the funding spends, and holding would block the claim.
fn is_wallet_sync_db(conn: &Connection) -> Result<bool, String> {
    Ok(
        table_exists(conn, "ext_vizor_sync_meta")?
            && read_meta(conn, "sync_in_progress")?.is_some(),
    )
}

pub(super) fn table_exists(conn: &Connection, name: &str) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)",
        params![name],
        |row| row.get::<_, bool>(0),
    )
    .map_err(|e| format!("check table {name}: {e}"))
}

fn read_meta(conn: &Connection, key: &str) -> Result<Option<String>, String> {
    conn.query_row(
        "SELECT value FROM ext_vizor_sync_meta WHERE key = ?1",
        params![key],
        |row| row.get::<_, String>(0),
    )
    .optional()
    .map_err(|e| format!("read sync metadata {key}: {e}"))
}

/// Marks every account verified when this policy first runs on a wallet that
/// already completed a sync and has no first-pass history pending below that
/// sync. Their spends up to the completed height were detected, so upgrading
/// does not hold funds that were usable before.
fn seed_verified_once(conn: &Connection) -> Result<(), String> {
    if read_meta(conn, POLICY_VERSION_KEY)?.is_some() {
        return Ok(());
    }
    let completed =
        read_meta(conn, "last_completed_sync_height")?.and_then(|value| value.parse::<i64>().ok());
    // An interrupted later sync leaves tip ranges only; history pending below
    // the completed height means an account was added or rewound since.
    if let Some(completed) = completed {
        let historic_below_completed: bool = conn
            .query_row(
                &format!(
                    "SELECT EXISTS(
                         SELECT 1 FROM scan_queue sq
                         WHERE {} AND sq.block_range_start < ?1
                     )",
                    history_pending("sq")
                ),
                params![completed.saturating_sub(100)],
                |row| row.get(0),
            )
            .map_err(|e| format!("read scan queue for history hold seeding: {e}"))?;
        if !historic_below_completed {
            conn.execute(
                &format!(
                    "INSERT OR IGNORE INTO {VERIFIED_TABLE} (account_uuid)
                     SELECT uuid FROM accounts"
                ),
                [],
            )
            .map_err(|e| format!("seed verified accounts: {e}"))?;
        }
    }
    conn.execute(
        "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![POLICY_VERSION_KEY, POLICY_VERSION.to_string()],
    )
    .map_err(|e| format!("write history hold policy version: {e}"))?;
    Ok(())
}

/// Records accounts with no first-pass history pending above their
/// birthday, at sync completion.
pub(crate) fn mark_verified_accounts(tx: &rusqlite::Transaction<'_>) -> Result<(), String> {
    if !table_exists(tx, "accounts")? || !table_exists(tx, "scan_queue")? {
        return Ok(());
    }
    ensure_tables(tx)?;
    tx.execute(
        &format!(
            "INSERT OR IGNORE INTO {VERIFIED_TABLE} (account_uuid)
             SELECT a.uuid FROM accounts a
             WHERE NOT EXISTS (
                 SELECT 1 FROM scan_queue sq
                 WHERE {} AND sq.block_range_end > a.birthday_height
             )",
            history_pending("sq")
        ),
        [],
    )
    .map(|_| ())
    .map_err(|e| format!("mark accounts verified: {e}"))
}

/// The tx-unexpired condition Zakura uses to decide whether a spend counts.
pub(super) fn tx_unexpired_condition(tx: &str) -> String {
    format!(
        "({tx}.mined_height < :target_height
          OR {tx}.expiry_height = 0
          OR {tx}.expiry_height >= :target_height
          OR ({tx}.expiry_height IS NULL
              AND COALESCE({tx}.target_height, {tx}.min_observed_height)
                  + {DEFAULT_TX_EXPIRY_DELTA} >= :target_height))"
    )
}

/// An un-mined transaction whose expiry has passed, so its spends no longer
/// count (the negation of `tx_unexpired_condition` for un-mined rows,
/// written without NULL comparisons).
fn tx_expired_unmined_condition(tx: &str) -> String {
    format!(
        "({tx}.mined_height IS NULL
          AND IFNULL({tx}.expiry_height, -1) <> 0
          AND IFNULL({tx}.expiry_height < :target_height,
                     COALESCE({tx}.target_height, {tx}.min_observed_height)
                         + {DEFAULT_TX_EXPIRY_DELTA} < :target_height))"
    )
}

/// A pending first-pass history range.
fn history_pending(sq: &str) -> String {
    format!("({sq}.priority > {SCANNED_PRIORITY} AND {sq}.priority < {CHAIN_TIP_PRIORITY})")
}

fn candidate_sql(pool: Pool) -> String {
    let p = pool.prefix;
    let index = pool.index_column;
    format!(
        "SELECT t.txid, rn.{index}, rn.lock_expiry_height, rn.lock_owner
         FROM {p}_received_notes rn
         JOIN transactions t ON t.id_tx = rn.transaction_id
         JOIN accounts a ON a.id = rn.account_id
         WHERE t.mined_height IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM {p}_received_note_spends ms
               JOIN transactions mtx ON mtx.id_tx = ms.transaction_id
               WHERE ms.{p}_received_note_id = rn.id
                 AND mtx.mined_height IS NOT NULL
           )
           AND (
               (a.uuid NOT IN (SELECT account_uuid FROM {VERIFIED_TABLE})
                AND EXISTS (
                    SELECT 1 FROM scan_queue sq
                    WHERE sq.priority > {SCANNED_PRIORITY}
                      AND sq.block_range_end > t.mined_height + 1
                ))
               OR EXISTS (
                   SELECT 1 FROM {p}_received_note_spends rns
                   JOIN transactions stx ON stx.id_tx = rns.transaction_id
                   WHERE rns.{p}_received_note_id = rn.id
                     AND {expired}
                     AND EXISTS (
                         SELECT 1 FROM scan_queue sq
                         WHERE sq.priority > {SCANNED_PRIORITY}
                           AND sq.block_range_end > t.mined_height + 1
                           AND sq.block_range_start <= COALESCE(
                               NULLIF(stx.expiry_height, 0),
                               COALESCE(stx.target_height, stx.min_observed_height)
                                   + {DEFAULT_TX_EXPIRY_DELTA}
                           )
                     )
               )
           )",
        expired = tx_expired_unmined_condition("stx"),
    )
}

type NoteKey = (i64, [u8; 32], u32);

/// A candidate's current lock, to tell a lock this owner still holds from
/// one that lapsed or was taken.
#[derive(Clone, Default)]
struct CurrentLock {
    expiry: Option<u32>,
    owner: Option<Vec<u8>>,
}

fn read_candidates(
    conn: &Connection,
    target_height: u32,
) -> Result<std::collections::BTreeMap<NoteKey, CurrentLock>, String> {
    let mut out = std::collections::BTreeMap::new();
    for pool in POOLS {
        if !table_exists(conn, &format!("{}_received_notes", pool.prefix))? {
            continue;
        }
        let mut stmt = conn
            .prepare(&candidate_sql(pool))
            .map_err(|e| format!("prepare {} hold candidates: {e}", pool.prefix))?;
        let rows = stmt
            .query_map(
                rusqlite::named_params![":target_height": target_height],
                |row| {
                    Ok((
                        row.get::<_, Vec<u8>>(0)?,
                        row.get::<_, u32>(1)?,
                        CurrentLock {
                            expiry: row.get(2)?,
                            owner: row.get(3)?,
                        },
                    ))
                },
            )
            .map_err(|e| format!("read {} hold candidates: {e}", pool.prefix))?;
        for row in rows {
            let (txid, index, lock) =
                row.map_err(|e| format!("read {} hold candidate: {e}", pool.prefix))?;
            if let Ok(txid) = <[u8; 32]>::try_from(txid.as_slice()) {
                out.insert((pool.code, txid, index), lock);
            }
        }
    }
    Ok(out)
}

fn read_ledger(conn: &Connection) -> Result<BTreeSet<NoteKey>, String> {
    let mut stmt = conn
        .prepare(&format!(
            "SELECT pool, txid, output_index FROM {LEDGER_TABLE}"
        ))
        .map_err(|e| format!("prepare history hold ledger: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, Vec<u8>>(1)?,
                row.get::<_, u32>(2)?,
            ))
        })
        .map_err(|e| format!("read history hold ledger: {e}"))?;
    let mut out = BTreeSet::new();
    for row in rows {
        let (pool, txid, index) = row.map_err(|e| format!("read history hold entry: {e}"))?;
        if let Ok(txid) = <[u8; 32]>::try_from(txid.as_slice()) {
            out.insert((pool, txid, index));
        }
    }
    Ok(out)
}

fn output_ref(key: &NoteKey) -> Option<OutputRef> {
    let pool = pool_for_code(key.0)?;
    Some(OutputRef::new(TxId::from_bytes(key.1), pool.pool, key.2))
}

/// Brings the hold locks in line with the rule. Must run under the wallet
/// write lock. A lock that cannot be taken (another owner holds the note,
/// which already keeps it out of selection) is skipped, and a failure only
/// costs this sweep; the next one retries.
pub(crate) fn sweep(db_path: &str, db: &mut WalletDatabase) -> Result<SweepOutcome, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
    if !is_wallet_sync_db(&conn)? {
        return Ok(SweepOutcome::default());
    }
    ensure_tables(&conn)?;
    seed_verified_once(&conn)?;
    let Some(tip) = db
        .chain_height()
        .map_err(|e| format!("read chain tip for history hold: {e}"))?
    else {
        return Ok(SweepOutcome::default());
    };
    let tip = u32::from(tip);
    let candidates = read_candidates(&conn, tip.saturating_add(1))?;
    let ledger = read_ledger(&conn)?;
    let owner = hold_owner();
    let expiry = BlockHeight::from_u32(tip.saturating_add(LOCK_LEAD_BLOCKS));

    let mut outcome = SweepOutcome::default();
    let mut added = Vec::new();
    for (key, current) in &candidates {
        let Some(output) = output_ref(key) else {
            continue;
        };
        let ours = current.owner.as_deref() == Some(owner.as_bytes().as_slice());
        let lock_expiry = current.expiry.unwrap_or(0);
        // Renewal rewrites the row, so a lock with half its lead left stays.
        if ledger.contains(key) && ours && lock_expiry >= tip.saturating_add(LOCK_LEAD_BLOCKS / 2) {
            outcome.held += 1;
            continue;
        }
        match db.lock_outputs(&[output], owner, expiry) {
            Ok(_) => {
                outcome.held += 1;
                if !ledger.contains(key) {
                    added.push(*key);
                } else if !ours || lock_expiry <= tip {
                    // The lock had lapsed (the tip moved past it while no
                    // sweep ran), so the note counted as spendable until now.
                    outcome.changed = true;
                }
            }
            Err(e) => log::debug!("history hold: note skipped, lock not acquired: {e:?}"),
        }
    }
    let mut released = Vec::new();
    for key in ledger.iter().filter(|key| !candidates.contains_key(key)) {
        if let Some(output) = output_ref(key) {
            if let Err(e) = db.unlock_output(&output, owner) {
                log::warn!("history hold: release failed, retrying next sweep: {e:?}");
                continue;
            }
        }
        released.push(*key);
    }
    if added.is_empty() && released.is_empty() {
        return Ok(outcome);
    }
    // One transaction: a first sweep can add thousands of rows.
    outcome.changed = true;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("begin history hold ledger update: {e}"))?;
    for key in &added {
        tx.execute(
            &format!(
                "INSERT OR IGNORE INTO {LEDGER_TABLE} (pool, txid, output_index)
                 VALUES (?1, ?2, ?3)"
            ),
            params![key.0, key.1.as_slice(), key.2],
        )
        .map_err(|e| format!("record history hold: {e}"))?;
    }
    for key in &released {
        tx.execute(
            &format!(
                "DELETE FROM {LEDGER_TABLE} WHERE pool = ?1 AND txid = ?2 AND output_index = ?3"
            ),
            params![key.0, key.1.as_slice(), key.2],
        )
        .map_err(|e| format!("clear history hold: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("commit history hold ledger update: {e}"))?;
    Ok(outcome)
}

/// Sweeps, logging instead of failing: holding is a safety margin that the
/// next sweep re-establishes, and must never stop a scan or a send.
pub(crate) fn sweep_logged(db_path: &str, db: &mut WalletDatabase, context: &str) -> SweepOutcome {
    match sweep(db_path, db) {
        Ok(outcome) => outcome,
        Err(e) => {
            log::warn!("history hold: sweep at {context} failed: {e}");
            SweepOutcome::default()
        }
    }
}

/// Establishes the hold before the first balance read of a session, so a
/// wallet upgraded mid-restore never shows held notes as spendable.
pub(crate) fn prepare(db_path: &str, network: WalletNetwork) {
    let result = with_wallet_db_write_lock("history_hold.prepare", || {
        let mut db = super::open_wallet_db(db_path, network)?;
        sweep(db_path, &mut db)
    });
    if let Err(e) = result {
        log::warn!("history hold: startup sweep failed: {e}");
    }
}

/// Held Orchard outputs, for selectors that bypass output locks.
pub(crate) fn held_orchard_outputs(db_path: &str) -> Result<BTreeSet<([u8; 32], u32)>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
    if !table_exists(&conn, LEDGER_TABLE)? {
        return Ok(BTreeSet::new());
    }
    Ok(read_ledger(&conn)?
        .into_iter()
        .filter(|(pool, _, _)| *pool == 3)
        .map(|(_, txid, index)| (txid, index))
        .collect())
}

#[cfg(test)]
mod restore_tests;

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::data_api::{
        wallet::input_selection::{LockFilter, LockedInputPolicy},
        WalletWrite,
    };
    use zcash_protocol::ShieldedPool;

    const NETWORK: WalletNetwork = WalletNetwork::Test;
    const NOTE_VALUE: i64 = 100_000;

    struct Fixture {
        _dir: tempfile::TempDir,
        path: String,
        account_uuid: String,
    }

    impl Fixture {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let path = dir.path().join("wallet.db").to_str().unwrap().to_string();
            let seed =
                crate::wallet::keys::mnemonic_to_seed(&crate::wallet::keys::generate_mnemonic())
                    .unwrap();
            let (account_uuid, _) = crate::wallet::keys::init_db_and_create_account(
                &path,
                NETWORK,
                &seed,
                Some(2_000_000),
                "test",
            )
            .unwrap();
            let mut db = super::super::open_wallet_db(&path, NETWORK).unwrap();
            db.update_chain_tip(BlockHeight::from_u32(2_000_010))
                .unwrap();
            let conn = Connection::open(&path).unwrap();
            ensure_tables(&conn).unwrap();
            conn.execute(
                "INSERT INTO ext_vizor_sync_meta (key, value) VALUES ('sync_in_progress', '1')",
                [],
            )
            .unwrap();
            Self {
                _dir: dir,
                path,
                account_uuid,
            }
        }

        fn conn(&self) -> Connection {
            Connection::open(&self.path).unwrap()
        }

        /// Replaces the scan queue with one range.
        fn set_queue(&self, start: u32, end: u32, priority: i64) {
            let conn = self.conn();
            conn.execute("DELETE FROM scan_queue", []).unwrap();
            conn.execute(
                "INSERT INTO scan_queue (block_range_start, block_range_end, priority)
                 VALUES (?1, ?2, ?3)",
                params![start, end, priority],
            )
            .unwrap();
        }

        /// A stabilized Sapling note mined at `height`; returns its txid.
        fn add_note(&self, txid_byte: u8, height: u32) -> [u8; 32] {
            let conn = self.conn();
            let txid = [txid_byte; 32];
            conn.execute(
                "INSERT INTO transactions (txid, mined_height, min_observed_height)
                 VALUES (?1, ?2, ?2)",
                params![txid.as_slice(), height],
            )
            .unwrap();
            let tx_id = conn.last_insert_rowid();
            let account_id: i64 = conn
                .query_row("SELECT id FROM accounts LIMIT 1", [], |row| row.get(0))
                .unwrap();
            conn.execute(
                "INSERT INTO sapling_received_notes (
                     transaction_id, output_index, account_id, diversifier, value, rcm,
                     nf, is_change, commitment_tree_position, recipient_key_scope,
                     witness_stabilized
                 ) VALUES (?1, 0, ?2, ?3, ?4, ?5, ?6, 0, ?7, 0, 1)",
                params![
                    tx_id,
                    account_id,
                    [0u8; 11].as_slice(),
                    NOTE_VALUE,
                    [0u8; 32].as_slice(),
                    [txid_byte; 32].as_slice(),
                    i64::from(txid_byte),
                ],
            )
            .unwrap();
            txid
        }

        /// Gives the fixture notes what Zakura needs to return them as
        /// spendable: a block and a diversifier valid for the account.
        fn make_selectable(&self) {
            use zcash_client_backend::data_api::{Account as _, WalletRead as _};
            let db = super::super::open_wallet_db(&self.path, NETWORK).unwrap();
            let id = crate::wallet::keys::parse_account_uuid(&self.account_uuid).unwrap();
            let account = db.get_account(id).unwrap().unwrap();
            let diversifier = account
                .ufvk()
                .unwrap()
                .sapling()
                .unwrap()
                .default_address()
                .1
                .diversifier()
                .0;
            let conn = self.conn();
            conn.execute(
                "INSERT OR IGNORE INTO blocks (height, hash, time, sapling_tree)
                 SELECT mined_height, x'00', 0, x'00' FROM transactions",
                [],
            )
            .unwrap();
            conn.execute("UPDATE transactions SET block = mined_height", [])
                .unwrap();
            conn.execute(
                "UPDATE sapling_received_notes SET diversifier = ?1",
                params![diversifier.as_slice()],
            )
            .unwrap();
        }

        fn selectable(&self, txid: &TxId, filter: LockFilter<'_>) -> bool {
            use zcash_client_backend::data_api::{wallet::TargetHeight, InputSource as _};
            let db = super::super::open_wallet_db(&self.path, NETWORK).unwrap();
            db.get_spendable_note(
                txid,
                ShieldedPool::Sapling,
                0,
                TargetHeight::from(BlockHeight::from_u32(2_000_011)),
                filter,
            )
            .unwrap()
            .is_some()
        }

        /// Ordinary sends exclude every locked output.
        fn selectable_by_sends(&self, txid: &TxId) -> bool {
            self.selectable(txid, LockFilter::Policy(&LockedInputPolicy::Exclude))
        }

        fn selectable_unfiltered(&self, txid: &TxId) -> bool {
            self.selectable(txid, LockFilter::Unfiltered)
        }

        fn verify_all(&self) {
            self.conn()
                .execute(
                    &format!(
                        "INSERT INTO {VERIFIED_TABLE} (account_uuid) SELECT uuid FROM accounts"
                    ),
                    [],
                )
                .unwrap();
        }

        /// Records a spend of every fixture note by one transaction.
        fn add_spend(&self, mined_height: Option<u32>, expiry_height: u32) {
            let conn = self.conn();
            conn.execute(
                "INSERT INTO transactions (txid, block, mined_height, expiry_height, min_observed_height)
                 VALUES (?1, NULL, ?2, ?3, 2_000_003)",
                params![[9u8; 32].as_slice(), mined_height, expiry_height],
            )
            .unwrap();
            let spend_tx = conn.last_insert_rowid();
            conn.execute(
                "INSERT INTO sapling_received_note_spends (sapling_received_note_id, transaction_id)
                 SELECT id, ?1 FROM sapling_received_notes",
                params![spend_tx],
            )
            .unwrap();
        }

        fn sweep(&self) -> SweepOutcome {
            let mut db = super::super::open_wallet_db(&self.path, NETWORK).unwrap();
            sweep(&self.path, &mut db).unwrap()
        }

        fn lock_owner_of(&self, txid: [u8; 32]) -> Option<Vec<u8>> {
            self.conn()
                .query_row(
                    "SELECT rn.lock_owner FROM sapling_received_notes rn
                     JOIN transactions t ON t.id_tx = rn.transaction_id
                     WHERE t.txid = ?1",
                    params![txid.as_slice()],
                    |row| row.get(0),
                )
                .unwrap()
        }

        fn held_sapling(&self) -> u64 {
            let uuid = crate::wallet::keys::parse_account_uuid(&self.account_uuid).unwrap();
            super::super::held_value::by_account(&self.path)
                .unwrap()
                .get(uuid.expose_uuid().as_bytes())
                .map_or(0, |held| held.history_hold.sapling)
        }
    }

    #[test]
    fn a_gift_card_claim_wallet_is_never_held() {
        let fixture = Fixture::new();
        // The wallet sync never runs on a claim DB, so it has no sync start.
        fixture
            .conn()
            .execute(
                "DELETE FROM ext_vizor_sync_meta WHERE key = 'sync_in_progress'",
                [],
            )
            .unwrap();
        let txid = fixture.add_note(1, 2_000_002);
        fixture.set_queue(2_000_005, 2_000_011, 20);

        assert_eq!(fixture.sweep(), SweepOutcome::default());
        assert!(fixture.lock_owner_of(txid).is_none());
    }

    #[test]
    fn a_held_note_is_not_selectable_by_sends_until_released() {
        let fixture = Fixture::new();
        let txid = TxId::from_bytes(fixture.add_note(1, 2_000_002));
        fixture.make_selectable();
        fixture.set_queue(2_000_005, 2_000_011, 20);
        assert!(fixture.selectable_by_sends(&txid));

        fixture.sweep();
        assert!(!fixture.selectable_by_sends(&txid));
        assert!(fixture.selectable_unfiltered(&txid));

        fixture.set_queue(2_000_005, 2_000_011, SCANNED_PRIORITY);
        fixture.sweep();
        assert!(fixture.selectable_by_sends(&txid));
    }

    #[test]
    fn a_note_below_pending_history_is_held_until_that_history_is_scanned() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_002);
        fixture.set_queue(2_000_005, 2_000_011, 20);

        let outcome = fixture.sweep();
        assert_eq!(
            outcome,
            SweepOutcome {
                held: 1,
                changed: true
            }
        );
        assert_eq!(
            fixture.lock_owner_of(txid),
            Some(hold_owner().as_bytes().to_vec())
        );
        assert_eq!(fixture.held_sapling(), NOTE_VALUE as u64);

        // A second sweep renews the lock without reporting a change.
        assert_eq!(
            fixture.sweep(),
            SweepOutcome {
                held: 1,
                changed: false
            }
        );

        fixture.set_queue(2_000_005, 2_000_011, SCANNED_PRIORITY);
        assert_eq!(
            fixture.sweep(),
            SweepOutcome {
                held: 0,
                changed: true
            }
        );
        assert_eq!(fixture.lock_owner_of(txid), None);
        assert_eq!(fixture.held_sapling(), 0);
    }

    #[test]
    fn history_below_the_note_does_not_hold_it() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_008);
        // Pending blocks end right after the note's own block: no block above
        // it is unscanned.
        fixture.set_queue(2_000_000, 2_000_009, 20);
        assert_eq!(fixture.sweep().held, 0);
        assert_eq!(fixture.lock_owner_of(txid), None);
    }

    #[test]
    fn verified_accounts_are_not_held_for_pending_history() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_002);
        fixture.set_queue(2_000_005, 2_000_011, 50);
        let conn = fixture.conn();
        ensure_tables(&conn).unwrap();
        conn.execute(
            &format!("INSERT INTO {VERIFIED_TABLE} (account_uuid) SELECT uuid FROM accounts"),
            [],
        )
        .unwrap();
        assert_eq!(fixture.sweep().held, 0);
        assert_eq!(fixture.lock_owner_of(txid), None);
    }

    #[test]
    fn a_rewound_expired_spend_holds_even_a_verified_note() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_002);
        // The rewind re-queued the blocks from 2_000_003 at the chain tip.
        fixture.set_queue(2_000_003, 2_000_011, 50);
        fixture.verify_all();
        fixture.add_spend(None, 2_000_004);
        assert_eq!(fixture.sweep().held, 1);
        assert_eq!(
            fixture.lock_owner_of(txid),
            Some(hold_owner().as_bytes().to_vec())
        );
    }

    #[test]
    fn an_expired_spend_cannot_hide_in_blocks_after_its_expiry() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_002);
        fixture.set_queue(2_000_005, 2_000_011, 50);
        fixture.verify_all();
        fixture.add_spend(None, 2_000_004);
        assert_eq!(fixture.sweep().held, 0);
        assert!(fixture.lock_owner_of(txid).is_none());
    }

    #[test]
    fn tip_ranges_hold_an_unverified_account() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_002);
        for priority in [50, 60] {
            fixture.set_queue(2_000_005, 2_000_011, priority);
            assert_eq!(fixture.sweep().held, 1, "priority {priority}");
            assert_eq!(
                fixture.lock_owner_of(txid),
                Some(hold_owner().as_bytes().to_vec())
            );
        }
        fixture.set_queue(2_000_005, 2_000_011, SCANNED_PRIORITY);
        assert_eq!(fixture.sweep().held, 0);
        assert!(fixture.lock_owner_of(txid).is_none());
    }

    #[test]
    fn a_note_spent_by_a_mined_transaction_is_not_held() {
        let fixture = Fixture::new();
        fixture.add_note(1, 2_000_002);
        fixture.set_queue(2_000_005, 2_000_011, 20);
        fixture.add_spend(Some(2_000_003), 2_000_040);
        assert_eq!(fixture.sweep().held, 0);
    }

    #[test]
    fn a_lapsed_lock_held_again_reports_a_change() {
        let fixture = Fixture::new();
        fixture.add_note(1, 2_000_002);
        fixture.set_queue(2_000_005, 2_000_011, 20);
        assert!(fixture.sweep().changed);
        assert!(!fixture.sweep().changed);
        // The tip moved past the lock while nothing swept.
        fixture
            .conn()
            .execute(
                "UPDATE sapling_received_notes SET lock_expiry_height = 2_000_005",
                [],
            )
            .unwrap();
        let outcome = fixture.sweep();
        assert_eq!(outcome.held, 1);
        assert!(outcome.changed);
    }

    #[test]
    fn accounts_born_after_pending_history_are_verified() {
        let fixture = Fixture::new();
        let mut conn = fixture.conn();
        // History below the 2_000_000 birthday is still pending.
        fixture.set_queue(1_800_000, 1_900_000, 20);
        let tx = conn.transaction().unwrap();
        mark_verified_accounts(&tx).unwrap();
        tx.commit().unwrap();
        let verified: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {VERIFIED_TABLE}"),
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(verified, 1);
    }

    #[test]
    fn a_note_locked_by_another_owner_is_skipped_and_left_alone() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_002);
        let other = fixture.add_note(2, 2_000_003);
        fixture.set_queue(2_000_005, 2_000_011, 20);
        let foreign = LockOwner::new([7; 32]);
        let mut db = super::super::open_wallet_db(&fixture.path, NETWORK).unwrap();
        db.lock_outputs(
            &[OutputRef::new(
                TxId::from_bytes(other),
                PoolType::SAPLING,
                0,
            )],
            foreign,
            BlockHeight::from_u32(2_000_100),
        )
        .unwrap();
        drop(db);

        assert_eq!(fixture.sweep().held, 1);
        assert_eq!(
            fixture.lock_owner_of(txid),
            Some(hold_owner().as_bytes().to_vec())
        );
        assert_eq!(
            fixture.lock_owner_of(other),
            Some(foreign.as_bytes().to_vec())
        );

        // Release never touches the foreign lock.
        fixture.set_queue(2_000_005, 2_000_011, SCANNED_PRIORITY);
        fixture.sweep();
        assert_eq!(
            fixture.lock_owner_of(other),
            Some(foreign.as_bytes().to_vec())
        );
    }

    #[test]
    fn hold_locks_lapse_when_sweeps_stop() {
        let fixture = Fixture::new();
        let txid = fixture.add_note(1, 2_000_002);
        fixture.set_queue(2_000_005, 2_000_011, 20);
        fixture.sweep();
        let expiry: u32 = fixture
            .conn()
            .query_row(
                "SELECT lock_expiry_height FROM sapling_received_notes",
                [],
                |row| row.get(0),
            )
            .unwrap();
        // An older build that never sweeps sees the lock lapse after the lead.
        assert_eq!(expiry, 2_000_010 + LOCK_LEAD_BLOCKS);
        assert!(fixture.lock_owner_of(txid).is_some());
    }

    #[test]
    fn upgraded_completed_wallets_start_verified() {
        let fixture = Fixture::new();
        let conn = fixture.conn();
        ensure_tables(&conn).unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO ext_vizor_sync_meta (key, value) VALUES
                 ('last_completed_sync_height', '2000010'), ('sync_in_progress', '0')",
            [],
        )
        .unwrap();
        fixture.set_queue(2_000_009, 2_000_011, 50);
        seed_verified_once(&conn).unwrap();
        let verified: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {VERIFIED_TABLE}"),
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(verified, 1);
    }

    #[test]
    fn an_interrupted_sync_after_completion_still_starts_verified() {
        let fixture = Fixture::new();
        let conn = fixture.conn();
        conn.execute(
            "INSERT OR REPLACE INTO ext_vizor_sync_meta (key, value) VALUES
                 ('last_completed_sync_height', '2000010'), ('sync_in_progress', '1')",
            [],
        )
        .unwrap();
        fixture.set_queue(2_000_009, 2_000_011, 50);
        seed_verified_once(&conn).unwrap();
        let verified: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {VERIFIED_TABLE}"),
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(verified, 1);
    }

    #[test]
    fn a_wallet_mid_restore_does_not_start_verified() {
        let fixture = Fixture::new();
        let conn = fixture.conn();
        ensure_tables(&conn).unwrap();
        fixture.set_queue(2_000_000, 2_000_011, 20);
        seed_verified_once(&conn).unwrap();
        let verified: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {VERIFIED_TABLE}"),
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(verified, 0);
    }

    #[test]
    fn held_orchard_outputs_lists_only_orchard_holds() {
        let fixture = Fixture::new();
        let conn = fixture.conn();
        ensure_tables(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {LEDGER_TABLE} (pool, txid, output_index) VALUES
                     (2, ?1, 0), (3, ?2, 1)"
            ),
            params![[1u8; 32].as_slice(), [2u8; 32].as_slice()],
        )
        .unwrap();
        let held = held_orchard_outputs(&fixture.path).unwrap();
        assert_eq!(held.into_iter().collect::<Vec<_>>(), vec![([2u8; 32], 1)]);
    }
}
