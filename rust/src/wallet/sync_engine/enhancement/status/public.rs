//! Public transaction-status source construction.

use std::future::{ready, Ready};

use tonic::transport::Channel;
use zakura_transaction_status::{lightwalletd::LightwalletdSource, StatusError, StatusSource};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;

pub(in crate::wallet::sync_engine::enhancement) fn lightwalletd_source<'a, F>(
    client: CompactTxStreamerClient<Channel>,
    should_exit: &'a F,
) -> impl StatusSource + 'a
where
    F: Fn() -> bool + Sync + 'a,
{
    LightwalletdSource::new(
        move || -> Ready<Result<CompactTxStreamerClient<Channel>, StatusError>> {
            ready(Ok(client))
        },
        should_exit,
    )
}
