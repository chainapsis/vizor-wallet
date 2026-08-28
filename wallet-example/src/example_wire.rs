use anyhow::{bail, Context, Result};
use zcash_voting::prelude::{
    recover_wire_json, SharePayload, SignedVoteCommitment, SignedVoteCommitments,
};

/// Serialize a delegation submission payload for vote-chain REST submission.
pub fn delegation_wire_json(
    submission: &zcash_voting::prelude::DelegationSubmission,
) -> Result<String> {
    submission
        .to_wire_json()
        .context("serialize delegation wire JSON")
}

/// Serialize one signed vote commitment for vote-chain REST submission.
pub fn vote_commitment_wire_json(commitment: &SignedVoteCommitment) -> Result<String> {
    commitment
        .to_wire_json()
        .context("serialize vote commitment wire JSON")
}

/// Serialize a legacy singleton result for vote-chain REST submission.
///
/// Atomic batches must instead be submitted once with [`vote_batch_wire_json`].
/// This helper rejects batch results so their batch signatures cannot be sent
/// with singleton request bodies.
pub fn vote_commitments_wire_json(
    commitments: &SignedVoteCommitments,
) -> Result<Vec<(u32, String)>> {
    match (&commitments.batch_digest, &commitments.batch_json) {
        (Some(_), Some(_)) => {
            bail!("atomic vote batch must be submitted once using vote_batch_wire_json")
        }
        (Some(_), None) | (None, Some(_)) => {
            bail!("atomic vote batch metadata is incomplete")
        }
        (None, None) => {}
    }

    if commitments.commitments.len() != 1 {
        bail!(
            "legacy singleton result must contain exactly one commitment, got {}",
            commitments.commitments.len()
        );
    }

    commitments
        .commitments
        .iter()
        .map(|commitment| {
            Ok((
                commitment.proposal_id,
                vote_commitment_wire_json(commitment)
                    .with_context(|| format!("proposal {}", commitment.proposal_id))?,
            ))
        })
        .collect()
}

/// Return the canonical request body for one atomic vote batch.
///
/// Submit this JSON once to the vote-chain batch endpoint. Do not serialize or
/// submit the batch's individual commitments as singleton requests.
pub fn vote_batch_wire_json(commitments: &SignedVoteCommitments) -> Result<String> {
    match (&commitments.batch_digest, &commitments.batch_json) {
        (Some(_), Some(batch_json)) => Ok(batch_json.clone()),
        (Some(_), None) | (None, Some(_)) => {
            bail!("atomic vote batch metadata is incomplete")
        }
        (None, None) => bail!("legacy singleton result has no atomic vote batch JSON"),
    }
}

/// Serialize one helper-share payload for helper-server submission.
pub fn vote_share_wire_json(
    payload: &SharePayload,
    vc_tree_position: Option<u64>,
    submit_at: u64,
) -> Result<String> {
    payload
        .to_wire_json(vc_tree_position, submit_at)
        .context("serialize vote share wire JSON")
}

/// Rebuild and serialize one helper-share payload from stored vote recovery JSON.
pub fn recovered_vote_share_wire_json(
    commitment_bundle_json: &str,
    proposal_id: u32,
    share_index: u32,
    vc_tree_position: u64,
    submit_at: u64,
) -> Result<String> {
    recover_wire_json(
        commitment_bundle_json,
        proposal_id,
        share_index,
        vc_tree_position,
        submit_at,
    )
    .context("recover vote share wire JSON")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn signed_commitment() -> SignedVoteCommitment {
        SignedVoteCommitment {
            proposal_id: 2,
            choice: 1,
            vote_round_id: "00".repeat(32),
            van_nullifier: [1; 32],
            vote_authority_note_new: [2; 32],
            vote_commitment: [3; 32],
            proof: vec![4; 10],
            encrypted_shares: vec![],
            share_payloads: vec![],
            anchor_height: 100,
            shares_hash: [5; 32],
            share_comms: vec![],
            r_vpk: [6; 32],
            vote_auth_sig: [7; 64],
            commitment_bundle_json: "{\"proposal_id\":2}".to_string(),
        }
    }

    fn signed_commitments() -> SignedVoteCommitments {
        SignedVoteCommitments {
            bundle_index: 1,
            commitments: vec![signed_commitment()],
            batch_digest: None,
            batch_json: None,
        }
    }

    #[test]
    fn legacy_singleton_result_still_serializes_one_request() {
        let requests = vote_commitments_wire_json(&signed_commitments()).unwrap();

        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].0, 2);
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&requests[0].1).unwrap()["proposal_id"],
            2
        );
    }

    #[test]
    fn atomic_batch_returns_its_canonical_request_body_once() {
        let mut commitments = signed_commitments();
        commitments.batch_digest = Some([0xAB; 32]);
        commitments.batch_json = Some("{\"votes\":[]}".to_string());

        assert_eq!(
            vote_batch_wire_json(&commitments).unwrap(),
            "{\"votes\":[]}"
        );
        assert!(vote_commitments_wire_json(&commitments)
            .unwrap_err()
            .to_string()
            .contains("must be submitted once"));
    }

    #[test]
    fn incomplete_batch_metadata_is_rejected() {
        let mut missing_json = signed_commitments();
        missing_json.batch_digest = Some([0xAB; 32]);
        assert!(vote_batch_wire_json(&missing_json)
            .unwrap_err()
            .to_string()
            .contains("metadata is incomplete"));

        let mut missing_digest = signed_commitments();
        missing_digest.batch_json = Some("{\"votes\":[]}".to_string());
        assert!(vote_commitments_wire_json(&missing_digest)
            .unwrap_err()
            .to_string()
            .contains("metadata is incomplete"));
    }
}
