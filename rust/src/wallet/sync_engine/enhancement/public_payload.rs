//! Public lightwalletd payload execution for already-routed enhancement work.
//!
//! This module never chooses a route. It receives only
//! `PublicTransactionEnhancementRequest` values from the unified wallet snapshot.

use std::{collections::HashSet, rc::Rc};

use rusqlite::{types::Value, vtab::array::Array};
use tonic::{transport::Channel, Code, Status};
use zcash_client_backend::{
    data_api::{
        wallet::decrypt_and_store_transaction, PublicTransactionEnhancementRequest, WalletWrite,
    },
    proto::service::{compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction},
};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::{BlockHeight, BranchId};

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
    transaction_data::payload::get_transaction_payload,
};

use super::{
    super::{block_source::MemoryBlockSource, SyncError, WalletDatabase},
    fees::fill_missing_fee,
};

/// A shared transaction can retain raw bytes after account deletion while losing
/// that account's sent outputs. Requeue it when encountered by a new scan.
///
/// Caller holds the wallet write lock. Queue before the scan so the existing
/// durable enhancement queue survives cancellation, errors, and process exit.
/// No import-time or startup sweep: only transactions in this downloaded batch.
/// Heights include transparent-only transactions omitted from compact blocks;
/// hashes also cover transactions whose mined height was cleared by a rewind.
pub(in crate::wallet::sync_engine) fn queue_stored_transactions(
    db_path: &str,
    blocks: &MemoryBlockSource,
) -> Result<(), SyncError> {
    let Some(heights) = blocks.height_range() else {
        return Ok(());
    };
    let hashes: Array = Rc::new(
        blocks
            .transaction_hashes()
            .map(|hash| Value::Blob(hash.to_vec()))
            .collect(),
    );
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    // query_type=1 is the SDK's Enhancement request. Status requests (0) and
    // dependency links already in the queue must be preserved.
    let count = conn
        .execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type, dependent_transaction_id)
         SELECT txid, 1, NULL FROM transactions
         WHERE raw IS NOT NULL
           AND (txid IN rarray(?1) OR mined_height BETWEEN ?2 AND ?3)
         ON CONFLICT (txid, query_type) DO NOTHING",
            rusqlite::params![hashes, heights.start(), heights.end()],
        )
        .map_err(|error| SyncError::db(format!("queue scanned stored transactions: {error}")))?;
    if count > 0 {
        log::info!("sync: queued {count} stored transaction(s) for scan-time enhancement");
    }
    Ok(())
}

/// Retrieves routed public payloads over lightwalletd for one sync pass.
///
/// Callers pass only [`PublicTransactionEnhancementRequest`]s taken from the
/// wallet's routed enhancement snapshot; this type never selects work itself.
/// An explicit "txid not recognized" response retires only enhancement work.
/// Other failures leave the request durable, skip that transaction for the
/// rest of the pass, and are reported by [`Self::finish`] as a retryable error.
#[derive(Default)]
pub(in crate::wallet::sync_engine) struct PublicPayloadExecutor {
    failed: HashSet<TxId>,
    deferred_error: Option<SyncError>,
}

impl PublicPayloadExecutor {
    /// Dispatches each request not already failed in this pass, stopping
    /// before the next dispatch once `should_exit` is set.
    pub(in crate::wallet::sync_engine) async fn run(
        &mut self,
        client: &mut CompactTxStreamerClient<Channel>,
        db: &mut WalletDatabase,
        db_path: &str,
        network: WalletNetwork,
        requests: &[PublicTransactionEnhancementRequest],
        should_exit: &impl Fn() -> bool,
    ) {
        for request in requests {
            if should_exit() {
                return;
            }
            let txid = request.txid();
            if self.failed.contains(&txid) {
                continue;
            }
            let txid_str = format!("{txid}");

            match cancelable(get_transaction_payload(client, txid), should_exit).await {
                Ok(raw) => match decode_enhancement_payload(&raw, txid) {
                    Ok((tx, mined_height)) => {
                        if let Err(e) = with_wallet_db_write_lock(
                            "sync_engine.enhance.decrypt_and_store_transaction",
                            || decrypt_and_store_transaction(&network, db, &tx, mined_height),
                        ) {
                            log::error!("sync: decrypt_and_store_transaction failed: {e}");
                            self.failed.insert(txid);
                            self.deferred_error.get_or_insert_with(|| {
                                SyncError::db(format!(
                                    "decrypt_and_store_transaction failed for {txid_str}: {e}"
                                ))
                            });
                        }
                        if let Err(e) = fill_missing_fee(client, db_path, &tx, should_exit).await {
                            log::warn!("sync: fee enhancement failed for {txid_str}: {e}");
                        }
                    }
                    Err(e) => {
                        log::warn!("sync: invalid enhancement payload for {txid_str}: {e}");
                        self.failed.insert(txid);
                        self.deferred_error.get_or_insert(e);
                    }
                },
                Err(e) => match classify_get_transaction_error(&e) {
                    GetTransactionErrorAction::CompleteEnhancementNotFound => {
                        log::warn!("sync: get_transaction did not recognize {txid_str}: {e}");
                        self.failed.insert(txid);
                        if let Err(e) = with_wallet_db_write_lock(
                            "sync_engine.enhance.notify_transaction_enhancement_not_found",
                            || db.notify_transaction_enhancement_not_found(txid),
                        ) {
                            log::error!(
                                "sync: notify_transaction_enhancement_not_found failed: {e}"
                            );
                            self.deferred_error.get_or_insert_with(|| {
                                SyncError::db(format!(
                                    "notify_transaction_enhancement_not_found failed for {txid}: {e}"
                                ))
                            });
                        }
                    }
                    GetTransactionErrorAction::RetryAsNetwork => {
                        self.failed.insert(txid);
                        self.deferred_error.get_or_insert_with(|| {
                            SyncError::net(format!("get_transaction failed for {txid_str}: {e}"))
                        });
                    }
                },
            }
        }
    }

    /// Reports the first retryable payload failure of this pass, if any.
    pub(in crate::wallet::sync_engine) fn finish(self) -> Result<(), SyncError> {
        self.deferred_error.map_or(Ok(()), Err)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum GetTransactionErrorAction {
    CompleteEnhancementNotFound,
    RetryAsNetwork,
}

pub(super) fn classify_get_transaction_error(status: &Status) -> GetTransactionErrorAction {
    match status.code() {
        Code::NotFound => GetTransactionErrorAction::CompleteEnhancementNotFound,
        _ => GetTransactionErrorAction::RetryAsNetwork,
    }
}

pub(super) fn mined_height_from_raw_height(
    raw_height: u64,
) -> Result<Option<BlockHeight>, SyncError> {
    match raw_height {
        0 | u64::MAX => Ok(None),
        h if h <= u32::MAX as u64 => Ok(Some(BlockHeight::from_u32(h as u32))),
        h => Err(SyncError::parse(format!(
            "raw transaction height out of range: {h}"
        ))),
    }
}

pub(super) fn decode_enhancement_payload(
    raw: &RawTransaction,
    expected_txid: TxId,
) -> Result<(Transaction, Option<BlockHeight>), SyncError> {
    let mined_height = mined_height_from_raw_height(raw.height)?;
    let tx = Transaction::read(&raw.data[..], BranchId::Sapling)
        .map_err(|e| SyncError::parse(format!("enhancement transaction: {e}")))?;
    if tx.txid() != expected_txid {
        return Err(SyncError::parse("enhancement transaction ID mismatch"));
    }
    Ok((tx, mined_height))
}

/// Cancellation is checked before dispatch and after completion, and dropping
/// the request future interrupts an in-flight wait. No queued request survives.
pub(super) async fn cancelable<T, E: CancelError>(
    request: impl std::future::Future<Output = Result<T, E>>,
    should_exit: &impl Fn() -> bool,
) -> Result<T, E> {
    if should_exit() {
        return Err(E::cancelled());
    }
    let result = tokio::select! {
        biased;
        _ = super::super::watch_for_exit(should_exit) => return Err(E::cancelled()),
        result = request => result,
    };
    if should_exit() {
        return Err(E::cancelled());
    }
    result
}

pub(super) trait CancelError {
    fn cancelled() -> Self;
}
impl CancelError for SyncError {
    fn cancelled() -> Self {
        Self::other("enhancement cancelled")
    }
}
impl CancelError for Status {
    fn cancelled() -> Self {
        Self::cancelled("enhancement cancelled")
    }
}

#[cfg(test)]
mod cancellation_tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    #[tokio::test]
    async fn cancelled_public_batch_never_dispatches_the_next_transaction() {
        let cancelled = AtomicBool::new(false);
        let dispatched = AtomicUsize::new(0);
        let exit = || cancelled.load(Ordering::SeqCst);
        let first = cancelable(
            async {
                dispatched.fetch_add(1, Ordering::SeqCst);
                cancelled.store(true, Ordering::SeqCst);
                Ok::<_, SyncError>(())
            },
            &exit,
        )
        .await;
        assert!(first.is_err());
        let second = cancelable(
            async {
                dispatched.fetch_add(1, Ordering::SeqCst);
                Ok::<_, SyncError>(())
            },
            &exit,
        )
        .await;
        assert!(second.is_err());
        assert_eq!(dispatched.load(Ordering::SeqCst), 1);
    }
    #[tokio::test]
    async fn cancellation_drops_a_waiting_public_request() {
        let cancelled = AtomicBool::new(false);
        let exit = || cancelled.load(Ordering::SeqCst);
        let request = cancelable(std::future::pending::<Result<(), SyncError>>(), &exit);
        let cancel = async {
            tokio::task::yield_now().await;
            cancelled.store(true, Ordering::SeqCst);
        };
        let (result, _) = tokio::join!(request, cancel);
        assert!(result.is_err());
    }
}
