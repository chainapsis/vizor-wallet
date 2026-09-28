//! Durable bookkeeping for owner-scoped locks held by in-memory send proposals.
//!
//! `PROPOSAL_STORE` deliberately remains process-local, but the wallet locks it
//! owns live in SQLite. This side table records enough generic `OutputRef`
//! information to release locks left by a previous process without touching
//! long-lived migration owners.

use std::collections::BTreeMap;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    LazyLock,
};

use rand::{rngs::OsRng, RngCore};
use rusqlite::{params, Connection};
use zcash_client_backend::{
    data_api::OutputLockStore,
    wallet::{LockOwner, OutputRef},
};
use zcash_primitives::transaction::TxId;
use zcash_protocol::{consensus::BlockHeight, PoolType, ShieldedPool};

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

use super::open_wallet_db;

const TABLE: &str = "vizor_send_proposal_locks";
// Kept only on the wallet-owned PCZT, never the device signer view.
pub(crate) const OWNER_KEY: &str = "vizor:send-lock-owner-v1";
static SHUTTING_DOWN: AtomicBool = AtomicBool::new(false);

pub(crate) fn is_shutting_down() -> bool {
    SHUTTING_DOWN.load(Ordering::Acquire)
}

pub(crate) fn require_active_session() -> Result<(), String> {
    if is_shutting_down() {
        Err("Wallet is shutting down; signing request was cancelled".into())
    } else {
        Ok(())
    }
}

pub(crate) fn begin_shutdown() {
    SHUTTING_DOWN.store(true, Ordering::Release);
}

pub(crate) fn bind_pczt(pczt: pczt::Pczt, owner: LockOwner) -> pczt::Pczt {
    pczt::roles::updater::Updater::new(pczt)
        .update_global_with(|mut global| {
            global.set_proprietary(OWNER_KEY.into(), owner.as_bytes().to_vec());
        })
        .finish()
}

pub(crate) fn pczt_owner(bytes: &[u8]) -> Result<Option<LockOwner>, String> {
    let pczt = pczt::Pczt::parse(bytes).map_err(|e| format!("Read PCZT reservation: {e:?}"))?;
    pczt.global()
        .proprietary()
        .get(OWNER_KEY)
        .map(|bytes| {
            let owner: [u8; 32] = bytes
                .as_slice()
                .try_into()
                .map_err(|_| "Invalid PCZT reservation owner".to_string())?;
            Ok(LockOwner::new(owner))
        })
        .transpose()
}

static PROCESS_SESSION_ID: LazyLock<[u8; 16]> = LazyLock::new(|| {
    let mut bytes = [0; 16];
    OsRng.fill_bytes(&mut bytes);
    bytes
});

fn pool_code(pool: PoolType) -> i64 {
    match pool {
        PoolType::Transparent => 0,
        PoolType::Shielded(ShieldedPool::Sapling) => 2,
        PoolType::Shielded(ShieldedPool::Orchard) => 3,
        PoolType::Shielded(ShieldedPool::Ironwood) => 4,
    }
}

fn pool_from_code(code: i64) -> Result<PoolType, String> {
    match code {
        0 => Ok(PoolType::TRANSPARENT),
        2 => Ok(PoolType::SAPLING),
        3 => Ok(PoolType::ORCHARD),
        4 => Ok(PoolType::IRONWOOD),
        _ => Err(format!("Unknown persisted send lock pool code {code}")),
    }
}

pub(crate) fn ensure_schema(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "CREATE TABLE IF NOT EXISTS {TABLE} (
            owner BLOB NOT NULL,
            session_id BLOB NOT NULL,
            txid BLOB NOT NULL,
            pool INTEGER NOT NULL,
            output_index INTEGER NOT NULL,
            expiry_height INTEGER NOT NULL,
            retain_until_expiry INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (owner, txid, pool, output_index)
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_send_proposal_locks_session
            ON {TABLE}(session_id, retain_until_expiry);"
    ))
    .map_err(|e| format!("Initialize send proposal lock recovery schema: {e}"))?;
    // A legacy retained row might already have reached the network. Never
    // infer that it is an abandoned signing request during upgrade.
    let columns = conn
        .prepare(&format!("PRAGMA table_info({TABLE})"))
        .map_err(|e| e.to_string())?
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    for (name, definition) in [
        ("phase", "TEXT NOT NULL DEFAULT 'legacy'"),
        ("operation_id", "TEXT"),
    ] {
        if !columns.iter().any(|column| column == name) {
            conn.execute_batch(&format!(
                "ALTER TABLE {TABLE} ADD COLUMN {name} {definition}"
            ))
            .map_err(|e| format!("Upgrade send reservation schema: {e}"))?;
        }
    }
    Ok(())
}

pub(crate) fn persist(
    db_path: &str,
    owner: LockOwner,
    outputs: &[OutputRef],
    expiry_height: BlockHeight,
) -> Result<(), String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .transaction()
        .map_err(|e| format!("Begin send proposal lock persistence: {e}"))?;
    for output in outputs {
        tx.execute(
            &format!(
                "INSERT OR REPLACE INTO {TABLE}
                    (owner, session_id, txid, pool, output_index, expiry_height,
                     retain_until_expiry, phase)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, 'session')"
            ),
            params![
                owner.as_bytes().as_slice(),
                PROCESS_SESSION_ID.as_slice(),
                output.txid().as_ref(),
                pool_code(output.pool()),
                output.output_index(),
                u32::from(expiry_height),
            ],
        )
        .map_err(|e| format!("Persist send proposal input lock: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit send proposal lock persistence: {e}"))
}

pub(crate) fn remove(db_path: &str, owner: LockOwner) -> Result<(), String> {
    remove_with_timeout(db_path, owner, READ_DB_BUSY_TIMEOUT)
}

pub(super) fn remove_with_timeout(
    db_path: &str,
    owner: LockOwner,
    timeout: std::time::Duration,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, timeout)?;
    ensure_schema(&conn)?;
    conn.execute(
        &format!("DELETE FROM {TABLE} WHERE owner = ?1"),
        params![owner.as_bytes().as_slice()],
    )
    .map_err(|e| format!("Remove send proposal lock recovery rows: {e}"))?;
    Ok(())
}

pub(super) fn mark_retain_until_expiry(db_path: &str, owner: LockOwner) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {TABLE}
             SET retain_until_expiry = 1, phase = CASE WHEN phase = 'signed' THEN phase ELSE 'broadcast' END
             WHERE owner = ?1"
            ),
            params![owner.as_bytes().as_slice()],
        )
        .map_err(|e| format!("Retain send proposal lock until expiry: {e}"))?;
    if updated == 0 {
        return Err("Send proposal lock recovery row no longer exists".to_string());
    }
    Ok(())
}

/// Caller holds the wallet write lock and the same SQLite transaction that
/// inserts the signed outbox row. A stale PCZT cannot resurrect a released owner.
pub(crate) fn checkpoint_owner(
    conn: &Connection,
    owner: LockOwner,
    operation_id: &str,
) -> Result<(), String> {
    require_active_session()?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {TABLE} SET retain_until_expiry = 1, phase = 'signed', operation_id = ?2
         WHERE owner = ?1 AND session_id = ?3 AND phase = 'session'"
            ),
            params![
                owner.as_bytes().as_slice(),
                operation_id,
                PROCESS_SESSION_ID.as_slice()
            ],
        )
        .map_err(|e| format!("Transfer signed reservation: {e}"))?;
    if updated == 0 {
        return Err("Signing reservation was cancelled or already transferred".into());
    }
    Ok(())
}

/// Must be committed with removal/terminalization of the outbox operation.
pub(crate) fn release_operation(conn: &Connection, operation_id: &str) -> Result<(), String> {
    ensure_schema(conn)?;
    conn.execute(
        &format!(
            "UPDATE {TABLE} SET retain_until_expiry = 0, phase = 'release'
         WHERE operation_id = ?1"
        ),
        params![operation_id],
    )
    .map_err(|e| format!("Release completed reservation: {e}"))?;
    Ok(())
}

#[cfg(test)]
pub(super) fn is_durable(db_path: &str, owner: LockOwner) -> Result<bool, String> {
    is_durable_with_timeout(db_path, owner, READ_DB_BUSY_TIMEOUT)
}

pub(super) fn is_durable_with_timeout(
    db_path: &str,
    owner: LockOwner,
    timeout: std::time::Duration,
) -> Result<bool, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, timeout)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!(
        "SELECT EXISTS(SELECT 1 FROM {TABLE} WHERE owner = ?1 AND phase IN ('signed', 'broadcast'))"
    ),
        params![owner.as_bytes().as_slice()],
        |row| row.get(0),
    )
    .map_err(|e| format!("Read reservation ownership: {e}"))
}

pub(super) fn update_expiry(
    db_path: &str,
    owner: LockOwner,
    expiry_height: BlockHeight,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {TABLE}
                 SET expiry_height = ?2
                 WHERE owner = ?1"
            ),
            params![owner.as_bytes().as_slice(), u32::from(expiry_height),],
        )
        .map_err(|e| format!("Update persisted send proposal lock expiry: {e}"))?;
    if updated == 0 {
        return Err("Send proposal lock recovery row no longer exists".to_string());
    }
    Ok(())
}

fn read_previous_session_locks(
    conn: &Connection,
) -> Result<BTreeMap<LockOwner, (u32, bool, Vec<OutputRef>)>, String> {
    ensure_schema(conn)?;
    let mut stmt = conn
        .prepare(&format!(
            "SELECT owner, txid, pool, output_index, expiry_height,
                    retain_until_expiry
             FROM {TABLE}
             WHERE session_id <> ?1 OR phase = 'release'
             ORDER BY owner, txid, pool, output_index"
        ))
        .map_err(|e| format!("Prepare orphan send lock recovery query: {e}"))?;
    let rows = stmt
        .query_map(params![PROCESS_SESSION_ID.as_slice()], |row| {
            Ok((
                row.get::<_, Vec<u8>>(0)?,
                row.get::<_, Vec<u8>>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, u32>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, bool>(5)?,
            ))
        })
        .map_err(|e| format!("Query orphan send locks: {e}"))?;

    let mut locks = BTreeMap::new();
    for row in rows {
        let (owner_bytes, txid_bytes, pool, output_index, expiry, retain) =
            row.map_err(|e| format!("Read orphan send lock: {e}"))?;
        let owner = LockOwner::new(
            owner_bytes
                .try_into()
                .map_err(|_| "Persisted send lock owner is not 32 bytes")?,
        );
        let txid = TxId::from_bytes(
            txid_bytes
                .try_into()
                .map_err(|_| "Persisted send lock txid is not 32 bytes")?,
        );
        let entry = locks
            .entry(owner)
            .or_insert_with(|| (expiry, retain, Vec::new()));
        if entry.0 != expiry || entry.1 != retain {
            return Err("Persisted send lock owner has inconsistent metadata".to_string());
        }
        entry
            .2
            .push(OutputRef::new(txid, pool_from_code(pool)?, output_index));
    }
    Ok(locks)
}

fn should_release_after_restart(
    retain_until_expiry: bool,
    target_height: Option<u32>,
    expiry_height: u32,
) -> bool {
    !retain_until_expiry || target_height.is_some_and(|height| height >= expiry_height)
}

/// Releases only recoverable send locks left by an earlier process. Migration
/// locks are never registered in this table and therefore cannot be cleared by
/// this recovery pass. Ambiguous-broadcast locks remain until their recorded
/// expiry height has passed.
pub(crate) fn recover_previous_process(
    db_path: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    recover(db_path, network, true)
}

/// Offline startup recovery, before the first balance snapshot. Retained and
/// legacy locks are deliberately left to height-aware sync recovery.
pub(crate) fn recover_before_balance(db_path: &str, network: WalletNetwork) -> Result<(), String> {
    recover(db_path, network, false)
}

fn recover(db_path: &str, network: WalletNetwork, check_expiry: bool) -> Result<(), String> {
    with_wallet_db_write_lock("proposal_locks.recover_previous_process", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        let locks = read_previous_session_locks(&conn)?;
        if locks.is_empty() {
            return Ok(());
        }
        drop(conn);

        let mut db = open_wallet_db(db_path, network)?;
        let target_height = if check_expiry {
            super::wallet_target_height(&db)
                .map_err(|e| format!("Read target height for send lock recovery: {e}"))?
                .map(u32::from)
        } else {
            None
        };

        let mut owners_to_remove = Vec::new();
        for (owner, (expiry, retain, outputs)) in locks {
            if !should_release_after_restart(retain, target_height, expiry) {
                continue;
            }
            for output in &outputs {
                db.unlock_output(output, owner)
                    .map_err(|e| format!("Release orphan send proposal input: {e}"))?;
            }
            owners_to_remove.push(owner);
        }
        drop(db);

        let mut conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        ensure_schema(&conn)?;
        let tx = conn
            .transaction()
            .map_err(|e| format!("Begin orphan send lock cleanup: {e}"))?;
        for owner in owners_to_remove {
            tx.execute(
                &format!("DELETE FROM {TABLE} WHERE owner = ?1"),
                params![owner.as_bytes().as_slice()],
            )
            .map_err(|e| format!("Delete recovered send lock rows: {e}"))?;
        }
        tx.commit()
            .map_err(|e| format!("Commit orphan send lock cleanup: {e}"))?;
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::data_api::WalletRead;

    fn seed_reservation(db_path: &str, owner: LockOwner) {
        persist(
            db_path,
            owner,
            &[OutputRef::new(
                TxId::from_bytes([9; 32]),
                PoolType::ORCHARD,
                0,
            )],
            BlockHeight::from_u32(100),
        )
        .unwrap();
    }

    #[test]
    fn checkpoint_transfer_rolls_back_with_the_outbox_transaction() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let owner = LockOwner::new([1; 32]);
        seed_reservation(path, owner);
        let mut conn = Connection::open(path).unwrap();
        {
            let tx = conn.transaction().unwrap();
            checkpoint_owner(&tx, owner, "ledger-op").unwrap();
            // Simulate a later outbox INSERT failure / interrupted commit.
        }
        assert!(!is_durable(path, owner).unwrap());
        {
            let tx = conn.transaction().unwrap();
            checkpoint_owner(&tx, owner, "ledger-op").unwrap();
            tx.commit().unwrap();
        }
        assert!(is_durable(path, owner).unwrap());
        assert!(checkpoint_owner(&conn, owner, "different-op").is_err());
    }

    #[test]
    fn cancelled_or_previous_session_pczt_cannot_be_checkpointed() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let owner = LockOwner::new([2; 32]);
        seed_reservation(path, owner);
        let conn = Connection::open(path).unwrap();
        conn.execute(&format!("UPDATE {TABLE} SET session_id = zeroblob(16)"), [])
            .unwrap();
        assert!(checkpoint_owner(&conn, owner, "old-op").is_err());
        remove(path, owner).unwrap();
        assert!(checkpoint_owner(&conn, owner, "cancelled-op").is_err());
    }

    #[test]
    fn offline_restart_releases_real_inputs_but_preserves_durable_and_foreign_owners() {
        use transparent::bundle::{OutPoint, TxOut};
        use zcash_client_backend::{data_api::WalletWrite, wallet::WalletTransparentOutput};
        use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest};
        use zcash_protocol::value::Zatoshis;

        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Test;
        let seed = crate::wallet::keys::mnemonic_to_seed(&crate::wallet::keys::generate_mnemonic())
            .unwrap();
        let (uuid, _) = crate::wallet::keys::init_db_and_create_account(
            path,
            network,
            &seed,
            Some(2_000_000),
            "test",
        )
        .unwrap();
        let account = crate::wallet::keys::parse_account_uuid(&uuid).unwrap();
        let mut db = open_wallet_db(path, network).unwrap();
        db.update_chain_tip(BlockHeight::from_u32(2_000_010))
            .unwrap();
        let request = UnifiedAddressRequest::custom(
            ReceiverRequirement::Require,
            ReceiverRequirement::Require,
            ReceiverRequirement::Require,
        )
        .unwrap();
        let address = *db
            .get_last_generated_address_matching(account, request)
            .unwrap()
            .unwrap()
            .transparent()
            .unwrap();
        let expiry = BlockHeight::from_u32(2_000_100);
        let owners: Vec<_> = (1..=5).map(|n| LockOwner::new([n; 32])).collect();
        for (index, owner) in owners.iter().enumerate() {
            let txid = [index as u8 + 1; 32];
            let output = OutputRef::new(TxId::from_bytes(txid), PoolType::TRANSPARENT, 0);
            let utxo = WalletTransparentOutput::from_parts(
                OutPoint::new(txid, 0),
                TxOut::new(Zatoshis::const_from_u64(100_000), address.script().into()),
                Some(BlockHeight::from_u32(2_000_001)),
                None,
                None,
                None,
            )
            .unwrap();
            db.put_received_transparent_utxo(&utxo).unwrap();
            db.lock_outputs(std::slice::from_ref(&output), *owner, expiry)
                .unwrap();
            if index != 4 {
                persist(path, *owner, &[output], expiry).unwrap();
            }
        }
        drop(db);
        // Session 1 = abandoned approval, 2 = signed, 3 = submitted,
        // 4 = still-live current process, 5 = unrelated migration owner.
        let conn = Connection::open(path).unwrap();
        checkpoint_owner(&conn, owners[1], "signed-op").unwrap();
        mark_retain_until_expiry(path, owners[2]).unwrap();
        conn.execute(
            &format!("UPDATE {TABLE} SET session_id = zeroblob(16) WHERE owner <> ?1"),
            params![owners[3].as_bytes().as_slice()],
        )
        .unwrap();
        crate::wallet::keys::ensure_db_migrated_once(path, network).unwrap();
        let locked: Vec<Vec<u8>> = conn.prepare("SELECT lock_owner FROM transparent_received_outputs WHERE lock_owner IS NOT NULL ORDER BY lock_owner").unwrap().query_map([], |row| row.get(0)).unwrap().collect::<Result<_, _>>().unwrap();
        assert_eq!(
            locked,
            owners[1..]
                .iter()
                .map(|owner| owner.as_bytes().to_vec())
                .collect::<Vec<_>>()
        );
        // Same-process completed outbox reservations are also reclaimed.
        release_operation(&conn, "signed-op").unwrap();
        recover_before_balance(path, network).unwrap();
        let count: u32 = conn
            .query_row(
                "SELECT COUNT(*) FROM transparent_received_outputs WHERE lock_owner IS NOT NULL",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(count, 3);
        // Re-running before any network request is idempotent.
        recover_before_balance(path, network).unwrap();
    }

    #[test]
    fn shutdown_drains_creators_and_keeps_durable_reservations() {
        // The exit gate is deliberately process-lifetime. Isolate it from the
        // parallel Rust suite instead of adding a production reset escape hatch.
        const CHILD: &str = "VIZOR_RESERVATION_SHUTDOWN_TEST_CHILD";
        if std::env::var_os(CHILD).is_none() {
            for mode in ["drain", "timeout"] {
                let result = std::process::Command::new(std::env::current_exe().unwrap())
                    .args(["--exact", "wallet::sync::proposal_locks::tests::shutdown_drains_creators_and_keeps_durable_reservations", "--nocapture"])
                    .env(CHILD, mode).output().unwrap();
                assert!(
                    result.status.success(),
                    "{mode}: {}\n{}",
                    String::from_utf8_lossy(&result.stdout),
                    String::from_utf8_lossy(&result.stderr)
                );
            }
            return;
        }
        let timeout = std::env::var(CHILD).unwrap() == "timeout";
        use super::super::{StoredProposalLock, PROPOSAL_STORE};
        use transparent::{
            address::TransparentAddress,
            bundle::{OutPoint, TxOut},
        };
        use zcash_client_backend::{
            data_api::wallet::ConfirmationsPolicy,
            fees::TransactionBalance,
            proposal::Proposal,
            wallet::WalletTransparentOutput,
            zip321::{Payment, TransactionRequest},
        };
        use zcash_keys::address::Address;
        use zcash_protocol::value::Zatoshis;
        let directory = tempfile::tempdir().unwrap();
        let path = directory
            .path()
            .join("wallet.db")
            .to_str()
            .unwrap()
            .to_owned();
        crate::wallet::keys::ensure_db_initialized(&path, WalletNetwork::Test).unwrap();
        let (entered_tx, entered_rx) = std::sync::mpsc::channel();
        let (continue_tx, continue_rx) = std::sync::mpsc::channel();
        let writer_path = path.clone();
        let creator = std::thread::spawn(move || {
            with_wallet_db_write_lock("test.accepted_creator", || {
                require_active_session().unwrap();
                entered_tx.send(()).unwrap();
                continue_rx.recv().unwrap();
                let address = TransparentAddress::PublicKeyHash([7; 20]);
                let utxo = WalletTransparentOutput::from_parts(
                    OutPoint::new([9; 32], 0),
                    TxOut::new(Zatoshis::const_from_u64(100_000), address.script().into()),
                    Some(BlockHeight::from_u32(1)),
                    None,
                    None,
                    None,
                )
                .unwrap();
                let payment = Payment::new(
                    Address::Transparent(address).to_zcash_address(&WalletNetwork::Test),
                    Some(Zatoshis::const_from_u64(90_000)),
                    None,
                    None,
                    None,
                    vec![],
                )
                .unwrap();
                let proposal = Proposal::single_step(
                    TransactionRequest::new(vec![payment]).unwrap(),
                    BTreeMap::from([(0, PoolType::TRANSPARENT)]),
                    vec![utxo],
                    None,
                    BlockHeight::from_u32(1),
                    TransactionBalance::new(vec![], Zatoshis::const_from_u64(10_000)).unwrap(),
                    super::super::send::ConservativeZip317FeeRule,
                    BlockHeight::from_u32(2).into(),
                    ConfirmationsPolicy::default(),
                    false,
                    false,
                )
                .unwrap();
                for id in 1..=3u64 {
                    let owner = LockOwner::new([id as u8; 32]);
                    seed_reservation(&writer_path, owner);
                    if id != 1 {
                        mark_retain_until_expiry(&writer_path, owner).unwrap();
                    }
                    // Creation has accepted the request but has not registered
                    // it yet when shutdown closes the gate.
                    PROPOSAL_STORE.lock().unwrap().locks.insert(
                        id,
                        StoredProposalLock {
                            proposal: proposal.clone(),
                            network: WalletNetwork::Test,
                            db_path: writer_path.clone(),
                            owner,
                            send_flow_id: format!("flow-{id}"),
                        },
                    );
                }
            });
        });
        entered_rx.recv().unwrap();
        let (finished_tx, finished_rx) = std::sync::mpsc::channel();
        let shutdown = std::thread::spawn(move || {
            finished_tx
                .send(super::super::shutdown_signing_reservations())
                .unwrap();
        });
        while require_active_session().is_ok() {
            std::thread::yield_now();
        }
        if timeout {
            // The creator still owns the write lock and has not registered any
            // proposal. Exit must defer, not mistake that empty store for idle.
            let result = finished_rx
                .recv_timeout(std::time::Duration::from_secs(2))
                .unwrap();
            assert!(result.unwrap_err().contains("deferred"));
        }
        continue_tx.send(()).unwrap();
        creator.join().unwrap();
        shutdown.join().unwrap();
        if !timeout {
            finished_rx.recv().unwrap().unwrap();
        }
        let conn = Connection::open(&path).unwrap();
        if timeout {
            let count: i64 = conn
                .query_row(&format!("SELECT COUNT(*) FROM {TABLE}"), [], |row| {
                    row.get(0)
                })
                .unwrap();
            assert_eq!(
                count, 3,
                "late creator reservations must survive timed-out exit"
            );
            // A fresh process sees a different session id. Exercise exactly its
            // offline recovery path; durable owners must still survive.
            conn.execute(&format!("UPDATE {TABLE} SET session_id = zeroblob(16)"), [])
                .unwrap();
            recover_before_balance(&path, WalletNetwork::Test).unwrap();
        }
        let rows: i64 = conn
            .query_row(&format!("SELECT COUNT(*) FROM {TABLE}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(
            rows, 2,
            "accepted creator must be drained; durable rows must survive"
        );
        assert!(super::super::stored_proposal_lock(2, "flow-2").is_err());
        assert!(checkpoint_owner(&conn, LockOwner::new([1; 32]), "late-signature").is_err());
        super::super::shutdown_signing_reservations().unwrap();

        // A queued FRB sync can clear its ordinary cancel flag after exit.
        // The process-lifetime gate must still reject it before touching a DB.
        tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(crate::wallet::sync_engine::run_sync_inner(
                "must-not-open.db",
                "http://127.0.0.1:1",
                WalletNetwork::Test,
                std::sync::Arc::new(AtomicBool::new(false)),
                1,
                &std::sync::atomic::AtomicU8::new(1),
                None,
                true,
                |_| panic!("a queued sync must not run during shutdown"),
            ))
            .unwrap();

        // An external SQLite writer must not introduce the ordinary 2s/10s
        // busy waits after the process-local write lock has been acquired.
        let owner = LockOwner::new([4; 32]);
        seed_reservation(&path, owner);
        {
            let mut store = PROPOSAL_STORE.lock().unwrap();
            let mut lock = store.locks.get(&2).unwrap().clone();
            lock.owner = owner;
            lock.send_flow_id = "flow-4".into();
            store.locks.insert(4, lock);
        }
        conn.execute_batch("BEGIN IMMEDIATE").unwrap();
        let (result_tx, result_rx) = std::sync::mpsc::channel();
        let blocked_cleanup = std::thread::spawn(move || {
            result_tx
                .send(super::super::shutdown_signing_reservations())
                .unwrap();
        });
        let result = result_rx.recv_timeout(std::time::Duration::from_secs(1));
        conn.execute_batch("ROLLBACK").unwrap();
        blocked_cleanup.join().unwrap();
        assert!(
            result.unwrap().is_err(),
            "busy SQLite cleanup must defer immediately"
        );
        let count: i64 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {TABLE} WHERE owner = ?1"),
                params![owner.as_bytes().as_slice()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(count, 1, "failed cleanup must preserve its recovery record");
    }

    #[test]
    fn legacy_retained_reservations_survive_offline_recovery_policy() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&format!("CREATE TABLE {TABLE} (owner BLOB, session_id BLOB, txid BLOB, pool INTEGER, output_index INTEGER, expiry_height INTEGER, retain_until_expiry INTEGER DEFAULT 0, PRIMARY KEY(owner, txid, pool, output_index)); INSERT INTO {TABLE} VALUES (zeroblob(32), zeroblob(16), zeroblob(32), 3, 0, 100, 1);")).unwrap();
        ensure_schema(&conn).unwrap();
        let phase: String = conn
            .query_row(&format!("SELECT phase FROM {TABLE}"), [], |row| row.get(0))
            .unwrap();
        assert_eq!(phase, "legacy");
        let locks = read_previous_session_locks(&conn).unwrap();
        assert!(!should_release_after_restart(
            locks.values().next().unwrap().1,
            None,
            100
        ));
    }

    #[test]
    fn persisted_pool_codes_round_trip() {
        for pool in [
            PoolType::TRANSPARENT,
            PoolType::SAPLING,
            PoolType::ORCHARD,
            PoolType::IRONWOOD,
        ] {
            assert_eq!(pool_from_code(pool_code(pool)).unwrap(), pool);
        }
    }

    #[test]
    fn current_session_rows_are_not_orphans() {
        let conn = Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {TABLE}
                    (owner, session_id, txid, pool, output_index, expiry_height)
                 VALUES (?1, ?2, ?3, 3, 0, 100)"
            ),
            params![
                [1u8; 32].as_slice(),
                PROCESS_SESSION_ID.as_slice(),
                [2u8; 32].as_slice(),
            ],
        )
        .unwrap();
        assert!(read_previous_session_locks(&conn).unwrap().is_empty());
    }

    #[test]
    fn restart_releases_only_recoverable_or_expired_locks() {
        assert!(should_release_after_restart(false, None, 100));
        assert!(should_release_after_restart(false, Some(50), 100));
        assert!(!should_release_after_restart(true, None, 100));
        assert!(!should_release_after_restart(true, Some(99), 100));
        assert!(should_release_after_restart(true, Some(100), 100));
        assert!(should_release_after_restart(true, Some(101), 100));
    }

    #[test]
    fn hardware_handoff_policy_is_persisted_durably() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let owner = LockOwner::new([7; 32]);
        {
            let conn = Connection::open(&db_path).unwrap();
            ensure_schema(&conn).unwrap();
            conn.execute(
                &format!(
                    "INSERT INTO {TABLE}
                        (owner, session_id, txid, pool, output_index, expiry_height)
                     VALUES (?1, ?2, ?3, 3, 0, 100)"
                ),
                params![
                    owner.as_bytes().as_slice(),
                    PROCESS_SESSION_ID.as_slice(),
                    [9u8; 32].as_slice(),
                ],
            )
            .unwrap();
        }

        mark_retain_until_expiry(db_path.to_str().unwrap(), owner).unwrap();

        let conn = Connection::open(db_path).unwrap();
        let retain: bool = conn
            .query_row(
                &format!("SELECT retain_until_expiry FROM {TABLE} WHERE owner = ?1"),
                params![owner.as_bytes().as_slice()],
                |row| row.get(0),
            )
            .unwrap();
        assert!(retain);
    }

    #[test]
    fn durable_updates_reject_missing_owner() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let owner = LockOwner::new([7; 32]);

        assert!(mark_retain_until_expiry(db_path, owner)
            .unwrap_err()
            .contains("no longer exists"));
        assert!(update_expiry(db_path, owner, BlockHeight::from_u32(100))
            .unwrap_err()
            .contains("no longer exists"));
    }
}
