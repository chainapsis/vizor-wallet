use std::{
    panic,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Instant,
};

#[cfg(test)]
use super::voting_helpers::bundle_policy;
use super::voting_helpers::{
    delegation_static_inputs,
};
use crate::wallet::{
    keys,
    voting::{db, delegation, hotkey, network::voting_network},
};
use zcash_voting::config;
use zcash_voting::wire::{
    ConfigSwitchKind, DynamicConfigAttempt, PirLayout, ResolveVotingConfigOptions,
    ResolvedVotingConfig, ResolvedVotingConfigSummary, VotingErrorView,
};
use zcash_voting::VotingError;

pub use zcash_voting::vote::{DraftVote, SignedVoteCommitments};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApiPirSnapshotEndpointStatus {
    Matched,
    Behind,
    Ahead,
    MissingHeight,
    MalformedJson,
    NonSuccessStatus,
    TimeoutOrNetworkError,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiPirSnapshotEndpointDiagnostic {
    pub endpoint: String,
    pub status: ApiPirSnapshotEndpointStatus,
    pub reported_height: Option<u64>,
    pub http_status_code: Option<u16>,
    pub message: Option<String>,
}

impl From<ApiPirSnapshotEndpointDiagnostic>
    for zcash_voting::pir_snapshot::PirSnapshotEndpointDiagnostic
{
    fn from(diagnostic: ApiPirSnapshotEndpointDiagnostic) -> Self {
        use zcash_voting::pir_snapshot::PirSnapshotEndpointStatus as CoreStatus;
        let status = match diagnostic.status {
            ApiPirSnapshotEndpointStatus::Matched => CoreStatus::Matched,
            ApiPirSnapshotEndpointStatus::Behind => CoreStatus::Behind,
            ApiPirSnapshotEndpointStatus::Ahead => CoreStatus::Ahead,
            ApiPirSnapshotEndpointStatus::MissingHeight => CoreStatus::MissingHeight,
            ApiPirSnapshotEndpointStatus::MalformedJson => CoreStatus::MalformedJson,
            ApiPirSnapshotEndpointStatus::NonSuccessStatus => CoreStatus::NonSuccessStatus,
            ApiPirSnapshotEndpointStatus::TimeoutOrNetworkError => {
                CoreStatus::TimeoutOrNetworkError
            }
        };
        Self {
            endpoint: diagnostic.endpoint,
            status,
            reported_height: diagnostic.reported_height,
            http_status_code: diagnostic.http_status_code,
            message: diagnostic.message,
        }
    }
}

/// Select an exact-height PIR endpoint using the SDK's snapshot policy.
///
/// Dart owns probing and diagnostics because it owns the routed HTTP client.
/// The protocol decision about which diagnostics are eligible remains here.
#[flutter_rust_bridge::frb(sync)]
pub fn select_pir_snapshot_endpoint(
    diagnostics: Vec<ApiPirSnapshotEndpointDiagnostic>,
    expected_snapshot_height: u64,
    match_index: u64,
) -> Result<Option<String>, VotingErrorView> {
    let diagnostics = diagnostics.into_iter().map(Into::into).collect::<Vec<_>>();
    if zcash_voting::pir_snapshot::matching_pir_snapshot_endpoints(
        &diagnostics,
        expected_snapshot_height,
    )
    .is_empty()
    {
        return Ok(None);
    }
    zcash_voting::pir_snapshot::select_pir_snapshot_endpoint(
        &diagnostics,
        expected_snapshot_height,
        match_index,
    )
    .map(|resolution| Some(resolution.endpoint))
    .map_err(view)
}

/// Prefix for coarse cast-vote stage timings (`log show` subsystem `frb_user`).
const VOTING_VOTE_LOG: &str = "[VOTING_VOTE]";

/// Return the shared last-moment helper-share buffer, in Unix seconds.
#[flutter_rust_bridge::frb(sync)]
pub fn last_moment_buffer_seconds(
    ceremony_start_seconds: u64,
    vote_end_time_seconds: u64,
) -> Option<u64> {
    zcash_voting::share::policy::last_moment_buffer_seconds(
        ceremony_start_seconds,
        vote_end_time_seconds,
    )
}

/// Return true when `now_seconds` is inside the active round's last-moment window.
#[flutter_rust_bridge::frb(sync)]
pub fn is_last_moment(
    now_seconds: u64,
    ceremony_start_seconds: u64,
    vote_end_time_seconds: u64,
) -> bool {
    zcash_voting::share::policy::is_last_moment(
        now_seconds,
        ceremony_start_seconds,
        vote_end_time_seconds,
    )
}

// Fixed-width Keystone payload fields used by adapter regression tests.
#[cfg(test)]
const KEYSTONE_SIG_LEN: usize = 64;
#[cfg(test)]
const KEYSTONE_SIGHASH_LEN: usize = 32;
#[cfg(test)]
const KEYSTONE_RK_LEN: usize = 32;

#[derive(Clone, Debug, PartialEq)]
/// Shared delegation/voting round context passed across the FRB boundary.
///
/// This bundles the reusable round and wallet scope required by delegation setup,
/// proving, and keystone request flows.
pub struct ApiVotingRoundContext {
    pub db_path: String,
    pub lightwalletd_url: String,
    pub network: String,
    pub round_params: zcash_voting::wire::VotingRoundParams,
    pub round_name: String,
    pub session_json: Option<String>,
    pub account_uuid: String,
    pub max_real_notes_per_bundle: Option<u32>,
    /// Authenticated PIR geometry expected from the selected endpoint.
    pub pir_layout: PirLayout,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Read-only minimum voting eligibility status for one round/account.
pub struct ApiVotingEligibility {
    pub is_eligible: bool,
    pub distinct_note_count: u32,
    pub eligible_weight_zatoshi: u64,
    /// Raw note value the privacy trim withholds from this round, not its
    /// bundle-quantized voting weight. Zero when nothing was withheld.
    pub privacy_trim_dropped_value_zatoshi: u64,
}

/// FRB-facing bundle layout for [`setup_delegation_bundles`].
///
/// Keeps the SDK's flat privacy-trim totals on the existing layout boundary so
/// Dart can surface withheld voting power without mirroring a nested policy.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiBundleLayout {
    pub bundle_count: u32,
    pub eligible_weight: u64,
    pub dropped_count: u32,
    pub privacy_trim_dropped_bundles: u32,
    pub privacy_trim_dropped_notes: u32,
    pub privacy_trim_dropped_value_zatoshi: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// PIR cache result for one snapshot-precomputed delegation bundle.
pub struct ApiSnapshotBundlePirResult {
    pub cached_count: u32,
    pub fetched_count: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Snapshot bundle plan and PIR warm-up result exposed to Dart.
pub struct ApiSnapshotBundlePrecomputeResult {
    pub bundle_count: u32,
    pub eligible_weight: u64,
    pub dropped_count: u32,
    pub privacy_trim_dropped_bundles: u32,
    pub privacy_trim_dropped_notes: u32,
    pub privacy_trim_dropped_value_zatoshi: u64,
    pub bundles: Vec<ApiSnapshotBundlePirResult>,
}

impl From<zcash_voting::precompute::SnapshotBundlePrecomputeReport>
    for ApiSnapshotBundlePrecomputeResult
{
    fn from(report: zcash_voting::precompute::SnapshotBundlePrecomputeReport) -> Self {
        let layout = report.layout;
        Self {
            bundle_count: layout.bundle_count,
            eligible_weight: layout.eligible_weight,
            dropped_count: layout.dropped_count,
            privacy_trim_dropped_bundles: layout.privacy_trim_dropped_bundles,
            privacy_trim_dropped_notes: layout.privacy_trim_dropped_notes,
            privacy_trim_dropped_value_zatoshi: layout.privacy_trim_dropped_value_zatoshi,
            bundles: report
                .bundles
                .into_iter()
                .map(|bundle| ApiSnapshotBundlePirResult {
                    cached_count: bundle.cached,
                    fetched_count: bundle.fetched,
                })
                .collect(),
        }
    }
}

impl From<zcash_voting::wire::BundleLayout> for ApiBundleLayout {
    fn from(layout: zcash_voting::wire::BundleLayout) -> Self {
        Self {
            bundle_count: layout.bundle_count,
            eligible_weight: layout.eligible_weight,
            dropped_count: layout.dropped_count,
            privacy_trim_dropped_bundles: layout.privacy_trim_dropped_bundles,
            privacy_trim_dropped_notes: layout.privacy_trim_dropped_notes,
            privacy_trim_dropped_value_zatoshi: layout.privacy_trim_dropped_value_zatoshi,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// One Keystone delegation signature tuple to persist atomically.
pub struct ApiKeystoneSignatureInput {
    pub bundle_index: u32,
    pub sig: Vec<u8>,
    pub sighash: Vec<u8>,
    pub rk: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// Outcome of an idempotent Keystone signature batch write.
///
/// A tuple for a different signing context fails the whole batch with
/// `VotingError::KeystoneSignatureConflict`, which names the bundle.
pub struct ApiKeystoneSignatureBatchResult {
    pub inserted: u32,
    pub already_present: u32,
}

/// One account and round with durable unconfirmed helper shares.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiPendingShareRound {
    pub account_uuid: String,
    pub round_id: String,
    pub session_json: Option<String>,
}

/// Build round params from server metadata while binding trusted `ea_pk`.
///
/// Trust model for the per-round parameters:
///
/// - `ea_pk` (the encryption-authority key votes are encrypted to) is the only
///   field that cannot be independently re-derived by the wallet, so it is
///   always sourced from the authenticated dynamic config and never from the
///   vote server's round response. This call ignores any server-supplied
///   `ea_pk` and substitutes the authenticated value for `round_id`.
/// - `snapshot_height` and `nc_root` are accepted from the server here but are
///   re-verified downstream against the wallet's own lightwalletd-synced
///   Orchard commitment tree: `zcash_voting`'s witness generation
///   (`validate_cached_tree_state_for_round`) requires the synced frontier
///   height and root to match these exactly, so a wrong value fails closed
///   before any vote material is produced.
/// - `nullifier_imt_root` is accepted from the server here but is used
///   downstream as the expected root that PIR nullifier proofs are verified
///   against; a wrong root makes proof verification fail closed rather than
///   enabling a forged non-membership claim.
///
/// In other words, every server-supplied field other than `ea_pk` is
/// cross-checked against an independent source (lightwalletd or PIR proofs)
/// downstream, and `ea_pk` is pinned to authenticated config here. A
/// compromised or stale endpoint therefore cannot steer voting to the wrong
/// authority or roots without being rejected.
pub fn trusted_voting_round_params_from_config(
    resolved_config: zcash_voting::config::ResolvedVotingConfig,
    round_id: String,
    snapshot_height: u64,
    nc_root: Vec<u8>,
    nullifier_imt_root: Vec<u8>,
) -> Result<zcash_voting::wire::VotingRoundParams, VotingErrorView> {
    catch(|| {
        resolved_config
            .trusted_voting_round_params(round_id, snapshot_height, nc_root, nullifier_imt_root)
            .map_err(|error| invalid_input(error.to_string()))
    })
}

fn share_record(
    share: zcash_voting::wire::ShareDelegationRecordView,
) -> zcash_voting::ShareDelegationRecord {
    // Convert API view type into core share-tracking record shape.
    zcash_voting::ShareDelegationRecord {
        round_id: share.round_id,
        bundle_index: share.bundle_index,
        proposal_id: share.proposal_id,
        share_index: share.share_index,
        sent_to_urls: share.sent_to_urls,
        ambiguous_urls: share.ambiguous_urls,
        attempting_urls: Vec::new(),
        target_count: share.target_count,
        nullifier: share.nullifier,
        confirmed: share.confirmed,
        submit_at: share.submit_at,
        created_at: share.created_at,
    }
}

/// One helper share identified within its round.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ApiShareKey {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
}

/// One share that reached a new helper during a tracking pass.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiResubmittedShare {
    pub share: ApiShareKey,
    pub server_url: String,
}

/// What one helper share-tracking pass did.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiShareTrackingReport {
    /// Shares durably confirmed by the crate's two-helper quorum.
    pub confirmed: Vec<ApiShareKey>,
    /// Shares that reached an additional helper during this pass.
    pub resubmitted: Vec<ApiResubmittedShare>,
    /// Outcome-unknown attempts retained durably during this pass.
    pub ambiguous: Vec<ApiResubmittedShare>,
    /// Shares whose recovery material is missing, so no retry can help.
    pub unrecoverable: Vec<ApiShareKey>,
    /// True when the pass stopped early because Dart cancelled it.
    pub cancelled: bool,
    /// Seconds until the next pass, or `None` when nothing is pending.
    pub next_delay_seconds: Option<u64>,
}

impl From<zcash_voting::share_tracking::ShareKey> for ApiShareKey {
    fn from(key: zcash_voting::share_tracking::ShareKey) -> Self {
        Self {
            bundle_index: key.bundle_index,
            proposal_id: key.proposal_id,
            share_index: key.share_index,
        }
    }
}

/// Account-and-round-bound helper state shared by submission and recovery.
///
/// Health scores are local ordering hints for this voting workflow. Keeping
/// them here prevents failures in one account or round from influencing
/// another while still letting initial fan-out and later recovery share the
/// same recent view of helper availability.
#[flutter_rust_bridge::frb(opaque)]
pub struct VotingHelperDeliveryContext {
    db_path: String,
    account_uuid: String,
    round_id: String,
    health: zcash_voting::HelperHealth,
    database: Arc<Mutex<Option<Arc<zcash_voting::round::VotingDb>>>>,
}

/// One account-and-round-bound cancellation handle for helper-share tracking.
///
/// Dart creates the opaque handle synchronously before dispatching the async
/// pass. FRB retains the same handle while the call is queued or running, so an
/// immediate destructive drain can cancel that exact pass without a
/// process-wide operation registry.
#[flutter_rust_bridge::frb(opaque)]
pub struct VotingShareTrackingPassHandle {
    db_path: String,
    account_uuid: String,
    round_id: String,
    health: zcash_voting::HelperHealth,
    database: Arc<Mutex<Option<Arc<zcash_voting::round::VotingDb>>>>,
    cancelled: AtomicBool,
}

impl VotingShareTrackingPassHandle {
    /// Stops this tracking pass at its next cancellation check.
    #[flutter_rust_bridge::frb(sync)]
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
    }

    fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::Acquire)
    }
}

/// Process-wide routed transport for helper and vote-chain traffic, so
/// connections and TLS sessions are reused across passes.
pub(super) fn routed_transport() -> Arc<zcash_voting::HyperTransport<crate::wallet::voting::route::VizorRoute>> {
    static TRANSPORT: std::sync::OnceLock<
        Arc<zcash_voting::HyperTransport<crate::wallet::voting::route::VizorRoute>>,
    > = std::sync::OnceLock::new();
    TRANSPORT
        .get_or_init(|| {
            Arc::new(zcash_voting::HyperTransport::with_route(
                crate::wallet::voting::route::VizorRoute::new(),
            ))
        })
        .clone()
}

pub(super) fn helper_client(health: &zcash_voting::HelperHealth) -> zcash_voting::HelperClient {
    zcash_voting::HelperClient::new(routed_transport(), health.clone())
}

/// Creates helper delivery state for one account-and-round voting workflow.
#[flutter_rust_bridge::frb(sync)]
pub fn create_voting_helper_delivery_context(
    db_path: String,
    account_uuid: String,
    round_id: String,
) -> VotingHelperDeliveryContext {
    VotingHelperDeliveryContext {
        db_path,
        account_uuid,
        round_id,
        health: zcash_voting::HelperHealth::default(),
        database: Arc::new(Mutex::new(None)),
    }
}

/// Creates one cancellable tracking-pass handle bound to its delivery context.
#[flutter_rust_bridge::frb(sync)]
pub fn begin_share_tracking_pass(
    context: &VotingHelperDeliveryContext,
) -> VotingShareTrackingPassHandle {
    share_tracking_pass_for(
        &context.db_path,
        &context.account_uuid,
        &context.round_id,
        &context.health,
        &context.database,
    )
}

pub(super) fn share_tracking_pass_for(
    db_path: &str,
    account_uuid: &str,
    round_id: &str,
    health: &zcash_voting::HelperHealth,
    database: &Arc<Mutex<Option<Arc<zcash_voting::round::VotingDb>>>>,
) -> VotingShareTrackingPassHandle {
    VotingShareTrackingPassHandle {
        db_path: db_path.to_string(),
        account_uuid: account_uuid.to_string(),
        round_id: round_id.to_string(),
        health: health.clone(),
        database: database.clone(),
        cancelled: AtomicBool::new(false),
    }
}

fn helper_delivery_db(
    db_path: &str,
    account_uuid: &str,
    database: &Mutex<Option<Arc<zcash_voting::round::VotingDb>>>,
) -> Result<Arc<zcash_voting::round::VotingDb>, VotingError> {
    let mut database = database
        .lock()
        .map_err(|_| internal("voting helper database lock poisoned"))?;
    if let Some(db) = database.as_ref() {
        return Ok(db.clone());
    }
    let opened = db::open_voting_db(db_path, account_uuid)?;
    *database = Some(opened.clone());
    Ok(opened)
}

/// Runs one confirm-or-retry pass over a round's unconfirmed helper shares.
///
/// This is the whole helper-facing workflow: the crate polls helpers, requires
/// matching confirmation responses from two distinct configured helpers,
/// persists confirmed shares, retries overdue shares against helpers that
/// missed them, and persists delivery outcomes. Dart owns only the timer and
/// cancellation triggers.
///
/// The sidecar write lock is held for the open (which may migrate) and then
/// released. Holding it across the pass would block user-initiated voting
/// writes for as long as helper polling takes; the writes this pass makes are
/// short and self-contained, and the sidecar runs in WAL mode with a busy
/// timeout.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails or a share record cannot be
/// read or updated. Helper failures are not errors: they are scored and
/// reported through the returned pass result.
pub async fn track_pending_shares(
    pass_handle: &VotingShareTrackingPassHandle,
    configured_helper_urls: Vec<String>,
    now_seconds: u64,
    vote_end_time_seconds: Option<u64>,
) -> Result<ApiShareTrackingReport, VotingErrorView> {
    let cancel = || pass_handle.is_cancelled();

    // Open under the sidecar lock so a concurrent opener cannot race schema
    // migration, then run the network pass without holding it.
    let db = helper_delivery_db(
        &pass_handle.db_path,
        &pass_handle.account_uuid,
        &pass_handle.database,
    )
    .map_err(view)?;

    let client = helper_client(&pass_handle.health);
    let params = zcash_voting::share_tracking::ShareTrackingParams {
        round_id: &pass_handle.round_id,
        configured_server_urls: &configured_helper_urls,
        now_seconds,
        vote_end_time_seconds,
        policy: zcash_voting::share::ShareTimingPolicy::default(),
    };

    let report = zcash_voting::share_tracking::track_pending_shares(&db, &params, &client, &cancel)
        .await
        .map_err(view)?;

    Ok(ApiShareTrackingReport {
        confirmed: report
            .confirmed
            .into_iter()
            .map(ApiShareKey::from)
            .collect(),
        resubmitted: report
            .resubmitted
            .into_iter()
            .map(|entry| ApiResubmittedShare {
                share: entry.share.into(),
                server_url: entry.server_url,
            })
            .collect(),
        ambiguous: report
            .ambiguous
            .into_iter()
            .map(|entry| ApiResubmittedShare {
                share: entry.share.into(),
                server_url: entry.server_url,
            })
            .collect(),
        unrecoverable: report
            .unrecoverable
            .into_iter()
            .map(ApiShareKey::from)
            .collect(),
        cancelled: report.cancelled,
        next_delay_seconds: report.next_delay_seconds,
    })
}

/// Checks confirmation quorum for one known share without walking the round.
///
/// Foreground submission completion depends only on the designated immediate
/// share. Using the full recovery pass for that gate makes completion latency
/// scale with every proposal's delayed shares. This focused check polls at most
/// four configured helpers concurrently, persists confirmation after two
/// distinct helpers agree (or the sole helper in a one-helper fleet), and does
/// not resubmit or otherwise mutate unrelated shares.
pub async fn confirm_share_with_helpers(
    pass_handle: &VotingShareTrackingPassHandle,
    configured_helper_urls: Vec<String>,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    now_seconds: u64,
) -> Result<bool, VotingErrorView> {
    let db = helper_delivery_db(
        &pass_handle.db_path,
        &pass_handle.account_uuid,
        &pass_handle.database,
    )
    .map_err(view)?;
    let client = helper_client(&pass_handle.health);
    let cancel = || pass_handle.is_cancelled();
    let report = zcash_voting::share_tracking::confirm_pending_share(
        &db,
        &zcash_voting::share_tracking::ShareConfirmationParams {
            round_id: &pass_handle.round_id,
            share: zcash_voting::share_tracking::ShareKey {
                bundle_index,
                proposal_id,
                share_index,
            },
            configured_server_urls: &configured_helper_urls,
            now_seconds,
        },
        &client,
        &cancel,
    )
    .await
    .map_err(view)?;

    Ok(report.confirmed)
}

/// Return the next share-tracking delay in seconds using crate policy.
pub fn next_share_tracking_delay_seconds(
    shares: Vec<zcash_voting::wire::ShareDelegationRecordView>,
    now_seconds: u64,
) -> Result<Option<u64>, VotingErrorView> {
    catch(|| {
        // Convert wire views into core records consumed by share policy.
        let shares = shares.into_iter().map(share_record).collect::<Vec<_>>();
        Ok(zcash_voting::share::policy::next_tracking_delay_seconds(
            &shares,
            now_seconds,
            zcash_voting::share::ShareTimingPolicy::default(),
        ))
    })
}

/// Generate opaque voting hotkey bytes for a local voting account.
///
/// Vizor v2 uses the same random app-owned hotkey model for software and
/// Keystone accounts. The app persists this random per-round hotkey in secure
/// storage and reuses it for delegation setup and vote commitment signing.
pub fn generate_voting_hotkey(network: String) -> Result<Vec<u8>, VotingErrorView> {
    catch(|| {
        // Voting hotkeys are app-owned random secrets, not wallet-seed-derived.
        let network = keys::parse_network(&network).map_err(invalid_input)?;
        zcash_voting::hotkey::generate_random_voting_hotkey(voting_network(network))
            .map(|hotkey| {
                // FRB returns owned bytes, so this copy cannot be zeroized by Rust
                // after Dart receives it.
                hotkey.stored_secret().to_vec()
            })
    })
}

/// Executes an API helper and converts Rust panics into typed errors.
///
/// Every FRB entry point returns `VotingErrorView` so Dart classifies failures
/// by kind; a panic crossing this boundary becomes an `Internal` error instead
/// of an unwind crossing FFI.
fn catch<T>(
    f: impl FnOnce() -> Result<T, VotingError> + panic::UnwindSafe,
) -> Result<T, VotingErrorView> {
    match panic::catch_unwind(f) {
        Ok(result) => result.map_err(VotingErrorView::from),
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(VotingErrorView::from(internal(format!("Rust panic: {msg}"))))
        }
    }
}

fn invalid_input(message: impl Into<String>) -> VotingError {
    VotingError::InvalidInput {
        message: message.into(),
    }
}

fn internal(message: impl Into<String>) -> VotingError {
    VotingError::Internal {
        message: message.into(),
    }
}

/// Converts a typed error at the FRB boundary.
fn view(error: VotingError) -> VotingErrorView {
    VotingErrorView::from(error)
}

/// Round inputs for the SDK delegation pipeline, from the FRB round context.
pub(super) fn delegation_static_inputs_for(
    ctx: &ApiVotingRoundContext,
) -> Result<delegation::RoundInputs, VotingError> {
    round_inputs(ctx)
}

fn round_inputs(ctx: &ApiVotingRoundContext) -> Result<delegation::RoundInputs, VotingError> {
    let (network, bundle_policy) =
        delegation_static_inputs(&ctx.network, ctx.max_real_notes_per_bundle)?;
    Ok(delegation::RoundInputs {
        db_path: ctx.db_path.clone(),
        account_uuid: ctx.account_uuid.clone(),
        lightwalletd_url: ctx.lightwalletd_url.clone(),
        network,
        round_params: ctx.round_params.clone(),
        round_name: ctx.round_name.clone(),
        session_json: ctx.session_json.clone(),
        bundle_policy,
    })
}

/// Select notes and persist bundle rows for the delegation pipeline.
///
/// # Errors
///
/// Returns an error if bundle policy parsing, opening the sidecar DB, note
/// selection, or bundle setup fails.
pub async fn setup_delegation_bundles(
    ctx: ApiVotingRoundContext,
) -> Result<ApiBundleLayout, VotingErrorView> {
    delegation::setup_delegation_bundles(round_inputs(&ctx).map_err(view)?)
        .await
        .map(Into::into)
        .map_err(view)
}

/// Check whether the account has enough selected notes to vote in this round.
///
/// This selects notes at the round snapshot height and returns the smart-bundle
/// eligibility result without initializing round rows or persisting delegation
/// bundles.
///
/// # Errors
///
/// Returns an error if bundle policy parsing, opening the sidecar DB, note
/// selection, or eligibility calculation fails.
pub async fn check_voting_eligibility(
    ctx: ApiVotingRoundContext,
) -> Result<ApiVotingEligibility, VotingErrorView> {
    let report = delegation::check_voting_eligibility(round_inputs(&ctx).map_err(view)?)
        .await
        .map_err(view)?;
    let eligibility = report.eligibility;
    let distinct_note_count = u32::try_from(eligibility.distinct_note_count)
        .map_err(|_| view(internal("distinct note count does not fit in u32")))?;
    Ok(ApiVotingEligibility {
        is_eligible: eligibility.is_eligible(),
        distinct_note_count,
        eligible_weight_zatoshi: eligibility.eligible_weight,
        privacy_trim_dropped_value_zatoshi: report.privacy_trim_dropped_value_zatoshi,
    })
}

/// Persist the snapshot-stable bundle plan and warm all bundle PIR inputs.
///
/// This is the vote-screen warm-up path. It requires an initialized round and
/// snapshot-selected notes, but no voting hotkey or wallet seed. The normal
/// prove path remains the correctness fallback for missing witnesses or PIR
/// cache rows.
pub async fn precompute_snapshot_bundles(
    ctx: ApiVotingRoundContext,
    pir_server_url: String,
) -> Result<ApiSnapshotBundlePrecomputeResult, VotingErrorView> {
    let pir_layout = ctx.pir_layout;
    delegation::precompute_snapshot_bundles(
        round_inputs(&ctx).map_err(view)?,
        &pir_server_url,
        pir_layout,
    )
    .await
    .map(Into::into)
    .map_err(view)
}

/// Generate and persist ZKP1 for one software delegation bundle without signing.
///
/// This is the account-bound continuation of snapshot PIR precompute. It uses
/// the stored app hotkey to prepare the bundle and persists the proof, but it
/// never receives the wallet mnemonic and cannot sign or submit a delegation.
/// Repeated calls reuse an existing proved, submitted, or confirmed bundle and
/// return `false`; a newly generated proof returns `true`.
///
/// # Errors
///
/// Returns an error if round inputs, hotkey validation, bundle preparation, PIR
/// access, or ZKP1 generation fails.
pub async fn precompute_delegation_proof(
    ctx: ApiVotingRoundContext,
    pir_server_urls: Vec<String>,
    stored_hotkey_secret: Vec<u8>,
    bundle_index: u32,
) -> Result<bool, VotingErrorView> {
    let inputs = round_inputs(&ctx).map_err(view)?;
    let voting_hotkey =
        hotkey::voting_hotkey_from_stored_secret(stored_hotkey_secret, inputs.network)
            .map_err(view)?;
    delegation::precompute_delegation_proof(
        inputs,
        &pir_server_urls,
        ctx.pir_layout,
        voting_hotkey,
        bundle_index,
    )
    .await
    .map_err(view)
}

/// Kick off process-lifetime Halo2 proving-key warm-up for voting proofs.
///
/// Safe to call repeatedly; only the first call starts work. Returns
/// immediately so Dart can overlap warm-up with PIR resolve / bundle setup.
#[flutter_rust_bridge::frb(sync)]
pub fn warm_voting_proving_caches() {
    delegation::start_proving_cache_warmup();
}

#[derive(Clone, Debug, PartialEq, Eq)]
/// FRB-facing outcome of the bundle-independent PIR proof cache warm-up.
pub struct ApiPirCacheWarmupResult {
    /// Eligible notes selected at the snapshot height.
    pub note_count: u32,
    /// Nullifiers that already had a cached proof under the served root.
    pub cached_count: u32,
    /// Proofs fetched from the PIR server during this warm-up.
    pub fetched_count: u32,
    /// IMT root the PIR server served, as 32 little-endian bytes. Compare with
    /// the round's `nullifier_imt_root` to detect a stale snapshot.
    pub served_root: Vec<u8>,
    /// Cache rows evicted by automatic recency prune. Always `0` on this
    /// crate pin: `precompute_pir_proofs` prunes internally and does not
    /// report a count.
    pub pruned_count: u32,
}

impl From<delegation::PirCacheWarmupOutcome> for ApiPirCacheWarmupResult {
    fn from(outcome: delegation::PirCacheWarmupOutcome) -> Self {
        Self {
            note_count: outcome.note_count,
            cached_count: outcome.cached_count,
            fetched_count: outcome.fetched_count,
            served_root: outcome.served_root,
            pruned_count: outcome.pruned_count,
        }
    }
}

/// Warm the bundle-independent PIR proof cache for one account and snapshot.
///
/// `keep_roots` is accepted for FRB compatibility; the SDK prunes cache rows
/// by age and does not take a keep list.
pub async fn warm_pir_proof_cache(
    db_path: String,
    account_uuid: String,
    network: String,
    lightwalletd_url: String,
    snapshot_height: u64,
    pir_server_url: String,
    pir_layout: PirLayout,
    _keep_roots: Vec<Vec<u8>>,
) -> Result<ApiPirCacheWarmupResult, VotingErrorView> {
    let wallet_network = keys::parse_network(&network).map_err(|message| view(invalid_input(message)))?;
    let network = voting_network(wallet_network);
    delegation::warm_pir_proof_cache(
        &db_path,
        &account_uuid,
        &lightwalletd_url,
        network,
        snapshot_height,
        &pir_server_url,
        pir_layout,
    )
    .await
    .map(ApiPirCacheWarmupResult::from)
    .map_err(view)
}

/// Build and redact voting PCZTs that Keystone can sign in one or more batches.
///
/// # Errors
///
/// Returns an error if bundle indexes are empty or duplicated, round input
/// resolution fails, or PCZT construction and redaction for any requested
/// bundle fails.
pub async fn build_keystone_delegation_requests(
    ctx: ApiVotingRoundContext,
    stored_hotkey_secret: Vec<u8>,
    bundle_indices: Vec<u32>,
) -> Result<Vec<zcash_voting::wire::KeystoneSigningRequest>, VotingErrorView> {
    if bundle_indices.is_empty() {
        return Err(view(invalid_input(
            "Keystone delegation bundle indexes must not be empty",
        )));
    }
    let unique_bundle_count = bundle_indices
        .iter()
        .copied()
        .collect::<std::collections::HashSet<_>>()
        .len();
    if unique_bundle_count != bundle_indices.len() {
        return Err(view(invalid_input(
            "Keystone delegation bundle indexes must be unique",
        )));
    }
    let inputs = round_inputs(&ctx).map_err(view)?;
    let voting_hotkey =
        hotkey::voting_hotkey_from_stored_secret(stored_hotkey_secret, inputs.network)
            .map_err(view)?;
    let pipeline = delegation::open_pipeline(&inputs, Some(voting_hotkey))
        .await
        .map_err(view)?;
    tokio::task::spawn_blocking(move || {
        bundle_indices
            .into_iter()
            .map(|bundle_index| pipeline.keystone_request(bundle_index))
            .collect::<Result<Vec<_>, _>>()
    })
    .await
    .map_err(|error| view(internal(format!("Keystone request task failed: {error}"))))?
    .map_err(view)
}

/// Atomically persist a batch of Keystone delegation signatures.
///
/// Existing tuples for the same sighash and randomized key are accepted as
/// idempotent retries, even when randomized signing produced different valid
/// signature bytes. A tuple for a different signing context is a
/// `KeystoneSignatureConflict` error, and any validation or database error
/// rolls back the complete batch.
pub fn store_keystone_signatures_batch(
    db_path: String,
    account_uuid: String,
    round_id: String,
    signatures: Vec<ApiKeystoneSignatureInput>,
) -> Result<ApiKeystoneSignatureBatchResult, VotingErrorView> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        let signatures = signatures
            .into_iter()
            .map(|signature| zcash_voting::storage::KeystoneSignatureInput {
                bundle_index: signature.bundle_index,
                sig: signature.sig,
                sighash: signature.sighash,
                rk: signature.rk,
            })
            .collect::<Vec<_>>();
        let result = db.store_keystone_signatures_batch(&round_id, &signatures)?;
        Ok(ApiKeystoneSignatureBatchResult {
            inserted: result.inserted,
            already_present: result.already_present,
        })
    })
}

/// Load persisted Keystone signatures for one voting round.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails or signature rows cannot be
/// loaded.
pub fn get_keystone_signatures(
    db_path: String,
    account_uuid: String,
    round_id: String,
) -> Result<Vec<zcash_voting::wire::KeystoneSignatureRecord>, VotingErrorView> {
    catch(|| {
        // Load all persisted Keystone signatures for this round.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        db.get_keystone_signatures(&round_id)
    })
}

/// Delete bundle rows at or above `keep_count` for partial-bundle recovery.
///
/// Returns the number of deleted rows.
pub fn delete_skipped_bundles(
    db_path: String,
    account_uuid: String,
    round_id: String,
    keep_count: u32,
) -> Result<u32, VotingErrorView> {
    catch(|| {
        // Delete skipped bundle rows and downcast deleted count for FRB.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        db.delete_skipped_bundles(&round_id, keep_count)
            .and_then(|deleted| {
                u32::try_from(deleted).map_err(|_| {
                    internal(format!("deleted bundle count {deleted} does not fit in u32"))
                })
            })
    })
}

/// Sync vote commitment tree state for a voting round.
///
/// Returns the latest synced tree height. The underlying tree client is cached
/// per `(db_path, account_uuid)` so later VAN witness calls can reuse the synced
/// in-memory tree state.
///
/// # Errors
///
/// Returns an error if opening the voting DB fails or tree sync against
/// `node_url` fails for `round_id`.
pub fn sync_vote_tree(
    db_path: String,
    account_uuid: String,
    round_id: String,
    node_url: String,
) -> Result<u32, VotingErrorView> {
    catch(|| {
        // Sync and cache vote tree state for this wallet/round.
        let started = Instant::now();
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        let height = zcash_voting::precompute::sync_vote_tree(&db, &round_id, &node_url)?;
        log::info!(
            "{VOTING_VOTE_LOG} sync-tree complete round={round_id} height={height} elapsed={:.3}s",
            started.elapsed().as_secs_f64()
        );
        Ok(height)
    })
}

/// Clear process-local vote-tree sync state for a wallet or round.
///
/// Passing a non-empty round ID clears only that round's cached vote-tree sync
/// state by calling `zcash_voting::precompute::reset_vote_tree(db, round_id)`.
/// Passing `None` or an empty round ID performs account-wide vote-tree cleanup
/// with `zcash_voting::precompute::reset_vote_tree(db, "")`.
///
/// This does not clear unsigned delegation setup fields, delete durable recovery
/// rows, or abort in-flight proof/vote work already running on worker threads.
pub fn reset_vote_tree(
    db_path: String,
    account_uuid: String,
    round_id: Option<String>,
) -> Result<(), VotingErrorView> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;

        let scoped_round_id = round_id
            .as_deref()
            .filter(|id| !id.is_empty())
            .unwrap_or("");
        let reset_scope = if scoped_round_id.is_empty() {
            "account"
        } else {
            "round"
        };
        zcash_voting::precompute::reset_vote_tree(&db, scoped_round_id)?;
        log::info!(
            "voting: reset vote-tree state \
             (account_uuid={}, scope={}, round_id={:?})",
            account_uuid,
            reset_scope,
            round_id
        );
        Ok(())
    })
}

/// Clear process-local voting session state for a wallet or round.
///
/// Passing a non-empty round ID clears only that round's cached vote-tree sync
/// state and unsigned delegation setup fields by calling
/// `zcash_voting::precompute::reset_voting_session_state(db, round_id)`.
/// Passing `None` or an empty round ID performs account-wide vote-tree cleanup
/// with `zcash_voting::precompute::reset_voting_session_state(db, "")`.
///
/// This does not delete durable recovery rows or abort in-flight proof/vote
/// work already running on worker threads.
pub fn reset_voting_session_state(
    db_path: String,
    account_uuid: String,
    round_id: Option<String>,
) -> Result<(), VotingErrorView> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;

        let scoped_round_id = round_id
            .as_deref()
            .filter(|id| !id.is_empty())
            .unwrap_or("");
        let reset_scope = if scoped_round_id.is_empty() {
            "account"
        } else {
            "round"
        };
        zcash_voting::precompute::reset_voting_session_state(&db, scoped_round_id)?;
        log::info!(
            "voting: reset process-local session state \
             (account_uuid={}, scope={}, round_id={:?})",
            account_uuid,
            reset_scope,
            round_id
        );
        Ok(())
    })
}

/// Delete all durable voting sidecar rows for an account.
///
/// This removes every persisted round scoped to `account_uuid`, relying on the
/// `zcash_voting` round deletion cascade for bundles, recovery rows, share
/// history, ballot intent, and cached tree state. It also deletes
/// round-independent `pir_proof_cache` rows for the same wallet id — browse-
/// only warm-up can persist those without ever creating a round. Use this only
/// at account deletion boundaries, not for ordinary voting-session retries.
pub fn delete_voting_account_state(
    db_path: String,
    account_uuid: String,
) -> Result<u32, VotingErrorView> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        let round_count = db.clear_wallet_state()?;

        log::info!(
            "voting: deleted durable account state (account_uuid={}, rounds={})",
            account_uuid,
            round_count
        );
        Ok(round_count)
    })
}

/// List rounds with durable unconfirmed helper shares for the given accounts.
///
/// Accounts with no pending rounds contribute nothing. The result is sorted by
/// account and round.
pub fn list_pending_share_rounds(
    db_path: String,
    mut account_uuids: Vec<String>,
) -> Result<Vec<ApiPendingShareRound>, VotingErrorView> {
    account_uuids.retain(|account_uuid| !account_uuid.is_empty());
    catch(move || {
        let sidecar_path =
            zcash_voting::storage::VotingDb::wallet_sidecar_path(Path::new(&db_path));
        if !sidecar_path.exists() {
            return Ok(Vec::new());
        }
        let Some(first) = account_uuids.first().cloned() else {
            return Ok(Vec::new());
        };
        let db = db::open_voting_db(&db_path, &first)?;
        let wallet_ids: Vec<&str> = account_uuids.iter().map(String::as_str).collect();
        let mut pending = zcash_voting::share::pending_rounds_for_accounts(&db, &wallet_ids)?
            .into_iter()
            .map(|round| ApiPendingShareRound {
                account_uuid: round.wallet_id,
                round_id: round.round_id,
                session_json: round.session_json,
            })
            .collect::<Vec<_>>();
        pending.sort_by(|left, right| {
            (&left.account_uuid, &left.round_id).cmp(&(&right.account_uuid, &right.round_id))
        });
        Ok(pending)
    })
}

/// Load the full recovery/share-tracking summary for one voting round.
pub fn get_round_recovery_state(
    db_path: String,
    account_uuid: String,
    round_id: String,
) -> Result<zcash_voting::wire::RoundRecoveryStateView, VotingErrorView> {
    catch(|| {
        // Load persisted round snapshot and expose wire-safe view fields.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        zcash_voting::recovery::round_snapshot(&db, &round_id)
            .map(zcash_voting::wire::RoundRecoveryStateView::from)
    })
}

/// Compute the resumable voting-session plan for a round. The plan reports the
/// ordered remaining work (`next_steps`) and which proposals are still open.
pub fn get_round_plan(
    db_path: String,
    account_uuid: String,
    round_id: String,
    proposal_ids: Vec<u32>,
) -> Result<zcash_voting::wire::RoundPlanView, VotingErrorView> {
    catch(|| {
        // Derive resumable next steps and convert to wire view.
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        let plan = zcash_voting::session::resume_plan(&db, &round_id, &proposal_ids)?;
        zcash_voting::wire::RoundPlanView::try_from(plan)
    })
}

/// Persist (insert or replace) the voter's ballot intent for one proposal.
/// Pass `skipped: true` for `Decision::Skipped`; otherwise `choice` must be set.
/// `num_options` is the proposal's declared option count.
pub fn set_ballot_intent(
    db_path: String,
    account_uuid: String,
    round_id: String,
    proposal_id: u32,
    num_options: u32,
    skipped: bool,
    choice: Option<u32>,
) -> Result<(), VotingErrorView> {
    catch(|| {
        let db = db::open_voting_db(&db_path, &account_uuid)?;
        // `skipped` takes precedence; otherwise a concrete choice is required.
        let decision = if skipped {
            zcash_voting::session::Decision::Skipped
        } else {
            let c = choice.ok_or_else(|| {
                invalid_input("set_ballot_intent: choice must be Some when skipped is false")
            })?;
            zcash_voting::session::Decision::Choice(c)
        };
        db.set_ballot_intent(&round_id, proposal_id, decision, num_options)
    })
}

/// One wallet-side fetch outcome for a single dynamic config mirror.
///
/// Flat by necessity: the crate's [`DynamicConfigAttempt`] carries a
/// `Result<Vec<u8>, String>`, which flutter_rust_bridge cannot represent as a
/// struct field. Exactly one of `bytes` / `error` is expected to be set;
/// `bytes: None` means this mirror did not produce usable bytes and `error`
/// explains why for logging and diagnostics.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDynamicConfigAttempt {
    pub url: String,
    pub bytes: Option<Vec<u8>>,
    pub error: Option<String>,
}

impl From<ApiDynamicConfigAttempt> for DynamicConfigAttempt {
    fn from(attempt: ApiDynamicConfigAttempt) -> Self {
        match attempt.bytes {
            Some(bytes) => DynamicConfigAttempt::fetched(attempt.url, bytes),
            None => DynamicConfigAttempt::failed(
                attempt.url,
                attempt.error.unwrap_or_else(|| "fetch failed".to_string()),
            ),
        }
    }
}

/// A dynamic config mirror the resolver passed over, and why.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiDynamicConfigMirrorFailure {
    pub url: String,
    pub reason: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VotingConfigResolution {
    pub config: ResolvedVotingConfig,
    pub switch_kind: ConfigSwitchKind,
    /// Mirrors skipped before the one that resolved. Empty on the happy path.
    pub skipped_mirrors: Vec<ApiDynamicConfigMirrorFailure>,
}

/// Authenticate the static voting config bytes and surface the dynamic mirrors.
///
/// The wallet fetches the static trust anchor with its own transport and passes
/// the bytes here. Rust verifies the hash pin and decodes the static config,
/// returning the ordered `dynamic_config_urls` the wallet must walk before
/// calling [`resolve_voting_config_from_attempts`].
///
/// The returned list is always non-empty. A v1 static config names exactly one
/// URL and yields a single entry, so the v1 path is unchanged; a v2 config
/// yields its full mirror list, canonical origin first. Config errors are
/// returned as a flat string.
pub fn resolve_static_voting_config(
    source: String,
    static_bytes: Vec<u8>,
) -> Result<Vec<String>, VotingErrorView> {
    config::resolve_static_voting_config(&source, &static_bytes)
        .map(|resolved| resolved.dynamic_config_urls)
        .map_err(config_error)
}

/// Config failures are input problems at this boundary: the wallet handed the
/// resolver bytes it could not authenticate or decode.
fn config_error(error: impl std::fmt::Display) -> VotingErrorView {
    view(invalid_input(error.to_string()))
}

/// Resolve and authenticate voting config from wallet-fetched bytes.
///
/// The wallet owns transport: it fetches the static bytes, calls
/// [`resolve_static_voting_config`] to learn the dynamic mirrors, fetches them
/// in order, and passes the accumulated per-mirror outcomes here. Rust picks the
/// first mirror that both decodes and authenticates, reports the ones it passed
/// over, and computes the config-switch classification against `previous`.
///
/// Callers are expected to re-invoke this after each mirror fetch rather than
/// gathering every mirror up front, so a healthy primary costs one request. A
/// mirror that resolves but authenticates no rounds is deprioritized rather than
/// skipped, so the caller should keep walking while `authenticated_rounds` is
/// empty and accept the round-less resolution only once the list is exhausted.
///
/// Config errors are returned as a flat string; transport failures never reach
/// this layer, they arrive as failed attempts.
pub fn resolve_voting_config_from_attempts(
    source: String,
    static_bytes: Vec<u8>,
    attempts: Vec<ApiDynamicConfigAttempt>,
    previous: Option<ResolvedVotingConfig>,
) -> Result<VotingConfigResolution, VotingErrorView> {
    let resolved_static =
        config::resolve_static_voting_config(&source, &static_bytes).map_err(config_error)?;
    let (next, skipped) = config::resolve_dynamic_voting_config_from_attempts(
        resolved_static,
        attempts
            .into_iter()
            .map(DynamicConfigAttempt::from)
            .collect(),
        ResolveVotingConfigOptions::default(),
    )
    .map_err(config_error)?;

    let switch_kind = config::decide_config_switch(
        previous.as_ref().map(ResolvedVotingConfigSummary::from),
        ResolvedVotingConfigSummary::from(&next),
    )
    .kind;

    Ok(VotingConfigResolution {
        config: next,
        switch_kind,
        skipped_mirrors: skipped
            .into_iter()
            .map(|failure| ApiDynamicConfigMirrorFailure {
                url: failure.url,
                reason: failure.reason,
            })
            .collect(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine as _;
    use crate::wallet::voting::test_support::{
        test_api_round_params, test_note_info, ROUND_ID, TEST_ACCOUNT_UUID,
    };
    use ff::PrimeField;
    use pasta_curves::group::{Group, GroupEncoding};
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };
    use zcash_client_backend::proto::service::TreeState;
    use zcash_voting::BundlePolicy;

    fn b64(bytes: impl AsRef<[u8]>) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    fn delegation_submission_wire_json(
        submission: zcash_voting::wire::SignedDelegationPayloadView,
    ) -> Result<String, String> {
        submission
            .submission
            .to_json()
            .map_err(|error| error.to_string())
    }

    fn vote_commitment_wire_json(
        commitment: zcash_voting::wire::VoteCommitmentWire,
    ) -> Result<String, String> {
        commitment.to_json().map_err(|error| error.to_string())
    }

    fn point_bytes(multiplier: u64) -> Vec<u8> {
        (pasta_curves::pallas::Point::generator() * pasta_curves::pallas::Scalar::from(multiplier))
            .to_bytes()
            .to_vec()
    }

    fn full_share_comms() -> Vec<[u8; 32]> {
        (0..16)
            .map(|index| pasta_curves::pallas::Base::from(index + 10).to_repr())
            .collect()
    }

    fn test_tx1_effects() -> Vec<u8> {
        let mut effects = vec![0; zcash_voting::tx1::TX1_EFFECTS_LEN];
        effects[0] = zcash_voting::tx1::TX1_EFFECTS_VERSION;
        effects
    }

    fn test_round_context(
        db_path: &std::path::Path,
        network: &str,
        account_uuid: &str,
    ) -> ApiVotingRoundContext {
        ApiVotingRoundContext {
            db_path: db_path.to_str().unwrap().to_string(),
            lightwalletd_url: "http://127.0.0.1:1".to_string(),
            network: network.to_string(),
            round_params: test_api_round_params(),
            round_name: "Demo".to_string(),
            session_json: None,
            account_uuid: account_uuid.to_string(),
            max_real_notes_per_bundle: None,
            pir_layout: test_pir_layout(),
        }
    }

    fn test_pir_layout() -> zcash_voting::wire::PirLayout {
        zcash_voting::wire::PirLayout {
            pir_depth: 19,
            tier0_layers: 12,
            tier1_layers: 7,
            poly_len: 4096,
        }
    }

    #[test]
    fn generate_voting_hotkey_happy_path_returns_valid_distinct_seeds() {
        let hotkey_a = generate_voting_hotkey("regtest".to_string()).unwrap();
        let hotkey_b = generate_voting_hotkey("regtest".to_string()).unwrap();
        assert_eq!(hotkey_a.len(), 64);
        assert_eq!(hotkey_b.len(), 64);
        assert_ne!(hotkey_a, hotkey_b);
    }

    #[test]
    fn warm_voting_proving_caches_is_idempotent() {
        warm_voting_proving_caches();
        warm_voting_proving_caches();
    }

    #[test]
    fn share_tracking_cancellation_is_scoped_and_bound_before_async_start() {
        let first_context = create_voting_helper_delivery_context(
            "db-1".to_string(),
            "account-1".to_string(),
            "round-1".to_string(),
        );
        let second_context = create_voting_helper_delivery_context(
            "db-2".to_string(),
            "account-2".to_string(),
            "round-2".to_string(),
        );
        let first = begin_share_tracking_pass(&first_context);
        let second = begin_share_tracking_pass(&second_context);

        first.cancel();

        assert!(first.is_cancelled());
        assert!(!second.is_cancelled());
        assert_eq!(first.account_uuid, "account-1");
        assert_eq!(first.round_id, "round-1");
        assert_eq!(second.account_uuid, "account-2");
        assert_eq!(second.round_id, "round-2");
    }

    #[test]
    fn helper_health_is_shared_within_a_context_and_isolated_between_contexts() {
        let first_context = create_voting_helper_delivery_context(
            "db-1".to_string(),
            "account-1".to_string(),
            "round-1".to_string(),
        );
        let second_context = create_voting_helper_delivery_context(
            "db-2".to_string(),
            "account-2".to_string(),
            "round-2".to_string(),
        );
        let helper_url = "https://helper.example";

        first_context.health.record_failure(helper_url, 100);
        let first_handle = begin_share_tracking_pass(&first_context);
        let second_handle = begin_share_tracking_pass(&second_context);

        assert_eq!(first_handle.health.failure_count(helper_url), 1);
        assert_eq!(second_handle.health.failure_count(helper_url), 0);
    }

    #[tokio::test]
    async fn focused_share_confirmation_persists_quorum_without_walking_round() {
        let first_helper = start_share_status_server();
        let second_helper = start_share_status_server();
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        seed_recovery_vote(&db, TEST_ACCOUNT_UUID, 0, 7, 1, 88);
        seed_recovery_vote(&db, TEST_ACCOUNT_UUID, 0, 8, 1, 89);
        zcash_voting::share::record_delivery_fixture(
            &db,
            ROUND_ID,
            0,
            7,
            0,
            &[first_helper.clone(), second_helper.clone()],
            &[],
            2,
            0,
        )
        .unwrap();
        zcash_voting::share::record_delivery_fixture(
            &db,
            ROUND_ID,
            0,
            8,
            0,
            &[first_helper.clone(), second_helper.clone()],
            &[],
            2,
            0,
        )
        .unwrap();
        drop(db);

        let context = create_voting_helper_delivery_context(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        );
        let handle = begin_share_tracking_pass(&context);
        assert!(confirm_share_with_helpers(
            &handle,
            vec![first_helper, second_helper],
            0,
            7,
            0,
            100,
        )
        .await
        .unwrap());

        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        assert!(zcash_voting::storage::queries::share_is_confirmed(
            &db.conn(),
            ROUND_ID,
            TEST_ACCOUNT_UUID,
            0,
            7,
            0,
        )
        .unwrap());
        assert!(!zcash_voting::storage::queries::share_is_confirmed(
            &db.conn(),
            ROUND_ID,
            TEST_ACCOUNT_UUID,
            0,
            8,
            0,
        )
        .unwrap());
    }

    #[test]
    fn bundle_policy_happy_path_maps_optional_limit() {
        assert_eq!(
            bundle_policy(None).unwrap(),
            zcash_voting::recoverable_bundle_policy_v1()
        );
        assert_eq!(
            bundle_policy(Some(2)).unwrap(),
            BundlePolicy::from_optional_max_real_notes_per_bundle(Some(2)).unwrap()
        );
    }

    #[test]
    fn api_round_params_convert_to_core_round_params() {
        let api = test_api_round_params();

        let core: zcash_voting::VotingRoundParams = api.clone();

        assert_eq!(core.vote_round_id, api.vote_round_id);
        assert_eq!(core.snapshot_height, api.snapshot_height);
        assert_eq!(core.ea_pk, api.ea_pk);
        assert_eq!(core.nc_root, api.nc_root);
        assert_eq!(core.nullifier_imt_root, api.nullifier_imt_root);
    }

    #[test]
    fn trusted_round_params_use_config_ea_pk() {
        let trusted_ea_pk = vec![7u8; 32];
        let config = zcash_voting::config::ResolvedVotingConfig {
            source_fingerprint: "source".to_string(),
            trusted_key_fingerprint: "keys".to_string(),
            dynamic_config_fingerprint: "dynamic".to_string(),
            vote_servers: vec![],
            pir_endpoints: vec![],
            pir_layout: test_pir_layout(),
            supported_versions: zcash_voting::config::SupportedVersions {
                pir: vec!["v0".to_string()],
                vote_protocol: "v0".to_string(),
                tally: "v0".to_string(),
                vote_server: "v1".to_string(),
            },
            authenticated_rounds: vec![zcash_voting::config::AuthenticatedRound {
                round_id: ROUND_ID.to_string(),
                ea_pk: trusted_ea_pk.clone(),
            }],
            skipped_round_ids: vec![],
            conditions: vec![],
        };

        let params = trusted_voting_round_params_from_config(
            config,
            ROUND_ID.to_string(),
            123,
            vec![2u8; 32],
            vec![3u8; 32],
        )
        .unwrap();

        assert_eq!(params.vote_round_id, ROUND_ID);
        assert_eq!(params.snapshot_height, 123);
        assert_eq!(params.ea_pk, trusted_ea_pk);
        assert_eq!(params.nc_root, vec![2u8; 32]);
        assert_eq!(params.nullifier_imt_root, vec![3u8; 32]);
    }

    #[test]
    fn api_bundle_setup_result_preserves_core_fields() {
        let api = ApiBundleLayout::from(zcash_voting::wire::BundleLayout {
            bundle_count: 2,
            eligible_weight: 50,
            dropped_count: 0,
            privacy_trim_dropped_bundles: 1,
            privacy_trim_dropped_notes: 4,
            privacy_trim_dropped_value_zatoshi: 900,
        });

        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.eligible_weight, 50);
        assert_eq!(api.dropped_count, 0);
        // The privacy-trim totals are flat scalars so the Dart mirror stays a
        // field-level delta instead of gaining a nested class.
        assert_eq!(api.privacy_trim_dropped_bundles, 1);
        assert_eq!(api.privacy_trim_dropped_notes, 4);
        assert_eq!(api.privacy_trim_dropped_value_zatoshi, 900);
    }

    #[test]
    fn api_signed_delegation_payload_preserves_core_fields() {
        let api = zcash_voting::wire::SignedDelegationPayloadView::try_from(
            zcash_voting::delegate::SignedDelegationBundle {
                submission: zcash_voting::delegate::DelegationSubmission {
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
                    tx1_effects: test_tx1_effects(),
                },
                pczt_bytes: vec![1, 2, 3],
                eligible_weight_zatoshi: 20,
                delegated_weight_zatoshi: 10,
                bundle_count: 2,
                bundle_index: 1,
            },
        )
        .unwrap();

        assert_eq!(api.pczt_bytes, vec![1, 2, 3]);
        assert_eq!(api.status, "ready_for_submission");
        assert_eq!(api.message, None);
        assert_eq!(api.submission.proof, b64(vec![4]));
        assert_eq!(api.submission.vote_round_id, b64([0, 1, 2, 3]));
        assert_eq!(api.eligible_weight_zatoshi, 20);
        assert_eq!(api.delegated_weight_zatoshi, 10);
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn api_keystone_delegation_request_preserves_display_memo() {
        let api = zcash_voting::wire::KeystoneSigningRequest {
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

        assert_eq!(api.display_memo, "I am authorizing this hotkey.");
        assert_eq!(api.bundle_count, 2);
        assert_eq!(api.bundle_index, 1);
    }

    #[test]
    fn delegation_wire_json_matches_vote_chain_shape() {
        let wire =
            delegation_submission_wire_json(zcash_voting::wire::SignedDelegationPayloadView {
                pczt_bytes: vec![],
                status: "ready".to_string(),
                message: None,
                submission: zcash_voting::wire::DelegationSubmissionWire {
                    proof: b64(vec![8; 96]),
                    rk: b64(vec![1; 32]),
                    spend_auth_sig: b64(vec![2; 64]),
                    tx1_effects: b64(test_tx1_effects()),
                    nf_signed: b64(vec![4; 32]),
                    cmx_new: b64(vec![5; 32]),
                    gov_comm: b64(vec![6; 32]),
                    gov_nullifiers: vec![b64(vec![7; 32]); zcash_voting::BUNDLE_NOTE_SLOTS],
                    vote_round_id: b64([0, 1, 2, 3]),
                },
                eligible_weight_zatoshi: 0,
                delegated_weight_zatoshi: 0,
                bundle_count: 1,
                bundle_index: 0,
            })
            .unwrap();

        let wire: serde_json::Value = serde_json::from_str(&wire).unwrap();
        assert!(wire.get("signed_note_nullifier").is_some());
        assert!(wire.get("van_cmx").is_some());
        assert!(wire.get("sighash").is_none());
        assert!(wire.get("tx1_effects").is_some());
        assert_eq!(
            wire["gov_nullifiers"].as_array().unwrap().len(),
            zcash_voting::BUNDLE_NOTE_SLOTS
        );
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(wire["vote_round_id"].as_str().unwrap())
                .unwrap(),
            vec![0, 1, 2, 3]
        );
    }

    #[test]
    fn cast_vote_wire_json_matches_vote_chain_shape() {
        let wire = vote_commitment_wire_json(zcash_voting::wire::VoteCommitmentWire {
            van_nullifier: b64(vec![1; 32]),
            vote_authority_note_new: b64(vec![2; 32]),
            vote_commitment: b64(vec![3; 32]),
            proposal_id: 7,
            proof: b64(vec![4; 96]),
            vote_round_id: b64(vec![0, 1, 2, 3]),
            anchor_height: 77,
            r_vpk: b64(vec![5; 32]),
            vote_auth_sig: b64(vec![6; 64]),
        })
        .unwrap();

        let wire: serde_json::Value = serde_json::from_str(&wire).unwrap();
        assert_eq!(wire["proposal_id"], 7);
        assert_eq!(wire["vote_comm_tree_anchor_height"], 77);
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(wire["vote_round_id"].as_str().unwrap())
                .unwrap(),
            vec![0, 1, 2, 3]
        );
    }

    #[test]
    fn next_share_tracking_delay_uses_crate_ready_interval() {
        let ready = zcash_voting::wire::ShareDelegationRecordView {
            round_id: ROUND_ID.to_string(),
            bundle_index: 0,
            proposal_id: 7,
            share_index: 0,
            sent_to_urls: vec!["https://helper.example".to_string()],
            ambiguous_urls: vec![],
            target_count: 1,
            nullifier: vec![1; 32],
            phase: zcash_voting::wire::WorkflowPhaseView::SubmittedShare,
            confirmed: false,
            submit_at: 100,
            created_at: 50,
        };
        let future = zcash_voting::wire::ShareDelegationRecordView {
            submit_at: 140,
            ..ready.clone()
        };

        assert_eq!(
            next_share_tracking_delay_seconds(vec![ready], 130).unwrap(),
            Some(15)
        );
        assert_eq!(
            next_share_tracking_delay_seconds(vec![future], 120).unwrap(),
            Some(30)
        );
    }

    #[test]
    fn api_van_witness_preserves_core_fields() {
        let mut witness = vec![vec![0u8; 32]; zcash_voting::vote::VAN_AUTH_PATH_LEN];
        witness[0] = vec![1; 32];
        witness[1] = vec![2; 32];
        let api = zcash_voting::wire::VanWitness {
            auth_path: witness,
            position: 7,
            anchor_height: 123,
        };

        assert_eq!(api.auth_path[0], vec![1; 32]);
        assert_eq!(api.auth_path[1], vec![2; 32]);
        assert_eq!(api.position, 7);
        assert_eq!(api.anchor_height, 123);
    }

    #[test]
    fn api_note_selection_result_preserves_core_fields() {
        let divisor = zcash_voting::governance::BALLOT_DIVISOR;
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), "wallet-api-selection").unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        let selected = zcash_voting::SelectedNotes {
            notes: vec![
                test_note_ref(divisor / 2, divisor / 2, 3),
                test_note_ref(divisor / 2, divisor / 2, 7),
            ],
            snapshot_height: 100,
            anchor_tree_state: test_tree_state(100),
        };

        let api = zcash_voting::wire::VotingNoteSelectionResultView::from_selected_for_round(
            selected, &db, ROUND_ID,
        )
        .unwrap();

        assert_eq!(api.note_count, 2);
        // Two half-ballot notes fit one bundle, so nothing is trimmed.
        assert_eq!(api.privacy_trim, Default::default());
        assert_eq!(api.eligible_weight_zatoshi, divisor);
        assert_eq!(api.snapshot_height, 100);
        assert_eq!(api.anchor_height, 100);
        assert_eq!(api.notes[0].commitment_tree_position, 3);
        assert_eq!(api.notes[1].value_zatoshi, divisor / 2);
        assert_eq!(api.notes[1].voting_weight_zatoshi, divisor / 2);
    }

    #[test]
    fn delete_skipped_bundles_api_is_bundle_indexed() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), "wallet-api-bundles").unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();

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
        assert_eq!(db.get_bundle_count(ROUND_ID).unwrap(), 1);
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
        let db = db::open_voting_db(db_path.to_str().unwrap(), "wallet-api-witness").unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        store_test_confirmed_van(&db, ROUND_ID, 0, 0);
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            "wallet-api-witness".to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();
        let witness = zcash_voting::precompute::van_witness(&db, ROUND_ID, 0, height).unwrap();

        assert_eq!(witness.position, 0);
        assert_eq!(witness.anchor_height, 1);
        assert_eq!(
            witness.auth_path.len(),
            zcash_voting::vote::VAN_AUTH_PATH_LEN
        );
        assert!(witness.auth_path.iter().all(|hash| hash.len() == 32));
    }

    #[test]
    fn reset_voting_session_state_with_round_drops_target_tree_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let account_uuid = "wallet-api-round-reset";
        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        store_test_confirmed_van(&db, ROUND_ID, 0, 0);
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            Some(ROUND_ID.to_string()),
        )
        .unwrap();

        assert!(zcash_voting::precompute::van_witness(&db, ROUND_ID, 0, height).is_err());
    }

    #[test]
    fn reset_voting_session_state_with_round_keeps_other_round_tree_sync() {
        const OTHER_ROUND_ID: &str =
            "0000000000000000000000000000000000000000000000000000000000000002";
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let account_uuid = "wallet-api-round-scope-reset";
        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        let mut other_round_params = test_api_round_params();
        other_round_params.vote_round_id = OTHER_ROUND_ID.to_string();
        db.init_round(zcash_voting::Network::Regtest, &other_round_params, None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        store_test_confirmed_van(&db, ROUND_ID, 0, 0);
        db.ensure_bundles(OTHER_ROUND_ID, &[test_note_info(0)])
            .unwrap();
        store_test_confirmed_van(&db, OTHER_ROUND_ID, 0, 0);

        let server_round_one = start_tree_server(1, vec![fp_one_base64()], 3);
        let round_one_height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
            server_round_one,
        )
        .unwrap();

        let server_round_two = start_tree_server(1, vec![fp_one_base64()], 3);
        let round_two_height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            OTHER_ROUND_ID.to_string(),
            server_round_two,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            Some(ROUND_ID.to_string()),
        )
        .unwrap();

        assert!(zcash_voting::precompute::van_witness(&db, ROUND_ID, 0, round_one_height).is_err());

        let round_two_witness = zcash_voting::precompute::van_witness(&db, OTHER_ROUND_ID, 0, round_two_height).unwrap();
        assert_eq!(round_two_witness.position, 0);
    }

    #[test]
    fn reset_voting_session_state_without_round_drops_tree_sync() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let account_uuid = "wallet-api-account-reset";
        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        store_test_confirmed_van(&db, ROUND_ID, 0, 0);
        let server = start_tree_server(1, vec![fp_one_base64()], 3);

        let height = sync_vote_tree(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
            server,
        )
        .unwrap();

        reset_voting_session_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            None,
        )
        .unwrap();

        assert!(zcash_voting::precompute::van_witness(&db, ROUND_ID, 0, height).is_err());
    }

    #[test]
    fn recovery_api_preserves_round_summary_and_share_records() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let account_uuid = "wallet-api-recovery";
        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        let conn = db.conn();
        zcash_voting::storage::queries::store_vote(
            &conn,
            ROUND_ID,
            account_uuid,
            1,
            2,
            1,
            b"vote-1",
        )
        .unwrap();
        drop(conn);
        db.mark_vote_submitted(ROUND_ID, 1, 2, "vote-tx-1-2")
            .unwrap();
        {
            let conn = db.conn();
            conn.execute(
                "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = :pos
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":json": test_vote_recovery_json(1, 2, 1, 99),
                    ":pos": 99i64,
                    ":round_id": ROUND_ID,
                    ":wallet_id": account_uuid,
                    ":bundle_index": 1i64,
                    ":proposal_id": 2i64,
                },
            )
            .unwrap();
        }
        zcash_voting::share::record_delivery_fixture(
            &db,
            ROUND_ID,
            1,
            2,
            0,
            &["https://helper.example".to_string()],
            &["https://helper-unknown.example".to_string()],
            2,
            123,
        )
        .unwrap();

        let state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();

        assert_eq!(state.bundle_count, 2);
        assert_eq!(
            state.delegation[0].tx_hash.as_deref(),
            Some("delegation-tx-0")
        );
        assert_eq!(state.votes[0].proposal_id, 2);
        assert_eq!(state.votes[0].tx_hash.as_deref(), Some("vote-tx-1-2"));
        assert_eq!(state.commitment_bundles[0].vc_tree_position, 99);
        assert_eq!(state.share_delegations[0].sent_to_urls.len(), 1);
        assert_eq!(
            state.share_delegations[0].ambiguous_urls,
            vec!["https://helper-unknown.example"]
        );
        assert_eq!(state.share_delegations[0].target_count, 2);
        assert_eq!(state.unconfirmed_share_delegations.len(), 1);

        let db = db::open_voting_db(db_path.to_str().unwrap(), account_uuid).unwrap();
        db.conn()
            .execute(
                "UPDATE share_delegations SET confirmed = 1
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index
                   AND proposal_id = :proposal_id
                   AND share_index = :share_index",
                rusqlite::named_params! {
                    ":round_id": ROUND_ID,
                    ":wallet_id": account_uuid,
                    ":bundle_index": 1i64,
                    ":proposal_id": 2i64,
                    ":share_index": 0i64,
                },
            )
            .unwrap();
        let confirmed_state = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            account_uuid.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert!(confirmed_state.unconfirmed_share_delegations.is_empty());
    }

    #[test]
    fn delete_voting_account_state_clears_target_account_rounds_only() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let target_account_uuid = "wallet-delete-target";
        let other_account_uuid = "wallet-delete-other";

        let target_db = db::open_voting_db(db_path.to_str().unwrap(), target_account_uuid).unwrap();
        target_db
            .init_round(
                zcash_voting::Network::Regtest,
                &test_api_round_params(),
                None,
            )
            .unwrap();
        target_db
            .ensure_bundles(ROUND_ID, &[test_note_info(0)])
            .unwrap();

        let other_db = db::open_voting_db(db_path.to_str().unwrap(), other_account_uuid).unwrap();
        other_db
            .init_round(
                zcash_voting::Network::Regtest,
                &test_api_round_params(),
                None,
            )
            .unwrap();
        other_db
            .ensure_bundles(ROUND_ID, &[test_note_info(1)])
            .unwrap();
        drop(target_db);
        drop(other_db);

        let deleted = delete_voting_account_state(
            db_path.to_str().unwrap().to_string(),
            target_account_uuid.to_string(),
        )
        .unwrap();

        let target_db = db::open_voting_db(db_path.to_str().unwrap(), target_account_uuid).unwrap();
        let other_db = db::open_voting_db(db_path.to_str().unwrap(), other_account_uuid).unwrap();
        assert_eq!(deleted, 1);
        assert!(target_db.list_rounds().unwrap().is_empty());
        assert_eq!(other_db.list_rounds().unwrap().len(), 1);
        assert_eq!(other_db.get_bundle_count(ROUND_ID).unwrap(), 1);
    }

    #[test]
    fn delete_voting_account_state_clears_roundless_pir_cache() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let target_account_uuid = "wallet-delete-pir-target";
        let other_account_uuid = "wallet-delete-pir-other";

        let target_db = db::open_voting_db(db_path.to_str().unwrap(), target_account_uuid).unwrap();
        seed_pir_cache_row(&target_db, target_account_uuid, 0x11);
        assert!(target_db.list_rounds().unwrap().is_empty());
        assert_eq!(pir_cache_row_count(&target_db, target_account_uuid), 1);
        drop(target_db);

        let other_db = db::open_voting_db(db_path.to_str().unwrap(), other_account_uuid).unwrap();
        seed_pir_cache_row(&other_db, other_account_uuid, 0x22);
        assert_eq!(pir_cache_row_count(&other_db, other_account_uuid), 1);
        drop(other_db);

        let deleted = delete_voting_account_state(
            db_path.to_str().unwrap().to_string(),
            target_account_uuid.to_string(),
        )
        .unwrap();
        assert_eq!(deleted, 0);

        let target_db = db::open_voting_db(db_path.to_str().unwrap(), target_account_uuid).unwrap();
        let other_db = db::open_voting_db(db_path.to_str().unwrap(), other_account_uuid).unwrap();
        assert_eq!(pir_cache_row_count(&target_db, target_account_uuid), 0);
        assert_eq!(pir_cache_row_count(&other_db, other_account_uuid), 1);
    }

    #[test]
    fn list_pending_share_rounds_preserves_session_context() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let sidecar_path = zcash_voting::storage::VotingDb::wallet_sidecar_path(&db_path);
        assert!(list_pending_share_rounds(
            db_path.to_str().unwrap().to_string(),
            vec![TEST_ACCOUNT_UUID.to_string()],
        )
        .unwrap()
        .is_empty());
        assert!(!sidecar_path.exists());

        let session_json = r#"{"vote_end_time":4102444800}"#;
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            Some(session_json),
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        seed_recovery_vote(&db, TEST_ACCOUNT_UUID, 0, 7, 1, 88);
        zcash_voting::share::record_delivery_fixture(
            &db,
            ROUND_ID,
            0,
            7,
            0,
            &["https://helper.example".to_string()],
            &[],
            1,
            123,
        )
        .unwrap();
        drop(db);

        assert_eq!(
            list_pending_share_rounds(
                db_path.to_str().unwrap().to_string(),
                vec![TEST_ACCOUNT_UUID.to_string(), TEST_ACCOUNT_UUID.to_string()],
            )
            .unwrap(),
            vec![ApiPendingShareRound {
                account_uuid: TEST_ACCOUNT_UUID.to_string(),
                round_id: ROUND_ID.to_string(),
                session_json: Some(session_json.to_string()),
            }]
        );
    }

    #[test]
    fn keystone_signature_round_trip_and_length_validation() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();

        let signature = |sig_len: usize| ApiKeystoneSignatureInput {
            bundle_index: 0,
            sig: vec![7; sig_len],
            sighash: vec![8; KEYSTONE_SIGHASH_LEN],
            rk: vec![9; KEYSTONE_RK_LEN],
        };
        store_keystone_signatures_batch(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![signature(KEYSTONE_SIG_LEN)],
        )
        .unwrap();
        let records = get_keystone_signatures(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();

        assert_eq!(records.len(), 1);
        assert_eq!(records[0].bundle_index, 0);
        assert_eq!(records[0].sig, vec![7; KEYSTONE_SIG_LEN]);

        let err = store_keystone_signatures_batch(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![signature(KEYSTONE_SIG_LEN - 1)],
        )
        .unwrap_err();
        assert!(err.message.contains("sig must be exactly"), "{err}");
    }

    #[test]
    fn keystone_signature_batch_accepts_resigning_same_context_and_rejects_conflicts() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        drop(db);

        let signature = ApiKeystoneSignatureInput {
            bundle_index: 0,
            sig: vec![7; KEYSTONE_SIG_LEN],
            sighash: vec![8; KEYSTONE_SIGHASH_LEN],
            rk: vec![9; KEYSTONE_RK_LEN],
        };
        let first = store_keystone_signatures_batch(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![signature.clone()],
        )
        .unwrap();
        assert_eq!(first.inserted, 1);
        assert_eq!(first.already_present, 0);

        let retry = store_keystone_signatures_batch(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![signature.clone()],
        )
        .unwrap();
        assert_eq!(retry.inserted, 0);
        assert_eq!(retry.already_present, 1);

        let resigned = store_keystone_signatures_batch(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![ApiKeystoneSignatureInput {
                sig: vec![10; KEYSTONE_SIG_LEN],
                ..signature.clone()
            }],
        )
        .unwrap();
        assert_eq!(resigned.inserted, 0);
        assert_eq!(resigned.already_present, 1);

        let records = get_keystone_signatures(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert_eq!(records[0].sig, vec![7; KEYSTONE_SIG_LEN]);

        let conflict = store_keystone_signatures_batch(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![ApiKeystoneSignatureInput {
                sighash: vec![11; KEYSTONE_SIGHASH_LEN],
                ..signature
            }],
        )
        .unwrap_err();
        assert_eq!(
            conflict.kind,
            zcash_voting::wire::VotingErrorKindView::KeystoneSignatureConflict
        );
        assert_eq!(conflict.bundle_index, Some(0));
        let records = get_keystone_signatures(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert_eq!(records[0].sig, vec![7; KEYSTONE_SIG_LEN]);
    }

    #[test]
    fn keystone_signature_batch_rolls_back_on_later_insert_failure() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        drop(db);

        let input = |bundle_index| ApiKeystoneSignatureInput {
            bundle_index,
            sig: vec![7; KEYSTONE_SIG_LEN],
            sighash: vec![8; KEYSTONE_SIGHASH_LEN],
            rk: vec![9; KEYSTONE_RK_LEN],
        };
        let err = store_keystone_signatures_batch(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![input(0), input(99)],
        )
        .unwrap_err();
        assert!(err.message.contains("bundle 99"));

        let records = get_keystone_signatures(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert!(records.is_empty());
    }

    #[test]
    fn set_ballot_intent_persists_choice_and_skipped() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();

        set_ballot_intent(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            1,
            3,
            false,
            Some(2),
        )
        .unwrap();
        set_ballot_intent(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            2,
            3,
            true,
            None,
        )
        .unwrap();

        let err = set_ballot_intent(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            3,
            3,
            false,
            None,
        )
        .unwrap_err();
        assert!(err.message.contains("choice must be Some"));
    }

    #[test]
    fn round_plan_happy_path_returns_round_and_open_proposals() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();

        let plan = get_round_plan(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
            vec![1, 2],
        )
        .unwrap();

        assert_eq!(plan.round_id, ROUND_ID);
        assert_eq!(plan.open_proposals, vec![1, 2]);
    }

    #[test]
    fn mark_delegation_submitted_updates_recovery_snapshot() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = db::open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &test_api_round_params(),
            None,
        )
        .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();

        db.mark_delegation_submitted(ROUND_ID, 0, "delegation-submitted-tx")
            .unwrap();

        let snapshot = get_round_recovery_state(
            db_path.to_str().unwrap().to_string(),
            TEST_ACCOUNT_UUID.to_string(),
            ROUND_ID.to_string(),
        )
        .unwrap();
        assert_eq!(snapshot.delegation.len(), 1);
        assert_eq!(
            snapshot.delegation[0].tx_hash.as_deref(),
            Some("delegation-submitted-tx")
        );
    }

    #[test]
    fn setup_delegation_bundles_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(setup_delegation_bundles(test_round_context(
                &db_path, "bogus", "wallet-1",
            )))
            .unwrap_err();

        assert!(err.message.contains("Unknown network"));
    }

    #[test]
    fn precompute_snapshot_bundles_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(precompute_snapshot_bundles(
                test_round_context(&db_path, "bogus", "wallet-1"),
                "http://127.0.0.1:2".to_string(),
            ))
            .unwrap_err();

        assert!(err.message.contains("Unknown network"));
    }

    #[test]
    fn precompute_snapshot_bundles_rejects_empty_pir_url_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(precompute_snapshot_bundles(
                test_round_context(&db_path, "regtest", "wallet-1"),
                "  ".to_string(),
            ))
            .unwrap_err();

        assert!(err.message.contains("must not contain an empty URL"), "{err}");
    }

    #[test]
    fn precompute_delegation_proof_rejects_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(precompute_delegation_proof(
                test_round_context(&db_path, "bogus", "wallet-1"),
                vec!["http://127.0.0.1:2".to_string()],
                vec![9; 64],
                0,
            ))
            .unwrap_err();

        assert!(err.message.contains("Unknown network"));
    }

    #[test]
    fn precompute_delegation_proof_rejects_invalid_hotkey_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(precompute_delegation_proof(
                test_round_context(&db_path, "regtest", "wallet-1"),
                vec!["http://127.0.0.1:2".to_string()],
                vec![9; 1],
                0,
            ))
            .unwrap_err();

        assert!(err.message.contains("Voting hotkey reconstruction failed"));
    }

    #[test]
    fn build_keystone_delegation_requests_reject_invalid_network_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_keystone_delegation_requests(
                test_round_context(&db_path, "bogus", "wallet-1"),
                vec![9; 64],
                vec![0],
            ))
            .unwrap_err();

        assert!(err.message.contains("Unknown network"));
    }

    #[test]
    fn build_keystone_delegation_requests_reject_invalid_hotkey_before_network_io() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_keystone_delegation_requests(
                test_round_context(&db_path, "regtest", "wallet-1"),
                vec![9; 1],
                vec![0],
            ))
            .unwrap_err();

        assert!(err.message.contains("Voting hotkey reconstruction failed"));
    }

    #[test]
    fn build_keystone_delegation_requests_rejects_empty_bundle_indexes() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_keystone_delegation_requests(
                test_round_context(&db_path, "regtest", "wallet-1"),
                vec![9; 64],
                vec![],
            ))
            .unwrap_err();

        assert!(err.message.contains("must not be empty"));
    }

    #[test]
    fn build_keystone_delegation_requests_rejects_duplicate_bundle_indexes() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_keystone_delegation_requests(
                test_round_context(&db_path, "regtest", "wallet-1"),
                vec![9; 64],
                vec![1, 1],
            ))
            .unwrap_err();

        assert!(err.message.contains("must be unique"));
    }

    #[test]
    fn dynamic_config_attempt_dto_maps_both_outcomes() {
        let fetched: DynamicConfigAttempt = ApiDynamicConfigAttempt {
            url: "https://mirror.example/dynamic.json".to_string(),
            bytes: Some(b"{}".to_vec()),
            error: None,
        }
        .into();
        assert_eq!(fetched.result.as_deref(), Ok(b"{}".as_slice()));

        let failed: DynamicConfigAttempt = ApiDynamicConfigAttempt {
            url: "https://mirror.example/dynamic.json".to_string(),
            bytes: None,
            error: Some("dns error".to_string()),
        }
        .into();
        assert_eq!(failed.result.as_ref().unwrap_err(), "dns error");

        // A caller that reports no bytes and no reason is still a failure, not
        // an empty-bodied success that would reach the resolver as valid input.
        let unexplained: DynamicConfigAttempt = ApiDynamicConfigAttempt {
            url: "https://mirror.example/dynamic.json".to_string(),
            bytes: None,
            error: None,
        }
        .into();
        assert!(unexplained.result.is_err());
    }

    fn test_vote_recovery_json(
        bundle_index: u32,
        proposal_id: u32,
        vote_decision: u32,
        vc_tree_position: u64,
    ) -> String {
        zcash_voting::vote::serialize_recovery(&zcash_voting::vote::VoteRecoveryBundle {
            vote_round_id: ROUND_ID.to_string(),
            bundle_index,
            proposal_id,
            vote_decision,
            anchor_height: 100,
            vc_tree_position,
            single_share: false,
            num_options: 2,
            van_nullifier: [1u8; 32],
            vote_authority_note_new: [2u8; 32],
            vote_commitment: [3u8; 32],
            proof: vec![4u8; 8],
            shares_hash: [5u8; 32],
            r_vpk: [6u8; 32],
            alpha_v: [7u8; 32],
            vote_auth_sig: [8u8; 64],
            encrypted_shares: vec![zcash_voting::EncryptedShare {
                c1: point_bytes(9),
                c2: point_bytes(10),
                share_index: 0,
                plaintext_value: 1,
                randomness: vec![11u8; 32],
            }],
            share_blinds: vec![[12u8; 32]],
            share_comms: full_share_comms(),
            batch: None,
        })
        .unwrap()
    }

    fn seed_recovery_vote(
        db: &zcash_voting::storage::VotingDb,
        account_uuid: &str,
        bundle_index: u32,
        proposal_id: u32,
        vote_decision: u32,
        vc_tree_position: u64,
    ) {
        let recovery_json =
            test_vote_recovery_json(bundle_index, proposal_id, vote_decision, vc_tree_position);
        let recovery = zcash_voting::vote::parse_recovery(&recovery_json).unwrap();
        let commitment_bytes = serde_json::to_vec(&serde_json::json!({
            "van_nullifier": hex::encode(recovery.van_nullifier),
            "vote_authority_note_new": hex::encode(recovery.vote_authority_note_new),
            "vote_commitment": hex::encode(recovery.vote_commitment),
            "proof": hex::encode(recovery.proof),
        }))
        .unwrap();
        zcash_voting::storage::queries::store_vote(
            &db.conn(),
            ROUND_ID,
            account_uuid,
            bundle_index,
            proposal_id,
            vote_decision,
            &commitment_bytes,
        )
        .unwrap();
        db.conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = :json
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":json": recovery_json,
                    ":round_id": ROUND_ID,
                    ":wallet_id": account_uuid,
                    ":bundle_index": i64::from(bundle_index),
                    ":proposal_id": i64::from(proposal_id),
                },
            )
            .unwrap();
    }

    fn seed_pir_cache_row(db: &zcash_voting::storage::VotingDb, wallet_id: &str, marker: u8) {
        db.conn()
            .execute(
                "INSERT INTO pir_proof_cache
                    (wallet_id, network, nullifier, root, nf_bounds, leaf_pos, path, created_at, updated_at)
                 VALUES (:wallet_id, 'regtest', :nullifier, :root, X'00', 0, X'00', 1, 1)",
                rusqlite::named_params! {
                    ":wallet_id": wallet_id,
                    ":nullifier": [marker; 32],
                    ":root": [marker.wrapping_add(1); 32],
                },
            )
            .unwrap();
    }

    fn pir_cache_row_count(db: &zcash_voting::storage::VotingDb, wallet_id: &str) -> i64 {
        db.conn()
            .query_row(
                "SELECT COUNT(*) FROM pir_proof_cache WHERE wallet_id = :wallet_id",
                rusqlite::named_params! { ":wallet_id": wallet_id },
                |row| row.get(0),
            )
            .unwrap()
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
    ) -> zcash_voting::NoteRef {
        zcash_voting::NoteRef {
            pool: "orchard".to_string(),
            txid_hex: hex::encode([commitment_tree_position as u8; 32]),
            output_index: commitment_tree_position as u32,
            value_zatoshi,
            voting_weight_zatoshi,
            commitment: vec![commitment_tree_position as u8; 32],
            nullifier: vec![commitment_tree_position as u8 ^ 0xaa; 32],
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

    struct MockTreeBlock {
        height: u32,
        start_index: usize,
        leaf: String,
        root: String,
    }

    fn start_tree_server(height: u32, leaves: Vec<String>, expected_requests: usize) -> String {
        let (latest_root, blocks) = mock_tree_blocks(&leaves);
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
                let body = tree_response_body(path, height, latest_root.as_deref(), &blocks);
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

    fn start_share_status_server() -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0u8; 2048];
            let len = stream.read(&mut request).unwrap();
            let request = String::from_utf8_lossy(&request[..len]);
            assert!(request
                .lines()
                .next()
                .is_some_and(|line| line.contains("/shielded-vote/v1/share-status/")));
            let body = r#"{"status":"confirmed"}"#;
            let response = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            stream.write_all(response.as_bytes()).unwrap();
        });
        url
    }

    fn tree_response_body(
        path: &str,
        height: u32,
        latest_root: Option<&str>,
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
                    return r#"{"blocks":[],"next_from_height":0}"#.to_string();
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

    fn mock_tree_blocks(leaves: &[String]) -> (Option<String>, Vec<MockTreeBlock>) {
        let mut server = vote_commitment_tree::MemoryTreeServer::empty();
        let mut blocks = Vec::new();

        for (idx, leaf_b64) in leaves.iter().enumerate() {
            let leaf_bytes = base64::engine::general_purpose::STANDARD
                .decode(leaf_b64)
                .unwrap();
            let leaf_bytes: [u8; 32] = leaf_bytes.try_into().unwrap();
            let leaf = vote_commitment_tree::MerkleHashVote::from_bytes(&leaf_bytes).unwrap();
            let height = (idx + 1) as u32;
            server.append(leaf.inner()).unwrap();
            server.checkpoint(height).unwrap();
            let root = vote_commitment_tree::MerkleHashVote::from_fp(server.root());
            blocks.push(MockTreeBlock {
                height,
                start_index: idx,
                leaf: leaf_b64.clone(),
                root: base64::engine::general_purpose::STANDARD.encode(root.to_bytes()),
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

    fn fp_one_base64() -> String {
        "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=".to_string()
    }

    /// Seeds the commitment and leaf position that a real confirmed delegation
    /// persists in separate proof-generation and confirmation steps.
    fn store_test_confirmed_van(
        db: &zcash_voting::storage::VotingDb,
        round_id: &str,
        bundle_index: u32,
        position: u32,
    ) {
        let commitment = base64::engine::general_purpose::STANDARD
            .decode(fp_one_base64())
            .unwrap();
        db.conn()
            .execute(
                "UPDATE bundles SET gov_comm = ?1
                 WHERE round_id = ?2 AND wallet_id = ?3 AND bundle_index = ?4",
                rusqlite::params![
                    commitment,
                    round_id,
                    db.wallet_id(),
                    i64::from(bundle_index)
                ],
            )
            .unwrap();
        db.store_van_position(round_id, bundle_index, position)
            .unwrap();
    }
}
