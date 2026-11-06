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
pub(crate) mod content_failures;
mod payload;
mod policy;
pub(crate) mod status;
pub(super) mod transport;

pub(super) use auxiliary::transparent_history::store_address_transaction;
pub(super) use payload::public::decode_enhancement_payload;
pub(super) use payload::{phase, queue_stored_transactions};
#[cfg(test)]
pub(crate) use policy::test_mode;
pub(crate) use policy::{
    live_transparent_mode, may_raise, private_queries_active, set_preference_confirmed,
    transparent_ledger_mode_for, transparent_mode_for_preference, EnhancementPolicy,
    PublicTransparentLookups,
};
#[cfg(test)]
pub(crate) use transport::test_log;
pub(super) use transport::RoutedExchange;
#[cfg(test)]
pub(super) use transport::{response, ObservedRequest, RequestObserver};

use std::collections::HashSet;
use tonic::transport::Channel;
use zcash_client_backend::data_api::{status::TransactionStatusRead, WalletRead};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;

use super::{block_source::MemoryBlockSource, SyncError, TransparentLookupGate, WalletDatabase};
use auxiliary::{fees::backfill_stored_fees, transparent_history::HistoryPass};
use payload::{EnhancePirRunError, ProductionEnhancementEffects, RoutedPayloadEnhancement};
use transport::RoutedTransport;

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
        Self::with_policy(network, db_path, EnhancementPolicy::current(network))
    }

    pub(super) fn with_policy(
        network: crate::wallet::network::WalletNetwork,
        db_path: &str,
        policy: EnhancementPolicy,
    ) -> Self {
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

    /// The policy captured for this sync, shared by every lane it runs.
    pub(super) fn policy(&self) -> EnhancementPolicy {
        self.policy
    }

    pub(super) fn take_ready_resubmission(&mut self) -> HashSet<Vec<u8>> {
        std::mem::take(&mut self.ready_resubmission)
    }

    /// Runs status and auxiliary metadata first, then drains the routed payload
    /// work that existed before them.
    pub(super) async fn run_checkpoint(
        &mut self,
        db: &mut WalletDatabase,
        client: &mut CompactTxStreamerClient<Channel>,
        cached: Option<&MemoryBlockSource>,
        should_exit: &(impl Fn() -> bool + Sync),
    ) -> Result<bool, SyncError> {
        let db_path = self.db_path.clone();
        let private_status = status::PrivateStatusSource::new(&db_path, self.network, should_exit);
        let route = RoutedTransport::new(should_exit);
        self.checkpoint_with(db, client, cached, private_status, &route, should_exit)
            .await
    }

    /// [`Self::run_checkpoint`] with the private status source and the
    /// Enhance transport given.
    pub(super) async fn checkpoint_with<S: zakura_pir_client::status::policy::StatusSource>(
        &mut self,
        db: &mut WalletDatabase,
        client: &mut CompactTxStreamerClient<Channel>,
        cached: Option<&MemoryBlockSource>,
        private_status: S,
        route: &impl zakura_pir_client::enhance::transport::Transport,
        should_exit: &(impl Fn() -> bool + Sync),
    ) -> Result<bool, SyncError> {
        self.policy.configure_db(db);
        // The private work as it stands before any reply at this drain point.
        // The work replies add waits for the next block: whether more
        // lookups follow, now or after a restart at this tip, must not
        // depend on what a reply said.
        let before = private_work(db)?;
        let result = self
            .checkpoint_from(
                db,
                client,
                cached,
                private_status,
                route,
                &before,
                should_exit,
            )
            .await;
        let after = private_work(db);
        if let Ok(after) = &after {
            content_failures::unlocked(&self.db_path, &before, after);
        }
        let ran = result?;
        after?;
        Ok(ran)
    }

    #[allow(clippy::too_many_arguments)]
    async fn checkpoint_from<S: zakura_pir_client::status::policy::StatusSource>(
        &mut self,
        db: &mut WalletDatabase,
        client: &mut CompactTxStreamerClient<Channel>,
        cached: Option<&MemoryBlockSource>,
        private_status: S,
        route: &impl zakura_pir_client::enhance::transport::Transport,
        before: &content_failures::PrivateWork,
        should_exit: &(impl Fn() -> bool + Sync),
    ) -> Result<bool, SyncError> {
        self.ready_resubmission.clear();
        // Captured once per checkpoint; the gate re-checks the durable
        // generation before every public request and completing commit.
        let gate = TransparentLookupGate::for_sync(
            self.policy.public_transparent_lookups(db)?,
            &self.db_path,
            self.network,
        )?;
        backfill_stored_fees(client, db, &self.db_path, should_exit).await?;

        // The public source reuses the caller-owned lightwalletd channel; the
        // private source is opened only if private work is asked.
        let public_source = status::lightwalletd_source(client.clone(), gate.clone(), should_exit);
        let mut status_reader = status::RoutedStatusReader::new(public_source, private_status);
        let mut attempted_statuses = HashSet::new();
        let mut history = HistoryPass::default();

        // One pass per checkpoint. Work a reply unlocks (a status that makes
        // a transaction mined, history that names another transaction) waits
        // for the next block. That includes the payload drain that ends the
        // checkpoint: it asks only the private work that existed before.
        let requests = db
            .transaction_data_requests()
            .map_err(|error| SyncError::db(format!("transaction_data_requests: {error}")))?;
        let status_work = db
            .transaction_status_work()
            .map_err(|error| SyncError::db(format!("transaction_status_work: {error}")))?;
        status::run_requests(
            &mut status_reader,
            db,
            &status_work,
            &gate,
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
        history
            .run_requests(
                client,
                db,
                &self.db_path,
                &requests,
                self.network,
                &gate,
                should_exit,
            )
            .await?;
        if should_exit() {
            return Ok(true);
        }

        self.drain(db, client, cached, route, before, should_exit)
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
        let before = private_work(db)?;
        let route = RoutedTransport::new(should_exit);
        let result = self
            .drain(db, client, cached, &route, &before, should_exit)
            .await;
        let after = private_work(db);
        if let Ok(after) = &after {
            content_failures::unlocked(&self.db_path, &before, after);
        }
        let ran = result?;
        after?;
        Ok(ran)
    }

    /// Drains the routed payload work, asking only the private work in
    /// `snapshot`.
    async fn drain(
        &mut self,
        db: &mut WalletDatabase,
        client: &mut CompactTxStreamerClient<Channel>,
        cached: Option<&MemoryBlockSource>,
        route: &impl zakura_pir_client::enhance::transport::Transport,
        snapshot: &content_failures::PrivateWork,
        should_exit: &impl Fn() -> bool,
    ) -> Result<bool, SyncError> {
        self.policy.configure_db(db);
        let gate = TransparentLookupGate::for_sync(
            self.policy.public_transparent_lookups(db)?,
            &self.db_path,
            self.network,
        )?;
        let mut effects =
            ProductionEnhancementEffects::new(self.network, &self.db_path, client, cached, gate);
        self.payload.snapshot = Some(snapshot.clone());
        let result = Box::pin(self.payload.run(db, route, &mut effects, should_exit)).await;
        self.payload.snapshot = None;
        match result {
            Ok(()) => effects.finish().map(|()| false),
            Err(EnhancePirRunError::ExitRequested) => Ok(true),
            Err(EnhancePirRunError::HttpStatus(status)) => Err(SyncError::net(format!(
                "transaction enhancement returned HTTP {status}"
            ))),
            Err(EnhancePirRunError::Failed(error)) => Err(error),
        }
    }
}

/// The wallet's private Enhance work and private status lookups as they
/// stand now.
fn private_work(db: &WalletDatabase) -> Result<content_failures::PrivateWork, SyncError> {
    use zcash_client_backend::data_api::enhance_pir::EnhancePirRead;
    Ok(content_failures::PrivateWork::new(
        db.transaction_enhancement_work()
            .map_err(|error| SyncError::db(format!("transaction_enhancement_work: {error}")))?,
        db.transaction_status_work()
            .map_err(|error| SyncError::db(format!("transaction_status_work: {error}")))?,
    ))
}

#[cfg(test)]
mod tests;
