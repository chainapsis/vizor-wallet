//! Public lightwalletd payload execution for already-routed enhancement work.
//!
//! This module never chooses a route. It receives only
//! `PublicTransactionEnhancementRequest` values from the unified wallet snapshot.

use std::collections::HashSet;

use tonic::{transport::Channel, Code, Status};
use zcash_client_backend::{
    data_api::{
        transparent_ledger::TransparentLedgerRead, wallet::decrypt_and_store_transaction,
        PublicTransactionEnhancementRequest, WalletWrite,
    },
    proto::service::{compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction},
};
use zcash_client_sqlite::error::SqliteClientError;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::{BlockHeight, BranchId};

use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};

use crate::wallet::sync_engine::{
    enhancement::{auxiliary::fees::fill_missing_fee, transport::cancelable},
    SyncError, TransparentLookupGate, WalletDatabase,
};

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
    /// before the next dispatch once `should_exit` is set or `gate` withholds
    /// a request. Withheld requests stay queued for a later pass.
    pub(in crate::wallet::sync_engine) async fn run(
        &mut self,
        client: &mut CompactTxStreamerClient<Channel>,
        db: &mut WalletDatabase,
        db_path: &str,
        network: WalletNetwork,
        requests: &[PublicTransactionEnhancementRequest],
        gate: &TransparentLookupGate,
        should_exit: &impl Fn() -> bool,
    ) {
        for (index, request) in requests.iter().enumerate() {
            if should_exit() {
                return;
            }
            let txid = request.txid();
            if self.failed.contains(&txid) {
                continue;
            }
            let txid_str = format!("{txid}");

            // GetTransaction discloses the txid, so the gate authorizes each
            // request. A policy read failure withholds too; the work stays
            // durable either way.
            let response = match cancelable(gate.transaction(client, txid), should_exit).await {
                Ok(Some(response)) => response,
                Ok(None) => {
                    log::info!(
                        "sync: transparent policy withholds {} public payload requests",
                        requests.len() - index
                    );
                    return;
                }
                Err(_) if should_exit() => return,
                Err(error) => {
                    log::warn!("sync: withholding public payloads; policy check failed: {error}");
                    return;
                }
            };
            match response {
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
                        // Retiring the request is a completion write: it reads
                        // the generation in its own transaction, so a transition
                        // while the lookup was in flight leaves it retryable.
                        let retired = with_wallet_db_write_lock(
                            "sync_engine.enhance.notify_transaction_enhancement_not_found",
                            || {
                                db.transactionally(|tx| {
                                    if !gate.permits_applied(tx.applied_transparent_policy()?) {
                                        return Ok(false);
                                    }
                                    tx.notify_transaction_enhancement_not_found(txid)?;
                                    Ok::<_, SqliteClientError>(true)
                                })
                            },
                        );
                        if matches!(retired, Ok(false)) {
                            log::info!("sync: transparent policy changed; {txid_str} stays queued");
                            return;
                        }
                        if let Err(e) = retired {
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
pub(in crate::wallet::sync_engine::enhancement) enum GetTransactionErrorAction {
    CompleteEnhancementNotFound,
    RetryAsNetwork,
}

pub(in crate::wallet::sync_engine::enhancement) fn classify_get_transaction_error(
    status: &Status,
) -> GetTransactionErrorAction {
    match status.code() {
        Code::NotFound => GetTransactionErrorAction::CompleteEnhancementNotFound,
        _ => GetTransactionErrorAction::RetryAsNetwork,
    }
}

pub(in crate::wallet::sync_engine::enhancement) fn mined_height_from_raw_height(
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

pub(in crate::wallet::sync_engine) fn decode_enhancement_payload(
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
