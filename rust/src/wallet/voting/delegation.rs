use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, OnceLock,
    },
    thread::{self, JoinHandle},
    time::Instant,
};

use ff::PrimeField;
use prost::Message;
use secrecy::{ExposeSecret, SecretVec};
use zcash_keys::keys::UnifiedSpendingKey;
use zip32::{fingerprint::SeedFingerprint, AccountId};

use crate::wallet::sync::open_wallet_db_for_read;
use crate::wallet::voting::network::wallet_network;

use super::db::{
    open_voting_db, retry_voting_db_locks, retry_voting_db_locks_coordinated,
    with_open_voting_db_write, with_voting_sidecar_write_lock,
};
use super::transport::fetch_snapshot_tree_state;

use zcash_voting::config::PirLayout;
pub use zcash_voting::delegate::DelegationProgress;
use zcash_voting::delegate::{
    DelegationSigningRequest, LoadPreparedDelegationRoundParams, PrepareDelegationBundleParams,
    PreparedDelegationBundle, PreparedDelegationBundleSignature, PreparedDelegationProof,
    PreparedDelegationRound,
};
use zcash_voting::selection::{select_notes_with_lwd, select_notes_with_wallet_db};
use zcash_voting::storage::VotingDb;
use zcash_voting::BundlePolicy;

const ZATOSHI_PER_ZEC: u64 = 100_000_000;
const WHALE_PROTECTION_BUNDLE_ADDITION_THRESHOLD_ZATOSHI: u64 = 25_000 * ZATOSHI_PER_ZEC;
// Matches zcash_voting / voting-circuits keygen warm-up threads.
const PROVING_CACHE_STACK_BYTES: usize = 64 * 1024 * 1024;
const MAX_CONCURRENT_DELEGATION_PROOFS: usize = 3;

static PROVING_CACHE_WARMUP_STARTED: OnceLock<()> = OnceLock::new();
/// Start a new bundle before adding a note would cross the whale threshold.
///
/// `zcash_voting` owns the final bundle planning. Vizor only supplies the
/// threshold used when deciding whether another note can join a bundle.
fn whale_protected_bundle_policy(bundle_policy: BundlePolicy) -> BundlePolicy {
    bundle_policy.with_bundle_addition_threshold(WHALE_PROTECTION_BUNDLE_ADDITION_THRESHOLD_ZATOSHI)
}

fn prepare_params_with_whale_protection<'a>(
    mut prepare_params: PrepareDelegationBundleParams<'a>,
) -> PrepareDelegationBundleParams<'a> {
    prepare_params.bundle_policy = whale_protected_bundle_policy(prepare_params.bundle_policy);
    prepare_params
}

pub(crate) fn normalize_bundle_indexes(bundle_indexes: &[u32]) -> Result<Vec<u32>, String> {
    if bundle_indexes.is_empty() {
        return Err("delegation bundle indexes must not be empty".to_string());
    }
    let mut normalized = bundle_indexes.to_vec();
    normalized.sort_unstable();
    if normalized.windows(2).any(|pair| pair[0] == pair[1]) {
        return Err("delegation bundle indexes must be unique".to_string());
    }
    Ok(normalized)
}

fn normalize_pir_server_urls(pir_server_urls: &[String]) -> Result<Vec<String>, String> {
    let mut normalized = Vec::with_capacity(pir_server_urls.len());
    for raw_url in pir_server_urls {
        let url = raw_url.trim();
        if url.is_empty() {
            return Err("PIR server URLs must not contain an empty URL".to_string());
        }
        if !normalized.iter().any(|existing| existing == url) {
            normalized.push(url.to_string());
        }
    }
    if normalized.is_empty() {
        return Err("at least one PIR server URL is required".to_string());
    }
    Ok(normalized)
}

/// Logs delegation progress so a stalled UI wheel can be correlated with Rust
/// work. The UI ring only fills after the first `ProofProgress` value above 0.
fn wrap_progress_with_timing<F>(
    bundle_index: u32,
    started: Instant,
    on_progress: F,
) -> impl Fn(DelegationProgress) + Send + Sync + 'static
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let first_event = AtomicBool::new(true);
    let first_moving = AtomicBool::new(true);
    move |progress| {
        let elapsed = started.elapsed().as_secs_f64();
        let is_first = first_event.swap(false, Ordering::Relaxed);
        match progress {
            DelegationProgress::ProofProgress(value) => {
                if is_first {
                    log::info!(
                        "[VOTING_PROVE] bundle={bundle_index} \
                         progress=proof_progress={value:.3} first_event=true \
                         elapsed={elapsed:.3}s"
                    );
                }
                if value > 0.0 && first_moving.swap(false, Ordering::Relaxed) {
                    log::info!(
                        "[VOTING_PROVE] bundle={bundle_index} \
                         progress=proof_progress={value:.3} wheel_moving=true \
                         elapsed={elapsed:.3}s"
                    );
                }
            }
            other => {
                log::info!(
                    "[VOTING_PROVE] bundle={bundle_index} progress={other:?} \
                     first_event={is_first} elapsed={elapsed:.3}s"
                );
            }
        }
        on_progress(progress);
    }
}

fn is_retryable_pir_query_error(error: &str) -> bool {
    let message = error.to_ascii_lowercase();
    let has_pir_context = message.contains("pir parallel fetch failed")
        || message.contains("connect to pir server failed")
        || message.contains("pir http request timed out");
    if !has_pir_context {
        return false;
    }
    if message.contains("pir http request timed out")
        || message.contains("send http request")
        || message.contains("read http response body")
    {
        return true;
    }

    ["http status ", "http "].iter().any(|prefix| {
        message.match_indices(prefix).any(|(index, prefix)| {
            let remainder = &message[index + prefix.len()..];
            let Some(digits) = remainder.get(..3) else {
                return false;
            };
            if remainder.as_bytes().get(3).is_some_and(u8::is_ascii_digit) {
                return false;
            }
            let Ok(status) = digits.parse::<u16>() else {
                return false;
            };
            status == 408 || status == 429 || (500..=599).contains(&status)
        })
    })
}

fn with_pir_endpoint_failover<T>(
    pir_server_urls: &[String],
    mut operation: impl FnMut(&str) -> Result<T, String>,
) -> Result<T, String> {
    for (attempt, url) in pir_server_urls.iter().enumerate() {
        match operation(url) {
            Ok(result) => return Ok(result),
            Err(error) => {
                let retryable = is_retryable_pir_query_error(&error);
                let has_failover = attempt + 1 < pir_server_urls.len();
                log::warn!(
                    "delegation PIR attempt failed endpoint={} attempt={}/{} retryable={} error={}",
                    url,
                    attempt + 1,
                    pir_server_urls.len(),
                    retryable,
                    error
                );
                if !retryable || !has_failover {
                    return Err(error);
                }
            }
        }
    }

    Err("delegation PIR failover exited without an endpoint attempt".to_string())
}

/// Start process-lifetime Halo2 proving-key warm-up if it has not started yet.
///
/// Returns immediately. The first proof that needs keys blocks on the shared
/// cache until this warm-up (or an inline cold keygen) finishes.
pub fn start_proving_cache_warmup() {
    if PROVING_CACHE_WARMUP_STARTED.set(()).is_err() {
        return;
    }
    let spawn_result = thread::Builder::new()
        .name("voting-proving-cache-warmup".to_string())
        .stack_size(PROVING_CACHE_STACK_BYTES)
        .spawn(|| {
            let started = Instant::now();
            log::info!("[VOTING_PROVE] proving-cache warmup start");
            zcash_voting::warm_proving_caches();
            log::info!(
                "[VOTING_PROVE] proving-cache warmup complete elapsed={:.3}s",
                started.elapsed().as_secs_f64()
            );
        });
    if let Err(error) = spawn_result {
        log::warn!(
            "[VOTING_PROVE] proving-cache warmup spawn failed: {error}; \
             prove will keygen inline if needed"
        );
    }
}

struct OwnedResultThread<T> {
    name: &'static str,
    handle: Option<JoinHandle<Result<T, String>>>,
}

impl<T> OwnedResultThread<T> {
    fn new(name: &'static str, handle: JoinHandle<Result<T, String>>) -> Self {
        Self {
            name,
            handle: Some(handle),
        }
    }

    fn join(mut self) -> Result<T, String> {
        self.handle
            .take()
            .expect("owned result thread can only be joined once")
            .join()
            .map_err(|_| format!("{} thread panicked", self.name))?
    }
}

impl<T> Drop for OwnedResultThread<T> {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            if handle.join().is_err() {
                log::warn!(
                    "[VOTING_PROVE] {} thread panicked while draining",
                    self.name
                );
            }
        }
    }
}

type PirConnectThread = OwnedResultThread<zcash_voting::PirClientBlocking>;

fn connect_pir_client(
    pir_server_url: &str,
    pir_layout: PirLayout,
) -> Result<zcash_voting::PirClientBlocking, String> {
    let started = Instant::now();
    log::info!("[VOTING_PROVE] pir-connect start");
    let client = zcash_voting::connect_pir_blocking(
        pir_layout,
        pir_server_url,
        Arc::new(zcash_voting::HyperTransport::new()),
    )
    .map_err(|e| format!("connect to PIR server failed: {e}"))?;
    log::info!(
        "[VOTING_PROVE] pir-connect complete elapsed={:.3}s",
        started.elapsed().as_secs_f64()
    );
    Ok(client)
}

fn finish_delegation_round_preparation_inner(
    db_path: &str,
    account_uuid: &str,
    round_params: &zcash_voting::VotingRoundParams,
    round_name: &str,
    voting_hotkey: &zcash_voting::VotingHotkey,
) -> Result<(VotingDb, PreparedDelegationRound), String> {
    let started = Instant::now();
    let wallet_open_started = Instant::now();
    let wallet_db = open_wallet_db_for_read(db_path, wallet_network(voting_hotkey.network()))?;
    log::info!(
        "[VOTING_TIMING] finish wallet-db-open elapsed={:.3}s",
        wallet_open_started.elapsed().as_secs_f64()
    );
    let sidecar_open_started = Instant::now();
    let voting_db = open_voting_db(db_path, account_uuid)?;
    log::info!(
        "[VOTING_TIMING] finish sidecar-open elapsed={:.3}s",
        sidecar_open_started.elapsed().as_secs_f64()
    );
    let lock_started = Instant::now();
    let prepared = with_voting_sidecar_write_lock(db_path, || {
        log::info!(
            "[VOTING_TIMING] finish sidecar-lock-wait elapsed={:.3}s",
            lock_started.elapsed().as_secs_f64()
        );
        let crate_started = Instant::now();
        zcash_voting::delegate::finish_delegation_round_preparation(
            &voting_db,
            &wallet_db,
            zcash_voting::delegate::FinishDelegationRoundPreparationParams {
                account_uuid,
                voting_hotkey,
                round_params,
                round_name,
            },
            &zcash_voting::NoopProgressReporter,
        )
        .map_err(|e| format!("finish delegation round preparation failed: {e}"))
        .inspect(|prepared| {
            log::info!(
                "[VOTING_TIMING] finish crate-call bundles={} elapsed={:.3}s",
                prepared.layout.bundle_count,
                crate_started.elapsed().as_secs_f64()
            );
        })
    })?;
    log::info!(
        "[VOTING_PROVE] round={} finish-preparation bundles={} total={:.3}s",
        prepared.round_id,
        prepared.layout.bundle_count,
        started.elapsed().as_secs_f64()
    );
    Ok((voting_db, prepared))
}

fn prove_captured_delegation_bundles<F>(
    captured: Vec<zcash_voting::delegate::CapturedDelegationProof>,
    on_progress: Arc<F>,
) -> Result<Vec<PreparedDelegationProof>, String>
where
    F: Fn(u32, DelegationProgress) + Send + Sync + 'static,
{
    let started = Instant::now();
    let mut pending = VecDeque::from(captured);
    let mut proofs = Vec::with_capacity(pending.len());
    let mut batch_index = 0usize;
    while !pending.is_empty() {
        let batch = (0..MAX_CONCURRENT_DELEGATION_PROOFS)
            .filter_map(|_| pending.pop_front())
            .collect::<Vec<_>>();
        log::info!(
            "[VOTING_TIMING] proof-batch index={batch_index} workers={} remaining={}",
            batch.len(),
            pending.len()
        );
        let mut batch_proofs = thread::scope(|scope| {
            let mut workers = Vec::with_capacity(batch.len());
            for captured_bundle in batch {
                let bundle_index = captured_bundle.bundle_index;
                let progress = on_progress.clone();
                let queued_at = Instant::now();
                let handle = thread::Builder::new()
                    .name(format!("voting-delegation-proof-{bundle_index}"))
                    .stack_size(PROVING_CACHE_STACK_BYTES)
                    .spawn_scoped(scope, move || {
                        let proof_started = Instant::now();
                        log::info!(
                            "[VOTING_TIMING] proof-worker bundle={bundle_index} queue-wait={:.3}s",
                            queued_at.elapsed().as_secs_f64()
                        );
                        let reporter = zcash_voting::DelegationProgressBridge::new(move |event| {
                            progress(bundle_index, event);
                        });
                        let proof = zcash_voting::delegate::prove_prepared_delegation_bundle(
                            captured_bundle,
                            &reporter,
                        )
                        .map_err(|e| {
                            format!("prove delegation bundle {bundle_index} failed: {e}")
                        })?;
                        log::info!(
                            "[VOTING_PROVE] bundle={bundle_index} pure-proof elapsed={:.3}s",
                            proof_started.elapsed().as_secs_f64()
                        );
                        Ok(proof)
                    })
                    .map_err(|e| {
                        format!("failed to spawn delegation proof worker {bundle_index}: {e}")
                    })?;
                workers.push((bundle_index, handle));
            }
            workers
                .into_iter()
                .map(|(bundle_index, worker)| {
                    worker
                        .join()
                        .map_err(|_| format!("delegation proof worker {bundle_index} panicked"))?
                })
                .collect::<Result<Vec<_>, String>>()
        })?;
        proofs.append(&mut batch_proofs);
        batch_index += 1;
    }
    proofs.sort_by_key(|proof| proof.bundle_index);
    log::info!(
        "[VOTING_PROVE] concurrent-proofs count={} elapsed={:.3}s stack_per_worker_mb=64",
        proofs.len(),
        started.elapsed().as_secs_f64()
    );
    Ok(proofs)
}

fn spawn_pir_connect(
    pir_server_url: &str,
    pir_layout: PirLayout,
) -> Result<PirConnectThread, String> {
    let pir_server_url = pir_server_url.to_string();
    let handle = thread::Builder::new()
        .name("voting-pir-connect".to_string())
        .spawn(move || connect_pir_client(&pir_server_url, pir_layout))
        .map_err(|e| format!("failed to spawn PIR connect thread: {e}"))?;
    log::info!("[VOTING_PROVE] pir-connect spawned");
    Ok(OwnedResultThread::new("PIR connect", handle))
}

async fn drain_pir_connect_after_error(handle: PirConnectThread) {
    match tokio::task::spawn_blocking(move || handle.join()).await {
        Ok(Ok(_)) => {}
        Ok(Err(error)) => {
            log::warn!("[VOTING_PROVE] PIR connect also failed while draining: {error}");
        }
        Err(error) => {
            log::warn!("[VOTING_PROVE] PIR connect drain task failed: {error}");
        }
    }
}

/// Completes the proof phase for a previously prepared delegation bundle.
///
/// Opens the voting database for `account_uuid`, joins the first in-flight PIR
/// connect, warms PIR rows when needed, then runs bundle proving on a blocking
/// worker thread while forwarding `DelegationProgress` updates to `on_progress`.
/// Retryable PIR transport failures rotate through the remaining exact-snapshot
/// endpoints while reusing the same prepared bundle.
///
/// # Errors
///
/// Returns an error if opening the voting database fails, connecting to the PIR
/// server fails, the underlying `PreparedDelegationBundle::prove` call fails, or
/// the spawned blocking task is cancelled or panics.
async fn prove_delegation_bundle<F>(
    db_path: &str,
    pir_server_urls: &[String],
    pir_layout: PirLayout,
    account_uuid: &str,
    prepared: &PreparedDelegationBundle,
    pir_connect: PirConnectThread,
    on_progress: Arc<F>,
) -> Result<(), String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let total_started = Instant::now();
    let proof_db_path = db_path.to_string();
    let proof_pir_server_urls = pir_server_urls.to_vec();
    let proof_account_uuid = account_uuid.to_string();
    let bundle_index = prepared.bundle_index;
    log::info!("[VOTING_PROVE] bundle={bundle_index} proof-task start");
    let prepared = prepared.clone();
    let proof_progress = on_progress.clone();
    tokio::task::spawn_blocking(move || {
        let db_started = Instant::now();
        let proof_voting_db = open_voting_db(&proof_db_path, &proof_account_uuid)?;
        let proof_wallet_db =
            open_wallet_db_for_read(&proof_db_path, wallet_network(prepared.network))?;
        log::info!(
            "[VOTING_PROVE] bundle={bundle_index} proof-db-open elapsed={:.3}s",
            db_started.elapsed().as_secs_f64()
        );
        let reporter = zcash_voting::DelegationProgressBridge::new(move |progress| {
            proof_progress(progress);
        });
        let mut first_connect = Some(pir_connect);
        with_pir_endpoint_failover(&proof_pir_server_urls, |pir_server_url| {
            let pir_client = match first_connect.take() {
                Some(connect) => {
                    let join_started = Instant::now();
                    log::info!("[VOTING_PROVE] bundle={bundle_index} pir-connect-join start");
                    let client = connect.join()?;
                    log::info!(
                        "[VOTING_PROVE] bundle={bundle_index} pir-connect-join elapsed={:.3}s",
                        join_started.elapsed().as_secs_f64()
                    );
                    client
                }
                None => connect_pir_client(pir_server_url, pir_layout)?,
            };

            // Fetch/cache PIR rows before Halo2 prove so remaining keygen
            // warm-up can overlap the first endpoint's network round-trip. Keep
            // the first database attempt parallel; only a SQLite writer-race
            // retry joins the per-wallet coordinator.
            let precompute_started = Instant::now();
            retry_voting_db_locks_coordinated(&proof_db_path, || {
                prepared
                    .precompute(&proof_voting_db, &proof_wallet_db, &pir_client)
                    .map(|_| ())
                    .map_err(|e| format!("delegate::precompute failed: {e}"))
            })?;
            log::info!(
                "[VOTING_PROVE] bundle={bundle_index} pir-precompute elapsed={:.3}s",
                precompute_started.elapsed().as_secs_f64()
            );

            let prove_started = Instant::now();
            retry_voting_db_locks_coordinated(&proof_db_path, || {
                prepared
                    .prove(&proof_voting_db, &pir_client, &reporter)
                    .map(|_| ())
                    .map_err(|e| format!("delegate::prove failed: {e}"))
            })?;
            log::info!(
                "[VOTING_PROVE] bundle={bundle_index} prepared-prove elapsed={:.3}s",
                prove_started.elapsed().as_secs_f64()
            );
            Ok(())
        })
    })
    .await
    .map_err(|e| format!("delegation proof task failed: {e}"))??;
    log::info!(
        "[VOTING_PROVE] bundle={bundle_index} complete total={:.3}s",
        total_started.elapsed().as_secs_f64()
    );
    Ok(())
}

/// Persist the complete hotkey-free delegation snapshot tier.
///
/// This initializes the round, selects notes and the anchor once, persists only
/// minimal bundle identities, generates union witnesses, and caches PIR proofs
/// for both real and padded slots. Confidential note material remains in the
/// wallet DB and an optional process-memory cache.
pub async fn prepare_delegation_snapshot(
    db_path: &str,
    account_uuid: &str,
    pir_server_url: &str,
    pir_layout: PirLayout,
    lwd_params: zcash_voting::delegate::ResolveDelegationLwdParams<'_>,
    session_json: Option<&str>,
    bundle_policy: BundlePolicy,
) -> Result<zcash_voting::precompute::DelegationSnapshotPreparationReport, String> {
    let pir_server_url = pir_server_url.trim();
    if pir_server_url.is_empty() {
        return Err("PIR server URL must not be empty".to_string());
    }

    let zcash_voting::delegate::ResolveDelegationLwdParams {
        lightwalletd_url,
        network,
        round_params,
        round_name,
    } = lwd_params;
    let started = Instant::now();
    log::info!("[VOTING_PROVE] delegation-snapshot start");
    start_proving_cache_warmup();

    let voting_db = open_voting_db(db_path, account_uuid)?;
    let context_started = Instant::now();
    let round_context = with_voting_sidecar_write_lock(db_path, || {
        zcash_voting::delegate::ensure_round_context(
            &voting_db,
            network,
            &round_params,
            round_name,
            session_json,
        )
        .map_err(|e| e.to_string())
    })?;
    log::info!(
        "[VOTING_PROVE] snapshot-bundles round-context elapsed={:.3}s",
        context_started.elapsed().as_secs_f64()
    );

    // Connect while note selection reads the snapshot tree and wallet DB.
    let pir_connect = spawn_pir_connect(pir_server_url, pir_layout)?;
    let select_started = Instant::now();
    let selected = match select_notes_with_lwd(
        &voting_db,
        db_path,
        lightwalletd_url,
        network,
        round_context.snapshot_height,
    )
    .await
    {
        Ok(selected) => selected,
        Err(error) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(error.to_string());
        }
    };
    let note_infos = selected.voting_note_infos().to_vec();
    let tree_state_bytes = selected.anchor_tree_state.encode_to_vec();
    log::info!(
        "[VOTING_PROVE] snapshot-bundles note-selection notes={} elapsed={:.3}s",
        note_infos.len(),
        select_started.elapsed().as_secs_f64()
    );

    let db_path = db_path.to_string();
    let account_uuid = account_uuid.to_string();
    let resolved_round_name = round_name.to_string();
    let session_json = session_json.map(str::to_string);
    let round_params_for_prepare = round_params;
    let policy = whale_protected_bundle_policy(bundle_policy);
    let precompute_started = Instant::now();
    let report = tokio::task::spawn_blocking(move || {
        let connect_started = Instant::now();
        let pir_client = pir_connect.join()?;
        log::info!(
            "[VOTING_PROVE] snapshot-bundles pir-connect-join elapsed={:.3}s",
            connect_started.elapsed().as_secs_f64()
        );
        let voting_db = open_voting_db(&db_path, &account_uuid)?;
        let wallet_db = open_wallet_db_for_read(&db_path, wallet_network(network))?;
        retry_voting_db_locks_coordinated(&db_path, || {
            zcash_voting::precompute::prepare_delegation_snapshot(
                &voting_db,
                &wallet_db,
                zcash_voting::precompute::PrepareDelegationSnapshotParams {
                    account_uuid: &account_uuid,
                    network,
                    round_params: &round_params_for_prepare,
                    round_name: &resolved_round_name,
                    session_json: session_json.as_deref(),
                    tree_state_bytes: &tree_state_bytes,
                    notes: &note_infos,
                    bundle_policy: policy,
                },
                &pir_client,
            )
            .map_err(|e| e.to_string())
        })
    })
    .await
    .map_err(|e| format!("snapshot bundle precompute task failed: {e}"))??;
    log::info!(
        "[VOTING_PROVE] snapshot-bundles crate-call bundles={} elapsed={:.3}s total={:.3}s",
        report.layout.bundle_count,
        precompute_started.elapsed().as_secs_f64(),
        started.elapsed().as_secs_f64()
    );
    Ok(report)
}

/// Read durable snapshot completeness without lightwalletd or PIR access.
pub fn delegation_snapshot_status(
    db_path: &str,
    account_uuid: &str,
    network: zcash_voting::Network,
    round_params: &zcash_voting::VotingRoundParams,
) -> Result<zcash_voting::precompute::DelegationSnapshotStatus, String> {
    let voting_db = open_voting_db(db_path, account_uuid)?;
    zcash_voting::precompute::delegation_snapshot_status(&voting_db, network, round_params)
        .map_err(|e| e.to_string())
}

/// Minimum voting eligibility plus the note value the privacy trim withholds.
///
/// Both come from one bundle plan. The withheld value is raw note value, not
/// bundle-quantized voting weight, and it is reported separately from
/// `dropped_count` (sub-ballot notes, already worth zero ballots).
///
/// This narrows the plan to the one field the API layer needs so bundle
/// contents do not leak into the FRB boundary.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VotingEligibilityReport {
    pub eligibility: zcash_voting::MinimumVotingEligibility,
    pub privacy_trim_dropped_value_zatoshi: u64,
}

/// Reports eligibility and the privacy-trim loss for an already-selected note set.
///
/// Split out from [`check_voting_eligibility`] so the planning behavior can be
/// tested without lightwalletd note selection.
///
/// `seed_policy` is only what an unplanned round would be planned with. Once a
/// round has a plan, its stored policy is authoritative, so the policy is
/// resolved from round state rather than assumed from the seed -- otherwise the
/// preview describes a plan the round would not actually derive.
///
/// # Errors
///
/// Returns an error if the round policy cannot be resolved or if any selected
/// note row is malformed.
fn voting_eligibility_report(
    voting_db: &VotingDb,
    round_id: &str,
    note_infos: &[zcash_voting::types::NoteInfo],
    seed_policy: BundlePolicy,
) -> Result<VotingEligibilityReport, String> {
    let bundle_policy = voting_db
        .effective_bundle_policy(round_id, seed_policy)
        .map_err(|e| e.to_string())?;
    // One plan, so the reported weight and the reported loss cannot describe
    // different bundle sets. This also applies the canonical duplicate-nullifier
    // collapse rather than repeating it here.
    let (eligibility, plan) =
        zcash_voting::minimum_voting_eligibility_and_plan_for_notes(note_infos, bundle_policy)
            .map_err(|e| e.to_string())?;
    Ok(VotingEligibilityReport {
        eligibility,
        privacy_trim_dropped_value_zatoshi: plan.privacy_trim.dropped_value,
    })
}

/// Select notes and check whether a wallet can vote without persisting bundles.
///
/// The selected notes are taken at the round snapshot height. The result uses
/// the same smart bundle quantization that delegation setup uses, but this path
/// does not initialize round rows or create bundle rows in the sidecar DB.
///
/// # Errors
///
/// Returns an error if lightwalletd note selection fails, the round policy
/// cannot be resolved, or any selected note row is malformed.
pub async fn check_voting_eligibility(
    voting_db: &VotingDb,
    db_path: &str,
    lightwalletd_url: &str,
    network: zcash_voting::Network,
    round_id: &str,
    snapshot_height: u64,
    bundle_policy: BundlePolicy,
) -> Result<VotingEligibilityReport, String> {
    let selected = select_notes_with_lwd(
        voting_db,
        db_path,
        lightwalletd_url,
        network,
        snapshot_height,
    )
    .await
    .map_err(|e| e.to_string())?;
    let note_infos = selected.voting_note_infos();
    let seed_policy = whale_protected_bundle_policy(bundle_policy);
    voting_eligibility_report(voting_db, round_id, &note_infos, seed_policy)
}

/// Outcome of the bundle-independent background PIR proof cache warm-up.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PirCacheWarmupOutcome {
    /// Eligible notes selected at the snapshot height.
    pub note_count: u32,
    /// Nullifiers that already had a cached proof under the served root.
    pub cached_count: u32,
    /// Proofs fetched from the PIR server during this warm-up.
    pub fetched_count: u32,
    /// IMT root the PIR server served, as 32 little-endian bytes.
    pub served_root: Vec<u8>,
    /// Cache rows evicted by the library's automatic recency prune (currently
    /// unused: `precompute_pir_proofs` prunes internally and does not report
    /// a count). Kept so the FRB result shape stays stable.
    pub pruned_count: u32,
}

/// Warms the bundle-independent PIR proof cache for the account's eligible
/// notes at `snapshot_height`.
///
/// This needs no hotkey, round rows, or bundles — only a wallet scanned to the
/// snapshot height and a PIR
/// endpoint serving it. Notes are planned with the same whale-protected
/// default [`BundlePolicy`] round setup uses, so a selected-note dust tail is
/// not PIR-queried. The delegation prove path reads the same cache, so
/// real-note proofs warmed here are never refetched at proving time; only the
/// per-bundle padded-slot nullifiers still need a fetch there.
///
/// The library garbage-collects cache rows older than four weeks on each
/// warm. `keep_roots` is accepted for FRB compatibility and is otherwise
/// unused.
///
/// # Errors
///
/// Returns an error if the sidecar cannot be opened, the wallet is not scanned
/// to the snapshot height, note selection fails, the PIR connect handshake
/// fails, or a fetched proof does not verify under the served root.
pub async fn warm_pir_proof_cache(
    db_path: &str,
    account_uuid: &str,
    lightwalletd_url: &str,
    network: zcash_voting::Network,
    snapshot_height: u64,
    pir_server_url: &str,
    pir_layout: PirLayout,
    _keep_roots: Vec<Vec<u8>>,
) -> Result<PirCacheWarmupOutcome, String> {
    let started = Instant::now();
    // Overlap the PIR handshake with sidecar open, lightwalletd anchor, and
    // note selection. Sidecar open (schema v15 migrate) and wallet-DB reads
    // stay off the FRB async worker so poll-list / wallet-summary calls are
    // not stuck behind a note scan or PIR fetch.
    let pir_connect = spawn_pir_connect(pir_server_url, pir_layout)?;

    let db_path = db_path.to_string();
    let account_uuid = account_uuid.to_string();
    let voting_db = match tokio::task::spawn_blocking({
        let db_path = db_path.clone();
        let account_uuid = account_uuid.clone();
        move || open_voting_db(&db_path, &account_uuid)
    })
    .await
    {
        Ok(Ok(db)) => db,
        Ok(Err(error)) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(error);
        }
        Err(error) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(format!("voting sidecar open task failed: {error}"));
        }
    };

    let anchor_tree_state = match fetch_snapshot_tree_state(lightwalletd_url, snapshot_height).await
    {
        Ok(anchor) => anchor,
        Err(error) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(format!("voting note selection failed: {error}"));
        }
    };

    let wallet_net = wallet_network(network);
    let selected = match tokio::task::spawn_blocking({
        let db_path = db_path.clone();
        let account_uuid = account_uuid.clone();
        move || {
            let wallet_db = open_wallet_db_for_read(&db_path, wallet_net)?;
            select_notes_with_wallet_db(
                &wallet_db,
                network,
                &account_uuid,
                snapshot_height,
                anchor_tree_state,
            )
            .map_err(|e| e.to_string())
        }
    })
    .await
    {
        Ok(Ok(selected)) => selected,
        Ok(Err(error)) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(format!("voting note selection failed: {error}"));
        }
        Err(error) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(format!("voting note selection task failed: {error}"));
        }
    };
    let note_infos = selected.voting_note_infos();
    let note_count = u32::try_from(note_infos.len())
        .map_err(|_| "selected note count does not fit in u32".to_string())?;

    let warmup = thread::Builder::new()
        .name("voting-pir-cache-warmup".to_string())
        .spawn(move || {
            let pir_client = pir_connect.join()?;
            let bundle_policy = whale_protected_bundle_policy(BundlePolicy::default());
            // The cache upserts are idempotent and run outside the process-local
            // sidecar write lock, so a lost SQLite writer race is safely retried.
            // `precompute_pir_proofs` also prunes rows older than four weeks.
            // A dedicated OS thread is required: `PirClientBlocking::fetch_proofs`
            // owns its own Tokio runtime, and `Runtime::block_on` from FRB's
            // `spawn_blocking` pool deadlocks that runtime (wallet/poll UI
            // then waits forever on later async FFI).
            let result = retry_voting_db_locks(|| {
                zcash_voting::precompute::precompute_pir_proofs(
                    &voting_db,
                    &note_infos,
                    bundle_policy,
                    network,
                    &pir_client,
                )
                .map_err(|e| e.to_string())
            })?;
            log::info!(
                "[VOTING_PIR_CACHE] warmup complete notes={note_count} cached={} fetched={} \
                 elapsed={:.3}s",
                result.cached_count,
                result.fetched_count,
                started.elapsed().as_secs_f64()
            );
            Ok(PirCacheWarmupOutcome {
                note_count,
                cached_count: result.cached_count,
                fetched_count: result.fetched_count,
                served_root: result.served_root,
                pruned_count: 0,
            })
        })
        .map_err(|e| format!("failed to spawn PIR proof cache warm-up thread: {e}"))?;
    tokio::task::spawn_blocking(move || {
        warmup
            .join()
            .map_err(|e| format!("PIR proof cache warm-up thread panicked: {e:?}"))?
    })
    .await
    .map_err(|e| format!("PIR proof cache warm-up task failed: {e}"))?
}

/// Prepare one round, prove the requested bundles concurrently, atomically
/// persist the proof batch, and assemble software-signed payloads.
pub async fn build_prove_and_sign_delegation_round<F>(
    db_path: String,
    seed: SecretVec<u8>,
    account_uuid: String,
    round_params: zcash_voting::VotingRoundParams,
    round_name: String,
    voting_hotkey: zcash_voting::VotingHotkey,
    bundle_indexes: Vec<u32>,
    on_progress: F,
) -> Result<Vec<zcash_voting::delegate::SignedDelegationBundle>, String>
where
    F: Fn(u32, DelegationProgress) + Send + Sync + 'static,
{
    let bundle_indexes = normalize_bundle_indexes(&bundle_indexes)?;
    start_proving_cache_warmup();
    let worker = thread::Builder::new()
        .name("voting-delegation-software-round".to_string())
        .spawn(move || {
            let total_started = Instant::now();
            let on_progress = Arc::new(on_progress);
            // Software has no external signing handoff, so finish and prove in
            // one worker. This reuses transient note material immediately
            // without persisting or caching it across operations.
            let (voting_db, prepared) = finish_delegation_round_preparation_inner(
                &db_path,
                &account_uuid,
                &round_params,
                &round_name,
                &voting_hotkey,
            )?;
            let capture_started = Instant::now();
            let captured = zcash_voting::delegate::capture_delegation_proof_inputs(
                &voting_db,
                &prepared,
                &bundle_indexes,
            )
            .map_err(|e| format!("capture delegation proof inputs failed: {e}"))?;
            log::info!(
                "[VOTING_PROVE] round={} capture count={} elapsed={:.3}s",
                prepared.round_id,
                captured.len(),
                capture_started.elapsed().as_secs_f64()
            );
            let proofs = prove_captured_delegation_bundles(captured, on_progress.clone())?;
            let persist_started = Instant::now();
            with_voting_sidecar_write_lock(&db_path, || {
                zcash_voting::delegate::persist_prepared_delegation_proofs(&voting_db, proofs)
                    .map(|_| ())
                    .map_err(|e| format!("persist delegation proof batch failed: {e}"))
            })?;
            log::info!(
                "[VOTING_PROVE] round={} proof-batch-persist elapsed={:.3}s",
                prepared.round_id,
                persist_started.elapsed().as_secs_f64()
            );

            let signing_started = Instant::now();
            let mut signatures = Vec::with_capacity(bundle_indexes.len());
            for bundle_index in &bundle_indexes {
                on_progress(*bundle_index, DelegationProgress::SigningPayload);
                let bundle_sign_started = Instant::now();
                let bundle = prepared
                    .bundles
                    .iter()
                    .find(|bundle| bundle.bundle_index == *bundle_index)
                    .ok_or_else(|| {
                        format!("prepared delegation bundle {bundle_index} not found")
                    })?;
                let request = bundle.signing_request(&voting_db).map_err(|e| {
                    format!("delegation signing request for bundle {bundle_index} failed: {e}")
                })?;
                let request_elapsed = bundle_sign_started.elapsed();
                let crypto_started = Instant::now();
                let (sig, sighash) = sign_delegation_request(&seed, request).map_err(|e| {
                    format!("delegation signing for bundle {bundle_index} failed: {e}")
                })?;
                log::info!(
                    "[VOTING_TIMING] sign bundle={bundle_index} request={:.3}s crypto={:.3}s",
                    request_elapsed.as_secs_f64(),
                    crypto_started.elapsed().as_secs_f64()
                );
                signatures.push(PreparedDelegationBundleSignature {
                    bundle_index: *bundle_index,
                    pczt_bytes: prepared
                        .setups
                        .get(*bundle_index as usize)
                        .ok_or_else(|| {
                            format!("delegation setup for bundle {bundle_index} not found")
                        })?
                        .pczt_bytes
                        .clone(),
                    signer: zcash_voting::delegate::PreparedSigner::signature(sig, sighash),
                });
            }
            let assembly_started = Instant::now();
            let signed = zcash_voting::delegate::assemble_signed_delegation_bundles(
                &voting_db, &prepared, signatures,
            )
            .map_err(|e| format!("assemble signed delegation bundles failed: {e}"))?;
            log::info!(
                "[VOTING_TIMING] sign assembly bundles={} elapsed={:.3}s",
                signed.len(),
                assembly_started.elapsed().as_secs_f64()
            );
            for bundle in &signed {
                on_progress(bundle.bundle_index, DelegationProgress::PayloadReady);
            }
            log::info!(
                "[VOTING_PROVE] round={} sign-assemble count={} elapsed={:.3}s total={:.3}s",
                prepared.round_id,
                signed.len(),
                signing_started.elapsed().as_secs_f64(),
                total_started.elapsed().as_secs_f64()
            );
            Ok(signed)
        })
        .map_err(|e| format!("failed to spawn software delegation round worker: {e}"))?;
    tokio::task::spawn_blocking(move || {
        worker
            .join()
            .map_err(|_| "software delegation round worker panicked".to_string())?
    })
    .await
    .map_err(|e| format!("software delegation round join task failed: {e}"))?
}

/// Bind a durable snapshot to the hotkey and return signer-safe PCZT requests.
pub async fn finish_delegation_round_preparation(
    db_path: String,
    account_uuid: String,
    round_params: zcash_voting::VotingRoundParams,
    round_name: String,
    voting_hotkey: zcash_voting::VotingHotkey,
    bundle_indexes: Vec<u32>,
) -> Result<Vec<zcash_voting::delegate::KeystoneSigningRequest>, String> {
    let bundle_indexes = normalize_bundle_indexes(&bundle_indexes)?;
    let worker = thread::Builder::new()
        .name("voting-delegation-keystone-prepare".to_string())
        .spawn(move || {
            let started = Instant::now();
            let (_, prepared) = finish_delegation_round_preparation_inner(
                &db_path,
                &account_uuid,
                &round_params,
                &round_name,
                &voting_hotkey,
            )?;
            let mut requests = Vec::with_capacity(bundle_indexes.len());
            for bundle_index in bundle_indexes {
                let request = prepared
                    .keystone_requests
                    .iter()
                    .find(|request| request.bundle_index == bundle_index)
                    .ok_or_else(|| {
                        format!("prepared Keystone request for bundle {bundle_index} not found")
                    })?;
                requests.push(request.clone());
            }
            log::info!(
                "[VOTING_PROVE] round={} keystone-requests count={} total={:.3}s",
                prepared.round_id,
                requests.len(),
                started.elapsed().as_secs_f64()
            );
            Ok(requests)
        })
        .map_err(|e| format!("failed to spawn Keystone delegation prepare worker: {e}"))?;
    tokio::task::spawn_blocking(move || {
        worker
            .join()
            .map_err(|_| "Keystone delegation prepare worker panicked".to_string())?
    })
    .await
    .map_err(|e| format!("Keystone delegation prepare join task failed: {e}"))?
}

/// Resume an already prepared Keystone round, prove selected bundles
/// concurrently, persist the proof batch, and assemble the supplied signatures.
pub async fn build_prove_delegation_round_with_keystone_signatures<F>(
    db_path: String,
    account_uuid: String,
    round_params: zcash_voting::VotingRoundParams,
    round_name: String,
    voting_hotkey: zcash_voting::VotingHotkey,
    signatures: Vec<(u32, Vec<u8>, Vec<u8>)>,
    on_progress: F,
) -> Result<Vec<zcash_voting::delegate::SignedDelegationBundle>, String>
where
    F: Fn(u32, DelegationProgress) + Send + Sync + 'static,
{
    let bundle_indexes =
        normalize_bundle_indexes(&signatures.iter().map(|item| item.0).collect::<Vec<_>>())?;
    start_proving_cache_warmup();
    let worker = thread::Builder::new()
        .name("voting-delegation-keystone-resume".to_string())
        .spawn(move || {
            let total_started = Instant::now();
            let on_progress = Arc::new(on_progress);
            let wallet_db =
                open_wallet_db_for_read(&db_path, wallet_network(voting_hotkey.network()))?;
            let voting_db = open_voting_db(&db_path, &account_uuid)?;
            let load_started = Instant::now();
            let prepared = zcash_voting::delegate::load_prepared_delegation_round(
                &voting_db,
                &wallet_db,
                LoadPreparedDelegationRoundParams {
                    account_uuid: &account_uuid,
                    voting_hotkey: &voting_hotkey,
                    round_params: &round_params,
                    round_name: &round_name,
                },
            )
            .map_err(|e| format!("load prepared delegation round failed: {e}"))?;
            log::info!(
                "[VOTING_PROVE] round={} resume-load elapsed={:.3}s",
                prepared.round_id,
                load_started.elapsed().as_secs_f64()
            );
            let captured = zcash_voting::delegate::capture_resumed_delegation_proof_inputs(
                &voting_db,
                &prepared,
                &bundle_indexes,
            )
            .map_err(|e| format!("capture delegation proof inputs failed: {e}"))?;
            let proofs = prove_captured_delegation_bundles(captured, on_progress.clone())?;
            with_voting_sidecar_write_lock(&db_path, || {
                zcash_voting::delegate::persist_prepared_delegation_proofs(&voting_db, proofs)
                    .map(|_| ())
                    .map_err(|e| format!("persist delegation proof batch failed: {e}"))
            })?;

            let mut prepared_signatures = Vec::with_capacity(signatures.len());
            for (bundle_index, sig, sighash) in signatures {
                on_progress(bundle_index, DelegationProgress::SigningPayload);
                let signer =
                    zcash_voting::delegate::PreparedSigner::signature_from_bytes(&sig, &sighash)
                        .map_err(|e| {
                            format!("invalid Keystone signature for bundle {bundle_index}: {e}")
                        })?;
                prepared_signatures.push(PreparedDelegationBundleSignature {
                    bundle_index,
                    // Resume intentionally uses the durable PCZT setup and never
                    // rebuilds or returns a stale full PCZT.
                    pczt_bytes: Vec::new(),
                    signer,
                });
            }
            prepared_signatures.sort_by_key(|signature| signature.bundle_index);
            let signed = zcash_voting::delegate::assemble_resumed_signed_delegation_bundles(
                &voting_db,
                &prepared,
                prepared_signatures,
            )
            .map_err(|e| format!("assemble Keystone delegation bundles failed: {e}"))?;
            for bundle in &signed {
                on_progress(bundle.bundle_index, DelegationProgress::PayloadReady);
            }
            log::info!(
                "[VOTING_PROVE] round={} keystone-resume count={} total={:.3}s",
                prepared.round_id,
                signed.len(),
                total_started.elapsed().as_secs_f64()
            );
            Ok(signed)
        })
        .map_err(|e| format!("failed to spawn Keystone delegation resume worker: {e}"))?;
    tokio::task::spawn_blocking(move || {
        worker
            .join()
            .map_err(|_| "Keystone delegation resume worker panicked".to_string())?
    })
    .await
    .map_err(|e| format!("Keystone delegation resume join task failed: {e}"))?
}

/// Build, prove, and sign one delegation payload.
///
/// Emits progress phases through `on_progress`. The returned value is a signed
/// delegation payload ready for Dart-side submission. PIR endpoints are tried
/// in order only for retryable transport failures, reusing one prepared bundle.
///
/// # Errors
///
/// Returns an error if note/bundle validation, witness
/// generation, PCZT construction, PIR proof generation, or delegation signing
/// fails.
pub async fn build_prove_and_sign_delegation_payload<F>(
    db_path: &str,
    pir_server_urls: &[String],
    pir_layout: PirLayout,
    seed: &SecretVec<u8>,
    prepare_params: PrepareDelegationBundleParams<'_>,
    on_progress: F,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let total_started = Instant::now();
    let pir_server_urls = normalize_pir_server_urls(pir_server_urls)?;
    let bundle_index = prepare_params.bundle_index;
    log::info!("[VOTING_PROVE] bundle={bundle_index} prove-sign start");
    let on_progress = Arc::new(wrap_progress_with_timing(
        bundle_index,
        total_started,
        on_progress,
    ));
    let account_uuid = prepare_params.account_uuid;

    zcash_voting::validate_round_params(&prepare_params.lwd.round_params)
        .map_err(|e| format!("Invalid voting round params: {e}"))?;

    // Overlap independent warm-ups with local preparation/PCZT setup.
    start_proving_cache_warmup();
    let pir_connect = spawn_pir_connect(&pir_server_urls[0], pir_layout)?;

    on_progress(DelegationProgress::SelectingNotes);
    let preparation = (|| {
        let wallet_db_started = Instant::now();
        let wallet_db = open_wallet_db_for_read(
            db_path,
            wallet_network(prepare_params.voting_hotkey.network()),
        )?;
        log::info!(
            "[VOTING_PROVE] bundle={bundle_index} wallet-db-open elapsed={:.3}s",
            wallet_db_started.elapsed().as_secs_f64()
        );
        let prepare_params = prepare_params_with_whale_protection(prepare_params);
        let prepare_bundle_started = Instant::now();
        let pczt_progress = on_progress.clone();
        let setup_stages = zcash_voting::DelegationProgressBridge::new(move |progress| {
            pczt_progress(progress);
        });
        with_open_voting_db_write(db_path, account_uuid, |voting_db| {
            let prepared_bundle = zcash_voting::delegate::prepare_delegation_bundle(
                voting_db,
                &wallet_db,
                prepare_params,
            )
            .map_err(|e| e.to_string())?;
            log::info!(
                "[VOTING_PROVE] bundle={} prepare-bundle elapsed={:.3}s",
                prepared_bundle.bundle_index,
                prepare_bundle_started.elapsed().as_secs_f64()
            );
            let pczt_setup_started = Instant::now();
            let delegation_setup = prepared_bundle
                .setup(voting_db, &setup_stages)
                .map_err(|e| format!("delegate::setup failed: {e}"))?;
            log::info!(
                "[VOTING_PROVE] bundle={} pczt-setup elapsed={:.3}s",
                prepared_bundle.bundle_index,
                pczt_setup_started.elapsed().as_secs_f64()
            );
            Ok((prepared_bundle, delegation_setup))
        })
    })();
    let (voting_db, (prepared_bundle, delegation_setup)) = match preparation {
        Ok(value) => value,
        Err(error) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(error);
        }
    };
    let prove_started = Instant::now();
    prove_delegation_bundle(
        db_path,
        &pir_server_urls,
        pir_layout,
        account_uuid,
        &prepared_bundle,
        pir_connect,
        on_progress.clone(),
    )
    .await?;
    log::info!(
        "[VOTING_PROVE] bundle={} prove-only elapsed={:.3}s",
        prepared_bundle.bundle_index,
        prove_started.elapsed().as_secs_f64()
    );

    on_progress(DelegationProgress::SigningPayload);
    let signing_started = Instant::now();
    let signing_request = prepared_bundle
        .signing_request(&voting_db)
        .map_err(|e| format!("delegation signing request failed: {e}"))?;
    let (sig, sighash) = sign_delegation_request(seed, signing_request)
        .map_err(|e| format!("delegation signing failed: {e}"))?;
    let signer = zcash_voting::delegate::PreparedSigner::signature(sig, sighash);
    log::info!(
        "[VOTING_PROVE] bundle={} signing elapsed={:.3}s",
        prepared_bundle.bundle_index,
        signing_started.elapsed().as_secs_f64()
    );
    let signed_bundle = prepared_bundle
        .signed_bundle(&voting_db, delegation_setup.pczt_bytes, signer)
        .map_err(|e| format!("delegate::signed_bundle failed: {e}"))?;
    log::info!(
        "[VOTING_PROVE] bundle={} signed-bundle total={:.3}s",
        prepared_bundle.bundle_index,
        total_started.elapsed().as_secs_f64()
    );

    on_progress(DelegationProgress::PayloadReady);
    Ok(signed_bundle)
}

/// Signs a delegation request with the Orchard spend authorizing key derived from
/// the wallet seed and account in the request.
///
/// Returns the detached signature bytes plus the original sighash when the seed,
/// account index, and randomizer all validate.
fn sign_delegation_request(
    seed: &SecretVec<u8>,
    request: DelegationSigningRequest,
) -> Result<([u8; 64], [u8; 32]), String> {
    let seed = seed.expose_secret();
    // Bind the request to this exact wallet seed before deriving any keys.
    let seed_fingerprint = SeedFingerprint::from_seed(seed)
        .ok_or_else(|| "wallet seed length is not valid for ZIP-32".to_string())?;
    if seed_fingerprint.to_bytes() != request.seed_fingerprint {
        return Err(
            "wallet seed fingerprint does not match delegation signing request".to_string(),
        );
    }

    // Derive the account Orchard signing key specified by the request metadata.
    let account = AccountId::try_from(request.account_index)
        .map_err(|_| format!("invalid account_index {}", request.account_index))?;
    let usk = UnifiedSpendingKey::from_seed(&request.network, seed, account)
        .map_err(|e| format!("derive account unified spending key failed: {e}"))?;
    let sk = *usk.orchard();
    let ask = orchard::keys::SpendAuthorizingKey::from(&sk);
    // The alpha randomizer must decode as a canonical Pallas scalar.
    let alpha = Option::<pasta_curves::pallas::Scalar>::from(
        pasta_curves::pallas::Scalar::from_repr(request.alpha),
    )
    .ok_or_else(|| "delegation alpha is not a valid Pallas scalar".to_string())?;
    // Sign the request-specific sighash with the randomized spend auth key.
    let rsk = ask.randomize(&alpha);
    let rng = voting_crypto_deps::rand::rngs::OsRng;
    let sig = rsk.sign(rng, &request.sighash);
    Ok(((&sig).into(), request.sighash))
}

/// Build one voting PCZT request for Keystone signing.
///
/// The full PCZT is persisted only in Rust-side voting state. `redacted_pczt_bytes`
/// is the payload that should be UR-encoded for Keystone.
///
/// # Errors
///
/// Returns an error if note selection, witness generation, account metadata,
/// PCZT construction, or redaction fails.
pub async fn build_keystone_delegation_request(
    db_path: &str,
    account_uuid: &str,
    prepare_params: PrepareDelegationBundleParams<'_>,
) -> Result<zcash_voting::delegate::KeystoneSigningRequest, String> {
    let wallet_db = open_wallet_db_for_read(
        db_path,
        wallet_network(prepare_params.voting_hotkey.network()),
    )?;
    let prepare_params = prepare_params_with_whale_protection(prepare_params);
    with_open_voting_db_write(db_path, account_uuid, |voting_db| {
        let prepared = zcash_voting::delegate::prepare_delegation_bundle(
            voting_db,
            &wallet_db,
            prepare_params,
        )
        .map_err(|e| e.to_string())?;
        let noop_stages = zcash_voting::NoopProgressReporter;
        prepared
            .keystone_request(voting_db, &noop_stages)
            .map_err(|e| format!("delegate::keystone_request failed: {e}"))
    })
    .map(|(_, request)| request)
}

/// Build a delegation proof and assemble the submission using a Keystone signature.
///
/// This path intentionally does not rebuild the governance PCZT. The signed PCZT
/// request already persisted the sighash and delegation fields; rebuilding here
/// would overwrite that state with a fresh PCZT that the device did not sign.
/// Retryable PIR transport failures rotate through `pir_server_urls` without
/// rebuilding that request.
///
/// # Errors
///
/// Returns an error if proof generation fails, the Keystone signature does not
/// match the stored PCZT sighash, or submission payload reconstruction fails.
pub async fn build_prove_delegation_payload_with_keystone_signature<F>(
    db_path: &str,
    pir_server_urls: &[String],
    pir_layout: PirLayout,
    account_uuid: &str,
    prepare_params: PrepareDelegationBundleParams<'_>,
    keystone_sig: &[u8],
    keystone_sighash: &[u8],
    on_progress: F,
) -> Result<zcash_voting::delegate::SignedDelegationBundle, String>
where
    F: Fn(DelegationProgress) + Send + Sync + 'static,
{
    let pir_server_urls = normalize_pir_server_urls(pir_server_urls)?;
    let total_started = Instant::now();
    let bundle_index = prepare_params.bundle_index;
    log::info!("[VOTING_PROVE] bundle={bundle_index} keystone-prove-sign start");
    let on_progress = Arc::new(wrap_progress_with_timing(
        bundle_index,
        total_started,
        on_progress,
    ));

    start_proving_cache_warmup();
    let pir_connect = spawn_pir_connect(&pir_server_urls[0], pir_layout)?;

    on_progress(DelegationProgress::SelectingNotes);
    let preparation = (|| {
        let wallet_db_started = Instant::now();
        let wallet_db = open_wallet_db_for_read(
            db_path,
            wallet_network(prepare_params.voting_hotkey.network()),
        )?;
        log::info!(
            "[VOTING_PROVE] bundle={bundle_index} wallet-db-open elapsed={:.3}s",
            wallet_db_started.elapsed().as_secs_f64()
        );
        let prepare_params = prepare_params_with_whale_protection(prepare_params);
        let prepare_bundle_started = Instant::now();
        let prepared = with_open_voting_db_write(db_path, account_uuid, |voting_db| {
            zcash_voting::delegate::prepare_delegation_bundle(voting_db, &wallet_db, prepare_params)
                .map_err(|e| e.to_string())
        })?;
        log::info!(
            "[VOTING_PROVE] bundle={bundle_index} prepare-bundle elapsed={:.3}s",
            prepare_bundle_started.elapsed().as_secs_f64()
        );
        Ok(prepared)
    })();
    let (voting_db, prepared_bundle) = match preparation {
        Ok(value) => value,
        Err(error) => {
            drain_pir_connect_after_error(pir_connect).await;
            return Err(error);
        }
    };
    prove_delegation_bundle(
        db_path,
        &pir_server_urls,
        pir_layout,
        account_uuid,
        &prepared_bundle,
        pir_connect,
        on_progress.clone(),
    )
    .await?;

    on_progress(DelegationProgress::SigningPayload);
    let signer = zcash_voting::delegate::PreparedSigner::signature_from_bytes(
        keystone_sig,
        keystone_sighash,
    )
    .map_err(|e| format!("invalid Keystone signature fields: {e}"))?;
    let signed_bundle = prepared_bundle
        .signed_bundle(&voting_db, Vec::new(), signer)
        .map_err(|e| format!("delegate::signed_bundle failed: {e}"))?;
    on_progress(DelegationProgress::PayloadReady);

    Ok(signed_bundle)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::voting::test_support::{ROUND_ID, TEST_ACCOUNT_UUID};
    use ff::PrimeField;
    use orchard::{
        keys::SpendAuthorizingKey,
        primitives::redpallas::{Signature, SpendAuth, VerificationKey},
    };
    use secrecy::ExposeSecret;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Barrier, Mutex,
    };
    use zip32::{fingerprint::SeedFingerprint, AccountId};

    fn note_with_value(position: u64, value: u64) -> zcash_voting::NoteInfo {
        let tag = position as u8;
        zcash_voting::NoteInfo {
            commitment: vec![tag; 32],
            nullifier: vec![tag.wrapping_add(1); 32],
            value,
            position,
            diversifier: vec![tag; 11],
            rho: vec![tag; 32],
            rseed: vec![tag; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }

    #[test]
    fn pir_endpoint_failover_rotates_after_retryable_transport_error() {
        let urls = vec![
            "https://pir-primary.example".to_string(),
            "https://pir-backup.example".to_string(),
        ];
        let mut attempts = Vec::new();

        let result = with_pir_endpoint_failover(&urls, |url| {
            attempts.push(url.to_string());
            if url.contains("primary") {
                Err(
                    "delegate::prove failed: Internal error: PIR parallel fetch failed: send HTTP request"
                        .to_string(),
                )
            } else {
                Ok("proof")
            }
        })
        .unwrap();

        assert_eq!(result, "proof");
        assert_eq!(attempts, urls);
    }

    #[test]
    fn pir_endpoint_failover_stops_on_validation_error() {
        let urls = vec![
            "https://pir-primary.example".to_string(),
            "https://pir-backup.example".to_string(),
        ];
        let mut attempts = Vec::new();

        let error = with_pir_endpoint_failover(&urls, |url| {
            attempts.push(url.to_string());
            Err::<(), _>(
                "delegate::prove failed: connected PIR circuit root does not match".to_string(),
            )
        })
        .unwrap_err();

        assert!(error.contains("circuit root"));
        assert_eq!(attempts, vec![urls[0].clone()]);
    }

    #[test]
    fn pir_endpoint_failover_returns_last_error_after_exhaustion() {
        let urls = vec![
            "https://pir-primary.example".to_string(),
            "https://pir-backup.example".to_string(),
        ];
        let mut attempts = Vec::new();

        let error = with_pir_endpoint_failover(&urls, |url| {
            attempts.push(url.to_string());
            Err::<(), _>(format!(
                "delegate::prove failed: Internal error: PIR parallel fetch failed: send HTTP request to {url}"
            ))
        })
        .unwrap_err();

        assert!(error.contains(&urls[1]));
        assert_eq!(attempts, urls);
    }

    #[test]
    fn pir_query_retry_classifier_is_transport_only() {
        for error in [
            "delegate::prove failed: Internal error: PIR parallel fetch failed: send HTTP request",
            "delegate::precompute failed: Internal error: PIR parallel fetch failed: send HTTP request",
            "connect to PIR server failed: PIR HTTP request timed out",
            "PIR parallel fetch failed: read HTTP response body: connection closed",
            "PIR parallel fetch failed: tier1 query failed: HTTP 503",
            "PIR parallel fetch failed: tier1 query failed: HTTP status 521",
        ] {
            assert!(is_retryable_pir_query_error(error), "{error}");
        }
        for error in [
            "delegate::prove failed: connected PIR circuit root does not match",
            "PIR parallel fetch failed: invalid proof encoding",
            "PIR parallel fetch failed: tier1 query failed: HTTP 400",
            "PIR parallel fetch failed: tier1 query failed: HTTP 5000",
            "network: gRPC connect failed: send HTTP request",
        ] {
            assert!(!is_retryable_pir_query_error(error), "{error}");
        }
    }

    #[test]
    fn pir_server_url_normalization_rejects_empty_and_deduplicates() {
        let normalized = normalize_pir_server_urls(&[
            " https://pir.example ".to_string(),
            "https://pir.example".to_string(),
            "https://pir-backup.example".to_string(),
        ])
        .unwrap();
        assert_eq!(
            normalized,
            vec![
                "https://pir.example".to_string(),
                "https://pir-backup.example".to_string(),
            ]
        );
        assert!(normalize_pir_server_urls(&[]).is_err());
        assert!(normalize_pir_server_urls(&[" ".to_string()]).is_err());
    }

    #[test]
    fn bundle_index_normalization_sorts_and_rejects_invalid_sets() {
        assert_eq!(normalize_bundle_indexes(&[9, 2, 5]).unwrap(), vec![2, 5, 9]);
        assert!(normalize_bundle_indexes(&[]).is_err());
        assert!(normalize_bundle_indexes(&[2, 1, 2]).is_err());
    }

    #[test]
    fn whale_protection_starts_new_bundle_when_addition_would_cross_threshold() {
        let notes = vec![
            note_with_value(1, 10_000 * ZATOSHI_PER_ZEC),
            note_with_value(2, 10_000 * ZATOSHI_PER_ZEC),
            note_with_value(3, 5_000 * ZATOSHI_PER_ZEC),
            note_with_value(4, ZATOSHI_PER_ZEC),
        ];
        let default_plan =
            zcash_voting::round::note_bundles_with_policy(&notes, BundlePolicy::default()).unwrap();
        assert_eq!(default_plan[0].len(), 4);

        let policy = whale_protected_bundle_policy(BundlePolicy::default());
        let protected_plan = zcash_voting::round::note_bundles_with_policy(&notes, policy).unwrap();
        let protected_positions: Vec<Vec<u64>> = protected_plan
            .iter()
            .map(|bundle| bundle.iter().map(|note| note.position).collect())
            .collect();

        assert_eq!(protected_plan.len(), 2);
        assert!(protected_positions.contains(&vec![1, 2, 3]));
        assert!(protected_positions.contains(&vec![4]));

        // The whale threshold and the privacy trim pull in opposite directions.
        // They compose because a 1% / 1000 ZEC drop budget can never pay for a
        // bundle sized near the 25,000 ZEC threshold, so splitting a whale never
        // costs it the bundle the split just created.
        let trim =
            zcash_voting::note_bundling::chunk_notes_with_policy(&notes, policy).privacy_trim;
        assert!(trim.is_empty());
    }

    /// Opens a fresh sidecar DB with the round row the report path looks up.
    fn test_voting_db(temp_dir: &tempfile::TempDir) -> VotingDb {
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), TEST_ACCOUNT_UUID).unwrap();
        db.init_round(
            zcash_voting::Network::Regtest,
            &zcash_voting::VotingRoundParams {
                vote_round_id: ROUND_ID.to_string(),
                snapshot_height: 100,
                ea_pk: vec![1],
                nc_root: vec![2; 32],
                nullifier_imt_root: vec![3; 32],
            },
            None,
        )
        .unwrap();
        db
    }

    /// Two 500 ZEC notes plus a 15-note 1 ZEC tail: the shape the trim exists for.
    ///
    /// Bundles pack five notes each, so this plans as 1003 / 5 / 5 / 2 ZEC.
    fn whale_with_dust_tail_notes() -> Vec<zcash_voting::NoteInfo> {
        let mut notes = vec![
            note_with_value(1, 500 * ZATOSHI_PER_ZEC),
            note_with_value(2, 500 * ZATOSHI_PER_ZEC),
        ];
        notes.extend((3..18).map(|position| note_with_value(position, ZATOSHI_PER_ZEC)));
        notes
    }

    #[test]
    fn voting_eligibility_report_surfaces_the_privacy_trim_for_a_dust_tail() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let notes = whale_with_dust_tail_notes();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // Budget is 1% of 1015 ZEC, which pays for the 2 ZEC and 5 ZEC tail
        // bundles and then hits the 2-bundle target.
        assert_eq!(
            report.privacy_trim_dropped_value_zatoshi,
            7 * ZATOSHI_PER_ZEC
        );
        assert!(report.eligibility.is_eligible());
        assert_eq!(
            report.eligibility.eligible_weight,
            1008 * ZATOSHI_PER_ZEC,
            "the reported weight must be the post-trim weight"
        );
    }

    #[test]
    fn voting_eligibility_report_withholds_nothing_from_uniform_notes() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        // No single tail bundle fits the budget, so a uniform holder cannot be
        // trimmed at all. This is a documented no-op case upstream; pin it so a
        // policy change cannot start quietly costing these voters weight.
        let notes: Vec<_> = (1..=20)
            .map(|position| note_with_value(position, 50 * ZATOSHI_PER_ZEC))
            .collect();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        assert_eq!(report.privacy_trim_dropped_value_zatoshi, 0);
        assert_eq!(report.eligibility.eligible_weight, 1000 * ZATOSHI_PER_ZEC);
    }

    #[test]
    fn voting_eligibility_report_matches_what_a_planned_round_actually_withheld() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let notes = whale_with_dust_tail_notes();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());
        let layout = db
            .ensure_bundles_with_policy(ROUND_ID, &notes, policy)
            .unwrap();
        assert!(layout.privacy_trim_dropped_value_zatoshi > 0);

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // The round stored a trimming policy, so the preview must agree with
        // the plan storage holds. Deriving this from the bundle count alone
        // would report zero for a round that genuinely withheld value.
        assert_eq!(
            report.privacy_trim_dropped_value_zatoshi,
            layout.privacy_trim_dropped_value_zatoshi
        );
        assert_eq!(report.eligibility.eligible_weight, layout.eligible_weight);
    }

    #[test]
    fn voting_eligibility_report_withholds_nothing_for_a_round_migrated_from_launch() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let notes = whale_with_dust_tail_notes();
        let policy = whale_protected_bundle_policy(BundlePolicy::default());
        db.ensure_bundles_with_policy(ROUND_ID, &notes, policy.with_max_privacy_bundles(None))
            .unwrap();
        // A round carried across the in-place schema upgrade has bundle rows
        // but no stored policy, and re-derives without the trim.
        db.conn()
            .execute(
                "UPDATE rounds SET bundle_policy_json = NULL WHERE round_id = ?1",
                rusqlite::params![ROUND_ID],
            )
            .unwrap();

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // Warning these voters about weight they are not losing is the worse
        // failure, so the preview must stay silent for them.
        assert_eq!(report.privacy_trim_dropped_value_zatoshi, 0);
        assert_eq!(report.eligibility.eligible_weight, 1015 * ZATOSHI_PER_ZEC);
    }

    #[test]
    fn voting_eligibility_report_ignores_duplicate_nullifiers() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = test_voting_db(&temp_dir);
        let mut notes = whale_with_dust_tail_notes();
        notes.extend(whale_with_dust_tail_notes());
        let policy = whale_protected_bundle_policy(BundlePolicy::default());

        let report = voting_eligibility_report(&db, ROUND_ID, &notes, policy).unwrap();

        // Duplicates must collapse before planning, or the trim preview would
        // describe a different note set than the eligibility weight beside it.
        assert_eq!(
            report.privacy_trim_dropped_value_zatoshi,
            7 * ZATOSHI_PER_ZEC
        );
        assert_eq!(report.eligibility.eligible_weight, 1008 * ZATOSHI_PER_ZEC);
    }

    #[test]
    fn build_prove_and_sign_delegation_payload_rejects_invalid_round_params_before_progress() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let seed = SecretVec::new(vec![7; 32]);
        let events = Arc::new(Mutex::new(Vec::new()));
        let events_for_callback = events.clone();
        let round_params = zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        };
        let pir_server_urls = vec!["http://127.0.0.1:2".to_string()];
        let err = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(build_prove_and_sign_delegation_payload(
                db_path.to_str().unwrap(),
                &pir_server_urls,
                PirLayout {
                    pir_depth: 19,
                    tier0_layers: 12,
                    tier1_layers: 7,
                    poly_len: 4096,
                },
                &seed,
                PrepareDelegationBundleParams {
                    lwd: zcash_voting::delegate::DelegationLwdInputs {
                        network: zcash_voting::Network::Regtest,
                        round_params,
                        resolved_round_name: "Demo".to_string(),
                        anchor_tree_state_bytes: Vec::new(),
                        branch_id_provider:
                            zcash_voting::delegate::LightwalletdBranchIdProvider::resolved(0),
                    },
                    session_json: None,
                    account_uuid: TEST_ACCOUNT_UUID,
                    voting_hotkey: &zcash_voting::VotingHotkey::from_stored_secret(
                        &[9; 64],
                        zcash_voting::Network::Regtest,
                    )
                    .unwrap(),
                    bundle_index: 0,
                    bundle_policy: BundlePolicy::default(),
                },
                move |event| events_for_callback.lock().unwrap().push(event),
            ))
            .unwrap_err();

        assert!(err.contains("Invalid voting round params"));
        assert!(events.lock().unwrap().is_empty());
    }

    #[test]
    fn start_proving_cache_warmup_is_idempotent() {
        start_proving_cache_warmup();
        start_proving_cache_warmup();
        assert!(PROVING_CACHE_WARMUP_STARTED.get().is_some());
    }

    #[test]
    fn owned_result_thread_joins_success_error_and_panic() {
        let success = OwnedResultThread::new("test", std::thread::spawn(|| Ok(7)));
        assert_eq!(success.join().unwrap(), 7);

        let failure =
            OwnedResultThread::<u32>::new("test", std::thread::spawn(|| Err("failed".to_string())));
        assert_eq!(failure.join().unwrap_err(), "failed");

        let panic =
            OwnedResultThread::<u32>::new("test", std::thread::spawn(|| panic!("injected panic")));
        assert_eq!(panic.join().unwrap_err(), "test thread panicked");
    }

    #[test]
    fn dropping_owned_result_thread_drains_it() {
        let active = Arc::new(AtomicUsize::new(0));
        let started = Arc::new(Barrier::new(2));
        let active_for_thread = Arc::clone(&active);
        let started_for_thread = Arc::clone(&started);
        let guard = OwnedResultThread::new(
            "test",
            std::thread::spawn(move || {
                active_for_thread.fetch_add(1, Ordering::SeqCst);
                started_for_thread.wait();
                std::thread::sleep(std::time::Duration::from_millis(25));
                active_for_thread.fetch_sub(1, Ordering::SeqCst);
                Ok(())
            }),
        );
        started.wait();

        drop(guard);

        assert_eq!(active.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn sign_delegation_request_happy_path_signs_and_verifies() {
        let seed = SecretVec::new(vec![0x42; 32]);
        let account_index = 0u32;
        let account = AccountId::try_from(account_index).unwrap();
        let usk = UnifiedSpendingKey::from_seed(
            &zcash_voting::Network::Testnet,
            seed.expose_secret(),
            account,
        )
        .unwrap();
        let ask = SpendAuthorizingKey::from(usk.orchard());
        let alpha = pasta_curves::pallas::Scalar::from(7);
        let sighash = [0xAB; 32];
        let request = DelegationSigningRequest {
            account_index,
            network: zcash_voting::Network::Testnet,
            seed_fingerprint: SeedFingerprint::from_seed(seed.expose_secret())
                .unwrap()
                .to_bytes(),
            sighash,
            alpha: alpha.to_repr(),
        };

        let (sig_bytes, returned_sighash) = sign_delegation_request(&seed, request).unwrap();

        let verification_key = VerificationKey::from(&ask.randomize(&alpha));
        verification_key
            .verify(&sighash, &Signature::<SpendAuth>::from(sig_bytes))
            .unwrap();
        assert_eq!(returned_sighash, sighash);
    }
}
