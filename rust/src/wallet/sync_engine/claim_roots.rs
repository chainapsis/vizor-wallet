//! Public tree data reuse for isolated gift-card wallets.

use std::time::{Duration, Instant};

use orchard::tree::MerkleHashOrchard;
use rusqlite::{params, OptionalExtension};
use tonic::transport::Channel;
use zcash_client_backend::{
    data_api::{chain::CommitmentTreeRoot, WalletCommitmentTrees, WalletRead},
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

use super::{lwd, SyncError, WalletDatabase};
use crate::wallet::{
    db::{open_readonly_conn_with_timeout, with_wallet_db_write_lock},
    network::WalletNetwork,
    wallet_summary_cache::get_wallet_summary_cached,
};

struct RootSnapshot {
    height: u32,
    hash: [u8; 32],
    complete_count: u64,
    roots: Vec<CommitmentTreeRoot<MerkleHashOrchard>>,
}

// Read one SQLite snapshot. Never import accounts, notes, or a partial frontier
// from the main wallet, and never wait for its sync writer to finish.
fn read_snapshot(path: &str, tip: BlockHeight) -> Result<Option<RootSnapshot>, String> {
    let mut conn = open_readonly_conn_with_timeout(path, Some(Duration::from_millis(50)))?;
    let tx = conn.transaction().map_err(|e| e.to_string())?;
    let checkpoint = tx
        .query_row(
            "SELECT height, hash, ironwood_commitment_tree_size FROM blocks
         WHERE height <= ?1 AND ironwood_commitment_tree_size IS NOT NULL
         ORDER BY height DESC LIMIT 1",
            [u32::from(tip)],
            |row| {
                Ok((
                    row.get::<_, u32>(0)?,
                    row.get::<_, Vec<u8>>(1)?,
                    row.get::<_, u64>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| e.to_string())?;
    let Some((height, hash, size)) = checkpoint else {
        return Ok(None);
    };
    let hash = hash.try_into().map_err(|_| "Invalid cached block hash")?;
    let complete_count = size >> zcash_client_backend::data_api::ORCHARD_SHARD_HEIGHT;
    let mut statement = tx
        .prepare(
            "SELECT shard_index, subtree_end_height, root_hash FROM ironwood_tree_shards
         WHERE shard_index < ?1 AND subtree_end_height <= ?2
         ORDER BY shard_index",
        )
        .map_err(|e| e.to_string())?;
    let mut rows = statement
        .query(params![complete_count, height])
        .map_err(|e| e.to_string())?;
    let mut roots = Vec::new();
    while let Some(row) = rows.next().map_err(|e| e.to_string())? {
        let index: u64 = row.get(0).map_err(|e| e.to_string())?;
        // Only a contiguous prefix can seed the destination's subtree cursor.
        if index != roots.len() as u64 {
            break;
        }
        let end: u32 = row.get(1).map_err(|e| e.to_string())?;
        let bytes: Vec<u8> = row.get(2).map_err(|e| e.to_string())?;
        let bytes: [u8; 32] = bytes.try_into().map_err(|_| "Invalid cached root length")?;
        let node = Option::<MerkleHashOrchard>::from(MerkleHashOrchard::from_bytes(&bytes))
            .ok_or("Invalid cached root")?;
        roots.push(CommitmentTreeRoot::from_parts(
            BlockHeight::from_u32(end),
            node,
        ));
    }
    Ok(Some(RootSnapshot {
        height,
        hash,
        complete_count,
        roots,
    }))
}

fn ironwood_only(network: WalletNetwork, birthday: Option<BlockHeight>) -> bool {
    birthday.is_some_and(|height| network.is_nu_active(NetworkUpgrade::Nu6_3, height))
}

fn next_index(path: &str, network: WalletNetwork) -> Result<u64, SyncError> {
    Ok(get_wallet_summary_cached(path, network)
        .map_err(SyncError::db)?
        .map_or(0, |s| s.next_ironwood_subtree_index()))
}

/// Current cards are funded into Ironwood. Older birthdays retain the full
/// pool path because issued links do not encode their funding pool.
pub(super) async fn prepare_roots(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    source_path: Option<&str>,
    network: WalletNetwork,
    tip: BlockHeight,
    tip_hash: &[u8],
) -> Result<(), SyncError> {
    let start = Instant::now();
    let birthday = db
        .get_wallet_birthday()
        .map_err(|e| SyncError::db(e.to_string()))?;
    if !ironwood_only(network, birthday) {
        return lwd::download_subtree_roots(client, db, db_path, network, tip).await;
    }
    let mut cursor = next_index(db_path, network)?;
    let snapshot = source_path
        .filter(|path| *path != db_path)
        .and_then(|path| read_snapshot(path, tip).ok().flatten());
    if let Some(snapshot) = snapshot {
        // A local DB can belong to another network or a replaced chain. Match
        // its checkpoint before accepting any of its roots.
        let matches = if snapshot.height == u32::from(tip) && tip_hash.len() == 32 {
            snapshot.hash.as_slice() == tip_hash
        } else if !snapshot.roots.is_empty() {
            lwd::get_compact_block_hash(client, u64::from(snapshot.height))
                .await
                .is_ok_and(|hash| hash.0 == snapshot.hash)
        } else {
            false
        };
        let overlap_matches = if matches {
            let mut equal = true;
            for index in 0..cursor.min(snapshot.roots.len() as u64) {
                if db
                    .get_ironwood_subtree_root(index)
                    .map_err(|e| SyncError::db(e.to_string()))?
                    != Some(*snapshot.roots[index as usize].root_hash())
                {
                    equal = false;
                    break;
                }
            }
            equal
        } else {
            false
        };
        if overlap_matches {
            let count = snapshot.roots.len() as u64;
            if count > cursor {
                with_wallet_db_write_lock("claim.copy_ironwood_roots", || {
                    db.put_ironwood_subtree_roots(cursor, &snapshot.roots[cursor as usize..])
                        .map_err(|e| SyncError::db(format!("copy Ironwood roots: {e}")))
                })?;
                log::info!("PaymentLinkClaim: reused {} Ironwood roots", count - cursor);
                cursor = count;
            }
            if snapshot.height == u32::from(tip)
                && cursor == snapshot.complete_count
                && count == cursor
            {
                log::info!(
                    "PaymentLinkClaim: roots ready source=local elapsed_ms={}",
                    start.elapsed().as_millis()
                );
                return Ok(());
            }
        }
    }
    log::info!("PaymentLinkClaim: fetching Ironwood roots start_index={cursor}");
    lwd::download_ironwood_subtree_roots(client, db, cursor).await?;
    log::info!(
        "PaymentLinkClaim: roots ready source=server elapsed_ms={}",
        start.elapsed().as_millis()
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::{keys, sync_engine::open_db};
    use zcash_client_backend::data_api::WalletWrite;

    fn wallet(path: &str, height: BlockHeight) -> WalletDatabase {
        let phrase = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&phrase).unwrap();
        let address = keys::derive_software_address(WalletNetwork::Main, &seed, 0).unwrap();
        keys::register_gift_card_observer(
            path,
            WalletNetwork::Main,
            phrase.as_bytes(),
            &address,
            u64::from(u32::from(height)),
        )
        .unwrap();
        let mut db = open_db(path, WalletNetwork::Main).unwrap();
        db.update_chain_tip(height).unwrap();
        db
    }

    // Storage fixture for public chain metadata, not a claim/proof fixture.
    fn checkpoint(path: &str, height: BlockHeight, count: u64) {
        rusqlite::Connection::open(path).unwrap().execute(
            "INSERT INTO blocks (height, hash, time, sapling_tree, ironwood_commitment_tree_size)
             VALUES (?1, ?2, 0, X'000000', ?3)",
            params![u32::from(height), [7u8; 32].as_slice(), count << 16],
        ).unwrap();
    }

    fn root(height: BlockHeight, byte: u8) -> CommitmentTreeRoot<MerkleHashOrchard> {
        let mut bytes = [0; 32];
        bytes[0] = byte;
        CommitmentTreeRoot::from_parts(
            height,
            Option::from(MerkleHashOrchard::from_bytes(&bytes)).unwrap(),
        )
    }

    #[test]
    fn only_post_activation_cards_skip_legacy_roots() {
        let network = WalletNetwork::Main;
        let activation = network.activation_height(NetworkUpgrade::Nu6_3).unwrap();
        assert!(!ironwood_only(network, None));
        assert!(!ironwood_only(network, Some(activation - 1)));
        assert!(ironwood_only(network, Some(activation)));
        assert!(ironwood_only(network, Some(activation + 10)));
    }

    #[tokio::test]
    async fn complete_current_cache_populates_claim_without_any_rpc_and_reuses_it() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.db");
        let dest = dir.path().join("claim.db");
        let (source, dest) = (source.to_str().unwrap(), dest.to_str().unwrap());
        let network = WalletNetwork::Main;
        let tip = network.activation_height(NetworkUpgrade::Nu6_3).unwrap() + 100;
        let mut source_db = wallet(source, tip);
        let roots = [root(tip - 1, 1), root(tip, 2)];
        source_db.put_ironwood_subtree_roots(0, &roots).unwrap();
        checkpoint(source, tip, 2);
        let mut dest_db = wallet(dest, tip);
        // The lazy channel has no server. Success proves no download occurred.
        let mut client =
            CompactTxStreamerClient::new(Channel::from_static("http://127.0.0.1:1").connect_lazy());
        for _ in 0..2 {
            prepare_roots(
                &mut client,
                &mut dest_db,
                dest,
                Some(source),
                network,
                tip,
                &[7; 32],
            )
            .await
            .unwrap();
            assert_eq!(
                dest_db.get_ironwood_subtree_root(0).unwrap(),
                Some(*roots[0].root_hash())
            );
            assert_eq!(
                dest_db.get_ironwood_subtree_root(1).unwrap(),
                Some(*roots[1].root_hash())
            );
        }
    }

    #[tokio::test]
    async fn different_chain_cache_is_not_imported() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.db");
        let dest = dir.path().join("claim.db");
        let (source, dest) = (source.to_str().unwrap(), dest.to_str().unwrap());
        let network = WalletNetwork::Main;
        let tip = network.activation_height(NetworkUpgrade::Nu6_3).unwrap() + 100;
        wallet(source, tip)
            .put_ironwood_subtree_roots(0, &[root(tip, 1)])
            .unwrap();
        checkpoint(source, tip, 1);
        let mut dest_db = wallet(dest, tip);
        let mut client =
            CompactTxStreamerClient::new(Channel::from_static("http://127.0.0.1:1").connect_lazy());
        // Cache rejection must attempt the server; this unreachable server
        // fails, rather than turning an unchecked cached root into success.
        assert!(prepare_roots(
            &mut client,
            &mut dest_db,
            dest,
            Some(source),
            network,
            tip,
            &[8; 32]
        )
        .await
        .is_err());
        assert!(dest_db.get_ironwood_subtree_root(0).unwrap().is_none());
    }

    #[test]
    fn partial_snapshot_excludes_roots_after_checkpoint() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("source.db");
        let path = path.to_str().unwrap();
        let tip = WalletNetwork::Main
            .activation_height(NetworkUpgrade::Nu6_3)
            .unwrap()
            + 100;
        let mut db = wallet(path, tip);
        db.put_ironwood_subtree_roots(0, &[root(tip - 1, 1)])
            .unwrap();
        checkpoint(path, tip, 2);
        let snapshot = read_snapshot(path, tip).unwrap().unwrap();
        assert_eq!(snapshot.complete_count, 2);
        assert_eq!(snapshot.roots.len(), 1);
        db.put_ironwood_subtree_roots(1, &[root(tip + 1, 2)])
            .unwrap();
        assert_eq!(read_snapshot(path, tip).unwrap().unwrap().roots.len(), 1);
        assert!(read_snapshot(path, tip - 1).unwrap().is_none());
    }

    #[test]
    fn cache_missing_or_corrupt_is_optional() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("missing.db");
        assert!(read_snapshot(missing.to_str().unwrap(), BlockHeight::from_u32(1)).is_err());
        assert!(!missing.exists());
        std::fs::write(&missing, b"not a SQLite wallet").unwrap();
        assert!(read_snapshot(missing.to_str().unwrap(), BlockHeight::from_u32(1)).is_err());
    }
}
