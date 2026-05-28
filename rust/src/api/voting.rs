use std::{panic, sync::Arc};

use crate::frb_generated::StreamSink;
use crate::wallet::{
    keys,
    voting::{
        bundle::{self, SelectedNotes},
        delegation,
        delegation::{
            BundleSetupResult, DelegationPirPrecomputeResult, KeystoneDelegationRequest,
            KeystoneSignatureRecord, ProofEvent, SignedDelegationPayload,
        },
        hotkey,
        progress::{cancel_voting_work, VotingWorkCancellation},
        recovery, state, tree_sync,
        tree_sync::VanWitness,
        vote,
    },
};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use rand::{rngs::OsRng, RngCore};
use secrecy::ExposeSecret;

#[derive(Clone, Debug, PartialEq, Eq)]
/// FRB-safe voting round parameters loaded from the coordinator/session.
pub struct ApiVotingRoundParams {
    pub vote_round_id: String,
    pub snapshot_height: u64,
    pub ea_pk: Vec<u8>,
    pub nc_root: Vec<u8>,
    pub nullifier_imt_root: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// FRB-safe reference to one Orchard note selected at the snapshot height.
pub struct ApiVotingNoteRef {
    pub pool: String,
    pub txid_hex: String,
    pub output_index: u32,
    pub value_zatoshi: u64,
    /// Legacy per-note display field. Voting weight is computed from smart
    /// bundles, so this carries the raw note value.
    pub voting_weight_zatoshi: u64,
    pub commitment_tree_position: u64,
    pub mined_height: u64,
    pub anchor_height: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Result of selecting voting notes for a snapshot height.
pub struct ApiVotingNoteSelectionResult {
    pub note_count: u32,
    pub eligible_weight_zatoshi: u64,
    pub snapshot_height: u64,
    pub anchor_height: u64,
    pub notes: Vec<ApiVotingNoteRef>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Summary of bundle setup keyed by `(round_id, wallet_id)`.
pub struct ApiVotingBundleSetupResult {
    pub bundle_count: u32,
    pub eligible_weight_zatoshi: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Summary of delegation PIR proof precomputation for one bundle.
pub struct ApiDelegationPirPrecomputeResult {
    pub cached_count: u32,
    pub fetched_count: u32,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Signed delegation payload ready for Dart-side submission.
pub struct ApiSignedDelegationPayload {
    pub pczt_bytes: Vec<u8>,
    pub status: String,
    pub message: Option<String>,
    pub proof: Vec<u8>,
    pub rk: Vec<u8>,
    pub spend_auth_sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub nf_signed: Vec<u8>,
    pub cmx_new: Vec<u8>,
    pub gov_comm: Vec<u8>,
    pub gov_nullifiers: Vec<Vec<u8>>,
    pub vote_round_id: String,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Voting PCZT request that should be signed by Keystone.
pub struct ApiKeystoneDelegationRequest {
    pub pczt_bytes: Vec<u8>,
    pub redacted_pczt_bytes: Vec<u8>,
    pub pczt_sighash: Vec<u8>,
    pub rk: Vec<u8>,
    pub action_index: u32,
    pub display_memo: String,
    pub eligible_weight_zatoshi: u64,
    pub delegated_weight_zatoshi: u64,
    pub bundle_count: u32,
    pub bundle_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Persisted Keystone signature for one delegation bundle.
pub struct ApiKeystoneSignatureRecord {
    pub bundle_index: u32,
    pub sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub rk: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq)]
/// Progress event emitted while building, proving, and signing a delegation payload.
///
/// A terminal `"result"` event carries `signed_delegation_payload`; earlier
/// phase events only describe local preparation progress.
pub struct ApiDelegationProofEvent {
    pub phase: String,
    pub proof_progress: Option<f64>,
    pub signed_delegation_payload: Option<ApiSignedDelegationPayload>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiVanWitness {
    /// 24 sibling hashes from the VAN leaf to the vote-tree root.
    pub auth_path: Vec<Vec<u8>>,
    /// VAN leaf position in the vote commitment tree.
    pub position: u32,
    /// Vote-tree height at which this witness is valid.
    pub anchor_height: u32,
}

#[derive(Clone, Debug, PartialEq)]
/// Progress event emitted while building ZKP2 vote commitments.
///
/// A terminal `"result"` event carries the completed commitment set; earlier
/// phase events include the active `(proposal_id, bundle_index)` pair.
pub struct ApiVoteCommitEvent {
    pub phase: String,
    pub proposal_id: Option<u32>,
    pub bundle_index: Option<u32>,
    pub proof_progress: Option<f64>,
    pub commitments: Option<ApiSignedVoteCommitments>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// One requested vote for a proposal in a bundle.
///
/// `choice` is zero-indexed and must be less than `num_options`. `single_share`
/// enables the last-moment vote mode where only share 0 is submitted.
pub struct ApiDraftVote {
    pub proposal_id: u32,
    pub choice: u32,
    pub num_options: u32,
    pub vc_tree_position: u64,
    pub single_share: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Public encrypted share fields safe to pass through Dart/REST.
///
/// Plaintext values and encryption randomness intentionally never cross this API.
pub struct ApiWireEncryptedShare {
    pub ciphertext1: Vec<u8>,
    pub ciphertext2: Vec<u8>,
    pub share_index: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Helper-server payload for one encrypted vote share.
///
/// Contains only public inputs and the selected public encrypted share. The
/// `primary_blind` is included for share tracking/nullifier recovery.
pub struct ApiVoteSharePayload {
    pub shares_hash: Vec<u8>,
    pub proposal_id: u32,
    pub vote_decision: u32,
    pub encrypted_share: ApiWireEncryptedShare,
    pub tree_position: u64,
    pub all_encrypted_shares: Vec<ApiWireEncryptedShare>,
    pub share_comms: Vec<Vec<u8>>,
    pub primary_blind: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Signed ZKP2 vote commitment and wire-safe share data for one proposal.
pub struct ApiSignedVoteCommitment {
    pub proposal_id: u32,
    pub choice: u32,
    pub vote_round_id: String,
    pub van_nullifier: Vec<u8>,
    pub vote_authority_note_new: Vec<u8>,
    pub vote_commitment: Vec<u8>,
    pub proof: Vec<u8>,
    pub encrypted_shares: Vec<ApiWireEncryptedShare>,
    pub share_payloads: Vec<ApiVoteSharePayload>,
    pub anchor_height: u32,
    pub shares_hash: Vec<u8>,
    pub share_comms: Vec<Vec<u8>>,
    pub r_vpk_bytes: Vec<u8>,
    pub vote_auth_sig: Vec<u8>,
    pub commitment_bundle_json: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Set of signed vote commitments produced for one bundle index.
pub struct ApiSignedVoteCommitments {
    pub bundle_index: u32,
    pub commitments: Vec<ApiSignedVoteCommitment>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// FRB-safe helper-share submission plan from `zcash_voting::share_policy`.
pub struct ApiShareSubmissionPlan {
    /// Unix seconds when helpers should submit this share, or 0 for immediate.
    pub submit_at: u64,
    /// Number of helpers this share should reach before local delivery succeeds.
    pub target_count: u32,
    /// Initial helper targets selected by the shared Rust policy.
    pub target_servers: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Stored vote row keyed by `(round_id, wallet_id, bundle_index, proposal_id)`.
pub struct ApiVoteRecord {
    pub proposal_id: u32,
    pub bundle_index: u32,
    pub choice: u32,
    pub submitted: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Stored commitment bundle recovery data for one `(bundle_index, proposal_id)`.
pub struct ApiCommitmentBundleRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub commitment_bundle_json: String,
    pub vc_tree_position: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Stored delegation transaction hash for one bundle.
pub struct ApiDelegationTxRecovery {
    pub bundle_index: u32,
    pub tx_hash: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Stored vote transaction hash for one `(bundle_index, proposal_id)`.
pub struct ApiVoteTxRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub tx_hash: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Helper-server share delegation state used for retry/resume.
pub struct ApiShareDelegationRecord {
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

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegationWorkflowRecovery {
    pub bundle_index: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub van_leaf_position: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiVoteWorkflowRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub vc_tree_position: Option<u64>,
    pub has_commitment_bundle: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiShareWorkflowRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub phase: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Recovery summary for resuming one voting round after app restart.
pub struct ApiRoundRecoveryState {
    pub round_id: String,
    pub bundle_count: u32,
    pub delegation_workflows: Vec<ApiDelegationWorkflowRecovery>,
    pub delegation_tx_hashes: Vec<ApiDelegationTxRecovery>,
    pub votes: Vec<ApiVoteRecord>,
    pub vote_workflows: Vec<ApiVoteWorkflowRecovery>,
    pub vote_tx_hashes: Vec<ApiVoteTxRecovery>,
    pub commitment_bundles: Vec<ApiCommitmentBundleRecovery>,
    pub share_workflows: Vec<ApiShareWorkflowRecovery>,
    pub share_delegations: Vec<ApiShareDelegationRecord>,
    pub unconfirmed_share_delegations: Vec<ApiShareDelegationRecord>,
}

/// Returns the vote-chain delegation submission body as validated wire JSON.
///
/// Binary fields are base64-encoded here so Dart does not duplicate protocol
/// field names or byte encoding rules.
pub fn delegation_submission_wire_json(
    submission: ApiSignedDelegationPayload,
) -> Result<String, String> {
    catch(|| delegation_submission_wire_json_inner(&submission))
}

/// Returns the vote-chain cast-vote submission body as validated wire JSON.
pub fn vote_commitment_wire_json(commitment: ApiSignedVoteCommitment) -> Result<String, String> {
    catch(|| vote_commitment_wire_json_inner(&commitment))
}

/// Returns the helper-server encrypted-share submission body as wire JSON.
///
/// `vc_tree_position` overrides the draft payload tree position after the
/// vote-chain cast-vote transaction confirms.
pub fn vote_share_wire_json(
    payload: ApiVoteSharePayload,
    vc_tree_position: Option<u64>,
    submit_at: u64,
) -> Result<String, String> {
    catch(|| vote_share_wire_json_inner(&payload, vc_tree_position, submit_at))
}

/// Plan independent helper-share timing and randomized helper targets.
///
/// This mirrors the zcash-swift-wallet-sdk wrapper around
/// `zcash_voting::share_policy::plan_share_submissions`, with Rust drawing the
/// policy-sized entropy from the OS CSPRNG before returning FRB-safe plans.
pub fn plan_share_submissions(
    share_count: u32,
    server_urls: Vec<String>,
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
    single_share: bool,
) -> Result<Vec<ApiShareSubmissionPlan>, String> {
    catch(|| {
        let share_count = usize::try_from(share_count)
            .map_err(|_| "share_count does not fit in usize".to_string())?;
        let required = zcash_voting::share_policy::share_submission_random_bytes_required(
            share_count,
            server_urls.len(),
            now_seconds,
            vote_end_time_seconds,
            last_moment_buffer_seconds,
            single_share,
        );
        let mut submit_at_random_bytes = vec![0u8; required.submit_at_random_bytes];
        let mut server_random_bytes = vec![0u8; required.server_random_bytes];
        OsRng
            .try_fill_bytes(&mut submit_at_random_bytes)
            .map_err(|e| format!("failed to draw submit_at entropy: {e}"))?;
        OsRng
            .try_fill_bytes(&mut server_random_bytes)
            .map_err(|e| format!("failed to draw share-server entropy: {e}"))?;

        let plans = zcash_voting::share_policy::plan_share_submissions(
            share_count,
            &server_urls,
            now_seconds,
            vote_end_time_seconds,
            last_moment_buffer_seconds,
            single_share,
            &submit_at_random_bytes,
            &server_random_bytes,
        )
        .map_err(|e| e.to_string())?;

        plans
            .into_iter()
            .map(|plan| {
                Ok(ApiShareSubmissionPlan {
                    submit_at: plan.submit_at,
                    target_count: u32::try_from(plan.target_count)
                        .map_err(|_| "share target_count does not fit in u32".to_string())?,
                    target_servers: plan.target_servers,
                })
            })
            .collect()
    })
}

/// Extract and validate one helper-share payload from stored recovery JSON.
///
/// The stored recovery blob is hex-encoded and also contains local-only
/// recovery material. This helper emits only the public base64 wire shape that
/// helper servers accept.
pub fn recovered_vote_share_wire_json(
    commitment_bundle_json: String,
    proposal_id: u32,
    share_index: u32,
    vc_tree_position: u64,
    submit_at: u64,
) -> Result<String, String> {
    catch(|| {
        recovered_vote_share_wire_json_inner(
            &commitment_bundle_json,
            proposal_id,
            share_index,
            vc_tree_position,
            submit_at,
        )
    })
}

/// Derive the opaque per-account, per-round voting hotkey bytes.
///
/// The seed stays platform-owned; Rust only applies the same zcash_voting
/// hotkey derivation used by delegation and returns bytes for secure storage.
/// The returned `Vec<u8>` is an unavoidable FRB copy boundary
pub fn derive_voting_hotkey(
    seed_bytes: Vec<u8>,
    round_id: String,
    account_uuid: String,
) -> Result<Vec<u8>, String> {
    catch(|| {
        let seed = secrecy::SecretVec::new(seed_bytes);
        hotkey::derive_hotkey(&seed, &round_id, &account_uuid).map(|hotkey| {
            // FRB returns owned bytes, so this copy cannot be zeroized by Rust
            // after Dart receives it.
            hotkey.expose_secret().to_vec()
        })
    })
}

/// Generate opaque voting hotkey bytes for a hardware account.
///
/// Hardware accounts cannot expose their wallet seed to derive the deterministic
/// software hotkey, so the app persists this random per-round hotkey in secure
/// storage and reuses it for vote commitment signing.
pub fn generate_voting_hotkey() -> Result<Vec<u8>, String> {
    catch(|| {
        hotkey::generate_random_hotkey().map(|hotkey| {
            // FRB returns owned bytes, so this copy cannot be zeroized by Rust
            // after Dart receives it.
            hotkey.expose_secret().to_vec()
        })
    })
}

impl From<ApiVotingRoundParams> for zcash_voting::VotingRoundParams {
    fn from(params: ApiVotingRoundParams) -> Self {
        Self {
            vote_round_id: params.vote_round_id,
            snapshot_height: params.snapshot_height,
            ea_pk: params.ea_pk,
            nc_root: params.nc_root,
            nullifier_imt_root: params.nullifier_imt_root,
        }
    }
}

impl From<bundle::NoteRef> for ApiVotingNoteRef {
    fn from(note: bundle::NoteRef) -> Self {
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

impl From<BundleSetupResult> for ApiVotingBundleSetupResult {
    fn from(result: BundleSetupResult) -> Self {
        Self {
            bundle_count: result.bundle_count,
            eligible_weight_zatoshi: result.eligible_weight_zatoshi,
        }
    }
}

impl From<DelegationPirPrecomputeResult> for ApiDelegationPirPrecomputeResult {
    fn from(result: DelegationPirPrecomputeResult) -> Self {
        Self {
            cached_count: result.cached_count,
            fetched_count: result.fetched_count,
            bundle_count: result.bundle_count,
            bundle_index: result.bundle_index,
        }
    }
}

impl From<SignedDelegationPayload> for ApiSignedDelegationPayload {
    fn from(result: SignedDelegationPayload) -> Self {
        Self {
            pczt_bytes: result.pczt_bytes,
            status: result.status,
            message: result.message,
            proof: result.proof,
            rk: result.rk,
            spend_auth_sig: result.spend_auth_sig,
            sighash: result.sighash,
            nf_signed: result.nf_signed,
            cmx_new: result.cmx_new,
            gov_comm: result.gov_comm,
            gov_nullifiers: result.gov_nullifiers,
            vote_round_id: result.vote_round_id,
            eligible_weight_zatoshi: result.eligible_weight_zatoshi,
            delegated_weight_zatoshi: result.delegated_weight_zatoshi,
            bundle_count: result.bundle_count,
            bundle_index: result.bundle_index,
        }
    }
}

impl From<KeystoneDelegationRequest> for ApiKeystoneDelegationRequest {
    fn from(result: KeystoneDelegationRequest) -> Self {
        Self {
            pczt_bytes: result.pczt_bytes,
            redacted_pczt_bytes: result.redacted_pczt_bytes,
            pczt_sighash: result.pczt_sighash,
            rk: result.rk,
            action_index: result.action_index,
            display_memo: result.display_memo,
            eligible_weight_zatoshi: result.eligible_weight_zatoshi,
            delegated_weight_zatoshi: result.delegated_weight_zatoshi,
            bundle_count: result.bundle_count,
            bundle_index: result.bundle_index,
        }
    }
}

impl From<KeystoneSignatureRecord> for ApiKeystoneSignatureRecord {
    fn from(record: KeystoneSignatureRecord) -> Self {
        Self {
            bundle_index: record.bundle_index,
            sig: record.sig,
            sighash: record.sighash,
            rk: record.rk,
        }
    }
}

impl From<ProofEvent> for ApiDelegationProofEvent {
    fn from(event: ProofEvent) -> Self {
        match event {
            ProofEvent::SelectingNotes => Self {
                phase: "selecting_notes".to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            ProofEvent::BuildingPczt => Self {
                phase: "building_pczt".to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
            ProofEvent::BuildingProof => Self {
                phase: "building_proof".to_string(),
                proof_progress: Some(0.0),
                signed_delegation_payload: None,
            },
            ProofEvent::ProofProgress { progress } => Self {
                phase: "proof_progress".to_string(),
                proof_progress: Some(progress),
                signed_delegation_payload: None,
            },
            ProofEvent::SigningPayload => Self {
                phase: "signing_payload".to_string(),
                proof_progress: Some(1.0),
                signed_delegation_payload: None,
            },
            ProofEvent::PayloadReady => Self {
                phase: "payload_ready".to_string(),
                proof_progress: None,
                signed_delegation_payload: None,
            },
        }
    }
}

impl From<VanWitness> for ApiVanWitness {
    fn from(witness: VanWitness) -> Self {
        Self {
            auth_path: witness.auth_path,
            position: witness.position,
            anchor_height: witness.anchor_height,
        }
    }
}

impl From<ApiVanWitness> for VanWitness {
    fn from(witness: ApiVanWitness) -> Self {
        Self {
            auth_path: witness.auth_path,
            position: witness.position,
            anchor_height: witness.anchor_height,
        }
    }
}

impl From<ApiDraftVote> for vote::DraftVote {
    fn from(draft: ApiDraftVote) -> Self {
        Self {
            proposal_id: draft.proposal_id,
            choice: draft.choice,
            num_options: draft.num_options,
            vc_tree_position: draft.vc_tree_position,
            single_share: draft.single_share,
        }
    }
}

impl From<vote::VoteCommitEvent> for ApiVoteCommitEvent {
    fn from(event: vote::VoteCommitEvent) -> Self {
        match event {
            vote::VoteCommitEvent::BuildingProof {
                proposal_id,
                bundle_index,
            } => Self {
                phase: "building_proof".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(0.0),
                commitments: None,
            },
            vote::VoteCommitEvent::ProofProgress {
                proposal_id,
                bundle_index,
                progress,
            } => Self {
                phase: "proof_progress".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(progress),
                commitments: None,
            },
            vote::VoteCommitEvent::BuildingSharePayloads {
                proposal_id,
                bundle_index,
            } => Self {
                phase: "building_share_payloads".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: Some(1.0),
                commitments: None,
            },
            vote::VoteCommitEvent::Signing {
                proposal_id,
                bundle_index,
            } => Self {
                phase: "signing".to_string(),
                proposal_id: Some(proposal_id),
                bundle_index: Some(bundle_index),
                proof_progress: None,
                commitments: None,
            },
            vote::VoteCommitEvent::Done => Self {
                phase: "done".to_string(),
                proposal_id: None,
                bundle_index: None,
                proof_progress: None,
                commitments: None,
            },
        }
    }
}

impl From<vote::WireEncryptedShare> for ApiWireEncryptedShare {
    fn from(share: vote::WireEncryptedShare) -> Self {
        Self {
            ciphertext1: share.ciphertext1,
            ciphertext2: share.ciphertext2,
            share_index: share.share_index,
        }
    }
}

impl From<vote::VoteSharePayload> for ApiVoteSharePayload {
    fn from(payload: vote::VoteSharePayload) -> Self {
        Self {
            shares_hash: payload.shares_hash,
            proposal_id: payload.proposal_id,
            vote_decision: payload.vote_decision,
            encrypted_share: payload.encrypted_share.into(),
            tree_position: payload.tree_position,
            all_encrypted_shares: payload
                .all_encrypted_shares
                .into_iter()
                .map(Into::into)
                .collect(),
            share_comms: payload.share_comms,
            primary_blind: payload.primary_blind,
        }
    }
}

impl From<vote::SignedVoteCommitment> for ApiSignedVoteCommitment {
    fn from(commitment: vote::SignedVoteCommitment) -> Self {
        Self {
            proposal_id: commitment.proposal_id,
            choice: commitment.choice,
            vote_round_id: commitment.vote_round_id,
            van_nullifier: commitment.van_nullifier,
            vote_authority_note_new: commitment.vote_authority_note_new,
            vote_commitment: commitment.vote_commitment,
            proof: commitment.proof,
            encrypted_shares: commitment
                .encrypted_shares
                .into_iter()
                .map(Into::into)
                .collect(),
            share_payloads: commitment
                .share_payloads
                .into_iter()
                .map(Into::into)
                .collect(),
            anchor_height: commitment.anchor_height,
            shares_hash: commitment.shares_hash,
            share_comms: commitment.share_comms,
            r_vpk_bytes: commitment.r_vpk_bytes,
            vote_auth_sig: commitment.vote_auth_sig,
            commitment_bundle_json: commitment.commitment_bundle_json,
        }
    }
}

impl From<vote::SignedVoteCommitments> for ApiSignedVoteCommitments {
    fn from(commitments: vote::SignedVoteCommitments) -> Self {
        Self {
            bundle_index: commitments.bundle_index,
            commitments: commitments
                .commitments
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}

impl From<vote::VoteRecord> for ApiVoteRecord {
    fn from(record: vote::VoteRecord) -> Self {
        Self {
            proposal_id: record.proposal_id,
            bundle_index: record.bundle_index,
            choice: record.choice,
            submitted: record.submitted,
        }
    }
}

impl From<recovery::CommitmentBundleRecovery> for ApiCommitmentBundleRecovery {
    fn from(record: recovery::CommitmentBundleRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            commitment_bundle_json: record.commitment_bundle_json,
            vc_tree_position: record.vc_tree_position,
        }
    }
}

impl From<recovery::DelegationTxRecovery> for ApiDelegationTxRecovery {
    fn from(record: recovery::DelegationTxRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            tx_hash: record.tx_hash,
        }
    }
}

impl From<recovery::VoteTxRecovery> for ApiVoteTxRecovery {
    fn from(record: recovery::VoteTxRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            tx_hash: record.tx_hash,
        }
    }
}

impl From<recovery::DelegationWorkflowRecovery> for ApiDelegationWorkflowRecovery {
    fn from(record: recovery::DelegationWorkflowRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            phase: record.phase,
            tx_hash: record.tx_hash,
            van_leaf_position: record.van_leaf_position,
        }
    }
}

impl From<recovery::VoteWorkflowRecovery> for ApiVoteWorkflowRecovery {
    fn from(record: recovery::VoteWorkflowRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            phase: record.phase,
            tx_hash: record.tx_hash,
            vc_tree_position: record.vc_tree_position,
            has_commitment_bundle: record.has_commitment_bundle,
        }
    }
}

impl From<recovery::ShareWorkflowRecovery> for ApiShareWorkflowRecovery {
    fn from(record: recovery::ShareWorkflowRecovery) -> Self {
        Self {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            share_index: record.share_index,
            phase: record.phase,
        }
    }
}

impl From<recovery::ShareDelegationRecord> for ApiShareDelegationRecord {
    fn from(record: recovery::ShareDelegationRecord) -> Self {
        Self {
            round_id: record.round_id,
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            share_index: record.share_index,
            sent_to_urls: record.sent_to_urls,
            nullifier: record.nullifier,
            phase: record.phase,
            confirmed: record.confirmed,
            submit_at: record.submit_at,
            created_at: record.created_at,
        }
    }
}

impl From<recovery::RoundRecoveryState> for ApiRoundRecoveryState {
    fn from(state: recovery::RoundRecoveryState) -> Self {
        Self {
            round_id: state.round_id,
            bundle_count: state.bundle_count,
            delegation_workflows: state
                .delegation_workflows
                .into_iter()
                .map(Into::into)
                .collect(),
            delegation_tx_hashes: state
                .delegation_tx_hashes
                .into_iter()
                .map(Into::into)
                .collect(),
            votes: state.votes.into_iter().map(Into::into).collect(),
            vote_workflows: state.vote_workflows.into_iter().map(Into::into).collect(),
            vote_tx_hashes: state.vote_tx_hashes.into_iter().map(Into::into).collect(),
            commitment_bundles: state
                .commitment_bundles
                .into_iter()
                .map(Into::into)
                .collect(),
            share_workflows: state.share_workflows.into_iter().map(Into::into).collect(),
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

fn b64(bytes: impl AsRef<[u8]>) -> String {
    BASE64_STANDARD.encode(bytes.as_ref())
}

const MAX_SAFE_JSON_INTEGER: u64 = 0x1f_ffff_ffff_ffff;

fn json_safe_u64(value: u64, field: &str) -> Result<u64, String> {
    if value > MAX_SAFE_JSON_INTEGER {
        return Err(format!(
            "field {field} is too large to encode as JSON integer"
        ));
    }
    Ok(value)
}

fn b64_hex(hex_value: &str, field: &str) -> Result<String, String> {
    let normalized = hex_value.strip_prefix("0x").unwrap_or(hex_value);
    hex::decode(normalized)
        .map(b64)
        .map_err(|e| format!("{field} is not valid hex: {e}"))
}

fn wire_share_json(share: &ApiWireEncryptedShare) -> serde_json::Value {
    serde_json::json!({
        "c1": b64(&share.ciphertext1),
        "c2": b64(&share.ciphertext2),
        "share_index": share.share_index,
    })
}

fn delegation_submission_wire_json_inner(
    submission: &ApiSignedDelegationPayload,
) -> Result<String, String> {
    serde_json::to_string(&serde_json::json!({
        "rk": b64(&submission.rk),
        "spend_auth_sig": b64(&submission.spend_auth_sig),
        "sighash": b64(&submission.sighash),
        "signed_note_nullifier": b64(&submission.nf_signed),
        "cmx_new": b64(&submission.cmx_new),
        "van_cmx": b64(&submission.gov_comm),
        "gov_nullifiers": submission.gov_nullifiers.iter().map(b64).collect::<Vec<_>>(),
        "proof": b64(&submission.proof),
        "vote_round_id": b64_hex(&submission.vote_round_id, "vote_round_id")?,
    }))
    .map_err(|e| format!("serialize delegation wire JSON failed: {e}"))
}

fn vote_commitment_wire_json_inner(commitment: &ApiSignedVoteCommitment) -> Result<String, String> {
    serde_json::to_string(&serde_json::json!({
        "van_nullifier": b64(&commitment.van_nullifier),
        "vote_authority_note_new": b64(&commitment.vote_authority_note_new),
        "vote_commitment": b64(&commitment.vote_commitment),
        "proposal_id": commitment.proposal_id,
        "proof": b64(&commitment.proof),
        "vote_round_id": b64_hex(&commitment.vote_round_id, "vote_round_id")?,
        "vote_comm_tree_anchor_height": commitment.anchor_height,
        "r_vpk": b64(&commitment.r_vpk_bytes),
        "vote_auth_sig": b64(&commitment.vote_auth_sig),
    }))
    .map_err(|e| format!("serialize vote commitment wire JSON failed: {e}"))
}

fn vote_share_wire_json_inner(
    payload: &ApiVoteSharePayload,
    vc_tree_position: Option<u64>,
    submit_at: u64,
) -> Result<String, String> {
    serde_json::to_string(&serde_json::json!({
        "shares_hash": b64(&payload.shares_hash),
        "proposal_id": payload.proposal_id,
        "vote_decision": payload.vote_decision,
        "enc_share": wire_share_json(&payload.encrypted_share),
        "share_index": payload.encrypted_share.share_index,
        "tree_position": json_safe_u64(
            vc_tree_position.unwrap_or(payload.tree_position),
            "tree_position",
        )?,
        "all_enc_shares": payload
            .all_encrypted_shares
            .iter()
            .map(wire_share_json)
            .collect::<Vec<_>>(),
        "share_comms": payload.share_comms.iter().map(b64).collect::<Vec<_>>(),
        "primary_blind": b64(&payload.primary_blind),
        "submit_at": json_safe_u64(submit_at, "submit_at")?,
    }))
    .map_err(|e| format!("serialize vote share wire JSON failed: {e}"))
}

fn recovered_vote_share_wire_json_inner(
    commitment_bundle_json: &str,
    proposal_id: u32,
    share_index: u32,
    vc_tree_position: u64,
    submit_at: u64,
) -> Result<String, String> {
    let decoded: serde_json::Value = serde_json::from_str(commitment_bundle_json)
        .map_err(|e| format!("commitment bundle recovery JSON is malformed: {e}"))?;
    let object = decoded
        .as_object()
        .ok_or_else(|| "commitment bundle recovery JSON is not an object".to_string())?;
    let format = object
        .get("format")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| "commitment bundle recovery JSON has no format".to_string())?;
    if format != "vizor_vote_commitment_bundle_recovery_v1" {
        return Err(format!(
            "unsupported commitment bundle recovery format: {format}"
        ));
    }
    let payloads = object
        .get("share_payloads")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "commitment bundle recovery JSON has no share_payloads list".to_string())?;
    let payload = payloads
        .iter()
        .find(|payload| {
            payload
                .get("proposal_id")
                .and_then(serde_json::Value::as_u64)
                == Some(u64::from(proposal_id))
                && payload
                    .get("enc_share")
                    .and_then(|share| share.get("share_index"))
                    .and_then(serde_json::Value::as_u64)
                    == Some(u64::from(share_index))
        })
        .ok_or_else(|| {
            format!("no stored share payload for proposal {proposal_id} share {share_index}")
        })?;

    recovered_share_payload_json(
        payload,
        proposal_id,
        share_index,
        vc_tree_position,
        submit_at,
    )
}

fn recovered_share_payload_json(
    payload: &serde_json::Value,
    proposal_id: u32,
    share_index: u32,
    vc_tree_position: u64,
    submit_at: u64,
) -> Result<String, String> {
    serde_json::to_string(&serde_json::json!({
        "shares_hash": b64_hex_field(payload, "shares_hash")?,
        "proposal_id": proposal_id,
        "vote_decision": u32_field(payload, "vote_decision")?,
        "enc_share": recovered_wire_share_json(
            payload
                .get("enc_share")
                .ok_or_else(|| "stored share payload has no enc_share".to_string())?,
        )?,
        "share_index": share_index,
        "tree_position": json_safe_u64(vc_tree_position, "tree_position")?,
        "all_enc_shares": recovered_wire_shares_json(
            payload
                .get("all_enc_shares")
                .ok_or_else(|| "stored share payload has no all_enc_shares list".to_string())?,
        )?,
        "share_comms": hex_list_field(payload, "share_comms")?
            .into_iter()
            .map(|hex| b64_hex(&hex, "share_comms entry"))
            .collect::<Result<Vec<_>, _>>()?,
        "primary_blind": b64_hex_field(payload, "primary_blind")?,
        "submit_at": json_safe_u64(submit_at, "submit_at")?,
    }))
    .map_err(|e| format!("serialize recovered vote share wire JSON failed: {e}"))
}

fn recovered_wire_share_json(share: &serde_json::Value) -> Result<serde_json::Value, String> {
    Ok(serde_json::json!({
        "c1": b64_hex_field(share, "c1")?,
        "c2": b64_hex_field(share, "c2")?,
        "share_index": u32_field(share, "share_index")?,
    }))
}

fn recovered_wire_shares_json(
    shares: &serde_json::Value,
) -> Result<Vec<serde_json::Value>, String> {
    let shares = shares
        .as_array()
        .ok_or_else(|| "stored share payload all_enc_shares is not a list".to_string())?;
    shares.iter().map(recovered_wire_share_json).collect()
}

fn b64_hex_field(object: &serde_json::Value, key: &str) -> Result<String, String> {
    let value = object
        .get(key)
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| format!("stored share payload field {key} is not a hex string"))?;
    b64_hex(value, key)
}

fn hex_list_field(object: &serde_json::Value, key: &str) -> Result<Vec<String>, String> {
    let values = object
        .get(key)
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| format!("stored share payload field {key} is not a hex string list"))?;
    values
        .iter()
        .map(|value| {
            value
                .as_str()
                .map(str::to_string)
                .ok_or_else(|| format!("stored share payload field {key} is not a hex string list"))
        })
        .collect()
}

fn u32_field(object: &serde_json::Value, key: &str) -> Result<u32, String> {
    let value = object
        .get(key)
        .and_then(serde_json::Value::as_u64)
        .ok_or_else(|| format!("stored share payload field {key} is not an unsigned integer"))?;
    u32::try_from(value)
        .map_err(|_| format!("stored share payload field {key} does not fit in u32"))
}

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(format!("Rust panic: {msg}"))
        }
    }
}

/// Initialize or load a voting round in the local voting database.
///
/// `session_json` is stored with the round when provided and can contain
/// coordinator metadata such as the human-readable round name.
pub fn prepare_voting_round(
    db_path: String,
    wallet_id: String,
    round_params: ApiVotingRoundParams,
    session_json: Option<String>,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        state::init_voting_round(&db, &round_params.into(), session_json.as_deref())
    })
}

/// Return the number of stored bundles for a voting round.
pub fn get_bundle_count(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<u32, String> {
    catch(|| delegation::get_bundle_count(&db_path, &wallet_id, &round_id))
}

/// Select voting-eligible notes at `snapshot_height` using lightwalletd data.
///
/// The returned notes are raw snapshot-unspent notes and include the cached
/// tree anchor used by later delegation setup. `eligible_weight_zatoshi` is
/// computed from `zcash_voting` smart bundles.
pub async fn select_voting_notes(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    account_uuid: String,
    snapshot_height: u64,
) -> Result<ApiVotingNoteSelectionResult, String> {
    let network = keys::parse_network(&network)?;
    let selected = bundle::select_notes_with_lwd(
        &db_path,
        &lightwalletd_url,
        network,
        &account_uuid,
        snapshot_height,
    )
    .await?;
    selection_result(selected)
}

fn selection_result(selected: SelectedNotes) -> Result<ApiVotingNoteSelectionResult, String> {
    let note_count = u32::try_from(selected.notes.len()).map_err(|_| {
        format!(
            "Selected note count {} does not fit in u32",
            selected.notes.len()
        )
    })?;
    let eligible_weight_zatoshi = bundle::voting_power(&selected);
    let snapshot_height = selected.snapshot_height;
    let anchor_height = selected.anchor_tree_state.height;
    let notes = selected.notes.into_iter().map(Into::into).collect();

    Ok(ApiVotingNoteSelectionResult {
        note_count,
        eligible_weight_zatoshi,
        snapshot_height,
        anchor_height,
        notes,
    })
}

/// Select notes and persist bundle rows for the delegation pipeline.
///
/// Reuses existing bundle rows for the same round/wallet, so callers can safely
/// retry setup before proving a specific bundle.
pub async fn setup_delegation_bundles(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
) -> Result<ApiVotingBundleSetupResult, String> {
    let network = keys::parse_network(&network)?;
    delegation::setup_delegation_bundles(
        &db_path,
        &lightwalletd_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
    )
    .await
    .map(Into::into)
}

#[allow(clippy::too_many_arguments)]
/// Build delegation PCZT material and prefetch/cache PIR-backed IMT proofs.
///
/// This is a background warm-up path. The normal proof path still fetches any
/// missing PIR proofs if this was not run or did not complete in time.
pub async fn precompute_delegation_pir(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    seed_bytes: Vec<u8>,
    bundle_index: u32,
) -> Result<ApiDelegationPirPrecomputeResult, String> {
    let network = keys::parse_network(&network)?;
    let round_id = round_params.vote_round_id.clone();
    let seed = secrecy::SecretVec::new(seed_bytes);
    let cancellation = VotingWorkCancellation::start(&db_path, &account_uuid, Some(&round_id))?;
    delegation::precompute_delegation_pir(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &seed,
        bundle_index,
        cancellation,
    )
    .await
    .map(Into::into)
}

#[allow(clippy::too_many_arguments)]
/// Build, prove, and sign one delegation payload.
///
/// This non-streaming variant drops intermediate proof progress and returns the
/// final signed payload directly. Submission and tx-hash storage happen in Dart.
pub async fn build_prove_and_sign_delegation_payload(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    seed_bytes: Vec<u8>,
    bundle_index: u32,
) -> Result<ApiSignedDelegationPayload, String> {
    let network = keys::parse_network(&network)?;
    let round_id = round_params.vote_round_id.clone();
    let seed = secrecy::SecretVec::new(seed_bytes);
    let cancellation = VotingWorkCancellation::start(&db_path, &account_uuid, Some(&round_id))?;
    delegation::build_prove_and_sign_delegation_payload(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &seed,
        bundle_index,
        |_| {},
        cancellation,
    )
    .await
    .map(Into::into)
}

#[allow(clippy::too_many_arguments)]
/// Streaming variant of `build_prove_and_sign_delegation_payload`.
///
/// Emits local preparation phase events while work progresses, then emits a
/// final `"result"` event containing `ApiSignedDelegationPayload`. The function
/// returns `Ok(())` after the terminal event is queued.
pub async fn build_prove_and_sign_delegation_payload_with_progress(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    seed_bytes: Vec<u8>,
    bundle_index: u32,
    sink: StreamSink<ApiDelegationProofEvent>,
) -> Result<(), String> {
    let network = keys::parse_network(&network)?;
    let round_id = round_params.vote_round_id.clone();
    let seed = secrecy::SecretVec::new(seed_bytes);
    let cancellation = VotingWorkCancellation::start(&db_path, &account_uuid, Some(&round_id))?;
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let progress_cancellation = cancellation.clone();
    let signed = delegation::build_prove_and_sign_delegation_payload(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &seed,
        bundle_index,
        move |event| {
            if progress_sink.add(event.into()).is_err() {
                progress_cancellation.cancel_local();
                log::warn!("voting delegation: StreamSink closed, progress not delivered");
            }
        },
        cancellation,
    )
    .await
    .map(ApiSignedDelegationPayload::from)?;

    if sink
        .add(ApiDelegationProofEvent {
            phase: "result".to_string(),
            proof_progress: None,
            signed_delegation_payload: Some(signed),
        })
        .is_err()
    {
        log::warn!("voting delegation: StreamSink closed before final result");
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
/// Build and redact a voting PCZT that Keystone must sign for one bundle.
pub async fn build_keystone_delegation_request(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    hotkey_seed: Vec<u8>,
    bundle_index: u32,
) -> Result<ApiKeystoneDelegationRequest, String> {
    let network = keys::parse_network(&network)?;
    let round_id = round_params.vote_round_id.clone();
    let hotkey_secret = secrecy::SecretVec::new(hotkey_seed);
    let cancellation = VotingWorkCancellation::start(&db_path, &account_uuid, Some(&round_id))?;
    delegation::build_keystone_delegation_request(
        &db_path,
        &lightwalletd_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &hotkey_secret,
        bundle_index,
        cancellation,
    )
    .await
    .map(Into::into)
}

/// Extract the ZIP-244 sighash from PCZT bytes.
pub fn extract_pczt_sighash(pczt_bytes: Vec<u8>) -> Result<Vec<u8>, String> {
    catch(|| delegation::extract_pczt_sighash(&pczt_bytes))
}

/// Extract a Keystone SpendAuth signature from signed PCZT bytes.
pub fn extract_spend_auth_signature_from_signed_pczt(
    signed_pczt_bytes: Vec<u8>,
    action_index: u32,
) -> Result<Vec<u8>, String> {
    catch(|| {
        delegation::extract_spend_auth_signature_from_signed_pczt(&signed_pczt_bytes, action_index)
    })
}

/// Persist a Keystone signature for one delegation bundle.
pub fn store_keystone_signature(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    sig: Vec<u8>,
    sighash: Vec<u8>,
    rk: Vec<u8>,
) -> Result<(), String> {
    catch(|| {
        delegation::store_keystone_signature(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            &sig,
            &sighash,
            &rk,
        )
    })
}

/// Load persisted Keystone signatures for one voting round.
pub fn get_keystone_signatures(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<Vec<ApiKeystoneSignatureRecord>, String> {
    catch(|| {
        delegation::get_keystone_signatures(&db_path, &wallet_id, &round_id)
            .map(|records| records.into_iter().map(Into::into).collect())
    })
}

#[allow(clippy::too_many_arguments)]
/// Streaming Keystone variant of `build_prove_and_sign_delegation_payload`.
pub async fn build_prove_delegation_payload_with_keystone_signature_with_progress(
    db_path: String,
    lightwalletd_url: String,
    pir_server_url: String,
    network: String,
    round_params: ApiVotingRoundParams,
    round_name: String,
    session_json: Option<String>,
    account_uuid: String,
    hotkey_seed: Vec<u8>,
    bundle_index: u32,
    keystone_sig: Vec<u8>,
    keystone_sighash: Vec<u8>,
    sink: StreamSink<ApiDelegationProofEvent>,
) -> Result<(), String> {
    let network = keys::parse_network(&network)?;
    let round_id = round_params.vote_round_id.clone();
    let hotkey_secret = secrecy::SecretVec::new(hotkey_seed);
    let cancellation = VotingWorkCancellation::start(&db_path, &account_uuid, Some(&round_id))?;
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let progress_cancellation = cancellation.clone();
    let signed = delegation::build_prove_delegation_payload_with_keystone_signature(
        &db_path,
        &lightwalletd_url,
        &pir_server_url,
        network,
        round_params.into(),
        &round_name,
        session_json.as_deref(),
        &account_uuid,
        &hotkey_secret,
        bundle_index,
        &keystone_sig,
        &keystone_sighash,
        move |event| {
            if progress_sink.add(event.into()).is_err() {
                progress_cancellation.cancel_local();
                log::warn!("voting delegation: StreamSink closed, progress not delivered");
            }
        },
        cancellation,
    )
    .await
    .map(ApiSignedDelegationPayload::from)?;

    if sink
        .add(ApiDelegationProofEvent {
            phase: "result".to_string(),
            proof_progress: None,
            signed_delegation_payload: Some(signed),
        })
        .is_err()
    {
        log::warn!("voting delegation: StreamSink closed before final result");
    }
    Ok(())
}

/// Store the broadcast transaction hash for one delegation bundle.
///
/// Hashes are keyed by `(round_id, wallet_id, bundle_index)` to support partial
/// bundle recovery.
pub fn store_delegation_tx_hash(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        delegation::store_delegation_tx_hash(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            &tx_hash,
        )
    })
}

pub fn mark_delegation_submitted(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        delegation::store_delegation_tx_hash(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            &tx_hash,
        )
    })
}

pub fn mark_delegation_confirmed(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    tx_hash: String,
    van_leaf_position: u32,
) -> Result<(), String> {
    catch(|| {
        recovery::mark_delegation_confirmed(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            &tx_hash,
            van_leaf_position,
        )
    })
}

/// Store the vote-authority-note leaf position emitted by the delegation TX.
pub fn store_van_position(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    position: u32,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        db.store_van_position(&round_id, bundle_index, position)
            .map_err(|e| format!("store_van_position failed: {e}"))
    })
}

/// Load the broadcast transaction hash for one delegation bundle, if present.
pub fn get_delegation_tx_hash(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
) -> Result<Option<String>, String> {
    catch(|| delegation::get_delegation_tx_hash(&db_path, &wallet_id, &round_id, bundle_index))
}

/// Delete bundle rows at or above `keep_count` for partial-bundle recovery.
///
/// Returns the number of deleted rows.
pub fn delete_skipped_bundles(
    db_path: String,
    wallet_id: String,
    round_id: String,
    keep_count: u32,
) -> Result<u32, String> {
    catch(|| delegation::delete_skipped_bundles(&db_path, &wallet_id, &round_id, keep_count))
}

/// Sync vote commitment tree state for a voting round.
///
/// Returns the latest synced tree height. The underlying tree client is cached
/// per `(db_path, wallet_id)` so later VAN witness calls can reuse the synced
/// in-memory tree state.
pub fn sync_vote_tree(
    db_path: String,
    wallet_id: String,
    round_id: String,
    node_url: String,
) -> Result<u32, String> {
    catch(|| tree_sync::sync_commitment_tree(&db_path, &wallet_id, &round_id, &node_url))
}

/// Generate a Vote Authority Note Merkle witness for a delegation bundle.
///
/// `anchor_height` is the vote-tree height where the witness should be anchored;
/// callers must sync the same round before requesting the witness.
pub fn generate_van_witness(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    anchor_height: u32,
) -> Result<ApiVanWitness, String> {
    catch(|| {
        tree_sync::generate_van_witness(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            anchor_height,
        )
        .map(Into::into)
    })
}

/// Reset cached vote-tree client state for one round or all rounds.
///
/// `None` and `Some("")` both clear every round for the `(db_path, wallet_id)`
/// session; a non-empty round ID clears only that round.
pub fn reset_tree_client(
    db_path: String,
    wallet_id: String,
    round_id: Option<String>,
) -> Result<(), String> {
    catch(|| tree_sync::reset_tree_client(&db_path, &wallet_id, round_id.as_deref()))
}

/// Clear process-local voting state for a wallet or round.
///
/// Passing a non-empty round ID clears prepared delegation PCZTs only for that
/// round. Passing `None` or an empty round ID performs account-wide cleanup:
/// prepared PCZTs for the wallet are cleared and the cached vote-tree client is
/// dropped.
pub fn reset_voting_session_state(
    db_path: String,
    wallet_id: String,
    round_id: Option<String>,
) -> Result<(), String> {
    catch(|| {
        cancel_voting_work(&db_path, &wallet_id, round_id.as_deref())?;
        let account_wide = round_id.as_deref().map(str::is_empty).unwrap_or(true);
        let tree_count = if account_wide {
            tree_sync::clear_tree_sync_session(&db_path, &wallet_id)?
        } else {
            0
        };
        let pczt_count = delegation::clear_prepared_delegation_pczt_cache(
            &db_path,
            &wallet_id,
            round_id.as_deref(),
        )?;
        log::info!(
            "voting: reset process-local session state \
             (wallet_id={}, round_id={:?}, tree_entries={}, prepared_pczts={})",
            wallet_id,
            round_id,
            tree_count,
            pczt_count
        );
        Ok(())
    })
}

#[allow(clippy::too_many_arguments)]
/// Build signed ZKP2 vote commitments for one bundle.
///
/// Callers must pass a VAN witness generated for the same round and anchor
/// height. Returned encrypted shares are wire-safe and exclude plaintext values
/// and randomness.
pub fn build_vote_commitments(
    db_path: String,
    wallet_id: String,
    network: String,
    round_id: String,
    bundle_index: u32,
    hotkey_seed: Vec<u8>,
    van_witness: ApiVanWitness,
    draft_votes: Vec<ApiDraftVote>,
) -> Result<ApiSignedVoteCommitments, String> {
    let network = keys::parse_network(&network)?;
    let hotkey_seed = secrecy::SecretVec::new(hotkey_seed);
    let cancellation = VotingWorkCancellation::start(&db_path, &wallet_id, Some(&round_id))?;
    vote::build_vote_commitments(
        &db_path,
        &wallet_id,
        network,
        &round_id,
        bundle_index,
        &hotkey_seed,
        van_witness.into(),
        draft_votes.into_iter().map(Into::into).collect(),
        |_| {},
        cancellation,
    )
    .map(Into::into)
}

#[allow(clippy::too_many_arguments)]
/// Streaming variant of `build_vote_commitments`.
///
/// Emits per-proposal progress events, then a terminal `"result"` event carrying
/// `ApiSignedVoteCommitments`.
pub async fn build_vote_commitments_with_progress(
    db_path: String,
    wallet_id: String,
    network: String,
    round_id: String,
    bundle_index: u32,
    hotkey_seed: Vec<u8>,
    van_witness: ApiVanWitness,
    draft_votes: Vec<ApiDraftVote>,
    sink: StreamSink<ApiVoteCommitEvent>,
) -> Result<(), String> {
    let network = keys::parse_network(&network)?;
    let hotkey_seed = secrecy::SecretVec::new(hotkey_seed);
    let cancellation = VotingWorkCancellation::start(&db_path, &wallet_id, Some(&round_id))?;
    let sink = Arc::new(sink);
    let progress_sink = sink.clone();
    let progress_cancellation = cancellation.clone();
    let commitments = tokio::task::spawn_blocking(move || {
        vote::build_vote_commitments(
            &db_path,
            &wallet_id,
            network,
            &round_id,
            bundle_index,
            &hotkey_seed,
            van_witness.into(),
            draft_votes.into_iter().map(Into::into).collect(),
            move |event| {
                if progress_sink.add(event.into()).is_err() {
                    progress_cancellation.cancel_local();
                    log::warn!("voting vote: StreamSink closed, progress not delivered");
                }
            },
            cancellation,
        )
    })
    .await
    .map_err(|e| format!("vote commitment task failed: {e}"))?
    .map(ApiSignedVoteCommitments::from)?;

    if sink
        .add(ApiVoteCommitEvent {
            phase: "result".to_string(),
            proposal_id: None,
            bundle_index: Some(commitments.bundle_index),
            proof_progress: None,
            commitments: Some(commitments),
        })
        .is_err()
    {
        log::warn!("voting vote: StreamSink closed before final result");
    }
    Ok(())
}

/// Load stored votes for a round across all bundles for this wallet.
pub fn get_votes(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<Vec<ApiVoteRecord>, String> {
    catch(|| {
        vote::get_votes(&db_path, &wallet_id, &round_id)
            .map(|records| records.into_iter().map(Into::into).collect())
    })
}

/// Compute the deterministic share nullifier as lowercase 64-character hex.
///
/// The helper validates the commitment and blind lengths through `zcash_voting`.
pub fn compute_share_nullifier_hex(
    vote_commitment: Vec<u8>,
    share_index: u32,
    primary_blind: Vec<u8>,
) -> Result<String, String> {
    catch(|| vote::compute_share_nullifier_hex(&vote_commitment, share_index, &primary_blind))
}

/// Load the full recovery/share-tracking summary for one voting round.
pub fn get_round_recovery_state(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<ApiRoundRecoveryState, String> {
    catch(|| recovery::get_round_recovery_state(&db_path, &wallet_id, &round_id).map(Into::into))
}

/// Store the broadcast transaction hash for one vote.
///
/// Keyed by `(round_id, wallet_id, bundle_index, proposal_id)` so multi-bundle
/// and multi-proposal rounds can resume without ambiguous "current vote" state.
pub fn store_vote_tx_hash(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        recovery::store_vote_tx_hash(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            proposal_id,
            &tx_hash,
        )
    })
}

pub fn mark_vote_submitted(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: String,
) -> Result<(), String> {
    catch(|| {
        recovery::store_vote_tx_hash(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            proposal_id,
            &tx_hash,
        )
    })
}

#[allow(clippy::too_many_arguments)]
pub fn mark_vote_confirmed(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: String,
    van_position: u32,
    vc_tree_position: u64,
    commitment_bundle_json: String,
) -> Result<(), String> {
    catch(|| {
        recovery::mark_vote_confirmed(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            proposal_id,
            &tx_hash,
            van_position,
            vc_tree_position,
            &commitment_bundle_json,
        )
    })
}

/// Load the broadcast transaction hash for one vote, if present.
pub fn get_vote_tx_hash(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<String>, String> {
    catch(|| recovery::get_vote_tx_hash(&db_path, &wallet_id, &round_id, bundle_index, proposal_id))
}

#[allow(clippy::too_many_arguments)]
/// Store commitment bundle recovery JSON and confirmed vote-tree position for one vote.
pub fn store_commitment_bundle(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    commitment_bundle_json: String,
    vc_tree_position: u64,
) -> Result<(), String> {
    catch(|| {
        let db = state::open_voting_db(&db_path, &wallet_id)?;
        db.store_commitment_bundle(
            &round_id,
            bundle_index,
            proposal_id,
            &commitment_bundle_json,
            vc_tree_position,
        )
        .map_err(|e| format!("store_commitment_bundle failed: {e}"))
    })
}

/// Load commitment bundle recovery JSON and vote-tree position for one vote.
pub fn get_commitment_bundle(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<ApiCommitmentBundleRecovery>, String> {
    catch(|| {
        recovery::get_commitment_bundle(&db_path, &wallet_id, &round_id, bundle_index, proposal_id)
            .map(|bundle| bundle.map(Into::into))
    })
}

#[allow(clippy::too_many_arguments)]
/// Record helper-server submission state for one encrypted vote share.
pub fn record_share_delegation(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: Vec<String>,
    nullifier: Vec<u8>,
    submit_at: u64,
) -> Result<(), String> {
    catch(|| {
        recovery::record_share_delegation(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            proposal_id,
            share_index,
            &sent_to_urls,
            &nullifier,
            submit_at,
        )
    })
}

/// Load all helper-server share delegation records for a round.
pub fn get_share_delegations(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<Vec<ApiShareDelegationRecord>, String> {
    catch(|| {
        recovery::get_share_delegations(&db_path, &wallet_id, &round_id)
            .map(|records| records.into_iter().map(Into::into).collect())
    })
}

/// Load only unconfirmed helper-server share delegation records for retry.
pub fn get_unconfirmed_share_delegations(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<Vec<ApiShareDelegationRecord>, String> {
    catch(|| {
        recovery::get_unconfirmed_share_delegations(&db_path, &wallet_id, &round_id)
            .map(|records| records.into_iter().map(Into::into).collect())
    })
}

/// Mark one delegated share as confirmed on-chain.
pub fn mark_share_confirmed(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), String> {
    catch(|| {
        recovery::mark_share_confirmed(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            proposal_id,
            share_index,
        )
    })
}

/// Merge additional helper-server URLs into one share delegation record.
pub fn add_sent_servers(
    db_path: String,
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: Vec<String>,
) -> Result<(), String> {
    catch(|| {
        recovery::add_sent_servers(
            &db_path,
            &wallet_id,
            &round_id,
            bundle_index,
            proposal_id,
            share_index,
            &new_urls,
        )
    })
}

/// Clear vote/delegation recovery columns and share-tracking rows for a round.
///
/// This is an explicit reset for finalized or abandoned rounds, not a normal
/// retry step.
pub fn clear_recovery_state(
    db_path: String,
    wallet_id: String,
    round_id: String,
) -> Result<(), String> {
    catch(|| recovery::clear_recovery_state(&db_path, &wallet_id, &round_id))
}

#[cfg(test)]
mod tests {
    use super::*;
    use pasta_curves::Fp;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };
    use vote_commitment_tree::{MemoryTreeServer, MerkleHashVote};
    use zcash_client_backend::proto::service::TreeState;

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn api_round_params_convert_to_core_round_params() {
        let api = test_api_round_params();

        let core: zcash_voting::VotingRoundParams = api.clone().into();

        assert_eq!(core.vote_round_id, api.vote_round_id);
        assert_eq!(core.snapshot_height, api.snapshot_height);
        assert_eq!(core.ea_pk, api.ea_pk);
        assert_eq!(core.nc_root, api.nc_root);
        assert_eq!(core.nullifier_imt_root, api.nullifier_imt_root);
    }

    #[test]
    fn api_bundle_setup_result_preserves_core_fields() {
        let api = ApiVotingBundleSetupResult::from(BundleSetupResult {
            bundle_count: 2,
            eligible_weight_zatoshi: 50,
        });

        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.eligible_weight_zatoshi, 50);
    }

    #[test]
    fn api_signed_delegation_payload_preserves_core_fields() {
        let api = ApiSignedDelegationPayload::from(SignedDelegationPayload {
            pczt_bytes: vec![1, 2, 3],
            status: "ready_for_submission".to_string(),
            message: Some("ok".to_string()),
            proof: vec![4],
            rk: vec![5],
            spend_auth_sig: vec![6],
            sighash: vec![7],
            nf_signed: vec![8],
            cmx_new: vec![9],
            gov_comm: vec![10],
            gov_nullifiers: vec![vec![11]],
            vote_round_id: "round".to_string(),
            eligible_weight_zatoshi: 20,
            delegated_weight_zatoshi: 10,
            bundle_count: 2,
            bundle_index: 1,
        });

        assert_eq!(api.pczt_bytes, vec![1, 2, 3]);
        assert_eq!(api.status, "ready_for_submission");
        assert_eq!(api.message.as_deref(), Some("ok"));
        assert_eq!(api.proof, vec![4]);
        assert_eq!(api.vote_round_id, "round");
        assert_eq!(api.eligible_weight_zatoshi, 20);
        assert_eq!(api.delegated_weight_zatoshi, 10);
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn api_keystone_delegation_request_preserves_display_memo() {
        let api = ApiKeystoneDelegationRequest::from(KeystoneDelegationRequest {
            pczt_bytes: vec![1],
            redacted_pczt_bytes: vec![2],
            pczt_sighash: vec![3],
            rk: vec![4],
            action_index: 5,
            display_memo: "I am authorizing this hotkey.".to_string(),
            eligible_weight_zatoshi: 20,
            delegated_weight_zatoshi: 10,
            bundle_count: 2,
            bundle_index: 1,
        });

        assert_eq!(api.display_memo, "I am authorizing this hotkey.");
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn delegation_wire_json_matches_vote_chain_shape() {
        let wire = delegation_submission_wire_json(ApiSignedDelegationPayload {
            pczt_bytes: vec![],
            status: "ready".to_string(),
            message: None,
            proof: vec![8],
            rk: vec![1],
            spend_auth_sig: vec![2],
            sighash: vec![3],
            nf_signed: vec![4],
            cmx_new: vec![5],
            gov_comm: vec![6],
            gov_nullifiers: vec![vec![7], vec![9]],
            vote_round_id: "00010203".to_string(),
            eligible_weight_zatoshi: 0,
            delegated_weight_zatoshi: 0,
            bundle_count: 1,
            bundle_index: 0,
        })
        .unwrap();

        assert_eq!(
            wire,
            r#"{"cmx_new":"BQ==","gov_nullifiers":["Bw==","CQ=="],"proof":"CA==","rk":"AQ==","sighash":"Aw==","signed_note_nullifier":"BA==","spend_auth_sig":"Ag==","van_cmx":"Bg==","vote_round_id":"AAECAw=="}"#
        );
    }

    #[test]
    fn cast_vote_wire_json_matches_vote_chain_shape() {
        let wire = vote_commitment_wire_json(ApiSignedVoteCommitment {
            proposal_id: 42,
            choice: 1,
            vote_round_id: "00010203".to_string(),
            van_nullifier: vec![1],
            vote_authority_note_new: vec![2],
            vote_commitment: vec![3],
            proof: vec![4],
            encrypted_shares: vec![],
            share_payloads: vec![],
            anchor_height: 77,
            shares_hash: vec![],
            share_comms: vec![],
            r_vpk_bytes: vec![5],
            vote_auth_sig: vec![6],
            commitment_bundle_json: String::new(),
        })
        .unwrap();

        assert_eq!(
            wire,
            r#"{"proof":"BA==","proposal_id":42,"r_vpk":"BQ==","van_nullifier":"AQ==","vote_auth_sig":"Bg==","vote_authority_note_new":"Ag==","vote_comm_tree_anchor_height":77,"vote_commitment":"Aw==","vote_round_id":"AAECAw=="}"#
        );
    }

    #[test]
    fn share_wire_json_matches_helper_shape_for_live_and_recovery_payloads() {
        let payload = ApiVoteSharePayload {
            shares_hash: vec![1],
            proposal_id: 42,
            vote_decision: 2,
            encrypted_share: ApiWireEncryptedShare {
                ciphertext1: vec![3],
                ciphertext2: vec![4],
                share_index: 1,
            },
            tree_position: 55,
            all_encrypted_shares: vec![
                ApiWireEncryptedShare {
                    ciphertext1: vec![3],
                    ciphertext2: vec![4],
                    share_index: 1,
                },
                ApiWireEncryptedShare {
                    ciphertext1: vec![5],
                    ciphertext2: vec![6],
                    share_index: 2,
                },
            ],
            share_comms: vec![vec![7], vec![8]],
            primary_blind: vec![9],
        };
        let live = vote_share_wire_json(payload, Some(99), 123).unwrap();
        let expected = r#"{"all_enc_shares":[{"c1":"Aw==","c2":"BA==","share_index":1},{"c1":"BQ==","c2":"Bg==","share_index":2}],"enc_share":{"c1":"Aw==","c2":"BA==","share_index":1},"primary_blind":"CQ==","proposal_id":42,"share_comms":["Bw==","CA=="],"share_index":1,"shares_hash":"AQ==","submit_at":123,"tree_position":99,"vote_decision":2}"#;
        assert_eq!(live, expected);

        let recovery_json = serde_json::json!({
            "format": "vizor_vote_commitment_bundle_recovery_v1",
            "share_payloads": [{
                "shares_hash": "01",
                "proposal_id": 42,
                "vote_decision": 2,
                "enc_share": {"c1": "03", "c2": "04", "share_index": 1},
                "tree_position": 55,
                "all_enc_shares": [
                    {"c1": "03", "c2": "04", "share_index": 1},
                    {"c1": "05", "c2": "06", "share_index": 2}
                ],
                "share_comms": ["07", "08"],
                "primary_blind": "09"
            }]
        })
        .to_string();
        let recovered = recovered_vote_share_wire_json(recovery_json, 42, 1, 99, 0).unwrap();
        let expected_recovered = r#"{"all_enc_shares":[{"c1":"Aw==","c2":"BA==","share_index":1},{"c1":"BQ==","c2":"Bg==","share_index":2}],"enc_share":{"c1":"Aw==","c2":"BA==","share_index":1},"primary_blind":"CQ==","proposal_id":42,"share_comms":["Bw==","CA=="],"share_index":1,"shares_hash":"AQ==","submit_at":0,"tree_position":99,"vote_decision":2}"#;
        assert_eq!(recovered, expected_recovered);
    }

    #[test]
    fn share_wire_json_rejects_json_unsafe_integer_fields() {
        let payload = ApiVoteSharePayload {
            shares_hash: vec![1],
            proposal_id: 42,
            vote_decision: 2,
            encrypted_share: ApiWireEncryptedShare {
                ciphertext1: vec![3],
                ciphertext2: vec![4],
                share_index: 1,
            },
            tree_position: MAX_SAFE_JSON_INTEGER + 1,
            all_encrypted_shares: vec![],
            share_comms: vec![],
            primary_blind: vec![9],
        };

        let err = vote_share_wire_json(payload, None, 123).unwrap_err();
        assert!(err.contains("tree_position"));
    }

    #[test]
    fn api_van_witness_preserves_core_fields() {
        let api = ApiVanWitness::from(VanWitness {
            auth_path: vec![vec![1; 32], vec![2; 32]],
            position: 7,
            anchor_height: 123,
        });

        assert_eq!(api.auth_path, vec![vec![1; 32], vec![2; 32]]);
        assert_eq!(api.position, 7);
        assert_eq!(api.anchor_height, 123);
    }

    #[test]
    fn api_delegation_proof_event_uses_stable_phase_names() {
        assert_eq!(
            ApiDelegationProofEvent::from(ProofEvent::SelectingNotes).phase,
            "selecting_notes"
        );
        assert_eq!(
            ApiDelegationProofEvent::from(ProofEvent::SigningPayload).phase,
            "signing_payload"
        );
        let ready = ApiDelegationProofEvent::from(ProofEvent::PayloadReady);
        assert_eq!(ready.phase, "payload_ready");
        assert_eq!(ready.proof_progress, None);
        assert!(ready.signed_delegation_payload.is_none());

        let proof = ApiDelegationProofEvent::from(ProofEvent::ProofProgress { progress: 0.5 });
        assert_eq!(proof.phase, "proof_progress");
        assert_eq!(proof.proof_progress, Some(0.5));

        let result = ApiDelegationProofEvent {
            phase: "result".to_string(),
            proof_progress: None,
            signed_delegation_payload: Some(ApiSignedDelegationPayload {
                pczt_bytes: vec![1],
                status: "ready_for_submission".to_string(),
                message: None,
                proof: vec![1],
                rk: vec![2],
                spend_auth_sig: vec![3],
                sighash: vec![4],
                nf_signed: vec![5],
                cmx_new: vec![6],
                gov_comm: vec![7],
                gov_nullifiers: vec![vec![8]],
                vote_round_id: "round".to_string(),
                eligible_weight_zatoshi: 10,
                delegated_weight_zatoshi: 10,
                bundle_count: 1,
                bundle_index: 0,
            }),
        };
        assert_eq!(result.phase, "result");
        assert_eq!(
            result.signed_delegation_payload.as_ref().unwrap().status,
            "ready_for_submission"
        );
    }

    #[test]
    fn api_vote_commit_event_uses_stable_phase_names() {
        let event = ApiVoteCommitEvent::from(vote::VoteCommitEvent::BuildingProof {
            proposal_id: 1,
            bundle_index: 2,
        });

        assert_eq!(event.phase, "building_proof");
        assert_eq!(event.proposal_id, Some(1));
        assert_eq!(event.bundle_index, Some(2));
        assert_eq!(event.proof_progress, Some(0.0));
        let proof = ApiVoteCommitEvent::from(vote::VoteCommitEvent::ProofProgress {
            proposal_id: 1,
            bundle_index: 2,
            progress: 0.5,
        });
        assert_eq!(proof.phase, "proof_progress");
        assert_eq!(proof.proof_progress, Some(0.5));
        assert_eq!(
            ApiVoteCommitEvent::from(vote::VoteCommitEvent::Done).phase,
            "done"
        );

        let result = ApiVoteCommitEvent {
            phase: "result".to_string(),
            proposal_id: None,
            bundle_index: Some(2),
            proof_progress: None,
            commitments: Some(ApiSignedVoteCommitments {
                bundle_index: 2,
                commitments: vec![],
            }),
        };
        assert_eq!(result.phase, "result");
        assert_eq!(result.commitments.as_ref().unwrap().bundle_index, 2);
    }

    #[test]
    fn api_signed_vote_commitments_preserve_public_wire_fields() {
        let api = ApiSignedVoteCommitments::from(vote::SignedVoteCommitments {
            bundle_index: 1,
            commitments: vec![vote::SignedVoteCommitment {
                proposal_id: 2,
                choice: 1,
                vote_round_id: ROUND_ID.to_string(),
                van_nullifier: vec![1; 32],
                vote_authority_note_new: vec![2; 32],
                vote_commitment: vec![3; 32],
                proof: vec![4; 10],
                encrypted_shares: vec![vote::WireEncryptedShare {
                    ciphertext1: vec![5; 32],
                    ciphertext2: vec![6; 32],
                    share_index: 0,
                }],
                share_payloads: vec![vote::VoteSharePayload {
                    shares_hash: vec![7; 32],
                    proposal_id: 2,
                    vote_decision: 1,
                    encrypted_share: vote::WireEncryptedShare {
                        ciphertext1: vec![5; 32],
                        ciphertext2: vec![6; 32],
                        share_index: 0,
                    },
                    tree_position: 9,
                    all_encrypted_shares: vec![],
                    share_comms: vec![vec![8; 32]],
                    primary_blind: vec![9; 32],
                }],
                anchor_height: 100,
                shares_hash: vec![7; 32],
                share_comms: vec![vec![8; 32]],
                r_vpk_bytes: vec![10; 32],
                vote_auth_sig: vec![9; 64],
                commitment_bundle_json: "{\"proposal_id\":2}".to_string(),
            }],
        });

        assert_eq!(api.bundle_index, 1);
        assert_eq!(api.commitments[0].proposal_id, 2);
        assert_eq!(
            api.commitments[0].encrypted_shares[0].ciphertext1,
            vec![5; 32]
        );
        assert_eq!(
            api.commitments[0].share_payloads[0].primary_blind,
            vec![9; 32]
        );
        assert_eq!(api.commitments[0].vote_auth_sig, vec![9; 64]);
    }

    #[test]
    fn api_note_selection_result_preserves_core_fields() {
        let divisor = zcash_voting::governance::BALLOT_DIVISOR;
        let selected = SelectedNotes {
            notes: vec![
                test_note_ref(divisor / 2, divisor / 2, 3),
                test_note_ref(divisor / 2, divisor / 2, 7),
            ],
            snapshot_height: 100,
            anchor_tree_state: test_tree_state(100),
        };

        let api = selection_result(selected).unwrap();

        assert_eq!(api.note_count, 2);
        assert_eq!(api.eligible_weight_zatoshi, divisor);
        assert_eq!(api.snapshot_height, 100);
        assert_eq!(api.anchor_height, 100);
        assert_eq!(api.notes[0].commitment_tree_position, 3);
        assert_eq!(api.notes[1].value_zatoshi, divisor / 2);
        assert_eq!(api.notes[1].voting_weight_zatoshi, divisor / 2);
    }

    #[test]
    fn prepare_voting_round_initializes_round_happy_path() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");

        prepare_voting_round(
            db_path.to_str().unwrap().to_string(),
            "wallet-1".to_string(),
            test_api_round_params(),
            Some(r#"{"round_name":"Demo"}"#.to_string()),
        )
        .unwrap();

        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        let state = db.get_round_state(ROUND_ID).unwrap();
        assert_eq!(state.round_id, ROUND_ID);
        assert_eq!(state.snapshot_height, 100);
    }

    #[test]
    fn prepare_voting_round_rejects_invalid_round_params() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let mut params = test_api_round_params();
        params.nc_root.pop();

        let err = prepare_voting_round(
            db_path.to_str().unwrap().to_string(),
            "wallet-1".to_string(),
            params,
            None,
        )
        .unwrap_err();

        assert!(err.contains("Invalid voting round params"));
    }

    #[test]
    fn bundle_count_tx_hash_and_delete_api_are_bundle_indexed() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-api-bundles").unwrap();
        state::init_voting_round(&db, &test_api_round_params().into(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.setup_bundles(ROUND_ID, &notes).unwrap();

        assert_eq!(
            get_bundle_count(
                db_path.to_str().unwrap().to_string(),
                "wallet-api-bundles".to_string(),
                ROUND_ID.to_string(),
            )
            .unwrap(),
            2
        );

        store_delegation_tx_hash(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-bundles".to_string(),
            ROUND_ID.to_string(),
            1,
            "txid-bundle-1".to_string(),
        )
        .unwrap();
        assert_eq!(
            get_delegation_tx_hash(
                db_path.to_str().unwrap().to_string(),
                "wallet-api-bundles".to_string(),
                ROUND_ID.to_string(),
                1,
            )
            .unwrap()
            .as_deref(),
            Some("txid-bundle-1")
        );

        assert_eq!(
            delete_skipped_bundles(
                db_path.to_str().unwrap().to_string(),
                "wallet-api-bundles".to_string(),
                ROUND_ID.to_string(),
                1,
            )
            .unwrap(),
            1
        );
        assert_eq!(
            get_bundle_count(
                db_path.to_str().unwrap().to_string(),
                "wallet-api-bundles".to_string(),
                ROUND_ID.to_string(),
            )
            .unwrap(),
            1
        );
    }

    #[test]
    fn sync_vote_tree_api_happy_path_accepts_empty_tree() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let server = start_tree_server(0, vec![], 1);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-empty-sync".to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        assert_eq!(height, 0);
    }

    #[test]
    fn generate_van_witness_api_happy_path_after_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-api-witness").unwrap();
        state::init_voting_round(&db, &test_api_round_params().into(), None).unwrap();
        db.setup_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![1], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-witness".to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();
        let witness = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-witness".to_string(),
            ROUND_ID.to_string(),
            0,
            height,
        )
        .unwrap();

        assert_eq!(witness.position, 0);
        assert_eq!(witness.anchor_height, 1);
        assert_eq!(witness.auth_path.len(), 24);
        assert!(witness.auth_path.iter().all(|hash| hash.len() == 32));
    }

    #[test]
    fn reset_tree_client_api_happy_path_accepts_round_and_all_rounds() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");

        reset_tree_client(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-reset".to_string(),
            Some(ROUND_ID.to_string()),
        )
        .unwrap();
        reset_tree_client(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-reset".to_string(),
            None,
        )
        .unwrap();
    }

    #[test]
    fn reset_voting_session_state_with_round_preserves_tree_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let wallet_id = "wallet-api-round-reset";
        let db = state::open_voting_db(db_path.to_str().unwrap(), wallet_id).unwrap();
        state::init_voting_round(&db, &test_api_round_params().into(), None).unwrap();
        db.setup_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![1], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            Some(ROUND_ID.to_string()),
        )
        .unwrap();

        let witness = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            0,
            height,
        )
        .unwrap();
        assert_eq!(witness.position, 0);
    }

    #[test]
    fn reset_voting_session_state_without_round_drops_tree_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let wallet_id = "wallet-api-account-reset";
        let db = state::open_voting_db(db_path.to_str().unwrap(), wallet_id).unwrap();
        state::init_voting_round(&db, &test_api_round_params().into(), None).unwrap();
        db.setup_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_van_position(ROUND_ID, 0, 0).unwrap();
        let server = start_tree_server(1, vec![1], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            None,
        )
        .unwrap();

        let err = generate_van_witness(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            0,
            height,
        )
        .unwrap_err();
        assert!(!err.is_empty());
    }

    #[test]
    fn compute_share_nullifier_hex_api_returns_hex() {
        let nullifier = compute_share_nullifier_hex(vec![1; 32], 3, vec![2; 32]).unwrap();

        assert_eq!(nullifier.len(), 64);
        assert!(nullifier.chars().all(|ch| ch.is_ascii_hexdigit()));
        assert_eq!(
            nullifier,
            "79d3c56235a9ba06ec95ce8e6d3c264a9b3d14777240c8e1e6a76ca4f885e51d"
        );
    }

    #[test]
    fn build_vote_commitments_rejects_invalid_network_before_db_work() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = build_vote_commitments(
            db_path.to_str().unwrap().to_string(),
            "wallet-1".to_string(),
            "bogus".to_string(),
            ROUND_ID.to_string(),
            0,
            vec![7; 32],
            ApiVanWitness {
                auth_path: vec![vec![1; 32]; 24],
                position: 0,
                anchor_height: 1,
            },
            vec![ApiDraftVote {
                proposal_id: 1,
                choice: 0,
                num_options: 2,
                vc_tree_position: 0,
                single_share: false,
            }],
        )
        .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    #[test]
    fn build_vote_commitments_rejects_invalid_witness_before_vote_work() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();
        state::init_voting_round(&db, &test_api_round_params().into(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.setup_bundles(ROUND_ID, &notes).unwrap();
        let err = build_vote_commitments(
            db_path.to_str().unwrap().to_string(),
            "wallet-1".to_string(),
            "regtest".to_string(),
            ROUND_ID.to_string(),
            0,
            vec![7; 32],
            ApiVanWitness {
                auth_path: vec![vec![1; 32]; 23],
                position: 0,
                anchor_height: 1,
            },
            vec![ApiDraftVote {
                proposal_id: 1,
                choice: 0,
                num_options: 2,
                vc_tree_position: 0,
                single_share: false,
            }],
        )
        .unwrap_err();

        assert!(err.contains("24 siblings"));
    }

    #[test]
    fn get_votes_api_preserves_bundle_and_proposal_keys() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), "wallet-api-votes").unwrap();
        state::init_voting_round(&db, &test_api_round_params().into(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.setup_bundles(ROUND_ID, &notes).unwrap();
        let conn = db.conn();
        zcash_voting::storage::queries::store_vote(
            &conn,
            ROUND_ID,
            "wallet-api-votes",
            0,
            1,
            0,
            b"vote-0",
        )
        .unwrap();
        zcash_voting::storage::queries::store_vote(
            &conn,
            ROUND_ID,
            "wallet-api-votes",
            1,
            2,
            1,
            b"vote-1",
        )
        .unwrap();
        drop(conn);

        let votes = get_votes(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-votes".to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();

        assert_eq!(votes.len(), 2);
        assert!(votes
            .iter()
            .any(|vote| vote.bundle_index == 0 && vote.proposal_id == 1 && vote.choice == 0));
        assert!(votes
            .iter()
            .any(|vote| vote.bundle_index == 1 && vote.proposal_id == 2 && vote.choice == 1));
    }

    #[test]
    fn recovery_api_preserves_round_summary_and_share_records() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let wallet_id = "wallet-api-recovery";
        let db = state::open_voting_db(db_path.to_str().unwrap(), wallet_id).unwrap();
        state::init_voting_round(&db, &test_api_round_params().into(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.setup_bundles(ROUND_ID, &notes).unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        let conn = db.conn();
        zcash_voting::storage::queries::store_vote(&conn, ROUND_ID, wallet_id, 1, 2, 1, b"vote-1")
            .unwrap();
        drop(conn);
        store_vote_tx_hash(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            1,
            2,
            "vote-tx-1-2".to_string(),
        )
        .unwrap();
        db.store_commitment_bundle(ROUND_ID, 1, 2, r#"{"bundle":"two"}"#, 99)
            .unwrap();
        record_share_delegation(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            1,
            2,
            0,
            vec!["https://helper.example".to_string()],
            vec![7; 32],
            123,
        )
        .unwrap();

        let state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();

        assert_eq!(state.bundle_count, 2);
        assert_eq!(state.delegation_tx_hashes[0].tx_hash, "delegation-tx-0");
        assert_eq!(state.votes[0].proposal_id, 2);
        assert_eq!(state.vote_tx_hashes[0].tx_hash, "vote-tx-1-2");
        assert_eq!(state.commitment_bundles[0].vc_tree_position, 99);
        assert_eq!(state.share_delegations[0].sent_to_urls.len(), 1);
        assert_eq!(state.unconfirmed_share_delegations.len(), 1);

        mark_share_confirmed(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
            1,
            2,
            0,
        )
        .unwrap();
        assert!(get_unconfirmed_share_delegations(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap()
        .is_empty());

        clear_recovery_state(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert!(get_share_delegations(
            db_path.to_str().unwrap().to_string(),
            wallet_id.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap()
        .is_empty());
    }

    #[test]
    fn select_voting_notes_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(select_voting_notes(
                db_path.to_str().unwrap().to_string(),
                "http://127.0.0.1:1".to_string(),
                "bogus".to_string(),
                "wallet-1".to_string(),
                100,
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    #[test]
    fn setup_delegation_bundles_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(setup_delegation_bundles(
                db_path.to_str().unwrap().to_string(),
                "http://127.0.0.1:1".to_string(),
                "bogus".to_string(),
                test_api_round_params(),
                "Demo".to_string(),
                None,
                "wallet-1".to_string(),
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    #[test]
    fn build_prove_and_sign_delegation_payload_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_prove_and_sign_delegation_payload(
                db_path.to_str().unwrap().to_string(),
                "http://127.0.0.1:1".to_string(),
                "http://127.0.0.1:2".to_string(),
                "bogus".to_string(),
                test_api_round_params(),
                "Demo".to_string(),
                None,
                "wallet-1".to_string(),
                vec![7; 32],
                0,
            ))
            .unwrap_err();

        assert!(err.contains("Unknown network"));
    }

    fn test_api_round_params() -> ApiVotingRoundParams {
        ApiVotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_tree_state(height: u64) -> TreeState {
        TreeState {
            network: "test".to_string(),
            height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
        }
    }

    fn test_note_ref(
        value_zatoshi: u64,
        voting_weight_zatoshi: u64,
        commitment_tree_position: u64,
    ) -> bundle::NoteRef {
        bundle::NoteRef {
            pool: "orchard".to_string(),
            txid_hex: hex::encode([commitment_tree_position as u8; 32]),
            output_index: commitment_tree_position as u32,
            value_zatoshi,
            voting_weight_zatoshi,
            commitment: vec![],
            nullifier: vec![],
            diversifier: vec![],
            rho: vec![],
            rseed: vec![],
            scope: 0,
            ufvk_str: String::new(),
            commitment_tree_position,
            mined_height: 1,
            anchor_height: 100,
        }
    }

    #[derive(Clone)]
    struct MockTreeBlock {
        height: u32,
        start_index: u64,
        leaf: String,
        root: String,
    }

    fn start_tree_server(height: u32, leaf_values: Vec<u64>, expected_requests: usize) -> String {
        let (latest_root, blocks) = mock_tree_blocks(&leaf_values);
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        thread::spawn(move || {
            for _ in 0..expected_requests {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0u8; 2048];
                let len = stream.read(&mut request).unwrap();
                let request = String::from_utf8_lossy(&request[..len]);
                let path = request
                    .lines()
                    .next()
                    .and_then(|line| line.split_whitespace().nth(1))
                    .unwrap_or("/");
                let body = tree_response_body(path, height, &latest_root, &blocks);
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                stream.write_all(response.as_bytes()).unwrap();
            }
        });
        url
    }

    fn tree_response_body(
        path: &str,
        height: u32,
        latest_root: &Option<String>,
        blocks: &[MockTreeBlock],
    ) -> String {
        if path.ends_with("/latest") {
            match latest_root {
                Some(root) => format!(
                    r#"{{"tree":{{"next_index":{},"root":"{}","height":{}}}}}"#,
                    blocks.len(),
                    root,
                    height
                ),
                None => format!(
                    r#"{{"tree":{{"next_index":{},"height":{}}}}}"#,
                    blocks.len(),
                    height
                ),
            }
        } else if path.contains("/leaves?") {
            if height == 0 || blocks.is_empty() {
                r#"{"blocks":[]}"#.to_string()
            } else {
                let from_height = query_u32(path, "from_height").unwrap_or(0);
                let to_height = query_u32(path, "to_height").unwrap_or(height);
                let Some(block) = blocks
                    .iter()
                    .find(|block| block.height >= from_height && block.height <= to_height)
                else {
                    return r#"{"blocks":[]}"#.to_string();
                };
                let next_from_height = blocks
                    .iter()
                    .find(|next| next.height > block.height && next.height <= to_height)
                    .map(|next| format!(r#","next_from_height":{}"#, next.height))
                    .unwrap_or_default();
                format!(
                    r#"{{"blocks":[{{"height":{},"start_index":{},"leaves":["{}"],"root":"{}"}}]{}}}"#,
                    block.height, block.start_index, block.leaf, block.root, next_from_height
                )
            }
        } else {
            r#"{"tree":null}"#.to_string()
        }
    }

    fn mock_tree_blocks(leaf_values: &[u64]) -> (Option<String>, Vec<MockTreeBlock>) {
        if leaf_values.is_empty() {
            return (None, vec![]);
        }

        let mut server = MemoryTreeServer::empty();
        let mut blocks = Vec::with_capacity(leaf_values.len());
        for (index, value) in leaf_values.iter().copied().enumerate() {
            let height = u32::try_from(index + 1).unwrap();
            server.append(Fp::from(value)).unwrap();
            server.checkpoint(height).unwrap();
            let root = server.root_at_height(height).unwrap();
            blocks.push(MockTreeBlock {
                height,
                start_index: u64::try_from(index).unwrap(),
                leaf: fp_base64(value),
                root: fp_base64_from_fp(root),
            });
        }

        let latest_root = blocks.last().map(|block| block.root.clone());
        (latest_root, blocks)
    }

    fn query_u32(path: &str, key: &str) -> Option<u32> {
        path.split('?').nth(1)?.split('&').find_map(|pair| {
            let (name, value) = pair.split_once('=')?;
            (name == key).then(|| value.parse().ok()).flatten()
        })
    }

    fn fp_base64(value: u64) -> String {
        fp_base64_from_fp(Fp::from(value))
    }

    fn fp_base64_from_fp(value: Fp) -> String {
        BASE64_STANDARD.encode(MerkleHashVote::from_fp(value).to_bytes())
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
