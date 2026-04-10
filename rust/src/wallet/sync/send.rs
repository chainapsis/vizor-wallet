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

use std::convert::Infallible;
use std::num::NonZeroUsize;

use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::{
    data_api::{
        Account as _, InputSource, WalletRead,
        wallet::{self, ConfirmationsPolicy, create_proposed_transactions, propose_transfer},
    },
    fees::{
        DustOutputPolicy, SplitPolicy, StandardFeeRule,
        zip317::MultiOutputChangeStrategy,
    },
    wallet::OvkPolicy,
    zip321::{Payment, TransactionRequest},
};
use zcash_client_backend::data_api::wallet::input_selection::GreedyInputSelector;
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::{
    ShieldedProtocol,
    consensus::Network,
    memo::{Memo, MemoBytes},
    value::Zatoshis,
};

use crate::wallet::keys::parse_account_uuid;

use super::{
    open_wallet_db, StoredProposal, WalletDatabase, PROPOSAL_STORE,
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

pub fn propose_send(
    db_path: &str,
    network: Network,
    account_uuid: &str,
    to_address: &str,
    amount_zatoshi: u64,
    memo_str: Option<&str>,
) -> Result<ProposalResult, String> {
    use zcash_protocol::{PoolType, ShieldedProtocol as SP};

    let mut db = open_wallet_db(db_path, network)?;
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
    let mut store = PROPOSAL_STORE.lock().map_err(|e| format!("Lock error: {e}"))?;
    let id = store.next_id;
    store.next_id += 1;
    store.proposals.insert(
        id,
        StoredProposal {
            proposal,
            network,
            account_id,
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
    network: Network,
    account_uuid: &str,
    to_address: &str,
    amount_zatoshi: u64,
    memo_str: Option<&str>,
) -> Result<u64, String> {
    let mut db = open_wallet_db(db_path, network)?;
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
    seed_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<String, String> {
    let mut store = PROPOSAL_STORE.lock().map_err(|e| format!("Lock error: {e}"))?;
    let stored = store
        .proposals
        .remove(&proposal_id)
        .ok_or("Proposal not found (expired or already executed)")?;
    let network = stored.network;
    drop(store);

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = stored.account_id;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;

    // Scope seed/USK so they are dropped before network I/O (broadcast).
    let txids = {
        let seed = SecretVec::new(seed_bytes.to_vec());
        let zip32_index = account
            .source()
            .key_derivation()
            .ok_or("No key derivation")?
            .account_index();
        let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
            .map_err(|e| format!("USK derivation failed: {e:?}"))?;

        match (spend_params_path, output_params_path) {
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
        }
        // seed + usk dropped here, before broadcast
    };

    // Connect to lightwalletd once for all broadcasts.
    let (mut client, _tor_guard) =
        crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
            .await
            .map_err(|e| e.to_string())?;

    // Broadcast each transaction.
    let txid_strings: Vec<String> = txids.iter().map(|id| format!("{id}")).collect();

    let read_conn = rusqlite::Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
    )
    .map_err(|e| format!("Failed to open DB for broadcast: {e}"))?;

    let mut broadcast_ok: Vec<String> = Vec::new();
    for txid in &txids {
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
                log::info!("send: broadcast {txid} ({} bytes)", raw_tx.len());
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
#[allow(dead_code)] // consumed by run_sync_impl in commit 3.3
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
/// The caller owns the gRPC client. In the sync loop the same
/// client that downloaded the compact blocks is threaded straight
/// through, so auto-resubmit inherits the same transport (plain
/// TLS or Tor) and the same connection state. That matters for Tor
/// — spawning a fresh isolated circuit per resubmit pass would
/// defeat the point of sharing a client with the active scan.
///
/// Logging uses `log::info!` for the "broadcasting N txs" entry
/// and `log::warn!` for per-tx failures / retries so an operator
/// can grep the live-stream log for `resubmit:` and see what the
/// wallet is doing without enabling DEBUG everywhere.
#[allow(dead_code)] // consumed by run_sync_impl in commit 3.3
pub(crate) async fn resubmit_pending_transactions(
    db_path: &str,
    client: &mut zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient<tonic::transport::Channel>,
    current_height: u32,
) -> ResubmitStats {
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
                // `TRANSACTION_RESUBMIT_RETRIES = 1`. Any remaining
                // failure is logged and counted; the next sync
                // batch will try again from scratch.
                log::warn!("resubmit: {txid_hex} first attempt failed: {first_err}");
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
    Diversifier, MerklePath, PaymentAddress, ProofGenerationKey, Rseed,
    bundle::GrothProofBytes,
    circuit,
    keys::EphemeralSecretKey,
    prover::{OutputProver, SpendProver},
    value::{NoteValue, ValueCommitTrapdoor},
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
