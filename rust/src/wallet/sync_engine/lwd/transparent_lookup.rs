//! The only path for requests that send a transparent address, script, or txid
//! to public lightwalletd.
//!
//! The raw RPC helpers are private to `lwd`, so a lane can reach them only
//! through [`TransparentLookupGate`], which re-checks authorization
//! immediately before each individual RPC. Per-RPC checks narrow, but cannot
//! close, the window between a check and its dispatch: another connection may
//! commit a transition in between. Closing it needs a transition-side fence
//! (see the enhancement README).

use std::future::Future;
use std::sync::{Arc, Mutex, PoisonError};

use tonic::{transport::Channel, Status};
use zcash_client_backend::data_api::transparent_ledger::AppliedTransparentPolicy;
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, GetAddressUtxosReply, RawTransaction,
};
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{open_wallet_db_readonly_with_timeout, SYNC_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

use super::super::{enhancement::PublicTransparentLookups, SyncError, WalletDatabase};

/// Authority to send transparent lookups to public lightwalletd, re-checked
/// before every RPC and before every commit that completes one.
///
/// Cloning shares the policy-read handle. The handle is a dedicated read-only
/// connection behind a mutex, so futures holding the gate stay `Send`.
#[derive(Clone)]
pub(crate) struct TransparentLookupGate {
    lookups: PublicTransparentLookups,
    policy: Option<Arc<Mutex<WalletDatabase>>>,
}

impl TransparentLookupGate {
    /// Gates lookups captured from a wallet handle. Authority captured under a
    /// durable policy generation is re-checked against the wallet at
    /// `db_path`, so a transition by any connection revokes it.
    pub(crate) fn for_wallet(
        lookups: PublicTransparentLookups,
        db_path: &str,
        network: WalletNetwork,
    ) -> Result<Self, SyncError> {
        let policy = match lookups {
            PublicTransparentLookups::Allowed {
                generation: Some(_),
            } => Some(Arc::new(Mutex::new(
                open_wallet_db_readonly_with_timeout(db_path, network, SYNC_DB_BUSY_TIMEOUT)
                    .map_err(SyncError::db)?,
            ))),
            _ => None,
        };
        Ok(Self { lookups, policy })
    }

    /// Gates lookups made before any wallet database exists. Only the captured
    /// mode applies.
    pub(crate) fn pre_db(lookups: PublicTransparentLookups) -> Self {
        Self {
            lookups,
            policy: None,
        }
    }

    /// Whether lookups were authorized when captured. A cheap early exit only;
    /// every RPC and commit still calls [`Self::permits`].
    pub(crate) fn is_allowed(&self) -> bool {
        self.lookups.is_allowed()
    }

    /// Whether lookups are still authorized. Call it immediately before a
    /// commit that completes a lookup, such as acknowledging a checked range.
    pub(crate) fn permits(&self) -> Result<bool, SyncError> {
        match &self.policy {
            None => Ok(self.lookups.is_allowed()),
            Some(policy) => self
                .lookups
                .still_allowed(&policy.lock().unwrap_or_else(PoisonError::into_inner)),
        }
    }

    /// Whether `applied`, read by the caller, still authorizes these lookups.
    /// Read it in the same SQLite transaction as a completing write to make
    /// that write's check atomic with it.
    pub(crate) fn permits_applied(&self, applied: AppliedTransparentPolicy) -> bool {
        self.lookups.permits(applied)
    }

    /// Runs `rpc` only if lookups are still authorized. `rpc` is lazy, so the
    /// check precedes the request on the wire; `None` means withheld.
    pub(crate) async fn dispatch<F: Future>(&self, rpc: F) -> Result<Option<F::Output>, SyncError> {
        if !self.permits()? {
            return Ok(None);
        }
        #[cfg(test)]
        test_hooks::dispatched();
        Ok(Some(rpc.await))
    }

    /// `GetAddressUtxosStream` for `addresses` from `start_height`.
    pub(crate) async fn address_utxos(
        &self,
        client: &mut CompactTxStreamerClient<Channel>,
        addresses: Vec<String>,
        start_height: BlockHeight,
    ) -> Result<Option<tonic::Streaming<GetAddressUtxosReply>>, SyncError> {
        self.dispatch(super::get_address_utxos_stream(
            client,
            addresses,
            start_height,
        ))
        .await?
        .transpose()
    }

    /// `GetTaddressTxids` for `address` over `start_height..=end_height`.
    pub(crate) async fn taddress_txids(
        &self,
        client: &mut CompactTxStreamerClient<Channel>,
        address: String,
        start_height: u64,
        end_height: u64,
    ) -> Result<Option<tonic::Streaming<RawTransaction>>, SyncError> {
        self.dispatch(super::get_taddress_txids(
            client,
            address,
            start_height,
            end_height,
        ))
        .await?
        .transpose()
    }

    /// `GetTransaction` for `txid`. The inner result keeps the gRPC status so
    /// callers can classify "not found".
    pub(crate) async fn transaction(
        &self,
        client: &mut CompactTxStreamerClient<Channel>,
        txid: TxId,
    ) -> Result<Option<Result<RawTransaction, Status>>, SyncError> {
        self.dispatch(super::get_transaction_payload(client, txid))
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::{db::open_wallet_db_with_timeout, keys};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use zcash_client_backend::data_api::transparent_ledger::{
        TransparentLedgerMode, TransparentLedgerWrite,
    };

    use super::super::super::enhancement::EnhancementPolicy;

    fn wallet() -> (tempfile::TempDir, String, TransparentLookupGate) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let network = WalletNetwork::Regtest;
        let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
        keys::init_db_and_create_account(&path, network, &seed, Some(100), "gate").unwrap();
        let db = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
        let lookups = EnhancementPolicy::current(network)
            .public_transparent_lookups(&db)
            .unwrap();
        let gate = TransparentLookupGate::for_wallet(lookups, &path, network).unwrap();
        (dir, path, gate)
    }

    fn apply(path: &str, mode: TransparentLedgerMode) {
        open_wallet_db_with_timeout(path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
            .unwrap()
            .apply_transparent_policy(mode)
            .unwrap();
    }

    /// Counts how often the "RPC" actually runs.
    async fn rpc(sent: &AtomicUsize) -> usize {
        sent.fetch_add(1, Ordering::SeqCst) + 1
    }

    #[tokio::test]
    async fn every_dispatch_rechecks_the_durable_policy() {
        let (_dir, path, gate) = wallet();
        let sent = AtomicUsize::new(0);
        assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), Some(1));

        // A clone shares the policy handle; the transition revokes both.
        let clone = gate.clone();
        apply(&path, TransparentLedgerMode::PrivateShadow);
        assert!(
            gate.is_allowed(),
            "the captured value is only an early exit"
        );
        assert!(!gate.permits().unwrap());
        assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), None);
        assert_eq!(clone.dispatch(rpc(&sent)).await.unwrap(), None);
        assert_eq!(sent.load(Ordering::SeqCst), 1, "a withheld RPC never runs");

        // The captured generation never comes back: a newer one is not it.
        apply(&path, TransparentLedgerMode::Public);
        assert!(!gate.permits().unwrap());
    }

    #[tokio::test]
    async fn a_stricter_durable_policy_fails_closed() {
        let (_dir, path, gate) = wallet();
        apply(&path, TransparentLedgerMode::PrivateRequired);
        let sent = AtomicUsize::new(0);
        // This build's Public read handle cannot read the stricter policy.
        assert!(gate.dispatch(rpc(&sent)).await.is_err());
        assert_eq!(sent.load(Ordering::SeqCst), 0);
    }

    #[tokio::test]
    async fn pre_db_gates_apply_only_the_captured_mode() {
        let sent = AtomicUsize::new(0);
        let allowed =
            TransparentLookupGate::pre_db(PublicTransparentLookups::Allowed { generation: None });
        assert_eq!(allowed.dispatch(rpc(&sent)).await.unwrap(), Some(1));
        let withheld = TransparentLookupGate::pre_db(PublicTransparentLookups::Withheld);
        assert_eq!(withheld.dispatch(rpc(&sent)).await.unwrap(), None);
        assert_eq!(sent.load(Ordering::SeqCst), 1);
    }
}

/// Test seam: runs a hook synchronously after each authorized dispatch check,
/// before the RPC is polled, so a test can land a policy transition between
/// two requests of one concurrent batch. Scoped to the calling thread, which
/// is where a `#[tokio::test]` runtime polls every lane future.
#[cfg(test)]
pub(crate) mod test_hooks {
    use std::cell::RefCell;

    thread_local! {
        static ON_DISPATCH: RefCell<Option<Box<dyn FnMut()>>> = RefCell::new(None);
    }

    pub(crate) struct DispatchHook(());

    impl Drop for DispatchHook {
        fn drop(&mut self) {
            ON_DISPATCH.with(|hook| hook.borrow_mut().take());
        }
    }

    pub(crate) fn on_dispatch(hook: impl FnMut() + 'static) -> DispatchHook {
        ON_DISPATCH.with(|slot| *slot.borrow_mut() = Some(Box::new(hook)));
        DispatchHook(())
    }

    pub(super) fn dispatched() {
        ON_DISPATCH.with(|hook| {
            if let Some(hook) = hook.borrow_mut().as_mut() {
                hook();
            }
        });
    }
}
