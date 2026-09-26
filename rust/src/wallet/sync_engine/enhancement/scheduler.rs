//! Unified scheduler for payload work already routed by the wallet.
//!
//! A bounded pass handles private work first, rereads the atomic routing
//! snapshot, and dispatches only explicitly public requests to lightwalletd.

use tonic::transport::Channel;
use zakura_pir_enhance::transport;
use zakura_pir_enhance::wallet::{Acceptance, PreparedWork};
use zakura_pir_enhance::{ClientResourceLimits, Manifest};
use zcash_client_backend::{
    data_api::{
        enhance_pir::{
            EnhancePirRead, EnhancePirRequest, EnhancePirStoreResult, EnhancePirWork,
            EnhancePirWrite, IronwoodEnhanceDiscoveryRequest, IronwoodEnhanceDiscoveryResult,
            TransactionEnhancementWork,
        },
        PublicTransactionEnhancementRequest,
    },
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};

use crate::wallet::{db::with_wallet_db_write_lock, network::WalletNetwork};

use super::{
    super::{
        super::{block_source::MemoryBlockSource, SyncError, WalletDatabase},
        transport::await_request_with_cancel,
    },
    private_pir::{rediscovery_cover_start, EnhancePirRunError, RoutedPayloadEnhancement},
    public_lwd::PublicPayloadExecutor,
};

/// Servicing one route can create work on the other.
const MAX_ROUTED_PASSES: usize = 3;
pub(super) const MAX_LOGICAL_ROWS: u64 = 65_536;

/// One routed enhancement snapshot, split by transport.
#[derive(Debug, Default, PartialEq, Eq)]
pub(in crate::wallet::sync_engine) struct RoutedWork {
    pub(super) public: Vec<PublicTransactionEnhancementRequest>,
    pub(super) private: Vec<EnhancePirWork>,
}

impl RoutedWork {
    fn new(work: impl IntoIterator<Item = TransactionEnhancementWork>) -> Self {
        let mut routed = Self::default();
        for work in work {
            match work {
                TransactionEnhancementWork::Public(request) => routed.public.push(request),
                TransactionEnhancementWork::Private(work) => routed.private.push(work),
            }
        }
        routed
    }

    pub(super) fn prepared(&self) -> PreparedWork {
        PreparedWork::new(self.private.iter().copied())
    }

    fn is_empty(&self) -> bool {
        self.public.is_empty() && self.private.is_empty()
    }
}

/// Storage boundary for recovery scheduling. The production adapter retains
/// wallet anchor validation, record authentication, and serialized writes.
pub(in crate::wallet::sync_engine) trait RecoveryWallet {
    /// Reads the wallet's single routed snapshot; never a second routing source.
    fn work(&self) -> Result<RoutedWork, EnhancePirRunError>;
    fn accept(
        &self,
        network: WalletNetwork,
        manifest: &Manifest,
    ) -> Result<Acceptance, EnhancePirRunError>;
    fn apply(
        &mut self,
        request: EnhancePirRequest,
        record: &zakura_pir_enhance::EnhanceRecord,
    ) -> Result<EnhancePirStoreResult, EnhancePirRunError>;
}

impl RecoveryWallet for WalletDatabase {
    fn work(&self) -> Result<RoutedWork, EnhancePirRunError> {
        Ok(RoutedWork::new(
            self.transaction_enhancement_work()
                .map_err(|e| SyncError::db(e.to_string()))?,
        ))
    }
    fn accept(
        &self,
        network: WalletNetwork,
        manifest: &Manifest,
    ) -> Result<Acceptance, EnhancePirRunError> {
        Ok(zakura_pir_enhance::wallet::acceptance(
            self,
            manifest,
            &network,
            ClientResourceLimits::new(MAX_LOGICAL_ROWS),
        )
        .map_err(|e| SyncError::db(e.to_string()))??)
    }
    fn apply(
        &mut self,
        request: EnhancePirRequest,
        record: &zakura_pir_enhance::EnhanceRecord,
    ) -> Result<EnhancePirStoreResult, EnhancePirRunError> {
        Ok(with_wallet_db_write_lock("enhance_pir.apply", || {
            self.apply_ironwood_enhance_record(request, record)
        })
        .map_err(|e| SyncError::db(e.to_string()))?)
    }
}

/// Work outside Enhance PIR that a routed pass dispatches. Production uses
/// lightwalletd; scheduler tests substitute a recording fake.
pub(in crate::wallet::sync_engine) trait EnhancementEffects<W> {
    /// Obtains the compact block for `request` and applies reconstruction.
    async fn rediscover(
        &mut self,
        db: &mut W,
        request: IronwoodEnhanceDiscoveryRequest,
        should_exit: &impl Fn() -> bool,
    ) -> Result<(), EnhancePirRunError>;

    /// Retrieves routed public payloads. Failures are retained for the caller;
    /// they never change routing.
    async fn public(
        &mut self,
        db: &mut W,
        requests: &[PublicTransactionEnhancementRequest],
        should_exit: &impl Fn() -> bool,
    );
}

/// Production effects: cached or downloaded compact blocks and lightwalletd payloads.
pub(in crate::wallet::sync_engine) struct ProductionEnhancementEffects<'a> {
    network: WalletNetwork,
    db_path: &'a str,
    lwd: &'a mut CompactTxStreamerClient<Channel>,
    cached: Option<&'a MemoryBlockSource>,
    public: PublicPayloadExecutor,
}

impl<'a> ProductionEnhancementEffects<'a> {
    pub(in crate::wallet::sync_engine) fn new(
        network: WalletNetwork,
        db_path: &'a str,
        lwd: &'a mut CompactTxStreamerClient<Channel>,
        cached: Option<&'a MemoryBlockSource>,
    ) -> Self {
        Self {
            network,
            db_path,
            lwd,
            cached,
            public: PublicPayloadExecutor::default(),
        }
    }

    /// Reports the first retryable public payload failure from this run.
    pub(in crate::wallet::sync_engine) fn finish(self) -> Result<(), SyncError> {
        self.public.finish()
    }
}

impl EnhancementEffects<WalletDatabase> for ProductionEnhancementEffects<'_> {
    async fn rediscover(
        &mut self,
        db: &mut WalletDatabase,
        request: IronwoodEnhanceDiscoveryRequest,
        should_exit: &impl Fn() -> bool,
    ) -> Result<(), EnhancePirRunError> {
        let downloaded;
        let block = if let Some(block) = self
            .cached
            .and_then(|source| source.block_at(request.height))
        {
            block
        } else {
            // Fetch a trailing cover range rather than one isolated block.
            // Accepted limitation: the requested height remains the range endpoint,
            // so an informed lightwalletd can still infer the height of interest.
            downloaded = await_request_with_cancel(
                crate::wallet::sync_engine::lwd::download_blocks(
                    self.lwd,
                    rediscovery_cover_start(request.height),
                    request.height,
                    self.network,
                ),
                should_exit,
                "rediscovery download timed out",
            )
            .await?;
            downloaded
                .block_at(request.height)
                .ok_or_else(|| SyncError::parse("rediscovery block missing"))?
        };
        if should_exit() {
            return Err(EnhancePirRunError::ExitRequested);
        }
        let result = with_wallet_db_write_lock("enhance_pir.rediscover", || {
            db.rebuild_ironwood_enhancement(request, block)
        })
        .map_err(|e| SyncError::db(e.to_string()))?;
        if matches!(result, IronwoodEnhanceDiscoveryResult::Rejected) {
            return Err(SyncError::parse("rediscovery block rejected").into());
        }
        Ok(())
    }

    async fn public(
        &mut self,
        db: &mut WalletDatabase,
        requests: &[PublicTransactionEnhancementRequest],
        should_exit: &impl Fn() -> bool,
    ) {
        self.public
            .run(
                self.lwd,
                db,
                self.db_path,
                self.network,
                requests,
                should_exit,
            )
            .await;
    }
}

impl RoutedPayloadEnhancement {
    /// Services one routed snapshot in bounded passes: rediscovery, private
    /// queries, a reread, then routed public payloads. Passes repeat only while
    /// the durable snapshot changes. Private failures defer PIR for this sync
    /// session and never dispatch public work; only a routed public request
    /// reaches lightwalletd. Cancellation stops before the next dispatch.
    pub(in crate::wallet::sync_engine) async fn run<W: RecoveryWallet, E: EnhancementEffects<W>>(
        &mut self,
        db: &mut W,
        route: &impl transport::Transport,
        effects: &mut E,
        should_exit: &impl Fn() -> bool,
    ) -> Result<(), EnhancePirRunError> {
        let mut previous = None;
        for _ in 0..MAX_ROUTED_PASSES {
            if should_exit() {
                return Err(EnhancePirRunError::ExitRequested);
            }
            let work = db.work()?;
            if work.is_empty() || previous.as_ref() == Some(&work) {
                break;
            }
            if self.private_work_enabled() && !work.private.is_empty() {
                match self
                    .run_private(db, route, effects, &work, should_exit)
                    .await
                {
                    Ok(()) => {}
                    Err(EnhancePirRunError::ExitRequested) => {
                        return Err(EnhancePirRunError::ExitRequested)
                    }
                    Err(error) => self.defer_after(error),
                }
            }
            // Applying a record can atomically move a transaction to LWD, and
            // rediscovery can resolve a mixed shape; dispatch that in this pass.
            let routed = db.work()?;
            if should_exit() {
                return Err(EnhancePirRunError::ExitRequested);
            }
            if !routed.public.is_empty() {
                effects.public(db, &routed.public, should_exit).await;
            }
            previous = Some(work);
        }
        if should_exit() {
            return Err(EnhancePirRunError::ExitRequested);
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "scheduler_tests.rs"]
mod tests;
