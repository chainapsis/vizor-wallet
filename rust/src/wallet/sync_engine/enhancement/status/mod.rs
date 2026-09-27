//! Transaction-status source policy.
//!
//! A reader selects exactly one source for its lifetime. When private Status
//! PIR is selected, initialization or observation failure is inconclusive and
//! must not fall back to a public transaction-ID request.

mod private;
mod public;
mod store;

use std::collections::HashSet;

use crate::wallet::{
    network::WalletNetwork,
    sync_engine::{SyncError, WalletDatabase},
};
use zakura_transaction_status::{
    DisabledSource, StatusError, StatusMode, StatusObservation, StatusReader, StatusRequest,
    StatusSource,
};
use zcash_client_backend::data_api::{status::TransactionStatusWork, WalletRead};
use zcash_primitives::transaction::TxId;

pub(crate) use private::PrivateStatusSource;
pub(super) use public::lightwalletd_source;
#[cfg(test)]
pub(super) use store::persist_status_observation;

/// Both sources are lazy. The work variant is the only dispatch authority; there is no
/// fallback and no second policy decision when servicing a snapshot.
pub(crate) struct RoutedStatusReader<P: StatusSource, R: StatusSource> {
    public: StatusReader<P, DisabledSource>,
    private: StatusReader<DisabledSource, R>,
}
impl<P: StatusSource, R: StatusSource> RoutedStatusReader<P, R> {
    pub(crate) fn new(public: P, private: R) -> Self {
        Self {
            public: StatusReader::new(StatusMode::PublicLightwalletd, public, DisabledSource),
            private: StatusReader::new(StatusMode::PrivatePir, DisabledSource, private),
        }
    }
    pub(crate) async fn observe(
        &mut self,
        work: TransactionStatusWork,
        required_through: Option<u32>,
    ) -> Result<StatusObservation, StatusError> {
        match work {
            TransactionStatusWork::Public(request) => {
                self.public
                    .observe(StatusRequest {
                        txid: request.txid(),
                        coverage: Default::default(),
                    })
                    .await
            }
            TransactionStatusWork::Private(request) => {
                self.private
                    .observe(StatusRequest {
                        txid: request.txid(),
                        coverage: zakura_pir_status::LocalCoverageContext {
                            earliest_possible_inclusion: request
                                .earliest_possible_inclusion()
                                .map(u32::from),
                            required_through,
                        },
                    })
                    .await
            }
        }
    }
}

pub(crate) fn reader<'a, F, P>(
    db_path: &'a str,
    network: WalletNetwork,
    should_exit: &'a F,
    public_source: P,
) -> RoutedStatusReader<P, PrivateStatusSource<'a, F>>
where
    F: Fn() -> bool + Sync,
    P: StatusSource,
{
    RoutedStatusReader::new(
        public_source,
        PrivateStatusSource::new(db_path, network, should_exit, false),
    )
}

pub(super) async fn run_requests<P, R>(
    reader: &mut RoutedStatusReader<P, R>,
    db: &mut WalletDatabase,
    work: &[TransactionStatusWork],
    attempted: &mut HashSet<TxId>,
    should_exit: &impl Fn() -> bool,
) -> Result<bool, SyncError>
where
    P: StatusSource,
    R: StatusSource,
{
    let pending: Vec<_> = work
        .iter()
        .copied()
        .filter(|work| !attempted.contains(&work.txid()))
        .collect();
    let actionable = !pending.is_empty();
    // set_transaction_status evaluates absence against this database's advertised chain tip.
    let required_through = db
        .chain_height()
        .map_err(|e| SyncError::db(e.to_string()))?
        .map(u32::from);
    let decision_hash = match required_through {
        Some(height) => db
            .get_block_hash(zcash_protocol::consensus::BlockHeight::from_u32(height))
            .map_err(|e| SyncError::db(e.to_string()))?,
        None => None,
    };
    for work in pending {
        if should_exit() {
            return Ok(actionable);
        }
        let txid = work.txid();
        attempted.insert(txid);
        let observation = match reader.observe(work, required_through).await {
            Ok(observation) => observation.into(),
            Err(StatusError::CoverageIncomplete) => {
                log::debug!("Status coverage incomplete; deferring pending observation");
                continue;
            }
            Err(StatusError::Cancelled) => return Ok(actionable),
            Err(error) => return Err(SyncError::net(error.to_string())),
        };
        if should_exit() {
            return Ok(actionable);
        }
        store::persist_work_observation(db, work, observation, required_through, decision_hash)?;
    }
    Ok(actionable)
}
