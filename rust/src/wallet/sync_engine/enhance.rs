//! Transaction enhancement pass for the sync engine.
//!
//! `scan_cached_blocks` walks compact blocks and discovers transactions
//! that are relevant to the wallet, but a compact block only carries
//! the subset of transaction data needed for shielded-note discovery.
//! Things the wallet still has to learn afterwards:
//!
//!   - The full transaction bytes (for memo decryption, transparent
//!     input/output tracking, etc.).
//!   - Mined status for a transaction the wallet knows about but
//!     hasn't confirmed on-chain yet.
//!   - Transparent-address history in a given block range (used when
//!     the wallet imports or derives a new t-address and has to
//!     backfill its activity).
//!
//! Librustzcash signals these gaps by populating
//! `db.transaction_data_requests()`. This module drains the queue
//! against lightwalletd via three gRPC calls (`GetTransaction`,
//! `TransactionsInvolvingAddress`) and writes the results back into
//! `db` using `decrypt_and_store_transaction` and
//! `set_transaction_status`. The loop retries up to three times
//! because servicing one request can legally populate new requests
//! (e.g. a newly-decrypted transaction may reveal additional parent
//! transactions to enhance).

use std::collections::HashSet;

use tonic::transport::Channel;
use zcash_client_backend::{
    data_api::{
        wallet::decrypt_and_store_transaction, TransactionDataRequest, TransactionStatus,
        WalletRead, WalletWrite,
    },
    proto::service::{
        self, compact_tx_streamer_client::CompactTxStreamerClient, BlockId, BlockRange, TxFilter,
    },
};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId};

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::network::WalletNetwork;

use super::{SyncError, WalletDatabase};

/// Drains `db.transaction_data_requests()` against lightwalletd until
/// the queue is empty or no request is actionable. Returns
/// `SyncError::Db` if `db.transaction_data_requests()` itself fails.
/// Per-request failures (bad transaction bytes, network hiccups,
/// "txid not recognized" from the server) are logged and, for
/// `GetStatus` requests, recorded via `set_transaction_status` so
/// they don't get retried forever.
pub(super) async fn run_enhancement(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    network: WalletNetwork,
) -> Result<(), SyncError> {
    let mut failed_txids: HashSet<String> = HashSet::new();

    for _ in 0..3 {
        let requests = db
            .transaction_data_requests()
            .map_err(|e| SyncError::db(format!("transaction_data_requests: {e}")))?;
        if requests.is_empty() {
            break;
        }

        // If nothing in the queue is actionable (e.g. address-scoped
        // requests without an `end` height, which we can't service
        // without synthesizing a range), break rather than looping
        // forever on the same inert queue.
        let actionable = requests.iter().any(|r| match r {
            TransactionDataRequest::Enhancement(_) | TransactionDataRequest::GetStatus(_) => true,
            TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                req.block_range_end().is_some()
            }
        });
        if !actionable {
            break;
        }

        for req in &requests {
            match req {
                TransactionDataRequest::GetStatus(txid)
                | TransactionDataRequest::Enhancement(txid) => {
                    let txid_str = format!("{txid}");
                    if failed_txids.contains(&txid_str) {
                        continue;
                    }

                    let hash = txid.as_ref().to_vec();

                    match client
                        .get_transaction(TxFilter {
                            block: None,
                            index: 0,
                            hash,
                        })
                        .await
                    {
                        Ok(response) => {
                            let raw = response.into_inner();
                            if !raw.data.is_empty() {
                                match Transaction::read(&raw.data[..], BranchId::Sapling) {
                                    Ok(tx) => {
                                        let height = if raw.height > 0 {
                                            Some(BlockHeight::from_u32(raw.height as u32))
                                        } else {
                                            None
                                        };
                                        if let Err(e) = with_wallet_db_write_lock(
                                            "sync_engine.enhance.decrypt_and_store_transaction",
                                            || {
                                                decrypt_and_store_transaction(
                                                    &network, db, &tx, height,
                                                )
                                            },
                                        ) {
                                            log::error!(
                                                "sync: decrypt_and_store_transaction failed: {e}"
                                            );
                                        }
                                    }
                                    Err(e) => log::warn!(
                                        "sync: Transaction::read failed for {txid_str}: {e}"
                                    ),
                                }
                            }
                            if matches!(req, TransactionDataRequest::GetStatus(_)) {
                                let height = raw.height;
                                let status = if height > 0 {
                                    TransactionStatus::Mined(BlockHeight::from_u32(height as u32))
                                } else {
                                    TransactionStatus::NotInMainChain
                                };
                                if let Err(e) = with_wallet_db_write_lock(
                                    "sync_engine.enhance.set_transaction_status",
                                    || db.set_transaction_status(*txid, status),
                                ) {
                                    log::error!("sync: set_transaction_status failed: {e}");
                                }
                            }
                        }
                        Err(e) => {
                            log::warn!("sync: get_transaction failed for {txid_str}: {e}");
                            failed_txids.insert(txid_str);
                            if let Err(e) = with_wallet_db_write_lock(
                                "sync_engine.enhance.set_transaction_status",
                                || {
                                    db.set_transaction_status(
                                        *txid,
                                        TransactionStatus::TxidNotRecognized,
                                    )
                                },
                            ) {
                                log::error!("sync: set_transaction_status failed: {e}");
                            }
                        }
                    }
                }
                TransactionDataRequest::TransactionsInvolvingAddress(req) => {
                    let end_height = match req.block_range_end() {
                        Some(h) => h,
                        None => continue,
                    };
                    let addr_str = zcash_keys::encoding::encode_transparent_address_p(
                        &network,
                        &req.address(),
                    );
                    let start = u32::from(req.block_range_start()) as u64;
                    let end = u32::from(end_height) as u64;

                    match client
                        .get_taddress_txids(service::TransparentAddressBlockFilter {
                            address: addr_str,
                            range: Some(BlockRange {
                                start: Some(BlockId {
                                    height: start,
                                    hash: vec![],
                                }),
                                end: Some(BlockId {
                                    height: end.saturating_sub(1),
                                    hash: vec![],
                                }),
                            }),
                        })
                        .await
                    {
                        Ok(response) => {
                            let mut stream = response.into_inner();
                            while let Ok(Some(raw)) = stream.message().await {
                                if !raw.data.is_empty() {
                                    match Transaction::read(&raw.data[..], BranchId::Sapling) {
                                        Ok(tx) => {
                                            let height = if raw.height > 0 {
                                                Some(BlockHeight::from_u32(raw.height as u32))
                                            } else {
                                                None
                                            };
                                            if let Err(e) = with_wallet_db_write_lock(
                                                "sync_engine.enhance.decrypt_and_store_transaction",
                                                || {
                                                    decrypt_and_store_transaction(
                                                        &network, db, &tx, height,
                                                    )
                                                },
                                            ) {
                                                log::error!(
                                                    "sync: decrypt_and_store_transaction (addr) failed: {e}"
                                                );
                                            }
                                        }
                                        Err(e) => {
                                            log::warn!("sync: Transaction::read (addr) failed: {e}")
                                        }
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            log::warn!("sync: get_taddress_txids failed: {e}");
                        }
                    }
                }
            }
        }
    }
    Ok(())
}
