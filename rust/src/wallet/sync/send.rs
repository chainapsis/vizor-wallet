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

use std::collections::{BTreeSet, HashMap, HashSet};
use std::convert::Infallible;
use std::num::NonZeroUsize;
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::Instant;

use rand::{rngs::OsRng, Rng};
use secrecy::{ExposeSecret, SecretVec};
use shardtree::error::{QueryError, ShardTreeError};
use transparent::{
    address::TransparentAddress, builder::TransparentSigningSet, bundle::OutPoint,
    keys::TransparentKeyScope,
};
use zcash_client_backend::data_api::wallet::input_selection::{GreedyInputSelector, InputSelector};
use zcash_client_backend::{
    data_api::{
        error::Error as WalletError,
        wallet::{
            self, create_proposed_transactions, propose_send_max_transfer, propose_shielding,
            ConfirmationsPolicy,
        },
        Account as _, AccountMeta, Balance, InputSource, MaxSpendMode, NoteFilter, ReceivedNotes,
        TargetValue, TransparentKeyOrigin, TransparentOutputFilter, WalletCommitmentTrees,
        WalletRead,
    },
    fees::{
        zip317::{MultiOutputChangeStrategy, Zip317FeeRule},
        DustOutputPolicy, SplitPolicy, StandardFeeRule,
    },
    proposal::{Proposal, ProposalError},
    wallet::{Note, OvkPolicy, ReceivedNote, WalletTransparentOutput},
    zip321::{Payment, TransactionRequest},
};
use zcash_client_sqlite::{wallet::commitment_tree, AccountUuid, ReceivedNoteId};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_primitives::transaction::TxVersion;
use zcash_primitives::transaction::{
    builder::{BuildConfig, Builder},
    fees::{
        transparent::InputSize as TransparentInputSize, zip317::P2PKH_STANDARD_INPUT_SIZE, FeeRule,
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

use crate::wallet::db::with_wallet_db_write_lock;
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

pub(crate) struct ReservedPcztBatchRequest {
    pub id: String,
    pub send_flow_id: String,
    pub to_address: String,
    pub amount_zatoshi: u64,
    pub memo: Option<String>,
}

pub(crate) struct ReservedPcztBatchItem {
    pub id: String,
    pub pczt_with_proofs: Vec<u8>,
    pub redacted_pczt: Vec<u8>,
    pub fee_zatoshi: u64,
    pub spend_nullifiers: Vec<String>,
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

pub(crate) struct KeystoneMigrationMessage {
    pub id: String,
    pub redacted_pczt: Vec<u8>,
}

pub(crate) struct KeystoneMigrationSigningRequest {
    pub request_id: String,
    pub messages: Vec<KeystoneMigrationMessage>,
    pub signing_batch_limit: u32,
}

pub(crate) struct KeystoneSignedMigrationMessage {
    pub id: String,
    pub signed_pczt: Vec<u8>,
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
static ACTIVE_IRONWOOD_MIGRATIONS: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
static KEYSTONE_DENOMINATION_REQUESTS: OnceLock<Mutex<HashMap<String, StoredDenominationPczt>>> =
    OnceLock::new();
static KEYSTONE_MIGRATION_REQUESTS: OnceLock<Mutex<HashMap<String, StoredMigrationPcztBatch>>> =
    OnceLock::new();
static KEYSTONE_SINGLE_QR_MIGRATION_REQUESTS: OnceLock<
    Mutex<HashMap<String, StoredSingleQrMigrationPczt>>,
> = OnceLock::new();

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

pub fn propose_send(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    send_flow_id: &str,
    to_address: &str,
    amount_zatoshi: u64,
    memo_str: Option<&str>,
    legacy_v5_pczt: bool,
) -> Result<ProposalResult, String> {
    use zcash_protocol::{PoolType, ShieldedProtocol as SP};

    if send_flow_id.is_empty() {
        return Err("Send flow id is required".to_string());
    }

    let proposed_tx_version = legacy_v5_pczt.then_some(TxVersion::V5);
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let request = build_send_request(to_address, amount_zatoshi, memo_str)?;
    let migration_locks = super::migration::locked_migration_note_refs(db_path, account_uuid)?;
    let proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &migration_locks,
        proposed_tx_version,
    )?;

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
            proposed_tx_version,
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

pub(crate) fn create_reserved_pczt_batch(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    requests: Vec<ReservedPcztBatchRequest>,
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<Vec<ReservedPcztBatchItem>, String> {
    use zcash_client_backend::data_api::wallet::create_pczt_from_proposal as zcb_create_pczt;

    if requests.is_empty() {
        return Err("Batch requires at least one request".to_string());
    }

    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let migration_locks = super::migration::locked_migration_note_refs(db_path, account_uuid)?;
    let mut reserved = BTreeSet::new();
    let mut items = Vec::with_capacity(requests.len());

    for request in requests {
        if request.id.is_empty() {
            return Err("Batch message id is required".to_string());
        }
        if request.send_flow_id.is_empty() {
            return Err(format!("Send flow id is required for {}", request.id));
        }

        let transaction_request = build_send_request(
            &request.to_address,
            request.amount_zatoshi,
            request.memo.as_deref(),
        )?;
        let proposal = propose_send_with_reserved_notes(
            &db,
            network,
            account_id,
            transaction_request,
            &reserved,
            &migration_locks,
            None,
        )
        .map_err(|e| format!("Proposal {} failed: {e}", request.id))?;

        for note_ref in proposal_selected_note_refs(&proposal) {
            reserved.insert(note_ref);
        }

        let fee_zatoshi = proposal_fee_zatoshi(&proposal);
        let pczt = with_wallet_db_write_lock("send.create_reserved_pczt_batch", || {
            let mut write_db = open_wallet_db(db_path, network)?;
            zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
                &mut write_db,
                &network,
                account_id,
                OvkPolicy::Sender,
                &proposal,
            )
            .map_err(|e| format!("Create PCZT {} failed: {e}", request.id))
        })?;
        let pczt_bytes = pczt.serialize();
        let spend_nullifiers = crate::wallet::keystone::pczt_spend_nullifiers(&pczt_bytes)?;
        let pczt_with_proofs =
            super::pczt::add_proofs_to_pczt(&pczt_bytes, spend_params_path, output_params_path)?;
        let redacted_pczt = super::pczt::redact_pczt_for_signer(&pczt_bytes)?;

        items.push(ReservedPcztBatchItem {
            id: request.id,
            pczt_with_proofs,
            redacted_pczt,
            fee_zatoshi,
            spend_nullifiers,
        });
    }

    Ok(items)
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
    legacy_v5_pczt: bool,
) -> Result<u64, String> {
    let proposed_tx_version = legacy_v5_pczt.then_some(TxVersion::V5);
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let request = build_send_request(to_address, amount_zatoshi, memo_str)?;
    let migration_locks = super::migration::locked_migration_note_refs(db_path, account_uuid)?;
    let proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &migration_locks,
        proposed_tx_version,
    )?;

    let fee: u64 = proposal
        .steps()
        .iter()
        .map(|step| u64::from(step.balance().fee_required()))
        .sum();

    Ok(fee)
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
    legacy_v5_pczt: bool,
) -> Result<SendMaxEstimateResult, String> {
    let proposed_tx_version = legacy_v5_pczt.then_some(TxVersion::V5);
    let mut db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let proposal = build_send_max_proposal(
        &mut db,
        network,
        account_id,
        to_address,
        memo_str,
        proposed_tx_version,
    )?;
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

/// Hardware transparent shielding is disabled until it can shield to Ironwood.
pub(crate) fn create_shield_transparent_pczt(
    _db_path: &str,
    _network: WalletNetwork,
    _account_uuid: &str,
) -> Result<ShieldTransparentPcztResult, String> {
    Err("Keystone transparent shielding is not available after NU7 yet.".to_string())
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
                None,
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
                        &stored.proposal,
                        None,
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
                        &stored.proposal,
                        None,
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

pub async fn migrate_orchard_to_ironwood(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    let migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;

    if let Some(run) = super::migration::active_migration_run(db_path, account_uuid, network)? {
        if super::migration::pending_prep_tx_for_run(
            db_path,
            &run.run_id,
            pending_password.as_slice(),
            pending_salt_base64,
        )?
        .is_some()
        {
            drop(seed);
            let prep_broadcast = broadcast_pending_migration_prep_tx(
                db_path,
                lightwalletd_url,
                network,
                &run.run_id,
                pending_password.as_slice(),
                pending_salt_base64,
            )
            .await?
            .ok_or("Migration prep transaction disappeared before broadcast")?;
            let result = migration_result_from_prep_broadcast(
                prep_broadcast,
                run.target_values_zatoshi.len() as u32,
                0,
                run.target_values_zatoshi.iter().sum(),
            );
            drop(migration_guard);
            return Ok(result);
        }

        if super::migration::pending_totals_for_run(db_path, &run.run_id)?.total_count == 0
            && super::migration::signed_child_pczt_count(db_path, &run.run_id)? > 0
        {
            drop(seed);
            if !run_may_finalize_presigned_migration_children(&run) {
                let result = prepared_notes_not_spendable_result(
                    run.target_values_zatoshi.len() as u32,
                    run.target_values_zatoshi.iter().sum(),
                );
                drop(migration_guard);
                return Ok(result);
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
                let result = prepared_notes_not_spendable_result(
                    run.target_values_zatoshi.len() as u32,
                    run.target_values_zatoshi.iter().sum(),
                );
                drop(migration_guard);
                return Ok(result);
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
        let action = prepare_active_migration_resume(
            db_path,
            network,
            account_uuid,
            run,
            seed,
            pending_password.as_slice(),
            pending_salt_base64,
        )?;
        let result = execute_active_migration_resume_action(
            action,
            db_path,
            lightwalletd_url,
            network,
            pending_password.as_slice(),
            pending_salt_base64,
        )
        .await;
        drop(migration_guard);
        return result;
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

    let split = prepared.split;
    let split_txid = format!("{}", split.txid);
    let run_id = super::migration::create_run_with_prepared_notes_and_signed_children(
        db_path,
        account_uuid,
        network,
        &split.plan,
        &split.migrated_outputs,
        true,
        prepared.signed_children,
        pending_password.as_slice(),
        pending_salt_base64,
        Some(&split_txid),
        Some(split.raw_tx.clone()),
    )?;

    let Some(broadcast) = broadcast_pending_migration_prep_tx(
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
            "Migration denomination split was staged without a prep transaction".to_string(),
        );
    };
    drop(migration_guard);

    Ok(migration_result_from_prep_broadcast(
        broadcast,
        split.migrated_outputs.len() as u32,
        u64::from(split.fee_amount),
        u64::from(split.total_migratable),
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

    let pending_totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
    let signed_child_count = super::migration::signed_child_pczt_count(db_path, &run.run_id)?;

    if let Some(prep_broadcast) = broadcast_pending_migration_prep_tx(
        db_path,
        lightwalletd_url,
        network,
        &run.run_id,
        pending_password.as_slice(),
        pending_salt_base64,
    )
    .await?
    {
        return Ok(migration_result_from_prep_broadcast(
            prep_broadcast,
            run.target_values_zatoshi.len() as u32,
            0,
            run.target_values_zatoshi.iter().sum(),
        ));
    }

    if pending_totals.total_count == 0 && signed_child_count > 0 {
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
        create_orchard_denomination_split_pczt(db_path, network, account_uuid)
    })?;
    let Some(split) = split else {
        return Err(
            "Create migration denominations failed: insufficient spendable Orchard funds"
                .to_string(),
        );
    };

    let request_id = new_keystone_migration_request_id("denominations");
    let message_id = "denominations".to_string();
    let worker_base_pczt = split.base_pczt.clone();
    let messages = vec![KeystoneMigrationMessage {
        id: message_id,
        redacted_pczt: split.redacted_pczt,
    }];
    validate_keystone_migration_messages(&messages)?;
    let mut request_store = keystone_denomination_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredDenominationPczt {
            account_uuid: account_uuid.to_string(),
            network,
            state: KeystoneMigrationRequestState::Proofing,
            pczt_with_proofs: None,
            proof_error: None,
            fee_zatoshi: split.fee_zatoshi,
            migrated_outputs: split.migrated_outputs,
            total_migratable_zatoshi: split.total_migratable_zatoshi,
            plan: split.plan,
        },
    );
    drop(request_store);
    spawn_denomination_proof_worker(request_id.clone(), worker_base_pczt);

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
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let signed_by_id = signed_migration_messages_by_id(request_id, signed_messages)?;
    let signed_pczt = signed_by_id
        .get("denominations")
        .ok_or("Keystone result did not include the denomination split")?;
    if signed_by_id.len() != 1 {
        return Err("Keystone denomination result contained unexpected messages".to_string());
    }
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
        let pczt_with_proofs = stored
            .pczt_with_proofs
            .clone()
            .ok_or("Keystone denomination proofs are not ready")?;
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredDenominationCompletion {
            pczt_with_proofs,
            fee_zatoshi: stored.fee_zatoshi,
            migrated_outputs: stored.migrated_outputs.clone(),
            total_migratable_zatoshi: stored.total_migratable_zatoshi,
            plan: stored.plan.clone(),
        }
    };

    let extracted_split = match super::pczt::extract_transaction_from_pczt(
        &stored.pczt_with_proofs,
        signed_pczt,
        None,
        None,
    ) {
        Ok(extracted) => extracted,
        Err(e) => {
            reset_denomination_request_after_failed_completion(request_id);
            return Err(e);
        }
    };

    let txid = extracted_split.txid.to_string();
    let prepared_refs = stored
        .migrated_outputs
        .iter()
        .map(|output| super::migration::PreparedOrchardNoteRef {
            txid_hex: txid.clone(),
            output_index: output.output_index,
            value_zatoshi: output.value_zatoshi,
            note_version: 2,
            nullifier_hex: None,
        })
        .collect::<Vec<_>>();

    let run_id = match super::migration::create_run_with_prepared_notes_and_prep_tx(
        db_path,
        account_uuid,
        network,
        &stored.plan,
        &prepared_refs,
        true,
        &txid,
        extracted_split.raw_tx,
        pending_password,
        pending_salt_base64,
    ) {
        Ok(run_id) => run_id,
        Err(e) => {
            reset_denomination_request_after_failed_completion(request_id);
            return Err(e);
        }
    };
    if let Ok(mut store) = keystone_denomination_requests().lock() {
        store.remove(request_id);
    }

    let Some(broadcast) = broadcast_pending_migration_prep_tx(
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
            "Migration denomination split was staged without a prep transaction".to_string(),
        );
    };

    Ok(migration_result_from_prep_broadcast(
        broadcast,
        prepared_refs.len() as u32,
        stored.fee_zatoshi,
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
        create_orchard_denomination_split_pczt(db_path, network, account_uuid)
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
        .checked_add(1)
        .ok_or("Keystone migration message count overflow")?;
    if total_messages > ZCASH_SIGN_BATCH_MAX_MESSAGES {
        return Err(format!(
            "Single Keystone migration signing supports at most {} migration notes, but this plan needs {}. Reduce the migration amount or use the staged flow.",
            ZCASH_SIGN_BATCH_MAX_MESSAGES - 1,
            split.predicted_notes.len()
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
    messages.push(KeystoneMigrationMessage {
        id: "denominations".to_string(),
        redacted_pczt: split.redacted_pczt,
    });
    messages.extend(
        child_messages
            .iter()
            .map(|message| KeystoneMigrationMessage {
                id: message.id.clone(),
                redacted_pczt: message.redacted_pczt.clone(),
            }),
    );
    validate_keystone_migration_messages(&messages)?;

    let split_base_pczt = split.base_pczt.clone();
    let mut request_store = keystone_single_qr_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredSingleQrMigrationPczt {
            account_uuid: account_uuid.to_string(),
            network,
            state: KeystoneMigrationRequestState::Proofing,
            split_pczt_with_proofs: None,
            proof_error: None,
            split_fee_zatoshi: split.fee_zatoshi,
            migrated_outputs: split.migrated_outputs,
            total_migratable_zatoshi: split.total_migratable_zatoshi,
            plan: split.plan,
            child_messages,
        },
    );
    drop(request_store);
    spawn_single_qr_split_proof_worker(request_id.clone(), split_base_pczt);

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
    let signed_split_pczt = signed_by_id
        .get("denominations")
        .ok_or("Keystone result did not include the denomination split")?;
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
            .checked_add(1)
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
        let split_pczt_with_proofs = stored
            .split_pczt_with_proofs
            .clone()
            .ok_or("Keystone denomination proofs are not ready")?;
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredSingleQrMigrationCompletion {
            split_pczt_with_proofs,
            split_fee_zatoshi: stored.split_fee_zatoshi,
            migrated_outputs: stored.migrated_outputs.clone(),
            total_migratable_zatoshi: stored.total_migratable_zatoshi,
            plan: stored.plan.clone(),
            child_messages: stored.child_messages.clone(),
        }
    };

    for child in &stored.child_messages {
        if !signed_by_id.contains_key(&child.id) {
            reset_single_qr_request_after_failed_completion(request_id);
            return Err(format!("Keystone result missing {}", child.id));
        }
    }

    let extracted_split = match super::pczt::extract_transaction_from_pczt(
        &stored.split_pczt_with_proofs,
        signed_split_pczt,
        None,
        None,
    ) {
        Ok(extracted) => extracted,
        Err(e) => {
            reset_single_qr_request_after_failed_completion(request_id);
            return Err(e);
        }
    };
    let txid = extracted_split.txid.to_string();
    let prepared_refs = stored
        .migrated_outputs
        .iter()
        .map(|output| super::migration::PreparedOrchardNoteRef {
            txid_hex: txid.clone(),
            output_index: output.output_index,
            value_zatoshi: output.value_zatoshi,
            note_version: 2,
            nullifier_hex: None,
        })
        .collect::<Vec<_>>();

    let finalize_result = (|| -> Result<String, String> {
        let signed_children = stored
            .child_messages
            .iter()
            .enumerate()
            .map(|(index, child)| {
                let selected_note = super::migration::PreparedOrchardNoteRef {
                    txid_hex: txid.clone(),
                    output_index: child.selected_note.output_index,
                    value_zatoshi: child.selected_note.value_zatoshi,
                    note_version: child.selected_note.note_version,
                    nullifier_hex: None,
                };
                let signed_pczt = signed_by_id
                    .get(&child.id)
                    .ok_or_else(|| format!("Keystone result missing {}", child.id))?
                    .clone();
                Ok(super::migration::SignedMigrationPcztInsert {
                    message_id: child.id.clone(),
                    child_index: index as u32,
                    base_pczt: child.base_pczt.clone(),
                    signed_pczt,
                    target_height: child.target_height,
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
        super::migration::create_run_with_prepared_notes_and_signed_children(
            db_path,
            account_uuid,
            network,
            &stored.plan,
            &prepared_refs,
            true,
            signed_children,
            pending_password,
            pending_salt_base64,
            Some(&txid),
            Some(extracted_split.raw_tx),
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

    let Some(broadcast) = broadcast_pending_migration_prep_tx(
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
            "Migration denomination split was staged without a prep transaction".to_string(),
        );
    };

    Ok(migration_result_from_prep_broadcast(
        broadcast,
        prepared_refs.len() as u32,
        stored.split_fee_zatoshi,
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
    let prepared_notes = super::migration::prepared_notes_for_run(db_path, &run.run_id)?;
    if prepared_notes.is_empty() {
        return Err("Migration run has no prepared denomination notes".to_string());
    }
    let mut pending_totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
    if pending_totals.total_count > 0
        && super::migration::clear_retriable_pending_txs(db_path, &run)?
    {
        pending_totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
    }
    if pending_totals.total_count > 0 {
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
    for (index, note_ref) in prepared_notes.iter().enumerate() {
        let pczt = match with_wallet_db_write_lock("send.migration.prepare_exact_note_pczt", || {
            create_orchard_to_ironwood_pczt_from_note(
                db_path,
                network,
                account_uuid,
                note_ref,
                (index + 1) as u32,
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
    if current_prepared != request_prepared {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Prepared migration notes changed before completion".to_string());
    }
    if super::migration::pending_totals_for_run(db_path, &run.run_id)?.total_count > 0 {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Migration transactions are already signed and scheduled".to_string());
    }

    let completion_result = (|| -> Result<super::migration::PendingMigrationTotals, String> {
        let mut pending_inserts = Vec::with_capacity(stored.messages.len());
        for message in stored.messages.clone() {
            let signed_pczt = signed_by_id
                .get(&message.id)
                .ok_or_else(|| format!("Keystone result missing {}", message.id))?;
            let extracted = super::pczt::extract_transaction_from_pczt(
                message
                    .pczt_with_proofs
                    .as_ref()
                    .ok_or("Keystone migration proof missing")?,
                signed_pczt,
                None,
                None,
            )?;
            pending_inserts.push(super::migration::PendingMigrationTxInsert {
                txid_hex: extracted.txid.to_string(),
                raw_tx: extracted.raw_tx,
                target_height: message.target_height,
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

        super::migration::insert_pending_txs(
            db_path,
            &stored.run_id,
            pending_inserts,
            pending_password,
            pending_salt_base64,
        )?;
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

// Returns a non-secret action for the async caller. Any software signing needed
// while resuming an active run happens before this function returns.
fn prepare_active_migration_resume(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run: super::migration::ActiveRun,
    seed: SecretVec<u8>,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<ActiveMigrationResumeAction, String> {
    let fallback_total_count = run.target_values_zatoshi.len() as u32;
    let fallback_migrated_zatoshi = run.target_values_zatoshi.iter().sum();

    if matches!(
        run.phase.as_str(),
        super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS
            | super::migration::PHASE_READY_TO_MIGRATE
            | super::migration::PHASE_FAILED_RECOVERABLE
    ) {
        let mut pending_totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
        if pending_totals.total_count > 0
            && super::migration::clear_retriable_pending_txs(db_path, &run)?
        {
            pending_totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
        }
        if pending_totals.total_count == 0 {
            let prepared_notes = super::migration::prepared_notes_for_run(db_path, &run.run_id)?;
            if prepared_notes.is_empty() {
                drop(seed);
                return Err("Migration run has no prepared denomination notes".to_string());
            }
            if !prepared_note_spend_metadata_is_available(db_path, &run.run_id)? {
                drop(seed);
                return Ok(ActiveMigrationResumeAction::Return(
                    prepared_notes_not_spendable_result(
                        fallback_total_count,
                        fallback_migrated_zatoshi,
                    ),
                ));
            }

            let pending =
                match with_wallet_db_write_lock("send.migration.create_exact_notes", move || {
                    let usk = derive_migration_usk(db_path, network, account_uuid, seed)?;
                    let mut pending = Vec::with_capacity(prepared_notes.len());
                    for note_ref in &prepared_notes {
                        let Some(tx) = create_orchard_to_ironwood_transaction_from_note(
                            db_path,
                            network,
                            &usk,
                            account_uuid,
                            note_ref,
                        )?
                        else {
                            return Ok(None);
                        };
                        pending.push(tx);
                    }
                    Ok::<_, String>(Some(pending))
                }) {
                    Ok(Some(pending)) => pending,
                    Ok(None) => {
                        mark_prepared_notes_waiting(db_path, &run.run_id)?;
                        return Ok(ActiveMigrationResumeAction::Return(
                            prepared_notes_not_spendable_result(
                                fallback_total_count,
                                fallback_migrated_zatoshi,
                            ),
                        ));
                    }
                    Err(e) if is_orchard_witness_not_ready_error(&e) => {
                        mark_prepared_notes_waiting(db_path, &run.run_id)?;
                        return Ok(ActiveMigrationResumeAction::Return(
                            prepared_notes_not_spendable_result(
                                fallback_total_count,
                                fallback_migrated_zatoshi,
                            ),
                        ));
                    }
                    Err(e) => return Err(e),
                };

            let pending_inserts = pending
                .iter()
                .map(|tx| super::migration::PendingMigrationTxInsert {
                    txid_hex: tx.txid_hex.clone(),
                    raw_tx: tx.raw_tx.clone(),
                    target_height: tx.target_height,
                    expiry_height: tx.expiry_height,
                    value_zatoshi: tx.migrated_zatoshi,
                    fee_zatoshi: tx.fee_zatoshi,
                    selected_note: tx.selected_note.clone(),
                    metadata: super::migration::PendingMigrationTxMetadata {
                        tx_kind: "migration".to_string(),
                        funding_account_uuid: account_uuid.to_string(),
                        selected_note: tx.selected_note.clone(),
                    },
                })
                .collect::<Vec<_>>();
            super::migration::insert_pending_txs(
                db_path,
                &run.run_id,
                pending_inserts,
                pending_password,
                pending_salt_base64,
            )?;
            let totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
            return Ok(ActiveMigrationResumeAction::Return(
                migration_result_from_pending_totals(
                    totals,
                    super::migration::PHASE_BROADCAST_SCHEDULED,
                    Some(
                        "Migration transactions were signed and scheduled for delayed broadcast."
                            .to_string(),
                    ),
                    fallback_total_count,
                    fallback_migrated_zatoshi,
                ),
            ));
        }
    }

    drop(seed);
    Ok(ActiveMigrationResumeAction::BroadcastDue {
        run_id: run.run_id,
        fallback_total_count,
        fallback_migrated_zatoshi,
    })
}

async fn execute_active_migration_resume_action(
    action: ActiveMigrationResumeAction,
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    match action {
        ActiveMigrationResumeAction::Return(result) => Ok(result),
        ActiveMigrationResumeAction::BroadcastDue {
            run_id,
            fallback_total_count,
            fallback_migrated_zatoshi,
        } => {
            broadcast_due_scheduled_migration_txs(
                db_path,
                lightwalletd_url,
                network,
                &run_id,
                pending_password,
                pending_salt_base64,
                fallback_total_count,
                fallback_migrated_zatoshi,
            )
            .await
        }
    }
}

fn is_orchard_witness_not_ready_error(error: &str) -> bool {
    let lower = error.to_ascii_lowercase();
    lower.contains("read orchard witnesses")
        && (lower.contains("notcontained")
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
    let Some(split) = create_orchard_denomination_split_transaction(db_path, network, &usk)? else {
        return Ok(None);
    };

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
            let selected_note = super::migration::PreparedOrchardNoteRef {
                txid_hex: format!("{}", split.txid),
                output_index: child.selected_note.output_index,
                value_zatoshi: child.selected_note.value_zatoshi,
                note_version: child.selected_note.note_version,
                nullifier_hex: None,
            };
            Ok(super::migration::SignedMigrationPcztInsert {
                message_id: child.id.clone(),
                child_index: index as u32,
                base_pczt: child.base_pczt.clone(),
                signed_pczt,
                target_height: child.target_height,
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
        split,
        signed_children,
    }))
}

struct CreatedDenominationSplitTx {
    txid: TxId,
    raw_tx: Vec<u8>,
    fee_amount: Zatoshis,
    migrated_outputs: Vec<super::migration::PreparedOrchardNoteRef>,
    predicted_notes: Vec<PredictedMigrationNote>,
    total_migratable: Zatoshis,
    plan: super::migration::DenominationPlan,
}

struct PreparedSoftwareMigrationRun {
    split: CreatedDenominationSplitTx,
    signed_children: Vec<super::migration::SignedMigrationPcztInsert>,
}

enum ActiveMigrationResumeAction {
    Return(IronwoodMigrationResult),
    BroadcastDue {
        run_id: String,
        fallback_total_count: u32,
        fallback_migrated_zatoshi: u64,
    },
}

struct CreatedPendingMigrationTx {
    txid_hex: String,
    raw_tx: Vec<u8>,
    target_height: u32,
    expiry_height: u32,
    fee_zatoshi: u64,
    migrated_zatoshi: u64,
    selected_note: super::migration::PreparedOrchardNoteRef,
}

#[derive(Clone)]
struct DenominationOutputTemplate {
    output_index: u32,
    value_zatoshi: u64,
}

#[derive(Clone)]
struct PredictedMigrationNote {
    output_index: u32,
    value_zatoshi: u64,
    note: orchard::Note,
}

struct BuiltPczt {
    bytes: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum KeystoneMigrationRequestState {
    Proofing,
    ProofReady,
    ProofFailed,
    Completing,
}

struct CreatedDenominationSplitPczt {
    base_pczt: Vec<u8>,
    redacted_pczt: Vec<u8>,
    fee_zatoshi: u64,
    migrated_outputs: Vec<DenominationOutputTemplate>,
    predicted_notes: Vec<PredictedMigrationNote>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

struct StoredDenominationPczt {
    account_uuid: String,
    network: WalletNetwork,
    state: KeystoneMigrationRequestState,
    pczt_with_proofs: Option<Vec<u8>>,
    proof_error: Option<String>,
    fee_zatoshi: u64,
    migrated_outputs: Vec<DenominationOutputTemplate>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
}

struct StoredDenominationCompletion {
    pczt_with_proofs: Vec<u8>,
    fee_zatoshi: u64,
    migrated_outputs: Vec<DenominationOutputTemplate>,
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
    state: KeystoneMigrationRequestState,
    proof_error: Option<String>,
    messages: Vec<CreatedMigrationPczt>,
}

struct StoredMigrationBatchCompletion {
    run_id: String,
    fallback_total_count: u32,
    fallback_migrated_zatoshi: u64,
    messages: Vec<CreatedMigrationPczt>,
}

struct StoredSingleQrMigrationPczt {
    account_uuid: String,
    network: WalletNetwork,
    state: KeystoneMigrationRequestState,
    split_pczt_with_proofs: Option<Vec<u8>>,
    proof_error: Option<String>,
    split_fee_zatoshi: u64,
    migrated_outputs: Vec<DenominationOutputTemplate>,
    total_migratable_zatoshi: u64,
    plan: super::migration::DenominationPlan,
    child_messages: Vec<CreatedMigrationPczt>,
}

struct StoredSingleQrMigrationCompletion {
    split_pczt_with_proofs: Vec<u8>,
    split_fee_zatoshi: u64,
    migrated_outputs: Vec<DenominationOutputTemplate>,
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
            proof_status_from_counts(
                if stored.split_pczt_with_proofs.is_some() {
                    1
                } else {
                    0
                },
                1,
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
            proof_status_from_counts(
                if stored.pczt_with_proofs.is_some() {
                    1
                } else {
                    0
                },
                1,
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

fn spawn_denomination_proof_worker(request_id: String, base_pczt: Vec<u8>) {
    let builder = thread::Builder::new().name("keystone-denomination-proof".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let started = Instant::now();
        log::info!("migration proofs: denomination proof started");
        let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
        let elapsed = started.elapsed();
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
                stored.pczt_with_proofs = Some(pczt_with_proofs);
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: denomination proof ready in {}ms",
                    elapsed.as_millis()
                );
            }
            Err(e) => {
                stored.proof_error = Some(e);
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                log::warn!(
                    "migration proofs: denomination proof failed after {}ms",
                    elapsed.as_millis()
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

fn spawn_single_qr_split_proof_worker(request_id: String, base_pczt: Vec<u8>) {
    let builder = thread::Builder::new().name("keystone-single-qr-split-proof".to_string());
    let worker_request_id = request_id.clone();
    if let Err(e) = builder.spawn(move || {
        let started = Instant::now();
        log::info!("migration proofs: single QR split proof started");
        let result = super::pczt::add_proofs_to_pczt(&base_pczt, None, None);
        let elapsed = started.elapsed();
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
                stored.split_pczt_with_proofs = Some(pczt_with_proofs);
                stored.state = KeystoneMigrationRequestState::ProofReady;
                log::info!(
                    "migration proofs: single QR split proof ready in {}ms",
                    elapsed.as_millis()
                );
            }
            Err(e) => {
                stored.proof_error = Some(e);
                stored.state = KeystoneMigrationRequestState::ProofFailed;
                log::warn!(
                    "migration proofs: single QR split proof failed after {}ms",
                    elapsed.as_millis()
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
) -> Result<HashMap<String, Vec<u8>>, String> {
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
        if message.signed_pczt.is_empty() {
            return Err(format!("Keystone signed message {} is empty", message.id));
        }
        if by_id
            .insert(message.id.clone(), message.signed_pczt)
            .is_some()
        {
            return Err(format!("Duplicate signed Keystone message {}", message.id));
        }
    }

    Ok(by_id)
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

    Ok(BuiltPczt {
        bytes: pczt.serialize(),
        orchard_spend_action_indices,
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

fn create_orchard_denomination_split_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<CreatedDenominationSplitPczt>, String> {
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
    let orchard_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    if orchard_notes.is_empty() {
        return Ok(None);
    }

    let selected_value = orchard_notes.iter().try_fold(Zatoshis::ZERO, |acc, note| {
        let value = note.note_value().map_err(|e| format!("{e}"))?;
        (acc + value).ok_or("Selected Orchard value overflow".to_string())
    })?;
    let (orchard_anchor, orchard_inputs) =
        orchard_witnesses(&mut db, anchor_height, &orchard_notes)?;
    let migration_fee_estimate = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            1,
        )
        .map_err(|e| format!("Failed to estimate migration fee: {e}"))?;

    let mut prep_fee = Zatoshis::ZERO;
    let mut plan = None;
    for _ in 0..8 {
        let next_plan = super::migration::plan_denominations(
            u64::from(selected_value),
            u64::from(prep_fee),
            u64::from(migration_fee_estimate),
            MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI,
        )?;
        if next_plan.migration_outputs.is_empty() {
            return Ok(None);
        }
        let split_outputs = split_output_values(&next_plan);
        let builder = make_orchard_split_builder(
            network,
            target_height.into(),
            orchard_anchor,
            &orchard_inputs,
            &orchard_fvk,
            internal_ovk.clone(),
            recipient,
            &split_outputs,
            &memo,
        )?;
        let next_fee = builder
            .get_fee(&fee_rule)
            .map_err(|e| format!("Failed to estimate denomination prep fee: {e}"))?;
        plan = Some(next_plan);
        if next_fee == prep_fee {
            break;
        }
        prep_fee = next_fee;
    }

    let plan = plan.ok_or("Denomination planner did not converge")?;
    let split_outputs = split_output_values(&plan);
    let output_sum = split_outputs
        .iter()
        .try_fold(Zatoshis::ZERO, |acc, value| {
            let value = Zatoshis::from_u64(*value).map_err(|_| "Bad split output value")?;
            (acc + value).ok_or("Split output total overflow".to_string())
        })?;
    if output_sum > selected_value {
        return Err("Denomination outputs exceed selected Orchard value".to_string());
    }

    let builder = make_orchard_split_builder(
        network,
        target_height.into(),
        orchard_anchor,
        &orchard_inputs,
        &orchard_fvk,
        internal_ovk,
        recipient,
        &split_outputs,
        &memo,
    )?;
    let build_result = builder
        .build_for_pczt(rand_core::OsRng, &fee_rule)
        .map_err(|e| format!("Build denomination split PCZT failed: {e}"))?;

    let migration_output_count = plan.migration_outputs.len();
    let migrated_outputs = split_outputs
        .iter()
        .take(migration_output_count)
        .enumerate()
        .map(|(logical_index, value)| {
            let output_index = build_result
                .orchard_meta
                .output_action_index(logical_index)
                .ok_or("Denomination split output index missing")?;
            Ok(DenominationOutputTemplate {
                output_index: output_index as u32,
                value_zatoshi: *value,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let orchard_bundle = build_result
        .pczt_parts
        .orchard
        .as_ref()
        .ok_or("Denomination split PCZT missing Orchard bundle")?;
    let predicted_notes = migrated_outputs
        .iter()
        .map(|output| {
            let action = orchard_bundle
                .actions()
                .get(output.output_index as usize)
                .ok_or("Denomination split output action missing")?;
            let note = predicted_note_from_split_action(action, output.value_zatoshi)?;
            Ok(PredictedMigrationNote {
                output_index: output.output_index,
                value_zatoshi: output.value_zatoshi,
                note,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let built_pczt = pczt_from_build_result(
        build_result,
        network,
        account_derivation,
        orchard_inputs.len(),
        split_outputs.len(),
    )?;
    let redacted_pczt = super::pczt::redact_pczt_for_signer(&built_pczt.bytes)?;

    Ok(Some(CreatedDenominationSplitPczt {
        base_pczt: built_pczt.bytes,
        redacted_pczt,
        fee_zatoshi: u64::from(prep_fee),
        migrated_outputs,
        predicted_notes,
        total_migratable_zatoshi: plan.total_migratable_zatoshi,
        plan,
    }))
}

fn create_orchard_denomination_split_transaction(
    db_path: &str,
    network: WalletNetwork,
    usk: &UnifiedSpendingKey,
) -> Result<Option<CreatedDenominationSplitTx>, String> {
    let mut db = open_wallet_db(db_path, network)?;
    let fee_rule = ConservativeZip317FeeRule;
    let ufvk = usk.to_unified_full_viewing_key();
    let account_id = db
        .get_account_for_ufvk(&ufvk)
        .map_err(|e| format!("{e}"))?
        .ok_or("Spending key not recognized")?
        .id();
    let orchard_fvk = ufvk
        .orchard()
        .cloned()
        .ok_or("Orchard spending key not available")?;
    let recipient_scope = orchard::keys::Scope::Internal;
    let recipient = orchard_fvk.address_at(0u32, recipient_scope);
    let internal_ovk = Some(orchard_fvk.to_ovk(recipient_scope));
    let memo = MemoBytes::empty();

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before preparing denominations")?;
    let orchard_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    if orchard_notes.is_empty() {
        return Ok(None);
    }

    let selected_value = orchard_notes.iter().try_fold(Zatoshis::ZERO, |acc, note| {
        let value = note.note_value().map_err(|e| format!("{e}"))?;
        (acc + value).ok_or("Selected Orchard value overflow".to_string())
    })?;
    let (orchard_anchor, orchard_inputs) =
        orchard_witnesses(&mut db, anchor_height, &orchard_notes)?;
    let migration_fee_estimate = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            1,
        )
        .map_err(|e| format!("Failed to estimate migration fee: {e}"))?;

    let mut prep_fee = Zatoshis::ZERO;
    let mut plan = None;
    for _ in 0..8 {
        let next_plan = super::migration::plan_denominations(
            u64::from(selected_value),
            u64::from(prep_fee),
            u64::from(migration_fee_estimate),
            MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI,
        )?;
        if next_plan.migration_outputs.is_empty() {
            return Ok(None);
        }
        let split_outputs = split_output_values(&next_plan);
        let builder = make_orchard_split_builder(
            network,
            target_height.into(),
            orchard_anchor,
            &orchard_inputs,
            &orchard_fvk,
            internal_ovk.clone(),
            recipient,
            &split_outputs,
            &memo,
        )?;
        let next_fee = builder
            .get_fee(&fee_rule)
            .map_err(|e| format!("Failed to estimate denomination prep fee: {e}"))?;
        plan = Some(next_plan);
        if next_fee == prep_fee {
            break;
        }
        prep_fee = next_fee;
    }

    let plan = plan.ok_or("Denomination planner did not converge")?;
    let split_outputs = split_output_values(&plan);
    let output_sum = split_outputs
        .iter()
        .try_fold(Zatoshis::ZERO, |acc, value| {
            let value = Zatoshis::from_u64(*value).map_err(|_| "Bad split output value")?;
            (acc + value).ok_or("Split output total overflow".to_string())
        })?;
    if output_sum > selected_value {
        return Err("Denomination outputs exceed selected Orchard value".to_string());
    }

    let builder = make_orchard_split_builder(
        network,
        target_height.into(),
        orchard_anchor,
        &orchard_inputs,
        &orchard_fvk,
        internal_ovk.clone(),
        recipient,
        &split_outputs,
        &memo,
    )?;

    let transparent_signing_set = TransparentSigningSet::new();
    let sapling_extsks = &[usk.sapling().clone(), usk.sapling().derive_internal()];
    let orchard_saks = &[usk.orchard().into()];
    let spend_prover = NoOpSpendProver;
    let output_prover = NoOpOutputProver;
    let build_result = builder
        .build(
            &transparent_signing_set,
            sapling_extsks,
            orchard_saks,
            rand_core::OsRng,
            &spend_prover,
            &output_prover,
            &fee_rule,
        )
        .map_err(|e| format!("Build denomination split TX failed: {e}"))?;
    let txid = build_result.transaction().txid();
    let mut raw_tx = Vec::new();
    build_result
        .transaction()
        .write(&mut raw_tx)
        .map_err(|e| format!("Serialize denomination split TX failed: {e}"))?;
    let migration_output_count = plan.migration_outputs.len();
    let mut prepared_refs = Vec::with_capacity(migration_output_count);
    let mut predicted_notes = Vec::with_capacity(migration_output_count);

    for (logical_index, value) in split_outputs.iter().enumerate() {
        let action_index = build_result
            .orchard_meta()
            .output_action_index(logical_index)
            .ok_or("Denomination split output index missing")?;
        let note = build_result
            .transaction()
            .orchard_bundle()
            .and_then(|bundle| {
                bundle
                    .decrypt_output_with_key(action_index, &orchard_fvk.to_ivk(recipient_scope))
                    .map(|(note, _, _)| Note::Orchard(note))
            })
            .ok_or("Wallet-internal denomination output did not decrypt")?;
        let predicted_note = match note {
            Note::Orchard(note) => note,
            Note::Sapling(_) => {
                return Err("Wallet-internal denomination output was Sapling".to_string())
            }
        };
        if logical_index < migration_output_count {
            prepared_refs.push(super::migration::PreparedOrchardNoteRef {
                txid_hex: format!("{txid}"),
                output_index: action_index as u32,
                value_zatoshi: *value,
                note_version: 2,
                nullifier_hex: None,
            });
            predicted_notes.push(PredictedMigrationNote {
                output_index: action_index as u32,
                value_zatoshi: *value,
                note: predicted_note,
            });
        }
    }

    Ok(Some(CreatedDenominationSplitTx {
        txid,
        raw_tx,
        fee_amount: prep_fee,
        migrated_outputs: prepared_refs,
        predicted_notes,
        total_migratable: Zatoshis::from_u64(plan.total_migratable_zatoshi)
            .map_err(|_| "Bad migratable total")?,
        plan,
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

fn split_output_values(plan: &super::migration::DenominationPlan) -> Vec<u64> {
    let mut outputs = plan.migration_outputs.clone();
    if let Some(change) = plan.orchard_change {
        outputs.push(change);
    }
    outputs
}

fn dummy_orchard_merkle_path() -> Result<orchard::tree::MerklePath, String> {
    let zero = Option::<orchard::tree::MerkleHashOrchard>::from(
        orchard::tree::MerkleHashOrchard::from_bytes(&[0; 32]),
    )
    .ok_or("Zero Orchard Merkle hash is invalid")?;
    Ok(orchard::tree::MerklePath::from_parts(0, [zero; 32]))
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
        let mut builder = Builder::new(
            network,
            BlockHeight::from(target_height),
            BuildConfig::Standard {
                sapling_anchor: None,
                orchard_anchor: Some(dummy_anchor),
                ironwood_anchor: Some(orchard::Anchor::empty_tree()),
            },
        )
        .with_expiry_height(BlockHeight::from(MIGRATION_NO_EXPIRY_HEIGHT));

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
    let migrated_amount =
        (selected_value - fee_amount).ok_or("Predicted migration amount underflow".to_string())?;
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
    let redacted_pczt = super::pczt::redact_pczt_for_signer(&built_pczt.bytes)?;
    let target_height_u32: u32 = target_height.into();

    Ok(Some(CreatedMigrationPczt {
        id: format!("migration-{migration_index}"),
        base_pczt: built_pczt.bytes,
        orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
        pczt_with_proofs: None,
        redacted_pczt,
        target_height: target_height_u32,
        expiry_height,
        fee_zatoshi: u64::from(fee_amount),
        migrated_zatoshi: u64::from(migrated_amount),
        selected_note: super::migration::PreparedOrchardNoteRef {
            txid_hex: String::new(),
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
    Ok(signer.finish().serialize())
}

fn create_orchard_to_ironwood_transaction_from_note(
    db_path: &str,
    network: WalletNetwork,
    usk: &UnifiedSpendingKey,
    account_uuid: &str,
    note_ref: &super::migration::PreparedOrchardNoteRef,
) -> Result<Option<CreatedPendingMigrationTx>, String> {
    if note_ref.note_version != 2 {
        return Err("Prepared migration note is not an Orchard V2 note".to_string());
    }

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let ufvk = usk.to_unified_full_viewing_key();
    let account_for_key = db
        .get_account_for_ufvk(&ufvk)
        .map_err(|e| format!("{e}"))?
        .ok_or("Spending key not recognized")?
        .id();
    if account_for_key != account_id {
        return Err("Spending key does not match migration account".to_string());
    }

    let orchard_fvk = ufvk
        .orchard()
        .cloned()
        .ok_or("Orchard spending key not available")?;
    let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);
    let internal_ovk = Some(orchard_fvk.to_ovk(orchard::keys::Scope::Internal));
    let memo = MemoBytes::empty();

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before migrating denominations")?;

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
        Note::Orchard(note) => *note,
        Note::Sapling(_) => return Err("Prepared note revalidated as Sapling".to_string()),
    };
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
    let (orchard_anchor, orchard_inputs) = orchard_witnesses(
        &mut db,
        anchor_height,
        std::slice::from_ref(&orchard_selected),
    )?;
    let fee_rule = ConservativeZip317FeeRule;
    let make_builder = |ironwood_amount: Zatoshis| {
        let mut builder = Builder::new(
            network,
            BlockHeight::from(target_height),
            BuildConfig::Standard {
                sapling_anchor: None,
                orchard_anchor: Some(orchard_anchor),
                ironwood_anchor: Some(orchard::Anchor::empty_tree()),
            },
        )
        .with_expiry_height(BlockHeight::from(MIGRATION_NO_EXPIRY_HEIGHT));

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
    let migrated_amount =
        (selected_value - fee_amount).ok_or("Exact-note migration amount underflow".to_string())?;
    let builder = if migrated_amount
        == Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?
    {
        builder_with_minimum_amount
    } else {
        make_builder(migrated_amount)?
    };

    let transparent_signing_set = TransparentSigningSet::new();
    let sapling_extsks = &[usk.sapling().clone(), usk.sapling().derive_internal()];
    let orchard_saks = &[usk.orchard().into()];
    let spend_prover = NoOpSpendProver;
    let output_prover = NoOpOutputProver;
    let build_result = builder
        .build(
            &transparent_signing_set,
            sapling_extsks,
            orchard_saks,
            rand_core::OsRng,
            &spend_prover,
            &output_prover,
            &fee_rule,
        )
        .map_err(|e| format!("Build exact-note migration TX failed: {e}"))?;
    let txid = build_result.transaction().txid();
    let mut raw_tx = Vec::new();
    build_result
        .transaction()
        .write(&mut raw_tx)
        .map_err(|e| format!("Serialize exact-note migration TX failed: {e}"))?;
    let target_height_u32: u32 = target_height.into();
    let expiry_height = u32::from(build_result.transaction().expiry_height());

    Ok(Some(CreatedPendingMigrationTx {
        txid_hex: format!("{txid}"),
        raw_tx,
        target_height: target_height_u32,
        expiry_height,
        fee_zatoshi: u64::from(fee_amount),
        migrated_zatoshi: u64::from(migrated_amount),
        selected_note: note_ref.clone(),
    }))
}

fn create_orchard_to_ironwood_pczt_from_note(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    note_ref: &super::migration::PreparedOrchardNoteRef,
    migration_index: u32,
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
        Note::Orchard(note) => *note,
        Note::Sapling(_) => return Err("Prepared note revalidated as Sapling".to_string()),
    };
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
    let (orchard_anchor, orchard_inputs) = orchard_witnesses(
        &mut db,
        anchor_height,
        std::slice::from_ref(&orchard_selected),
    )?;
    let fee_rule = ConservativeZip317FeeRule;
    let make_builder = |ironwood_amount: Zatoshis| {
        let mut builder = Builder::new(
            network,
            BlockHeight::from(target_height),
            BuildConfig::Standard {
                sapling_anchor: None,
                orchard_anchor: Some(orchard_anchor),
                ironwood_anchor: Some(orchard::Anchor::empty_tree()),
            },
        )
        .with_expiry_height(BlockHeight::from(MIGRATION_NO_EXPIRY_HEIGHT));

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
    let migrated_amount =
        (selected_value - fee_amount).ok_or("Exact-note migration amount underflow".to_string())?;
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
    let redacted_pczt = super::pczt::redact_pczt_for_signer(&built_pczt.bytes)?;
    let target_height_u32: u32 = target_height.into();

    Ok(Some(CreatedMigrationPczt {
        id: format!("migration-{migration_index}"),
        base_pczt: built_pczt.bytes,
        orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
        pczt_with_proofs: None,
        redacted_pczt,
        target_height: target_height_u32,
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

#[allow(clippy::too_many_arguments)]
fn make_orchard_split_builder(
    network: WalletNetwork,
    target_height: u32,
    orchard_anchor: orchard::Anchor,
    orchard_inputs: &[(orchard::Note, orchard::tree::MerklePath)],
    orchard_fvk: &orchard::keys::FullViewingKey,
    internal_ovk: Option<orchard::keys::OutgoingViewingKey>,
    recipient: orchard::Address,
    outputs: &[u64],
    memo: &MemoBytes,
) -> Result<Builder<'static, WalletNetwork, ()>, String> {
    let mut builder = Builder::new(
        network,
        BlockHeight::from(target_height),
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: Some(orchard_anchor),
            ironwood_anchor: Some(orchard::Anchor::empty_tree()),
        },
    )
    .with_expiry_height(BlockHeight::from(MIGRATION_NO_EXPIRY_HEIGHT));

    #[cfg(zcash_unstable = "nu7")]
    if network.is_nu_active(
        zcash_protocol::consensus::NetworkUpgrade::Nu7,
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

    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None, None);
    let proposal = propose_shielding::<_, _, _, _, Infallible>(
        db,
        &network,
        &input_selector,
        &change_strategy,
        shielding_threshold,
        &from_addrs,
        account_id,
        ConfirmationsPolicy::MIN,
        TransparentOutputFilter::All,
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
    let (change_strategy, input_selector) =
        zip317_helper::<ReservedInputSource<'_>>(None, proposed_tx_version);

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
        output_filter: TransparentOutputFilter,
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
    proposed_tx_version: Option<TxVersion>,
) -> Result<Proposal<WalletFeeRule, <WalletDatabase as InputSource>::NoteRef>, String> {
    let to: zcash_address::ZcashAddress = to_address
        .parse()
        .map_err(|e| format!("Bad address: {e}"))?;
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
    propose_send_max_transfer::<_, _, _, Infallible>(
        db,
        &network,
        account_id,
        // NU7 Ironwood notes are selected through the Orchard protocol path as
        // v3 note rows; librustzcash does not expose a separate Ironwood
        // ShieldedProtocol selector. This is why balance prechecks can treat
        // spendable Ironwood value as available to ordinary sends.
        &[ShieldedProtocol::Sapling, ShieldedProtocol::Orchard],
        &fee_rule,
        to,
        memo_bytes,
        MaxSpendMode::MaxSpendable,
        ConfirmationsPolicy::default(),
        proposed_tx_version,
    )
    .map_err(|e| format!("Propose max failed: {e}"))
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

fn same_prepared_note_without_nullifier(
    lhs: &super::migration::PreparedOrchardNoteRef,
    rhs: &super::migration::PreparedOrchardNoteRef,
) -> bool {
    lhs.txid_hex.eq_ignore_ascii_case(&rhs.txid_hex)
        && lhs.output_index == rhs.output_index
        && lhs.value_zatoshi == rhs.value_zatoshi
        && lhs.note_version == rhs.note_version
}

fn orchard_anchor_and_witness_for_prepared_note(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    note_ref: &super::migration::PreparedOrchardNoteRef,
) -> Result<Option<(orchard::Anchor, orchard::tree::MerklePath)>, String> {
    if note_ref.note_version != 2 {
        return Err("Prepared migration note is not an Orchard V2 note".to_string());
    }

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    db.get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before finalizing migration")?;
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
        Note::Orchard(note) => *note,
        Note::Sapling(_) => return Err("Prepared note revalidated as Sapling".to_string()),
    };
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
    let (orchard_anchor, mut orchard_inputs) = orchard_witnesses(
        &mut db,
        anchor_height,
        std::slice::from_ref(&orchard_selected),
    )?;
    let (_, witness) = orchard_inputs
        .pop()
        .ok_or("Prepared migration note witness missing")?;
    Ok(Some((orchard_anchor, witness)))
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
    if super::migration::pending_totals_for_run(db_path, run_id)?.total_count > 0 {
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
    let mut pending_inserts = Vec::with_capacity(signed_children.len());
    for child in signed_children {
        let current_note = current_prepared
            .iter()
            .find(|note| same_prepared_note_without_nullifier(note, &child.selected_note))
            .ok_or("Prepared migration notes changed before child finalization")?;
        let Some((orchard_anchor, orchard_witness)) =
            (match orchard_anchor_and_witness_for_prepared_note(
                db_path,
                network,
                account_uuid,
                current_note,
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

        // Keep this before proof creation. V6 signatures survive the anchor
        // update, but Orchard proofs depend on the real anchor.
        let base_pczt = super::pczt::set_orchard_anchor_and_witness(
            &child.base_pczt,
            orchard_anchor,
            &orchard_witness,
            current_note_nullifier_hex,
        )?;
        let signed_pczt = super::pczt::set_orchard_anchor_and_witness(
            &child.signed_pczt,
            orchard_anchor,
            &orchard_witness,
            current_note_nullifier_hex,
        )?;
        let pczt_with_proofs = super::pczt::add_proofs_to_pczt(&base_pczt, None, None)?;
        let extracted = super::pczt::extract_transaction_from_pczt(
            &pczt_with_proofs,
            &signed_pczt,
            None,
            None,
        )?;
        pending_inserts.push(super::migration::PendingMigrationTxInsert {
            txid_hex: extracted.txid.to_string(),
            raw_tx: extracted.raw_tx,
            target_height: child.target_height,
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

    super::migration::promote_signed_child_pczts_to_pending_txs(
        db_path,
        run_id,
        pending_inserts,
        pending_password,
        pending_salt_base64,
    )?;
    Ok(true)
}

async fn broadcast_pending_migration_prep_tx(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<Option<CreatedBroadcastResult>, String> {
    let Some(prep_tx) = super::migration::pending_prep_tx_for_run(
        db_path,
        run_id,
        pending_password,
        pending_salt_base64,
    )?
    else {
        return Ok(None);
    };

    let mut client = match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
        Ok(client) => client,
        Err(e) => {
            let message = format!("Denomination split broadcast could not start: {e}");
            return Ok(Some(CreatedBroadcastResult {
                txids: prep_tx.txid_hex,
                status: CreatedBroadcastResult::PENDING_BROADCAST,
                broadcasted_count: 0,
                total_count: 1,
                message: Some(message),
            }));
        }
    };

    if let Err(e) = broadcast_raw_transaction(&mut client, &prep_tx.raw_tx).await {
        let message = format!("Denomination split broadcast failed: {e}");
        return Ok(Some(CreatedBroadcastResult {
            txids: prep_tx.txid_hex,
            status: CreatedBroadcastResult::PENDING_BROADCAST,
            broadcasted_count: 0,
            total_count: 1,
            message: Some(message),
        }));
    }

    record_accepted_prep_migration_tx(
        db_path,
        network,
        run_id,
        &prep_tx,
        decrypt_and_store_migration_tx,
    )
    .map(Some)
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

    let due =
        super::migration::due_pending_txs(db_path, run_id, pending_password, pending_salt_base64)?;
    if due.is_empty() {
        let status = if super::migration::next_scheduled_delay_ms(db_path, run_id)?.is_some() {
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
            let message = format!(
                "Migration broadcast failed for {}. Error: {e}",
                pending.txid_hex
            );
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

fn record_accepted_prep_migration_tx<F>(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
    prep_tx: &super::migration::MigrationPrepTx,
    store_tx: F,
) -> Result<CreatedBroadcastResult, String>
where
    F: FnOnce(&str, WalletNetwork, &[u8]) -> Result<(), String>,
{
    if let Err(e) = store_tx(db_path, network, &prep_tx.raw_tx) {
        let result = migration_prep_storage_retry_result(prep_tx.txid_hex.clone(), &e);
        if let Some(message) = &result.message {
            log::warn!("migration: {message}");
            if let Err(mark_err) = super::migration::mark_run_phase(
                db_path,
                run_id,
                super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS,
                Some(message),
            ) {
                log::warn!(
                    "migration: could not persist denomination split retry message: {mark_err}"
                );
            }
        }
        return Ok(result);
    }

    let phase = match super::migration::mark_prep_tx_broadcasted(db_path, run_id) {
        Ok(phase) => phase,
        Err(e) => {
            let message = format!(
                "Denomination split broadcast was accepted, but local state update failed: {e}"
            );
            log::warn!(
                "migration: broadcast denomination split {} but could not mark it broadcasted: {}",
                prep_tx.txid_hex,
                e
            );
            return Ok(CreatedBroadcastResult {
                txids: prep_tx.txid_hex.clone(),
                status: CreatedBroadcastResult::PENDING_BROADCAST,
                broadcasted_count: 0,
                total_count: 1,
                message: Some(message),
            });
        }
    };
    let status = if phase == super::migration::PHASE_READY_TO_MIGRATE {
        super::migration::PHASE_READY_TO_MIGRATE
    } else {
        super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS
    };
    let message = if status == super::migration::PHASE_READY_TO_MIGRATE {
        "Denomination notes are ready. Continue migration.".to_string()
    } else {
        "Denomination notes were created. Migration will continue after confirmation.".to_string()
    };

    Ok(CreatedBroadcastResult {
        txids: prep_tx.txid_hex.clone(),
        status,
        broadcasted_count: 1,
        total_count: 1,
        message: Some(message),
    })
}

fn migration_prep_storage_retry_result(txid_hex: String, error: &str) -> CreatedBroadcastResult {
    let message = migration_storage_retry_message("Denomination split", &txid_hex, error);
    CreatedBroadcastResult {
        txids: txid_hex,
        status: CreatedBroadcastResult::PENDING_BROADCAST,
        broadcasted_count: 0,
        total_count: 1,
        message: Some(message),
    }
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

fn migration_result_from_prep_broadcast(
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
    #[cfg(zcash_unstable = "nu7")]
    let change_strategy = if matches!(proposed_tx_version, Some(TxVersion::V5)) {
        change_strategy.with_legacy_orchard_change()
    } else {
        change_strategy
    };

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
            prep_fee_zatoshi: 10_000,
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
    fn prep_broadcast_result_preserves_status_and_migrated_amount() {
        let result = migration_result_from_prep_broadcast(
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
    fn prep_storage_failure_after_acceptance_leaves_prep_tx_retryable() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        let raw_tx = vec![1, 2, 3, 4];
        let plan = migration_test_plan();
        let prepared_notes = vec![migration_test_note(txid_hex)];
        let run_id = migration::create_run_with_prepared_notes_and_prep_tx(
            &db_path,
            MIGRATION_TEST_ACCOUNT,
            WalletNetwork::Test,
            &plan,
            &prepared_notes,
            true,
            txid_hex,
            raw_tx.clone(),
            MIGRATION_TEST_PASSWORD,
            MIGRATION_TEST_SALT,
        )
        .unwrap();
        let prep_tx = migration::pending_prep_tx_for_run(
            &db_path,
            &run_id,
            MIGRATION_TEST_PASSWORD,
            MIGRATION_TEST_SALT,
        )
        .unwrap()
        .unwrap();

        let result = record_accepted_prep_migration_tx(
            &db_path,
            WalletNetwork::Test,
            &run_id,
            &prep_tx,
            |_db_path, _network, _raw_tx| Err("db busy".to_string()),
        )
        .unwrap();

        assert_eq!(result.txids, txid_hex);
        assert_eq!(result.status, CreatedBroadcastResult::PENDING_BROADCAST);
        assert_eq!(result.broadcasted_count, 0);
        assert_eq!(result.total_count, 1);
        let message = result.message.as_deref().unwrap();
        assert!(message.contains("accepted by lightwalletd"));
        assert!(message.contains("Vizor will retry"));
        assert_eq!(
            migration::pending_prep_tx_for_run(
                &db_path,
                &run_id,
                MIGRATION_TEST_PASSWORD,
                MIGRATION_TEST_SALT,
            )
            .unwrap()
            .unwrap()
            .txid_hex,
            txid_hex
        );
        let active =
            migration::active_migration_run(&db_path, MIGRATION_TEST_ACCOUNT, WalletNetwork::Test)
                .unwrap()
                .unwrap();
        assert_eq!(active.phase, migration::PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert_eq!(active.last_error.as_deref(), Some(message));
        migration::mark_run_phase(
            &db_path,
            &run_id,
            migration::PHASE_READY_TO_MIGRATE,
            Some("ready before retry"),
        )
        .unwrap();

        let result = record_accepted_prep_migration_tx(
            &db_path,
            WalletNetwork::Test,
            &run_id,
            &prep_tx,
            |_db_path, _network, _raw_tx| Ok(()),
        )
        .unwrap();

        assert_eq!(result.txids, txid_hex);
        assert_eq!(result.status, migration::PHASE_READY_TO_MIGRATE);
        assert_eq!(result.broadcasted_count, 1);
        assert!(migration::pending_prep_tx_for_run(
            &db_path,
            &run_id,
            MIGRATION_TEST_PASSWORD,
            MIGRATION_TEST_SALT,
        )
        .unwrap()
        .is_none());
        let active =
            migration::active_migration_run(&db_path, MIGRATION_TEST_ACCOUNT, WalletNetwork::Test)
                .unwrap()
                .unwrap();
        assert_eq!(active.phase, migration::PHASE_READY_TO_MIGRATE);
        assert_eq!(active.last_error, None);
    }

    #[test]
    fn scheduled_storage_failure_after_acceptance_leaves_tx_scheduled() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let selected_note_txid = "101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f";
        let pending_txid = "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f";
        let selected_note = migration_test_note(selected_note_txid);
        let plan = migration_test_plan();
        let run_id = migration::create_run_with_prepared_notes_and_signed_children(
            &db_path,
            MIGRATION_TEST_ACCOUNT,
            WalletNetwork::Test,
            &plan,
            &[selected_note.clone()],
            true,
            Vec::new(),
            MIGRATION_TEST_PASSWORD,
            MIGRATION_TEST_SALT,
            None,
            None,
        )
        .unwrap();
        migration::insert_pending_txs(
            &db_path,
            &run_id,
            vec![migration::PendingMigrationTxInsert {
                txid_hex: pending_txid.to_string(),
                raw_tx: vec![5, 6, 7, 8],
                target_height: 100,
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
            )
            .unwrap();

        assert_eq!(conservative_fee, standard_p2pkh_fee);
        assert_eq!(u64::from(conservative_fee), 15_000);
        assert_eq!(u64::from(standard_undersized_fee), 10_000);
    }

    #[test]
    #[cfg(zcash_unstable = "nu7")]
    fn orchard_denomination_split_pczt_uses_v6_for_change_outputs() {
        let network = WalletNetwork::LocalIronwoodTestnet;
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

            make_orchard_split_builder(
                network,
                target_height,
                orchard_anchor,
                &[(note, merkle_path)],
                &fvk,
                internal_ovk.clone(),
                recipient,
                &[output_value],
                &memo,
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
        crate::wallet::sync::pczt::redact_pczt_for_signer(&built_pczt.bytes).unwrap();
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
        let (ua, _) = db
            .get_next_available_address(account_id, ua_request)
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
            None,
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
