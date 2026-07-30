//! Wallet-facing operations used by Vizor's Ironwood migration engine.
//!
//! The migration state machine and its `vizor_migration_*` persistence remain
//! application-owned. This module is the compatibility boundary for wallet
//! state owned by `librustzcash`: spendable notes, locks, anchors, witnesses,
//! and transaction storage. New wallet interactions belong here and must use
//! public wallet APIs. A few legacy confirmation/reorg inspection queries still
//! exist in `migration.rs` where the current generic API does not expose the
//! spender linkage or checkpoint detail they require; those are compatibility
//! debt, not a pattern to extend.

use sha2::{Digest, Sha256};
use std::collections::BTreeSet;

use zcash_client_backend::{
    data_api::{
        wallet::{
            input_selection::{LockFilter, LockedInputPolicy, NonEmptyBTreeSet},
            ConfirmationsPolicy,
        },
        InputSource, OutputLockStore, WalletRead,
    },
    wallet::{LockOwner, OutputRef, ReceivedNote},
};
use zcash_client_sqlite::{AccountUuid, ReceivedNoteId};
use zcash_primitives::transaction::TxId;
use zcash_protocol::{consensus::BlockHeight, PoolType, ShieldedPool};

use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};

use super::{open_wallet_db, WalletDatabase};

pub(super) type OrchardReceivedNote = ReceivedNote<ReceivedNoteId, orchard::Note>;

/// Returns the spendable Orchard V2 notes visible at `anchor_height`.
///
/// V1 notes are intentionally excluded: the Orchard-to-Ironwood migration
/// transaction shape is defined for the V2 notes created for NU6.3 migration.
pub(super) fn select_spendable_orchard_v2_notes(
    db: &WalletDatabase,
    account_id: AccountUuid,
    anchor_height: BlockHeight,
) -> Result<Vec<OrchardReceivedNote>, String> {
    db.get_unspent_orchard_notes_at_historical_height(account_id, anchor_height)
        .map(|notes| {
            notes
                .into_iter()
                .filter(|note| note.note().version() == orchard::note::NoteVersion::V2)
                .collect()
        })
        .map_err(|e| format!("Failed to select Orchard notes: {e}"))
}

/// Derives the stable owner token used for all wallet-level note locks held by
/// one Vizor migration run.
pub(super) fn migration_lock_owner(run_id: &str) -> LockOwner {
    let mut digest = Sha256::new();
    digest.update(b"vizor-ironwood-migration-lock-v1");
    digest.update(run_id.as_bytes());
    LockOwner::new(digest.finalize().into())
}

/// Restricts migration input selection to this run's own locks while
/// preferring those reserved notes over unrelated unlocked funds.
pub(super) fn migration_locked_input_policy(run_id: &str) -> LockedInputPolicy {
    LockedInputPolicy::PreferLocked(NonEmptyBTreeSet::singleton(migration_lock_owner(run_id)))
}

/// Ensures that every candidate that currently exists as a spendable Orchard
/// note is locked for this run.
///
/// Candidates may include outputs of denomination transactions that have not
/// been mined yet. Those are deliberately ignored until a later reconciliation
/// call can see them through the wallet API.
pub(super) fn ensure_orchard_migration_locks(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
    candidates: &[(String, u32)],
) -> Result<bool, String> {
    if candidates.is_empty() {
        return Ok(true);
    }

    with_wallet_db_write_lock("migration.ensure_orchard_migration_locks", || {
        let candidates = candidates
            .iter()
            .map(|(txid_hex, output_index)| orchard_output_ref(txid_hex, *output_index))
            .collect::<Result<Vec<_>, _>>()?;
        let mut db = open_wallet_db(db_path, network)?;
        let Some((target_height, _)) = db
            .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
            .map_err(|e| format!("Read wallet target height for migration locks: {e}"))?
        else {
            // Startup can inspect durable migration state before the wallet has
            // restored a usable target height. Existing locks remain persisted;
            // the next post-sync reconciliation will discover any new outputs.
            return Ok(false);
        };
        let mut outputs = Vec::new();
        let mut seen = BTreeSet::new();
        for output in candidates {
            let key = (*output.txid(), output.output_index());
            if seen.insert(key)
                && db
                    .get_spendable_note(
                        output.txid(),
                        ShieldedPool::Orchard,
                        output.output_index(),
                        target_height,
                        LockFilter::Unfiltered,
                    )
                    .map_err(|e| format!("Resolve migration input through wallet API: {e}"))?
                    .is_some()
            {
                outputs.push(output);
            }
        }
        if outputs.is_empty() {
            return Ok(true);
        }
        db.lock_outputs(
            &outputs,
            migration_lock_owner(run_id),
            BlockHeight::from_u32(u32::MAX),
        )
        .map(|_| true)
        .map_err(|e| format!("Lock migration inputs in wallet DB: {e:?}"))
    })
}

pub(super) fn unlock_orchard_migration_outputs(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
    candidates: &[(String, u32)],
) -> Result<(), String> {
    if candidates.is_empty() {
        return Ok(());
    }

    with_wallet_db_write_lock("migration.unlock_orchard_migration_outputs", || {
        let owner = migration_lock_owner(run_id);
        let mut db = open_wallet_db(db_path, network)?;
        for (txid_hex, output_index) in candidates {
            db.unlock_output(&orchard_output_ref(txid_hex, *output_index)?, owner)
                .map_err(|e| format!("Unlock migration input in wallet DB: {e}"))?;
        }
        Ok(())
    })
}

fn orchard_output_ref(txid_hex: &str, output_index: u32) -> Result<OutputRef, String> {
    let mut txid_bytes: [u8; 32] = hex::decode(txid_hex)
        .map_err(|e| format!("Decode migration input txid: {e}"))?
        .try_into()
        .map_err(|_| "Migration input txid must be 32 bytes".to_string())?;
    txid_bytes.reverse();
    Ok(OutputRef::new(
        TxId::from_bytes(txid_bytes),
        PoolType::Shielded(ShieldedPool::Orchard),
        output_index,
    ))
}

#[cfg(test)]
mod tests {
    use super::{migration_lock_owner, migration_locked_input_policy};

    #[test]
    fn migration_lock_owner_is_stable_and_domain_separated() {
        let first = migration_lock_owner("run-1");
        assert_eq!(first, migration_lock_owner("run-1"));
        assert_ne!(first, migration_lock_owner("run-2"));
        assert!(migration_locked_input_policy("run-1")
            .overridable_owners()
            .contains(&first));
    }
}
