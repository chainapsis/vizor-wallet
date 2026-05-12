use super::{state::open_voting_db, vote::VoteRecord};

/// Stored commitment bundle recovery data for one `(bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommitmentBundleRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub commitment_bundle_json: String,
    pub vc_tree_position: u64,
}

/// Stored delegation transaction hash for one voting note bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationTxRecovery {
    pub bundle_index: u32,
    pub tx_hash: String,
}

/// Stored vote transaction hash for one `(bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteTxRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub tx_hash: String,
}

/// Stored helper-server share delegation state for retry/resume.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShareDelegationRecord {
    pub round_id: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub sent_to_urls: Vec<String>,
    pub nullifier: Vec<u8>,
    pub confirmed: bool,
    pub submit_at: u64,
    pub created_at: u64,
}

/// Recovery summary for one round.
///
/// Resume semantics:
/// - A delegation bundle is complete once its `delegation_tx_hash` is stored.
/// - A vote is complete once its vote tx hash and/or commitment bundle recovery
///   fields exist for the same `(bundle_index, proposal_id)`.
/// - Share submission resumes from unconfirmed share delegations, preserving
///   the merged `sent_to_urls` history.
/// - `clear_recovery_state` is an explicit escape hatch for finalized or
///   abandoned rounds, not part of normal retry flow.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RoundRecoveryState {
    pub round_id: String,
    pub bundle_count: u32,
    pub delegation_tx_hashes: Vec<DelegationTxRecovery>,
    pub votes: Vec<VoteRecord>,
    pub vote_tx_hashes: Vec<VoteTxRecovery>,
    pub commitment_bundles: Vec<CommitmentBundleRecovery>,
    pub share_delegations: Vec<ShareDelegationRecord>,
    pub unconfirmed_share_delegations: Vec<ShareDelegationRecord>,
}

/// Loads the persisted recovery snapshot for a voting round.
///
/// The snapshot is keyed by `db_path`, `wallet_id`, and `round_id`, and includes
/// bundle-level delegation tx hashes, vote records, vote tx hashes, commitment
/// bundles, and share delegation retry state. Missing recovery rows are omitted
/// rather than synthesized.
///
/// # Errors
///
/// Returns an error if the voting sidecar database cannot be opened or any
/// recovery table query fails.
pub fn get_round_recovery_state(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<RoundRecoveryState, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    let bundle_count = voting_db
        .get_bundle_count(round_id)
        .map_err(|e| format!("get_bundle_count failed: {e}"))?;
    let votes = voting_db
        .get_votes(round_id)
        .map_err(|e| format!("get_votes failed: {e}"))?
        .into_iter()
        .map(|record| VoteRecord {
            proposal_id: record.proposal_id,
            bundle_index: record.bundle_index,
            choice: record.choice,
            submitted: record.submitted,
        })
        .collect::<Vec<_>>();

    let mut delegation_tx_hashes = Vec::new();
    for bundle_index in 0..bundle_count {
        if let Some(tx_hash) = voting_db
            .get_delegation_tx_hash(round_id, bundle_index)
            .map_err(|e| format!("get_delegation_tx_hash failed: {e}"))?
        {
            delegation_tx_hashes.push(DelegationTxRecovery {
                bundle_index,
                tx_hash,
            });
        }
    }

    let mut vote_tx_hashes = Vec::new();
    let mut commitment_bundles = Vec::new();
    for vote in &votes {
        if let Some(tx_hash) = voting_db
            .get_vote_tx_hash(round_id, vote.bundle_index, vote.proposal_id)
            .map_err(|e| format!("get_vote_tx_hash failed: {e}"))?
        {
            vote_tx_hashes.push(VoteTxRecovery {
                bundle_index: vote.bundle_index,
                proposal_id: vote.proposal_id,
                tx_hash,
            });
        }

        if let Some((commitment_bundle_json, vc_tree_position)) = voting_db
            .get_commitment_bundle(round_id, vote.bundle_index, vote.proposal_id)
            .map_err(|e| format!("get_commitment_bundle failed: {e}"))?
        {
            commitment_bundles.push(CommitmentBundleRecovery {
                bundle_index: vote.bundle_index,
                proposal_id: vote.proposal_id,
                commitment_bundle_json,
                vc_tree_position,
            });
        }
    }

    let share_delegations = get_share_delegations_from_db(&voting_db, round_id)?;
    let unconfirmed_share_delegations =
        get_unconfirmed_share_delegations_from_db(&voting_db, round_id)?;

    Ok(RoundRecoveryState {
        round_id: round_id.to_string(),
        bundle_count,
        delegation_tx_hashes,
        votes,
        vote_tx_hashes,
        commitment_bundles,
        share_delegations,
        unconfirmed_share_delegations,
    })
}

/// Persists the broadcast transaction hash for a vote and marks that vote submitted.
///
/// The `(round_id, bundle_index, proposal_id)` tuple must identify an existing
/// vote row. After storing, the value is read back and must match `tx_hash`.
///
/// # Errors
///
/// Returns an error if storage fails, the vote row is missing, or read-after-write
/// verification observes a different hash.
pub fn store_vote_tx_hash(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .store_vote_tx_hash(round_id, bundle_index, proposal_id, tx_hash)
        .map_err(|e| format!("store_vote_tx_hash failed: {e}"))?;
    voting_db
        .mark_vote_submitted(round_id, bundle_index, proposal_id)
        .map_err(|e| format!("mark_vote_submitted failed: {e}"))?;
    match voting_db
        .get_vote_tx_hash(round_id, bundle_index, proposal_id)
        .map_err(|e| format!("get_vote_tx_hash failed after store: {e}"))?
    {
        Some(stored) if stored == tx_hash => Ok(()),
        Some(stored) => Err(format!(
            "stored vote tx hash {stored} did not match requested tx hash {tx_hash}"
        )),
        None => Err(format!(
            "no vote row found for bundle_index {bundle_index}, proposal_id {proposal_id}"
        )),
    }
}

/// Returns the stored vote transaction hash for one vote, when present.
///
/// `None` means no recovery hash has been persisted for the exact
/// `(round_id, bundle_index, proposal_id)` key.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_vote_tx_hash(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<String>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_vote_tx_hash(round_id, bundle_index, proposal_id)
        .map_err(|e| format!("get_vote_tx_hash failed: {e}"))
}

/// Returns the stored commitment bundle recovery payload for one vote.
///
/// The returned value preserves the caller-supplied `bundle_index` and
/// `proposal_id` alongside the stored bundle JSON and vote commitment tree
/// position.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_commitment_bundle(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<CommitmentBundleRecovery>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_commitment_bundle(round_id, bundle_index, proposal_id)
        .map(|bundle| {
            bundle.map(
                |(commitment_bundle_json, vc_tree_position)| CommitmentBundleRecovery {
                    bundle_index,
                    proposal_id,
                    commitment_bundle_json,
                    vc_tree_position,
                },
            )
        })
        .map_err(|e| format!("get_commitment_bundle failed: {e}"))
}

/// Records helper-server share delegation progress for retry/resume.
///
/// `sent_to_urls` is the set of helper endpoints already attempted for the share,
/// `nullifier` is the share nullifier bytes, and `submit_at` is the caller-owned
/// retry scheduling timestamp.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or the share record
/// cannot be persisted.
pub fn record_share_delegation(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    nullifier: &[u8],
    submit_at: u64,
) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .record_share_delegation(
            round_id,
            bundle_index,
            proposal_id,
            share_index,
            sent_to_urls,
            nullifier,
            submit_at,
        )
        .map_err(|e| format!("record_share_delegation failed: {e}"))
}

/// Lists all stored share delegation records for a round.
///
/// Returned records include both confirmed and unconfirmed shares.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_share_delegations(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    get_share_delegations_from_db(&voting_db, round_id)
}

/// Lists share delegation records that still need confirmation.
///
/// A returned record may already have `sent_to_urls` populated; callers should
/// preserve that history when retrying helper submission.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_unconfirmed_share_delegations(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    get_unconfirmed_share_delegations_from_db(&voting_db, round_id)
}

/// Marks one share delegation as confirmed.
///
/// The key is the exact `(round_id, bundle_index, proposal_id, share_index)`
/// tuple previously passed to `record_share_delegation`.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or no matching share
/// delegation can be updated.
pub fn mark_share_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .mark_share_confirmed(round_id, bundle_index, proposal_id, share_index)
        .map_err(|e| format!("mark_share_confirmed failed: {e}"))
}

/// Adds helper-server URLs to the sent history for one share delegation.
///
/// Existing URLs are preserved and duplicates are ignored by the storage layer.
/// The share delegation must already exist.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or the share record
/// cannot be updated.
pub fn add_sent_servers(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .add_sent_servers(round_id, bundle_index, proposal_id, share_index, new_urls)
        .map_err(|e| format!("add_sent_servers failed: {e}"))
}

/// Clears retry/recovery artifacts for a voting round.
///
/// This removes delegation tx hashes, vote tx hashes, commitment bundle recovery
/// data, and share delegation tracking for `round_id`. Use only after a round is
/// finalized or intentionally abandoned.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or recovery state
/// cannot be cleared.
pub fn clear_recovery_state(db_path: &str, wallet_id: &str, round_id: &str) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .clear_recovery_state(round_id)
        .map_err(|e| format!("clear_recovery_state failed: {e}"))
}

/// Reads share delegation rows using an already-open voting database.
fn get_share_delegations_from_db(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    voting_db
        .get_share_delegations(round_id)
        .map(|records| {
            records
                .into_iter()
                .map(share_record_from_upstream)
                .collect()
        })
        .map_err(|e| format!("get_share_delegations failed: {e}"))
}

/// Reads only unconfirmed share delegation rows using an already-open database.
fn get_unconfirmed_share_delegations_from_db(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    voting_db
        .get_unconfirmed_delegations(round_id)
        .map(|records| {
            records
                .into_iter()
                .map(share_record_from_upstream)
                .collect()
        })
        .map_err(|e| format!("get_unconfirmed_delegations failed: {e}"))
}

/// Converts the upstream share record into the flat API-facing recovery type.
fn share_record_from_upstream(
    record: zcash_voting::ShareDelegationRecord,
) -> ShareDelegationRecord {
    ShareDelegationRecord {
        round_id: record.round_id,
        bundle_index: record.bundle_index,
        proposal_id: record.proposal_id,
        share_index: record.share_index,
        sent_to_urls: record.sent_to_urls,
        nullifier: record.nullifier,
        confirmed: record.confirmed,
        submit_at: record.submit_at,
        created_at: record.created_at,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::voting::state;

    const WALLET_ID: &str = "wallet-recovery";
    const ROUND_ID: &str = "round-recovery";

    #[test]
    fn vote_tx_hashes_are_isolated_by_bundle_and_proposal() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_vote(0, 2, 1, b"vote-0-2");
        fixture.insert_vote(1, 1, 1, b"vote-1-1");

        store_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "tx-0-1").unwrap();
        store_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 1, 1, "tx-1-1").unwrap();

        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .as_deref(),
            Some("tx-0-1")
        );
        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 2)
                .unwrap()
                .as_deref(),
            None
        );
        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 1, 1)
                .unwrap()
                .as_deref(),
            Some("tx-1-1")
        );
    }

    #[test]
    fn commitment_bundle_recovery_returns_exact_vote_key() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_vote(1, 1, 1, b"vote-1-1");
        fixture
            .db
            .store_commitment_bundle(ROUND_ID, 1, 1, r#"{"bundle":"one"}"#, 42)
            .unwrap();

        assert!(
            get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .is_none()
        );
        let recovery = get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 1, 1)
            .unwrap()
            .unwrap();

        assert_eq!(recovery.bundle_index, 1);
        assert_eq!(recovery.proposal_id, 1);
        assert_eq!(recovery.commitment_bundle_json, r#"{"bundle":"one"}"#);
        assert_eq!(recovery.vc_tree_position, 42);
    }

    #[test]
    fn share_delegation_record_add_and_mark_confirmed_flow() {
        let fixture = RecoveryFixture::new();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            &[7; 32],
            1234,
        )
        .unwrap();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &[
                "https://helper-a.example".to_string(),
                "https://helper-b.example".to_string(),
            ],
            &[8; 32],
            5678,
        )
        .unwrap();

        let shares = get_share_delegations(fixture.path(), WALLET_ID, ROUND_ID).unwrap();
        assert_eq!(shares.len(), 1);
        assert_eq!(
            shares[0].sent_to_urls,
            vec![
                "https://helper-a.example".to_string(),
                "https://helper-b.example".to_string()
            ]
        );
        assert_eq!(shares[0].nullifier, vec![8; 32]);
        assert_eq!(shares[0].submit_at, 5678);

        mark_share_confirmed(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, 0).unwrap();
        assert!(
            get_unconfirmed_share_delegations(fixture.path(), WALLET_ID, ROUND_ID)
                .unwrap()
                .is_empty()
        );
        assert!(mark_share_confirmed(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, 9).is_err());
    }

    #[test]
    fn add_sent_servers_merges_and_deduplicates_urls() {
        let fixture = RecoveryFixture::new();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            &[7; 32],
            1234,
        )
        .unwrap();

        add_sent_servers(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &[
                "https://helper-a.example".to_string(),
                "https://helper-c.example".to_string(),
            ],
        )
        .unwrap();

        let shares = get_share_delegations(fixture.path(), WALLET_ID, ROUND_ID).unwrap();
        assert_eq!(
            shares[0].sent_to_urls,
            vec![
                "https://helper-a.example".to_string(),
                "https://helper-c.example".to_string()
            ]
        );
        assert_eq!(shares[0].submit_at, 0);
    }

    #[test]
    fn round_recovery_state_summarizes_mixed_state() {
        let fixture = RecoveryFixture::new();
        fixture
            .db
            .store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_vote(1, 2, 1, b"vote-1-2");
        store_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 1, 2, "vote-tx-1-2").unwrap();
        fixture
            .db
            .store_commitment_bundle(ROUND_ID, 1, 2, r#"{"bundle":"two"}"#, 77)
            .unwrap();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            1,
            2,
            0,
            &["https://helper-a.example".to_string()],
            &[9; 32],
            0,
        )
        .unwrap();

        let state = get_round_recovery_state(fixture.path(), WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(state.round_id, ROUND_ID);
        assert_eq!(state.bundle_count, 2);
        assert_eq!(state.delegation_tx_hashes.len(), 1);
        assert_eq!(state.votes.len(), 2);
        assert_eq!(state.vote_tx_hashes[0].tx_hash, "vote-tx-1-2");
        assert_eq!(state.commitment_bundles[0].vc_tree_position, 77);
        assert_eq!(state.share_delegations.len(), 1);
        assert_eq!(state.unconfirmed_share_delegations.len(), 1);
    }

    #[test]
    fn store_vote_tx_hash_marks_vote_submitted() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");

        store_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();

        let votes = fixture.db.get_votes(ROUND_ID).unwrap();
        assert_eq!(votes.len(), 1);
        assert_eq!(votes[0].proposal_id, 1);
        assert_eq!(votes[0].bundle_index, 0);
        assert!(votes[0].submitted);
    }

    #[test]
    fn clear_recovery_state_clears_recovery_columns_and_share_tracking() {
        let fixture = RecoveryFixture::new();
        fixture
            .db
            .store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        store_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();
        fixture
            .db
            .store_commitment_bundle(ROUND_ID, 0, 1, r#"{"bundle":"one"}"#, 11)
            .unwrap();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            &[7; 32],
            0,
        )
        .unwrap();

        clear_recovery_state(fixture.path(), WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(
            fixture
                .db
                .get_delegation_tx_hash(ROUND_ID, 0)
                .unwrap()
                .as_deref(),
            None
        );
        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .as_deref(),
            None
        );
        assert!(
            get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .is_none()
        );
        assert!(get_share_delegations(fixture.path(), WALLET_ID, ROUND_ID)
            .unwrap()
            .is_empty());
    }

    struct RecoveryFixture {
        _temp_dir: tempfile::TempDir,
        db_path: std::path::PathBuf,
        db: zcash_voting::storage::VotingDb,
    }

    impl RecoveryFixture {
        fn new() -> Self {
            let temp_dir = tempfile::tempdir().unwrap();
            let db_path = temp_dir.path().join("voting.sqlite");
            let db = state::open_voting_db(db_path.to_str().unwrap(), WALLET_ID).unwrap();
            state::init_voting_round(&db, &test_round_params(), None).unwrap();
            let notes: Vec<_> = (0..6).map(test_note_info).collect();
            db.setup_bundles(ROUND_ID, &notes).unwrap();
            Self {
                _temp_dir: temp_dir,
                db_path,
                db,
            }
        }

        fn path(&self) -> &str {
            self.db_path.to_str().unwrap()
        }

        fn insert_vote(&self, bundle_index: u32, proposal_id: u32, choice: u32, commitment: &[u8]) {
            let conn = self.db.conn();
            zcash_voting::storage::queries::store_vote(
                &conn,
                ROUND_ID,
                WALLET_ID,
                bundle_index,
                proposal_id,
                choice,
                commitment,
            )
            .unwrap();
        }
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_note_info(position: u64) -> zcash_voting::NoteInfo {
        zcash_voting::NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: zcash_voting::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}
