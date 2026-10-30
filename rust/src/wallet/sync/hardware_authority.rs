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
//! A wallet database too busy to reserve is [`DispatchRefusal::Unavailable`],
//! waited out and kept the same way: a long write, such as a private
//! recovery settlement, says nothing about the transaction.

use std::{
    fmt,
    future::Future,
    time::{Duration, Instant},
};

use futures::future::{select, Either};

use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::data_api::{
    transparent_ledger::{TransparentLedgerMode, TransparentLedgerRead},
    WalletRead,
};
use zcash_client_sqlite::{
    error::{AuthorityRefusal, SqliteClientError},
    util::SystemClock,
    AccountUuid, WalletDb,
};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, WaitingWriter, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
    sync_engine::{
        enhancement::{private_queries_active, transparent_ledger_mode_for},
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
    /// The wallet database could not be opened or reserved in time, as while
    /// another connection holds its write lock. Nothing was decided about the
    /// transaction, so callers keep it for a retry.
    Unavailable(String),
    /// Anything else: a revoked or unreadable policy, quarantine, a hold,
    /// withdrawn, unknown, spent or immature inputs. Retrying the same
    /// transaction will not help.
    Refused(String),
}

impl DispatchRefusal {
    /// Whether the same signed transaction may be authorized later, so a
    /// caller keeps it rather than releasing its inputs.
    pub(crate) fn is_retryable(&self) -> bool {
        matches!(
            self,
            DispatchRefusal::CatchingUp(_) | DispatchRefusal::Unavailable(_)
        )
    }
}

impl fmt::Display for DispatchRefusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DispatchRefusal::CatchingUp(message)
            | DispatchRefusal::Unavailable(message)
            | DispatchRefusal::Refused(message) => f.write_str(message),
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
/// Returns at once when they are, or when the refusal is final; a retryable
/// one ([`DispatchRefusal::is_retryable`]) is checked again until the wait
/// ends. [`dispatch`] still decides under its reservation.
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
            Err(refusal) if refusal.is_retryable() && Instant::now() < deadline => {}
            Err(refusal) => return Err(refusal),
        }
        tokio::time::sleep(CATCH_UP_POLL).await;
    }
}

/// [`authorize`], retried while the wallet is [`DispatchRefusal::Unavailable`]
/// until [`CATCH_UP_WAIT`] ends. Any other outcome returns at once: a
/// reservation, or a refusal its caller already waited out.
async fn reserve(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
    network_tip: u64,
) -> Result<(ReservedWallet, Instant), DispatchRefusal> {
    let deadline = Instant::now() + CATCH_UP_WAIT;
    loop {
        match authorize(db_path, network, tx, earlier, network_tip) {
            Err(DispatchRefusal::Unavailable(_)) if Instant::now() < deadline => {}
            reserved => return reserved,
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
    let (db, reserved) = reserve(db_path, network, tx, earlier, network_tip).await?;

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
    // A long background write steps aside between its transactions while
    // this waits for the wallet's write lock.
    let waiting = WaitingWriter::new();
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)
        .map_err(DispatchRefusal::Unavailable)?;
    conn.execute_batch("BEGIN IMMEDIATE").map_err(|e| {
        let message = format!("Reserve transparent broadcast authority: {e}");
        if is_busy(&e) {
            DispatchRefusal::Unavailable(message)
        } else {
            refused(message)
        }
    })?;
    drop(waiting);
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
    db.check_transparent_transaction_inputs(tx, earlier, target.into())
        .map_err(|error| refusal(&error, |owner| catching_up(owner, db_path, network, mode)))?;
    Ok((db, reserved))
}

/// What a failed input check means for the broadcast: waiting while
/// `waits_for` admits every account a pending refusal names, keeping the
/// transaction when the check could not read the wallet, and otherwise a final
/// refusal.
fn refusal(
    error: &SqliteClientError,
    waits_for: impl Fn(&[AccountUuid]) -> bool,
) -> DispatchRefusal {
    let message = format!("Transparent broadcast authority unavailable: {error}");
    match error {
        SqliteClientError::TransparentAuthorityUnavailable(AuthorityRefusal::Pending {
            accounts,
        }) if waits_for(accounts) => DispatchRefusal::CatchingUp(message),
        // Nothing was decided about the transaction.
        SqliteClientError::DbError(_) => DispatchRefusal::Unavailable(message),
        _ => DispatchRefusal::Refused(message),
    }
}

/// Whether `error` is SQLite reporting another connection's lock.
fn is_busy(error: &rusqlite::Error) -> bool {
    matches!(
        error.sqlite_error_code(),
        Some(rusqlite::ErrorCode::DatabaseBusy | rusqlite::ErrorCode::DatabaseLocked)
    )
}

/// Whether a refusal pending on `accounts` is only private recovery catching
/// up with the wallet's latest block: private queries are on, so recovery
/// runs, the policy requires it, and no owning account is held. The
/// library decides the input and ledger conditions in the read that refused;
/// a hold lives only in this process.
fn catching_up(
    accounts: &[AccountUuid],
    db_path: &str,
    network: WalletNetwork,
    mode: TransparentLedgerMode,
) -> bool {
    mode == TransparentLedgerMode::PrivateRequired
        && private_queries_active(db_path, network)
        && accounts
            .iter()
            .all(|owner| recovery_hold(db_path, *owner).is_none())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_refusal_waits_only_when_pending_on_accounts_it_may_wait_for() {
        let account = AccountUuid::from_uuid(uuid::Uuid::from_u128(1));
        let pending =
            SqliteClientError::TransparentAuthorityUnavailable(AuthorityRefusal::Pending {
                accounts: vec![account],
            });
        assert!(matches!(
            refusal(&pending, |_| true),
            DispatchRefusal::CatchingUp(_)
        ));
        assert!(matches!(
            refusal(&pending, |_| false),
            DispatchRefusal::Refused(_)
        ));
        let spent = SqliteClientError::TransparentAuthorityUnavailable(AuthorityRefusal::Refused(
            zcash_client_sqlite::error::RefusalReason::Spent,
        ));
        assert!(matches!(
            refusal(&spent, |_| true),
            DispatchRefusal::Refused(_)
        ));
    }

    #[test]
    fn a_check_that_could_not_read_the_wallet_keeps_the_transaction() {
        let busy = SqliteClientError::DbError(rusqlite::Error::SqliteFailure(
            rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_BUSY),
            None,
        ));
        let refusal = refusal(&busy, |_| false);
        assert!(
            matches!(refusal, DispatchRefusal::Unavailable(_)),
            "{refusal}"
        );
        assert!(refusal.is_retryable());
    }
}
