//! Prepares an event gift from its known funding transaction, without scanning
//! the birthday-to-tip range. Only explicitly identified mined transactions'
//! blocks are processed. Gaps remain unscanned in the wallet database.

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use rusqlite::OptionalExtension;
use tonic::transport::Channel;
use zcash_client_backend::data_api::wallet::input_selection::{LockFilter, LockedInputPolicy};
use zcash_client_backend::data_api::{
    chain::{scan_cached_blocks, ChainState},
    InputSource, TransactionStatus, WalletCommitmentTrees, WalletRead, WalletWrite,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::{BlockHeight, BranchId};
use zcash_protocol::ShieldedPool;

use super::{
    download_scan_batch, get_latest_block, get_tree_state, open_db, open_lwd_channel,
    validate_scan_batch,
};
use crate::wallet::{
    db::open_wallet_raw_conn_with_timeout, db::with_wallet_db_write_lock, db::READ_DB_BUSY_TIMEOUT,
    network::WalletNetwork, transaction_data::payload::get_transaction_payload,
};

pub(crate) struct Preparation {
    pub funding_txid: TxId,
    pub funding_height: BlockHeight,
    pub tip_height: BlockHeight,
}

fn parse_txid(value: &str) -> Result<TxId, String> {
    let mut bytes: [u8; 32] = hex::decode(value)
        .map_err(|_| "Gift Card funding transaction ID is invalid")?
        .try_into()
        .map_err(|_| "Gift Card funding transaction ID is invalid")?;
    bytes.reverse();
    Ok(TxId::from_bytes(bytes))
}

pub(crate) fn load(path: &str) -> Result<Option<Preparation>, String> {
    let conn = open_wallet_raw_conn_with_timeout(path, READ_DB_BUSY_TIMEOUT)?;
    let exists: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='vizor_gift_direct_claim')",
        [], |row| row.get(0)).map_err(|e| e.to_string())?;
    if !exists {
        return Ok(None);
    }
    let row: Option<(String, u32, u32)> = conn.query_row(
        "SELECT funding_txid, funding_height, tip_height FROM vizor_gift_direct_claim WHERE id=1",
        [], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .optional().map_err(|e| e.to_string())?;
    row.map(|(txid, height, tip)| {
        Ok(Preparation {
            funding_txid: parse_txid(&txid)?,
            funding_height: height.into(),
            tip_height: tip.into(),
        })
    })
    .transpose()
}

/// A failed or cancelled refresh must not leave an old quote usable.
pub(crate) fn clear(path: &str) -> Result<(), String> {
    with_wallet_db_write_lock("direct_claim.clear", || {
        let conn = open_wallet_raw_conn_with_timeout(path, READ_DB_BUSY_TIMEOUT)?;
        let exists: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='vizor_gift_direct_claim')",
        [], |row| row.get(0)).map_err(|e| e.to_string())?;
        if exists {
            conn.execute("DELETE FROM vizor_gift_direct_claim", [])
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    })
}

pub(crate) async fn prepare(
    path: &str,
    url: &str,
    network: WalletNetwork,
    funding_txid: &str,
    cancel: Arc<AtomicBool>,
    allow_resubmit: bool,
) -> Result<(), String> {
    clear(path)?;
    if cancel.load(Ordering::Relaxed) {
        return Err("Gift Card preparation cancelled".into());
    }
    let funding_id = parse_txid(funding_txid)?;
    let mut client = open_lwd_channel(url).await.map_err(|e| e.to_string())?;
    let tip = get_latest_block(&mut client)
        .await
        .map_err(|e| e.to_string())?;
    let tip_height: u32 = tip
        .height
        .try_into()
        .map_err(|_| "Gift Card chain height is invalid")?;
    let raw = get_transaction_payload(&mut client, funding_id)
        .await
        .map_err(|e| format!("Read Gift Card funding transaction: {e}"))?;
    let tx = Transaction::read(raw.data.as_slice(), BranchId::Sapling)
        .map_err(|_| "Gift Card funding transaction is invalid")?;
    if tx.txid() != funding_id {
        return Err("Gift Card funding transaction ID does not match".into());
    }
    let height: u32 = raw
        .height
        .try_into()
        .map_err(|_| "Gift Card funding height is invalid")?;
    if height == 0 || height > tip_height {
        return Err("Gift Card funding transaction is not confirmed yet".into());
    }
    let mut db = open_db(path, network).map_err(|e| e.to_string())?;
    if db.get_account_ids().map_err(|e| e.to_string())?.len() != 1 {
        return Err("Direct Gift Card preparation requires an isolated account".into());
    }
    let birthday = db
        .get_wallet_birthday()
        .map_err(|e| e.to_string())?
        .ok_or("Gift Card birthday is missing")?;
    if BlockHeight::from(height) < birthday {
        return Err("Gift Card funding precedes its birthday".into());
    }
    if let Some(previous) = db.get_tx_height(funding_id).map_err(|e| e.to_string())? {
        if previous != BlockHeight::from(height) {
            let divergent_height = previous.min(height.into());
            rewind(&mut client, &mut db, divergent_height).await?;
        }
    }

    crate::wallet::sync::recover_orphaned_send_locks(path, network)?;
    with_wallet_db_write_lock("direct_claim.update_tip", || {
        db.update_chain_tip(tip_height.into())
    })
    .map_err(|e| e.to_string())?;
    if cancel.load(Ordering::Relaxed) {
        return Err("Gift Card preparation cancelled".into());
    }

    process_transaction_block(&mut client, &mut db, network, funding_id, height, &cancel).await?;
    crate::wallet::sync::decrypt_and_store_transaction(path, network, &raw.data, Some(raw.height))?;
    with_wallet_db_write_lock("direct_claim.witnesses", || {
        validate_funding_witnesses(&mut db, funding_id, height.into(), tip_height.into())
    })?;

    // Observe only our durable outgoing transactions. Absence is not evidence
    // that somebody else spent this card; broadcast remains the spentness check.
    let conn = open_wallet_raw_conn_with_timeout(path, READ_DB_BUSY_TIMEOUT)?;
    let ids = {
        let mut stmt = conn
            .prepare(
                "SELECT DISTINCT t.txid, t.mined_height FROM transactions t
            WHERE EXISTS(SELECT 1 FROM sent_notes s WHERE s.transaction_id=t.id_tx)",
            )
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |row| {
                Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, Option<u32>>(1)?))
            })
            .map_err(|e| e.to_string())?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())?;
        rows
    };
    drop(conn);
    for (bytes, previous_height) in ids {
        if cancel.load(Ordering::Relaxed) {
            return Err("Gift Card preparation cancelled".into());
        }
        let id = TxId::from_bytes(
            bytes
                .try_into()
                .map_err(|_| "Stored Gift Card transaction ID is invalid")?,
        );
        let raw = match get_transaction_payload(&mut client, id).await {
            Ok(raw) => raw,
            Err(error) if error.code() == tonic::Code::NotFound => {
                rewind_claim_if_moved(&mut client, &mut db, previous_height, None).await?;
                with_wallet_db_write_lock("direct_claim.missing_claim", || {
                    db.set_transaction_status(id, TransactionStatus::TxidNotRecognized)
                })
                .map_err(|e| e.to_string())?;
                continue;
            }
            Err(error) => return Err(format!("Read Gift Card claim transaction: {error}")),
        };
        let tx = Transaction::read(raw.data.as_slice(), BranchId::Sapling)
            .map_err(|_| "Gift Card claim transaction is invalid")?;
        if tx.txid() != id {
            return Err("Gift Card claim transaction ID does not match".into());
        }
        if raw.height > 0 && raw.height <= tip.height {
            let h: u32 = raw
                .height
                .try_into()
                .map_err(|_| "Gift Card claim height is invalid")?;
            rewind_claim_if_moved(&mut client, &mut db, previous_height, Some(h)).await?;
            process_transaction_block(&mut client, &mut db, network, id, h, &cancel).await?;
            crate::wallet::sync::decrypt_and_store_transaction(
                path,
                network,
                &raw.data,
                Some(raw.height),
            )?;
        } else {
            rewind_claim_if_moved(&mut client, &mut db, previous_height, None).await?;
            with_wallet_db_write_lock("direct_claim.unmined_claim", || {
                db.set_transaction_status(id, TransactionStatus::NotInMainChain)
            })
            .map_err(|e| e.to_string())?;
        }
    }
    if cancel.load(Ordering::Relaxed) {
        return Err("Gift Card preparation cancelled".into());
    }
    // A rewind trims the SDK scan queue's view of the tip. Restore the current
    // tip before considering expiry or resubmitting our durable transactions.
    with_wallet_db_write_lock("direct_claim.restore_tip", || {
        db.update_chain_tip(tip_height.into())
    })
    .map_err(|e| e.to_string())?;
    if allow_resubmit {
        let exclusions = crate::wallet::sync::payment_link_resubmit_exclusions(path)?;
        let _ = crate::wallet::sync::resubmit_pending_transactions(
            path,
            url,
            &mut client,
            tip_height,
            &exclusions,
            || cancel.load(Ordering::Relaxed),
        )
        .await;
    }
    if cancel.load(Ordering::Relaxed) {
        return Err("Gift Card preparation cancelled".into());
    }
    with_wallet_db_write_lock("direct_claim.save", || -> Result<(), String> {
        let conn = open_wallet_raw_conn_with_timeout(path, READ_DB_BUSY_TIMEOUT)?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS vizor_gift_direct_claim (
        id INTEGER PRIMARY KEY CHECK(id=1), funding_txid TEXT NOT NULL,
        funding_height INTEGER NOT NULL, tip_height INTEGER NOT NULL);",
        )
        .map_err(|e| e.to_string())?;
        conn.execute(
            "INSERT INTO vizor_gift_direct_claim (id, funding_txid, funding_height, tip_height)
        VALUES(1, ?1, ?2, ?3)",
            rusqlite::params![funding_id.to_string(), height, tip_height],
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    })?;
    log::info!(
        "PaymentLinkClaim: direct funding preparation ready; historical ranges remain unscanned"
    );
    Ok(())
}

async fn rewind_claim_if_moved(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut crate::wallet::db::WalletDatabase,
    previous: Option<u32>,
    current: Option<u32>,
) -> Result<(), String> {
    if let Some(previous) = previous.filter(|height| Some(*height) != current) {
        let divergent: BlockHeight = current.map_or(previous, |h| h.min(previous)).into();
        rewind(client, db, divergent).await?;
    }
    Ok(())
}

async fn rewind(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut crate::wallet::db::WalletDatabase,
    divergent: BlockHeight,
) -> Result<(), String> {
    let height = divergent - 1;
    let state = get_tree_state(client, u64::from(u32::from(height)))
        .await
        .map_err(|e| e.to_string())?
        .to_chain_state()
        .map_err(|e| e.to_string())?;
    if state.block_height() != height {
        return Err("Gift Card rewind frontier height does not match".into());
    }
    rewind_to_state(db, state)
}

fn rewind_to_state(
    db: &mut crate::wallet::db::WalletDatabase,
    state: ChainState,
) -> Result<(), String> {
    // Sparse card DBs can have a frontier checkpoint with no matching blocks
    // row. The SDK's chain-state API handles that without a history scan.
    with_wallet_db_write_lock("direct_claim.rewind", || db.truncate_to_chain_state(state))
        .map_err(|e| e.to_string())
}

fn validate_funding_witnesses(
    db: &mut crate::wallet::db::WalletDatabase,
    id: TxId,
    height: BlockHeight,
    tip: BlockHeight,
) -> Result<(), String> {
    use shardtree::error::{QueryError, ShardTreeError};
    use zcash_client_sqlite::wallet::commitment_tree;
    type TreeError = ShardTreeError<commitment_tree::Error>;
    let account = db.get_account_ids().map_err(|e| e.to_string())?[0];
    let notes = db
        .select_unspent_notes(
            account,
            &[
                ShieldedPool::Sapling,
                ShieldedPool::Orchard,
                ShieldedPool::Ironwood,
            ],
            (tip + 1).into(),
            &[],
            LockFilter::Policy(&LockedInputPolicy::Exclude),
        )
        .map_err(|e| e.to_string())?;
    let result: Result<(), TreeError> = db.with_sapling_tree_mut(|tree| {
        for note in notes.sapling().iter().filter(|n| *n.txid() == id) {
            tree.witness_at_checkpoint_id_caching(note.note_commitment_tree_position(), &height)?
                .ok_or(ShardTreeError::Query(QueryError::CheckpointPruned))?;
        }
        tree.ensure_retained(height)
    });
    result.map_err(|e| format!("Prepare Gift Card Sapling witness: {e:?}"))?;
    let result: Result<(), TreeError> = db.with_orchard_tree_mut(|tree| {
        for note in notes.orchard().iter().filter(|n| *n.txid() == id) {
            tree.witness_at_checkpoint_id_caching(note.note_commitment_tree_position(), &height)?
                .ok_or(ShardTreeError::Query(QueryError::CheckpointPruned))?;
        }
        tree.ensure_retained(height)
    });
    result.map_err(|e| format!("Prepare Gift Card Orchard witness: {e:?}"))?;
    let result: Result<Option<()>, TreeError> = db.with_ironwood_tree_mut(|tree| {
        for note in notes.ironwood().iter().filter(|n| *n.txid() == id) {
            tree.witness_at_checkpoint_id_caching(note.note_commitment_tree_position(), &height)?
                .ok_or(ShardTreeError::Query(QueryError::CheckpointPruned))?;
        }
        tree.ensure_retained(height)
    });
    result.map_err(|e| format!("Prepare Gift Card Ironwood witness: {e:?}"))?;
    Ok(())
}

async fn process_transaction_block(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut crate::wallet::db::WalletDatabase,
    network: WalletNetwork,
    id: TxId,
    height: u32,
    cancel: &AtomicBool,
) -> Result<(), String> {
    let start = BlockHeight::from(height);
    let (source, state) = download_scan_batch(client, start, start, network)
        .await
        .map_err(|e| e.to_string())?;
    validate_scan_batch(&source, &state, start, start + 1).map_err(|e| e.to_string())?;
    if !source.transaction_hashes().any(|hash| hash == id.as_ref()) {
        return Err("Gift Card transaction is missing from its reported block".into());
    }
    let block_hash = source
        .block_at(start)
        .ok_or("Gift Card funding block is missing")?
        .hash();
    if db
        .get_block_hash(start)
        .map_err(|e| e.to_string())?
        .is_some_and(|stored| stored != block_hash)
    {
        rewind_to_state(db, state.clone())?;
    }
    if cancel.load(Ordering::Relaxed) {
        return Err("Gift Card preparation cancelled".into());
    }
    with_wallet_db_write_lock("direct_claim.scan_block", || {
        scan_cached_blocks(&network, &source, db, start, &state, 1)
    })
    .map_err(|e| format!("Prepare Gift Card transaction block: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests;
