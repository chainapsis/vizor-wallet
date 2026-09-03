//! Round session: the FRB surface over `zcash_voting::RoundExecutor`.
//!
//! One session binds the sidecar, the account, the round, its proposal
//! roster, the routed chain and helper transports, and (when votes may be
//! cast) the voting hotkey. Dart records ballot decisions, reads the plan,
//! and advances steps; the SDK owns step interpretation, proving threads,
//! chain episodes, confirmation, and helper-share delivery. Dart keeps only
//! scheduling, cancellation, the network route, and secret custody.

use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use zcash_voting::delegation_pipeline::{DelegationSigner, KeystoneSignatureSource};
use zcash_voting::wire::{
    KeystoneSigningRequest, NextStepView, RoundPlanView, RoundStepFailureView,
    RoundStepOutcomeView, RoundStepProgressView,
};
use zcash_voting::{
    BallotIntent, ChainAdvancePolicy, ChainSubmissionClientConfig, ChainSubmissionControl,
    DelegationStepInputs, HelperHealth, ProposalRosterEntry, RoundBinding, RoundExecutor,
    RoundHostContext, RoundStepProgressBridge, VotingErrorView,
};
use zeroize::Zeroizing;

use crate::frb_generated::StreamSink;
use crate::wallet::voting::delegation::{self, RoundInputs, VizorDelegationPipeline};
use crate::wallet::voting::signer::SeedSpendAuthSigner;
use crate::wallet::voting::{db, hotkey};

use super::voting::{
    delegation_static_inputs_for, helper_client, routed_transport, share_tracking_pass_for,
    ApiVotingRoundContext, VotingShareTrackingPassHandle,
};
use super::voting_helpers::seed_from_mnemonic;

type RoutedExecutor = RoundExecutor<
    Arc<zcash_voting::HyperTransport<crate::wallet::voting::route::VizorRoute>>,
>;

/// One proposal from the authenticated round configuration.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApiProposalRosterEntry {
    pub proposal_id: u32,
    pub num_options: u32,
}

/// One ballot decision to record before casting.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApiBallotIntent {
    pub proposal_id: u32,
    /// `true` records `Skipped`; otherwise `choice` is required.
    pub skipped: bool,
    pub choice: Option<u32>,
}

/// Host inputs that change per step call.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiRoundHostContext {
    /// Complete current helper fleet, already mapped to transport URLs.
    pub configured_helper_urls: Vec<String>,
    pub now_seconds: u64,
    pub ceremony_start_seconds: Option<u64>,
    pub vote_end_time_seconds: Option<u64>,
    /// Vote-tree node URLs tried in order by cast-vote steps.
    pub vote_tree_node_urls: Vec<String>,
    pub max_proof_concurrency: u32,
}

/// How a delegation step signs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiDelegationSignerKind {
    /// Software account: `mnemonic` must be set.
    Mnemonic,
    /// Keystone account: use the signature stored for the bundle.
    KeystoneStored,
    /// Keystone account: use the provided signature bytes.
    KeystoneProvided,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDelegationSignerInput {
    pub kind: ApiDelegationSignerKind,
    pub mnemonic: Option<String>,
    pub keystone_sig: Option<Vec<u8>>,
    pub keystone_sighash: Option<Vec<u8>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiRoundStepEventKind {
    Progress,
    Result,
}

/// One event of a streamed step: progress while it runs, then one result.
#[derive(Clone, Debug, PartialEq)]
pub struct ApiRoundStepEvent {
    pub kind: ApiRoundStepEventKind,
    pub progress: Option<RoundStepProgressView>,
    pub outcome: Option<RoundStepOutcomeView>,
    pub failure: Option<RoundStepFailureView>,
}

/// SDK-owned execution of one round for one account.
#[frb(opaque)]
pub struct VotingRoundSession {
    executor: RoutedExecutor,
    inputs: RoundInputs,
    pir_server_urls: Vec<String>,
    pir_layout: zcash_voting::config::PirLayout,
    hotkey_secret: Option<Zeroizing<Vec<u8>>>,
    pipeline: Mutex<Option<Arc<VizorDelegationPipeline>>>,
    control: ChainSubmissionControl,
    health: HelperHealth,
    database: Arc<Mutex<Option<Arc<zcash_voting::round::VotingDb>>>>,
}

/// Opens a session bound to `ctx`'s account and round.
///
/// `stored_hotkey_secret` is required only for sessions that cast votes.
/// Chain and helper traffic use the wallet's network route; PIR and vote-tree
/// traffic use the SDK's direct transport.
#[frb(sync)]
pub fn open_voting_round_session(
    ctx: ApiVotingRoundContext,
    chain_endpoints: Vec<String>,
    pir_server_urls: Vec<String>,
    proposals: Vec<ApiProposalRosterEntry>,
    stored_hotkey_secret: Option<Vec<u8>>,
    operation_epoch: u64,
) -> Result<VotingRoundSession, VotingErrorView> {
    let inputs = delegation_static_inputs_for(&ctx).map_err(invalid_input)?;
    if let Some(secret) = stored_hotkey_secret.as_ref() {
        // Validate early so a bad secret fails at open, not mid-step.
        hotkey::voting_hotkey_from_stored_secret(secret.clone(), inputs.network)
            .map_err(invalid_input)?;
    }
    let database = db::open_voting_db(&ctx.db_path, &ctx.account_uuid).map_err(storage)?;
    let health = HelperHealth::default();
    let executor = RoundExecutor::with_transport(
        Arc::clone(&database),
        routed_transport(),
        ChainSubmissionClientConfig::for_network(inputs.network, chain_endpoints),
        helper_client(&health),
    )
    .map_err(|failure| VotingErrorView::from(zcash_voting::VotingError::InvalidInput {
        message: failure.message().to_string(),
    }))?
    .with_binding(RoundBinding {
        round_id: ctx.round_params.vote_round_id.clone(),
        network: inputs.network,
        proposals: proposals
            .into_iter()
            .map(|entry| ProposalRosterEntry {
                proposal_id: entry.proposal_id,
                num_options: entry.num_options,
            })
            .collect(),
        hotkey_secret: stored_hotkey_secret.clone().map(Zeroizing::new),
    })
    .map_err(VotingErrorView::from)?;
    Ok(VotingRoundSession {
        executor,
        inputs,
        pir_server_urls,
        pir_layout: ctx.pir_layout,
        hotkey_secret: stored_hotkey_secret.map(Zeroizing::new),
        pipeline: Mutex::new(None),
        control: ChainSubmissionControl::new(operation_epoch),
        health,
        database: Arc::new(Mutex::new(Some(database))),
    })
}

impl VotingRoundSession {
    /// Cancels every step in flight or queued on this session.
    #[frb(sync)]
    pub fn cancel(&self) {
        self.control.cancel();
    }

    #[frb(sync)]
    pub fn set_operation_epoch(&self, operation_epoch: u64) {
        self.control.set_operation_epoch(operation_epoch);
    }

    /// Plans the round from durable state.
    pub async fn plan(&self) -> Result<RoundPlanView, VotingErrorView> {
        let plan = self.executor.plan().map_err(VotingErrorView::from)?;
        RoundPlanView::try_from(plan).map_err(VotingErrorView::from)
    }

    /// Records ballot decisions against the bound roster and re-plans.
    pub async fn set_ballot_intents(
        &self,
        intents: Vec<ApiBallotIntent>,
    ) -> Result<RoundPlanView, VotingErrorView> {
        let intents = intents
            .into_iter()
            .map(|intent| {
                let decision = if intent.skipped {
                    zcash_voting::session::Decision::Skipped
                } else {
                    let choice = intent.choice.ok_or_else(|| {
                        invalid_input("ballot intent needs a choice when not skipped".to_string())
                    })?;
                    zcash_voting::session::Decision::Choice(choice)
                };
                Ok(BallotIntent {
                    proposal_id: intent.proposal_id,
                    decision,
                })
            })
            .collect::<Result<Vec<_>, VotingErrorView>>()?;
        let plan = self
            .executor
            .set_ballot_intents(&intents)
            .map_err(VotingErrorView::from)?;
        RoundPlanView::try_from(plan).map_err(VotingErrorView::from)
    }

    /// Runs the first planned step, streaming progress then one result.
    pub async fn advance_next(
        &self,
        host: ApiRoundHostContext,
        signer: Option<ApiDelegationSignerInput>,
        sink: StreamSink<ApiRoundStepEvent>,
    ) -> Result<(), VotingErrorView> {
        self.advance(None, host, signer, sink).await
    }

    /// Runs one planned step, streaming progress then one result.
    pub async fn advance_step(
        &self,
        step: NextStepView,
        host: ApiRoundHostContext,
        signer: Option<ApiDelegationSignerInput>,
        sink: StreamSink<ApiRoundStepEvent>,
    ) -> Result<(), VotingErrorView> {
        self.advance(Some(step), host, signer, sink).await
    }

    /// Builds redacted Keystone signing requests for the given bundles.
    pub async fn keystone_signing_requests(
        &self,
        bundle_indices: Vec<u32>,
    ) -> Result<Vec<KeystoneSigningRequest>, VotingErrorView> {
        let pipeline = self.pipeline().await?;
        tokio::task::spawn_blocking(move || {
            bundle_indices
                .into_iter()
                .map(|bundle_index| pipeline.keystone_request(bundle_index))
                .collect::<Result<Vec<_>, _>>()
        })
        .await
        .map_err(|error| internal(format!("Keystone request task failed: {error}")))?
        .map_err(VotingErrorView::from)
    }

    /// Cancellation handle for one helper-share tracking pass on this round.
    ///
    /// Tracking passes are cancelled by the destructive drain independently
    /// of the session's own control, so a background drain never aborts a
    /// foreground cast.
    #[frb(sync)]
    pub fn begin_share_tracking_pass(&self) -> VotingShareTrackingPassHandle {
        share_tracking_pass_for(
            &self.inputs.db_path,
            &self.inputs.account_uuid,
            &self.inputs.round_params.vote_round_id,
            &self.health,
            &self.database,
        )
    }

    async fn pipeline(&self) -> Result<Arc<VizorDelegationPipeline>, VotingErrorView> {
        if let Some(pipeline) = self
            .pipeline
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
        {
            return Ok(pipeline);
        }
        let hotkey = match self.hotkey_secret.as_ref() {
            Some(secret) => Some(
                hotkey::voting_hotkey_from_stored_secret(secret.to_vec(), self.inputs.network)
                    .map_err(invalid_input)?,
            ),
            None => None,
        };
        let pipeline = delegation::open_pipeline(&self.inputs, hotkey)
            .await
            .map_err(storage)?;
        *self
            .pipeline
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(Arc::clone(&pipeline));
        Ok(pipeline)
    }

    async fn delegation_inputs(
        &self,
        signer: Option<ApiDelegationSignerInput>,
    ) -> Result<Option<DelegationStepInputs>, VotingErrorView> {
        let Some(signer) = signer else {
            return Ok(None);
        };
        let signer = match signer.kind {
            ApiDelegationSignerKind::Mnemonic => {
                let mnemonic = signer.mnemonic.ok_or_else(|| {
                    invalid_input("mnemonic signer needs a mnemonic".to_string())
                })?;
                let seed = seed_from_mnemonic(mnemonic).map_err(invalid_input)?;
                DelegationSigner::Software(Arc::new(SeedSpendAuthSigner::new(seed)))
            }
            ApiDelegationSignerKind::KeystoneStored => {
                DelegationSigner::Keystone(KeystoneSignatureSource::Stored)
            }
            ApiDelegationSignerKind::KeystoneProvided => {
                let sig = signer.keystone_sig.ok_or_else(|| {
                    invalid_input("Keystone signer needs signature bytes".to_string())
                })?;
                let sighash = signer.keystone_sighash.ok_or_else(|| {
                    invalid_input("Keystone signer needs the signed sighash".to_string())
                })?;
                DelegationSigner::Keystone(KeystoneSignatureSource::Provided { sig, sighash })
            }
        };
        let pir = delegation::pir_fleet(&self.pir_server_urls, self.pir_layout).map_err(invalid_input)?;
        let driver = self.pipeline().await?;
        Ok(Some(DelegationStepInputs {
            driver,
            signer,
            pir,
        }))
    }

    async fn advance(
        &self,
        step: Option<NextStepView>,
        host: ApiRoundHostContext,
        signer: Option<ApiDelegationSignerInput>,
        sink: StreamSink<ApiRoundStepEvent>,
    ) -> Result<(), VotingErrorView> {
        let delegation = self.delegation_inputs(signer).await?;
        let host = RoundHostContext {
            configured_helper_urls: host.configured_helper_urls,
            now_seconds: host.now_seconds,
            ceremony_start_seconds: host.ceremony_start_seconds,
            vote_end_time_seconds: host.vote_end_time_seconds,
            vote_tree_node_urls: host.vote_tree_node_urls,
            delegation,
            chain_policy: ChainAdvancePolicy::default(),
            max_proof_concurrency: host.max_proof_concurrency.max(1) as usize,
        };
        let sink = Arc::new(sink);
        let progress_sink = Arc::clone(&sink);
        let reporter = RoundStepProgressBridge::new(move |progress| {
            let Ok(view) = RoundStepProgressView::try_from(progress) else {
                return;
            };
            let _ = progress_sink.add(ApiRoundStepEvent {
                kind: ApiRoundStepEventKind::Progress,
                progress: Some(view),
                outcome: None,
                failure: None,
            });
        });
        let result = match step {
            Some(step) => {
                self.executor
                    .advance_step(step.into(), &host, &self.control, &reporter)
                    .await
            }
            None => {
                self.executor
                    .advance_next(&host, &self.control, &reporter)
                    .await
            }
        };
        let event = match result {
            Ok(outcome) => ApiRoundStepEvent {
                kind: ApiRoundStepEventKind::Result,
                progress: None,
                outcome: Some(RoundStepOutcomeView::try_from(outcome).map_err(VotingErrorView::from)?),
                failure: None,
            },
            Err(failure) => ApiRoundStepEvent {
                kind: ApiRoundStepEventKind::Result,
                progress: None,
                outcome: None,
                failure: Some(RoundStepFailureView::try_from(failure).map_err(VotingErrorView::from)?),
            },
        };
        let _ = sink.add(event);
        Ok(())
    }
}

fn invalid_input(message: String) -> VotingErrorView {
    VotingErrorView::from(zcash_voting::VotingError::InvalidInput { message })
}

fn storage(message: String) -> VotingErrorView {
    VotingErrorView::from(zcash_voting::VotingError::Storage { message })
}

fn internal(message: String) -> VotingErrorView {
    VotingErrorView::from(zcash_voting::VotingError::Internal { message })
}
