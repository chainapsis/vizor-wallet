//! Transparent-address history transaction ingestion.

use std::collections::HashSet;

use futures::{FutureExt, StreamExt};
use tonic::transport::Channel;
use transparent::address::TransparentAddress;
use zcash_client_backend::{
    data_api::{
        transparent_ledger::TransparentLedgerRead, wallet::decrypt_and_store_transaction,
        TransactionDataRequest, WalletWrite,
    },
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_client_sqlite::error::SqliteClientError;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::BranchId;

use crate::wallet::{
    db::with_wallet_db_write_lock,
    network::WalletNetwork,
    sync_engine::{lwd, SyncError, TransparentLookupGate, WalletDatabase},
};

use super::{super::payload::public::mined_height_from_raw_height, fees::fill_missing_fee};

#[derive(Default)]
pub(in crate::wallet::sync_engine::enhancement) struct HistoryPass {
    failed_addresses: HashSet<TransparentAddress>,
}

impl HistoryPass {
    pub(in crate::wallet::sync_engine::enhancement) async fn run_requests(
        &mut self,
        client: &mut CompactTxStreamerClient<Channel>,
        db: &mut WalletDatabase,
        db_path: &str,
        requests: &[TransactionDataRequest],
        network: WalletNetwork,
        gate: &TransparentLookupGate,
        should_exit: &impl Fn() -> bool,
    ) -> Result<bool, SyncError> {
        let mut planned = super::super::super::address_history::plan(requests);
        planned.retain(|group| !self.failed_addresses.contains(&group[0].address()));
        let actionable = !planned.is_empty();
        if !actionable {
            return Ok(false);
        }

        let download_client = client.clone();
        let open_gate = gate.clone();
        // Every open sends a transparent address, so the gate authorizes each
        // one as it is first polled, including every stream of the initial
        // fill. A withheld open surfaces as an error the loop resolves below.
        let open: super::super::super::address_history::OpenHistory = Box::new(move |req| {
            let mut client = download_client.clone();
            let gate = open_gate.clone();
            async move {
                let address =
                    zcash_keys::encoding::encode_transparent_address_p(&network, &req.address());
                let stream = gate
                    .taddress_txids(
                        &mut client,
                        address,
                        u64::from(u32::from(req.block_range_start())),
                        u64::from(u32::from(req.block_range_end().unwrap())) - 1,
                    )
                    .await?
                    .ok_or_else(|| SyncError::other("address history withheld by policy"))?;
                Ok(
                    futures::stream::try_unfold(stream, |mut stream| async move {
                        Ok(
                            lwd::next_stream_message(&mut stream, "get_taddress_txids stream")
                                .await?
                                .map(|raw| (raw, stream)),
                        )
                    })
                    .boxed(),
                )
            }
            .boxed()
        });
        let mut reads = super::super::super::address_history::HistoryReads::new(planned, open);
        loop {
            let event = tokio::select! {
                biased;
                _ = super::super::super::watch_for_exit(should_exit) => return Ok(actionable),
                event = reads.next() => event,
            };
            let Some((mut read, result)) = event else {
                break;
            };
            if should_exit() {
                return Ok(actionable);
            }
            let req = read.request().clone();
            // A withheld open, or any failure once authority is revoked, ends
            // the lane quietly: unacknowledged ranges stay unchecked and
            // durable, and dropping `reads` cancels the open streams.
            let result = match result {
                Err(_) if !gate.permits()? => return Ok(false),
                result => result?,
            };
            match result {
                Some(raw) => {
                    let tx = match store_address_transaction(&network, db, &raw.data, raw.height) {
                        Ok(tx) => tx,
                        Err(error) => {
                            log::warn!(
                                "sync: address transaction processing failed; leaving range unchecked for retry: {error}"
                            );
                            self.failed_addresses.insert(req.address());
                            continue;
                        }
                    };
                    let fee_result = tokio::select! {
                        biased;
                        _ = super::super::super::watch_for_exit(should_exit) => {
                            return Ok(actionable)
                        },
                        result = fill_missing_fee(client, db_path, &tx, should_exit) => result,
                    };
                    if let Err(error) = fee_result {
                        log::warn!(
                            "sync: fee enhancement (addr) failed for {}: {error}",
                            tx.txid()
                        );
                    }
                }
                None => {
                    // A transition while this stream was open withholds the
                    // acknowledgement, so the range is retried under the new
                    // policy rather than marked checked under the old one. The
                    // generation is read in the acknowledging transaction, so a
                    // commit by another connection between the two fails the
                    // write instead of slipping past the check.
                    let acknowledged =
                        with_wallet_db_write_lock("sync_engine.notify_address_checked", || {
                            db.transactionally(|tx| {
                                if !gate.permits_applied(tx.applied_transparent_policy()?) {
                                    return Ok(false);
                                }
                                tx.notify_address_checked(
                                    req.clone(),
                                    req.block_range_end().unwrap() - 1,
                                )?;
                                Ok::<_, SqliteClientError>(true)
                            })
                        });
                    match acknowledged {
                        Ok(true) => read.finish_range(),
                        Ok(false) => return Ok(false),
                        Err(error) => {
                            log::warn!(
                                "sync: address completion write failed; retrying on a later sync: {error}"
                            );
                            self.failed_addresses.insert(req.address());
                            continue;
                        }
                    }
                }
            }
            reads.resume(read);
        }
        Ok(actionable)
    }
}

/// Parses and stores one streamed transaction before its address range may be
/// acknowledged. A failure therefore leaves the durable range retryable.
fn store_address_transaction(
    network: &WalletNetwork,
    db: &mut WalletDatabase,
    bytes: &[u8],
    raw_height: u64,
) -> Result<Transaction, SyncError> {
    let mined_height = mined_height_from_raw_height(raw_height)?;
    let transaction = Transaction::read(bytes, BranchId::Sapling)
        .map_err(|error| SyncError::parse(format!("Transaction::read (addr): {error}")))?;
    with_wallet_db_write_lock("sync_engine.enhance.decrypt_and_store_transaction", || {
        decrypt_and_store_transaction(network, db, &transaction, mined_height)
    })
    .map_err(|error| SyncError::db(format!("decrypt_and_store_transaction (addr): {error}")))?;
    Ok(transaction)
}
