//! Transaction enhancement orchestration.
//!
//! See `enhancement/README.md` for the complete data-flow guide.
//!
//! Wallet data comes from three separate snapshots:
//!
//! - `transaction_status_work()` routes each status obligation to public or private transport.
//! - `transaction_data_requests()` contains only transparent address history.
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
//! The configured status mode selects private status PIR for mainnet private
//! preference, otherwise authorized public lightwalletd. Work variants carry
//! that decision. Callers outside the sync engine (iOS read-only FFI,
//! migration reconciliation) resolve the same policy through this module.

mod auxiliary;
mod payload;
mod policy;
pub(crate) mod status;
mod transport;

/// Default mainnet endpoint shared by payload and status PIR. Each lane keeps
/// its own env-var override.
pub(super) const DEFAULT_MAINNET_ENDPOINT: &str = "https://enhance-pir.valargroup.dev";

pub(super) use auxiliary::transparent_history::store_address_transaction;
pub(super) use payload::{phase, queue_stored_transactions};
pub(crate) use policy::EnhancementPolicy;

use std::collections::HashSet;
use tonic::transport::Channel;
use zcash_client_backend::data_api::{status::TransactionStatusRead, WalletRead};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;

use super::{block_source::MemoryBlockSource, SyncError, WalletDatabase};
use auxiliary::{fees::backfill_stored_fees, transparent_history::HistoryPass};
use payload::{EnhancePirRunError, ProductionEnhancementEffects, RoutedPayloadEnhancement};
use transport::RoutedTransport;

const MAX_CHECKPOINT_PASSES: usize = 3;

/// One immutable policy and private payload session for a foreground sync.
pub(super) struct EnhancementSession {
    policy: EnhancementPolicy,
    payload: RoutedPayloadEnhancement,
    network: crate::wallet::network::WalletNetwork,
    db_path: String,
    /// Set by the first failed private status lookup; later checkpoints in this
    /// session leave private status work pending instead of retrying the service.
    private_status_failed: bool,
    ready_resubmission: HashSet<Vec<u8>>,
}

impl EnhancementSession {
    pub(super) fn new(network: crate::wallet::network::WalletNetwork, db_path: &str) -> Self {
        let policy = EnhancementPolicy::current(network);
        payload::begin_session(db_path);
        Self {
            policy,
            payload: RoutedPayloadEnhancement::new(network, policy.is_private(), db_path),
            network,
            db_path: db_path.into(),
            private_status_failed: false,
            ready_resubmission: HashSet::new(),
        }
    }

    pub(super) fn take_ready_resubmission(&mut self) -> HashSet<Vec<u8>> {
        std::mem::take(&mut self.ready_resubmission)
    }

    /// Runs status and auxiliary metadata first, then drains the routed payload
    /// snapshot that those lanes may have populated.
    pub(super) async fn run_checkpoint(
        &mut self,
        db: &mut WalletDatabase,
        client: &mut CompactTxStreamerClient<Channel>,
        cached: Option<&MemoryBlockSource>,
        should_exit: &(impl Fn() -> bool + Sync),
    ) -> Result<bool, SyncError> {
        self.ready_resubmission.clear();
        self.policy.configure_db(db);
        backfill_stored_fees(client, db, &self.db_path, should_exit).await?;

        // The public source reuses the caller-owned lightwalletd channel, while
        // `status::reader` constructs the private source from wallet context.
        // Both remain lazy: only the source selected by policy is opened.
        let public_source = status::lightwalletd_source(client.clone(), should_exit);
        let mut status_reader =
            status::reader(&self.db_path, self.network, should_exit, public_source);
        let mut attempted_statuses = HashSet::new();
        let mut history = HistoryPass::default();

        for _ in 0..MAX_CHECKPOINT_PASSES {
            let requests = db
                .transaction_data_requests()
                .map_err(|error| SyncError::db(format!("transaction_data_requests: {error}")))?;
            let status_work = db
                .transaction_status_work()
                .map_err(|error| SyncError::db(format!("transaction_status_work: {error}")))?;
            let status_actionable = status::run_requests(
                &mut status_reader,
                db,
                &status_work,
                &mut attempted_statuses,
                &mut self.private_status_failed,
                &self.db_path,
                &mut self.ready_resubmission,
                should_exit,
            )
            .await?;
            if should_exit() {
                return Ok(true);
            }
            let history_actionable = history
                .run_requests(
                    client,
                    db,
                    &self.db_path,
                    &requests,
                    self.network,
                    should_exit,
                )
                .await?;
            if should_exit() {
                return Ok(true);
            }
            if !status_actionable && !history_actionable {
                break;
            }
        }

        self.run_payload_recovery(db, client, cached, should_exit)
            .await
    }

    /// Retries already-routed payload work without running metadata lanes.
    pub(super) async fn run_payload_recovery(
        &mut self,
        db: &mut WalletDatabase,
        client: &mut CompactTxStreamerClient<Channel>,
        cached: Option<&MemoryBlockSource>,
        should_exit: &impl Fn() -> bool,
    ) -> Result<bool, SyncError> {
        self.policy.configure_db(db);
        let mut effects =
            ProductionEnhancementEffects::new(self.network, &self.db_path, client, cached);
        let route = RoutedTransport::new(should_exit);
        match Box::pin(self.payload.run(db, &route, &mut effects, should_exit)).await {
            Ok(()) => effects.finish().map(|()| false),
            Err(EnhancePirRunError::ExitRequested) => Ok(true),
            Err(EnhancePirRunError::HttpStatus(status)) => Err(SyncError::net(format!(
                "transaction enhancement returned HTTP {status}"
            ))),
            Err(EnhancePirRunError::Failed(error)) => Err(error),
        }
    }
}

#[cfg(test)]
mod tests;
