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
//!      the USK from the supplied seed (scoped + dropped before
//!      network I/O), build + sign the transaction(s), and broadcast
//!      them via `send_transaction` gRPC. Returns a comma-separated
//!      txid string on success.
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
        Account as _, Balance, InputSource, MaxSpendMode, WalletRead,
    },
    fees::{zip317::MultiOutputChangeStrategy, DustOutputPolicy, SplitPolicy, StandardFeeRule},
    proposal::Proposal,
    wallet::OvkPolicy,
    zip321::{Payment, TransactionRequest},
};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_primitives::transaction::TxId;
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::{
    memo::{Memo, MemoBytes},
    value::Zatoshis,
    PoolType, ShieldedProtocol,
};

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::keys::parse_account_uuid;
use crate::wallet::network::WalletNetwork;

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

pub(crate) struct SendMaxEstimateResult {
    pub amount_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub needs_sapling_params: bool,
}

pub(crate) struct ShieldTransparentResult {
    pub txids: String,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
}

pub(crate) struct ShieldTransparentStatus {
    pub can_shield: bool,
    pub fee_zatoshi: u64,
    pub shielded_zatoshi: u64,
    pub reason: String,
}

const SHIELDING_THRESHOLD_ZATOSHI: u64 = 100_000;

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
    let payment = Payment::new(to, value, memo_bytes, None, None, vec![])
        .ok_or("Cannot send memo to this address type")?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let proposal = propose_transfer::<_, _, _, _, Infallible>(
        &mut db,
        &network,
        account_id,
        &input_selector,
        &change_strategy,
        request,
        ConfirmationsPolicy::default(),
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
    let payment = Payment::new(to, value, memo_bytes, None, None, vec![])
        .ok_or("Cannot send memo to this address type")?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let proposal = propose_transfer::<_, _, _, _, Infallible>(
        &mut db,
        &network,
        account_id,
        &input_selector,
        &change_strategy,
        request,
        ConfirmationsPolicy::default(),
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

/// Shield spendable transparent funds for a software account to its
/// internal shielded address. This is intentionally a one-shot API:
/// unlike normal sends there is no confirmation screen, proposal ID,
/// or hardware-wallet branch.
pub(crate) async fn shield_transparent_balance(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed_bytes: &[u8],
) -> Result<ShieldTransparentResult, String> {
    let shielding_threshold = shielding_threshold()?;

    let (txids, fee_zatoshi, shielded_zatoshi) = with_wallet_db_write_lock(
        "send.shield_transparent_balance.create_transactions",
        || {
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

            let seed = SecretVec::new(seed_bytes.to_vec());
            let zip32_index = account
                .source()
                .key_derivation()
                .ok_or("No key derivation")?
                .account_index();
            let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
                .map_err(|e| format!("USK derivation failed: {e:?}"))?;

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
    let txids = broadcast_created_transactions(db_path, lightwalletd_url, &txids, "shield").await?;
    Ok(ShieldTransparentResult {
        txids,
        fee_zatoshi,
        shielded_zatoshi,
    })
}

/// Execute a previously proposed transfer, then broadcast to the
/// network. Returns comma-separated txids on success.
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
    seed_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<String, String> {
    let stored = consume_stored_proposal(
        proposal_id,
        send_flow_id,
        "Proposal not found (expired or already executed)",
    )?;
    let network = stored.network;

    // Scope DB writes and seed/USK so they are dropped before network I/O (broadcast).
    let txids = with_wallet_db_write_lock("send.execute_proposal.create_transactions", || {
        let mut db = open_wallet_db(db_path, network)?;
        let account_id = stored.account_id;
        let account = db
            .get_account(account_id)
            .map_err(|e| format!("{e}"))?
            .ok_or("Account not found")?;
        let seed = SecretVec::new(seed_bytes.to_vec());
        let zip32_index = account
            .source()
            .key_derivation()
            .ok_or("No key derivation")?
            .account_index();
        let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
            .map_err(|e| format!("USK derivation failed: {e:?}"))?;

        let txids = match (spend_params_path, output_params_path) {
            (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
                let prover = LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
                create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
                    &mut db,
                    &network,
                    &prover,
                    &prover,
                    &wallet::SpendingKeys::from_unified_spending_key(usk),
                    OvkPolicy::Sender,
                    &stored.proposal,
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
                )
                .map_err(|e| format!("Create TX failed: {e}"))?
            }
        };
        // seed + usk dropped here, before broadcast
        Ok::<_, String>(txids)
    })?;

    let txids: Vec<TxId> = txids.iter().cloned().collect();
    broadcast_created_transactions(db_path, lightwalletd_url, &txids, "send").await
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
) -> Result<(Proposal<StandardFeeRule, Infallible>, Zatoshis), String> {
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
) -> Result<Proposal<StandardFeeRule, <WalletDatabase as InputSource>::NoteRef>, String> {
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
    let fee_rule = StandardFeeRule::Zip317;
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
    proposal: &Proposal<StandardFeeRule, NoteRef>,
) -> Result<SendMaxEstimateResult, String> {
    let amount_zatoshi = proposal.steps().iter().try_fold(0u64, |acc, step| {
        let step_total = step
            .transaction_request()
            .total()
            .map_err(|e| format!("Max amount calculation failed: {e}"))?;
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
    account_receivers: HashMap<TransparentAddress, (TransparentKeyScope, Balance)>,
    shielding_threshold: Zatoshis,
) -> Result<(Vec<TransparentAddress>, Zatoshis), String> {
    let mut ephemeral = Vec::new();
    let mut non_ephemeral = Vec::new();

    for (address, (scope, balance)) in account_receivers {
        let spendable = balance.spendable_value();
        if spendable > Zatoshis::ZERO {
            if scope == TransparentKeyScope::EPHEMERAL {
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

fn proposal_fee_zatoshi<NoteRef>(proposal: &Proposal<StandardFeeRule, NoteRef>) -> u64 {
    proposal
        .steps()
        .iter()
        .map(|step| u64::from(step.balance().fee_required()))
        .sum()
}

fn proposal_shielded_zatoshi(proposal: &Proposal<StandardFeeRule, Infallible>) -> u64 {
    proposal
        .steps()
        .iter()
        .flat_map(|step| step.balance().proposed_change().iter())
        .map(|change| u64::from(change.value()))
        .sum()
}

async fn broadcast_created_transactions(
    db_path: &str,
    lightwalletd_url: &str,
    txids: &[TxId],
    log_label: &str,
) -> Result<String, String> {
    // Connect to lightwalletd once for all broadcasts.
    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;

    let txid_strings: Vec<String> = txids.iter().map(|id| format!("{id}")).collect();

    let read_conn =
        open_readonly_conn(db_path).map_err(|e| format!("Failed to open DB for broadcast: {e}"))?;

    let mut broadcast_ok: Vec<String> = Vec::new();
    for txid in txids.iter() {
        let raw_tx = read_conn
            .query_row(
                "SELECT raw FROM transactions WHERE txid = ?1",
                rusqlite::params![txid.as_ref()],
                |row| row.get::<_, Vec<u8>>(0),
            )
            .map_err(|e| format!("Failed to get raw tx for {txid}: {e}"))?;

        match broadcast_raw_transaction(&mut client, &raw_tx).await {
            Ok(()) => {
                broadcast_ok.push(format!("{txid}"));
                log::info!("{log_label}: broadcast {txid} ({} bytes)", raw_tx.len());
            }
            Err(e) => {
                return Err(format!(
                    "Broadcast failed after {}/{} txs sent ({}). Error: {e}",
                    broadcast_ok.len(),
                    txids.len(),
                    broadcast_ok.join(",")
                ));
            }
        }
    }

    Ok(txid_strings.join(","))
}

/// Broadcast a raw transaction using an existing gRPC client.
async fn broadcast_raw_transaction(
    client: &mut zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient<tonic::transport::Channel>,
    raw_tx: &[u8],
) -> Result<(), String> {
    use zcash_client_backend::proto::service::RawTransaction;

    let resp = client
        .send_transaction(RawTransaction {
            data: raw_tx.to_vec(),
            height: 0,
        })
        .await
        .map_err(|e| format!("SendTransaction gRPC failed: {e}"))?
        .into_inner();

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
    MultiOutputChangeStrategy<StandardFeeRule, DbT>,
    GreedyInputSelector<DbT>,
) {
    (
        MultiOutputChangeStrategy::new(
            StandardFeeRule::Zip317,
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

    fn receiver(value: u64, scope: TransparentKeyScope) -> (TransparentKeyScope, Balance) {
        (scope, balance(value))
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
