//! Delegation stages for the FRB boundary, driven by the SDK pipeline.
//!
//! `zcash_voting::DelegationPipeline` owns note selection, bundle setup,
//! witnesses, PIR warm-up with endpoint failover, proving, and signing. Vizor
//! keeps only what the SDK deliberately leaves to the host: the lightwalletd
//! anchor fetched over the wallet's network route, the wallet-database opener,
//! the seed-owning signer, and the choice of PIR transport.
//!
//! PIR proof fetches deliberately use the SDK's direct HTTP transport rather
//! than the Tor route; the settings copy discloses this.

use std::sync::Arc;

use zcash_voting::config::PirLayout;
pub use zcash_voting::delegate::DelegationProgress;
use zcash_voting::delegate::{
    DelegationLwdInputs, DelegationProofStatus,
};
use zcash_voting::precompute::SnapshotBundlePrecomputeReport;
use zcash_voting::round::BundleLayout;
use zcash_voting::selection::select_notes_with_wallet_db;
pub use zcash_voting::VotingEligibilityReport;
use zcash_voting::{
    BundlePolicy, DelegationPipeline, HyperTransport,
    NoopProgressReporter, PirFleet, VotingError, VotingHotkey,
    WalletDbOpener,
};

use crate::wallet::db::WalletDatabase;
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync::open_wallet_db_for_read;
use crate::wallet::voting::network::wallet_network;

use super::db::open_voting_db;
use super::transport::fetch_snapshot_tree_state;

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

/// Round inputs every delegation stage needs.
#[derive(Clone, Debug)]
pub struct RoundInputs {
    pub db_path: String,
    pub account_uuid: String,
    pub lightwalletd_url: String,
    pub network: zcash_voting::Network,
    pub round_params: zcash_voting::wire::VotingRoundParams,
    pub round_name: String,
    pub session_json: Option<String>,
    pub bundle_policy: BundlePolicy,
}

/// Opens the wallet database for reads through Vizor's busy-timeout settings.
pub struct VizorWalletDbOpener {
    db_path: String,
    network: WalletNetwork,
}

impl WalletDbOpener for VizorWalletDbOpener {
    type Conn = rusqlite::Connection;
    type Params = WalletNetwork;
    type Clock = zcash_client_sqlite::util::SystemClock;
    type Rng = voting_crypto_deps::rand::rngs::OsRng;

    fn open_for_read(&self) -> Result<WalletDatabase, VotingError> {
        open_wallet_db_for_read(&self.db_path, self.network)
            .map_err(|message| VotingError::Storage { message })
    }
}

pub type VizorDelegationPipeline = DelegationPipeline<VizorWalletDbOpener>;

/// Binds the SDK pipeline for `inputs`, fetching the snapshot anchor over the
/// wallet's network route first.
pub async fn open_pipeline(
    inputs: &RoundInputs,
    hotkey: Option<VotingHotkey>,
) -> Result<Arc<VizorDelegationPipeline>, VotingError> {
    zcash_voting::validate_round_params(&inputs.round_params)
        .map_err(|error| invalid_input(format!("Invalid voting round params: {error}")))?;
    let tree_state =
        fetch_snapshot_tree_state(&inputs.lightwalletd_url, inputs.round_params.snapshot_height)
            .await
            .map_err(internal)?;
    let lwd = DelegationLwdInputs::from_anchor_tree_state(
        inputs.network,
        inputs.round_params.clone(),
        &inputs.round_name,
        &tree_state,
    )?;
    let voting_db = open_voting_db(&inputs.db_path, &inputs.account_uuid)?;
    let opener = VizorWalletDbOpener {
        db_path: inputs.db_path.clone(),
        network: wallet_network(inputs.network),
    };
    DelegationPipeline::new(
        voting_db,
        opener,
        lwd,
        &inputs.account_uuid,
        hotkey,
        inputs.bundle_policy,
        inputs.session_json.as_deref(),
    )
    .map(Arc::new)
}

/// PIR fleet over the SDK's direct HTTP transport.
pub fn pir_fleet(
    pir_server_urls: &[String],
    pir_layout: PirLayout,
) -> Result<Arc<PirFleet>, VotingError> {
    PirFleet::new(pir_server_urls, pir_layout, Arc::new(HyperTransport::new())).map(Arc::new)
}

async fn blocking<T: Send + 'static>(
    label: &'static str,
    work: impl FnOnce() -> Result<T, VotingError> + Send + 'static,
) -> Result<T, VotingError> {
    tokio::task::spawn_blocking(work)
        .await
        .map_err(|error| internal(format!("{label} task failed: {error}")))?
}

/// Runs proving work on a dedicated large-stack thread.
async fn proving<T: Send + 'static>(
    label: &'static str,
    work: impl FnOnce() -> Result<T, VotingError> + Send + 'static,
) -> Result<T, VotingError> {
    const PROVING_STACK_BYTES: usize = 64 * 1024 * 1024;
    let (tx, rx) = tokio::sync::oneshot::channel();
    std::thread::Builder::new()
        .name(format!("voting-{label}"))
        .stack_size(PROVING_STACK_BYTES)
        .spawn(move || {
            let _ = tx.send(work());
        })
        .map_err(|error| internal(format!("failed to spawn {label} thread: {error}")))?;
    rx.await
        .map_err(|_| internal(format!("{label} thread exited without a result")))?
}

/// Start process-lifetime Halo2 proving-key warm-up if it has not started yet.
pub fn start_proving_cache_warmup() {
    zcash_voting::start_proving_cache_warmup();
}

/// Select notes and create/reuse delegation bundle rows for a round.
pub async fn setup_delegation_bundles(inputs: RoundInputs) -> Result<BundleLayout, VotingError> {
    let pipeline = open_pipeline(&inputs, None).await?;
    blocking("bundle setup", move || pipeline.setup_bundles()).await
}

/// Select notes and check whether a wallet can vote without persisting bundles.
///
/// Eligibility failures carry the snapshot height so the app can say which
/// block the check was made at.
pub async fn check_voting_eligibility(
    inputs: RoundInputs,
) -> Result<VotingEligibilityReport, VotingError> {
    let snapshot_height = inputs.round_params.snapshot_height;
    let pipeline = open_pipeline(&inputs, None).await?;
    blocking("eligibility", move || {
        pipeline
            .eligibility()
            .map_err(|error| error.with_snapshot_height(snapshot_height))
    })
    .await
}

/// Persist the snapshot-stable bundle plan and warm PIR for every bundle.
pub async fn precompute_snapshot_bundles(
    inputs: RoundInputs,
    pir_server_url: &str,
    pir_layout: PirLayout,
) -> Result<SnapshotBundlePrecomputeReport, VotingError> {
    start_proving_cache_warmup();
    let fleet = pir_fleet(&[pir_server_url.to_string()], pir_layout)?;
    let pipeline = open_pipeline(&inputs, None).await?;
    let network = inputs.network;
    let bundle_policy = inputs.bundle_policy;
    blocking("snapshot bundle precompute", move || {
        pipeline.ensure_round()?;
        let notes = pipeline.select_notes()?;
        let round_id = pipeline.round_id().to_string();
        fleet.with_failover(|session| {
            zcash_voting::precompute::precompute_snapshot_bundles(
                &pipeline.voting_db(),
                &round_id,
                &notes,
                bundle_policy,
                session,
                network,
            )
        })
    })
    .await
}

/// Prepare and persist ZKP1 for a software or Keystone bundle without signing.
///
/// Returns `true` when this call generated the proof and `false` when a
/// persisted proof was reused.
pub async fn precompute_delegation_proof(
    inputs: RoundInputs,
    pir_server_urls: &[String],
    pir_layout: PirLayout,
    hotkey: VotingHotkey,
    bundle_index: u32,
) -> Result<bool, VotingError> {
    let fleet = pir_fleet(pir_server_urls, pir_layout)?;
    let pipeline = open_pipeline(&inputs, Some(hotkey)).await?;
    let status = proving("delegation-proof", move || {
        pipeline.ensure_proof(bundle_index, &fleet, &NoopProgressReporter)
    })
    .await?;
    Ok(matches!(status, DelegationProofStatus::Generated))
}

/// Outcome of the bundle-independent background PIR proof cache warm-up.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PirCacheWarmupOutcome {
    pub note_count: u32,
    pub cached_count: u32,
    pub fetched_count: u32,
    pub served_root: Vec<u8>,
    /// Always `0` on this crate pin: the SDK prunes internally without a count.
    pub pruned_count: u32,
}

/// Warms the bundle-independent PIR proof cache for the account's eligible
/// notes at `snapshot_height`.
pub async fn warm_pir_proof_cache(
    db_path: &str,
    account_uuid: &str,
    lightwalletd_url: &str,
    network: zcash_voting::Network,
    snapshot_height: u64,
    pir_server_url: &str,
    pir_layout: PirLayout,
) -> Result<PirCacheWarmupOutcome, VotingError> {
    let fleet = pir_fleet(&[pir_server_url.to_string()], pir_layout)?;
    let anchor_tree_state = fetch_snapshot_tree_state(lightwalletd_url, snapshot_height)
        .await
        .map_err(|error| internal(format!("voting note selection failed: {error}")))?;
    let db_path = db_path.to_string();
    let account_uuid = account_uuid.to_string();
    let wallet_net = wallet_network(network);
    blocking("PIR proof cache warm-up", move || {
        let voting_db = open_voting_db(&db_path, &account_uuid)?;
        let wallet_db = open_wallet_db_for_read(&db_path, wallet_net)
            .map_err(|message| VotingError::Storage { message })?;
        let selected = select_notes_with_wallet_db(
            &wallet_db,
            network,
            &account_uuid,
            snapshot_height,
            anchor_tree_state,
        )?;
        let notes = selected.voting_note_infos();
        let note_count = u32::try_from(notes.len())
            .map_err(|_| internal("selected note count does not fit in u32"))?;
        let bundle_policy = zcash_voting::recoverable_bundle_policy_v1();
        let result = fleet.with_failover(|session| {
            zcash_voting::precompute::precompute_pir_proofs(
                &voting_db,
                &notes,
                bundle_policy,
                network,
                session,
            )
        })?;
        Ok(PirCacheWarmupOutcome {
            note_count,
            cached_count: result.cached_count,
            fetched_count: result.fetched_count,
            served_root: result.served_root,
            pruned_count: 0,
        })
    })
    .await
}
