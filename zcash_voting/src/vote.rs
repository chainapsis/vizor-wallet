//! Stable cast-vote lifecycle API.
//!
//! This module owns the wallet-facing vote flow: build ZKP #2 for one
//! proposal, sign the cast-vote payload, persist crash-recovery material, and
//! reconstruct chain-ready submission fields.

#[allow(unused_imports)]
pub(crate) use crate::backend::{orchard, pasta_curves};
use serde::{Deserialize, Serialize};

use std::{
    collections::{BTreeSet, HashSet},
    sync::{
        atomic::{AtomicUsize, Ordering},
        Mutex,
    },
};

use rusqlite::{named_params, OptionalExtension, TransactionBehavior};

use crate::{
    round::VotingDb,
    types::{
        validate_proposal_id, validate_vote_decision, validate_vote_round_id_hex,
        CastVoteSignature, EncryptedShare, Network, ProgressReporter, SharePayload,
        VoteCommitmentBundle, VotingError, VotingHotkey, WireEncryptedShare,
    },
};

/// Number of siblings in a vote-authority-note witness.
pub const VAN_AUTH_PATH_LEN: usize = 24;

/// Default number of ZKP #2 builders allowed to run at once for one bundle.
pub const DEFAULT_BATCH_PROOF_CONCURRENCY: usize = 3;

/// Protocol maximum for the number of actions in one atomic vote batch.
pub const MAX_VOTE_BATCH_ACTIONS: usize = 15;

const VOTE_RECOVERY_FORMAT: &str = "zcash_voting_vote_recovery_v1";
const VOTE_BATCH_RECOVERY_FORMAT: &str = "zcash_voting_vote_batch_recovery_v1";

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

    let mut proposal_ids = HashSet::with_capacity(draft_votes.len());
    for draft in draft_votes {
        validate_draft_vote(draft)?;
        if !proposal_ids.insert(draft.proposal_id) {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "draft_votes contains duplicate proposal_id {}",
                    draft.proposal_id
                ),
            });
        }
    }

    Ok(())
}

/// Validates the one-draft contract of the historical batch-named singleton APIs.
///
/// Multiple singleton proofs built from one witness would spend the same current
/// VAN. Callers voting on multiple proposals must use the atomic batch API.
fn validate_legacy_singleton_batch(draft_votes: &[DraftVote]) -> Result<(), VotingError> {
    validate_draft_votes(draft_votes)?;
    validate_legacy_singleton_batch_len(draft_votes.len())
}

fn validate_legacy_singleton_batch_len(len: usize) -> Result<(), VotingError> {
    if len != 1 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "legacy singleton batch APIs require exactly one draft, got {len}; use commit_atomic_vote_batch for multiple drafts"
            ),
        });
    }
    Ok(())
}

fn validate_atomic_vote_batch(draft_votes: &[DraftVote]) -> Result<(), VotingError> {
    if draft_votes.len() > MAX_VOTE_BATCH_ACTIONS {
        return Err(VotingError::InvalidInput {
            message: format!(
                "atomic vote batch must contain at most {MAX_VOTE_BATCH_ACTIONS} actions, got {}",
                draft_votes.len()
            ),
        });
    }
    validate_draft_votes(draft_votes)
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
    share_payloads: Vec<SharePayload>,
}

/// Wallet-facing aggregate of one committed vote and its durable recovery data.
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
    pub anchor_height: u32,
    pub shares_hash: [u8; 32],
    pub share_comms: Vec<[u8; 32]>,
    pub r_vpk: [u8; 32],
    pub vote_auth_sig: [u8; 64],
    pub commitment_bundle_json: String,
}

/// One-item result from the historical batch-named singleton API.
///
/// The contained commitment is submitted through the singleton cast-vote endpoint.
#[derive(Clone, Debug)]
pub struct SignedVoteCommitments {
    pub bundle_index: u32,
    pub commitments: Vec<SignedVoteCommitment>,
}

/// One signed atomic vote batch ready for the batch transaction endpoint.
///
/// The digest and canonical request body are mandatory so an atomic batch
/// cannot be mistaken for a collection of singleton vote submissions.
#[derive(Clone, Debug)]
pub struct SignedVoteBatch {
    /// Delegation bundle that authorized every action.
    pub bundle_index: u32,
    /// Ordered commitments carried by the atomic transaction.
    pub commitments: Vec<SignedVoteCommitment>,
    /// Batch-wide digest signed by every commitment.
    pub batch_digest: [u8; 32],
    /// Canonical request body for the batch cast-vote endpoint.
    pub batch_json: String,
}

/// Unpersisted cast-vote work produced without holding the voting database lock.
///
/// This is an opaque, process-local handoff between [`prepare_commit`] and
/// [`persist_prepared_commit`]. It is intentionally not serializable.
pub struct PreparedVoteCommit {
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    draft: DraftVote,
    recovery: VoteRecoveryBundle,
    commit: VoteCommit,
    captured_state: CapturedVoteState,
}

enum CapturedVoteState {
    Fresh(crate::storage::queries::VotePreparationState),
    Recovered(crate::storage::queries::VoteRowState),
}

/// Opaque handoff for independently signed commitments prepared through the
/// historical batch API.
pub struct PreparedVoteCommitments {
    bundle_index: u32,
    commitments: Vec<PreparedVoteCommit>,
}

/// Unpersisted atomic cast-vote work for one delegation bundle.
pub struct PreparedAtomicVoteBatch {
    wallet_id: String,
    round_id: String,
    bundle_index: u32,
    commitments: Vec<PreparedVoteCommit>,
    batch_digest: [u8; 32],
    batch_json: String,
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
    commitment_bundle_json: String,
    commit: VoteCommit,
}

impl CommittedVote {
    /// Builds, signs, persists, and returns a committed cast-vote handle.
    ///
    /// Imported capability rounds require every delegation bundle to be
    /// confirmed before the first vote is committed.
    pub fn commit(
        db: &VotingDb,
        round_id: &str,
        bundle_index: u32,
        draft: &DraftVote,
        witness: &VanWitness,
        signer: VoteSigner<'_>,
        stages: &dyn crate::types::VoteCommitStageReporter,
    ) -> Result<Self, VotingError> {
        crate::vote::commit(db, round_id, bundle_index, draft, witness, signer, stages)?;
        Self::recover(db, round_id, bundle_index, draft.proposal_id)
    }

    /// Reconstructs a committed cast-vote handle from persisted recovery state.
    pub fn recover(
        db: &VotingDb,
        round_id: &str,
        bundle_index: u32,
        proposal_id: u32,
    ) -> Result<Self, VotingError> {
        let (commit, commitment_bundle_json) =
            recover_commit_with_generation(db, round_id, bundle_index, proposal_id)?;
        Ok(Self {
            round_id: round_id.to_string(),
            bundle_index,
            commitment_bundle_json,
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

    /// Returns the committed vote internals for crate-owned lifecycle work.
    #[cfg(test)]
    pub(crate) fn data(&self) -> &VoteCommit {
        &self.commit
    }

    #[cfg(test)]
    pub(crate) fn share_payloads_mut(&mut self) -> &mut [SharePayload] {
        &mut self.commit.share_payloads
    }

    /// Prepares and atomically persists the complete helper-share delivery plan.
    ///
    /// `params.proposal_ids` must be the complete proposal roster from the
    /// authenticated round configuration. Every proposal must have a durable
    /// terminal ballot intent; the SDK derives the round's immediate share.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] without persisting a plan when the
    /// roster is empty, duplicated, nonterminal, or differs from durable intent;
    /// when the committed vote is stale; or when an existing plan conflicts
    /// with the derived immediate designation or helper-placement policy.
    pub fn prepare_share_delivery(
        &self,
        db: &VotingDb,
        params: crate::share_tracking::ShareDeliveryPlanningParams<'_>,
    ) -> Result<crate::share_tracking::ShareDeliveryPlan, VotingError> {
        crate::share_tracking::prepare_share_delivery_plan(
            db,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            &self.commitment_bundle_json,
            &self.commit.share_payloads,
            params,
        )
    }

    /// Submits every incomplete helper share from the persisted complete plan.
    ///
    /// The complete plan and every helper payload are validated before the
    /// first POST. A process-wide semaphore enforces the SDK's exported helper
    /// concurrency policy across simultaneous wallets and committed votes. The
    /// plan retains its original target across fleet churn, but only helpers in
    /// `params.configured_server_urls` are eligible for delivery.
    /// This handle must match the exact durable recovery snapshot; recover a
    /// fresh `CommittedVote` after confirmation synchronizes a pre-confirmation
    /// plan to its confirmed VC tree position.
    pub async fn submit_prepared_shares(
        &self,
        db: &VotingDb,
        client: &crate::helper::client::HelperClient,
        params: crate::share_tracking::ShareDeliverySubmissionParams<'_>,
        cancel: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<crate::share_tracking::ShareBatchDeliveryReport, VotingError> {
        use futures_util::{stream, StreamExt as _};
        use std::sync::LazyLock;
        use std::time::Duration;
        use tokio::sync::Semaphore;

        const DELIVERY_PERMIT_CANCEL_CHECK_MILLISECONDS: u64 = 50;
        static DELIVERY_PERMITS: LazyLock<Semaphore> = LazyLock::new(|| {
            Semaphore::new(crate::share_policy::SHARE_HELPER_MAX_CONCURRENT_POSTS)
        });

        let scope = crate::share::ShareOperationScope::capture(db);
        let (plan, plan_generation) = crate::share_tracking::load_share_delivery_plan(
            db,
            &scope,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            &self.commitment_bundle_json,
            params.configured_server_urls,
            &self.commit.share_payloads,
        )?;

        let recovery = crate::recovery::helper_recovery_material_for_wallet(
            db,
            scope.wallet_id(),
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
        )?;
        let vc_tree_position = match recovery {
            crate::recovery::HelperRecoveryMaterial::Ready(bundle)
                if bundle.commitment_bundle_json == plan_generation =>
            {
                bundle.vc_tree_position
            }
            crate::recovery::HelperRecoveryMaterial::Ready(_) => {
                return Err(VotingError::InvalidInput {
                    message: "committed vote changed after loading its helper-share delivery plan"
                        .to_string(),
                })
            }
            crate::recovery::HelperRecoveryMaterial::AwaitingVcPosition => {
                return Err(VotingError::InvalidInput {
                    message: "committed vote must be confirmed before submitting helper shares"
                        .to_string(),
                })
            }
            crate::recovery::HelperRecoveryMaterial::Missing => {
                return Err(VotingError::Internal {
                    message: "committed vote is missing durable helper recovery material"
                        .to_string(),
                })
            }
        };
        for (payload, share_plan) in self.commit.share_payloads.iter().zip(&plan.share_plans) {
            payload.to_wire_json(Some(vc_tree_position), share_plan.submit_at)?;
        }

        let configured = params.configured_server_urls.to_vec();
        let planning_fleet = plan.configured_server_urls.clone();
        let now_seconds = params.now_seconds;
        let work = self
            .commit
            .share_payloads
            .iter()
            .zip(plan.share_plans.iter())
            .map(|(payload, share_plan)| (payload.enc_share.share_index, share_plan.clone()))
            .collect::<Vec<_>>();
        let deliveries = stream::iter(work)
            .map(|(share_index, share_plan)| {
                let configured = &configured;
                let planning_fleet = &planning_fleet;
                let plan_generation = &plan_generation;
                let scope = &scope;
                async move {
                    if cancel() {
                        return Ok(None);
                    }
                    let acquire_permit = DELIVERY_PERMITS.acquire();
                    tokio::pin!(acquire_permit);
                    let permit = loop {
                        if cancel() {
                            return Ok(None);
                        }
                        tokio::select! {
                            biased;
                            result = &mut acquire_permit => {
                                break result.map_err(|_| VotingError::Internal {
                                    message: "helper-share delivery semaphore closed".to_string(),
                                })?;
                            }
                            _ = tokio::time::sleep(Duration::from_millis(
                                DELIVERY_PERMIT_CANCEL_CHECK_MILLISECONDS,
                            )) => {}
                        }
                    };
                    if cancel() {
                        drop(permit);
                        return Ok(None);
                    }
                    let submission = self
                        .submit_share_to_helpers_for_generation(
                            db,
                            client,
                            crate::share_tracking::CommittedShareSubmissionRequest {
                                share_index,
                                plan: &share_plan,
                                planning_server_urls: planning_fleet,
                                configured_server_urls: configured,
                                now_seconds,
                            },
                            plan_generation,
                            scope,
                            cancel,
                        )
                        .await?;
                    drop(permit);
                    Ok(Some(crate::share_tracking::ShareDeliveryOutcome {
                        share_index,
                        submission,
                    }))
                }
            })
            .buffer_unordered(crate::share_policy::SHARE_HELPER_MAX_CONCURRENT_POSTS)
            .collect::<Vec<Result<Option<crate::share_tracking::ShareDeliveryOutcome>, VotingError>>>()
            .await;
        let mut completed = Vec::new();
        for delivery in deliveries {
            if let Some(delivery) = delivery? {
                completed.push(delivery);
            }
        }
        completed.sort_by_key(|delivery| delivery.share_index);
        let completed_indices = completed
            .iter()
            .map(|delivery| delivery.share_index)
            .collect::<std::collections::HashSet<_>>();
        let pending_share_indices = self
            .commit
            .share_payloads
            .iter()
            .map(|payload| payload.enc_share.share_index)
            .filter(|share_index| !completed_indices.contains(share_index))
            .collect();
        Ok(crate::share_tracking::ShareBatchDeliveryReport {
            deliveries: completed,
            pending_share_indices,
            cancelled: cancel(),
            placement_guarantee: plan.placement_guarantee,
        })
    }

    /// Submits one committed helper share using crate-owned durable journaling.
    ///
    /// The request selects only a share index and a planner-produced placement
    /// plan. Identity, payload bytes, nullifier material, placement target,
    /// and schedule are derived from this committed vote, so they cannot be
    /// supplied inconsistently. Every POST is reserved in storage before
    /// dispatch and its outcome is persisted before this future returns.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] before storage or network side
    /// effects when the fleet is empty, invalid, or duplicated; the plan does
    /// not match that fleet; the share index is absent; or this handle has been
    /// replaced by a newer committed vote. Storage and payload reconstruction
    /// failures are returned unchanged.
    #[cfg(test)]
    pub(crate) async fn submit_share_to_helpers_internal(
        &self,
        db: &VotingDb,
        client: &crate::helper::client::HelperClient,
        request: crate::share_tracking::CommittedShareSubmissionRequest<'_>,
        cancel: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<crate::share_tracking::ShareSubmissionReport, VotingError> {
        let scope = crate::share::ShareOperationScope::capture(db);
        self.submit_share_to_helpers_for_generation(
            db,
            client,
            request,
            &self.commitment_bundle_json,
            &scope,
            cancel,
        )
        .await
    }

    async fn submit_share_to_helpers_for_generation(
        &self,
        db: &VotingDb,
        client: &crate::helper::client::HelperClient,
        request: crate::share_tracking::CommittedShareSubmissionRequest<'_>,
        expected_commitment_bundle_json: &str,
        scope: &crate::share::ShareOperationScope,
        cancel: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<crate::share_tracking::ShareSubmissionReport, VotingError> {
        crate::share_tracking::submit_committed_share_to_helpers(
            db,
            client,
            &self.round_id,
            self.bundle_index,
            self.commit.proposal_id,
            &self.commit.vote_commitment,
            &self.commit.share_payloads,
            request,
            expected_commitment_bundle_json,
            scope,
            cancel,
        )
        .await
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
        signed_commitment_from_parts(&self.commit, &recovery)
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

fn signed_commitment_from_parts(
    commit: &VoteCommit,
    recovery: &VoteRecoveryBundle,
) -> Result<SignedVoteCommitment, VotingError> {
    Ok(SignedVoteCommitment {
        proposal_id: commit.proposal_id,
        choice: recovery.vote_decision,
        vote_round_id: recovery.vote_round_id.clone(),
        van_nullifier: commit.van_nullifier,
        vote_authority_note_new: commit.vote_authority_note_new,
        vote_commitment: commit.vote_commitment,
        proof: commit.proof.clone(),
        encrypted_shares: commit.encrypted_shares.clone(),
        anchor_height: commit.anchor_height,
        shares_hash: recovery.shares_hash,
        share_comms: recovery.share_comms.clone(),
        r_vpk: commit.r_vpk,
        vote_auth_sig: commit.vote_auth_sig,
        commitment_bundle_json: serialize_recovery(recovery)?,
    })
}

/// Inputs for the historical batch-named singleton preparation API.
///
/// `drafts` must contain exactly one item. Use [`AtomicVoteBatch`] for multiple
/// proposals submitted in one atomic transaction.
pub struct VoteCommitBatch<'a> {
    pub round_id: &'a str,
    pub bundle_index: u32,
    pub drafts: &'a [DraftVote],
    pub witness: &'a VanWitness,
    pub stages: &'a dyn crate::types::VoteCommitStageReporter,
}

/// Builds one signed singleton vote commitment under the historical batch name.
///
/// `drafts` must contain exactly one item because multiple singleton proofs from
/// one witness would spend the same current VAN. Use
/// [`commit_atomic_vote_batch`] for multiple proposals.
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
    validate_legacy_singleton_batch(drafts)?;
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

/// Builds and signs one singleton commitment without holding SQLite during
/// ZKP #2 computation.
///
/// `batch.drafts` must contain exactly one item. Use
/// [`prepare_atomic_vote_batch`] for multiple proposals.
pub fn prepare_commit_batch(
    db: &VotingDb,
    signer: VoteSigner<'_>,
    batch: VoteCommitBatch<'_>,
) -> Result<PreparedVoteCommitments, VotingError> {
    validate_legacy_singleton_batch(batch.drafts)?;
    let bundle_count = db.get_bundle_count(batch.round_id)?;
    crate::round::validate_bundle_index(bundle_count, batch.bundle_index, "voting")?;

    let mut commitments = Vec::with_capacity(batch.drafts.len());
    for draft in batch.drafts {
        commitments.push(prepare_commit(
            db,
            batch.round_id,
            batch.bundle_index,
            draft,
            batch.witness,
            signer,
            batch.stages,
        )?);
    }

    Ok(PreparedVoteCommitments {
        bundle_index: batch.bundle_index,
        commitments,
    })
}

/// Persists the one commitment prepared through [`prepare_commit_batch`].
pub fn persist_prepared_commit_batch(
    db: &VotingDb,
    prepared: PreparedVoteCommitments,
) -> Result<SignedVoteCommitments, VotingError> {
    validate_legacy_singleton_batch_len(prepared.commitments.len())?;
    let mut commitments = Vec::with_capacity(prepared.commitments.len());
    for prepared_commit in prepared.commitments {
        let committed = persist_prepared_commit(db, prepared_commit)?;
        commitments.push(committed.signed_commitment(db)?);
    }
    Ok(SignedVoteCommitments {
        bundle_index: prepared.bundle_index,
        commitments,
    })
}

/// Builds, signs, and persists one atomic vote batch with default proof
/// concurrency.
#[allow(clippy::too_many_arguments)]
pub fn commit_atomic_vote_batch(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    drafts: &[DraftVote],
    witness: &VanWitness,
    signer: VoteSigner<'_>,
    stages: &dyn crate::types::VoteCommitStageReporter,
) -> Result<SignedVoteBatch, VotingError> {
    let prepared = prepare_atomic_vote_batch(
        db,
        signer,
        AtomicVoteBatch::new(round_id, bundle_index, drafts, witness, stages),
    )?;
    persist_prepared_atomic_vote_batch(db, prepared)
}

/// Inputs for preparing one atomic vote batch.
pub struct AtomicVoteBatch<'a> {
    round_id: &'a str,
    bundle_index: u32,
    drafts: &'a [DraftVote],
    witness: &'a VanWitness,
    stages: &'a dyn crate::types::VoteCommitStageReporter,
    max_proof_concurrency: usize,
}

impl<'a> AtomicVoteBatch<'a> {
    /// Creates an atomic batch using [`DEFAULT_BATCH_PROOF_CONCURRENCY`].
    pub fn new(
        round_id: &'a str,
        bundle_index: u32,
        drafts: &'a [DraftVote],
        witness: &'a VanWitness,
        stages: &'a dyn crate::types::VoteCommitStageReporter,
    ) -> Self {
        Self {
            round_id,
            bundle_index,
            drafts,
            witness,
            stages,
            max_proof_concurrency: DEFAULT_BATCH_PROOF_CONCURRENCY,
        }
    }

    /// Overrides the maximum number of ZKP #2 builders that may run at once.
    pub fn with_max_proof_concurrency(
        mut self,
        max_proof_concurrency: usize,
    ) -> Result<Self, VotingError> {
        if max_proof_concurrency == 0 {
            return Err(VotingError::InvalidInput {
                message: "max_proof_concurrency must be at least 1".to_string(),
            });
        }
        self.max_proof_concurrency = max_proof_concurrency;
        Ok(self)
    }
}

/// Builds and signs an atomic batch without holding SQLite during ZKP #2
/// computation.
pub fn prepare_atomic_vote_batch(
    db: &VotingDb,
    signer: VoteSigner<'_>,
    batch: AtomicVoteBatch<'_>,
) -> Result<PreparedAtomicVoteBatch, VotingError> {
    validate_atomic_vote_batch(batch.drafts)?;
    let bundle_count = db.get_bundle_count(batch.round_id)?;
    crate::round::validate_bundle_index(bundle_count, batch.bundle_index, "voting")?;
    let (secret, network) = signer_secret_and_network(signer);
    db.require_round_network(batch.round_id, network, "vote signer")?;
    let wallet_id = db.wallet_id();

    // Capture every proposal row under one read transaction. The proofs run
    // after this transaction is released and persistence revalidates the same
    // snapshots under one Immediate write transaction.
    let (captured, recovered) = {
        let mut conn = db.conn();
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("failed to begin vote batch preparation transaction: {e}"),
        })?;
        let mut recoveries = Vec::with_capacity(batch.drafts.len());
        for draft in batch.drafts {
            recoveries.push(recovery_bundle_with_conn(
                &tx,
                &wallet_id,
                batch.round_id,
                batch.bundle_index,
                draft.proposal_id,
            )?);
        }
        let recovered_count = recoveries
            .iter()
            .filter(|recovery| recovery.is_some())
            .count();
        if recovered_count != 0 && recovered_count != recoveries.len() {
            return Err(VotingError::InvalidInput {
                message: "found a partial persisted vote batch; recover or clear the inconsistent local state before rebuilding".to_string(),
            });
        }
        let proposal_ids = batch
            .drafts
            .iter()
            .map(|draft| draft.proposal_id)
            .collect::<Vec<_>>();
        if recovered_count == 0 {
            ensure_no_competing_pending_vote_chain_with_conn(
                &tx,
                &wallet_id,
                batch.round_id,
                batch.bundle_index,
                &proposal_ids,
            )?;
        }
        let (captured, recovered) = if recovered_count == recoveries.len() {
            let recovered = batch
                .drafts
                .iter()
                .zip(recoveries)
                .map(|(draft, recovery)| {
                    let vote = crate::storage::queries::load_vote_row_state(
                        &tx,
                        batch.round_id,
                        &wallet_id,
                        batch.bundle_index,
                        draft.proposal_id,
                    )?
                    .ok_or_else(|| {
                        vote_not_found_error(batch.round_id, batch.bundle_index, draft.proposal_id)
                    })?;
                    Ok((vote, recovery.expect("all recovery rows were counted")))
                })
                .collect::<Result<Vec<_>, VotingError>>()?;
            (Vec::new(), Some(recovered))
        } else {
            let captured = batch
                .drafts
                .iter()
                .map(|draft| {
                    crate::storage::queries::load_vote_preparation_state(
                        &tx,
                        batch.round_id,
                        &wallet_id,
                        batch.bundle_index,
                        draft.proposal_id,
                    )
                })
                .collect::<Result<Vec<_>, VotingError>>()?;
            (captured, None)
        };
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("failed to finish vote batch preparation transaction: {e}"),
        })?;
        (captured, recovered)
    };

    if let Some(recovered) = recovered {
        return prepare_recovered_vote_batch(
            &wallet_id,
            batch.round_id,
            batch.bundle_index,
            batch.drafts,
            recovered,
        );
    }

    db.require_capability_delegations_confirmed(batch.round_id)?;
    for draft in batch.drafts {
        ensure_vote_rebuild_allowed(db, batch.round_id, batch.bundle_index, draft.proposal_id)?;
    }
    validate_captured_batch_state(
        batch.round_id,
        batch.bundle_index,
        batch.drafts,
        batch.witness,
        network,
        &captured,
    )?;

    let first_state = &captured[0];
    let round_id_bytes =
        hex::decode(&first_state.zkp2.voting_round_id).map_err(|e| VotingError::Internal {
            message: format!(
                "invalid voting_round_id hex '{}': {e}",
                first_state.zkp2.voting_round_id
            ),
        })?;
    let mut authority = first_state.zkp2.proposal_authority;
    let mut proof_plans = Vec::with_capacity(batch.drafts.len());
    for (index, (draft, state)) in batch.drafts.iter().zip(captured.iter()).enumerate() {
        let transition = crate::zkp2::plan_vote_authority_transition(
            secret,
            network,
            state.zkp2.address_index,
            state.zkp2.total_note_value,
            &state.zkp2.gov_comm_rand,
            &round_id_bytes,
            draft.proposal_id,
            authority,
        )?;
        authority = transition.proposal_authority_new;
        let (auth_path, position) = if index == 0 {
            (batch.witness.auth_path_fixed()?, batch.witness.position)
        } else {
            (
                single_leaf_auth_path(transition.vote_authority_note_old)?,
                0,
            )
        };
        proof_plans.push(BatchProofPlan {
            draft: draft.clone(),
            state: state.clone(),
            auth_path,
            position,
            proposal_authority: transition.proposal_authority_old,
            expected_new_van: transition.vote_authority_note_new,
        });
    }

    let bundles = build_batch_proofs(
        secret,
        batch.bundle_index,
        batch.witness.anchor_height,
        &round_id_bytes,
        batch.stages,
        batch.max_proof_concurrency.min(MAX_VOTE_BATCH_ACTIONS),
        &proof_plans,
    )?;

    let sighash_actions = bundles
        .iter()
        .map(
            |bundle| crate::vote_commitment::CastVoteBatchSighashAction {
                r_vpk: &bundle.r_vpk_bytes,
                van_nullifier: &bundle.van_nullifier,
                vote_authority_note_new: &bundle.vote_authority_note_new,
                vote_commitment: &bundle.vote_commitment,
                proposal_id: bundle.proposal_id,
            },
        )
        .collect::<Vec<_>>();
    let batch_digest = crate::vote_commitment::cast_vote_batch_sighash(
        batch.round_id,
        batch.witness.anchor_height as u64,
        &sighash_actions,
    )?;

    let batch_size = u32::try_from(batch.drafts.len()).map_err(|_| VotingError::Internal {
        message: "vote batch length does not fit in u32".to_string(),
    })?;
    let mut commitments = Vec::with_capacity(batch.drafts.len());
    for (index, (plan, bundle)) in proof_plans.into_iter().zip(bundles).enumerate() {
        let wire_shares = bundle
            .enc_shares
            .iter()
            .map(WireEncryptedShare::from)
            .collect::<Vec<_>>();
        batch
            .stages
            .on_stage(VoteCommitStage::SharePayloadsBuilding {
                proposal_id: plan.draft.proposal_id,
                bundle_index: batch.bundle_index,
            });
        let share_payloads = db.build_share_payloads(
            &wire_shares,
            &bundle,
            plan.draft.choice,
            plan.draft.num_options,
            plan.draft.vc_tree_position,
            plan.draft.single_share,
        )?;
        batch.stages.on_stage(VoteCommitStage::Signing {
            proposal_id: plan.draft.proposal_id,
            bundle_index: batch.bundle_index,
        });
        let signature = crate::vote_commitment::sign_cast_vote_digest(
            secret,
            network,
            &batch_digest,
            &bundle.alpha_v,
        )?;
        let vote_auth_sig = array64("vote_auth_sig", signature.vote_auth_sig)?;
        let mut recovery =
            VoteRecoveryBundle::from_parts(batch.bundle_index, &plan.draft, bundle, vote_auth_sig)?;
        recovery.batch = Some(VoteBatchRecovery {
            digest: batch_digest,
            index: index as u32,
            size: batch_size,
        });
        let commit = commit_from_recovery(&recovery)?;
        commitments.push(PreparedVoteCommit {
            wallet_id: wallet_id.clone(),
            round_id: batch.round_id.to_string(),
            bundle_index: batch.bundle_index,
            draft: plan.draft,
            recovery,
            commit: VoteCommit {
                encrypted_shares: wire_shares,
                share_payloads,
                ..commit
            },
            captured_state: CapturedVoteState::Fresh(plan.state),
        });
    }

    let batch_json = canonical_batch_json(&commitments)?;
    Ok(PreparedAtomicVoteBatch {
        wallet_id,
        round_id: batch.round_id.to_string(),
        bundle_index: batch.bundle_index,
        commitments,
        batch_digest,
        batch_json,
    })
}

/// Atomically persists the complete batch after revalidating every captured row.
/// All fallible return-payload construction happens before the write commits.
pub fn persist_prepared_atomic_vote_batch(
    db: &VotingDb,
    prepared: PreparedAtomicVoteBatch,
) -> Result<SignedVoteBatch, VotingError> {
    persist_prepared_atomic_vote_batch_inner(db, prepared, || {})
}

fn persist_prepared_atomic_vote_batch_inner<F>(
    db: &VotingDb,
    prepared: PreparedAtomicVoteBatch,
    after_persist: F,
) -> Result<SignedVoteBatch, VotingError>
where
    F: FnOnce(),
{
    let PreparedAtomicVoteBatch {
        wallet_id,
        round_id,
        bundle_index,
        commitments: prepared_commits,
        batch_digest,
        batch_json,
    } = prepared;
    if prepared_commits.iter().any(|prepared| {
        prepared.wallet_id != wallet_id
            || prepared.round_id != round_id
            || prepared.bundle_index != bundle_index
    }) {
        return Err(VotingError::Internal {
            message: "prepared vote batch contains mismatched storage identities".to_string(),
        });
    }
    let commitments = prepared_commits
        .iter()
        .map(|prepared| signed_commitment_from_parts(&prepared.commit, &prepared.recovery))
        .collect::<Result<Vec<_>, _>>()?;
    persist_prepared_commits(db, prepared_commits)?;
    after_persist();
    Ok(SignedVoteBatch {
        bundle_index,
        commitments,
        batch_digest,
        batch_json,
    })
}

/// Recovers one persisted vote commitment as a single-item batch result.
pub fn recover_signed_commitments(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<SignedVoteCommitments, VotingError> {
    let requested = recovery_bundle(db, round_id, bundle_index, proposal_id)?.ok_or_else(|| {
        VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        }
    })?;
    if requested.batch.is_some() {
        return Err(VotingError::InvalidInput {
            message: "vote belongs to an atomic batch; use recover_atomic_vote_batch".to_string(),
        });
    }
    let committed = CommittedVote::recover(db, round_id, bundle_index, proposal_id)?;
    Ok(SignedVoteCommitments {
        bundle_index,
        commitments: vec![committed.signed_commitment(db)?],
    })
}

/// Recovers the complete atomic batch containing `proposal_id`.
pub fn recover_atomic_vote_batch(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<SignedVoteBatch, VotingError> {
    let requested = recovery_bundle(db, round_id, bundle_index, proposal_id)?.ok_or_else(|| {
        VotingError::InvalidInput {
            message: format!(
                "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        }
    })?;
    let batch = requested
        .batch
        .as_ref()
        .ok_or_else(|| VotingError::InvalidInput {
            message: "vote is a singleton; use recover_signed_commitments".to_string(),
        })?;
    let digest = batch.digest;
    let recoveries = {
        let conn = db.conn();
        load_vote_batch_recoveries_with_conn(
            &conn,
            &db.wallet_id(),
            round_id,
            bundle_index,
            digest,
        )?
    };
    let mut commitments = Vec::with_capacity(recoveries.len());
    for recovery in &recoveries {
        let commit = commit_from_recovery(recovery)?;
        commitments.push(signed_commitment_from_parts(&commit, recovery)?);
    }
    let batch_json = crate::wire::VoteCommitmentBatchWire {
        votes: commitments
            .iter()
            .map(crate::wire::VoteCommitmentWire::try_from)
            .collect::<Result<Vec<_>, _>>()?,
    }
    .to_json()?;
    Ok(SignedVoteBatch {
        bundle_index,
        commitments,
        batch_digest: digest,
        batch_json,
    })
}

#[derive(Clone)]
struct BatchProofPlan {
    draft: DraftVote,
    state: crate::storage::queries::VotePreparationState,
    auth_path: [[u8; 32]; VAN_AUTH_PATH_LEN],
    position: u32,
    proposal_authority: u64,
    expected_new_van: [u8; 32],
}

fn validate_captured_batch_state(
    round_id: &str,
    bundle_index: u32,
    drafts: &[DraftVote],
    witness: &VanWitness,
    network: Network,
    captured: &[crate::storage::queries::VotePreparationState],
) -> Result<(), VotingError> {
    let first = &captured[0];
    if first.van_position != witness.position {
        return Err(VotingError::InvalidInput {
            message: format!(
                "VAN witness position {} does not match current bundle position {} for round={round_id}, bundle={bundle_index}",
                witness.position, first.van_position
            ),
        });
    }
    for (draft, state) in drafts.iter().zip(captured) {
        if state.network != network
            || state.zkp2 != first.zkp2
            || state.van_position != first.van_position
        {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "vote batch state is inconsistent for round={round_id}, bundle={bundle_index}, proposal={}",
                    draft.proposal_id
                ),
            });
        }
        if let Some((skipped, intent_choice)) = state.ballot_intent {
            if skipped || intent_choice != Some(draft.choice) {
                return Err(VotingError::InvalidInput {
                    message: format!(
                        "vote draft conflicts with current ballot intent for round={round_id}, bundle={bundle_index}, proposal={}",
                        draft.proposal_id
                    ),
                });
            }
        }
    }
    Ok(())
}

fn single_leaf_auth_path(
    leaf_bytes: [u8; 32],
) -> Result<[[u8; 32]; VAN_AUTH_PATH_LEN], VotingError> {
    use pasta_curves::group::ff::PrimeField;

    let leaf =
        Option::from(pasta_curves::pallas::Base::from_repr(leaf_bytes)).ok_or_else(|| {
            VotingError::Internal {
                message: "planned VAN is not a canonical Pallas field element".to_string(),
            }
        })?;
    let mut tree = vote_commitment_tree::MemoryTreeServer::empty();
    tree.append(leaf).map_err(|e| VotingError::Internal {
        message: format!("build synthetic vote tree failed: {e:?}"),
    })?;
    tree.checkpoint(1).map_err(|e| VotingError::Internal {
        message: format!("checkpoint synthetic vote tree failed: {e:?}"),
    })?;
    let path = tree.path(0, 1).ok_or_else(|| VotingError::Internal {
        message: "synthetic vote tree did not produce its single-leaf path".to_string(),
    })?;
    let mut auth_path = [[0u8; 32]; VAN_AUTH_PATH_LEN];
    for (output, sibling) in auth_path.iter_mut().zip(path.auth_path()) {
        *output = sibling.to_bytes();
    }
    Ok(auth_path)
}

#[allow(clippy::too_many_arguments)]
fn build_batch_proofs(
    hotkey_seed: &[u8],
    bundle_index: u32,
    anchor_height: u32,
    round_id_bytes: &[u8],
    stages: &dyn crate::types::VoteCommitStageReporter,
    max_concurrency: usize,
    plans: &[BatchProofPlan],
) -> Result<Vec<VoteCommitmentBundle>, VotingError> {
    let next = AtomicUsize::new(0);
    let results = Mutex::new(
        (0..plans.len())
            .map(|_| None)
            .collect::<Vec<Option<Result<VoteCommitmentBundle, VotingError>>>>(),
    );
    let worker_count = max_concurrency.max(1).min(plans.len());
    std::thread::scope(|scope| -> Result<(), VotingError> {
        let mut workers = Vec::with_capacity(worker_count);
        for _ in 0..worker_count {
            workers.push(scope.spawn(|| {
                loop {
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    let Some(plan) = plans.get(index) else {
                        break;
                    };
                    stages.on_stage(VoteCommitStage::ProofStarting {
                        proposal_id: plan.draft.proposal_id,
                        bundle_index,
                    });
                    let progress = VoteProofProgressReporter {
                        proposal_id: plan.draft.proposal_id,
                        bundle_index,
                        stages,
                    };
                    let result = crate::zkp2::build_vote_commitment(
                        hotkey_seed,
                        plan.state.network,
                        plan.state.zkp2.address_index,
                        plan.state.zkp2.total_note_value,
                        &plan.state.zkp2.gov_comm_rand,
                        round_id_bytes,
                        &plan.state.zkp2.ea_pk,
                        plan.draft.proposal_id,
                        plan.draft.choice,
                        plan.draft.num_options,
                        &plan.auth_path,
                        plan.position,
                        anchor_height,
                        plan.proposal_authority,
                        plan.draft.single_share,
                        &progress,
                    )
                    .and_then(|bundle| {
                        if bundle.vote_authority_note_new != plan.expected_new_van {
                            return Err(VotingError::Internal {
                                message: format!(
                                    "proof output disagrees with preplanned authority transition for proposal {}",
                                    plan.draft.proposal_id
                                ),
                            });
                        }
                        Ok(bundle)
                    });
                    results.lock().expect("batch proof result mutex poisoned")[index] =
                        Some(result);
                }
            }));
        }
        for worker in workers {
            worker.join().map_err(|_| VotingError::Internal {
                message: "vote batch proof worker panicked".to_string(),
            })?;
        }
        Ok(())
    })?;

    results
        .into_inner()
        .map_err(|_| VotingError::Internal {
            message: "batch proof result mutex poisoned".to_string(),
        })?
        .into_iter()
        .enumerate()
        .map(|(index, result)| {
            result.ok_or_else(|| VotingError::Internal {
                message: format!("vote batch proof worker omitted action {index}"),
            })?
        })
        .collect()
}

fn prepare_recovered_vote_batch(
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    drafts: &[DraftVote],
    captured: Vec<(crate::storage::queries::VoteRowState, VoteRecoveryBundle)>,
) -> Result<PreparedAtomicVoteBatch, VotingError> {
    let size = u32::try_from(drafts.len()).map_err(|_| VotingError::Internal {
        message: "vote batch length does not fit in u32".to_string(),
    })?;
    let mut commitments = Vec::with_capacity(drafts.len());
    let mut expected_digest = None;
    for (index, (draft, (captured_vote, recovery))) in drafts.iter().zip(captured).enumerate() {
        if !recovery_matches_draft(&recovery, draft) {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "persisted vote recovery does not match the requested draft for proposal {}",
                    draft.proposal_id
                ),
            });
        }
        let metadata = recovery
            .batch
            .as_ref()
            .ok_or_else(|| VotingError::InvalidInput {
                message: format!(
                    "persisted proposal {} is a legacy singleton, not an atomic vote batch",
                    draft.proposal_id
                ),
            })?;
        if metadata.index != index as u32 || metadata.size != size {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "persisted vote batch order is inconsistent at proposal {}",
                    draft.proposal_id
                ),
            });
        }
        if expected_digest
            .replace(metadata.digest)
            .is_some_and(|digest| digest != metadata.digest)
        {
            return Err(VotingError::InvalidInput {
                message: "persisted vote batch actions have different digests".to_string(),
            });
        }
        commitments.push(PreparedVoteCommit {
            wallet_id: wallet_id.to_string(),
            round_id: round_id.to_string(),
            bundle_index,
            draft: draft.clone(),
            commit: commit_from_recovery(&recovery)?,
            recovery,
            captured_state: CapturedVoteState::Recovered(captured_vote),
        });
    }
    let batch_digest = expected_digest.expect("non-empty batch has a digest");
    let recomputed = batch_sighash_for_prepared(&commitments)?;
    if recomputed != batch_digest {
        return Err(VotingError::InvalidInput {
            message: "persisted vote batch digest does not match its ordered actions".to_string(),
        });
    }
    let batch_json = canonical_batch_json(&commitments)?;
    Ok(PreparedAtomicVoteBatch {
        wallet_id: wallet_id.to_string(),
        round_id: round_id.to_string(),
        bundle_index,
        commitments,
        batch_digest,
        batch_json,
    })
}

fn batch_sighash_for_prepared(commitments: &[PreparedVoteCommit]) -> Result<[u8; 32], VotingError> {
    let first = commitments.first().ok_or_else(|| VotingError::Internal {
        message: "cannot hash an empty prepared vote batch".to_string(),
    })?;
    let actions = commitments
        .iter()
        .map(
            |prepared| crate::vote_commitment::CastVoteBatchSighashAction {
                r_vpk: &prepared.commit.r_vpk,
                van_nullifier: &prepared.commit.van_nullifier,
                vote_authority_note_new: &prepared.commit.vote_authority_note_new,
                vote_commitment: &prepared.commit.vote_commitment,
                proposal_id: prepared.commit.proposal_id,
            },
        )
        .collect::<Vec<_>>();
    crate::vote_commitment::cast_vote_batch_sighash(
        &first.round_id,
        first.commit.anchor_height as u64,
        &actions,
    )
}

fn canonical_batch_json(commitments: &[PreparedVoteCommit]) -> Result<String, VotingError> {
    let votes = commitments
        .iter()
        .map(|prepared| {
            signed_commitment_from_parts(&prepared.commit, &prepared.recovery)
                .and_then(|signed| crate::wire::VoteCommitmentWire::try_from(&signed))
        })
        .collect::<Result<Vec<_>, _>>()?;
    crate::wire::VoteCommitmentBatchWire { votes }.to_json()
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
    /// Present when this vote is one ordered action in an atomic batch.
    pub batch: Option<VoteBatchRecovery>,
}

/// Stable recovery metadata shared by actions in one atomic vote batch.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteBatchRecovery {
    pub digest: [u8; 32],
    pub index: u32,
    pub size: u32,
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
    #[serde(default)]
    batch_digest: Option<Vec<u8>>,
    #[serde(default)]
    batch_index: Option<u32>,
    #[serde(default)]
    batch_size: Option<u32>,
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
/// Fresh votes in an imported capability round require every delegation bundle
/// to have a recorded confirmation.
pub fn commit(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    draft: &DraftVote,
    witness: &VanWitness,
    signer: VoteSigner<'_>,
    stages: &dyn crate::types::VoteCommitStageReporter,
) -> Result<VoteCommit, VotingError> {
    let prepared = prepare_commit(db, round_id, bundle_index, draft, witness, signer, stages)?;
    Ok(persist_prepared_commit(db, prepared)?.commit)
}

/// Builds and signs one vote while keeping the SQLite mutation window short.
///
/// A bundle cannot start another vote chain while one remains unconfirmed.
#[allow(clippy::too_many_arguments)]
pub fn prepare_commit(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    draft: &DraftVote,
    witness: &VanWitness,
    signer: VoteSigner<'_>,
    stages: &dyn crate::types::VoteCommitStageReporter,
) -> Result<PreparedVoteCommit, VotingError> {
    validate_draft_vote(draft)?;

    let (secret, network) = signer_secret_and_network(signer);
    db.require_round_network(round_id, network, "vote signer")?;

    let wallet_id = db.wallet_id();
    let recovered = {
        let mut conn = db.conn();
        let tx = conn.transaction().map_err(|e| VotingError::Internal {
            message: format!("failed to begin recovered vote preparation transaction: {e}"),
        })?;
        let recovered =
            recovery_bundle_with_conn(&tx, &wallet_id, round_id, bundle_index, draft.proposal_id)?;
        if let Some(recovered) = recovered.as_ref() {
            ensure_singleton_vote_recovery(recovered)?;
        }
        let recovered = recovered
            .filter(|recovered| recovery_matches_draft(recovered, draft))
            .map(|recovered| {
                let state = crate::storage::queries::load_vote_row_state(
                    &tx,
                    round_id,
                    &wallet_id,
                    bundle_index,
                    draft.proposal_id,
                )?
                .ok_or_else(|| vote_not_found_error(round_id, bundle_index, draft.proposal_id))?;
                Ok((recovered, CapturedVoteState::Recovered(state)))
            })
            .transpose()?;
        if recovered.is_none() {
            ensure_no_competing_pending_vote_chain_with_conn(
                &tx,
                &wallet_id,
                round_id,
                bundle_index,
                &[draft.proposal_id],
            )?;
        }
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("failed to finish recovered vote preparation transaction: {e}"),
        })?;
        recovered
    };
    if let Some((recovered, captured_state)) = recovered {
        return Ok(PreparedVoteCommit {
            wallet_id,
            round_id: round_id.to_string(),
            bundle_index,
            draft: draft.clone(),
            commit: commit_from_recovery(&recovered)?,
            recovery: recovered,
            captured_state,
        });
    }
    db.require_capability_delegations_confirmed(round_id)?;
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
    let prepared_proof = db.prepare_vote_commitment(
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
    let bundle = prepared_proof.bundle;
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
    let commit = VoteCommit {
        proposal_id: draft.proposal_id,
        van_nullifier: recovery.van_nullifier,
        vote_authority_note_new: recovery.vote_authority_note_new,
        vote_commitment: recovery.vote_commitment,
        proof: recovery.proof.clone(),
        anchor_height: recovery.anchor_height,
        r_vpk: recovery.r_vpk,
        vote_auth_sig: recovery.vote_auth_sig,
        encrypted_shares: wire_shares,
        share_payloads,
    };

    Ok(PreparedVoteCommit {
        wallet_id: prepared_proof.wallet_id,
        round_id: round_id.to_string(),
        bundle_index,
        draft: draft.clone(),
        recovery,
        commit,
        captured_state: CapturedVoteState::Fresh(prepared_proof.state),
    })
}

/// Persists one prepared vote in a transaction after optimistic revalidation.
pub fn persist_prepared_commit(
    db: &VotingDb,
    prepared: PreparedVoteCommit,
) -> Result<CommittedVote, VotingError> {
    persist_prepared_commits(db, vec![prepared])?
        .pop()
        .ok_or_else(|| VotingError::Internal {
            message: "single prepared vote persistence returned no vote".to_string(),
        })
}

fn persist_prepared_commits(
    db: &VotingDb,
    prepared: Vec<PreparedVoteCommit>,
) -> Result<Vec<CommittedVote>, VotingError> {
    if prepared.is_empty() {
        return Err(VotingError::Internal {
            message: "cannot persist an empty prepared vote set".to_string(),
        });
    }
    let current_wallet_id = db.wallet_id();
    for vote in &prepared {
        if current_wallet_id != vote.wallet_id {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "wallet identity changed while preparing vote for round={}, bundle={}, proposal={}; recompute for the current wallet",
                    vote.round_id, vote.bundle_index, vote.draft.proposal_id
                ),
            });
        }
    }
    let mut conn = db.conn();
    // Immediate takes the write lock before the optimistic re-read so a concurrent
    // writer cannot make the snapshot look fresh and then fail the later write with
    // SQLITE_BUSY (which WAL often returns without waiting out busy_timeout).
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("failed to begin prepared vote persistence transaction: {e}"),
        })?;
    let fresh_proposal_ids = prepared
        .iter()
        .filter(|vote| matches!(&vote.captured_state, CapturedVoteState::Fresh(_)))
        .map(|vote| vote.draft.proposal_id)
        .collect::<Vec<_>>();
    if let Some(first_fresh) = prepared
        .iter()
        .find(|vote| matches!(&vote.captured_state, CapturedVoteState::Fresh(_)))
    {
        ensure_no_competing_pending_vote_chain_with_conn(
            &tx,
            &first_fresh.wallet_id,
            &first_fresh.round_id,
            first_fresh.bundle_index,
            &fresh_proposal_ids,
        )?;
    }
    let mut stored_fresh_vote = false;
    for vote in &prepared {
        match &vote.captured_state {
            CapturedVoteState::Recovered(captured_vote) => {
                let current_vote = crate::storage::queries::load_vote_row_state(
                    &tx,
                    &vote.round_id,
                    &vote.wallet_id,
                    vote.bundle_index,
                    vote.draft.proposal_id,
                )?;
                if current_vote.as_ref() != Some(captured_vote) {
                    return Err(VotingError::InvalidInput {
                        message: format!(
                            "recovered vote state changed while preparing vote for round={}, bundle={}, proposal={}; recover from current state",
                            vote.round_id, vote.bundle_index, vote.draft.proposal_id
                        ),
                    });
                }
            }
            CapturedVoteState::Fresh(captured_state) => {
                let current_state = crate::storage::queries::load_vote_preparation_state(
                    &tx,
                    &vote.round_id,
                    &vote.wallet_id,
                    vote.bundle_index,
                    vote.draft.proposal_id,
                )?;
                validate_prepared_vote_state(
                    &vote.round_id,
                    vote.bundle_index,
                    vote.draft.proposal_id,
                    captured_state,
                    &current_state,
                )?;
                let commitment_bytes = stored_vote_commitment_bytes(&vote.recovery)?;
                let recovery_json = serialize_recovery(&vote.recovery)?;
                crate::storage::queries::store_vote(
                    &tx,
                    &vote.round_id,
                    &vote.wallet_id,
                    vote.bundle_index,
                    vote.draft.proposal_id,
                    vote.draft.choice,
                    &commitment_bytes,
                )?;
                store_recovery_json_for_vote_with_conn(
                    &tx,
                    VoteRecoveryStorageIdentity {
                        round_id: &vote.round_id,
                        wallet_id: &vote.wallet_id,
                        bundle_index: vote.bundle_index,
                        proposal_id: vote.draft.proposal_id,
                        choice: vote.draft.choice,
                        commitment: Some(&commitment_bytes),
                    },
                    &recovery_json,
                )?;
                stored_fresh_vote = true;
            }
        }
    }
    if stored_fresh_vote {
        let first = &prepared[0];
        crate::storage::queries::advance_round_phase(
            &tx,
            &first.round_id,
            &first.wallet_id,
            crate::storage::RoundPhase::VoteReady,
        )?;
    }
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("failed to commit prepared vote persistence transaction: {e}"),
    })?;
    drop(conn);

    prepared
        .into_iter()
        .map(|vote| {
            CommittedVote::recover(
                db,
                &vote.round_id,
                vote.bundle_index,
                vote.commit.proposal_id,
            )
        })
        .collect()
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

/// Reconstructs one committed vote for crate-owned lifecycle work.
#[cfg(test)]
pub(crate) fn recover_commit(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<VoteCommit, VotingError> {
    recover_commit_with_generation(db, round_id, bundle_index, proposal_id)
        .map(|(commit, _)| commit)
}

fn recover_commit_with_generation(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(VoteCommit, String), VotingError> {
    let wallet_id = db.wallet_id();
    let conn = db.conn();
    let commitment_bundle_json =
        recovery_json_with_conn(&conn, &wallet_id, round_id, bundle_index, proposal_id)?.ok_or_else(
            || VotingError::InvalidInput {
                message: format!(
                    "vote recovery bundle not found for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
                ),
            },
        )?;
    let recovery = parse_recovery(&commitment_bundle_json)?;
    Ok((commit_from_recovery(&recovery)?, commitment_bundle_json))
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
        .and_then(|bundle| {
            ensure_singleton_vote_recovery(&bundle)?;
            Ok(VoteSubmission {
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
        })
}

/// Records the cast-vote transaction hash and marks a singleton vote submitted.
///
/// Atomic batch members must use [`record_batch_submission`].
pub fn record_submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
) -> Result<(), VotingError> {
    db.record_vote_submission(round_id, bundle_index, proposal_id, tx_hash)
}

/// Atomically records one transaction hash for every action in a persisted
/// vote batch. This is the durable retry point immediately after CheckTx.
pub fn record_batch_submission(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    batch_digest: &[u8],
    tx_hash: &str,
) -> Result<(), VotingError> {
    let batch_digest: [u8; 32] =
        batch_digest
            .try_into()
            .map_err(|_| VotingError::InvalidInput {
                message: format!("batch_digest must be 32 bytes, got {}", batch_digest.len()),
            })?;
    if tx_hash.trim().is_empty() {
        return Err(VotingError::InvalidInput {
            message: "tx_hash must not be empty".to_string(),
        });
    }
    let wallet_id = db.wallet_id();
    let mut conn = db.conn();
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("begin vote batch submission transaction failed: {e}"),
        })?;
    let recoveries = load_vote_batch_recoveries_with_conn(
        &tx,
        &wallet_id,
        round_id,
        bundle_index,
        batch_digest,
    )?;
    for recovery in recoveries {
        crate::storage::queries::record_vote_submission(
            &tx,
            round_id,
            &wallet_id,
            bundle_index,
            recovery.proposal_id,
            tx_hash,
        )?;
    }
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit vote batch submission transaction failed: {e}"),
    })
}

pub(crate) fn load_vote_batch_recoveries_with_conn(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    batch_digest: [u8; 32],
) -> Result<Vec<VoteRecoveryBundle>, VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT commitment_bundle_json FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND commitment_bundle_json IS NOT NULL",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("prepare vote batch recovery query failed: {e}"),
        })?;
    let rows = stmt
        .query_map(
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("query vote batch recovery rows failed: {e}"),
        })?;
    let mut recoveries = Vec::new();
    for row in rows {
        let recovery = parse_recovery(&row.map_err(|e| VotingError::Internal {
            message: format!("read vote batch recovery row failed: {e}"),
        })?)?;
        if recovery
            .batch
            .as_ref()
            .is_some_and(|batch| batch.digest == batch_digest)
        {
            recoveries.push(recovery);
        }
    }
    recoveries.sort_by_key(|recovery| recovery.batch.as_ref().map(|batch| batch.index));
    let expected_size = recoveries
        .first()
        .and_then(|recovery| recovery.batch.as_ref())
        .map(|batch| batch.size as usize)
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!(
                "vote batch recovery not found for round={round_id}, bundle={bundle_index}, digest={}",
                hex::encode(batch_digest)
            ),
        })?;
    if recoveries.len() != expected_size
        || recoveries.iter().enumerate().any(|(index, recovery)| {
            recovery.batch.as_ref().is_none_or(|batch| {
                batch.digest != batch_digest
                    || batch.index != index as u32
                    || batch.size as usize != expected_size
            })
        })
    {
        return Err(VotingError::InvalidInput {
            message: "persisted atomic vote batch is incomplete or out of order".to_string(),
        });
    }
    let actions = recoveries
        .iter()
        .map(
            |recovery| crate::vote_commitment::CastVoteBatchSighashAction {
                r_vpk: &recovery.r_vpk,
                van_nullifier: &recovery.van_nullifier,
                vote_authority_note_new: &recovery.vote_authority_note_new,
                vote_commitment: &recovery.vote_commitment,
                proposal_id: recovery.proposal_id,
            },
        )
        .collect::<Vec<_>>();
    let recomputed = crate::vote_commitment::cast_vote_batch_sighash(
        round_id,
        recoveries[0].anchor_height as u64,
        &actions,
    )?;
    if recomputed != batch_digest {
        return Err(VotingError::InvalidInput {
            message: "persisted atomic vote batch digest does not match its actions".to_string(),
        });
    }
    Ok(recoveries)
}

/// Clears unsubmitted recovery when a vote no longer matches ballot intent.
/// A batch is one signed envelope, so changing one member clears every member.
pub(crate) fn invalidate_unsubmitted_vote_recoveries_for_intent(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    proposal_id: u32,
    choice: Option<u32>,
) -> Result<(), VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT bundle_index, choice, commitment_bundle_json
             FROM votes
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND proposal_id = :proposal_id
               AND commitment_bundle_json IS NOT NULL
             ORDER BY bundle_index",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("prepare conflicting vote batch query failed: {e}"),
        })?;
    let rows = stmt
        .query_map(
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":proposal_id": proposal_id as i64,
            },
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, String>(2)?,
                ))
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("query conflicting vote batch rows failed: {e}"),
        })?;

    let mut batch_keys = BTreeSet::new();
    let mut singleton_keys = BTreeSet::new();
    for row in rows {
        let (bundle_index, stored_choice, recovery_json) =
            row.map_err(|e| VotingError::Internal {
                message: format!("read conflicting vote batch row failed: {e}"),
            })?;
        let bundle_index = u32::try_from(bundle_index).map_err(|_| VotingError::Internal {
            message: format!("stored bundle_index must be non-negative, got {bundle_index}"),
        })?;
        let recovery = parse_recovery(&recovery_json)?;
        validate_recovery_matches_stored_vote(
            &recovery,
            round_id,
            bundle_index,
            proposal_id,
            stored_choice,
            None,
        )?;
        if choice == Some(recovery.vote_decision) {
            continue;
        }
        if let Some(batch) = recovery.batch.as_ref() {
            batch_keys.insert((bundle_index, batch.digest));
        } else {
            singleton_keys.insert((bundle_index, proposal_id));
        }
    }
    drop(stmt);

    let mut batches = Vec::with_capacity(batch_keys.len());
    for (bundle_index, digest) in batch_keys {
        let recoveries =
            load_vote_batch_recoveries_with_conn(conn, wallet_id, round_id, bundle_index, digest)?;
        for recovery in &recoveries {
            let state = crate::storage::queries::load_vote_row_state(
                conn,
                round_id,
                wallet_id,
                bundle_index,
                recovery.proposal_id,
            )?
            .ok_or_else(|| VotingError::InvalidInput {
                message: format!(
                    "persisted atomic vote batch is missing proposal {} for round={round_id}, bundle={bundle_index}",
                    recovery.proposal_id
                ),
            })?;
            if state.tx_hash.is_some() || state.vc_tree_position.is_some() {
                return Err(VotingError::InvalidInput {
                    message: format!(
                        "round {round_id} bundle {bundle_index} has a submitted atomic vote batch that conflicts with ballot intent for proposal {proposal_id}"
                    ),
                });
            }
        }
        batches.push((bundle_index, recoveries));
    }

    for &(bundle_index, singleton_proposal_id) in &singleton_keys {
        let state = crate::storage::queries::load_vote_row_state(
            conn,
            round_id,
            wallet_id,
            bundle_index,
            singleton_proposal_id,
        )?
        .ok_or_else(|| VotingError::InvalidInput {
            message: format!(
                "persisted singleton vote is missing for round={round_id}, bundle={bundle_index}, proposal={singleton_proposal_id}"
            ),
        })?;
        if state.tx_hash.is_some() || state.vc_tree_position.is_some() {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "round {round_id} bundle {bundle_index} has a submitted singleton vote that conflicts with ballot intent for proposal {singleton_proposal_id}"
                ),
            });
        }
    }

    for (bundle_index, recoveries) in batches {
        for recovery in recoveries {
            clear_unsubmitted_vote_recovery_with_conn(
                conn,
                wallet_id,
                round_id,
                bundle_index,
                recovery.proposal_id,
            )?;
        }
    }
    for (bundle_index, singleton_proposal_id) in singleton_keys {
        clear_unsubmitted_vote_recovery_with_conn(
            conn,
            wallet_id,
            round_id,
            bundle_index,
            singleton_proposal_id,
        )?;
    }

    Ok(())
}

fn clear_unsubmitted_vote_recovery_with_conn(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    let updated = conn
        .execute(
            "UPDATE votes SET commitment_bundle_json = NULL
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index
               AND proposal_id = :proposal_id
               AND tx_hash IS NULL
               AND vc_tree_position IS NULL",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("clear stale vote recovery failed: {e}"),
        })?;
    if updated != 1 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "vote recovery changed while updating ballot intent for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        });
    }
    conn.execute(
        "DELETE FROM share_delegations
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
    )
    .map_err(|e| VotingError::Internal {
        message: format!("clear stale vote shares failed: {e}"),
    })?;
    Ok(())
}

/// Records the on-chain vote commitment tree position after confirmation.
///
/// This does not advance the bundle's current VAN position. Prefer
/// `confirmation::confirm_vote_submission` when recording chain events so all
/// confirmation fields are stored atomically. Atomic batch members must use
/// `confirmation::confirm_vote_batch_submission`.
pub fn record_vc_position(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    vc_tree_position: u64,
) -> Result<(), VotingError> {
    let wallet_id = db.wallet_id();
    let mut conn = db.conn();
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("begin vote VC position transaction failed: {e}"),
        })?;
    ensure_singleton_vote_update_with_conn(&tx, &wallet_id, round_id, bundle_index, proposal_id)?;
    record_vc_position_with_conn(
        &tx,
        &wallet_id,
        round_id,
        bundle_index,
        proposal_id,
        vc_tree_position,
    )?;
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit vote VC position transaction failed: {e}"),
    })
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
    recovery_bundle_with_conn(&conn, &wallet_id, round_id, bundle_index, proposal_id)
}

pub(crate) fn recovery_bundle_with_conn(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<VoteRecoveryBundle>, VotingError> {
    recovery_json_with_conn(conn, wallet_id, round_id, bundle_index, proposal_id)?
        .as_deref()
        .map(parse_recovery)
        .transpose()
}

fn recovery_json_with_conn(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<String>, VotingError> {
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
    Ok(json.flatten())
}

fn ensure_singleton_vote_recovery(recovery: &VoteRecoveryBundle) -> Result<(), VotingError> {
    if recovery.batch.is_some() {
        return Err(VotingError::InvalidInput {
            message: "vote belongs to an atomic batch; use the complete batch lifecycle instead of a per-vote API"
                .to_string(),
        });
    }
    Ok(())
}

/// Rejects a persisted batch member before a public singleton state mutation.
///
/// Only the batch markers are inspected here. Full recovery validation belongs
/// to APIs that consume the recovery payload, while transaction recording must
/// continue to support legacy singleton rows with partial recovery JSON.
pub(crate) fn ensure_singleton_vote_update_with_conn(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    let Some(json) = recovery_json_with_conn(conn, wallet_id, round_id, bundle_index, proposal_id)?
    else {
        return Ok(());
    };
    let recovery: serde_json::Value =
        serde_json::from_str(&json).map_err(|e| VotingError::InvalidInput {
            message: format!("invalid vote recovery JSON: {e}"),
        })?;
    if ["batch_digest", "batch_index", "batch_size"]
        .iter()
        .any(|field| recovery.get(field).is_some_and(|value| !value.is_null()))
    {
        return Err(VotingError::InvalidInput {
            message: "vote belongs to an atomic batch; use the complete batch lifecycle instead of a per-vote API"
                .to_string(),
        });
    }
    Ok(())
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
    let has_batch_metadata = parsed.batch_digest.is_some()
        || parsed.batch_index.is_some()
        || parsed.batch_size.is_some();
    match parsed.format.as_str() {
        VOTE_RECOVERY_FORMAT if !has_batch_metadata => {}
        VOTE_BATCH_RECOVERY_FORMAT if has_batch_metadata => {}
        VOTE_RECOVERY_FORMAT | VOTE_BATCH_RECOVERY_FORMAT => {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "vote recovery format {} does not match its record contents",
                    parsed.format
                ),
            });
        }
        _ => {
            return Err(VotingError::InvalidInput {
                message: format!("unsupported vote recovery format: {}", parsed.format),
            });
        }
    }
    VoteRecoveryBundle::try_from(parsed)
}

/// Persists the state produced by a successful vote commit for downstream tests.
///
/// This helper is available only in this crate's tests or with the
/// `test-fixtures` feature. The caller must create the round and its bundles
/// first. It stores the vote and recovery bundle and advances the round to
/// [`crate::storage::RoundPhase::VoteReady`], while leaving submission and
/// confirmation fields unset.
///
/// Exact reinsertions are idempotent. If recovery material changes before vote
/// submission or confirmation, matching helper-share tracking is cleared in
/// the same transaction. A vote with a submission hash or commitment-tree
/// position is never replaced.
///
/// Unlike [`commit`], this does not run any commit-time verification gates,
/// including capability, signer network, witness, proof, or signature checks.
/// Only use trusted fixture data. Cargo features are additive and are not a
/// security boundary; production builds should not enable `test-fixtures`.
#[cfg(any(test, feature = "test-fixtures"))]
pub fn insert_recovery_fixture(
    db: &VotingDb,
    bundle: &VoteRecoveryBundle,
) -> Result<(), VotingError> {
    let recovery_json = serialize_recovery(bundle)?;
    let commitment = stored_vote_commitment_bytes(bundle)?;
    let wallet_id = db.wallet_id();
    let mut conn = db.conn();
    let tx = conn.transaction().map_err(|e| VotingError::Internal {
        message: format!("begin vote recovery fixture transaction failed: {e}"),
    })?;

    let bundle_exists = tx
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM bundles
                WHERE round_id = :round_id AND wallet_id = :wallet_id
                  AND bundle_index = :bundle_index
            )",
            rusqlite::named_params! {
                ":round_id": &bundle.vote_round_id,
                ":wallet_id": &wallet_id,
                ":bundle_index": bundle.bundle_index as i64,
            },
            |row| Ok(row.get::<_, i64>(0)? != 0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to validate vote recovery fixture bundle: {e}"),
        })?;
    if !bundle_exists {
        return Err(VotingError::InvalidInput {
            message: format!(
                "bundle not found for vote recovery fixture: round={}, bundle={}",
                bundle.vote_round_id, bundle.bundle_index
            ),
        });
    }

    let existing_state = tx
        .query_row(
            "SELECT tx_hash IS NOT NULL, vc_tree_position IS NOT NULL,
                    commitment_bundle_json
             FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":round_id": &bundle.vote_round_id,
                ":wallet_id": &wallet_id,
                ":bundle_index": bundle.bundle_index as i64,
                ":proposal_id": bundle.proposal_id as i64,
            },
            |row| {
                Ok((
                    row.get::<_, i64>(0)? != 0,
                    row.get::<_, i64>(1)? != 0,
                    row.get::<_, Option<String>>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to check vote recovery fixture lifecycle state: {e}"),
        })?;
    if let Some((submitted, confirmed, _)) = &existing_state {
        if *submitted {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "cannot replace submitted vote with recovery fixture for round={}, bundle={}, proposal={}",
                    bundle.vote_round_id, bundle.bundle_index, bundle.proposal_id
                ),
            });
        }
        if *confirmed {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "cannot replace confirmed vote with recovery fixture for round={}, bundle={}, proposal={}",
                    bundle.vote_round_id, bundle.bundle_index, bundle.proposal_id
                ),
            });
        }
    }
    let recovery_changed = existing_state
        .as_ref()
        .map(|(_, _, stored_json)| stored_json.as_deref() != Some(recovery_json.as_str()))
        .unwrap_or(true);

    crate::storage::queries::store_vote(
        &tx,
        &bundle.vote_round_id,
        &wallet_id,
        bundle.bundle_index,
        bundle.proposal_id,
        bundle.vote_decision,
        &commitment,
    )?;
    if recovery_changed {
        tx.execute(
            "DELETE FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            rusqlite::named_params! {
                ":round_id": &bundle.vote_round_id,
                ":wallet_id": &wallet_id,
                ":bundle_index": bundle.bundle_index as i64,
                ":proposal_id": bundle.proposal_id as i64,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to clear stale vote recovery fixture shares: {e}"),
        })?;
    }
    crate::storage::queries::advance_round_phase(
        &tx,
        &bundle.vote_round_id,
        &wallet_id,
        crate::storage::RoundPhase::VoteReady,
    )?;
    store_recovery_json_for_vote_with_conn(
        &tx,
        VoteRecoveryStorageIdentity {
            round_id: &bundle.vote_round_id,
            wallet_id: &wallet_id,
            bundle_index: bundle.bundle_index,
            proposal_id: bundle.proposal_id,
            choice: bundle.vote_decision,
            commitment: Some(&commitment),
        },
        &recovery_json,
    )?;

    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit vote recovery fixture transaction failed: {e}"),
    })
}

#[cfg(test)]
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
    store_recovery_json_for_vote_with_conn(
        &conn,
        VoteRecoveryStorageIdentity {
            round_id,
            wallet_id: &wallet_id,
            bundle_index,
            proposal_id,
            choice,
            commitment,
        },
        json,
    )
}

struct VoteRecoveryStorageIdentity<'a> {
    round_id: &'a str,
    wallet_id: &'a str,
    bundle_index: u32,
    proposal_id: u32,
    choice: u32,
    commitment: Option<&'a [u8]>,
}

fn store_recovery_json_for_vote_with_conn(
    conn: &rusqlite::Connection,
    identity: VoteRecoveryStorageIdentity<'_>,
    json: &str,
) -> Result<(), VotingError> {
    let VoteRecoveryStorageIdentity {
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        choice,
        commitment,
    } = identity;
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
            conn,
            round_id,
            wallet_id,
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

fn validate_prepared_vote_state(
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    captured: &crate::storage::queries::VotePreparationState,
    current: &crate::storage::queries::VotePreparationState,
) -> Result<(), VotingError> {
    let stale = if current.network != captured.network {
        Some("round network")
    } else if current.zkp2.gov_comm_rand != captured.zkp2.gov_comm_rand {
        Some("governance commitment randomness")
    } else if current.zkp2.total_note_value != captured.zkp2.total_note_value {
        Some("delegated note value")
    } else if current.zkp2.address_index != captured.zkp2.address_index {
        Some("delegation address index")
    } else if current.zkp2.ea_pk != captured.zkp2.ea_pk {
        Some("encryption authority key")
    } else if current.zkp2.voting_round_id != captured.zkp2.voting_round_id {
        Some("voting round identity")
    } else if current.van_position != captured.van_position {
        Some("bundle VAN position")
    } else if current.zkp2.proposal_authority != captured.zkp2.proposal_authority {
        Some("proposal-authority state")
    } else if current.ballot_intent != captured.ballot_intent {
        Some("ballot intent")
    } else if current.vote != captured.vote {
        Some("current vote state")
    } else {
        None
    };
    if let Some(stale) = stale {
        return Err(VotingError::InvalidInput {
            message: format!(
                "{stale} changed while preparing vote for round={round_id}, bundle={bundle_index}, proposal={proposal_id}; recompute from current state"
            ),
        });
    }
    Ok(())
}

pub(crate) fn validate_recovery_bundle_vote_fields(
    bundle: &VoteRecoveryBundle,
) -> Result<(), VotingError> {
    validate_vote_round_id_hex(&bundle.vote_round_id)?;
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

/// Rejects another pending commitment that would spend the bundle's same current VAN.
fn ensure_no_competing_pending_vote_chain_with_conn(
    conn: &rusqlite::Connection,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_ids: &[u32],
) -> Result<(), VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT proposal_id FROM votes
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index
               AND commitment_bundle_json IS NOT NULL
               AND (tx_hash IS NULL OR vc_tree_position IS NULL)
             ORDER BY proposal_id",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare pending vote-chain query: {e}"),
        })?;
    let rows = stmt
        .query_map(
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
            },
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query pending vote chains: {e}"),
        })?;
    for row in rows {
        let stored_proposal_id = row.map_err(|e| VotingError::Internal {
            message: format!("failed to read pending vote-chain proposal: {e}"),
        })?;
        let stored_proposal_id =
            u32::try_from(stored_proposal_id).map_err(|_| VotingError::Internal {
                message: format!(
                    "stored pending vote-chain proposal must be non-negative, got {stored_proposal_id}"
                ),
            })?;
        if !proposal_ids.contains(&stored_proposal_id) {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "round {round_id} bundle {bundle_index} already has a pending vote chain for proposal {stored_proposal_id}; recover and confirm it before preparing another vote chain"
                ),
            });
        }
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
            batch: None,
        })
    }
}

impl From<&VoteRecoveryBundle> for VoteRecoveryJson {
    fn from(bundle: &VoteRecoveryBundle) -> Self {
        Self {
            format: if bundle.batch.is_some() {
                VOTE_BATCH_RECOVERY_FORMAT
            } else {
                VOTE_RECOVERY_FORMAT
            }
            .to_string(),
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
            batch_digest: bundle.batch.as_ref().map(|batch| batch.digest.to_vec()),
            batch_index: bundle.batch.as_ref().map(|batch| batch.index),
            batch_size: bundle.batch.as_ref().map(|batch| batch.size),
        }
    }
}

impl TryFrom<VoteRecoveryJson> for VoteRecoveryBundle {
    type Error = VotingError;

    fn try_from(value: VoteRecoveryJson) -> Result<Self, Self::Error> {
        validate_vote_round_id_hex(&value.vote_round_id)?;
        validate_proposal_id(value.proposal_id)?;
        validate_vote_decision(value.vote_decision, value.num_options)?;
        let batch =
            match (value.batch_digest, value.batch_index, value.batch_size) {
                (None, None, None) => None,
                (Some(digest), Some(index), Some(size)) => {
                    if size == 0 || size as usize > MAX_VOTE_BATCH_ACTIONS || index >= size {
                        return Err(VotingError::InvalidInput {
                            message: format!(
                                "invalid vote batch recovery position index={index}, size={size}"
                            ),
                        });
                    }
                    Some(VoteBatchRecovery {
                        digest: array32("batch_digest", digest)?,
                        index,
                        size,
                    })
                }
                _ => return Err(VotingError::InvalidInput {
                    message:
                        "vote batch recovery metadata must include digest, index, and size together"
                            .to_string(),
                }),
            };

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
            batch,
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
        seeded_vote_db(VotingDb::open_in_memory().unwrap())
    }

    fn seeded_vote_db(db: VotingDb) -> VotingDb {
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
            batch: None,
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

    fn two_action_recovery_batch() -> ([u8; 32], Vec<VoteRecoveryBundle>) {
        let mut first = recovery_bundle_fixture();
        first.proposal_id = 1;
        first.vote_commitment = [0x61; 32];
        let mut second = recovery_bundle_fixture();
        second.proposal_id = 2;
        second.vote_decision = 1;
        second.van_nullifier = [0x20; 32];
        second.vote_authority_note_new = [0x21; 32];
        second.vote_commitment = [0x62; 32];
        second.r_vpk = [0x25; 32];
        let actions = [&first, &second]
            .into_iter()
            .map(
                |recovery| crate::vote_commitment::CastVoteBatchSighashAction {
                    r_vpk: &recovery.r_vpk,
                    van_nullifier: &recovery.van_nullifier,
                    vote_authority_note_new: &recovery.vote_authority_note_new,
                    vote_commitment: &recovery.vote_commitment,
                    proposal_id: recovery.proposal_id,
                },
            )
            .collect::<Vec<_>>();
        let digest = crate::vote_commitment::cast_vote_batch_sighash(
            ROUND_ID,
            first.anchor_height as u64,
            &actions,
        )
        .unwrap();
        first.batch = Some(VoteBatchRecovery {
            digest,
            index: 0,
            size: 2,
        });
        second.batch = Some(VoteBatchRecovery {
            digest,
            index: 1,
            size: 2,
        });
        (digest, vec![first, second])
    }

    fn db_with_two_action_recovery_batch() -> (VotingDb, [u8; 32]) {
        let db = db_with_vote();
        queries::store_vote(&db.conn(), ROUND_ID, WALLET_ID, 0, 2, 1, &[0xCB; 32]).unwrap();
        let (digest, recoveries) = two_action_recovery_batch();
        for (recovery, stored_commitment) in
            recoveries.iter().zip([&[0xCA; 32][..], &[0xCB; 32][..]])
        {
            store_recovery_json_for_vote(
                &db,
                ROUND_ID,
                0,
                recovery.proposal_id,
                recovery.vote_decision,
                Some(stored_commitment),
                &serialize_recovery(recovery).unwrap(),
            )
            .unwrap();
        }
        (db, digest)
    }

    #[test]
    fn draft_batch_rejects_duplicate_proposals() {
        let draft = draft_vote_fixture();
        let err = validate_draft_votes(&[draft.clone(), draft]).unwrap_err();
        assert!(err.to_string().contains("duplicate proposal_id"), "{err}");
    }

    fn legacy_batch_drafts() -> [DraftVote; 2] {
        [
            DraftVote {
                proposal_id: 2,
                ..draft_vote_fixture()
            },
            DraftVote {
                proposal_id: 3,
                ..draft_vote_fixture()
            },
        ]
    }

    fn assert_no_legacy_batch_vote_state(db: &VotingDb) {
        for proposal_id in [2, 3] {
            assert!(
                queries::load_vote_row_state(&db.conn(), ROUND_ID, WALLET_ID, 0, proposal_id,)
                    .unwrap()
                    .is_none()
            );
            assert!(recovery_bundle(db, ROUND_ID, 0, proposal_id)
                .unwrap()
                .is_none());
        }
    }

    #[test]
    fn legacy_commit_batch_rejects_multiple_drafts_without_persisting() {
        let db = db_with_vote();
        let drafts = legacy_batch_drafts();
        let hotkey = VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap();

        let error = commit_batch(
            &db,
            ROUND_ID,
            0,
            &drafts,
            &VanWitness {
                auth_path: Vec::new(),
                position: 0,
                anchor_height: 0,
            },
            VoteSigner::hotkey(&hotkey),
            &NoopProgressReporter,
        )
        .unwrap_err();

        assert!(error.to_string().contains("commit_atomic_vote_batch"));
        assert_no_legacy_batch_vote_state(&db);
    }

    #[test]
    fn legacy_prepare_commit_batch_rejects_multiple_drafts_before_proving() {
        let db = db_with_vote();
        let drafts = legacy_batch_drafts();
        let hotkey = VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap();
        let witness = VanWitness {
            auth_path: Vec::new(),
            position: 0,
            anchor_height: 0,
        };

        let error = match prepare_commit_batch(
            &db,
            VoteSigner::hotkey(&hotkey),
            VoteCommitBatch {
                round_id: ROUND_ID,
                bundle_index: 0,
                drafts: &drafts,
                witness: &witness,
                stages: &NoopProgressReporter,
            },
        ) {
            Ok(_) => panic!("multiple legacy drafts must be rejected"),
            Err(error) => error,
        };

        assert!(error.to_string().contains("commit_atomic_vote_batch"));
        assert_no_legacy_batch_vote_state(&db);
    }

    #[test]
    fn atomic_vote_batch_reports_the_protocol_action_limit() {
        let drafts = (1..=(MAX_VOTE_BATCH_ACTIONS as u32 + 1))
            .map(|proposal_id| DraftVote {
                proposal_id,
                choice: 0,
                num_options: 2,
                single_share: false,
                vc_tree_position: 0,
            })
            .collect::<Vec<_>>();

        let error = validate_atomic_vote_batch(&drafts).unwrap_err();
        assert!(error.to_string().contains("at most 15 actions"));
    }

    #[test]
    fn batch_recovery_metadata_round_trips() {
        let (digest, recoveries) = two_action_recovery_batch();
        for (index, recovery) in recoveries.iter().enumerate() {
            let json = serialize_recovery(recovery).unwrap();
            let value: serde_json::Value = serde_json::from_str(&json).unwrap();
            assert_eq!(value["format"], VOTE_BATCH_RECOVERY_FORMAT);
            let parsed = parse_recovery(&json).unwrap();
            assert_eq!(
                parsed.batch,
                Some(VoteBatchRecovery {
                    digest,
                    index: index as u32,
                    size: 2,
                })
            );
        }
    }

    #[test]
    fn batch_recovery_rejects_the_singleton_format() {
        let (_, recoveries) = two_action_recovery_batch();
        let mut value: serde_json::Value =
            serde_json::from_str(&serialize_recovery(&recoveries[0]).unwrap()).unwrap();
        value["format"] = serde_json::json!(VOTE_RECOVERY_FORMAT);

        let error = parse_recovery(&value.to_string()).unwrap_err();
        assert!(error
            .to_string()
            .contains("does not match its record contents"));
    }

    #[test]
    fn records_one_batch_tx_hash_for_all_actions_atomically() {
        let (db, digest) = db_with_two_action_recovery_batch();

        record_batch_submission(&db, ROUND_ID, 0, &digest, "batch-tx").unwrap();
        assert_eq!(
            db.get_vote_tx_hash(ROUND_ID, 0, 1).unwrap().as_deref(),
            Some("batch-tx")
        );
        assert_eq!(
            db.get_vote_tx_hash(ROUND_ID, 0, 2).unwrap().as_deref(),
            Some("batch-tx")
        );
    }

    #[test]
    fn singleton_state_mutations_reject_batch_members() {
        let (db, _) = db_with_two_action_recovery_batch();

        let submission_error = record_submission(&db, ROUND_ID, 0, 1, "single-tx")
            .expect_err("a batch member must not be submitted independently");
        let recovery_error = db
            .mark_vote_submitted(ROUND_ID, 0, 2, "single-tx")
            .expect_err("a batch member must not use the singleton recovery API");
        let position_error = record_vc_position(&db, ROUND_ID, 0, 1, 789)
            .expect_err("a batch member must not record one VC position");

        for error in [submission_error, recovery_error, position_error] {
            assert!(
                error.to_string().contains("complete batch lifecycle"),
                "{error}"
            );
        }
        for proposal_id in [1, 2] {
            assert_eq!(db.get_vote_tx_hash(ROUND_ID, 0, proposal_id).unwrap(), None);
            assert_eq!(
                db.get_commitment_bundle_recovery_fields(ROUND_ID, 0, proposal_id)
                    .unwrap()
                    .and_then(|(_, position)| position),
                None
            );
        }
    }

    #[test]
    fn fresh_batch_rejects_another_unsubmitted_batch_for_the_bundle() {
        let (db, _) = db_with_two_action_recovery_batch();
        let drafts = [
            DraftVote {
                proposal_id: 3,
                choice: 0,
                num_options: 2,
                single_share: false,
                vc_tree_position: 0,
            },
            DraftVote {
                proposal_id: 4,
                choice: 1,
                num_options: 2,
                single_share: false,
                vc_tree_position: 0,
            },
        ];
        let witness = VanWitness {
            auth_path: Vec::new(),
            position: 0,
            anchor_height: 0,
        };
        let hotkey = VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap();

        let batch = AtomicVoteBatch::new(ROUND_ID, 0, &drafts, &witness, &NoopProgressReporter)
            .with_max_proof_concurrency(1)
            .unwrap();
        let err = match prepare_atomic_vote_batch(&db, VoteSigner::hotkey(&hotkey), batch) {
            Ok(_) => panic!("a disjoint batch must not reuse an unsubmitted bundle VAN"),
            Err(err) => err,
        };

        assert!(
            err.to_string().contains("already has a pending vote chain"),
            "{err}"
        );
    }

    #[test]
    fn fresh_singleton_rejects_an_unsubmitted_batch_for_the_bundle() {
        let (db, _) = db_with_two_action_recovery_batch();
        let witness = VanWitness {
            auth_path: Vec::new(),
            position: 0,
            anchor_height: 0,
        };
        let hotkey = VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap();

        let err = match prepare_commit(
            &db,
            ROUND_ID,
            0,
            &DraftVote {
                proposal_id: 3,
                choice: 0,
                num_options: 2,
                single_share: false,
                vc_tree_position: 0,
            },
            &witness,
            VoteSigner::hotkey(&hotkey),
            &NoopProgressReporter,
        ) {
            Ok(_) => panic!("a singleton must not reuse an unsubmitted batch VAN"),
            Err(err) => err,
        };

        assert!(
            err.to_string().contains("already has a pending vote chain"),
            "{err}"
        );
    }

    #[test]
    fn fresh_singleton_rejects_a_submitted_unconfirmed_batch_for_the_bundle() {
        let (db, digest) = db_with_two_action_recovery_batch();
        record_batch_submission(&db, ROUND_ID, 0, &digest, "batch-tx").unwrap();
        let witness = VanWitness {
            auth_path: Vec::new(),
            position: 0,
            anchor_height: 0,
        };
        let hotkey = VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap();

        let err = match prepare_commit(
            &db,
            ROUND_ID,
            0,
            &DraftVote {
                proposal_id: 3,
                choice: 0,
                num_options: 2,
                single_share: false,
                vc_tree_position: 0,
            },
            &witness,
            VoteSigner::hotkey(&hotkey),
            &NoopProgressReporter,
        ) {
            Ok(_) => panic!("a singleton must wait for batch confirmation"),
            Err(err) => err,
        };

        assert!(
            err.to_string().contains("already has a pending vote chain"),
            "{err}"
        );
    }

    fn configure_prepared_vote_fixture_bundle(db: &VotingDb) {
        db.conn()
            .execute(
                "UPDATE bundles SET van_comm_rand = ?1, total_note_value = ?2,
                    address_index = 0, van_leaf_position = 7
                 WHERE round_id = ?3 AND wallet_id = ?4 AND bundle_index = 0",
                rusqlite::params![
                    vec![0u8; 32],
                    crate::governance::BALLOT_DIVISOR as i64,
                    ROUND_ID,
                    WALLET_ID
                ],
            )
            .unwrap();
    }

    fn prepared_vote_from_recovery(
        db: &VotingDb,
        recovery: VoteRecoveryBundle,
    ) -> PreparedVoteCommit {
        db.set_ballot_intent(
            ROUND_ID,
            recovery.proposal_id,
            crate::session::Decision::Choice(recovery.vote_decision),
            recovery.num_options,
        )
        .unwrap();
        let state = queries::load_vote_preparation_state(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            0,
            recovery.proposal_id,
        )
        .unwrap();
        let draft = DraftVote {
            proposal_id: recovery.proposal_id,
            choice: recovery.vote_decision,
            num_options: recovery.num_options,
            single_share: recovery.single_share,
            vc_tree_position: recovery.vc_tree_position,
        };
        let commit = VoteCommit {
            proposal_id: recovery.proposal_id,
            van_nullifier: recovery.van_nullifier,
            vote_authority_note_new: recovery.vote_authority_note_new,
            vote_commitment: recovery.vote_commitment,
            proof: recovery.proof.clone(),
            anchor_height: recovery.anchor_height,
            r_vpk: recovery.r_vpk,
            vote_auth_sig: recovery.vote_auth_sig,
            encrypted_shares: Vec::new(),
            share_payloads: Vec::new(),
        };
        PreparedVoteCommit {
            wallet_id: WALLET_ID.to_string(),
            round_id: ROUND_ID.to_string(),
            bundle_index: 0,
            draft,
            recovery,
            commit,
            captured_state: CapturedVoteState::Fresh(state),
        }
    }

    fn prepared_vote_fixture(db: &VotingDb) -> PreparedVoteCommit {
        configure_prepared_vote_fixture_bundle(db);
        prepared_vote_from_recovery(db, recovery_bundle_fixture())
    }

    fn prepared_atomic_vote_batch_fixture(db: &VotingDb) -> PreparedAtomicVoteBatch {
        configure_prepared_vote_fixture_bundle(db);
        let (batch_digest, recoveries) = two_action_recovery_batch();
        let commitments = recoveries
            .into_iter()
            .map(|recovery| prepared_vote_from_recovery(db, recovery))
            .collect::<Vec<_>>();
        let batch_json = canonical_batch_json(&commitments).unwrap();

        PreparedAtomicVoteBatch {
            wallet_id: WALLET_ID.to_string(),
            round_id: ROUND_ID.to_string(),
            bundle_index: 0,
            commitments,
            batch_digest,
            batch_json,
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
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["format"], VOTE_RECOVERY_FORMAT);
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
    fn recovery_json_rejects_invalid_vote_identity() {
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

        value["vote_decision"] = serde_json::json!(2);
        value["vote_round_id"] = serde_json::json!("AA".repeat(32));
        assert!(parse_recovery(&value.to_string()).is_err());
    }

    #[test]
    fn recovery_json_serialization_rejects_invalid_vote_identity() {
        let mut bundle = recovery_bundle_fixture();
        bundle.num_options = 1;

        assert!(serialize_recovery(&bundle).is_err());

        let mut bundle = recovery_bundle_fixture();
        bundle.vote_round_id = "AA".repeat(32);

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
        assert_eq!(committed.data().share_payloads.len(), 2);
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

        crate::share::record(
            &db,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            1234,
        )
        .unwrap();
        crate::share::add_sent_servers(
            &db,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-b.example".to_string()],
        )
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

        crate::share::confirm(&db, ROUND_ID, 0, 1, 0).unwrap();
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
        assert_eq!(signed.encrypted_shares[0].c1, vec![0x21; 32]);
        assert_eq!(signed.shares_hash, [0x14; 32]);
        assert_eq!(signed.share_comms[0], [0x51; 32]);
        assert_eq!(signed.r_vpk, [0x15; 32]);
        assert_eq!(signed.vote_auth_sig, [0x17; 64]);
        assert_eq!(signed.commitment_bundle_json, recovery_json);
    }

    #[test]
    fn atomic_vote_batch_replays_signed_commitments_for_bundle() {
        let db = db_with_vote();
        let mut recovery = recovery_bundle_fixture();
        recovery.share_blinds = vec![scalar_bytes(1), scalar_bytes(2)];
        let digest = crate::vote_commitment::cast_vote_batch_sighash(
            ROUND_ID,
            recovery.anchor_height as u64,
            &[crate::vote_commitment::CastVoteBatchSighashAction {
                r_vpk: &recovery.r_vpk,
                van_nullifier: &recovery.van_nullifier,
                vote_authority_note_new: &recovery.vote_authority_note_new,
                vote_commitment: &recovery.vote_commitment,
                proposal_id: recovery.proposal_id,
            }],
        )
        .unwrap();
        recovery.batch = Some(VoteBatchRecovery {
            digest,
            index: 0,
            size: 1,
        });
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

        let result = commit_atomic_vote_batch(
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
        assert_eq!(result.batch_digest, digest);
        assert!(result.batch_json.starts_with("{\"votes\":["));

        let error = recover_signed_commitments(&db, ROUND_ID, 0, 1).unwrap_err();
        assert!(error.to_string().contains("recover_atomic_vote_batch"));
    }

    #[test]
    fn prepared_vote_is_unpersisted_until_atomic_persist() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());

        persist_prepared_commit(&db, prepared).unwrap();

        let stored = recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().unwrap();
        assert_eq!(stored.vote_decision, 2);
        assert_eq!(stored.proof, vec![0x13; 96]);
    }

    #[test]
    fn atomic_batch_persist_returns_payload_after_concurrent_invalidation() {
        let db = db_with_vote();
        let prepared = prepared_atomic_vote_batch_fixture(&db);
        let expected_batch_json = prepared.batch_json.clone();
        let expected_recovery_json = prepared
            .commitments
            .iter()
            .map(|prepared| serialize_recovery(&prepared.recovery).unwrap())
            .collect::<Vec<_>>();

        let signed = persist_prepared_atomic_vote_batch_inner(&db, prepared, || {
            std::thread::scope(|scope| {
                scope
                    .spawn(|| {
                        db.set_ballot_intent(ROUND_ID, 2, crate::session::Decision::Skipped, 3)
                            .unwrap();
                    })
                    .join()
                    .unwrap();
            });
        })
        .unwrap();

        assert_eq!(signed.batch_json, expected_batch_json);
        assert_eq!(signed.commitments.len(), 2);
        for (index, commitment) in signed.commitments.iter().enumerate() {
            assert_eq!(commitment.proposal_id, index as u32 + 1);
            assert_eq!(
                commitment.commitment_bundle_json,
                expected_recovery_json[index]
            );
            assert!(recovery_bundle(&db, ROUND_ID, 0, commitment.proposal_id)
                .unwrap()
                .is_none());
        }
    }

    #[test]
    fn prepared_vote_rejects_stale_van_position() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        queries::store_van_position(&db.conn(), ROUND_ID, WALLET_ID, 0, 8).unwrap();

        let err = persist_prepared_commit(&db, prepared).unwrap_err();
        assert!(
            err.to_string().contains("bundle VAN position changed"),
            "{err}"
        );
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn prepared_vote_rejects_a_submitted_competing_chain_before_persistence() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        let mut competing = recovery_bundle_fixture();
        competing.proposal_id = 2;
        competing.vote_commitment = [0x62; 32];
        let commitment = stored_vote_commitment_bytes(&competing).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            0,
            competing.proposal_id,
            competing.vote_decision,
            &commitment,
        )
        .unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            0,
            competing.proposal_id,
            competing.vote_decision,
            Some(&commitment),
            &serialize_recovery(&competing).unwrap(),
        )
        .unwrap();
        queries::record_vote_submission(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            0,
            competing.proposal_id,
            "pending-tx",
        )
        .unwrap();

        let err = persist_prepared_commit(&db, prepared).unwrap_err();

        assert!(
            err.to_string().contains("already has a pending vote chain"),
            "{err}"
        );
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn persist_waits_for_external_writer_then_rejects_stale_state() {
        use std::time::{Duration, Instant};

        use rusqlite::Connection;

        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "zcash-voting-persist-immediate-{}-{unique}.sqlite",
            std::process::id()
        ));
        let path_string = path.to_string_lossy().into_owned();
        let db = seeded_vote_db(VotingDb::open(&path_string).unwrap());
        let prepared = prepared_vote_fixture(&db);

        let lock = Connection::open(&path).unwrap();
        lock.busy_timeout(Duration::from_secs(5)).unwrap();
        lock.execute_batch("BEGIN IMMEDIATE").unwrap();
        queries::store_van_position(&lock, ROUND_ID, WALLET_ID, 0, 8).unwrap();

        let started = Instant::now();
        std::thread::scope(|scope| {
            let persist = scope.spawn(|| persist_prepared_commit(&db, prepared));
            std::thread::sleep(Duration::from_millis(400));
            lock.execute_batch("COMMIT").unwrap();

            let err = persist.join().unwrap().unwrap_err();
            assert!(started.elapsed() >= Duration::from_millis(300), "{err}");
            assert!(
                err.to_string().contains("bundle VAN position changed"),
                "{err}"
            );
        });

        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
        drop(db);
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(format!("{path_string}-shm"));
        let _ = std::fs::remove_file(format!("{path_string}-wal"));
    }

    #[test]
    fn prepared_vote_rejects_stale_proposal_authority() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        queries::store_vote(&db.conn(), ROUND_ID, WALLET_ID, 0, 2, 0, &[0xAB; 32]).unwrap();
        db.conn()
            .execute(
                "UPDATE votes SET tx_hash = 'submitted' WHERE round_id = ?1
                 AND wallet_id = ?2 AND bundle_index = 0 AND proposal_id = 2",
                rusqlite::params![ROUND_ID, WALLET_ID],
            )
            .unwrap();

        let err = persist_prepared_commit(&db, prepared).unwrap_err();
        assert!(
            err.to_string().contains("proposal-authority state changed"),
            "{err}"
        );
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn prepared_vote_ignores_authority_changes_in_independent_bundle() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        queries::insert_bundle(&db.conn(), ROUND_ID, WALLET_ID, 1, &[1]).unwrap();
        db.conn()
            .execute(
                "UPDATE bundles SET van_comm_rand = ?1, total_note_value = ?2,
                    address_index = 0, van_leaf_position = 9
                 WHERE round_id = ?3 AND wallet_id = ?4 AND bundle_index = 1",
                rusqlite::params![
                    vec![0u8; 32],
                    crate::governance::BALLOT_DIVISOR as i64,
                    ROUND_ID,
                    WALLET_ID
                ],
            )
            .unwrap();
        queries::store_vote(&db.conn(), ROUND_ID, WALLET_ID, 1, 2, 0, &[0xAB; 32]).unwrap();
        db.conn()
            .execute(
                "UPDATE votes SET tx_hash = 'submitted' WHERE round_id = ?1
                 AND wallet_id = ?2 AND bundle_index = 1 AND proposal_id = 2",
                rusqlite::params![ROUND_ID, WALLET_ID],
            )
            .unwrap();

        persist_prepared_commit(&db, prepared).unwrap();
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_some());
    }

    #[test]
    fn prepared_vote_rejects_changed_ballot_intent() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        db.set_ballot_intent(ROUND_ID, 1, crate::session::Decision::Choice(1), 3)
            .unwrap();

        let err = persist_prepared_commit(&db, prepared).unwrap_err();
        assert!(err.to_string().contains("ballot intent changed"), "{err}");
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn prepared_vote_rejects_changed_current_vote_state() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        queries::store_vote(&db.conn(), ROUND_ID, WALLET_ID, 0, 1, 1, &[0xBC; 32]).unwrap();

        let err = persist_prepared_commit(&db, prepared).unwrap_err();
        assert!(
            err.to_string().contains("current vote state changed"),
            "{err}"
        );
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn prepared_vote_rejects_changed_zkp2_inputs() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        db.conn()
            .execute(
                "UPDATE rounds SET ea_pk = ?1 WHERE round_id = ?2 AND wallet_id = ?3",
                rusqlite::params![vec![0xEFu8; 32], ROUND_ID, WALLET_ID],
            )
            .unwrap();

        let err = persist_prepared_commit(&db, prepared).unwrap_err();
        assert!(
            err.to_string().contains("encryption authority key changed"),
            "{err}"
        );
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn prepared_vote_rejects_changed_wallet_identity() {
        let db = db_with_vote();
        let prepared = prepared_vote_fixture(&db);
        db.set_wallet_id("different-wallet");

        let err = persist_prepared_commit(&db, prepared).unwrap_err();
        assert!(err.to_string().contains("wallet identity changed"), "{err}");

        db.set_wallet_id(WALLET_ID);
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn recovered_prepared_vote_rejects_deleted_vote_state() {
        let db = db_with_vote();
        let recovery = recovery_bundle_fixture();
        let commitment = stored_vote_commitment_bytes(&recovery).unwrap();
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            0,
            recovery.proposal_id,
            recovery.vote_decision,
            &commitment,
        )
        .unwrap();
        store_recovery_json_for_vote(
            &db,
            ROUND_ID,
            0,
            recovery.proposal_id,
            recovery.vote_decision,
            Some(&commitment),
            &serialize_recovery(&recovery).unwrap(),
        )
        .unwrap();
        let hotkey = VotingHotkey::from_stored_secret(&[0x99; 64], Network::Testnet).unwrap();
        let prepared = prepare_commit(
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
                auth_path: vec![],
                position: 0,
                anchor_height: 0,
            },
            VoteSigner::hotkey(&hotkey),
            &NoopProgressReporter,
        )
        .unwrap();
        db.conn()
            .execute(
                "DELETE FROM votes WHERE round_id = ?1 AND wallet_id = ?2
                 AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::params![ROUND_ID, WALLET_ID],
            )
            .unwrap();

        let err = persist_prepared_commit(&db, prepared).unwrap_err();
        assert!(
            err.to_string().contains("recovered vote state changed"),
            "{err}"
        );
    }

    #[test]
    fn legacy_commit_batch_and_recovery_keep_singleton_result() {
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

        let committed = commit_batch(
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
        assert_eq!(committed.bundle_index, 0);
        assert_eq!(committed.commitments.len(), 1);
        assert_eq!(committed.commitments[0].proposal_id, 1);

        let signed = recover_signed_commitments(&db, ROUND_ID, 0, 1).unwrap();
        assert_eq!(signed.bundle_index, 0);
        assert_eq!(signed.commitments.len(), 1);
        assert_eq!(signed.commitments[0].commitment_bundle_json, recovery_json);

        let error = recover_atomic_vote_batch(&db, ROUND_ID, 0, 1).unwrap_err();
        assert!(error.to_string().contains("recover_signed_commitments"));
    }

    #[test]
    fn legacy_prepared_batch_rejects_multiple_before_persisting() {
        let db = db_with_vote();
        let prepared = PreparedVoteCommitments {
            bundle_index: 0,
            commitments: vec![prepared_vote_fixture(&db), prepared_vote_fixture(&db)],
        };

        let error = persist_prepared_commit_batch(&db, prepared).unwrap_err();
        assert!(error.to_string().contains("commit_atomic_vote_batch"));
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_none());
    }

    #[test]
    fn legacy_prepared_batch_persists_one_fresh_commitment() {
        let db = db_with_vote();
        let prepared = PreparedVoteCommitments {
            bundle_index: 0,
            commitments: vec![prepared_vote_fixture(&db)],
        };

        let signed = persist_prepared_commit_batch(&db, prepared).unwrap();
        assert_eq!(signed.bundle_index, 0);
        assert_eq!(signed.commitments.len(), 1);
        assert_eq!(signed.commitments[0].proposal_id, 1);
        assert!(recovery_bundle(&db, ROUND_ID, 0, 1).unwrap().is_some());
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
