use anyhow::{Context, Result};
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

/// Serialize every commitment in one bundle for vote-chain REST submission.
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
