//! Transaction-status source policy.
//!
//! A reader selects exactly one source for its lifetime. When private Status
//! PIR is selected, initialization or observation failure is inconclusive and
//! must not fall back to a public transaction-ID request.

mod private;
mod public;
mod store;

use std::collections::HashSet;

use zakura_transaction_status::{StatusReader, StatusRequest, StatusSource};
use zcash_client_backend::data_api::TransactionDataRequest;
use zcash_primitives::transaction::TxId;

use super::policy::EnhancementPolicy;
use crate::wallet::{
    network::WalletNetwork,
    sync_engine::{SyncError, WalletDatabase},
};

pub(crate) use private::PrivateStatusSource;
pub(super) use public::lightwalletd_source;
pub(super) use store::persist_status_observation;

/// Selects one status source from the operation's immutable policy. The
/// unselected source remains lazy and is never opened as fallback.
pub(crate) fn reader<'a, F, P>(
    db_path: &'a str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    should_exit: &'a F,
    public_source: P,
) -> StatusReader<P, PrivateStatusSource<'a, F>>
where
    F: Fn() -> bool + Sync,
    P: StatusSource,
{
    StatusReader::new(
        policy.status_mode(),
        public_source,
        PrivateStatusSource::new(db_path, network, should_exit, false),
    )
}

pub(super) async fn run_requests<P, R>(
    reader: &mut StatusReader<P, R>,
    db: &mut WalletDatabase,
    requests: &[TransactionDataRequest],
    observed: &mut HashSet<TxId>,
    should_exit: &impl Fn() -> bool,
) -> Result<bool, SyncError>
where
    P: StatusSource,
    R: StatusSource,
{
    let pending: Vec<_> = requests
        .iter()
        .cloned()
        .filter_map(TransactionDataRequest::into_status_request)
        .filter(|request| !observed.contains(&request.txid()))
        .collect();
    let actionable = !pending.is_empty();

    for request in pending {
        let txid = request.txid();
        let observation = match reader
            .observe(StatusRequest {
                txid,
                coverage: zakura_pir_status::LocalCoverageContext::default(),
            })
            .await
        {
            Ok(observation) => observation.into(),
            Err(zakura_transaction_status::StatusError::Cancelled) => return Ok(actionable),
            Err(error) => return Err(SyncError::net(error.to_string())),
        };
        if should_exit() {
            return Ok(actionable);
        }
        persist_status_observation(db, txid, observation)?;
        observed.insert(txid);
    }

    Ok(actionable)
}
