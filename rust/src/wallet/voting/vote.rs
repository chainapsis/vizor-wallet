use crate::wallet::network::WalletNetwork;

use secrecy::{ExposeSecret, SecretVec};

use super::{state::open_voting_db, tree_sync::VanWitness, workflow};

const VAN_AUTH_PATH_LEN: usize = 24;

#[derive(Clone, Debug, PartialEq, Eq)]
/// Internal progress phases for ZKP2 vote commitment generation.
pub enum VoteCommitEvent {
    BuildingProof { proposal_id: u32, bundle_index: u32 },
    BuildingSharePayloads { proposal_id: u32, bundle_index: u32 },
    Signing { proposal_id: u32, bundle_index: u32 },
    Done,
}

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
    pub submitted: bool,
}

/// Initialize the local voting database for vote commitment operations.
pub fn prepare_vote(db_path: &str, wallet_id: &str) -> Result<(), String> {
    open_voting_db(db_path, wallet_id).map(|_| ())
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
) -> Result<SignedVoteCommitments, String>
where
    F: Fn(VoteCommitEvent),
{
    validate_draft_votes(&draft_votes)?;
    let van_auth_path = van_auth_path_array(&van_witness)?;
    let voting_db = open_voting_db(db_path, wallet_id)?;
    let mut commitments = Vec::with_capacity(draft_votes.len());

    for draft in draft_votes {
        let total_start = std::time::Instant::now();
        on_progress(VoteCommitEvent::BuildingProof {
            proposal_id: draft.proposal_id,
            bundle_index,
        });
        let reporter = zcash_voting::NoopProgressReporter;
        let proof_start = std::time::Instant::now();
        log::info!(
            "voting vote: starting proof generation (bundle_index={bundle_index}, proposal_id={})",
            draft.proposal_id
        );
        let bundle = voting_db
            .build_vote_commitment(
                round_id,
                bundle_index,
                hotkey_seed.expose_secret(),
                network.voting_id().into(),
                draft.proposal_id,
                draft.choice,
                draft.num_options,
                &van_auth_path,
                van_witness.position,
                van_witness.anchor_height,
                draft.single_share,
                &reporter,
            )
            .map_err(|e| format!("build_vote_commitment failed: {e}"))?;
        log::info!(
            "voting vote: proof generation completed \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            proof_start.elapsed().as_secs_f64(),
        );

        let wire_shares: Vec<zcash_voting::WireEncryptedShare> =
            bundle.enc_shares.iter().map(Into::into).collect();

        on_progress(VoteCommitEvent::BuildingSharePayloads {
            proposal_id: draft.proposal_id,
            bundle_index,
        });
        let payload_start = std::time::Instant::now();
        let share_payloads = voting_db
            .build_share_payloads(
                &wire_shares,
                &bundle,
                draft.choice,
                draft.num_options,
                draft.vc_tree_position,
                draft.single_share,
            )
            .map_err(|e| format!("build_share_payloads failed: {e}"))?;
        log::info!(
            "voting vote: share payloads built \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            payload_start.elapsed().as_secs_f64(),
        );

        let commitment_json = public_commitment_json(&bundle, &wire_shares, &share_payloads)?;

        on_progress(VoteCommitEvent::Signing {
            proposal_id: draft.proposal_id,
            bundle_index,
        });
        let signing_start = std::time::Instant::now();
        let signature = zcash_voting::vote_commitment::sign_cast_vote(
            hotkey_seed.expose_secret(),
            network.voting_id().into(),
            &bundle.vote_round_id,
            &bundle.r_vpk_bytes,
            &bundle.van_nullifier,
            &bundle.vote_authority_note_new,
            &bundle.vote_commitment,
            bundle.proposal_id,
            bundle.anchor_height,
            &bundle.alpha_v,
        )
        .map_err(|e| format!("sign_cast_vote failed: {e}"))?;
        log::info!(
            "voting vote: commitment signed \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            signing_start.elapsed().as_secs_f64(),
        );

        workflow::store_signed_vote_commitment(
            &voting_db,
            round_id,
            bundle_index,
            draft.proposal_id,
            &commitment_json,
        )?;

        commitments.push(SignedVoteCommitment {
            proposal_id: draft.proposal_id,
            choice: draft.choice,
            vote_round_id: bundle.vote_round_id,
            van_nullifier: bundle.van_nullifier,
            vote_authority_note_new: bundle.vote_authority_note_new,
            vote_commitment: bundle.vote_commitment,
            proof: bundle.proof,
            encrypted_shares: wire_shares.iter().map(wire_share_from_upstream).collect(),
            share_payloads: share_payloads
                .iter()
                .map(share_payload_from_upstream)
                .collect(),
            anchor_height: bundle.anchor_height,
            shares_hash: bundle.shares_hash,
            share_comms: bundle.share_comms,
            r_vpk_bytes: bundle.r_vpk_bytes,
            vote_auth_sig: signature.vote_auth_sig,
            commitment_bundle_json: commitment_json,
        });
        log::info!(
            "voting vote: commitment completed \
             (bundle_index={bundle_index}, proposal_id={}, elapsed={:.2}s)",
            draft.proposal_id,
            total_start.elapsed().as_secs_f64(),
        );
    }

    on_progress(VoteCommitEvent::Done);
    Ok(SignedVoteCommitments {
        bundle_index,
        commitments,
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
                    submitted: record.submitted,
                })
                .collect()
        })
        .map_err(|e| format!("get_votes failed: {e}"))
}

/// Compute a deterministic share nullifier and return it as 64-character hex.
///
/// Used by recovery/share-tracking callers to identify delegated shares without
/// exposing share plaintext.
pub fn compute_share_nullifier_hex(
    vote_commitment: &[u8],
    share_index: u32,
    primary_blind: &[u8],
) -> Result<String, String> {
    zcash_voting::share_tracking::compute_share_nullifier(
        vote_commitment,
        share_index,
        primary_blind,
    )
    .map(hex::encode)
    .map_err(|e| format!("compute_share_nullifier failed: {e}"))
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

fn public_commitment_json(
    bundle: &zcash_voting::VoteCommitmentBundle,
    shares: &[zcash_voting::WireEncryptedShare],
    payloads: &[zcash_voting::SharePayload],
) -> Result<String, String> {
    serde_json::to_string(&serde_json::json!({
        "van_nullifier": hex::encode(&bundle.van_nullifier),
        "vote_authority_note_new": hex::encode(&bundle.vote_authority_note_new),
        "vote_commitment": hex::encode(&bundle.vote_commitment),
        "proposal_id": bundle.proposal_id,
        "proof": hex::encode(&bundle.proof),
        "anchor_height": bundle.anchor_height,
        "vote_round_id": bundle.vote_round_id,
        "shares_hash": hex::encode(&bundle.shares_hash),
        "encrypted_shares": shares.iter().map(|share| {
            serde_json::json!({
                "ciphertext1": hex::encode(&share.c1),
                "ciphertext2": hex::encode(&share.c2),
                "share_index": share.share_index,
            })
        }).collect::<Vec<_>>(),
        "share_payload_count": payloads.len(),
    }))
    .map_err(|e| format!("serialize commitment bundle failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prepare_vote_initializes_voting_db_schema() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");

        prepare_vote(db_path.to_str().unwrap(), "wallet-1").unwrap();

        let db = zcash_voting::storage::VotingDb::open(db_path.to_str().unwrap()).unwrap();
        db.set_wallet_id("wallet-1");
        assert!(db.list_rounds().unwrap().is_empty());
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
    fn compute_share_nullifier_hex_returns_64_hex_chars() {
        let nullifier = compute_share_nullifier_hex(&[1; 32], 5, &[2; 32]).unwrap();

        assert_eq!(nullifier.len(), 64);
        assert!(nullifier.chars().all(|ch| ch.is_ascii_hexdigit()));
        assert_eq!(
            nullifier,
            compute_share_nullifier_hex(&[1; 32], 5, &[2; 32]).unwrap()
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
            vote_commitment: vec![0xCC; 32],
            proposal_id: 1,
            proof: vec![0xAB; 256],
            enc_shares: vec![],
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
