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
    KeystoneSigningRequest, RoundDriveEventView, RoundPlanView, RoundRunReportView,
};
use zcash_voting::{
    BallotIntent, ChainAdvancePolicy, ChainSubmissionClientConfig, ChainSubmissionControl,
    DelegationStepInputs, FailureIsolation, HelperHealth, ProposalRosterEntry, RoundBinding,
    RoundDrivePolicy, RoundDriveReporterBridge, RoundDriver, RoundExecutor, RoundHostContext,
    RoundHostSourceBridge, VotingErrorView,
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

type RoutedExecutor =
    RoundExecutor<Arc<zcash_voting::HyperTransport<crate::wallet::voting::route::VizorRoute>>>;

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

/// A typed bridge failure carried by a result event.
///
/// Mirrors [`VotingErrorView`] field for field instead of embedding it. The
/// bridge marks a type as a Dart exception only while it is used purely as an
/// error type; using the view as a struct field here would demote it to plain
/// data, and `#[frb(sync)]` entry points depend on that marker — the
/// generated `executeSync` rethrows only `FrbException`s and turns everything
/// else into a `PanicException`, which would cost
/// [`open_voting_round_session`] its typed failure.
///
/// [`From`] destructures the view exhaustively, so a field added upstream
/// fails the build here rather than silently disappearing on this path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiRoundStepError {
    pub kind: zcash_voting::wire::VotingErrorKindView,
    pub retryable: bool,
    pub message: String,
    pub bundle_index: Option<u32>,
    pub setup_field: Option<zcash_voting::wire::DelegationSetupFieldView>,
    pub snapshot_height: Option<u64>,
    pub required_weight_zatoshi: Option<u64>,
    pub selected_weight_zatoshi: Option<u64>,
    pub bundle_note_slots: Option<u32>,
    pub selected_notes: Option<u32>,
    pub http_status: Option<u16>,
    pub endpoint: Option<String>,
}

impl From<VotingErrorView> for ApiRoundStepError {
    fn from(error: VotingErrorView) -> Self {
        let VotingErrorView {
            kind,
            retryable,
            message,
            bundle_index,
            setup_field,
            snapshot_height,
            required_weight_zatoshi,
            selected_weight_zatoshi,
            bundle_note_slots,
            selected_notes,
            http_status,
            endpoint,
        } = error;
        Self {
            kind,
            retryable,
            message,
            bundle_index,
            setup_field,
            snapshot_height,
            required_weight_zatoshi,
            selected_weight_zatoshi,
            bundle_note_slots,
            selected_notes,
            http_status,
            endpoint,
        }
    }
}

/// One observation from a round run, or its single terminal report.
///
/// Exactly one `Result`-kind event is emitted however the run ends, carrying
/// either the report or a bridge error.
pub struct ApiRoundRunEvent {
    pub kind: ApiRoundStepEventKind,
    pub event: Option<RoundDriveEventView>,
    pub report: Option<RoundRunReportView>,
    pub error: Option<ApiRoundStepError>,
}

/// How a run paces itself. Omitted fields keep the SDK defaults, which are the
/// cadence the Dart driver used before the SDK owned the loop.
pub struct ApiRoundDrivePolicy {
    pub pending_repoll_seconds: Option<f64>,
    pub max_bundle_concurrency: Option<u32>,
    pub max_dispatches: Option<u32>,
    /// `true` keeps every other bundle running after one fails.
    pub skip_failed_bundle: Option<bool>,
}

/// SDK-owned execution of one round for one account.
#[frb(opaque)]
pub struct VotingRoundSession {
    executor: RoutedExecutor,
    inputs: RoundInputs,
    pir_server_urls: Vec<String>,
    pir_layout: zcash_voting::config::PirLayout,
    hotkey_secret: Option<Zeroizing<Vec<u8>>>,
    pipeline: tokio::sync::OnceCell<Arc<VizorDelegationPipeline>>,
    control: ChainSubmissionControl,
    health: HelperHealth,
    database: Arc<Mutex<Option<Arc<zcash_voting::round::VotingDb>>>>,
}

/// Opens a session bound to `ctx`'s account and round.
///
/// `stored_hotkey_secret` is required only for sessions that cast votes.
/// Chain and helper traffic use the wallet's network route; PIR and vote-tree
/// traffic use the SDK's direct transport.
///
/// Synchronous on purpose for now: opening the sidecar can run schema
/// migrations, which would be better off the Dart isolate that draws the UI,
/// but the voting session fakes and their gate-based tests assume the handle
/// exists without an intervening event-loop turn. Moving it needs that
/// harness work, not just this signature.
#[frb(sync)]
pub fn open_voting_round_session(
    ctx: ApiVotingRoundContext,
    chain_endpoints: Vec<String>,
    pir_server_urls: Vec<String>,
    proposals: Vec<ApiProposalRosterEntry>,
    stored_hotkey_secret: Option<Vec<u8>>,
    operation_epoch: u64,
) -> Result<VotingRoundSession, VotingErrorView> {
    let inputs = delegation_static_inputs_for(&ctx).map_err(VotingErrorView::from)?;
    if let Some(secret) = stored_hotkey_secret.as_ref() {
        // Validate early so a bad secret fails at open, not mid-step.
        hotkey::voting_hotkey_from_stored_secret(secret.clone(), inputs.network)
            .map_err(VotingErrorView::from)?;
    }
    let database =
        db::open_voting_db(&ctx.db_path, &ctx.account_uuid).map_err(VotingErrorView::from)?;
    let health = HelperHealth::default();
    let executor = RoundExecutor::with_transport(
        Arc::clone(&database),
        routed_transport(),
        ChainSubmissionClientConfig::for_network(inputs.network, chain_endpoints),
        helper_client(&health),
    )
    .map_err(|failure| {
        VotingErrorView::from(zcash_voting::VotingError::InvalidInput {
            message: failure.message().to_string(),
        })
    })?
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
        pipeline: tokio::sync::OnceCell::new(),
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

    /// Clears durable ballot intents for proposals outside the bound roster
    /// and re-plans.
    ///
    /// A decision recorded before a proposal left the authenticated
    /// configuration outlives that proposal. The planner reports those in
    /// `RoundPlanView::unrostered_intents` and withholds `CastVote` until
    /// they are cleared, because the round's immediate helper share is
    /// derived from the complete set of choices and a stale intent would
    /// make that set disagree with the roster.
    ///
    /// Pass the ids the plan reported. The SDK refuses to clear an intent
    /// whose vote the chain lifecycle already owns, but the planner omits
    /// exactly those from `unrostered_intents`, so a plan-sourced list is
    /// always clearable.
    pub async fn clear_ballot_intents(
        &self,
        proposal_ids: Vec<u32>,
    ) -> Result<RoundPlanView, VotingErrorView> {
        let db = self.executor.database();
        let round_id = self.inputs.round_params.vote_round_id.clone();
        for proposal_id in proposal_ids {
            db.clear_ballot_intent(&round_id, proposal_id)
                .map_err(VotingErrorView::from)?;
        }
        let plan = self.executor.plan().map_err(VotingErrorView::from)?;
        RoundPlanView::try_from(plan).map_err(VotingErrorView::from)
    }

    /// Drives the bound round to quiescence, streaming events then one report.
    ///
    /// Emits exactly one `Result` event for the reason [`Self::advance`]
    /// documents: a streaming function's `Err` return never reaches Dart.
    ///
    /// `host` is a template. The driver reads the host context once per
    /// dispatch and this bridge restamps `now_seconds` each time, because a
    /// run can take minutes and a long proof can cross the last-moment or
    /// vote-end boundary. Every other field is fixed for the run, so a helper
    /// fleet that changes mid-run needs a new call.
    pub async fn run_round(
        &self,
        host: ApiRoundHostContext,
        signer: Option<ApiDelegationSignerInput>,
        policy: Option<ApiRoundDrivePolicy>,
        sink: StreamSink<ApiRoundRunEvent>,
    ) {
        let sink = Arc::new(sink);
        let event = match self.drive(host, signer, policy, Arc::clone(&sink)).await {
            Ok(event) => event,
            Err(error) => ApiRoundRunEvent {
                kind: ApiRoundStepEventKind::Result,
                event: None,
                report: None,
                error: Some(ApiRoundStepError::from(error)),
            },
        };
        let _ = sink.add(event);
    }

    /// Runs the round, streaming events, and returns its report event.
    async fn drive(
        &self,
        host: ApiRoundHostContext,
        signer: Option<ApiDelegationSignerInput>,
        policy: Option<ApiRoundDrivePolicy>,
        sink: Arc<StreamSink<ApiRoundRunEvent>>,
    ) -> Result<ApiRoundRunEvent, VotingErrorView> {
        // Built once for the whole run: opening it fetches the lightwalletd
        // anchor, and the driver overlaps bundles that would each pay for it.
        let delegation = self.delegation_inputs(signer).await?;
        let template = RoundHostContext {
            configured_helper_urls: host.configured_helper_urls,
            now_seconds: host.now_seconds,
            ceremony_start_seconds: host.ceremony_start_seconds,
            vote_end_time_seconds: host.vote_end_time_seconds,
            vote_tree_node_urls: host.vote_tree_node_urls,
            delegation,
            chain_policy: ChainAdvancePolicy::default(),
            max_proof_concurrency: host.max_proof_concurrency.max(1) as usize,
        };
        let host_source = RoundHostSourceBridge::new(move || RoundHostContext {
            now_seconds: unix_now_seconds(template.now_seconds),
            ..template.clone()
        });

        let event_sink = sink;
        let reporter = RoundDriveReporterBridge::new(move |event| {
            let Ok(view) = RoundDriveEventView::try_from(event) else {
                return;
            };
            let _ = event_sink.add(ApiRoundRunEvent {
                kind: ApiRoundStepEventKind::Progress,
                event: Some(view),
                report: None,
                error: None,
            });
        });

        let report = RoundDriver::new(&self.executor)
            .with_policy(round_drive_policy(policy))
            .run(&host_source, &self.control, &reporter)
            .await;
        Ok(ApiRoundRunEvent {
            kind: ApiRoundStepEventKind::Result,
            event: None,
            report: Some(RoundRunReportView::try_from(report).map_err(VotingErrorView::from)?),
            error: None,
        })
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

    /// The session's delegation pipeline, built once.
    ///
    /// Single-flight: a batch runs several delegation steps concurrently on
    /// one session, and opening the pipeline fetches the snapshot anchor from
    /// lightwalletd. A check-then-set cache would let every step in the batch
    /// pay for its own fetch and its own chance to fail. A failed build leaves
    /// the cell empty, so a later step can still succeed.
    async fn pipeline(&self) -> Result<Arc<VizorDelegationPipeline>, VotingErrorView> {
        self.pipeline
            .get_or_try_init(|| async {
                let hotkey = match self.hotkey_secret.as_ref() {
                    Some(secret) => Some(
                        hotkey::voting_hotkey_from_stored_secret(
                            secret.to_vec(),
                            self.inputs.network,
                        )
                        .map_err(VotingErrorView::from)?,
                    ),
                    None => None,
                };
                delegation::open_pipeline(&self.inputs, hotkey)
                    .await
                    .map_err(VotingErrorView::from)
            })
            .await
            .map(Arc::clone)
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
                let mnemonic = signer
                    .mnemonic
                    .ok_or_else(|| invalid_input("mnemonic signer needs a mnemonic".to_string()))?;
                let seed = seed_from_mnemonic(mnemonic).map_err(VotingErrorView::from)?;
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
        let pir = delegation::pir_fleet(&self.pir_server_urls, self.pir_layout)
            .map_err(VotingErrorView::from)?;
        let driver = self.pipeline().await?;
        Ok(Some(DelegationStepInputs {
            driver,
            signer,
            pir,
        }))
    }
}

/// The current wall clock, falling back to the host's own stamp.
///
/// The driver reads the context once per dispatch so a long run does not plan
/// against a frozen clock; a system clock before the epoch is not a reason to
/// fail a round, so the host's value stands in.
fn unix_now_seconds(fallback: u64) -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(fallback)
}

fn round_drive_policy(policy: Option<ApiRoundDrivePolicy>) -> RoundDrivePolicy {
    let defaults = RoundDrivePolicy::default();
    let Some(policy) = policy else {
        return defaults;
    };
    RoundDrivePolicy {
        pending_repoll: policy
            .pending_repoll_seconds
            .filter(|seconds| seconds.is_finite() && *seconds >= 0.0)
            .map(std::time::Duration::from_secs_f64)
            .unwrap_or(defaults.pending_repoll),
        max_bundle_concurrency: policy
            .max_bundle_concurrency
            .and_then(|limit| std::num::NonZeroUsize::new(limit as usize))
            .unwrap_or(defaults.max_bundle_concurrency),
        failure_isolation: match policy.skip_failed_bundle {
            Some(false) => FailureIsolation::StopRound,
            _ => FailureIsolation::SkipBundle,
        },
        max_dispatches: policy
            .max_dispatches
            .map(|budget| budget as usize)
            .filter(|budget| *budget > 0)
            .unwrap_or(defaults.max_dispatches),
    }
}

fn invalid_input(message: String) -> VotingErrorView {
    VotingErrorView::from(zcash_voting::VotingError::InvalidInput { message })
}

fn internal(message: String) -> VotingErrorView {
    VotingErrorView::from(zcash_voting::VotingError::Internal { message })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn policy(input: ApiRoundDrivePolicy) -> RoundDrivePolicy {
        round_drive_policy(Some(input))
    }

    fn unset() -> ApiRoundDrivePolicy {
        ApiRoundDrivePolicy {
            pending_repoll_seconds: None,
            max_bundle_concurrency: None,
            max_dispatches: None,
            skip_failed_bundle: None,
        }
    }

    #[test]
    fn an_absent_policy_keeps_the_sdk_cadence() {
        let defaults = RoundDrivePolicy::default();
        let mapped = round_drive_policy(None);
        assert_eq!(mapped.pending_repoll, defaults.pending_repoll);
        assert_eq!(
            mapped.max_bundle_concurrency,
            defaults.max_bundle_concurrency
        );
        assert_eq!(mapped.max_dispatches, defaults.max_dispatches);
    }

    #[test]
    fn each_unset_field_falls_back_on_its_own() {
        let defaults = RoundDrivePolicy::default();
        let mapped = policy(ApiRoundDrivePolicy {
            max_bundle_concurrency: Some(1),
            ..unset()
        });
        assert_eq!(mapped.max_bundle_concurrency.get(), 1);
        assert_eq!(
            mapped.pending_repoll, defaults.pending_repoll,
            "an unset field is not zeroed by a set sibling"
        );
        assert_eq!(mapped.max_dispatches, defaults.max_dispatches);
    }

    #[test]
    fn a_nonsense_repoll_cannot_panic_the_run() {
        // `Duration::from_secs_f64` panics on a negative or non-finite value,
        // and this value crosses a language boundary, so it is filtered rather
        // than trusted.
        for seconds in [-1.0, f64::NAN, f64::INFINITY] {
            let mapped = policy(ApiRoundDrivePolicy {
                pending_repoll_seconds: Some(seconds),
                ..unset()
            });
            assert_eq!(
                mapped.pending_repoll,
                RoundDrivePolicy::default().pending_repoll
            );
        }
        let mapped = policy(ApiRoundDrivePolicy {
            pending_repoll_seconds: Some(0.5),
            ..unset()
        });
        assert_eq!(mapped.pending_repoll, std::time::Duration::from_millis(500));
    }

    #[test]
    fn a_zero_budget_or_concurrency_falls_back_instead_of_stalling() {
        // Zero dispatches would end every run at once, and zero concurrency is
        // not representable; both mean "unset" from a host that sent 0.
        let mapped = policy(ApiRoundDrivePolicy {
            max_bundle_concurrency: Some(0),
            max_dispatches: Some(0),
            ..unset()
        });
        let defaults = RoundDrivePolicy::default();
        assert_eq!(
            mapped.max_bundle_concurrency,
            defaults.max_bundle_concurrency
        );
        assert_eq!(mapped.max_dispatches, defaults.max_dispatches);
    }

    #[test]
    fn failure_isolation_follows_the_hosts_choice() {
        assert_eq!(
            policy(ApiRoundDrivePolicy {
                skip_failed_bundle: Some(false),
                ..unset()
            })
            .failure_isolation,
            FailureIsolation::StopRound
        );
        for choice in [Some(true), None] {
            assert_eq!(
                policy(ApiRoundDrivePolicy {
                    skip_failed_bundle: choice,
                    ..unset()
                })
                .failure_isolation,
                FailureIsolation::SkipBundle,
                "a host that says nothing keeps every other bundle running"
            );
        }
    }

    #[test]
    fn the_clock_falls_back_to_the_hosts_own_stamp() {
        assert!(unix_now_seconds(0) > 1_700_000_000, "a real clock is used");
    }
}
