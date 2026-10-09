//! Final transparent-input authorization for every hardware broadcast path.
//!
//! Signing can outlive recovery authority. Validate using the library's input
//! selector, then keep a SQLite writer reservation until the SendTransaction
//! request has been handed to the transport. This prevents policy changes,
//! rewinds, or evidence withdrawal between validation and submission,
//! including writes from another connection. Once the request has left, a
//! later write can no longer recall it, so the reservation ends there rather
//! than at the response. A request that never finishes leaving keeps the
//! reservation through the bounded attempt. No transaction is stored here:
//! dropping the connection rolls back the reservation on success, failure, or
//! cancellation.
//!
//! Under a private policy, inputs are checked for the block after the
//! wallet's own tip, the only target private authority covers, rather than
//! after lightwalletd's: a block that lands while a device signs must not
//! refuse the signature. The unseen blocks can only have spent an input
//! elsewhere or removed its receive, and the node rejects either, so nothing
//! is lost; maturity and confirmations only get stricter at the lower target.
//! Until private recovery covers a block the wallet has scanned, the refusal
//! is [`DispatchRefusal::CatchingUp`]: [`await_authority`] waits for it, and
//! callers keep the signed transaction for a retry rather than releasing it.

use std::{
    fmt,
    future::Future,
    time::{Duration, Instant},
};

use futures::future::{select, Either};

use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::data_api::{
    transparent_ledger::{
        CandidateBlocker, RecoveryBlocker, TransparentLedgerMode, TransparentLedgerRead,
    },
    WalletRead,
};
use zcash_client_sqlite::{util::SystemClock, AccountUuid, WalletDb};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
    sync_engine::{
        enhancement::{selects_private_recovery, transparent_ledger_mode_for},
        transparent_ledger::recovery_hold,
        Dispatched,
    },
};

/// How long a broadcast waits for private recovery to cover the wallet's
/// latest block before it reports the refusal as retryable. A sync scans a
/// new block and runs the private pass after it, so this spans the usual
/// catch-up.
pub(crate) const CATCH_UP_WAIT: Duration = Duration::from_secs(30);

/// How often a broadcast waiting for private recovery checks again.
const CATCH_UP_POLL: Duration = Duration::from_millis(500);

/// Why a transparent broadcast was withheld.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum DispatchRefusal {
    /// Private recovery has not yet covered the wallet's latest block. The
    /// signed transaction is authorized once it does, so callers keep it for
    /// a retry.
    CatchingUp(String),
    /// Anything else: a revoked or unreadable policy, quarantine, a hold,
    /// withdrawn, unknown, spent or immature inputs. Retrying the same
    /// transaction will not help.
    Refused(String),
}

impl fmt::Display for DispatchRefusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DispatchRefusal::CatchingUp(message) | DispatchRefusal::Refused(message) => {
                f.write_str(message)
            }
        }
    }
}

impl From<DispatchRefusal> for String {
    fn from(refusal: DispatchRefusal) -> Self {
        refusal.to_string()
    }
}

/// Reservations held at least this long are logged, as evidence for whether
/// the remaining writer contention needs a narrower lock.
const SLOW_RESERVATION: Duration = Duration::from_millis(250);

/// Waits up to [`CATCH_UP_WAIT`] for `tx`'s transparent inputs to be
/// authorized, without holding a reservation, so a sync can write meanwhile.
/// Returns at once when they are, or when the refusal is not
/// [`DispatchRefusal::CatchingUp`]. [`dispatch`] still decides under its
/// reservation.
pub(crate) async fn await_authority(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
    network_tip: u64,
) -> Result<(), DispatchRefusal> {
    await_authority_within(db_path, network, tx, earlier, network_tip, CATCH_UP_WAIT).await
}

/// [`await_authority`], waiting at most `wait`.
pub(crate) async fn await_authority_within(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
    network_tip: u64,
    wait: Duration,
) -> Result<(), DispatchRefusal> {
    if tx.transparent_bundle().is_none_or(|b| b.vin.is_empty()) {
        return Ok(());
    }
    let deadline = Instant::now() + wait;
    loop {
        match authorize(db_path, network, tx, earlier, network_tip) {
            Ok(_reservation) => return Ok(()),
            Err(DispatchRefusal::CatchingUp(message)) => {
                if Instant::now() >= deadline {
                    return Err(DispatchRefusal::CatchingUp(message));
                }
            }
            Err(refused) => return Err(refused),
        }
        tokio::time::sleep(CATCH_UP_POLL).await;
    }
}

/// Authorizes `tx` immediately before starting `send`. Earlier finalized batch
/// transactions may supply local chained inputs (TEX); the output must exist.
/// Unknown, withdrawn, competing-spent, immature, or unauthorized wallet inputs fail
/// before `send` is started. Exact stored retries may consume their own recorded inputs.
/// Shielded-only transactions require no reservation.
///
/// `send` receives a [`Dispatched`] signal to fire once its request has been
/// handed to the transport; the reservation ends then, or when the send
/// finishes or is cancelled if it never fires.
pub(crate) async fn dispatch<T, F>(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
    network_tip: u64,
    send: impl FnOnce(Dispatched) -> F,
) -> Result<T, DispatchRefusal>
where
    F: Future<Output = T>,
{
    let inputs = tx.transparent_bundle().map_or(&[][..], |b| &b.vin[..]);
    if inputs.is_empty() {
        return Ok(send(Dispatched::unobserved()).await);
    }
    let (db, reserved) = authorize(db_path, network, tx, earlier, network_tip)?;

    let (dispatched, signal) = Dispatched::new();
    let mut send = std::pin::pin!(send(dispatched));
    let release = |db| {
        drop(db);
        let held = reserved.elapsed();
        if held >= SLOW_RESERVATION {
            log::info!(
                "Transparent broadcast reservation held for {} ms",
                held.as_millis()
            );
        }
    };
    let result = match select(send.as_mut(), signal).await {
        Either::Left((result, _)) => {
            release(db);
            result
        }
        // The request has left: a later write can no longer recall it.
        Either::Right((Ok(()), _)) => {
            release(db);
            send.await
        }
        // The request was dropped before it finished leaving; hold until the
        // bounded attempt ends.
        Either::Right((Err(_), _)) => {
            let result = send.await;
            release(db);
            result
        }
    };
    Ok(result)
}

type ReservedWallet = WalletDb<rusqlite::Connection, WalletNetwork, SystemClock, OsRng>;

/// Checks `tx`'s transparent inputs under a new writer reservation, which the
/// returned handle holds until it is dropped.
fn authorize(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
    network_tip: u64,
) -> Result<(ReservedWallet, Instant), DispatchRefusal> {
    let refused = |message: String| DispatchRefusal::Refused(message);
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT).map_err(refused)?;
    conn.execute_batch("BEGIN IMMEDIATE")
        .map_err(|e| refused(format!("Reserve transparent broadcast authority: {e}")))?;
    let reserved = Instant::now();
    let db = WalletDb::from_connection(conn, network, SystemClock, OsRng)
        .with_transparent_ledger_mode(transparent_ledger_mode_for(db_path, network));
    // Read under the reservation, so the durable policy the library resolves
    // the handle under is the one authorized. Reading the mode also rejects
    // an unreadable or incompatible policy.
    let mode = db
        .transparent_ledger_mode()
        .map_err(|e| refused(format!("Transparent broadcast authority unavailable: {e}")))?;
    let Some(tip) = db.chain_height().map_err(|e| refused(e.to_string()))? else {
        return Err(refused(
            "Transparent broadcast authority unavailable: chain height unknown".into(),
        ));
    };
    let target = match mode {
        // Private authority covers exactly the block after the wallet's tip.
        TransparentLedgerMode::PrivateRequired => tip + 1,
        TransparentLedgerMode::Public => u32::try_from(network_tip)
            .ok()
            .and_then(|h| h.checked_add(1))
            .map(BlockHeight::from_u32)
            .ok_or_else(|| refused("Transparent broadcast target exceeds u32".into()))?,
    };
    match db.check_transparent_transaction_inputs(tx, earlier, target.into()) {
        Ok(()) => Ok((db, reserved)),
        Err(error) => {
            let message = format!("Transparent broadcast authority unavailable: {error}");
            if mode == TransparentLedgerMode::PrivateRequired
                && catching_up(&db, db_path, network, tx, earlier)
            {
                Err(DispatchRefusal::CatchingUp(message))
            } else {
                Err(refused(message))
            }
        }
    }
}

/// Whether private authority is missing for `tx`'s inputs only because
/// private recovery has not yet covered the wallet's latest block: this build
/// recovers the wallet privately, and every account owning an input that no
/// earlier batch transaction creates is active, unheld, and blocked by
/// nothing but coverage or a scan behind the tip. Any doubt is `false`, so the
/// refusal stays final.
fn catching_up(
    db: &ReservedWallet,
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
) -> bool {
    if !selects_private_recovery(db_path, network) {
        return false;
    }
    let Some(bundle) = tx.transparent_bundle() else {
        return false;
    };
    // A separate reader: the classification only chooses between waiting and
    // failing, and the reservation's own check still decides.
    let Ok(reader) = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT) else {
        return false;
    };
    let mut owners = Vec::new();
    for input in &bundle.vin {
        let prevout = input.prevout();
        if earlier
            .iter()
            .any(|parent| parent.txid() == *prevout.txid())
        {
            continue;
        }
        match input_owner(&reader, prevout) {
            Some(owner) if !owners.contains(&owner) => owners.push(owner),
            Some(_) => {}
            None => return false,
        }
    }
    !owners.is_empty()
        && owners.into_iter().all(|owner| {
            recovery_hold(db_path, owner).is_none()
                && db
                    .transparent_ledger_snapshot(owner, crate::wallet::confirmations_policy())
                    .is_ok_and(|snapshot| {
                        !snapshot.blockers.is_empty()
                            && snapshot.blockers.iter().all(|blocker| {
                                matches!(
                                    blocker,
                                    RecoveryBlocker::Recovery(CandidateBlocker::IncompleteCoverage)
                                        | RecoveryBlocker::ChainBehindTip
                                )
                            })
                    })
        })
}

/// The account owning the wallet output `prevout`, if the wallet holds it.
fn input_owner(
    conn: &rusqlite::Connection,
    prevout: &transparent::bundle::OutPoint,
) -> Option<AccountUuid> {
    conn.query_row(
        "SELECT a.uuid FROM transparent_received_outputs o
             JOIN transactions t ON t.id_tx = o.transaction_id
             JOIN accounts a ON a.id = o.account_id
             WHERE t.txid = ?1 AND o.output_index = ?2",
        rusqlite::params![prevout.hash(), prevout.n()],
        |row| row.get::<_, uuid::Uuid>(0),
    )
    .ok()
    .map(AccountUuid::from_uuid)
}
