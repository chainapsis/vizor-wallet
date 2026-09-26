//! Transaction enhancement orchestration.
//!
//! See `enhancement/README.md` for the complete data-flow guide.
//!
//! Wallet data comes from two deliberately separate snapshots:
//!
//! - `transaction_data_requests()` contains status observation and transparent
//!   address history. Its public payload variants are deliberately ignored here.
//! - `transaction_enhancement_work()` is the single routing authority for
//!   payload retrieval. It assigns every obligation to either private Enhance
//!   PIR or public lightwalletd transport, never both.
//!
//! Auxiliary requests run before routed payload enhancement because transparent
//! history can discover transactions whose parent payloads then need routing.
//! A normal post-scan checkpoint therefore has this black-box order:
//!
//! 1. backfill fees and observe status,
//! 2. ingest and acknowledge transparent-address history,
//! 3. rediscover private payload positions and execute private PIR,
//! 4. reread durable routing, then fetch only explicitly public payloads.
//!
//! Every network lane is cancellation-aware and leaves unfinished obligations
//! durable. Diagnostic recovery phases are advisory; they never select a route
//! or authorize a privacy downgrade.
//!
//! `status_pir` selects the status source for that snapshot: private status
//! PIR when the release gate and preference allow it, otherwise public
//! lightwalletd. Callers outside the sync engine (iOS read-only FFI, migration
//! reconciliation) reach it through this module as well.

mod auxiliary;
mod payload;
mod status;
mod transport;

/// Compatibility surface for status callers outside the sync engine.
///
/// New implementation code should depend on the semantically named types in
/// `status`; this shim keeps the existing crate-visible path stable.
pub(crate) mod status_pir {
    pub(crate) use super::status::{enabled_for_preference, reader, PrivateStatusSource as Source};
}

/// Default mainnet endpoint shared by payload and status PIR. Each lane keeps
/// its own env-var override.
pub(super) const DEFAULT_MAINNET_ENDPOINT: &str = "https://enhance-pir.valargroup.dev";

pub(super) use auxiliary::run_auxiliary_transaction_requests;
pub(super) use payload::{
    begin_session, phase, queue_stored_transactions, EnhancePirRunError, RoutedPayloadEnhancement,
};
pub(super) use transport::RoutedTransport;

use tonic::transport::Channel;
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;

use super::{block_source::MemoryBlockSource, SyncError, WalletDatabase};
use payload::ProductionEnhancementEffects;

/// Runs the single routed payload scheduler for one sync checkpoint.
///
/// Private-service failures are deferred by the coordinator so compact sync
/// remains independent. Public payload failures remain retryable and are
/// reported after the bounded run. `Ok(true)` means cancellation or mode
/// handoff won and the caller must stop.
pub(super) async fn run_routed_payload_enhancement(
    enhancement: &mut RoutedPayloadEnhancement,
    db: &mut WalletDatabase,
    client: &mut CompactTxStreamerClient<Channel>,
    cached: Option<&MemoryBlockSource>,
    db_path: &str,
    network: crate::wallet::network::WalletNetwork,
    should_exit: &impl Fn() -> bool,
) -> Result<bool, SyncError> {
    let mut effects = ProductionEnhancementEffects::new(network, db_path, client, cached);
    let route = RoutedTransport::new(should_exit);
    match Box::pin(enhancement.run(db, &route, &mut effects, should_exit)).await {
        Ok(()) => effects.finish().map(|()| false),
        Err(EnhancePirRunError::ExitRequested) => Ok(true),
        Err(EnhancePirRunError::HttpStatus(status)) => Err(SyncError::net(format!(
            "transaction enhancement returned HTTP {status}"
        ))),
        Err(EnhancePirRunError::Failed(error)) => Err(error),
    }
}
