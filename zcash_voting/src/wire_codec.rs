//! Behavioral helpers for `crate::wire` DTOs.
//!
//! This module owns conversion/serialization logic (`TryFrom`, `From`,
//! `to_json`, and payload shaping) that depends on internal crate types such as
//! `VotingError`, recovery records, and share payload models.
//!
//! It is kept separate from `wire.rs` so the FRB-scanned `wire` module can stay
//! struct-only and expose a clean, stable cross-language schema.

#[allow(unused_imports)]
pub(crate) use crate::backend::{orchard, pasta_curves, zcash_client_backend};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use pasta_curves::group::ff::PrimeField;
use pasta_curves::pallas;

use crate::{
    delegate::{DelegationSubmission, PreparedDelegationReport, SignedDelegationBundle},
    phases::WorkflowPhase,
    recovery, session,
    types::{
        validate_32_bytes, validate_encrypted_shares, validate_proposal_id, validate_round_params,
        validate_share_index, validate_vote_chain_id, validate_vote_round_id_hex, Network, NoteRef,
        RoundBoundVotingHotkeyTarget, SelectedNotes, SharePayload, VotingError, VotingHotkeyTarget,
        MAX_VOTE_OPTIONS,
    },
    vote::{SignedVoteBatch, SignedVoteCommitment, SignedVoteCommitments},
    wire::{
        CompletedVoteChoiceView, CompletedVoteDisplayView, DelegationPirPrecomputeResultView,
        DelegationRecoveryView, DelegationRecoveryWorkView, DelegationStatusView,
        DelegationSubmissionWire, NextStepView, RoundPlanView, RoundRecoveryStateView,
        ShareDelegationRecordView, ShareWorkflowRecoveryView, SignedDelegationPayloadView,
        SignedVoteBatchView, SignedVoteCommitmentView, SignedVoteCommitmentsView,
        VoteCommitmentBatchWire, VoteCommitmentWire, VoteRecoveryView, VoteRecoveryWorkView,
        VoteShareWire, VotingHotkeyTargetV1, VotingNoteRefView, VotingNoteSelectionResultView,
        VotingRoundParams,
    },
    BundlePolicy,
};

const MAX_SAFE_JSON_INTEGER: u64 = 0x1f_ffff_ffff_ffff;
const MAX_HELPER_TREE_POSITION: u64 = u32::MAX as u64;
const VOTING_HOTKEY_TARGET_FORMAT_VERSION: u32 = 1;
const MAX_VOTING_HOTKEY_TARGET_JSON_BYTES: usize = 2_048;
const MAX_VOTE_SHARE_JSON_BYTES: usize = 4_096;

impl VotingHotkeyTargetV1 {
    /// Parses and validates a version 1 target from JSON.
    ///
    /// Object field order is ignored. Unknown fields, duplicate keys, and
    /// noncanonical encodings are rejected.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when the JSON or any target field
    /// violates the version 1 contract.
    pub fn from_json(json: &str) -> Result<Self, VotingError> {
        if json.len() > MAX_VOTING_HOTKEY_TARGET_JSON_BYTES {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "voting hotkey target JSON exceeds {} bytes",
                    MAX_VOTING_HOTKEY_TARGET_JSON_BYTES
                ),
            });
        }
        let wire: Self = serde_json::from_str(json).map_err(|e| VotingError::InvalidInput {
            message: format!("invalid voting hotkey target JSON: {e}"),
        })?;
        wire.validated_parts()?;
        Ok(wire)
    }

    /// Serializes a valid version 1 target as compact JSON.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when any public DTO field violates
    /// the version 1 contract.
    pub fn to_json(&self) -> Result<String, VotingError> {
        self.validated_parts()?;
        serde_json::to_string(self).map_err(|e| VotingError::Internal {
            message: format!("serialize voting hotkey target JSON failed: {e}"),
        })
    }

    /// Validates this public target against the caller's chain, network, and
    /// round context.
    ///
    /// This is the only public constructor for
    /// [`RoundBoundVotingHotkeyTarget`].
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when the DTO is malformed, the
    /// expected context is invalid, or any bound value differs.
    pub fn validate_for(
        &self,
        expected_chain_id: &str,
        expected_network: Network,
        expected_round_params: &VotingRoundParams,
    ) -> Result<RoundBoundVotingHotkeyTarget, VotingError> {
        let (target, vote_round_id) = self.validated_parts()?;
        validate_vote_chain_id(expected_chain_id)?;
        validate_round_params(expected_round_params)?;

        if self.vote_chain_id != expected_chain_id {
            return Err(VotingError::InvalidInput {
                message: "vote_chain_id does not match the expected vote chain".to_string(),
            });
        }
        if target.network() != expected_network {
            return Err(VotingError::InvalidInput {
                message: "network does not match the expected network".to_string(),
            });
        }
        if self.vote_round_id != expected_round_params.vote_round_id {
            return Err(VotingError::InvalidInput {
                message: "vote_round_id does not match the expected round".to_string(),
            });
        }

        Ok(RoundBoundVotingHotkeyTarget::from_validated_parts(
            target,
            self.vote_chain_id.clone(),
            vote_round_id,
        ))
    }

    pub(crate) fn validated_parts(&self) -> Result<(VotingHotkeyTarget, [u8; 32]), VotingError> {
        if self.format_version != VOTING_HOTKEY_TARGET_FORMAT_VERSION {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "format_version must be {}, got {}",
                    VOTING_HOTKEY_TARGET_FORMAT_VERSION, self.format_version
                ),
            });
        }

        validate_vote_chain_id(&self.vote_chain_id)?;
        let network = parse_target_network(&self.network)?;
        validate_vote_round_id_hex(&self.vote_round_id)?;
        let vote_round_id: [u8; 32] = hex::decode(&self.vote_round_id)
            .expect("validated lowercase hex must decode")
            .try_into()
            .expect("validated vote_round_id must contain 32 bytes");

        if self.address_index != crate::hotkey::VOTING_HOTKEY_ADDRESS_INDEX {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "address_index must be {}, got {}",
                    crate::hotkey::VOTING_HOTKEY_ADDRESS_INDEX,
                    self.address_index
                ),
            });
        }

        if self.raw_orchard_address.len() != 60 || !self.raw_orchard_address.ends_with("==") {
            return Err(VotingError::InvalidInput {
                message: "raw_orchard_address must be canonical padded standard Base64".to_string(),
            });
        }
        let raw_orchard_address = BASE64_STANDARD
            .decode(self.raw_orchard_address.as_bytes())
            .map_err(|e| VotingError::InvalidInput {
                message: format!("raw_orchard_address is not valid standard Base64: {e}"),
            })?;
        if BASE64_STANDARD.encode(&raw_orchard_address) != self.raw_orchard_address {
            return Err(VotingError::InvalidInput {
                message: "raw_orchard_address must use its canonical Base64 encoding".to_string(),
            });
        }
        let target = VotingHotkeyTarget::from_raw_orchard_address(&raw_orchard_address, network)?;

        Ok((target, vote_round_id))
    }
}

fn parse_target_network(network: &str) -> Result<Network, VotingError> {
    match network {
        "mainnet" => Ok(Network::Mainnet),
        "testnet" => Ok(Network::Testnet),
        "regtest" => Ok(Network::Regtest),
        _ => Err(VotingError::InvalidInput {
            message: "network must be exactly mainnet, testnet, or regtest".to_string(),
        }),
    }
}

impl DelegationSubmissionWire {
    pub fn to_json(&self) -> Result<String, VotingError> {
        serde_json::to_string(self).map_err(|e| VotingError::Internal {
            message: format!("serialize delegation wire JSON failed: {e}"),
        })
    }
}

impl VoteCommitmentWire {
    pub fn to_json(&self) -> Result<String, VotingError> {
        serde_json::to_string(self).map_err(|e| VotingError::Internal {
            message: format!("serialize vote commitment wire JSON failed: {e}"),
        })
    }
}

impl VoteCommitmentBatchWire {
    /// Serializes the exact JSON request accepted by vote-sdk's batch endpoint.
    ///
    /// Returns [`VotingError::InvalidInput`] unless the batch contains between
    /// one and [`crate::vote::MAX_VOTE_BATCH_ACTIONS`] actions.
    pub fn to_json(&self) -> Result<String, VotingError> {
        if self.votes.is_empty() || self.votes.len() > crate::vote::MAX_VOTE_BATCH_ACTIONS {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "atomic vote batch must contain between 1 and {} actions, got {}",
                    crate::vote::MAX_VOTE_BATCH_ACTIONS,
                    self.votes.len()
                ),
            });
        }
        serde_json::to_string(self).map_err(|e| VotingError::Internal {
            message: format!("serialize vote commitment batch JSON failed: {e}"),
        })
    }
}

impl VoteShareWire {
    /// Parses and validates one helper-share request from JSON.
    ///
    /// Unknown and duplicate fields, noncanonical encodings, oversized input,
    /// and values outside the helper protocol's bounds are rejected.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when the JSON or any share field
    /// violates the helper request contract.
    pub fn from_json(json: &str) -> Result<Self, VotingError> {
        if json.len() > MAX_VOTE_SHARE_JSON_BYTES {
            return Err(VotingError::InvalidInput {
                message: format!("vote share JSON exceeds {MAX_VOTE_SHARE_JSON_BYTES} bytes"),
            });
        }
        let wire: Self = serde_json::from_str(json).map_err(|e| VotingError::InvalidInput {
            message: format!("invalid vote share JSON: {e}"),
        })?;
        wire.validate()?;
        Ok(wire)
    }

    pub fn from_payload(
        payload: &SharePayload,
        vc_tree_position: Option<u64>,
        submit_at: u64,
    ) -> Result<Self, VotingError> {
        crate::types::validate_vote_round_id_hex(&payload.vote_round_id)?;
        let wire = Self {
            vote_round_id: payload.vote_round_id.clone(),
            shares_hash: b64(&payload.shares_hash),
            proposal_id: payload.proposal_id,
            vote_decision: payload.vote_decision,
            encrypted_share: payload.enc_share.clone(),
            share_index: payload.enc_share.share_index,
            vc_tree_position: helper_tree_position(
                vc_tree_position.unwrap_or(payload.tree_position),
            )?,
            share_comms: payload.share_comms.iter().map(b64).collect(),
            primary_blind: b64(&payload.primary_blind),
            submit_at: json_safe_u64(submit_at, "submit_at")?,
        };
        wire.validate()?;
        Ok(wire)
    }

    pub fn to_json(&self) -> Result<String, VotingError> {
        self.validate()?;
        serde_json::to_string(self).map_err(|e| VotingError::Internal {
            message: format!("serialize vote share wire JSON failed: {e}"),
        })
    }

    pub fn with_late_bound(
        mut self,
        vc_tree_position: Option<u64>,
        submit_at: u64,
    ) -> Result<Self, VotingError> {
        if let Some(position) = vc_tree_position {
            self.vc_tree_position = helper_tree_position(position)?;
        }
        self.submit_at = json_safe_u64(submit_at, "submit_at")?;
        Ok(self)
    }

    fn validate(&self) -> Result<(), VotingError> {
        validate_vote_round_id_hex(&self.vote_round_id)?;
        validate_canonical_field_b64_32(&self.shares_hash, "shares_hash")?;
        validate_proposal_id(self.proposal_id)?;
        if self.vote_decision >= MAX_VOTE_OPTIONS {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "vote_decision must be in [0, {MAX_VOTE_OPTIONS}), got {}",
                    self.vote_decision
                ),
            });
        }
        validate_encrypted_shares(std::slice::from_ref(&self.encrypted_share))?;
        validate_share_index(self.share_index)?;
        if self.share_index != self.encrypted_share.share_index {
            return Err(VotingError::InvalidInput {
                message: "share_index must match enc_share.share_index".to_string(),
            });
        }
        helper_tree_position(self.vc_tree_position)?;
        if self.share_comms.len() != crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "share_comms must have exactly {} entries, got {}",
                    crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT,
                    self.share_comms.len()
                ),
            });
        }
        for (index, share_comm) in self.share_comms.iter().enumerate() {
            validate_canonical_field_b64_32(share_comm, &format!("share_comms[{index}]"))?;
        }
        validate_canonical_field_b64_32(&self.primary_blind, "primary_blind")?;
        json_safe_u64(self.submit_at, "submit_at")?;
        Ok(())
    }
}

fn decode_canonical_b64_32(value: &str, field: &str) -> Result<[u8; 32], VotingError> {
    let decoded =
        BASE64_STANDARD
            .decode(value.as_bytes())
            .map_err(|_| VotingError::InvalidInput {
                message: format!("{field} must be canonical padded standard Base64"),
            })?;
    if BASE64_STANDARD.encode(&decoded) != value {
        return Err(VotingError::InvalidInput {
            message: format!("{field} must be canonical padded standard Base64"),
        });
    }
    validate_32_bytes(&decoded, field)?;
    Ok(decoded
        .try_into()
        .expect("validated 32-byte value must convert to an array"))
}

fn validate_canonical_field_b64_32(value: &str, field: &str) -> Result<(), VotingError> {
    let decoded = decode_canonical_b64_32(value, field)?;
    Option::<pallas::Base>::from(pallas::Base::from_repr(decoded))
        .map(|_| ())
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!("{field} is not a canonical Pallas field element"),
        })
}

impl TryFrom<&DelegationSubmission> for DelegationSubmissionWire {
    type Error = VotingError;

    fn try_from(submission: &DelegationSubmission) -> Result<Self, Self::Error> {
        Ok(Self {
            rk: b64(submission.rk),
            spend_auth_sig: b64(submission.spend_auth_sig),
            tx1_effects: b64(&submission.tx1_effects),
            nf_signed: b64(submission.nf_signed),
            cmx_new: b64(submission.cmx_new),
            gov_comm: b64(submission.gov_comm),
            gov_nullifiers: submission.gov_nullifiers.iter().map(b64).collect(),
            proof: b64(&submission.proof),
            vote_round_id: b64_hex(&submission.vote_round_id, "vote_round_id")?,
        })
    }
}

impl TryFrom<&SignedVoteCommitment> for VoteCommitmentWire {
    type Error = VotingError;

    fn try_from(commitment: &SignedVoteCommitment) -> Result<Self, Self::Error> {
        Ok(Self {
            van_nullifier: b64(commitment.van_nullifier),
            vote_authority_note_new: b64(commitment.vote_authority_note_new),
            vote_commitment: b64(commitment.vote_commitment),
            proposal_id: commitment.proposal_id,
            proof: b64(&commitment.proof),
            vote_round_id: b64_hex(&commitment.vote_round_id, "vote_round_id")?,
            anchor_height: commitment.anchor_height,
            r_vpk: b64(commitment.r_vpk),
            vote_auth_sig: b64(commitment.vote_auth_sig),
        })
    }
}

impl DelegationSubmission {
    pub fn to_wire_json(&self) -> Result<String, VotingError> {
        DelegationSubmissionWire::try_from(self)?.to_json()
    }
}

impl SignedVoteCommitment {
    pub fn to_wire_json(&self) -> Result<String, VotingError> {
        VoteCommitmentWire::try_from(self)?.to_json()
    }
}

impl SharePayload {
    pub fn to_wire_json(
        &self,
        vc_tree_position: Option<u64>,
        submit_at: u64,
    ) -> Result<String, VotingError> {
        VoteShareWire::from_payload(self, vc_tree_position, submit_at)?.to_json()
    }
}

impl From<NoteRef> for VotingNoteRefView {
    fn from(note: NoteRef) -> Self {
        Self {
            pool: note.pool,
            txid_hex: note.txid_hex,
            output_index: note.output_index,
            value_zatoshi: note.value_zatoshi,
            voting_weight_zatoshi: note.voting_weight_zatoshi,
            commitment_tree_position: note.commitment_tree_position,
            mined_height: note.mined_height,
            anchor_height: note.anchor_height,
        }
    }
}

impl VotingNoteSelectionResultView {
    /// Builds a selection view using the policy authoritative for `round_id`.
    ///
    /// Wallet setup persists the effective policy before this view is built.
    pub fn from_selected_for_round(
        selected: SelectedNotes,
        voting_db: &crate::round::VotingDb,
        round_id: &str,
    ) -> Result<Self, VotingError> {
        let effective_policy =
            voting_db.effective_bundle_policy(round_id, BundlePolicy::default())?;
        Self::from_selected_with_policy(selected, effective_policy)
    }

    fn from_selected_with_policy(
        selected: SelectedNotes,
        bundle_policy: BundlePolicy,
    ) -> Result<Self, VotingError> {
        let note_count =
            u32::try_from(selected.notes.len()).map_err(|_| VotingError::InvalidInput {
                message: format!(
                    "Selected note count {} does not fit in u32",
                    selected.notes.len()
                ),
            })?;
        // Plan once so the reported weight and the privacy trim describe the
        // same bundle set; recomputing the weight separately could drift.
        // Malformed note rows report zero weight rather than failing, matching
        // the behavior this view had when it called `voting_power_with_policy`.
        let plan = crate::note_bundling::canonical_note_bundle_plan_for_notes(
            &selected.voting_note_infos(),
            bundle_policy,
        )
        .ok();
        let eligible_weight_zatoshi = plan.as_ref().map_or(0, |plan| plan.eligible_weight);
        let privacy_trim = plan.map(|plan| plan.privacy_trim).unwrap_or_default();
        let snapshot_height = selected.snapshot_height;
        let anchor_height = selected.anchor_tree_state.height;
        let notes = selected.notes.into_iter().map(Into::into).collect();
        Ok(Self {
            note_count,
            eligible_weight_zatoshi,
            snapshot_height,
            anchor_height,
            notes,
            privacy_trim,
        })
    }
}

impl From<PreparedDelegationReport> for DelegationPirPrecomputeResultView {
    fn from(result: PreparedDelegationReport) -> Self {
        Self {
            cached_count: result.report.cached,
            fetched_count: result.report.fetched,
            bundle_count: result.layout.bundle_count,
            bundle_index: result.bundle_index,
        }
    }
}

impl TryFrom<SignedDelegationBundle> for SignedDelegationPayloadView {
    type Error = VotingError;

    fn try_from(result: SignedDelegationBundle) -> Result<Self, Self::Error> {
        let submission = DelegationSubmissionWire::try_from(&result.submission)?;
        Ok(Self {
            pczt_bytes: result.pczt_bytes,
            status: "ready_for_submission".to_string(),
            message: None,
            submission,
            eligible_weight_zatoshi: result.eligible_weight_zatoshi,
            delegated_weight_zatoshi: result.delegated_weight_zatoshi,
            bundle_count: result.bundle_count,
            bundle_index: result.bundle_index,
        })
    }
}

impl TryFrom<SignedVoteCommitment> for SignedVoteCommitmentView {
    type Error = VotingError;

    fn try_from(commitment: SignedVoteCommitment) -> Result<Self, Self::Error> {
        let wire = VoteCommitmentWire::try_from(&commitment)?;
        let shares = commitment
            .share_payloads
            .iter()
            .map(|payload| VoteShareWire::from_payload(payload, None, 0))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(Self {
            proposal_id: commitment.proposal_id,
            wire,
            shares,
        })
    }
}

impl TryFrom<SignedVoteCommitments> for SignedVoteCommitmentsView {
    type Error = VotingError;

    fn try_from(commitments: SignedVoteCommitments) -> Result<Self, Self::Error> {
        Ok(Self {
            bundle_index: commitments.bundle_index,
            commitments: commitments
                .commitments
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<Vec<_>, _>>()?,
        })
    }
}

impl TryFrom<SignedVoteBatch> for SignedVoteBatchView {
    type Error = VotingError;

    fn try_from(batch: SignedVoteBatch) -> Result<Self, Self::Error> {
        Ok(Self {
            bundle_index: batch.bundle_index,
            commitments: batch
                .commitments
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<Vec<_>, _>>()?,
            batch_digest: batch.batch_digest.to_vec(),
            batch_json: batch.batch_json,
        })
    }
}

impl From<recovery::DelegationRecovery> for DelegationRecoveryView {
    fn from(record: recovery::DelegationRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            phase: record.workflow_phase().as_str().to_string(),
            tx_hash: record.tx_hash,
            van_leaf_position: record.van_leaf_position,
        }
    }
}

impl From<recovery::VoteRecovery> for VoteRecoveryView {
    fn from(record: recovery::VoteRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            choice: record.choice,
            phase: record.workflow_phase().as_str().to_string(),
            tx_hash: record.tx_hash,
            vc_tree_position: record.vc_tree_position,
            has_commitment_bundle: record.has_commitment_bundle,
        }
    }
}

impl From<crate::types::ShareDelegationRecord> for ShareDelegationRecordView {
    fn from(record: crate::types::ShareDelegationRecord) -> Self {
        Self {
            round_id: record.round_id,
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            share_index: record.share_index,
            sent_to_urls: record.sent_to_urls,
            nullifier: record.nullifier,
            phase: if record.confirmed {
                WorkflowPhase::Confirmed.as_str().to_string()
            } else {
                WorkflowPhase::SubmittedShare.as_str().to_string()
            },
            confirmed: record.confirmed,
            submit_at: record.submit_at,
            created_at: record.created_at,
        }
    }
}

impl From<recovery::ShareWorkflow> for ShareWorkflowRecoveryView {
    fn from(record: recovery::ShareWorkflow) -> Self {
        Self {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            share_index: record.share_index,
            phase: record.workflow_phase().as_str().to_string(),
        }
    }
}

impl From<recovery::RoundRecoverySnapshot> for RoundRecoveryStateView {
    fn from(state: recovery::RoundRecoverySnapshot) -> Self {
        Self {
            round_id: state.round_id,
            bundle_count: state.bundle_count,
            delegation: state.delegation.into_iter().map(Into::into).collect(),
            votes: state.votes.into_iter().map(Into::into).collect(),
            commitment_bundles: state.commitment_bundles,
            shares: state.shares.into_iter().map(Into::into).collect(),
            share_delegations: state
                .share_delegations
                .into_iter()
                .map(Into::into)
                .collect(),
            unconfirmed_share_delegations: state
                .unconfirmed_share_delegations
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

impl TryFrom<session::NextStep> for NextStepView {
    type Error = VotingError;

    fn try_from(step: session::NextStep) -> Result<Self, Self::Error> {
        let kind = step.kind().to_string();
        match step {
            session::NextStep::Delegate { bundle_index }
            | session::NextStep::PollDelegation { bundle_index } => Ok(Self {
                kind,
                bundle_index,
                proposal_id: 0,
                choice: 0,
                share_index: 0,
            }),
            session::NextStep::CastVote {
                bundle_index,
                proposal_id,
                choice,
            } => Ok(Self {
                kind,
                bundle_index,
                proposal_id,
                choice,
                share_index: 0,
            }),
            session::NextStep::SubmitVote {
                bundle_index,
                proposal_id,
            }
            | session::NextStep::SubmitVoteBatch {
                bundle_index,
                proposal_id,
            }
            | session::NextStep::PollVote {
                bundle_index,
                proposal_id,
            }
            | session::NextStep::PollVoteBatch {
                bundle_index,
                proposal_id,
            } => Ok(Self {
                kind,
                bundle_index,
                proposal_id,
                choice: 0,
                share_index: 0,
            }),
            session::NextStep::SubmitShares {
                bundle_index,
                proposal_id,
                share_index,
            }
            | session::NextStep::ConfirmShare {
                bundle_index,
                proposal_id,
                share_index,
            } => Ok(Self {
                kind,
                bundle_index,
                proposal_id,
                choice: 0,
                share_index,
            }),
        }
    }
}

impl From<session::DelegationStatus> for DelegationStatusView {
    fn from(status: session::DelegationStatus) -> Self {
        Self {
            bundle_index: status.bundle_index,
            phase: WorkflowPhase::for_delegation(status.phase)
                .as_str()
                .to_string(),
            tx_hash: status.tx_hash,
        }
    }
}

impl From<session::DelegationRecoveryWork> for DelegationRecoveryWorkView {
    fn from(work: session::DelegationRecoveryWork) -> Self {
        Self {
            kind: work.kind.as_str().to_string(),
            bundle_index: work.bundle_index,
            phase: WorkflowPhase::for_delegation(work.phase)
                .as_str()
                .to_string(),
            tx_hash: work.tx_hash,
        }
    }
}

impl From<session::VoteRecoveryWork> for VoteRecoveryWorkView {
    fn from(work: session::VoteRecoveryWork) -> Self {
        Self {
            kind: work.kind.as_str().to_string(),
            bundle_index: work.bundle_index,
            proposal_id: work.proposal_id,
            tx_hash: work.tx_hash,
            vc_tree_position: work.vc_tree_position,
            share_indexes: work.share_indexes,
        }
    }
}

impl From<session::CompletedVoteChoice> for CompletedVoteChoiceView {
    fn from(choice: session::CompletedVoteChoice) -> Self {
        Self {
            proposal_id: choice.proposal_id,
            choice: choice.choice,
        }
    }
}

impl From<session::CompletedVoteDisplay> for CompletedVoteDisplayView {
    fn from(display: session::CompletedVoteDisplay) -> Self {
        Self {
            choices: display.choices.into_iter().map(Into::into).collect(),
            voted_at: display.voted_at,
        }
    }
}

impl TryFrom<session::RoundPlan> for RoundPlanView {
    type Error = VotingError;

    fn try_from(plan: session::RoundPlan) -> Result<Self, Self::Error> {
        Ok(Self {
            round_id: plan.round_id,
            pending_recovery: plan.pending_recovery,
            blocking_recovery: plan.blocking_recovery,
            blocking_share_work: plan.blocking_share_work,
            hotkey_bound: plan.hotkey_bound,
            completed_vote_artifact: plan.completed_vote_artifact,
            completed_for_display: plan.completed_for_display,
            completed_vote_display: plan.completed_vote_display.map(Into::into),
            needs_draft_setup: plan.needs_draft_setup,
            primary_action: plan.primary_action.as_str().to_string(),
            next_steps: plan
                .next_steps
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<Vec<_>, _>>()?,
            delegation_statuses: plan
                .delegation_statuses
                .into_iter()
                .map(Into::into)
                .collect(),
            recovered_delegation_work: plan
                .recovered_delegation_work
                .into_iter()
                .map(Into::into)
                .collect(),
            recovered_vote_work: plan
                .recovered_vote_work
                .into_iter()
                .map(Into::into)
                .collect(),
            open_proposals: plan.open_proposals,
            immediate_share_key: plan.immediate_share_key,
            all_decided: plan.all_decided,
        })
    }
}

fn b64(bytes: impl AsRef<[u8]>) -> String {
    BASE64_STANDARD.encode(bytes.as_ref())
}

fn b64_hex(hex_value: &str, field: &str) -> Result<String, VotingError> {
    let normalized = hex_value.strip_prefix("0x").unwrap_or(hex_value);
    let bytes = hex::decode(normalized).map_err(|e| VotingError::InvalidInput {
        message: format!("{field} is not valid hex: {e}"),
    })?;
    Ok(b64(bytes))
}

fn json_safe_u64(value: u64, field: &str) -> Result<u64, VotingError> {
    if value > MAX_SAFE_JSON_INTEGER {
        return Err(VotingError::InvalidInput {
            message: format!("field {field} is too large to encode as JSON integer"),
        });
    }
    Ok(value)
}

fn helper_tree_position(value: u64) -> Result<u64, VotingError> {
    if value > MAX_HELPER_TREE_POSITION {
        return Err(VotingError::InvalidInput {
            message: format!(
                "field tree_position exceeds helper protocol maximum {MAX_HELPER_TREE_POSITION}"
            ),
        });
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vote::SignedVoteCommitment;
    use crate::VotingHotkey;
    use pasta_curves::group::{Group, GroupEncoding};
    use zcash_client_backend::proto::service::TreeState;

    fn decode_b64(value: &str) -> Vec<u8> {
        BASE64_STANDARD.decode(value).unwrap()
    }

    fn point_bytes(multiplier: u64) -> Vec<u8> {
        (pallas::Point::generator() * pallas::Scalar::from(multiplier))
            .to_bytes()
            .to_vec()
    }

    fn field_bytes(value: u64) -> Vec<u8> {
        pallas::Base::from(value).to_repr().to_vec()
    }

    fn full_share_comm_arrays() -> Vec<[u8; 32]> {
        (0..crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT)
            .map(|index| pallas::Base::from(index as u64 + 10).to_repr())
            .collect()
    }

    fn full_share_comms() -> Vec<Vec<u8>> {
        full_share_comm_arrays()
            .into_iter()
            .map(|comm| comm.to_vec())
            .collect()
    }

    fn valid_vote_share_wire() -> VoteShareWire {
        VoteShareWire {
            vote_round_id: "01".repeat(32),
            shares_hash: b64(field_bytes(1)),
            proposal_id: 1,
            vote_decision: 0,
            encrypted_share: crate::WireEncryptedShare {
                c1: point_bytes(2),
                c2: point_bytes(3),
                share_index: 0,
            },
            share_index: 0,
            vc_tree_position: 1,
            share_comms: full_share_comms().iter().map(b64).collect(),
            primary_blind: b64(field_bytes(4)),
            submit_at: 0,
        }
    }

    fn target_round_params(value: u64) -> VotingRoundParams {
        VotingRoundParams {
            vote_round_id: hex::encode(pallas::Base::from(value).to_repr()),
            snapshot_height: 100,
            ea_pk: vec![0xEA; 32],
            nc_root: vec![0xAA; 32],
            nullifier_imt_root: vec![0xBB; 32],
        }
    }

    fn valid_voting_hotkey_target_wire() -> VotingHotkeyTargetV1 {
        let hotkey = VotingHotkey::from_stored_secret(&[0xAB; 64], Network::Regtest).unwrap();
        VotingHotkeyTargetV1 {
            format_version: 1,
            vote_chain_id: "vote-chain-1".to_string(),
            network: "regtest".to_string(),
            vote_round_id: target_round_params(7).vote_round_id,
            address_index: 0,
            raw_orchard_address: BASE64_STANDARD.encode(hotkey.raw_orchard_address()),
        }
    }

    #[test]
    fn voting_hotkey_target_json_roundtrip_validates_expected_context() {
        let wire = valid_voting_hotkey_target_wire();
        let json = wire.to_json().unwrap();
        assert_eq!(
            json,
            format!(
                "{{\"format_version\":1,\"vote_chain_id\":\"vote-chain-1\",\"network\":\"regtest\",\"vote_round_id\":\"{}\",\"address_index\":0,\"raw_orchard_address\":\"{}\"}}",
                wire.vote_round_id, wire.raw_orchard_address
            )
        );

        let reordered = format!(
            "{{\"raw_orchard_address\":\"{}\",\"address_index\":0,\"vote_round_id\":\"{}\",\"network\":\"regtest\",\"vote_chain_id\":\"vote-chain-1\",\"format_version\":1}}",
            wire.raw_orchard_address, wire.vote_round_id
        );
        let parsed = VotingHotkeyTargetV1::from_json(&reordered).unwrap();
        assert_eq!(parsed, wire);

        let round_params = target_round_params(7);
        let bound = parsed
            .validate_for("vote-chain-1", Network::Regtest, &round_params)
            .unwrap();
        let hotkey = VotingHotkey::from_stored_secret(&[0xAB; 64], Network::Regtest).unwrap();
        assert_eq!(bound.target(), hotkey.delegation_target());
        assert_eq!(bound.vote_chain_id(), "vote-chain-1");
        assert_eq!(
            bound.vote_round_id().as_slice(),
            hex::decode(&wire.vote_round_id).unwrap()
        );
    }

    #[test]
    fn voting_hotkey_target_json_rejects_unknown_duplicate_and_wrong_types() {
        let wire = valid_voting_hotkey_target_wire();
        let json = wire.to_json().unwrap();

        let unknown = format!("{},\"extra\":true}}", json.strip_suffix('}').unwrap());
        assert!(VotingHotkeyTargetV1::from_json(&unknown).is_err());

        let duplicate = format!(
            "{},\"network\":\"regtest\"}}",
            json.strip_suffix('}').unwrap()
        );
        assert!(VotingHotkeyTargetV1::from_json(&duplicate).is_err());

        let wrong_type = json.replace("\"format_version\":1", "\"format_version\":\"1\"");
        assert!(VotingHotkeyTargetV1::from_json(&wrong_type).is_err());

        let oversized = format!("{json}{}", " ".repeat(MAX_VOTING_HOTKEY_TARGET_JSON_BYTES));
        assert!(VotingHotkeyTargetV1::from_json(&oversized).is_err());
    }

    #[test]
    fn voting_hotkey_target_wire_rejects_invalid_scalar_fields() {
        let mut wire = valid_voting_hotkey_target_wire();
        wire.format_version = 2;
        assert!(wire.to_json().is_err());

        for invalid_chain_id in ["", "chain id", "chain\n", "chaîn"] {
            let mut wire = valid_voting_hotkey_target_wire();
            wire.vote_chain_id = invalid_chain_id.to_string();
            assert!(wire.to_json().is_err(), "{invalid_chain_id:?}");
        }
        let mut wire = valid_voting_hotkey_target_wire();
        wire.vote_chain_id = "x".repeat(129);
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        wire.network = "Regtest".to_string();
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        wire.vote_round_id = "AA".repeat(32);
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        wire.vote_round_id = "00".repeat(31);
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        wire.vote_round_id = "ff".repeat(32);
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        wire.address_index = 1;
        assert!(wire.to_json().is_err());
    }

    #[test]
    fn voting_hotkey_target_wire_rejects_noncanonical_or_invalid_address() {
        let mut wire = valid_voting_hotkey_target_wire();
        wire.raw_orchard_address = wire.raw_orchard_address.trim_end_matches('=').to_string();
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        wire.raw_orchard_address = BASE64_STANDARD
            .encode([0xFB; 43])
            .replace('+', "-")
            .replace('/', "_");
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        let mut noncanonical = wire.raw_orchard_address.into_bytes();
        let trailing = noncanonical
            .get_mut(57)
            .expect("43-byte Base64 has a second data character before padding");
        *trailing = match *trailing {
            b'A' => b'B',
            b'Q' => b'R',
            b'g' => b'h',
            b'w' => b'x',
            value => panic!("unexpected canonical trailing Base64 character {value}"),
        };
        wire.raw_orchard_address = String::from_utf8(noncanonical).unwrap();
        assert!(wire.to_json().is_err());

        let mut wire = valid_voting_hotkey_target_wire();
        wire.raw_orchard_address = BASE64_STANDARD.encode([0xFF; 43]);
        let err = wire.to_json().unwrap_err();
        assert!(err
            .to_string()
            .contains("raw_orchard_address is not a valid Orchard address"));
    }

    #[test]
    fn voting_hotkey_target_validation_rejects_context_mismatches() {
        let wire = valid_voting_hotkey_target_wire();
        let round_params = target_round_params(7);

        let chain_err = wire
            .validate_for("other-chain", Network::Regtest, &round_params)
            .unwrap_err();
        assert!(chain_err
            .to_string()
            .contains("vote_chain_id does not match"));

        let network_err = wire
            .validate_for("vote-chain-1", Network::Testnet, &round_params)
            .unwrap_err();
        assert!(network_err.to_string().contains("network does not match"));

        let round_err = wire
            .validate_for("vote-chain-1", Network::Regtest, &target_round_params(8))
            .unwrap_err();
        assert!(round_err
            .to_string()
            .contains("vote_round_id does not match"));
    }

    fn test_tree_state(height: u64) -> TreeState {
        TreeState {
            network: "test".to_string(),
            height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
            ironwood_tree: String::new(),
        }
    }

    fn test_note_ref(
        value_zatoshi: u64,
        voting_weight_zatoshi: u64,
        commitment_tree_position: u64,
    ) -> NoteRef {
        NoteRef {
            pool: "orchard".to_string(),
            txid_hex: hex::encode([commitment_tree_position as u8; 32]),
            output_index: commitment_tree_position as u32,
            value_zatoshi,
            voting_weight_zatoshi,
            commitment: vec![0x01; 32],
            nullifier: vec![commitment_tree_position as u8; 32],
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: String::new(),
            commitment_tree_position,
            mined_height: 1,
            anchor_height: 100,
        }
    }

    #[test]
    fn delegation_submission_wire_json_shape() {
        let submission = DelegationSubmission {
            proof: vec![0xAA; 8],
            rk: [0x01; 32],
            nf_signed: [0x02; 32],
            cmx_new: [0x03; 32],
            gov_comm: [0x04; 32],
            gov_nullifiers: [[0x05; 32]; crate::BUNDLE_NOTE_SLOTS],
            alpha: [0; 32],
            vote_round_id: "0a0b".to_string(),
            spend_auth_sig: [0x06; 64],
            sighash: [0x07; 32],
            tx1_effects: crate::tx1::placeholder_tx1_effects(),
        };

        let json = submission.to_wire_json().unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert!(value.get("sighash").is_none());
        assert!(value.get("signed_note_nullifier").is_some());
        assert!(value.get("van_cmx").is_some());
        assert_eq!(
            decode_b64(value.get("tx1_effects").unwrap().as_str().unwrap()),
            crate::tx1::placeholder_tx1_effects()
        );
        assert_eq!(
            decode_b64(value.get("vote_round_id").unwrap().as_str().unwrap()),
            vec![0x0a, 0x0b]
        );
    }

    #[test]
    fn vote_commitment_wire_json_shape() {
        let commitment = SignedVoteCommitment {
            proposal_id: 7,
            choice: 1,
            vote_round_id: "0c0d".to_string(),
            van_nullifier: [0x11; 32],
            vote_authority_note_new: [0x12; 32],
            vote_commitment: [0x13; 32],
            proof: vec![0x14; 8],
            encrypted_shares: vec![],
            share_payloads: vec![],
            anchor_height: 123,
            shares_hash: [0x15; 32],
            share_comms: vec![],
            r_vpk: [0x16; 32],
            vote_auth_sig: [0x17; 64],
            commitment_bundle_json: "{}".to_string(),
        };

        let json = commitment.to_wire_json().unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(
            value
                .get("vote_comm_tree_anchor_height")
                .unwrap()
                .as_u64()
                .unwrap(),
            123
        );
        assert_eq!(value.get("proposal_id").unwrap().as_u64().unwrap(), 7);
    }

    #[test]
    fn vote_share_wire_json_contains_only_assigned_encrypted_share() {
        let payload = SharePayload {
            vote_round_id: "01".repeat(32),
            shares_hash: field_bytes(1),
            proposal_id: 9,
            vote_decision: 2,
            enc_share: crate::WireEncryptedShare {
                c1: point_bytes(2),
                c2: point_bytes(3),
                share_index: 1,
            },
            tree_position: 99,
            all_enc_shares: vec![
                crate::WireEncryptedShare {
                    c1: vec![0x24; 32],
                    c2: vec![0x25; 32],
                    share_index: 0,
                },
                crate::WireEncryptedShare {
                    c1: vec![0x28; 32],
                    c2: vec![0x29; 32],
                    share_index: 1,
                },
            ],
            share_comms: full_share_comms(),
            primary_blind: field_bytes(4),
        };

        let json = payload.to_wire_json(None, 123).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value.get("tree_position").unwrap().as_u64().unwrap(), 99);
        assert_eq!(value.get("submit_at").unwrap().as_u64().unwrap(), 123);
        assert_eq!(value["vote_round_id"], "01".repeat(32));
        assert_eq!(value["enc_share"]["share_index"].as_u64().unwrap(), 1);
        assert_eq!(value["enc_share"]["c1"], b64(&payload.enc_share.c1));
        assert_eq!(value["enc_share"]["c2"], b64(&payload.enc_share.c2));
        assert!(
            value.get("all_enc_shares").is_none(),
            "helper wire JSON does not include all_enc_shares"
        );
    }

    #[test]
    fn vote_share_wire_from_json_rejects_noncanonical_shares_hash_field() {
        let mut wire = valid_vote_share_wire();
        wire.shares_hash = BASE64_STANDARD.encode([0xff_u8; 32]);
        let raw_json = serde_json::to_string(&wire).unwrap();

        let error = VoteShareWire::from_json(&raw_json).unwrap_err();

        assert!(
            error
                .to_string()
                .contains("shares_hash is not a canonical Pallas field element"),
            "{error}"
        );
    }

    #[test]
    fn vote_share_wire_rejects_tree_position_above_helper_protocol_maximum() {
        let payload = SharePayload {
            vote_round_id: "01".repeat(32),
            shares_hash: vec![0x21; 32],
            proposal_id: 1,
            vote_decision: 1,
            enc_share: crate::WireEncryptedShare {
                c1: vec![0x22; 32],
                c2: vec![0x23; 32],
                share_index: 0,
            },
            tree_position: MAX_SAFE_JSON_INTEGER + 1,
            all_enc_shares: vec![],
            share_comms: vec![],
            primary_blind: vec![0x27; 32],
        };

        let err = payload.to_wire_json(None, 10).unwrap_err();
        assert!(err
            .to_string()
            .contains("field tree_position exceeds helper protocol maximum 4294967295"));
    }

    #[test]
    fn vote_share_wire_accepts_maximum_helper_tree_position() {
        let mut wire = valid_vote_share_wire();
        wire.vc_tree_position = MAX_HELPER_TREE_POSITION;

        let json = wire.to_json().unwrap();
        let decoded = VoteShareWire::from_json(&json).unwrap();

        assert_eq!(decoded.vc_tree_position, MAX_HELPER_TREE_POSITION);
    }

    #[test]
    fn vote_share_wire_json_rejects_noncanonical_vote_round_id() {
        let payload = SharePayload {
            vote_round_id: "AA".repeat(32),
            shares_hash: vec![0x21; 32],
            proposal_id: 1,
            vote_decision: 1,
            enc_share: crate::WireEncryptedShare {
                c1: vec![0x22; 32],
                c2: vec![0x23; 32],
                share_index: 0,
            },
            tree_position: 1,
            all_enc_shares: vec![],
            share_comms: vec![],
            primary_blind: vec![0x27; 32],
        };

        let err = payload
            .to_wire_json(None, 10)
            .expect_err("non-canonical vote round ID should fail");
        assert!(err.to_string().contains("vote_round_id"), "{err}");
    }

    #[test]
    fn vote_share_wire_to_json_rejects_noncanonical_vote_round_id() {
        let mut wire = VoteShareWire::from_payload(
            &SharePayload {
                vote_round_id: "01".repeat(32),
                shares_hash: field_bytes(1),
                proposal_id: 1,
                vote_decision: 1,
                enc_share: crate::WireEncryptedShare {
                    c1: point_bytes(2),
                    c2: point_bytes(3),
                    share_index: 0,
                },
                tree_position: 1,
                all_enc_shares: vec![],
                share_comms: full_share_comms(),
                primary_blind: field_bytes(4),
            },
            None,
            10,
        )
        .unwrap();
        wire.vote_round_id = "AA".repeat(32);

        let err = wire
            .to_json()
            .expect_err("non-canonical vote round ID should fail at serialization");
        assert!(err.to_string().contains("vote_round_id"), "{err}");
    }

    #[test]
    fn bundle_layout_preserves_core_fields() {
        let view = crate::round::BundleLayout {
            bundle_count: 2,
            eligible_weight: 50,
            dropped_count: 0,
            privacy_trim_dropped_bundles: 1,
            privacy_trim_dropped_notes: 4,
            privacy_trim_dropped_value_zatoshi: 900,
        };
        assert_eq!(view.bundle_count, 2);
        assert_eq!(view.eligible_weight, 50);

        let json = serde_json::to_string(&view).unwrap();
        assert_eq!(
            serde_json::from_str::<crate::round::BundleLayout>(&json).unwrap(),
            view
        );
        let json = serde_json::to_value(&view).unwrap();
        assert_eq!(json["privacy_trim_dropped_bundles"], 1);
        assert_eq!(json["privacy_trim_dropped_notes"], 4);
        assert_eq!(json["privacy_trim_dropped_value_zatoshi"], 900);
        assert!(json.get("privacy_trim").is_none());
    }

    #[test]
    fn wire_encrypted_share_serde_roundtrip_preserves_base64_shape() {
        let share = crate::WireEncryptedShare {
            c1: vec![0xAA, 0xBB],
            c2: vec![0xCC, 0xDD],
            share_index: 7,
        };
        let json = serde_json::to_value(&share).unwrap();
        assert_eq!(json["c1"], "qrs=");
        assert_eq!(json["c2"], "zN0=");
        let decoded: crate::WireEncryptedShare = serde_json::from_value(json).unwrap();
        assert_eq!(decoded, share);
    }

    #[test]
    fn van_witness_serde_roundtrip_preserves_auth_path() {
        let witness = crate::vote::VanWitness {
            auth_path: vec![vec![1; 32], vec![2; 32]],
            position: 9,
            anchor_height: 101,
        };
        let json = serde_json::to_value(&witness).unwrap();
        assert_eq!(json["auth_path"][0].as_array().unwrap().len(), 32);
        let decoded: crate::vote::VanWitness = serde_json::from_value(json).unwrap();
        assert_eq!(decoded.position, 9);
        assert_eq!(decoded.anchor_height, 101);
        assert_eq!(decoded.auth_path[0], vec![1; 32]);
    }

    #[test]
    fn share_submission_plan_serde_roundtrip_preserves_fields() {
        let plan = crate::share_policy::ShareSubmissionPlan {
            immediate: true,
            submit_at: 123,
            target_count: 2,
            target_servers: vec![
                "https://helper-1.example".to_string(),
                "https://helper-2.example".to_string(),
            ],
        };
        let mut json = serde_json::to_value(&plan).unwrap();
        assert!(json["immediate"].as_bool().unwrap());
        assert_eq!(json["target_count"].as_u64().unwrap(), 2);
        assert_eq!(json["target_servers"].as_array().unwrap().len(), 2);
        let decoded: crate::share_policy::ShareSubmissionPlan =
            serde_json::from_value(json.clone()).unwrap();
        assert_eq!(decoded, plan);

        json.as_object_mut().unwrap().remove("immediate");
        let legacy: crate::share_policy::ShareSubmissionPlan =
            serde_json::from_value(json).unwrap();
        assert!(!legacy.immediate);
    }

    #[test]
    fn signed_delegation_payload_view_preserves_core_fields() {
        let view = SignedDelegationPayloadView::try_from(SignedDelegationBundle {
            submission: DelegationSubmission {
                proof: vec![4],
                rk: [5; 32],
                nf_signed: [8; 32],
                cmx_new: [9; 32],
                gov_comm: [10; 32],
                gov_nullifiers: [[11; 32]; 5],
                alpha: [12; 32],
                vote_round_id: "00010203".to_string(),
                spend_auth_sig: [6; 64],
                sighash: [7; 32],
                tx1_effects: crate::tx1::placeholder_tx1_effects(),
            },
            pczt_bytes: vec![1, 2, 3],
            eligible_weight_zatoshi: 20,
            delegated_weight_zatoshi: 10,
            bundle_count: 2,
            bundle_index: 1,
        })
        .unwrap();
        assert_eq!(view.pczt_bytes, vec![1, 2, 3]);
        assert_eq!(view.status, "ready_for_submission");
        assert_eq!(view.message, None);
        assert_eq!(
            view.submission.proof,
            base64::engine::general_purpose::STANDARD.encode(vec![4])
        );
        assert_eq!(
            view.submission.vote_round_id,
            base64::engine::general_purpose::STANDARD.encode([0, 1, 2, 3])
        );
        assert_eq!(view.eligible_weight_zatoshi, 20);
        assert_eq!(view.delegated_weight_zatoshi, 10);
        assert_eq!(view.bundle_count, 2);
        assert_eq!(view.bundle_index, 1);
        assert!(serde_json::to_value(&view)
            .unwrap()
            .get("privacy_trim")
            .is_none());
    }

    #[test]
    fn keystone_signing_request_preserves_display_memo() {
        let view = crate::delegate::KeystoneSigningRequest {
            pczt_bytes: vec![1],
            redacted_pczt_bytes: vec![2],
            pczt_sighash: vec![3; 32],
            rk: vec![4; 32],
            action_index: 5,
            display_memo: "I am authorizing this hotkey.".to_string(),
            eligible_weight_zatoshi: 20,
            delegated_weight_zatoshi: 10,
            bundle_count: 2,
            bundle_index: 1,
        };
        assert_eq!(view.display_memo, "I am authorizing this hotkey.");
        assert_eq!(view.bundle_count, 2);
        assert_eq!(view.bundle_index, 1);
    }

    #[test]
    fn van_witness_preserves_core_fields() {
        let mut witness = vec![vec![0u8; 32]; crate::vote::VAN_AUTH_PATH_LEN];
        witness[0] = vec![1; 32];
        witness[1] = vec![2; 32];
        let view = crate::vote::VanWitness {
            auth_path: witness,
            position: 7,
            anchor_height: 123,
        };
        assert_eq!(view.auth_path[0], vec![1; 32]);
        assert_eq!(view.auth_path[1], vec![2; 32]);
        assert_eq!(view.position, 7);
        assert_eq!(view.anchor_height, 123);
    }

    #[test]
    fn draft_vote_wire_type_has_expected_fields() {
        let draft = crate::wire::DraftVote {
            proposal_id: 9,
            choice: 2,
            num_options: 4,
            vc_tree_position: 123,
            single_share: true,
        };
        assert_eq!(draft.proposal_id, 9);
        assert_eq!(draft.choice, 2);
        assert_eq!(draft.num_options, 4);
        assert_eq!(draft.vc_tree_position, 123);
        assert!(draft.single_share);
    }

    fn signed_vote_commitment_fixture() -> crate::vote::SignedVoteCommitment {
        crate::vote::SignedVoteCommitment {
            proposal_id: 2,
            choice: 1,
            vote_round_id: "00".repeat(32),
            van_nullifier: [1; 32],
            vote_authority_note_new: [2; 32],
            vote_commitment: [3; 32],
            proof: vec![4; 10],
            encrypted_shares: vec![crate::WireEncryptedShare {
                c1: point_bytes(5),
                c2: point_bytes(6),
                share_index: 0,
            }],
            share_payloads: vec![crate::SharePayload {
                vote_round_id: "00".repeat(32),
                shares_hash: field_bytes(7),
                proposal_id: 2,
                vote_decision: 1,
                enc_share: crate::WireEncryptedShare {
                    c1: point_bytes(5),
                    c2: point_bytes(6),
                    share_index: 0,
                },
                tree_position: 9,
                all_enc_shares: vec![],
                share_comms: full_share_comms(),
                primary_blind: field_bytes(9),
            }],
            anchor_height: 100,
            shares_hash: pallas::Base::from(7).to_repr(),
            share_comms: full_share_comm_arrays(),
            r_vpk: [10; 32],
            vote_auth_sig: [9; 64],
            commitment_bundle_json: "{\"proposal_id\":2}".to_string(),
        }
    }

    #[test]
    fn vote_commitment_batch_wire_enforces_protocol_action_bounds() {
        let vote = VoteCommitmentWire::try_from(&signed_vote_commitment_fixture()).unwrap();

        let empty_error = VoteCommitmentBatchWire { votes: vec![] }
            .to_json()
            .unwrap_err();
        assert!(empty_error.to_string().contains("between 1 and 15 actions"));

        let maximum = VoteCommitmentBatchWire {
            votes: vec![vote.clone(); crate::vote::MAX_VOTE_BATCH_ACTIONS],
        }
        .to_json()
        .unwrap();
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&maximum).unwrap()["votes"]
                .as_array()
                .unwrap()
                .len(),
            crate::vote::MAX_VOTE_BATCH_ACTIONS
        );

        let oversized_error = VoteCommitmentBatchWire {
            votes: vec![vote; crate::vote::MAX_VOTE_BATCH_ACTIONS + 1],
        }
        .to_json()
        .unwrap_err();
        assert!(oversized_error
            .to_string()
            .contains("between 1 and 15 actions"));
    }

    #[test]
    fn signed_vote_commitments_view_preserves_singleton_wire_fields() {
        let view = SignedVoteCommitmentsView::try_from(crate::vote::SignedVoteCommitments {
            bundle_index: 1,
            commitments: vec![signed_vote_commitment_fixture()],
        })
        .unwrap();
        assert_eq!(view.bundle_index, 1);
        assert_eq!(view.commitments[0].proposal_id, 2);
        assert_eq!(view.commitments[0].wire.proposal_id, 2);
        assert_eq!(view.commitments[0].shares[0].vote_round_id, "00".repeat(32));
        assert_eq!(
            view.commitments[0].shares[0].encrypted_share.c1,
            point_bytes(5)
        );
        assert_eq!(
            view.commitments[0].shares[0].primary_blind,
            base64::engine::general_purpose::STANDARD.encode(field_bytes(9))
        );
        assert_eq!(
            view.commitments[0].wire.vote_auth_sig,
            base64::engine::general_purpose::STANDARD.encode(vec![9; 64])
        );
    }

    #[test]
    fn signed_vote_batch_view_preserves_atomic_fields() {
        let view = SignedVoteBatchView::try_from(crate::vote::SignedVoteBatch {
            bundle_index: 1,
            commitments: vec![signed_vote_commitment_fixture()],
            batch_digest: [0xAB; 32],
            batch_json: "{\"votes\":[]}".to_string(),
        })
        .unwrap();
        assert_eq!(view.bundle_index, 1);
        assert_eq!(view.batch_digest, vec![0xAB; 32]);
        assert_eq!(view.batch_json, "{\"votes\":[]}");
        assert_eq!(view.commitments[0].proposal_id, 2);
    }

    #[test]
    fn voting_note_selection_result_view_preserves_core_fields() {
        let divisor = crate::governance::BALLOT_DIVISOR;
        let selected = SelectedNotes {
            notes: vec![
                test_note_ref(divisor / 2, divisor / 2, 3),
                test_note_ref(divisor / 2, divisor / 2, 7),
            ],
            snapshot_height: 100,
            anchor_tree_state: test_tree_state(100),
        };
        let view = VotingNoteSelectionResultView::from_selected_with_policy(
            selected,
            BundlePolicy::default(),
        )
        .unwrap();
        assert_eq!(view.note_count, 2);
        assert_eq!(view.eligible_weight_zatoshi, divisor);
        assert_eq!(view.snapshot_height, 100);
        assert_eq!(view.anchor_height, 100);
        assert_eq!(view.notes[0].commitment_tree_position, 3);
        assert_eq!(view.notes[1].value_zatoshi, divisor / 2);
        assert_eq!(view.notes[1].voting_weight_zatoshi, divisor / 2);

        // Results cached before privacy trimming shipped must still decode.
        let mut legacy_json = serde_json::to_value(&view).unwrap();
        legacy_json.as_object_mut().unwrap().remove("privacy_trim");
        let decoded: VotingNoteSelectionResultView = serde_json::from_value(legacy_json).unwrap();
        assert_eq!(decoded.privacy_trim, Default::default());
    }

    #[test]
    fn voting_note_selection_result_view_uses_persisted_round_policy() {
        let divisor = crate::governance::BALLOT_DIVISOR;
        let note_value = divisor * 3 / 5;
        let selected = SelectedNotes {
            notes: (1..=4)
                .map(|position| test_note_ref(note_value, note_value, position))
                .collect(),
            snapshot_height: 100,
            anchor_tree_state: test_tree_state(100),
        };
        let params = target_round_params(42);
        let voting_db = crate::round::VotingDb::open_in_memory().unwrap();
        voting_db.set_wallet_id("selection-view-policy");
        voting_db
            .ensure_round(Network::Regtest, &params, None)
            .unwrap();

        // The original caller groups two 0.6-ballot notes per bundle, producing
        // two eligible bundles. A later caller policy puts each note in its own
        // sub-ballot bundle and would report zero weight if used for the view.
        let persisted_policy = BundlePolicy::new(2).unwrap().with_max_privacy_bundles(None);
        let requested_policy = BundlePolicy::new(1).unwrap().with_max_privacy_bundles(None);
        let layout = voting_db
            .ensure_bundles_with_policy(
                &params.vote_round_id,
                &selected.voting_note_infos(),
                persisted_policy,
            )
            .unwrap();
        assert_eq!(layout.eligible_weight, 2 * divisor);

        assert_eq!(
            crate::note_bundling::voting_power_with_policy(&selected, requested_policy),
            0
        );
        assert_eq!(
            crate::voting_power_for_round(&selected, &voting_db, &params.vote_round_id,).unwrap(),
            2 * divisor
        );

        let resumed_round_view = VotingNoteSelectionResultView::from_selected_for_round(
            selected,
            &voting_db,
            &params.vote_round_id,
        )
        .unwrap();
        assert_eq!(resumed_round_view.eligible_weight_zatoshi, 2 * divisor);
    }

    #[test]
    fn round_plan_view_maps_all_supported_next_steps() {
        let plan = session::RoundPlan {
            round_id: "round-1".to_string(),
            pending_recovery: true,
            blocking_recovery: true,
            blocking_share_work: false,
            hotkey_bound: true,
            completed_vote_artifact: true,
            completed_for_display: false,
            completed_vote_display: Some(session::CompletedVoteDisplay {
                choices: vec![session::CompletedVoteChoice {
                    proposal_id: 11,
                    choice: Some(1),
                }],
                voted_at: Some(123),
            }),
            needs_draft_setup: false,
            primary_action: session::RoundPlanAction::Vote,
            next_steps: vec![
                session::NextStep::Delegate { bundle_index: 1 },
                session::NextStep::PollDelegation { bundle_index: 2 },
                session::NextStep::CastVote {
                    bundle_index: 3,
                    proposal_id: 11,
                    choice: 1,
                },
                session::NextStep::SubmitVote {
                    bundle_index: 4,
                    proposal_id: 12,
                },
                session::NextStep::SubmitVoteBatch {
                    bundle_index: 5,
                    proposal_id: 13,
                },
                session::NextStep::PollVote {
                    bundle_index: 6,
                    proposal_id: 14,
                },
                session::NextStep::PollVoteBatch {
                    bundle_index: 7,
                    proposal_id: 15,
                },
                session::NextStep::SubmitShares {
                    bundle_index: 8,
                    proposal_id: 14,
                    share_index: 0,
                },
                session::NextStep::ConfirmShare {
                    bundle_index: 9,
                    proposal_id: 15,
                    share_index: 1,
                },
            ],
            delegation_statuses: vec![session::DelegationStatus {
                bundle_index: 2,
                phase: crate::phases::DelegationPhase::Submitted,
                tx_hash: Some("delegation-tx".to_string()),
            }],
            recovered_delegation_work: vec![session::DelegationRecoveryWork {
                kind: session::DelegationRecoveryWorkKind::PollDelegation,
                bundle_index: 2,
                phase: crate::phases::DelegationPhase::Submitted,
                tx_hash: Some("delegation-tx".to_string()),
            }],
            recovered_vote_work: vec![
                session::VoteRecoveryWork {
                    kind: session::VoteRecoveryWorkKind::SubmitVoteBatch,
                    bundle_index: 4,
                    proposal_id: 12,
                    tx_hash: None,
                    vc_tree_position: None,
                    share_indexes: Vec::new(),
                },
                session::VoteRecoveryWork {
                    kind: session::VoteRecoveryWorkKind::PollVoteBatch,
                    bundle_index: 5,
                    proposal_id: 13,
                    tx_hash: Some("batch-tx".to_string()),
                    vc_tree_position: None,
                    share_indexes: Vec::new(),
                },
                session::VoteRecoveryWork {
                    kind: session::VoteRecoveryWorkKind::SubmitShares,
                    bundle_index: 6,
                    proposal_id: 14,
                    tx_hash: None,
                    vc_tree_position: Some(99),
                    share_indexes: vec![0, 1],
                },
            ],
            open_proposals: vec![11, 12],
            immediate_share_key: Some(crate::share_policy::ImmediateShareKey {
                bundle_index: 7,
                proposal_id: 11,
                share_index: 0,
            }),
            all_decided: false,
        };

        let view = RoundPlanView::try_from(plan).unwrap();
        assert_eq!(view.round_id, "round-1");
        assert!(view.pending_recovery);
        assert!(view.blocking_recovery);
        assert!(!view.blocking_share_work);
        assert!(view.hotkey_bound);
        assert!(view.completed_vote_artifact);
        assert!(!view.completed_for_display);
        assert_eq!(
            view.completed_vote_display
                .as_ref()
                .unwrap()
                .choices
                .first()
                .unwrap()
                .choice,
            Some(1)
        );
        assert_eq!(
            view.completed_vote_display.as_ref().unwrap().voted_at,
            Some(123)
        );
        assert!(!view.needs_draft_setup);
        assert_eq!(view.primary_action, "vote");
        assert_eq!(view.open_proposals, vec![11, 12]);
        assert_eq!(
            view.immediate_share_key,
            Some(crate::share_policy::ImmediateShareKey {
                bundle_index: 7,
                proposal_id: 11,
                share_index: 0,
            })
        );
        assert!(!view.all_decided);

        let kinds = view
            .next_steps
            .iter()
            .map(|step| step.kind.as_str())
            .collect::<Vec<_>>();
        assert_eq!(
            kinds,
            vec![
                "delegate",
                "poll_delegation",
                "cast_vote",
                "submit_vote",
                "submit_vote_batch",
                "poll_vote",
                "poll_vote_batch",
                "submit_shares",
                "confirm_share"
            ]
        );
        assert_eq!(view.next_steps[0].bundle_index, 1);
        assert_eq!(view.next_steps[2].proposal_id, 11);
        assert_eq!(view.next_steps[2].choice, 1);
        assert_eq!(view.next_steps[8].share_index, 1);
        assert_eq!(view.delegation_statuses[0].phase, "submitted_delegation");
        assert_eq!(view.recovered_delegation_work[0].kind, "poll_delegation");
        assert_eq!(view.recovered_vote_work[0].kind, "submit_vote_batch");
        assert_eq!(view.recovered_vote_work[1].kind, "poll_vote_batch");
        assert_eq!(
            view.recovered_vote_work[1].tx_hash.as_deref(),
            Some("batch-tx")
        );
        assert_eq!(view.recovered_vote_work[2].kind, "submit_shares");
        assert_eq!(view.recovered_vote_work[2].vc_tree_position, Some(99));
        assert_eq!(view.recovered_vote_work[2].share_indexes, vec![0, 1]);
    }
}
