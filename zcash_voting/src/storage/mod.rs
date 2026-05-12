mod migrations;
pub mod operations;
pub mod queries;

use std::sync::Mutex;

use rusqlite::Connection;

use crate::types::VotingError;

/// Current phase of a voting round.
///
/// Discriminants are ordered lifecycle ranks; `advance_round_phase` compares
/// them to enforce forward-only progression.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(i32)]
pub enum RoundPhase {
    Initialized = 0,
    HotkeyGenerated = 1,
    DelegationConstructed = 2,
    DelegationProved = 3,
    VoteReady = 4,
}

impl RoundPhase {
    pub fn from_i32(v: i32) -> Self {
        match v {
            0 => Self::Initialized,
            1 => Self::HotkeyGenerated,
            2 => Self::DelegationConstructed,
            3 => Self::DelegationProved,
            4 => Self::VoteReady,
            _ => Self::Initialized,
        }
    }
}

/// Summary state of a voting round (for UI / SDK queries).
#[derive(Clone, Debug)]
pub struct RoundState {
    pub round_id: String,
    pub phase: RoundPhase,
    pub snapshot_height: u64,
    pub hotkey_address: Option<String>,
    pub delegated_weight: Option<u64>,
    pub proof_generated: bool,
}

/// A vote record from the votes table.
#[derive(Clone, Debug)]
pub struct VoteRecord {
    pub proposal_id: u32,
    pub bundle_index: u32,
    pub choice: u32,
    pub submitted: bool,
}

/// Compact round info for list_rounds().
#[derive(Clone, Debug)]
pub struct RoundSummary {
    pub round_id: String,
    pub wallet_id: String,
    pub phase: RoundPhase,
    pub snapshot_height: u64,
    pub created_at: u64,
}

/// A Keystone bundle signature stored in the DB.
#[derive(Clone, Debug)]
pub struct KeystoneSignatureRecord {
    pub bundle_index: u32,
    pub sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub rk: Vec<u8>,
}

/// Database handle for voting state. Wraps a SQLite connection and a
/// wallet identifier that scopes all round data to a single wallet.
pub struct VotingDb {
    conn: Mutex<Connection>,
    wallet_id: Mutex<String>,
}

impl VotingDb {
    /// Open (or create) the voting database at the given path.
    /// Runs migrations automatically.
    /// Call `set_wallet_id` before performing any round operations.
    pub fn open(path: &str) -> Result<Self, VotingError> {
        let conn = if path == ":memory:" {
            Connection::open_in_memory()
        } else {
            Connection::open(path)
        }
        .map_err(|e| VotingError::Internal {
            message: format!("failed to open database: {}", e),
        })?;

        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            .map_err(|e| VotingError::Internal {
                message: format!("failed to set pragmas: {}", e),
            })?;

        migrations::migrate(&conn)?;

        Ok(Self {
            conn: Mutex::new(conn),
            wallet_id: Mutex::new(String::new()),
        })
    }

    /// Set the wallet identifier used to scope all subsequent operations.
    pub fn set_wallet_id(&self, id: &str) {
        *self.wallet_id.lock().expect("wallet_id mutex poisoned") = id.to_string();
    }

    /// Get the current wallet identifier. Panics if not set.
    pub fn wallet_id(&self) -> String {
        let id = self
            .wallet_id
            .lock()
            .expect("wallet_id mutex poisoned")
            .clone();
        assert!(
            !id.is_empty(),
            "wallet_id must be set before performing voting operations"
        );
        id
    }

    /// Get a lock on the underlying connection for query execution.
    pub fn conn(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.conn.lock().expect("database mutex poisoned")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::VotingRoundParams;

    const W: &str = "test-wallet";

    fn test_db() -> VotingDb {
        VotingDb::open(":memory:").unwrap()
    }

    fn test_params() -> VotingRoundParams {
        VotingRoundParams {
            vote_round_id: "test-round-1".to_string(),
            snapshot_height: 1000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    #[test]
    fn test_open_in_memory() {
        let db = test_db();
        let conn = db.conn();
        let version: u32 = conn
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, 8);
    }

    #[test]
    fn test_round_lifecycle() {
        let db = test_db();
        let conn = db.conn();
        let params = test_params();

        queries::insert_round(&conn, W, &params, None).unwrap();

        let state = queries::get_round_state(&conn, "test-round-1", W).unwrap();
        assert_eq!(state.phase, RoundPhase::Initialized);
        assert_eq!(state.snapshot_height, 1000);
        assert!(!state.proof_generated);

        let rounds = queries::list_rounds(&conn, W).unwrap();
        assert_eq!(rounds.len(), 1);
        assert_eq!(rounds[0].round_id, "test-round-1");

        queries::clear_round(&conn, "test-round-1", W).unwrap();
        let rounds = queries::list_rounds(&conn, W).unwrap();
        assert!(rounds.is_empty());
    }

    #[test]
    fn test_tree_state_cache() {
        let db = test_db();
        let conn = db.conn();
        queries::insert_round(&conn, W, &test_params(), None).unwrap();

        let tree_state = vec![0xCC; 1024];
        queries::store_tree_state(&conn, "test-round-1", W, 1000, &tree_state).unwrap();

        let loaded = queries::load_tree_state(&conn, "test-round-1", W).unwrap();
        assert_eq!(loaded, tree_state);
    }

    #[test]
    fn test_proof_storage() {
        let db = test_db();
        let conn = db.conn();
        queries::insert_round(&conn, W, &test_params(), None).unwrap();
        queries::insert_bundle(&conn, "test-round-1", W, 0, &[]).unwrap();
        queries::store_proof(&conn, "test-round-1", W, 0, &vec![0xAB; 256]).unwrap();

        let state = queries::get_round_state(&conn, "test-round-1", W).unwrap();
        assert!(!state.proof_generated, "proof alone should not be enough");

        queries::store_van_position(&conn, "test-round-1", W, 0, 42).unwrap();
        let state = queries::get_round_state(&conn, "test-round-1", W).unwrap();
        assert!(
            state.proof_generated,
            "proof + VAN position should be enough"
        );
    }

    #[test]
    fn test_vote_storage() {
        let db = test_db();
        let conn = db.conn();
        queries::insert_round(&conn, W, &test_params(), None).unwrap();
        queries::insert_bundle(&conn, "test-round-1", W, 0, &[]).unwrap();

        let commitment = vec![0xCC; 128];
        queries::store_vote(&conn, "test-round-1", W, 0, 0, 0, &commitment).unwrap();
        queries::store_vote(&conn, "test-round-1", W, 0, 1, 1, &commitment).unwrap();

        queries::mark_vote_submitted(&conn, "test-round-1", W, 0, 0).unwrap();
        queries::mark_vote_submitted(&conn, "test-round-1", W, 0, 0).unwrap();

        let err = queries::mark_vote_submitted(&conn, "test-round-1", W, 0, 99).unwrap_err();
        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }

    #[test]
    fn test_get_votes() {
        let db = test_db();
        let conn = db.conn();
        queries::insert_round(&conn, W, &test_params(), None).unwrap();
        queries::insert_bundle(&conn, "test-round-1", W, 0, &[]).unwrap();

        let votes = queries::get_votes(&conn, "test-round-1", W).unwrap();
        assert!(votes.is_empty());

        let commitment = vec![0xCC; 128];
        queries::store_vote(&conn, "test-round-1", W, 0, 0, 0, &commitment).unwrap();
        queries::store_vote(&conn, "test-round-1", W, 0, 1, 2, &commitment).unwrap();

        let votes = queries::get_votes(&conn, "test-round-1", W).unwrap();
        assert_eq!(votes.len(), 2);
        assert_eq!(votes[0].proposal_id, 0);
        assert_eq!(votes[0].choice, 0);
        assert!(!votes[0].submitted);
        assert_eq!(votes[1].proposal_id, 1);
        assert_eq!(votes[1].choice, 2);

        queries::mark_vote_submitted(&conn, "test-round-1", W, 0, 0).unwrap();
        let votes = queries::get_votes(&conn, "test-round-1", W).unwrap();
        assert!(votes[0].submitted);
        assert!(!votes[1].submitted);
    }

    #[test]
    fn test_wallet_isolation() {
        let db = test_db();
        let conn = db.conn();
        let params = test_params();

        queries::insert_round(&conn, "wallet-a", &params, None).unwrap();
        queries::insert_round(&conn, "wallet-b", &params, None).unwrap();

        queries::insert_bundle(&conn, "test-round-1", "wallet-a", 0, &[]).unwrap();
        queries::insert_bundle(&conn, "test-round-1", "wallet-b", 0, &[]).unwrap();

        let commitment = vec![0xCC; 128];
        queries::store_vote(&conn, "test-round-1", "wallet-a", 0, 0, 1, &commitment).unwrap();
        queries::store_vote(&conn, "test-round-1", "wallet-b", 0, 0, 2, &commitment).unwrap();

        let votes_a = queries::get_votes(&conn, "test-round-1", "wallet-a").unwrap();
        let votes_b = queries::get_votes(&conn, "test-round-1", "wallet-b").unwrap();
        assert_eq!(votes_a.len(), 1);
        assert_eq!(votes_b.len(), 1);
        assert_eq!(votes_a[0].choice, 1);
        assert_eq!(votes_b[0].choice, 2);

        queries::clear_round(&conn, "test-round-1", "wallet-a").unwrap();
        let rounds_b = queries::list_rounds(&conn, "wallet-b").unwrap();
        assert_eq!(
            rounds_b.len(),
            1,
            "wallet-b round should survive wallet-a clear"
        );
    }
}
