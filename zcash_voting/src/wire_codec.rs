//! Behavioral helpers for `crate::wire` DTOs.
//!
//! This module owns conversion/serialization logic (`TryFrom`, `From`,
//! `to_json`, and payload shaping) that depends on internal crate types such as
//! `VotingError`, recovery records, and share payload models.
//!
//! It is kept separate from `wire.rs` so the FRB-scanned `wire` module can stay
//! struct-only and expose a clean, stable cross-language schema.

use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};

use crate::{
    delegate::{DelegationSubmission, PreparedDelegationReport, SignedDelegationBundle},
    phases::WorkflowPhase,
    recovery, session,
    types::{NoteRef, SelectedNotes, SharePayload, VotingError},
    vote::{SignedVoteCommitment, SignedVoteCommitments},
    wire::{
        CompletedVoteChoiceView, CompletedVoteDisplayView, DelegationPirPrecomputeResultView,
        DelegationRecoveryView, DelegationRecoveryWorkView, DelegationStatusView,
        DelegationSubmissionWire, NextStepView, RoundPlanView, RoundRecoveryStateView,
        ShareDelegationRecordView, ShareWorkflowRecoveryView, SignedDelegationPayloadView,
        SignedVoteCommitmentView, SignedVoteCommitmentsView, VoteCommitmentWire, VoteRecoveryView,
        VoteRecoveryWorkView, VoteShareWire, VotingNoteRefView, VotingNoteSelectionResultView,
    },
    BundlePolicy,
};

const MAX_SAFE_JSON_INTEGER: u64 = 0x1f_ffff_ffff_ffff;

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

impl VoteShareWire {
    pub fn from_payload(
        payload: &SharePayload,
        vc_tree_position: Option<u64>,
        submit_at: u64,
    ) -> Result<Self, VotingError> {
        Ok(Self {
            shares_hash: b64(&payload.shares_hash),
            proposal_id: payload.proposal_id,
            vote_decision: payload.vote_decision,
            encrypted_share: payload.enc_share.clone(),
            share_index: payload.enc_share.share_index,
            vc_tree_position: json_safe_u64(
                vc_tree_position.unwrap_or(payload.tree_position),
                "tree_position",
            )?,
            all_encrypted_shares: payload.all_enc_shares.clone(),
            share_comms: payload.share_comms.iter().map(b64).collect(),
            primary_blind: b64(&payload.primary_blind),
            submit_at: json_safe_u64(submit_at, "submit_at")?,
        })
    }

    pub fn to_json(&self) -> Result<String, VotingError> {
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
            self.vc_tree_position = json_safe_u64(position, "tree_position")?;
        }
        self.submit_at = json_safe_u64(submit_at, "submit_at")?;
        Ok(self)
    }
}

impl TryFrom<&DelegationSubmission> for DelegationSubmissionWire {
    type Error = VotingError;

    fn try_from(submission: &DelegationSubmission) -> Result<Self, Self::Error> {
        Ok(Self {
            rk: b64(submission.rk),
            spend_auth_sig: b64(submission.spend_auth_sig),
            sighash: b64(submission.sighash),
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
    pub fn from_selected(
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
        let eligible_weight_zatoshi = crate::voting_power_with_policy(&selected, bundle_policy);
        let snapshot_height = selected.snapshot_height;
        let anchor_height = selected.anchor_tree_state.height;
        let notes = selected.notes.into_iter().map(Into::into).collect();
        Ok(Self {
            note_count,
            eligible_weight_zatoshi,
            snapshot_height,
            anchor_height,
            notes,
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
            | session::NextStep::PollVote {
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vote::SignedVoteCommitment;
    use zcash_client_backend::proto::service::TreeState;

    fn decode_b64(value: &str) -> Vec<u8> {
        BASE64_STANDARD.decode(value).unwrap()
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
        };

        let json = submission.to_wire_json().unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert!(value.get("signed_note_nullifier").is_some());
        assert!(value.get("van_cmx").is_some());
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
    fn vote_share_wire_json_shape() {
        let payload = SharePayload {
            shares_hash: vec![0x21; 32],
            proposal_id: 9,
            vote_decision: 2,
            enc_share: crate::WireEncryptedShare {
                c1: vec![0x22; 32],
                c2: vec![0x23; 32],
                share_index: 1,
            },
            tree_position: 99,
            all_enc_shares: vec![crate::WireEncryptedShare {
                c1: vec![0x24; 32],
                c2: vec![0x25; 32],
                share_index: 1,
            }],
            share_comms: vec![vec![0x26; 32]],
            primary_blind: vec![0x27; 32],
        };

        let json = payload.to_wire_json(None, 123).unwrap();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value.get("tree_position").unwrap().as_u64().unwrap(), 99);
        assert_eq!(value.get("submit_at").unwrap().as_u64().unwrap(), 123);
        assert!(value.get("enc_share").is_some());
        assert!(value.get("all_enc_shares").is_some());
    }

    #[test]
    fn vote_share_wire_json_rejects_large_json_integer() {
        let payload = SharePayload {
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
            .contains("field tree_position is too large to encode as JSON integer"));
    }

    #[test]
    fn bundle_layout_preserves_core_fields() {
        let view = crate::round::BundleLayout {
            bundle_count: 2,
            eligible_weight: 50,
            dropped_count: 0,
        };
        assert_eq!(view.bundle_count, 2);
        assert_eq!(view.eligible_weight, 50);
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
            submit_at: 123,
            target_count: 2,
            target_servers: vec![
                "https://helper-1.example".to_string(),
                "https://helper-2.example".to_string(),
            ],
        };
        let json = serde_json::to_value(&plan).unwrap();
        assert_eq!(json["target_count"].as_u64().unwrap(), 2);
        assert_eq!(json["target_servers"].as_array().unwrap().len(), 2);
        let decoded: crate::share_policy::ShareSubmissionPlan =
            serde_json::from_value(json).unwrap();
        assert_eq!(decoded, plan);
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

    #[test]
    fn signed_vote_commitments_view_preserves_public_wire_fields() {
        let view = SignedVoteCommitmentsView::try_from(crate::vote::SignedVoteCommitments {
            bundle_index: 1,
            commitments: vec![crate::vote::SignedVoteCommitment {
                proposal_id: 2,
                choice: 1,
                vote_round_id: "00".repeat(32),
                van_nullifier: [1; 32],
                vote_authority_note_new: [2; 32],
                vote_commitment: [3; 32],
                proof: vec![4; 10],
                encrypted_shares: vec![crate::WireEncryptedShare {
                    c1: vec![5; 32],
                    c2: vec![6; 32],
                    share_index: 0,
                }],
                share_payloads: vec![crate::SharePayload {
                    shares_hash: vec![7; 32],
                    proposal_id: 2,
                    vote_decision: 1,
                    enc_share: crate::WireEncryptedShare {
                        c1: vec![5; 32],
                        c2: vec![6; 32],
                        share_index: 0,
                    },
                    tree_position: 9,
                    all_enc_shares: vec![],
                    share_comms: vec![vec![8; 32]],
                    primary_blind: vec![9; 32],
                }],
                anchor_height: 100,
                shares_hash: [7; 32],
                share_comms: vec![[8; 32]],
                r_vpk: [10; 32],
                vote_auth_sig: [9; 64],
                commitment_bundle_json: "{\"proposal_id\":2}".to_string(),
            }],
        })
        .unwrap();
        assert_eq!(view.bundle_index, 1);
        assert_eq!(view.commitments[0].proposal_id, 2);
        assert_eq!(view.commitments[0].wire.proposal_id, 2);
        assert_eq!(
            view.commitments[0].shares[0].encrypted_share.c1,
            vec![5; 32]
        );
        assert_eq!(
            view.commitments[0].shares[0].primary_blind,
            base64::engine::general_purpose::STANDARD.encode(vec![9; 32])
        );
        assert_eq!(
            view.commitments[0].wire.vote_auth_sig,
            base64::engine::general_purpose::STANDARD.encode(vec![9; 64])
        );
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
        let view = VotingNoteSelectionResultView::from_selected(selected, BundlePolicy::default())
            .unwrap();
        assert_eq!(view.note_count, 2);
        assert_eq!(view.eligible_weight_zatoshi, divisor);
        assert_eq!(view.snapshot_height, 100);
        assert_eq!(view.anchor_height, 100);
        assert_eq!(view.notes[0].commitment_tree_position, 3);
        assert_eq!(view.notes[1].value_zatoshi, divisor / 2);
        assert_eq!(view.notes[1].voting_weight_zatoshi, divisor / 2);
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
                session::NextStep::PollVote {
                    bundle_index: 5,
                    proposal_id: 13,
                },
                session::NextStep::SubmitShares {
                    bundle_index: 6,
                    proposal_id: 14,
                    share_index: 0,
                },
                session::NextStep::ConfirmShare {
                    bundle_index: 7,
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
            recovered_vote_work: vec![session::VoteRecoveryWork {
                kind: session::VoteRecoveryWorkKind::SubmitShares,
                bundle_index: 6,
                proposal_id: 14,
                tx_hash: None,
                vc_tree_position: Some(99),
                share_indexes: vec![0, 1],
            }],
            open_proposals: vec![11, 12],
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
                "poll_vote",
                "submit_shares",
                "confirm_share"
            ]
        );
        assert_eq!(view.next_steps[0].bundle_index, 1);
        assert_eq!(view.next_steps[2].proposal_id, 11);
        assert_eq!(view.next_steps[2].choice, 1);
        assert_eq!(view.next_steps[6].share_index, 1);
        assert_eq!(view.delegation_statuses[0].phase, "submitted_delegation");
        assert_eq!(view.recovered_delegation_work[0].kind, "poll_delegation");
        assert_eq!(view.recovered_vote_work[0].kind, "submit_shares");
        assert_eq!(view.recovered_vote_work[0].vc_tree_position, Some(99));
        assert_eq!(view.recovered_vote_work[0].share_indexes, vec![0, 1]);
    }
}
