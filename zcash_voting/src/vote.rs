//! Stable cast-vote lifecycle API.
//!
//! This module owns the wallet-facing vote flow: build ZKP #2 for one
//! proposal, sign the cast-vote payload, persist crash-recovery material, and
//! reconstruct chain-ready submission fields.

use serde::{Deserialize, Serialize};

use rusqlite::{named_params, OptionalExtension};

use crate::{
    round::VotingDb,
    types::{
        validate_proposal_id, validate_vote_decision, CastVoteSignature, EncryptedShare, Network,
        ProgressReporter, SharePayload, VoteCommitmentBundle, VotingError, VotingHotkey,
        WireEncryptedShare,
    },
};

/// Number of siblings in a vote-authority-note witness.
pub const VAN_AUTH_PATH_LEN: usize = 24;

const VOTE_RECOVERY_FORMAT: &str = "zcash_voting_vote_recovery_v1";

/// Wallet-supplied cast-vote intent for one proposal in one bundle.
pub use crate::wire::DraftVote;

/// Validates one wallet-supplied cast-vote draft before proof construction.
pub fn validate_draft_vote(draft: &DraftVote) -> Result<(), VotingError> {
    validate_proposal_id(draft.proposal_id)?;
    validate_vote_decision(draft.choice, draft.num_options)?;
    Ok(())
}

/// Validates a non-empty batch of wallet-supplied cast-vote drafts.
pub fn validate_draft_votes(draft_votes: &[DraftVote]) -> Result<(), VotingError> {
    if draft_votes.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "draft_votes must not be empty".to_string(),
        });
    }

    for draft in draft_votes {
        validate_draft_vote(draft)?;
    }

    Ok(())
}

/// VAN Merkle witness produced by `precompute::van_witness`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VanWitness {
    pub auth_path: Vec<Vec<u8>>,
    pub position: u32,
    pub anchor_height: u32,
}

impl VanWitness {
    /// Builds a typed witness from wire-friendly sibling bytes.
    pub fn from_wire(
        auth_path: &[Vec<u8>],
        position: u32,
        anchor_height: u32,
    ) -> Result<Self, VotingError> {
        if auth_path.len() != VAN_AUTH_PATH_LEN {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "van_auth_path must have {VAN_AUTH_PATH_LEN} siblings, got {}",
                    auth_path.len()
                ),
            });
        }

        for (idx, hash) in auth_path.iter().enumerate() {
            if hash.len() != 32 {
                return Err(VotingError::InvalidInput {
                    message: format!("van_auth_path[{idx}] must be 32 bytes, got {}", hash.len()),
                });
            }
        }

        Ok(Self {
            auth_path: auth_path.to_vec(),
            position,
            anchor_height,
        })
    }

    pub fn auth_path_fixed(&self) -> Result<[[u8; 32]; VAN_AUTH_PATH_LEN], VotingError> {
        if self.auth_path.len() != VAN_AUTH_PATH_LEN {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "van_auth_path must have {VAN_AUTH_PATH_LEN} siblings, got {}",
                    self.auth_path.len()
                ),
            });
        }

        let mut typed_path = [[0u8; 32]; VAN_AUTH_PATH_LEN];
        for (idx, hash) in self.auth_path.iter().enumerate() {
            typed_path[idx] =
                hash.as_slice()
                    .try_into()
                    .map_err(|_| VotingError::InvalidInput {
                        message: format!(
                            "van_auth_path[{idx}] must be 32 bytes, got {}",
                            hash.len()
                        ),
                    })?;
        }

        Ok(typed_path)
    }
}

/// Result of building, signing, and persisting one cast-vote.
#[derive(Clone, Debug)]
pub struct VoteCommit {
    pub proposal_id: u32,
    pub van_nullifier: [u8; 32],
    pub vote_authority_note_new: [u8; 32],
    pub vote_commitment: [u8; 32],
    pub proof: Vec<u8>,
    pub anchor_height: u32,
    pub r_vpk: [u8; 32],
    pub vote_auth_sig: [u8; 64],
    pub encrypted_shares: Vec<WireEncryptedShare>,
    pub share_payloads: Vec<SharePayload>,
}

/// Wallet-facing aggregate of one committed vote and public helper-share data.
#[derive(Clone, Debug)]
pub struct SignedVoteCommitment {
    pub proposal_id: u32,
    pub choice: u32,
    pub vote_round_id: String,
    pub van_nullifier: [u8; 32],
    pub vote_authority_note_new: [u8; 32],
    pub vote_commitment: [u8; 32],
    pub proof: Vec<u8>,
    pub encrypted_shares: Vec<WireEncryptedShare>,
    pub share_payloads: Vec<SharePayload>,
    pub anchor_height: u32,
    pub shares_hash: [u8; 32],
    pub share_comms: Vec<[u8; 32]>,
    pub r_vpk: [u8; 32],
    pub vote_auth_sig: [u8; 64],
    pub commitment_bundle_json: String,
}

/// Signed vote commitments produced for one delegation bundle.
#[derive(Clone, Debug)]
pub struct SignedVoteCommitments {
    pub bundle_index: u32,
    pub commitments: Vec<SignedVoteCommitment>,
}

/// Committed cast-vote handle for the post-commit lifecycle.
///
/// This wraps the signed commitment payload with the round and bundle keys used
/// to recover chain submission fields, track helper shares, and record
/// confirmation state.
#[derive(Clone, Debug)]
pub struct CommittedVote {
    round_id: String,
    bundle_index: u32,
    commit: VoteCommit,
}

impl CommittedVote {
    /// Builds, signs, persists, and returns a committed cast-vote handle.
    pub fn commit(
        db: &VotingDb,
        round_id: &str,
        bundle_index: u32,
        draft: &DraftVote,
        witness: &VanWitness,
        signer: VoteSigner<'_>,
        stages: &dyn crate::types::VoteCommitStageReporter,
    ) -> Result<Self, VotingError> {
        let commit =
            crate::vote::commit(db, round_id, bundle_index, draft, witness, signer, stages)?;
        Ok(Self {
            round_id: round_id.to_string(),
            bundle_index,
            commit,
        })
    }

    /// Reconstructs a committed cast-vote handle from persisted recovery state.
    pub fn recover(
        db: &VotingDb,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
    ) -> Result<Self, VotingError> {
        let commit = recover_commit(db, round_id, bundle_index, proposal_id)?;
        Ok(Self {
            round_id: round_id.to_string(),
            bundle_index,
            commit,
        })
    }

    /// Returns the round identifier for this committed vote.
    pub fn round_id(&self) -> &str {
        &self.round_id
    }

    /// Returns the delegation bundle index that authorized this vote.
    pub fn bundle_index(&self) -> u32 {
        self.bundle_index
    }

    /// Returns the proposal identifier for this committed vote.
    pub fn proposal_id(&self) -> u32 {
        self.commit.proposal_id
    }

    /// Returns the signed commitment payload and public helper-share data.
    pub fn data(&self) -> &VoteCommit {
        &self.commit
    }

    /// Returns helper-server payloads to submit outside the wallet library.
    pub fn share_payloads(&self) -> &[SharePayload] {
        &self.commit.share_payloads
    }

    /// Reconstructs chain-ready cast-vote fields from persisted recovery state.
    pub fn submission(&self, db: &VotingDb) -> Result<VoteSubmission, VotingError> {
        submission(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
        )
    }

    /// Serializes the persisted recovery bundle for this committed vote.
    pub fn recovery_json(&self, db: &VotingDb) -> Result<String, VotingError> {
        let bundle = recovery_bundle(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
        )?
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={}, bundle={}, proposal={}",
                self.round_id, self.bundle_index, self.commit.proposal_id
            ),
        })?;
        serialize_recovery(&bundle)
    }

    /// Returns a wire-facing signed commitment bundle for wallet API layers.
    pub fn signed_commitment(&self, db: &VotingDb) -> Result<SignedVoteCommitment, VotingError> {
        let recovery = recovery_bundle(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
        )?
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={}, bundle={}, proposal={}",
                self.round_id, self.bundle_index, self.commit.proposal_id
            ),
        })?;
        let commitment_bundle_json = serialize_recovery(&recovery)?;

        Ok(SignedVoteCommitment {
            proposal_id: self.commit.proposal_id,
            choice: recovery.vote_decision,
            vote_round_id: recovery.vote_round_id,
            van_nullifier: self.commit.van_nullifier,
            vote_authority_note_new: self.commit.vote_authority_note_new,
            vote_commitment: self.commit.vote_commitment,
            proof: self.commit.proof.clone(),
            encrypted_shares: self.commit.encrypted_shares.clone(),
            share_payloads: self.commit.share_payloads.clone(),
            anchor_height: self.commit.anchor_height,
            shares_hash: recovery.shares_hash,
            share_comms: recovery.share_comms,
            r_vpk: self.commit.r_vpk,
            vote_auth_sig: self.commit.vote_auth_sig,
            commitment_bundle_json,
        })
    }

    /// Records a helper-share submission using recovery-owned nullifier material.
    pub fn record_share(
        &self,
        db: &VotingDb,
        share_index: u32,
        sent_to_urls: &[String],
        submit_at: u64,
    ) -> Result<(), VotingError> {
        crate::share::record(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            share_index,
            sent_to_urls,
            submit_at,
        )
    }

    /// Marks one helper-share submission confirmed.
    pub fn confirm_share(&self, db: &VotingDb, share_index: u32) -> Result<(), VotingError> {
        crate::share::confirm(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            share_index,
        )
    }

    /// Adds helper URLs to a previously recorded share submission.
    pub fn add_sent_servers(
        &self,
        db: &VotingDb,
        share_index: u32,
        new_urls: &[String],
    ) -> Result<(), VotingError> {
        crate::share::add_sent_servers(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            share_index,
            new_urls,
        )
    }

    /// Records the cast-vote transaction hash for this vote.
    pub fn record_submission(&self, db: &VotingDb, tx_hash: &str) -> Result<(), VotingError> {
        record_submission(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            tx_hash,
        )
    }

    /// Records the confirmed vote-commitment tree position for this vote.
    pub fn record_vc_position(
        &self,
        db: &VotingDb,
        vc_tree_position: u64,
    ) -> Result<(), VotingError> {
        record_vc_position(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            vc_tree_position,
        )
    }
}

/// Builds signed vote commitments for every draft in one bundle.
///
/// This validates the draft list and bundle index once, then commits each draft
/// in order while reporting commit progress.
#[allow(clippy::too_many_arguments)]
pub fn commit_batch(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    drafts: &[DraftVote],
    witness: &VanWitness,
    signer: VoteSigner<'_>,
    stages: &dyn crate::types::VoteCommitStageReporter,
) -> Result<SignedVoteCommitments, VotingError> {
    validate_draft_votes(drafts)?;
    let bundle_count = db.get_bundle_count(round_id)?;
    crate::round::validate_bundle_index(bundle_count, bundle_index, "voting")?;

    let mut commitments = Vec::with_capacity(drafts.len());
    for draft in drafts {
        let committed =
            CommittedVote::commit(db, round_id, bundle_index, draft, witness, signer, stages)?;
        commitments.push(committed.signed_commitment(db)?);
    }

    Ok(SignedVoteCommitments {
        bundle_index,
        commitments,
    })
}

/// Recovers one persisted vote commitment as a single-item batch result.
pub fn recover_signed_commitments(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<SignedVoteCommitments, VotingError> {
    let committed = CommittedVote::recover(db, round_id, bundle_index, proposal_id)?;
    Ok(SignedVoteCommitments {
        bundle_index,
        commitments: vec![committed.signed_commitment(db)?],
    })
}

/// Lifecycle events emitted while building one cast-vote commitment.
#[derive(Clone, Copy, Debug, PartialEq)]
#[non_exhaustive]
pub enum VoteCommitStage {
    ProofStarting {
        proposal_id: u32,
        bundle_index: u32,
    },
    ProofProgress {
        proposal_id: u32,
        bundle_index: u32,
        progress: f64,
    },
    SharePayloadsBuilding {
        proposal_id: u32,
        bundle_index: u32,
    },
    Signing {
        proposal_id: u32,
        bundle_index: u32,
    },
}

/// Cast-vote signing source.
#[derive(Clone, Copy)]
#[non_exhaustive]
pub enum VoteSigner<'a> {
    /// Crate-owned voting hotkey material.
    Hotkey { hotkey: &'a VotingHotkey },
}

impl<'a> VoteSigner<'a> {
    /// Builds a vote signer from crate-owned voting hotkey material.
    pub fn hotkey(hotkey: &'a VotingHotkey) -> Self {
        Self::Hotkey { hotkey }
    }
}

struct CastVoteSigningFields<'a> {
    vote_round_id: &'a str,
    r_vpk_bytes: &'a [u8],
    van_nullifier: &'a [u8],
    vote_authority_note_new: &'a [u8],
    vote_commitment: &'a [u8],
    proposal_id: u32,
    anchor_height: u32,
    alpha_v: &'a [u8],
}

fn signer_secret_and_network<'a>(signer: VoteSigner<'a>) -> (&'a [u8], Network) {
    match signer {
        VoteSigner::Hotkey { hotkey } => (hotkey.stored_secret(), hotkey.network()),
    }
}

fn sign_cast_vote_with_signer(
    signer: VoteSigner<'_>,
    fields: CastVoteSigningFields<'_>,
) -> Result<CastVoteSignature, VotingError> {
    let (secret, network) = signer_secret_and_network(signer);
    crate::vote_commitment::sign_cast_vote(
        secret,
        network,
        fields.vote_round_id,
        fields.r_vpk_bytes,
        fields.van_nullifier,
        fields.vote_authority_note_new,
        fields.vote_commitment,
        fields.proposal_id,
        fields.anchor_height,
        fields.alpha_v,
    )
}

/// Chain-ready cast-vote submission fields for the vote chain.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteSubmission {
    pub vote_round_id: String,
    pub proposal_id: u32,
    pub van_nullifier: [u8; 32],
    pub vote_authority_note_new: [u8; 32],
    pub vote_commitment: [u8; 32],
    pub proof: Vec<u8>,
    pub r_vpk: [u8; 32],
    pub vote_auth_sig: [u8; 64],
    pub anchor_height: u32,
}

/// Library-owned vote recovery material persisted after `commit`.
#[derive(Clone, Debug)]
pub struct VoteRecoveryBundle {
    pub vote_round_id: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub vote_decision: u32,
    pub anchor_height: u32,
    pub vc_tree_position: u64,
    pub single_share: bool,
    pub num_options: u32,
    pub van_nullifier: [u8; 32],
    pub vote_authority_note_new: [u8; 32],
    pub vote_commitment: [u8; 32],
    pub proof: Vec<u8>,
    pub shares_hash: [u8; 32],
    pub r_vpk: [u8; 32],
    pub alpha_v: [u8; 32],
    pub vote_auth_sig: [u8; 64],
    /// Secret local share recovery material. Do not send this struct over the network.
    pub encrypted_shares: Vec<EncryptedShare>,
    pub share_blinds: Vec<[u8; 32]>,
    pub share_comms: Vec<[u8; 32]>,
}

#[derive(Serialize, Deserialize)]
struct VoteRecoveryJson {
    format: String,
    vote_round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    vote_decision: u32,
    anchor_height: u32,
    vc_tree_position: u64,
    single_share: bool,
    num_options: u32,
    van_nullifier: Vec<u8>,
    vote_authority_note_new: Vec<u8>,
    vote_commitment: Vec<u8>,
    proof: Vec<u8>,
    shares_hash: Vec<u8>,
    r_vpk: Vec<u8>,
    alpha_v: Vec<u8>,
    vote_auth_sig: Vec<u8>,
    encrypted_shares: Vec<EncryptedShareJson>,
    share_blinds: Vec<Vec<u8>>,
    share_comms: Vec<Vec<u8>>,
}

#[derive(Serialize, Deserialize)]
struct EncryptedShareJson {
    c1: Vec<u8>,
    c2: Vec<u8>,
    share_index: u32,
    plaintext_value: u64,
    randomness: Vec<u8>,
}

/// Build ZKP #2, sign cast-vote, build helper-share payloads, and persist recovery state.
///
/// Repeated calls for the same `(round_id, bundle_index, proposal_id)` return
/// the persisted recovery bundle without rebuilding the proof.
pub fn commit(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    draft: &DraftVote,
    witness: &VanWitness,
    signer: VoteSigner<'_>,
    stages: &dyn crate::types::VoteCommitStageReporter,
) -> Result<VoteCommit, VotingError> {
    validate_draft_vote(draft)?;

    let (secret, network) = signer_secret_and_network(signer);
    db.require_round_network(round_id, network, "vote signer")?;

    if let Some(recovered) = recovery_bundle(db, round_id, bundle_index, draft.proposal_id)? {
        if recovery_matches_draft(&recovered, draft) {
            return commit_from_recovery(&recovered);
        }
    }
    ensure_vote_rebuild_allowed(db, round_id, bundle_index, draft.proposal_id)?;

    stages.on_stage(VoteCommitStage::ProofStarting {
        proposal_id: draft.proposal_id,
        bundle_index,
    });
    let progress = VoteProofProgressReporter {
        proposal_id: draft.proposal_id,
        bundle_index,
        stages,
    };
    let auth_path = witness.auth_path_fixed()?;
    let bundle = db.build_vote_commitment(
        round_id,
        bundle_index,
        secret,
        network,
        draft.proposal_id,
        draft.choice,
        draft.num_options,
        &auth_path,
        witness.position,
        witness.anchor_height,
        draft.single_share,
        &progress,
    )?;
    let wire_shares = bundle
        .enc_shares
        .iter()
        .map(WireEncryptedShare::from)
        .collect::<Vec<_>>();
    stages.on_stage(VoteCommitStage::SharePayloadsBuilding {
        proposal_id: draft.proposal_id,
        bundle_index,
    });
    let share_payloads = db.build_share_payloads(
        &wire_shares,
        &bundle,
        draft.choice,
        draft.num_options,
        draft.vc_tree_position,
        draft.single_share,
    )?;
    stages.on_stage(VoteCommitStage::Signing {
        proposal_id: draft.proposal_id,
        bundle_index,
    });
    let signature = sign_cast_vote_with_signer(
        signer,
        CastVoteSigningFields {
            vote_round_id: &bundle.vote_round_id,
            r_vpk_bytes: &bundle.r_vpk_bytes,
            van_nullifier: &bundle.van_nullifier,
            vote_authority_note_new: &bundle.vote_authority_note_new,
            vote_commitment: &bundle.vote_commitment,
            proposal_id: bundle.proposal_id,
            anchor_height: bundle.anchor_height,
            alpha_v: &bundle.alpha_v,
        },
    )?;
    let vote_auth_sig = array64("vote_auth_sig", signature.vote_auth_sig)?;
    let recovery = VoteRecoveryBundle::from_parts(bundle_index, draft, bundle, vote_auth_sig)?;
    let commitment_bytes = stored_vote_commitment_bytes(&recovery)?;
    store_recovery_json_for_vote(
        db,
        round_id,
        bundle_index,
        draft.proposal_id,
        draft.choice,
        Some(&commitment_bytes),
        &serialize_recovery(&recovery)?,
    )?;

    Ok(VoteCommit {
        proposal_id: draft.proposal_id,
        van_nullifier: recovery.van_nullifier,
        vote_authority_note_new: recovery.vote_authority_note_new,
        vote_commitment: recovery.vote_commitment,
        proof: recovery.proof,
        anchor_height: recovery.anchor_height,
        r_vpk: recovery.r_vpk,
        vote_auth_sig: recovery.vote_auth_sig,
        encrypted_shares: wire_shares,
        share_payloads,
    })
}

struct VoteProofProgressReporter<'a> {
    proposal_id: u32,
    bundle_index: u32,
    stages: &'a dyn crate::types::VoteCommitStageReporter,
}

impl ProgressReporter for VoteProofProgressReporter<'_> {
    fn on_progress(&self, progress: f64) {
        self.stages.on_stage(VoteCommitStage::ProofProgress {
            proposal_id: self.proposal_id,
            bundle_index: self.bundle_index,
            progress,
        });
    }
}

/// Reconstructs a previously committed vote from persisted recovery state.
///
/// This returns helper-share payloads using the currently stored vote
/// commitment tree position. For the pre-confirmation `NextStep::SubmitVote`
/// cast-vote resend, use [`submission`] so stale helper-share payloads are not
/// accidentally submitted. After `confirmation::confirm_vote_submission`
/// records the confirmed VC position, call this helper again and submit the
/// freshly recovered helper-share payloads.
pub fn recover_commit(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<VoteCommit, VotingError> {
    recovery_bundle(db, round_id, bundle_index, proposal_id)?
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        })
        .and_then(|bundle| commit_from_recovery(&bundle))
}

/// Reconstructs chain-ready cast-vote fields from persisted recovery state.
pub fn submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<VoteSubmission, VotingError> {
    recovery_bundle(db, round_id, bundle_index, proposal_id)?
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        })
        .map(|bundle| VoteSubmission {
            vote_round_id: bundle.vote_round_id,
            proposal_id: bundle.proposal_id,
            van_nullifier: bundle.van_nullifier,
            vote_authority_note_new: bundle.vote_authority_note_new,
            vote_commitment: bundle.vote_commitment,
            proof: bundle.proof,
            r_vpk: bundle.r_vpk,
            vote_auth_sig: bundle.vote_auth_sig,
            anchor_height: bundle.anchor_height,
        })
}

/// Records the cast-vote transaction hash and marks the vote submitted.
pub fn record_submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
) -> Result<(), VotingError> {
    db.record_vote_submission(round_id, bundle_index, proposal_id, tx_hash)
}

/// Records the on-chain vote commitment tree position after confirmation.
pub fn record_vc_position(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    vc_tree_position: u64,
) -> Result<(), VotingError> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    record_vc_position_with_conn(
        &conn,
        &wallet_id,
        round_id,
        bundle_index,
        proposal_id,
        vc_tree_position,
    )
}

pub(crate) fn record_vc_position_with_conn(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    vc_tree_position: u64,
) -> Result<(), VotingError> {
    let vc_tree_position_i64 =
        i64::try_from(vc_tree_position).map_err(|_| VotingError::InvalidInput {
            message: format!("vc_tree_position {vc_tree_position} does not fit in SQLite i64"),
        })?;
    let stored_vote: Option<(i64, Option<Vec<u8>>, Option<String>, Option<i64>)> = {
        conn.query_row(
            "SELECT choice, commitment, commitment_bundle_json, vc_tree_position FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load vote recovery bundle: {e}"),
        })?
    };

    let Some((stored_choice, stored_commitment, stored_json, stored_position)) = stored_vote else {
        return Err(vote_not_found_error(round_id, bundle_index, proposal_id));
    };

    if let Some(stored_position) = stored_position {
        if stored_position < 0 {
            return Err(invalid_stored_vc_position_error(stored_position));
        }
        let stored_position = stored_position as u64;
        if stored_position != vc_tree_position {
            return Err(vc_position_already_recorded_error(
                round_id,
                bundle_index,
                proposal_id,
            ));
        }
    }

    if let Some(json) = stored_json {
        let mut recovery = parse_recovery(&json)?;
        validate_recovery_matches_stored_vote(
            &recovery,
            round_id,
            bundle_index,
            proposal_id,
            stored_choice,
            stored_commitment.as_deref(),
        )?;
        recovery.vc_tree_position = vc_tree_position;
        store_recovery_json_with_vc_position_if_unchanged(
            conn,
            wallet_id,
            round_id,
            bundle_index,
            proposal_id,
            stored_choice,
            stored_commitment.as_deref(),
            &json,
            &serialize_recovery(&recovery)?,
            vc_tree_position_i64,
        )
    } else {
        store_vc_position_if_unset_or_same(
            conn,
            wallet_id,
            round_id,
            bundle_index,
            proposal_id,
            stored_choice,
            stored_commitment.as_deref(),
            vc_tree_position_i64,
        )
    }
}

/// Loads and parses the persisted vote recovery bundle, if present.
pub fn recovery_bundle(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<VoteRecoveryBundle>, VotingError> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    let json: Option<Option<String>> = conn
        .query_row(
            "SELECT commitment_bundle_json FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load vote recovery bundle: {e}"),
        })?;
    json.flatten().as_deref().map(parse_recovery).transpose()
}

/// Serializes a recovery bundle using the library-owned JSON format.
pub fn serialize_recovery(bundle: &VoteRecoveryBundle) -> Result<String, VotingError> {
    validate_recovery_bundle_vote_fields(bundle)?;
    serde_json::to_string(&VoteRecoveryJson::from(bundle)).map_err(|e| VotingError::Internal {
        message: format!("failed to serialize vote recovery bundle: {e}"),
    })
}

/// Parses a recovery bundle from the library-owned JSON format.
pub fn parse_recovery(json: &str) -> Result<VoteRecoveryBundle, VotingError> {
    let parsed: VoteRecoveryJson =
        serde_json::from_str(json).map_err(|e| VotingError::InvalidInput {
            message: format!("invalid vote recovery JSON: {e}"),
        })?;
    if parsed.format != VOTE_RECOVERY_FORMAT {
        return Err(VotingError::InvalidInput {
            message: format!("unsupported vote recovery format: {}", parsed.format),
        });
    }
    VoteRecoveryBundle::try_from(parsed)
}

fn store_recovery_json_for_vote(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    choice: u32,
    commitment: Option<&[u8]>,
    json: &str,
) -> Result<(), VotingError> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    let rows = conn
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id
               AND choice = :choice
               AND (commitment = :commitment OR (commitment IS NULL AND :commitment IS NULL))",
            rusqlite::named_params! {
                ":json": json,
                ":choice": choice as i64,
                ":commitment": commitment,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store vote recovery bundle: {e}"),
        })?;
    if rows == 0 {
        return handle_vote_identity_update_miss(
            &conn,
            round_id,
            &wallet_id,
            bundle_index,
            proposal_id,
            choice as i64,
            commitment,
            "storing recovery",
        );
    }
    Ok(())
}

fn vote_not_found_error(round_id: &str, bundle_index: u32, proposal_id: u32) -> VotingError {
    VotingError::InvalidInput {
        message: format!(
            "vote not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
        ),
    }
}

fn vc_position_already_recorded_error(
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> VotingError {
    VotingError::InvalidInput {
        message: format!(
            "vote commitment tree position already recorded for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
        ),
    }
}

fn invalid_stored_vc_position_error(stored_position: i64) -> VotingError {
    VotingError::Internal {
        message: format!("stored vc_tree_position must be non-negative, got {stored_position}"),
    }
}

fn vote_identity_changed_error(
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    action: &str,
) -> VotingError {
    VotingError::InvalidInput {
        message: format!(
            "vote changed while {action} for round={round_id}, bundle={bundle_index}, proposal={proposal_id}; retry with the current ballot intent"
        ),
    }
}

fn vote_recovery_identity_mismatch_error(
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    field: &str,
) -> VotingError {
    VotingError::InvalidInput {
        message: format!(
            "vote recovery bundle {field} mismatch for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
        ),
    }
}

fn invalid_stored_choice_error(stored_choice: i64) -> VotingError {
    VotingError::Internal {
        message: format!("stored vote choice must be non-negative, got {stored_choice}"),
    }
}

fn validate_recovery_matches_stored_vote(
    recovery: &VoteRecoveryBundle,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    stored_choice: i64,
    stored_commitment: Option<&[u8]>,
) -> Result<(), VotingError> {
    if recovery.vote_round_id != round_id {
        return Err(vote_recovery_identity_mismatch_error(
            round_id,
            bundle_index,
            proposal_id,
            "round_id",
        ));
    }
    if recovery.bundle_index != bundle_index {
        return Err(vote_recovery_identity_mismatch_error(
            round_id,
            bundle_index,
            proposal_id,
            "bundle_index",
        ));
    }
    if recovery.proposal_id != proposal_id {
        return Err(vote_recovery_identity_mismatch_error(
            round_id,
            bundle_index,
            proposal_id,
            "proposal_id",
        ));
    }
    let stored_choice =
        u32::try_from(stored_choice).map_err(|_| invalid_stored_choice_error(stored_choice))?;
    if recovery.vote_decision != stored_choice {
        return Err(vote_recovery_identity_mismatch_error(
            round_id,
            bundle_index,
            proposal_id,
            "vote_decision",
        ));
    }
    if let Some(stored_commitment) = stored_commitment {
        let recovery_commitment = stored_vote_commitment_bytes(recovery)?;
        if stored_commitment != recovery_commitment {
            return Err(vote_recovery_identity_mismatch_error(
                round_id,
                bundle_index,
                proposal_id,
                "commitment",
            ));
        }
    }
    Ok(())
}

fn handle_vote_identity_update_miss(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    choice: i64,
    commitment: Option<&[u8]>,
    action: &str,
) -> Result<(), VotingError> {
    let existing: Option<(i64, Option<Vec<u8>>)> = conn
        .query_row(
            "SELECT choice, commitment FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load vote identity: {e}"),
        })?;

    match existing {
        None => Err(vote_not_found_error(round_id, bundle_index, proposal_id)),
        Some((existing_choice, existing_commitment))
            if existing_choice == choice && existing_commitment.as_deref() == commitment =>
        {
            Ok(())
        }
        Some(_) => Err(vote_identity_changed_error(
            round_id,
            bundle_index,
            proposal_id,
            action,
        )),
    }
}

fn handle_vc_position_update_miss(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    vc_tree_position: i64,
) -> Result<(), VotingError> {
    let existing_position: Option<Option<i64>> = conn
        .query_row(
            "SELECT vc_tree_position FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to load vote commitment tree position: {e}"),
        })?;

    match existing_position {
        None => Err(vote_not_found_error(round_id, bundle_index, proposal_id)),
        Some(Some(existing)) if existing < 0 => Err(invalid_stored_vc_position_error(existing)),
        Some(Some(existing)) if existing != vc_tree_position => Err(
            vc_position_already_recorded_error(round_id, bundle_index, proposal_id),
        ),
        Some(_) => Ok(()),
    }
}

fn store_recovery_json_with_vc_position_if_unchanged(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    choice: i64,
    commitment: Option<&[u8]>,
    expected_json: &str,
    updated_json: &str,
    vc_tree_position: i64,
) -> Result<(), VotingError> {
    let rows = conn
        .execute(
            "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id
               AND choice = :choice
               AND (commitment = :commitment OR (commitment IS NULL AND :commitment IS NULL))
               AND commitment_bundle_json = :expected_json
               AND (vc_tree_position IS NULL OR vc_tree_position = :pos)",
            rusqlite::named_params! {
                ":json": updated_json,
                ":expected_json": expected_json,
                ":choice": choice,
                ":commitment": commitment,
                ":pos": vc_tree_position,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to store vote recovery bundle position: {e}"),
        })?;
    if rows == 0 {
        handle_vote_identity_update_miss(
            conn,
            round_id,
            wallet_id,
            bundle_index,
            proposal_id,
            choice,
            commitment,
            "recording vote commitment tree position",
        )?;
        let current: Option<(Option<String>, Option<i64>)> = conn
            .query_row(
                "SELECT commitment_bundle_json, vc_tree_position FROM votes
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index as i64,
                    ":proposal_id": proposal_id as i64,
                },
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to reload vote recovery bundle: {e}"),
            })?;
        match current {
            Some((Some(current_json), Some(current_position)))
                if current_json == updated_json && current_position == vc_tree_position =>
            {
                return Ok(());
            }
            Some((_, Some(current_position))) if current_position != vc_tree_position => {
                return handle_vc_position_update_miss(
                    conn,
                    round_id,
                    wallet_id,
                    bundle_index,
                    proposal_id,
                    vc_tree_position,
                );
            }
            Some(_) => {
                return Err(vote_identity_changed_error(
                    round_id,
                    bundle_index,
                    proposal_id,
                    "recording vote commitment tree position",
                ));
            }
            None => return Err(vote_not_found_error(round_id, bundle_index, proposal_id)),
        }
    }
    Ok(())
}

fn store_vc_position_if_unset_or_same(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    choice: i64,
    commitment: Option<&[u8]>,
    vc_tree_position: i64,
) -> Result<(), VotingError> {
    let rows = conn
        .execute(
            "UPDATE votes SET vc_tree_position = :pos
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id
               AND choice = :choice
               AND (commitment = :commitment OR (commitment IS NULL AND :commitment IS NULL))
               AND (vc_tree_position IS NULL OR vc_tree_position = :pos)",
            rusqlite::named_params! {
                ":pos": vc_tree_position,
                ":choice": choice,
                ":commitment": commitment,
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to record vote commitment tree position: {e}"),
        })?;
    if rows == 0 {
        handle_vote_identity_update_miss(
            conn,
            round_id,
            wallet_id,
            bundle_index,
            proposal_id,
            choice,
            commitment,
            "recording vote commitment tree position",
        )?;
        return handle_vc_position_update_miss(
            conn,
            round_id,
            wallet_id,
            bundle_index,
            proposal_id,
            vc_tree_position,
        );
    }
    Ok(())
}

fn commit_from_recovery(bundle: &VoteRecoveryBundle) -> Result<VoteCommit, VotingError> {
    let wire_shares = bundle
        .encrypted_shares
        .iter()
        .map(WireEncryptedShare::from)
        .collect::<Vec<_>>();
    let share_payloads = crate::share::recover_payloads(bundle)?;
    Ok(VoteCommit {
        proposal_id: bundle.proposal_id,
        van_nullifier: bundle.van_nullifier,
        vote_authority_note_new: bundle.vote_authority_note_new,
        vote_commitment: bundle.vote_commitment,
        proof: bundle.proof.clone(),
        anchor_height: bundle.anchor_height,
        r_vpk: bundle.r_vpk,
        vote_auth_sig: bundle.vote_auth_sig,
        encrypted_shares: wire_shares,
        share_payloads,
    })
}

fn stored_vote_commitment_bytes(bundle: &VoteRecoveryBundle) -> Result<Vec<u8>, VotingError> {
    serde_json::to_vec(&serde_json::json!({
        "van_nullifier": hex::encode(bundle.van_nullifier),
        "vote_authority_note_new": hex::encode(bundle.vote_authority_note_new),
        "vote_commitment": hex::encode(bundle.vote_commitment),
        "proof": hex::encode(&bundle.proof),
    }))
    .map_err(|e| VotingError::Internal {
        message: format!("failed to serialize vote commitment: {e}"),
    })
}

fn recovery_matches_draft(bundle: &VoteRecoveryBundle, draft: &DraftVote) -> bool {
    bundle.vote_decision == draft.choice
        && bundle.num_options == draft.num_options
        && bundle.single_share == draft.single_share
        && bundle.vc_tree_position == draft.vc_tree_position
}

pub(crate) fn validate_recovery_bundle_vote_fields(
    bundle: &VoteRecoveryBundle,
) -> Result<(), VotingError> {
    validate_proposal_id(bundle.proposal_id)?;
    validate_vote_decision(bundle.vote_decision, bundle.num_options)?;
    Ok(())
}

fn ensure_vote_rebuild_allowed(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    let has_tx_hash = conn
        .query_row(
            "SELECT tx_hash IS NOT NULL FROM votes
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index
               AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| Ok(row.get::<_, i64>(0)? != 0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to check vote submission state: {e}"),
        })?
        .unwrap_or(false);

    if has_tx_hash {
        return Err(VotingError::InvalidInput {
            message: format!(
                "round {round_id} bundle {bundle_index} proposal {proposal_id} has a submitted vote that conflicts with requested draft"
            ),
        });
    }
    Ok(())
}

impl VoteRecoveryBundle {
    fn from_parts(
        bundle_index: u32,
        draft: &DraftVote,
        bundle: VoteCommitmentBundle,
        vote_auth_sig: [u8; 64],
    ) -> Result<Self, VotingError> {
        Ok(Self {
            vote_round_id: bundle.vote_round_id,
            bundle_index,
            proposal_id: bundle.proposal_id,
            vote_decision: draft.choice,
            anchor_height: bundle.anchor_height,
            vc_tree_position: draft.vc_tree_position,
            single_share: draft.single_share,
            num_options: draft.num_options,
            van_nullifier: array32("van_nullifier", bundle.van_nullifier)?,
            vote_authority_note_new: array32(
                "vote_authority_note_new",
                bundle.vote_authority_note_new,
            )?,
            vote_commitment: array32("vote_commitment", bundle.vote_commitment)?,
            proof: bundle.proof,
            shares_hash: array32("shares_hash", bundle.shares_hash)?,
            r_vpk: array32("r_vpk", bundle.r_vpk_bytes)?,
            alpha_v: array32("alpha_v", bundle.alpha_v)?,
            vote_auth_sig,
            encrypted_shares: bundle.enc_shares,
            share_blinds: array32_vec("share_blinds", bundle.share_blinds)?,
            share_comms: array32_vec("share_comms", bundle.share_comms)?,
        })
    }
}

impl From<&VoteRecoveryBundle> for VoteRecoveryJson {
    fn from(bundle: &VoteRecoveryBundle) -> Self {
        Self {
            format: VOTE_RECOVERY_FORMAT.to_string(),
            vote_round_id: bundle.vote_round_id.clone(),
            bundle_index: bundle.bundle_index,
            proposal_id: bundle.proposal_id,
            vote_decision: bundle.vote_decision,
            anchor_height: bundle.anchor_height,
            vc_tree_position: bundle.vc_tree_position,
            single_share: bundle.single_share,
            num_options: bundle.num_options,
            van_nullifier: bundle.van_nullifier.to_vec(),
            vote_authority_note_new: bundle.vote_authority_note_new.to_vec(),
            vote_commitment: bundle.vote_commitment.to_vec(),
            proof: bundle.proof.clone(),
            shares_hash: bundle.shares_hash.to_vec(),
            r_vpk: bundle.r_vpk.to_vec(),
            alpha_v: bundle.alpha_v.to_vec(),
            vote_auth_sig: bundle.vote_auth_sig.to_vec(),
            encrypted_shares: bundle
                .encrypted_shares
                .iter()
                .map(EncryptedShareJson::from)
                .collect(),
            share_blinds: bundle.share_blinds.iter().map(|v| v.to_vec()).collect(),
            share_comms: bundle.share_comms.iter().map(|v| v.to_vec()).collect(),
        }
    }
}

impl TryFrom<VoteRecoveryJson> for VoteRecoveryBundle {
    type Error = VotingError;

    fn try_from(value: VoteRecoveryJson) -> Result<Self, Self::Error> {
        validate_proposal_id(value.proposal_id)?;
        validate_vote_decision(value.vote_decision, value.num_options)?;

        Ok(Self {
            vote_round_id: value.vote_round_id,
            bundle_index: value.bundle_index,
            proposal_id: value.proposal_id,
            vote_decision: value.vote_decision,
            anchor_height: value.anchor_height,
            vc_tree_position: value.vc_tree_position,
            single_share: value.single_share,
            num_options: value.num_options,
            van_nullifier: array32("van_nullifier", value.van_nullifier)?,
            vote_authority_note_new: array32(
                "vote_authority_note_new",
                value.vote_authority_note_new,
            )?,
            vote_commitment: array32("vote_commitment", value.vote_commitment)?,
            proof: value.proof,
            shares_hash: array32("shares_hash", value.shares_hash)?,
            r_vpk: array32("r_vpk", value.r_vpk)?,
            alpha_v: array32("alpha_v", value.alpha_v)?,
            vote_auth_sig: array64("vote_auth_sig", value.vote_auth_sig)?,
            encrypted_shares: value
                .encrypted_shares
                .into_iter()
                .map(EncryptedShare::from)
                .collect(),
            share_blinds: array32_vec("share_blinds", value.share_blinds)?,
            share_comms: array32_vec("share_comms", value.share_comms)?,
        })
    }
}

impl From<&EncryptedShare> for EncryptedShareJson {
    fn from(share: &EncryptedShare) -> Self {
        Self {
            c1: share.c1.clone(),
            c2: share.c2.clone(),
            share_index: share.share_index,
            plaintext_value: share.plaintext_value,
            randomness: share.randomness.clone(),
        }
    }
}

impl From<EncryptedShareJson> for EncryptedShare {
    fn from(value: EncryptedShareJson) -> Self {
        Self {
            c1: value.c1,
            c2: value.c2,
            share_index: value.share_index,
            plaintext_value: value.plaintext_value,
            randomness: value.randomness,
        }
    }
}

fn array32(label: &str, value: Vec<u8>) -> Result<[u8; 32], VotingError> {
    value
        .try_into()
        .map_err(|value: Vec<u8>| VotingError::Internal {
            message: format!("{label} must be 32 bytes, got {}", value.len()),
        })
}

fn array64(label: &str, value: Vec<u8>) -> Result<[u8; 64], VotingError> {
    value
        .try_into()
        .map_err(|value: Vec<u8>| VotingError::Internal {
            message: format!("{label} must be 64 bytes, got {}", value.len()),
        })
}

fn array32_vec(label: &str, values: Vec<Vec<u8>>) -> Result<Vec<[u8; 32]>, VotingError> {
    values
        .into_iter()
        .enumerate()
        .map(|(idx, value)| array32(&format!("{label}[{idx}]"), value))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        round::RoundParams,
        storage::{queries, VotingDb},
        types::{NoopProgressReporter, NoteInfo, MAX_PROPOSAL_ID, MAX_VOTE_OPTIONS},
    };

    const ROUND_ID: &str = "0101010101010101010101010101010101010101010101010101010101010101";
    const WALLET_ID: &str = "wallet";

    fn db_with_vote() -> VotingDb {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[note(0)]).unwrap();
        queries::store_vote(&db.conn(), ROUND_ID, WALLET_ID, 0, 1, 2, &[0xCA; 32]).unwrap();
        db
    }

    fn round_params() -> RoundParams {
        RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 1000,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    fn note(position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
            value: crate::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: "uview1test".to_string(),
        }
    }

    fn recovery_bundle_fixture() -> VoteRecoveryBundle {
        VoteRecoveryBundle {
            vote_round_id: ROUND_ID.to_string(),
            bundle_index: 0,
            proposal_id: 1,
            vote_decision: 2,
            anchor_height: 123,
            vc_tree_position: 456,
            single_share: false,
            num_options: 3,
            van_nullifier: [0x10; 32],
            vote_authority_note_new: [0x11; 32],
            vote_commitment: [0x12; 32],
            proof: vec![0x13; 96],
            shares_hash: [0x14; 32],
            r_vpk: [0x15; 32],
            alpha_v: [0x16; 32],
            vote_auth_sig: [0x17; 64],
            encrypted_shares: vec![
                EncryptedShare {
                    c1: vec![0x21; 32],
                    c2: vec![0x22; 32],
                    share_index: 0,
                    plaintext_value: 5,
                    randomness: vec![0x23; 32],
                },
                EncryptedShare {
                    c1: vec![0x31; 32],
                    c2: vec![0x32; 32],
                    share_index: 1,
                    plaintext_value: 6,
                    randomness: vec![0x33; 32],
                },
            ],
            share_blinds: vec![[0x41; 32], [0x42; 32]],
            share_comms: vec![[0x51; 32], [0x52; 32]],
        }
    }

    fn draft_vote_fixture() -> DraftVote {
        DraftVote {
            proposal_id: 1,
            choice: 0,
            num_options: 2,
            single_share: false,
            vc_tree_position: 0,
        }
    }

    #[test]
    fn draft_vote_validation_accepts_valid_bounds() {
        assert!(validate_draft_vote(&draft_vote_fixture()).is_ok());
        assert!(validate_draft_vote(&DraftVote {
            proposal_id: MAX_PROPOSAL_ID,
            choice: MAX_VOTE_OPTIONS - 1,
            num_options: MAX_VOTE_OPTIONS,
            ..draft_vote_fixture()
        })
        .is_ok());
    }

    #[test]
    fn draft_vote_validation_rejects_invalid_bounds() {
        assert!(validate_draft_vote(&DraftVote {
            proposal_id: 0,
            ..draft_vote_fixture()
        })
        .is_err());
        assert!(validate_draft_vote(&DraftVote {
            proposal_id: MAX_PROPOSAL_ID + 1,
            ..draft_vote_fixture()
        })
        .is_err());
        assert!(validate_draft_vote(&DraftVote {
            num_options: 1,
            ..draft_vote_fixture()
        })
        .is_err());
        assert!(validate_draft_vote(&DraftVote {
            choice: 2,
            num_options: 2,
            ..draft_vote_fixture()
        })
        .is_err());
    }

    #[test]
    fn draft_votes_validation_rejects_empty_batches() {
        assert!(validate_draft_votes(&[]).is_err());
        assert!(validate_draft_votes(&[draft_vote_fixture()]).is_ok());
    }

    #[test]
    fn van_witness_from_wire_validates_length_and_element_size() {
        let mut auth_path = vec![vec![0xAA; 32]; VAN_AUTH_PATH_LEN];
        let witness = VanWitness::from_wire(&auth_path, 7, 123).unwrap();
        assert_eq!(witness.position, 7);
        assert_eq!(witness.anchor_height, 123);
        assert_eq!(witness.auth_path[0], [0xAA; 32]);

        auth_path.pop();
        let wrong_length = VanWitness::from_wire(&auth_path, 7, 123).unwrap_err();
        assert!(wrong_length.to_string().contains("24 siblings"));

        let wrong_width = vec![vec![0xAA; 31]; VAN_AUTH_PATH_LEN];
        let wrong_width_err = VanWitness::from_wire(&wrong_width, 7, 123).unwrap_err();
        assert!(wrong_width_err.to_string().contains("32 bytes"));
    }

    #[test]
    fn validate_draft_votes_rejects_invalid_inputs_before_db_work() {
        assert!(validate_draft_votes(&[])
            .unwrap_err()
            .to_string()
            .contains("must not be empty"));
        assert!(validate_draft_votes(&[DraftVote {
            proposal_id: 0,
            choice: 0,
            num_options: 2,
            single_share: false,
            vc_tree_position: 0,
        }])
        .unwrap_err()
        .to_string()
        .contains("proposal_id"));
        assert!(validate_draft_votes(&[DraftVote {
            proposal_id: 1,
            choice: 0,
            num_options: 1,
            single_share: false,
            vc_tree_position: 0,
        }])
        .unwrap_err()
        .to_string()
        .contains("num_options"));
        assert!(validate_draft_votes(&[DraftVote {
            proposal_id: 1,
            choice: 2,
            num_options: 2,
            single_share: false,
            vc_tree_position: 0,
        }])
        .unwrap_err()
        .to_string()
        .contains("vote_decision"));
    }

    #[test]
    fn recovery_json_round_trip_preserves_vote_and_share_material() {
        let bundle = recovery_bundle_fixture();

        let json = serialize_recovery(&bundle).unwrap();
        let parsed = parse_recovery(&json).unwrap();

        assert_eq!(parsed.vote_round_id, ROUND_ID);
        assert_eq!(parsed.proposal_id, 1);
        assert_eq!(parsed.vote_auth_sig, [0x17; 64]);
        assert_eq!(parsed.encrypted_shares.len(), 2);
        assert_eq!(parsed.encrypted_shares[0].plaintext_value, 5);
        assert_eq!(parsed.encrypted_shares[0].randomness, vec![0x23; 32]);
        assert_eq!(parsed.share_blinds[1], [0x42; 32]);
        assert_eq!(parsed.share_comms[0], [0x51; 32]);
    }

    #[test]
    fn recovery_json_rejects_invalid_vote_bounds() {
        let json = serialize_recovery(&recovery_bundle_fixture()).unwrap();
        let mut value: serde_json::Value = serde_json::from_str(&json).unwrap();

        value["proposal_id"] = serde_json::json!(0);
        assert!(parse_recovery(&value.to_string()).is_err());

        value["proposal_id"] = serde_json::json!(1);
        value["num_options"] = serde_json::json!(9);
        assert!(parse_recovery(&value.to_string()).is_err());

        value["num_options"] = serde_json::json!(3);
        value["vote_decision"] = serde_json::json!(3);
        assert!(parse_recovery(&value.to_string()).is_err());
    }

    #[test]
    fn recovery_json_serialization_rejects_invalid_vote_bounds() {
        let mut bundle = recovery_bundle_fixture();
        bundle.num_options = 1;

        assert!(serialize_recovery(&bundle).is_err());
    }

    #[test]
    fn recovered_commit_is_replayed_only_for_matching_draft() {
        let bundle = recovery_bundle_fixture();
        let matching = DraftVote {
            proposal_id: 1,
            choice: 2,
            num_options: 3,
            single_share: false,
            vc_tree_position: 456,
        };
        assert!(recovery_matches_draft(&bundle, &matching));

        assert!(!recovery_matches_draft(
            &bundle,
            &DraftVote {
                choice: 1,
                ..matching.clone()
            }
        ));
        assert!(!recovery_matches_draft(
            &bundle,
            &DraftVote {
                num_options: 4,
                ..matching.clone()
            }
        ));
        assert!(!recovery_matches_draft(
            &bundle,
            &DraftVote {
                single_share: true,
                ..matching.clone()
            }
        ));
        assert!(!recovery_matches_draft(
            &bundle,
            &DraftVote {
                vc_tree_position: 789,
                ..matching
            }
        ));
    }

    #[test]
    fn typed_hotkey_signer_signs_cast_vote_payload_with_its_network() {
        use orchard::{
            keys::SpendAuthorizingKey,
            primitives::redpallas::{Signature, SpendAuth, VerificationKey},
        };

        fn randomized_verification_key(
            seed: &[u8],
            network: Network,
            alpha: &pasta_curves::pallas::Scalar,
        ) -> VerificationKey<SpendAuth> {
            let sk = crate::hotkey::spending_key_from_hotkey_seed(
                seed,
                network,
                crate::hotkey::VOTING_HOTKEY_ACCOUNT_INDEX,
            )
            .unwrap();
            let ask = SpendAuthorizingKey::from(&sk);
            VerificationKey::from(&ask.randomize(alpha))
        }

        let hotkey = VotingHotkey::from_stored_secret(&[0xAB; 64], Network::Regtest).unwrap();
        let r_vpk = [0x10; 32];
        let van_nullifier = [0x11; 32];
        let vote_authority_note_new = [0x12; 32];
        let vote_commitment = [0x13; 32];
        let mut alpha_v = [0u8; 32];
        alpha_v[0] = 7;
        let fields = || CastVoteSigningFields {
            vote_round_id: ROUND_ID,
            r_vpk_bytes: &r_vpk,
            van_nullifier: &van_nullifier,
            vote_authority_note_new: &vote_authority_note_new,
            vote_commitment: &vote_commitment,
            proposal_id: 1,
            anchor_height: 123,
            alpha_v: &alpha_v,
        };

        let typed_sig = sign_cast_vote_with_signer(VoteSigner::hotkey(&hotkey), fields()).unwrap();
        assert_eq!(typed_sig.vote_auth_sig.len(), 64);

        let sighash = crate::vote_commitment::cast_vote_sighash(
            ROUND_ID,
            &r_vpk,
            &van_nullifier,
            &vote_authority_note_new,
            &vote_commitment,
            1,
            123,
        )
        .unwrap();
        let alpha = pasta_curves::pallas::Scalar::from(7);
        let regtest_key =
            randomized_verification_key(hotkey.stored_secret(), Network::Regtest, &alpha);

        let typed_sig_bytes: [u8; 64] = typed_sig.vote_auth_sig.as_slice().try_into().unwrap();
        regtest_key
            .verify(&sighash, &Signature::<SpendAuth>::from(typed_sig_bytes))
            .unwrap();

        assert_ne!(Network::Regtest, Network::Testnet);
    }

    #[test]
    fn submitted_vote_rebuild_is_rejected() {
        let db = db_with_vote();
        db.record_vote_submission(ROUND_ID, 0, 1, "vote-tx")
            .unwrap();

        let err = ensure_vote_rebuild_allowed(&db, ROUND_ID, 0, 1)
            .expect_err("submitted votes cannot be rebuilt");

        assert!(
            err.to_string()
                .contains("submitted vote that conflicts with requested draft"),
            "{err}"
        );
    }

    #[test]
    fn vote_lifecycle_apis_replay_persisted_recovery_happy_path() {
        let db = db_with_vote();
        let recovery = recovery_bundle_fixture();
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            &commitment,
        )
        .unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &serialize_recovery(&recovery).unwrap(),
        )
        .unwrap();

        let loaded = recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().unwrap();
        assert_eq!(loaded.vote_commitment, [0x12; 32]);

        let submission = submission(&db, ROUND_ID, 0, 1).unwrap();
        assert_eq!(submission.vote_round_id, ROUND_ID);
        assert_eq!(submission.r_vpk, [0x15; 32]);
        assert_eq!(submission.vote_auth_sig, [0x17; 64]);

        let recovered = recover_commit(&db, ROUND_ID, 0, 1).unwrap();
        assert_eq!(recovered.vote_commitment, [0x12; 32]);
        assert_eq!(recovered.share_payloads.len(), 2);

        let commit = commit(
            &db,
            ROUND_ID,
            0,
            &DraftVote {
                proposal_id: 1,
                choice: 2,
                num_options: 3,
                single_share: false,
                vc_tree_position: 456,
            },
            &VanWitness {
                auth_path: vec![vec![0xAA; 32]; VAN_AUTH_PATH_LEN],
                position: 7,
                anchor_height: 123,
            },
            VoteSigner::hotkey(
                &VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap(),
            ),
            &NoopProgressReporter,
        )
        .unwrap();
        assert_eq!(commit.vote_commitment, [0x12; 32]);
        assert_eq!(commit.encrypted_shares.len(), 2);
        assert_eq!(commit.share_payloads.len(), 2);

        record_submission(&db, ROUND_ID, 0, 1, "txid").unwrap();
        assert_eq!(
            db.get_vote_tx_hash(ROUND_ID, 0, 1).unwrap().as_deref(),
            Some("txid")
        );
        assert_eq!(
            db.vote_phase(ROUND_ID, 0, 1).unwrap(),
            crate::phases::VotePhase::Submitted
        );

        record_vc_position(&db, ROUND_ID, 0, 1, 789).unwrap();
        record_vc_position(&db, ROUND_ID, 0, 1, 789).unwrap();
        let conflict = record_vc_position(&db, ROUND_ID, 0, 1, 790)
            .expect_err("different confirmed tree position must fail");
        assert!(
            conflict
                .to_string()
                .contains("tree position already recorded"),
            "{conflict}"
        );
        assert_eq!(
            db.vote_phase(ROUND_ID, 0, 1).unwrap(),
            crate::phases::VotePhase::Confirmed
        );
        let (_, position) = db.get_commitment_bundle(ROUND_ID, 0, 1).unwrap().unwrap();
        assert_eq!(position, 789);
        assert_eq!(
            recovery_bundle(&db, ROUND_ID, 0, 1)
                .unwrap()
                .unwrap()
                .vc_tree_position,
            789
        );
    }

    #[test]
    fn commit_rejects_signer_network_mismatch_before_recovery_replay() {
        let db = db_with_vote();
        let recovery = recovery_bundle_fixture();
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            &commitment,
        )
        .unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &serialize_recovery(&recovery).unwrap(),
        )
        .unwrap();

        let err = commit(
            &db,
            ROUND_ID,
            0,
            &DraftVote {
                proposal_id: 1,
                choice: 2,
                num_options: 3,
                single_share: false,
                vc_tree_position: 456,
            },
            &VanWitness {
                auth_path: vec![vec![0xAA; 32]; VAN_AUTH_PATH_LEN],
                position: 7,
                anchor_height: 123,
            },
            VoteSigner::hotkey(
                &VotingHotkey::from_stored_secret(&[0x99; 64], Network::Mainnet).unwrap(),
            ),
            &NoopProgressReporter,
        )
        .unwrap_err();

        assert!(
            err.to_string().contains(
                "vote signer network Mainnet does not match stored round network Testnet"
            ),
            "{err}"
        );
    }

    #[test]
    fn committed_vote_handle_replays_and_records_lifecycle() {
        let db = db_with_vote();
        let mut recovery = recovery_bundle_fixture();
        recovery.share_blinds = vec![scalar_bytes(1), scalar_bytes(2)];
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            &commitment,
        )
        .unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &serialize_recovery(&recovery).unwrap(),
        )
        .unwrap();

        let committed = CommittedVote::commit(
            &db,
            ROUND_ID,
            0,
            &DraftVote {
                proposal_id: 1,
                choice: 2,
                num_options: 3,
                single_share: false,
                vc_tree_position: 456,
            },
            &VanWitness {
                auth_path: vec![vec![0xAA; 32]; VAN_AUTH_PATH_LEN],
                position: 7,
                anchor_height: 123,
            },
            VoteSigner::hotkey(
                &VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap(),
            ),
            &NoopProgressReporter,
        )
        .unwrap();

        assert_eq!(committed.round_id(), ROUND_ID);
        assert_eq!(committed.bundle_index(), 0);
        assert_eq!(committed.proposal_id(), 1);
        assert_eq!(committed.data().vote_commitment, [0x12; 32]);
        assert_eq!(committed.share_payloads().len(), 2);
        assert_eq!(
            committed.recovery_json(&db).unwrap(),
            serialize_recovery(&recovery).unwrap()
        );

        let recovered = CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
        assert_eq!(
            recovered.data().vote_commitment,
            committed.data().vote_commitment
        );
        let submission = recovered.submission(&db).unwrap();
        assert_eq!(submission.vote_round_id, ROUND_ID);
        assert_eq!(submission.vote_auth_sig, [0x17; 64]);

        recovered
            .record_share(&db, 0, &["https://helper-a.example".to_string()], 1234)
            .unwrap();
        recovered
            .add_sent_servers(&db, 0, &["https://helper-b.example".to_string()])
            .unwrap();
        let shares = crate::share::list(&db, ROUND_ID).unwrap();
        assert_eq!(shares.len(), 1);
        assert_eq!(
            shares[0].sent_to_urls,
            vec![
                "https://helper-a.example".to_string(),
                "https://helper-b.example".to_string()
            ]
        );

        recovered.confirm_share(&db, 0).unwrap();
        assert!(crate::share::unconfirmed(&db, ROUND_ID).unwrap().is_empty());

        recovered.record_submission(&db, "vote-tx").unwrap();
        assert_eq!(
            db.get_vote_tx_hash(ROUND_ID, 0, 1).unwrap().as_deref(),
            Some("vote-tx")
        );
        recovered.record_vc_position(&db, 789).unwrap();
        assert_eq!(
            recovery_bundle(&db, ROUND_ID, 0, 1)
                .unwrap()
                .unwrap()
                .vc_tree_position,
            789
        );
    }

    #[test]
    fn signed_commitment_exposes_public_payload_without_reparsing_json() {
        let db = db_with_vote();
        let mut recovery = recovery_bundle_fixture();
        recovery.share_blinds = vec![scalar_bytes(1), scalar_bytes(2)];
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            &commitment,
        )
        .unwrap();
        let recovery_json = serialize_recovery(&recovery).unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &recovery_json,
        )
        .unwrap();

        let committed = CommittedVote::recover(&db, ROUND_ID, 0, 1).unwrap();
        let signed = committed.signed_commitment(&db).unwrap();

        assert_eq!(signed.proposal_id, 1);
        assert_eq!(signed.choice, recovery.vote_decision);
        assert_eq!(signed.vote_round_id, ROUND_ID);
        assert_eq!(signed.share_payloads.len(), 2);
        assert_eq!(signed.encrypted_shares[0].c1, vec![0x21; 32]);
        assert_eq!(signed.shares_hash, [0x14; 32]);
        assert_eq!(signed.share_comms[0], [0x51; 32]);
        assert_eq!(signed.r_vpk, [0x15; 32]);
        assert_eq!(signed.vote_auth_sig, [0x17; 64]);
        assert_eq!(signed.commitment_bundle_json, recovery_json);
    }

    #[test]
    fn commit_batch_returns_signed_commitments_for_bundle() {
        let db = db_with_vote();
        let mut recovery = recovery_bundle_fixture();
        recovery.share_blinds = vec![scalar_bytes(1), scalar_bytes(2)];
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            &commitment,
        )
        .unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &serialize_recovery(&recovery).unwrap(),
        )
        .unwrap();

        let result = commit_batch(
            &db,
            ROUND_ID,
            0,
            &[DraftVote {
                proposal_id: 1,
                choice: 2,
                num_options: 3,
                single_share: false,
                vc_tree_position: 456,
            }],
            &VanWitness {
                auth_path: vec![vec![0xAA; 32]; VAN_AUTH_PATH_LEN],
                position: 7,
                anchor_height: 123,
            },
            VoteSigner::hotkey(
                &VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap(),
            ),
            &NoopProgressReporter,
        )
        .unwrap();

        assert_eq!(result.bundle_index, 0);
        assert_eq!(result.commitments.len(), 1);
        assert_eq!(result.commitments[0].proposal_id, 1);
        assert_eq!(result.commitments[0].choice, 2);
    }

    #[test]
    fn recover_signed_commitments_returns_single_item_batch() {
        let db = db_with_vote();
        let mut recovery = recovery_bundle_fixture();
        recovery.share_blinds = vec![scalar_bytes(1), scalar_bytes(2)];
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            &commitment,
        )
        .unwrap();
        let recovery_json = serialize_recovery(&recovery).unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &recovery_json,
        )
        .unwrap();

        let signed = recover_signed_commitments(&db, ROUND_ID, 0, 1).unwrap();
        assert_eq!(signed.bundle_index, 0);
        assert_eq!(signed.commitments.len(), 1);
        assert_eq!(signed.commitments[0].commitment_bundle_json, recovery_json);
    }

    #[test]
    fn recovery_json_write_rejects_replaced_vote_identity() {
        let db = db_with_vote();
        let recovery = recovery_bundle_fixture();
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();

        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            3,
            &[0xDD; 32],
        )
        .unwrap();
        let err = store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            recovery.bundle_index,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &serialize_recovery(&recovery).unwrap(),
        )
        .unwrap_err();

        assert!(
            err.to_string()
                .contains("vote changed while storing recovery"),
            "{err}"
        );
    }

    #[test]
    fn recovery_bundle_missing_vote_returns_none() {
        let db = db_with_vote();

        let recovery = recovery_bundle(&db, ROUND_ID, 0, 99).unwrap();

        assert!(recovery.is_none());
    }

    #[test]
    fn record_vc_position_without_recovery_json_updates_column() {
        let db = db_with_vote();

        record_vc_position(&db, ROUND_ID, 0, 1, 321).unwrap();
        record_vc_position(&db, ROUND_ID, 0, 1, 321).unwrap();
        let conflict = record_vc_position(&db, ROUND_ID, 0, 1, 322)
            .expect_err("different tree position must fail");
        assert!(
            conflict
                .to_string()
                .contains("tree position already recorded"),
            "{conflict}"
        );
        let position: Option<i64> = db
            .conn()
            .query_row(
                "SELECT vc_tree_position FROM votes
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::named_params! {
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(position, Some(321));
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn record_vc_position_missing_vote_returns_invalid_input() {
        let db = db_with_vote();

        let err = record_vc_position(&db, ROUND_ID, 0, 99, 321).unwrap_err();

        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }

    fn scalar_bytes(value: u8) -> [u8; 32] {
        let mut bytes = [0u8; 32];
        bytes[0] = value;
        bytes
    }
}
