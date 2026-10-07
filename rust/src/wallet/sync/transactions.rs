//! Read-only transaction / balance / pending-tx query surface.
//!
//! Everything in this module is an "ask the wallet a question"
//! helper that the FRB layer in `api/sync.rs` or the C FFI layer in
//! `ffi.rs` calls per user action:
//!
//! - Balance queries (`get_wallet_balance`).
//! - Transaction list + on-chain enhancement requests
//!   (`get_transaction_history`, `get_transaction_data_requests`,
//!   `decrypt_and_store_transaction`, `set_transaction_status`).
//!
//! None of these belong to the orchestration loop — the loop lives
//! in `sync_engine/mod.rs`. They're one-shot lookups the UI drives
//! directly, so extracting them into their own submodule keeps
//! `sync/mod.rs` focused on per-wallet infrastructure (DB open,
//! chain-tip update, scan range management) and the shared
//! PROPOSAL_STORE used by both the software and PCZT send paths.

use std::{
    collections::{HashMap, HashSet},
    ops::Range,
    rc::Rc,
};

use rusqlite::{types::Value, vtab::array::Array, OptionalExtension};
use transparent::address::TransparentAddress;
#[cfg(test)]
use zcash_client_backend::data_api::transparent_ledger::WholeTransactionFee;
use zcash_client_backend::data_api::{
    transparent_ledger::{
        AggregatePayment, DetailCompleteness, FeeState, HistoryClassification, RecoveryBlocker,
        TransactionHistoryDetails, TransparentAuthority, TransparentLedgerBalance,
        TransparentLedgerMode, TransparentLedgerRead, TransparentLedgerSnapshot,
    },
    Account as _, Balance, WalletRead, WalletWrite,
};
use zcash_client_sqlite::{wallet::history::TransactionSummary, AccountUuid};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::{
    consensus::{BlockHeight, BranchId},
    memo::{Memo, MemoBytes},
    value::Zatoshis,
    PoolType,
};

use crate::wallet::block_times::{self, BlockTimePoint};
use crate::wallet::db::{wallet_db_on, with_wallet_db_write_lock, WalletDatabase};
use crate::wallet::keys::{hardware_signer_kind, parse_account_uuid, HardwareSignerKind};
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::selects_private_recovery;
use crate::wallet::sync_engine::transparent_ledger::{recovery_hold, HoldCause};

use super::{open_readonly_conn, open_wallet_db, open_wallet_db_for_read};

const ORCHARD_NOTE_VERSION: i64 = 2;
const IRONWOOD_NOTE_VERSION: i64 = 3;
const TRANSPARENT_POOL: i64 = 0;
const SAPLING_POOL: i64 = 2;
const ORCHARD_POOL: i64 = 3;
const IRONWOOD_POOL: i64 = 4;
/// The key scope of the account's ephemeral transparent addresses, which
/// carry a TEX send's funds from its funding step to the send.
const EPHEMERAL_KEY_SCOPE: i64 = 2;

// ======================== Balance ========================

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum WalletBalanceAvailability {
    Available,
    SummaryUnavailable,
    AccountUnavailable,
}

/// What the transparent fields of a [`WalletBalance`] represent.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TransparentBalanceAuthority {
    /// Current authorized amounts, from public discovery or an active private
    /// ledger complete through the chain tip.
    Current,
    /// No current authority. The transparent fields are zero because nothing
    /// is spendable; `transparent_last_known` holds the prior amount, which is
    /// informational only.
    LastKnown,
    /// No current authority and no prior amount. Unknown, not zero.
    Unavailable,
    /// No current authority, and private recovery will not restore it on its
    /// own: `transparent_stop` says why. The transparent fields are zero, and
    /// `transparent_last_known` holds the prior amount, if any.
    Stopped,
}

/// Why private transparent recovery cannot restore an account's authority.
///
/// Reported only while the account has no current authority. The first that
/// applies wins, in this order.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TransparentStopReason {
    /// An integrity failure quarantined the account or a source of its
    /// evidence. Nothing clears a quarantine yet.
    Quarantined,
    /// A Ledger account under `PrivateRequired`. Recovery from its birthday
    /// would miss earlier history, so it is not recovered privately.
    Ledger,
    /// Legacy public evidence that the complete private ledger cannot explain
    /// blocks promotion. The account is held.
    LegacyDiscrepancy,
    /// The source withdrew a publication it had answered from. The account is
    /// held.
    Withdrawn,
    /// Recovery stalled in consecutive runs. The account is held.
    Stalled,
    /// The wallet durably requires private recovery, which this build does
    /// not run. Turning off private queries restores public lookups.
    NotSelected,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct WalletBalance {
    pub availability: WalletBalanceAvailability,
    pub transparent_authority: TransparentBalanceAuthority,
    /// The prior transparent total when `transparent_authority` is `LastKnown`
    /// or `Stopped`.
    pub transparent_last_known: Option<u64>,
    /// Why recovery is stopped, present only when `transparent_authority` is
    /// `Stopped`.
    pub transparent_stop: Option<TransparentStopReason>,
    /// The wallet durably requires private transparent authority, so a current
    /// amount lasts only while the private ledger covers the chain tip.
    pub transparent_private: bool,
    pub transparent: u64,
    pub sapling: u64,
    pub orchard: u64,
    pub ironwood: u64,
    pub transparent_locked: u64,
    pub sapling_locked: u64,
    pub orchard_locked: u64,
    pub ironwood_locked: u64,
    pub transparent_pending: u64,
    pub sapling_pending: u64,
    pub orchard_pending: u64,
    pub ironwood_pending: u64,
    pub change_pending_confirmation: u64,
    pub value_pending_spendability: u64,
    pub uneconomic_value: u64,
}

impl WalletBalance {
    fn unavailable(availability: WalletBalanceAvailability, private: bool) -> Self {
        debug_assert_ne!(availability, WalletBalanceAvailability::Available);
        Self::from_pools(
            availability,
            TransparentStatus {
                authority: TransparentBalanceAuthority::Unavailable,
                last_known: None,
                stop: None,
                private,
            },
            PoolBalance::default(),
            [PoolBalance::default(); 3],
        )
    }

    /// Assembles a balance from one transparent and three shielded pools
    /// (Sapling, Orchard, Ironwood), deriving the cross-pool totals.
    fn from_pools(
        availability: WalletBalanceAvailability,
        status: TransparentStatus,
        transparent: PoolBalance,
        [sapling, orchard, ironwood]: [PoolBalance; 3],
    ) -> Self {
        let pools = [transparent, sapling, orchard, ironwood];
        Self {
            availability,
            transparent_authority: status.authority,
            transparent_last_known: status.last_known,
            transparent_stop: status.stop,
            transparent_private: status.private,
            transparent: transparent.spendable,
            sapling: sapling.spendable,
            orchard: orchard.spendable,
            ironwood: ironwood.spendable,
            transparent_locked: transparent.locked,
            sapling_locked: sapling.locked,
            orchard_locked: orchard.locked,
            ironwood_locked: ironwood.locked,
            transparent_pending: transparent.change + transparent.pending,
            sapling_pending: sapling.change + sapling.pending,
            orchard_pending: orchard.change + orchard.pending,
            ironwood_pending: ironwood.change + ironwood.pending,
            change_pending_confirmation: pools.iter().map(|p| p.change).sum(),
            value_pending_spendability: pools.iter().map(|p| p.pending).sum(),
            uneconomic_value: pools.iter().map(|p| p.uneconomic).sum(),
        }
    }
}

/// The transparent status fields of a [`WalletBalance`].
#[derive(Clone, Copy, Debug)]
struct TransparentStatus {
    authority: TransparentBalanceAuthority,
    last_known: Option<u64>,
    stop: Option<TransparentStopReason>,
    private: bool,
}

/// One pool's balance categories, in zatoshis.
#[derive(Clone, Copy, Debug, Default)]
struct PoolBalance {
    spendable: u64,
    locked: u64,
    change: u64,
    pending: u64,
    uneconomic: u64,
}

impl PoolBalance {
    fn of(balance: &Balance) -> Self {
        Self {
            spendable: u64::from(balance.spendable_value()),
            locked: u64::from(balance.locked_value()),
            change: u64::from(balance.change_pending_confirmation()),
            pending: u64::from(balance.value_pending_spendability()),
            uneconomic: u64::from(balance.uneconomic_value()),
        }
    }

    fn of_transparent(balance: &TransparentLedgerBalance) -> Self {
        let (regular, coinbase) = (Self::of(&balance.regular), Self::of(&balance.coinbase));
        Self {
            spendable: regular.spendable + coinbase.spendable,
            locked: regular.locked + coinbase.locked,
            change: regular.change + coinbase.change,
            pending: regular.pending + coinbase.pending,
            uneconomic: regular.uneconomic + coinbase.uneconomic,
        }
    }
}

pub(crate) fn get_wallet_balance(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<WalletBalance, String> {
    let mut balances = get_wallet_balances(db_path, network, std::slice::from_ref(&account_uuid))?;
    Ok(balances
        .pop()
        .expect("get_wallet_balances returns one entry per requested account"))
}

/// Balances for several accounts from a single `get_wallet_summary`.
///
/// `get_wallet_summary` computes every account's balance regardless of
/// which one the caller wants, so asking it once per account is
/// quadratic in account count. Callers that need more than one account
/// — the Ironwood migration coordinator sweeps all of them every poll —
/// must use this instead of looping over `get_wallet_balance`.
///
/// Returns one entry per requested uuid, in the order given. An account
/// missing from the summary yields `AccountUnavailable` rather than an
/// error, matching the single-account behaviour, so one unknown account
/// cannot fail the whole batch.
///
/// Under a private transparent ledger mode the summary carries no
/// transparent funds, so the transparent fields come from each account's
/// ledger snapshot: its authorized amounts, or none with the last-known
/// amount when authority is unavailable, and why recovery is stopped when it
/// will not restore authority on its own. Durable private policy is respected
/// even when this build opens a Public handle after restart.
pub(crate) fn get_wallet_balances(
    db_path: &str,
    network: WalletNetwork,
    account_uuids: &[&str],
) -> Result<Vec<WalletBalance>, String> {
    let target_ids = account_uuids
        .iter()
        .map(|uuid| parse_account_uuid(uuid))
        .collect::<Result<Vec<_>, _>>()?;

    let mut db = open_wallet_db_for_read(db_path, network)?;
    read_wallet_balances(&mut db, db_path, network, &target_ids)
}

/// [`get_wallet_balances`] on `db`, a handle on the wallet at `db_path`.
pub(crate) fn read_wallet_balances(
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    target_ids: &[AccountUuid],
) -> Result<Vec<WalletBalance>, String> {
    // Read durable policy, summary, and authority from one snapshot. A
    // policy applied by another connection since `db` was opened must not
    // label a private-policy summary's suppressed zero as current funds, so
    // the handle adopts it here. Configuring this read handle does not change
    // policy.
    db.transactionally(|db| {
        let durable = match db.applied_transparent_policy() {
            Err(
                zcash_client_sqlite::error::SqliteClientError::TransparentLedgerPolicyConflict {
                    applied: TransparentLedgerMode::PrivateRequired,
                    ..
                },
            ) => {
                db.set_transparent_ledger_mode(TransparentLedgerMode::PrivateRequired);
                TransparentLedgerMode::PrivateRequired
            }
            result => result?.mode,
        };
        let private = durable == TransparentLedgerMode::PrivateRequired;
        // No run recovers a private wallet in a build that does not select
        // private recovery.
        let not_selected = private && !selects_private_recovery(db_path, network);
        let summary = db.get_wallet_summary(crate::wallet::confirmations_policy())?;

        let Some(summary) = summary else {
            return Ok(target_ids
                .iter()
                .map(|_| {
                    WalletBalance::unavailable(
                        WalletBalanceAvailability::SummaryUnavailable,
                        private,
                    )
                })
                .collect());
        };

        target_ids
            .iter()
            .map(|target_id| {
                let Some(b) = summary.account_balances().get(target_id) else {
                    return Ok(WalletBalance::unavailable(
                        WalletBalanceAvailability::AccountUnavailable,
                        private,
                    ));
                };
                let shielded = [
                    PoolBalance::of(b.sapling_balance()),
                    PoolBalance::of(b.orchard_balance()),
                    PoolBalance::of(b.ironwood_balance()),
                ];
                let snapshot = db.transparent_ledger_snapshot(
                    *target_id,
                    crate::wallet::confirmations_policy(),
                )?;
                let (mut status, transparent) = ledger_transparent_balance(&snapshot, private);
                if status.authority != TransparentBalanceAuthority::Current {
                    if let Some(reason) =
                        transparent_stop_reason(&*db, db_path, &snapshot, not_selected)?
                    {
                        status.authority = TransparentBalanceAuthority::Stopped;
                        status.stop = Some(reason);
                    }
                }
                Ok(WalletBalance::from_pools(
                    WalletBalanceAvailability::Available,
                    status,
                    transparent,
                    shielded,
                ))
            })
            .collect::<Result<Vec<_>, zcash_client_sqlite::error::SqliteClientError>>()
    })
    .map_err(|e| format!("Failed to read wallet balances: {e}"))
}

/// The transparent part of a balance under a private ledger mode.
fn ledger_transparent_balance<A>(
    snapshot: &TransparentLedgerSnapshot<A>,
    private: bool,
) -> (TransparentStatus, PoolBalance) {
    let status = |authority, last_known| TransparentStatus {
        authority,
        last_known,
        stop: None,
        private,
    };
    match (snapshot.authority, &snapshot.authorized) {
        (TransparentAuthority::Public | TransparentAuthority::Private, Some(authorized)) => (
            status(TransparentBalanceAuthority::Current, None),
            PoolBalance::of_transparent(authorized),
        ),
        _ => match &snapshot.last_known {
            Some(last_known) => (
                status(
                    TransparentBalanceAuthority::LastKnown,
                    Some(
                        u64::from(last_known.balance.regular.total())
                            + u64::from(last_known.balance.coinbase.total()),
                    ),
                ),
                PoolBalance::default(),
            ),
            None => (
                status(TransparentBalanceAuthority::Unavailable, None),
                PoolBalance::default(),
            ),
        },
    }
}

/// Why private recovery will not restore authority to the account of
/// `snapshot`, which has none, or `None` while recovery may still restore it.
/// `not_selected` is whether this build leaves the durably private wallet
/// unrecovered.
fn transparent_stop_reason<W>(
    db: &W,
    db_path: &str,
    snapshot: &TransparentLedgerSnapshot<AccountUuid>,
    not_selected: bool,
) -> Result<Option<TransparentStopReason>, W::Error>
where
    W: WalletRead<AccountId = AccountUuid>,
{
    if snapshot.blockers.contains(&RecoveryBlocker::Quarantined) {
        return Ok(Some(TransparentStopReason::Quarantined));
    }
    // The coordinator pauses Ledger accounts under `PrivateRequired`.
    if snapshot.mode == TransparentLedgerMode::PrivateRequired
        && db.get_account(snapshot.account)?.is_some_and(|account| {
            hardware_signer_kind(account.source()) == Some(HardwareSignerKind::Ledger)
        })
    {
        return Ok(Some(TransparentStopReason::Ledger));
    }
    if let Some(cause) = recovery_hold(db_path, snapshot.account) {
        return Ok(Some(match cause {
            HoldCause::Withdrawn(_) | HoldCause::Unreconciled => TransparentStopReason::Withdrawn,
            HoldCause::LegacyDiscrepancy => TransparentStopReason::LegacyDiscrepancy,
            HoldCause::Stalled => TransparentStopReason::Stalled,
        }));
    }
    Ok(not_selected.then_some(TransparentStopReason::NotSelected))
}

// ======================== Transaction Enhancement Requests ========================

pub(crate) struct TxDataRequest {
    pub request_type: String, // "address_txids"
    pub txid: Option<String>,
    pub address: Option<String>,
    pub block_range_start: Option<u64>,
    pub block_range_end: Option<u64>,
}

pub(crate) fn get_transaction_data_requests(
    db_path: &str,
    network: WalletNetwork,
) -> Result<Vec<TxDataRequest>, String> {
    use zcash_client_backend::data_api::TransactionDataRequest;

    let db = open_wallet_db_for_read(db_path, network)?;
    let requests = db.transaction_data_requests().map_err(|e| format!("{e}"))?;

    Ok(requests
        .into_iter()
        .map(|r| match r {
            TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                let addr =
                    zcash_keys::encoding::encode_transparent_address_p(&network, &req.address());
                TxDataRequest {
                    request_type: "address_txids".into(),
                    txid: None,
                    address: Some(addr),
                    block_range_start: Some(u32::from(req.block_range_start()) as u64),
                    block_range_end: req.block_range_end().map(|h| u32::from(h) as u64),
                }
            }
        })
        .collect())
}

/// Returns unmined transactions that the wallet previously discovered in a
/// compact block and that a pending scan range could still restore as mined.
/// A shielded note only receives a commitment-tree position when it is scanned
/// as mined; truncation retains that position even after it clears the
/// transaction's mined height. A local history record also preserves mined
/// evidence for transactions without received notes.
pub(crate) fn get_unmined_txids_with_mined_output_evidence(
    db_path: &str,
    pending_ranges: &[Range<BlockHeight>],
) -> Result<HashSet<Vec<u8>>, String> {
    if pending_ranges.is_empty() {
        return Ok(HashSet::new());
    }

    let conn = open_readonly_conn(db_path)?;
    let mut stmt = conn
        .prepare(&format!(
            "SELECT DISTINCT t.txid, t.min_observed_height, t.expiry_height
             FROM transactions t
             WHERE t.mined_height IS NULL AND {MINED_TRANSACTION_EVIDENCE}"
        ))
        .map_err(|e| format!("SQL error: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, Vec<u8>>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, Option<u32>>(2)?,
            ))
        })
        .map_err(|e| format!("Query error: {e}"))?;

    rows.filter_map(|row| match row {
        Ok((txid, min_observed_height, expiry_height))
            if pending_ranges.iter().any(|range| {
                let range_start = u32::from(range.start);
                let range_end = u32::from(range.end);
                let known_expiry = expiry_height.filter(|height| *height > 0);
                range_end > min_observed_height
                    && known_expiry.is_none_or(|height| range_start < height)
            }) =>
        {
            Some(Ok(txid))
        }
        Ok(_) => None,
        Err(error) => Some(Err(error)),
    })
    .collect::<Result<HashSet<_>, _>>()
    .map_err(|e| format!("Row error: {e}"))
}

pub fn decrypt_and_store_transaction(
    db_path: &str,
    network: WalletNetwork,
    tx_bytes: &[u8],
    mined_height: Option<u64>,
) -> Result<(), String> {
    use zcash_client_backend::data_api::wallet::decrypt_and_store_transaction;
    use zcash_primitives::transaction::Transaction;
    use zcash_protocol::consensus::BranchId;

    let tx = Transaction::read(tx_bytes, BranchId::Sapling)
        .map_err(|e| format!("Failed to read transaction: {e}"))?;
    let height = mined_height.map(|h| BlockHeight::from_u32(h as u32));

    with_wallet_db_write_lock("transactions.decrypt_and_store_transaction", || {
        let mut db = open_wallet_db(db_path, network)?;
        decrypt_and_store_transaction(&network, &mut db, &tx, height)
            .map_err(|e| format!("Failed to decrypt/store transaction: {e}"))
    })
}

pub fn set_transaction_status(
    db_path: &str,
    network: WalletNetwork,
    txid_hex: &str,
    status: i64,
) -> Result<(), String> {
    use zcash_client_backend::data_api::TransactionStatus;

    let txid_bytes = hex::decode(txid_hex).map_err(|e| format!("Bad txid hex: {e}"))?;
    let txid = zcash_primitives::transaction::TxId::from_bytes(
        txid_bytes.try_into().map_err(|_| "TxId must be 32 bytes")?,
    );

    let tx_status = match status {
        -2 => TransactionStatus::TxidNotRecognized,
        -1 => TransactionStatus::NotInMainChain,
        h => TransactionStatus::Mined(BlockHeight::from_u32(h as u32)),
    };

    with_wallet_db_write_lock("transactions.set_transaction_status", || {
        let mut db = open_wallet_db(db_path, network)?;
        db.set_transaction_status(txid, tx_status)
            .map_err(|e| format!("Failed to set status: {e}"))
    })
}

// ======================== Transaction History ========================

pub(crate) struct TransactionInfo {
    pub txid_hex: String,
    pub mined_height: u64,
    pub expired_unmined: bool,
    pub account_balance_delta: i64,
    /// The network fee shown for the transaction. Zero unless `fee_state` is
    /// `Known` or `WholeTransaction`. Display only: it is never subtracted
    /// from `display_amount` or `account_balance_delta`.
    pub fee: u64,
    pub fee_state: TransactionFeeState,
    pub block_time: u64,
    pub is_transparent: bool,
    pub tx_kind: String,
    pub display_amount: u64,
    pub display_pool: String,
    pub activity_pool: Option<String>,
    pub funding_parent_txid: Option<String>,
    pub funding_parent_mined_height: Option<u64>,
    pub funding_parent_expired: Option<bool>,
    pub created_time: u64,
    /// Whether the recipients, payment amounts, and memos are known. A
    /// missing recipient row does not mean there was no payment.
    pub details_complete: bool,
    /// Whether later discovery or enhancement can still change this row. A
    /// provisional net debit is not a payment amount.
    pub provisional: bool,
    /// Whether `display_amount` is the account's net balance change rather
    /// than a payment: the wallet knows the debit but not where its value
    /// went, so nothing, not even a known fee, is subtracted from it. When
    /// the account's own fee (`Known`) equals it, the change is that fee
    /// alone.
    pub amount_is_net_change: bool,
}

/// The network fee shown for a transaction. Unknown, zero, and not
/// applicable stay distinct.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum TransactionFeeState {
    /// The account's recorded fee.
    Known,
    /// The account's share is unknown; the fee shown is the exact
    /// whole-transaction fee from privately recovered metadata, with that of
    /// any TEX funding step shown as part of it, which other funders may have
    /// shared.
    WholeTransaction,
    /// The account spent funds, or may have, but neither its fee nor the
    /// whole transaction's is known.
    Unknown,
    /// The account spent nothing, so it paid no fee.
    NotApplicable,
}

pub(crate) struct TransactionDetail {
    pub txid_hex: String,
    pub tx_kind: String,
    pub primary_address: Option<String>,
    pub source_address: Option<String>,
    pub source_pool: Option<String>,
    pub memo: Option<String>,
    pub outputs: Vec<TransactionDetailOutput>,
    /// See [`TransactionInfo::details_complete`]: `outputs` may be partial.
    pub details_complete: bool,
    /// See [`TransactionInfo::provisional`].
    pub provisional: bool,
}

pub(crate) struct TransactionDetailOutput {
    pub address: Option<String>,
    pub amount_zatoshi: u64,
    pub pool: String,
    /// Exact output pool for activity and Gift Card destination metadata.
    pub activity_pool: Option<String>,
    pub uses_orchard_receiver: bool,
}

pub(crate) struct ExportBirthdayAnchor {
    pub block_height: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct TxBase {
    txid: Vec<u8>,
    transaction_id: i64,
    mined_height: Option<u32>,
    expired_unmined: bool,
    account_balance_delta: i64,
    /// The recorded fee, if any. Never assumed zero.
    fee: Option<u64>,
    block_time: u64,
    total_spent: u64,
    total_received: u64,
    is_shielding: bool,
    expiry_height: Option<i64>,
    tx_index: i64,
    created: Option<String>,
    created_time: u64,
    spent_orchard_note: bool,
    /// How many of the account's recorded inputs the transaction spends.
    spent_note_count: u32,
    history: HistoryCompleteness,
}

/// A fee, as far as history knows it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Fee {
    /// The account's own fee.
    Known(u64),
    /// The exact fee of the whole transaction, shown when the account's own
    /// fee is unknown. Other funders may have shared it.
    Whole(u64),
    Unknown,
    NotApplicable,
}

impl Fee {
    /// The fee of a transaction and of a funding step shown as part of it.
    /// Any whole-transaction part makes the sum the transactions' network
    /// fees rather than the account's.
    fn plus(self, other: Fee) -> Fee {
        match (self, other) {
            (Fee::Known(a), Fee::Known(b)) => Fee::Known(a.saturating_add(b)),
            (Fee::Unknown, _) | (_, Fee::Unknown) => Fee::Unknown,
            (Fee::NotApplicable, fee) | (fee, Fee::NotApplicable) => fee,
            (Fee::Known(a) | Fee::Whole(a), Fee::Known(b) | Fee::Whole(b)) => {
                Fee::Whole(a.saturating_add(b))
            }
        }
    }

    fn known_or_zero(self) -> u64 {
        match self {
            Fee::Known(fee) | Fee::Whole(fee) => fee,
            Fee::Unknown | Fee::NotApplicable => 0,
        }
    }

    fn state(self) -> TransactionFeeState {
        match self {
            Fee::Known(_) => TransactionFeeState::Known,
            Fee::Whole(_) => TransactionFeeState::WholeTransaction,
            Fee::Unknown => TransactionFeeState::Unknown,
            Fee::NotApplicable => TransactionFeeState::NotApplicable,
        }
    }
}

/// What the wallet knows about the account's side of a transaction, from the
/// library's history read.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct HistoryCompleteness {
    /// Transaction-wide Enhance shape assertion, independent of payment completeness.
    has_transparent_outputs: Option<bool>,
    details_complete: bool,
    provisional: bool,
    /// The library's classification of the account's side, once read. A net
    /// reconstruction (a privately recovered mixed shielding) has a final
    /// movement but no attributed fee or payment; see
    /// [`Self::justifies_shielding`].
    classification: Option<HistoryClassification>,
    /// Whether every effect of the transaction on the account is settled, so
    /// its balance change is final whatever the classification.
    effects_settled: bool,
    /// The fee as it concerns the account: never [`Fee::Whole`].
    fee: Fee,
    /// The exact fee of the whole transaction, reconciled by the library
    /// from stored and recovered fee evidence, when the account spent in it.
    /// Other funders may have shared it, so it is shown as the network fee
    /// when the account's fee is unknown and never charged to the account.
    whole_fee: Option<u64>,
    /// Whether recovered metadata proves a transparent-only transaction
    /// whose inputs all belong to the account. Counting transparent inputs
    /// in a mixed transaction cannot rule out foreign shielded contributors.
    sole_transparent_funder: bool,
    /// The exact payment outside the account that the library reconstructed
    /// from recovered transaction metadata (private recovery: the account
    /// funded every transparent input of a transaction with no shielded
    /// components, and the whole fee is known), when no local record exists.
    /// The recipients themselves stay unknown.
    inferred_payment: Option<u64>,
    /// Activity-only residual supplied by the library; recipient and fee attribution stay unknown.
    inferred_outgoing: Option<u64>,
}

impl HistoryCompleteness {
    /// Complete history, with the fee the library would report for `base`.
    #[cfg(test)]
    fn complete_for(base: &TxBase) -> Self {
        Self {
            has_transparent_outputs: None,
            details_complete: true,
            provisional: false,
            classification: Some(HistoryClassification::Reconstructed),
            effects_settled: true,
            fee: match (base.total_spent > 0, base.fee) {
                (false, _) => Fee::NotApplicable,
                (true, Some(fee)) => Fee::Known(fee),
                (true, None) => Fee::Unknown,
            },
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
            inferred_outgoing: None,
        }
    }

    /// Local intent can know every payment detail before scanning discovers
    /// all owned effects. Public discovery still counts as settled.
    /// `spent_note_count` is the account's recorded inputs in the transaction.
    fn of(details: &TransactionHistoryDetails, spent_note_count: u32) -> Self {
        let effects_settled = details
            .effects
            .iter()
            .all(|effect| effect.completeness.is_settled());
        let spent_in = |transparent: bool| {
            details.effects.iter().any(|effect| {
                (effect.pool == PoolType::Transparent) == transparent
                    && effect.spent > Zatoshis::ZERO
            })
        };
        let own_transparent_inputs = match (spent_in(true), spent_in(false)) {
            (false, _) => Some(0),
            (true, false) => Some(spent_note_count),
            (true, true) => None,
        };
        Self {
            has_transparent_outputs: details.has_transparent_outputs,
            details_complete: details.payment_details == DetailCompleteness::Complete,
            classification: Some(details.classification),
            // A net reconstruction (a privately recovered mixed shielding) has a final
            // movement: it is shown, but its fee stays the whole transaction's and no
            // payment is inferred from it.
            provisional: match details.classification {
                HistoryClassification::Provisional => true,
                HistoryClassification::LocalIntent
                | HistoryClassification::Reconstructed
                | HistoryClassification::NetReconstructed => false,
            } || !effects_settled,
            effects_settled,
            fee: match details.fee {
                FeeState::Known(fee) => Fee::Known(fee.into()),
                FeeState::Unknown => Fee::Unknown,
                FeeState::NotApplicable => Fee::NotApplicable,
            },
            // Only an account that spent can owe any of the fee: a receive,
            // settled or not, never shows its sender's fee.
            whole_fee: details
                .whole_fee
                .filter(|_| details.account_movement.spent > 0)
                .map(|fee| fee.into_u64()),
            inferred_outgoing: details.inferred_outgoing.map(|amount| amount.into_u64()),
            sole_transparent_funder: details.transaction_metadata.as_ref().is_some_and(|e| {
                !e.metadata.has_shielded_components
                    && e.metadata.transparent_input_count > 0
                    && own_transparent_inputs == Some(e.metadata.transparent_input_count)
            }),
            inferred_payment: match details.aggregate_payment {
                AggregatePayment::Exact(amount)
                    if details.classification == HistoryClassification::Reconstructed
                        && details
                            .transaction_metadata
                            .as_ref()
                            .is_some_and(|e| !e.metadata.has_shielded_components) =>
                {
                    Some(amount.into_u64())
                }
                _ => None,
            },
        }
    }

    /// Assumed until the history read reports on a transaction: nothing is
    /// known to be complete.
    fn unread(fee: Option<u64>) -> Self {
        Self {
            has_transparent_outputs: None,
            details_complete: false,
            provisional: true,
            classification: None,
            effects_settled: false,
            fee: fee.map_or(Fee::Unknown, Fee::Known),
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
            inferred_outgoing: None,
        }
    }

    /// The network fee shown for the transaction: the account's fee, or the
    /// exact whole-transaction fee when the account's is unknown. A provable
    /// absence of an account fee stays not applicable. Display only.
    fn shown_fee(self) -> Fee {
        match (self.fee, self.whole_fee) {
            (Fee::Unknown, Some(whole)) => Fee::Whole(whole),
            (fee, _) => fee,
        }
    }

    /// The exact fee a settled balance change can be compared with: the
    /// account's own fee or, when that is unknown, the whole transaction's,
    /// but only when metadata proves a transparent-only transaction funded
    /// entirely by the account. Another transparent or shielded funder could
    /// otherwise have paid the fee while the account's funds paid someone
    /// else as much as it received back.
    fn exact_fee(self) -> Option<u64> {
        if !self.effects_settled {
            return None;
        }
        match self.fee {
            Fee::Known(fee) | Fee::Whole(fee) => Some(fee),
            Fee::Unknown => self.whole_fee.filter(|_| self.sole_transparent_funder),
            Fee::NotApplicable => None,
        }
    }

    /// Only full payment details can show that a transaction moved the
    /// account's transparent funds into its shielded pools and paid no one.
    /// Local intent and a full reconstruction show every payment. A net
    /// reconstruction shows that the account's transparent spends became its
    /// own Ironwood receipt and the whole transaction's fee, which stays
    /// unattributed: the row shows the receipt and that fee, charging none of
    /// it. A provisional or unread history never justifies a shielding.
    fn justifies_shielding(self) -> bool {
        self.details_complete
            && !self.provisional
            && match self.classification {
                Some(
                    HistoryClassification::LocalIntent
                    | HistoryClassification::Reconstructed
                    | HistoryClassification::NetReconstructed,
                ) => true,
                Some(HistoryClassification::Provisional) | None => false,
            }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct TxOutput {
    txid: Vec<u8>,
    output_pool: i64,
    output_index: i64,
    from_account_uuid: Option<Vec<u8>>,
    to_account_uuid: Option<Vec<u8>>,
    to_address: Option<String>,
    sent_to_address: Option<String>,
    transparent_receiver_address: Option<String>,
    to_key_scope: Option<i64>,
    value: u64,
    memo: Option<Vec<u8>>,
    note_version: Option<i64>,
}

impl TxOutput {
    fn detail_address(&self, tx_kind: &str) -> Option<String> {
        if tx_kind == "migration" {
            // A migration moves value between pools owned by the same account.
            // Its internal receiver is implementation detail, not a
            // counterparty address that should be exposed in Activity.
            None
        } else if tx_kind == "sent" {
            if self.output_pool == 0 {
                return self
                    .transparent_receiver_address
                    .clone()
                    .or_else(|| self.sent_to_address.clone())
                    .or_else(|| self.to_address.clone());
            }

            self.sent_to_address
                .clone()
                .or_else(|| self.to_address.clone())
        } else if self.output_pool == 0 {
            // Received transparent outputs: surface the bare t-address. The
            // wallet stores the account UA in `to_address`, so without this
            // recovery the UA leaks into the receiving-address line and the
            // desktop receipt's address-prefix heuristic mislabels a
            // transparent->transparent receive as shielded (crimson shield +
            // u1 address). Mirrors the `sent` pool-0 branch above.
            self.transparent_receiver_address
                .clone()
                .or_else(|| self.to_address.clone())
        } else {
            self.to_address.clone()
        }
    }
}

#[derive(Default, Clone)]
struct ActivityAmounts {
    amount: u64,
    output_count: usize,
    has_transparent: bool,
    has_sapling: bool,
    has_orchard: bool,
    has_ironwood: bool,
}

impl ActivityAmounts {
    fn add_output(&mut self, output: &TxOutput) {
        self.amount = self.amount.saturating_add(output.value);
        self.output_count += 1;
        match output.output_pool {
            TRANSPARENT_POOL => self.has_transparent = true,
            SAPLING_POOL => self.has_sapling = true,
            ORCHARD_POOL => self.has_orchard = true,
            IRONWOOD_POOL => self.has_ironwood = true,
            _ => {}
        }
    }

    fn display_pool(&self) -> &'static str {
        // Preserve the legacy grouping used by Gift Card activity.
        match (
            self.has_transparent,
            self.has_sapling || self.has_orchard,
            self.has_ironwood,
        ) {
            (true, false, false) => "transparent",
            (false, true, false) => "shielded",
            (false, false, true) => "ironwood",
            (false, false, false) => "unknown",
            _ => "mixed",
        }
    }

    fn activity_pool(&self) -> &'static str {
        match (
            self.has_transparent,
            self.has_sapling,
            self.has_orchard,
            self.has_ironwood,
        ) {
            (true, false, false, false) => "transparent",
            (false, true, false, false) => "sapling",
            (false, false, true, false) => "orchard",
            (false, false, false, true) => "ironwood",
            (false, false, false, false) => "unknown",
            _ => "mixed",
        }
    }
}

#[derive(Default, Clone)]
struct ActivitySummary {
    sent: ActivityAmounts,
    received: ActivityAmounts,
    /// Actual owned transparent receipts, excluding shielded change.
    received_transparent: ActivityAmounts,
    /// Owned transparent change/funding excluded from the visible outgoing residual.
    internal_transparent: ActivityAmounts,
    /// The account's own outputs at its visible addresses (external or
    /// foreign, or with a recorded recipient), whoever funded them. Change and
    /// intermediate outputs are not among them.
    visible_own: ActivityAmounts,
    shielded: ActivityAmounts,
    internal_ironwood_transition: ActivityAmounts,
    own_transparent_output_amount: u64,
    has_own_transparent_output: bool,
    /// An output pays one of the account's ephemeral addresses: the
    /// transaction funds a TEX send.
    has_own_ephemeral_output: bool,
    has_external_transparent_send: bool,
}

type FundingStepMatchKey = (String, i64, u64);

#[derive(Default)]
struct SuppressedFundingStepFees {
    suppressed_funding_txids: HashSet<i64>,
    /// The fees of the funding steps folded into each send.
    extra_fee_by_send_txid: HashMap<i64, Fee>,
    /// The funding step folded into each send.
    funding_parent_by_send_txid: HashMap<i64, i64>,
}

/// Which transactions spend each transaction's outputs to the account's
/// ephemeral addresses, by txid.
type EphemeralSpends = HashMap<Vec<u8>, Vec<Vec<u8>>>;

struct ClassifiedTx {
    info: TransactionInfo,
    sort_pending_rank: u8,
    sort_timestamp: u64,
    sort_mined_height: u64,
    tx_index: i64,
    row_order: u8,
}

pub(crate) fn get_transaction_history(
    db_path: &str,
    network: WalletNetwork,
    limit: Option<u32>,
    account_uuid: &str,
) -> Result<Vec<TransactionInfo>, String> {
    let account = parse_account_uuid(account_uuid)?;
    let conn = open_readonly_conn(db_path)?;
    read_transaction_history(&conn, db_path, network, limit, account)
}

fn read_transaction_history(
    conn: &rusqlite::Connection,
    db_path: &str,
    network: WalletNetwork,
    limit: Option<u32>,
    account: AccountUuid,
) -> Result<Vec<TransactionInfo>, String> {
    let uuid = account.expose_uuid();
    let uuid_bytes = uuid.as_bytes();
    // All library and output reads borrow this connection. The summary API joins
    // the caller's transaction, keeping one WAL snapshot across concurrent sync.
    let read_tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("SQL error: {e}"))?;
    let mut bases = read_history_bases(&read_tx, db_path, network, account)?;
    if let Some(state) = crate::wallet::sync_engine::gift_card_claim::snapshot_from_conn(&read_tx)?
    {
        for base in &mut bases {
            if base.created.is_some() {
                base.mined_height = read_tx
                    .query_row(
                        "SELECT height FROM vizor_giftcard_mined WHERE txid=?1",
                        [&base.txid],
                        |r| r.get(0),
                    )
                    .optional()
                    .map_err(|e| e.to_string())?;
                base.expired_unmined = state.complete
                    && base.mined_height.is_none()
                    && base
                        .expiry_height
                        .is_some_and(|h| h > 0 && h as u64 + 5 <= state.checked_height as u64);
            }
        }
    }
    if bases.is_empty() {
        return Ok(Vec::new());
    }
    attach_history_details(&read_tx, db_path, network, account, &mut bases)?;

    // Bind the txids already in `bases` instead of re-querying
    // `v_transactions` for DISTINCT txid. That view selects
    // `transactions.raw`, so a second pass would re-materialize every
    // raw blob even though this path never reads them.
    let outputs_by_txid = read_history_outputs(
        &read_tx,
        uuid_bytes,
        bases.iter().map(|base| base.txid.as_slice()),
    )?;
    let ephemeral_spends = read_ephemeral_spends(
        &read_tx,
        uuid_bytes,
        bases.iter().map(|base| base.txid.as_slice()),
    )?;
    drop(read_tx);

    Ok(assemble_history(
        &bases,
        &outputs_by_txid,
        &ephemeral_spends,
        uuid_bytes,
        limit,
    ))
}

/// How many transactions one library history read covers.
const HISTORY_DETAILS_BATCH: usize = 256;

/// Attaches the library's history view of each base. It is read through a
/// configured handle over `conn`, inside the transaction the bases were read
/// in, so both describe the same database state.
fn attach_history_details(
    conn: &rusqlite::Connection,
    db_path: &str,
    network: WalletNetwork,
    account: AccountUuid,
    bases: &mut [TxBase],
) -> Result<(), String> {
    let db = wallet_db_on(conn, db_path, network);
    let txids = bases
        .iter()
        .map(|base| txid_of(&base.txid))
        .collect::<Result<Vec<_>, _>>()?;
    let mut read = HashMap::with_capacity(bases.len());
    for batch in txids.chunks(HISTORY_DETAILS_BATCH) {
        for details in db
            .transaction_history_details(account, batch)
            .map_err(|e| format!("Failed to read history details: {e}"))?
        {
            read.insert(details.txid.as_ref().to_vec(), details);
        }
    }
    for base in bases {
        let history = read.get(&base.txid).map_or(base.history, |details| {
            HistoryCompleteness::of(details, base.spent_note_count)
        });
        base.attach_history(history);
    }
    Ok(())
}

fn txid_of(bytes: &[u8]) -> Result<TxId, String> {
    <[u8; 32]>::try_from(bytes)
        .map(TxId::from_bytes)
        .map_err(|_| "Invalid txid length".to_string())
}

/// Turn raw history rows into the display list.
///
/// This is the whole classification pipeline — summarize, suppress
/// funding steps, classify, filter, sort, truncate — with no database
/// access, so it can be exercised directly from `TxBase` / `TxOutput`
/// values instead of through SQL fixtures. Library summaries and output reads
/// provide local facts; completeness remains a separate library read. Migrated
/// wallet fixtures cover their agreement and snapshot boundary, while synthetic
/// fixtures exercise display classification independently.
fn assemble_history(
    bases: &[TxBase],
    outputs_by_txid: &HashMap<Vec<u8>, Vec<TxOutput>>,
    ephemeral_spends: &EphemeralSpends,
    uuid_bytes: &[u8],
    limit: Option<u32>,
) -> Vec<TransactionInfo> {
    let summaries: HashMap<Vec<u8>, ActivitySummary> = bases
        .iter()
        .map(|base| {
            let outputs = outputs_by_txid
                .get(&base.txid)
                .map(Vec::as_slice)
                .unwrap_or(&[]);
            (
                base.txid.clone(),
                summarize_activity_outputs(base, outputs, uuid_bytes),
            )
        })
        .collect();
    let external_send_keys = build_external_send_keys(bases, &summaries);
    let suppressed_funding_step_fees =
        build_suppressed_funding_step_fees(bases, &summaries, &external_send_keys);
    let linked_funding_step_fees = link_funding_steps(
        bases,
        &summaries,
        ephemeral_spends,
        &suppressed_funding_step_fees.suppressed_funding_txids,
    );

    let bases_by_id: HashMap<i64, &TxBase> = bases
        .iter()
        .map(|base| (base.transaction_id, base))
        .collect();
    let mut visible = Vec::new();
    for base in bases {
        let summary = summaries.get(&base.txid).cloned().unwrap_or_default();
        if suppressed_funding_step_fees
            .suppressed_funding_txids
            .contains(&base.transaction_id)
            || linked_funding_step_fees
                .suppressed_funding_txids
                .contains(&base.transaction_id)
        {
            continue;
        }

        let extra_sent_fee = if summary.has_external_transparent_send {
            suppressed_funding_step_fees
                .extra_fee_by_send_txid
                .get(&base.transaction_id)
                .copied()
                .unwrap_or(Fee::NotApplicable)
        } else {
            Fee::NotApplicable
        }
        .plus(
            linked_funding_step_fees
                .extra_fee_by_send_txid
                .get(&base.transaction_id)
                .copied()
                .unwrap_or(Fee::NotApplicable),
        );

        let mut rows = classify_history_tx(base, &summary, extra_sent_fee);
        if let Some(parent_id) = suppressed_funding_step_fees
            .funding_parent_by_send_txid
            .get(&base.transaction_id)
            .or_else(|| {
                linked_funding_step_fees
                    .funding_parent_by_send_txid
                    .get(&base.transaction_id)
            })
        {
            if let Some(parent) = bases_by_id.get(parent_id) {
                for row in &mut rows {
                    if row.info.tx_kind == "sent" {
                        row.info.funding_parent_txid = Some(hex::encode(&parent.txid));
                        row.info.funding_parent_mined_height =
                            Some(parent.mined_height.unwrap_or(0).into());
                        row.info.funding_parent_expired = Some(parent.expired_unmined);
                    }
                }
            }
        }
        visible.extend(rows);
    }

    visible.sort_by(|a, b| {
        b.sort_pending_rank
            .cmp(&a.sort_pending_rank)
            .then_with(|| b.sort_timestamp.cmp(&a.sort_timestamp))
            .then_with(|| b.sort_mined_height.cmp(&a.sort_mined_height))
            .then_with(|| b.tx_index.cmp(&a.tx_index))
            .then_with(|| b.info.txid_hex.cmp(&a.info.txid_hex))
            .then_with(|| a.row_order.cmp(&b.row_order))
    });

    if let Some(limit) = limit {
        visible.truncate(limit as usize);
    }

    visible.into_iter().map(|tx| tx.info).collect()
}

pub fn get_previous_transaction_count_for_address(
    db_path: &str,
    _network: WalletNetwork,
    account_uuid: &str,
    address: &str,
) -> Result<u32, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
    let uuid_bytes = uuid.as_bytes().to_vec();
    let address = address.trim();
    if address.is_empty() {
        return Ok(0);
    }

    let conn = open_readonly_conn(db_path)?;
    let count = conn
        .query_row(
            r#"
        SELECT COUNT(*)
        FROM (
            SELECT DISTINCT tx.txid
            FROM sent_notes sn
            JOIN transactions tx ON tx.id_tx = sn.transaction_id
            JOIN accounts from_acc ON from_acc.id = sn.from_account_id
            JOIN v_transactions vt ON vt.txid = tx.txid
            WHERE from_acc.uuid = ?1
              AND vt.account_uuid = ?1
              AND sn.to_address = ?2
              AND COALESCE(sn.value, 0) > 0

            UNION

            SELECT DISTINCT txo.txid
            FROM v_tx_outputs txo
            JOIN v_transactions vt ON vt.txid = txo.txid
            WHERE txo.from_account_uuid = ?1
              AND vt.account_uuid = ?1
              AND txo.to_address = ?2
              AND COALESCE(txo.value, 0) > 0
        ) matched
        "#,
            rusqlite::params![uuid_bytes.as_slice(), address],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| format!("Previous transaction count query error: {e}"))?;

    Ok(u32::try_from(count).unwrap_or(u32::MAX))
}

pub(crate) fn get_oldest_mined_transaction_anchor(
    db_path: &str,
    account_uuid: &str,
) -> Result<Option<ExportBirthdayAnchor>, String> {
    let account_id = parse_account_uuid(account_uuid)?;
    let conn = open_readonly_conn(db_path)?;
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            mined_height
        FROM v_transactions
        WHERE account_uuid = ?1
          AND mined_height IS NOT NULL
        ORDER BY mined_height ASC, COALESCE(tx_index, -1) ASC
        LIMIT 1
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    stmt.query_row(
        rusqlite::params![account_id.expose_uuid().as_bytes().as_slice()],
        |row| {
            let block_height = row.get::<_, u32>(0)?;
            Ok(ExportBirthdayAnchor {
                block_height: u64::from(block_height),
            })
        },
    )
    .optional()
    .map_err(|e| format!("Query error: {e}"))
}

pub(crate) fn get_export_birthday_anchor(
    db_path: &str,
    account_uuid: &str,
) -> Result<ExportBirthdayAnchor, String> {
    if let Some(anchor) = get_oldest_mined_transaction_anchor(db_path, account_uuid)? {
        return Ok(anchor);
    }

    get_account_birthday_height(db_path, account_uuid)?
        .map(|block_height| ExportBirthdayAnchor { block_height })
        .ok_or_else(|| "Account birthday not found".to_string())
}

/// Header time of block `height`, from local data only.
///
/// Returns the exact time when the wallet has scanned that block. Otherwise,
/// where [`block_times::table_covers`] the network (real mainnet), estimates
/// it from the compiled-in block-time table, anchored past the table by the
/// wallet's highest scanned block. Returns `None` elsewhere, including Ironwood
/// masquerade builds, when the block is not stored locally.
///
/// Callers pass the height they already display, so the returned time always
/// belongs to that height even if the wallet's data changes in between.
pub(crate) fn get_local_block_time(
    db_path: &str,
    network: WalletNetwork,
    height: u64,
) -> Result<Option<u64>, String> {
    let conn = open_readonly_conn(db_path)?;
    let exact = conn
        .query_row(
            "SELECT time FROM blocks WHERE height = ?1",
            [height],
            |row| row.get::<_, Option<u32>>(0),
        )
        .optional()
        .map_err(|e| format!("Block time query error: {e}"))?
        .flatten();
    if let Some(time) = exact {
        return Ok(Some(u64::from(time)));
    }
    if !block_times::table_covers(network) {
        return Ok(None);
    }

    let highest_scanned = conn
        .query_row(
            "SELECT height, time FROM blocks
             WHERE time IS NOT NULL
             ORDER BY height DESC
             LIMIT 1",
            [],
            |row| {
                Ok(BlockTimePoint {
                    height: row.get(0)?,
                    time: row.get(1)?,
                })
            },
        )
        .optional()
        .map_err(|e| format!("Highest scanned block query error: {e}"))?;
    Ok(Some(u64::from(block_times::mainnet_time_for_height(
        height,
        highest_scanned,
    ))))
}

fn get_account_birthday_height(db_path: &str, account_uuid: &str) -> Result<Option<u64>, String> {
    let account_id = parse_account_uuid(account_uuid)?;
    let conn = open_readonly_conn(db_path)?;
    let mut stmt = conn
        .prepare("SELECT birthday_height FROM accounts WHERE uuid = ?1")
        .map_err(|e| format!("SQL error: {e}"))?;

    stmt.query_row(
        rusqlite::params![account_id.expose_uuid().as_bytes().as_slice()],
        |row| {
            let block_height = row.get::<_, u32>(0)?;
            Ok(u64::from(block_height))
        },
    )
    .optional()
    .map_err(|e| format!("Query error: {e}"))
}

pub(crate) fn get_transaction_detail(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    txid_hex: &str,
    tx_kind: &str,
) -> Result<TransactionDetail, String> {
    let account = parse_account_uuid(account_uuid)?;
    let conn = open_readonly_conn(db_path)?;
    let read_tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("SQL error: {e}"))?;
    read_transaction_detail(&read_tx, network, account, txid_hex, tx_kind, |base| {
        attach_history_details(
            &read_tx,
            db_path,
            network,
            account,
            std::slice::from_mut(base),
        )
    })
}

/// `get_transaction_detail` within an open read transaction. `attach_history`
/// records the history view of the transaction on its base.
fn read_transaction_detail(
    read_tx: &rusqlite::Connection,
    network: WalletNetwork,
    account: AccountUuid,
    txid_hex: &str,
    tx_kind: &str,
    attach_history: impl FnOnce(&mut TxBase) -> Result<(), String>,
) -> Result<TransactionDetail, String> {
    let uuid_bytes = account.expose_uuid().as_bytes().to_vec();
    let txid = hex::decode(txid_hex).map_err(|e| format!("Invalid txid: {e}"))?;
    if txid.len() != 32 {
        return Err("Invalid txid length".to_string());
    }

    let Some(mut base) = read_history_base_by_txid(read_tx, &uuid_bytes, &txid)? else {
        return Err("Transaction not found".to_string());
    };
    attach_history(&mut base)?;
    let mut outputs = read_outputs_for_tx(read_tx, &uuid_bytes, &txid)?;
    outputs.sort_by(|a, b| {
        a.output_index
            .cmp(&b.output_index)
            .then_with(|| a.output_pool.cmp(&b.output_pool))
    });

    let pays_others = pays_others(&outputs, uuid_bytes.as_slice());
    let visible_outputs = outputs
        .iter()
        .filter(|output| {
            detail_includes_output(&base, output, uuid_bytes.as_slice(), tx_kind, pays_others)
        })
        .collect::<Vec<_>>();
    let memo = visible_outputs
        .iter()
        .find_map(|output| decode_text_memo(output.memo.as_deref()));
    let primary_address = if tx_kind == "sent" {
        visible_outputs
            .iter()
            .find_map(|output| output.detail_address(tx_kind))
    } else {
        None
    };
    let source = if matches!(tx_kind, "received" | "receiving") && !visible_outputs.is_empty() {
        let raw_tx = read_raw_transaction_for_tx(read_tx, &uuid_bytes, &txid)?;
        Some(received_source_from_raw_transaction(
            network,
            raw_tx.as_deref(),
        ))
    } else {
        None
    };
    let outputs = visible_outputs
        .into_iter()
        .map(|output| TransactionDetailOutput {
            address: output.detail_address(tx_kind),
            amount_zatoshi: output.value,
            pool: output_pool_label(output.output_pool).to_string(),
            activity_pool: exact_output_pool_label(output.output_pool).map(str::to_string),
            uses_orchard_receiver: matches!(output.output_pool, ORCHARD_POOL | IRONWOOD_POOL),
        })
        .collect();

    Ok(TransactionDetail {
        txid_hex: hex::encode(&base.txid),
        tx_kind: tx_kind.to_string(),
        primary_address,
        source_address: source.as_ref().and_then(|s| s.address.clone()),
        source_pool: source.map(|s| s.pool.to_string()),
        memo,
        outputs,
        details_complete: base.history.details_complete,
        provisional: base.history.provisional,
    })
}

struct TransactionSource {
    address: Option<String>,
    pool: &'static str,
}

fn received_source_from_raw_transaction(
    network: WalletNetwork,
    raw_tx: Option<&[u8]>,
) -> TransactionSource {
    let Some(raw_tx) = raw_tx else {
        return TransactionSource {
            address: None,
            pool: "unknown",
        };
    };

    let Ok(tx) = Transaction::read(raw_tx, BranchId::Sapling) else {
        return TransactionSource {
            address: None,
            pool: "unknown",
        };
    };

    let Some(bundle) = tx.transparent_bundle() else {
        return TransactionSource {
            address: None,
            pool: "shielded",
        };
    };

    if bundle.vin.is_empty() {
        return TransactionSource {
            address: None,
            pool: "shielded",
        };
    }

    TransactionSource {
        address: bundle.vin.iter().find_map(|input| {
            transparent_source_address_from_script_sig(network, input.script_sig().0 .0.as_slice())
        }),
        pool: "transparent",
    }
}

fn transparent_source_address_from_script_sig(
    network: WalletNetwork,
    script_sig: &[u8],
) -> Option<String> {
    let pubkey = parse_standard_p2pkh_pubkey_from_script_sig(script_sig)?;
    let address = TransparentAddress::PublicKeyHash(transparent::util::hash160::hash(pubkey));
    Some(zcash_keys::encoding::encode_transparent_address_p(
        &network, &address,
    ))
}

fn parse_standard_p2pkh_pubkey_from_script_sig(script_sig: &[u8]) -> Option<&[u8]> {
    let pushes = parse_script_pushes(script_sig)?;
    pushes
        .into_iter()
        .rev()
        .find(|push| push.len() == 33 && matches!(push.first(), Some(0x02 | 0x03)))
}

fn parse_script_pushes(script: &[u8]) -> Option<Vec<&[u8]>> {
    let mut pushes = Vec::new();
    let mut index = 0;
    while index < script.len() {
        let opcode = script[index];
        index += 1;

        let len = match opcode {
            0x01..=0x4b => opcode as usize,
            0x4c => {
                let len = *script.get(index)? as usize;
                index += 1;
                len
            }
            0x4d => {
                let bytes = script.get(index..index + 2)?;
                index += 2;
                u16::from_le_bytes([bytes[0], bytes[1]]) as usize
            }
            _ => return None,
        };

        let data = script.get(index..index + len)?;
        pushes.push(data);
        index += len;
    }

    Some(pushes)
}

fn read_raw_transaction_for_tx(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    txid: &[u8],
) -> Result<Option<Vec<u8>>, String> {
    conn.query_row(
        "SELECT raw FROM v_transactions \
         WHERE account_uuid = ?1 AND txid = ?2 AND raw IS NOT NULL \
         LIMIT 1",
        rusqlite::params![account_uuid, txid],
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| format!("Query error: {e}"))
}

fn read_history_base_by_txid(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    txid: &[u8],
) -> Result<Option<TxBase>, String> {
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            vt.txid,
            COALESCE(tx.id_tx, -1) AS transaction_id,
            vt.mined_height,
            -- NULL when no scanned block or expiry height makes expiry comparable: pending.
            COALESCE(vt.expired_unmined, 0) AS expired_unmined,
            vt.account_balance_delta,
            vt.fee_paid AS fee_paid,
            COALESCE(vt.block_time, 0) AS block_time,
            COALESCE(vt.total_spent, 0) AS total_spent,
            COALESCE(vt.total_received, 0) AS total_received,
            COALESCE(vt.is_shielding, 0) AS is_shielding,
            vt.expiry_height,
            COALESCE(vt.tx_index, -1) AS tx_index,
            tx.created,
            CAST(COALESCE(strftime('%s', tx.created), 0) AS INTEGER) AS created_time,
            EXISTS (
                SELECT 1
                FROM transactions spent_tx
                JOIN orchard_received_note_spends spent
                    ON spent.transaction_id = spent_tx.id_tx
                JOIN orchard_received_notes spent_note
                    ON spent_note.id = spent.orchard_received_note_id
                WHERE spent_tx.txid = vt.txid
                  AND spent_note.note_version = ?3
            ) AS spent_orchard_note,
            COALESCE(vt.spent_note_count, 0) AS spent_note_count
        FROM v_transactions vt
        LEFT JOIN transactions tx ON tx.txid = vt.txid
        WHERE vt.account_uuid = ?1
          AND vt.txid = ?2
        LIMIT 1
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let row = stmt
        .query_row(
            rusqlite::params![account_uuid, txid, ORCHARD_NOTE_VERSION],
            |row| {
                let fee = row.get::<_, Option<i64>>(5)?.map(i64::unsigned_abs);
                Ok(TxBase {
                    txid: row.get(0)?,
                    transaction_id: row.get(1)?,
                    mined_height: row.get(2)?,
                    expired_unmined: row.get(3)?,
                    account_balance_delta: row.get(4)?,
                    fee,
                    block_time: row.get::<_, i64>(6)?.unsigned_abs(),
                    total_spent: row.get::<_, i64>(7)?.unsigned_abs(),
                    total_received: row.get::<_, i64>(8)?.unsigned_abs(),
                    is_shielding: row.get(9)?,
                    expiry_height: row.get(10)?,
                    tx_index: row.get(11)?,
                    created: row.get(12)?,
                    created_time: row.get::<_, i64>(13)?.unsigned_abs(),
                    spent_orchard_note: row.get(14)?,
                    spent_note_count: row.get(15)?,
                    history: HistoryCompleteness::unread(fee),
                })
            },
        )
        .optional()
        .map_err(|e| format!("Query error: {e}"))?;

    Ok(row)
}

/// Read the library-owned accounting projection through the caller's connection.
/// Completeness and output reads must stay in the same transaction as this read.
fn read_history_bases(
    conn: &rusqlite::Connection,
    db_path: &str,
    network: WalletNetwork,
    account: AccountUuid,
) -> Result<Vec<TxBase>, String> {
    wallet_db_on(conn, db_path, network)
        .transaction_history_summaries(account)
        .map(|summaries| summaries.into_iter().map(TxBase::from).collect())
        .map_err(|e| format!("Failed to read history summaries: {e}"))
}

impl From<TransactionSummary> for TxBase {
    fn from(summary: TransactionSummary) -> Self {
        Self {
            txid: summary.txid.as_ref().to_vec(),
            transaction_id: summary.transaction_id,
            mined_height: summary.mined_height.map(u32::from),
            expired_unmined: summary.expired_unmined,
            account_balance_delta: summary.account_balance_delta,
            fee: summary.fee,
            block_time: summary.block_time.unwrap_or(0),
            total_spent: summary.total_spent,
            total_received: summary.total_received,
            is_shielding: summary.is_shielding,
            expiry_height: summary
                .expiry_height
                .map(|height| i64::from(u32::from(height))),
            tx_index: summary.tx_index.map(i64::from).unwrap_or(-1),
            created: summary.created,
            created_time: summary.created_time.map(i64::unsigned_abs).unwrap_or(0),
            spent_orchard_note: summary.has_orchard_spend,
            spent_note_count: summary.spent_note_count,
            history: HistoryCompleteness::unread(summary.fee),
        }
    }
}

fn read_history_outputs<'a>(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    txids: impl IntoIterator<Item = &'a [u8]>,
) -> Result<HashMap<Vec<u8>, Vec<TxOutput>>, String> {
    let mut seen = HashSet::<&[u8]>::new();
    let txid_array: Array = Rc::new(
        txids
            .into_iter()
            .filter(|txid| seen.insert(*txid))
            .map(|txid| Value::Blob(txid.to_vec()))
            .collect(),
    );
    if txid_array.is_empty() {
        return Ok(HashMap::new());
    }

    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            txo.txid,
            txo.output_pool,
            txo.output_index,
            txo.from_account_uuid,
            txo.to_account_uuid,
            txo.to_address,
            (
                SELECT sn.to_address
                FROM sent_notes sn
                JOIN transactions st ON st.id_tx = sn.transaction_id
                JOIN accounts from_acc ON from_acc.id = sn.from_account_id
                WHERE st.txid = txo.txid
                  AND from_acc.uuid = ?1
                  AND sn.output_pool = txo.output_pool
                  AND sn.output_index = txo.output_index
                  AND sn.to_address IS NOT NULL
                LIMIT 1
            ) AS sent_to_address,
            NULL AS transparent_receiver_address,
            (
                SELECT a.key_scope
                FROM accounts acc
                JOIN addresses a ON a.account_id = acc.id
                WHERE acc.uuid = txo.to_account_uuid
                  AND (
                      a.address = txo.to_address
                      OR a.cached_transparent_receiver_address = txo.to_address
                  )
                LIMIT 1
            ) AS to_key_scope,
            txo.value,
            txo.memo,
            (
                SELECT orn.note_version
                FROM orchard_received_notes orn
                WHERE txo.output_pool IN (3, 4)
                  AND orn.transaction_id = txo.transaction_id
                  AND orn.action_index = txo.output_index
                LIMIT 1
            ) AS note_version
        FROM v_tx_outputs txo
        JOIN rarray(?2) AS active_tx ON active_tx.value = txo.txid
        WHERE txo.from_account_uuid = ?1
           OR txo.to_account_uuid = ?1
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map(rusqlite::params![account_uuid, txid_array], |row| {
            Ok(TxOutput {
                txid: row.get(0)?,
                output_pool: row.get(1)?,
                output_index: row.get(2)?,
                from_account_uuid: row.get(3)?,
                to_account_uuid: row.get(4)?,
                to_address: row.get(5)?,
                sent_to_address: row.get(6)?,
                transparent_receiver_address: row.get(7)?,
                to_key_scope: row.get(8)?,
                value: row.get::<_, i64>(9)?.unsigned_abs(),
                memo: row.get(10)?,
                note_version: row.get(11)?,
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    let mut outputs = HashMap::<Vec<u8>, Vec<TxOutput>>::new();
    for row in rows {
        let output = row.map_err(|e| format!("Row error: {e}"))?;
        outputs.entry(output.txid.clone()).or_default().push(output);
    }
    Ok(outputs)
}

/// Reads which transactions spend the account's outputs to its ephemeral
/// addresses that `txids` created. A TEX send spends the output its funding
/// step created; restored wallets have no creation time to match them by.
fn read_ephemeral_spends<'a>(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    txids: impl IntoIterator<Item = &'a [u8]>,
) -> Result<EphemeralSpends, String> {
    let txid_array: Array = Rc::new(
        txids
            .into_iter()
            .map(|txid| Value::Blob(txid.to_vec()))
            .collect(),
    );
    let mut stmt = conn
        .prepare(
            r#"
        SELECT DISTINCT funding.txid, spending.txid
        FROM transparent_received_outputs tro
        JOIN accounts acc ON acc.id = tro.account_id
        JOIN addresses a ON a.id = tro.address_id
        JOIN transactions funding ON funding.id_tx = tro.transaction_id
        JOIN rarray(?2) AS active_tx ON active_tx.value = funding.txid
        JOIN transparent_received_output_spends s
            ON s.transparent_received_output_id = tro.id
        JOIN transactions spending ON spending.id_tx = s.transaction_id
        WHERE acc.uuid = ?1
          AND a.key_scope = ?3
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;
    let rows = stmt
        .query_map(
            rusqlite::params![account_uuid, txid_array, EPHEMERAL_KEY_SCOPE],
            |row| Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, Vec<u8>>(1)?)),
        )
        .map_err(|e| format!("Query error: {e}"))?;
    let mut spends = EphemeralSpends::new();
    for row in rows {
        let (funding, spending) = row.map_err(|e| format!("Row error: {e}"))?;
        spends.entry(funding).or_default().push(spending);
    }
    Ok(spends)
}

fn read_outputs_for_tx(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    txid: &[u8],
) -> Result<Vec<TxOutput>, String> {
    let mut stmt = conn
        .prepare(
            r#"
        SELECT
            txo.txid,
            txo.output_pool,
            txo.output_index,
            txo.from_account_uuid,
            txo.to_account_uuid,
            txo.to_address,
            (
                SELECT sn.to_address
                FROM sent_notes sn
                JOIN transactions st ON st.id_tx = sn.transaction_id
                JOIN accounts from_acc ON from_acc.id = sn.from_account_id
                WHERE st.txid = txo.txid
                  AND from_acc.uuid = ?1
                  AND sn.output_pool = txo.output_pool
                  AND sn.output_index = txo.output_index
                  AND sn.to_address IS NOT NULL
                LIMIT 1
            ) AS sent_to_address,
            (
                SELECT a.cached_transparent_receiver_address
                FROM accounts acc
                JOIN addresses a ON a.account_id = acc.id
                WHERE acc.uuid = txo.to_account_uuid
                  AND txo.output_pool = 0
                  AND (
                      a.address = txo.to_address
                      OR a.cached_transparent_receiver_address = txo.to_address
                  )
                  AND a.cached_transparent_receiver_address IS NOT NULL
                LIMIT 1
            ) AS transparent_receiver_address,
            (
                SELECT a.key_scope
                FROM accounts acc
                JOIN addresses a ON a.account_id = acc.id
                WHERE acc.uuid = txo.to_account_uuid
                  AND (
                      a.address = txo.to_address
                      OR a.cached_transparent_receiver_address = txo.to_address
                  )
                LIMIT 1
            ) AS to_key_scope,
            txo.value,
            txo.memo,
            (
                SELECT orn.note_version
                FROM orchard_received_notes orn
                WHERE txo.output_pool IN (3, 4)
                  AND orn.transaction_id = txo.transaction_id
                  AND orn.action_index = txo.output_index
                LIMIT 1
            ) AS note_version
        FROM v_tx_outputs txo
        WHERE txo.txid = ?2
          AND (
              txo.from_account_uuid = ?1
              OR txo.to_account_uuid = ?1
          )
        "#,
        )
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map(rusqlite::params![account_uuid, txid], |row| {
            Ok(TxOutput {
                txid: row.get(0)?,
                output_pool: row.get(1)?,
                output_index: row.get(2)?,
                from_account_uuid: row.get(3)?,
                to_account_uuid: row.get(4)?,
                to_address: row.get(5)?,
                sent_to_address: row.get(6)?,
                transparent_receiver_address: row.get(7)?,
                to_key_scope: row.get(8)?,
                value: row.get::<_, i64>(9)?.unsigned_abs(),
                memo: row.get(10)?,
                note_version: row.get(11)?,
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

fn summarize_activity_outputs(
    base: &TxBase,
    outputs: &[TxOutput],
    account_uuid: &[u8],
) -> ActivitySummary {
    let mut summary = ActivitySummary::default();
    let pays_others = pays_others(outputs, account_uuid);
    let recovered_self_transfer = recovered_transparent_self_transfer(base);

    for output in outputs {
        let from_own = output.from_account_uuid.as_deref() == Some(account_uuid);
        let to_own = output.to_account_uuid.as_deref() == Some(account_uuid);
        // Private output recovery can establish the receiver's scope before it
        // links the sender. Only account-funded recovery justifies treating an
        // unlinked owned output as self-payment/change rather than incoming.
        let recovered_from_own = output.from_account_uuid.is_none()
            && (base.history.inferred_outgoing.is_some() || recovered_self_transfer);

        if base.is_shielding {
            if to_own && is_shielded_pool(output.output_pool) {
                summary.shielded.add_output(output);
            }
            continue;
        }

        if from_own && to_own && base.spent_orchard_note && is_ironwood_output(output) {
            summary.internal_ironwood_transition.add_output(output);
            continue;
        }

        if to_own && is_user_visible_self_output(output) {
            summary.visible_own.add_output(output);
        }

        if output.output_pool == TRANSPARENT_POOL
            && to_own
            && output.to_key_scope == Some(EPHEMERAL_KEY_SCOPE)
        {
            summary.has_own_ephemeral_output = true;
        }

        if output.output_pool == 0 && from_own && to_own {
            summary.has_own_transparent_output = true;
            summary.own_transparent_output_amount = summary
                .own_transparent_output_amount
                .saturating_add(output.value);
        }

        if output.output_pool == TRANSPARENT_POOL
            && to_own
            && (from_own || recovered_from_own)
            && matches!(output.to_key_scope, Some(1) | Some(2))
        {
            summary.internal_transparent.add_output(output);
            continue;
        }

        let visible_self_output = (from_own || (recovered_self_transfer && recovered_from_own))
            && to_own
            && is_user_visible_self_output(output);
        let visible_sent = from_own && (!to_own || (visible_self_output && !pays_others));
        let visible_sent =
            visible_sent || (recovered_self_transfer && visible_self_output && !pays_others);
        let visible_received = to_own && (!from_own || visible_self_output);

        if visible_sent {
            summary.sent.add_output(output);
            if output.output_pool == 0 && !to_own {
                summary.has_external_transparent_send = true;
            }
        }
        if visible_received {
            summary.received.add_output(output);
            if output.output_pool == TRANSPARENT_POOL {
                summary.received_transparent.add_output(output);
            }
        }
    }

    summary
}

/// An exact zero payment outside the account plus its fully attributed fee
/// proves self-funding. It does not mean an external-scope self-payment is
/// change: that payment still belongs in Activity as Sent and Received.
fn recovered_transparent_self_transfer(base: &TxBase) -> bool {
    let debit = base.account_balance_delta.unsigned_abs();
    base.history.inferred_payment == Some(0)
        && base.account_balance_delta < 0
        && base.history.whole_fee == Some(debit)
        && base.history.shown_fee() == Fee::Known(debit)
}

/// Whether the account paid anyone else in the transaction. A self-payment
/// then shows only as the receive it is: counting it in the sent row too
/// would report the account's own funds as paid away (H09: a transparent
/// input paying an external address and the account's own shielded address).
/// Without another recipient, a self-payment is the whole payment and shows
/// as both a send and a receive.
fn pays_others(outputs: &[TxOutput], account_uuid: &[u8]) -> bool {
    outputs.iter().any(|output| {
        output.from_account_uuid.as_deref() == Some(account_uuid)
            && output.to_account_uuid.as_deref() != Some(account_uuid)
    })
}

fn detail_includes_output(
    base: &TxBase,
    output: &TxOutput,
    account_uuid: &[u8],
    tx_kind: &str,
    pays_others: bool,
) -> bool {
    let from_own = output.from_account_uuid.as_deref() == Some(account_uuid);
    let to_own = output.to_account_uuid.as_deref() == Some(account_uuid);

    match tx_kind {
        "shielded" => base.is_shielding && to_own && is_shielded_pool(output.output_pool),
        "sent" => {
            !base.is_shielding
                && from_own
                && (!to_own || (is_user_visible_self_output(output) && !pays_others))
        }
        "received" | "receiving" => {
            !base.is_shielding && to_own && (!from_own || is_user_visible_self_output(output))
        }
        "migration" => {
            !base.is_shielding
                && from_own
                && to_own
                && base.spent_orchard_note
                && is_ironwood_output(output)
        }
        _ => false,
    }
}

fn is_shielded_pool(output_pool: i64) -> bool {
    matches!(output_pool, SAPLING_POOL | ORCHARD_POOL | IRONWOOD_POOL)
}

fn exact_output_pool_label(output_pool: i64) -> Option<&'static str> {
    match output_pool {
        TRANSPARENT_POOL => Some("transparent"),
        SAPLING_POOL => Some("sapling"),
        ORCHARD_POOL => Some("orchard"),
        IRONWOOD_POOL => Some("ironwood"),
        _ => None,
    }
}

fn output_pool_label(output_pool: i64) -> &'static str {
    match output_pool {
        TRANSPARENT_POOL => "transparent",
        SAPLING_POOL | ORCHARD_POOL => "shielded",
        IRONWOOD_POOL => "ironwood",
        _ => "unknown",
    }
}

fn is_ironwood_output(output: &TxOutput) -> bool {
    output.output_pool == IRONWOOD_POOL || output.note_version == Some(IRONWOOD_NOTE_VERSION)
}

fn is_user_visible_self_output(output: &TxOutput) -> bool {
    let has_external_or_foreign_scope = matches!(output.to_key_scope, Some(0) | Some(-1));

    match output.output_pool {
        // Transparent self outputs are user-visible only when they land on a
        // normal external/foreign receiver. Internal and ephemeral receivers
        // are change/funding mechanics.
        TRANSPARENT_POOL => has_external_or_foreign_scope,
        // `is_change` is best-effort for wallet-owned outputs and can also be
        // set on explicit self-transfers. Treat external/foreign receivers and
        // sent-note recipients as visible; keep internal change hidden.
        SAPLING_POOL | ORCHARD_POOL | IRONWOOD_POOL => {
            has_external_or_foreign_scope || output.sent_to_address.is_some()
        }
        _ => false,
    }
}

fn decode_text_memo(memo: Option<&[u8]>) -> Option<String> {
    let memo = memo?;
    let memo_bytes = MemoBytes::from_bytes(memo).ok()?;
    match Memo::try_from(&memo_bytes).ok()? {
        Memo::Text(text) => {
            let text = String::from(text);
            if text.trim().is_empty() {
                None
            } else {
                Some(text)
            }
        }
        Memo::Empty | Memo::Future(_) | Memo::Arbitrary(_) => None,
    }
}

fn build_external_send_keys(
    bases: &[TxBase],
    summaries: &HashMap<Vec<u8>, ActivitySummary>,
) -> HashSet<FundingStepMatchKey> {
    let mut keys = HashSet::new();

    for base in bases {
        let Some(summary) = summaries.get(&base.txid) else {
            continue;
        };
        let Some(key) = external_send_key(base, summary) else {
            continue;
        };
        keys.insert(key);
    }

    keys
}

fn build_suppressed_funding_step_fees(
    bases: &[TxBase],
    summaries: &HashMap<Vec<u8>, ActivitySummary>,
    external_send_keys: &HashSet<FundingStepMatchKey>,
) -> SuppressedFundingStepFees {
    let mut funding_by_key: HashMap<FundingStepMatchKey, Vec<(i64, Fee)>> = HashMap::new();
    let mut external_by_key: HashMap<FundingStepMatchKey, Vec<i64>> = HashMap::new();

    for base in bases {
        let summary = summaries.get(&base.txid).cloned().unwrap_or_default();
        if let Some(key) = external_send_key(base, &summary) {
            external_by_key
                .entry(key)
                .or_default()
                .push(base.transaction_id);
        }

        if should_suppress_funding_step(base, &summary, external_send_keys) {
            if let Some(key) = funding_step_key(base, &summary) {
                funding_by_key
                    .entry(key)
                    .or_default()
                    .push((base.transaction_id, base.history.shown_fee()));
            }
        }
    }

    let mut matched = SuppressedFundingStepFees::default();
    for (key, mut funding_steps) in funding_by_key {
        let Some(mut external_sends) = external_by_key.remove(&key) else {
            continue;
        };

        funding_steps.sort_by_key(|(transaction_id, _)| *transaction_id);
        external_sends.sort_unstable();

        let mut external_index = 0;
        for (funding_transaction_id, funding_fee) in funding_steps {
            while external_index < external_sends.len()
                && external_sends[external_index] <= funding_transaction_id
            {
                external_index += 1;
            }

            let Some(external_transaction_id) = external_sends.get(external_index).copied() else {
                continue;
            };
            external_index += 1;

            matched
                .funding_parent_by_send_txid
                .insert(external_transaction_id, funding_transaction_id);
            matched
                .suppressed_funding_txids
                .insert(funding_transaction_id);
            let entry = matched
                .extra_fee_by_send_txid
                .entry(external_transaction_id)
                .or_insert(Fee::NotApplicable);
            *entry = entry.plus(funding_fee);
        }
    }

    matched
}

/// Folds TEX funding steps into the send that spends their ephemeral output,
/// matched by that output rather than by creation time, which a restored
/// wallet does not have. A step folds only when the account moved its own
/// funds in it and only its fee left ([`is_pure_funding_step`]), so the step
/// is the send's cost and no payment of its own, and only into a send that
/// shows a sent row with a known fee to carry the step's. Otherwise it keeps
/// its own row. Of several spenders, a mined one is the send, then one that
/// has not expired: an expired attempt's output was spent again.
fn link_funding_steps(
    bases: &[TxBase],
    summaries: &HashMap<Vec<u8>, ActivitySummary>,
    ephemeral_spends: &EphemeralSpends,
    already_suppressed: &HashSet<i64>,
) -> SuppressedFundingStepFees {
    let by_txid: HashMap<&[u8], &TxBase> = bases
        .iter()
        .map(|base| (base.txid.as_slice(), base))
        .collect();
    let summary_of = |base: &TxBase| summaries.get(&base.txid).cloned().unwrap_or_default();
    let mut linked = SuppressedFundingStepFees::default();
    for step in bases {
        if step.transaction_id < 0
            || already_suppressed.contains(&step.transaction_id)
            || !is_pure_funding_step(step, &summary_of(step))
        {
            continue;
        }
        let Some(send) = ephemeral_spends
            .get(&step.txid)
            .into_iter()
            .flatten()
            .filter_map(|txid| by_txid.get(txid.as_slice()).copied())
            .filter(|send| send.transaction_id >= 0 && send.txid != step.txid)
            .min_by_key(|send| {
                (
                    send.mined_height.is_none(),
                    send.expired_unmined,
                    send.transaction_id,
                )
            })
        else {
            continue;
        };
        // A send that is itself folded away, or funds a later send in turn,
        // would not carry the fee, and one whose own fee is unknown would
        // hide it in its unknown total: the step keeps its row.
        if already_suppressed.contains(&send.transaction_id)
            || is_pure_funding_step(send, &summary_of(send))
            || send.history.shown_fee() == Fee::Unknown
        {
            continue;
        }
        let send_shows_a_sent_row =
            classify_history_tx(send, &summary_of(send), Fee::NotApplicable)
                .iter()
                .any(|row| row.info.tx_kind == "sent");
        if !send_shows_a_sent_row {
            continue;
        }
        linked.suppressed_funding_txids.insert(step.transaction_id);
        linked
            .funding_parent_by_send_txid
            .entry(send.transaction_id)
            .or_insert(step.transaction_id);
        let fee = linked
            .extra_fee_by_send_txid
            .entry(send.transaction_id)
            .or_insert(Fee::NotApplicable);
        *fee = fee.plus(step.history.shown_fee());
    }
    linked
}

/// Whether `base` only funds the account's ephemeral outputs: it pays no
/// recorded or visible output, and its settled balance change is exactly the
/// fee it paid, so nothing else left the account.
fn is_pure_funding_step(base: &TxBase, summary: &ActivitySummary) -> bool {
    !base.is_shielding
        && base.account_balance_delta < 0
        && summary.has_own_ephemeral_output
        && summary.sent.output_count == 0
        && summary.visible_own.output_count == 0
        && base.history.exact_fee() == Some(base.account_balance_delta.unsigned_abs())
}

fn external_send_key(base: &TxBase, summary: &ActivitySummary) -> Option<FundingStepMatchKey> {
    if !summary.has_external_transparent_send || base.total_spent == 0 || base.transaction_id < 0 {
        return None;
    }

    base.created
        .as_ref()
        .map(|created| (created.clone(), base.expiry_key(), base.total_spent))
}

fn funding_step_key(base: &TxBase, summary: &ActivitySummary) -> Option<FundingStepMatchKey> {
    if summary.own_transparent_output_amount == 0 || base.transaction_id < 0 {
        return None;
    }

    base.created.as_ref().map(|created| {
        (
            created.clone(),
            base.expiry_key(),
            summary.own_transparent_output_amount,
        )
    })
}

fn should_suppress_funding_step(
    base: &TxBase,
    summary: &ActivitySummary,
    external_send_keys: &HashSet<FundingStepMatchKey>,
) -> bool {
    !base.is_shielding
        && base.total_spent > 0
        && base.total_received > 0
        && base.account_balance_delta <= 0
        && base.created.is_some()
        && summary.sent.amount == 0
        && summary.received.amount == 0
        && summary.has_own_transparent_output
        && funding_step_key(base, summary)
            .map(|key| external_send_keys.contains(&key))
            .unwrap_or(false)
}

fn classify_history_tx(
    base: &TxBase,
    summary: &ActivitySummary,
    extra_sent_fee: Fee,
) -> Vec<ClassifiedTx> {
    if base.is_shielding {
        let amount = if summary.shielded.amount > 0 {
            summary.shielded.amount
        } else {
            base.total_received
        };
        return vec![build_classified_tx(
            base, "shielded", amount, "shielded", false, 0,
        )];
    }

    if is_internal_ironwood_transition(base, summary) {
        return vec![build_classified_tx(
            base,
            "migration",
            summary.internal_ironwood_transition.amount,
            "ironwood",
            false,
            1,
        )];
    }

    // Private recovery reconstructed the exact payment of a transparent-only
    // debit the account fully funded, but not its recipients: no output it
    // paid is visible, so the outputs it knows of are change and none of them
    // is shown as a receive. The payment went to transparent outputs.
    if let Some(payment) = base.history.inferred_payment {
        if payment > 0 && base.account_balance_delta < 0 && summary.sent.output_count == 0 {
            return vec![build_classified_tx_with_fee(
                base,
                "sent",
                payment,
                "transparent",
                true,
                1,
                base.history.shown_fee().plus(extra_sent_fee),
            )];
        }
        // Without a known visible self-payment, the only amount we can show
        // for this recovered self-transfer is its fee as a net balance change.
        let debit = base.account_balance_delta.unsigned_abs();
        if payment == 0
            && base.account_balance_delta < 0
            && summary.sent.output_count == 0
            && base.history.whole_fee == Some(debit)
            && matches!(
                base.history.shown_fee(),
                Fee::Known(fee) | Fee::Whole(fee) if fee == debit
            )
        {
            let mut row = build_classified_tx_with_fee(
                base,
                "sent",
                debit,
                "transparent",
                true,
                1,
                base.history.shown_fee().plus(extra_sent_fee),
            );
            row.info.amount_is_net_change = true;
            return vec![row];
        }
    }

    // The library reconciled compact-scanned shielded effects and the Enhance fee.
    // The residual includes owned transparent outputs. Exclude known internal
    // change/funding, and show ordinary receipts separately from shielded change.
    if let Some(outgoing) = base.history.inferred_outgoing {
        if outgoing > 0 && summary.sent.output_count == 0 {
            let visible_outgoing = outgoing.checked_sub(summary.internal_transparent.amount);
            // Internal change has no visible payment. An ungrouped ephemeral
            // funding step still needs its net-change row: an Activity-only
            // residual does not prove that its debit was the account's fee.
            if visible_outgoing == Some(0) && summary.received_transparent.output_count == 0 {
                if summary.has_own_ephemeral_output && base.account_balance_delta < 0 {
                    return vec![build_movement_debit_row(base, extra_sent_fee)];
                }
                return Vec::new();
            }
            // Inconsistent local evidence must not underflow or erase a debit.
            let outgoing = visible_outgoing
                .filter(|amount| *amount > 0)
                .unwrap_or(outgoing);
            let mut sent = build_classified_tx(base, "sent", outgoing, "transparent", true, 1);
            sent.info.activity_pool = Some("transparent".to_string());
            let mut rows = vec![sent];
            if summary.received_transparent.output_count > 0 {
                let mut received = build_classified_tx(
                    base,
                    receiving_tx_kind(base),
                    summary.received_transparent.amount,
                    "transparent",
                    true,
                    2,
                );
                received.info.activity_pool = Some("transparent".to_string());
                rows.push(received);
            }
            return rows;
        }
    }

    // Discovery found this debit but not where the value went. The outputs it
    // knows of can only be change, so none of them is shown as a receive, and
    // the account's balance change is all that can be shown: it is
    // provisional, not a payment amount. A visible sent output, even a
    // zero-value memo-only one, is where the value went, and keeps its own row
    // below.
    if base.history.provisional && base.account_balance_delta < 0 && summary.sent.output_count == 0
    {
        return vec![build_unsettled_debit_row(base, extra_sent_fee)];
    }

    // A visible output makes a row even at zero value: zero-value outputs are
    // how memo-only payments travel.
    let mut rows = Vec::new();
    if summary.sent.output_count > 0 {
        let mut row = build_classified_tx_with_fee(
            base,
            "sent",
            summary.sent.amount,
            summary.sent.display_pool(),
            summary.sent.has_transparent,
            1,
            base.history.shown_fee().plus(extra_sent_fee),
        );
        row.info.activity_pool = Some(summary.sent.activity_pool().to_string());
        rows.push(row);
    }
    // Before enhancement links our zero-value change to its send, the change
    // looks like an external receipt, so a zero-value receipt needs a tx that
    // spent nothing or also produced a sent row.
    let zero_value_receipt_allowed = base.total_spent == 0 || summary.sent.output_count > 0;
    if summary.received.amount > 0
        || (summary.received.output_count > 0 && zero_value_receipt_allowed)
    {
        let mut row = build_classified_tx(
            base,
            receiving_tx_kind(base),
            summary.received.amount,
            summary.received.display_pool(),
            summary.received.has_transparent,
            2,
        );
        row.info.activity_pool = Some(summary.received.activity_pool().to_string());
        rows.push(row);
    }

    if rows.is_empty() {
        // An unmined debit of more than the account's own fee paid something
        // no output shows yet.
        if base.mined_height.is_none()
            && base.account_balance_delta < 0
            && base.total_spent > 0
            && base.account_balance_delta.unsigned_abs() > base.history.fee.known_or_zero()
        {
            rows.push(build_unsettled_debit_row(base, extra_sent_fee));
            return rows;
        }
        // A TEX funding step that no send carries the fee of: the fee was
        // still paid, so it keeps a row.
        if summary.has_own_ephemeral_output && base.account_balance_delta < 0 {
            rows.push(build_movement_debit_row(base, extra_sent_fee));
            return rows;
        }
        if base.total_spent > 0 && base.total_received > 0 {
            return rows;
        }
        if base.account_balance_delta > 0 {
            rows.push(build_classified_tx(
                base,
                receiving_tx_kind(base),
                base.account_balance_delta as u64,
                "unknown",
                false,
                2,
            ));
        } else {
            rows.push(build_classified_tx(base, "unknown", 0, "unknown", false, 3));
        }
    }

    rows
}

/// Owned Ironwood outputs do not prove an internal migration when the library
/// has reconciled a positive outgoing amount. They may instead be change from
/// an Orchard-funded payment whose recipient details are still unavailable.
fn is_internal_ironwood_transition(base: &TxBase, summary: &ActivitySummary) -> bool {
    !base.is_shielding
        && !base
            .history
            .inferred_outgoing
            .is_some_and(|amount| amount > 0)
        && base.spent_orchard_note
        && base.total_spent > 0
        && summary.internal_ironwood_transition.amount > 0
        && summary.sent.amount == 0
        && summary.received.amount == 0
}

fn receiving_tx_kind(base: &TxBase) -> &'static str {
    if base.mined_height.is_none() && !base.expired_unmined {
        "receiving"
    } else {
        "received"
    }
}

fn build_classified_tx(
    base: &TxBase,
    tx_kind: &str,
    display_amount: u64,
    display_pool: &str,
    is_transparent: bool,
    row_order: u8,
) -> ClassifiedTx {
    build_classified_tx_with_fee(
        base,
        tx_kind,
        display_amount,
        display_pool,
        is_transparent,
        row_order,
        base.history.shown_fee(),
    )
}

/// The row of a debit known only as the account's balance change, with no
/// output showing where its value went. With complete details and the
/// account's own fee, the rest of the change is exactly what it paid.
/// Otherwise the amount is the whole net change, nothing subtracted, and no
/// payment; when the account's own fee is all of it, the change is that fee.
fn build_movement_debit_row(base: &TxBase, extra_sent_fee: Fee) -> ClassifiedTx {
    let change = base.account_balance_delta.unsigned_abs();
    let (amount, net_change) = match base.history.fee {
        Fee::Known(fee) if base.history.details_complete && change > fee => (change - fee, false),
        _ => (change, true),
    };
    let mut row = build_classified_tx_with_fee(
        base,
        "sent",
        amount,
        "unknown",
        false,
        1,
        base.history.shown_fee().plus(extra_sent_fee),
    );
    // Enhance can establish activity shape before recipients, payment amounts, or the
    // account's fee share are known. Keep that display fact separate from destination
    // classification and completeness; false or missing evidence supplies no new label.
    if base.history.has_transparent_outputs == Some(true) {
        row.info.activity_pool = Some("transparent".to_string());
    }
    row.info.amount_is_net_change = net_change;
    row
}

/// The row of a debit still being filled in (provisional, or unmined) with
/// no output showing where its value went, as public history has always
/// shown it: the account's own known fee is subtracted and the rest is sent
/// or, with nothing left, an entry of unknown kind. Without the account's own
/// fee nothing can be subtracted, so the amount is its net change.
fn build_unsettled_debit_row(base: &TxBase, extra_sent_fee: Fee) -> ClassifiedTx {
    let Fee::Known(fee) = base.history.fee else {
        return build_movement_debit_row(base, extra_sent_fee);
    };
    let debit = base
        .account_balance_delta
        .unsigned_abs()
        .saturating_sub(fee);
    build_classified_tx_with_fee(
        base,
        if debit > 0 { "sent" } else { "unknown" },
        debit,
        "unknown",
        false,
        1,
        base.history.shown_fee().plus(extra_sent_fee),
    )
}

fn build_classified_tx_with_fee(
    base: &TxBase,
    tx_kind: &str,
    display_amount: u64,
    display_pool: &str,
    is_transparent: bool,
    row_order: u8,
    fee: Fee,
) -> ClassifiedTx {
    let sort_timestamp = base.display_timestamp();
    ClassifiedTx {
        info: TransactionInfo {
            txid_hex: hex::encode(&base.txid),
            mined_height: base.mined_height.unwrap_or(0) as u64,
            expired_unmined: base.expired_unmined,
            account_balance_delta: base.account_balance_delta,
            fee: fee.known_or_zero(),
            fee_state: fee.state(),
            block_time: base.block_time,
            is_transparent,
            tx_kind: tx_kind.to_string(),
            display_amount,
            display_pool: display_pool.to_string(),
            activity_pool: None,
            funding_parent_txid: None,
            funding_parent_mined_height: None,
            funding_parent_expired: None,
            created_time: base.created_time,
            details_complete: base.history.details_complete,
            provisional: base.history.provisional,
            amount_is_net_change: false,
        },
        sort_pending_rank: u8::from(base.mined_height.is_none() && !base.expired_unmined),
        sort_timestamp,
        sort_mined_height: base.mined_height.unwrap_or(0) as u64,
        tx_index: base.tx_index,
        row_order,
    }
}

impl TxBase {
    /// Records the history read's view of this transaction. A shielding is
    /// inferred only where the payment details justify it.
    fn attach_history(&mut self, history: HistoryCompleteness) {
        self.is_shielding &= history.justifies_shielding();
        self.history = history;
    }

    fn expiry_key(&self) -> i64 {
        self.expiry_height.unwrap_or(-1)
    }

    fn display_timestamp(&self) -> u64 {
        if self.block_time > 0 {
            self.block_time
        } else {
            self.created_time
        }
    }
}

/// A wallet-created transaction that is eligible for automatic
/// resubmit: unmined, not past its expiry height or explicitly
/// no-expiry, and sending value out of the wallet.
///
/// `raw_tx` is the full serialized transaction bytes ready to feed
/// back into `send_transaction` — no re-encoding required. The
/// resubmit path at `sync::send::resubmit_pending_transactions`
/// consumes this struct directly.
pub(crate) struct ResubmittableTx {
    pub txid_bytes: Vec<u8>,
    pub raw_tx: Vec<u8>,
    pub expiry_height: u32,
}

// Correlated to `t` in transactions. Positions survive a rewind that clears
// mined_height; even position zero proves this transaction was scanned as mined.
// The history trigger also retains mined evidence for transactions without change.
const MINED_TRANSACTION_EVIDENCE: &str = "(
    EXISTS (SELECT 1 FROM vizor_mined_transactions m WHERE m.txid = t.txid)
    OR EXISTS (SELECT 1 FROM sapling_received_notes n
            WHERE n.transaction_id = t.id_tx AND n.commitment_tree_position IS NOT NULL)
    OR EXISTS (SELECT 1 FROM orchard_received_notes n
               WHERE n.transaction_id = t.id_tx AND n.commitment_tree_position IS NOT NULL)
    OR EXISTS (SELECT 1 FROM ironwood_received_notes n
               WHERE n.transaction_id = t.id_tx AND n.commitment_tree_position IS NOT NULL)
)";

fn resubmission_candidate_sql(columns: &str) -> String {
    format!(
        "SELECT DISTINCT {columns} FROM v_transactions v
         WHERE v.mined_height IS NULL
           AND (v.expiry_height = 0 OR v.expiry_height > ?1)
           AND v.account_balance_delta < 0 AND v.raw IS NOT NULL
           AND NOT EXISTS (
               SELECT 1 FROM transactions t
               JOIN tx_retrieval_queue q ON q.txid = t.txid AND q.query_type = 0
               WHERE t.txid = v.txid AND {MINED_TRANSACTION_EVIDENCE}
           )"
    )
}

/// Whether a status request protects an outbound transaction with prior mined evidence.
/// This read does not retire the guard; callers retain it until tip validation.
pub(crate) fn has_recovered_status_work(
    conn: &rusqlite::Connection,
    txid: &[u8],
) -> Result<bool, String> {
    conn.query_row(
        &format!(
            "SELECT EXISTS (
            SELECT 1 FROM transactions t
            JOIN tx_retrieval_queue q ON q.txid = t.txid AND q.query_type = 0
            WHERE t.txid = ?1 AND t.mined_height IS NULL AND {MINED_TRANSACTION_EVIDENCE}
              AND EXISTS (SELECT 1 FROM v_transactions v WHERE v.txid = t.txid
                          AND v.account_balance_delta < 0 AND v.raw IS NOT NULL)
        )"
        ),
        [txid],
        |row| row.get(0),
    )
    .map_err(|e| format!("Recovery status evidence: {e}"))
}

/// Complete a conclusive non-mined status observation for the rewind recovery
/// case after tip identity validation. The caller holds the wallet write lock.
/// Rechecking evidence, recording the observation, and completing only status
/// work share one write transaction.
/// Returns false when the normal backend status policy should handle the txid.
pub(crate) fn resolve_recovered_nonmined_status(
    conn: &mut rusqlite::Connection,
    txid: &[u8],
) -> Result<bool, String> {
    let tx = conn
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(|e| format!("Recovery status transaction: {e}"))?;
    if !has_recovered_status_work(&tx, txid)? {
        return Ok(false);
    }
    // Match the pinned backend's chain_tip_height: scan ranges are end-exclusive.
    let range_end: Option<u32> = tx
        .query_row("SELECT MAX(block_range_end) FROM scan_queue", [], |row| {
            row.get(0)
        })
        .map_err(|e| format!("Recovery status chain tip: {e}"))?;
    let tip = range_end
        .filter(|end| *end > 0)
        .ok_or("Recovery status requires a known chain tip")?
        - 1;
    tx.execute(
        "UPDATE transactions SET confirmed_unmined_at_height = ?2 WHERE txid = ?1",
        rusqlite::params![txid, tip],
    )
    .map_err(|e| format!("Recovery status observation: {e}"))?;
    tx.execute(
        "DELETE FROM tx_retrieval_queue WHERE txid = ?1 AND query_type = 0",
        [txid],
    )
    .map_err(|e| format!("Recovery status completion: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Recovery status commit: {e}"))?;
    Ok(true)
}

/// Returns whether the base transaction table contains anything the full
/// account-aware resubmission query could accept.
///
/// This may return a false positive for an inbound transaction, because the
/// outbound balance predicate exists only in `v_transactions`. It must not
/// return a false negative. An empty result lets the normal sync case avoid
/// materializing that comparatively expensive aggregate view.
fn has_pending_raw_transaction(
    conn: &rusqlite::Connection,
    current_height: u32,
) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS ( \
             SELECT 1 FROM transactions \
             WHERE mined_height IS NULL \
               AND (expiry_height = 0 OR expiry_height > ?1) \
               AND raw IS NOT NULL \
         )",
        [current_height],
        |row| row.get(0),
    )
    .map_err(|e| format!("Pending transaction preflight error: {e}"))
}

fn should_skip_resubmission_view(conn: &rusqlite::Connection, current_height: u32) -> bool {
    match has_pending_raw_transaction(conn, current_height) {
        Ok(has_candidate) => !has_candidate,
        Err(error) => {
            // This is an optimization only. Preserve resubmission liveness if
            // an old or partially migrated database cannot run the preflight.
            log::warn!("resubmit: {error}; falling back to v_transactions");
            false
        }
    }
}

/// Return every wallet transaction that is eligible for automatic
/// resubmit at `current_height`.
///
/// Mirrors zcash-android-wallet-sdk's `SELECTION_TRX_RESUBMISSION`
/// predicate — see the Phase 3 design notes for why we follow the
/// SDK exactly:
///
///   * `mined_height IS NULL` — the transaction has not yet been
///     confirmed in a block.
///   * `expiry_height = 0 OR expiry_height > ?current_height` — the
///     transaction is still valid to relay. A zero expiry height means
///     no expiry; otherwise, once the current tip passes
///     `expiry_height`, the network will drop it and there is nothing
///     we can do by resubmitting.
///   * `account_balance_delta < 0` — the net balance change for the
///     account is negative, i.e. this is an outbound transaction
///     the wallet originated. Inbound transactions the sync loop
///     merely discovered on-chain (via `get_transaction` enhance
///     calls) should never be "resubmitted".
///   * Pending status work plus durable mined evidence suppresses relay
///     until the previously mined transaction has a conclusive status.
///   * `raw IS NOT NULL` — we actually have the serialized bytes to
///     broadcast. Defense-in-depth on top of the delta filter.
///
/// A transaction that touches more than one of the wallet's own
/// accounts shows up as more than one row in `v_transactions`; we
/// `SELECT DISTINCT` on `(txid, raw, expiry_height)` to collapse
/// that into a single broadcast instead of double-sending the same
/// bytes.
pub(crate) fn get_resubmittable_txs(
    db_path: &str,
    current_height: u32,
) -> Result<Vec<ResubmittableTx>, String> {
    let mut connection = open_readonly_conn(db_path)?;
    let conn = connection
        .transaction()
        .map_err(|e| format!("Read transaction error: {e}"))?;
    if should_skip_resubmission_view(&conn, current_height) {
        return Ok(Vec::new());
    }

    let mut stmt = conn
        .prepare(&resubmission_candidate_sql(
            "v.txid, v.raw, v.expiry_height",
        ))
        .map_err(|e| format!("SQL error: {e}"))?;

    let rows = stmt
        .query_map([current_height], |row| {
            let txid_bytes: Vec<u8> = row.get(0)?;
            let raw_tx: Vec<u8> = row.get(1)?;
            // The WHERE clause rejects NULL expiry heights but still
            // permits 0 as the protocol no-expiry marker.
            let expiry_height: u32 = row
                .get::<_, Option<i64>>(2)?
                .map(|h| h.max(0) as u32)
                .unwrap_or(0);
            Ok(ResubmittableTx {
                txid_bytes,
                raw_tx,
                expiry_height,
            })
        })
        .map_err(|e| format!("Query error: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Row error: {e}"))
}

/// Returns resubmittable transactions after filtering `excluded_txids` before
/// loading raw transaction bytes.
pub(crate) fn get_resubmittable_txs_excluding(
    db_path: &str,
    current_height: u32,
    excluded_txids: &HashSet<Vec<u8>>,
) -> Result<Vec<ResubmittableTx>, String> {
    if excluded_txids.is_empty() {
        return get_resubmittable_txs(db_path, current_height);
    }

    let mut connection = open_readonly_conn(db_path)?;
    let conn = connection
        .transaction()
        .map_err(|e| format!("Read transaction error: {e}"))?;
    if should_skip_resubmission_view(&conn, current_height) {
        return Ok(Vec::new());
    }
    let candidate_metadata = {
        let mut stmt = conn
            .prepare(&resubmission_candidate_sql("v.txid, v.expiry_height"))
            .map_err(|e| format!("SQL error: {e}"))?;
        let rows = stmt
            .query_map([current_height], |row| {
                let txid_bytes: Vec<u8> = row.get(0)?;
                let expiry_height = row
                    .get::<_, Option<i64>>(1)?
                    .map(|h| h.max(0) as u32)
                    .unwrap_or(0);
                Ok((txid_bytes, expiry_height))
            })
            .map_err(|e| format!("Query error: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Row error: {e}"))?
    };

    let mut raw_stmt = conn
        .prepare("SELECT raw FROM transactions WHERE txid = ?1 AND raw IS NOT NULL")
        .map_err(|e| format!("SQL error: {e}"))?;
    candidate_metadata
        .into_iter()
        .filter(|(txid_bytes, _)| !excluded_txids.contains(txid_bytes))
        .map(|(txid_bytes, expiry_height)| {
            let raw_tx = raw_stmt
                .query_row([&txid_bytes], |row| row.get::<_, Vec<u8>>(0))
                .map_err(|e| format!("Raw transaction query error: {e}"))?;
            Ok(ResubmittableTx {
                txid_bytes,
                raw_tx,
                expiry_height,
            })
        })
        .collect()
}

#[cfg(test)]
#[path = "transactions/resubmission_tests.rs"]
pub(super) mod resubmission_tests;

#[cfg(test)]
#[path = "transactions/history_summary_tests.rs"]
mod history_summary_tests;

#[cfg(test)]
#[path = "transactions/private_shielding_tests.rs"]
mod private_shielding_tests;

#[cfg(test)]
#[path = "transactions/private_recovery_tests.rs"]
mod private_recovery_tests;

#[cfg(test)]
mod tests {
    //! SQL-predicate regression tests for `get_resubmittable_txs`.
    //!
    //! `get_resubmittable_txs` is a thin wrapper around a `v_transactions`
    //! SELECT, but the SELECT is the entire contract: it's the piece that
    //! encodes the four resubmit invariants we copied from
    //! `zcash-android-wallet-sdk`'s `SELECTION_TRX_RESUBMISSION`.
    //!
    //! We test against a stand-in schema: a real SQLite DB with a plain
    //! `v_transactions` table mirroring the columns the production view
    //! exposes. That's enough for the WHERE clause to exercise each
    //! filter independently without standing up the whole
    //! `zcash_client_sqlite` migration stack.
    //!
    //! If the production `v_transactions` view ever gains (or loses)
    //! one of the columns we query here (`txid`, `raw`, `mined_height`,
    //! `expiry_height`, `account_balance_delta`), the real build breaks
    //! loudly at the first real query — but these unit tests still
    //! exercise the logic, so a regression in the SQL text shows up here
    //! first.
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn unavailable_wallet_balance_is_zero_but_not_available() {
        for availability in [
            WalletBalanceAvailability::SummaryUnavailable,
            WalletBalanceAvailability::AccountUnavailable,
        ] {
            let balance = WalletBalance::unavailable(availability, false);
            assert_eq!(balance.availability, availability);
            assert_eq!(balance.transparent_stop, None);
            assert_eq!(balance.transparent, 0);
            assert_eq!(balance.sapling, 0);
            assert_eq!(balance.orchard, 0);
            assert_eq!(balance.transparent_pending, 0);
            assert_eq!(balance.sapling_pending, 0);
            assert_eq!(balance.orchard_pending, 0);
            assert_eq!(balance.change_pending_confirmation, 0);
            assert_eq!(balance.value_pending_spendability, 0);
            assert_eq!(balance.uneconomic_value, 0);
        }
    }

    /// Build a throwaway SQLite database with a minimal
    /// `v_transactions` table and return its `NamedTempFile`
    /// handle. Tests keep the handle alive for the duration of the
    /// test so the file isn't auto-deleted under them.
    pub(super) fn fresh_db() -> NamedTempFile {
        let file = NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY,
                 txid BLOB UNIQUE,
                 confirmed_unmined_at_height INTEGER,
                 raw BLOB,
                 mined_height INTEGER,
                 expiry_height INTEGER
             );
             CREATE TABLE tx_retrieval_queue (txid BLOB, query_type INTEGER,
                 PRIMARY KEY (txid, query_type));
             CREATE TABLE scan_queue (block_range_end INTEGER);
             INSERT INTO scan_queue VALUES (900001);
             CREATE TABLE sapling_received_notes (transaction_id INTEGER, commitment_tree_position INTEGER);
             CREATE TABLE orchard_received_notes (transaction_id INTEGER, commitment_tree_position INTEGER);
             CREATE TABLE ironwood_received_notes (transaction_id INTEGER, commitment_tree_position INTEGER);
             CREATE TABLE v_transactions (
                 txid BLOB NOT NULL,
                 raw BLOB,
                 mined_height INTEGER,
                 expiry_height INTEGER,
                 account_balance_delta INTEGER NOT NULL
             );",
        )
        .unwrap();
        crate::wallet::db::ensure_mined_transaction_history(&conn).unwrap();
        file
    }

    fn mined_output_evidence_db() -> NamedTempFile {
        let file = NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY,
                 txid BLOB NOT NULL,
                 mined_height INTEGER,
                 min_observed_height INTEGER NOT NULL,
                 expiry_height INTEGER
             );
             CREATE TABLE sapling_received_notes (
                 transaction_id INTEGER NOT NULL,
                 commitment_tree_position INTEGER
             );
             CREATE TABLE orchard_received_notes (
                 transaction_id INTEGER NOT NULL,
                 commitment_tree_position INTEGER
             );
             CREATE TABLE ironwood_received_notes (
                 transaction_id INTEGER NOT NULL,
                 commitment_tree_position INTEGER
             );",
        )
        .unwrap();
        crate::wallet::db::ensure_mined_transaction_history(&conn).unwrap();
        file
    }

    /// Insert one synthetic row into `v_transactions`.
    pub(super) fn insert_row(
        db: &NamedTempFile,
        txid: &[u8],
        raw: Option<&[u8]>,
        mined_height: Option<i64>,
        expiry_height: Option<i64>,
        account_balance_delta: i64,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, raw, mined_height, expiry_height)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(txid) DO UPDATE SET
                 raw = excluded.raw,
                 mined_height = excluded.mined_height,
                 expiry_height = excluded.expiry_height",
            rusqlite::params![txid, raw, mined_height, expiry_height],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO v_transactions (txid, raw, mined_height, expiry_height, account_balance_delta)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![txid, raw, mined_height, expiry_height, account_balance_delta],
        )
        .unwrap();
    }

    pub(super) fn fake_txid(byte: u8) -> [u8; 32] {
        [byte; 32]
    }

    #[test]
    fn mined_output_evidence_requires_an_unmined_tx_with_a_positioned_note() {
        let db = mined_output_evidence_db();
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        for (id, mined_height) in [
            (1, None),
            (2, None),
            (3, None),
            (4, None),
            (5, Some(1_000_000)),
            (6, None),
        ] {
            conn.execute(
                "INSERT INTO transactions
                    (id_tx, txid, mined_height, min_observed_height, expiry_height)
                 VALUES (?1, ?2, ?3, 900, 1_100)",
                rusqlite::params![id, fake_txid(id as u8), mined_height],
            )
            .unwrap();
        }
        conn.execute(
            "INSERT INTO sapling_received_notes VALUES (1, 10), (4, NULL), (5, 20)",
            [],
        )
        .unwrap();
        conn.execute("INSERT INTO orchard_received_notes VALUES (2, 30)", [])
            .unwrap();
        conn.execute("INSERT INTO ironwood_received_notes VALUES (3, 40)", [])
            .unwrap();
        drop(conn);

        let pending_ranges = [BlockHeight::from_u32(900)..BlockHeight::from_u32(1_100)];
        let got = get_unmined_txids_with_mined_output_evidence(
            db.path().to_str().unwrap(),
            &pending_ranges,
        )
        .unwrap();
        assert_eq!(
            got,
            HashSet::from([
                fake_txid(1).to_vec(),
                fake_txid(2).to_vec(),
                fake_txid(3).to_vec(),
            ])
        );
    }

    #[test]
    fn mined_output_evidence_stops_deferring_after_restoring_ranges_pass() {
        let db = mined_output_evidence_db();
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        for (id, expiry_height) in [(1, 600), (2, 0)] {
            conn.execute(
                "INSERT INTO transactions
                    (id_tx, txid, mined_height, min_observed_height, expiry_height)
                 VALUES (?1, ?2, NULL, 500, ?3)",
                rusqlite::params![id, fake_txid(id as u8), expiry_height],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO orchard_received_notes VALUES (?1, ?2)",
                rusqlite::params![id, id * 10],
            )
            .unwrap();
        }
        drop(conn);

        let recovery_and_older = [
            BlockHeight::from_u32(500)..BlockHeight::from_u32(600),
            BlockHeight::from_u32(100)..BlockHeight::from_u32(400),
        ];
        assert_eq!(
            get_unmined_txids_with_mined_output_evidence(
                db.path().to_str().unwrap(),
                &recovery_and_older,
            )
            .unwrap(),
            HashSet::from([fake_txid(1).to_vec(), fake_txid(2).to_vec()])
        );

        let older_only = [BlockHeight::from_u32(100)..BlockHeight::from_u32(400)];
        assert!(get_unmined_txids_with_mined_output_evidence(
            db.path().to_str().unwrap(),
            &older_only,
        )
        .unwrap()
        .is_empty());

        let after_expiry = [BlockHeight::from_u32(600)..BlockHeight::from_u32(700)];
        assert_eq!(
            get_unmined_txids_with_mined_output_evidence(
                db.path().to_str().unwrap(),
                &after_expiry,
            )
            .unwrap(),
            HashSet::from([fake_txid(2).to_vec()])
        );
    }

    fn tx_base_for_history() -> TxBase {
        TxBase {
            txid: fake_txid(1).to_vec(),
            transaction_id: 1,
            mined_height: Some(121),
            expired_unmined: false,
            account_balance_delta: -625_000_000,
            fee: Some(20_000),
            block_time: 1_800_000_000,
            total_spent: 625_000_000,
            total_received: 0,
            is_shielding: false,
            expiry_height: Some(122),
            tx_index: 0,
            created: None,
            created_time: 0,
            spent_orchard_note: true,
            spent_note_count: 1,
            history: HistoryCompleteness {
                has_transparent_outputs: None,
                details_complete: true,
                classification: Some(HistoryClassification::Reconstructed),
                provisional: false,
                effects_settled: true,
                fee: Fee::Known(20_000),
                whole_fee: None,
                sole_transparent_funder: false,
                inferred_payment: None,
                inferred_outgoing: None,
            },
        }
    }

    #[test]
    fn classify_internal_ironwood_transition_as_migration() {
        let mut summary = ActivitySummary::default();
        summary.internal_ironwood_transition.amount = 624_980_000;

        for outgoing in [None, Some(0)] {
            let mut base = tx_base_for_history();
            base.history.inferred_outgoing = outgoing;
            let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

            assert_eq!(rows.len(), 1);
            assert_eq!(rows[0].info.tx_kind, "migration");
            assert_eq!(rows[0].info.display_amount, 624_980_000);
            assert_eq!(rows[0].info.display_pool, "ironwood");
            assert_eq!(rows[0].info.activity_pool, None);
        }
    }

    #[test]
    fn classify_expired_internal_ironwood_transition_as_failed_migration() {
        let mut base = tx_base_for_history();
        base.mined_height = None;
        base.expired_unmined = true;

        let mut summary = ActivitySummary::default();
        summary.internal_ironwood_transition.amount = 624_980_000;

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "migration");
        assert!(rows[0].info.expired_unmined);
        assert_eq!(rows[0].info.display_amount, 624_980_000);
        assert_eq!(rows[0].info.display_pool, "ironwood");
    }

    #[test]
    fn private_orchard_unshielding_with_ironwood_change_matches_public_activity() {
        let account = test_account_uuid().as_bytes().to_vec();
        // Ironwood notes occur both in the legacy Orchard representation and
        // in the dedicated Ironwood pool. Neither representation proves that
        // a transaction containing change was only an internal migration.
        for change_pool in [ORCHARD_POOL, IRONWOOD_POOL] {
            for owned_receipt in [false, true] {
                let mut base = tx_base_for_history();
                base.total_spent = 1_000_000;
                base.total_received = 735_000 + if owned_receipt { 250_000 } else { 0 };
                base.account_balance_delta = if owned_receipt { -15_000 } else { -265_000 };
                base.attach_history(HistoryCompleteness {
                    effects_settled: true,
                    sole_transparent_funder: false,
                    has_transparent_outputs: Some(true),
                    details_complete: false,
                    classification: Some(HistoryClassification::Provisional),
                    provisional: true,
                    fee: Fee::Unknown,
                    whole_fee: Some(15_000),
                    inferred_payment: None,
                    inferred_outgoing: Some(250_000),
                });
                let change = TxOutput {
                    txid: base.txid.clone(),
                    output_pool: change_pool,
                    output_index: 0,
                    from_account_uuid: Some(account.clone()),
                    to_account_uuid: Some(account.clone()),
                    to_address: None,
                    sent_to_address: None,
                    transparent_receiver_address: None,
                    to_key_scope: Some(1),
                    value: 735_000,
                    memo: None,
                    note_version: Some(IRONWOOD_NOTE_VERSION),
                };
                let recipient = TxOutput {
                    txid: base.txid.clone(),
                    output_pool: TRANSPARENT_POOL,
                    output_index: 0,
                    from_account_uuid: Some(account.clone()),
                    to_account_uuid: owned_receipt.then(|| account.clone()),
                    to_address: None,
                    sent_to_address: None,
                    transparent_receiver_address: None,
                    to_key_scope: Some(0),
                    value: 250_000,
                    memo: None,
                    note_version: None,
                };
                let mut private_outputs = vec![change.clone()];
                if owned_receipt {
                    let mut receipt = recipient.clone();
                    // Private address recovery observes our receipt without
                    // recovering the transaction's outgoing recipient details.
                    receipt.from_account_uuid = None;
                    private_outputs.push(receipt);
                }
                let private_summary = summarize_activity_outputs(&base, &private_outputs, &account);
                let private_rows = classify_history_tx(&base, &private_summary, Fee::NotApplicable);

                base.history.inferred_outgoing = None;
                base.history.provisional = false;
                base.history.details_complete = true;
                base.history.classification = Some(HistoryClassification::Reconstructed);
                base.history.fee = Fee::Known(15_000);
                let public_summary =
                    summarize_activity_outputs(&base, &[change, recipient], &account);
                let public_rows = classify_history_tx(&base, &public_summary, Fee::NotApplicable);

                assert_eq!(private_rows.len(), if owned_receipt { 2 } else { 1 });
                assert_eq!(private_rows.len(), public_rows.len());
                assert_eq!(private_rows[0].info.tx_kind, "sent");
                for (private, public) in private_rows.iter().zip(&public_rows) {
                    assert_eq!(private.info.tx_kind, public.info.tx_kind);
                    assert_eq!(private.info.display_amount, 250_000);
                    assert_eq!(private.info.display_amount, public.info.display_amount);
                    assert_eq!(private.info.activity_pool, public.info.activity_pool);
                    assert_eq!(private.info.fee, public.info.fee);
                    assert_eq!(private.info.fee, 15_000);
                    assert_eq!(
                        private.info.amount_is_net_change,
                        public.info.amount_is_net_change
                    );
                    assert!(!private.info.amount_is_net_change);
                    assert!(private.info.provisional);
                    assert!(!private.info.details_complete);
                }
            }
        }
    }

    /// A mined debit that discovery found without its payment details: the
    /// account spent 1 ZEC and got 0.3 ZEC of change back.
    fn provisional_debit() -> (TxBase, ActivitySummary) {
        let mut base = tx_base_for_history();
        base.spent_orchard_note = false;
        base.fee = None;
        base.account_balance_delta = -70_000_000;
        base.total_spent = 100_000_000;
        base.total_received = 30_000_000;
        base.attach_history(HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: true,
            effects_settled: true,
            fee: Fee::Unknown,
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
            inferred_outgoing: None,
        });
        let mut summary = ActivitySummary::default();
        // The change arrived on an address that reads as a receive.
        summary.received.amount = 30_000_000;
        summary.received.has_transparent = true;
        (base, summary)
    }

    #[test]
    fn compact_enhanced_outgoing_matches_public_activity_with_or_without_owned_receipt() {
        for owned_receipt in [false, true] {
            let (mut base, mut summary) = provisional_debit();
            base.total_spent = 107_485_000;
            base.total_received = 107_220_000 + if owned_receipt { 250_000 } else { 0 };
            base.account_balance_delta = if owned_receipt { -15_000 } else { -265_000 };
            base.history.whole_fee = Some(15_000);
            base.history.inferred_outgoing = Some(250_000);
            base.history.has_transparent_outputs = Some(true);
            // Shielded change is visible in the unreconciled output summary too.
            summary.received.amount = base.total_received;
            if owned_receipt {
                summary.received_transparent.amount = 250_000;
                summary.received_transparent.output_count = 1;
            }

            let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
            assert_eq!(rows.len(), if owned_receipt { 2 } else { 1 });
            assert_eq!(rows[0].info.tx_kind, "sent");
            assert_eq!(rows[0].info.display_amount, 250_000);
            assert_eq!(rows[0].info.activity_pool.as_deref(), Some("transparent"));
            assert_eq!(rows[0].info.fee, 15_000);
            assert!(!rows[0].info.amount_is_net_change);
            assert!(rows[0].info.provisional);
            assert!(!rows[0].info.details_complete);
            if owned_receipt {
                assert_eq!(rows[1].info.tx_kind, "received");
                assert_eq!(rows[1].info.display_amount, 250_000);
            }
        }
    }

    #[test]
    fn compact_enhanced_external_send_excludes_the_network_fee() {
        let (mut base, summary) = provisional_debit();
        base.account_balance_delta = -215_000;
        base.history.whole_fee = Some(15_000);
        base.history.inferred_outgoing = Some(200_000);
        base.history.has_transparent_outputs = Some(true);
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "sent");
        assert_eq!(rows[0].info.display_amount, 200_000);
        assert_eq!(rows[0].info.fee, 15_000);
        assert!(!rows[0].info.amount_is_net_change);
    }

    /// Read scopes through the production SQL reader, then run the complete
    /// Activity pipeline. Synthetic outputs model restoration without a sender
    /// link; public enhancement supplies that link on the very same outputs.
    fn recovered_activity_fixture(
        mut base: TxBase,
        owned_outputs: &[(u64, Option<i64>)],
        public: bool,
    ) -> Vec<TransactionInfo> {
        let db = fresh_history_db();
        let account = test_account_uuid();
        insert_history_tx(
            &db,
            account,
            &base.txid,
            Some(121),
            0,
            Some(122),
            base.account_balance_delta,
            base.total_spent as i64,
            base.total_received as i64,
            false,
            None,
        );
        for (index, &(value, scope)) in owned_outputs.iter().enumerate() {
            insert_output_with_address(
                &db,
                &base.txid,
                TRANSPARENT_POOL,
                public.then_some(account),
                Some(account),
                value as i64,
                false,
                Some(&format!("synthetic-receiver-{index}")),
                scope,
            );
        }
        let conn = open_readonly_conn(db.path().to_str().unwrap()).unwrap();
        let outputs =
            read_history_outputs(&conn, account.as_bytes(), [base.txid.as_slice()]).unwrap();
        if public {
            base.history = HistoryCompleteness::complete_for(&base);
        }
        assemble_history(
            &[base],
            &outputs,
            &EphemeralSpends::new(),
            account.as_bytes(),
            None,
        )
    }

    fn compact_funding_base(amount: u64) -> TxBase {
        let (mut base, _) = provisional_debit();
        base.total_spent = 1_000_000 + amount + 15_000;
        base.total_received = 1_000_000 + amount;
        base.account_balance_delta = -15_000;
        base.history.whole_fee = Some(15_000);
        base.history.inferred_outgoing = Some(amount);
        base.history.has_transparent_outputs = Some(true);
        base
    }

    #[test]
    fn recovered_activity_excludes_internal_funding_amounts_without_created_metadata() {
        for amount in [20_000, 110_000] {
            for scope in [1, 2] {
                let base = compact_funding_base(amount);
                assert!(base.created.is_none());
                let public =
                    recovered_activity_fixture(base.clone(), &[(amount, Some(scope))], true);
                let private = recovered_activity_fixture(base, &[(amount, Some(scope))], false);
                if scope == EPHEMERAL_KEY_SCOPE {
                    // An unmatched funding step keeps its known net change,
                    // without presenting its internal output as payment. This
                    // fixture supplies no account fee, so keep it unknown.
                    assert_eq!(public.len(), 1);
                    assert_eq!(public[0].tx_kind, "sent");
                    assert_eq!(public[0].display_amount, 15_000);
                    assert!(public[0].amount_is_net_change);
                    assert_eq!(public[0].fee_state, TransactionFeeState::Unknown);
                    assert_eq!(public[0].fee, 0);
                } else {
                    assert!(public.is_empty(), "ordinary change remains hidden");
                }
                if scope == EPHEMERAL_KEY_SCOPE {
                    assert_eq!(private.len(), 1, "ungrouped funding keeps its debit");
                    assert_eq!(private[0].tx_kind, "sent");
                    assert_eq!(private[0].display_amount, 15_000);
                    assert!(private[0].amount_is_net_change);
                    assert!(private[0].provisional);
                    assert!(!private[0].details_complete);
                    assert_eq!(private[0].display_pool, "unknown");
                    assert_eq!(
                        (private[0].fee_state, private[0].fee),
                        (TransactionFeeState::WholeTransaction, 15_000)
                    );
                } else {
                    assert!(private.is_empty(), "ordinary change remains hidden");
                }
            }
        }
    }

    #[test]
    fn recovered_activity_preserves_external_self_payment_like_public() {
        for scope in [0, -1] {
            let base = compact_funding_base(250_000);
            let public = recovered_activity_fixture(base.clone(), &[(250_000, Some(scope))], true);
            let private = recovered_activity_fixture(base, &[(250_000, Some(scope))], false);
            let signature = |rows: &[TransactionInfo]| {
                rows.iter()
                    .map(|row| {
                        (
                            row.tx_kind.clone(),
                            row.display_amount,
                            row.activity_pool.clone(),
                        )
                    })
                    .collect::<Vec<_>>()
            };
            assert_eq!(signature(&private), signature(&public));
            assert_eq!(private.len(), 2);
            assert_eq!(private[0].display_amount, 250_000);
            assert_eq!(private[1].display_amount, 250_000);
            assert!(private
                .iter()
                .all(|row| row.provisional && !row.details_complete));
        }
    }

    #[test]
    fn recovered_activity_subtracts_only_known_internal_funding() {
        let base = compact_funding_base(270_000);
        let rows =
            recovered_activity_fixture(base, &[(20_000, Some(2)), (250_000, Some(0))], false);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].tx_kind, "sent");
        assert_eq!(rows[0].display_amount, 250_000);
        assert_eq!(rows[1].tx_kind, "received");
        assert_eq!(rows[1].display_amount, 250_000);

        // The remainder can also be an external payment whose recipient is
        // unavailable. It must survive removing the known change output.
        let rows =
            recovered_activity_fixture(compact_funding_base(220_000), &[(20_000, Some(1))], false);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].display_amount, 200_000);
    }

    #[test]
    fn recovered_activity_does_not_hide_unknown_scope_or_erase_conflicting_debits() {
        let rows =
            recovered_activity_fixture(compact_funding_base(20_000), &[(20_000, None)], false);
        assert_eq!(
            rows.len(),
            2,
            "unknown scope does not prove internal funding"
        );
        assert_eq!(rows[0].display_amount, 20_000);
        assert!(rows[0].provisional);
        let rows =
            recovered_activity_fixture(compact_funding_base(20_000), &[(30_000, Some(2))], false);
        assert_eq!(rows.len(), 1, "conflicting evidence cannot erase the debit");
        assert_eq!(rows[0].display_amount, 20_000);
        assert!(rows[0].provisional);
    }

    #[test]
    fn recovered_activity_keeps_unrelated_incoming_on_internal_receivers() {
        let mut base = tx_base_for_history();
        base.total_spent = 0;
        base.total_received = 20_000;
        base.account_balance_delta = 20_000;
        base.history = HistoryCompleteness::unread(None);
        let rows = recovered_activity_fixture(base, &[(20_000, Some(2))], false);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].tx_kind, "received");
        assert_eq!(rows[0].display_amount, 20_000);
    }

    #[test]
    fn recovered_activity_restores_visible_transparent_self_transfer_instead_of_fee_only() {
        let mut base = tx_base_for_history();
        base.spent_orchard_note = false;
        base.total_spent = 110_000;
        base.total_received = 100_000;
        base.account_balance_delta = -10_000;
        base.fee = Some(10_000);
        base.history = HistoryCompleteness {
            effects_settled: true,
            sole_transparent_funder: true,
            inferred_payment: Some(0),
            whole_fee: Some(10_000),
            fee: Fee::Known(10_000),
            details_complete: false,
            provisional: false,
            classification: None,
            has_transparent_outputs: Some(true),
            inferred_outgoing: None,
        };
        for scope in [0, -1] {
            let public = recovered_activity_fixture(base.clone(), &[(100_000, Some(scope))], true);
            let private =
                recovered_activity_fixture(base.clone(), &[(100_000, Some(scope))], false);
            assert_eq!(public.len(), 2);
            assert_eq!(private.len(), 2);
            for (actual, expected) in private.iter().zip(public.iter()) {
                assert_eq!(actual.tx_kind, expected.tx_kind);
                assert_eq!(actual.display_amount, expected.display_amount);
                assert_eq!(actual.display_amount, 100_000);
                assert!(!actual.amount_is_net_change);
                assert!(!actual.details_complete);
            }
        }
        // An owned internal receiver is still not an explicit self-payment.
        let rows = recovered_activity_fixture(base, &[(100_000, Some(1))], false);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].display_amount, 10_000);
        assert!(rows[0].amount_is_net_change);
    }

    #[test]
    fn a_provisional_debit_with_change_is_one_sent_row_not_a_receive() {
        let (base, summary) = provisional_debit();

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "sent");
        assert_eq!(
            info.display_amount, 70_000_000,
            "the net debit, fee included"
        );
        assert!(info.amount_is_net_change, "not a payment amount");
        assert_eq!(info.display_pool, "unknown", "no recipient is invented");
        assert_eq!(info.fee_state, TransactionFeeState::Unknown);
        assert_eq!(info.fee, 0);
        assert!(info.provisional);
        assert!(!info.details_complete);
    }

    /// The account's own recorded fee is subtracted from a provisional debit,
    /// as public history has always shown it.
    #[test]
    fn a_provisional_debit_excludes_a_recorded_fee() {
        let (mut base, summary) = provisional_debit();
        base.history.fee = Fee::Known(10_000);

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "sent");
        assert_eq!(rows[0].info.display_amount, 69_990_000);
        assert!(!rows[0].info.amount_is_net_change);
        assert_eq!(rows[0].info.fee_state, TransactionFeeState::Known);
        assert_eq!(rows[0].info.fee, 10_000);
    }

    #[test]
    fn a_provisional_fee_only_debit_stays_visible() {
        let (mut base, _) = provisional_debit();
        base.account_balance_delta = -10_000;
        base.history.fee = Fee::Known(10_000);

        let rows = classify_history_tx(&base, &ActivitySummary::default(), Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "unknown");
        assert_eq!(info.display_amount, 0);
        assert!(!info.amount_is_net_change);
        assert_eq!(
            (info.fee_state, info.fee),
            (TransactionFeeState::Known, 10_000)
        );
        assert!(info.provisional);
    }

    /// A locally built memo-only send is provisional until scanning settles its
    /// effects, but its zero-value payment is known: it keeps its sent row
    /// instead of becoming a net debit.
    #[test]
    fn a_provisional_zero_value_send_keeps_its_sent_row() {
        let (mut base, _) = provisional_debit();
        base.account_balance_delta = -10_000;
        base.total_received = 90_000;
        base.history.details_complete = true;
        base.history.fee = Fee::Known(10_000);
        let mut summary = ActivitySummary::default();
        summary.sent.output_count = 1;
        summary.sent.has_orchard = true;

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "sent");
        assert_eq!(rows[0].info.display_amount, 0);
        assert_eq!(rows[0].info.display_pool, "shielded");
        assert_eq!(rows[0].info.fee, 10_000);
        assert!(rows[0].info.provisional);
    }

    #[test]
    fn a_complete_debit_with_change_keeps_its_classification() {
        let (mut base, summary) = provisional_debit();
        base.history = HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: true,
            classification: Some(HistoryClassification::Reconstructed),
            provisional: false,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
            inferred_outgoing: None,
        };

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "received");
        assert!(!rows[0].info.provisional);
    }

    /// Private recovery's view of a transparent-only send the account fully
    /// funded: the library reconstructed the exact payment from the recovered
    /// metadata, and only the change is visible.
    #[test]
    fn a_recovered_send_with_change_is_its_exact_payment_not_a_receive() {
        let (mut base, summary) = provisional_debit();
        base.history = HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: false,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: Some(69_990_000),
            inferred_outgoing: None,
        };

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "sent");
        assert_eq!(info.display_amount, 69_990_000);
        assert_eq!(info.display_pool, "transparent");
        assert_eq!(info.fee_state, TransactionFeeState::Known);
        assert_eq!(info.fee, 10_000);
        assert!(!info.details_complete, "the recipients stay unknown");

        // Without change it is still the payment, never an unknown zero.
        base.history.inferred_payment = Some(base.account_balance_delta.unsigned_abs() - 10_000);
        let rows = classify_history_tx(&base, &ActivitySummary::default(), Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "sent");
        assert_eq!(rows[0].info.display_amount, 69_990_000);
    }

    /// The exact payment shown is the library's reconstructed one, not the
    /// balance change less the fee, and the row is final but incomplete.
    #[test]
    fn a_recovered_send_shows_the_reconstructed_payment_itself() {
        let (mut base, summary) = provisional_debit();
        base.history = HistoryCompleteness {
            inferred_outgoing: None,
            has_transparent_outputs: None,
            details_complete: false,
            provisional: false,
            classification: None,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            inferred_payment: Some(42_000_000),
        };

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.display_amount, 42_000_000);
        assert_ne!(
            info.display_amount,
            base.account_balance_delta.unsigned_abs() - 10_000
        );
        assert!(info.is_transparent);
        assert_eq!(info.display_pool, "transparent");
        assert!(!info.provisional);
        assert!(!info.amount_is_net_change);
    }

    /// Once the outputs the account paid are recorded (the transaction's data
    /// arrived after recovery), they show where the value went, even while
    /// the library still reports its reconstruction.
    #[test]
    fn a_recorded_payment_output_replaces_the_reconstructed_payment() {
        let (mut base, mut summary) = provisional_debit();
        base.history = HistoryCompleteness {
            inferred_outgoing: None,
            has_transparent_outputs: None,
            details_complete: false,
            provisional: false,
            classification: None,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            inferred_payment: Some(69_990_000),
        };
        summary.sent.amount = 60_000_000;
        summary.sent.output_count = 1;
        summary.sent.has_orchard = true;

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows[0].info.tx_kind, "sent");
        assert_eq!(rows[0].info.display_amount, 60_000_000);
        assert_eq!(rows[0].info.display_pool, "shielded");
    }

    /// With the account's own fee unknown, the whole fee shown on a recorded
    /// payment and on a folded funding step is the transaction's.
    #[test]
    fn a_whole_fee_stays_the_transactions_on_payments_and_funding_steps() {
        let whole = HistoryCompleteness {
            inferred_outgoing: None,
            has_transparent_outputs: None,
            details_complete: false,
            provisional: false,
            classification: None,
            effects_settled: true,
            fee: Fee::Unknown,
            whole_fee: Some(WHOLE_FEE),
            sole_transparent_funder: true,
            inferred_payment: None,
        };
        let (mut base, mut summary) = provisional_debit();
        base.history = whole;
        summary.sent.amount = 60_000_000;
        summary.sent.output_count = 1;
        summary.sent.has_orchard = true;
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
        assert_eq!(
            (rows[0].info.fee_state, rows[0].info.fee),
            (TransactionFeeState::WholeTransaction, WHOLE_FEE)
        );

        // A retained wallet's TEX send, its funding step matched by creation
        // time: the step's whole fee joins the send's own.
        let account = test_account_uuid();
        let uuid = account.as_bytes().to_vec();
        let created = Some("2026-10-01T10:00:00Z".to_string());
        let (step_txid, send_txid) = (fake_txid(0xF3).to_vec(), fake_txid(0xF4).to_vec());
        let mut step = tx_base_for_history();
        step.txid = step_txid.clone();
        step.transaction_id = 1;
        step.spent_orchard_note = false;
        step.created = created.clone();
        step.account_balance_delta = -(WHOLE_FEE as i64);
        step.total_spent = 1_000_000;
        step.total_received = 1_000_000 - WHOLE_FEE;
        step.attach_history(whole);
        let mut send = tx_base_for_history();
        send.txid = send_txid.clone();
        send.transaction_id = 2;
        send.spent_orchard_note = false;
        send.created = created;
        send.account_balance_delta = -500_000;
        send.total_spent = 500_000;
        send.total_received = 0;
        send.attach_history(HistoryCompleteness {
            fee: Fee::Known(10_000),
            whole_fee: None,
            ..whole
        });
        let output = |txid: &[u8], to_own: bool, scope, value| TxOutput {
            txid: txid.to_vec(),
            output_pool: TRANSPARENT_POOL,
            output_index: 0,
            from_account_uuid: Some(uuid.clone()),
            to_account_uuid: to_own.then(|| uuid.clone()),
            to_address: None,
            sent_to_address: None,
            transparent_receiver_address: None,
            to_key_scope: scope,
            value,
            memo: None,
            note_version: None,
        };
        let outputs = HashMap::from([
            (
                step_txid.clone(),
                vec![output(&step_txid, true, Some(EPHEMERAL_KEY_SCOPE), 500_000)],
            ),
            (
                send_txid.clone(),
                vec![output(&send_txid, false, None, 490_000)],
            ),
        ]);
        let rows = assemble_history(
            &[step, send],
            &outputs,
            &EphemeralSpends::new(),
            &uuid,
            None,
        );
        assert_eq!(rows.len(), 1, "the step folds into the send");
        assert_eq!(
            (rows[0].fee_state, rows[0].fee),
            (TransactionFeeState::WholeTransaction, WHOLE_FEE + 10_000)
        );
    }

    /// A transparent-only self-transfer: the account spent 2 ZEC and every
    /// output (1.2 ZEC and 0.7999 ZEC change) is its own, so its balance
    /// changed by the fee alone.
    fn self_transfer(history: HistoryCompleteness) -> (TxBase, ActivitySummary) {
        let mut base = tx_base_for_history();
        base.spent_orchard_note = false;
        base.fee = Some(10_000);
        base.account_balance_delta = -10_000;
        base.total_spent = 200_000_000;
        base.total_received = 199_990_000;
        base.attach_history(history);
        let mut summary = ActivitySummary::default();
        summary.received.amount = 199_990_000;
        summary.received.output_count = 2;
        summary.received.has_transparent = true;
        (base, summary)
    }

    #[test]
    fn a_recovered_self_transfer_is_its_network_fee() {
        let (base, summary) = self_transfer(HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: false,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            inferred_payment: Some(0),
            inferred_outgoing: None,
        });

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "sent");
        assert_eq!(info.display_amount, 10_000);
        assert_eq!(info.fee, 10_000);
        assert_eq!(info.fee_state, TransactionFeeState::Known);
        assert!(info.amount_is_net_change, "the whole movement is the fee");
        assert_eq!(info.display_pool, "transparent");
        assert!(info.is_transparent);
        assert!(!info.provisional);

        // With the account's own fee unknown, the movement is still its net
        // change, and the fee shown is the whole transaction's.
        let (base, summary) = self_transfer(HistoryCompleteness {
            inferred_outgoing: None,
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: false,
            effects_settled: true,
            fee: Fee::Unknown,
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            inferred_payment: Some(0),
        });
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(
            (info.tx_kind.as_str(), info.display_amount),
            ("sent", 10_000)
        );
        assert_eq!(
            (info.fee_state, info.fee),
            (TransactionFeeState::WholeTransaction, 10_000)
        );
        assert!(info.amount_is_net_change);
    }

    #[test]
    fn a_public_self_transfer_keeps_its_classification() {
        let (base, summary) = self_transfer(HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: false,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
            inferred_outgoing: None,
        });

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "received");
        assert_eq!(info.display_amount, 199_990_000);
        assert!(!info.amount_is_net_change);
    }

    #[test]
    fn an_inexact_self_transfer_is_not_shown_as_its_fee() {
        let received = |history| {
            let (base, summary) = self_transfer(history);
            let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
            assert_eq!(rows.len(), 1);
            assert_eq!(rows[0].info.tx_kind, "received");
            assert!(!rows[0].info.amount_is_net_change);
        };
        let exact = HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: false,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            inferred_payment: Some(0),
            inferred_outgoing: None,
        };
        // No exact payment.
        received(HistoryCompleteness {
            inferred_payment: None,
            inferred_outgoing: None,
            ..exact
        });
        // No exact whole fee.
        received(HistoryCompleteness {
            whole_fee: None,
            ..exact
        });
        // A whole fee that is not the movement.
        received(HistoryCompleteness {
            whole_fee: Some(20_000),
            ..exact
        });
    }

    #[test]
    fn a_recovered_zero_payment_keeps_the_fee_not_a_false_receive() {
        let (mut base, mut summary) = provisional_debit();
        base.account_balance_delta = -10_000;
        base.total_spent = 110_000;
        base.total_received = 100_000;
        base.history = HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: false,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            inferred_payment: Some(0),
            inferred_outgoing: None,
        };
        summary.received.amount = 100_000;
        summary.received.output_count = 1;

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1, "keep the transaction visible");
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "sent");
        assert_eq!(
            info.display_amount, 10_000,
            "returned funds are not a receipt"
        );
        assert!(info.amount_is_net_change, "the movement is the fee alone");
        assert_eq!(info.display_pool, "transparent");
        assert!(info.is_transparent);
        assert_eq!(info.fee_state, TransactionFeeState::Known);
        assert_eq!(info.fee, 10_000);
        assert_eq!(info.account_balance_delta, -10_000);
        assert!(!info.provisional);
        assert!(!info.details_complete, "recipient details remain unknown");

        // An explicitly recorded zero-value output still has its sent row.
        summary.sent.output_count = 1;
        summary.sent.has_transparent = true;
        summary.received = ActivityAmounts::default();
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "sent");
        assert_eq!(rows[0].info.display_amount, 0);
        assert_eq!(rows[0].info.fee, 10_000);
        assert!(!rows[0].info.amount_is_net_change);
    }

    #[test]
    fn only_a_reconstructed_transparent_only_payment_is_inferred() {
        use zcash_client_backend::data_api::transparent_ledger::{
            AccountMovement, MetadataProvenance, TransactionMetadata, TransactionMetadataEvidence,
        };
        use zcash_protocol::value::Zatoshis;

        let evidence = |has_shielded_components| TransactionMetadataEvidence {
            metadata: TransactionMetadata {
                fee: WholeTransactionFee::Exact(Zatoshis::from_u64(10_000).unwrap()),
                transparent_input_count: 1,
                has_shielded_components,
            },
            provenance: vec![MetadataProvenance {
                source: vec![1],
                revision: vec![2],
                lineage: 0,
            }],
        };
        let mut details = TransactionHistoryDetails {
            has_transparent_outputs: None,
            transaction_metadata: Some(evidence(false)),
            whole_fee: None,
            inferred_outgoing: None,
            aggregate_payment: AggregatePayment::Exact(Zatoshis::from_u64(50_000).unwrap()),
            account_movement: AccountMovement {
                received: 40_000,
                spent: 100_000,
                complete: true,
            },
            txid: TxId::from_bytes([1; 32]),
            mined_height: None,
            effects: vec![],
            payment_details: DetailCompleteness::Incomplete,
            fee: FeeState::Known(Zatoshis::from_u64(10_000).unwrap()),
            classification: HistoryClassification::Reconstructed,
            pending_private_details: vec![],
        };
        assert_eq!(
            HistoryCompleteness::of(&details, 1).inferred_payment,
            Some(50_000)
        );

        details.aggregate_payment = AggregatePayment::Exact(Zatoshis::ZERO);
        assert_eq!(
            HistoryCompleteness::of(&details, 1).inferred_payment,
            Some(0)
        );
        details.aggregate_payment = AggregatePayment::Exact(Zatoshis::from_u64(50_000).unwrap());

        // A local record's payment, a provisional one, public evidence, and
        // shielded components are not a reconstructed transparent payment.
        details.classification = HistoryClassification::LocalIntent;
        assert_eq!(HistoryCompleteness::of(&details, 1).inferred_payment, None);
        details.classification = HistoryClassification::Provisional;
        assert_eq!(HistoryCompleteness::of(&details, 1).inferred_payment, None);
        details.classification = HistoryClassification::Reconstructed;
        details.transaction_metadata = None;
        assert_eq!(HistoryCompleteness::of(&details, 1).inferred_payment, None);
        details.transaction_metadata = Some(evidence(true));
        assert_eq!(HistoryCompleteness::of(&details, 1).inferred_payment, None);
        details.transaction_metadata = Some(evidence(false));
        details.aggregate_payment = AggregatePayment::Partial(Zatoshis::from_u64(50_000).unwrap());
        assert_eq!(HistoryCompleteness::of(&details, 1).inferred_payment, None);
    }

    const WHOLE_FEE: u64 = 10_000;

    /// The library's view of a mined transaction known only from private
    /// recovery, as `provisional_debit` shows it: the account spent 1 ZEC of
    /// transparent value and got 0.3 ZEC back, another party funded the
    /// transaction's second input, and the recovered metadata carries `whole`.
    /// The account's fee and the aggregate payment are unknown.
    fn shared_funding_details(whole: WholeTransactionFee) -> TransactionHistoryDetails {
        use zcash_client_backend::data_api::transparent_ledger::{
            AccountMovement, MetadataProvenance, TransactionMetadata, TransactionMetadataEvidence,
        };

        TransactionHistoryDetails {
            has_transparent_outputs: None,
            transaction_metadata: Some(TransactionMetadataEvidence {
                metadata: TransactionMetadata {
                    fee: whole,
                    transparent_input_count: 2,
                    has_shielded_components: false,
                },
                provenance: vec![MetadataProvenance {
                    source: vec![1],
                    revision: vec![2],
                    lineage: 0,
                }],
            }),
            whole_fee: match whole {
                WholeTransactionFee::Exact(fee) => Some(fee),
                _ => None,
            },
            inferred_outgoing: None,
            aggregate_payment: AggregatePayment::Unknown,
            account_movement: AccountMovement {
                received: 30_000_000,
                spent: 100_000_000,
                complete: true,
            },
            txid: TxId::from_bytes([1; 32]),
            mined_height: Some(BlockHeight::from_u32(121)),
            effects: vec![],
            payment_details: DetailCompleteness::Incomplete,
            fee: FeeState::Unknown,
            classification: HistoryClassification::Provisional,
            pending_private_details: vec![],
        }
    }

    fn exact_whole_fee() -> WholeTransactionFee {
        WholeTransactionFee::Exact(zcash_protocol::value::Zatoshis::from_u64(WHOLE_FEE).unwrap())
    }

    #[test]
    fn enhance_shape_changes_only_the_movement_activity_pool() {
        for outputs in [Some(true), Some(false), None] {
            let mut details = shared_funding_details(exact_whole_fee());
            details.has_transparent_outputs = outputs;
            let (mut base, summary) = provisional_debit();
            base.attach_history(HistoryCompleteness::of(&details, 1));
            let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
            let info = &rows[0].info;
            assert_eq!(
                info.activity_pool.as_deref(),
                outputs.filter(|v| *v).map(|_| "transparent")
            );
            assert_eq!(info.display_pool, "unknown");
            assert!(!info.is_transparent);
            assert_eq!(info.display_amount, 70_000_000);
            assert_eq!(info.account_balance_delta, -70_000_000);
            assert_eq!(info.fee, WHOLE_FEE);
            assert!(info.amount_is_net_change);
            assert!(info.provisional);
            assert!(!info.details_complete);
        }
    }

    /// D2: the exact whole fee is shown as the network fee, while the
    /// account's movement stays its known received minus spent. The fee may
    /// have been shared, so none of it is charged to the account.
    #[test]
    fn a_shared_funding_debit_shows_the_whole_fee_without_charging_it() {
        let details = shared_funding_details(exact_whole_fee());
        let history = HistoryCompleteness::of(&details, 1);
        assert_eq!(
            history.fee,
            Fee::Unknown,
            "the account's share stays unknown"
        );
        assert_eq!(history.whole_fee, Some(WHOLE_FEE));
        assert_eq!(history.inferred_payment, None);

        let (mut base, summary) = provisional_debit();
        base.attach_history(history);
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "sent");
        assert_eq!(info.display_pool, "unknown");
        assert_eq!(
            -i128::from(info.display_amount),
            details.account_movement.net(),
            "the movement, with no fee charged"
        );
        assert_eq!(info.account_balance_delta, -70_000_000);
        assert_eq!(
            info.fee_state,
            TransactionFeeState::WholeTransaction,
            "the transaction's fee, not the account's"
        );
        assert_eq!(info.fee, WHOLE_FEE);
        assert!(info.amount_is_net_change, "a net change, not a payment");
        assert!(info.provisional);
        assert!(!info.details_complete);
    }

    /// The library's net reconstruction of a privately recovered mixed shielding
    /// keeps the shielding, shows the whole fee, and charges and infers nothing.
    #[test]
    fn a_net_reconstructed_shielding_is_shown_without_attributing_its_fee() {
        let mut details = shared_funding_details(exact_whole_fee());
        if let Some(evidence) = details.transaction_metadata.as_mut() {
            evidence.metadata.has_shielded_components = true;
        }
        details.payment_details = DetailCompleteness::Complete;
        details.classification = HistoryClassification::NetReconstructed;
        let history = HistoryCompleteness::of(&details, 1);
        assert!(history.justifies_shielding());
        assert_eq!(history.fee, Fee::Unknown);
        assert_eq!(history.whole_fee, Some(WHOLE_FEE));
        assert_eq!(history.inferred_payment, None);
        assert_eq!(history.shown_fee(), Fee::Whole(WHOLE_FEE));
    }

    /// Only a complete, final history justifies a shielding: a net
    /// reconstruction without its payment details, a provisional history with
    /// them, and an unread one do not.
    #[test]
    fn only_complete_final_histories_justify_a_shielding() {
        let mut details = shared_funding_details(exact_whole_fee());
        if let Some(evidence) = details.transaction_metadata.as_mut() {
            evidence.metadata.has_shielded_components = true;
        }
        details.classification = HistoryClassification::NetReconstructed;
        details.payment_details = DetailCompleteness::Incomplete;
        assert!(!HistoryCompleteness::of(&details, 1).justifies_shielding());

        details.payment_details = DetailCompleteness::Complete;
        details.classification = HistoryClassification::Provisional;
        assert!(!HistoryCompleteness::of(&details, 1).justifies_shielding());

        assert!(!HistoryCompleteness::unread(Some(WHOLE_FEE)).justifies_shielding());

        // A net reconstruction never charges the whole fee to the account, and
        // a shielding row built from it shows the receipt, not the movement.
        details.classification = HistoryClassification::NetReconstructed;
        let history = HistoryCompleteness::of(&details, 1);
        let mut base = tx_base_for_history();
        base.spent_orchard_note = false;
        base.fee = None;
        base.is_shielding = true;
        base.account_balance_delta = -(WHOLE_FEE as i64);
        base.total_spent = 100_000_000;
        base.total_received = 100_000_000 - WHOLE_FEE;
        base.attach_history(history);
        assert!(base.is_shielding);
        let mut summary = ActivitySummary::default();
        summary.shielded.amount = base.total_received;
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "shielded");
        assert_eq!(info.display_amount, 100_000_000 - WHOLE_FEE);
        assert_eq!(info.account_balance_delta, -(WHOLE_FEE as i64));
        assert_eq!(info.fee, WHOLE_FEE);
        assert_eq!(info.fee_state, TransactionFeeState::WholeTransaction);
        assert!(!info.amount_is_net_change);
        assert!(!info.provisional);
        assert!(info.details_complete);

        // Without the SQL shielding candidate, a net reconstruction alone
        // makes nothing a shielding.
        let mut base = tx_base_for_history();
        base.is_shielding = false;
        base.attach_history(history);
        assert!(!base.is_shielding);
    }

    #[test]
    fn a_recovered_shielding_shows_the_whole_fee() {
        let mut details = shared_funding_details(exact_whole_fee());
        if let Some(evidence) = details.transaction_metadata.as_mut() {
            evidence.metadata.transparent_input_count = 1;
            evidence.metadata.has_shielded_components = true;
        }
        details.payment_details = DetailCompleteness::Complete;
        details.classification = HistoryClassification::Reconstructed;

        let mut base = tx_base_for_history();
        base.spent_orchard_note = false;
        base.fee = None;
        base.is_shielding = true;
        base.account_balance_delta = -(WHOLE_FEE as i64);
        base.total_spent = 100_000_000;
        base.total_received = 100_000_000 - WHOLE_FEE;
        base.attach_history(HistoryCompleteness::of(&details, 1));
        let mut summary = ActivitySummary::default();
        summary.shielded.amount = base.total_received;

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "shielded");
        assert_eq!(info.display_amount, 100_000_000 - WHOLE_FEE);
        assert_eq!(info.fee_state, TransactionFeeState::WholeTransaction);
        assert_eq!(info.fee, WHOLE_FEE);
        assert!(
            !info.amount_is_net_change,
            "a complete shielding shows what arrived, fee excluded"
        );
    }

    /// Without either transaction metadata or a reconciled whole fee, a
    /// public row has no network fee to show. The account's fee stays unknown.
    #[test]
    fn a_public_debit_without_whole_fee_keeps_its_unknown_fee() {
        let mut details = shared_funding_details(exact_whole_fee());
        details.transaction_metadata = None;
        details.whole_fee = None;
        let (mut base, summary) = provisional_debit();
        let before = classify_history_tx(&base, &summary, Fee::NotApplicable);
        base.attach_history(HistoryCompleteness::of(&details, 1));

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let (info, before) = (&rows[0].info, &before[0].info);
        assert_eq!(info.fee_state, TransactionFeeState::Unknown);
        assert_eq!(info.fee, 0);
        assert_eq!(
            (&info.tx_kind, info.display_amount, &info.display_pool),
            (&before.tx_kind, before.display_amount, &before.display_pool)
        );
        assert!(info.amount_is_net_change, "still the net change");
    }

    #[test]
    fn a_public_debit_shows_the_library_whole_fee_without_metadata() {
        let mut details = shared_funding_details(exact_whole_fee());
        details.transaction_metadata = None;
        let history = HistoryCompleteness::of(&details, 1);
        assert_eq!(
            history.fee,
            Fee::Unknown,
            "the account's share stays unknown"
        );

        let (mut base, summary) = provisional_debit();
        base.attach_history(history);
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "sent");
        assert_eq!(info.display_amount, 70_000_000);
        assert_eq!(info.fee_state, TransactionFeeState::WholeTransaction);
        assert_eq!(info.fee, WHOLE_FEE);
        assert!(
            info.amount_is_net_change,
            "the movement was not reduced by an unknown fee share"
        );
    }

    #[test]
    fn only_an_exact_whole_fee_replaces_an_unknown_account_fee() {
        let shown = |whole, fee| {
            let mut details = shared_funding_details(whole);
            details.fee = fee;
            HistoryCompleteness::of(&details, 1).shown_fee()
        };
        let known = |fee| FeeState::Known(zcash_protocol::value::Zatoshis::from_u64(fee).unwrap());

        assert_eq!(
            shown(exact_whole_fee(), FeeState::Unknown),
            Fee::Whole(WHOLE_FEE)
        );
        // Unknown metadata stays unknown, and coinbase's not-applicable whole
        // fee proves nothing about an account that spent.
        assert_eq!(
            shown(WholeTransactionFee::Unknown, FeeState::Unknown),
            Fee::Unknown
        );
        assert_eq!(
            shown(WholeTransactionFee::NotApplicable, FeeState::Unknown),
            Fee::Unknown
        );
        // An account that provably spent nothing paid no fee, and an account
        // fee the wallet recorded is the one shown.
        assert_eq!(
            shown(exact_whole_fee(), FeeState::NotApplicable),
            Fee::NotApplicable
        );
        assert_eq!(shown(exact_whole_fee(), known(4_000)), Fee::Known(4_000));
    }

    /// A self-shield known only from private recovery, before its payment
    /// details arrive: the account's whole balance change is the network
    /// fee, so the row shows that net change with the whole fee.
    #[test]
    fn a_recovered_self_shield_movement_is_its_whole_fee() {
        let mut details = shared_funding_details(exact_whole_fee());
        if let Some(evidence) = details.transaction_metadata.as_mut() {
            evidence.metadata.transparent_input_count = 1;
            evidence.metadata.has_shielded_components = true;
        }
        details.account_movement.received = 100_000_000 - WHOLE_FEE;

        let mut base = tx_base_for_history();
        base.spent_orchard_note = false;
        base.fee = None;
        base.is_shielding = true;
        base.account_balance_delta = -(WHOLE_FEE as i64);
        base.total_spent = 100_000_000;
        base.total_received = 100_000_000 - WHOLE_FEE;
        base.attach_history(HistoryCompleteness::of(&details, 1));
        assert!(
            !base.is_shielding,
            "incomplete details justify no shielding"
        );

        // The shielded output is internal change, so none of it is visible.
        let rows = classify_history_tx(&base, &ActivitySummary::default(), Fee::NotApplicable);

        assert_eq!(rows.len(), 1);
        let info = &rows[0].info;
        assert_eq!(info.tx_kind, "sent");
        assert_eq!(info.display_amount, WHOLE_FEE);
        assert_eq!(info.fee_state, TransactionFeeState::WholeTransaction);
        assert_eq!(info.fee, WHOLE_FEE);
        assert!(info.amount_is_net_change);
        assert!(info.provisional);
    }

    /// An unmined debit with no visible output shows its net change, as a
    /// provisional one does, whether or not its details are complete, unless
    /// the account's own fee can be subtracted.
    #[test]
    fn an_unmined_movement_debit_is_its_net_change() {
        for details_complete in [false, true] {
            let (mut base, _) = provisional_debit();
            base.mined_height = None;
            base.history = HistoryCompleteness {
                details_complete,
                has_transparent_outputs: None,
                provisional: false,
                effects_settled: true,
                classification: details_complete.then_some(HistoryClassification::Reconstructed),
                fee: Fee::Unknown,
                whole_fee: Some(WHOLE_FEE),
                sole_transparent_funder: true,
                inferred_payment: None,
                inferred_outgoing: None,
            };

            let rows = classify_history_tx(&base, &ActivitySummary::default(), Fee::NotApplicable);

            assert_eq!(rows.len(), 1, "details_complete: {details_complete}");
            let info = &rows[0].info;
            assert_eq!(info.tx_kind, "sent");
            assert_eq!(info.display_amount, 70_000_000);
            assert_eq!(
                (info.fee_state, info.fee),
                (TransactionFeeState::WholeTransaction, WHOLE_FEE)
            );
            assert!(
                info.amount_is_net_change,
                "details_complete: {details_complete}"
            );
        }

        // The account's own fee is subtracted, as public history shows it.
        let (mut base, _) = provisional_debit();
        base.mined_height = None;
        base.history.fee = Fee::Known(10_000);
        base.history.provisional = false;
        let rows = classify_history_tx(&base, &ActivitySummary::default(), Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        assert_eq!(
            (rows[0].info.tx_kind.as_str(), rows[0].info.display_amount),
            ("sent", 69_990_000)
        );
        assert!(!rows[0].info.amount_is_net_change);

        // A debit of just the account's own fee pays nothing unseen yet.
        let (mut base, _) = provisional_debit();
        base.mined_height = None;
        base.account_balance_delta = -10_000;
        base.history.fee = Fee::Known(10_000);
        base.history.provisional = false;
        assert!(
            classify_history_tx(&base, &ActivitySummary::default(), Fee::NotApplicable).is_empty()
        );
    }

    /// Only a row whose amount is the account's whole balance change is a net
    /// change: a visible or reconstructed payment is a payment, whatever fee
    /// is shown, and so is the rest of a debit once its own fee is
    /// subtracted.
    #[test]
    fn only_a_movement_row_is_a_net_change() {
        let whole = HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: true,
            effects_settled: true,
            fee: Fee::Unknown,
            whole_fee: Some(WHOLE_FEE),
            sole_transparent_funder: true,
            inferred_payment: None,
            inferred_outgoing: None,
        };
        let (_, change) = provisional_debit();
        let flags = |history: HistoryCompleteness, summary: &ActivitySummary| {
            let (mut base, _) = provisional_debit();
            base.history = history;
            classify_history_tx(&base, summary, Fee::NotApplicable)
                .iter()
                .map(|row| row.info.amount_is_net_change)
                .collect::<Vec<_>>()
        };

        assert_eq!(flags(whole, &change), [true]);
        assert_eq!(
            flags(
                HistoryCompleteness {
                    fee: Fee::Known(4_000),
                    ..whole
                },
                &change
            ),
            [false],
            "a recorded account fee is subtracted"
        );
        assert_eq!(
            flags(
                HistoryCompleteness {
                    whole_fee: None,
                    ..whole
                },
                &change
            ),
            [true],
            "public evidence"
        );
        assert_eq!(
            flags(
                HistoryCompleteness {
                    provisional: false,
                    fee: Fee::Known(WHOLE_FEE),
                    inferred_payment: Some(69_990_000),
                    inferred_outgoing: None,
                    ..whole
                },
                &change
            ),
            [false],
            "a reconstructed payment"
        );
        let mut paid = change.clone();
        paid.sent.amount = 60_000_000;
        paid.sent.output_count = 1;
        paid.sent.has_orchard = true;
        assert_eq!(flags(whole, &paid), [false, false], "a visible payment");
        // A mined debit with complete details and no visible output is never
        // shown as its movement: its outputs are internal change, with no
        // receipt to stand in for them.
        let complete_mined = flags(
            HistoryCompleteness {
                has_transparent_outputs: None,
                details_complete: true,
                classification: Some(HistoryClassification::Reconstructed),
                provisional: false,
                ..whole
            },
            &ActivitySummary::default(),
        );
        assert!(
            !complete_mined.contains(&true),
            "a mined complete debit: {complete_mined:?}"
        );
    }

    #[test]
    fn local_history_with_incomplete_effects_stays_provisional_until_scanned() {
        use zcash_client_backend::data_api::transparent_ledger::{
            AccountMovement, AggregatePayment, EffectCompleteness, PoolEffect,
        };
        use zcash_protocol::{value::Zatoshis, PoolType};

        // Local construction knows the payment, but scanning still has to
        // discover the receipt to the account's own external shielded address.
        let mut details = TransactionHistoryDetails {
            has_transparent_outputs: None,
            transaction_metadata: None,
            whole_fee: None,
            inferred_outgoing: None,
            aggregate_payment: AggregatePayment::Exact(Zatoshis::from_u64(50_000).unwrap()),
            account_movement: AccountMovement {
                received: 140_000,
                spent: 200_000,
                complete: false,
            },
            txid: TxId::from_bytes([1; 32]),
            mined_height: None,
            effects: vec![PoolEffect {
                pool: PoolType::SAPLING,
                received: Zatoshis::from_u64(140_000).unwrap(),
                spent: Zatoshis::from_u64(200_000).unwrap(),
                completeness: EffectCompleteness::Incomplete,
            }],
            payment_details: DetailCompleteness::Complete,
            fee: FeeState::Known(Zatoshis::from_u64(10_000).unwrap()),
            classification: HistoryClassification::LocalIntent,
            pending_private_details: vec![],
        };
        let pending = HistoryCompleteness::of(&details, 1);
        assert!(pending.details_complete);
        assert!(pending.provisional);
        assert_eq!(pending.fee, Fee::Known(10_000));

        let mut base = tx_base_for_history();
        base.attach_history(pending);
        let mut summary = ActivitySummary::default();
        summary.sent.amount = 50_000;
        summary.sent.output_count = 1;
        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        assert!(rows[0].info.details_complete);
        assert!(rows[0].info.provisional);

        details.effects[0].received = Zatoshis::from_u64(190_000).unwrap();
        details.effects[0].completeness = EffectCompleteness::Complete;
        let scanned = HistoryCompleteness::of(&details, 1);
        assert!(scanned.details_complete);
        assert!(!scanned.provisional);
        assert_eq!(scanned.fee, pending.fee);
    }

    #[test]
    fn history_mapping_keeps_public_discovery_settled_and_provisional_classification() {
        use zcash_client_backend::data_api::transparent_ledger::{
            AccountMovement, AggregatePayment, EffectCompleteness, PoolEffect,
        };
        use zcash_protocol::{value::Zatoshis, PoolType};

        let mut details = TransactionHistoryDetails {
            has_transparent_outputs: None,
            transaction_metadata: None,
            whole_fee: None,
            inferred_outgoing: None,
            aggregate_payment: AggregatePayment::Unknown,
            account_movement: AccountMovement {
                received: 0,
                spent: 0,
                complete: true,
            },
            txid: TxId::from_bytes([1; 32]),
            mined_height: None,
            effects: vec![
                PoolEffect {
                    pool: PoolType::SAPLING,
                    received: Zatoshis::ZERO,
                    spent: Zatoshis::ZERO,
                    completeness: EffectCompleteness::Complete,
                },
                PoolEffect {
                    pool: PoolType::Transparent,
                    received: Zatoshis::ZERO,
                    spent: Zatoshis::ZERO,
                    completeness: EffectCompleteness::PublicDiscovery,
                },
            ],
            payment_details: DetailCompleteness::Complete,
            fee: FeeState::NotApplicable,
            classification: HistoryClassification::Reconstructed,
            pending_private_details: vec![],
        };
        for classification in [
            HistoryClassification::LocalIntent,
            HistoryClassification::Reconstructed,
            HistoryClassification::Provisional,
        ] {
            details.classification = classification;
            for completeness in [
                EffectCompleteness::Complete,
                EffectCompleteness::PublicDiscovery,
                EffectCompleteness::Incomplete,
            ] {
                // The unsettled effect need not be the first one.
                details.effects[1].completeness = completeness;
                let mapped = HistoryCompleteness::of(&details, 1);
                assert_eq!(
                    mapped.provisional,
                    classification == HistoryClassification::Provisional
                        || completeness == EffectCompleteness::Incomplete,
                    "{classification:?} with {completeness:?}"
                );
                assert_eq!(
                    mapped.effects_settled,
                    completeness != EffectCompleteness::Incomplete,
                    "{classification:?} with {completeness:?}"
                );
                assert!(mapped.details_complete);
                assert_eq!(mapped.fee, Fee::NotApplicable);
            }
        }

        // A missing memo alone does not make settled effects provisional.
        details.classification = HistoryClassification::Reconstructed;
        details.effects[1].completeness = EffectCompleteness::PublicDiscovery;
        details.payment_details = DetailCompleteness::Incomplete;
        details.fee = FeeState::Unknown;
        let mapped = HistoryCompleteness::of(&details, 1);
        assert!(!mapped.details_complete);
        assert!(!mapped.provisional);
        assert_eq!(mapped.fee, Fee::Unknown);
    }

    #[test]
    fn shielding_is_inferred_only_from_complete_details() {
        let mut base = tx_base_for_history();
        base.is_shielding = true;
        base.attach_history(HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: false,
            classification: None,
            provisional: true,
            effects_settled: true,
            fee: Fee::Unknown,
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
            inferred_outgoing: None,
        });
        assert!(!base.is_shielding);

        let mut base = tx_base_for_history();
        base.is_shielding = true;
        base.attach_history(HistoryCompleteness {
            has_transparent_outputs: None,
            details_complete: true,
            classification: Some(HistoryClassification::Reconstructed),
            provisional: false,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
            inferred_outgoing: None,
        });
        assert!(base.is_shielding);
    }

    #[test]
    fn an_unknown_fee_is_never_zero() {
        let mut base = tx_base_for_history();
        base.spent_orchard_note = false;
        base.history.fee = Fee::Unknown;
        let mut summary = ActivitySummary::default();
        summary.sent.amount = 5_000_000;
        summary.sent.output_count = 1;
        summary.sent.has_orchard = true;

        let rows = classify_history_tx(&base, &summary, Fee::NotApplicable);
        assert_eq!(rows[0].info.fee_state, TransactionFeeState::Unknown);

        // A funding step whose fee is unknown makes the combined fee unknown.
        base.history.fee = Fee::Known(10_000);
        let rows = classify_history_tx(&base, &summary, Fee::Unknown);
        assert_eq!(rows[0].info.fee_state, TransactionFeeState::Unknown);
        let rows = classify_history_tx(&base, &summary, Fee::Known(5_000));
        assert_eq!(rows[0].info.fee_state, TransactionFeeState::Known);
        assert_eq!(rows[0].info.fee, 15_000);
    }

    #[test]
    fn unread_history_is_provisional() {
        let mut base = tx_base_for_history();
        base.is_shielding = true;
        base.attach_history(HistoryCompleteness::unread(Some(10_000)));
        assert!(base.history.provisional);
        assert!(!base.history.details_complete);
        assert!(!base.is_shielding);
        assert_eq!(base.history.fee, Fee::Known(10_000));
        assert_eq!(HistoryCompleteness::unread(None).fee, Fee::Unknown);
    }

    pub(super) fn fake_raw() -> Vec<u8> {
        vec![0xDE, 0xAD, 0xBE, 0xEF]
    }

    fn transparent_source_raw_tx() -> Vec<u8> {
        hex::decode(
            "0400008085202f8901aee37187e843da597683c26c01457f5fd3b1a038996ef74dc8d60d483aaf395a000000006b483045022100874c70db77ea9e93f75cc83a9e141e17c8eb97588e29fe4e307631fdde4f162a02203493df62d648cd86a1189eaf9bcafc652bc14c5df02519d9e45e25b32aaffb5b012102106a2dcaaac2ae3b24358a03f4264e05db420c5b090399bc23885fa02fef7716ffffffff02764e1900000000001976a914fb451987556f7a19b726966ee6cff917e0bb3bfb88ac560ca400000000001976a9141634f5ff0b8f6603a17570436d6c12a91f4b1fed88ac00000000000000000000000000000000000000",
        )
        .unwrap()
    }

    fn transparent_source_test_address() -> String {
        let pubkey =
            hex::decode("02106a2dcaaac2ae3b24358a03f4264e05db420c5b090399bc23885fa02fef7716")
                .unwrap();
        let address = TransparentAddress::PublicKeyHash(transparent::util::hash160::hash(&pubkey));
        zcash_keys::encoding::encode_transparent_address_p(&WalletNetwork::Test, &address)
    }

    fn test_account_uuid() -> uuid::Uuid {
        uuid::Uuid::from_u128(0x7e2b16db08384ddba8026fd48b9e0d02)
    }

    fn second_test_account_uuid() -> uuid::Uuid {
        uuid::Uuid::from_u128(0x3eb4ded306b74bf2a5393f1b78d792a6)
    }

    #[test]
    fn history_exposes_activity_pools_without_changing_legacy_grouping() {
        let cases: &[(&[i64], &str, &str)] = &[
            (&[TRANSPARENT_POOL], "transparent", "transparent"),
            (&[SAPLING_POOL], "sapling", "shielded"),
            (&[ORCHARD_POOL], "orchard", "shielded"),
            (&[IRONWOOD_POOL], "ironwood", "ironwood"),
            (&[SAPLING_POOL, ORCHARD_POOL], "mixed", "shielded"),
            (&[ORCHARD_POOL, IRONWOOD_POOL], "mixed", "mixed"),
            (&[TRANSPARENT_POOL, SAPLING_POOL], "mixed", "mixed"),
            (&[TRANSPARENT_POOL, IRONWOOD_POOL], "mixed", "mixed"),
        ];
        for &(pools, activity_pool, legacy_pool) in cases {
            let db = fresh_history_db();
            let account = test_account_uuid();
            let txid = fake_txid(0xB0);
            let amount = pools.len() as i64 * 100_000;
            insert_history_tx(
                &db,
                account,
                &txid,
                Some(1_000_000),
                1,
                None,
                0,
                amount,
                amount,
                false,
                None,
            );
            for &pool in pools {
                insert_output_with_address(
                    &db,
                    &txid,
                    pool,
                    Some(account),
                    Some(account),
                    100_000,
                    false,
                    Some("self-address"),
                    Some(0),
                );
            }
            let rows = history_from_fixture(
                db.path().to_str().unwrap(),
                WalletNetwork::Test,
                None,
                &account.to_string(),
            )
            .unwrap();
            assert_eq!(rows.len(), 2, "pools: {pools:?}");
            assert_eq!(rows[0].tx_kind, "sent");
            assert_eq!(rows[1].tx_kind, "received");
            for row in rows {
                assert_eq!(row.activity_pool.as_deref(), Some(activity_pool));
                assert_eq!(row.display_pool, legacy_pool);
                assert_eq!(row.display_amount, amount as u64);
            }
        }
    }

    #[test]
    fn history_unknown_pool_fallback_has_no_exact_activity_pool() {
        let mut base = tx_base_for_history();
        base.total_spent = 0;
        base.account_balance_delta = 50_000;
        let rows = classify_history_tx(&base, &ActivitySummary::default(), Fee::NotApplicable);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].info.tx_kind, "received");
        assert_eq!(rows[0].info.display_pool, "unknown");
        assert_eq!(rows[0].info.activity_pool, None);
    }

    #[test]
    fn received_transparent_output_detail_returns_bare_t_address() {
        // The wallet stores the account UA in `to_address` for a received
        // transparent output; `transparent_receiver_address` holds the bare
        // t-address recovered from the addresses table. The received detail
        // must surface the t-address, not the UA — otherwise the desktop
        // receipt mislabels a transparent->transparent receive as shielded
        // (crimson shield + u1 address). Regression for that bug.
        let t_addr = transparent_source_test_address();
        let ua = "u1qexampleunifiedaddressexampleunifiedaddress".to_string();

        let transparent_received = TxOutput {
            txid: vec![0u8; 32],
            output_pool: 0,
            output_index: 0,
            from_account_uuid: None,
            to_account_uuid: Some(test_account_uuid().as_bytes().to_vec()),
            to_address: Some(ua.clone()),
            sent_to_address: None,
            transparent_receiver_address: Some(t_addr.clone()),
            to_key_scope: Some(0),
            value: 1_000_000,
            memo: None,
            note_version: None,
        };
        assert_eq!(
            transparent_received.detail_address("received"),
            Some(t_addr.clone()),
        );
        assert_eq!(
            transparent_received.detail_address("receiving"),
            Some(t_addr),
        );

        // Shielded receives (pool 2) still surface their stored address.
        let shielded_received = TxOutput {
            txid: vec![0u8; 32],
            output_pool: 2,
            output_index: 0,
            from_account_uuid: None,
            to_account_uuid: Some(test_account_uuid().as_bytes().to_vec()),
            to_address: Some(ua.clone()),
            sent_to_address: None,
            transparent_receiver_address: None,
            to_key_scope: Some(0),
            value: 1_000_000,
            memo: None,
            note_version: None,
        };
        assert_eq!(shielded_received.detail_address("received"), Some(ua));
    }

    fn fresh_history_db() -> NamedTempFile {
        let file = NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE accounts (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 uuid BLOB NOT NULL UNIQUE,
                 birthday_height INTEGER NOT NULL DEFAULT 0
             );
             CREATE TABLE addresses (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 account_id INTEGER NOT NULL,
                 key_scope INTEGER NOT NULL,
                 address TEXT NOT NULL,
                 cached_transparent_receiver_address TEXT
             );
             CREATE TABLE v_transactions (
                 account_uuid BLOB NOT NULL,
                 txid BLOB NOT NULL,
                 raw BLOB,
                 mined_height INTEGER,
                 expired_unmined INTEGER NOT NULL,
                 account_balance_delta INTEGER NOT NULL,
                 fee_paid INTEGER,
                 block_time INTEGER,
                 total_spent INTEGER,
                 total_received INTEGER,
                 is_shielding INTEGER,
                 expiry_height INTEGER,
                 tx_index INTEGER,
                 spent_note_count INTEGER
             );
             CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY AUTOINCREMENT,
                 txid BLOB NOT NULL UNIQUE,
                 created TEXT
             );
             CREATE TABLE sent_notes (
                 transaction_id INTEGER NOT NULL,
                 output_pool INTEGER NOT NULL,
                 output_index INTEGER NOT NULL,
                 from_account_id INTEGER NOT NULL,
                 to_account_id INTEGER,
                 to_address TEXT,
                 value INTEGER NOT NULL,
                 memo BLOB
             );
             CREATE TABLE orchard_received_notes (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 transaction_id INTEGER NOT NULL,
                 action_index INTEGER NOT NULL,
                 note_version INTEGER NOT NULL
             );
             CREATE TABLE orchard_received_note_spends (
                 orchard_received_note_id INTEGER NOT NULL,
                 transaction_id INTEGER NOT NULL
             );
             CREATE TABLE transparent_received_outputs (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 transaction_id INTEGER NOT NULL,
                 account_id INTEGER NOT NULL,
                 address_id INTEGER NOT NULL
             );
             CREATE TABLE transparent_received_output_spends (
                 transparent_received_output_id INTEGER NOT NULL,
                 transaction_id INTEGER NOT NULL
             );
             CREATE TABLE v_tx_outputs (
                 transaction_id INTEGER NOT NULL,
                 txid BLOB NOT NULL,
                 output_pool INTEGER NOT NULL,
                 output_index INTEGER NOT NULL,
                 from_account_uuid BLOB,
                 to_account_uuid BLOB,
                 to_address TEXT,
                 value INTEGER NOT NULL,
                 is_change INTEGER NOT NULL,
                 memo BLOB
             );",
        )
        .unwrap();
        file
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_history_tx(
        db: &NamedTempFile,
        account: uuid::Uuid,
        txid: &[u8],
        mined_height: Option<i64>,
        tx_index: i64,
        expiry_height: Option<i64>,
        account_balance_delta: i64,
        total_spent: i64,
        total_received: i64,
        is_shielding: bool,
        created: Option<&str>,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        ensure_account_row(&conn, account);
        conn.execute(
            "INSERT INTO transactions (txid, created) VALUES (?1, ?2)",
            rusqlite::params![txid, created],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO v_transactions (
                 account_uuid, txid, raw, mined_height, expired_unmined,
                 account_balance_delta, fee_paid, block_time, total_spent,
                 total_received, is_shielding, expiry_height, tx_index
             ) VALUES (?1, ?2, NULL, ?3, 0, ?4, 0, 0, ?5, ?6, ?7, ?8, ?9)",
            rusqlite::params![
                account.as_bytes().as_slice(),
                txid,
                mined_height,
                account_balance_delta,
                total_spent,
                total_received,
                is_shielding,
                expiry_height,
                tx_index,
            ],
        )
        .unwrap();
    }

    fn set_history_tx_raw(db: &NamedTempFile, account: uuid::Uuid, txid: &[u8], raw: &[u8]) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET raw = ?1 WHERE account_uuid = ?2 AND txid = ?3",
            rusqlite::params![raw, account.as_bytes().as_slice(), txid],
        )
        .unwrap();
    }

    fn ensure_account_row(conn: &rusqlite::Connection, account: uuid::Uuid) -> i64 {
        conn.execute(
            "INSERT OR IGNORE INTO accounts (uuid) VALUES (?1)",
            rusqlite::params![account.as_bytes().as_slice()],
        )
        .unwrap();
        conn.query_row(
            "SELECT id FROM accounts WHERE uuid = ?1",
            rusqlite::params![account.as_bytes().as_slice()],
            |row| row.get(0),
        )
        .unwrap()
    }

    fn insert_output(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        from_account: Option<uuid::Uuid>,
        to_account: Option<uuid::Uuid>,
        value: i64,
        is_change: bool,
    ) -> i64 {
        insert_output_with_address(
            db,
            txid,
            output_pool,
            from_account,
            to_account,
            value,
            is_change,
            None,
            None,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_output_with_address(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        from_account: Option<uuid::Uuid>,
        to_account: Option<uuid::Uuid>,
        value: i64,
        is_change: bool,
        to_address: Option<&str>,
        to_key_scope: Option<i64>,
    ) -> i64 {
        insert_output_with_address_and_memo(
            db,
            txid,
            output_pool,
            from_account,
            to_account,
            value,
            is_change,
            to_address,
            to_key_scope,
            None,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_output_with_address_and_memo(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        from_account: Option<uuid::Uuid>,
        to_account: Option<uuid::Uuid>,
        value: i64,
        is_change: bool,
        to_address: Option<&str>,
        to_key_scope: Option<i64>,
        memo: Option<&[u8]>,
    ) -> i64 {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        if let Some(account) = from_account {
            ensure_account_row(&conn, account);
        }
        if let Some(account) = to_account {
            let account_id = ensure_account_row(&conn, account);
            if let (Some(address), Some(key_scope)) = (to_address, to_key_scope) {
                conn.execute(
                    "INSERT INTO addresses (
                         account_id, key_scope, address, cached_transparent_receiver_address
                     ) VALUES (?1, ?2, ?3, ?3)",
                    rusqlite::params![account_id, key_scope, address],
                )
                .unwrap();
            }
        }
        let transaction_id = conn
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                rusqlite::params![txid],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        let output_index = conn
            .query_row(
                "SELECT COALESCE(MAX(output_index) + 1, 0)
                 FROM v_tx_outputs
                 WHERE txid = ?1 AND output_pool = ?2",
                rusqlite::params![txid, output_pool],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        let from_bytes = from_account.map(|uuid| uuid.as_bytes().to_vec());
        let to_bytes = to_account.map(|uuid| uuid.as_bytes().to_vec());
        conn.execute(
            "INSERT INTO v_tx_outputs (
                 transaction_id, txid, output_pool, output_index, from_account_uuid,
                 to_account_uuid, to_address, value, is_change, memo
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            rusqlite::params![
                transaction_id,
                txid,
                output_pool,
                output_index,
                from_bytes,
                to_bytes,
                to_address,
                value,
                is_change,
                memo,
            ],
        )
        .unwrap();
        output_index
    }

    fn insert_received_note_version(
        db: &NamedTempFile,
        txid: &[u8],
        output_index: i64,
        note_version: i64,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let transaction_id = conn
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                rusqlite::params![txid],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes (
                 transaction_id, action_index, note_version
             ) VALUES (?1, ?2, ?3)",
            rusqlite::params![transaction_id, output_index, note_version],
        )
        .unwrap();
    }

    fn insert_spent_note_version(db: &NamedTempFile, txid: &[u8], note_version: i64) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let transaction_id = conn
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                rusqlite::params![txid],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        conn.execute(
            "INSERT INTO transactions (txid) VALUES (randomblob(32))",
            [],
        )
        .unwrap();
        let source_transaction_id = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO orchard_received_notes (
                 transaction_id, action_index, note_version
             ) VALUES (?1, 0, ?2)",
            rusqlite::params![source_transaction_id, note_version],
        )
        .unwrap();
        let note_id = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO orchard_received_note_spends (
                 orchard_received_note_id, transaction_id
             ) VALUES (?1, ?2)",
            rusqlite::params![note_id, transaction_id],
        )
        .unwrap();
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_sent_note(
        db: &NamedTempFile,
        txid: &[u8],
        output_pool: i64,
        output_index: i64,
        from_account: uuid::Uuid,
        to_account: Option<uuid::Uuid>,
        to_address: Option<&str>,
        value: i64,
        memo: Option<&[u8]>,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let transaction_id = conn
            .query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                rusqlite::params![txid],
                |row| row.get::<_, i64>(0),
            )
            .unwrap();
        let from_account_id = ensure_account_row(&conn, from_account);
        let to_account_id = to_account.map(|account| ensure_account_row(&conn, account));
        conn.execute(
            "INSERT INTO sent_notes (
                 transaction_id, output_pool, output_index, from_account_id,
                 to_account_id, to_address, value, memo
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            rusqlite::params![
                transaction_id,
                output_pool,
                output_index,
                from_account_id,
                to_account_id,
                to_address,
                value,
                memo,
            ],
        )
        .unwrap();
    }

    fn set_cached_transparent_receiver_address(
        db: &NamedTempFile,
        account: uuid::Uuid,
        address: &str,
        transparent_address: &str,
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let account_id = ensure_account_row(&conn, account);
        let changed = conn
            .execute(
                "UPDATE addresses
                 SET cached_transparent_receiver_address = ?3
                 WHERE account_id = ?1 AND address = ?2",
                rusqlite::params![account_id, address, transparent_address],
            )
            .unwrap();
        assert_eq!(changed, 1);
    }

    #[test]
    fn previous_transaction_count_for_address_counts_distinct_sent_transactions() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let target = "u1contactaddress";
        let other_target = "u1otheraddress";

        let txid_a = fake_txid(0xC1);
        insert_history_tx(
            &db,
            account,
            &txid_a,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -5_000_000,
            5_000_000,
            0,
            false,
            Some("2026-04-28T14:03:00Z"),
        );
        let output_index = insert_output_with_address(
            &db,
            &txid_a,
            3,
            Some(account),
            None,
            5_000_000,
            false,
            Some(target),
            None,
        );
        insert_sent_note(
            &db,
            &txid_a,
            3,
            output_index,
            account,
            None,
            Some(target),
            5_000_000,
            None,
        );

        let txid_b = fake_txid(0xC2);
        insert_history_tx(
            &db,
            account,
            &txid_b,
            Some(1_000_001),
            2,
            Some(1_000_101),
            -7_000_000,
            7_000_000,
            0,
            false,
            Some("2026-04-28T14:04:00Z"),
        );
        let output_index = insert_output_with_address(
            &db,
            &txid_b,
            3,
            Some(account),
            None,
            7_000_000,
            false,
            Some(target),
            None,
        );
        insert_sent_note(
            &db,
            &txid_b,
            3,
            output_index,
            account,
            None,
            Some(target),
            7_000_000,
            None,
        );

        let txid_c = fake_txid(0xC3);
        insert_history_tx(
            &db,
            account,
            &txid_c,
            Some(1_000_002),
            3,
            Some(1_000_102),
            -9_000_000,
            9_000_000,
            0,
            false,
            Some("2026-04-28T14:05:00Z"),
        );
        let output_index = insert_output_with_address(
            &db,
            &txid_c,
            3,
            Some(account),
            None,
            9_000_000,
            false,
            Some(other_target),
            None,
        );
        insert_sent_note(
            &db,
            &txid_c,
            3,
            output_index,
            account,
            None,
            Some(other_target),
            9_000_000,
            None,
        );

        let txid_d = fake_txid(0xC4);
        insert_history_tx(
            &db,
            other_account,
            &txid_d,
            Some(1_000_003),
            4,
            Some(1_000_103),
            -11_000_000,
            11_000_000,
            0,
            false,
            Some("2026-04-28T14:06:00Z"),
        );
        let output_index = insert_output_with_address(
            &db,
            &txid_d,
            3,
            Some(other_account),
            None,
            11_000_000,
            false,
            Some(target),
            None,
        );
        insert_sent_note(
            &db,
            &txid_d,
            3,
            output_index,
            other_account,
            None,
            Some(target),
            11_000_000,
            None,
        );

        let got = get_previous_transaction_count_for_address(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &format!(" {target} "),
        )
        .unwrap();

        assert_eq!(got, 2);
    }

    fn mark_expired_unmined(db: &NamedTempFile, txid: &[u8]) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET expired_unmined = 1 WHERE txid = ?1",
            rusqlite::params![txid],
        )
        .unwrap();
    }

    fn clear_tx_index(db: &NamedTempFile, txid: &[u8]) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET tx_index = NULL WHERE txid = ?1",
            rusqlite::params![txid],
        )
        .unwrap();
    }

    fn set_history_fee(db: &NamedTempFile, txid: &[u8], fee_paid: i64) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET fee_paid = ?2 WHERE txid = ?1",
            rusqlite::params![txid, fee_paid],
        )
        .unwrap();
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_zip320_history_pair(
        db: &NamedTempFile,
        account: uuid::Uuid,
        funding_step: &[u8],
        external_send: &[u8],
        created: &str,
        funding_tx_index: i64,
        external_tx_index: i64,
        expiry_height: i64,
        funding_amount: i64,
        funding_fee: i64,
        external_fee: i64,
    ) {
        let send_amount = funding_amount - external_fee;

        insert_history_tx(
            db,
            account,
            funding_step,
            None,
            funding_tx_index,
            Some(expiry_height),
            -funding_fee,
            funding_amount + funding_fee,
            funding_amount,
            false,
            Some(created),
        );
        set_history_fee(db, funding_step, funding_fee);
        insert_output_with_address(
            db,
            funding_step,
            0,
            Some(account),
            Some(account),
            funding_amount,
            false,
            Some("t-ephemeral"),
            Some(2),
        );

        insert_history_tx(
            db,
            account,
            external_send,
            None,
            external_tx_index,
            Some(expiry_height),
            -funding_amount,
            funding_amount,
            0,
            false,
            Some(created),
        );
        set_history_fee(db, external_send, external_fee);
        insert_output(
            db,
            external_send,
            0,
            Some(account),
            None,
            send_amount,
            false,
        );
    }

    fn set_account_birthday(db: &NamedTempFile, account: uuid::Uuid, birthday_height: i64) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        ensure_account_row(&conn, account);
        conn.execute(
            "UPDATE accounts SET birthday_height = ?2 WHERE uuid = ?1",
            rusqlite::params![account.as_bytes().as_slice(), birthday_height],
        )
        .unwrap();
    }

    #[test]
    fn export_birthday_anchor_uses_oldest_mined_tx_for_account() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let newer = fake_txid(0x71);
        let older_late_index = fake_txid(0x72);
        let older_early_index = fake_txid(0x73);
        let other_older = fake_txid(0x74);
        let pending = fake_txid(0x75);

        insert_history_tx(
            &db,
            account,
            &newer,
            Some(300),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            account,
            &older_late_index,
            Some(200),
            5,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            account,
            &older_early_index,
            Some(200),
            1,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            other_account,
            &other_older,
            Some(100),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(400),
            1,
            0,
            1,
            false,
            None,
        );

        let got =
            get_oldest_mined_transaction_anchor(db.path().to_str().unwrap(), &account.to_string())
                .unwrap()
                .unwrap();

        assert_eq!(got.block_height, 200);
    }

    #[test]
    fn export_birthday_anchor_returns_none_without_mined_tx() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let pending = fake_txid(0x81);
        let other_mined = fake_txid(0x82);

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(400),
            1,
            0,
            1,
            false,
            None,
        );
        insert_history_tx(
            &db,
            other_account,
            &other_mined,
            Some(100),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        let got =
            get_oldest_mined_transaction_anchor(db.path().to_str().unwrap(), &account.to_string())
                .unwrap();

        assert!(got.is_none());
    }

    #[test]
    fn export_birthday_anchor_falls_back_to_account_birthday_without_mined_tx() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let pending = fake_txid(0x91);
        let other_mined = fake_txid(0x92);

        set_account_birthday(&db, account, 333_100);
        set_account_birthday(&db, other_account, 111_100);
        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(400),
            1,
            0,
            1,
            false,
            None,
        );
        insert_history_tx(
            &db,
            other_account,
            &other_mined,
            Some(100),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );

        let got =
            get_export_birthday_anchor(db.path().to_str().unwrap(), &account.to_string()).unwrap();

        assert_eq!(got.block_height, 333_100);
    }

    fn add_blocks_table(db: &NamedTempFile, rows: &[(u32, u32)]) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "CREATE TABLE blocks (height INTEGER PRIMARY KEY, time INTEGER)",
            [],
        )
        .unwrap();
        for (height, time) in rows {
            conn.execute(
                "INSERT INTO blocks (height, time) VALUES (?1, ?2)",
                rusqlite::params![height, time],
            )
            .unwrap();
        }
    }

    #[test]
    fn local_block_time_uses_the_scanned_block_exactly() {
        let db = fresh_history_db();
        add_blocks_table(&db, &[(2_000_000, 1_677_600_000)]);

        for network in [WalletNetwork::Main, WalletNetwork::Test] {
            let got =
                get_local_block_time(db.path().to_str().unwrap(), network, 2_000_000).unwrap();
            assert_eq!(got, Some(1_677_600_000));
        }
    }

    #[test]
    fn local_block_time_answers_for_the_requested_height_only() {
        // The export anchor would now resolve to the mined transaction at
        // 2,500,000, but the caller asks about the height it already shows.
        let db = fresh_history_db();
        let account = test_account_uuid();
        set_account_birthday(&db, account, 2_000_000);
        insert_history_tx(
            &db,
            account,
            &fake_txid(0x93),
            Some(2_500_000),
            0,
            None,
            1,
            0,
            1,
            false,
            None,
        );
        add_blocks_table(
            &db,
            &[(2_000_000, 1_677_600_000), (2_500_000, 1_715_296_781)],
        );

        let got = get_local_block_time(db.path().to_str().unwrap(), WalletNetwork::Main, 2_000_000)
            .unwrap();
        assert_eq!(got, Some(1_677_600_000));
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn local_block_time_estimates_unscanned_mainnet_blocks() {
        let db = fresh_history_db();
        add_blocks_table(&db, &[]);
        let path = db.path().to_str().unwrap();

        let got = get_local_block_time(path, WalletNetwork::Main, 2_000_000)
            .unwrap()
            .unwrap();
        // Mainnet block 2,000,000 was mined at 1,677,602,242.
        assert!(got.abs_diff(1_677_602_242) <= 6 * 60 * 60, "{got}");

        assert_eq!(
            get_local_block_time(path, WalletNetwork::Test, 2_000_000).unwrap(),
            None
        );
    }

    #[cfg(ironwood_masquerade)]
    #[test]
    fn local_block_time_never_estimates_masquerade_chain_blocks() {
        let db = fresh_history_db();
        add_blocks_table(&db, &[(1_000, 1_790_000_000)]);
        let path = db.path().to_str().unwrap();

        // Unscanned heights fall back to the chain's own endpoint.
        assert_eq!(
            get_local_block_time(path, WalletNetwork::Main, 400).unwrap(),
            None
        );
        // Scanned heights still answer exactly.
        assert_eq!(
            get_local_block_time(path, WalletNetwork::Main, 1_000).unwrap(),
            Some(1_790_000_000)
        );
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn local_block_time_anchors_past_the_table_on_the_highest_scanned_block() {
        let db = fresh_history_db();
        add_blocks_table(&db, &[(900_000_100, 4_000_000_000)]);

        let got = get_local_block_time(
            db.path().to_str().unwrap(),
            WalletNetwork::Main,
            900_000_000,
        )
        .unwrap()
        .unwrap();
        assert!(got < 4_000_000_000);
        assert!(got > 3_999_000_000, "{got}");
    }

    /// Read `TxBase` from a synthetic `v_transactions` table.
    ///
    /// Synthetic classification fixtures do not have the library's note schema.
    /// Real-schema tests separately compare the library projection with this view.
    fn read_history_bases_via_v_transactions(
        conn: &rusqlite::Connection,
        account_uuid: &[u8],
    ) -> Result<Vec<TxBase>, String> {
        let mut stmt = conn
            .prepare(
                r#"
            SELECT
                vt.txid,
                COALESCE(tx.id_tx, -1) AS transaction_id,
                vt.mined_height,
                COALESCE(vt.expired_unmined, 0) AS expired_unmined,
                vt.account_balance_delta,
                vt.fee_paid AS fee_paid,
                COALESCE(vt.block_time, 0) AS block_time,
                COALESCE(vt.total_spent, 0) AS total_spent,
                COALESCE(vt.total_received, 0) AS total_received,
                COALESCE(vt.is_shielding, 0) AS is_shielding,
                vt.expiry_height,
                COALESCE(vt.tx_index, -1) AS tx_index,
                tx.created,
                CAST(COALESCE(strftime('%s', tx.created), 0) AS INTEGER) AS created_time,
                EXISTS (
                    SELECT 1
                    FROM transactions spent_tx
                    JOIN orchard_received_note_spends spent
                        ON spent.transaction_id = spent_tx.id_tx
                    JOIN orchard_received_notes spent_note
                        ON spent_note.id = spent.orchard_received_note_id
                    WHERE spent_tx.txid = vt.txid
                      AND spent_note.note_version = ?2
                ) AS spent_orchard_note,
                COALESCE(vt.spent_note_count, 0) AS spent_note_count
            FROM v_transactions vt
            LEFT JOIN transactions tx ON tx.txid = vt.txid
            WHERE vt.account_uuid = ?1
            "#,
            )
            .map_err(|e| format!("SQL error: {e}"))?;

        let rows = stmt
            .query_map(
                rusqlite::params![account_uuid, ORCHARD_NOTE_VERSION],
                |row| {
                    let fee = row.get::<_, Option<i64>>(5)?.map(i64::unsigned_abs);
                    Ok(TxBase {
                        txid: row.get(0)?,
                        transaction_id: row.get(1)?,
                        mined_height: row.get(2)?,
                        expired_unmined: row.get(3)?,
                        account_balance_delta: row.get(4)?,
                        fee,
                        block_time: row.get::<_, i64>(6)?.unsigned_abs(),
                        total_spent: row.get::<_, i64>(7)?.unsigned_abs(),
                        total_received: row.get::<_, i64>(8)?.unsigned_abs(),
                        is_shielding: row.get(9)?,
                        expiry_height: row.get(10)?,
                        tx_index: row.get(11)?,
                        created: row.get(12)?,
                        created_time: row.get::<_, i64>(13)?.unsigned_abs(),
                        spent_orchard_note: row.get(14)?,
                        spent_note_count: row.get(15)?,
                        history: HistoryCompleteness::unread(fee),
                    })
                },
            )
            .map_err(|e| format!("Query error: {e}"))?;

        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Row error: {e}"))
    }

    /// `get_transaction_detail` over a synthetic fixture, which has no ledger
    /// facts: the transaction is treated as completely known.
    fn detail_from_fixture(
        db_path: &str,
        network: WalletNetwork,
        account_uuid: &str,
        txid_hex: &str,
        tx_kind: &str,
    ) -> Result<TransactionDetail, String> {
        let account = parse_account_uuid(account_uuid)?;
        let conn = open_readonly_conn(db_path)?;
        let read_tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("SQL error: {e}"))?;
        read_transaction_detail(&read_tx, network, account, txid_hex, tx_kind, |base| {
            base.attach_history(HistoryCompleteness::complete_for(base));
            Ok(())
        })
    }

    /// `get_transaction_history` with its bases read from the synthetic
    /// `v_transactions` fixture instead of the library summary API.
    ///
    /// Everything else is production code: the real
    /// `read_history_outputs` and the real `assemble_history`. The fixture has
    /// no ledger facts, so every transaction is treated as completely known,
    /// as for a wallet that built or fully enhanced it.
    fn history_from_fixture(
        db_path: &str,
        _network: WalletNetwork,
        limit: Option<u32>,
        account_uuid: &str,
    ) -> Result<Vec<TransactionInfo>, String> {
        let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| format!("Invalid UUID: {e}"))?;
        let uuid_bytes = uuid.as_bytes().to_vec();

        let conn = open_readonly_conn(db_path)?;
        let read_tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("SQL error: {e}"))?;
        let mut bases = read_history_bases_via_v_transactions(&read_tx, &uuid_bytes)?;
        if bases.is_empty() {
            return Ok(Vec::new());
        }
        for base in &mut bases {
            base.attach_history(HistoryCompleteness::complete_for(base));
        }
        let outputs_by_txid = read_history_outputs(
            &read_tx,
            &uuid_bytes,
            bases.iter().map(|base| base.txid.as_slice()),
        )?;
        let ephemeral_spends = read_ephemeral_spends(
            &read_tx,
            &uuid_bytes,
            bases.iter().map(|base| base.txid.as_slice()),
        )?;
        drop(read_tx);

        Ok(assemble_history(
            &bases,
            &outputs_by_txid,
            &ephemeral_spends,
            &uuid_bytes,
            limit,
        ))
    }

    /// Pin the batched balance read to the single-account one.
    ///
    /// `get_wallet_balances` exists so a caller wanting several accounts
    /// pays for one `get_wallet_summary` instead of one per account. It
    /// must return exactly what looping over `get_wallet_balance` would,
    /// including order and the unavailable-account fallbacks.
    ///
    /// Needs a real wallet DB, same as the history equivalence check:
    ///
    /// ```text
    /// VIZOR_HISTORY_EQUIV_DB=/path/to/zcash_wallet.db \
    ///   cargo test --lib wallet_balances_batch_matches_single -- --ignored --nocapture
    /// ```
    #[test]
    #[ignore = "requires a librustzcash-built wallet DB via VIZOR_HISTORY_EQUIV_DB"]
    fn wallet_balances_batch_matches_single() {
        let db_path = std::env::var("VIZOR_HISTORY_EQUIV_DB")
            .expect("set VIZOR_HISTORY_EQUIV_DB to a librustzcash-built wallet DB");
        let conn = open_readonly_conn(&db_path).unwrap();
        let uuids: Vec<String> = conn
            .prepare("SELECT uuid FROM accounts ORDER BY id")
            .unwrap()
            .query_map([], |row| row.get::<_, Vec<u8>>(0))
            .unwrap()
            .map(|raw| uuid::Uuid::from_slice(&raw.unwrap()).unwrap().to_string())
            .collect();
        assert!(!uuids.is_empty(), "{db_path} has no accounts");
        drop(conn);

        let network = WalletNetwork::Main;
        let refs: Vec<&str> = uuids.iter().map(String::as_str).collect();
        let batched = get_wallet_balances(&db_path, network, &refs).unwrap();
        assert_eq!(
            batched.len(),
            uuids.len(),
            "batch must return one entry per requested account"
        );

        for (uuid, batch_entry) in uuids.iter().zip(batched.iter()) {
            let single = get_wallet_balance(&db_path, network, uuid).unwrap();
            assert_eq!(
                batch_entry, &single,
                "account {uuid}: batched balance diverged from get_wallet_balance"
            );
        }

        // An account absent from the summary must degrade per entry, not
        // fail the batch, so one stale uuid cannot blank a whole sweep.
        let missing = uuid::Uuid::nil().to_string();
        let mut with_missing: Vec<&str> = refs.clone();
        with_missing.push(&missing);
        let mixed = get_wallet_balances(&db_path, network, &with_missing).unwrap();
        assert_eq!(mixed.len(), with_missing.len());
        assert_eq!(
            mixed.last().unwrap().availability,
            WalletBalanceAvailability::AccountUnavailable
        );
        assert_eq!(
            &mixed[..refs.len()],
            &batched[..],
            "a missing account must not disturb the others"
        );
        println!("compared {} accounts", uuids.len());
    }

    /// Additional equivalence coverage on a synced wallet, beyond the automatic
    /// migrated-schema fixtures in `history_summary_tests`.
    ///
    /// It needs a database built by librustzcash itself. Point it at a
    /// regtest wallet (`./run-regtest-rust-tests.sh` leaves one behind)
    /// or any real wallet DB:
    ///
    /// ```text
    /// VIZOR_HISTORY_EQUIV_DB=/path/to/zcash_wallet.db \
    ///   cargo test --lib history_bases_match_v_transactions -- --ignored --nocapture
    /// ```
    #[test]
    #[ignore = "requires a librustzcash-built wallet DB via VIZOR_HISTORY_EQUIV_DB"]
    fn history_bases_match_v_transactions() {
        let db_path = std::env::var("VIZOR_HISTORY_EQUIV_DB")
            .expect("set VIZOR_HISTORY_EQUIV_DB to a librustzcash-built wallet DB");
        let conn = open_readonly_conn(&db_path).unwrap();

        let accounts: Vec<Vec<u8>> = conn
            .prepare("SELECT uuid FROM accounts ORDER BY id")
            .unwrap()
            .query_map([], |row| row.get::<_, Vec<u8>>(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(
            !accounts.is_empty(),
            "{db_path} has no accounts; point at a synced wallet"
        );

        let read_tx = conn.unchecked_transaction().unwrap();
        let mut compared = 0usize;
        for account in &accounts {
            let sort = |mut rows: Vec<TxBase>| {
                rows.sort_by(|a, b| a.txid.cmp(&b.txid));
                rows
            };
            let account_id = AccountUuid::from_uuid(uuid::Uuid::from_slice(account).unwrap());
            let via_summary = sort(
                read_history_bases(&read_tx, &db_path, WalletNetwork::Main, account_id).unwrap(),
            );
            let via_view = sort(read_history_bases_via_v_transactions(&read_tx, account).unwrap());

            assert_eq!(
                via_summary.len(),
                via_view.len(),
                "account {}: row count differs between library summaries and v_transactions",
                hex::encode(account)
            );
            for (summary, view) in via_summary.iter().zip(via_view.iter()) {
                assert_eq!(
                    summary,
                    view,
                    "account {} tx {}: library summaries diverged from v_transactions; \
                     re-check the summary mapping against the upstream view definition",
                    hex::encode(account),
                    hex::encode(&summary.txid),
                );
            }
            compared += via_summary.len();
        }
        println!(
            "compared {compared} rows across {} accounts",
            accounts.len()
        );
        assert!(compared > 0, "{db_path} has no history rows to compare");
    }

    /// Old `read_history_outputs` filter: DISTINCT txid from
    /// `v_transactions` for the active account. Kept only as the
    /// equivalence oracle for the `rarray(bases)` path.
    fn read_history_outputs_via_v_transactions_distinct(
        conn: &rusqlite::Connection,
        account_uuid: &[u8],
    ) -> Result<HashMap<Vec<u8>, Vec<TxOutput>>, String> {
        let mut stmt = conn
            .prepare(
                r#"
            SELECT
                txo.txid,
                txo.output_pool,
                txo.output_index,
                txo.from_account_uuid,
                txo.to_account_uuid,
                txo.to_address,
                (
                    SELECT sn.to_address
                    FROM sent_notes sn
                    JOIN transactions st ON st.id_tx = sn.transaction_id
                    JOIN accounts from_acc ON from_acc.id = sn.from_account_id
                    WHERE st.txid = txo.txid
                      AND from_acc.uuid = ?1
                      AND sn.output_pool = txo.output_pool
                      AND sn.output_index = txo.output_index
                      AND sn.to_address IS NOT NULL
                    LIMIT 1
                ) AS sent_to_address,
                NULL AS transparent_receiver_address,
                (
                    SELECT a.key_scope
                    FROM accounts acc
                    JOIN addresses a ON a.account_id = acc.id
                    WHERE acc.uuid = txo.to_account_uuid
                      AND (
                          a.address = txo.to_address
                          OR a.cached_transparent_receiver_address = txo.to_address
                      )
                    LIMIT 1
                ) AS to_key_scope,
                txo.value,
                txo.memo,
                (
                    SELECT orn.note_version
                    FROM orchard_received_notes orn
                    WHERE txo.output_pool IN (3, 4)
                      AND orn.transaction_id = txo.transaction_id
                      AND orn.action_index = txo.output_index
                    LIMIT 1
                ) AS note_version
            FROM v_tx_outputs txo
            JOIN (
                SELECT DISTINCT txid
                FROM v_transactions
                WHERE account_uuid = ?1
            ) active_tx ON active_tx.txid = txo.txid
            WHERE txo.from_account_uuid = ?1
               OR txo.to_account_uuid = ?1
            "#,
            )
            .map_err(|e| format!("SQL error: {e}"))?;

        let rows = stmt
            .query_map(rusqlite::params![account_uuid], |row| {
                Ok(TxOutput {
                    txid: row.get(0)?,
                    output_pool: row.get(1)?,
                    output_index: row.get(2)?,
                    from_account_uuid: row.get(3)?,
                    to_account_uuid: row.get(4)?,
                    to_address: row.get(5)?,
                    sent_to_address: row.get(6)?,
                    transparent_receiver_address: row.get(7)?,
                    to_key_scope: row.get(8)?,
                    value: row.get::<_, i64>(9)?.unsigned_abs(),
                    memo: row.get(10)?,
                    note_version: row.get(11)?,
                })
            })
            .map_err(|e| format!("Query error: {e}"))?;

        let mut outputs = HashMap::<Vec<u8>, Vec<TxOutput>>::new();
        for row in rows {
            let output = row.map_err(|e| format!("Row error: {e}"))?;
            outputs.entry(output.txid.clone()).or_default().push(output);
        }
        Ok(outputs)
    }

    fn distinct_v_transactions_txids(
        conn: &rusqlite::Connection,
        account_uuid: &[u8],
    ) -> Result<HashSet<Vec<u8>>, String> {
        let mut stmt = conn
            .prepare("SELECT DISTINCT txid FROM v_transactions WHERE account_uuid = ?1")
            .map_err(|e| format!("SQL error: {e}"))?;
        let rows = stmt
            .query_map(rusqlite::params![account_uuid], |row| row.get(0))
            .map_err(|e| format!("Query error: {e}"))?;
        rows.collect::<Result<HashSet<_>, _>>()
            .map_err(|e| format!("Row error: {e}"))
    }

    fn sorted_history_outputs(outputs: &HashMap<Vec<u8>, Vec<TxOutput>>) -> Vec<TxOutput> {
        let mut flat: Vec<TxOutput> = outputs.values().flatten().cloned().collect();
        flat.sort_by(|a, b| {
            (
                &a.txid,
                a.output_pool,
                a.output_index,
                &a.from_account_uuid,
                &a.to_account_uuid,
                a.value,
            )
                .cmp(&(
                    &b.txid,
                    b.output_pool,
                    b.output_index,
                    &b.from_account_uuid,
                    &b.to_account_uuid,
                    b.value,
                ))
        });
        flat
    }

    #[test]
    fn history_outputs_rarray_matches_v_transactions_distinct_txids() {
        // `read_history_outputs` binds txids from `read_history_bases`
        // via `rarray` instead of re-deriving
        // `SELECT DISTINCT txid FROM v_transactions`. These setups pin
        // that the two filters stay row-identical.
        struct Case {
            name: &'static str,
            setup: fn(&NamedTempFile, uuid::Uuid, uuid::Uuid),
        }

        let cases = [
            Case {
                name: "empty",
                setup: |_, _, _| {},
            },
            Case {
                name: "one_received",
                setup: |db, account, _| {
                    let txid = fake_txid(0x01);
                    insert_history_tx(
                        db,
                        account,
                        &txid,
                        Some(100),
                        0,
                        None,
                        1_000_000,
                        0,
                        1_000_000,
                        false,
                        Some("2026-01-01T00:00:00Z"),
                    );
                    insert_output(db, &txid, 3, None, Some(account), 1_000_000, false);
                },
            },
            Case {
                name: "many_mixed",
                setup: |db, account, _| {
                    for (i, (pool, delta, spent, received, from_self, to_self)) in [
                        (3_i64, 500_000_i64, 0_i64, 500_000_i64, false, true),
                        (3, -400_000, 400_000, 0, true, false),
                        (0, -250_000, 250_000, 0, true, false),
                        (3, 0, 100_000, 100_000, true, true),
                        (4, 75_000, 0, 75_000, false, true),
                    ]
                    .into_iter()
                    .enumerate()
                    {
                        let txid = fake_txid(0x10 + i as u8);
                        insert_history_tx(
                            db,
                            account,
                            &txid,
                            Some(200 + i as i64),
                            i as i64,
                            None,
                            delta,
                            spent,
                            received,
                            false,
                            Some("2026-01-02T00:00:00Z"),
                        );
                        // Fat raw must not change the output filter set.
                        set_history_tx_raw(db, account, &txid, &vec![0xAB; 64 * (i + 1)]);
                        let from = from_self.then_some(account);
                        let to = to_self.then_some(account);
                        insert_output(db, &txid, pool, from, to, received.max(spent), false);
                        if from_self && to_self {
                            insert_output(db, &txid, pool, Some(account), None, 1, true);
                        }
                    }
                },
            },
            Case {
                name: "other_account_only",
                setup: |db, _, other| {
                    let txid = fake_txid(0x20);
                    insert_history_tx(
                        db,
                        other,
                        &txid,
                        Some(300),
                        0,
                        None,
                        2_000_000,
                        0,
                        2_000_000,
                        false,
                        None,
                    );
                    insert_output(db, &txid, 3, None, Some(other), 2_000_000, false);
                },
            },
            Case {
                name: "mixed_accounts",
                setup: |db, account, other| {
                    let ours = fake_txid(0x30);
                    let theirs = fake_txid(0x31);
                    insert_history_tx(
                        db,
                        account,
                        &ours,
                        Some(400),
                        0,
                        None,
                        3_000_000,
                        0,
                        3_000_000,
                        false,
                        None,
                    );
                    insert_output(db, &ours, 3, None, Some(account), 3_000_000, false);
                    insert_history_tx(
                        db,
                        other,
                        &theirs,
                        Some(401),
                        0,
                        None,
                        4_000_000,
                        0,
                        4_000_000,
                        false,
                        None,
                    );
                    insert_output(db, &theirs, 3, None, Some(other), 4_000_000, false);
                },
            },
            Case {
                name: "tx_without_outputs",
                setup: |db, account, _| {
                    insert_history_tx(
                        db,
                        account,
                        &fake_txid(0x40),
                        Some(500),
                        0,
                        None,
                        0,
                        0,
                        0,
                        false,
                        None,
                    );
                },
            },
            Case {
                name: "duplicate_v_transactions_rows",
                setup: |db, account, _| {
                    let txid = fake_txid(0x50);
                    insert_history_tx(
                        db,
                        account,
                        &txid,
                        Some(600),
                        0,
                        None,
                        1_000_000,
                        0,
                        1_000_000,
                        false,
                        None,
                    );
                    // Second view row for the same account+txid: DISTINCT
                    // collapses it; rarray dedupes the same way so the
                    // joined output rows stay identical.
                    let conn = rusqlite::Connection::open(db.path()).unwrap();
                    conn.execute(
                        "INSERT INTO v_transactions (
                             account_uuid, txid, raw, mined_height, expired_unmined,
                             account_balance_delta, fee_paid, block_time, total_spent,
                             total_received, is_shielding, expiry_height, tx_index
                         ) VALUES (?1, ?2, NULL, 600, 0, 1_000_000, 0, 0, 0, 1_000_000, 0, NULL, 0)",
                        rusqlite::params![account.as_bytes().as_slice(), txid.as_slice()],
                    )
                    .unwrap();
                    insert_output(db, &txid, 3, None, Some(account), 1_000_000, false);
                },
            },
        ];

        for case in cases {
            let db = fresh_history_db();
            let account = test_account_uuid();
            let other = second_test_account_uuid();
            (case.setup)(&db, account, other);

            let conn = open_readonly_conn(db.path().to_str().unwrap()).unwrap();
            let account_bytes = account.as_bytes().as_slice();
            // Bases come from the fixture oracle, not the library API:
            // this case is about the outputs filter, and the synthetic
            // schema cannot feed the library query. Real-schema tests cover
            // the summary adapter's agreement with `v_transactions`.
            let bases = read_history_bases_via_v_transactions(&conn, account_bytes).unwrap();
            let base_txids: HashSet<Vec<u8>> = bases.iter().map(|base| base.txid.clone()).collect();
            let distinct_txids = distinct_v_transactions_txids(&conn, account_bytes).unwrap();
            assert_eq!(
                base_txids, distinct_txids,
                "{}: bases txids must equal DISTINCT v_transactions.txid",
                case.name
            );

            let via_rarray = read_history_outputs(
                &conn,
                account_bytes,
                bases.iter().map(|base| base.txid.as_slice()),
            )
            .unwrap();
            let via_view =
                read_history_outputs_via_v_transactions_distinct(&conn, account_bytes).unwrap();
            assert_eq!(
                sorted_history_outputs(&via_rarray),
                sorted_history_outputs(&via_view),
                "{}: rarray(bases) outputs must match DISTINCT v_transactions join",
                case.name
            );
        }
    }

    #[test]
    fn history_suppresses_funding_step_after_limit_filtering() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let external_send = fake_txid(0xA1);
        let funding_step = fake_txid(0xA2);
        let created = "2026-04-28T13:03:00Z";

        insert_history_tx(
            &db,
            account,
            &funding_step,
            None,
            2,
            Some(1_000_100),
            -40_000,
            18_302_101,
            18_262_101,
            false,
            Some(created),
        );
        set_history_fee(&db, &funding_step, 40_000);
        insert_output_with_address(
            &db,
            &funding_step,
            0,
            Some(account),
            Some(account),
            10_010_000,
            false,
            Some("t-ephemeral"),
            Some(2),
        );

        insert_history_tx(
            &db,
            account,
            &external_send,
            None,
            1,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            0,
            false,
            Some(created),
        );
        set_history_fee(&db, &external_send, 10_000);
        insert_output(
            &db,
            &external_send,
            0,
            Some(account),
            None,
            10_000_000,
            false,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(external_send));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 10_000_000);
        assert_eq!(got[0].fee, 50_000);
        assert_eq!(got[0].funding_parent_txid, Some(hex::encode(funding_step)));
        assert_eq!(got[0].funding_parent_mined_height, Some(0));
        assert_eq!(got[0].funding_parent_expired, Some(false));
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "UPDATE v_transactions SET mined_height = 100 WHERE txid = ?1",
            rusqlite::params![funding_step],
        )
        .unwrap();
        let confirmed = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Main,
            Some(1),
            &account.to_string(),
        )
        .unwrap();
        assert_eq!(confirmed[0].funding_parent_mined_height, Some(100));
        conn.execute(
            "UPDATE v_transactions SET mined_height = NULL, expired_unmined = 1 WHERE txid = ?1",
            rusqlite::params![funding_step],
        )
        .unwrap();
        let expired = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Main,
            Some(1),
            &account.to_string(),
        )
        .unwrap();
        assert_eq!(expired[0].funding_parent_expired, Some(true));
    }

    #[test]
    fn history_pairs_suppressed_funding_fees_by_transparent_amount() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let external_send_a = fake_txid(0xA3);
        let funding_step_a = fake_txid(0xA4);
        let external_send_b = fake_txid(0xA5);
        let funding_step_b = fake_txid(0xA6);
        let created = "2026-04-28T13:03:00Z";

        insert_zip320_history_pair(
            &db,
            account,
            &funding_step_a,
            &external_send_a,
            created,
            4,
            3,
            1_000_100,
            10_010_000,
            40_000,
            10_000,
        );
        insert_zip320_history_pair(
            &db,
            account,
            &funding_step_b,
            &external_send_b,
            created,
            2,
            1,
            1_000_100,
            20_015_000,
            50_000,
            15_000,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);

        let row_a = got
            .iter()
            .find(|tx| tx.txid_hex == hex::encode(external_send_a))
            .unwrap();
        assert_eq!(row_a.tx_kind, "sent");
        assert_eq!(row_a.display_amount, 10_000_000);
        assert_eq!(row_a.fee, 50_000);

        let row_b = got
            .iter()
            .find(|tx| tx.txid_hex == hex::encode(external_send_b))
            .unwrap();
        assert_eq!(row_b.tx_kind, "sent");
        assert_eq!(row_b.display_amount, 20_000_000);
        assert_eq!(row_b.fee, 65_000);
    }

    #[test]
    fn history_pairs_same_amount_funding_fees_by_insert_order() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let external_send_a = fake_txid(0xA7);
        let funding_step_a = fake_txid(0xA8);
        let external_send_b = fake_txid(0xA9);
        let funding_step_b = fake_txid(0xAA);
        let created = "2026-04-28T13:03:00Z";

        insert_zip320_history_pair(
            &db,
            account,
            &funding_step_a,
            &external_send_a,
            created,
            4,
            3,
            1_000_100,
            10_010_000,
            40_000,
            10_000,
        );
        insert_zip320_history_pair(
            &db,
            account,
            &funding_step_b,
            &external_send_b,
            created,
            2,
            1,
            1_000_100,
            10_010_000,
            50_000,
            10_000,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);

        let row_a = got
            .iter()
            .find(|tx| tx.txid_hex == hex::encode(external_send_a))
            .unwrap();
        assert_eq!(row_a.tx_kind, "sent");
        assert_eq!(row_a.display_amount, 10_000_000);
        assert_eq!(row_a.fee, 50_000);

        let row_b = got
            .iter()
            .find(|tx| tx.txid_hex == hex::encode(external_send_b))
            .unwrap();
        assert_eq!(row_b.tx_kind, "sent");
        assert_eq!(row_b.display_amount, 10_000_000);
        assert_eq!(row_b.fee, 60_000);
    }

    #[test]
    fn history_splits_same_account_transparent_self_send() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xB1);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -40_000,
            18_302_101,
            18_262_101,
            false,
            Some("2026-04-28T13:03:00Z"),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            0,
            Some(account),
            Some(account),
            18_262_101,
            false,
            Some("t-self"),
            Some(0),
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 18_262_101);
        assert_eq!(got[0].display_pool, "transparent");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 18_262_101);
        assert_eq!(got[1].display_pool, "transparent");
    }

    #[test]
    fn history_classifies_orchard_to_ironwood_internal_transition_as_migration() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let migration_tx = fake_txid(0xB5);

        insert_history_tx(
            &db,
            account,
            &migration_tx,
            None,
            1,
            Some(1_000_100),
            -20_000,
            625_000_000,
            624_980_000,
            false,
            Some("2026-06-08T22:45:02Z"),
        );
        let output_index = insert_output_with_address_and_memo(
            &db,
            &migration_tx,
            3,
            Some(account),
            Some(account),
            624_980_000,
            true,
            None,
            Some(1),
            None,
        );
        insert_received_note_version(&db, &migration_tx, output_index, IRONWOOD_NOTE_VERSION);
        insert_spent_note_version(&db, &migration_tx, ORCHARD_NOTE_VERSION);

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(migration_tx));
        assert_eq!(got[0].tx_kind, "migration");
        assert_eq!(got[0].display_amount, 624_980_000);
        assert_eq!(got[0].display_pool, "ironwood");
    }

    #[test]
    fn history_classifies_pool_4_internal_transition_as_migration() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let migration_tx = fake_txid(0xB6);

        insert_history_tx(
            &db,
            account,
            &migration_tx,
            None,
            1,
            Some(1_000_100),
            -20_000,
            625_000_000,
            624_980_000,
            false,
            Some("2026-06-08T22:45:02Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &migration_tx,
            IRONWOOD_POOL,
            Some(account),
            Some(account),
            624_980_000,
            true,
            None,
            Some(1),
            None,
        );
        insert_spent_note_version(&db, &migration_tx, ORCHARD_NOTE_VERSION);

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(migration_tx));
        assert_eq!(got[0].tx_kind, "migration");
        assert_eq!(got[0].display_amount, 624_980_000);
        assert_eq!(got[0].display_pool, "ironwood");
    }

    #[test]
    fn history_treats_send_to_other_local_account_as_sent() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let txid = fake_txid(0xB2);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -5_000_000,
            5_000_000,
            0,
            false,
            Some("2026-04-28T14:03:00Z"),
        );
        insert_output(
            &db,
            &txid,
            0,
            Some(account),
            Some(other_account),
            5_000_000,
            false,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 5_000_000);
    }

    #[test]
    fn history_treats_receive_from_other_local_account_as_received() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let other_account = second_test_account_uuid();
        let txid = fake_txid(0xB3);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            5_000_000,
            0,
            5_000_000,
            false,
            Some("2026-04-28T14:04:00Z"),
        );
        insert_output(
            &db,
            &txid,
            0,
            Some(other_account),
            Some(account),
            5_000_000,
            false,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "received");
        assert_eq!(got[0].display_amount, 5_000_000);
    }

    #[test]
    fn history_splits_same_account_shielded_self_send_and_hides_change() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xC0);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            17_252_101,
            17_237_101,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self"),
            Some(0),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            16_237_101,
            true,
            Some("u-change"),
            Some(1),
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 1_000_000);
        assert_eq!(got[0].display_pool, "shielded");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 1_000_000);
        assert_eq!(got[1].display_pool, "shielded");
    }

    #[test]
    fn history_uses_sent_note_when_self_send_key_scope_is_unresolved() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xC7);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            1_015_000,
            1_000_000,
            false,
            Some("2026-04-28T16:36:00Z"),
        );
        let output_index = insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self-unresolved"),
            None,
        );
        insert_sent_note(
            &db,
            &self_tx,
            3,
            output_index,
            account,
            Some(account),
            Some("u-self-unresolved"),
            1_000_000,
            None,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 1_000_000);
        assert_eq!(got[0].display_pool, "shielded");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 1_000_000);
        assert_eq!(got[1].display_pool, "shielded");
    }

    #[test]
    fn history_preserves_mixed_pool_for_visible_self_outputs() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let self_tx = fake_txid(0xC6);

        insert_history_tx(
            &db,
            account,
            &self_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            6_115_000,
            6_100_000,
            false,
            Some("2026-04-28T16:40:00Z"),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            0,
            Some(account),
            Some(account),
            100_000,
            true,
            Some("t-self"),
            Some(0),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self"),
            Some(0),
        );
        insert_output_with_address(
            &db,
            &self_tx,
            3,
            Some(account),
            Some(account),
            5_000_000,
            true,
            Some("u-change"),
            Some(1),
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].txid_hex, hex::encode(self_tx));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 1_100_000);
        assert_eq!(got[0].display_pool, "mixed");
        assert_eq!(got[1].txid_hex, hex::encode(self_tx));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 1_100_000);
        assert_eq!(got[1].display_pool, "mixed");
    }

    /// H09: one transparent input pays an external transparent address and
    /// the account's own shielded address. The sent row is the external
    /// payment only; the shielded output is the account's receive, not money
    /// paid away (the app showed −1.9998 for a 1.2998 payment).
    #[test]
    fn history_mixed_pool_payment_excludes_the_accounts_own_output() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let tx = fake_txid(0xC9);

        // 2.0 in; 1.29985 to B (external t), 0.7 to the account's own
        // external UA (Orchard), 0.00015 fee.
        insert_history_tx(
            &db,
            account,
            &tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -130_000_000,
            200_000_000,
            70_000_000,
            false,
            None,
        );
        insert_output_with_address(
            &db,
            &tx,
            0,
            Some(account),
            None,
            129_985_000,
            false,
            Some("t-external-b"),
            None,
        );
        insert_output_with_address(
            &db,
            &tx,
            3,
            Some(account),
            Some(account),
            70_000_000,
            false,
            Some("u-own-external"),
            Some(0),
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 2);
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 129_985_000);
        assert_eq!(got[0].display_pool, "transparent");
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 70_000_000);
        assert_eq!(got[1].display_pool, "shielded");

        let detail = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(tx),
            "sent",
        )
        .unwrap();
        assert_eq!(detail.outputs.len(), 1, "the sent detail lists only B");
        assert_eq!(detail.outputs[0].amount_zatoshi, 129_985_000);
    }

    /// The H09 shape with the shielded output paid to another wallet account:
    /// that output is money the sender paid away, so it stays in the sender's
    /// sent row, and the other account shows it as its receive.
    #[test]
    fn history_mixed_pool_payment_to_another_account_stays_sent() {
        let db = fresh_history_db();
        let sender = test_account_uuid();
        let recipient = second_test_account_uuid();
        let tx = fake_txid(0xCA);

        insert_history_tx(
            &db,
            sender,
            &tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -200_000_000,
            200_000_000,
            0,
            false,
            None,
        );
        {
            // The recipient's row of the same transaction.
            let conn = rusqlite::Connection::open(db.path()).unwrap();
            ensure_account_row(&conn, recipient);
            conn.execute(
                "INSERT INTO v_transactions (
                     account_uuid, txid, raw, mined_height, expired_unmined,
                     account_balance_delta, fee_paid, block_time, total_spent,
                     total_received, is_shielding, expiry_height, tx_index
                 ) VALUES (?1, ?2, NULL, 1000000, 0, 70000000, 0, 0, 0, 70000000, 0, 1000100, 1)",
                rusqlite::params![recipient.as_bytes().as_slice(), &tx[..]],
            )
            .unwrap();
        }
        insert_output_with_address(
            &db,
            &tx,
            0,
            Some(sender),
            None,
            129_985_000,
            false,
            Some("t-external-b"),
            None,
        );
        insert_output_with_address(
            &db,
            &tx,
            3,
            Some(sender),
            Some(recipient),
            70_000_000,
            false,
            Some("u-recipient-external"),
            Some(0),
        );

        let path = db.path().to_str().unwrap();
        let sent =
            history_from_fixture(path, WalletNetwork::Test, None, &sender.to_string()).unwrap();
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0].tx_kind, "sent");
        assert_eq!(sent[0].display_amount, 199_985_000);
        assert_eq!(sent[0].display_pool, "mixed");

        let received =
            history_from_fixture(path, WalletNetwork::Test, None, &recipient.to_string()).unwrap();
        assert_eq!(received.len(), 1);
        assert_eq!(received[0].tx_kind, "received");
        assert_eq!(received[0].display_amount, 70_000_000);
        assert_eq!(received[0].display_pool, "shielded");
    }

    #[test]
    fn history_hides_change_only_internal_tx() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let change_only_tx = fake_txid(0xC3);

        insert_history_tx(
            &db,
            account,
            &change_only_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            17_252_102,
            17_242_102,
            false,
            Some("2026-04-28T15:43:00Z"),
        );
        insert_output_with_address(
            &db,
            &change_only_tx,
            3,
            Some(account),
            Some(account),
            7_242_102,
            true,
            Some("u-change-1"),
            Some(1),
        );
        insert_output_with_address(
            &db,
            &change_only_tx,
            3,
            Some(account),
            Some(account),
            10_000_000,
            true,
            Some("u-change-2"),
            Some(1),
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert!(got.is_empty());
    }

    #[test]
    fn history_keeps_shielding_tx_as_single_shielded_row() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let shielding_tx = fake_txid(0xC4);

        insert_history_tx(
            &db,
            account,
            &shielding_tx,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            10_010_000,
            10_000_000,
            true,
            Some("2026-04-28T15:44:00Z"),
        );
        insert_output(
            &db,
            &shielding_tx,
            3,
            Some(account),
            Some(account),
            10_000_000,
            true,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(shielding_tx));
        assert_eq!(got[0].tx_kind, "shielded");
        assert_eq!(got[0].display_amount, 10_000_000);
        assert_eq!(got[0].display_pool, "shielded");
    }

    #[test]
    fn history_sent_to_transparent_excludes_shielded_change() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xC5);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            1_265_000,
            1_150_000,
            false,
            Some("2026-04-28T16:45:00Z"),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            150_000,
            false,
            Some("t-ephemeral"),
            Some(2),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-change"),
            Some(1),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            None,
            100_000,
            false,
            Some("t-recipient"),
            None,
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 100_000);
        assert_eq!(got[0].display_pool, "transparent");
    }

    #[test]
    fn detail_sent_row_returns_recipient_address_and_memo() {
        for (output_pool, label, activity_pool, uses_orchard) in [
            (SAPLING_POOL, "shielded", "sapling", false),
            (ORCHARD_POOL, "shielded", "orchard", true),
            (IRONWOOD_POOL, "ironwood", "ironwood", true),
        ] {
            let db = fresh_history_db();
            let account = test_account_uuid();
            let txid = fake_txid(0xD1);

            insert_history_tx(
                &db,
                account,
                &txid,
                Some(1_000_000),
                1,
                Some(1_000_100),
                -1_010_000,
                1_010_000,
                0,
                false,
                Some("2026-04-28T17:00:00Z"),
            );
            insert_output_with_address_and_memo(
                &db,
                &txid,
                output_pool,
                Some(account),
                None,
                1_000_000,
                false,
                Some("u-recipient"),
                None,
                Some(b"hello from activity"),
            );

            let got = detail_from_fixture(
                db.path().to_str().unwrap(),
                WalletNetwork::Test,
                &account.to_string(),
                &hex::encode(txid),
                "sent",
            )
            .unwrap();

            assert_eq!(got.txid_hex, hex::encode(txid));
            assert_eq!(got.tx_kind, "sent");
            assert_eq!(got.primary_address.as_deref(), Some("u-recipient"));
            assert_eq!(got.memo.as_deref(), Some("hello from activity"));
            assert_eq!(got.outputs.len(), 1);
            assert_eq!(got.outputs[0].address.as_deref(), Some("u-recipient"));
            assert_eq!(got.outputs[0].amount_zatoshi, 1_000_000);
            assert_eq!(got.outputs[0].pool, label);
            assert_eq!(got.outputs[0].activity_pool.as_deref(), Some(activity_pool));
            assert_eq!(got.outputs[0].uses_orchard_receiver, uses_orchard);
        }
    }

    fn zero_value_history(db: &NamedTempFile, account: uuid::Uuid) -> Vec<TransactionInfo> {
        history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap()
    }

    fn zero_value_detail(
        db: &NamedTempFile,
        account: uuid::Uuid,
        txid: &[u8],
        tx_kind: &str,
    ) -> TransactionDetail {
        detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            tx_kind,
        )
        .unwrap()
    }

    #[test]
    fn history_shows_zero_value_receipt_and_its_memo() {
        for (mined_height, tx_kind) in [(Some(1_000_000), "received"), (None, "receiving")] {
            let db = fresh_history_db();
            let account = test_account_uuid();
            let txid = fake_txid(0xE1);

            insert_history_tx(
                &db,
                account,
                &txid,
                mined_height,
                1,
                Some(1_000_100),
                0,
                0,
                0,
                false,
                None,
            );
            insert_output_with_address_and_memo(
                &db,
                &txid,
                ORCHARD_POOL,
                None,
                Some(account),
                0,
                false,
                Some("u-own"),
                Some(0),
                Some(b"memo-only payment"),
            );

            let got = zero_value_history(&db, account);
            assert_eq!(got.len(), 1);
            assert_eq!(got[0].tx_kind, tx_kind);
            assert_eq!(got[0].display_amount, 0);
            assert_eq!(got[0].display_pool, "shielded");

            let detail = zero_value_detail(&db, account, &txid, tx_kind);
            assert_eq!(detail.memo.as_deref(), Some("memo-only payment"));
            assert_eq!(detail.outputs.len(), 1);
            assert_eq!(detail.outputs[0].amount_zatoshi, 0);
        }
    }

    #[test]
    fn history_shows_zero_value_receipt_without_text_memo() {
        for (output_pool, memo, pool_label) in [
            (ORCHARD_POOL, None, "shielded"),
            (ORCHARD_POOL, Some(&[0xFF_u8][..]), "shielded"),
            (TRANSPARENT_POOL, None, "transparent"),
        ] {
            let db = fresh_history_db();
            let account = test_account_uuid();
            let txid = fake_txid(0xE2);

            insert_history_tx(
                &db,
                account,
                &txid,
                Some(1_000_000),
                1,
                Some(1_000_100),
                0,
                0,
                0,
                false,
                None,
            );
            insert_output_with_address_and_memo(
                &db,
                &txid,
                output_pool,
                None,
                Some(account),
                0,
                false,
                Some("own-address"),
                Some(0),
                memo,
            );

            let got = zero_value_history(&db, account);
            assert_eq!(got.len(), 1);
            assert_eq!(got[0].tx_kind, "received");
            assert_eq!(got[0].display_amount, 0);
            assert_eq!(got[0].display_pool, pool_label);
            assert_eq!(
                zero_value_detail(&db, account, &txid, "received").memo,
                None
            );
        }
    }

    #[test]
    fn history_shows_zero_value_send_and_its_memo() {
        for with_change in [true, false] {
            let db = fresh_history_db();
            let account = test_account_uuid();
            let txid = fake_txid(0xE3);
            let (total_spent, change) = if with_change {
                (100_000, 90_000)
            } else {
                (10_000, 0)
            };

            insert_history_tx(
                &db,
                account,
                &txid,
                Some(1_000_000),
                1,
                Some(1_000_100),
                -10_000,
                total_spent,
                change,
                false,
                Some("2026-09-29T09:00:00Z"),
            );
            set_history_fee(&db, &txid, 10_000);
            insert_output_with_address_and_memo(
                &db,
                &txid,
                ORCHARD_POOL,
                Some(account),
                None,
                0,
                false,
                Some("u-recipient"),
                None,
                Some(b"memo-only payment"),
            );
            if with_change {
                insert_output_with_address(
                    &db,
                    &txid,
                    ORCHARD_POOL,
                    Some(account),
                    Some(account),
                    change,
                    true,
                    Some("u-change"),
                    Some(1),
                );
            }

            let got = zero_value_history(&db, account);
            assert_eq!(got.len(), 1, "with_change={with_change}");
            assert_eq!(got[0].tx_kind, "sent");
            assert_eq!(got[0].display_amount, 0);
            assert_eq!(got[0].display_pool, "shielded");
            assert_eq!(got[0].fee, 10_000);

            let detail = zero_value_detail(&db, account, &txid, "sent");
            assert_eq!(detail.primary_address.as_deref(), Some("u-recipient"));
            assert_eq!(detail.memo.as_deref(), Some("memo-only payment"));
            assert_eq!(detail.outputs.len(), 1);
            assert_eq!(detail.outputs[0].amount_zatoshi, 0);
        }
    }

    #[test]
    fn history_splits_zero_value_memo_to_self() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xE4);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            100_000,
            90_000,
            false,
            Some("2026-09-29T09:00:00Z"),
        );
        set_history_fee(&db, &txid, 10_000);
        insert_output_with_address_and_memo(
            &db,
            &txid,
            ORCHARD_POOL,
            Some(account),
            Some(account),
            0,
            true,
            Some("u-self"),
            Some(0),
            Some(b"note to self"),
        );
        insert_output_with_address(
            &db,
            &txid,
            ORCHARD_POOL,
            Some(account),
            Some(account),
            90_000,
            true,
            Some("u-change"),
            Some(1),
        );

        let got = zero_value_history(&db, account);
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 0);
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[1].display_amount, 0);
    }

    #[test]
    fn history_keeps_unenhanced_zero_value_change_unknown() {
        // Before enhancement our zero-value change has no sent-note link, so
        // it arrives with no sender like an external receipt.
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xE5);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -100_000,
            100_000,
            0,
            false,
            None,
        );
        insert_output_with_address(
            &db,
            &txid,
            ORCHARD_POOL,
            None,
            Some(account),
            0,
            true,
            Some("u-change"),
            Some(1),
        );

        let got = zero_value_history(&db, account);
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].tx_kind, "unknown");
    }

    /// A TEX funding step no send carries the fee of keeps a row: the fee
    /// was paid, and it is all the step moved out of the account.
    #[test]
    fn history_keeps_an_unmatched_funding_step_as_its_fee() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xE6);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            1,
            Some(1_000_100),
            -10_000,
            1_010_000,
            1_000_000,
            false,
            Some("2026-09-29T09:00:00Z"),
        );
        set_history_fee(&db, &txid, 10_000);
        insert_output_with_address(
            &db,
            &txid,
            TRANSPARENT_POOL,
            Some(account),
            Some(account),
            1_000_000,
            false,
            Some("t-ephemeral"),
            Some(EPHEMERAL_KEY_SCOPE),
        );

        let rows = zero_value_history(&db, account);
        assert_eq!(rows.len(), 1);
        let row = &rows[0];
        assert_eq!(row.tx_kind, "sent");
        assert_eq!(
            (row.display_amount, row.fee_state, row.fee),
            (10_000, TransactionFeeState::Known, 10_000),
            "the account's own fee is the whole change"
        );
        assert!(row.amount_is_net_change);
        assert_eq!(row.display_pool, "unknown");
    }

    /// Roman's private 38c60b4a and 71c0e25d: a TEX send to his own
    /// transparent address, known only from private recovery. The funding step
    /// moves Ironwood funds to an ephemeral address with Ironwood change, its
    /// fee only the transaction's whole fee; the send spends that output to
    /// his own external address with its own fee. The funding step keeps its
    /// uncertain net-change row: its whole fee does not establish the
    /// account's share. The send keeps Sent and Received rows for the moved
    /// amount. An attributed account fee allows the funding step to fold.
    #[test]
    fn a_private_tex_send_to_self_keeps_its_unattributed_funding_step() {
        let account = test_account_uuid();
        let uuid = account.as_bytes().to_vec();
        let (step_txid, send_txid) = (fake_txid(0xF1).to_vec(), fake_txid(0xF2).to_vec());
        let output = |txid: &[u8], pool, from_own: bool, scope, value| TxOutput {
            txid: txid.to_vec(),
            output_pool: pool,
            output_index: 0,
            from_account_uuid: from_own.then(|| uuid.clone()),
            to_account_uuid: Some(uuid.clone()),
            to_address: None,
            sent_to_address: None,
            transparent_receiver_address: None,
            to_key_scope: Some(scope),
            value,
            memo: None,
            note_version: None,
        };
        let base = |txid: &[u8], id, delta: i64, spent, history| {
            let mut base = tx_base_for_history();
            base.txid = txid.to_vec();
            base.transaction_id = id;
            base.spent_orchard_note = false;
            base.fee = None;
            base.account_balance_delta = delta;
            base.total_spent = spent;
            base.total_received = spent - delta.unsigned_abs();
            base.attach_history(history);
            base
        };
        let bases = [
            base(
                &step_txid,
                1,
                -15_000,
                107_670_000,
                HistoryCompleteness {
                    inferred_outgoing: Some(110_000),
                    has_transparent_outputs: Some(true),
                    details_complete: false,
                    provisional: true,
                    classification: None,
                    effects_settled: true,
                    fee: Fee::Unknown,
                    whole_fee: Some(15_000),
                    sole_transparent_funder: false,
                    inferred_payment: None,
                },
            ),
            base(
                &send_txid,
                2,
                -10_000,
                110_000,
                HistoryCompleteness {
                    inferred_outgoing: None,
                    has_transparent_outputs: None,
                    details_complete: false,
                    provisional: false,
                    classification: None,
                    effects_settled: true,
                    fee: Fee::Known(10_000),
                    whole_fee: Some(10_000),
                    sole_transparent_funder: true,
                    inferred_payment: Some(0),
                },
            ),
        ];
        let outputs = HashMap::from([
            (
                step_txid.clone(),
                vec![
                    output(
                        &step_txid,
                        TRANSPARENT_POOL,
                        false,
                        EPHEMERAL_KEY_SCOPE,
                        110_000,
                    ),
                    output(&step_txid, IRONWOOD_POOL, true, 1, 107_545_000),
                ],
            ),
            (
                send_txid.clone(),
                vec![output(&send_txid, TRANSPARENT_POOL, false, 0, 100_000)],
            ),
        ]);
        let rows = |spends: &EphemeralSpends| {
            assemble_history(&bases, &outputs, spends, &uuid, None)
                .into_iter()
                .map(|row| {
                    (
                        row.txid_hex == hex::encode(&send_txid),
                        row.tx_kind,
                        row.display_amount,
                        row.display_pool,
                        row.fee_state,
                        row.fee,
                    )
                })
                .collect::<Vec<_>>()
        };

        let whole = TransactionFeeState::WholeTransaction;
        assert_eq!(
            rows(&HashMap::from([(
                step_txid.clone(),
                vec![send_txid.clone()]
            )])),
            [
                (
                    true,
                    "sent".into(),
                    100_000,
                    "transparent".into(),
                    TransactionFeeState::Known,
                    10_000,
                ),
                (
                    true,
                    "received".into(),
                    100_000,
                    "transparent".into(),
                    TransactionFeeState::Known,
                    10_000,
                ),
                (
                    false,
                    "sent".into(),
                    15_000,
                    "unknown".into(),
                    whole,
                    15_000,
                ),
            ],
            "the uncertain funding activity stays separate from the self-transfer"
        );
        let linked = HashMap::from([(step_txid.clone(), vec![send_txid.clone()])]);
        let mut attributed = bases.clone();
        attributed[0].history.fee = Fee::Known(15_000);
        attributed[0].history.provisional = false;
        let attributed_rows = assemble_history(&attributed, &outputs, &linked, &uuid, None);
        assert!(fees_of(&attributed_rows, &step_txid).is_empty());
        assert_eq!(
            fees_of(&attributed_rows, &send_txid),
            [
                (TransactionFeeState::Known, 25_000, false),
                (TransactionFeeState::Known, 10_000, false),
            ],
            "an attributed account fee still folds into the send's Sent row"
        );
        // Unlinked, the step keeps a row with its fee, never a receipt of its
        // intermediate output.
        let step_rows = |rows: Vec<(bool, String, u64, String, TransactionFeeState, u64)>| {
            rows.into_iter().filter(|row| !row.0).collect::<Vec<_>>()
        };
        assert_eq!(
            step_rows(rows(&EphemeralSpends::new())),
            [(
                false,
                "sent".into(),
                15_000,
                "unknown".into(),
                whole,
                15_000
            )]
        );

        // A step whose balance change is more than its fee also paid
        // something: it is no mere cost of the send and keeps its own row.
        let mut paid = bases.clone();
        paid[0].account_balance_delta = -25_000;
        let shown = assemble_history(&paid, &outputs, &linked, &uuid, None);
        assert_eq!(
            shown
                .iter()
                .filter(|row| row.txid_hex == hex::encode(&step_txid))
                .map(|row| (row.display_amount, row.amount_is_net_change))
                .collect::<Vec<_>>(),
            [(25_000, true)]
        );
        assert_eq!(
            shown
                .iter()
                .filter(|row| row.txid_hex == hex::encode(&send_txid) && row.tx_kind == "sent")
                .map(|row| row.fee)
                .collect::<Vec<_>>(),
            [10_000],
            "the send carries only its own fee"
        );
    }

    /// Chained funding steps: the first step's ephemeral output funds a
    /// second step, whose output funds the send. Only the step the send
    /// spends folds into it; the first keeps its own fee row, so no fee is
    /// lost or shown twice.
    #[test]
    fn a_chained_funding_step_keeps_its_fee_row() {
        let account = test_account_uuid();
        let uuid = account.as_bytes().to_vec();
        let txids = [fake_txid(0xF5), fake_txid(0xF6), fake_txid(0xF7)].map(|t| t.to_vec());
        let recovered = |payment| HistoryCompleteness {
            inferred_outgoing: None,
            has_transparent_outputs: None,
            details_complete: false,
            provisional: false,
            classification: None,
            effects_settled: true,
            fee: Fee::Known(10_000),
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            inferred_payment: Some(payment),
        };
        let base = |index: usize, delta: i64, payment| {
            let mut base = tx_base_for_history();
            base.txid = txids[index].clone();
            base.transaction_id = index as i64 + 1;
            base.spent_orchard_note = false;
            base.fee = None;
            base.account_balance_delta = delta;
            base.total_spent = 1_000_000;
            base.total_received = 1_000_000 - delta.unsigned_abs();
            base.attach_history(recovered(payment));
            base
        };
        let ephemeral = |index: usize, value| TxOutput {
            txid: txids[index].clone(),
            output_pool: TRANSPARENT_POOL,
            output_index: 0,
            from_account_uuid: None,
            to_account_uuid: Some(uuid.clone()),
            to_address: None,
            sent_to_address: None,
            transparent_receiver_address: None,
            to_key_scope: Some(EPHEMERAL_KEY_SCOPE),
            value,
            memo: None,
            note_version: None,
        };
        let bases = [
            base(0, -10_000, 0),
            base(1, -10_000, 0),
            base(2, -980_000, 970_000),
        ];
        let outputs = HashMap::from([
            (txids[0].clone(), vec![ephemeral(0, 990_000)]),
            (txids[1].clone(), vec![ephemeral(1, 980_000)]),
        ]);
        let spends = HashMap::from([
            (txids[0].clone(), vec![txids[1].clone()]),
            (txids[1].clone(), vec![txids[2].clone()]),
        ]);

        let mut rows = assemble_history(&bases, &outputs, &spends, &uuid, None)
            .into_iter()
            .map(|row| {
                (
                    txids.iter().position(|t| hex::encode(t) == row.txid_hex),
                    row.display_amount,
                    row.fee,
                    row.amount_is_net_change,
                )
            })
            .collect::<Vec<_>>();
        rows.sort();
        assert_eq!(
            rows,
            [
                (Some(0), 10_000, 10_000, true),
                (Some(2), 970_000, 20_000, false),
            ]
        );
    }

    /// Records that `spending` spends the output `funding` paid to the
    /// account's `address`.
    fn link_transparent_spend(
        db: &NamedTempFile,
        account: uuid::Uuid,
        funding: &[u8],
        address: &str,
        spending: &[u8],
    ) {
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let account_id = ensure_account_row(&conn, account);
        let id_of = |txid: &[u8]| -> i64 {
            conn.query_row(
                "SELECT id_tx FROM transactions WHERE txid = ?1",
                rusqlite::params![txid],
                |row| row.get(0),
            )
            .unwrap()
        };
        let address_id: i64 = conn
            .query_row(
                "SELECT id FROM addresses WHERE account_id = ?1 AND address = ?2 LIMIT 1",
                rusqlite::params![account_id, address],
                |row| row.get(0),
            )
            .unwrap();
        conn.execute(
            "INSERT INTO transparent_received_outputs (transaction_id, account_id, address_id)
             VALUES (?1, ?2, ?3)",
            rusqlite::params![id_of(funding), account_id, address_id],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO transparent_received_output_spends
                 (transparent_received_output_id, transaction_id)
             VALUES (?1, ?2)",
            rusqlite::params![conn.last_insert_rowid(), id_of(spending)],
        )
        .unwrap();
    }

    /// A restored wallet's TEX send (Roman's ae3e57d0 and 3fb9fe13): the
    /// funding step moves Orchard funds to an ephemeral address with change,
    /// and the send spends that output to the TEX recipient. Neither has a
    /// creation time, so the step is matched by the output the send spends:
    /// its fee folds into the send's, and it has no row of its own.
    #[test]
    fn history_folds_a_restored_funding_step_into_the_send_spending_its_output() {
        let history = |linked: bool| {
            let db = fresh_history_db();
            let account = test_account_uuid();
            let funding_step = fake_txid(0xE7);
            let send = fake_txid(0xE8);
            insert_history_tx(
                &db,
                account,
                &funding_step,
                Some(1_000),
                1,
                Some(1_040),
                -15_000,
                1_000_000,
                985_000,
                false,
                None,
            );
            set_history_fee(&db, &funding_step, 15_000);
            insert_output_with_address(
                &db,
                &funding_step,
                TRANSPARENT_POOL,
                Some(account),
                Some(account),
                20_000,
                false,
                Some("t-ephemeral"),
                Some(EPHEMERAL_KEY_SCOPE),
            );
            insert_output_with_address(
                &db,
                &funding_step,
                ORCHARD_POOL,
                Some(account),
                Some(account),
                965_000,
                true,
                Some("u-change"),
                Some(1),
            );
            insert_history_tx(
                &db,
                account,
                &send,
                Some(1_000),
                2,
                Some(1_040),
                -20_000,
                20_000,
                0,
                false,
                None,
            );
            set_history_fee(&db, &send, 10_000);
            insert_output(
                &db,
                &send,
                TRANSPARENT_POOL,
                Some(account),
                None,
                10_000,
                false,
            );
            if linked {
                link_transparent_spend(&db, account, &funding_step, "t-ephemeral", &send);
            }
            zero_value_history(&db, account)
                .into_iter()
                .map(|row| {
                    (
                        row.txid_hex == hex::encode(send),
                        row.tx_kind,
                        row.display_amount,
                        row.display_pool,
                        row.fee,
                        row.funding_parent_txid == Some(hex::encode(funding_step)),
                    )
                })
                .collect::<Vec<_>>()
        };

        assert_eq!(
            history(true),
            [(
                true,
                "sent".into(),
                10_000,
                "transparent".into(),
                25_000,
                true
            )],
            "one send, both legs' fees, funded by the step"
        );
        // Unlinked, neither leg's fee is lost.
        let mut unlinked = history(false);
        unlinked.sort();
        assert_eq!(
            unlinked,
            [
                (
                    false,
                    "sent".into(),
                    15_000,
                    "unknown".into(),
                    15_000,
                    false
                ),
                (
                    true,
                    "sent".into(),
                    10_000,
                    "transparent".into(),
                    10_000,
                    false
                ),
            ]
        );
    }

    /// A retained wallet's TEX send matched to its funding step both by
    /// creation time and by the output it spends: the step's fee joins the
    /// send once.
    #[test]
    fn a_funding_step_matched_both_ways_folds_once() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let (step, send) = (fake_txid(0xEB), fake_txid(0xEC));
        insert_zip320_history_pair(
            &db,
            account,
            &step,
            &send,
            "2026-04-28T13:03:00Z",
            1,
            2,
            200,
            500_000,
            15_000,
            10_000,
        );
        link_transparent_spend(&db, account, &step, "t-ephemeral", &send);

        let rows = zero_value_history(&db, account);

        assert_eq!(rows.len(), 1);
        assert_eq!((rows[0].tx_kind.as_str(), rows[0].fee), ("sent", 25_000));
        assert_eq!(rows[0].funding_parent_txid, Some(hex::encode(step)));
    }

    /// Only the spend of a step's ephemeral output is its send: its
    /// transparent change spent by another transaction carries no fee of it.
    #[test]
    fn a_funding_step_folds_into_the_spender_of_its_ephemeral_output_only() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let (step, sweep, send) = (fake_txid(0xED), fake_txid(0xEE), fake_txid(0xEF));
        insert_history_tx(
            &db,
            account,
            &step,
            Some(1_000),
            1,
            Some(1_040),
            -15_000,
            1_000_000,
            985_000,
            false,
            None,
        );
        set_history_fee(&db, &step, 15_000);
        insert_output_with_address(
            &db,
            &step,
            TRANSPARENT_POOL,
            Some(account),
            Some(account),
            20_000,
            false,
            Some("t-ephemeral"),
            Some(EPHEMERAL_KEY_SCOPE),
        );
        insert_output_with_address(
            &db,
            &step,
            TRANSPARENT_POOL,
            Some(account),
            Some(account),
            965_000,
            true,
            Some("t-change"),
            Some(1),
        );
        // The change is spent first, by a transaction of its own.
        for (txid, index, spent, fee) in [(&sweep, 2, 965_000, 10_000), (&send, 3, 20_000, 10_000)]
        {
            insert_history_tx(
                &db,
                account,
                txid,
                Some(1_001),
                index,
                Some(1_041),
                -spent,
                spent,
                0,
                false,
                None,
            );
            set_history_fee(&db, txid, fee);
            insert_output(
                &db,
                txid,
                TRANSPARENT_POOL,
                Some(account),
                None,
                spent - fee,
                false,
            );
        }
        link_transparent_spend(&db, account, &step, "t-change", &sweep);
        link_transparent_spend(&db, account, &step, "t-ephemeral", &send);

        let rows = zero_value_history(&db, account);

        let known = TransactionFeeState::Known;
        assert_eq!(fees_of(&rows, &send), [(known, 25_000, false)]);
        assert_eq!(fees_of(&rows, &sweep), [(known, 10_000, false)]);
        assert!(fees_of(&rows, &step).is_empty());
    }

    /// A transaction and its outputs for the funding-step folding tests.
    fn funding_base(txid: &[u8], id: i64, delta: i64, history: HistoryCompleteness) -> TxBase {
        let mut base = tx_base_for_history();
        base.txid = txid.to_vec();
        base.transaction_id = id;
        base.spent_orchard_note = false;
        base.fee = None;
        base.account_balance_delta = delta;
        base.total_spent = 1_000_000;
        base.total_received = 1_000_000 - delta.unsigned_abs();
        base.attach_history(history);
        base
    }

    fn funding_output(txid: &[u8], uuid: &[u8], to_own: bool, scope: Option<i64>) -> TxOutput {
        TxOutput {
            txid: txid.to_vec(),
            output_pool: TRANSPARENT_POOL,
            output_index: 0,
            from_account_uuid: Some(uuid.to_vec()),
            to_account_uuid: to_own.then(|| uuid.to_vec()),
            to_address: None,
            sent_to_address: None,
            transparent_receiver_address: None,
            to_key_scope: scope,
            value: 490_000,
            memo: None,
            note_version: None,
        }
    }

    fn known_fee_history(fee: u64) -> HistoryCompleteness {
        HistoryCompleteness {
            inferred_outgoing: None,
            has_transparent_outputs: None,
            details_complete: true,
            provisional: false,
            classification: Some(HistoryClassification::Reconstructed),
            effects_settled: true,
            fee: Fee::Known(fee),
            whole_fee: None,
            sole_transparent_funder: false,
            inferred_payment: None,
        }
    }

    /// The fee and net-change flag of each row of `txid`.
    fn fees_of(rows: &[TransactionInfo], txid: &[u8]) -> Vec<(TransactionFeeState, u64, bool)> {
        rows.iter()
            .filter(|row| row.txid_hex == hex::encode(txid))
            .map(|row| (row.fee_state, row.fee, row.amount_is_net_change))
            .collect()
    }

    /// A step folds only into a send that shows a sent row with a known fee:
    /// a sweep to the account's own internal address shows no row to carry
    /// it, and a send whose own fee is unknown would hide it in its unknown
    /// total. The step then keeps its own fee row.
    #[test]
    fn a_funding_step_folds_only_into_a_send_that_shows_its_fee() {
        let uuid = test_account_uuid().as_bytes().to_vec();
        let (step, send) = (fake_txid(0xA1).to_vec(), fake_txid(0xA2).to_vec());
        let spends = HashMap::from([(step.clone(), vec![send.clone()])]);
        let rows = |send_history: HistoryCompleteness, send_to_own: bool| {
            let bases = [
                funding_base(&step, 1, -10_000, known_fee_history(10_000)),
                funding_base(&send, 2, -500_000, send_history),
            ];
            let outputs = HashMap::from([
                (
                    step.clone(),
                    vec![funding_output(
                        &step,
                        &uuid,
                        true,
                        Some(EPHEMERAL_KEY_SCOPE),
                    )],
                ),
                (
                    send.clone(),
                    vec![funding_output(
                        &send,
                        &uuid,
                        send_to_own,
                        send_to_own.then_some(1),
                    )],
                ),
            ]);
            assemble_history(&bases, &outputs, &spends, &uuid, None)
        };
        let known = TransactionFeeState::Known;

        let swept = rows(known_fee_history(10_000), true);
        assert!(fees_of(&swept, &send).is_empty(), "a sweep has no row");
        assert_eq!(fees_of(&swept, &step), [(known, 10_000, true)]);

        let unknown = rows(
            HistoryCompleteness {
                fee: Fee::Unknown,
                ..known_fee_history(0)
            },
            false,
        );
        assert_eq!(
            fees_of(&unknown, &send),
            [(TransactionFeeState::Unknown, 0, false)]
        );
        assert_eq!(fees_of(&unknown, &step), [(known, 10_000, true)]);

        let carried = rows(known_fee_history(10_000), false);
        assert_eq!(fees_of(&carried, &send), [(known, 20_000, false)]);
        assert!(fees_of(&carried, &step).is_empty());
    }

    /// A send known only as its balance change carries a folded step's fee
    /// as one that shows its payment does.
    #[test]
    fn a_funding_steps_fee_joins_a_send_known_only_as_its_balance_change() {
        let uuid = test_account_uuid().as_bytes().to_vec();
        let (step, send) = (fake_txid(0xA3).to_vec(), fake_txid(0xA4).to_vec());
        let spends = HashMap::from([(step.clone(), vec![send.clone()])]);
        let outputs = HashMap::from([(
            step.clone(),
            vec![funding_output(
                &step,
                &uuid,
                true,
                Some(EPHEMERAL_KEY_SCOPE),
            )],
        )]);
        let provisional = HistoryCompleteness {
            details_complete: false,
            provisional: true,
            ..known_fee_history(10_000)
        };
        let rows = |send_history| {
            let bases = [
                funding_base(&step, 1, -10_000, known_fee_history(10_000)),
                funding_base(&send, 2, -500_000, send_history),
            ];
            let rows = assemble_history(&bases, &outputs, &spends, &uuid, None);
            assert!(fees_of(&rows, &step).is_empty());
            fees_of(&rows, &send)
        };

        // The account's own fee is subtracted from its debit: a send of the
        // rest, with both fees.
        assert_eq!(
            rows(provisional),
            [(TransactionFeeState::Known, 20_000, false)]
        );
        // Only the whole fee is known: its net change, with both fees.
        assert_eq!(
            rows(HistoryCompleteness {
                fee: Fee::Unknown,
                whole_fee: Some(10_000),
                ..provisional
            }),
            [(TransactionFeeState::WholeTransaction, 20_000, true)]
        );
    }

    /// When an earlier send's funding output was spent again, the mined
    /// resend is the send the step funded, not the attempt that never mined,
    /// whether that attempt has expired yet or not.
    #[test]
    fn a_funding_step_folds_into_its_mined_send_over_an_unmined_attempt() {
        for expired_unmined in [true, false] {
            assert_a_funding_step_folds_into_the_mined_resend(expired_unmined);
        }
    }

    fn assert_a_funding_step_folds_into_the_mined_resend(expired_unmined: bool) {
        let uuid = test_account_uuid().as_bytes().to_vec();
        let (step, expired, resend) = (
            fake_txid(0xA5).to_vec(),
            fake_txid(0xA6).to_vec(),
            fake_txid(0xA7).to_vec(),
        );
        let mut attempt = funding_base(&expired, 2, -500_000, known_fee_history(10_000));
        attempt.mined_height = None;
        attempt.expired_unmined = expired_unmined;
        let bases = [
            funding_base(&step, 1, -10_000, known_fee_history(10_000)),
            attempt,
            funding_base(&resend, 3, -500_000, known_fee_history(10_000)),
        ];
        let outputs = HashMap::from([
            (
                step.clone(),
                vec![funding_output(
                    &step,
                    &uuid,
                    true,
                    Some(EPHEMERAL_KEY_SCOPE),
                )],
            ),
            (
                expired.clone(),
                vec![funding_output(&expired, &uuid, false, None)],
            ),
            (
                resend.clone(),
                vec![funding_output(&resend, &uuid, false, None)],
            ),
        ]);
        let spends = HashMap::from([(step.clone(), vec![expired.clone(), resend.clone()])]);

        let rows = assemble_history(&bases, &outputs, &spends, &uuid, None);

        let known = TransactionFeeState::Known;
        let case = format!("attempt expired: {expired_unmined}");
        assert_eq!(fees_of(&rows, &resend), [(known, 20_000, false)], "{case}");
        assert_eq!(fees_of(&rows, &expired), [(known, 10_000, false)], "{case}");
        assert!(fees_of(&rows, &step).is_empty(), "{case}");
    }

    /// A funding step no send carries that moved more than its own fee is a
    /// debit like any other: with complete details the rest of its change is
    /// what it paid, and without them its whole change is a net change.
    #[test]
    fn an_unmatched_funding_step_shows_what_it_paid_beyond_its_fee() {
        let uuid = test_account_uuid().as_bytes().to_vec();
        let step = fake_txid(0xA8).to_vec();
        let outputs = HashMap::from([(
            step.clone(),
            vec![funding_output(
                &step,
                &uuid,
                true,
                Some(EPHEMERAL_KEY_SCOPE),
            )],
        )]);
        let row = |history| {
            let bases = [funding_base(&step, 1, -30_000, history)];
            let rows = assemble_history(&bases, &outputs, &EphemeralSpends::new(), &uuid, None);
            assert_eq!(rows.len(), 1);
            let row = &rows[0];
            (
                row.tx_kind.clone(),
                row.display_amount,
                row.fee,
                row.amount_is_net_change,
            )
        };

        assert_eq!(
            row(known_fee_history(10_000)),
            ("sent".to_string(), 20_000, 10_000, false)
        );
        assert_eq!(
            row(HistoryCompleteness {
                details_complete: false,
                ..known_fee_history(10_000)
            }),
            ("sent".to_string(), 30_000, 10_000, true)
        );
    }

    /// A privately recovered funding step that also moved funds to one of
    /// the account's visible addresses is no pure funding step: it keeps its
    /// rows and its fee, and the send that spends its ephemeral output shows
    /// only its own fee.
    #[test]
    fn a_funding_step_that_also_moves_funds_to_a_visible_address_keeps_its_rows() {
        let uuid = test_account_uuid().as_bytes().to_vec();
        let (step, send) = (fake_txid(0xA9).to_vec(), fake_txid(0xAA).to_vec());
        let recovered = HistoryCompleteness {
            whole_fee: Some(10_000),
            sole_transparent_funder: true,
            ..known_fee_history(10_000)
        };
        let bases = [
            funding_base(&step, 1, -10_000, recovered),
            funding_base(&send, 2, -500_000, known_fee_history(10_000)),
        ];
        // Private recovery does not record who funded the step's outputs.
        let unattributed = |scope, value, index| TxOutput {
            from_account_uuid: None,
            to_key_scope: Some(scope),
            value,
            output_index: index,
            ..funding_output(&step, &uuid, true, None)
        };
        let outputs = HashMap::from([
            (
                step.clone(),
                vec![
                    unattributed(EPHEMERAL_KEY_SCOPE, 490_000, 0),
                    unattributed(0, 100_000, 1),
                ],
            ),
            (
                send.clone(),
                vec![funding_output(&send, &uuid, false, None)],
            ),
        ]);
        let spends = HashMap::from([(step.clone(), vec![send.clone()])]);

        let rows = assemble_history(&bases, &outputs, &spends, &uuid, None);

        let step_rows = rows
            .iter()
            .filter(|row| row.txid_hex == hex::encode(&step))
            .map(|row| row.fee)
            .collect::<Vec<_>>();
        assert!(!step_rows.is_empty(), "the step keeps its rows");
        assert!(
            step_rows.iter().all(|&fee| fee == 10_000),
            "with its own fee: {step_rows:?}"
        );
        assert_eq!(
            fees_of(&rows, &send),
            [(TransactionFeeState::Known, 10_000, false)]
        );
    }

    /// Only an output to an ephemeral address makes a transaction a funding
    /// step: a consolidation into the account's internal transparent change
    /// stays hidden, as before.
    #[test]
    fn an_internal_consolidation_is_no_funding_step() {
        let uuid = test_account_uuid().as_bytes().to_vec();
        let txid = fake_txid(0xA8).to_vec();
        let rows = |scope| {
            let bases = [funding_base(&txid, 1, -10_000, known_fee_history(10_000))];
            let outputs = HashMap::from([(
                txid.clone(),
                vec![funding_output(&txid, &uuid, true, Some(scope))],
            )]);
            assemble_history(&bases, &outputs, &EphemeralSpends::new(), &uuid, None)
        };

        assert!(rows(1).is_empty());
        assert_eq!(
            fees_of(&rows(EPHEMERAL_KEY_SCOPE), &txid),
            [(TransactionFeeState::Known, 10_000, true)]
        );
    }

    /// The library's view of a settled transaction whose balance change is
    /// the whole fee, the account's own fee unknown: the account spent in
    /// `spent` pools and has `spent_note_count` recorded inputs, and the
    /// recovered metadata counts `metadata_inputs` transparent inputs.
    fn whole_fee_movement(
        spent: &[PoolType],
        spent_note_count: u32,
        metadata_inputs: u32,
    ) -> HistoryCompleteness {
        use zcash_client_backend::data_api::transparent_ledger::{EffectCompleteness, PoolEffect};

        let mut details = shared_funding_details(exact_whole_fee());
        if let Some(evidence) = details.transaction_metadata.as_mut() {
            evidence.metadata.transparent_input_count = metadata_inputs;
            evidence.metadata.has_shielded_components =
                spent.iter().any(|pool| *pool != PoolType::Transparent);
        }
        details.effects = spent
            .iter()
            .map(|&pool| PoolEffect {
                pool,
                received: Zatoshis::ZERO,
                spent: Zatoshis::from_u64(100_000).unwrap(),
                completeness: EffectCompleteness::Complete,
            })
            .collect();
        HistoryCompleteness::of(&details, spent_note_count)
    }

    /// A balance change of exactly the whole fee shows that only the fee left
    /// the account, so that a funding step folds, only when the account alone
    /// funded a transparent-only transaction: the metadata counts its own
    /// inputs and rules out shielded components. A jointly funded
    /// transaction (A puts in 110,000 and B 100,000; 100,000 goes to A's
    /// ephemeral address, 100,000 to someone else, 10,000 is the fee) changes
    /// A's balance by the fee too, yet B may have paid A while A paid someone
    /// else.
    #[test]
    fn only_the_sole_transparent_funder_proves_a_whole_fee_funding_step() {
        let uuid = test_account_uuid().as_bytes().to_vec();
        let step = fake_txid(0xAB).to_vec();
        let outputs = [funding_output(
            &step,
            &uuid,
            true,
            Some(EPHEMERAL_KEY_SCOPE),
        )];
        let proves = |spent: &[PoolType], spent_note_count, metadata_inputs| {
            let history = whole_fee_movement(spent, spent_note_count, metadata_inputs);
            let base = funding_base(&step, 1, -(WHOLE_FEE as i64), history);
            let pure =
                is_pure_funding_step(&base, &summarize_activity_outputs(&base, &outputs, &uuid));
            assert_eq!(
                history.exact_fee().is_some(),
                pure,
                "{spent:?}: {spent_note_count} own inputs, {metadata_inputs} in the metadata"
            );
            assert_eq!(history.shown_fee(), Fee::Whole(WHOLE_FEE), "still shown");
            pure
        };
        assert!(proves(&[PoolType::Transparent], 2, 2));
        assert!(!proves(&[], 0, 0), "no owned input proves no funding");
        assert!(
            !proves(&[PoolType::Transparent], 1, 2),
            "another party funded a transparent input"
        );
        assert!(
            !proves(&[PoolType::ORCHARD], 1, 0),
            "shielded inputs may include another party's contribution"
        );
        assert!(
            !proves(&[PoolType::ORCHARD], 1, 1),
            "a transparent input is not the account's"
        );
        assert!(
            !proves(&[PoolType::Transparent, PoolType::ORCHARD], 2, 1),
            "the account's own transparent inputs are not counted apart"
        );
    }

    #[test]
    fn detail_sent_to_transparent_prefers_external_recipient_over_shielded_change() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD7);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            1_265_000,
            1_150_000,
            false,
            Some("2026-04-28T17:05:00Z"),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            150_000,
            false,
            Some("t-ephemeral"),
            Some(2),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-change"),
            Some(1),
        );
        insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            None,
            100_000,
            false,
            Some("t-recipient"),
            None,
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs[0].amount_zatoshi, 100_000);
        assert_eq!(got.outputs[0].pool, "transparent");
    }

    #[test]
    fn detail_sent_to_own_transparent_receiver_uses_sent_note_address() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD8);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            1,
            Some(1_000_100),
            -15_000,
            6_980_000,
            6_965_000,
            false,
            Some("2026-05-15T06:11:44Z"),
        );
        let recipient_output_index = insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            1_200_000,
            false,
            Some("u-merged-own-transparent-receiver"),
            Some(0),
        );
        set_cached_transparent_receiver_address(
            &db,
            account,
            "u-merged-own-transparent-receiver",
            "t-recipient",
        );
        insert_sent_note(
            &db,
            &txid,
            0,
            recipient_output_index,
            account,
            None,
            Some("t-recipient"),
            1_200_000,
            None,
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            5_765_000,
            true,
            None,
            None,
            Some(&[0xF6]),
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("t-recipient"));
        assert_eq!(got.outputs[0].amount_zatoshi, 1_200_000);
        assert_eq!(got.outputs[0].pool, "transparent");
    }

    #[test]
    fn detail_sent_to_transparent_pool_prefers_cached_transparent_receiver() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD9);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -15_000,
            18_990_000,
            18_975_000,
            false,
            Some("2026-05-14T13:14:15Z"),
        );
        let recipient_output_index = insert_output_with_address(
            &db,
            &txid,
            0,
            Some(account),
            Some(account),
            11_000_000,
            false,
            Some("u-known-receiver"),
            Some(0),
        );
        set_cached_transparent_receiver_address(
            &db,
            account,
            "u-known-receiver",
            "t-known-receiver",
        );
        insert_sent_note(
            &db,
            &txid,
            0,
            recipient_output_index,
            account,
            None,
            Some("u-known-receiver"),
            11_000_000,
            None,
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            7_975_000,
            true,
            None,
            None,
            Some(&[0xF6]),
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address.as_deref(), Some("t-known-receiver"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("t-known-receiver"));
        assert_eq!(got.outputs[0].amount_zatoshi, 11_000_000);
        assert_eq!(got.outputs[0].pool, "transparent");
    }

    #[test]
    fn detail_received_row_does_not_invent_from_address() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD2);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            Some("2026-04-28T17:01:00Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            None,
            Some(account),
            2_000_000,
            false,
            Some("u-my-receiver"),
            Some(0),
            Some(b"incoming memo"),
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "received",
        )
        .unwrap();

        assert_eq!(got.tx_kind, "received");
        assert_eq!(got.primary_address, None);
        assert_eq!(got.source_address, None);
        assert_eq!(got.source_pool.as_deref(), Some("unknown"));
        assert_eq!(got.memo.as_deref(), Some("incoming memo"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].address.as_deref(), Some("u-my-receiver"));
    }

    #[test]
    fn detail_received_transparent_output_surfaces_bare_t_address() {
        // End-to-end guard for BUG-1: a received transparent output stores the
        // account unified address in to_address, but the detail must surface
        // the bare t-address (the cached transparent receiver). Exercises the
        // read_outputs_for_tx subquery + the detail_address received pool-0
        // branch together (the standalone detail_address unit test only covers
        // the in-memory half).
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD3);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            Some("2026-06-20T10:00:00Z"),
        );
        insert_output_with_address(
            &db,
            &txid,
            0, // transparent pool
            None,
            Some(account),
            2_000_000,
            false,
            Some("u-my-receiver"),
            Some(0),
        );
        set_cached_transparent_receiver_address(&db, account, "u-my-receiver", "t-my-receiver");

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "received",
        )
        .unwrap();

        assert_eq!(got.tx_kind, "received");
        assert_eq!(got.outputs.len(), 1);
        // The fix: the bare t-address, not the unified address.
        assert_eq!(got.outputs[0].address.as_deref(), Some("t-my-receiver"));
        assert_eq!(got.outputs[0].pool, "transparent");
    }

    #[test]
    fn detail_received_row_recovers_transparent_source_from_raw_tx() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD7);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            Some("2026-04-28T17:01:00Z"),
        );
        let raw = transparent_source_raw_tx();
        set_history_tx_raw(&db, account, &txid, &raw);
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            None,
            Some(account),
            2_000_000,
            false,
            Some("u-my-receiver"),
            Some(0),
            Some(b"incoming memo"),
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "received",
        )
        .unwrap();

        let expected_source = transparent_source_test_address();
        assert_eq!(got.primary_address, None);
        assert_eq!(
            got.source_address.as_deref(),
            Some(expected_source.as_str())
        );
        assert_eq!(got.source_pool.as_deref(), Some("transparent"));
        assert_eq!(got.outputs.len(), 1);
    }

    #[test]
    fn detail_receiving_row_uses_received_outputs() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD6);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            1,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            None,
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            None,
            Some(account),
            2_000_000,
            false,
            Some("u-my-pending-receiver"),
            Some(0),
            Some(b"pending incoming memo"),
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "receiving",
        )
        .unwrap();

        assert_eq!(got.tx_kind, "receiving");
        assert_eq!(got.primary_address, None);
        assert_eq!(got.source_address, None);
        assert_eq!(got.source_pool.as_deref(), Some("unknown"));
        assert_eq!(got.memo.as_deref(), Some("pending incoming memo"));
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(
            got.outputs[0].address.as_deref(),
            Some("u-my-pending-receiver")
        );
    }

    #[test]
    fn detail_separates_same_account_self_send_by_kind() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD3);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            1_010_000,
            1_000_000,
            false,
            Some("2026-04-28T17:02:00Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-self"),
            Some(0),
            Some(b"self memo"),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            500_000,
            true,
            Some("u-change"),
            Some(1),
        );

        let sent = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();
        let received = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "received",
        )
        .unwrap();

        assert_eq!(sent.primary_address.as_deref(), Some("u-self"));
        assert_eq!(sent.memo.as_deref(), Some("self memo"));
        assert_eq!(sent.outputs.len(), 1);
        assert_eq!(sent.outputs[0].amount_zatoshi, 1_000_000);
        assert_eq!(received.primary_address, None);
        assert_eq!(received.memo.as_deref(), Some("self memo"));
        assert_eq!(received.outputs.len(), 1);
        assert_eq!(received.outputs[0].amount_zatoshi, 1_000_000);
    }

    #[test]
    fn detail_hides_change_only_outputs_and_empty_memos() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD4);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            1_010_000,
            1_000_000,
            false,
            Some("2026-04-28T17:03:00Z"),
        );
        insert_output_with_address_and_memo(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-change"),
            Some(1),
            Some(&[0xF6]),
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "sent",
        )
        .unwrap();

        assert_eq!(got.primary_address, None);
        assert_eq!(got.memo, None);
        assert!(got.outputs.is_empty());
    }

    #[test]
    fn detail_shielding_row_has_no_primary_address() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD5);

        insert_history_tx(
            &db,
            account,
            &txid,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -10_000,
            1_010_000,
            1_000_000,
            true,
            Some("2026-04-28T17:04:00Z"),
        );
        insert_output_with_address(
            &db,
            &txid,
            3,
            Some(account),
            Some(account),
            1_000_000,
            true,
            Some("u-shielded-self"),
            Some(0),
        );

        let got = detail_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            &account.to_string(),
            &hex::encode(txid),
            "shielded",
        )
        .unwrap();

        assert_eq!(got.tx_kind, "shielded");
        assert_eq!(got.primary_address, None);
        assert_eq!(got.outputs.len(), 1);
        assert_eq!(got.outputs[0].amount_zatoshi, 1_000_000);
    }

    #[test]
    fn history_sorts_by_display_timestamp_before_limit() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let older_failed = fake_txid(0xC1);
        let newer_self_send = fake_txid(0xC2);

        insert_history_tx(
            &db,
            account,
            &older_failed,
            None,
            2,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            0,
            false,
            Some("2026-04-28T13:04:00Z"),
        );
        mark_expired_unmined(&db, &older_failed);
        insert_output(
            &db,
            &older_failed,
            0,
            Some(account),
            None,
            10_000_000,
            false,
        );

        insert_history_tx(
            &db,
            account,
            &newer_self_send,
            Some(1_000_000),
            1,
            Some(1_000_100),
            -40_000,
            17_040_000,
            17_000_000,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output_with_address(
            &db,
            &newer_self_send,
            0,
            Some(account),
            Some(account),
            17_000_000,
            false,
            Some("t-newer-self"),
            Some(0),
        );

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 3);
        assert_eq!(got[0].txid_hex, hex::encode(newer_self_send));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[1].txid_hex, hex::encode(newer_self_send));
        assert_eq!(got[1].tx_kind, "received");
        assert_eq!(got[2].txid_hex, hex::encode(older_failed));
        assert!(got[2].expired_unmined);

        let limited = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(limited.len(), 1);
        assert_eq!(limited[0].txid_hex, hex::encode(newer_self_send));
        assert_eq!(limited[0].tx_kind, "sent");
    }

    #[test]
    fn history_prioritizes_unmined_receiving_rows() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let confirmed = fake_txid(0xE1);
        let pending = fake_txid(0xE2);

        insert_history_tx(
            &db,
            account,
            &confirmed,
            Some(1_000_000),
            1,
            Some(1_000_100),
            1_000_000,
            0,
            1_000_000,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output(&db, &confirmed, 3, None, Some(account), 1_000_000, false);

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(1_000_100),
            2_000_000,
            0,
            2_000_000,
            false,
            None,
        );
        insert_output(&db, &pending, 3, None, Some(account), 2_000_000, false);

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(pending));
        assert_eq!(got[0].tx_kind, "receiving");
        assert_eq!(got[0].mined_height, 0);
        assert_eq!(got[0].display_amount, 2_000_000);
    }

    #[test]
    fn history_prioritizes_active_unmined_sent_rows() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let confirmed = fake_txid(0xE3);
        let pending = fake_txid(0xE4);

        insert_history_tx(
            &db,
            account,
            &confirmed,
            Some(1_000_000),
            1,
            Some(1_000_100),
            1_000_000,
            0,
            1_000_000,
            false,
            Some("2026-04-28T16:32:00Z"),
        );
        insert_output(&db, &confirmed, 3, None, Some(account), 1_000_000, false);

        insert_history_tx(
            &db,
            account,
            &pending,
            None,
            0,
            Some(1_000_100),
            -1_010_000,
            1_010_000,
            0,
            false,
            None,
        );
        insert_output(&db, &pending, 3, Some(account), None, 1_000_000, false);

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            Some(1),
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(pending));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].mined_height, 0);
        assert_eq!(got[0].display_amount, 1_000_000);
    }

    /// `expired_unmined` is SQL NULL for an unmined transaction whose expiry
    /// cannot be compared to a scanned height: no `blocks` rows yet (a
    /// hardware wallet that broadcasts before its first scan, as the Ledger
    /// Speculos fixtures do) or no recorded expiry height. Such a row is
    /// pending, not expired, and must not fail the whole history read.
    #[test]
    fn history_reads_unmined_rows_without_a_comparable_expiry() {
        use transparent::{address::TransparentAddress, bundle::OutPoint, bundle::TxOut};
        use zcash_client_backend::{data_api::WalletWrite, wallet::WalletTransparentOutput};
        use zcash_keys::encoding::AddressCodec as _;

        let network = WalletNetwork::Regtest;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let seed = crate::wallet::keys::mnemonic_to_seed(&crate::wallet::keys::generate_mnemonic())
            .unwrap();
        let (uuid, _) =
            crate::wallet::keys::init_db_and_create_account(&path, network, &seed, Some(100), "a")
                .unwrap();
        let address =
            crate::wallet::keys::software_account_transparent_addresses(network, &seed, 0, 1)
                .unwrap()
                .swap_remove(0);
        let address = TransparentAddress::decode(&network, &address).unwrap();
        let output = WalletTransparentOutput::from_parts(
            OutPoint::new([0x51; 32], 0),
            TxOut::new(
                zcash_protocol::value::Zatoshis::const_from_u64(50_000),
                address.script().into(),
            ),
            None,
            None,
            None,
            None,
        )
        .unwrap();
        let mut db = open_wallet_db(&path, network).unwrap();
        db.put_received_transparent_utxo(&output).unwrap();
        drop(db);
        let conn = rusqlite::Connection::open(&path).unwrap();
        let blocks: i64 = conn
            .query_row("SELECT COUNT(*) FROM blocks", [], |row| row.get(0))
            .unwrap();
        assert_eq!(blocks, 0, "the wallet has not scanned a block");

        for expiry_height in [None, Some(140)] {
            conn.execute(
                "UPDATE transactions SET expiry_height = ?1 WHERE txid = ?2",
                rusqlite::params![expiry_height, [0x51u8; 32].as_slice()],
            )
            .unwrap();
            let history = get_transaction_history(&path, network, None, &uuid).unwrap();
            assert_eq!(history.len(), 1, "expiry {expiry_height:?}");
            assert_eq!(history[0].mined_height, 0);
            assert!(!history[0].expired_unmined, "expiry {expiry_height:?}");
            // The receipt reads the same row through its own query, where the
            // expiry is not comparable either: it opens, as pending.
            let detail = get_transaction_detail(
                &path,
                network,
                &uuid,
                &history[0].txid_hex,
                &history[0].tx_kind,
            )
            .unwrap_or_else(|e| panic!("expiry {expiry_height:?}: {e}"));
            assert_eq!(detail.tx_kind, history[0].tx_kind);
            assert_eq!(
                detail
                    .outputs
                    .iter()
                    .map(|output| output.amount_zatoshi)
                    .collect::<Vec<_>>(),
                [50_000],
                "expiry {expiry_height:?}"
            );
        }
    }

    #[test]
    fn history_accepts_unmined_tx_with_null_tx_index() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD1);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            0,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            0,
            false,
            Some("2026-04-28T13:04:00Z"),
        );
        clear_tx_index(&db, &txid);
        insert_output(&db, &txid, 0, Some(account), None, 10_000_000, false);

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "sent");
    }

    #[test]
    fn history_shows_unmined_sent_when_output_metadata_missing() {
        let db = fresh_history_db();
        let account = test_account_uuid();
        let txid = fake_txid(0xD2);

        insert_history_tx(
            &db,
            account,
            &txid,
            None,
            0,
            Some(1_000_100),
            -10_010_000,
            10_010_000,
            9_000_000,
            false,
            Some("2026-04-28T13:04:00Z"),
        );
        set_history_fee(&db, &txid, 10_000);
        insert_output(&db, &txid, 3, Some(account), Some(account), 9_000_000, true);

        let got = history_from_fixture(
            db.path().to_str().unwrap(),
            WalletNetwork::Test,
            None,
            &account.to_string(),
        )
        .unwrap();

        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_hex, hex::encode(txid));
        assert_eq!(got[0].tx_kind, "sent");
        assert_eq!(got[0].display_amount, 10_000_000);
        assert_eq!(got[0].mined_height, 0);
    }

    #[test]
    fn resubmit_excludes_mined_txs() {
        // A tx with `mined_height IS NOT NULL` is already on-chain;
        // resubmitting would be pointless at best and could surface a
        // confusing rejection from lightwalletd.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x01),
            Some(&fake_raw()),
            Some(1_000_000), // mined_height set → mined
            Some(1_000_100),
            -5_000,
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 900_000).unwrap();
        assert!(
            got.is_empty(),
            "mined tx must not be a resubmit candidate, got {got:?}",
            got = got.len(),
        );
    }

    #[test]
    fn resubmit_excludes_expired_txs() {
        // `expiry_height > current_height` is the network's
        // still-relayable check for expiring transactions. A tx whose
        // expiry equals the current height is already past the window.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x02),
            Some(&fake_raw()),
            None,
            Some(1_000_000), // expiry == current → expired
            -5_000,
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty(), "tx with expiry==current must be excluded");

        // Walk the boundary: one block below current is definitely expired.
        let db2 = fresh_db();
        insert_row(
            &db2,
            &fake_txid(0x02),
            Some(&fake_raw()),
            None,
            Some(999_999),
            -5_000,
        );
        let got2 = get_resubmittable_txs(db2.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got2.is_empty(), "tx with expiry<current must be excluded");
    }

    #[test]
    fn resubmit_excludes_received_txs() {
        // `account_balance_delta >= 0` means the account gained or broke
        // even on this tx — it's an incoming transfer we just happened to
        // have raw bytes for (e.g. re-read from lightwalletd during a
        // rescan). Resubmitting "our" received txs back to the network
        // would be meaningless.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x03),
            Some(&fake_raw()),
            None,
            Some(1_000_100),
            5_000, // positive delta → inbound
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty(), "received-only tx must be excluded");

        // Also the zero case: a break-even tx shouldn't show up either
        // (it's still not an "outbound" the wallet needs to keep alive).
        let db2 = fresh_db();
        insert_row(
            &db2,
            &fake_txid(0x03),
            Some(&fake_raw()),
            None,
            Some(1_000_100),
            0,
        );
        let got2 = get_resubmittable_txs(db2.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got2.is_empty(), "zero-delta tx must be excluded");
    }

    #[test]
    fn resubmit_excludes_raw_null_txs() {
        // `raw IS NULL` means we don't have bytes to broadcast. This row
        // exists because sync learned about the tx via decrypt-and-store
        // without the raw bundle, and there's nothing we can resubmit.
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x04),
            None, // raw NULL
            None,
            Some(1_000_100),
            -5_000,
        );
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty(), "raw-null tx must be excluded");
    }

    #[test]
    fn resubmit_includes_valid_outbound_pending() {
        // The happy path: unmined, inside expiry, outbound, raw present.
        let db = fresh_db();
        let txid = fake_txid(0x05);
        let raw = fake_raw();
        insert_row(&db, &txid, Some(&raw), None, Some(1_000_100), -5_000);
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert_eq!(got.len(), 1, "outbound pending tx must appear exactly once");
        assert_eq!(got[0].txid_bytes, txid.to_vec());
        assert_eq!(got[0].raw_tx, raw);
        assert_eq!(got[0].expiry_height, 1_000_100);
    }

    #[test]
    fn resubmit_falls_back_when_preflight_schema_is_unavailable() {
        let (db, txid) = (fresh_db(), fake_txid(0x08));
        insert_row(&db, &txid, Some(&fake_raw()), None, Some(1_000_100), -5_000);
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute("DROP TRIGGER vizor_preserve_mined_transaction", [])
            .unwrap();
        conn.execute("ALTER TABLE transactions DROP COLUMN mined_height", [])
            .unwrap();
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert_eq!(got[0].txid_bytes, txid);
    }

    #[test]
    fn resubmit_excludes_only_deferred_txids() {
        let db = fresh_db();
        let deferred_txid = fake_txid(0x15);
        let pending_txid = fake_txid(0x16);
        let raw = fake_raw();
        insert_row(
            &db,
            &deferred_txid,
            Some(&raw),
            None,
            Some(1_000_100),
            -5_000,
        );
        insert_row(
            &db,
            &pending_txid,
            Some(&raw),
            None,
            Some(1_000_100),
            -5_000,
        );
        // The metadata query's stand-in view still reports raw bytes, but the
        // backing lookup cannot return them. Exclusion must happen before the
        // raw transaction query.
        rusqlite::Connection::open(db.path())
            .unwrap()
            .execute(
                "UPDATE transactions SET raw = NULL WHERE txid = ?1",
                [&deferred_txid],
            )
            .unwrap();

        let excluded = HashSet::from([deferred_txid.to_vec()]);
        let got =
            get_resubmittable_txs_excluding(db.path().to_str().unwrap(), 1_000_000, &excluded)
                .unwrap();
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].txid_bytes, pending_txid);
    }

    #[test]
    fn resubmit_includes_no_expiry_outbound_pending() {
        // Expiry height 0 is the protocol no-expiry marker, so these
        // transactions must keep participating in auto-resubmit across
        // restarts and long migration windows.
        let db = fresh_db();
        let txid = fake_txid(0x07);
        let raw = fake_raw();
        insert_row(&db, &txid, Some(&raw), None, Some(0), -5_000);

        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert_eq!(
            got.len(),
            1,
            "no-expiry outbound pending tx must be resubmittable"
        );
        assert_eq!(got[0].txid_bytes, txid.to_vec());
        assert_eq!(got[0].raw_tx, raw);
        assert_eq!(got[0].expiry_height, 0);
    }

    #[test]
    fn resubmit_dedupes_multi_account_rows() {
        // A tx that touches two of the wallet's own accounts shows up as
        // two rows in `v_transactions`. `SELECT DISTINCT txid, raw,
        // expiry_height` should collapse that to one broadcast — double-
        // sending identical bytes would be a regression.
        let db = fresh_db();
        let txid = fake_txid(0x06);
        let raw = fake_raw();
        // Two rows for the same tx, different account-level deltas, both
        // still outbound at the row level (account-internal transfer with
        // a net negative for both of the wallet's participating accounts
        // after fees — contrived but possible).
        insert_row(&db, &txid, Some(&raw), None, Some(1_000_100), -3_000);
        insert_row(&db, &txid, Some(&raw), None, Some(1_000_100), -2_000);

        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert_eq!(
            got.len(),
            1,
            "multi-account rows with same (txid, raw, expiry) must dedupe",
        );
    }

    #[test]
    fn resubmit_returns_empty_when_table_empty() {
        // Baseline: an empty table must return `Ok(vec![])`, not an
        // error. `resubmit_pending_transactions` relies on this to
        // decide the "nothing to do" case.
        let db = fresh_db();
        let got = get_resubmittable_txs(db.path().to_str().unwrap(), 1_000_000).unwrap();
        assert!(got.is_empty());
    }
}
