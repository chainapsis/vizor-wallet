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

use secrecy::{ExposeSecret, SecretVec};
use shardtree::error::{QueryError, ShardTreeError};
use tonic::Code;
use transparent::{address::TransparentAddress, bundle::OutPoint, keys::TransparentKeyScope};
use zcash_client_backend::data_api::wallet::input_selection::{
    GreedyInputSelector, InputSelector, LockFilter, LockedInputPolicy, SpendPolicy,
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

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::keys::parse_account_uuid;
use crate::wallet::network::WalletNetwork;

use super::{
    consume_stored_proposal, open_readonly_conn, open_wallet_db, open_wallet_db_for_read,
    StoredProposal, WalletDatabase, PROPOSAL_STORE,
};

mod immediate_migration;
pub(crate) use immediate_migration::{
    get_plan as get_orchard_migration_immediate_plan,
    migrate as migrate_orchard_to_ironwood_immediately,
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct OrchardMigrationImmediatePlan {
    pub total_input_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub migrated_zatoshi: u64,
    pub input_note_count: u32,
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
    /// Estimated blocks from trusted preparation confirmation until the
    /// boundary containing the final prepared note becomes usable.
    pub proof_readiness_delay_blocks: u32,
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
/// the wallet's held proofs-PCZT for that id.
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
static ACTIVE_IRONWOOD_MIGRATIONS: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

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
    let spend_policy =
        ordinary_send_spend_policy(orchard_migration_active(db_path, network, account_uuid)?);
    let pass1_proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &spend_policy,
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
                &spend_policy,
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
    let spend_policy =
        ordinary_send_spend_policy(orchard_migration_active(db_path, network, account_uuid)?);
    let pass1_proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &spend_policy,
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
                &spend_policy,
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
    let spend_pools =
        ordinary_send_spend_pools(orchard_migration_active(db_path, network, account_uuid)?);
    let proposal = build_send_max_proposal(
        &mut db,
        network,
        account_id,
        to_address,
        memo_str,
        &spend_pools,
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
                        &proposal,
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

pub(super) struct ActiveIronwoodMigration {
    key: String,
}

impl ActiveIronwoodMigration {
    pub(super) fn acquire(db_path: &str, account_uuid: &str) -> Result<Self, String> {
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
        None,
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
    spend_policy: &SpendPolicy,
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
            spend_policy,
            proposed_tx_version,
        )
        .map_err(|e| format!("Propose failed: {e}"))
}

fn ordinary_send_spend_pools(migration_active: bool) -> Vec<ShieldedProtocol> {
    if migration_active {
        vec![ShieldedProtocol::Ironwood]
    } else {
        vec![
            ShieldedProtocol::Sapling,
            ShieldedProtocol::Orchard,
            ShieldedProtocol::Ironwood,
        ]
    }
}

fn orchard_migration_active(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<bool, String> {
    super::shared_migration::has_active_migration(db_path, network, account_uuid)
}

fn ordinary_send_spend_policy(migration_active: bool) -> SpendPolicy {
    SpendPolicy::shielded_pools(ordinary_send_spend_pools(migration_active))
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
}

impl ReservedInputSource<'_> {
    fn merged_excludes(&self, exclude: &[ReceivedNoteId]) -> Vec<ReceivedNoteId> {
        let mut merged = exclude.to_vec();
        merged.extend(self.reserved.iter().copied());
        merged.sort_unstable();
        merged.dedup();
        merged
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
        lock_filter: LockFilter<'_>,
    ) -> Result<Option<ReceivedNote<Self::NoteRef, Note>>, Self::Error> {
        Ok(self
            .inner
            .get_spendable_note(txid, protocol, index, target_height, lock_filter)?
            .filter(|note| !self.reserved.contains(note.internal_note_id())))
    }

    fn select_spendable_notes(
        &self,
        account: Self::AccountId,
        target_value: TargetValue,
        sources: &[ShieldedProtocol],
        target_height: wallet::TargetHeight,
        confirmations_policy: ConfirmationsPolicy,
        exclude: &[Self::NoteRef],
        lock_filter: LockFilter<'_>,
    ) -> Result<ReceivedNotes<Self::NoteRef>, Self::Error> {
        let selected = self.inner.select_spendable_notes(
            account,
            target_value,
            sources,
            target_height,
            confirmations_policy,
            &self.merged_excludes(exclude),
            lock_filter,
        )?;
        Ok(ReceivedNotes::new(
            selected.sapling().to_vec(),
            selected.orchard().to_vec(),
            selected.ironwood().to_vec(),
        ))
    }

    fn select_unspent_notes(
        &self,
        account: Self::AccountId,
        sources: &[ShieldedProtocol],
        target_height: wallet::TargetHeight,
        exclude: &[Self::NoteRef],
        lock_filter: LockFilter<'_>,
    ) -> Result<ReceivedNotes<Self::NoteRef>, Self::Error> {
        let selected = self.inner.select_unspent_notes(
            account,
            sources,
            target_height,
            &self.merged_excludes(exclude),
            lock_filter,
        )?;
        Ok(ReceivedNotes::new(
            selected.sapling().to_vec(),
            selected.orchard().to_vec(),
            selected.ironwood().to_vec(),
        ))
    }

    fn get_account_metadata(
        &self,
        account: Self::AccountId,
        selector: &NoteFilter,
        target_height: wallet::TargetHeight,
        exclude: &[Self::NoteRef],
        lock_filter: LockFilter<'_>,
    ) -> Result<AccountMeta, Self::Error> {
        self.inner.get_account_metadata(
            account,
            selector,
            target_height,
            &self.merged_excludes(exclude),
            lock_filter,
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
        lock_filter: LockFilter<'_>,
    ) -> Result<Vec<WalletTransparentOutput<Self::AccountId>>, Self::Error> {
        self.inner.get_spendable_transparent_outputs(
            address,
            target_height,
            confirmations_policy,
            output_filter,
            lock_filter,
        )
    }
}

fn build_send_max_proposal(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    to_address: &str,
    memo_str: Option<&str>,
    spend_pools: &[ShieldedProtocol],
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
            db,
            network,
            account_id,
            to,
            memo_bytes,
            fee_rule,
            spend_pools,
        );
    }

    propose_send_max_transfer::<_, _, _, Infallible>(
        db,
        &network,
        account_id,
        spend_pools,
        &fee_rule,
        to,
        memo_bytes,
        MaxSpendMode::MaxSpendable,
        ConfirmationsPolicy::default(),
        &LockedInputPolicy::Exclude,
        None,
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
    spend_pools: &[ShieldedProtocol],
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
            spend_pools,
            target_height,
            confirmations_policy,
            &[],
            LockFilter::Policy(&LockedInputPolicy::Exclude),
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
    let ironwood_input_count = spendable_notes.ironwood().len();

    let sapling_output_count = sapling_crypto::builder::BundleType::DEFAULT
        .num_outputs(sapling_input_count, 0)
        .map_err(|e| format!("Max Sapling bundle size failed: {e:?}"))?;
    // Count the two Orchard-family pools independently because V6 carries
    // legacy Orchard and Ironwood in separate bundles.
    let orchard_action_count = ::orchard::builder::BundleType::DEFAULT
        .num_actions(
            ::orchard::bundle::BundleVersion::orchard_v2().default_flags(),
            orchard_input_count,
            0,
        )
        .map_err(|e| format!("Max Orchard bundle size failed: {e:?}"))?;
    let ironwood_action_count = ::orchard::builder::BundleType::DEFAULT
        .num_actions(
            ::orchard::bundle::BundleVersion::ironwood_v3().default_flags(),
            ironwood_input_count,
            0,
        )
        .map_err(|e| format!("Max Ironwood bundle size failed: {e:?}"))?;

    let fee = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            [P2PKH_STANDARD_OUTPUT_SIZE],
            sapling_input_count,
            sapling_output_count,
            orchard_action_count,
            ironwood_action_count,
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
mod tests;
