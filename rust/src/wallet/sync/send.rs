//! Software-wallet send flow.
//!
//! This module owns the three-step software-key send pipeline:
//!
//!   1. [`propose_send`] — build a librustzcash `Proposal` from a
//!      user-supplied (address, amount, memo) tuple, stash it in the
//!      shared `PROPOSAL_STORE`, and return enough metadata to drive
//!      the confirmation UI (`ProposalResult`: proposal id, fee,
//!      whether the recipient forces a Sapling bundle).
//!
//!   2. [`estimate_fee`] — the validation-only mirror of
//!      `propose_send`: runs the same proposal construction but does
//!      NOT store the result. Safe to call on every keystroke in the
//!      amount field.
//!
//!   3. [`execute_proposal`] — consume the stored proposal, derive
//!      the USK from the supplied seed (scoped + zeroized before
//!      network I/O), build + sign the transaction(s), and broadcast
//!      them via `send_transaction` gRPC. Once transaction creation
//!      succeeds, broadcast failures are returned as a structured
//!      pending-broadcast result instead of a fatal send failure.
//!
//! The `PROPOSAL_STORE` stays in `sync/mod.rs` because the hardware
//! PCZT pipeline also consumes from it (see `sync/pczt.rs`) and
//! keeping it in the parent avoids a cross-submodule cycle.
//!
//! **Sapling-proofs shortcut**: Orchard-only sends (recipient has an
//! Orchard receiver) go through [`NoOpSpendProver`] /
//! [`NoOpOutputProver`] so we don't have to ship the 50MB Sapling
//! params with the app. `create_proposed_transactions` only touches
//! the provers for Sapling spend/output circuits, so for an
//! Orchard-only proposal these never get called — if they do get
//! called it's a bug (the proposal contained unexpected Sapling
//! components) and the provers log+fail loudly rather than produce a
//! silently-invalid proof.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::convert::Infallible;
use std::num::NonZeroUsize;
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::Instant;

use rand::{rngs::OsRng, Rng};
use secrecy::{ExposeSecret, SecretVec};
use shardtree::error::{QueryError, ShardTreeError};
use transparent::{address::TransparentAddress, bundle::OutPoint, keys::TransparentKeyScope};
use zcash_client_backend::data_api::wallet::input_selection::{
    GreedyInputSelector, InputSelector, SpendPolicy,
};
use zcash_client_backend::{
    data_api::{
        error::Error as WalletError,
        wallet::{
            self, create_proposed_transactions, propose_send_max_transfer, propose_shielding,
            ConfirmationsPolicy, TargetHeight,
        },
        Account as _, AccountMeta, Balance, CoinbaseFilter, InputSource, MaxSpendMode, NoteFilter,
        NoteRetention, ReceivedNotes, TargetValue, TransparentKeyOrigin, WalletCommitmentTrees,
        WalletRead,
    },
    fees::{
        zip317::{MultiOutputChangeStrategy, Zip317FeeRule},
        DustOutputPolicy, SplitPolicy, StandardFeeRule, TransactionBalance,
    },
    proposal::{Proposal, ProposalError, ShieldedInputs},
    wallet::{Note, OvkPolicy, ReceivedNote, WalletTransparentOutput},
    zip321::{Payment, TransactionRequest},
};
use zcash_client_sqlite::{wallet::commitment_tree, AccountUuid, ReceivedNoteId};
use zcash_keys::{address::Address, keys::UnifiedSpendingKey};
use zcash_primitives::transaction::TxVersion;
use zcash_primitives::transaction::{
    builder::{BuildConfig, Builder},
    fees::{
        transparent::InputSize as TransparentInputSize,
        zip317::{P2PKH_STANDARD_INPUT_SIZE, P2PKH_STANDARD_OUTPUT_SIZE},
        FeeRule,
    },
    TxId,
};
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::{
    consensus::{self, BlockHeight, NetworkConstants, Parameters},
    memo::{Memo, MemoBytes},
    value::Zatoshis,
    PoolType, ShieldedProtocol,
};

use crate::wallet::db::{
    open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, READ_DB_BUSY_TIMEOUT,
};
use crate::wallet::keys::parse_account_uuid;
use crate::wallet::keystone::ZCASH_SIGN_BATCH_MAX_MESSAGES;
use crate::wallet::network::WalletNetwork;

use super::migration::MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI;
use super::{
    consume_stored_proposal, open_readonly_conn, open_wallet_db, open_wallet_db_for_read,
    StoredProposal, WalletDatabase, PROPOSAL_STORE,
};

/// Result of a successful [`propose_send`]. `proposal_id` is the
/// handle the caller feeds back to [`execute_proposal`] or
/// `create_pczt_from_proposal`. `needs_sapling_params` tells the UI
/// whether it has to download the Sapling proving parameters (~50MB)
/// before the send can actually complete; `fee_zatoshi` lets the
/// confirmation dialog show a real fee rather than an estimate.
pub(crate) struct ProposalResult {
    pub proposal_id: u64,
    pub needs_sapling_params: bool,
    pub fee_zatoshi: u64,
}

pub struct ExecuteProposalResult {
    pub txids: String,
    pub status: String,
    pub broadcasted_count: u32,
    pub total_count: u32,
    pub message: Option<String>,
}

pub struct IronwoodMigrationResult {
    pub txids: String,
    pub status: String,
    pub broadcasted_count: u32,
    pub total_count: u32,
    pub message: Option<String>,
    pub fee_zatoshi: u64,
    pub migrated_zatoshi: u64,
}

pub(crate) struct SendMaxEstimateResult {
    pub amount_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub needs_sapling_params: bool,
}

pub(crate) struct ShieldTransparentResult {
    pub txids: String,
    pub status: String,
    pub broadcasted_count: u32,
    pub total_count: u32,
    pub message: Option<String>,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
}

pub(crate) struct ShieldTransparentStatus {
    pub can_shield: bool,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
    pub reason: String,
}

pub(crate) struct ShieldTransparentPcztResult {
    pub pczt_bytes: Vec<u8>,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
    pub needs_sapling_params: bool,
}

pub(crate) struct OrchardMigrationPrivatePlan {
    pub target_values_zatoshi: Vec<u64>,
    pub total_input_zatoshi: u64,
    pub total_migratable_zatoshi: u64,
    pub orchard_change_zatoshi: Option<u64>,
    pub denomination_split_fee_zatoshi: u64,
    pub migration_fee_zatoshi: u64,
    pub estimated_total_fee_zatoshi: u64,
    pub planned_batch_count: u32,
    pub denomination_split_stage_count: u32,
    pub signing_batch_limit: u32,
    pub schedule_mean_delay_blocks: u32,
    pub schedule_max_delay_blocks: u32,
    pub max_prepared_notes_per_run: u32,
    pub scheduled_transfers: Vec<super::migration::MigrationScheduleEntry>,
}

pub(crate) struct KeystoneMigrationMessage {
    pub id: String,
    pub redacted_pczt: Vec<u8>,
}

pub(crate) struct KeystoneMigrationSigningRequest {
    pub request_id: String,
    pub messages: Vec<KeystoneMigrationMessage>,
    pub signing_batch_limit: u32,
}

/// One signed message in the compact "signatures-only" response: the produced
/// spend-authorization signatures for the request message `id`, correlated to
/// the wallet's held proofs-PCZT for that id. Replaces the old full-signed-PCZT
/// payload; the wallet re-applies these via [`super::pczt::apply_sigs_and_extract`].
pub(crate) struct KeystoneSignedMigrationMessage {
    pub id: String,
    pub sigs: Vec<pczt::roles::signer::SpendAuthSignature>,
}

pub(crate) struct KeystoneMigrationProofStatus {
    pub ready_count: u32,
    pub total_count: u32,
    pub is_ready: bool,
    pub is_failed: bool,
    pub message: Option<String>,
}

const SHIELDING_THRESHOLD_ZATOSHI: u64 = 100_000;
const MIGRATION_NO_EXPIRY_HEIGHT: u32 = 0;
const MIGRATION_ORCHARD_ACTION_COUNT: usize = 2;
const MIGRATION_IRONWOOD_ACTION_COUNT: usize = 1;
static ACTIVE_IRONWOOD_MIGRATIONS: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
static KEYSTONE_DENOMINATION_REQUESTS: OnceLock<Mutex<HashMap<String, StoredDenominationPczt>>> =
    OnceLock::new();
static KEYSTONE_MIGRATION_REQUESTS: OnceLock<Mutex<HashMap<String, StoredMigrationPcztBatch>>> =
    OnceLock::new();
static KEYSTONE_SINGLE_QR_MIGRATION_REQUESTS: OnceLock<
    Mutex<HashMap<String, StoredSingleQrMigrationPczt>>,
> = OnceLock::new();

struct RetainAllNotes;

impl<NoteRef> NoteRetention<NoteRef> for RetainAllNotes {
    fn should_retain_sapling(&self, _: &ReceivedNote<NoteRef, sapling_crypto::Note>) -> bool {
        true
    }

    fn should_retain_orchard(&self, _: &ReceivedNote<NoteRef, orchard::note::Note>) -> bool {
        true
    }

    fn should_retain_ironwood(&self, _: &ReceivedNote<NoteRef, orchard::note::Note>) -> bool {
        true
    }
}

/// Wallet-local ZIP-317 rule that preserves standard fee parameters but
/// prevents exact transparent-input serialization from shrinking below
/// ZIP-317's P2PKH size bound between proposal and transaction build.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub(in crate::wallet) struct ConservativeZip317FeeRule;

pub(in crate::wallet) type WalletFeeRule = ConservativeZip317FeeRule;

impl FeeRule for ConservativeZip317FeeRule {
    type Error = <StandardFeeRule as FeeRule>::Error;

    #[allow(clippy::too_many_arguments)]
    fn fee_required<P: consensus::Parameters>(
        &self,
        params: &P,
        target_height: zcash_protocol::consensus::BlockHeight,
        transparent_input_sizes: impl IntoIterator<Item = TransparentInputSize>,
        transparent_output_sizes: impl IntoIterator<Item = usize>,
        sapling_input_count: usize,
        sapling_output_count: usize,
        orchard_action_count: usize,
        ironwood_action_count: usize,
    ) -> Result<Zatoshis, Self::Error> {
        let transparent_input_sizes = transparent_input_sizes.into_iter().map(|size| match size {
            TransparentInputSize::Known(size) => {
                TransparentInputSize::Known(size.max(P2PKH_STANDARD_INPUT_SIZE))
            }
            TransparentInputSize::Unknown(outpoint) => TransparentInputSize::Unknown(outpoint),
        });

        StandardFeeRule::Zip317.fee_required(
            params,
            target_height,
            transparent_input_sizes,
            transparent_output_sizes,
            sapling_input_count,
            sapling_output_count,
            orchard_action_count,
            ironwood_action_count,
        )
    }
}

impl Zip317FeeRule for ConservativeZip317FeeRule {
    fn marginal_fee(&self) -> Zatoshis {
        StandardFeeRule::Zip317.marginal_fee()
    }

    fn grace_actions(&self) -> usize {
        StandardFeeRule::Zip317.grace_actions()
    }
}

fn canonical_migration_fee_zatoshi(
    network: WalletNetwork,
    target_height: u32,
) -> Result<u64, String> {
    ConservativeZip317FeeRule
        .fee_required(
            &network,
            BlockHeight::from_u32(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            MIGRATION_ORCHARD_ACTION_COUNT,
            MIGRATION_IRONWOOD_ACTION_COUNT,
        )
        .map(u64::from)
        .map_err(|e| format!("Calculate canonical migration fee: {e}"))
}

fn pending_migration_policy_rebuild_message(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<Option<String>, String> {
    let canonical_fee = canonical_migration_fee_zatoshi(
        network,
        chain_tip_height
            .checked_add(1)
            .ok_or("Migration target height overflow")?,
    )?;
    let stale_fee_count =
        super::migration::noncanonical_unconfirmed_fee_count(db_path, run_id, canonical_fee)?;
    if stale_fee_count > 0 {
        return Ok(Some(format!(
            "{stale_fee_count} migration transaction(s) use an outdated canonical fee. Review and approve a fresh schedule for the remaining Orchard balance."
        )));
    }

    let externally_spent =
        super::migration::scheduled_inputs_spent_by_mined_transactions(db_path, run_id)?;
    if !externally_spent.is_empty() {
        return Ok(Some(format!(
            "{} scheduled migration input(s) were spent outside this run. Review and approve a revised schedule for the remaining Orchard balance.",
            externally_spent.len()
        )));
    }
    Ok(None)
}

pub fn propose_send(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    send_flow_id: &str,
    to_address: &str,
    amount_zatoshi: u64,
    memo_str: Option<&str>,
) -> Result<ProposalResult, String> {
    use zcash_protocol::{PoolType, ShieldedProtocol as SP};

    if send_flow_id.is_empty() {
        return Err("Send flow id is required".to_string());
    }

    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let proposed_tx_version = proposed_tx_version_for_wallet_db(&db, network, "creating a send")?;
    let request = build_send_request(to_address, amount_zatoshi, memo_str)?;
    let migration_locks = super::migration::locked_migration_note_refs(db_path, account_uuid)?;
    let pass1_proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &migration_locks,
        proposed_tx_version,
        false,
    )?;
    let (proposal, stored_tx_version) =
        propose_with_note_version_downgrade(pass1_proposal, proposed_tx_version, |tx_version| {
            let request = build_send_request(to_address, amount_zatoshi, memo_str)?;
            propose_send_with_reserved_notes(
                &db,
                network,
                account_id,
                request,
                &BTreeSet::new(),
                &migration_locks,
                tx_version,
                false,
            )
        });

    let needs_sapling = proposal
        .steps()
        .iter()
        .any(|step| step.involves(PoolType::Shielded(SP::Sapling)));

    let fee: u64 = proposal
        .steps()
        .iter()
        .map(|step| u64::from(step.balance().fee_required()))
        .sum();

    // Store proposal for later execution.
    let mut store = PROPOSAL_STORE
        .lock()
        .map_err(|e| format!("Lock error: {e}"))?;
    let id = store.next_id;
    store.next_id += 1;
    store.proposals.insert(
        id,
        StoredProposal {
            proposal,
            proposed_tx_version: stored_tx_version,
            // Regular sends stay padded; only migration children opt in.
            unpadded_orchard_pool_bundles: false,
            network,
            account_id,
            send_flow_id: send_flow_id.to_string(),
        },
    );

    Ok(ProposalResult {
        proposal_id: id,
        needs_sapling_params: needs_sapling,
        fee_zatoshi: fee,
    })
}

/// Estimate the fee for a transfer without storing the proposal.
/// Used for validation only — does not consume resources in
/// `PROPOSAL_STORE`.
pub fn estimate_fee(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    to_address: &str,
    amount_zatoshi: u64,
    memo_str: Option<&str>,
) -> Result<u64, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let proposed_tx_version =
        proposed_tx_version_for_wallet_db(&db, network, "estimating a send fee")?;
    let request = build_send_request(to_address, amount_zatoshi, memo_str)?;
    let migration_locks = super::migration::locked_migration_note_refs(db_path, account_uuid)?;
    let pass1_proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &migration_locks,
        proposed_tx_version,
        false,
    )?;
    // Same two-pass rule as `propose_send`, so the displayed estimate equals
    // the stored proposal's fee.
    let (proposal, _) =
        propose_with_note_version_downgrade(pass1_proposal, proposed_tx_version, |tx_version| {
            let request = build_send_request(to_address, amount_zatoshi, memo_str)?;
            propose_send_with_reserved_notes(
                &db,
                network,
                account_id,
                request,
                &BTreeSet::new(),
                &migration_locks,
                tx_version,
                false,
            )
        });

    Ok(proposal_fee_zatoshi(&proposal))
}

/// Estimate the maximum recipient amount for the current destination and memo.
///
/// This uses librustzcash's max-spend proposal path instead of subtracting a
/// guessed fee from the aggregate balance. That keeps note selection, ZIP-317
/// fees, recipient pool choice, and ZIP-315 confirmation policy aligned with
/// the actual send flow.
pub(crate) fn estimate_send_max(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    to_address: &str,
    memo_str: Option<&str>,
) -> Result<SendMaxEstimateResult, String> {
    let mut db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    // librustzcash's max-spend proposal path no longer takes a proposed tx
    // version: the version (and its fee shape) is decided when the PCZT is
    // created, so the quote stays aligned with what `propose_send` can build.
    let proposal = build_send_max_proposal(&mut db, network, account_id, to_address, memo_str)?;
    summarize_send_max_proposal(&proposal)
}

/// Dry-run the transparent shielding proposal path without creating or
/// broadcasting a transaction. This is used to decide whether the home screen
/// should offer the Shield Balance action.
pub(crate) fn get_shield_transparent_status(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<ShieldTransparentStatus, String> {
    let shielding_threshold = shielding_threshold()?;
    let mut db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;

    match build_shielding_proposal(&mut db, network, account_id, shielding_threshold) {
        Ok((proposal, _)) => Ok(ShieldTransparentStatus {
            can_shield: true,
            fee_zatoshi: proposal_fee_zatoshi(&proposal),
            shielded_zatoshi: proposal_shielded_zatoshi(&proposal),
            reason: String::new(),
        }),
        Err(reason) => Ok(ShieldTransparentStatus {
            can_shield: false,
            fee_zatoshi: 0,
            shielded_zatoshi: 0,
            reason,
        }),
    }
}

/// Create an Ironwood transparent-shielding PCZT for hardware accounts.
pub(crate) fn create_shield_transparent_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<ShieldTransparentPcztResult, String> {
    use zcash_client_backend::data_api::wallet::create_pczt_from_proposal as zcb_create_pczt;

    let shielding_threshold = shielding_threshold()?;

    with_wallet_db_write_lock("send.create_shield_transparent_pczt", || {
        let mut db = open_wallet_db(db_path, network)?;
        let account_id = parse_account_uuid(account_uuid)?;
        let (proposal, _) =
            build_shielding_proposal(&mut db, network, account_id, shielding_threshold)?;
        let fee_zatoshi = proposal_fee_zatoshi(&proposal);
        let shielded_zatoshi = proposal_shielded_zatoshi(&proposal);

        // The version-less creator pins V5; shielding must request V6
        // explicitly once NU6.3 is active so the shielded output lands in the
        // Ironwood pool (the fork derived this from the target height). Use
        // the proposal's own target height rather than the synced-wallet
        // probe: the shielding flow works from the chain tip alone.
        let proposed_tx_version =
            proposed_tx_version_for_send(network, proposal.min_target_height());
        // The transaction version rides on the proposal now; `None` builds at
        // the version implied by the target height.
        let proposal = proposal.with_proposed_version(proposed_tx_version);
        let pczt = zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &network,
            account_id,
            OvkPolicy::Sender,
            &proposal,
            // Keep the builder-derived expiry height.
            None,
            orchard::builder::BundleType::DEFAULT,
        )
        .map_err(|e| format!("Create shielding PCZT failed: {e}"))?;
        let pczt_bytes = pczt
            .serialize()
            .map_err(|e| format!("Serialize shielding PCZT: {e:?}"))?;
        ensure_transparent_shielding_pczt_targets_ironwood(&pczt_bytes)?;

        Ok(ShieldTransparentPcztResult {
            pczt_bytes,
            fee_zatoshi,
            shielded_zatoshi,
            needs_sapling_params: false,
        })
    })
}

/// Shield spendable transparent funds for a software account to its
/// internal shielded address. This is intentionally a one-shot API:
/// unlike normal sends there is no confirmation screen, proposal ID,
/// or hardware-wallet branch.
pub(crate) async fn shield_transparent_balance(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
) -> Result<ShieldTransparentResult, String> {
    let shielding_threshold = shielding_threshold()?;

    let (txids, fee_zatoshi, shielded_zatoshi) = with_wallet_db_write_lock(
        "send.shield_transparent_balance.create_transactions",
        move || {
            let mut db = open_wallet_db(db_path, network)?;
            let account_id = parse_account_uuid(account_uuid)?;
            let account = db
                .get_account(account_id)
                .map_err(|e| format!("{e}"))?
                .ok_or("Account not found")?;

            let (proposal, _) =
                build_shielding_proposal(&mut db, network, account_id, shielding_threshold)?;
            let fee_zatoshi = proposal_fee_zatoshi(&proposal);
            let shielded_zatoshi = proposal_shielded_zatoshi(&proposal);

            let zip32_index = account
                .source()
                .key_derivation()
                .ok_or("No key derivation")?
                .account_index();
            let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
                .map_err(|e| format!("USK derivation failed: {e:?}"))?;
            drop(seed);

            let spend_prover = NoOpSpendProver;
            let output_prover = NoOpOutputProver;
            let txids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
                &mut db,
                &network,
                &spend_prover,
                &output_prover,
                &wallet::SpendingKeys::from_unified_spending_key(usk),
                OvkPolicy::Sender,
                &proposal,
            )
            .map_err(|e| format!("Create shielding TX failed: {e}"))?;

            Ok::<_, String>((txids, fee_zatoshi, shielded_zatoshi))
        },
    )?;

    let txids: Vec<TxId> = txids.iter().cloned().collect();
    Ok(
        broadcast_created_transactions(db_path, lightwalletd_url, &txids, "shield")
            .await
            .into_shield_transparent_result(fee_zatoshi, shielded_zatoshi),
    )
}

/// Execute a previously proposed transfer, then broadcast to the
/// network.
///
/// Consume-on-entry: the proposal is removed from `PROPOSAL_STORE`
/// before any fallible work, mirroring `create_pczt_from_proposal`
/// in `sync/pczt.rs`. A second call with the same id returns
/// "Proposal not found".
pub async fn execute_proposal(
    db_path: &str,
    lightwalletd_url: &str,
    proposal_id: u64,
    send_flow_id: &str,
    seed: SecretVec<u8>,
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExecuteProposalResult, String> {
    let stored = consume_stored_proposal(
        proposal_id,
        send_flow_id,
        "Proposal not found (expired or already executed)",
    )?;
    execute_stored_proposal(
        db_path,
        lightwalletd_url,
        stored,
        seed,
        spend_params_path,
        output_params_path,
    )
    .await
}

pub async fn execute_proposal_with_seed_loader<F>(
    db_path: &str,
    lightwalletd_url: &str,
    proposal_id: u64,
    send_flow_id: &str,
    load_seed: F,
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExecuteProposalResult, String>
where
    F: FnOnce(WalletNetwork, AccountUuid) -> Result<SecretVec<u8>, String>,
{
    let stored = consume_stored_proposal(
        proposal_id,
        send_flow_id,
        "Proposal not found (expired or already executed)",
    )?;
    let seed = load_seed(stored.network, stored.account_id)?;
    execute_stored_proposal(
        db_path,
        lightwalletd_url,
        stored,
        seed,
        spend_params_path,
        output_params_path,
    )
    .await
}

async fn execute_stored_proposal(
    db_path: &str,
    lightwalletd_url: &str,
    stored: StoredProposal,
    seed: SecretVec<u8>,
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExecuteProposalResult, String> {
    let network = stored.network;

    // Scope DB writes and signing material so they are dropped before network I/O (broadcast).
    let txids =
        with_wallet_db_write_lock("send.execute_proposal.create_transactions", move || {
            let mut db = open_wallet_db(db_path, network)?;
            let account_id = stored.account_id;
            let account = db
                .get_account(account_id)
                .map_err(|e| format!("{e}"))?
                .ok_or("Account not found")?;
            let zip32_index = account
                .source()
                .key_derivation()
                .ok_or("No key derivation")?
                .account_index();
            let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
                .map_err(|e| format!("USK derivation failed: {e:?}"))?;
            drop(seed);
            // The transaction version rides on the proposal now; `None` builds
            // at the version implied by the target height.
            let proposal = stored
                .proposal
                .clone()
                .with_proposed_version(stored.proposed_tx_version);

            let txids = match (spend_params_path, output_params_path) {
                (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
                    let prover =
                        LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
                    create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
                        &mut db,
                        &network,
                        &prover,
                        &prover,
                        &wallet::SpendingKeys::from_unified_spending_key(usk),
                        OvkPolicy::Sender,
                        &proposal,
                    )
                    .map_err(|e| format!("Create TX failed: {e}"))?
                }
                _ => {
                    let spend_prover = NoOpSpendProver;
                    let output_prover = NoOpOutputProver;
                    create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
                        &mut db,
                        &network,
                        &spend_prover,
                        &output_prover,
                        &wallet::SpendingKeys::from_unified_spending_key(usk),
                        OvkPolicy::Sender,
                        &proposal,
                    )
                    .map_err(|e| format!("Create TX failed: {e}"))?
                }
            };
            // USK and derived spending keys dropped here, before broadcast.
            Ok::<_, String>(txids)
        })?;

    let txids: Vec<TxId> = txids.iter().cloned().collect();
    Ok(
        broadcast_created_transactions(db_path, lightwalletd_url, &txids, "send")
            .await
            .into_execute_result(),
    )
}

pub(crate) async fn migrate_orchard_to_ironwood(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
    approved_schedule: Vec<super::migration::MigrationScheduleEntry>,
) -> Result<IronwoodMigrationResult, String> {
    let migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;

    if let Some(run) = super::migration::active_migration_run(db_path, account_uuid, network)? {
        match advance_staged_denomination_run(
            db_path,
            lightwalletd_url,
            network,
            account_uuid,
            &run,
            pending_password.as_slice(),
            pending_salt_base64,
        )
        .await?
        {
            StagedDenominationAdvance::Waiting(result) => {
                drop(seed);
                drop(migration_guard);
                return Ok(result);
            }
            StagedDenominationAdvance::Ready => {
                let chain_tip_height =
                    u32::try_from(super::get_sync_progress(db_path, network)?.chain_tip_height)
                        .map_err(|_| "Migration chain tip exceeds u32".to_string())?;
                if let Some(message) = pending_migration_policy_rebuild_message(
                    db_path,
                    network,
                    &run.run_id,
                    chain_tip_height,
                )? {
                    drop(seed);
                    super::migration::retire_run_for_rebuild(db_path, &run.run_id, &message)?;
                    let totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
                    let result = migration_result_from_pending_totals(
                        totals,
                        super::migration::PHASE_FAILED_TERMINAL,
                        Some(message),
                        run.target_values_zatoshi.len() as u32,
                        run.target_values_zatoshi.iter().sum(),
                    );
                    drop(migration_guard);
                    return Ok(result);
                }
                super::migration::mark_expired_pending_parts_for_resign(
                    db_path,
                    &run.run_id,
                    chain_tip_height,
                )?;
                let recoveries =
                    super::migration::pending_parts_needing_resign(db_path, &run.run_id)?;
                if recoveries.is_empty() {
                    drop(seed);
                } else {
                    let usk = derive_migration_usk(db_path, network, account_uuid, seed)?;
                    rebuild_expired_software_migration_parts(
                        db_path,
                        network,
                        account_uuid,
                        &run.run_id,
                        recoveries,
                        &usk,
                        pending_password.as_slice(),
                        pending_salt_base64,
                    )?;
                }
                if super::migration::signed_child_pczt_count(db_path, &run.run_id)? > 0 {
                    let finalized = finalize_presigned_migration_children(
                        db_path,
                        network,
                        account_uuid,
                        &run.run_id,
                        pending_password.as_slice(),
                        pending_salt_base64,
                    )?;
                    if !finalized {
                        let result = prepared_notes_not_spendable_result(
                            run.target_values_zatoshi.len() as u32,
                            run.target_values_zatoshi.iter().sum(),
                        );
                        drop(migration_guard);
                        return Ok(result);
                    }
                }
                let result = broadcast_due_scheduled_migration_txs(
                    db_path,
                    lightwalletd_url,
                    network,
                    &run.run_id,
                    pending_password.as_slice(),
                    pending_salt_base64,
                    run.target_values_zatoshi.len() as u32,
                    run.target_values_zatoshi.iter().sum(),
                )
                .await;
                drop(migration_guard);
                return result;
            }
        }
    }

    let prepared = with_wallet_db_write_lock("send.migration.create_denominations", move || {
        prepare_software_migration_run(db_path, network, account_uuid, seed)
    })?;

    let Some(prepared) = prepared else {
        return Err(
            "Create migration denominations failed: insufficient spendable Orchard funds"
                .to_string(),
        );
    };

    let PreparedSoftwareMigrationRun {
        plan,
        prepared_refs,
        denomination_stages,
        signed_children,
        fee_zatoshi,
        total_migratable_zatoshi,
    } = prepared;
    super::migration::validate_schedule(&approved_schedule, &plan.migration_outputs, network)?;
    let prepared_count = u32::try_from(prepared_refs.len())
        .map_err(|_| "Migration output count exceeds u32".to_string())?;
    let run_id = super::migration::create_run_with_staged_denominations_and_signed_children(
        db_path,
        account_uuid,
        network,
        &plan,
        &prepared_refs,
        signed_children,
        denomination_stages,
        pending_password.as_slice(),
        pending_salt_base64,
    )?;
    super::migration::set_run_approved_schedule(
        db_path,
        &run_id,
        network,
        &approved_schedule,
        &plan.migration_outputs,
    )?;

    let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run_id,
        pending_password.as_slice(),
        pending_salt_base64,
    )
    .await?
    else {
        return Err(
            "Migration denomination split has no broadcastable root transaction".to_string(),
        );
    };
    drop(migration_guard);

    Ok(migration_result_from_split_broadcast(
        broadcast,
        prepared_count,
        fee_zatoshi,
        total_migratable_zatoshi,
    ))
}

pub async fn broadcast_due_orchard_migration_transactions(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let Some(run) = super::migration::active_migration_run(db_path, account_uuid, network)? else {
        return Ok(IronwoodMigrationResult {
            txids: String::new(),
            status: super::migration::PHASE_COMPLETE.to_string(),
            broadcasted_count: 0,
            total_count: 0,
            message: None,
            fee_zatoshi: 0,
            migrated_zatoshi: 0,
        });
    };

    match advance_staged_denomination_run(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        &run,
        pending_password.as_slice(),
        pending_salt_base64,
    )
    .await?
    {
        StagedDenominationAdvance::Waiting(result) => return Ok(result),
        StagedDenominationAdvance::Ready => {}
    }

    let signed_child_count = super::migration::signed_child_pczt_count(db_path, &run.run_id)?;
    if signed_child_count > 0 {
        if !run_may_finalize_presigned_migration_children(&run) {
            return Ok(prepared_notes_not_spendable_result(
                run.target_values_zatoshi.len() as u32,
                run.target_values_zatoshi.iter().sum(),
            ));
        }
        let finalized = finalize_presigned_migration_children(
            db_path,
            network,
            account_uuid,
            &run.run_id,
            pending_password.as_slice(),
            pending_salt_base64,
        )?;
        if !finalized {
            return Ok(prepared_notes_not_spendable_result(
                run.target_values_zatoshi.len() as u32,
                run.target_values_zatoshi.iter().sum(),
            ));
        }
    }

    broadcast_due_scheduled_migration_txs(
        db_path,
        lightwalletd_url,
        network,
        &run.run_id,
        pending_password.as_slice(),
        pending_salt_base64,
        run.target_values_zatoshi.len() as u32,
        run.target_values_zatoshi.iter().sum(),
    )
    .await
}

pub(crate) fn prepare_orchard_migration_denominations_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err("Migration already has an active run. Start migration next.".to_string());
    }
    {
        let mut request_store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        ensure_no_live_single_qr_migration_request(&mut request_store, account_uuid, network)?;
    }
    {
        let mut request_store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        ensure_no_live_denomination_request(&mut request_store, account_uuid, network)?;
    }

    let split = with_wallet_db_write_lock("send.migration.prepare_denominations_pczt", || {
        create_padded_orchard_denomination_pczts(db_path, network, account_uuid)
    })?;
    let Some(split) = split else {
        return Err(
            "Create migration denominations failed: insufficient spendable Orchard funds"
                .to_string(),
        );
    };

    let request_id = new_keystone_migration_request_id("denominations");
    let messages = split
        .stages
        .iter()
        .map(|stage| KeystoneMigrationMessage {
            id: stage.id.clone(),
            redacted_pczt: stage.redacted_pczt.clone(),
        })
        .collect::<Vec<_>>();
    validate_keystone_migration_messages(&messages)?;
    let root_proofs = split
        .stages
        .iter()
        .filter(|stage| !stage.deferred)
        .map(|stage| (stage.id.clone(), stage.base_pczt.clone()))
        .collect::<Vec<_>>();
    if root_proofs.is_empty() {
        return Err("Padded denomination plan has no immediately provable root".to_string());
    }
    let mut request_store = keystone_denomination_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredDenominationPczt {
            account_uuid: account_uuid.to_string(),
            network,
            state: KeystoneMigrationRequestState::Proofing,
            proof_error: None,
            split_stages: split.stages,
            total_migratable_zatoshi: split.total_migratable_zatoshi,
            plan: split.plan,
        },
    );
    drop(request_store);
    spawn_denomination_proof_worker(request_id.clone(), root_proofs);

    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
    })
}

pub(crate) async fn complete_orchard_migration_denominations_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    pending_password: &[u8],
    pending_salt_base64: &str,
    approved_schedule: Vec<super::migration::MigrationScheduleEntry>,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let signed_by_id = signed_migration_messages_by_id(request_id, signed_messages)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err(
            "Migration already has an active run. Reject this Keystone request.".to_string(),
        );
    }

    let stored = {
        let mut store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        let stored = store.get_mut(request_id).ok_or_else(|| {
            format!("Keystone denomination request {request_id} was not found or was already used")
        })?;
        if stored.account_uuid != account_uuid || stored.network != network {
            return Err(
                "Signed denomination request does not match the active account".to_string(),
            );
        }
        if signed_by_id.len() != stored.split_stages.len() {
            return Err(format!(
                "Keystone returned {} signed messages for {} requested denomination splits",
                signed_by_id.len(),
                stored.split_stages.len()
            ));
        }
        match stored.state {
            KeystoneMigrationRequestState::Proofing => {
                return Err(
                    "Vizor is still finishing migration proofs. Try again shortly.".to_string(),
                );
            }
            KeystoneMigrationRequestState::ProofFailed => {
                return Err(stored.proof_error.clone().unwrap_or_else(|| {
                    "Vizor proof generation failed. Reject and prepare a new request.".to_string()
                }));
            }
            KeystoneMigrationRequestState::Completing => {
                return Err("Keystone denomination request is already completing".to_string());
            }
            KeystoneMigrationRequestState::ProofReady => {}
        }
        if stored
            .split_stages
            .iter()
            .any(|stage| !stage.deferred && stage.pczt_with_proofs.is_none())
        {
            return Err("Keystone denomination root proofs are not ready".to_string());
        }
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredDenominationCompletion {
            split_stages: stored.split_stages.clone(),
            total_migratable_zatoshi: stored.total_migratable_zatoshi,
            plan: stored.plan.clone(),
        }
    };

    for stage in &stored.split_stages {
        if !signed_by_id.contains_key(&stage.id) {
            reset_denomination_request_after_failed_completion(request_id);
            return Err(format!("Keystone result missing {}", stage.id));
        }
    }
    let prepared_refs = prepared_refs_from_denomination_stages(&stored.split_stages);
    if let Err(e) = super::migration::validate_schedule(
        &approved_schedule,
        &stored.plan.migration_outputs,
        network,
    ) {
        reset_denomination_request_after_failed_completion(request_id);
        return Err(e);
    }

    let finalize_result = (|| -> Result<String, String> {
        let denomination_stages =
            signed_denomination_stage_inserts(&stored.split_stages, &signed_by_id)?;
        super::migration::create_run_with_staged_denominations_and_signed_children(
            db_path,
            account_uuid,
            network,
            &stored.plan,
            &prepared_refs,
            Vec::new(),
            denomination_stages,
            pending_password,
            pending_salt_base64,
        )
    })();
    let run_id = match finalize_result {
        Ok(run_id) => run_id,
        Err(e) => {
            reset_denomination_request_after_failed_completion(request_id);
            return Err(e);
        }
    };
    if let Err(e) = super::migration::set_run_approved_schedule(
        db_path,
        &run_id,
        network,
        &approved_schedule,
        &stored.plan.migration_outputs,
    ) {
        let _ = super::migration::retire_run_for_rebuild(
            db_path,
            &run_id,
            "The approved Keystone migration schedule could not be saved.",
        );
        reset_denomination_request_after_failed_completion(request_id);
        return Err(e);
    }
    if let Ok(mut store) = keystone_denomination_requests().lock() {
        store.remove(request_id);
    }

    let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run_id,
        pending_password,
        pending_salt_base64,
    )
    .await?
    else {
        return Err(
            "Migration denomination split has no broadcastable root transaction".to_string(),
        );
    };

    Ok(migration_result_from_split_broadcast(
        broadcast,
        prepared_refs.len() as u32,
        stored.split_stages.iter().try_fold(0u64, |total, stage| {
            total
                .checked_add(stage.fee_zatoshi)
                .ok_or("Denomination stage fee total overflow")
        })?,
        stored.total_migratable_zatoshi,
    ))
}

pub(crate) fn prepare_orchard_migration_single_qr_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err("Migration already has an active run.".to_string());
    }
    {
        let mut store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        ensure_no_live_denomination_request(&mut store, account_uuid, network)?;
    }
    {
        let mut store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        ensure_no_live_single_qr_migration_request(&mut store, account_uuid, network)?;
    }

    let split = with_wallet_db_write_lock("send.migration.prepare_single_qr_pczt", || {
        create_padded_orchard_denomination_pczts(db_path, network, account_uuid)
    })?;
    let Some(split) = split else {
        return Err(
            "Create migration denominations failed: insufficient spendable Orchard funds"
                .to_string(),
        );
    };

    let total_messages = split
        .predicted_notes
        .len()
        .checked_add(split.stages.len())
        .ok_or("Keystone migration message count overflow")?;
    if total_messages > ZCASH_SIGN_BATCH_MAX_MESSAGES {
        return Err(format!(
            "Single Keystone migration signing supports at most {ZCASH_SIGN_BATCH_MAX_MESSAGES} PCZTs, but this plan needs {} split transactions plus {} migration transactions. Reduce the migration amount or use the staged flow.",
            split.stages.len(),
            split.predicted_notes.len(),
        ));
    }

    let mut child_messages = Vec::with_capacity(split.predicted_notes.len());
    for (index, predicted) in split.predicted_notes.iter().enumerate() {
        let pczt = create_orchard_to_ironwood_pczt_from_predicted_note(
            db_path,
            network,
            account_uuid,
            predicted,
            (index + 1) as u32,
        )?
        .ok_or("Predicted migration note is below the migration fee threshold")?;
        child_messages.push(pczt);
    }

    let request_id = new_keystone_migration_request_id("single");
    let mut messages = Vec::with_capacity(total_messages);
    messages.extend(split.stages.iter().map(|stage| KeystoneMigrationMessage {
        id: stage.id.clone(),
        redacted_pczt: stage.redacted_pczt.clone(),
    }));
    messages.extend(
        child_messages
            .iter()
            .map(|message| KeystoneMigrationMessage {
                id: message.id.clone(),
                redacted_pczt: message.redacted_pczt.clone(),
            }),
    );
    validate_keystone_migration_messages(&messages)?;

    let root_proofs = split
        .stages
        .iter()
        .filter(|stage| !stage.deferred)
        .map(|stage| (stage.id.clone(), stage.base_pczt.clone()))
        .collect::<Vec<_>>();
    if root_proofs.is_empty() {
        return Err("Padded denomination plan has no immediately provable root".to_string());
    }
    let mut request_store = keystone_single_qr_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredSingleQrMigrationPczt {
            account_uuid: account_uuid.to_string(),
            network,
            state: KeystoneMigrationRequestState::Proofing,
            proof_error: None,
            split_stages: split.stages,
            total_migratable_zatoshi: split.total_migratable_zatoshi,
            plan: split.plan,
            child_messages,
        },
    );
    drop(request_store);
    spawn_single_qr_split_proof_worker(request_id.clone(), root_proofs);

    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
    })
}

pub(crate) async fn complete_orchard_migration_single_qr_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let signed_by_id = signed_migration_messages_by_id(request_id, signed_messages)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err(
            "Migration already has an active run. Reject this Keystone request.".to_string(),
        );
    }

    let stored = {
        let mut store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        let stored = store.get_mut(request_id).ok_or_else(|| {
            format!("Keystone migration request {request_id} was not found or was already used")
        })?;
        if stored.account_uuid != account_uuid || stored.network != network {
            return Err("Signed migration request does not match the active account".to_string());
        }
        let expected_count = stored
            .child_messages
            .len()
            .checked_add(stored.split_stages.len())
            .ok_or("Keystone migration message count overflow")?;
        if signed_by_id.len() != expected_count {
            return Err(format!(
                "Keystone returned {} signed messages for {} requested messages",
                signed_by_id.len(),
                expected_count
            ));
        }
        match stored.state {
            KeystoneMigrationRequestState::Proofing => {
                return Err(
                    "Vizor is still finishing migration proofs. Try again shortly.".to_string(),
                );
            }
            KeystoneMigrationRequestState::ProofFailed => {
                return Err(stored.proof_error.clone().unwrap_or_else(|| {
                    "Vizor proof generation failed. Reject and prepare a new request.".to_string()
                }));
            }
            KeystoneMigrationRequestState::Completing => {
                return Err("Keystone migration request is already completing".to_string());
            }
            KeystoneMigrationRequestState::ProofReady => {}
        }
        if stored
            .split_stages
            .iter()
            .any(|stage| !stage.deferred && stage.pczt_with_proofs.is_none())
        {
            return Err("Keystone denomination root proofs are not ready".to_string());
        }
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredSingleQrMigrationCompletion {
            split_stages: stored.split_stages.clone(),
            total_migratable_zatoshi: stored.total_migratable_zatoshi,
            plan: stored.plan.clone(),
            child_messages: stored.child_messages.clone(),
        }
    };

    for id in stored
        .split_stages
        .iter()
        .map(|stage| stage.id.as_str())
        .chain(stored.child_messages.iter().map(|child| child.id.as_str()))
    {
        if !signed_by_id.contains_key(id) {
            reset_single_qr_request_after_failed_completion(request_id);
            return Err(format!("Keystone result missing {id}"));
        }
    }

    let prepared_refs = prepared_refs_from_denomination_stages(&stored.split_stages);

    let finalize_result = (|| -> Result<String, String> {
        let denomination_stages =
            signed_denomination_stage_inserts(&stored.split_stages, &signed_by_id)?;
        let signed_children = stored
            .child_messages
            .iter()
            .enumerate()
            .map(|(index, child)| {
                let mut selected_note = child.selected_note.clone();
                selected_note.nullifier_hex = None;
                let sigs = signed_by_id
                    .get(&child.id)
                    .ok_or_else(|| format!("Keystone result missing {}", child.id))?
                    .clone();
                super::pczt::preflight_orchard_spend_auth_signatures(&child.base_pczt, &sigs)?;
                Ok(super::migration::SignedMigrationPcztInsert {
                    message_id: child.id.clone(),
                    child_index: index as u32,
                    base_pczt: child.base_pczt.clone(),
                    sigs,
                    target_height: child.target_height,
                    anchor_boundary_height: child.anchor_boundary_height,
                    expiry_height: child.expiry_height,
                    value_zatoshi: child.migrated_zatoshi,
                    fee_zatoshi: child.fee_zatoshi,
                    selected_note: selected_note.clone(),
                    metadata: super::migration::PendingMigrationTxMetadata {
                        tx_kind: "migration".to_string(),
                        funding_account_uuid: account_uuid.to_string(),
                        selected_note,
                    },
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        super::migration::create_run_with_staged_denominations_and_signed_children(
            db_path,
            account_uuid,
            network,
            &stored.plan,
            &prepared_refs,
            signed_children,
            denomination_stages,
            pending_password,
            pending_salt_base64,
        )
    })();
    let run_id = match finalize_result {
        Ok(run_id) => run_id,
        Err(e) => {
            reset_single_qr_request_after_failed_completion(request_id);
            return Err(e);
        }
    };
    if let Ok(mut store) = keystone_single_qr_migration_requests().lock() {
        store.remove(request_id);
    }

    let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run_id,
        pending_password,
        pending_salt_base64,
    )
    .await?
    else {
        return Err(
            "Migration denomination split has no broadcastable root transaction".to_string(),
        );
    };

    Ok(migration_result_from_split_broadcast(
        broadcast,
        prepared_refs.len() as u32,
        stored
            .split_stages
            .iter()
            .map(|stage| stage.fee_zatoshi)
            .sum(),
        stored.total_migratable_zatoshi,
    ))
}

pub(crate) fn prepare_orchard_migration_batch_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let run = super::migration::active_migration_run(db_path, account_uuid, network)?
        .ok_or("No active migration run")?;
    let chain_tip_height =
        u32::try_from(super::get_sync_progress(db_path, network)?.chain_tip_height)
            .map_err(|_| "Migration chain tip exceeds u32".to_string())?;
    if let Some(message) =
        pending_migration_policy_rebuild_message(db_path, network, &run.run_id, chain_tip_height)?
    {
        super::migration::retire_run_for_rebuild(db_path, &run.run_id, &message)?;
        return Err(message);
    }
    super::migration::mark_expired_pending_parts_for_resign(
        db_path,
        &run.run_id,
        chain_tip_height,
    )?;
    let recoveries = super::migration::pending_parts_needing_resign(db_path, &run.run_id)?;
    let all_prepared_notes = super::migration::prepared_notes_for_run(db_path, &run.run_id)?;
    let prepared_notes = if recoveries.is_empty() {
        all_prepared_notes
    } else {
        recoveries
            .iter()
            .map(|recovery| recovery.selected_note.clone())
            .collect()
    };
    if prepared_notes.is_empty() {
        return Err("Migration run has no prepared denomination notes".to_string());
    }
    let pending_totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
    if recoveries.is_empty() && pending_totals.total_count > 0 {
        return Err("Migration transactions are already signed and scheduled".to_string());
    }
    if !prepared_note_spend_metadata_is_available(db_path, &run.run_id)? {
        return Err(
            "Prepared denomination notes are not spendable yet. Sync and try again.".to_string(),
        );
    }
    {
        let mut request_store = keystone_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
        ensure_no_live_migration_request(&mut request_store, account_uuid, network, &run.run_id)?;
    }

    let mut created = Vec::with_capacity(prepared_notes.len());
    let mut anchor_cohort_counts =
        super::migration::pending_anchor_cohort_counts(db_path, &run.run_id)?;
    for (index, note_ref) in prepared_notes.iter().enumerate() {
        let pczt = match with_wallet_db_write_lock("send.migration.prepare_exact_note_pczt", || {
            create_orchard_to_ironwood_pczt_from_note(
                db_path,
                network,
                account_uuid,
                note_ref,
                (index + 1) as u32,
                &mut anchor_cohort_counts,
                !recoveries.is_empty(),
            )
        }) {
            Ok(pczt) => pczt,
            Err(e) if is_orchard_witness_not_ready_error(&e) => {
                mark_prepared_notes_waiting(db_path, &run.run_id)?;
                return Err(
                    "Prepared denomination notes are not spendable yet. Sync and try again."
                        .to_string(),
                );
            }
            Err(e) => return Err(e),
        };
        let Some(pczt) = pczt else {
            mark_prepared_notes_waiting(db_path, &run.run_id)?;
            return Err(
                "Prepared denomination notes are not spendable yet. Sync and try again."
                    .to_string(),
            );
        };
        if let Some(recovery) = recoveries.get(index) {
            if pczt.migrated_zatoshi != recovery.value_zatoshi {
                return Err("Expired migration denomination changed during rebuild".to_string());
            }
            if pczt.fee_zatoshi != recovery.fee_zatoshi {
                return Err(
                    "Canonical migration fee changed while rebuilding an expired part".to_string(),
                );
            }
        }
        created.push(pczt);
    }

    let request_id = new_keystone_migration_request_id("batch");
    let messages = created
        .iter()
        .map(|message| KeystoneMigrationMessage {
            id: message.id.clone(),
            redacted_pczt: message.redacted_pczt.clone(),
        })
        .collect::<Vec<_>>();
    validate_keystone_migration_messages(&messages)?;
    let proof_worker_messages = created
        .iter()
        .map(|message| (message.id.clone(), message.base_pczt.clone()))
        .collect::<Vec<_>>();
    let mut request_store = keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredMigrationPcztBatch {
            account_uuid: account_uuid.to_string(),
            network,
            run_id: run.run_id,
            fallback_total_count: run.target_values_zatoshi.len() as u32,
            fallback_migrated_zatoshi: run.target_values_zatoshi.iter().sum(),
            recovery_old_txids: recoveries
                .iter()
                .map(|recovery| recovery.old_txid_hex.clone())
                .collect(),
            state: KeystoneMigrationRequestState::Proofing,
            proof_error: None,
            messages: created,
        },
    );
    drop(request_store);
    spawn_migration_proof_worker(request_id.clone(), proof_worker_messages);

    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
    })
}

pub(crate) fn complete_orchard_migration_batch_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let signed_by_id = signed_migration_messages_by_id(request_id, signed_messages)?;
    let stored = {
        let mut store = keystone_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
        let stored = store.get_mut(request_id).ok_or_else(|| {
            format!("Keystone migration request {request_id} was not found or was already used")
        })?;
        if stored.account_uuid != account_uuid || stored.network != network {
            return Err("Signed migration request does not match the active account".to_string());
        }
        if signed_by_id.len() != stored.messages.len() {
            return Err(format!(
                "Keystone returned {} signed messages for {} requested messages",
                signed_by_id.len(),
                stored.messages.len()
            ));
        }
        match stored.state {
            KeystoneMigrationRequestState::Proofing => {
                return Err(
                    "Vizor is still finishing migration proofs. Try again shortly.".to_string(),
                );
            }
            KeystoneMigrationRequestState::ProofFailed => {
                return Err(stored.proof_error.clone().unwrap_or_else(|| {
                    "Vizor proof generation failed. Reject and prepare a new request.".to_string()
                }));
            }
            KeystoneMigrationRequestState::Completing => {
                return Err("Keystone migration request is already completing".to_string());
            }
            KeystoneMigrationRequestState::ProofReady => {}
        }
        if stored
            .messages
            .iter()
            .any(|message| message.pczt_with_proofs.is_none())
        {
            return Err("Keystone migration proofs are not ready".to_string());
        }
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredMigrationBatchCompletion {
            run_id: stored.run_id.clone(),
            fallback_total_count: stored.fallback_total_count,
            fallback_migrated_zatoshi: stored.fallback_migrated_zatoshi,
            recovery_old_txids: stored.recovery_old_txids.clone(),
            messages: stored.messages.clone(),
        }
    };

    let run = super::migration::active_migration_run(db_path, account_uuid, network)?
        .ok_or("No active migration run")?;
    if run.run_id != stored.run_id {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Signed migration request is for an old migration run".to_string());
    }
    let current_prepared = super::migration::prepared_notes_for_run(db_path, &run.run_id)?;
    let request_prepared = stored
        .messages
        .iter()
        .map(|message| message.selected_note.clone())
        .collect::<Vec<_>>();
    let prepared_notes_unchanged = if stored.recovery_old_txids.is_empty() {
        current_prepared == request_prepared
    } else {
        request_prepared.iter().all(|requested| {
            current_prepared
                .iter()
                .any(|current| same_prepared_note_without_nullifier(current, requested))
        })
    };
    if !prepared_notes_unchanged {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Prepared migration notes changed before completion".to_string());
    }
    if stored.recovery_old_txids.is_empty()
        && super::migration::pending_totals_for_run(db_path, &run.run_id)?.total_count > 0
    {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Migration transactions are already signed and scheduled".to_string());
    }

    let completion_result = (|| -> Result<super::migration::PendingMigrationTotals, String> {
        let mut pending_inserts = Vec::with_capacity(stored.messages.len());
        for message in stored.messages.clone() {
            let sigs = signed_by_id
                .get(&message.id)
                .ok_or_else(|| format!("Keystone result missing {}", message.id))?;
            let extracted = super::pczt::apply_sigs_and_extract(
                message
                    .pczt_with_proofs
                    .as_ref()
                    .ok_or("Keystone migration proof missing")?,
                sigs,
                None,
                None,
            )?;
            pending_inserts.push(super::migration::PendingMigrationTxInsert {
                txid_hex: extracted.txid.to_string(),
                raw_tx: extracted.raw_tx,
                target_height: message.target_height,
                anchor_boundary_height: message.anchor_boundary_height,
                expiry_height: message.expiry_height,
                value_zatoshi: message.migrated_zatoshi,
                fee_zatoshi: message.fee_zatoshi,
                selected_note: message.selected_note.clone(),
                metadata: super::migration::PendingMigrationTxMetadata {
                    tx_kind: "migration".to_string(),
                    funding_account_uuid: account_uuid.to_string(),
                    selected_note: message.selected_note,
                },
            });
        }

        if stored.recovery_old_txids.is_empty() {
            super::migration::insert_pending_txs(
                db_path,
                &stored.run_id,
                pending_inserts,
                pending_password,
                pending_salt_base64,
            )?;
        } else {
            if stored.recovery_old_txids.len() != pending_inserts.len() {
                return Err("Expired migration recovery batch changed size".to_string());
            }
            let replacements = stored
                .recovery_old_txids
                .iter()
                .cloned()
                .zip(pending_inserts)
                .map(|(old_txid_hex, replacement)| {
                    super::migration::PendingMigrationTxReplacement {
                        old_txid_hex,
                        replacement,
                    }
                })
                .collect();
            super::migration::replace_resigned_pending_parts(
                db_path,
                &stored.run_id,
                network,
                replacements,
                Vec::new(),
                pending_password,
                pending_salt_base64,
            )?;
        }
        super::migration::pending_totals_for_run(db_path, &stored.run_id)
    })();
    if completion_result.is_err() {
        reset_migration_request_after_failed_completion(request_id);
    }
    let totals = completion_result?;
    if let Ok(mut store) = keystone_migration_requests().lock() {
        store.remove(request_id);
    }
    Ok(migration_result_from_pending_totals(
        totals,
        super::migration::PHASE_BROADCAST_SCHEDULED,
        Some("Migration transactions were signed and scheduled for delayed broadcast.".to_string()),
        stored.fallback_total_count,
        stored.fallback_migrated_zatoshi,
    ))
}

fn is_orchard_witness_not_ready_error(error: &str) -> bool {
    let lower = error.to_ascii_lowercase();
    lower.contains("read orchard witnesses")
        && (lower.contains("anchornotfound")
            || lower.contains("notcontained")
            || lower.contains("checkpoint")
            || lower.contains("commitmenttree"))
}

fn mark_prepared_notes_waiting(db_path: &str, run_id: &str) -> Result<(), String> {
    super::migration::mark_run_phase(
        db_path,
        run_id,
        super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS,
        Some("Prepared denomination notes are not spendable yet."),
    )
}

fn prepared_note_spend_metadata_is_available(db_path: &str, run_id: &str) -> Result<bool, String> {
    if super::migration::prepared_note_spend_metadata_available(db_path, run_id)? {
        return Ok(true);
    }
    mark_prepared_notes_waiting(db_path, run_id)?;
    Ok(false)
}

fn prepared_notes_not_spendable_result(
    total_count: u32,
    migrated_zatoshi: u64,
) -> IronwoodMigrationResult {
    IronwoodMigrationResult {
        txids: String::new(),
        status: super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS.to_string(),
        broadcasted_count: 0,
        total_count,
        message: Some(
            "Prepared denomination notes are not spendable yet. Sync and try again.".to_string(),
        ),
        fee_zatoshi: 0,
        migrated_zatoshi,
    }
}

enum StagedDenominationAdvance {
    Waiting(IronwoodMigrationResult),
    Ready,
}

fn reconcile_mined_denomination_stages(
    db_path: &str,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<Vec<super::migration::DenominationStage>, String> {
    super::migration::reconcile_denomination_stage_chain_state(db_path, run_id)?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    let stages = super::migration::denomination_stages_for_run(
        &conn,
        run_id,
        pending_password,
        pending_salt_base64,
    )?;
    let mut recovered_included_stage = false;
    for stage in stages
        .iter()
        .filter(|stage| stage.status == super::migration::DenominationStageStatus::AwaitingInputs)
    {
        let Some(identity) =
            super::migration::local_denomination_chain_identity(&conn, &stage.expected_txid_hex)?
        else {
            continue;
        };
        let raw_tx = super::migration::local_transaction_raw(&conn, &stage.expected_txid_hex)?
            .ok_or_else(|| {
                format!(
                    "Mined denomination stage {} is missing wallet transaction bytes",
                    stage.expected_txid_hex
                )
            })?;
        super::migration::promote_awaiting_denomination_stage(
            &conn,
            run_id,
            stage.stage_index,
            &stage.expected_txid_hex,
            raw_tx,
            pending_password,
            pending_salt_base64,
        )?;
        super::migration::replace_denomination_stage_confirmation_identity(
            &conn,
            run_id,
            &stage.expected_txid_hex,
            identity.mined_height,
            &identity.block_hash,
        )?;
        recovered_included_stage = true;
    }
    if recovered_included_stage {
        super::migration::denomination_stages_for_run(
            &conn,
            run_id,
            pending_password,
            pending_salt_base64,
        )
    } else {
        Ok(stages)
    }
}

async fn advance_staged_denomination_run(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run: &super::migration::ActiveRun,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<StagedDenominationAdvance, String> {
    let stages = reconcile_mined_denomination_stages(
        db_path,
        &run.run_id,
        pending_password,
        pending_salt_base64,
    )?;
    if stages.is_empty() {
        return Err(format!(
            "Migration state invariant failed: active run {} has no denomination stages",
            run.run_id
        ));
    }

    let fallback_total_count = u32::try_from(run.target_values_zatoshi.len())
        .map_err(|_| "Migration output count exceeds u32".to_string())?;
    let fallback_migrated_zatoshi = run.target_values_zatoshi.iter().sum();
    let split_fee_zatoshi = stages.iter().try_fold(0u64, |total, stage| {
        total
            .checked_add(stage.fee_zatoshi)
            .ok_or("Denomination stage fee total overflow")
    })?;

    if let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run.run_id,
        pending_password,
        pending_salt_base64,
    )
    .await?
    {
        return Ok(StagedDenominationAdvance::Waiting(
            migration_result_from_split_broadcast(
                broadcast,
                fallback_total_count,
                split_fee_zatoshi,
                fallback_migrated_zatoshi,
            ),
        ));
    }

    if stages
        .iter()
        .any(|stage| stage.status == super::migration::DenominationStageStatus::AwaitingInputs)
    {
        if finalize_ready_denomination_stages(
            db_path,
            network,
            account_uuid,
            &run.run_id,
            pending_password,
            pending_salt_base64,
        )? {
            let broadcast = broadcast_pending_denomination_stages(
                db_path,
                lightwalletd_url,
                network,
                &run.run_id,
                pending_password,
                pending_salt_base64,
            )
            .await?
            .ok_or("Finalized denomination stage was not pending broadcast")?;
            return Ok(StagedDenominationAdvance::Waiting(
                migration_result_from_split_broadcast(
                    broadcast,
                    fallback_total_count,
                    split_fee_zatoshi,
                    fallback_migrated_zatoshi,
                ),
            ));
        }
        return Ok(StagedDenominationAdvance::Waiting(
            prepared_notes_not_spendable_result(fallback_total_count, fallback_migrated_zatoshi),
        ));
    }

    if super::migration::reconcile_denomination_run(db_path, &run.run_id)? {
        return Ok(StagedDenominationAdvance::Ready);
    }
    Ok(StagedDenominationAdvance::Waiting(
        prepared_notes_not_spendable_result(fallback_total_count, fallback_migrated_zatoshi),
    ))
}

fn run_may_finalize_presigned_migration_children(run: &super::migration::ActiveRun) -> bool {
    matches!(
        run.phase.as_str(),
        super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS
            | super::migration::PHASE_READY_TO_MIGRATE
    )
}

fn derive_migration_usk(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
) -> Result<UnifiedSpendingKey, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let zip32_index = account
        .source()
        .key_derivation()
        .ok_or("No key derivation")?
        .account_index();
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
        .map_err(|e| format!("USK derivation failed: {e:?}"))?;
    let derived_account_id = db
        .get_account_for_ufvk(&usk.to_unified_full_viewing_key())
        .map_err(|e| format!("{e}"))?
        .ok_or("Spending key not recognized")?
        .id();
    if derived_account_id != account_id {
        return Err("Spending key does not match migration account".to_string());
    }
    drop(seed);

    Ok(usk)
}

// Keep software migration signing in synchronous preparation scopes. These
// helpers return only signed PCZT or raw transaction artifacts, so callers can
// perform network broadcast after seed and USK values have been dropped.
fn prepare_software_migration_run(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
) -> Result<Option<PreparedSoftwareMigrationRun>, String> {
    let usk = derive_migration_usk(db_path, network, account_uuid, seed)?;
    let Some(mut split) = create_padded_orchard_denomination_pczts(db_path, network, account_uuid)?
    else {
        return Ok(None);
    };

    let mut split_sigs = HashMap::with_capacity(split.stages.len());
    for stage in &mut split.stages {
        let signed_pczt = sign_orchard_migration_pczt_with_usk(
            &stage.base_pczt,
            &stage.orchard_spend_action_indices,
            &usk,
        )?;
        let sigs = super::pczt::extract_required_compact_sigs_from_signed_pczt(
            &stage.base_pczt,
            &signed_pczt,
        )?;
        super::pczt::preflight_orchard_spend_auth_signatures(&stage.base_pczt, &sigs)?;
        if !stage.deferred {
            stage.pczt_with_proofs = Some(super::pczt::add_proofs_to_pczt(
                &stage.base_pczt,
                None,
                None,
            )?);
        }
        split_sigs.insert(stage.id.clone(), sigs);
    }
    let prepared_refs = prepared_refs_from_denomination_stages(&split.stages);
    let denomination_stages = signed_denomination_stage_inserts(&split.stages, &split_sigs)?;

    let child_messages = split
        .predicted_notes
        .iter()
        .enumerate()
        .map(|(index, predicted)| {
            create_orchard_to_ironwood_pczt_from_predicted_note(
                db_path,
                network,
                account_uuid,
                predicted,
                (index + 1) as u32,
            )?
            .ok_or("Predicted migration note is below the migration fee threshold".to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;
    let signed_children = child_messages
        .iter()
        .enumerate()
        .map(|(index, child)| {
            let signed_pczt = sign_orchard_migration_pczt_with_usk(
                &child.base_pczt,
                &child.orchard_spend_action_indices,
                &usk,
            )?;
            // Persist only the produced signatures, matching the hardware
            // "signatures-only" path's compact storage form rather than the
            // full signed PCZT.
            let sigs = super::pczt::extract_required_compact_sigs_from_signed_pczt(
                &child.base_pczt,
                &signed_pczt,
            )?;
            super::pczt::preflight_orchard_spend_auth_signatures(&child.base_pczt, &sigs)?;
            let mut selected_note = child.selected_note.clone();
            selected_note.nullifier_hex = None;
            Ok(super::migration::SignedMigrationPcztInsert {
                message_id: child.id.clone(),
                child_index: index as u32,
                base_pczt: child.base_pczt.clone(),
                sigs,
                target_height: child.target_height,
                anchor_boundary_height: child.anchor_boundary_height,
                expiry_height: child.expiry_height,
                value_zatoshi: child.migrated_zatoshi,
                fee_zatoshi: child.fee_zatoshi,
                selected_note: selected_note.clone(),
                metadata: super::migration::PendingMigrationTxMetadata {
                    tx_kind: "migration".to_string(),
                    funding_account_uuid: account_uuid.to_string(),
                    selected_note,
                },
            })
        })
        .collect::<Result<Vec<_>, String>>()?;

    Ok(Some(PreparedSoftwareMigrationRun {
        plan: split.plan,
        prepared_refs,
        denomination_stages,
        signed_children,
        fee_zatoshi: split.stages.iter().try_fold(0u64, |total, stage| {
            total
                .checked_add(stage.fee_zatoshi)
                .ok_or("Denomination stage fee total overflow")
        })?,
        total_migratable_zatoshi: split.total_migratable_zatoshi,
    }))
}

struct PreparedSoftwareMigrationRun {
    plan: super::migration::DenominationPlan,
    prepared_refs: Vec<super::migration::PreparedOrchardNoteRef>,
    denomination_stages: Vec<super::migration::DenominationStageInsert>,
    signed_children: Vec<super::migration::SignedMigrationPcztInsert>,
    fee_zatoshi: u64,
    total_migratable_zatoshi: u64,
}

#[derive(Clone)]
struct PredictedMigrationNote {
    txid_hex: String,
    output_index: u32,
    value_zatoshi: u64,
    note: orchard::Note,
}

struct BuiltPczt {
    bytes: Vec<u8>,
    redacted_bytes: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KeystoneMigrationRequestState {
    Proofing,
    ProofReady,
    ProofFailed,
    Completing,
}

#[derive(Clone)]
struct CreatedDenominationStagePczt {
    id: String,
    base_pczt: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
    redacted_pczt: Vec<u8>,
    pczt_with_proofs: Option<Vec<u8>>,
    expected_txid_hex: String,
    target_height: u32,
    expiry_height: u32,
    fee_zatoshi: u64,
    deferred: bool,
    inputs: Vec<super::migration::DenominationStageInputRef>,
    outputs: Vec<super::migration::DenominationStageOutputRef>,
}

struct CreatedPaddedDenominationPczts {
    stages: Vec<CreatedDenominationStagePczt>,
    predicted_notes: Vec<PredictedMigrationNote>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

struct StoredDenominationPczt {
    account_uuid: String,
    network: WalletNetwork,
    state: KeystoneMigrationRequestState,
    proof_error: Option<String>,
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

struct StoredDenominationCompletion {
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

#[derive(Clone)]
struct CreatedMigrationPczt {
    id: String,
    base_pczt: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
    pczt_with_proofs: Option<Vec<u8>>,
    redacted_pczt: Vec<u8>,
    target_height: u32,
    anchor_boundary_height: Option<u32>,
    expiry_height: u32,
    fee_zatoshi: u64,
    migrated_zatoshi: u64,
    selected_note: super::migration::PreparedOrchardNoteRef,
}

struct StoredMigrationPcztBatch {
    account_uuid: String,
    network: WalletNetwork,
    run_id: String,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
    recovery_old_txids: Vec<String>,
    state: KeystoneMigrationRequestState,
    proof_error: Option<String>,
    messages: Vec<CreatedMigrationPczt>,
}

struct StoredMigrationBatchCompletion {
    run_id: String,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
    recovery_old_txids: Vec<String>,
    messages: Vec<CreatedMigrationPczt>,
}

struct StoredSingleQrMigrationPczt {
    account_uuid: String,
    network: WalletNetwork,
    state: KeystoneMigrationRequestState,
    proof_error: Option<String>,
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
    child_messages: Vec<CreatedMigrationPczt>,
}

struct StoredSingleQrMigrationCompletion {
    split_stages: Vec<CreatedDenominationStagePczt>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
    child_messages: Vec<CreatedMigrationPczt>,
}

fn new_keystone_migration_request_id(label: &str) -> String {
    let nonce: u64 = OsRng.gen();
    format!("ironwood-migration-{label}-{nonce:016x}")
}

fn keystone_denomination_requests() -> &'static Mutex<HashMap<String, StoredDenominationPczt>> {
    KEYSTONE_DENOMINATION_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn keystone_migration_requests() -> &'static Mutex<HashMap<String, StoredMigrationPcztBatch>> {
    KEYSTONE_MIGRATION_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn keystone_single_qr_migration_requests(
) -> &'static Mutex<HashMap<String, StoredSingleQrMigrationPczt>> {
    KEYSTONE_SINGLE_QR_MIGRATION_REQUESTS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn prune_failed_denomination_requests(
    store: &mut HashMap<String, StoredDenominationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) {
    store.retain(|_, stored| {
        !(stored.account_uuid == account_uuid
            && stored.network == network
            && stored.state == KeystoneMigrationRequestState::ProofFailed)
    });
}

fn ensure_no_live_denomination_request(
    store: &mut HashMap<String, StoredDenominationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    prune_failed_denomination_requests(store, account_uuid, network);
    if store
        .values()
        .any(|stored| stored.account_uuid == account_uuid && stored.network == network)
    {
        return Err(
            "A Keystone denomination request is already in progress. Reject it before preparing a new one."
                .to_string(),
        );
    }
    Ok(())
}

fn prune_failed_single_qr_migration_requests(
    store: &mut HashMap<String, StoredSingleQrMigrationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) {
    store.retain(|_, stored| {
        !(stored.account_uuid == account_uuid
            && stored.network == network
            && stored.state == KeystoneMigrationRequestState::ProofFailed)
    });
}

fn ensure_no_live_single_qr_migration_request(
    store: &mut HashMap<String, StoredSingleQrMigrationPczt>,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    prune_failed_single_qr_migration_requests(store, account_uuid, network);
    if store
        .values()
        .any(|stored| stored.account_uuid == account_uuid && stored.network == network)
    {
        return Err(
            "A Keystone migration request is already in progress. Reject it before preparing a new one."
                .to_string(),
        );
    }
    Ok(())
}

fn prune_failed_migration_requests(
    store: &mut HashMap<String, StoredMigrationPcztBatch>,
    account_uuid: &str,
    network: WalletNetwork,
    run_id: &str,
) {
    store.retain(|_, stored| {
        !(stored.account_uuid == account_uuid
            && stored.network == network
            && stored.run_id == run_id
            && stored.state == KeystoneMigrationRequestState::ProofFailed)
    });
}

fn ensure_no_live_migration_request(
    store: &mut HashMap<String, StoredMigrationPcztBatch>,
    account_uuid: &str,
    network: WalletNetwork,
    run_id: &str,
) -> Result<(), String> {
    prune_failed_migration_requests(store, account_uuid, network, run_id);
    if store.values().any(|stored| {
        stored.account_uuid == account_uuid && stored.network == network && stored.run_id == run_id
    }) {
        return Err(
            "A Keystone migration request is already in progress. Reject it before preparing a new one."
                .to_string(),
        );
    }
    Ok(())
}

fn validate_keystone_migration_messages(
    messages: &[KeystoneMigrationMessage],
) -> Result<(), String> {
    if messages.is_empty() {
        return Err("Keystone migration request has no messages".to_string());
    }
    let mut ids = HashSet::with_capacity(messages.len());
    let mut payloads = HashSet::with_capacity(messages.len());
    for message in messages {
        if message.id.is_empty() {
            return Err("Keystone migration message id is empty".to_string());
        }
        if message.redacted_pczt.is_empty() {
            return Err(format!(
                "Keystone migration message {} has an empty PCZT payload",
                message.id
            ));
        }
        if !ids.insert(message.id.as_bytes().to_vec()) {
            return Err(format!(
                "Duplicate Keystone migration message id {}",
                message.id
            ));
        }
        if !payloads.insert(message.redacted_pczt.clone()) {
            return Err("Duplicate Keystone migration PCZT payload".to_string());
        }
    }
    Ok(())
}

pub(crate) fn keystone_migration_proof_status(
    request_id: &str,
) -> Result<KeystoneMigrationProofStatus, String> {
    if let Some(status) = keystone_single_qr_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?
        .get(request_id)
        .map(|stored| {
            let roots = stored
                .split_stages
                .iter()
                .filter(|stage| !stage.deferred)
                .collect::<Vec<_>>();
            proof_status_from_counts(
                roots
                    .iter()
                    .filter(|stage| stage.pczt_with_proofs.is_some())
                    .count(),
                roots.len(),
                stored.state,
                stored.proof_error.clone(),
            )
        })
    {
        return Ok(status);
    }

    if let Some(status) = keystone_denomination_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?
        .get(request_id)
        .map(|stored| {
            let roots = stored
                .split_stages
                .iter()
                .filter(|stage| !stage.deferred)
                .collect::<Vec<_>>();
            proof_status_from_counts(
                roots
                    .iter()
                    .filter(|stage| stage.pczt_with_proofs.is_some())
                    .count(),
                roots.len(),
                stored.state,
                stored.proof_error.clone(),
            )
        })
    {
        return Ok(status);
    }

    keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?
        .get(request_id)
        .map(|stored| {
            let ready_count = stored
                .messages
                .iter()
                .filter(|message| message.pczt_with_proofs.is_some())
                .count();
            proof_status_from_counts(
                ready_count,
                stored.messages.len(),
                stored.state,
                stored.proof_error.clone(),
            )
        })
        .ok_or_else(|| format!("Keystone migration request {request_id} was not found"))
}

pub(crate) fn discard_keystone_migration_request(request_id: &str) -> Result<(), String> {
    {
        let mut store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        if store
            .get(request_id)
            .is_some_and(|stored| stored.state == KeystoneMigrationRequestState::Completing)
        {
            return Ok(());
        }
        if store.remove(request_id).is_some() {
            return Ok(());
        }
    }

    {
        let mut store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        if store
            .get(request_id)
            .is_some_and(|stored| stored.state == KeystoneMigrationRequestState::Completing)
        {
            return Ok(());
        }
        if store.remove(request_id).is_some() {
            return Ok(());
        }
    }

    let mut store = keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
    if store
        .get(request_id)
        .is_some_and(|stored| stored.state == KeystoneMigrationRequestState::Completing)
    {
        return Ok(());
    }
    store.remove(request_id);
    Ok(())
}

fn proof_status_from_counts(
    ready_count: usize,
    total_count: usize,
    state: KeystoneMigrationRequestState,
    message: Option<String>,
) -> KeystoneMigrationProofStatus {
    KeystoneMigrationProofStatus {
        ready_count: ready_count as u32,
        total_count: total_count as u32,
        is_ready: state == KeystoneMigrationRequestState::ProofReady,
        is_failed: state == KeystoneMigrationRequestState::ProofFailed,
        message,
    }
}

fn spawn_denomination_proof_worker(request_id: String, roots: Vec<(String, Vec<u8>)>) {
    let builder = thread::Builder::new().name("keystone-denomination-proof".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let total = roots.len();
        let started = Instant::now();
        log::info!("migration proofs: denomination started for {total} split roots");
        for (index, (id, base_pczt)) in roots.into_iter().enumerate() {
            let proof_started = Instant::now();
            let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
            let mut store = match keystone_denomination_requests().lock() {
                Ok(store) => store,
                Err(e) => {
                    log::error!("migration proofs: denomination store lock failed: {e}");
                    return;
                }
            };
            let Some(stored) = store.get_mut(&worker_request_id) else {
                log::info!("migration proofs: denomination request was discarded");
                return;
            };
            if stored.state == KeystoneMigrationRequestState::Completing {
                return;
            }
            match result {
                Ok(pczt_with_proofs) => {
                    let Some(stage) = stored.split_stages.iter_mut().find(|stage| stage.id == id)
                    else {
                        stored.proof_error = Some(format!("Missing split root {id}"));
                        stored.state = KeystoneMigrationRequestState::ProofFailed;
                        return;
                    };
                    stage.pczt_with_proofs = Some(pczt_with_proofs);
                    log::info!(
                        "migration proofs: denomination root {}/{} ready in {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                }
                Err(e) => {
                    stored.proof_error = Some(e);
                    stored.state = KeystoneMigrationRequestState::ProofFailed;
                    log::warn!(
                        "migration proofs: denomination root {}/{} failed after {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                    return;
                }
            }
        }

        let mut store = match keystone_denomination_requests().lock() {
            Ok(store) => store,
            Err(e) => {
                log::error!("migration proofs: denomination store lock failed: {e}");
                return;
            }
        };
        if let Some(stored) = store.get_mut(&worker_request_id) {
            if stored.state != KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: all denomination roots ready in {}ms",
                    started.elapsed().as_millis()
                );
            }
        }
    }) {
        log::error!("migration proofs: failed to start denomination proof worker: {e}");
        if let Ok(mut store) = keystone_denomination_requests().lock() {
            if let Some(stored) = store.get_mut(&request_id) {
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                stored.proof_error = Some(format!("Start proof worker: {e}"));
            }
        }
    }
}

fn spawn_single_qr_split_proof_worker(request_id: String, roots: Vec<(String, Vec<u8>)>) {
    let builder = thread::Builder::new().name("keystone-single-qr-split-proof".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let total = roots.len();
        let started = Instant::now();
        log::info!("migration proofs: single QR started for {total} split roots");
        for (index, (id, base_pczt)) in roots.into_iter().enumerate() {
            let proof_started = Instant::now();
            let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
            let mut store = match keystone_single_qr_migration_requests().lock() {
                Ok(store) => store,
                Err(e) => {
                    log::error!("migration proofs: single QR store lock failed: {e}");
                    return;
                }
            };
            let Some(stored) = store.get_mut(&worker_request_id) else {
                log::info!("migration proofs: single QR request was discarded");
                return;
            };
            if stored.state == KeystoneMigrationRequestState::Completing {
                return;
            }
            match result {
                Ok(pczt_with_proofs) => {
                    let Some(stage) = stored.split_stages.iter_mut().find(|stage| stage.id == id)
                    else {
                        stored.proof_error = Some(format!("Missing split root {id}"));
                        stored.state = KeystoneMigrationRequestState::ProofFailed;
                        return;
                    };
                    stage.pczt_with_proofs = Some(pczt_with_proofs);
                    log::info!(
                        "migration proofs: split root {}/{} ready in {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                }
                Err(e) => {
                    stored.proof_error = Some(e);
                    stored.state = KeystoneMigrationRequestState::ProofFailed;
                    log::warn!(
                        "migration proofs: split root {}/{} failed after {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                    return;
                }
            }
        }

        let mut store = match keystone_single_qr_migration_requests().lock() {
            Ok(store) => store,
            Err(e) => {
                log::error!("migration proofs: single QR store lock failed: {e}");
                return;
            }
        };
        if let Some(stored) = store.get_mut(&worker_request_id) {
            if stored.state != KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: all split roots ready in {}ms",
                    started.elapsed().as_millis()
                );
            }
        }
    }) {
        log::error!("migration proofs: failed to start single QR split proof worker: {e}");
        if let Ok(mut store) = keystone_single_qr_migration_requests().lock() {
            if let Some(stored) = store.get_mut(&request_id) {
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                stored.proof_error = Some(format!("Start proof worker: {e}"));
            }
        }
    }
}

fn spawn_migration_proof_worker(request_id: String, messages: Vec<(String, Vec<u8>)>) {
    let builder = thread::Builder::new().name("keystone-migration-proofs".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let total = messages.len();
        let started = Instant::now();
        log::info!("migration proofs: batch proof worker started for {total} messages");

        for (index, (id, base_pczt)) in messages.into_iter().enumerate() {
            {
                let store = match keystone_migration_requests().lock() {
                    Ok(store) => store,
                    Err(e) => {
                        log::error!("migration proofs: migration store lock failed: {e}");
                        return;
                    }
                };
                if !store.contains_key(&worker_request_id) {
                    log::info!("migration proofs: migration request was discarded");
                    return;
                }
            }

            let proof_started = Instant::now();
            let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
            let mut store = match keystone_migration_requests().lock() {
                Ok(store) => store,
                Err(e) => {
                    log::error!("migration proofs: migration store lock failed: {e}");
                    return;
                }
            };
            let Some(stored) = store.get_mut(&worker_request_id) else {
                return;
            };
            if stored.state == KeystoneMigrationRequestState::Completing {
                return;
            }
            match result {
                Ok(pczt_with_proofs) => {
                    if let Some(message) = stored.messages.iter_mut().find(|m| m.id == id) {
                        message.pczt_with_proofs = Some(pczt_with_proofs);
                    }
                    log::info!(
                        "migration proofs: batch message {}/{} ready in {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                }
                Err(e) => {
                    stored.state = KeystoneMigrationRequestState::ProofFailed;
                    stored.proof_error = Some(e);
                    log::warn!(
                        "migration proofs: batch message {}/{} failed after {}ms",
                        index + 1,
                        total,
                        proof_started.elapsed().as_millis()
                    );
                    return;
                }
            }
        }

        let mut store = match keystone_migration_requests().lock() {
            Ok(store) => store,
            Err(e) => {
                log::error!("migration proofs: migration store lock failed: {e}");
                return;
            }
        };
        if let Some(stored) = store.get_mut(&worker_request_id) {
            if stored.state != KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: batch proofs ready in {}ms",
                    started.elapsed().as_millis()
                );
            }
        }
    }) {
        log::error!("migration proofs: failed to start batch proof worker: {e}");
        if let Ok(mut store) = keystone_migration_requests().lock() {
            if let Some(stored) = store.get_mut(&request_id) {
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                stored.proof_error = Some(format!("Start proof worker: {e}"));
            }
        }
    }
}

fn reset_migration_request_after_failed_completion(request_id: &str) {
    if let Ok(mut store) = keystone_migration_requests().lock() {
        if let Some(stored) = store.get_mut(request_id) {
            if stored.state == KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
            }
        }
    }
}

fn reset_denomination_request_after_failed_completion(request_id: &str) {
    if let Ok(mut store) = keystone_denomination_requests().lock() {
        if let Some(stored) = store.get_mut(request_id) {
            if stored.state == KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
            }
        }
    }
}

fn reset_single_qr_request_after_failed_completion(request_id: &str) {
    if let Ok(mut store) = keystone_single_qr_migration_requests().lock() {
        if let Some(stored) = store.get_mut(request_id) {
            if stored.state == KeystoneMigrationRequestState::Completing {
                stored.state = KeystoneMigrationRequestState::ProofReady;
            }
        }
    }
}

fn signed_migration_messages_by_id(
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
) -> Result<HashMap<String, Vec<pczt::roles::signer::SpendAuthSignature>>, String> {
    if signed_messages.is_empty() {
        return Err(format!(
            "Keystone returned no signed messages for request {request_id}"
        ));
    }

    let mut by_id = HashMap::with_capacity(signed_messages.len());
    for message in signed_messages {
        if message.id.is_empty() {
            return Err("Keystone signed message id is empty".to_string());
        }
        if message.sigs.is_empty() {
            return Err(format!(
                "Keystone signed message {} carried no signatures",
                message.id
            ));
        }
        if by_id.insert(message.id.clone(), message.sigs).is_some() {
            return Err(format!("Duplicate signed Keystone message {}", message.id));
        }
    }

    Ok(by_id)
}

fn prepared_refs_from_denomination_stages(
    stages: &[CreatedDenominationStagePczt],
) -> Vec<super::migration::PreparedOrchardNoteRef> {
    stages
        .iter()
        .flat_map(|stage| {
            stage
                .outputs
                .iter()
                .filter(|output| {
                    output.kind == super::migration::DenominationStageOutputKind::Migration
                })
                .map(|output| super::migration::PreparedOrchardNoteRef {
                    txid_hex: stage.expected_txid_hex.clone(),
                    output_index: output.output_index,
                    value_zatoshi: output.value_zatoshi,
                    note_version: output.note_version,
                    nullifier_hex: None,
                })
        })
        .collect()
}

fn signed_denomination_stage_inserts(
    stages: &[CreatedDenominationStagePczt],
    signed_by_id: &HashMap<String, Vec<pczt::roles::signer::SpendAuthSignature>>,
) -> Result<Vec<super::migration::DenominationStageInsert>, String> {
    stages
        .iter()
        .enumerate()
        .map(|(stage_index, stage)| {
            let sigs = signed_by_id
                .get(&stage.id)
                .ok_or_else(|| format!("Keystone result missing {}", stage.id))?
                .clone();
            super::pczt::preflight_orchard_spend_auth_signatures(&stage.base_pczt, &sigs)?;
            let raw_tx = if stage.deferred {
                None
            } else {
                let proofed = stage
                    .pczt_with_proofs
                    .as_ref()
                    .ok_or("Keystone denomination root proofs are not ready")?;
                let extracted = super::pczt::apply_sigs_and_extract(proofed, &sigs, None, None)?;
                if extracted.txid.to_string() != stage.expected_txid_hex {
                    return Err(format!(
                        "Denomination root {} extracted an unexpected txid",
                        stage.id
                    ));
                }
                Some(extracted.raw_tx)
            };
            Ok(super::migration::DenominationStageInsert {
                stage_index: u32::try_from(stage_index)
                    .map_err(|_| "Denomination stage index overflow".to_string())?,
                base_pczt: stage.base_pczt.clone(),
                sigs,
                raw_tx,
                expected_txid_hex: stage.expected_txid_hex.clone(),
                target_height: stage.target_height,
                expiry_height: stage.expiry_height,
                fee_zatoshi: stage.fee_zatoshi,
                status: if stage.deferred {
                    super::migration::DenominationStageStatus::AwaitingInputs
                } else {
                    super::migration::DenominationStageStatus::Pending
                },
                inputs: stage.inputs.clone(),
                outputs: stage.outputs.clone(),
            })
        })
        .collect()
}

fn pczt_from_build_result(
    build_result: zcash_primitives::transaction::builder::PcztResult<WalletNetwork>,
    network: WalletNetwork,
    account_derivation: Option<&zcash_client_backend::data_api::Zip32Derivation>,
    orchard_spend_count: usize,
    orchard_change_output_count: usize,
) -> Result<BuiltPczt, String> {
    use pczt::roles::{creator::Creator, io_finalizer::IoFinalizer, updater::Updater};

    let orchard_spend_action_indices = (0..orchard_spend_count)
        .map(|i| {
            build_result
                .orchard_meta
                .spend_action_index(i)
                .ok_or_else(|| "Orchard spend action index missing".to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;
    let mut orchard_derivation_action_indices =
        Vec::with_capacity(orchard_spend_count + orchard_change_output_count);
    orchard_derivation_action_indices.extend(orchard_spend_action_indices.iter().copied());
    for i in 0..orchard_change_output_count {
        let index = build_result
            .orchard_meta
            .output_action_index(i)
            .ok_or_else(|| "Orchard change output action index missing".to_string())?;
        if !orchard_derivation_action_indices.contains(&index) {
            orchard_derivation_action_indices.push(index);
        }
    }
    let orchard_derivation_actions = orchard_derivation_action_indices
        .iter()
        .copied()
        .collect::<HashSet<_>>();
    let created = Creator::build_from_parts(build_result.pczt_parts).ok_or("Build PCZT failed")?;
    let io_finalized = IoFinalizer::new(created)
        .finalize_io()
        .map_err(|e| format!("Finalize PCZT IO: {e:?}"))?;

    let pczt = Updater::new(io_finalized)
        .update_orchard_with(|mut updater| {
            if let Some(derivation) = account_derivation {
                for index in &orchard_derivation_actions {
                    updater.update_action_with(*index, |mut action_updater| {
                        action_updater.set_spend_zip32_derivation(
                            orchard::pczt::Zip32Derivation::parse(
                                derivation.seed_fingerprint().to_bytes(),
                                vec![
                                    zip32::ChildIndex::hardened(32).index(),
                                    zip32::ChildIndex::hardened(network.network_type().coin_type())
                                        .index(),
                                    zip32::ChildIndex::hardened(u32::from(
                                        derivation.account_index(),
                                    ))
                                    .index(),
                                ],
                            )
                            .expect("valid ZIP32 derivation"),
                        );
                        Ok(())
                    })?;
                }
            }
            Ok(())
        })
        .map_err(|e| format!("Update Orchard PCZT derivations: {e:?}"))?
        .finish();

    let bytes = pczt
        .serialize()
        .map_err(|e| format!("Serialize built PCZT: {e:?}"))?;
    let redacted_bytes = super::pczt::redact_pczt_for_batch_signer(&bytes)?;

    Ok(BuiltPczt {
        bytes,
        redacted_bytes,
        // Post-NU6.3 Orchard change outputs are paired with wallet-controlled
        // zero-valued spends. They are not IO-finalizer dummies, so software
        // signing must authorize their actions along with the requested input
        // spends. This union is also the set that receives derivation metadata
        // for hardware signing above.
        orchard_spend_action_indices: orchard_derivation_action_indices,
    })
}

fn predicted_note_from_split_action(
    action: &orchard::pczt::Action,
    value_zatoshi: u64,
) -> Result<orchard::Note, String> {
    let recipient = action
        .output()
        .recipient()
        .as_ref()
        .copied()
        .ok_or("Denomination split output recipient missing")?;
    let rseed = action
        .output()
        .rseed()
        .as_ref()
        .copied()
        .ok_or("Denomination split output rseed missing")?;
    let rho = orchard::note::Rho::from_bytes(&action.spend().nullifier().to_bytes())
        .into_option()
        .ok_or("Denomination split output rho is invalid")?;
    orchard::Note::from_parts(
        recipient,
        orchard::value::NoteValue::from_raw(value_zatoshi),
        rho,
        rseed,
        orchard::note::NoteVersion::V2,
    )
    .into_option()
    .ok_or("Denomination split output note is invalid".to_string())
}

fn synthetic_orchard_anchor_and_witnesses(
    notes: &[orchard::Note],
) -> Result<(orchard::Anchor, Vec<orchard::tree::MerklePath>), String> {
    use incrementalmerkletree::{frontier::CommitmentTree, witness::IncrementalWitness};

    if notes.is_empty() {
        return Err("Synthetic Orchard witness set is empty".to_string());
    }
    let mut tree = CommitmentTree::<orchard::tree::MerkleHashOrchard, 32>::empty();
    let mut witnesses = Vec::<IncrementalWitness<orchard::tree::MerkleHashOrchard, 32>>::new();
    for note in notes {
        let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
        let leaf = orchard::tree::MerkleHashOrchard::from_cmx(&cmx);
        for witness in &mut witnesses {
            witness
                .append(leaf)
                .map_err(|_| "Extend synthetic Orchard witness failed".to_string())?;
        }
        tree.append(leaf)
            .map_err(|_| "Append synthetic Orchard commitment failed".to_string())?;
        witnesses.push(
            IncrementalWitness::from_tree(tree.clone())
                .ok_or("Create synthetic Orchard witness failed")?,
        );
    }
    let anchor = witnesses
        .first()
        .ok_or("Synthetic Orchard witness set is empty")?
        .root()
        .into();
    let paths = witnesses
        .into_iter()
        .map(|witness| {
            witness
                .path()
                .map(Into::into)
                .ok_or_else(|| "Complete synthetic Orchard witness failed".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok((anchor, paths))
}

fn create_padded_orchard_denomination_pczts(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<CreatedPaddedDenominationPczts>, String> {
    let mut db = open_wallet_db(db_path, network)?;
    let fee_rule = ConservativeZip317FeeRule;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let ufvk = account.ufvk().ok_or("Account cannot create PCZTs")?;
    let account_derivation = account.source().key_derivation();
    let orchard_fvk = ufvk
        .orchard()
        .cloned()
        .ok_or("Orchard viewing key not available")?;
    let recipient_scope = orchard::keys::Scope::Internal;
    let recipient = orchard_fvk.address_at(0u32, recipient_scope);
    let internal_ovk = Some(orchard_fvk.to_ovk(recipient_scope));
    let memo = MemoBytes::empty();

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before preparing denominations")?;
    let mut orchard_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    orchard_notes.sort_by_key(|note| (format!("{}", note.txid()), note.output_index()));
    if orchard_notes.is_empty() {
        return Ok(None);
    }
    let (orchard_anchor, orchard_inputs) =
        orchard_witnesses(&mut db, anchor_height, &orchard_notes)?;
    let input_values = orchard_notes
        .iter()
        .map(|note| note.note_value().map(u64::from).map_err(|e| format!("{e}")))
        .collect::<Result<Vec<_>, String>>()?;
    let input_refs = orchard_notes
        .iter()
        .map(|received| super::migration::DenominationStageInputRef {
            txid_hex: format!("{}", received.txid()),
            output_index: received.output_index() as u32,
            value_zatoshi: u64::from(
                received
                    .note_value()
                    .expect("Orchard V2 input value was validated above"),
            ),
            note_version: 2,
            nullifier_hex: Some(hex::encode(
                received.note().nullifier(&orchard_fvk).to_bytes(),
            )),
        })
        .collect::<Vec<_>>();

    let migration_fee_estimate = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            MIGRATION_ORCHARD_ACTION_COUNT,
            MIGRATION_IRONWOOD_ACTION_COUNT,
        )
        .map_err(|e| format!("Failed to estimate migration fee: {e}"))?;
    let split_fee = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            super::migration::DENOMINATION_SPLIT_ACTIONS,
            0,
        )
        .map_err(|e| format!("Failed to estimate padded denomination fee: {e}"))?;
    let padded_plan = super::migration::plan_padded_denominations(
        &input_values,
        u64::from(split_fee),
        u64::from(migration_fee_estimate),
        MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI,
        super::migration::MIGRATION_MAX_PREPARED_NOTES_PER_RUN,
    )?
    .ok_or("Insufficient spendable Orchard funds for denomination split")?;

    let padded_bundle_type = orchard::builder::BundleType::Transactional {
        bundle_required: false,
        pad_to_minimum: Some(
            u8::try_from(super::migration::DENOMINATION_SPLIT_ACTIONS)
                .map_err(|_| "Padded denomination action count exceeds u8".to_string())?,
        ),
    };
    let mut stages = Vec::with_capacity(padded_plan.stages.len());
    let mut predicted_migration_notes =
        Vec::with_capacity(padded_plan.denominations.migration_outputs.len());
    let mut previous_continuation = None::<PredictedMigrationNote>;

    for (stage_index, stage_plan) in padded_plan.stages.iter().enumerate() {
        let mut stage_notes = Vec::new();
        let mut stage_input_refs = Vec::new();
        if stage_plan.spends_previous_continuation {
            let continuation = previous_continuation
                .take()
                .ok_or("Denomination stage is missing its continuation input")?;
            stage_input_refs.push(super::migration::DenominationStageInputRef {
                txid_hex: continuation.txid_hex.clone(),
                output_index: continuation.output_index,
                value_zatoshi: continuation.value_zatoshi,
                note_version: 2,
                nullifier_hex: Some(hex::encode(
                    continuation.note.nullifier(&orchard_fvk).to_bytes(),
                )),
            });
            stage_notes.push(continuation.note);
        } else if previous_continuation.is_some() {
            return Err("Independent denomination root left an unused continuation".to_string());
        }
        for input_index in &stage_plan.original_input_indices {
            let (note, _) = orchard_inputs
                .get(*input_index)
                .ok_or("Denomination stage input index is out of range")?;
            stage_notes.push(*note);
            stage_input_refs.push(
                input_refs
                    .get(*input_index)
                    .ok_or("Denomination stage input reference is out of range")?
                    .clone(),
            );
        }
        if stage_notes.is_empty() {
            return Err("Denomination stage has no Orchard inputs".to_string());
        }

        let deferred = stage_plan.spends_previous_continuation;
        let (stage_anchor, stage_inputs) = if deferred {
            let (anchor, witnesses) = synthetic_orchard_anchor_and_witnesses(&stage_notes)?;
            (
                anchor,
                stage_notes
                    .iter()
                    .copied()
                    .zip(witnesses.into_iter())
                    .collect::<Vec<_>>(),
            )
        } else {
            let inputs = stage_plan
                .original_input_indices
                .iter()
                .map(|index| {
                    orchard_inputs
                        .get(*index)
                        .cloned()
                        .ok_or("Denomination root input index is out of range")
                })
                .collect::<Result<Vec<_>, _>>()?;
            (orchard_anchor, inputs)
        };

        let mut output_values = stage_plan
            .terminal_outputs
            .iter()
            .map(|output| output.value_zatoshi)
            .collect::<Vec<_>>();
        if let Some(value) = stage_plan.continuation_value_zatoshi {
            output_values.push(value);
        }
        let builder = make_orchard_split_builder_with_type(
            network,
            target_height.into(),
            stage_anchor,
            &stage_inputs,
            &orchard_fvk,
            internal_ovk.clone(),
            recipient,
            &output_values,
            &memo,
            padded_bundle_type,
        )?;
        let exact_fee = builder
            .get_fee(&fee_rule)
            .map_err(|e| format!("Failed to verify padded denomination fee: {e}"))?;
        if exact_fee != split_fee || u64::from(exact_fee) != stage_plan.fee_zatoshi {
            return Err("Padded denomination stage fee changed after planning".to_string());
        }
        let build_result = builder
            .build_for_pczt(rand_core::OsRng, &fee_rule)
            .map_err(|e| format!("Build padded denomination PCZT failed: {e}"))?;
        let expiry_height = u32::from(build_result.pczt_parts.expiry_height);
        let orchard_bundle = build_result
            .pczt_parts
            .orchard
            .as_ref()
            .ok_or("Padded denomination PCZT missing Orchard bundle")?;
        if orchard_bundle.actions().len() != super::migration::DENOMINATION_SPLIT_ACTIONS {
            return Err(format!(
                "Padded denomination stage built {} actions instead of {}",
                orchard_bundle.actions().len(),
                super::migration::DENOMINATION_SPLIT_ACTIONS
            ));
        }

        let mut predicted_outputs = Vec::with_capacity(output_values.len());
        for (logical_output, value_zatoshi) in output_values.iter().enumerate() {
            let action_index = build_result
                .orchard_meta
                .output_action_index(logical_output)
                .ok_or("Padded denomination output action index missing")?;
            let action = orchard_bundle
                .actions()
                .get(action_index)
                .ok_or("Padded denomination output action missing")?;
            predicted_outputs.push((
                action_index as u32,
                *value_zatoshi,
                predicted_note_from_split_action(action, *value_zatoshi)?,
            ));
        }

        let built_pczt = pczt_from_build_result(
            build_result,
            network,
            account_derivation,
            stage_inputs.len(),
            output_values.len(),
        )?;
        let expected_txid = super::pczt::txid_from_io_finalized_pczt(&built_pczt.bytes)?;
        let expected_txid_hex = expected_txid.to_string();
        let mut stage_output_refs = Vec::with_capacity(predicted_outputs.len());
        for (terminal, (output_index, value_zatoshi, note)) in stage_plan
            .terminal_outputs
            .iter()
            .zip(predicted_outputs.iter())
        {
            let kind = match terminal.kind {
                super::migration::SplitTerminalKind::Migration => {
                    super::migration::DenominationStageOutputKind::Migration
                }
                super::migration::SplitTerminalKind::OrchardChange => {
                    super::migration::DenominationStageOutputKind::Change
                }
            };
            stage_output_refs.push(super::migration::DenominationStageOutputRef {
                output_index: *output_index,
                value_zatoshi: *value_zatoshi,
                note_version: 2,
                kind,
            });
            if terminal.kind == super::migration::SplitTerminalKind::Migration {
                predicted_migration_notes.push((
                    terminal.logical_index,
                    PredictedMigrationNote {
                        txid_hex: expected_txid_hex.clone(),
                        output_index: *output_index,
                        value_zatoshi: *value_zatoshi,
                        note: *note,
                    },
                ));
            }
        }
        if let Some(continuation_value) = stage_plan.continuation_value_zatoshi {
            let (output_index, value_zatoshi, note) = predicted_outputs
                .last()
                .ok_or("Denomination continuation output missing")?;
            if *value_zatoshi != continuation_value {
                return Err("Denomination continuation value changed after build".to_string());
            }
            stage_output_refs.push(super::migration::DenominationStageOutputRef {
                output_index: *output_index,
                value_zatoshi: *value_zatoshi,
                note_version: 2,
                kind: super::migration::DenominationStageOutputKind::Continuation,
            });
            previous_continuation = Some(PredictedMigrationNote {
                txid_hex: expected_txid_hex.clone(),
                output_index: *output_index,
                value_zatoshi: *value_zatoshi,
                note: *note,
            });
        }

        stages.push(CreatedDenominationStagePczt {
            id: if stage_index == 0 {
                "denominations".to_string()
            } else {
                format!("denominations-{}", stage_index + 1)
            },
            base_pczt: built_pczt.bytes,
            orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
            redacted_pczt: built_pczt.redacted_bytes,
            pczt_with_proofs: None,
            expected_txid_hex,
            target_height: target_height.into(),
            expiry_height,
            fee_zatoshi: u64::from(split_fee),
            deferred,
            inputs: stage_input_refs,
            outputs: stage_output_refs,
        });
    }
    if previous_continuation.is_some() {
        return Err("Denomination plan left an unspent continuation".to_string());
    }
    predicted_migration_notes.sort_by_key(|(logical_index, _)| *logical_index);
    let predicted_notes = predicted_migration_notes
        .into_iter()
        .map(|(_, note)| note)
        .collect::<Vec<_>>();
    if predicted_notes.len() != padded_plan.denominations.migration_outputs.len() {
        return Err("Padded denomination plan did not build every migration output".to_string());
    }

    Ok(Some(CreatedPaddedDenominationPczts {
        stages,
        predicted_notes,
        total_migratable_zatoshi: padded_plan.denominations.total_migratable_zatoshi,
        plan: padded_plan.denominations,
    }))
}

pub(crate) fn get_orchard_migration_private_plan(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<OrchardMigrationPrivatePlan>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let fee_rule = ConservativeZip317FeeRule;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let ufvk = account.ufvk().ok_or("Account cannot create PCZTs")?;
    let orchard_fvk = ufvk.orchard().ok_or("Orchard viewing key not available")?;

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before estimating migration plan")?;
    let mut orchard_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    orchard_notes.sort_by_key(|note| (format!("{}", note.txid()), note.output_index()));
    if orchard_notes.is_empty() {
        return Ok(None);
    }

    let input_values = orchard_notes
        .iter()
        .map(|note| note.note_value().map(u64::from).map_err(|e| format!("{e}")))
        .collect::<Result<Vec<_>, String>>()?;
    // Touch the FVK-derived nullifiers in the read-only estimate path so the
    // note-version/value assumptions match the mutating PCZT builder path.
    for received in &orchard_notes {
        let _ = received.note().nullifier(orchard_fvk);
    }

    let migration_fee_estimate = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            MIGRATION_ORCHARD_ACTION_COUNT,
            MIGRATION_IRONWOOD_ACTION_COUNT,
        )
        .map_err(|e| format!("Failed to estimate migration fee: {e}"))?;
    let split_fee = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            super::migration::DENOMINATION_SPLIT_ACTIONS,
            0,
        )
        .map_err(|e| format!("Failed to estimate padded denomination fee: {e}"))?;
    let padded_plan = super::migration::plan_padded_denominations(
        &input_values,
        u64::from(split_fee),
        u64::from(migration_fee_estimate),
        MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI,
        super::migration::MIGRATION_MAX_PREPARED_NOTES_PER_RUN,
    )?;
    let Some(padded_plan) = padded_plan else {
        return Ok(None);
    };

    let planned_batch_count = u32::try_from(padded_plan.denominations.migration_outputs.len())
        .map_err(|_| "Migration batch count exceeds u32".to_string())?;
    let denomination_split_stage_count = u32::try_from(padded_plan.stages.len())
        .map_err(|_| "Denomination split stage count exceeds u32".to_string())?;
    let migration_fee_zatoshi = u64::from(migration_fee_estimate)
        .checked_mul(u64::from(planned_batch_count))
        .ok_or("Migration fee estimate overflow")?;
    let estimated_total_fee_zatoshi = padded_plan
        .denominations
        .split_fee_zatoshi
        .checked_add(migration_fee_zatoshi)
        .ok_or("Migration total fee estimate overflow")?;
    let scheduled_transfers = super::migration::planned_transfer_schedule(
        padded_plan.denominations.migration_outputs.iter().copied(),
        network,
        &mut OsRng,
    );

    Ok(Some(OrchardMigrationPrivatePlan {
        target_values_zatoshi: padded_plan.denominations.migration_outputs,
        total_input_zatoshi: padded_plan.denominations.total_input_zatoshi,
        total_migratable_zatoshi: padded_plan.denominations.total_migratable_zatoshi,
        orchard_change_zatoshi: padded_plan.denominations.orchard_change,
        denomination_split_fee_zatoshi: padded_plan.denominations.split_fee_zatoshi,
        migration_fee_zatoshi,
        estimated_total_fee_zatoshi,
        planned_batch_count,
        denomination_split_stage_count,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        schedule_mean_delay_blocks: super::migration::schedule_parameters(network).0,
        schedule_max_delay_blocks: super::migration::schedule_parameters(network).1,
        max_prepared_notes_per_run: super::migration::MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        scheduled_transfers,
    }))
}

fn select_all_orchard_v2_notes(
    db: &WalletDatabase,
    account_id: AccountUuid,
    anchor_height: BlockHeight,
) -> Result<Vec<ReceivedNote<ReceivedNoteId, orchard::Note>>, String> {
    db.get_unspent_orchard_notes_at_historical_height(account_id, anchor_height)
        .map(|notes| {
            notes
                .into_iter()
                .filter(|note| note.note().version() == orchard::note::NoteVersion::V2)
                .collect()
        })
        .map_err(|e| format!("Failed to select Orchard notes: {e}"))
}

fn dummy_orchard_merkle_path() -> Result<orchard::tree::MerklePath, String> {
    let zero = Option::<orchard::tree::MerkleHashOrchard>::from(
        orchard::tree::MerkleHashOrchard::from_bytes(&[0; 32]),
    )
    .ok_or("Zero Orchard Merkle hash is invalid")?;
    Ok(orchard::tree::MerklePath::from_parts(0, [zero; 32]))
}

/// Builds a migration child with 2 Orchard actions and 1 Ironwood action.
pub(super) fn migration_child_builder<P: consensus::Parameters>(
    network: P,
    target_height: BlockHeight,
    orchard_anchor: orchard::Anchor,
) -> Result<Builder<P, ()>, String> {
    let target_height_u32: u32 = target_height.into();
    let expiry_height =
        super::migration::zip318_canonical_migration_expiry_height(target_height_u32)?;

    Ok(Builder::new(
        network,
        target_height,
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: Some(orchard_anchor),
            ironwood_anchor: Some(orchard::Anchor::empty_tree()),
            orchard_bundle_type: orchard::builder::BundleType::DEFAULT,
            ironwood_bundle_type: orchard::builder::BundleType::UNPADDED,
        },
    )
    .with_expiry_height(BlockHeight::from(expiry_height)))
}

fn create_orchard_to_ironwood_pczt_from_predicted_note(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    predicted: &PredictedMigrationNote,
    migration_index: u32,
) -> Result<Option<CreatedMigrationPczt>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let ufvk = account.ufvk().ok_or("Account cannot create PCZTs")?;
    let account_derivation = account.source().key_derivation();
    let orchard_fvk = ufvk
        .orchard()
        .cloned()
        .ok_or("Orchard viewing key not available")?;
    let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);
    let internal_ovk = Some(orchard_fvk.to_ovk(orchard::keys::Scope::Internal));
    let memo = MemoBytes::empty();
    let (target_height, _) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read target height: {e}"))?
        .ok_or("Wallet must sync before preparing migration")?;
    let selected_value: Zatoshis = predicted
        .value_zatoshi
        .try_into()
        .map_err(|e| format!("Predicted migration note value invalid: {e}"))?;
    // Migration children are built from predicted denomination notes before the
    // split tx is mined. This dummy anchor is v6-only scaffolding. Orchard
    // spend signatures do not commit to it, and finalization replaces it with
    // the real anchor/witness before creating proofs.
    let dummy_witness = dummy_orchard_merkle_path()?;
    let dummy_anchor = {
        let cmx: orchard::note::ExtractedNoteCommitment = predicted.note.commitment().into();
        dummy_witness.root(cmx)
    };
    let fee_rule = ConservativeZip317FeeRule;
    let make_builder = |ironwood_amount: Zatoshis| {
        let mut builder =
            migration_child_builder(network, BlockHeight::from(target_height), dummy_anchor)?;

        builder
            .add_orchard_spend::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                orchard_fvk.clone(),
                predicted.note,
                dummy_witness.clone(),
            )
            .map_err(|e| format!("Add predicted Orchard migration spend failed: {e}"))?;
        builder
            .add_ironwood_output::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                internal_ovk.clone(),
                recipient,
                ironwood_amount,
                memo.clone(),
            )
            .map_err(|e| format!("Add predicted Ironwood migration output failed: {e}"))?;
        Ok::<_, String>(builder)
    };

    let builder_with_minimum_amount = make_builder(
        Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?,
    )?;
    let fee_amount = builder_with_minimum_amount
        .get_fee(&fee_rule)
        .map_err(|e| format!("Failed to estimate predicted migration fee: {e}"))?;
    if selected_value <= fee_amount {
        return Ok(None);
    }
    let migrated_amount: Zatoshis = (selected_value - fee_amount)
        .ok_or_else(|| "Predicted migration amount underflow".to_string())?;
    if !super::migration::is_zip318_canonical_denomination(u64::from(migrated_amount)) {
        return Err(
            "Predicted migration amount is not a ZIP 318 canonical denomination".to_string(),
        );
    }
    let builder = if migrated_amount
        == Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?
    {
        builder_with_minimum_amount
    } else {
        make_builder(migrated_amount)?
    };

    let build_result = builder
        .build_for_pczt(rand_core::OsRng, &fee_rule)
        .map_err(|e| format!("Build predicted migration PCZT failed: {e}"))?;
    let expiry_height = u32::from(build_result.pczt_parts.expiry_height);
    let built_pczt = pczt_from_build_result(build_result, network, account_derivation, 1, 0)?;
    let target_height_u32: u32 = target_height.into();

    Ok(Some(CreatedMigrationPczt {
        id: format!("migration-{migration_index}"),
        base_pczt: built_pczt.bytes,
        orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
        pczt_with_proofs: None,
        redacted_pczt: built_pczt.redacted_bytes,
        target_height: target_height_u32,
        anchor_boundary_height: None,
        expiry_height,
        fee_zatoshi: u64::from(fee_amount),
        migrated_zatoshi: u64::from(migrated_amount),
        selected_note: super::migration::PreparedOrchardNoteRef {
            txid_hex: predicted.txid_hex.clone(),
            output_index: predicted.output_index,
            value_zatoshi: predicted.value_zatoshi,
            note_version: 2,
            nullifier_hex: None,
        },
    }))
}

fn sign_orchard_migration_pczt_with_usk(
    pczt_bytes: &[u8],
    orchard_spend_action_indices: &[usize],
    usk: &UnifiedSpendingKey,
) -> Result<Vec<u8>, String> {
    use pczt::roles::signer::Signer;

    if orchard_spend_action_indices.is_empty() {
        return Err("Migration PCZT has no Orchard spend actions".to_string());
    }
    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse migration PCZT: {e:?}"))?;
    let orchard_ask = orchard::keys::SpendAuthorizingKey::from(usk.orchard());
    let mut signer =
        Signer::new(pczt).map_err(|e| format!("Create migration PCZT signer: {e:?}"))?;
    for index in orchard_spend_action_indices {
        signer
            .sign_orchard(*index, &orchard_ask)
            .map_err(|e| format!("Sign migration PCZT action {index}: {e:?}"))?;
    }
    signer
        .finish()
        .serialize()
        .map_err(|e| format!("Serialize signed migration PCZT: {e:?}"))
}

fn create_orchard_to_ironwood_pczt_from_note(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    note_ref: &super::migration::PreparedOrchardNoteRef,
    migration_index: u32,
    anchor_cohort_counts: &mut BTreeMap<u32, u32>,
    allow_replacing_local_spend: bool,
) -> Result<Option<CreatedMigrationPczt>, String> {
    if note_ref.note_version != 2 {
        return Err("Prepared migration note is not an Orchard V2 note".to_string());
    }

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let ufvk = account.ufvk().ok_or("Account cannot create PCZTs")?;
    let account_derivation = account.source().key_derivation();
    let orchard_fvk = ufvk
        .orchard()
        .cloned()
        .ok_or("Orchard viewing key not available")?;
    let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);
    let internal_ovk = Some(orchard_fvk.to_ovk(orchard::keys::Scope::Internal));
    let memo = MemoBytes::empty();

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before migrating denominations")?;

    let orchard_selected = if allow_replacing_local_spend {
        let available_notes =
            select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
        let Some(selected) = available_notes.iter().find(|selected| {
            format!("{}", selected.txid()).eq_ignore_ascii_case(&note_ref.txid_hex)
                && selected.output_index() as u32 == note_ref.output_index
        }) else {
            return Ok(None);
        };
        ReceivedNote::from_parts(
            *selected.internal_note_id(),
            *selected.txid(),
            selected.output_index(),
            *selected.note(),
            selected.spending_key_scope(),
            selected.note_commitment_tree_position(),
            selected.mined_height(),
            selected.max_shielding_input_height(),
        )
    } else {
        let txid = parse_txid_hex(&note_ref.txid_hex)?;
        let selected = db
            .get_spendable_note(
                &txid,
                ShieldedProtocol::Orchard,
                note_ref.output_index,
                target_height,
            )
            .map_err(|e| format!("Failed to revalidate prepared note: {e}"))?;
        let Some(selected) = selected else {
            return Ok(None);
        };
        let orchard_note = match selected.note() {
            Note::Orchard { note, .. } => *note,
            Note::Sapling(_) => return Err("Prepared note revalidated as Sapling".to_string()),
        };
        ReceivedNote::from_parts(
            *selected.internal_note_id(),
            *selected.txid(),
            selected.output_index(),
            orchard_note,
            selected.spending_key_scope(),
            selected.note_commitment_tree_position(),
            selected.mined_height(),
            selected.max_shielding_input_height(),
        )
    };
    let orchard_note = *orchard_selected.note();
    if orchard_note.version() != orchard::note::NoteVersion::V2 {
        return Err("Prepared note revalidated as non-V2 Orchard".to_string());
    }
    let selected_value: Zatoshis = orchard_note
        .value()
        .inner()
        .try_into()
        .map_err(|e| format!("Prepared note value invalid: {e}"))?;
    if u64::from(selected_value) != note_ref.value_zatoshi {
        return Err("Prepared note value changed during revalidation".to_string());
    }
    let target_height_u32: u32 = target_height.into();
    let anchor_height_u32 = u32::from(anchor_height);
    let nu6_3_activation_height = nu6_3_activation_height_u32(network)?;
    let mined_height = orchard_selected
        .mined_height()
        .ok_or("Prepared migration note mined height unavailable")?;
    let Some(anchor_boundary_height) =
        super::migration::zip318_draw_anchor_boundary_for_note_with_cohorts(
            network,
            anchor_height_u32,
            u32::from(mined_height),
            nu6_3_activation_height,
            anchor_cohort_counts,
        )
    else {
        return Ok(None);
    };
    *anchor_cohort_counts
        .entry(anchor_boundary_height)
        .or_default() += 1;

    let (orchard_anchor, orchard_inputs) = migration_orchard_witnesses(
        &mut db,
        network,
        BlockHeight::from(anchor_boundary_height),
        std::slice::from_ref(&orchard_selected),
    )?;
    let fee_rule = ConservativeZip317FeeRule;
    let make_builder = |ironwood_amount: Zatoshis| {
        let mut builder =
            migration_child_builder(network, BlockHeight::from(target_height), orchard_anchor)?;

        for (note, merkle_path) in orchard_inputs.iter() {
            builder
                .add_orchard_spend::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                    orchard_fvk.clone(),
                    *note,
                    merkle_path.clone(),
                )
                .map_err(|e| format!("Add migration Orchard spend failed: {e}"))?;
        }
        builder
            .add_ironwood_output::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                internal_ovk.clone(),
                recipient,
                ironwood_amount,
                memo.clone(),
            )
            .map_err(|e| format!("Add migration Ironwood output failed: {e}"))?;
        Ok::<_, String>(builder)
    };

    let builder_with_minimum_amount = make_builder(
        Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?,
    )?;
    let fee_amount = builder_with_minimum_amount
        .get_fee(&fee_rule)
        .map_err(|e| format!("Failed to estimate exact-note migration fee: {e}"))?;
    if selected_value <= fee_amount {
        return Ok(None);
    }
    let migrated_amount: Zatoshis = (selected_value - fee_amount)
        .ok_or_else(|| "Exact-note migration amount underflow".to_string())?;
    if !super::migration::is_zip318_canonical_denomination(u64::from(migrated_amount)) {
        return Err(
            "Exact-note migration amount is not a ZIP 318 canonical denomination".to_string(),
        );
    }
    let builder = if migrated_amount
        == Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?
    {
        builder_with_minimum_amount
    } else {
        make_builder(migrated_amount)?
    };

    let build_result = builder
        .build_for_pczt(rand_core::OsRng, &fee_rule)
        .map_err(|e| format!("Build exact-note migration PCZT failed: {e}"))?;
    let expiry_height = u32::from(build_result.pczt_parts.expiry_height);
    let built_pczt = pczt_from_build_result(
        build_result,
        network,
        account_derivation,
        orchard_inputs.len(),
        0,
    )?;
    Ok(Some(CreatedMigrationPczt {
        id: format!("migration-{migration_index}"),
        base_pczt: built_pczt.bytes,
        orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
        pczt_with_proofs: None,
        redacted_pczt: built_pczt.redacted_bytes,
        target_height: target_height_u32,
        anchor_boundary_height: Some(anchor_boundary_height),
        expiry_height,
        fee_zatoshi: u64::from(fee_amount),
        migrated_zatoshi: u64::from(migrated_amount),
        selected_note: note_ref.clone(),
    }))
}

fn parse_txid_hex(txid_hex: &str) -> Result<TxId, String> {
    let bytes = hex::decode(txid_hex).map_err(|e| format!("Bad migration txid hex: {e}"))?;
    let mut bytes: [u8; 32] = bytes
        .try_into()
        .map_err(|_| "Migration txid must be 32 bytes".to_string())?;
    bytes.reverse();
    Ok(TxId::from_bytes(bytes))
}

fn nu6_3_activation_height_u32(network: WalletNetwork) -> Result<u32, String> {
    network
        .activation_height(consensus::NetworkUpgrade::Nu6_3)
        .map(u32::from)
        .ok_or("NU6.3 activation height unavailable".to_string())
}

fn orchard_witnesses(
    db: &mut WalletDatabase,
    anchor_height: BlockHeight,
    orchard_notes: &[ReceivedNote<ReceivedNoteId, orchard::Note>],
) -> Result<
    (
        orchard::Anchor,
        Vec<(orchard::Note, orchard::tree::MerklePath)>,
    ),
    String,
> {
    type WitnessError = WalletError<
        (),
        commitment_tree::Error,
        (),
        <ConservativeZip317FeeRule as FeeRule>::Error,
        (),
        ReceivedNoteId,
    >;

    let result: Result<_, WitnessError> = db.with_orchard_tree_mut(|orchard_tree| {
        let anchor = orchard_tree
            .root_at_checkpoint_id(&anchor_height)?
            .ok_or(ProposalError::AnchorNotFound(anchor_height))?
            .into();

        let inputs = orchard_notes
            .iter()
            .map(|selected| {
                orchard_tree
                    .witness_at_checkpoint_id_caching(
                        selected.note_commitment_tree_position(),
                        &anchor_height,
                    )
                    .and_then(|witness| {
                        witness.ok_or(ShardTreeError::Query(QueryError::CheckpointPruned))
                    })
                    .map(|merkle_path| (*selected.note(), merkle_path.into()))
                    .map_err(WalletError::from)
            })
            .collect::<Result<Vec<_>, _>>()?;

        Ok((anchor, inputs))
    });
    result.map_err(|e| format!("Read Orchard witnesses: {e:?}"))
}

fn migration_orchard_witnesses(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    anchor_boundary_height: BlockHeight,
    orchard_notes: &[ReceivedNote<ReceivedNoteId, orchard::Note>],
) -> Result<
    (
        orchard::Anchor,
        Vec<(orchard::Note, orchard::tree::MerklePath)>,
    ),
    String,
> {
    if network != WalletNetwork::Regtest {
        return orchard_witnesses(db, anchor_boundary_height, orchard_notes);
    }

    let newest_note_height = orchard_notes
        .iter()
        .filter_map(|note| note.mined_height())
        .map(u32::from)
        .max()
        .ok_or("Prepared migration note mined height unavailable")?;
    let boundary = u32::from(anchor_boundary_height);
    let oldest_candidate = boundary
        .saturating_sub(super::migration::ZIP318_ANCHOR_AGE_CAP)
        .max(newest_note_height);
    let mut last_error = None;

    for checkpoint in (oldest_candidate..=boundary).rev() {
        match orchard_witnesses(db, BlockHeight::from(checkpoint), orchard_notes) {
            Ok(result) => return Ok(result),
            Err(error) if is_orchard_witness_not_ready_error(&error) => {
                last_error = Some(error);
            }
            Err(error) => return Err(error),
        }
    }

    Err(last_error.unwrap_or_else(|| {
        "Read Orchard witnesses: no regtest checkpoint at or before anchor boundary".to_string()
    }))
}

#[allow(clippy::too_many_arguments)]
fn make_orchard_split_builder_with_type(
    network: WalletNetwork,
    target_height: u32,
    orchard_anchor: orchard::Anchor,
    orchard_inputs: &[(orchard::Note, orchard::tree::MerklePath)],
    orchard_fvk: &orchard::keys::FullViewingKey,
    internal_ovk: Option<orchard::keys::OutgoingViewingKey>,
    recipient: orchard::Address,
    outputs: &[u64],
    memo: &MemoBytes,
    bundle_type: orchard::builder::BundleType,
) -> Result<Builder<WalletNetwork, ()>, String> {
    let mut builder = Builder::new(
        network,
        BlockHeight::from(target_height),
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: Some(orchard_anchor),
            ironwood_anchor: Some(orchard::Anchor::empty_tree()),
            // A denomination stage is an ordinary private Orchard-to-Orchard split;
            // keep it padded like regular sends.
            orchard_bundle_type: bundle_type,
            ironwood_bundle_type: orchard::builder::BundleType::DEFAULT,
        },
    )
    .with_expiry_height(BlockHeight::from(MIGRATION_NO_EXPIRY_HEIGHT));

    if network.is_nu_active(
        zcash_protocol::consensus::NetworkUpgrade::Nu6_3,
        BlockHeight::from(target_height),
    ) {
        builder
            .propose_version::<<ConservativeZip317FeeRule as FeeRule>::Error>(TxVersion::V6)
            .map_err(|e| format!("Use V6 for Orchard denomination split PCZT: {e:?}"))?;
    }

    for (note, merkle_path) in orchard_inputs {
        builder
            .add_orchard_spend::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                orchard_fvk.clone(),
                *note,
                merkle_path.clone(),
            )
            .map_err(|e| format!("Add Orchard denomination spend failed: {e}"))?;
    }

    for value in outputs {
        builder
            .add_orchard_change_output::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                orchard_fvk.clone(),
                internal_ovk.clone(),
                recipient,
                Zatoshis::from_u64(*value).map_err(|_| "Bad denomination output value")?,
                memo.clone(),
            )
            .map_err(|e| format!("Add Orchard denomination output failed: {e}"))?;
    }

    Ok(builder)
}

struct ActiveIronwoodMigration {
    key: String,
}

impl ActiveIronwoodMigration {
    fn acquire(db_path: &str, account_uuid: &str) -> Result<Self, String> {
        let key = format!("{db_path}:{account_uuid}");
        let mut active = active_ironwood_migrations()
            .lock()
            .map_err(|_| "Ironwood migration lock poisoned".to_string())?;

        if !active.insert(key.clone()) {
            log::warn!("migration finalizer: active migration guard already held");
            return Err("An Ironwood migration is already running for this account".to_string());
        }

        Ok(Self { key })
    }
}

impl Drop for ActiveIronwoodMigration {
    fn drop(&mut self) {
        if let Ok(mut active) = active_ironwood_migrations().lock() {
            active.remove(&self.key);
        }
    }
}

fn active_ironwood_migrations() -> &'static Mutex<HashSet<String>> {
    ACTIVE_IRONWOOD_MIGRATIONS.get_or_init(|| Mutex::new(HashSet::new()))
}

fn shielding_threshold() -> Result<Zatoshis, String> {
    Zatoshis::from_u64(SHIELDING_THRESHOLD_ZATOSHI)
        .map_err(|_| "Bad shielding threshold".to_string())
}

fn build_shielding_proposal(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    shielding_threshold: Zatoshis,
) -> Result<(Proposal<WalletFeeRule, Infallible>, Zatoshis), String> {
    let chain_height = db
        .chain_height()
        .map_err(|e| format!("Failed to read chain height: {e}"))?
        .ok_or("Wallet must sync before shielding transparent funds")?;
    let balances = db
        .get_transparent_balances(
            account_id,
            (chain_height + 1).into(),
            ConfirmationsPolicy::MIN,
        )
        .map_err(|e| format!("Failed to get transparent balances: {e}"))?;
    let (from_addrs, selected_value) = select_shielding_sources(balances, shielding_threshold)?;

    // Regular shielding transactions stay padded (`DEFAULT`); only migration
    // children opt in to unpadded Orchard-pool bundles.
    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None, None, false);
    let proposal = propose_shielding::<_, _, _, _, Infallible>(
        db,
        &network,
        &input_selector,
        &change_strategy,
        shielding_threshold,
        &from_addrs,
        account_id,
        ConfirmationsPolicy::MIN,
        CoinbaseFilter::AllTransparentOutputs,
    )
    .map_err(|e| format!("Shield proposal failed: {e}"))?;

    Ok((proposal, selected_value))
}

fn build_send_request(
    to_address: &str,
    amount_zatoshi: u64,
    memo_str: Option<&str>,
) -> Result<TransactionRequest, String> {
    let to: zcash_address::ZcashAddress = to_address
        .parse()
        .map_err(|e| format!("Bad address: {e}"))?;
    let value = Zatoshis::from_u64(amount_zatoshi).map_err(|_| "Bad amount")?;
    let memo_bytes = match memo_str {
        Some(m) => {
            let bytes = MemoBytes::from(
                Memo::from_bytes(m.as_bytes()).map_err(|e| format!("Bad memo: {e}"))?,
            );
            Some(bytes)
        }
        None => None,
    };

    let payment = Payment::new(to, Some(value), memo_bytes, None, None, vec![])
        .map_err(|e| format!("Cannot create payment: {e:?}"))?;
    TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))
}

fn propose_send_with_reserved_notes(
    db: &WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    request: TransactionRequest,
    reserved: &BTreeSet<ReceivedNoteId>,
    migration_locks: &BTreeSet<(String, u32)>,
    proposed_tx_version: Option<TxVersion>,
    unpadded_orchard_pool_bundles: bool,
) -> Result<Proposal<WalletFeeRule, ReceivedNoteId>, String> {
    let confirmations_policy = ConfirmationsPolicy::default();
    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(confirmations_policy.trusted())
        .map_err(|e| format!("Read chain state for proposal: {e}"))?
        .ok_or("Wallet must sync before creating a reserved batch")?;
    let reserved_db = ReservedInputSource {
        inner: db,
        reserved,
        migration_locks,
    };
    let (change_strategy, input_selector) = zip317_helper::<ReservedInputSource<'_>>(
        None,
        proposed_tx_version,
        unpadded_orchard_pool_bundles,
    );

    input_selector
        .propose_transaction(
            &network,
            &reserved_db,
            target_height,
            anchor_height,
            confirmations_policy,
            account_id,
            request,
            &change_strategy,
            // Reserved-note sends never fall back to transparent UTXOs
            // (the default policy permits shielded pools only).
            &SpendPolicy::default(),
            proposed_tx_version,
        )
        .map_err(|e| format!("Propose failed: {e}"))
}

fn proposal_selected_note_refs(
    proposal: &Proposal<WalletFeeRule, ReceivedNoteId>,
) -> impl Iterator<Item = ReceivedNoteId> + '_ {
    proposal
        .steps()
        .iter()
        .flat_map(|step| step.shielded_inputs().into_iter())
        .flat_map(|inputs| inputs.notes().iter())
        .map(|note| *note.internal_note_id())
}

#[derive(Default)]
struct SelectedOrchardNoteVersions {
    has_v2: bool,
    has_v3: bool,
}

fn proposal_selected_orchard_note_versions<NoteRef>(
    proposal: &Proposal<WalletFeeRule, NoteRef>,
) -> SelectedOrchardNoteVersions {
    let mut versions = SelectedOrchardNoteVersions::default();
    for note in proposal.steps().iter().flat_map(|step| {
        step.shielded_inputs()
            .into_iter()
            .flat_map(|inputs| inputs.notes().iter())
    }) {
        if let Note::Orchard { note, .. } = note.note() {
            match note.version() {
                orchard::note::NoteVersion::V2 => versions.has_v2 = true,
                orchard::note::NoteVersion::V3 => versions.has_v3 = true,
            }
        }
    }
    versions
}

/// Whether any proposal step pays a shielded-**Orchard** recipient.
///
/// Only *payment* outputs are considered: `payment_pools()` maps the request's
/// payment indices to their pool, and change is not represented there. This is
/// what makes the legacy-V5 downgrade safe — a legacy `orchard_v3` bundle at
/// NU6.3 has cross-address transfers disabled, so it can carry a self-address
/// Orchard *change* output but not an Orchard *payment* to another party;
/// building such a payment as V5 fails with `CrossAddressDisabled`. If this
/// returns true the send must stay V6.
fn proposal_has_orchard_payment<NoteRef>(proposal: &Proposal<WalletFeeRule, NoteRef>) -> bool {
    proposal.steps().iter().any(|step| {
        step.payment_pools()
            .values()
            .any(|pool| *pool == PoolType::Shielded(ShieldedProtocol::Orchard))
    })
}

/// Pass-2 decision for the ordinary send/estimate paths: a pass-1 V6 proposal
/// is downgraded to a legacy V5 transaction iff every selected Orchard note is
/// legacy (V2) — so the change note stays V2 — and no step pays a
/// shielded-Orchard recipient. V3-only and mixed V2+V3 selections keep V6 with
/// an Ironwood (V3) change note — splitting mixed change per spent-note version
/// is a deliberate future item — and pre-activation proposals (`initial` of
/// `None`) are never rewritten.
///
/// `has_orchard_payment` gates out sends whose recipient is a shielded-Orchard
/// address: the V5 proposal would build fine but fail at execution with
/// `CrossAddressDisabled`, and that failure is past the point
/// [`propose_with_note_version_downgrade`]'s re-proposal fallback can catch it,
/// so such sends must stay V6. Orchard *change* is unaffected (it is not a
/// payment pool), so an Orchard→transparent V2 send still downgrades.
fn should_downgrade_send_to_legacy_v5(
    initial: Option<TxVersion>,
    versions: &SelectedOrchardNoteVersions,
    has_orchard_payment: bool,
) -> bool {
    matches!(initial, Some(TxVersion::V6))
        && versions.has_v2
        && !versions.has_v3
        && !has_orchard_payment
}

/// Shared pass-2 of [`propose_send`] and [`estimate_fee`]: when
/// [`should_downgrade_send_to_legacy_v5`]
/// holds for the pass-1 proposal, re-propose as legacy V5 via `repropose` and
/// return that proposal with `Some(TxVersion::V5)`. Any re-proposal error keeps
/// the pass-1 (V6) proposal and version instead of failing the send;
/// `repropose` is a closure so tests can exercise that fallback directly.
///
/// (`estimate_send_max` deliberately does NOT funnel through here — see the
/// note there for why the quoted max stays at the V6 ceiling.)
///
/// Callers must build with the *returned* version (applied to the proposal
/// via `with_proposed_version` at PCZT/transaction construction) so the
/// built transaction matches the downgrade decision made here.
fn propose_with_note_version_downgrade<NoteRef, F>(
    pass1_proposal: Proposal<WalletFeeRule, NoteRef>,
    pass1_tx_version: Option<TxVersion>,
    repropose: F,
) -> (Proposal<WalletFeeRule, NoteRef>, Option<TxVersion>)
where
    F: FnOnce(Option<TxVersion>) -> Result<Proposal<WalletFeeRule, NoteRef>, String>,
{
    if !should_downgrade_send_to_legacy_v5(
        pass1_tx_version,
        &proposal_selected_orchard_note_versions(&pass1_proposal),
        proposal_has_orchard_payment(&pass1_proposal),
    ) {
        return (pass1_proposal, pass1_tx_version);
    }
    match repropose(Some(TxVersion::V5)) {
        Ok(proposal) => (proposal, Some(TxVersion::V5)),
        Err(e) => {
            log::warn!("Legacy-V5 re-proposal failed; keeping the pass-1 V6 proposal: {e}");
            (pass1_proposal, pass1_tx_version)
        }
    }
}

struct ReservedInputSource<'a> {
    inner: &'a WalletDatabase,
    reserved: &'a BTreeSet<ReceivedNoteId>,
    migration_locks: &'a BTreeSet<(String, u32)>,
}

impl ReservedInputSource<'_> {
    fn merged_excludes(&self, exclude: &[ReceivedNoteId]) -> Vec<ReceivedNoteId> {
        let mut merged = exclude.to_vec();
        merged.extend(self.reserved.iter().copied());
        merged.sort_unstable();
        merged.dedup();
        merged
    }

    fn note_is_locked<N>(&self, note: &ReceivedNote<ReceivedNoteId, N>) -> bool {
        let key = (
            format!("{}", note.txid()).to_lowercase(),
            note.output_index() as u32,
        );
        self.migration_locks.contains(&key)
    }
}

impl InputSource for ReservedInputSource<'_> {
    type Error = <WalletDatabase as InputSource>::Error;
    type AccountId = <WalletDatabase as InputSource>::AccountId;
    type NoteRef = <WalletDatabase as InputSource>::NoteRef;

    fn get_spendable_note(
        &self,
        txid: &TxId,
        protocol: ShieldedProtocol,
        index: u32,
        target_height: wallet::TargetHeight,
    ) -> Result<Option<ReceivedNote<Self::NoteRef, Note>>, Self::Error> {
        Ok(self
            .inner
            .get_spendable_note(txid, protocol, index, target_height)?
            .filter(|note| !self.reserved.contains(note.internal_note_id()))
            .filter(|note| !self.note_is_locked(note)))
    }

    fn select_spendable_notes(
        &self,
        account: Self::AccountId,
        target_value: TargetValue,
        sources: &[ShieldedProtocol],
        target_height: wallet::TargetHeight,
        confirmations_policy: ConfirmationsPolicy,
        exclude: &[Self::NoteRef],
    ) -> Result<ReceivedNotes<Self::NoteRef>, Self::Error> {
        let selected = self.inner.select_spendable_notes(
            account,
            target_value,
            sources,
            target_height,
            confirmations_policy,
            &self.merged_excludes(exclude),
        )?;
        Ok(ReceivedNotes::new(
            selected.sapling().to_vec(),
            selected
                .orchard()
                .iter()
                .filter(|note| !self.note_is_locked(note))
                .cloned()
                .collect(),
            selected
                .ironwood()
                .iter()
                .filter(|note| !self.note_is_locked(note))
                .cloned()
                .collect(),
        ))
    }

    fn select_unspent_notes(
        &self,
        account: Self::AccountId,
        sources: &[ShieldedProtocol],
        target_height: wallet::TargetHeight,
        exclude: &[Self::NoteRef],
    ) -> Result<ReceivedNotes<Self::NoteRef>, Self::Error> {
        let selected = self.inner.select_unspent_notes(
            account,
            sources,
            target_height,
            &self.merged_excludes(exclude),
        )?;
        Ok(ReceivedNotes::new(
            selected.sapling().to_vec(),
            selected
                .orchard()
                .iter()
                .filter(|note| !self.note_is_locked(note))
                .cloned()
                .collect(),
            selected
                .ironwood()
                .iter()
                .filter(|note| !self.note_is_locked(note))
                .cloned()
                .collect(),
        ))
    }

    fn get_account_metadata(
        &self,
        account: Self::AccountId,
        selector: &NoteFilter,
        target_height: wallet::TargetHeight,
        exclude: &[Self::NoteRef],
    ) -> Result<AccountMeta, Self::Error> {
        self.inner.get_account_metadata(
            account,
            selector,
            target_height,
            &self.merged_excludes(exclude),
        )
    }

    fn get_unspent_transparent_output(
        &self,
        outpoint: &OutPoint,
        target_height: wallet::TargetHeight,
    ) -> Result<Option<WalletTransparentOutput<Self::AccountId>>, Self::Error> {
        self.inner
            .get_unspent_transparent_output(outpoint, target_height)
    }

    fn get_spendable_transparent_outputs(
        &self,
        address: &TransparentAddress,
        target_height: wallet::TargetHeight,
        confirmations_policy: ConfirmationsPolicy,
        output_filter: CoinbaseFilter,
    ) -> Result<Vec<WalletTransparentOutput<Self::AccountId>>, Self::Error> {
        self.inner.get_spendable_transparent_outputs(
            address,
            target_height,
            confirmations_policy,
            output_filter,
        )
    }
}

fn build_send_max_proposal(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    to_address: &str,
    memo_str: Option<&str>,
) -> Result<Proposal<WalletFeeRule, <WalletDatabase as InputSource>::NoteRef>, String> {
    let to: zcash_address::ZcashAddress = to_address
        .parse()
        .map_err(|e| format!("Bad address: {e}"))?;
    let recipient_address: Address = to
        .clone()
        .convert_if_network(network.network_type())
        .map_err(|e| format!("Bad address: {e:?}"))?;
    let memo_bytes = match memo_str {
        Some(m) => {
            let bytes = MemoBytes::from(
                Memo::from_bytes(m.as_bytes()).map_err(|e| format!("Bad memo: {e}"))?,
            );
            Some(bytes)
        }
        None => None,
    };
    let fee_rule = ConservativeZip317FeeRule;

    if matches!(recipient_address, Address::Transparent(_)) {
        return build_transparent_recipient_send_max_proposal(
            db, network, account_id, to, memo_bytes, fee_rule,
        );
    }

    propose_send_max_transfer::<_, _, _, Infallible>(
        db,
        &network,
        account_id,
        // Ironwood / NU6.3 notes are selected through the Orchard protocol path as
        // v3 note rows; librustzcash does not expose a separate Ironwood
        // ShieldedProtocol selector. This is why balance prechecks can treat
        // spendable Ironwood value as available to ordinary sends.
        &[ShieldedProtocol::Sapling, ShieldedProtocol::Orchard],
        &fee_rule,
        to,
        memo_bytes,
        MaxSpendMode::MaxSpendable,
        ConfirmationsPolicy::default(),
    )
    .map_err(|e| format!("Propose max failed: {e}"))
}

/// Pass-1 "ceiling" tx version for the wallet's current target height (see
/// [`proposed_tx_version_for_send`]); the ordinary send paths may still
/// downgrade it per [`should_downgrade_send_to_legacy_v5`].
fn proposed_tx_version_for_wallet_db(
    db: &WalletDatabase,
    network: WalletNetwork,
    context: &str,
) -> Result<Option<TxVersion>, String> {
    let confirmations_policy = ConfirmationsPolicy::default();
    let (target_height, _) = db
        .get_target_and_anchor_heights(confirmations_policy.trusted())
        .map_err(|e| format!("Read chain state for {context}: {e}"))?
        .ok_or_else(|| format!("Wallet must sync before {context}"))?;
    Ok(proposed_tx_version_for_send(network, target_height))
}

/// Pass-1 "ceiling" tx version: `Some(V6)` once NU6.3 is active at the target
/// height, before [`should_downgrade_send_to_legacy_v5`] is applied to the
/// selected notes.
fn proposed_tx_version_for_send(
    network: WalletNetwork,
    target_height: wallet::TargetHeight,
) -> Option<TxVersion> {
    if network.is_nu_active(
        consensus::NetworkUpgrade::Nu6_3,
        BlockHeight::from(target_height),
    ) {
        return Some(TxVersion::V6);
    }

    None
}

fn build_transparent_recipient_send_max_proposal(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    to: zcash_address::ZcashAddress,
    memo_bytes: Option<MemoBytes>,
    fee_rule: WalletFeeRule,
) -> Result<Proposal<WalletFeeRule, <WalletDatabase as InputSource>::NoteRef>, String> {
    let confirmations_policy = ConfirmationsPolicy::default();
    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(confirmations_policy.trusted())
        .map_err(|e| format!("Failed to read target height: {e}"))?
        .ok_or("Wallet must sync before sending max")?;

    let spendable_notes = db
        .select_spendable_notes(
            account_id,
            TargetValue::AllFunds(MaxSpendMode::MaxSpendable),
            &[ShieldedProtocol::Sapling, ShieldedProtocol::Orchard],
            target_height,
            confirmations_policy,
            &[],
        )
        .map_err(|e| format!("Select max inputs failed: {e}"))?;

    build_transparent_recipient_send_max_proposal_from_notes(
        network,
        target_height,
        anchor_height,
        to,
        memo_bytes,
        spendable_notes,
        fee_rule,
    )
}

fn build_transparent_recipient_send_max_proposal_from_notes<NoteRef>(
    network: WalletNetwork,
    target_height: TargetHeight,
    anchor_height: BlockHeight,
    to: zcash_address::ZcashAddress,
    memo_bytes: Option<MemoBytes>,
    spendable_notes: ReceivedNotes<NoteRef>,
    fee_rule: WalletFeeRule,
) -> Result<Proposal<WalletFeeRule, NoteRef>, String> {
    let input_total = spendable_notes
        .total_value()
        .map_err(|e| format!("Max input calculation failed: {e}"))?;
    let sapling_input_count = spendable_notes.sapling().len();
    let orchard_input_count = spendable_notes.orchard().len();

    let sapling_output_count = sapling_crypto::builder::BundleType::DEFAULT
        .num_outputs(sapling_input_count, 0)
        .map_err(|e| format!("Max Sapling bundle size failed: {e:?}"))?;
    // Legacy/V5 Orchard send path, so count actions under the post-NU6.2 bundle
    // version's default flags (matches librustzcash's `transactional_action_count`).
    let orchard_action_count = ::orchard::builder::BundleType::DEFAULT
        .num_actions(
            ::orchard::bundle::BundleVersion::orchard_v2().default_flags(),
            orchard_input_count,
            0,
        )
        .map_err(|e| format!("Max Orchard bundle size failed: {e:?}"))?;

    let fee = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            [P2PKH_STANDARD_OUTPUT_SIZE],
            sapling_input_count,
            sapling_output_count,
            orchard_action_count,
            // Legacy/V5 path: no Ironwood bundle.
            0,
        )
        .map_err(|e| format!("Max fee calculation failed: {e}"))?;

    let total_to_recipient =
        (input_total - fee).ok_or("Insufficient shielded balance to cover fee")?;
    if total_to_recipient == Zatoshis::ZERO {
        return Err("Insufficient shielded balance to cover fee".to_string());
    }

    let payment = Payment::new(to, Some(total_to_recipient), memo_bytes, None, None, vec![])
        .map_err(|e| format!("Cannot create payment: {e:?}"))?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let shielded_inputs = nonempty::NonEmpty::from_vec(spendable_notes.into_vec(&RetainAllNotes))
        .map(ShieldedInputs::from_parts)
        .ok_or("No shielded funds available to send")?;

    let balance = TransactionBalance::new(vec![], fee)
        .map_err(|e| format!("Max balance calculation failed: {e}"))?;

    Proposal::single_step(
        request,
        BTreeMap::from([(0usize, PoolType::TRANSPARENT)]),
        vec![],
        Some(shielded_inputs),
        anchor_height,
        balance,
        fee_rule,
        target_height,
        // Matches the flow's proposal policy (see zip317_helper callers).
        ConfirmationsPolicy::default(),
        false,
        network.is_nu_active(
            zcash_protocol::consensus::NetworkUpgrade::Nu6_3,
            BlockHeight::from(target_height),
        ),
    )
    .map_err(|e| format!("Propose transparent max failed: {e}"))
}

fn summarize_send_max_proposal<NoteRef>(
    proposal: &Proposal<WalletFeeRule, NoteRef>,
) -> Result<SendMaxEstimateResult, String> {
    let amount_zatoshi = proposal.steps().iter().try_fold(0u64, |acc, step| {
        let step_total = step
            .transaction_request()
            .total()
            .map_err(|e| format!("Max amount calculation failed: {e}"))?;
        let step_total = step_total.ok_or("Max amount calculation missing payment amount")?;
        acc.checked_add(u64::from(step_total))
            .ok_or_else(|| "Max amount overflow".to_string())
    })?;
    let needs_sapling_params = proposal
        .steps()
        .iter()
        .any(|step| step.involves(PoolType::Shielded(ShieldedProtocol::Sapling)));

    Ok(SendMaxEstimateResult {
        amount_zatoshi,
        fee_zatoshi: proposal_fee_zatoshi(proposal),
        needs_sapling_params,
    })
}

fn select_shielding_sources(
    account_receivers: HashMap<TransparentAddress, (TransparentKeyOrigin, Balance)>,
    shielding_threshold: Zatoshis,
) -> Result<(Vec<TransparentAddress>, Zatoshis), String> {
    let mut ephemeral = Vec::new();
    let mut non_ephemeral = Vec::new();

    for (address, (origin, balance)) in account_receivers {
        let spendable = balance.spendable_value();
        if spendable > Zatoshis::ZERO {
            if matches!(
                origin,
                TransparentKeyOrigin::Derived {
                    scope: TransparentKeyScope::EPHEMERAL
                }
            ) {
                ephemeral.push((address, spendable));
            } else {
                non_ephemeral.push((address, spendable));
            }
        }
    }

    // Match the SDK policy: spend all non-ephemeral transparent receivers
    // together, but never link more than one ephemeral receiver in a single
    // shielding transaction.
    let selected = if non_ephemeral.is_empty() {
        ephemeral
            .into_iter()
            .max_by_key(|(_, value)| u64::from(*value))
            .into_iter()
            .collect()
    } else {
        non_ephemeral
    };

    let mut total = Zatoshis::ZERO;
    let mut addresses = Vec::with_capacity(selected.len());
    for (address, value) in selected {
        total = (total + value).ok_or("Selected transparent balance overflow")?;
        addresses.push(address);
    }

    if addresses.is_empty() || total < shielding_threshold {
        return Err("No transparent funds available to shield above the fee threshold".to_string());
    }

    Ok((addresses, total))
}

fn proposal_fee_zatoshi<NoteRef>(proposal: &Proposal<WalletFeeRule, NoteRef>) -> u64 {
    proposal
        .steps()
        .iter()
        .map(|step| u64::from(step.balance().fee_required()))
        .sum()
}

fn proposal_shielded_zatoshi(proposal: &Proposal<WalletFeeRule, Infallible>) -> u64 {
    proposal
        .steps()
        .iter()
        .flat_map(|step| step.balance().proposed_change().iter())
        .map(|change| u64::from(change.value()))
        .sum()
}

fn ensure_transparent_shielding_pczt_targets_ironwood(pczt_bytes: &[u8]) -> Result<(), String> {
    let pczt = pczt::Pczt::parse(pczt_bytes)
        .map_err(|e| format!("Parse transparent shielding PCZT: {e:?}"))?;
    if *pczt.global().tx_version() != zcash_protocol::constants::V6_TX_VERSION {
        return Err("Transparent shielding PCZT must use transaction v6 after NU6.3.".to_string());
    }
    if pczt.ironwood().actions().is_empty() {
        return Err("Transparent shielding PCZT did not target Ironwood.".to_string());
    }
    if !pczt.orchard().actions().is_empty() {
        return Err(
            "Transparent shielding PCZT unexpectedly contains legacy Orchard actions.".to_string(),
        );
    }

    Ok(())
}

fn same_prepared_note_without_nullifier(
    lhs: &super::migration::PreparedOrchardNoteRef,
    rhs: &super::migration::PreparedOrchardNoteRef,
) -> bool {
    lhs.txid_hex.eq_ignore_ascii_case(&rhs.txid_hex)
        && lhs.output_index == rhs.output_index
        && lhs.value_zatoshi == rhs.value_zatoshi
        && lhs.note_version == rhs.note_version
}

fn orchard_anchor_and_witnesses_for_denomination_inputs(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    inputs: &[super::migration::DenominationStageInputRef],
) -> Result<Option<(orchard::Anchor, Vec<(String, orchard::tree::MerklePath)>)>, String> {
    if inputs.is_empty() {
        return Err("Denomination stage has no inputs".to_string());
    }

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let orchard_fvk = account
        .ufvk()
        .and_then(|ufvk| ufvk.orchard().cloned())
        .ok_or("Orchard viewing key not available")?;
    let (_, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before finalizing a denomination stage")?;
    // Select at the trusted anchor rather than through `get_spendable_note`.
    // The latter intentionally hides a note once any unexpired local
    // transaction spends it. After a reorg we need to reprove the same signed
    // effecting data, so the old unmined authorization must not hide the
    // stage-owned input from recovery.
    let available_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;

    let mut selected_notes = Vec::with_capacity(inputs.len());
    let mut nullifiers = Vec::with_capacity(inputs.len());
    for input in inputs {
        if input.note_version != 2 {
            return Err("Denomination stage input is not an Orchard V2 note".to_string());
        }
        let Some(selected) = available_notes.iter().find(|selected| {
            format!("{}", selected.txid()).eq_ignore_ascii_case(&input.txid_hex)
                && selected.output_index() as u32 == input.output_index
        }) else {
            return Ok(None);
        };
        let orchard_note = *selected.note();
        if orchard_note.version() != orchard::note::NoteVersion::V2 {
            return Err("Denomination stage input revalidated as non-V2 Orchard".to_string());
        }
        let selected_value: Zatoshis = orchard_note
            .value()
            .inner()
            .try_into()
            .map_err(|e| format!("Denomination stage input value invalid: {e}"))?;
        if u64::from(selected_value) != input.value_zatoshi {
            return Err("Denomination stage input value changed during revalidation".to_string());
        }
        let nullifier_hex = hex::encode(orchard_note.nullifier(&orchard_fvk).to_bytes());
        let expected_nullifier = input
            .nullifier_hex
            .as_deref()
            .ok_or("Denomination stage input nullifier is missing")?;
        if !nullifier_hex.eq_ignore_ascii_case(expected_nullifier) {
            return Err(
                "Denomination stage input nullifier changed during revalidation".to_string(),
            );
        }
        nullifiers.push(nullifier_hex);
        selected_notes.push(ReceivedNote::from_parts(
            *selected.internal_note_id(),
            *selected.txid(),
            selected.output_index(),
            orchard_note,
            selected.spending_key_scope(),
            selected.note_commitment_tree_position(),
            selected.mined_height(),
            selected.max_shielding_input_height(),
        ));
    }

    let (anchor, witnesses) = orchard_witnesses(&mut db, anchor_height, &selected_notes)?;
    if witnesses.len() != nullifiers.len() {
        return Err("Denomination stage witness count changed".to_string());
    }
    Ok(Some((
        anchor,
        nullifiers
            .into_iter()
            .zip(witnesses.into_iter().map(|(_, witness)| witness))
            .collect(),
    )))
}

fn orchard_anchor_and_witness_for_prepared_note(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    note_ref: &super::migration::PreparedOrchardNoteRef,
    preferred_anchor_boundary_height: Option<u32>,
    anchor_cohort_counts: &mut BTreeMap<u32, u32>,
) -> Result<Option<(u32, orchard::Anchor, orchard::tree::MerklePath)>, String> {
    if note_ref.note_version != 2 {
        return Err("Prepared migration note is not an Orchard V2 note".to_string());
    }

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    db.get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;

    let (_, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before finalizing migration")?;
    let available_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    let Some(selected) = available_notes.iter().find(|selected| {
        format!("{}", selected.txid()).eq_ignore_ascii_case(&note_ref.txid_hex)
            && selected.output_index() as u32 == note_ref.output_index
    }) else {
        return Ok(None);
    };
    let orchard_note = *selected.note();
    if orchard_note.version() != orchard::note::NoteVersion::V2 {
        return Err("Prepared note revalidated as non-V2 Orchard".to_string());
    }
    let selected_value: Zatoshis = orchard_note
        .value()
        .inner()
        .try_into()
        .map_err(|e| format!("Prepared note value invalid: {e}"))?;
    if u64::from(selected_value) != note_ref.value_zatoshi {
        return Err("Prepared note value changed during revalidation".to_string());
    }
    let anchor_height_u32 = u32::from(anchor_height);
    let nu6_3_activation_height = nu6_3_activation_height_u32(network)?;
    let mined_height = selected
        .mined_height()
        .ok_or("Prepared migration note mined height unavailable")?;
    let mined_height = u32::from(mined_height);
    let anchor_boundary_height = preferred_anchor_boundary_height
        .filter(|boundary| {
            anchor_cohort_counts
                .get(boundary)
                .copied()
                .unwrap_or_default()
                < super::migration::ZIP318_MAX_PARTS_PER_ANCHOR_COHORT
                && super::migration::zip318_anchor_boundary_is_candidate(
                    network,
                    *boundary,
                    anchor_height_u32,
                    mined_height,
                    nu6_3_activation_height,
                )
        })
        .or_else(|| {
            super::migration::zip318_draw_anchor_boundary_for_note_with_cohorts(
                network,
                anchor_height_u32,
                mined_height,
                nu6_3_activation_height,
                anchor_cohort_counts,
            )
        });
    let Some(anchor_boundary_height) = anchor_boundary_height else {
        return Ok(None);
    };
    *anchor_cohort_counts
        .entry(anchor_boundary_height)
        .or_default() += 1;

    let orchard_selected = ReceivedNote::from_parts(
        *selected.internal_note_id(),
        *selected.txid(),
        selected.output_index(),
        orchard_note,
        selected.spending_key_scope(),
        selected.note_commitment_tree_position(),
        selected.mined_height(),
        selected.max_shielding_input_height(),
    );
    let (orchard_anchor, mut orchard_inputs) = migration_orchard_witnesses(
        &mut db,
        network,
        BlockHeight::from(anchor_boundary_height),
        std::slice::from_ref(&orchard_selected),
    )?;
    let (_, witness) = orchard_inputs
        .pop()
        .ok_or("Prepared migration note witness missing")?;
    Ok(Some((anchor_boundary_height, orchard_anchor, witness)))
}

#[allow(clippy::too_many_arguments)]
fn rebuild_expired_software_migration_parts(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run_id: &str,
    recoveries: Vec<super::migration::PendingMigrationPartRecovery>,
    usk: &UnifiedSpendingKey,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<(), String> {
    let retained_children = super::migration::signed_child_pczts_for_run(
        db_path,
        run_id,
        pending_password,
        pending_salt_base64,
    )?;
    let mut anchor_cohort_counts = super::migration::pending_anchor_cohort_counts(db_path, run_id)?;
    let mut replacements = Vec::with_capacity(recoveries.len());
    let mut replacement_children = Vec::with_capacity(recoveries.len());

    for (index, recovery) in recoveries.into_iter().enumerate() {
        let created = create_orchard_to_ironwood_pczt_from_note(
            db_path,
            network,
            account_uuid,
            &recovery.selected_note,
            (index + 1) as u32,
            &mut anchor_cohort_counts,
            true,
        )?
        .ok_or("Expired migration funding note is not spendable at a canonical anchor")?;
        if created.migrated_zatoshi != recovery.value_zatoshi {
            return Err("Expired migration denomination changed during rebuild".to_string());
        }
        if created.fee_zatoshi != recovery.fee_zatoshi {
            return Err(
                "Canonical migration fee changed while rebuilding an expired part".to_string(),
            );
        }

        let signed_pczt = sign_orchard_migration_pczt_with_usk(
            &created.base_pczt,
            &created.orchard_spend_action_indices,
            usk,
        )?;
        let sigs = super::pczt::extract_required_compact_sigs_from_signed_pczt(
            &created.base_pczt,
            &signed_pczt,
        )?;
        super::pczt::preflight_orchard_spend_auth_signatures(&created.base_pczt, &sigs)?;
        let proofed = super::pczt::add_proofs_to_pczt(&created.base_pczt, None, None)?;
        let extracted = super::pczt::apply_sigs_and_extract(&proofed, &sigs, None, None)?;
        let retained = retained_children
            .iter()
            .find(|child| {
                same_prepared_note_without_nullifier(&child.selected_note, &recovery.selected_note)
            })
            .ok_or("Retained migration signature record is missing for expired part")?;
        let metadata = super::migration::PendingMigrationTxMetadata {
            tx_kind: "migration".to_string(),
            funding_account_uuid: account_uuid.to_string(),
            selected_note: recovery.selected_note.clone(),
        };

        replacements.push(super::migration::PendingMigrationTxReplacement {
            old_txid_hex: recovery.old_txid_hex,
            replacement: super::migration::PendingMigrationTxInsert {
                txid_hex: extracted.txid.to_string(),
                raw_tx: extracted.raw_tx,
                target_height: created.target_height,
                anchor_boundary_height: created.anchor_boundary_height,
                expiry_height: created.expiry_height,
                value_zatoshi: created.migrated_zatoshi,
                fee_zatoshi: created.fee_zatoshi,
                selected_note: recovery.selected_note.clone(),
                metadata: metadata.clone(),
            },
        });
        replacement_children.push(super::migration::SignedMigrationPcztInsert {
            message_id: retained.message_id.clone(),
            child_index: retained.child_index,
            base_pczt: created.base_pczt,
            sigs,
            target_height: created.target_height,
            anchor_boundary_height: created.anchor_boundary_height,
            expiry_height: created.expiry_height,
            value_zatoshi: created.migrated_zatoshi,
            fee_zatoshi: created.fee_zatoshi,
            selected_note: recovery.selected_note,
            metadata,
        });
    }

    super::migration::replace_resigned_pending_parts(
        db_path,
        run_id,
        network,
        replacements,
        replacement_children,
        pending_password,
        pending_salt_base64,
    )
}

fn finalize_presigned_migration_children(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<bool, String> {
    if super::migration::signed_child_pczt_count(db_path, run_id)? == 0 {
        return Ok(false);
    }
    if !prepared_note_spend_metadata_is_available(db_path, run_id)? {
        return Ok(false);
    }

    let signed_children = super::migration::signed_child_pczts_for_run(
        db_path,
        run_id,
        pending_password,
        pending_salt_base64,
    )?;
    if signed_children.is_empty() {
        return Ok(false);
    }

    let current_prepared = super::migration::prepared_notes_for_run(db_path, run_id)?;
    let already_pending = super::migration::pending_migration_note_outpoints(db_path, run_id)?;
    let mut anchor_cohort_counts = super::migration::pending_anchor_cohort_counts(db_path, run_id)?;
    let mut pending_inserts = Vec::with_capacity(signed_children.len());
    let signed_child_count = signed_children.len();
    for (child_index, child) in signed_children.into_iter().enumerate() {
        if already_pending.contains(&(
            child.selected_note.txid_hex.to_ascii_lowercase(),
            child.selected_note.output_index,
        )) {
            continue;
        }
        let current_note = current_prepared
            .iter()
            .find(|note| same_prepared_note_without_nullifier(note, &child.selected_note))
            .ok_or("Prepared migration notes changed before child finalization")?;
        let Some((anchor_boundary_height, orchard_anchor, orchard_witness)) =
            (match orchard_anchor_and_witness_for_prepared_note(
                db_path,
                network,
                account_uuid,
                current_note,
                child.anchor_boundary_height,
                &mut anchor_cohort_counts,
            ) {
                Ok(result) => result,
                Err(e) if is_orchard_witness_not_ready_error(&e) => {
                    mark_prepared_notes_waiting(db_path, run_id)?;
                    return Ok(false);
                }
                Err(e) => return Err(e),
            })
        else {
            mark_prepared_notes_waiting(db_path, run_id)?;
            return Ok(false);
        };
        let current_note_nullifier_hex = current_note
            .nullifier_hex
            .as_deref()
            .ok_or("Prepared migration note nullifier unavailable")?;

        // Set the real anchor/witness on the base before proving — Orchard
        // proofs depend on the real anchor. The stored spend-authorization
        // signatures are anchor-independent (the ZIP-244 spend-auth sighash does
        // not commit to the anchor), so we apply them directly onto the proofed
        // base via the compact path instead of re-anchoring a full signed PCZT.
        let base_pczt = super::pczt::set_orchard_anchor_and_witness(
            &child.base_pczt,
            orchard_anchor,
            &orchard_witness,
            current_note_nullifier_hex,
        )?;
        log::debug!(
            "migration: proving child {}/{} for run {}",
            child_index + 1,
            signed_child_count,
            run_id,
        );
        let pczt_with_proofs = super::pczt::add_proofs_to_pczt(&base_pczt, None, None)?;
        let extracted =
            super::pczt::apply_sigs_and_extract(&pczt_with_proofs, &child.sigs, None, None)?;
        log::debug!(
            "migration: proved child {}/{} for run {} as {} from {}:{}",
            child_index + 1,
            signed_child_count,
            run_id,
            extracted.txid,
            current_note.txid_hex,
            current_note.output_index,
        );
        pending_inserts.push(super::migration::PendingMigrationTxInsert {
            txid_hex: extracted.txid.to_string(),
            raw_tx: extracted.raw_tx,
            target_height: child.target_height,
            anchor_boundary_height: Some(anchor_boundary_height),
            expiry_height: child.expiry_height,
            value_zatoshi: child.value_zatoshi,
            fee_zatoshi: child.fee_zatoshi,
            selected_note: current_note.clone(),
            metadata: super::migration::PendingMigrationTxMetadata {
                tx_kind: child.metadata.tx_kind,
                funding_account_uuid: child.metadata.funding_account_uuid,
                selected_note: current_note.clone(),
            },
        });
    }

    if pending_inserts.is_empty() {
        return Ok(false);
    }

    super::migration::promote_signed_child_pczts_to_pending_txs(
        db_path,
        run_id,
        pending_inserts,
        pending_password,
        pending_salt_base64,
    )?;
    Ok(true)
}

fn finalize_ready_denomination_stages(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<bool, String> {
    let stages = {
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        super::migration::denomination_stages_for_run(
            &conn,
            run_id,
            pending_password,
            pending_salt_base64,
        )?
    };
    if stages.is_empty() {
        return Ok(false);
    }

    let mut promoted = false;
    for stage in stages
        .iter()
        .filter(|stage| stage.status == super::migration::DenominationStageStatus::AwaitingInputs)
    {
        let Some((anchor, witnesses)) = (match orchard_anchor_and_witnesses_for_denomination_inputs(
            db_path,
            network,
            account_uuid,
            &stage.inputs,
        ) {
            Ok(result) => result,
            Err(e) if is_orchard_witness_not_ready_error(&e) => return Ok(promoted),
            Err(e) => return Err(e),
        }) else {
            continue;
        };
        let base_pczt = super::pczt::set_orchard_anchor_and_witnesses(
            &stage.base_pczt,
            anchor,
            witnesses
                .iter()
                .map(|(nullifier, witness)| (nullifier.as_str(), witness)),
        )?;
        let pczt_with_proofs = super::pczt::add_proofs_to_pczt(&base_pczt, None, None)?;
        let extracted =
            super::pczt::apply_sigs_and_extract(&pczt_with_proofs, &stage.sigs, None, None)?;
        if !extracted
            .txid
            .to_string()
            .eq_ignore_ascii_case(&stage.expected_txid_hex)
        {
            return Err(format!(
                "Denomination stage {} extracted an unexpected txid",
                stage.stage_index
            ));
        }

        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        super::migration::promote_awaiting_denomination_stage(
            &conn,
            run_id,
            stage.stage_index,
            &stage.expected_txid_hex,
            extracted.raw_tx,
            pending_password,
            pending_salt_base64,
        )?;
        promoted = true;
    }
    Ok(promoted)
}

async fn broadcast_pending_denomination_stages(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<Option<CreatedBroadcastResult>, String> {
    let pending = {
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        super::migration::pending_raw_denomination_stages(
            &conn,
            run_id,
            pending_password,
            pending_salt_base64,
        )?
    };
    if pending.is_empty() {
        return Ok(None);
    }

    let txids = pending
        .iter()
        .map(|stage| stage.expected_txid_hex.as_str())
        .collect::<Vec<_>>()
        .join(",");
    let total_count = u32::try_from(pending.len())
        .map_err(|_| "Pending denomination stage count exceeds u32".to_string())?;
    let mut client = match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
        Ok(client) => client,
        Err(e) => {
            return Ok(Some(CreatedBroadcastResult {
                txids,
                status: CreatedBroadcastResult::PENDING_BROADCAST,
                broadcasted_count: 0,
                total_count,
                message: Some(format!("Denomination split broadcast could not start: {e}")),
            }));
        }
    };

    let mut broadcasted_count = 0u32;
    for stage in &pending {
        if let Err(e) = broadcast_raw_transaction(&mut client, &stage.raw_tx).await {
            return Ok(Some(CreatedBroadcastResult {
                txids,
                status: if broadcasted_count == 0 {
                    CreatedBroadcastResult::PENDING_BROADCAST
                } else {
                    CreatedBroadcastResult::PARTIAL_BROADCAST
                },
                broadcasted_count,
                total_count,
                message: Some(format!(
                    "Denomination split broadcast failed for {}: {e}",
                    stage.expected_txid_hex
                )),
            }));
        }

        if let Err(e) = decrypt_and_store_migration_tx(db_path, network, &stage.raw_tx) {
            let message =
                migration_storage_retry_message("Denomination split", &stage.expected_txid_hex, &e);
            log::warn!("migration: {message}");
            return Ok(Some(CreatedBroadcastResult {
                txids,
                status: if broadcasted_count == 0 {
                    CreatedBroadcastResult::PENDING_BROADCAST
                } else {
                    CreatedBroadcastResult::PARTIAL_BROADCAST
                },
                broadcasted_count,
                total_count,
                message: Some(message),
            }));
        }

        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        super::migration::mark_denomination_stage_broadcasted(
            &conn,
            run_id,
            &stage.expected_txid_hex,
        )?;
        broadcasted_count = broadcasted_count
            .checked_add(1)
            .ok_or("Broadcasted denomination stage count overflow")?;
        log::info!(
            "migration: broadcast denomination stage {} ({})",
            stage.stage_index,
            stage.expected_txid_hex
        );
    }

    Ok(Some(CreatedBroadcastResult {
        txids,
        status: super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS,
        broadcasted_count,
        total_count,
        message: Some(if total_count == 1 {
            "Denomination split stage was created. Migration will continue after confirmation."
                .to_string()
        } else {
            format!(
                "{total_count} independent denomination split stages were created. Migration will continue after confirmation."
            )
        }),
    }))
}

async fn broadcast_due_scheduled_migration_txs(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
) -> Result<IronwoodMigrationResult, String> {
    let totals_before = super::migration::pending_totals_for_run(db_path, run_id)?;
    if totals_before.total_count == 0 {
        return Ok(migration_result_from_pending_totals(
            totals_before,
            super::migration::PHASE_READY_TO_MIGRATE,
            Some("No signed migration transactions are scheduled yet.".to_string()),
            fallback_total_count,
            fallback_migrated_zatoshi,
        ));
    }

    let chain_tip_height =
        u32::try_from(super::get_sync_progress(db_path, network)?.chain_tip_height)
            .map_err(|_| "Migration chain tip exceeds u32".to_string())?;
    if let Some(message) =
        pending_migration_policy_rebuild_message(db_path, network, run_id, chain_tip_height)?
    {
        super::migration::retire_run_for_rebuild(db_path, run_id, &message)?;
        return Ok(migration_result_from_pending_totals(
            totals_before,
            super::migration::PHASE_FAILED_TERMINAL,
            Some(message),
            fallback_total_count,
            fallback_migrated_zatoshi,
        ));
    }

    let expired_count =
        super::migration::expired_unconfirmed_pending_count(db_path, run_id, chain_tip_height)?;
    if expired_count > 0 {
        let message = format!(
            "{expired_count} migration transaction(s) expired before confirmation. Re-sign the affected denomination(s) with fresh anchors and expiry heights."
        );
        super::migration::mark_expired_pending_parts_for_resign(db_path, run_id, chain_tip_height)?;
        return Ok(migration_result_from_pending_totals(
            totals_before,
            super::migration::PHASE_READY_TO_MIGRATE,
            Some(message),
            fallback_total_count,
            fallback_migrated_zatoshi,
        ));
    }
    let due = super::migration::due_pending_txs(
        db_path,
        run_id,
        chain_tip_height,
        pending_password,
        pending_salt_base64,
    )?;
    if due.is_empty() {
        let status = if super::migration::next_scheduled_height(db_path, run_id)?.is_some() {
            super::migration::PHASE_BROADCAST_SCHEDULED
        } else {
            super::migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS
        };
        return Ok(migration_result_from_pending_totals(
            totals_before,
            status,
            Some("Migration transactions are scheduled for delayed broadcast.".to_string()),
            fallback_total_count,
            fallback_migrated_zatoshi,
        ));
    }

    let mut client = match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
        Ok(client) => client,
        Err(e) => {
            let message = format!("Migration broadcast could not start: {e}");
            super::migration::mark_run_phase(
                db_path,
                run_id,
                super::migration::PHASE_FAILED_RECOVERABLE,
                Some(&message),
            )?;
            return Ok(IronwoodMigrationResult {
                txids: String::new(),
                status: super::migration::PHASE_FAILED_RECOVERABLE.to_string(),
                broadcasted_count: 0,
                total_count: fallback_total_count,
                message: Some(message),
                fee_zatoshi: 0,
                migrated_zatoshi: fallback_migrated_zatoshi,
            });
        }
    };

    super::migration::mark_run_phase(db_path, run_id, super::migration::PHASE_BROADCASTING, None)?;
    for pending in due {
        if let Err(e) = broadcast_raw_transaction(&mut client, &pending.raw_tx).await {
            log::error!(
                "migration: broadcast rejected for {}: {}",
                pending.txid_hex,
                e,
            );
            let message = format!(
                "Migration broadcast failed for {}. Error: {e}",
                pending.txid_hex
            );
            if migration_broadcast_failure_requires_rebuild(&e) {
                let rebuild_message = format!(
                    "Migration transaction {} was rejected by the network. Review and approve a fresh schedule for the remaining Orchard balance. Error: {e}",
                    pending.txid_hex
                );
                super::migration::retire_run_for_rebuild(db_path, run_id, &rebuild_message)?;
                let totals = super::migration::pending_totals_for_run(db_path, run_id)?;
                return Ok(migration_result_from_pending_totals(
                    totals,
                    super::migration::PHASE_FAILED_TERMINAL,
                    Some(rebuild_message),
                    fallback_total_count,
                    fallback_migrated_zatoshi,
                ));
            }
            super::migration::mark_run_phase(
                db_path,
                run_id,
                super::migration::PHASE_FAILED_RECOVERABLE,
                Some(&message),
            )?;
            let totals = super::migration::pending_totals_for_run(db_path, run_id)?;
            return Ok(migration_result_from_pending_totals(
                totals,
                super::migration::PHASE_FAILED_RECOVERABLE,
                Some(message),
                fallback_total_count,
                fallback_migrated_zatoshi,
            ));
        }

        if let Some(result) = record_accepted_scheduled_migration_tx(
            db_path,
            network,
            run_id,
            &pending,
            fallback_total_count,
            fallback_migrated_zatoshi,
            decrypt_and_store_migration_tx,
        )? {
            return Ok(result);
        }
        super::migration::reschedule_overdue_pending_txs(
            db_path,
            run_id,
            network,
            chain_tip_height,
        )?;
        log::info!("migration: broadcast scheduled tx {}", pending.txid_hex);
    }

    let totals = super::migration::pending_totals_for_run(db_path, run_id)?;
    let scheduled_remaining = super::migration::scheduled_pending_count(db_path, run_id)?;
    let status = if scheduled_remaining > 0 {
        super::migration::PHASE_BROADCAST_SCHEDULED
    } else {
        super::migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS
    };
    let message = if scheduled_remaining > 0 {
        "Due migration transactions were submitted. More are scheduled.".to_string()
    } else {
        "Migration transactions were broadcast on the saved schedule.".to_string()
    };
    Ok(migration_result_from_pending_totals(
        totals,
        status,
        Some(message),
        fallback_total_count,
        fallback_migrated_zatoshi,
    ))
}

fn migration_broadcast_failure_requires_rebuild(error: &str) -> bool {
    error.starts_with("Broadcast rejected:")
}

fn decrypt_and_store_migration_tx(
    db_path: &str,
    network: WalletNetwork,
    raw_tx: &[u8],
) -> Result<(), String> {
    super::transactions::decrypt_and_store_transaction(db_path, network, raw_tx, None)
}

fn migration_storage_retry_message(tx_label: &str, txid_hex: &str, error: &str) -> String {
    format!(
        "{tx_label} {txid_hex} was accepted by lightwalletd, but local wallet storage failed: {error}. Vizor will retry until local state is recorded."
    )
}

fn record_accepted_scheduled_migration_tx<F>(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
    pending: &super::migration::DuePendingMigrationTx,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
    store_tx: F,
) -> Result<Option<IronwoodMigrationResult>, String>
where
    F: FnOnce(&str, WalletNetwork, &[u8]) -> Result<(), String>,
{
    if let Err(e) = store_tx(db_path, network, &pending.raw_tx) {
        let message =
            migration_storage_retry_message("Migration transaction", &pending.txid_hex, &e);
        log::warn!("migration: {message}");
        super::migration::mark_run_phase(
            db_path,
            run_id,
            super::migration::PHASE_BROADCAST_SCHEDULED,
            Some(&message),
        )?;
        let totals = super::migration::pending_totals_for_run(db_path, run_id)?;
        return Ok(Some(migration_result_from_pending_totals(
            totals,
            super::migration::PHASE_BROADCAST_SCHEDULED,
            Some(message),
            fallback_total_count,
            fallback_migrated_zatoshi,
        )));
    }

    super::migration::mark_pending_broadcasted(db_path, run_id, &pending.txid_hex)?;
    Ok(None)
}

fn migration_result_from_pending_totals(
    totals: super::migration::PendingMigrationTotals,
    status: &str,
    message: Option<String>,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
) -> IronwoodMigrationResult {
    IronwoodMigrationResult {
        txids: totals.txids.join(","),
        status: status.to_string(),
        broadcasted_count: totals.broadcasted_count,
        total_count: totals.total_count.max(fallback_total_count),
        message,
        fee_zatoshi: totals.fee_zatoshi,
        migrated_zatoshi: totals.value_zatoshi.max(fallback_migrated_zatoshi),
    }
}

fn migration_result_from_split_broadcast(
    result: CreatedBroadcastResult,
    fallback_total_count: u32,
    fee_zatoshi: u64,
    migrated_zatoshi: u64,
) -> IronwoodMigrationResult {
    IronwoodMigrationResult {
        txids: result.txids,
        status: result.status.to_string(),
        broadcasted_count: result.broadcasted_count,
        total_count: fallback_total_count,
        message: result.message,
        fee_zatoshi,
        migrated_zatoshi,
    }
}

#[derive(Debug)]
struct CreatedBroadcastResult {
    txids: String,
    status: &'static str,
    broadcasted_count: u32,
    total_count: u32,
    message: Option<String>,
}

impl CreatedBroadcastResult {
    const BROADCASTED: &'static str = "broadcasted";
    const PENDING_BROADCAST: &'static str = "pending_broadcast";
    const PARTIAL_BROADCAST: &'static str = "partial_broadcast";
    fn into_execute_result(self) -> ExecuteProposalResult {
        ExecuteProposalResult {
            txids: self.txids,
            status: self.status.to_string(),
            broadcasted_count: self.broadcasted_count,
            total_count: self.total_count,
            message: self.message,
        }
    }

    fn into_shield_transparent_result(
        self,
        fee_zatoshi: u64,
        shielded_zatoshi: u64,
    ) -> ShieldTransparentResult {
        ShieldTransparentResult {
            txids: self.txids,
            status: self.status.to_string(),
            broadcasted_count: self.broadcasted_count,
            total_count: self.total_count,
            message: self.message,
            fee_zatoshi,
            shielded_zatoshi,
        }
    }
}

async fn broadcast_created_transactions(
    db_path: &str,
    lightwalletd_url: &str,
    txids: &[TxId],
    log_label: &str,
) -> CreatedBroadcastResult {
    let txid_strings: Vec<String> = txids.iter().map(|id| format!("{id}")).collect();
    let txids_joined = txid_strings.join(",");
    let total_count = txids.len() as u32;

    // Connect to lightwalletd once for all broadcasts.
    let mut client = match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
        Ok(client) => client,
        Err(e) => {
            let message =
                format!("Broadcast could not start after local transaction creation. Error: {e}");
            log::warn!("{log_label}: {message}");
            return CreatedBroadcastResult {
                txids: txids_joined,
                status: CreatedBroadcastResult::PENDING_BROADCAST,
                broadcasted_count: 0,
                total_count,
                message: Some(message),
            };
        }
    };

    let read_conn = match open_readonly_conn(db_path) {
        Ok(conn) => conn,
        Err(e) => {
            let message =
                format!("Failed to open DB for broadcast after local transaction creation: {e}");
            log::warn!("{log_label}: {message}");
            return CreatedBroadcastResult {
                txids: txids_joined,
                status: CreatedBroadcastResult::PENDING_BROADCAST,
                broadcasted_count: 0,
                total_count,
                message: Some(message),
            };
        }
    };

    let mut broadcast_ok: Vec<String> = Vec::new();
    for txid in txids.iter() {
        let raw_tx = match read_conn.query_row(
            "SELECT raw FROM transactions WHERE txid = ?1",
            rusqlite::params![txid.as_ref()],
            |row| row.get::<_, Vec<u8>>(0),
        ) {
            Ok(raw_tx) => raw_tx,
            Err(e) => {
                let message = format!(
                    "Failed to get raw tx for {txid} after local transaction creation: {e}"
                );
                log::warn!("{log_label}: {message}");
                return CreatedBroadcastResult {
                    txids: txids_joined,
                    status: if broadcast_ok.is_empty() {
                        CreatedBroadcastResult::PENDING_BROADCAST
                    } else {
                        CreatedBroadcastResult::PARTIAL_BROADCAST
                    },
                    broadcasted_count: broadcast_ok.len() as u32,
                    total_count,
                    message: Some(message),
                };
            }
        };

        match broadcast_raw_transaction(&mut client, &raw_tx).await {
            Ok(()) => {
                broadcast_ok.push(format!("{txid}"));
                log::info!("{log_label}: broadcast {txid} ({} bytes)", raw_tx.len());
            }
            Err(e) => {
                let message = format!(
                    "Broadcast failed after {}/{} txs sent ({}). Error: {e}",
                    broadcast_ok.len(),
                    txids.len(),
                    broadcast_ok.join(",")
                );
                log::warn!("{log_label}: {message}");
                return CreatedBroadcastResult {
                    txids: txids_joined,
                    status: if broadcast_ok.is_empty() {
                        CreatedBroadcastResult::PENDING_BROADCAST
                    } else {
                        CreatedBroadcastResult::PARTIAL_BROADCAST
                    },
                    broadcasted_count: broadcast_ok.len() as u32,
                    total_count,
                    message: Some(message),
                };
            }
        }
    }

    CreatedBroadcastResult {
        txids: txids_joined,
        status: CreatedBroadcastResult::BROADCASTED,
        broadcasted_count: total_count,
        total_count,
        message: None,
    }
}

/// Broadcast a raw transaction using an existing gRPC client.
async fn broadcast_raw_transaction(
    client: &mut zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient<tonic::transport::Channel>,
    raw_tx: &[u8],
) -> Result<(), String> {
    let resp = crate::wallet::sync_engine::send_transaction(client, raw_tx)
        .await
        .map_err(|e| format!("SendTransaction gRPC failed: {e}"))?;

    if let Some(error) = super::broadcast::send_response_rejection_error(&resp) {
        return Err(error);
    }

    Ok(())
}

// ======================== Auto-Resubmit ========================

/// Summary of a single [`resubmit_pending_transactions`] pass.
///
/// `attempted` counts the candidates pulled from the DB — one entry
/// per unmined, unexpired, outbound wallet transaction visible at
/// the requested height. `succeeded` is the subset where
/// lightwalletd accepted the broadcast (either on the first try or
/// the single retry). `failed` is everything else; per-tx failures
/// are always logged before being counted and never propagated up.
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct ResubmitStats {
    pub attempted: usize,
    pub succeeded: usize,
    pub failed: usize,
}

/// Auto-resubmit every wallet-created unmined, unexpired,
/// outbound transaction we still have bytes for.
///
/// Mirrors zcash-android-wallet-sdk's `resubmitUnminedTransactions`
/// behaviour:
///
///   * The candidate list comes from
///     [`crate::wallet::sync::transactions::get_resubmittable_txs`]
///     — the same SQL predicate the SDK uses
///     (`mined_height IS NULL AND (expiry_height = 0 OR expiry_height
///     > current_tip) AND account_balance_delta < 0`).
///   * Each failed broadcast retries exactly **once**, matching
///     `TRANSACTION_RESUBMIT_RETRIES = 1` in the SDK. After that we
///     log and move on rather than aborting the whole pass — a
///     single flaky tx must not stop us from retrying the others,
///     and the main sync loop is expected to call this helper
///     again at the next batch boundary.
///   * Errors from `get_resubmittable_txs` itself (DB open or
///     query failure) are logged and returned as an all-zero
///     `ResubmitStats`; resubmit is a best-effort background job,
///     never a fatal-to-sync operation.
///
/// # Cancellation
///
/// The helper takes a `should_exit` closure that reflects the
/// sync loop's cancel / mode-change condition. It is consulted:
///
///   * Before iterating the candidate list at all (so a cancel
///     arriving during `run_enhancement` aborts the resubmit pass
///     entirely without opening a single rebroadcast RPC).
///   * Before every individual candidate's first broadcast.
///   * Before the retry call for any candidate that failed on
///     its first attempt.
///
/// Codex adversarial-review finding 3: rebroadcast is an
/// irreversible network side effect, so the window between
/// "user pressed cancel" and "observer stops calling
/// `send_transaction`" needs to be as tight as we can make it
/// without introducing an extra await point between the RPC
/// response and the stats bump.
///
/// The caller owns the gRPC client. In the sync loop the same
/// client that downloaded the compact blocks is threaded straight
/// through, so auto-resubmit reuses the same connection.
///
/// Logging uses `log::info!` for the "broadcasting N txs" entry
/// and `log::warn!` for per-tx failures / retries so an operator
/// can grep the live-stream log for `resubmit:` and see what the
/// wallet is doing without enabling DEBUG everywhere.
pub(crate) async fn resubmit_pending_transactions<ShouldExit>(
    db_path: &str,
    client: &mut zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient<tonic::transport::Channel>,
    current_height: u32,
    should_exit: ShouldExit,
) -> ResubmitStats
where
    ShouldExit: Fn() -> bool,
{
    if should_exit() {
        log::info!("resubmit: cancel observed before candidate query, skipping pass");
        return ResubmitStats::default();
    }

    let candidates = match super::transactions::get_resubmittable_txs(db_path, current_height) {
        Ok(c) => c,
        Err(e) => {
            log::warn!(
                "resubmit: failed to query resubmittable txs at height {current_height}: {e}",
            );
            return ResubmitStats::default();
        }
    };

    if candidates.is_empty() {
        return ResubmitStats::default();
    }

    log::info!(
        "resubmit: broadcasting {} unmined tx(s) at height {current_height}",
        candidates.len(),
    );

    let mut stats = ResubmitStats {
        attempted: candidates.len(),
        succeeded: 0,
        failed: 0,
    };

    for tx in &candidates {
        // Cancel-check at the top of every iteration: this is
        // the tightest window we can afford between "user pressed
        // cancel" and "we stop sending more transactions". The
        // pass so far is already committed to the wire, but we
        // at least stop initiating new ones.
        if should_exit() {
            log::info!(
                "resubmit: cancel observed mid-pass, stopping at {}/{} attempted",
                stats.succeeded + stats.failed,
                stats.attempted,
            );
            break;
        }

        let txid_hex = hex::encode(&tx.txid_bytes);
        match broadcast_raw_transaction(client, &tx.raw_tx).await {
            Ok(()) => {
                log::info!(
                    "resubmit: {txid_hex} ok (expiry={}, bytes={})",
                    tx.expiry_height,
                    tx.raw_tx.len(),
                );
                stats.succeeded += 1;
            }
            Err(first_err) => {
                // One retry, matching zcash-android-wallet-sdk's
                // `TRANSACTION_RESUBMIT_RETRIES = 1`. Check
                // cancel *before* the retry too — a user who hit
                // stop during the first-attempt gRPC round-trip
                // shouldn't see us immediately fire a second
                // round-trip for the same tx.
                log::warn!("resubmit: {txid_hex} first attempt failed: {first_err}");
                if should_exit() {
                    log::info!(
                        "resubmit: cancel observed before {txid_hex} retry; \
                         counting as failure and stopping pass",
                    );
                    stats.failed += 1;
                    break;
                }
                match broadcast_raw_transaction(client, &tx.raw_tx).await {
                    Ok(()) => {
                        log::info!("resubmit: {txid_hex} ok on retry");
                        stats.succeeded += 1;
                    }
                    Err(retry_err) => {
                        log::warn!(
                            "resubmit: {txid_hex} retry failed: {retry_err} \
                             (will try again next scan batch)",
                        );
                        stats.failed += 1;
                    }
                }
            }
        }
    }

    log::info!(
        "resubmit: pass complete — {} succeeded, {} failed of {} attempted",
        stats.succeeded,
        stats.failed,
        stats.attempted,
    );

    stats
}

/// ZIP-317 change-strategy / input-selector factory used by both
/// `propose_send` and `estimate_fee`. Keeps the configuration
/// (Orchard-preferred change, minimum 0.1 ZEC output split) in one
/// place so the two entry points can't drift.
fn zip317_helper<DbT: InputSource>(
    change_memo: Option<MemoBytes>,
    proposed_tx_version: Option<TxVersion>,
    unpadded_orchard_pool_bundles: bool,
) -> (
    MultiOutputChangeStrategy<WalletFeeRule, DbT>,
    GreedyInputSelector<DbT>,
) {
    let change_strategy = MultiOutputChangeStrategy::new(
        ConservativeZip317FeeRule,
        change_memo,
        ShieldedProtocol::Orchard,
        DustOutputPolicy::default(),
        SplitPolicy::with_min_output_value(
            NonZeroUsize::new(4).unwrap(),
            Zatoshis::const_from_u64(1000_0000),
        ),
    );
    // Migration children only: count exactly the requested actions so the
    // proposal's fee matches the unpadded bundle the PCZT builder produces.
    let change_strategy = if unpadded_orchard_pool_bundles {
        change_strategy.with_unpadded_orchard_pool_bundles()
    } else {
        change_strategy
    };
    // No V5 legacy-change override is needed anymore: change-pool selection
    // follows the input pools (an Orchard-input V5 send yields Orchard change)
    // and enforces the Ironwood turnstile.
    let _ = proposed_tx_version;

    (change_strategy, GreedyInputSelector::new())
}

// ======================== No-op Sapling Provers ========================
// Used for Orchard-only transactions where Sapling params are not
// available. `create_proposed_transactions` only invokes the
// Sapling prover methods for proposals that actually contain a
// Sapling bundle, so for an Orchard-only proposal these methods
// should never be called. If they are called we log and fail noisily
// rather than producing a silently-invalid all-zero proof.

use sapling_crypto::{
    bundle::GrothProofBytes,
    circuit,
    keys::EphemeralSecretKey,
    prover::{OutputProver, SpendProver},
    value::{NoteValue, ValueCommitTrapdoor},
    Diversifier, MerklePath, PaymentAddress, ProofGenerationKey, Rseed,
};

const GROTH_PROOF_SIZE: usize = 192;

struct NoOpSpendProver;

impl SpendProver for NoOpSpendProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _proof_generation_key: ProofGenerationKey,
        _diversifier: Diversifier,
        _rseed: Rseed,
        _value: NoteValue,
        _alpha: jubjub::Fr,
        _rcv: ValueCommitTrapdoor,
        _anchor: bls12_381::Scalar,
        _merkle_path: MerklePath,
    ) -> Option<circuit::Spend> {
        log::error!(
            "NoOpSpendProver::prepare_circuit called — proposal contains unexpected Sapling spend"
        );
        None
    }

    fn create_proof<R: rand_core::RngCore>(
        &self,
        _circuit: circuit::Spend,
        _rng: &mut R,
    ) -> Self::Proof {
        log::error!("NoOpSpendProver::create_proof called — should never happen");
        [0u8; GROTH_PROOF_SIZE]
    }

    fn encode_proof(_proof: Self::Proof) -> GrothProofBytes {
        [0u8; GROTH_PROOF_SIZE]
    }
}

struct NoOpOutputProver;

impl OutputProver for NoOpOutputProver {
    type Proof = GrothProofBytes;

    fn prepare_circuit(
        _esk: &EphemeralSecretKey,
        _payment_address: PaymentAddress,
        _rcm: jubjub::Fr,
        _value: NoteValue,
        _rcv: ValueCommitTrapdoor,
    ) -> circuit::Output {
        log::error!(
            "NoOpOutputProver::prepare_circuit called — proposal contains unexpected Sapling output"
        );
        circuit::Output {
            value_commitment_opening: None,
            payment_address: None,
            commitment_randomness: None,
            esk: None,
        }
    }

    fn create_proof<R: rand_core::RngCore>(
        &self,
        _circuit: circuit::Output,
        _rng: &mut R,
    ) -> Self::Proof {
        log::error!("NoOpOutputProver::create_proof called — should never happen");
        [0u8; GROTH_PROOF_SIZE]
    }

    fn encode_proof(_proof: Self::Proof) -> GrothProofBytes {
        [0u8; GROTH_PROOF_SIZE]
    }
}

#[cfg(test)]
mod tests {
    use super::super::migration;
    use super::*;

    use incrementalmerkletree::Position;
    use transparent::bundle::{OutPoint, TxOut};
    use zcash_client_backend::{data_api::WalletWrite, wallet::WalletTransparentOutput};
    use zcash_keys::keys::{ReceiverRequirement, UnifiedSpendingKey};
    use zcash_protocol::consensus::BlockHeight;

    const MIGRATION_TEST_ACCOUNT: &str = "account-1";
    const MIGRATION_TEST_PASSWORD: &[u8] = b"correct horse battery staple";
    const MIGRATION_TEST_SALT: &str = "AQIDBAUGBwgJCgsMDQ4PEA==";

    fn taddr(seed: u8) -> TransparentAddress {
        TransparentAddress::PublicKeyHash([seed; 20])
    }

    fn balance(value: u64) -> Balance {
        let mut balance = Balance::ZERO;
        balance
            .add_spendable_value(Zatoshis::from_u64(value).unwrap())
            .unwrap();
        balance
    }

    fn receiver(value: u64, scope: TransparentKeyScope) -> (TransparentKeyOrigin, Balance) {
        (TransparentKeyOrigin::Derived { scope }, balance(value))
    }

    fn migration_test_plan() -> migration::DenominationPlan {
        migration::DenominationPlan {
            migration_outputs: vec![100_000],
            orchard_change: None,
            split_fee_zatoshi: 10_000,
            migration_fee_zatoshi: 10_000,
            total_input_zatoshi: 120_000,
            total_migratable_zatoshi: 100_000,
        }
    }

    fn migration_test_note(txid_hex: &str) -> migration::PreparedOrchardNoteRef {
        migration::PreparedOrchardNoteRef {
            txid_hex: txid_hex.to_string(),
            output_index: 0,
            value_zatoshi: 100_000,
            note_version: 2,
            nullifier_hex: None,
        }
    }

    #[test]
    fn missing_orchard_anchor_is_a_retryable_witness_error() {
        assert!(is_orchard_witness_not_ready_error(
            "Read Orchard witnesses: Proposal(AnchorNotFound(BlockHeight(509)))"
        ));
        assert!(!is_orchard_witness_not_ready_error(
            "Read Orchard witnesses: invalid note commitment"
        ));
    }

    fn migration_test_stage(
        input_txid_hex: &str,
        output_txid_hex: &str,
    ) -> migration::DenominationStageInsert {
        migration::DenominationStageInsert {
            stage_index: 0,
            base_pczt: vec![0xa0],
            sigs: Vec::new(),
            raw_tx: Some(vec![1, 2, 3, 4]),
            expected_txid_hex: output_txid_hex.to_string(),
            target_height: 90,
            expiry_height: 120,
            fee_zatoshi: 10_000,
            status: migration::DenominationStageStatus::Pending,
            inputs: vec![migration::DenominationStageInputRef {
                txid_hex: input_txid_hex.to_string(),
                output_index: 0,
                value_zatoshi: 120_000,
                note_version: 2,
                nullifier_hex: None,
            }],
            outputs: vec![migration::DenominationStageOutputRef {
                output_index: 0,
                value_zatoshi: 100_000,
                note_version: 2,
                kind: migration::DenominationStageOutputKind::Migration,
            }],
        }
    }

    #[test]
    fn parse_txid_hex_accepts_display_order_hex() {
        let txid_hex = "838813428b78712263511ed5c6fb9a108c939038a440b74f72bee6caedf602fd";
        let txid = parse_txid_hex(txid_hex).unwrap();

        assert_eq!(format!("{txid}"), txid_hex);
    }

    #[test]
    fn shield_result_preserves_pending_broadcast_status() {
        let result = CreatedBroadcastResult {
            txids: "abc123".to_string(),
            status: CreatedBroadcastResult::PENDING_BROADCAST,
            broadcasted_count: 0,
            total_count: 1,
            message: Some("Broadcast could not start".to_string()),
        }
        .into_shield_transparent_result(10_000, 90_000);

        assert_eq!(result.txids, "abc123");
        assert_eq!(result.status, CreatedBroadcastResult::PENDING_BROADCAST);
        assert_eq!(result.broadcasted_count, 0);
        assert_eq!(result.total_count, 1);
        assert_eq!(result.message.as_deref(), Some("Broadcast could not start"));
        assert_eq!(result.fee_zatoshi, 10_000);
        assert_eq!(result.shielded_zatoshi, 90_000);
    }

    #[test]
    fn migration_rebuilds_only_after_explicit_server_rejection() {
        assert!(migration_broadcast_failure_requires_rebuild(
            "Broadcast rejected: bad-txns-inputs-spent (code 18)"
        ));
        assert!(!migration_broadcast_failure_requires_rebuild(
            "SendTransaction gRPC failed: connection unavailable"
        ));
    }

    #[test]
    fn send_proposals_use_v6_after_nu6_3() {
        let network = WalletNetwork::Regtest;
        crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
        let v2_only = SelectedOrchardNoteVersions {
            has_v2: true,
            has_v3: false,
        };

        // Pass-1 ceiling: no explicit version before activation, V6 after.
        let before = proposed_tx_version_for_send(network, TargetHeight::from(1));
        let after = proposed_tx_version_for_send(network, TargetHeight::from(2));
        assert_eq!(before, None);
        assert_eq!(after, Some(TxVersion::V6));

        // The pass-2 decision keys off that ceiling: a V2-only selection with a
        // non-Orchard payment downgrades a post-activation V6 proposal, never a
        // pre-activation one.
        assert!(should_downgrade_send_to_legacy_v5(after, &v2_only, false));
        assert!(!should_downgrade_send_to_legacy_v5(before, &v2_only, false));
    }

    #[test]
    fn v5_downgrade_requires_v6_ceiling_and_v2_only_spends() {
        let versions = |has_v2, has_v3| SelectedOrchardNoteVersions { has_v2, has_v3 };

        // Canonical downgrade case: V6 ceiling, V2-only spends, non-Orchard
        // recipient.
        assert!(should_downgrade_send_to_legacy_v5(
            Some(TxVersion::V6),
            &versions(true, false),
            false,
        ));
        // Shielded-Orchard recipient: a legacy-V5 build would fail with
        // CrossAddressDisabled, so stay V6 even for V2-only spends.
        assert!(!should_downgrade_send_to_legacy_v5(
            Some(TxVersion::V6),
            &versions(true, false),
            true,
        ));
        // V3-only and mixed selections keep V6 (mixed keeps the V3 change).
        assert!(!should_downgrade_send_to_legacy_v5(
            Some(TxVersion::V6),
            &versions(false, true),
            false,
        ));
        assert!(!should_downgrade_send_to_legacy_v5(
            Some(TxVersion::V6),
            &versions(true, true),
            false,
        ));
        // No Orchard spends at all: nothing to preserve, keep V6.
        assert!(!should_downgrade_send_to_legacy_v5(
            Some(TxVersion::V6),
            &versions(false, false),
            false,
        ));
        // Pre-activation (no pass-1 ceiling) proposals are never rewritten.
        assert!(!should_downgrade_send_to_legacy_v5(
            None,
            &versions(true, false),
            false,
        ));
        assert!(!should_downgrade_send_to_legacy_v5(
            Some(TxVersion::V5),
            &versions(true, false),
            false,
        ));
    }

    /// Fabricates a transparent-recipient proposal spending one Orchard note
    /// per entry in `versions` (plus a lone Sapling note when `versions` is
    /// empty, so the proposal still has a shielded input), mirroring
    /// `transparent_recipient_send_max_proposal_spends_shielded_notes`.
    fn fabricated_shielded_spend_proposal(
        versions: &[orchard::note::NoteVersion],
    ) -> Proposal<WalletFeeRule, u32> {
        let network = WalletNetwork::Regtest;
        let orchard_notes = versions
            .iter()
            .enumerate()
            .map(|(index, version)| {
                let sk = orchard::keys::SpendingKey::from_bytes([7 + index as u8; 32]).unwrap();
                let fvk = orchard::keys::FullViewingKey::from(&sk);
                let recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
                let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
                let rseed = (0u8..=255)
                    .find_map(|b| {
                        orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option()
                    })
                    .expect("test rseed");
                let note = orchard::Note::from_parts(
                    recipient,
                    orchard::value::NoteValue::from_raw(100_000),
                    rho,
                    rseed,
                    *version,
                )
                .unwrap();
                ReceivedNote::from_parts(
                    index as u32,
                    TxId::from_bytes([index as u8; 32]),
                    0,
                    note,
                    zip32::Scope::External,
                    Position::from(index as u64),
                    Some(BlockHeight::from_u32(20)),
                    None,
                )
            })
            .collect::<Vec<_>>();
        let sapling_notes = if orchard_notes.is_empty() {
            let spending_key = sapling_crypto::zip32::ExtendedSpendingKey::master(&[7u8; 32]);
            let (_, recipient) = spending_key.default_address();
            let note = sapling_crypto::Note::from_parts(
                recipient,
                sapling_crypto::value::NoteValue::from_raw(100_000),
                sapling_crypto::Rseed::AfterZip212([3u8; 32]),
            );
            vec![ReceivedNote::from_parts(
                100u32,
                TxId::from_bytes([100u8; 32]),
                0,
                note,
                zip32::Scope::External,
                Position::from(0u64),
                Some(BlockHeight::from_u32(20)),
                None,
            )]
        } else {
            vec![]
        };
        let recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

        build_transparent_recipient_send_max_proposal_from_notes(
            network,
            TargetHeight::from(BlockHeight::from_u32(1_000)),
            BlockHeight::from_u32(900),
            recipient,
            None,
            ReceivedNotes::new(sapling_notes, orchard_notes, vec![]),
            ConservativeZip317FeeRule,
        )
        .expect("fabricated proposal should build")
    }

    /// Fabricates a single-step proposal that spends one V2 Orchard note and
    /// pays a recipient in `payment_pool`, so `payment_pools()` reflects the
    /// requested recipient pool. Used to exercise
    /// [`proposal_has_orchard_payment`] and the recipient-pool guard.
    fn fabricated_proposal_with_payment_pool(
        payment_pool: PoolType,
    ) -> Proposal<WalletFeeRule, u32> {
        let network = WalletNetwork::Regtest;
        let sk = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
        let fvk = orchard::keys::FullViewingKey::from(&sk);
        let orchard_recipient = fvk.address_at(0u32, orchard::keys::Scope::External);
        let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
        let rseed = (0u8..=255)
            .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
            .expect("test rseed");
        let note = orchard::Note::from_parts(
            orchard_recipient,
            orchard::value::NoteValue::from_raw(100_000),
            rho,
            rseed,
            orchard::note::NoteVersion::V2,
        )
        .unwrap();
        let received_note = ReceivedNote::from_parts(
            0u32,
            TxId::from_bytes([0u8; 32]),
            0,
            note,
            zip32::Scope::External,
            Position::from(0u64),
            Some(BlockHeight::from_u32(20)),
            None,
        );

        // Recipient address matches the requested payment pool.
        let to = match payment_pool {
            PoolType::Transparent => Address::Transparent(taddr(9)).to_zcash_address(&network),
            PoolType::Shielded(ShieldedProtocol::Orchard) => {
                let ua = zcash_keys::address::UnifiedAddress::from_receivers(
                    Some(orchard_recipient),
                    None,
                    None,
                )
                .expect("UA with an Orchard receiver is valid");
                Address::from(ua).to_zcash_address(&network)
            }
            PoolType::Shielded(ShieldedProtocol::Sapling) => {
                let esk = sapling_crypto::zip32::ExtendedSpendingKey::master(&[9u8; 32]);
                let (_, sapling_recipient) = esk.default_address();
                Address::from(sapling_recipient).to_zcash_address(&network)
            }
            PoolType::Shielded(ShieldedProtocol::Ironwood) => {
                unreachable!("this fixture never requests Ironwood payments")
            }
        };

        // No change: amount + fee must equal the single 100_000-zat input, or
        // `Proposal::single_step` rejects the unbalanced proposal.
        let fee = Zatoshis::const_from_u64(10_000);
        let amount = Zatoshis::const_from_u64(90_000);
        let payment = Payment::new(to, Some(amount), None, None, None, vec![]).unwrap();
        let request = TransactionRequest::new(vec![payment]).unwrap();
        // `ShieldedInputs` wants `ReceivedNote<_, wallet::Note>`; wrap the
        // orchard-typed note through `ReceivedNotes::into_vec` to get that form.
        let notes =
            ReceivedNotes::new(vec![], vec![received_note], vec![]).into_vec(&RetainAllNotes);
        let shielded_inputs =
            ShieldedInputs::from_parts(nonempty::NonEmpty::from_vec(notes).unwrap());
        let balance = TransactionBalance::new(vec![], fee).unwrap();

        Proposal::single_step(
            request,
            BTreeMap::from([(0usize, payment_pool)]),
            vec![],
            Some(shielded_inputs),
            BlockHeight::from_u32(900),
            balance,
            ConservativeZip317FeeRule,
            TargetHeight::from(BlockHeight::from_u32(1_000)),
            ConfirmationsPolicy::default(),
            false,
            false,
        )
        .expect("fabricated payment-pool proposal should build")
    }

    #[test]
    fn proposal_has_orchard_payment_detects_recipient_pool() {
        // Orchard recipient => Orchard payment.
        assert!(proposal_has_orchard_payment(
            &fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Orchard)),
        ));
        // Transparent recipient (Orchard change is not a payment pool) => none.
        assert!(!proposal_has_orchard_payment(
            &fabricated_proposal_with_payment_pool(PoolType::Transparent),
        ));
        // Sapling recipient => not an Orchard payment.
        assert!(!proposal_has_orchard_payment(
            &fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Sapling)),
        ));
        // Change-only send-max proposal (transparent recipient, Orchard spend)
        // has no Orchard payment pool either.
        assert!(!proposal_has_orchard_payment(
            &fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]),
        ));
    }

    #[test]
    fn orchard_recipient_v2_send_keeps_v6_without_rerun() {
        // V2-only spend paying a shielded-Orchard recipient: must stay V6 (a V5
        // build would fail with CrossAddressDisabled), and the re-proposal
        // closure must never run.
        let pass1 =
            fabricated_proposal_with_payment_pool(PoolType::Shielded(ShieldedProtocol::Orchard));

        let (_, tx_version) =
            propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |_| {
                panic!("re-proposal must not run for a shielded-Orchard recipient")
            });

        assert_eq!(tx_version, Some(TxVersion::V6));
    }

    #[test]
    fn transparent_recipient_v2_send_downgrades_to_v5() {
        // Contrast with the Orchard-recipient case: a transparent recipient with
        // the same V2-only spend downgrades to V5.
        let pass1 = fabricated_proposal_with_payment_pool(PoolType::Transparent);
        let rerun = fabricated_proposal_with_payment_pool(PoolType::Transparent);

        let (_, tx_version) =
            propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), move |requested| {
                assert_eq!(requested, Some(TxVersion::V5));
                Ok(rerun)
            });

        assert_eq!(tx_version, Some(TxVersion::V5));
    }

    #[test]
    fn proposal_selected_orchard_note_versions_detects_spent_versions() {
        use orchard::note::NoteVersion;

        let v2_only =
            proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
                NoteVersion::V2,
            ]));
        assert!(v2_only.has_v2 && !v2_only.has_v3);

        let v3_only =
            proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
                NoteVersion::V3,
            ]));
        assert!(!v3_only.has_v2 && v3_only.has_v3);

        let mixed =
            proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[
                NoteVersion::V2,
                NoteVersion::V3,
            ]));
        assert!(mixed.has_v2 && mixed.has_v3);

        // Sapling-only selection: no Orchard notes at all.
        let none =
            proposal_selected_orchard_note_versions(&fabricated_shielded_spend_proposal(&[]));
        assert!(!none.has_v2 && !none.has_v3);
    }

    #[test]
    fn v5_rerun_falls_back_to_v6_proposal_on_failure() {
        let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]);
        let pass1_fee = proposal_fee_zatoshi(&pass1);
        let rerun_calls = std::cell::Cell::new(0);

        let (proposal, tx_version) =
            propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |requested| {
                rerun_calls.set(rerun_calls.get() + 1);
                assert_eq!(requested, Some(TxVersion::V5));
                Err("simulated re-proposal failure".to_string())
            });

        // The failed downgrade keeps the pass-1 proposal under its V6 version.
        assert_eq!(rerun_calls.get(), 1);
        assert_eq!(tx_version, Some(TxVersion::V6));
        assert_eq!(proposal_fee_zatoshi(&proposal), pass1_fee);
    }

    #[test]
    fn v5_rerun_returns_reproposed_v5_proposal_on_success() {
        use orchard::note::NoteVersion;

        let pass1 = fabricated_shielded_spend_proposal(&[NoteVersion::V2]);
        let rerun = fabricated_shielded_spend_proposal(&[NoteVersion::V2, NoteVersion::V2]);

        let (proposal, tx_version) =
            propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), move |_| Ok(rerun));

        assert_eq!(tx_version, Some(TxVersion::V5));
        // The returned proposal is the re-proposed one (two spends, not one).
        let selected: Vec<_> = proposal
            .steps()
            .iter()
            .flat_map(|step| step.shielded_inputs().into_iter())
            .flat_map(|inputs| inputs.notes().iter())
            .collect();
        assert_eq!(selected.len(), 2);
    }

    #[test]
    fn v3_only_spends_keep_v6_without_rerun() {
        let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V3]);

        let (_, tx_version) =
            propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |_| {
                panic!("re-proposal must not run for a V3-only selection")
            });

        assert_eq!(tx_version, Some(TxVersion::V6));
    }

    // `estimate_send_max` deliberately quotes at the pass-1 V6 ceiling and does
    // NOT apply the V2->V5 downgrade, so the quoted max is always realizable by
    // `propose_send` (whose pass-1 is hard-gated at V6). A cheaper V5-priced max
    // would over-quote for V2-only wallets and fail `propose_send` with
    // InsufficientFunds. This test pins that policy: the same V2-only
    // transparent-recipient max proposal that send-max builds *would* be
    // downgraded by the shared decision, and the value send-max returns is the
    // V6-ceiling summary, unchanged by any downgrade.
    #[test]
    fn estimate_send_max_stays_at_v6_ceiling_for_v2_only_spends() {
        // The pass-1 proposal send-max builds for a V2-only spend to a
        // transparent recipient.
        let pass1 = fabricated_shielded_spend_proposal(&[orchard::note::NoteVersion::V2]);

        // The shared decision WOULD downgrade this (V6 ceiling, V2-only spends,
        // transparent recipient), confirming send-max is intentionally opting
        // out rather than the case being ineligible.
        assert!(should_downgrade_send_to_legacy_v5(
            Some(TxVersion::V6),
            &proposal_selected_orchard_note_versions(&pass1),
            proposal_has_orchard_payment(&pass1),
        ));

        // The value send-max returns is the V6-ceiling summary. Running the
        // shared downgrade helper here (as the removed code did) would have
        // produced a different, V5-priced result; send-max must return the
        // undowngraded V6 summary instead.
        let v6_summary = summarize_send_max_proposal(&pass1).unwrap();
        let (downgraded, downgraded_version) =
            propose_with_note_version_downgrade(pass1, Some(TxVersion::V6), |tx_version| {
                assert_eq!(tx_version, Some(TxVersion::V5));
                // Stand in for a cheaper V5 re-proposal so the two paths differ.
                Ok(fabricated_shielded_spend_proposal(&[
                    orchard::note::NoteVersion::V2,
                    orchard::note::NoteVersion::V2,
                ]))
            });
        // Sanity: the downgrade path really does diverge from what send-max
        // returns (different selection/amount), so the assertion below is
        // meaningful rather than vacuous.
        assert_eq!(downgraded_version, Some(TxVersion::V5));
        assert_ne!(
            summarize_send_max_proposal(&downgraded)
                .unwrap()
                .amount_zatoshi,
            v6_summary.amount_zatoshi,
        );
    }

    #[test]
    fn keystone_transparent_shielding_pczt_targets_ironwood() {
        crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let network = WalletNetwork::Regtest;
        let mnemonic = crate::wallet::keys::generate_mnemonic();
        let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
        let (account_uuid, _) = crate::wallet::keys::init_db_and_create_account(
            db_path,
            network,
            &seed,
            Some(1),
            "shield",
        )
        .unwrap();
        let account_id = parse_account_uuid(&account_uuid).unwrap();

        let mut db = open_wallet_db(db_path, network).unwrap();
        let tip = BlockHeight::from_u32(120);
        db.update_chain_tip(tip).unwrap();
        // Shielding now derives the target/anchor heights from scan progress
        // (shard-tree checkpoints) rather than the raw chain tip; checkpoint
        // the empty Orchard tree at the tip to stand in for a scan.
        {
            type CheckpointError = WalletError<
                (),
                commitment_tree::Error,
                (),
                <ConservativeZip317FeeRule as FeeRule>::Error,
                (),
                ReceivedNoteId,
            >;
            let result: Result<_, CheckpointError> =
                db.with_sapling_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
            assert!(result.unwrap(), "checkpointing the empty Sapling tree");
            let result: Result<_, CheckpointError> =
                db.with_orchard_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
            assert!(result.unwrap(), "checkpointing the empty Orchard tree");
            let result: Result<_, CheckpointError> =
                db.with_ironwood_tree_mut(|tree| Ok(tree.checkpoint(tip)?));
            result.unwrap();
        }

        let ua_request = zcash_keys::keys::UnifiedAddressRequest::custom(
            ReceiverRequirement::Require,
            ReceiverRequirement::Require,
            ReceiverRequirement::Require,
        )
        .unwrap();
        // Use the account's existing default address (no allocation) so the test
        // setup doesn't trip the transparent gap limit on a fresh account.
        let ua = db
            .get_last_generated_address_matching(account_id, ua_request)
            .unwrap()
            .unwrap();
        let taddr = *ua.transparent().unwrap();
        let outpoint = OutPoint::new([42u8; 32], 0);
        let txout = TxOut::new(Zatoshis::const_from_u64(1_000_000), taddr.script().into());
        let utxo =
            WalletTransparentOutput::from_parts(outpoint, txout, Some(tip), None, None, None)
                .unwrap();
        db.put_received_transparent_utxo(&utxo).unwrap();
        drop(db);

        let result = create_shield_transparent_pczt(db_path, network, &account_uuid).unwrap();
        let pczt = pczt::Pczt::parse(&result.pczt_bytes).unwrap();

        assert_eq!(
            *pczt.global().tx_version(),
            zcash_protocol::constants::V6_TX_VERSION
        );
        assert!(!pczt.ironwood().actions().is_empty());
        assert!(pczt.orchard().actions().is_empty());
        assert_eq!(result.needs_sapling_params, false);
        assert!(result.fee_zatoshi > 0);
        assert!(result.shielded_zatoshi > 0);
    }

    #[test]
    fn split_broadcast_result_preserves_status_and_migrated_amount() {
        let result = migration_result_from_split_broadcast(
            CreatedBroadcastResult {
                txids: "abc123,def456".to_string(),
                status: CreatedBroadcastResult::PARTIAL_BROADCAST,
                broadcasted_count: 1,
                total_count: 2,
                message: Some("Only one transaction broadcast".to_string()),
            },
            7,
            20_000,
            180_000,
        );

        assert_eq!(result.txids, "abc123,def456");
        assert_eq!(result.status, CreatedBroadcastResult::PARTIAL_BROADCAST);
        assert_eq!(result.broadcasted_count, 1);
        assert_eq!(result.total_count, 7);
        assert_eq!(
            result.message.as_deref(),
            Some("Only one transaction broadcast")
        );
        assert_eq!(result.fee_zatoshi, 20_000);
        assert_eq!(result.migrated_zatoshi, 180_000);
    }

    #[test]
    fn scheduled_storage_failure_after_acceptance_leaves_tx_scheduled() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let denomination_input_txid =
            "303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f";
        let selected_note_txid = "101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f";
        let pending_txid = "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f";
        let selected_note = migration_test_note(selected_note_txid);
        let plan = migration_test_plan();
        let run_id = migration::create_run_with_staged_denominations_and_signed_children(
            &db_path,
            MIGRATION_TEST_ACCOUNT,
            WalletNetwork::Test,
            &plan,
            &[selected_note.clone()],
            Vec::new(),
            vec![migration_test_stage(
                denomination_input_txid,
                selected_note_txid,
            )],
            MIGRATION_TEST_PASSWORD,
            MIGRATION_TEST_SALT,
        )
        .unwrap();
        migration::insert_pending_txs(
            &db_path,
            &run_id,
            vec![migration::PendingMigrationTxInsert {
                txid_hex: pending_txid.to_string(),
                raw_tx: vec![5, 6, 7, 8],
                target_height: 100,
                anchor_boundary_height: None,
                expiry_height: 120,
                value_zatoshi: 100_000,
                fee_zatoshi: 10_000,
                selected_note: selected_note.clone(),
                metadata: migration::PendingMigrationTxMetadata {
                    tx_kind: "migration".to_string(),
                    funding_account_uuid: MIGRATION_TEST_ACCOUNT.to_string(),
                    selected_note,
                },
            }],
            MIGRATION_TEST_PASSWORD,
            MIGRATION_TEST_SALT,
        )
        .unwrap();
        let pending = migration::DuePendingMigrationTx {
            txid_hex: pending_txid.to_string(),
            raw_tx: vec![5, 6, 7, 8],
        };

        let result = record_accepted_scheduled_migration_tx(
            &db_path,
            WalletNetwork::Test,
            &run_id,
            &pending,
            1,
            100_000,
            |_db_path, _network, _raw_tx| Err("db busy".to_string()),
        )
        .unwrap()
        .unwrap();

        assert_eq!(result.txids, pending_txid);
        assert_eq!(result.status, migration::PHASE_BROADCAST_SCHEDULED);
        assert_eq!(result.broadcasted_count, 0);
        assert_eq!(result.total_count, 1);
        assert_eq!(result.fee_zatoshi, 10_000);
        assert_eq!(result.migrated_zatoshi, 100_000);
        let message = result.message.as_deref().unwrap();
        assert!(message.contains("accepted by lightwalletd"));
        assert!(message.contains("Vizor will retry"));
        assert_eq!(
            migration::scheduled_pending_count(&db_path, &run_id).unwrap(),
            1
        );
        assert_eq!(
            migration::pending_totals_for_run(&db_path, &run_id)
                .unwrap()
                .broadcasted_count,
            0
        );
        let active =
            migration::active_migration_run(&db_path, MIGRATION_TEST_ACCOUNT, WalletNetwork::Test)
                .unwrap()
                .unwrap();
        assert_eq!(active.phase, migration::PHASE_BROADCAST_SCHEDULED);
        assert_eq!(active.last_error.as_deref(), Some(message));

        let result = record_accepted_scheduled_migration_tx(
            &db_path,
            WalletNetwork::Test,
            &run_id,
            &pending,
            1,
            100_000,
            |_db_path, _network, _raw_tx| Ok(()),
        )
        .unwrap();

        assert!(result.is_none());
        assert_eq!(
            migration::scheduled_pending_count(&db_path, &run_id).unwrap(),
            0
        );
        assert_eq!(
            migration::pending_totals_for_run(&db_path, &run_id)
                .unwrap()
                .broadcasted_count,
            1
        );
        let active =
            migration::active_migration_run(&db_path, MIGRATION_TEST_ACCOUNT, WalletNetwork::Test)
                .unwrap()
                .unwrap();
        assert_eq!(
            active.phase,
            migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS
        );
        assert_eq!(active.last_error, None);
    }

    #[test]
    fn migration_child_bundle_shape_and_fee_are_two_plus_one() {
        let orchard_actions = orchard::builder::BundleType::DEFAULT
            .num_actions(
                orchard::bundle::BundleVersion::orchard_v3().default_flags(),
                1,
                0,
            )
            .unwrap();
        let ironwood_actions = orchard::builder::BundleType::UNPADDED
            .num_actions(
                orchard::bundle::BundleVersion::ironwood_v3().default_flags(),
                0,
                1,
            )
            .unwrap();

        assert_eq!(orchard_actions, MIGRATION_ORCHARD_ACTION_COUNT);
        assert_eq!(ironwood_actions, MIGRATION_IRONWOOD_ACTION_COUNT);

        let fee = ConservativeZip317FeeRule
            .fee_required(
                &WalletNetwork::Regtest,
                BlockHeight::from_u32(120),
                std::iter::empty::<TransparentInputSize>(),
                std::iter::empty::<usize>(),
                0,
                0,
                orchard_actions,
                ironwood_actions,
            )
            .unwrap();
        assert_eq!(u64::from(fee), 15_000);
    }

    #[test]
    fn conservative_zip317_fee_rule_clamps_known_transparent_inputs_to_p2pkh_size() {
        let network = WalletNetwork::Regtest;
        let height = BlockHeight::from_u32(1_000);
        let undersized_inputs = vec![
            TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
            TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
            TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE - 50),
        ];
        let standard_inputs = vec![
            TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
            TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
            TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE),
        ];

        let conservative_fee = ConservativeZip317FeeRule
            .fee_required(
                &network,
                height,
                undersized_inputs.clone(),
                std::iter::empty::<usize>(),
                0,
                0,
                0,
                0,
            )
            .unwrap();
        let standard_p2pkh_fee = StandardFeeRule::Zip317
            .fee_required(
                &network,
                height,
                standard_inputs,
                std::iter::empty::<usize>(),
                0,
                0,
                0,
                0,
            )
            .unwrap();
        let standard_undersized_fee = StandardFeeRule::Zip317
            .fee_required(
                &network,
                height,
                undersized_inputs,
                std::iter::empty::<usize>(),
                0,
                0,
                0,
                0,
            )
            .unwrap();

        assert_eq!(conservative_fee, standard_p2pkh_fee);
        assert_eq!(u64::from(conservative_fee), 15_000);
        assert_eq!(u64::from(standard_undersized_fee), 10_000);
    }

    /// Builds a real IO-finalized v6 Orchard split PCZT, shared by the version and
    /// signer-redaction tests below. Every action's spend is wallet-controlled (the
    /// real spend plus the fabricated zero-value spend paired with the change
    /// output), so all of them carry the wallet `fvk` on the wire and are signable
    /// with the returned spending key.
    fn built_v6_split_pczt() -> (BuiltPczt, orchard::keys::SpendingKey) {
        crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
        let network = WalletNetwork::Regtest;
        let target_height = 120;
        let sk = orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap();
        let fvk = orchard::keys::FullViewingKey::from(&sk);
        let recipient_scope = orchard::keys::Scope::Internal;
        let recipient = fvk.address_at(0u32, recipient_scope);
        let internal_ovk = Some(fvk.to_ovk(recipient_scope));
        let memo = MemoBytes::empty();
        let output_value = 100_000;
        let fee_rule = ConservativeZip317FeeRule;

        let build_builder = |input_value| {
            let rho = orchard::note::Rho::from_bytes(&[1; 32]).unwrap();
            let rseed = (0u8..=255)
                .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
                .expect("test rseed");
            let note = orchard::Note::from_parts(
                recipient,
                orchard::value::NoteValue::from_raw(input_value),
                rho,
                rseed,
                orchard::note::NoteVersion::V2,
            )
            .unwrap();
            let merkle_path = dummy_orchard_merkle_path().unwrap();
            let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
            let orchard_anchor = merkle_path.root(cmx);

            make_orchard_split_builder_with_type(
                network,
                target_height,
                orchard_anchor,
                &[(note, merkle_path)],
                &fvk,
                internal_ovk.clone(),
                recipient,
                &[output_value],
                &memo,
                orchard::builder::BundleType::DEFAULT,
            )
        };

        let fee = build_builder(1_000_000)
            .unwrap()
            .get_fee(&fee_rule)
            .unwrap();
        let builder = build_builder(output_value + u64::from(fee)).unwrap();
        let build_result = builder.build_for_pczt(rand_core::OsRng, &fee_rule).unwrap();

        assert_eq!(build_result.pczt_parts.version, TxVersion::V6);
        let built_pczt = pczt_from_build_result(build_result, network, None, 1, 1).unwrap();
        (built_pczt, sk)
    }

    #[test]
    fn orchard_denomination_split_pczt_uses_v6_for_change_outputs() {
        let (built_pczt, _sk) = built_v6_split_pczt();
        crate::wallet::sync::pczt::redact_pczt_for_signer(&built_pczt.bytes).unwrap();
    }

    #[test]
    fn padded_denomination_split_builds_exactly_sixteen_actions() {
        crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
        let network = WalletNetwork::Regtest;
        let target_height = 120;
        let usk =
            UnifiedSpendingKey::from_seed(&network, &[9; 32], zip32::AccountId::ZERO).unwrap();
        let fvk = orchard::keys::FullViewingKey::from(usk.orchard());
        let recipient_scope = orchard::keys::Scope::Internal;
        let recipient = fvk.address_at(0u32, recipient_scope);
        let internal_ovk = Some(fvk.to_ovk(recipient_scope));
        let memo = MemoBytes::empty();
        let outputs = vec![100_000u64; 10];
        let fee_rule = ConservativeZip317FeeRule;
        let bundle_type = orchard::builder::BundleType::Transactional {
            bundle_required: false,
            pad_to_minimum: Some(16),
        };

        let build_builder = |input_value| {
            let rho = orchard::note::Rho::from_bytes(&[2; 32]).unwrap();
            let rseed = (0u8..=255)
                .find_map(|b| orchard::note::RandomSeed::from_bytes([b; 32], &rho).into_option())
                .expect("test rseed");
            let note = orchard::Note::from_parts(
                recipient,
                orchard::value::NoteValue::from_raw(input_value),
                rho,
                rseed,
                orchard::note::NoteVersion::V2,
            )
            .unwrap();
            let merkle_path = dummy_orchard_merkle_path().unwrap();
            let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
            let anchor = merkle_path.root(cmx);
            make_orchard_split_builder_with_type(
                network,
                target_height,
                anchor,
                &[(note, merkle_path)],
                &fvk,
                internal_ovk.clone(),
                recipient,
                &outputs,
                &memo,
                bundle_type,
            )
        };

        let fee = build_builder(2_000_000)
            .unwrap()
            .get_fee(&fee_rule)
            .unwrap();
        assert_eq!(u64::from(fee), 80_000);
        let input_value = outputs.iter().sum::<u64>() + u64::from(fee);
        let build_result = build_builder(input_value)
            .unwrap()
            .build_for_pczt(rand_core::OsRng, &fee_rule)
            .unwrap();
        assert_eq!(
            build_result
                .pczt_parts
                .orchard
                .as_ref()
                .unwrap()
                .actions()
                .len(),
            16
        );
        let built = pczt_from_build_result(build_result, network, None, 1, outputs.len()).unwrap();
        assert_eq!(
            pczt::Pczt::parse(&built.bytes)
                .unwrap()
                .orchard()
                .actions()
                .len(),
            16
        );
        assert_eq!(built.orchard_spend_action_indices.len(), 11);

        let signed = sign_orchard_migration_pczt_with_usk(
            &built.bytes,
            &built.orchard_spend_action_indices,
            &usk,
        )
        .unwrap();
        let sigs = crate::wallet::sync::pczt::extract_required_compact_sigs_from_signed_pczt(
            &built.bytes,
            &signed,
        )
        .unwrap();
        assert_eq!(sigs.len(), 11);
        crate::wallet::sync::pczt::preflight_orchard_spend_auth_signatures(&built.bytes, &sigs)
            .unwrap();
    }

    #[test]
    fn transparent_recipient_send_max_proposal_spends_shielded_notes() {
        let network = WalletNetwork::Regtest;
        let input_value = 60_000u64;
        let spending_key = sapling_crypto::zip32::ExtendedSpendingKey::master(&[7u8; 32]);
        let (_, recipient) = spending_key.default_address();
        let note = sapling_crypto::Note::from_parts(
            recipient,
            sapling_crypto::value::NoteValue::from_raw(input_value),
            sapling_crypto::Rseed::AfterZip212([3u8; 32]),
        );
        let received_note = ReceivedNote::from_parts(
            1u32,
            TxId::from_bytes([4u8; 32]),
            0,
            note,
            zip32::Scope::External,
            Position::from(0u64),
            Some(BlockHeight::from_u32(20)),
            None,
        );
        let recipient = Address::Transparent(taddr(9)).to_zcash_address(&network);

        let proposal = build_transparent_recipient_send_max_proposal_from_notes(
            network,
            TargetHeight::from(BlockHeight::from_u32(1_000)),
            BlockHeight::from_u32(900),
            recipient,
            None,
            ReceivedNotes::new(vec![received_note], vec![], vec![]),
            ConservativeZip317FeeRule,
        )
        .expect("transparent-recipient send-max should build from shielded notes");

        let step = proposal.steps().iter().next().unwrap();
        assert_eq!(step.payment_pools().get(&0), Some(&PoolType::TRANSPARENT));
        assert_eq!(step.transparent_inputs().len(), 0);
        assert_eq!(step.shielded_inputs().unwrap().notes().len(), 1);

        let estimate = summarize_send_max_proposal(&proposal).unwrap();
        assert_eq!(estimate.amount_zatoshi + estimate.fee_zatoshi, input_value);
        assert!(estimate.fee_zatoshi > 0);
        assert!(estimate.needs_sapling_params);
    }

    #[test]
    fn batch_signer_redaction_compacts_and_preserves_signable_spends() {
        use pczt::roles::redactor::Redactor;
        use pczt::roles::signer::Signer;

        let (built_pczt, _) = built_v6_split_pczt();
        let request_bytes = built_pczt.bytes.clone();
        let request = pczt::Pczt::parse(&request_bytes).unwrap();
        let mut has_unsigned_zero_value_spend = false;
        pczt::roles::verifier::Verifier::new(request.clone())
            .with_orchard::<Infallible, _>(|bundle| {
                has_unsigned_zero_value_spend = bundle.actions().iter().any(|action| {
                    action
                        .spend()
                        .value()
                        .as_ref()
                        .is_some_and(|value| value.inner() == 0)
                        && action.spend().spend_auth_sig().is_none()
                });
                Ok(())
            })
            .unwrap();
        assert!(has_unsigned_zero_value_spend);

        let standard = crate::wallet::sync::pczt::redact_pczt_for_signer(&request_bytes).unwrap();
        let batch =
            crate::wallet::sync::pczt::redact_pczt_for_batch_signer(&request_bytes).unwrap();
        assert_eq!(batch, built_pczt.redacted_bytes);

        let batch_parsed = pczt::Pczt::parse(&batch).unwrap();
        for index in 0..batch_parsed.orchard().actions().len() {
            let without_alpha = Redactor::new(batch_parsed.clone())
                .redact_orchard_with(|mut r| {
                    r.redact_action(index, |mut ar| ar.clear_spend_alpha());
                })
                .finish()
                .serialize()
                .unwrap();
            assert_ne!(
                without_alpha, batch,
                "every wallet-controlled split spend must retain alpha",
            );
        }

        // The batch redaction additionally applies the compact-format elisions
        // (cv_net, decryptable ciphertexts as memo plaintext, bundle bsk and
        // anchor), so it must be meaningfully smaller than the standard signer
        // redaction.
        assert!(
            batch.len() + 1_000 < standard.len(),
            "batch redaction should elide compact-format fields ({} vs {} bytes)",
            batch.len(),
            standard.len(),
        );
        // The v6 sighash does not commit to anchors.
        assert!(batch_parsed.orchard().anchor().is_none());
        // Every action sheds `cv_net`. A ciphertext rides as stripped memo
        // plaintext whenever the wire note fields can decrypt it; only a
        // dummy output's randomized ciphertext may fail that swap and stay
        // encrypted on the wire.
        for action in batch_parsed.orchard().actions() {
            assert!(action.cv_net().is_none());
            assert!(action.output().cmx().is_none());
            if matches!(
                action.output().enc_ciphertext(),
                pczt::orchard::EncCiphertext::Encrypted(_)
            ) {
                assert_eq!(*action.output().value(), Some(0));
            }
        }
        assert!(
            batch_parsed.orchard().actions().iter().any(|action| {
                matches!(
                    action.output().enc_ciphertext(),
                    pczt::orchard::EncCiphertext::MemoPlaintext(_)
                )
            }),
            "at least the real split output's ciphertext must ride as memo plaintext",
        );

        // The compact-format contract: resolving the elided fields reproduces
        // the original values byte-identically.
        let mut refilled = batch_parsed;
        refilled.resolve_fields().unwrap();
        for (reb, orig) in refilled
            .orchard()
            .actions()
            .iter()
            .zip(request.orchard().actions().iter())
        {
            assert_eq!(reb.cv_net(), orig.cv_net());
            assert_eq!(reb.output().cmx(), orig.output().cmx());
            assert_eq!(
                reb.output().enc_ciphertext(),
                orig.output().enc_ciphertext()
            );
        }
        assert_eq!(
            Signer::new(refilled).unwrap().shielded_sighash(),
            Signer::new(request).unwrap().shielded_sighash(),
        );

        // Guard that the fvk clear is not vacuous: re-clearing the fvk on the batch
        // redaction changes nothing (it was already cleared), while the standard
        // redaction still carries the wire fvks.
        let clear_fvks = |bytes: &[u8]| {
            let parsed = pczt::Pczt::parse(bytes).unwrap();
            Redactor::new(parsed)
                .redact_orchard_with(|mut r| {
                    r.redact_actions(|mut ar| {
                        ar.clear_spend_fvk();
                    });
                })
                .redact_ironwood_with(|mut r| {
                    r.redact_actions(|mut ar| {
                        ar.clear_spend_fvk();
                    });
                })
                .finish()
                .serialize()
                .unwrap()
        };
        assert_eq!(
            clear_fvks(&batch),
            batch,
            "batch redaction must already have cleared the wire spend fvks",
        );
        assert_ne!(
            clear_fvks(&standard),
            standard,
            "standard redaction must retain the wire spend fvks",
        );
    }

    #[test]
    #[ignore = "slow librustzcash transaction-construction regression (~100s); run explicitly when touching shielding transaction construction"]
    fn many_utxo_shielding_builds_with_conservative_zip317_fee() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let network = WalletNetwork::Regtest;
        let mnemonic = crate::wallet::keys::generate_mnemonic();
        let seed = crate::wallet::keys::mnemonic_to_seed(&mnemonic).unwrap();
        let (account_uuid, _) = crate::wallet::keys::init_db_and_create_account(
            db_path,
            network,
            &seed,
            Some(1),
            "repro",
        )
        .unwrap();
        let account_id = parse_account_uuid(&account_uuid).unwrap();

        let mut db = open_wallet_db(db_path, network).unwrap();
        let tip = BlockHeight::from_u32(1_000);
        db.update_chain_tip(tip).unwrap();

        let ua_request = zcash_keys::keys::UnifiedAddressRequest::custom(
            ReceiverRequirement::Require,
            ReceiverRequirement::Require,
            ReceiverRequirement::Require,
        )
        .unwrap();
        // Use the account's existing default address (no allocation) so the test
        // setup doesn't trip the transparent gap limit on a fresh account.
        let ua = db
            .get_last_generated_address_matching(account_id, ua_request)
            .unwrap()
            .unwrap();
        let taddr = *ua.transparent().unwrap();
        let value = Zatoshis::const_from_u64(1_000_000);

        for i in 0..322u32 {
            let mut txid = [0u8; 32];
            txid[..4].copy_from_slice(&i.to_le_bytes());
            txid[4..8].copy_from_slice(&0xfeed_beefu32.to_le_bytes());
            let outpoint = OutPoint::new(txid, 0);
            let txout = TxOut::new(value, taddr.script().into());
            let utxo =
                WalletTransparentOutput::from_parts(outpoint, txout, Some(tip), None, None, None)
                    .unwrap();
            db.put_received_transparent_utxo(&utxo).unwrap();
        }

        let shielding_threshold = Zatoshis::const_from_u64(SHIELDING_THRESHOLD_ZATOSHI);
        let (proposal, selected_value) =
            build_shielding_proposal(&mut db, network, account_id, shielding_threshold).unwrap();
        assert_eq!(u64::from(selected_value), 322_000_000);

        let seed = SecretVec::new(seed.expose_secret().to_vec());
        let usk =
            UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32::AccountId::ZERO)
                .unwrap();
        let spend_prover = NoOpSpendProver;
        let output_prover = NoOpOutputProver;
        let txids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &network,
            &spend_prover,
            &output_prover,
            &wallet::SpendingKeys::from_unified_spending_key(usk),
            OvkPolicy::Sender,
            &proposal,
        )
        .expect("many-UTXO shielding should build without a fee/change mismatch");
        let change_values = proposal
            .steps()
            .iter()
            .flat_map(|step| step.balance().proposed_change().iter())
            .map(|change| u64::from(change.value()).to_string())
            .collect::<Vec<_>>()
            .join(",");
        eprintln!(
            "repro fixed: utxos=322 selected={} proposal_fee={} proposed_shielded={} change_values=[{}] txids={:?}",
            u64::from(selected_value),
            proposal_fee_zatoshi(&proposal),
            proposal_shielded_zatoshi(&proposal),
            change_values,
            txids,
        );

        assert_eq!(txids.len(), 1);
        assert_eq!(proposal_fee_zatoshi(&proposal), 1_630_000);
        assert_eq!(proposal_shielded_zatoshi(&proposal), 320_370_000);
    }

    #[test]
    fn selects_fragmented_non_ephemeral_sources_by_aggregate_threshold() {
        let mut receivers = HashMap::new();
        receivers.insert(taddr(1), receiver(60_000, TransparentKeyScope::EXTERNAL));
        receivers.insert(taddr(2), receiver(50_000, TransparentKeyScope::INTERNAL));

        let threshold = Zatoshis::from_u64(100_000).unwrap();
        let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

        assert_eq!(addresses.len(), 2);
        assert_eq!(u64::from(total), 110_000);
    }

    #[test]
    fn rejects_non_ephemeral_sources_below_aggregate_threshold() {
        let mut receivers = HashMap::new();
        receivers.insert(taddr(1), receiver(40_000, TransparentKeyScope::EXTERNAL));
        receivers.insert(taddr(2), receiver(50_000, TransparentKeyScope::INTERNAL));

        let threshold = Zatoshis::from_u64(100_000).unwrap();
        let err = select_shielding_sources(receivers, threshold).unwrap_err();

        assert!(err.contains("No transparent funds available"));
    }

    #[test]
    fn selects_largest_ephemeral_source_only() {
        let mut receivers = HashMap::new();
        receivers.insert(taddr(1), receiver(110_000, TransparentKeyScope::EPHEMERAL));
        receivers.insert(taddr(2), receiver(150_000, TransparentKeyScope::EPHEMERAL));

        let threshold = Zatoshis::from_u64(100_000).unwrap();
        let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

        assert_eq!(addresses, vec![taddr(2)]);
        assert_eq!(u64::from(total), 150_000);
    }

    #[test]
    fn prefers_non_ephemeral_sources_over_ephemeral_sources() {
        let mut receivers = HashMap::new();
        receivers.insert(taddr(1), receiver(140_000, TransparentKeyScope::EPHEMERAL));
        receivers.insert(taddr(2), receiver(120_000, TransparentKeyScope::EXTERNAL));

        let threshold = Zatoshis::from_u64(100_000).unwrap();
        let (addresses, total) = select_shielding_sources(receivers, threshold).unwrap();

        assert_eq!(addresses, vec![taddr(2)]);
        assert_eq!(u64::from(total), 120_000);
    }
}
