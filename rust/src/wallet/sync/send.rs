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

use std::collections::HashMap;
use std::convert::Infallible;
use std::num::NonZeroUsize;

use secrecy::{ExposeSecret, SecretVec};
use transparent::{address::TransparentAddress, keys::TransparentKeyScope};
use zcash_client_backend::data_api::wallet::input_selection::GreedyInputSelector;
use zcash_client_backend::{
    data_api::{
        wallet::{
            self, create_proposed_transactions, propose_send_max_transfer, propose_shielding,
            propose_transfer, ConfirmationsPolicy,
        },
        Account as _, Balance, InputSource, MaxSpendMode, TransparentKeyOrigin,
        TransparentOutputFilter, WalletRead,
    },
    fees::{
        zip317::{MultiOutputChangeStrategy, Zip317FeeRule},
        DustOutputPolicy, SplitPolicy, StandardFeeRule,
    },
    proposal::Proposal,
    wallet::OvkPolicy,
    zip321::{Payment, TransactionRequest},
};
use zcash_client_sqlite::AccountUuid;
use zcash_client_sqlite::ReceivedNoteId;
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_primitives::transaction::{
    fees::{
        transparent::InputSize as TransparentInputSize, zip317::P2PKH_STANDARD_INPUT_SIZE, FeeRule,
    },
    TxId,
};
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::{
    consensus,
    memo::{Memo, MemoBytes},
    value::Zatoshis,
    PoolType, ShieldedProtocol,
};

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::keys::parse_account_uuid;
use crate::wallet::network::WalletNetwork;
use crate::wallet::spendability_pir as wallet_pir;

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

const SHIELDING_THRESHOLD_ZATOSHI: u64 = 100_000;

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

fn should_use_pir_witnesses(
    db: &WalletDatabase,
    proposal: &Proposal<WalletFeeRule, ReceivedNoteId>,
) -> bool {
    // PIR witnesses are only considered for Orchard spends while sync is still in
    // progress (fully scanned height is behind chain tip). Once fully synced, use
    // standard local ShardTree witnesses.
    if !proposal_uses_orchard_spends(proposal) {
        return false;
    }

    match db.get_wallet_summary(ConfirmationsPolicy::default()) {
        Ok(Some(summary)) => summary.fully_scanned_height() < summary.chain_tip_height(),
        Ok(None) => false,
        Err(e) => {
            log::warn!("PIR: unable to read wallet summary for witness selection: {e}");
            false
        }
    }
}

fn is_pir_anchor_mismatch(error: &str) -> bool {
    error.contains("PIR witness anchor") || error.contains("incompatible PIR witness anchors")
}

fn proposal_uses_orchard_spends(proposal: &Proposal<WalletFeeRule, ReceivedNoteId>) -> bool {
    !proposal_orchard_spend_positions(proposal).is_empty()
}

fn proposal_orchard_spend_positions(
    proposal: &Proposal<WalletFeeRule, ReceivedNoteId>,
) -> Vec<u64> {
    use zcash_client_backend::wallet::Note;

    let mut positions = Vec::new();
    for step in proposal.steps() {
        if let Some(inputs) = step.shielded_inputs() {
            for selected in inputs.notes() {
                if matches!(selected.note(), Note::Orchard(_)) {
                    positions.push(u64::from(selected.note_commitment_tree_position()));
                }
            }
        }
    }
    positions
}

fn refresh_proposal_pir_witnesses(
    db: &WalletDatabase,
    network: WalletNetwork,
    proposal: &Proposal<WalletFeeRule, ReceivedNoteId>,
) -> Result<u32, String> {
    let selected_positions = proposal_orchard_spend_positions(proposal);
    if selected_positions.is_empty() {
        return Ok(0);
    }

    let notes: Vec<_> = selected_positions
        .into_iter()
        .filter_map(|position| match db.position_needs_pir_witness(position) {
            Ok(Some(note_id)) => Some(Ok((note_id, position))),
            Ok(None) => None,
            Err(e) => Some(Err(format!(
                "failed to read PIR witness eligibility for position {position}: {e}"
            ))),
        })
        .collect::<Result<Vec<_>, _>>()?;
    if notes.is_empty() {
        return Ok(0);
    }

    let urls = wallet_pir::server_urls_for(network, None, None);
    let client = witness_client::WitnessClientBlocking::connect(&urls.witness_url)
        .map_err(|e| format!("PIR witness refresh connect failed: {e}"))?;
    let positions: Vec<_> = notes.iter().map(|(_, position)| *position).collect();
    let witnesses = client
        .get_witnesses(&positions, |_| {})
        .map_err(|e| format!("PIR witness refresh query failed: {e}"))?;

    let mut inserted = 0u32;
    for ((note_id, position), witness) in notes.iter().zip(witnesses.iter()) {
        let validation = db
            .validate_pir_orchard_witness(
                *note_id,
                &witness.siblings,
                &witness.anchor_root,
            )
            .map_err(|e| format!("PIR witness refresh validation failed: {e}"))?;
        if !validation.witness_root_matches_anchor() {
            log::warn!(
                "PIR: refreshed witness did not validate for proposal note {} at position {}",
                note_id,
                position
            );
            continue;
        }
        db.insert_pir_witness(
            *note_id,
            &witness.siblings,
            witness.anchor_height,
            &witness.anchor_root,
        )
        .map_err(|e| format!("PIR witness refresh insert failed: {e}"))?;
        inserted += 1;
    }
    Ok(inserted)
}

#[allow(clippy::too_many_arguments)]
fn create_transactions_with_optional_pir_retry<SpendP, OutputP>(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    spend_prover: &SpendP,
    output_prover: &OutputP,
    spending_keys: &wallet::SpendingKeys,
    proposal: &Proposal<WalletFeeRule, ReceivedNoteId>,
    context: &str,
) -> Result<Vec<TxId>, String>
where
    SpendP: SpendProver,
    OutputP: OutputProver,
{
    let use_pir_witnesses = should_use_pir_witnesses(db, proposal);
    let result = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
        db,
        &network,
        spend_prover,
        output_prover,
        spending_keys,
        OvkPolicy::Sender,
        proposal,
        None,
        use_pir_witnesses,
    );

    match result {
        Ok(txids) => Ok(txids.iter().cloned().collect()),
        Err(e) => {
            let message = format!("{e}");
            if !use_pir_witnesses || !is_pir_anchor_mismatch(&message) {
                return Err(format!("{context}: {message}"));
            }

            log::info!("PIR: refreshing proposal witnesses after anchor mismatch");
            let refreshed = refresh_proposal_pir_witnesses(db, network, proposal)?;
            if refreshed == 0 {
                return Err(format!("{context}: {message}"));
            }

            create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
                db,
                &network,
                spend_prover,
                output_prover,
                spending_keys,
                OvkPolicy::Sender,
                proposal,
                None,
                true,
            )
            .map(|txids| txids.iter().cloned().collect())
            .map_err(|retry_error| {
                format!(
                    "{context}: {message}; retry after refreshing {refreshed} PIR witnesses failed: {retry_error}"
                )
            })
        }
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
) -> Result<ProposalResult, String> {
    use zcash_protocol::{PoolType, ShieldedProtocol as SP};

    if send_flow_id.is_empty() {
        return Err("Send flow id is required".to_string());
    }

    let mut db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;

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

    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None);
    let payment = Payment::new(to, Some(value), memo_bytes, None, None, vec![])
        .map_err(|e| format!("Cannot create payment: {e:?}"))?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let proposal = propose_transfer::<_, _, _, _, Infallible>(
        &mut db,
        &network,
        account_id,
        &input_selector,
        &change_strategy,
        request,
        ConfirmationsPolicy::default(),
        None,
    )
    .map_err(|e| format!("Propose failed: {e}"))?;

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
    let mut db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;

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

    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None);
    let payment = Payment::new(to, Some(value), memo_bytes, None, None, vec![])
        .map_err(|e| format!("Cannot create payment: {e:?}"))?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let proposal = propose_transfer::<_, _, _, _, Infallible>(
        &mut db,
        &network,
        account_id,
        &input_selector,
        &change_strategy,
        request,
        ConfirmationsPolicy::default(),
        None,
    )
    .map_err(|e| format!("Propose failed: {e}"))?;

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
) -> Result<SendMaxEstimateResult, String> {
    let mut db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
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

/// Create a PCZT for shielding transparent funds on a hardware account.
/// This mirrors `shield_transparent_balance` up to proposal creation, but
/// stops before signing/broadcast and returns the base PCZT for Keystone.
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
        let needs_sapling_params = proposal
            .steps()
            .iter()
            .any(|step| step.involves(PoolType::Shielded(ShieldedProtocol::Sapling)));

        let pczt = zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &network,
            account_id,
            OvkPolicy::Sender,
            &proposal,
        )
        .map_err(|e| format!("Create shielding PCZT failed: {e}"))?;

        Ok(ShieldTransparentPcztResult {
            pczt_bytes: pczt.serialize(),
            fee_zatoshi,
            shielded_zatoshi,
            needs_sapling_params,
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
                None,
                false,
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
            let spending_keys = wallet::SpendingKeys::from_unified_spending_key(usk);

            let txids = match (spend_params_path, output_params_path) {
                (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
                    let prover =
                        LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
                    create_transactions_with_optional_pir_retry(
                        &mut db,
                        network,
                        &prover,
                        &prover,
                        &spending_keys,
                        &stored.proposal,
                        "Create TX failed",
                    )?
                }
                _ => {
                    let spend_prover = NoOpSpendProver;
                    let output_prover = NoOpOutputProver;
                    create_transactions_with_optional_pir_retry(
                        &mut db,
                        network,
                        &spend_prover,
                        &output_prover,
                        &spending_keys,
                        &stored.proposal,
                        "Create TX failed",
                    )?
                }
            };
            // USK and derived spending keys dropped here, before broadcast.
            Ok::<_, String>(txids)
        })?;

    Ok(
        broadcast_created_transactions(db_path, lightwalletd_url, &txids, "send")
            .await
            .into_execute_result(),
    )
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

    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None);
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
        &[ShieldedProtocol::Sapling, ShieldedProtocol::Orchard],
        &fee_rule,
        to,
        memo_bytes,
        MaxSpendMode::MaxSpendable,
        ConfirmationsPolicy::default(),
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

    if resp.error_code != 0 {
        return Err(format!(
            "Broadcast rejected: {} (code {})",
            resp.error_message, resp.error_code
        ));
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
///     (`mined_height IS NULL AND expiry_height > current_tip AND
///     account_balance_delta < 0`).
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
) -> (
    MultiOutputChangeStrategy<WalletFeeRule, DbT>,
    GreedyInputSelector<DbT>,
) {
    (
        MultiOutputChangeStrategy::new(
            ConservativeZip317FeeRule,
            change_memo,
            ShieldedProtocol::Orchard,
            DustOutputPolicy::default(),
            SplitPolicy::with_min_output_value(
                NonZeroUsize::new(4).unwrap(),
                Zatoshis::const_from_u64(1000_0000),
            ),
        ),
        GreedyInputSelector::new(),
    )
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
    use super::*;

    use transparent::bundle::{OutPoint, TxOut};
    use zcash_client_backend::{data_api::WalletWrite, wallet::WalletTransparentOutput};
    use zcash_keys::keys::{ReceiverRequirement, UnifiedSpendingKey};
    use zcash_protocol::consensus::BlockHeight;

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
            let utxo = WalletTransparentOutput::from_parts(outpoint, txout, Some(tip))
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
            false,
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
