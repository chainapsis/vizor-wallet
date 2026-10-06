//! Public, txid-disclosing GetTransaction transport. Payload-required callers
//! and the explicit status adapter use it for different purposes.
use std::time::Duration;
use tonic::{transport::Channel, Request, Status};
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, RawTransaction, TxFilter,
};
use zcash_primitives::transaction::TxId;

const TIMEOUT: Duration = Duration::from_secs(20);

pub(crate) async fn get_transaction_payload(
    client: &mut CompactTxStreamerClient<Channel>,
    txid: TxId,
) -> Result<RawTransaction, Status> {
    let mut request = Request::new(TxFilter {
        block: None,
        index: 0,
        hash: txid.as_ref().to_vec(),
    });
    request.set_timeout(TIMEOUT);
    tokio::time::timeout(TIMEOUT, client.get_transaction(request))
        .await
        .map_err(|_| Status::deadline_exceeded("get_transaction_payload timed out"))?
        .map(|response| response.into_inner())
}
