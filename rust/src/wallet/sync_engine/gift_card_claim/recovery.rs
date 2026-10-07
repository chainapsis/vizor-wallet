//! Recovery uses a completed, chain-validated observer pass, never an isolated
//! transaction lookup. Ordinary wallet status/resubmission policy is unchanged.
use super::*;
use crate::wallet::sync::ResubmittableTx;
use zcash_client_backend::data_api::TransactionStatus;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BranchId;

// Restrict recovery to locally signed attempts spending this card's funding.
const CLAIMS: &str = "SELECT DISTINCT t.id_tx FROM transactions t
    JOIN v_received_output_spends spent ON spent.transaction_id=t.id_tx AND spent.pool=4
    JOIN ironwood_received_notes n ON n.id=spent.received_output_id
    JOIN transactions funding ON funding.id_tx=n.transaction_id
    JOIN vizor_giftcard_check g ON g.funding_txid=funding.txid
    WHERE t.created IS NOT NULL AND t.raw IS NOT NULL";

pub(super) fn reconcile_mined_claims(
    path: &str,
    network: WalletNetwork,
    c: &Connection,
    state: &Snapshot,
) -> Result<Option<u32>, String> {
    if funding_spends_settled(c, state)? {
        reconcile_settled_claims(path, network, c)?;
        return Ok(Some(state.anchor_height));
    }
    let stale_height: Option<u32> = c
        .query_row(
            &format!(
                "SELECT MIN(t.mined_height) FROM transactions t
                 LEFT JOIN vizor_giftcard_mined m ON m.txid=t.txid
                 WHERE t.id_tx IN ({CLAIMS}) AND t.mined_height IS NOT NULL
                   AND (m.height IS NULL OR m.height!=t.mined_height)"
            ),
            [],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    let Some(stale_height) = stale_height else {
        return Ok(Some(state.anchor_height));
    };
    // Status-only receipts can remain even after later blocks were scanned.
    // Rewind below the earliest stale receipt, never below the funding itself.
    let anchor_height = state.anchor_height.min(stale_height.saturating_sub(1));
    if anchor_height < state.funding_height {
        return Ok(None);
    }

    // Rewind is a wallet-wide SDK operation. Preserve every currently valid
    // receipt it will clear, including unrelated local transactions in an old
    // claim DB. Observer mining facts were just validated through checked_height.
    let mut q = c
        .prepare("SELECT t.txid,m.height FROM transactions t JOIN vizor_giftcard_mined m ON m.txid=t.txid WHERE t.mined_height>?1")
        .map_err(|e| e.to_string())?;
    let retained = q
        .query_map([anchor_height], |r| {
            Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, u32>(1)?))
        })
        .map_err(|e| e.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    drop(q);
    let mut db = open_db(path, network).map_err(|e| e.to_string())?;
    // Observation may stop once every funding input has six confirmations.
    // Preserve the endpoint tip already learned by the caller, even then.
    let current_tip = db
        .chain_height()
        .map_err(|e| e.to_string())?
        .unwrap_or_else(|| state.checked_height.into());
    let result = db.transactionally(|wdb| {
        let anchor = BlockHeight::from_u32(anchor_height);
        // Use all SDK rewind hooks, rather than clearing mined_height alone.
        // Never accept a lower rewind that could discard the funding witnesses.
        let achieved = wdb.truncate_to_height(anchor)?;
        if achieved != anchor {
            return Err(SqliteClientError::RequestedRewindInvalid {
                safe_rewind_height: Some(achieved),
                requested_height: anchor,
            });
        }
        wdb.update_chain_tip(current_tip)?;
        for (bytes, height) in &retained {
            let bytes: [u8; 32] = bytes.as_slice().try_into().map_err(|_| {
                SqliteClientError::CorruptedData("Invalid Gift Card transaction ID".into())
            })?;
            WalletWrite::set_transaction_status(
                wdb,
                zcash_primitives::transaction::TxId::from_bytes(bytes),
                TransactionStatus::Mined(BlockHeight::from_u32(*height)),
            )?;
        }
        Ok::<_, SqliteClientError>(())
    });
    match result {
        Ok(()) => Ok(Some(anchor_height)),
        // The failed rewind rolls back atomically. A pruned or damaged cache
        // uses the caller's bounded rediscovery, which keeps signed attempts.
        Err(
            SqliteClientError::RequestedRewindInvalid { .. }
            | SqliteClientError::TruncateCommitmentTree { .. }
            | SqliteClientError::CorruptedData(_),
        ) => Ok(None),
        Err(e) => Err(format!("Recover Gift Card mined receipts: {e}")),
    }
}

/// Settlement is decided by the validated observer. Keep SDK history usable
/// for mixed success/conflict outcomes, without clearing any other receipts.
/// An orphaned local claim remains settled by positive input-conflict evidence,
/// rather than by unmining its SDK receipt in a wallet-wide rewind.
fn reconcile_settled_claims(
    path: &str,
    network: WalletNetwork,
    c: &Connection,
) -> Result<(), String> {
    let mut q = c
        .prepare(&format!(
            "SELECT t.txid,m.height FROM transactions t
             JOIN vizor_giftcard_mined m ON m.txid=t.txid
             WHERE t.id_tx IN ({CLAIMS})
               AND (t.mined_height IS NULL OR t.mined_height!=m.height)"
        ))
        .map_err(|e| e.to_string())?;
    let mined = q
        .query_map([], |r| Ok((r.get::<_, Vec<u8>>(0)?, r.get::<_, u32>(1)?)))
        .map_err(|e| e.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    drop(q);
    if mined.is_empty() {
        return Ok(());
    }
    let mut db = open_db(path, network).map_err(|e| e.to_string())?;
    db.transactionally(|wdb| {
        for (bytes, height) in &mined {
            let bytes: [u8; 32] = bytes.as_slice().try_into().map_err(|_| {
                SqliteClientError::CorruptedData("Invalid Gift Card transaction ID".into())
            })?;
            WalletWrite::set_transaction_status(
                wdb,
                zcash_primitives::transaction::TxId::from_bytes(bytes),
                TransactionStatus::Mined(BlockHeight::from_u32(*height)),
            )?;
        }
        Ok::<_, SqliteClientError>(())
    })
    .map_err(|e| format!("Record settled Gift Card mined claims: {e}"))
}

pub(super) fn resubmittable_claims(
    path: &str,
    network: WalletNetwork,
    c: &Connection,
    state: &Snapshot,
) -> Result<Vec<ResubmittableTx>, String> {
    if !state.complete {
        return Err("Gift Card resubmission requires a completed check".into());
    }
    let mut q = c
        .prepare(&format!(
            "SELECT t.txid,t.raw,t.expiry_height FROM transactions t
             WHERE t.id_tx IN ({CLAIMS})
               AND (t.expiry_height=0 OR t.expiry_height>?1)
               AND NOT EXISTS (SELECT 1 FROM vizor_giftcard_mined m WHERE m.txid=t.txid)
               AND NOT EXISTS (
                 SELECT 1 FROM v_received_output_spends spent
                 JOIN ironwood_received_notes n ON spent.pool=4 AND spent.received_output_id=n.id
                 JOIN vizor_giftcard_spends s ON s.nf=n.nf
                 WHERE spent.transaction_id=t.id_tx)
               AND NOT EXISTS (
                 SELECT 1 FROM v_received_output_spends spent
                 LEFT JOIN ironwood_received_notes n ON spent.pool=4 AND spent.received_output_id=n.id
                 LEFT JOIN transactions funding ON funding.id_tx=n.transaction_id
                 WHERE spent.transaction_id=t.id_tx
                   AND (spent.pool!=4 OR funding.txid!=(SELECT funding_txid FROM vizor_giftcard_check)))"
        ))
        .map_err(|e| e.to_string())?;
    let candidates = q
        .query_map([state.checked_height], |r| {
            Ok(ResubmittableTx {
                txid_bytes: r.get(0)?,
                raw_tx: r.get(1)?,
                expiry_height: r.get(2)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    if candidates.is_empty() {
        return Ok(candidates);
    }
    // A legacy attempt can carry an orphaned anchor even after rediscovery.
    // Only relay bytes whose actual proof anchor exists in the validated prefix.
    let mut checkpoints = c
        .prepare("SELECT checkpoint_id FROM ironwood_tree_checkpoints WHERE checkpoint_id BETWEEN ?1 AND ?2")
        .map_err(|e| e.to_string())?;
    let heights = checkpoints
        .query_map(
            rusqlite::params![state.funding_height, state.anchor_height],
            |r| r.get::<_, u32>(0),
        )
        .map_err(|e| e.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    let mut db = open_db(path, network).map_err(|e| e.to_string())?;
    let roots = db
        .with_ironwood_tree_mut(|tree| {
            let mut roots = HashSet::new();
            for height in &heights {
                if let Some(root) = tree.root_at_checkpoint_id(&(*height).into())? {
                    roots.insert(orchard::Anchor::from(root).to_bytes());
                }
            }
            Ok::<_, ShardTreeError<zcash_client_sqlite::wallet::commitment_tree::Error>>(roots)
        })
        .map_err(|e| format!("Read Gift Card resubmission anchors: {e}"))?
        .unwrap_or_default();
    Ok(candidates
        .into_iter()
        .filter(|candidate| {
            let Ok(tx) = Transaction::read(
                candidate.raw_tx.as_slice(),
                BranchId::for_height(&network, state.checked_height.into()),
            ) else {
                return false;
            };
            tx.txid().as_ref().as_slice() == candidate.txid_bytes.as_slice()
                && tx
                    .ironwood_bundle()
                    .is_some_and(|b| roots.contains(&b.anchor().to_bytes()))
        })
        .collect())
}
