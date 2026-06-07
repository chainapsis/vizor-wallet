//! Vote commitment tree sync and VAN witness generation.
//!
//! Manages per-round in-memory `TreeClient` instances that sync incrementally
//! from a chain node via HTTP, then generates Merkle authentication paths
//! (witnesses) for Vote Authority Notes (VANs) needed by ZKP #2.

use std::collections::{BTreeSet, HashMap};
use std::sync::{Arc, Mutex};

use vote_commitment_tree::{MerklePath, TreeClient, TreeSyncApi};
use vote_commitment_tree_client::http_sync_api::HttpTreeSyncApi;

use crate::storage::VotingDb;
use crate::types::VotingError;
use crate::vote::{VanWitness, VAN_AUTH_PATH_LEN};
use crate::HyperTransport;

impl From<(MerklePath, u32)> for VanWitness {
    fn from((path, anchor_height): (MerklePath, u32)) -> Self {
        let auth_path = path
            .auth_path()
            .iter()
            .take(VAN_AUTH_PATH_LEN)
            .map(|hash| hash.to_bytes().to_vec())
            .collect();
        Self {
            auth_path,
            position: path.position(),
            anchor_height,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pasta_curves::Fp;
    use vote_commitment_tree::MemoryTreeServer;

    use crate::{governance::BALLOT_DIVISOR, round::RoundParams, types::NoteInfo};

    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const WALLET_ID: &str = "wallet-tree-sync";

    #[test]
    fn sync_rebuilds_when_recovery_marks_already_synced_position() {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(&round_params(), None).unwrap();
        let notes = (0..6).map(note).collect::<Vec<_>>();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        db.store_van_position(ROUND_ID, 1, 1).unwrap();

        let sync = VoteTreeSync::new();
        let server = server_with_single_leaf_blocks(7);

        let height = sync.sync_with_api(&db, ROUND_ID, &server).unwrap();
        assert_eq!(height, 7);

        // A resumed wallet may confirm earlier cast-vote transactions after a
        // tree sync already passed their new VAN leaves. Those positions must
        // still be retained for later vote witnesses.
        db.store_van_position(ROUND_ID, 0, 2).unwrap();
        db.store_van_position(ROUND_ID, 1, 4).unwrap();

        let height = sync.sync_with_api(&db, ROUND_ID, &server).unwrap();
        let witness = sync.generate_van_witness(&db, ROUND_ID, 1, height).unwrap();

        assert_eq!(height, 7);
        assert_eq!(witness.position, 4);
        assert_eq!(witness.anchor_height, 7);
    }

    fn server_with_single_leaf_blocks(count: u32) -> MemoryTreeServer {
        let mut server = MemoryTreeServer::empty();
        for index in 0..count {
            server.append(Fp::from(u64::from(index + 1))).unwrap();
            server.checkpoint(index + 1).unwrap();
        }
        server
    }

    fn round_params() -> RoundParams {
        RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn note(position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![1; 32],
            nullifier: {
                let mut nf = vec![2; 32];
                nf[0] = position as u8;
                nf
            },
            value: BALLOT_DIVISOR + 500_000,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}

struct RoundTreeClient {
    client: TreeClient,
    marked_positions: BTreeSet<u64>,
}

impl RoundTreeClient {
    fn empty() -> Self {
        Self {
            client: TreeClient::empty(),
            marked_positions: BTreeSet::new(),
        }
    }

    fn needs_resync_for(&self, positions: &BTreeSet<u64>) -> bool {
        positions
            .iter()
            .any(|pos| !self.marked_positions.contains(pos) && *pos < self.client.size())
    }

    fn mark_positions(&mut self, positions: &BTreeSet<u64>) {
        for pos in positions {
            self.client.mark_position(*pos);
        }
        self.marked_positions.extend(positions.iter().copied());
    }
}

/// Manages per-round in-memory vote commitment trees for VAN witness generation.
///
/// Wraps a `HashMap<String, RoundTreeClient>` behind a `Mutex` for thread-safe
/// per-round incremental sync. Each round gets its own `TreeClient`, created
/// lazily on first `sync` call for that round.
pub struct VoteTreeSync {
    clients: Mutex<HashMap<String, RoundTreeClient>>,
    transport: Arc<HyperTransport>,
}

impl VoteTreeSync {
    pub fn new() -> Self {
        Self {
            clients: Mutex::new(HashMap::new()),
            transport: Arc::new(HyperTransport::new()),
        }
    }

    /// Sync the vote commitment tree for a specific round from a chain node.
    ///
    /// Creates a per-round `TreeClient` on first call, then syncs incrementally
    /// on subsequent calls. VAN positions from ALL bundles are automatically
    /// marked for witness generation before syncing. If recovery records a new
    /// VAN position that is already behind the synced tip, the round client is
    /// rebuilt so the sparse tree retains that historical leaf.
    ///
    /// Returns the latest synced block height.
    pub fn sync(&self, db: &VotingDb, round_id: &str, node_url: &str) -> Result<u32, VotingError> {
        let api = HttpTreeSyncApi::new(node_url, round_id, self.transport.clone());
        self.sync_with_api(db, round_id, &api)
    }

    fn sync_with_api<A>(&self, db: &VotingDb, round_id: &str, api: &A) -> Result<u32, VotingError>
    where
        A: TreeSyncApi,
    {
        let bundle_count = db.get_bundle_count(round_id)?;
        let mut positions = BTreeSet::new();
        for bi in 0..bundle_count {
            if let Ok(pos) = db.load_van_position(round_id, bi) {
                positions.insert(u64::from(pos));
            }
        }

        let mut guard = self.clients.lock().map_err(|e| VotingError::Internal {
            message: format!("tree client lock poisoned: {}", e),
        })?;

        let round_client = guard
            .entry(round_id.to_string())
            .or_insert_with(RoundTreeClient::empty);

        if round_client.needs_resync_for(&positions) {
            *round_client = RoundTreeClient::empty();
        }
        round_client.mark_positions(&positions);

        round_client
            .client
            .sync(api)
            .map_err(|e| VotingError::Internal {
                message: format!("vote tree sync failed: {}", e),
            })?;

        // Empty tree is valid before the first delegation commitment is appended.
        // Report height 0 so callers can proceed instead of failing sync.
        Ok(round_client.client.last_synced_height().unwrap_or(0))
    }

    /// Generate a VAN Merkle witness for ZKP #2.
    ///
    /// Requires `sync` to have been called first for this round. Loads the VAN
    /// position for the specified bundle and generates a witness at the given
    /// anchor height.
    pub fn generate_van_witness(
        &self,
        db: &VotingDb,
        round_id: &str,
        bundle_index: u32,
        anchor_height: u32,
    ) -> Result<VanWitness, VotingError> {
        let van_position = db.load_van_position(round_id, bundle_index)?;

        let guard = self.clients.lock().map_err(|e| VotingError::Internal {
            message: format!("tree client lock poisoned: {}", e),
        })?;

        let round_client = guard
            .get(round_id)
            .ok_or_else(|| VotingError::InvalidInput {
                message: "must call sync before generate_van_witness".to_string(),
            })?;

        let path = round_client
            .client
            .witness(van_position as u64, anchor_height)
            .ok_or_else(|| VotingError::Internal {
                message: format!(
                    "failed to generate witness for position {} at height {}",
                    van_position, anchor_height
                ),
            })?;

        Ok(VanWitness::from((path, anchor_height)))
    }

    /// Drop the in-memory TreeClient for a round so the next `sync` call
    /// creates a fresh one and does a full resync. This recovers from stale
    /// state that would otherwise cause `StartIndexMismatch` or `RootMismatch`.
    /// If `round_id` is empty, all clients are dropped.
    pub fn reset(&self, round_id: &str) -> Result<(), VotingError> {
        let mut guard = self.clients.lock().map_err(|e| VotingError::Internal {
            message: format!("tree client lock poisoned: {}", e),
        })?;
        if round_id.is_empty() {
            guard.clear();
        } else {
            guard.remove(round_id);
        }
        Ok(())
    }
}
