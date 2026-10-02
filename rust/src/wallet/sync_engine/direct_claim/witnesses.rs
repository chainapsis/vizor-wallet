//! Advance the funding note's witness using sparse tree frontiers. A frontier
//! cannot reveal children of an opaque subtree containing the note, so locate
//! the blocks that completed missing witness nodes by their tree sizes.

use std::collections::{BTreeMap, BTreeSet};

use incrementalmerkletree::{Address, Hashable, Marking, Position, Retention};
use shardtree::{
    error::{QueryError, ShardTreeError},
    store::ShardStore,
    ShardTree,
};

use super::*;

pub(super) async fn prepare_recent_anchor(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut crate::wallet::db::WalletDatabase,
    network: WalletNetwork,
    id: TxId,
    funding_height: u32,
    tip: u32,
    anchor: u32,
    cancel: &AtomicBool,
) -> Result<(), String> {
    check_cancel(cancel)?;
    process_block(client, db, network, None, anchor, cancel).await?;
    let reference = read_state(client, anchor, cancel).await?;
    if db
        .get_block_hash(anchor.into())
        .map_err(|e| e.to_string())?
        != Some(reference.block_hash())
    {
        return Err("Gift Card anchor changed during preparation; retry".into());
    }
    with_wallet_db_write_lock("direct_claim.anchor_frontier", || {
        insert_anchor_frontier(db, &reference)
    })?;
    let mut states = BTreeMap::from([(anchor, reference.clone())]);
    let mut processed = BTreeSet::from([anchor]);
    loop {
        check_cancel(cancel)?;
        let missing = with_wallet_db_write_lock("direct_claim.recent_witness", || {
            missing_witness_nodes(db, id, tip.into(), &reference)
        })?;
        let Some((pool, address)) = missing.first().copied() else {
            return Ok(());
        };
        let target_size = u64::from(address.position_range_end()).min(tree_size(&reference, pool));
        // The missing node must be after the known funding note. Tree-size
        // lookups are small responses; no intervening compact blocks are read.
        let mut low = funding_height;
        let mut high = anchor;
        while low < high {
            check_cancel(cancel)?;
            let mid = low + (high - low) / 2;
            if let std::collections::btree_map::Entry::Vacant(entry) = states.entry(mid) {
                entry.insert(read_state(client, mid, cancel).await?);
            }
            if tree_size(&states[&mid], pool) >= target_size {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        if !processed.insert(low) {
            return Err(
                "Gift Card witness could not be advanced to the recent anchor; retry".into(),
            );
        }
        process_block(client, db, network, None, low, cancel).await?;
    }
}

fn check_cancel(cancel: &AtomicBool) -> Result<(), String> {
    if cancel.load(Ordering::Relaxed) {
        Err("Gift Card preparation cancelled".into())
    } else {
        Ok(())
    }
}

async fn read_state(
    client: &mut CompactTxStreamerClient<Channel>,
    height: u32,
    cancel: &AtomicBool,
) -> Result<ChainState, String> {
    check_cancel(cancel)?;
    let state = get_tree_state(client, height.into())
        .await
        .map_err(|e| e.to_string())?
        .to_chain_state()
        .map_err(|e| e.to_string())?;
    if state.block_height() != BlockHeight::from(height) {
        return Err("Gift Card witness frontier height does not match".into());
    }
    Ok(state)
}

fn tree_size(state: &ChainState, pool: ShieldedPool) -> u64 {
    match pool {
        ShieldedPool::Sapling => state.final_sapling_tree().tree_size(),
        ShieldedPool::Orchard => state.final_orchard_tree().tree_size(),
        ShieldedPool::Ironwood => state.final_ironwood_tree().tree_size(),
    }
}

pub(super) fn insert_anchor_frontier(
    db: &mut crate::wallet::db::WalletDatabase,
    reference: &ChainState,
) -> Result<(), String> {
    // Empty blocks do not always create an SDK checkpoint. Pin the verified
    // end-of-block frontier explicitly, without scanning the gap before it.
    let retention = Retention::Checkpoint {
        id: reference.block_height(),
        marking: Marking::None,
    };
    db.with_sapling_tree_mut(|tree| {
        tree.insert_frontier(reference.final_sapling_tree().clone(), retention.clone())
    })
    .map_err(|e| format!("Pin Gift Card Sapling anchor: {e:?}"))?;
    db.with_orchard_tree_mut(|tree| {
        tree.insert_frontier(reference.final_orchard_tree().clone(), retention.clone())
    })
    .map_err(|e| format!("Pin Gift Card Orchard anchor: {e:?}"))?;
    db.with_ironwood_tree_mut(|tree| {
        tree.insert_frontier(reference.final_ironwood_tree().clone(), retention)
    })
    .map_err(|e| format!("Pin Gift Card Ironwood anchor: {e:?}"))?;
    Ok(())
}

pub(super) fn missing_witness_nodes(
    db: &mut crate::wallet::db::WalletDatabase,
    id: TxId,
    tip: BlockHeight,
    reference: &ChainState,
) -> Result<Vec<(ShieldedPool, Address)>, String> {
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
    let anchor = reference.block_height();
    let mut missing = vec![];
    macro_rules! inspect {
        ($method:ident, $notes:ident, $pool:expr, $root:expr, $leaf:expr) => {{
            let positions = notes
                .$notes()
                .iter()
                .filter(|n| *n.txid() == id)
                .map(|n| (n.note_commitment_tree_position(), ($leaf)(n.note())))
                .collect::<Vec<_>>();
            let result = db
                .$method(|tree| inspect_tree(tree, &positions, anchor, &$root))
                .map_err(|e| format!("Prepare recent Gift Card {:?} witness: {e:?}", $pool))?;
            result
        }};
    }
    let sapling = inspect!(
        with_sapling_tree_mut,
        sapling,
        ShieldedPool::Sapling,
        reference.final_sapling_tree().root(),
        |note: &sapling_crypto::Note| sapling_crypto::Node::from_cmu(&note.cmu())
    );
    missing.extend(sapling.into_iter().map(|a| (ShieldedPool::Sapling, a)));
    let orchard = inspect!(
        with_orchard_tree_mut,
        orchard,
        ShieldedPool::Orchard,
        reference.final_orchard_tree().root(),
        orchard_leaf
    );
    missing.extend(orchard.into_iter().map(|a| (ShieldedPool::Orchard, a)));
    let ironwood = inspect!(
        with_ironwood_tree_mut,
        ironwood,
        ShieldedPool::Ironwood,
        reference.final_ironwood_tree().root(),
        orchard_leaf
    );
    missing.extend(
        ironwood
            .into_iter()
            .flatten()
            .map(|a| (ShieldedPool::Ironwood, a)),
    );
    Ok(missing)
}

fn orchard_leaf(note: &orchard::Note) -> orchard::tree::MerkleHashOrchard {
    let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
    orchard::tree::MerkleHashOrchard::from_cmx(&cmx)
}

fn inspect_tree<S, const DEPTH: u8, const SHARD_HEIGHT: u8>(
    tree: &mut ShardTree<S, DEPTH, SHARD_HEIGHT>,
    positions: &[(Position, S::H)],
    anchor: BlockHeight,
    expected_root: &S::H,
) -> Result<Vec<Address>, ShardTreeError<S::Error>>
where
    S: ShardStore<CheckpointId = BlockHeight>,
    S::H: Hashable + Clone + PartialEq,
{
    if positions.is_empty() {
        return Ok(vec![]);
    }
    let mut missing = BTreeSet::new();
    for (position, leaf) in positions {
        match tree.witness_at_checkpoint_id_caching(*position, &anchor) {
            Ok(Some(witness)) => {
                if witness.root(leaf.clone()) != *expected_root {
                    return Err(QueryError::TreeIncomplete(vec![ShardTree::<
                        S,
                        DEPTH,
                        SHARD_HEIGHT,
                    >::root_addr(
                    )])
                    .into());
                }
            }
            Ok(None) => return Err(QueryError::CheckpointPruned.into()),
            Err(ShardTreeError::Query(QueryError::TreeIncomplete(addresses))) => {
                missing.extend(addresses)
            }
            Err(error) => return Err(error),
        }
    }
    if missing.is_empty() {
        // Check the root independently of the sparse data used to repair the
        // witness. Never silently fall back to a funding-height anchor.
        if tree.root_at_checkpoint_id(&anchor)?.as_ref() != Some(expected_root) {
            return Err(QueryError::TreeIncomplete(vec![
                ShardTree::<S, DEPTH, SHARD_HEIGHT>::root_addr(),
            ])
            .into());
        }
        tree.ensure_retained(anchor)?;
    }
    Ok(missing.into_iter().collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use incrementalmerkletree::{frontier::Frontier, Marking, Retention};
    use orchard::tree::MerkleHashOrchard;
    use shardtree::store::memory::MemoryShardStore;

    #[test]
    fn sparse_boundaries_advance_a_marked_note_across_shards() {
        let mut frontier = Frontier::<MerkleHashOrchard, 32>::empty();
        let mut frontiers = vec![];
        let mut leaves = vec![];
        for i in 1..=97u8 {
            let mut bytes = [0; 32];
            bytes[0] = i;
            let leaf = MerkleHashOrchard::from_bytes(&bytes).unwrap();
            leaves.push(leaf);
            frontier.append(leaf);
            frontiers.push(frontier.clone());
        }
        // Small shards exercise both intra-shard siblings and cap nodes. Only
        // the funding leaf and the latest frontier are initially available.
        let mut tree = ShardTree::<MemoryShardStore<_, BlockHeight>, 32, 4>::new(
            MemoryShardStore::empty(),
            100,
        );
        let anchor = BlockHeight::from(200);
        tree.insert_frontier(frontiers[0].clone(), Retention::Marked)
            .unwrap();
        tree.insert_frontier(
            frontier.clone(),
            Retention::Checkpoint {
                id: anchor,
                marking: Marking::None,
            },
        )
        .unwrap();
        let position = Position::from(0);
        assert!(!inspect_tree(
            &mut tree,
            &[(position, leaves[0])],
            anchor,
            &frontier.root()
        )
        .unwrap()
        .is_empty());
        let mut repairs = 0;
        loop {
            let missing = inspect_tree(
                &mut tree,
                &[(position, leaves[0])],
                anchor,
                &frontier.root(),
            )
            .unwrap();
            let Some(address) = missing.first() else {
                break;
            };
            let size = u64::from(address.position_range_end()).min(frontier.tree_size());
            tree.insert_frontier(frontiers[size as usize - 1].clone(), Retention::Ephemeral)
                .unwrap();
            repairs += 1;
            assert!(repairs <= 32, "must repair tree nodes, not every leaf");
        }
        let witness = tree
            .witness_at_checkpoint_id(position, &anchor)
            .unwrap()
            .unwrap();
        assert_eq!(witness.root(leaves[0]), frontier.root());
        assert!(repairs < leaves.len());
        assert!(
            inspect_tree(
                &mut tree,
                &[(position, leaves[1])],
                anchor,
                &frontier.root()
            )
            .is_err(),
            "the witness must commit to the actual funding note, not just a cached root"
        );
        assert!(
            inspect_tree(
                &mut tree,
                &[(position, leaves[0])],
                anchor,
                &frontiers[0].root()
            )
            .is_err(),
            "must reject an old or inconsistent reference root"
        );
    }
}
