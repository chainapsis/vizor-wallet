//! Transaction enhancement orchestration.
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

mod fees;
mod private_pir;
mod public_payload;
mod scheduler;
mod transaction_requests;
mod transport;

pub(super) use private_pir::{begin_session, phase, EnhancePirRunError, RoutedPayloadEnhancement};
pub(super) use public_payload::queue_stored_transactions;
pub(super) use transaction_requests::run_auxiliary_transaction_requests;
pub(super) use transport::RoutedTransport;

use tonic::transport::Channel;
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;

use super::{block_source::MemoryBlockSource, SyncError, WalletDatabase};
use scheduler::ProductionEnhancementEffects;

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
