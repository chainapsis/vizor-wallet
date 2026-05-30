use crate::wallet::network::WalletNetwork;

use secrecy::SecretVec;

use super::{
    hotkey::voting_hotkey_from_secret, progress::VotingWorkCancellation, state::open_voting_db,
    tree_sync::VanWitness,
};

/// One proposal choice to turn into a signed vote commitment.
pub use zcash_voting::vote::DraftVote;
/// Vote commitments produced for a single bundle index.
pub use zcash_voting::vote::SignedVoteCommitments;

#[allow(clippy::too_many_arguments)]
/// Build signed vote commitments and public share payloads for one bundle.
///
/// The VAN witness must correspond to `round_id` and `bundle_index`. Secret
/// share plaintext and encryption randomness remain inside `zcash_voting`; only
/// ciphertexts, public inputs, and recovery metadata are returned.
pub fn build_vote_commitments<F>(
    db_path: &str,
    wallet_id: &str,
    network: WalletNetwork,
    round_id: &str,
    bundle_index: u32,
    hotkey_seed: &SecretVec<u8>,
    van_witness: VanWitness,
    draft_votes: Vec<DraftVote>,
    on_progress: F,
    cancellation: VotingWorkCancellation,
) -> Result<SignedVoteCommitments, String>
where
    F: Fn(zcash_voting::vote::VoteCommitStage) + Send + Sync + 'static,
{
    let on_progress = std::sync::Arc::new(on_progress);
    let voting_db = open_voting_db(db_path, wallet_id)?;
    let typed_van_witness = zcash_voting::vote::VanWitness::from_wire(
        &van_witness.auth_path,
        van_witness.position,
        van_witness.anchor_height,
    )
    .map_err(|e| e.to_string())?;
    let voting_hotkey = voting_hotkey_from_secret(hotkey_seed, network)?;
    let progress_cancellation = cancellation.clone();
    let vote_stages = on_progress.clone();
    let reporter = zcash_voting::VoteCommitStageBridge::new(move |stage| {
        if progress_cancellation.check().is_ok() {
            vote_stages(stage);
        }
    });

    zcash_voting::vote::commit_batch(
        &voting_db,
        round_id,
        bundle_index,
        &draft_votes,
        &typed_van_witness,
        zcash_voting::vote::VoteSigner::hotkey(&voting_hotkey),
        &cancellation,
        &reporter,
    )
    .map_err(|e| format!("vote commit batch failed: {e}"))
}

/// Reconstruct a signed vote commitment from persisted recovery state.
pub fn recover_vote_commitment(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<SignedVoteCommitments, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::vote::recover_signed_commitments(&voting_db, round_id, bundle_index, proposal_id)
        .map_err(|e| format!("vote commitment recovery failed: {e}"))
}

/// Load stored vote rows for `round_id` in this wallet.
pub fn get_votes(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<zcash_voting::storage::VoteRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_votes(round_id)
        .map_err(|e| format!("get_votes failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_draft_votes_rejects_invalid_inputs_before_db_work() {
        assert!(zcash_voting::vote::validate_draft_votes(&[])
            .unwrap_err()
            .to_string()
            .contains("must not be empty"));
        assert!(zcash_voting::vote::validate_draft_votes(&[DraftVote {
            proposal_id: 0,
            choice: 0,
            num_options: 2,
            vc_tree_position: 0,
            single_share: false,
        }])
        .unwrap_err()
        .to_string()
        .contains("proposal_id"));
        assert!(zcash_voting::vote::validate_draft_votes(&[DraftVote {
            proposal_id: 1,
            choice: 0,
            num_options: 1,
            vc_tree_position: 0,
            single_share: false,
        }])
        .unwrap_err()
        .to_string()
        .contains("num_options"));
        assert!(zcash_voting::vote::validate_draft_votes(&[DraftVote {
            proposal_id: 1,
            choice: 2,
            num_options: 2,
            vc_tree_position: 0,
            single_share: false,
        }])
        .unwrap_err()
        .to_string()
        .contains("vote_decision"));
    }

    #[test]
    fn build_vote_commitments_rejects_out_of_range_bundle_before_vote_work() {
        let temp_dir = tempfile::tempdir().unwrap();
        let wallet_db_path = temp_dir.path().join("wallet.sqlite");
        let db = open_voting_db(wallet_db_path.to_str().unwrap(), "wallet-1").unwrap();
        db.init_round(&test_round_params(), None).unwrap();
        db.ensure_bundles("round-1", &[test_note_info(0)]).unwrap();
        let events = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let captured_events = events.clone();

        let err = build_vote_commitments(
            wallet_db_path.to_str().unwrap(),
            "wallet-1",
            WalletNetwork::Regtest,
            "round-1",
            1,
            &SecretVec::new(vec![7; 32]),
            VanWitness {
                auth_path: vec![vec![7; 32]; zcash_voting::vote::VAN_AUTH_PATH_LEN],
                position: 0,
                anchor_height: 1,
            },
            vec![DraftVote {
                proposal_id: 1,
                choice: 0,
                num_options: 2,
                vc_tree_position: 0,
                single_share: false,
            }],
            move |event| captured_events.lock().unwrap().push(event),
            VotingWorkCancellation::start(
                wallet_db_path.to_str().unwrap(),
                "wallet-1",
                Some("round-1"),
            )
            .unwrap(),
        )
        .unwrap_err();

        assert!(err.contains("bundle_index 1 is out of range for 1 voting bundles"));
        assert!(events.lock().unwrap().is_empty());
    }

    #[test]
    fn van_witness_from_wire_requires_24_32_byte_siblings() {
        let mut witness = VanWitness {
            auth_path: vec![vec![7; 32]; zcash_voting::vote::VAN_AUTH_PATH_LEN],
            position: 0,
            anchor_height: 1,
        };
        assert_eq!(
            zcash_voting::vote::VanWitness::from_wire(
                &witness.auth_path,
                witness.position,
                witness.anchor_height
            )
            .unwrap()
            .auth_path[0],
            [7; 32]
        );

        witness.auth_path.pop();
        assert!(zcash_voting::vote::VanWitness::from_wire(
            &witness.auth_path,
            witness.position,
            witness.anchor_height
        )
        .unwrap_err()
        .to_string()
        .contains("24 siblings"));

        witness.auth_path = vec![vec![7; 31]; zcash_voting::vote::VAN_AUTH_PATH_LEN];
        assert!(zcash_voting::vote::VanWitness::from_wire(
            &witness.auth_path,
            witness.position,
            witness.anchor_height
        )
        .unwrap_err()
        .to_string()
        .contains("32 bytes"));
    }

    #[test]
    fn get_votes_preserves_bundle_index_and_proposal_keys() {
        let temp_dir = tempfile::tempdir().unwrap();
        let wallet_db_path = temp_dir.path().join("wallet.sqlite");
        let voting_db_path = format!("{}.voting", wallet_db_path.to_str().unwrap());
        let db = zcash_voting::storage::VotingDb::open(&voting_db_path).unwrap();
        db.set_wallet_id("wallet-1");
        db.init_round(&test_round_params(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles("round-1", &notes).unwrap();
        let conn = db.conn();
        zcash_voting::storage::queries::store_vote(&conn, "round-1", "wallet-1", 0, 1, 0, b"a")
            .unwrap();
        zcash_voting::storage::queries::store_vote(&conn, "round-1", "wallet-1", 1, 1, 1, b"b")
            .unwrap();
        drop(conn);

        let votes = get_votes(wallet_db_path.to_str().unwrap(), "wallet-1", "round-1").unwrap();

        assert_eq!(votes.len(), 2);
        assert!(votes
            .iter()
            .any(|vote| vote.proposal_id == 1 && vote.bundle_index == 0 && vote.choice == 0));
        assert!(votes
            .iter()
            .any(|vote| vote.proposal_id == 1 && vote.bundle_index == 1 && vote.choice == 1));
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: "round-1".to_string(),
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
