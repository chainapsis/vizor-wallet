use crate::wallet::network::WalletNetwork;

use secrecy::{ExposeSecret, SecretVec};

use super::{
    bundle::validate_bundle_index, progress::VotingWorkCancellation, state::open_voting_db,
    tree_sync::VanWitness, voting_network,
};

const VAN_AUTH_PATH_LEN: usize = 24;

#[derive(Clone, Debug, PartialEq, Eq)]
/// One proposal choice to turn into a signed vote commitment.
pub struct DraftVote {
    pub proposal_id: u32,
    pub choice: u32,
    pub num_options: u32,
    pub vc_tree_position: u64,
    pub single_share: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Wire-safe encrypted share with no plaintext or randomness fields.
pub struct WireEncryptedShare {
    pub ciphertext1: Vec<u8>,
    pub ciphertext2: Vec<u8>,
    pub share_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Public helper-server payload for submitting one encrypted vote share.
pub struct VoteSharePayload {
    pub shares_hash: Vec<u8>,
    pub proposal_id: u32,
    pub vote_decision: u32,
    pub encrypted_share: WireEncryptedShare,
    pub tree_position: u64,
    pub all_encrypted_shares: Vec<WireEncryptedShare>,
    pub share_comms: Vec<Vec<u8>>,
    pub primary_blind: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Signed vote commitment plus public encrypted-share data for one proposal.
pub struct SignedVoteCommitment {
    pub proposal_id: u32,
    pub choice: u32,
    pub vote_round_id: String,
    pub van_nullifier: Vec<u8>,
    pub vote_authority_note_new: Vec<u8>,
    pub vote_commitment: Vec<u8>,
    pub proof: Vec<u8>,
    pub encrypted_shares: Vec<WireEncryptedShare>,
    pub share_payloads: Vec<VoteSharePayload>,
    pub anchor_height: u32,
    pub shares_hash: Vec<u8>,
    pub share_comms: Vec<Vec<u8>>,
    pub r_vpk_bytes: Vec<u8>,
    pub vote_auth_sig: Vec<u8>,
    pub commitment_bundle_json: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Vote commitments produced for a single bundle index.
pub struct SignedVoteCommitments {
    pub bundle_index: u32,
    pub commitments: Vec<SignedVoteCommitment>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Stored vote status for one `(bundle_index, proposal_id)` pair.
pub struct VoteRecord {
    pub proposal_id: u32,
    pub bundle_index: u32,
    pub choice: u32,
}

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
    validate_draft_votes(&draft_votes)?;
    let on_progress = std::sync::Arc::new(on_progress);
    let voting_db = open_voting_db(db_path, wallet_id)?;
    let bundle_count = voting_db
        .get_bundle_count(round_id)
        .map_err(|e| format!("get_bundle_count failed: {e}"))?;
    validate_bundle_index(bundle_count, bundle_index, "voting")?;
    let van_auth_path = van_auth_path_array(&van_witness)?;
    let mut commitments = Vec::with_capacity(draft_votes.len());

    for draft in draft_votes {
        let total_start = std::time::Instant::now();
        cancellation.check()?;
        let progress_cancellation = cancellation.clone();
        let vote_stages = on_progress.clone();
        let reporter = zcash_voting::VoteCommitStageBridge::new(move |stage| {
            if progress_cancellation.check().is_ok() {
                vote_stages(stage);
            }
        });
        let proof_start = std::time::Instant::now();
        log::info!(
            "voting vote: starting proof generation (bundle_index={bundle_index}, proposal_id={})",
            draft.proposal_id
        );
        let commit = zcash_voting::vote::commit(
            &voting_db,
            round_id,
            bundle_index,
            &zcash_voting::vote::DraftVote {
                proposal_id: draft.proposal_id,
                choice: draft.choice,
                num_options: draft.num_options,
                vc_tree_position: draft.vc_tree_position,
                single_share: draft.single_share,
            },
            &zcash_voting::vote::VanWitness {
                auth_path: van_auth_path,
                position: van_witness.position,
                anchor_height: van_witness.anchor_height,
            },
            zcash_voting::vote::VoteSigner::Seed {
                seed: hotkey_seed.expose_secret(),
                network: voting_network(network),
                account_index: 0,
            },
            &reporter,
        )
        .map_err(|e| format!("vote commit failed: {e}"))?;
        let recovery = zcash_voting::vote::recovery_bundle(
            &voting_db,
            round_id,
            bundle_index,
            draft.proposal_id,
        )
        .map_err(|e| format!("load vote recovery bundle failed: {e}"))?
        .ok_or_else(|| "vote recovery bundle missing after commit".to_string())?;
        let commitment_json = zcash_voting::vote::serialize_recovery(&recovery)
            .map_err(|e| format!("serialize vote recovery failed: {e}"))?;
        cancellation.check()?;
        log::info!(
            "voting vote: proof generation completed \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            proof_start.elapsed().as_secs_f64(),
        );

        let payload_start = std::time::Instant::now();
        let share_payloads = commit.share_payloads;
        log::info!(
            "voting vote: share payloads built \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            payload_start.elapsed().as_secs_f64(),
        );

        let signing_start = std::time::Instant::now();
        log::info!(
            "voting vote: commitment signed \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            signing_start.elapsed().as_secs_f64(),
        );

        commitments.push(SignedVoteCommitment {
            proposal_id: draft.proposal_id,
            choice: draft.choice,
            vote_round_id: recovery.vote_round_id,
            van_nullifier: commit.van_nullifier.to_vec(),
            vote_authority_note_new: commit.vote_authority_note_new.to_vec(),
            vote_commitment: commit.vote_commitment.to_vec(),
            proof: commit.proof,
            encrypted_shares: commit
                .encrypted_shares
                .iter()
                .map(wire_share_from_upstream)
                .collect(),
            share_payloads: share_payloads
                .iter()
                .map(share_payload_from_upstream)
                .collect(),
            anchor_height: commit.anchor_height,
            shares_hash: recovery.shares_hash.to_vec(),
            share_comms: recovery
                .share_comms
                .iter()
                .map(|comm| comm.to_vec())
                .collect(),
            r_vpk_bytes: commit.r_vpk.to_vec(),
            vote_auth_sig: commit.vote_auth_sig.to_vec(),
            commitment_bundle_json: commitment_json,
        });
        log::info!(
            "voting vote: commitment completed \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            total_start.elapsed().as_secs_f64(),
        );
    }

    Ok(SignedVoteCommitments {
        bundle_index,
        commitments,
    })
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
    let recovery =
        zcash_voting::vote::recovery_bundle(&voting_db, round_id, bundle_index, proposal_id)
            .map_err(|e| format!("load vote recovery bundle failed: {e}"))?
            .ok_or_else(|| {
                format!(
                    "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
                )
            })?;
    let commit =
        zcash_voting::vote::recover_commit(&voting_db, round_id, bundle_index, proposal_id)
            .map_err(|e| format!("vote commitment recovery failed: {e}"))?;
    let commitment_json = zcash_voting::vote::serialize_recovery(&recovery)
        .map_err(|e| format!("serialize vote recovery failed: {e}"))?;

    Ok(SignedVoteCommitments {
        bundle_index,
        commitments: vec![SignedVoteCommitment {
            proposal_id,
            choice: recovery.vote_decision,
            vote_round_id: recovery.vote_round_id,
            van_nullifier: commit.van_nullifier.to_vec(),
            vote_authority_note_new: commit.vote_authority_note_new.to_vec(),
            vote_commitment: commit.vote_commitment.to_vec(),
            proof: commit.proof,
            encrypted_shares: commit
                .encrypted_shares
                .iter()
                .map(wire_share_from_upstream)
                .collect(),
            share_payloads: commit
                .share_payloads
                .iter()
                .map(share_payload_from_upstream)
                .collect(),
            anchor_height: commit.anchor_height,
            shares_hash: recovery.shares_hash.to_vec(),
            share_comms: recovery
                .share_comms
                .iter()
                .map(|comm| comm.to_vec())
                .collect(),
            r_vpk_bytes: commit.r_vpk.to_vec(),
            vote_auth_sig: commit.vote_auth_sig.to_vec(),
            commitment_bundle_json: commitment_json,
        }],
    })
}

/// Load stored vote rows for `round_id` in this wallet.
pub fn get_votes(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<VoteRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_votes(round_id)
        .map(|records| {
            records
                .into_iter()
                .map(|record| VoteRecord {
                    proposal_id: record.proposal_id,
                    bundle_index: record.bundle_index,
                    choice: record.choice,
                })
                .collect()
        })
        .map_err(|e| format!("get_votes failed: {e}"))
}

fn validate_draft_votes(draft_votes: &[DraftVote]) -> Result<(), String> {
    if draft_votes.is_empty() {
        return Err("draft_votes must not be empty".to_string());
    }
    for draft in draft_votes {
        if draft.proposal_id < 1 || draft.proposal_id > 15 {
            return Err(format!(
                "proposal_id must be 1..15, got {}",
                draft.proposal_id
            ));
        }
        if draft.num_options < 2 || draft.num_options > 8 {
            return Err(format!(
                "num_options must be 2..8, got {}",
                draft.num_options
            ));
        }
        if draft.choice >= draft.num_options {
            return Err(format!(
                "choice must be in [0, {}), got {}",
                draft.num_options, draft.choice
            ));
        }
    }
    Ok(())
}

fn van_auth_path_array(witness: &VanWitness) -> Result<[[u8; 32]; VAN_AUTH_PATH_LEN], String> {
    if witness.auth_path.len() != VAN_AUTH_PATH_LEN {
        return Err(format!(
            "van_auth_path must have {VAN_AUTH_PATH_LEN} siblings, got {}",
            witness.auth_path.len()
        ));
    }

    let mut auth_path = [[0u8; 32]; VAN_AUTH_PATH_LEN];
    for (idx, hash) in witness.auth_path.iter().enumerate() {
        let hash: [u8; 32] = hash
            .as_slice()
            .try_into()
            .map_err(|_| format!("van_auth_path[{idx}] must be 32 bytes, got {}", hash.len()))?;
        auth_path[idx] = hash;
    }
    Ok(auth_path)
}

fn wire_share_from_upstream(share: &zcash_voting::WireEncryptedShare) -> WireEncryptedShare {
    WireEncryptedShare {
        ciphertext1: share.c1.clone(),
        ciphertext2: share.c2.clone(),
        share_index: share.share_index,
    }
}

fn share_payload_from_upstream(payload: &zcash_voting::SharePayload) -> VoteSharePayload {
    VoteSharePayload {
        shares_hash: payload.shares_hash.clone(),
        proposal_id: payload.proposal_id,
        vote_decision: payload.vote_decision,
        encrypted_share: wire_share_from_upstream(&payload.enc_share),
        tree_position: payload.tree_position,
        all_encrypted_shares: payload
            .all_enc_shares
            .iter()
            .map(wire_share_from_upstream)
            .collect(),
        share_comms: payload.share_comms.clone(),
        primary_blind: payload.primary_blind.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn commitment_bundle_recovery_json(
        bundle: &zcash_voting::VoteCommitmentBundle,
        payloads: &[zcash_voting::SharePayload],
        vote_auth_sig: &[u8],
    ) -> Result<String, String> {
        let draft = zcash_voting::vote::DraftVote {
            proposal_id: bundle.proposal_id,
            choice: payloads.first().map(|p| p.vote_decision).unwrap_or(0),
            num_options: 2,
            single_share: payloads.len() == 1,
            vc_tree_position: payloads.first().map(|p| p.tree_position).unwrap_or(0),
        };
        let recovery = zcash_voting::vote::VoteRecoveryBundle {
            vote_round_id: bundle.vote_round_id.clone(),
            bundle_index: 0,
            proposal_id: bundle.proposal_id,
            vote_decision: draft.choice,
            anchor_height: bundle.anchor_height,
            vc_tree_position: draft.vc_tree_position,
            single_share: draft.single_share,
            num_options: draft.num_options,
            van_nullifier: bundle.van_nullifier.clone().try_into().unwrap(),
            vote_authority_note_new: bundle.vote_authority_note_new.clone().try_into().unwrap(),
            vote_commitment: bundle.vote_commitment.clone().try_into().unwrap(),
            proof: bundle.proof.clone(),
            shares_hash: bundle.shares_hash.clone().try_into().unwrap(),
            r_vpk: bundle.r_vpk_bytes.clone().try_into().unwrap(),
            alpha_v: bundle.alpha_v.clone().try_into().unwrap(),
            vote_auth_sig: vote_auth_sig.try_into().unwrap(),
            encrypted_shares: bundle.enc_shares.clone(),
            share_blinds: bundle
                .share_blinds
                .iter()
                .cloned()
                .map(|blind| blind.try_into().unwrap())
                .collect(),
            share_comms: bundle
                .share_comms
                .iter()
                .cloned()
                .map(|comm| comm.try_into().unwrap())
                .collect(),
        };
        zcash_voting::vote::serialize_recovery(&recovery)
            .map_err(|e| format!("serialize recovery failed: {e}"))
    }

    #[test]
    fn validate_draft_votes_rejects_invalid_inputs_before_db_work() {
        assert!(validate_draft_votes(&[])
            .unwrap_err()
            .contains("must not be empty"));
        assert!(validate_draft_votes(&[DraftVote {
            proposal_id: 0,
            choice: 0,
            num_options: 2,
            vc_tree_position: 0,
            single_share: false,
        }])
        .unwrap_err()
        .contains("proposal_id"));
        assert!(validate_draft_votes(&[DraftVote {
            proposal_id: 1,
            choice: 2,
            num_options: 2,
            vc_tree_position: 0,
            single_share: false,
        }])
        .unwrap_err()
        .contains("choice"));
    }

    #[test]
    fn build_vote_commitments_rejects_out_of_range_bundle_before_vote_work() {
        let temp_dir = tempfile::tempdir().unwrap();
        let wallet_db_path = temp_dir.path().join("wallet.sqlite");
        let db = open_voting_db(wallet_db_path.to_str().unwrap(), "wallet-1").unwrap();
        db.init_round(&test_round_params(), None).unwrap();
        db.setup_bundles("round-1", &[test_note_info(0)]).unwrap();
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
                auth_path: vec![vec![7; 32]; VAN_AUTH_PATH_LEN],
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
    fn van_auth_path_array_requires_24_32_byte_siblings() {
        let mut witness = VanWitness {
            auth_path: vec![vec![7; 32]; VAN_AUTH_PATH_LEN],
            position: 0,
            anchor_height: 1,
        };
        assert_eq!(van_auth_path_array(&witness).unwrap()[0], [7; 32]);

        witness.auth_path.pop();
        assert!(van_auth_path_array(&witness)
            .unwrap_err()
            .contains("24 siblings"));

        witness.auth_path = vec![vec![7; 31]; VAN_AUTH_PATH_LEN];
        assert!(van_auth_path_array(&witness)
            .unwrap_err()
            .contains("32 bytes"));
    }

    #[test]
    fn share_payload_conversion_preserves_public_wire_fields() {
        let upstream_shares = mock_upstream_wire_shares();
        let commitment = mock_commitment_bundle();
        let payloads = zcash_voting::vote_commitment::build_share_payloads(
            &upstream_shares,
            &commitment,
            1,
            2,
            42,
            false,
        )
        .unwrap();

        let converted: Vec<_> = payloads.iter().map(share_payload_from_upstream).collect();

        assert_eq!(converted.len(), 2);
        assert_eq!(converted[0].encrypted_share.ciphertext1, vec![0xC1; 32]);
        assert_eq!(converted[0].encrypted_share.ciphertext2, vec![0xC2; 32]);
        assert_eq!(converted[0].all_encrypted_shares.len(), 2);
        assert_eq!(converted[0].primary_blind, vec![0x11; 32]);
    }

    #[test]
    fn single_share_payload_conversion_keeps_all_public_shares_for_context() {
        let upstream_shares = mock_upstream_wire_shares();
        let commitment = mock_commitment_bundle();
        let payloads = zcash_voting::vote_commitment::build_share_payloads(
            &upstream_shares,
            &commitment,
            1,
            2,
            42,
            true,
        )
        .unwrap();

        let converted: Vec<_> = payloads.iter().map(share_payload_from_upstream).collect();

        assert_eq!(converted.len(), 1);
        assert_eq!(converted[0].all_encrypted_shares.len(), 2);
    }

    #[test]
    fn commitment_bundle_recovery_json_persists_full_share_recovery_material() {
        let upstream_shares = mock_upstream_wire_shares();
        let commitment = mock_commitment_bundle();
        let payloads = zcash_voting::vote_commitment::build_share_payloads(
            &upstream_shares,
            &commitment,
            1,
            2,
            42,
            false,
        )
        .unwrap();

        let json = commitment_bundle_recovery_json(&commitment, &payloads, &[0x99; 64]).unwrap();
        let recovered = zcash_voting::vote::parse_recovery(&json).unwrap();
        let recovered_payloads = zcash_voting::share::recover_payloads(&recovered).unwrap();

        assert_eq!(recovered.encrypted_shares.len(), 2);
        assert_eq!(recovered.encrypted_shares[0].plaintext_value, 5);
        assert_eq!(recovered.encrypted_shares[0].randomness, vec![0x33; 32]);
        assert_eq!(recovered.share_blinds.len(), 2);
        assert_eq!(recovered.share_blinds[0], [0x11; 32]);
        assert_eq!(recovered_payloads.len(), 2);
        assert_eq!(recovered_payloads[0].primary_blind, vec![0x11; 32]);
        assert_eq!(recovered_payloads[0].share_comms.len(), 2);
        assert_eq!(recovered_payloads[0].enc_share.c1, vec![0xC1; 32]);
        assert_eq!(recovered.vote_auth_sig, [0x99; 64]);
        assert_eq!(recovered.alpha_v, [0x01; 32]);
    }

    #[test]
    fn stored_commitment_bundle_round_trip_preserves_share_nullifier_inputs() {
        let temp_dir = tempfile::tempdir().unwrap();
        let wallet_db_path = temp_dir.path().join("wallet.sqlite");
        let voting_db_path = format!("{}.voting", wallet_db_path.to_str().unwrap());
        let db = zcash_voting::storage::VotingDb::open(&voting_db_path).unwrap();
        db.set_wallet_id("wallet-1");
        db.init_round(&test_round_params(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.setup_bundles("round-1", &notes).unwrap();
        let conn = db.conn();
        zcash_voting::storage::queries::store_vote(&conn, "round-1", "wallet-1", 0, 1, 1, b"vc")
            .unwrap();
        drop(conn);

        let upstream_shares = mock_upstream_wire_shares();
        let commitment = mock_commitment_bundle();
        let payloads = zcash_voting::vote_commitment::build_share_payloads(
            &upstream_shares,
            &commitment,
            1,
            2,
            42,
            false,
        )
        .unwrap();
        let json = commitment_bundle_recovery_json(&commitment, &payloads, &[0x99; 64]).unwrap();

        let conn = db.conn();
        conn.execute(
            "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":json": json,
                ":pos": 42i64,
                ":round_id": "round-1",
                ":wallet_id": "wallet-1",
                ":bundle_index": 0i64,
                ":proposal_id": 1i64,
            },
        )
        .unwrap();
        drop(conn);
        let (commitment_bundle_json, vc_tree_position) =
            db.get_commitment_bundle("round-1", 0, 1).unwrap().unwrap();
        assert_eq!(commitment_bundle_json, json);
        assert_eq!(vc_tree_position, 42);

        let conn = db.conn();
        let stored_json: String = conn
            .query_row(
                "SELECT commitment_bundle_json FROM votes
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                 AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":round_id": "round-1",
                    ":wallet_id": "wallet-1",
                    ":bundle_index": 0i64,
                    ":proposal_id": 1i64,
                },
                |row| row.get(0),
            )
            .unwrap();
        drop(conn);
        let stored = zcash_voting::vote::parse_recovery(&stored_json).unwrap();
        let stored_payload = zcash_voting::share::recover_payload(&stored, 0).unwrap();
        let stored_vote_commitment = stored.vote_commitment;
        let stored_primary_blind = stored_payload.primary_blind.clone();
        let stored_share_index = stored_payload.enc_share.share_index;
        let expected_vote_commitment: [u8; 32] =
            commitment.vote_commitment.as_slice().try_into().unwrap();
        let expected_primary_blind: [u8; 32] =
            payloads[0].primary_blind.as_slice().try_into().unwrap();
        let stored_primary_blind_array: [u8; 32] =
            stored_primary_blind.as_slice().try_into().unwrap();
        let expected_nullifier = zcash_voting::share::compute_nullifier(
            &expected_vote_commitment,
            payloads[0].enc_share.share_index,
            &expected_primary_blind,
        )
        .map(hex::encode)
        .unwrap();

        assert_eq!(stored_payload.tree_position, 42);
        assert_eq!(
            stored_payload.all_enc_shares.len(),
            payloads[0].all_enc_shares.len()
        );
        assert_eq!(
            zcash_voting::share::compute_nullifier(
                &stored_vote_commitment,
                stored_share_index,
                &stored_primary_blind_array
            )
            .map(hex::encode)
            .unwrap(),
            expected_nullifier
        );
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
        db.setup_bundles("round-1", &notes).unwrap();
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

    fn mock_upstream_wire_shares() -> Vec<zcash_voting::WireEncryptedShare> {
        vec![
            zcash_voting::WireEncryptedShare {
                c1: vec![0xC1; 32],
                c2: vec![0xC2; 32],
                share_index: 0,
            },
            zcash_voting::WireEncryptedShare {
                c1: vec![0xC3; 32],
                c2: vec![0xC4; 32],
                share_index: 1,
            },
        ]
    }

    fn mock_commitment_bundle() -> zcash_voting::VoteCommitmentBundle {
        zcash_voting::VoteCommitmentBundle {
            van_nullifier: vec![0xAA; 32],
            vote_authority_note_new: vec![0xBB; 32],
            vote_commitment: vec![1; 32],
            proposal_id: 1,
            proof: vec![0xAB; 256],
            enc_shares: vec![
                zcash_voting::EncryptedShare {
                    c1: vec![0xC1; 32],
                    c2: vec![0xC2; 32],
                    share_index: 0,
                    plaintext_value: 5,
                    randomness: vec![0x33; 32],
                },
                zcash_voting::EncryptedShare {
                    c1: vec![0xC3; 32],
                    c2: vec![0xC4; 32],
                    share_index: 1,
                    plaintext_value: 7,
                    randomness: vec![0x44; 32],
                },
            ],
            anchor_height: 1,
            vote_round_id: "round-1".to_string(),
            shares_hash: vec![0xDD; 32],
            share_blinds: (0..2).map(|_| vec![0x11; 32]).collect(),
            share_comms: (0..2).map(|_| vec![0x22; 32]).collect(),
            r_vpk_bytes: vec![0xEE; 32],
            alpha_v: vec![0x01; 32],
        }
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
