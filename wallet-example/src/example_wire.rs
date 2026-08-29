use anyhow::{Context, Result};
use zcash_voting::prelude::{
    recover_wire_json, SharePayload, SignedVoteBatch, SignedVoteCommitment, SignedVoteCommitments,
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

/// Serialize independently signed commitments for singleton REST submission.
pub fn vote_commitments_wire_json(
    commitments: &SignedVoteCommitments,
) -> Result<Vec<(u32, String)>> {
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
pub fn vote_batch_wire_json(batch: &SignedVoteBatch) -> String {
    batch.batch_json.clone()
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
            commitments: vec![
                signed_commitment(),
                SignedVoteCommitment {
                    proposal_id: 3,
                    ..signed_commitment()
                },
            ],
        }
    }

    fn signed_batch() -> SignedVoteBatch {
        SignedVoteBatch {
            bundle_index: 1,
            commitments: vec![signed_commitment()],
            batch_digest: [0xAB; 32],
            batch_json: "{\"votes\":[]}".to_string(),
        }
    }

    #[test]
    fn independently_signed_commitments_serialize_as_separate_requests() {
        let requests = vote_commitments_wire_json(&signed_commitments()).unwrap();

        assert_eq!(requests.len(), 2);
        assert_eq!(requests[0].0, 2);
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&requests[0].1).unwrap()["proposal_id"],
            2
        );
    }

    #[test]
    fn atomic_batch_returns_its_canonical_request_body_once() {
        assert_eq!(vote_batch_wire_json(&signed_batch()), "{\"votes\":[]}");
    }
}
