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
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex, OnceLock,
};
use std::thread;
use std::time::Instant;

use rand::{rngs::OsRng, Rng};
use secrecy::{ExposeSecret, SecretVec};
use shardtree::{
    error::{QueryError, ShardTreeError},
    store::ShardStore,
};
use tonic::Code;
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
use crate::wallet::sync_engine;

use super::migration::MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI;
use super::{
    consume_stored_proposal, open_readonly_conn, open_wallet_db, open_wallet_db_for_read,
    StoredProposal, WalletDatabase, PROPOSAL_STORE,
};

const UNBROADCAST_MIGRATION_RECOVERY_SAFETY_BLOCKS: u32 = 10;

#[derive(Clone, Copy)]
struct MigrationBroadcastPolicy<'a> {
    max_per_step: Option<usize>,
    max_proofs_per_step: Option<usize>,
    defer_broadcast_after_proving: bool,
    cancel: Option<&'a AtomicBool>,
}

impl MigrationBroadcastPolicy<'_> {
    const FOREGROUND: Self = Self {
        max_per_step: None,
        max_proofs_per_step: None,
        defer_broadcast_after_proving: false,
        cancel: None,
    };

    const ONE_FOREGROUND: Self = Self {
        max_per_step: Some(1),
        max_proofs_per_step: None,
        defer_broadcast_after_proving: false,
        cancel: None,
    };

    fn background_preparation(cancel: &AtomicBool) -> MigrationBroadcastPolicy<'_> {
        MigrationBroadcastPolicy {
            max_per_step: None,
            max_proofs_per_step: None,
            defer_broadcast_after_proving: false,
            cancel: Some(cancel),
        }
    }

    fn is_cancelled(self) -> bool {
        self.cancel
            .is_some_and(|cancel| cancel.load(Ordering::SeqCst))
    }

    fn limit(self, total: usize) -> usize {
        self.max_per_step.unwrap_or(total).min(total)
    }

    fn proof_limit(self, total: usize) -> usize {
        self.max_proofs_per_step.unwrap_or(total).min(total)
    }

    fn should_defer_broadcast(self, proofs_created: usize) -> bool {
        self.defer_broadcast_after_proving && proofs_created > 0
    }
}

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

impl IronwoodMigrationResult {
    pub(crate) async fn prepare_outbox(
        db_path: &str,
        lightwalletd_url: &str,
        network: WalletNetwork,
        account_uuid: &str,
        pending_password: &[u8],
        pending_salt_base64: &str,
    ) -> Result<Self, String> {
        prepare_orchard_migration_outbox(
            db_path,
            lightwalletd_url,
            network,
            account_uuid,
            pending_password,
            pending_salt_base64,
        )
        .await
    }

    pub(crate) fn export_outbox(
        db_path: &str,
        network: WalletNetwork,
        account_uuid: &str,
        pending_password: &[u8],
        pending_salt_base64: &str,
    ) -> Result<Option<super::migration::MigrationOutboxBatch>, String> {
        super::migration::export_scheduled_migration_outbox(
            db_path,
            account_uuid,
            network,
            pending_password,
            pending_salt_base64,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn reconcile_outbox_receipt(
        db_path: &str,
        network: WalletNetwork,
        account_uuid: &str,
        run_id: &str,
        txid_hex: &str,
        outcome: &str,
        remote_height: u32,
        response_message: Option<&str>,
        schedule_updates: Vec<(String, u32, u32)>,
        accepted_raw_transaction: Option<Vec<u8>>,
    ) -> Result<(), String> {
        reconcile_orchard_migration_outbox_receipt(
            db_path,
            network,
            account_uuid,
            run_id,
            txid_hex,
            outcome,
            remote_height,
            response_message,
            schedule_updates,
            accepted_raw_transaction,
        )
    }
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
    let spend_policy = ordinary_send_spend_policy(
        super::migration::active_migration_run(db_path, account_uuid, network)?.is_some(),
    );
    let pass1_proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &migration_locks,
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
                &migration_locks,
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
    let migration_locks = super::migration::locked_migration_note_refs(db_path, account_uuid)?;
    let spend_policy = ordinary_send_spend_policy(
        super::migration::active_migration_run(db_path, account_uuid, network)?.is_some(),
    );
    let pass1_proposal = propose_send_with_reserved_notes(
        &db,
        network,
        account_id,
        request,
        &BTreeSet::new(),
        &migration_locks,
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
                &migration_locks,
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
    let spend_pools = ordinary_send_spend_pools(
        super::migration::active_migration_run(db_path, account_uuid, network)?.is_some(),
    );
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
            MigrationBroadcastPolicy::FOREGROUND,
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
                        MigrationBroadcastPolicy::FOREGROUND,
                    )?;
                    if finalized == 0 {
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
                    MigrationBroadcastPolicy::FOREGROUND,
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
        Some(&approved_schedule),
        pending_password.as_slice(),
        pending_salt_base64,
    )?;

    let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run_id,
        pending_password.as_slice(),
        pending_salt_base64,
        MigrationBroadcastPolicy::FOREGROUND,
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

/// Performs the user-selected Immediate migration as one foreground
/// Orchard-to-Ironwood transaction. Unlike the privacy migration this does
/// not create denomination stages, a migration run, or scheduled children.
pub(crate) async fn migrate_orchard_to_ironwood_immediately(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
    approved_plan: OrchardMigrationImmediatePlan,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err("An Ironwood migration is already in progress for this account".to_string());
    }

    let (base_pczt, orchard_spend_action_indices, fee_zatoshi, migrated_zatoshi) =
        with_wallet_db_write_lock("send.immediate_migration.build", || {
            let mut db = open_wallet_db(db_path, network)?;
            let account_id = parse_account_uuid(account_uuid)?;
            let account = db
                .get_account(account_id)
                .map_err(|e| format!("{e}"))?
                .ok_or("Account not found")?;
            let ufvk = account
                .ufvk()
                .ok_or("Account cannot create an Immediate migration")?;
            let account_derivation = account.source().key_derivation();
            let orchard_fvk = ufvk
                .orchard()
                .cloned()
                .ok_or("Orchard viewing key not available")?;
            let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);
            let internal_ovk = Some(orchard_fvk.to_ovk(orchard::keys::Scope::Internal));
            let (target_height, anchor_height) = db
                .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
                .map_err(|e| format!("Failed to read anchor height: {e}"))?
                .ok_or("Wallet must sync before migrating")?;
            let orchard_notes =
                select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
            let valued_notes = orchard_notes
                .into_iter()
                .map(|note| {
                    let value = note
                        .note_value()
                        .map(u64::from)
                        .map_err(|e| format!("{e}"))?;
                    Ok((note, value))
                })
                .collect::<Result<Vec<_>, String>>()?;
            let plan = immediate_migration_plan_for_values(
                network,
                target_height.into(),
                valued_notes.iter().map(|(_, value)| *value),
            )?
            .ok_or(
                "No spendable Orchard notes are available for Immediate migration".to_string(),
            )?;
            if plan != approved_plan {
                return Err(
                    "Immediate migration plan changed. Review the updated amount and fee."
                        .to_string(),
                );
            }
            let orchard_notes = valued_notes
                .into_iter()
                .filter_map(|(note, value)| (value > 0).then_some(note))
                .collect::<Vec<_>>();
            if orchard_notes.is_empty() {
                return Err(
                    "No spendable Orchard notes are available for Immediate migration".to_string(),
                );
            }
            let (orchard_anchor, orchard_inputs) = migration_orchard_witnesses(
                &mut db,
                network,
                BlockHeight::from(anchor_height),
                &orchard_notes,
            )?;
            let fee_rule = ConservativeZip317FeeRule;
            let make_builder = |amount: Zatoshis| {
                let mut builder = migration_child_builder(
                    network,
                    BlockHeight::from(target_height),
                    orchard_anchor.clone(),
                )?;
                for (note, merkle_path) in &orchard_inputs {
                    builder
                        .add_orchard_spend::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                            orchard_fvk.clone(),
                            *note,
                            merkle_path.clone(),
                        )
                        .map_err(|e| format!("Add Immediate Orchard spend failed: {e}"))?;
                }
                builder
                    .add_ironwood_output::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                        internal_ovk.clone(),
                        recipient,
                        amount,
                        MemoBytes::empty(),
                    )
                    .map_err(|e| format!("Add Immediate Ironwood output failed: {e}"))?;
                Ok::<_, String>(builder)
            };
            let minimum = Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
                .map_err(|_| "Bad Immediate migration minimum output")?;
            let fee = make_builder(minimum)?
                .get_fee(&fee_rule)
                .map_err(|e| format!("Estimate Immediate migration fee failed: {e}"))?;
            if u64::from(fee) != plan.fee_zatoshi {
                return Err("Immediate migration fee changed while building".to_string());
            }
            let amount = Zatoshis::from_u64(plan.migrated_zatoshi)
                .map_err(|_| "Bad Immediate migration output amount")?;
            let built = pczt_from_build_result(
                make_builder(amount)?
                    .build_for_pczt(rand_core::OsRng, &fee_rule)
                    .map_err(|e| format!("Build Immediate migration PCZT failed: {e}"))?,
                network,
                account_derivation,
                orchard_inputs.len(),
                0,
            )?;
            Ok::<_, String>((
                built.bytes,
                built.orchard_spend_action_indices,
                plan.fee_zatoshi,
                plan.migrated_zatoshi,
            ))
        })?;
    let usk = derive_migration_usk(db_path, network, account_uuid, seed)?;
    let signed =
        sign_orchard_migration_pczt_with_usk(&base_pczt, &orchard_spend_action_indices, &usk)?;
    let sigs = super::pczt::extract_required_compact_sigs_from_signed_pczt(&base_pczt, &signed)?;
    super::pczt::preflight_orchard_spend_auth_signatures(&base_pczt, &sigs)?;
    let proofed = super::pczt::add_proofs_to_pczt(&base_pczt, None, None)?;
    let extracted = super::pczt::apply_sigs_and_extract(&proofed, &sigs, None, None)?;
    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| format!("Connect to lightwalletd for Immediate migration failed: {e}"))?;
    let response = match crate::wallet::sync_engine::send_transaction_with_status(
        &mut client,
        &extracted.raw_tx,
    )
    .await
    {
        Ok(response) => response,
        Err(status) if status.code() == Code::DeadlineExceeded => {
            let storage_message = match decrypt_and_store_migration_tx(
                db_path,
                network,
                &extracted.raw_tx,
            ) {
                Ok(()) => {
                    "The transaction was stored locally and will retry automatically during sync."
                        .to_string()
                }
                Err(error) => format!("Local tracking also failed: {error}"),
            };
            return Ok(IronwoodMigrationResult {
                txids: extracted.txid.to_string(),
                status: CreatedBroadcastResult::PENDING_BROADCAST.to_string(),
                broadcasted_count: 0,
                total_count: 1,
                message: Some(format!(
                    "The Immediate migration broadcast timed out and may already be on the network. {storage_message}"
                )),
                fee_zatoshi,
                migrated_zatoshi,
            });
        }
        Err(status) => {
            return Err(format!(
                "Immediate migration broadcast failed before acceptance: {status}"
            ));
        }
    };
    if let Some(error) = super::broadcast::send_response_rejection_error(&response) {
        return Err(error);
    }
    let storage_error = decrypt_and_store_migration_tx(db_path, network, &extracted.raw_tx).err();

    Ok(IronwoodMigrationResult {
        txids: extracted.txid.to_string(),
        status: super::migration::PHASE_BROADCASTING.to_string(),
        broadcasted_count: 1,
        total_count: 1,
        message: storage_error.map(|error| {
            format!(
                "The Immediate migration was accepted, but local tracking failed: {error}. Sync will recover the transaction."
            )
        }),
        fee_zatoshi,
        migrated_zatoshi,
    })
}

fn validate_unbroadcast_migration_recovery_candidates(
    candidates: &[super::migration::UnbroadcastMigrationRecoveryCandidate],
    chain_tip_height: u32,
) -> Result<(), String> {
    for candidate in candidates {
        if candidate.status != "scheduled" {
            return Err(format!(
                "Migration transaction {} was already marked as broadcasted",
                candidate.txid_hex
            ));
        }
        let safe_recovery_height = candidate
            .scheduled_height
            .checked_add(UNBROADCAST_MIGRATION_RECOVERY_SAFETY_BLOCKS)
            .ok_or("Migration recovery safety height overflow")?;
        if chain_tip_height < safe_recovery_height {
            return Err(format!(
                "Migration recovery must wait until block {safe_recovery_height}"
            ));
        }
    }
    Ok(())
}

pub(crate) async fn retire_unbroadcast_orchard_migration(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
) -> Result<(), String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let candidates = super::migration::unbroadcast_migration_recovery_candidates(
        db_path,
        account_uuid,
        network,
        expected_run_id,
    )?;
    let mut client = sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| format!("Open migration recovery endpoint: {e}"))?;
    let chain_tip = sync_engine::get_latest_block(&mut client)
        .await
        .map_err(|e| format!("Read migration recovery chain tip: {e}"))?;
    let chain_tip_height =
        u32::try_from(chain_tip.height).map_err(|_| "Migration recovery chain tip exceeds u32")?;
    validate_unbroadcast_migration_recovery_candidates(&candidates, chain_tip_height)?;

    for candidate in &candidates {
        let txid = parse_txid_hex(&candidate.txid_hex)?;
        match sync_engine::get_transaction(&mut client, txid.as_ref().to_vec()).await {
            Ok(_) => {
                return Err(format!(
                    "Migration transaction {} is present in the mempool or chain",
                    candidate.txid_hex
                ));
            }
            Err(status) if status.code() == Code::NotFound => {}
            Err(status) => {
                return Err(format!(
                    "Could not verify migration transaction {}: {status}",
                    candidate.txid_hex
                ));
            }
        }
    }

    super::migration::retire_run_for_rebuild(
        db_path,
        expected_run_id,
        "The previous signed migration transactions were absent after their broadcast windows. Rebuilding with a new credential.",
    )
}

async fn prepare_orchard_migration_outbox(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    pending_password: &[u8],
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
        pending_password,
        pending_salt_base64,
        MigrationBroadcastPolicy::FOREGROUND,
    )
    .await?
    {
        StagedDenominationAdvance::Waiting(result) => return Ok(result),
        StagedDenominationAdvance::Ready => {}
    }

    let chain_tip_height =
        u32::try_from(super::get_sync_progress(db_path, network)?.chain_tip_height)
            .map_err(|_| "Migration chain tip exceeds u32".to_string())?;
    if let Some(message) =
        pending_migration_policy_rebuild_message(db_path, network, &run.run_id, chain_tip_height)?
    {
        super::migration::retire_run_for_rebuild(db_path, &run.run_id, &message)?;
        let totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
        return Ok(migration_result_from_pending_totals(
            totals,
            super::migration::PHASE_FAILED_TERMINAL,
            Some(message),
            run.target_values_zatoshi.len() as u32,
            run.target_values_zatoshi.iter().sum(),
        ));
    }
    let expired_count = super::migration::mark_expired_pending_parts_for_resign(
        db_path,
        &run.run_id,
        chain_tip_height,
    )?;
    if expired_count > 0 {
        let totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
        return Ok(migration_result_from_pending_totals(
            totals,
            super::migration::PHASE_READY_TO_MIGRATE,
            Some(format!(
                "{expired_count} migration transaction(s) need fresh signatures before outbox export."
            )),
            run.target_values_zatoshi.len() as u32,
            run.target_values_zatoshi.iter().sum(),
        ));
    }

    if super::migration::signed_child_pczt_count(db_path, &run.run_id)? > 0
        && run_may_finalize_presigned_migration_children(&run)
    {
        finalize_presigned_migration_children(
            db_path,
            network,
            account_uuid,
            &run.run_id,
            pending_password,
            pending_salt_base64,
            MigrationBroadcastPolicy::FOREGROUND,
        )?;
    }

    let totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
    let status = super::migration::run_phase(db_path, &run.run_id)?;
    let message = if super::migration::signed_child_pczt_count(db_path, &run.run_id)? > 0 {
        "Migration proofs will continue when the next anchor is ready."
    } else if totals.total_count > 0 {
        "Migration transactions are prepared for the Swift outbox."
    } else {
        "No migration transactions are ready for outbox export yet."
    };
    Ok(migration_result_from_pending_totals(
        totals,
        &status,
        Some(message.to_string()),
        run.target_values_zatoshi.len() as u32,
        run.target_values_zatoshi.iter().sum(),
    ))
}

/// Advances only the denomination preparation graph for an existing migration.
///
/// This deliberately stops at `ready_to_migrate`: child proof creation stays
/// in the foreground, while prepared migration transaction broadcast belongs
/// to the separate mobile outbox lane.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn advance_orchard_migration_preparation_for_run(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
    cancel: &AtomicBool,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let Some(run) = super::migration::active_migration_run(db_path, account_uuid, network)? else {
        return Err("Ironwood migration preparation has no active run".to_string());
    };
    if run.run_id != expected_run_id {
        return Err("Ironwood migration preparation run changed".to_string());
    }

    if run.phase != super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS {
        return Ok(IronwoodMigrationResult {
            txids: String::new(),
            status: run.phase.clone(),
            broadcasted_count: 0,
            total_count: run.target_values_zatoshi.len() as u32,
            message: None,
            fee_zatoshi: 0,
            migrated_zatoshi: run.target_values_zatoshi.iter().sum(),
        });
    }

    match advance_staged_denomination_run(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        &run,
        pending_password.as_slice(),
        pending_salt_base64,
        MigrationBroadcastPolicy::background_preparation(cancel),
    )
    .await?
    {
        StagedDenominationAdvance::Waiting(result) => Ok(result),
        StagedDenominationAdvance::Ready => {
            let timing_policy =
                super::migration::timing_policy_for_run(db_path, &run.run_id, network)?;
            let proof_ready_height = super::migration::prepared_notes_proof_ready_height(
                db_path,
                &run.run_id,
                network,
                timing_policy,
            )?
            .ok_or("Prepared denomination notes are missing their mined height")?;
            super::migration::set_proof_retry_height(db_path, &run.run_id, proof_ready_height)?;
            Ok(IronwoodMigrationResult {
                txids: String::new(),
                status: super::migration::PHASE_READY_TO_MIGRATE.to_string(),
                broadcasted_count: 0,
                total_count: run.target_values_zatoshi.len() as u32,
                message: None,
                fee_zatoshi: 0,
                migrated_zatoshi: run.target_values_zatoshi.iter().sum(),
            })
        }
    }
}

pub async fn broadcast_due_orchard_migration_transactions(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    broadcast_due_orchard_migration_transactions_inner(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        pending_password,
        pending_salt_base64,
        MigrationBroadcastPolicy::FOREGROUND,
    )
    .await
}

pub async fn broadcast_one_due_orchard_migration_transaction(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    broadcast_due_orchard_migration_transactions_inner(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        pending_password,
        pending_salt_base64,
        MigrationBroadcastPolicy::ONE_FOREGROUND,
    )
    .await
}

async fn broadcast_due_orchard_migration_transactions_inner(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
    policy: MigrationBroadcastPolicy<'_>,
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
    if policy.is_cancelled() {
        return Ok(cancelled_migration_result(&run));
    }

    // Reconcile chain changes before deciding whether an already-scheduled
    // child is still valid. Independent due children should not miss their
    // broadcast height while another denomination branch is still advancing.
    super::migration::reconcile_denomination_stage_chain_state(db_path, &run.run_id)?;
    let chain_tip_height =
        u32::try_from(super::get_sync_progress(db_path, network)?.chain_tip_height)
            .map_err(|_| "Migration chain tip exceeds u32".to_string())?;
    if super::migration::due_scheduled_pending_count(db_path, &run.run_id, chain_tip_height)? > 0 {
        return broadcast_due_scheduled_migration_txs(
            db_path,
            lightwalletd_url,
            network,
            &run.run_id,
            pending_password.as_slice(),
            pending_salt_base64,
            run.target_values_zatoshi.len() as u32,
            run.target_values_zatoshi.iter().sum(),
            policy,
        )
        .await;
    }

    match advance_staged_denomination_run(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        &run,
        pending_password.as_slice(),
        pending_salt_base64,
        policy,
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
            policy,
        )?;
        if finalized == 0 || policy.should_defer_broadcast(finalized) {
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
        policy,
    )
    .await
}

include!("send/ironwood_migration.rs");

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

fn orchard_checkpoint_heights(db: &mut WalletDatabase) -> Result<Vec<u32>, String> {
    let result: Result<Vec<u32>, ShardTreeError<commitment_tree::Error>> = db
        .with_orchard_tree_mut(|tree| {
            let checkpoint_count = tree
                .store()
                .checkpoint_count()
                .map_err(ShardTreeError::Storage)?;
            let mut heights = Vec::with_capacity(checkpoint_count);
            tree.store()
                .for_each_checkpoint(checkpoint_count, |height, _| {
                    heights.push(u32::from(*height));
                    Ok(())
                })
                .map_err(ShardTreeError::Storage)?;
            Ok(heights)
        });
    result.map_err(|e| format!("Read Orchard checkpoint heights: {e:?}"))
}

fn representative_orchard_checkpoint(
    checkpoint_heights: &[u32],
    logical_boundary_height: u32,
    note_mined_height: u32,
) -> Option<u32> {
    checkpoint_heights
        .iter()
        .copied()
        .filter(|height| *height >= note_mined_height && *height <= logical_boundary_height)
        .max()
}

fn available_orchard_anchor_candidates(
    logical_boundaries: &[u32],
    checkpoint_heights: &[u32],
    note_mined_height: u32,
) -> Vec<(u32, u32)> {
    let mut seen_checkpoints = BTreeSet::new();
    logical_boundaries
        .iter()
        .filter_map(|boundary| {
            let checkpoint = representative_orchard_checkpoint(
                checkpoint_heights,
                *boundary,
                note_mined_height,
            )?;
            // Several empty ZIP 318 buckets can share one Orchard root. Treat
            // that root as one cohort instead of multiplying its draw weight
            // and per-cohort allowance under different logical heights.
            seen_checkpoints
                .insert(checkpoint)
                .then_some((*boundary, checkpoint))
        })
        .collect()
}

fn retain_orchard_checkpoint(
    db: &mut WalletDatabase,
    checkpoint_height: u32,
) -> Result<(), String> {
    let result: Result<(), ShardTreeError<commitment_tree::Error>> =
        db.with_orchard_tree_mut(|tree| tree.ensure_retained(BlockHeight::from(checkpoint_height)));
    result.map_err(|e| format!("Retain Orchard migration checkpoint: {e:?}"))
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

fn ordinary_send_spend_policy(migration_active: bool) -> SpendPolicy {
    SpendPolicy::shielded_pools(ordinary_send_spend_pools(migration_active))
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
    timing_policy: super::migration::MigrationTimingPolicy,
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
    let checkpoint_heights = orchard_checkpoint_heights(&mut db)?;
    // The ZIP 318 bucket is a logical chain height. Empty blocks do not always
    // create an Orchard checkpoint, so the tree root for a bucket can live at
    // the last checkpoint before that boundary. Preserve the newest such root
    // while it is still young; one bucket later it becomes eligible instead of
    // being pruned before the proof attempt.
    if let Some(latest_boundary) = super::migration::zip318_anchor_boundary_at_or_before_with_policy(
        network,
        timing_policy,
        anchor_height_u32,
    ) {
        if let Some(checkpoint_height) =
            representative_orchard_checkpoint(&checkpoint_heights, latest_boundary, mined_height)
        {
            retain_orchard_checkpoint(&mut db, checkpoint_height)?;
        }
    }
    let policy_candidates = super::migration::zip318_anchor_candidate_boundaries_with_policy(
        network,
        timing_policy,
        anchor_height_u32,
        mined_height,
        nu6_3_activation_height,
    );
    let available_anchor_candidates =
        available_orchard_anchor_candidates(&policy_candidates, &checkpoint_heights, mined_height);
    let available_candidates = available_anchor_candidates
        .iter()
        .map(|(boundary, _)| *boundary)
        .collect::<Vec<_>>();
    let mut checkpoint_cohort_counts = BTreeMap::<u32, u32>::new();
    for (boundary, count) in anchor_cohort_counts.iter() {
        if let Some(checkpoint) =
            representative_orchard_checkpoint(&checkpoint_heights, *boundary, mined_height)
        {
            let cohort_count = checkpoint_cohort_counts.entry(checkpoint).or_default();
            *cohort_count = cohort_count
                .checked_add(*count)
                .ok_or("Migration anchor cohort count overflow")?;
        }
    }
    let draw_cohort_counts = available_anchor_candidates
        .iter()
        .map(|(boundary, checkpoint)| {
            (
                *boundary,
                checkpoint_cohort_counts
                    .get(checkpoint)
                    .copied()
                    .unwrap_or_default(),
            )
        })
        .collect::<BTreeMap<_, _>>();
    let anchor_boundary_height = preferred_anchor_boundary_height
        .filter(|boundary| {
            available_anchor_candidates
                .iter()
                .find(|(candidate, _)| candidate == boundary)
                .is_some_and(|(_, checkpoint)| {
                    checkpoint_cohort_counts
                        .get(checkpoint)
                        .copied()
                        .unwrap_or_default()
                        < super::migration::ZIP318_MAX_PARTS_PER_ANCHOR_COHORT
                })
                && super::migration::zip318_anchor_boundary_is_candidate_with_policy(
                    network,
                    timing_policy,
                    *boundary,
                    anchor_height_u32,
                    mined_height,
                    nu6_3_activation_height,
                )
                && available_candidates.contains(boundary)
        })
        .or_else(|| {
            super::migration::zip318_draw_anchor_boundary_from_available_with_policy(
                network,
                timing_policy,
                anchor_height_u32,
                &available_candidates,
                &draw_cohort_counts,
            )
        });
    let Some(anchor_boundary_height) = anchor_boundary_height else {
        return Ok(None);
    };
    let checkpoint_height = available_anchor_candidates
        .iter()
        .find_map(|(boundary, checkpoint)| {
            (*boundary == anchor_boundary_height).then_some(*checkpoint)
        })
        .ok_or("Orchard migration checkpoint disappeared during anchor selection")?;
    retain_orchard_checkpoint(&mut db, checkpoint_height)?;
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
        BlockHeight::from(checkpoint_height),
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
    let timing_policy = super::migration::timing_policy_for_run(db_path, run_id, network)?;
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
            timing_policy,
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
                part_index: recovery.part_index,
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
    policy: MigrationBroadcastPolicy<'_>,
) -> Result<usize, String> {
    if super::migration::signed_child_pczt_count(db_path, run_id)? == 0 {
        return Ok(0);
    }
    if !prepared_note_spend_metadata_is_available(db_path, run_id)? {
        let timing_policy = super::migration::timing_policy_for_run(db_path, run_id, network)?;
        if let Some(retry_height) = super::migration::prepared_notes_proof_ready_height(
            db_path,
            run_id,
            network,
            timing_policy,
        )? {
            super::migration::set_proof_retry_height(db_path, run_id, retry_height)?;
        }
        return Ok(0);
    }

    let signed_children = super::migration::signed_child_pczts_for_run(
        db_path,
        run_id,
        pending_password,
        pending_salt_base64,
    )?;
    if signed_children.is_empty() {
        return Ok(0);
    }

    let current_prepared = super::migration::prepared_notes_for_run(db_path, run_id)?;
    let timing_policy = super::migration::timing_policy_for_run(db_path, run_id, network)?;
    let already_pending = super::migration::pending_migration_note_outpoints(db_path, run_id)?;
    let mut anchor_cohort_counts = super::migration::pending_anchor_cohort_counts(db_path, run_id)?;
    let signed_child_count = signed_children.len();
    let proof_limit = policy.proof_limit(signed_child_count);
    let mut finalized_count = 0usize;
    let mut deferred_child_seen = false;
    let mut stopped_at_proof_limit = false;
    for (child_index, child) in signed_children.into_iter().enumerate() {
        if policy.is_cancelled() {
            break;
        }
        if finalized_count >= proof_limit {
            stopped_at_proof_limit = true;
            break;
        }
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
        let mut candidate_anchor_cohort_counts = anchor_cohort_counts.clone();
        let Some((anchor_boundary_height, orchard_anchor, orchard_witness)) =
            (match orchard_anchor_and_witness_for_prepared_note(
                db_path,
                network,
                account_uuid,
                current_note,
                child.anchor_boundary_height,
                timing_policy,
                &mut candidate_anchor_cohort_counts,
            ) {
                Ok(result) => result,
                Err(e) if is_orchard_witness_not_ready_error(&e) => {
                    deferred_child_seen = true;
                    continue;
                }
                Err(e) => return Err(e),
            })
        else {
            deferred_child_seen = true;
            continue;
        };
        anchor_cohort_counts = candidate_anchor_cohort_counts;
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
        let pending_insert = super::migration::PendingMigrationTxInsert {
            part_index: child.child_index,
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
        };
        // Persist each completed proof independently so an OS expiration loses
        // at most the proof that is currently in flight.
        super::migration::promote_signed_child_pczts_to_pending_txs(
            db_path,
            run_id,
            vec![pending_insert],
            pending_password,
            pending_salt_base64,
        )?;
        finalized_count = finalized_count
            .checked_add(1)
            .ok_or("Finalized migration proof count overflow")?;
    }

    if deferred_child_seen && !stopped_at_proof_limit && !policy.is_cancelled() {
        let mut retry_height = super::migration::next_anchor_retry_height_after(
            network,
            timing_policy,
            current_migration_scanned_height(db_path, network)?,
        )?;
        if let Some(ready_height) = super::migration::prepared_notes_proof_ready_height(
            db_path,
            run_id,
            network,
            timing_policy,
        )? {
            retry_height = retry_height.max(ready_height);
        }
        defer_presigned_proof_until(db_path, run_id, retry_height)?;
    }

    Ok(finalized_count)
}

fn finalize_ready_denomination_stages(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
    policy: MigrationBroadcastPolicy<'_>,
) -> Result<usize, String> {
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
        return Ok(0);
    }

    let awaiting_count = stages
        .iter()
        .filter(|stage| stage.status == super::migration::DenominationStageStatus::AwaitingInputs)
        .count();
    let proof_limit = policy.proof_limit(awaiting_count);
    let mut promoted_count = 0usize;
    for stage in stages
        .iter()
        .filter(|stage| stage.status == super::migration::DenominationStageStatus::AwaitingInputs)
    {
        if policy.is_cancelled() || promoted_count >= proof_limit {
            break;
        }
        let Some((anchor, witnesses)) = (match orchard_anchor_and_witnesses_for_denomination_inputs(
            db_path,
            network,
            account_uuid,
            &stage.inputs,
        ) {
            Ok(result) => result,
            Err(e) if is_orchard_witness_not_ready_error(&e) => return Ok(promoted_count),
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
        promoted_count = promoted_count
            .checked_add(1)
            .ok_or("Finalized denomination proof count overflow")?;
    }
    Ok(promoted_count)
}

async fn broadcast_pending_denomination_stages(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
    policy: MigrationBroadcastPolicy<'_>,
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
    if policy.is_cancelled() {
        return Ok(Some(CreatedBroadcastResult {
            txids,
            status: CreatedBroadcastResult::PENDING_BROADCAST,
            broadcasted_count: 0,
            total_count,
            message: Some(
                "Background migration stopped before denomination broadcast.".to_string(),
            ),
        }));
    }
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
    for stage in pending.iter().take(policy.limit(pending.len())) {
        if policy.is_cancelled() {
            break;
        }
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
        status: if broadcasted_count == 0 {
            CreatedBroadcastResult::PENDING_BROADCAST
        } else {
            super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS
        },
        broadcasted_count,
        total_count,
        message: Some(if policy.is_cancelled() {
            "Background migration stopped before the next denomination broadcast.".to_string()
        } else if broadcasted_count < total_count && policy.max_per_step.is_some() {
            "One denomination stage was submitted. Remaining stages will continue in later background runs."
                .to_string()
        } else if total_count == 1 {
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
    policy: MigrationBroadcastPolicy<'_>,
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
        let status = super::migration::run_phase(db_path, run_id)?;
        let message = if status == super::migration::PHASE_BROADCAST_SCHEDULED
            && super::migration::next_scheduled_height(db_path, run_id)?.is_none()
        {
            "Migration is waiting to prepare the next transaction."
        } else {
            "Migration transactions are scheduled for delayed broadcast."
        };
        return Ok(migration_result_from_pending_totals(
            totals_before,
            &status,
            Some(message.to_string()),
            fallback_total_count,
            fallback_migrated_zatoshi,
        ));
    }
    if policy.is_cancelled() {
        return Ok(migration_result_from_pending_totals(
            totals_before,
            super::migration::PHASE_BROADCAST_SCHEDULED,
            Some("Background migration stopped before the next broadcast.".to_string()),
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
    for pending in due.into_iter().take(policy.limit(usize::MAX)) {
        if policy.is_cancelled() {
            super::migration::mark_run_phase(
                db_path,
                run_id,
                super::migration::PHASE_BROADCAST_SCHEDULED,
                Some("Background migration stopped before the next broadcast."),
            )?;
            break;
        }
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
    let status = super::migration::run_phase(db_path, run_id)?;
    let message = if scheduled_remaining > 0 {
        "Due migration transactions were submitted. More are scheduled.".to_string()
    } else if status == super::migration::PHASE_BROADCAST_SCHEDULED {
        "Due migration transactions were submitted. More proofs remain to prepare.".to_string()
    } else {
        "Migration transactions were broadcast on the saved schedule.".to_string()
    };
    Ok(migration_result_from_pending_totals(
        totals,
        &status,
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

#[allow(clippy::too_many_arguments)]
fn reconcile_orchard_migration_outbox_receipt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run_id: &str,
    txid_hex: &str,
    outcome: &str,
    remote_height: u32,
    response_message: Option<&str>,
    schedule_updates: Vec<(String, u32, u32)>,
    accepted_raw_transaction: Option<Vec<u8>>,
) -> Result<(), String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let state = super::migration::migration_outbox_tx_state(
        db_path,
        account_uuid,
        network,
        run_id,
        txid_hex,
    )?;
    match outcome {
        "accepted" | "acceptedEquivalent" => {
            if state.run_phase == super::migration::PHASE_FAILED_TERMINAL
                || state.run_phase == super::migration::PHASE_ABANDONED
            {
                return Err(
                    "Migration outbox receipt cannot accept a retired migration run".to_string(),
                );
            }
            let raw_tx = accepted_raw_transaction.ok_or_else(|| {
                "Accepted migration outbox receipt is missing its raw transaction".to_string()
            })?;
            let actual_txid = {
                use zcash_primitives::transaction::Transaction;
                use zcash_protocol::consensus::BranchId;

                let tx = Transaction::read(&raw_tx[..], BranchId::Sapling)
                    .map_err(|e| format!("Failed to read accepted migration transaction: {e}"))?;
                tx.txid().to_string()
            };
            if !actual_txid.eq_ignore_ascii_case(txid_hex) {
                return Err(format!(
                    "Accepted migration outbox transaction ID mismatch: expected {txid_hex}, got {actual_txid}"
                ));
            }
            decrypt_and_store_migration_tx(db_path, network, &raw_tx)?;
            let schedule_updates = schedule_updates
                .into_iter()
                .map(|(item_id, scheduled_height, schedule_start_height)| {
                    super::migration::MigrationOutboxScheduleUpdate {
                        item_id,
                        scheduled_height,
                        schedule_start_height,
                    }
                })
                .collect::<Vec<_>>();
            super::migration::apply_accepted_migration_outbox_receipt(
                db_path,
                account_uuid,
                network,
                run_id,
                txid_hex,
                remote_height,
                &schedule_updates,
            )
        }
        "rejected" => {
            if !schedule_updates.is_empty() {
                return Err("Rejected migration outbox receipt cannot update schedules".to_string());
            }
            if state.run_phase == super::migration::PHASE_FAILED_TERMINAL {
                return Ok(());
            }
            let message = response_message
                .filter(|message| !message.is_empty())
                .map(|message| {
                    format!("Swift outbox rejected migration transaction {txid_hex}: {message}")
                })
                .unwrap_or_else(|| {
                    format!("Swift outbox rejected migration transaction {txid_hex}")
                });
            super::migration::retire_run_for_rebuild(db_path, run_id, &message)
        }
        "expired" => {
            if !schedule_updates.is_empty() {
                return Err("Expired migration outbox receipt cannot update schedules".to_string());
            }
            if state.expiry_height == 0 || state.expiry_height > remote_height {
                return Err(
                    "Migration outbox receipt expired before the transaction expiry height"
                        .to_string(),
                );
            }
            if state.status == "needs_resign" {
                return Ok(());
            }
            if !matches!(state.status.as_str(), "scheduled" | "broadcasted") {
                return Err(format!(
                    "Migration outbox receipt cannot expire a transaction in status {}",
                    state.status
                ));
            }
            let updated = super::migration::mark_expired_pending_parts_for_resign(
                db_path,
                run_id,
                remote_height,
            )?;
            if updated == 0 {
                return Err(
                    "Migration outbox expiry receipt did not find an expired transaction"
                        .to_string(),
                );
            }
            Ok(())
        }
        _ => Err(format!(
            "Unsupported migration outbox receipt outcome: {outcome}"
        )),
    }
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
mod tests;
