//! Stable wire-format DTOs for vote-chain and helper endpoints.
//!
//! This module is intentionally **struct-only** and is the canonical owner of
//! protocol field names so wallet integrations do not duplicate payload-shaping
//! logic.
//!
//! FRB scans `zcash_voting::wire` directly from `vizor-wallet` to generate
//! Dart bindings. Keeping only plain DTO structs in this module prevents FRB
//! from traversing behavior-level APIs that depend on internal crate types.
//!
//! All conversions, validation, and serialization helpers live in
//! `crate::wire_codec`, while `wire.rs` remains the stable cross-language
//! schema surface.

use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use serde::{Deserialize, Serialize};

pub mod serde_base64_bytes {
    use super::*;

    pub fn serialize<S>(value: &[u8], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&BASE64_STANDARD.encode(value))
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Vec<u8>, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let encoded = String::deserialize(deserializer)?;
        BASE64_STANDARD
            .decode(encoded.as_bytes())
            .map_err(serde::de::Error::custom)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct BoundedU32(pub u32);

impl TryFrom<usize> for BoundedU32 {
    type Error = std::num::TryFromIntError;

    fn try_from(value: usize) -> Result<Self, Self::Error> {
        Ok(Self(u32::try_from(value)?))
    }
}

impl TryFrom<u64> for BoundedU32 {
    type Error = std::num::TryFromIntError;

    fn try_from(value: u64) -> Result<Self, Self::Error> {
        Ok(Self(u32::try_from(value)?))
    }
}

pub use crate::config::{
    ConfigCondition, ConfigConditionKind, ConfigSwitchDecision, ConfigSwitchKind,
    PinnedConfigSource, ResolveVotingConfigOptions, ResolvedVotingConfig,
    ResolvedVotingConfigSummary, ServiceEndpoint, SupportedVersions, VotingConfigError,
    WalletCapabilities,
};
pub use crate::delegate::KeystoneSigningRequest;
pub use crate::round::BundleLayout;
pub use crate::share_policy::ShareSubmissionPlan;
pub use crate::types::WireEncryptedShare;
pub use crate::vote::VanWitness;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DelegationSubmissionWire {
    pub rk: String,
    pub spend_auth_sig: String,
    pub sighash: String,
    #[serde(rename = "signed_note_nullifier")]
    pub nf_signed: String,
    pub cmx_new: String,
    #[serde(rename = "van_cmx")]
    pub gov_comm: String,
    pub gov_nullifiers: Vec<String>,
    pub proof: String,
    pub vote_round_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteCommitmentWire {
    pub van_nullifier: String,
    pub vote_authority_note_new: String,
    pub vote_commitment: String,
    pub proposal_id: u32,
    pub proof: String,
    pub vote_round_id: String,
    #[serde(rename = "vote_comm_tree_anchor_height")]
    pub anchor_height: u32,
    pub r_vpk: String,
    pub vote_auth_sig: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteShareWire {
    pub shares_hash: String,
    pub proposal_id: u32,
    pub vote_decision: u32,
    #[serde(rename = "enc_share")]
    pub encrypted_share: WireEncryptedShare,
    pub share_index: u32,
    #[serde(rename = "tree_position")]
    pub vc_tree_position: u64,
    #[serde(rename = "all_enc_shares")]
    pub all_encrypted_shares: Vec<WireEncryptedShare>,
    pub share_comms: Vec<String>,
    pub primary_blind: String,
    pub submit_at: u64,
}

/// Parsed confirmation data for a submitted delegation transaction.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DelegationConfirmation {
    /// Confirmed transaction hash.
    pub tx_hash: String,
    /// Confirmed vote-authority-note leaf position.
    pub van_leaf_position: u32,
}

/// Parsed confirmation data for a submitted cast-vote transaction.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteConfirmation {
    /// Confirmed transaction hash.
    pub tx_hash: String,
    /// Confirmed vote-authority-note leaf position.
    pub van_leaf_position: u32,
    /// Confirmed vote commitment tree position.
    pub vc_tree_position: u64,
}

/// Parameters for a voting round, sourced from vote chain.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VotingRoundParams {
    pub vote_round_id: String,
    pub snapshot_height: u64,
    pub ea_pk: Vec<u8>,
    pub nc_root: Vec<u8>,
    pub nullifier_imt_root: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VotingNoteRefView {
    pub pool: String,
    pub txid_hex: String,
    pub output_index: u32,
    pub value_zatoshi: u64,
    pub voting_weight_zatoshi: u64,
    pub commitment_tree_position: u64,
    pub mined_height: u64,
    pub anchor_height: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VotingNoteSelectionResultView {
    pub note_count: u32,
    pub eligible_weight_zatoshi: u64,
    pub snapshot_height: u64,
    pub anchor_height: u64,
    pub notes: Vec<VotingNoteRefView>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DelegationPirPrecomputeResultView {
    pub cached_count: u32,
    pub fetched_count: u32,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignedDelegationPayloadView {
    pub pczt_bytes: Vec<u8>,
    pub status: String,
    pub message: Option<String>,
    pub submission: DelegationSubmissionWire,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeystoneSignatureRecord {
    pub bundle_index: u32,
    pub sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub rk: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DraftVote {
    pub proposal_id: u32,
    pub choice: u32,
    pub num_options: u32,
    pub vc_tree_position: u64,
    pub single_share: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignedVoteCommitmentView {
    pub proposal_id: u32,
    pub wire: VoteCommitmentWire,
    pub shares: Vec<VoteShareWire>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignedVoteCommitmentsView {
    pub bundle_index: u32,
    pub commitments: Vec<SignedVoteCommitmentView>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteRecord {
    pub proposal_id: u32,
    pub bundle_index: u32,
    pub choice: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DelegationRecoveryView {
    pub bundle_index: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub van_leaf_position: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteRecoveryView {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub choice: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub vc_tree_position: Option<u64>,
    pub has_commitment_bundle: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecoverableCommitmentBundle {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub commitment_bundle_json: String,
    pub vc_tree_position: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareDelegationRecordView {
    pub round_id: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub sent_to_urls: Vec<String>,
    pub nullifier: Vec<u8>,
    pub phase: String,
    pub confirmed: bool,
    pub submit_at: u64,
    pub created_at: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShareWorkflowRecoveryView {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub phase: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NextStepView {
    pub kind: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub choice: u32,
    pub share_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundRecoveryStateView {
    pub round_id: String,
    pub bundle_count: u32,
    pub delegation: Vec<DelegationRecoveryView>,
    pub votes: Vec<VoteRecoveryView>,
    pub commitment_bundles: Vec<RecoverableCommitmentBundle>,
    pub shares: Vec<ShareWorkflowRecoveryView>,
    pub share_delegations: Vec<ShareDelegationRecordView>,
    pub unconfirmed_share_delegations: Vec<ShareDelegationRecordView>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DelegationStatusView {
    pub bundle_index: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DelegationRecoveryWorkView {
    pub kind: String,
    pub bundle_index: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VoteRecoveryWorkView {
    pub kind: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub tx_hash: Option<String>,
    pub vc_tree_position: Option<u64>,
    pub share_indexes: Vec<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompletedVoteChoiceView {
    pub proposal_id: u32,
    pub choice: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompletedVoteDisplayView {
    pub choices: Vec<CompletedVoteChoiceView>,
    pub voted_at: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundPlanView {
    pub round_id: String,
    pub pending_recovery: bool,
    pub blocking_recovery: bool,
    pub blocking_share_work: bool,
    pub hotkey_bound: bool,
    pub completed_vote_artifact: bool,
    pub completed_for_display: bool,
    pub completed_vote_display: Option<CompletedVoteDisplayView>,
    pub needs_draft_setup: bool,
    pub primary_action: String,
    pub next_steps: Vec<NextStepView>,
    pub delegation_statuses: Vec<DelegationStatusView>,
    pub recovered_delegation_work: Vec<DelegationRecoveryWorkView>,
    pub recovered_vote_work: Vec<VoteRecoveryWorkView>,
    pub open_proposals: Vec<u32>,
    pub all_decided: bool,
}
