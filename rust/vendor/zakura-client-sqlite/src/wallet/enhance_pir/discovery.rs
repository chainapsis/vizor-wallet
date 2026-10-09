//! Durable rediscovery after an Ironwood spend becomes linkable retroactively.

use std::collections::{HashMap, HashSet};

use orchard::note_encryption::CompactAction;
use rusqlite::{Connection, OptionalExtension, Transaction, named_params};
use zcash_client_backend::{
    data_api::enhance_pir::{
        IronwoodEnhanceDiscoveryFailure, IronwoodEnhanceDiscoveryFailureReason,
        IronwoodEnhanceDiscoveryRequest, IronwoodEnhanceDiscoveryResult, is_ironwood_pir_candidate,
    },
    proto::compact_formats::{CompactBlock, CompactTx},
    wallet::{IronwoodEnhanceCandidate, IronwoodEnhancementPlan},
};
use zcash_primitives::block::BlockHash;
use zcash_primitives::transaction::TxId;

use crate::{AccountUuid, TxRef, error::SqliteClientError, wallet::KeyScope};

use super::{
    LWD_REQUIRED, TxQueryType, outgoing_position_owned_by_other, queue_transaction,
    retire_enhancement_if_complete, route,
};

struct ReconstructedCandidates {
    outgoing: Vec<IronwoodEnhanceCandidate<AccountUuid>>,
    received_context: Vec<(u32, [u8; 32], [u8; 52])>,
    /// Whether the actions reveal every funding nullifier.
    funded: bool,
}

/// Reopens outgoing discovery in the same transaction that persists the spend link.
/// This is mode-independent; Standard exposes the restored request, PrivateIronwood withholds it.
pub(crate) fn queue(conn: &Connection, tx_ref: TxRef) -> Result<(), SqliteClientError> {
    let needs_work: bool = conn.query_row(
        "SELECT raw IS NULL AND mined_height IS NOT NULL FROM transactions WHERE id_tx = :tx",
        named_params![":tx": tx_ref.0],
        |row| row.get(0),
    )?;
    if !needs_work {
        return Ok(());
    }
    // Recent-first scanning could not identify change before this spend link existed.
    // Repair internal outputs belonging to funding accounts before rediscovery uses
    // the stored flag; another wallet account's received payment is not change.
    conn.execute(
        "UPDATE ironwood_received_notes SET is_change = 1
         WHERE transaction_id = :tx AND recipient_key_scope = :internal_scope
         AND account_id IN (
             SELECT rn.account_id FROM ironwood_received_note_spends s
             JOIN ironwood_received_notes rn ON rn.id = s.ironwood_received_note_id
             WHERE s.transaction_id = :tx
         )",
        named_params![":tx": tx_ref.0, ":internal_scope": KeyScope::INTERNAL.encode()],
    )?;
    if route(conn, tx_ref)? == Some(LWD_REQUIRED) {
        return super::require_lwd(conn, tx_ref);
    }
    conn.execute(
        "INSERT INTO ironwood_enhance_discovery_queue (transaction_id, suspended) VALUES (:tx, :suspended)
         ON CONFLICT(transaction_id) DO UPDATE SET suspended = excluded.suspended",
        named_params![":tx": tx_ref.0, ":suspended": funding(conn, tx_ref)?.is_empty()],
    )?;
    conn.execute(
        concat!(
            "INSERT INTO ironwood_enhance_routing (transaction_id, route) VALUES (:tx, ",
            private_protected!(),
            ")
         ON CONFLICT(transaction_id) DO NOTHING"
        ),
        named_params![":tx": tx_ref.0],
    )?;
    conn.execute(
        "INSERT INTO tx_retrieval_queue (txid, query_type)
         SELECT txid, :enhancement FROM transactions WHERE id_tx = :tx
         ON CONFLICT(txid, query_type) DO NOTHING",
        named_params![":tx": tx_ref.0, ":enhancement": TxQueryType::Enhancement.code()],
    )?;
    Ok(())
}

/// Unlike the scan-time nullifier set, this includes already-spent funding notes.
pub(super) fn funding(
    conn: &Connection,
    tx_ref: TxRef,
) -> Result<Vec<(AccountUuid, [u8; 32])>, SqliteClientError> {
    let mut stmt = conn.prepare_cached(
        "SELECT a.uuid, rn.nf FROM ironwood_received_note_spends s
         JOIN ironwood_received_notes rn ON rn.id = s.ironwood_received_note_id
         JOIN accounts a ON a.id = rn.account_id
         WHERE s.transaction_id = :tx AND rn.nf IS NOT NULL",
    )?;
    stmt.query_map(named_params![":tx": tx_ref.0], |row| {
        Ok((AccountUuid(row.get(0)?), row.get(1)?))
    })?
    .collect::<Result<_, _>>()
    .map_err(Into::into)
}

/// Validates the entire reconstruction before mutating any work, using current funding
/// associations under the caller's SQL transaction (not a pre-network account snapshot).
pub(crate) fn rebuild(
    conn: &Transaction<'_>,
    request: IronwoodEnhanceDiscoveryRequest,
    block: &CompactBlock,
) -> Result<IronwoodEnhanceDiscoveryResult, SqliteClientError> {
    use IronwoodEnhanceDiscoveryFailureReason::{
        ContextMismatch, NoFundingAccounts, TransactionMissing,
    };
    use IronwoodEnhanceDiscoveryResult::{AlreadyResolved, Incomplete, Rebuilt, Rejected};
    let metadata: Option<([u8; 32], Option<u32>)> = conn
        .query_row(
            "SELECT hash, ironwood_commitment_tree_size FROM blocks WHERE height = :height",
            named_params![":height": u32::from(request.height)],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;
    let Some((hash, Some(end))) = metadata else {
        return Ok(AlreadyResolved);
    };
    if BlockHash(hash) != request.block_hash {
        return Ok(AlreadyResolved);
    }
    let block_hash = if block.header.is_empty() {
        block.hash.as_slice().try_into().ok().map(BlockHash)
    } else {
        block.header().map(|header| header.hash())
    };
    if block.height != u64::from(u32::from(request.height))
        || block_hash != Some(request.block_hash)
        || block
            .chain_metadata
            .as_ref()
            .is_none_or(|m| m.ironwood_commitment_tree_size != end)
    {
        return Ok(Rejected);
    }
    let mut stmt = conn.prepare_cached(concat!(
        "WITH jobs AS (
            SELECT transaction_id FROM ironwood_enhance_discovery_queue WHERE suspended = 0
            UNION SELECT transaction_id FROM ironwood_enhance_metadata_queue WHERE commitment_tree_position IS NULL
         ) SELECT t.id_tx, t.txid, t.tx_index,
            EXISTS(SELECT 1 FROM ironwood_enhance_discovery_queue d WHERE d.transaction_id = t.id_tx AND d.suspended = 0)
         FROM jobs q
         JOIN transactions t ON t.id_tx = q.transaction_id
         ",
        active_private_tx!(),
        "
           AND t.mined_height = :height
         ORDER BY t.tx_index, t.txid"
    ))?;
    let jobs = stmt
        .query_map(named_params![":height": u32::from(request.height)], |row| {
            Ok((
                TxRef(row.get(0)?),
                row.get::<_, [u8; 32]>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, bool>(3)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    if jobs.is_empty() {
        return Ok(AlreadyResolved);
    }

    let count = block.vtx.iter().try_fold(0u32, |sum, tx| {
        sum.checked_add(u32::try_from(tx.ironwood_actions.len()).ok()?)
    });
    let Some(mut position) = count.and_then(|n| end.checked_sub(n)) else {
        return Ok(Rejected);
    };
    // The preceding tree size anchors the action list. A claimed block hash does
    // not prove that the supplied compact action list is complete.
    let expected_start = if u32::from(request.height) == 0 {
        Some(0)
    } else {
        conn.query_row(
            "SELECT ironwood_commitment_tree_size FROM blocks WHERE height = :height",
            named_params![":height": u32::from(request.height) - 1],
            |row| row.get(0),
        )
        .optional()?
        .flatten()
    };
    if expected_start != Some(position) {
        return Ok(Rejected);
    }

    // Validate block-wide ordering before considering any transaction-local failures.
    // The same full block supplies positions for every independently processed job.
    let mut transactions = HashMap::new();
    let mut previous_index = None;
    for compact_tx in &block.vtx {
        if compact_tx.txid.len() != 32
            || transactions
                .insert(compact_tx.txid.as_slice(), (position, compact_tx))
                .is_some()
            || previous_index.is_some_and(|index| index >= compact_tx.index)
        {
            return Ok(Rejected);
        }
        previous_index = Some(compact_tx.index);
        position += u32::try_from(compact_tx.ironwood_actions.len()).expect("checked total");
    }

    let mut metadata_plans = vec![];
    let mut metadata_rebuilt = 0;
    let mut received_context_plans = vec![];
    let mut plans = vec![];
    let mut unresolved = vec![];
    let mut suspend = vec![];
    for (tx_ref, txid, index, needs_outgoing) in jobs {
        let funding = if needs_outgoing {
            funding(conn, tx_ref)?
        } else {
            vec![]
        };
        let tx = transactions.get(txid.as_slice());
        // Validate geometry, locators and received positions even for metadata-only jobs.
        let reconstructed = match tx {
            Some((position, compact_tx)) => {
                candidates(conn, tx_ref, index, *position, compact_tx, &funding)?
                    .map(|reconstructed| (*position, *compact_tx, reconstructed))
            }
            None => None,
        };
        if let Some((position, compact_tx, _)) = &reconstructed {
            // Every action position covers every outgoing candidate, so ownership is checked
            // before mixed transactions discard their candidates. A locally contradictory
            // reconstruction must not change routing to LWD.
            for index in 0..compact_tx.ironwood_actions.len() {
                if outgoing_position_owned_by_other(
                    conn,
                    tx_ref,
                    u64::from(*position) + index as u64,
                )? {
                    return Ok(Rejected);
                }
            }
            if !compact_tx.ironwood_actions.is_empty() {
                metadata_plans.push((tx_ref, *position, is_ironwood_pir_candidate(compact_tx)));
            }
        }
        let reason = match reconstructed {
            _ if needs_outgoing && funding.is_empty() => {
                // Defensive handling for an active orphan, even if deletion cleanup was missed.
                suspend.push(tx_ref);
                NoFundingAccounts
            }
            Some((_, compact_tx, reconstructed))
                if !needs_outgoing && !compact_tx.ironwood_actions.is_empty() =>
            {
                received_context_plans.push((tx_ref, reconstructed.received_context));
                metadata_rebuilt += 1;
                continue;
            }
            Some((_, compact_tx, reconstructed)) if needs_outgoing && reconstructed.funded => {
                plans.push((
                    tx_ref,
                    if is_ironwood_pir_candidate(compact_tx) {
                        IronwoodEnhancementPlan::Eligible {
                            outgoing: reconstructed.outgoing,
                        }
                    } else {
                        IronwoodEnhancementPlan::Ineligible
                    },
                    reconstructed.received_context,
                ));
                continue;
            }
            _ if tx.is_some() => ContextMismatch,
            _ => TransactionMissing,
        };
        unresolved.push(IronwoodEnhanceDiscoveryFailure {
            txid: TxId::from_bytes(txid),
            reason,
        });
    }

    // Transaction-local failures retain intent while valid siblings progress.
    // Any SQL error still rolls back all writes in this call, including suspension.
    let rebuilt = plans.len() + metadata_rebuilt;
    for (tx_ref, position, eligible) in metadata_plans {
        if eligible {
            super::metadata::bind(conn, tx_ref, u64::from(position), 0)?;
        } else {
            super::require_lwd(conn, tx_ref)?;
        }
    }
    for (tx_ref, received_context) in received_context_plans {
        restore_received_context(conn, tx_ref, received_context)?;
    }
    for tx_ref in suspend {
        conn.execute(
            "UPDATE ironwood_enhance_discovery_queue SET suspended = 1 WHERE transaction_id = :tx",
            named_params![":tx": tx_ref.0],
        )?;
    }
    for (tx_ref, plan, received_context) in plans {
        restore_received_context(conn, tx_ref, received_context)?;
        queue_transaction(conn, tx_ref, &plan)?;
        conn.execute(
            "DELETE FROM ironwood_enhance_discovery_queue WHERE transaction_id = :tx",
            named_params![":tx": tx_ref.0],
        )?;
        retire_enhancement_if_complete(conn, tx_ref)?;
    }
    Ok(if unresolved.is_empty() {
        Rebuilt(rebuilt)
    } else {
        Incomplete {
            rebuilt,
            unresolved,
        }
    })
}

fn restore_received_context(
    conn: &Connection,
    tx_ref: TxRef,
    received_context: Vec<(u32, [u8; 32], [u8; 52])>,
) -> Result<(), SqliteClientError> {
    for (index, epk, ciphertext) in received_context {
        conn.execute(
            "UPDATE ironwood_received_notes
             SET ephemeral_key = :epk, compact_ciphertext = :ciphertext
             WHERE transaction_id = :tx AND action_index = :index
               AND ephemeral_key IS NULL AND compact_ciphertext IS NULL",
            named_params![
                ":epk": epk,
                ":ciphertext": ciphertext,
                ":tx": tx_ref.0,
                ":index": index,
            ],
        )?;
    }
    Ok(())
}

/// Returns None for transaction-local context mismatches. Database errors remain errors;
/// neither case is permission to declare the transaction complete or fetch it publicly.
/// Unspent funding nullifiers are reported through `funded` so metadata-only validation
/// sees the same reconstruction.
fn candidates(
    conn: &Connection,
    tx_ref: TxRef,
    expected_index: u64,
    position: u32,
    compact_tx: &CompactTx,
    funding: &[(AccountUuid, [u8; 32])],
) -> Result<Option<ReconstructedCandidates>, SqliteClientError> {
    if expected_index != compact_tx.index {
        return Ok(None);
    }
    let accounts = funding
        .iter()
        .map(|(account, _)| *account)
        .collect::<HashSet<_>>();
    let mut stmt = conn.prepare_cached(
        "SELECT action_index, commitment_tree_position, is_change FROM ironwood_received_notes
         WHERE transaction_id = :tx",
    )?;
    let received = stmt
        .query_map(named_params![":tx": tx_ref.0], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                (row.get::<_, Option<u64>>(1)?, row.get::<_, bool>(2)?),
            ))
        })?
        .collect::<Result<HashMap<_, _>, _>>()?;
    if received.iter().any(|(index, (pos, _))| {
        *index as usize >= compact_tx.ironwood_actions.len()
            || *pos != Some(u64::from(position) + u64::from(*index))
    }) {
        return Ok(None);
    }
    let mut candidates = vec![];
    let mut received_context = vec![];
    let mut nullifiers = HashSet::new();
    for (index, raw) in compact_tx.ironwood_actions.iter().enumerate() {
        let Ok(action) = CompactAction::try_from(raw) else {
            return Ok(None);
        };
        nullifiers.insert(action.nullifier().to_bytes());
        if received.contains_key(&(index as u32)) {
            received_context.push((
                index as u32,
                raw.ephemeral_key
                    .as_slice()
                    .try_into()
                    .expect("validated CompactAction"),
                raw.ciphertext
                    .as_slice()
                    .try_into()
                    .expect("validated CompactAction"),
            ));
        }
        if !received
            .get(&(index as u32))
            .is_some_and(|(_, is_change)| *is_change)
        {
            candidates.push(IronwoodEnhanceCandidate::from_parts(
                (u64::from(position) + index as u64).into(),
                index,
                action.nullifier().to_bytes(),
                action.cmx().to_bytes(),
                raw.ephemeral_key
                    .as_slice()
                    .try_into()
                    .expect("validated CompactAction"),
                raw.ciphertext
                    .as_slice()
                    .try_into()
                    .expect("validated CompactAction"),
                accounts.iter().copied().collect(),
            ));
        }
    }
    Ok(Some(ReconstructedCandidates {
        outgoing: candidates,
        received_context,
        funded: funding.iter().all(|(_, nf)| nullifiers.contains(nf)),
    }))
}
