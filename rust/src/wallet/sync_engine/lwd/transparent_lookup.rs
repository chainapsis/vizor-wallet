//! The only path for requests that send a transparent address, script, or txid
//! to public lightwalletd.
//!
//! The raw RPC helpers are private to `lwd`, so a lane can reach them only
//! through [`TransparentLookupGate`], which re-checks authorization
//! immediately before each individual RPC.
//!
//! A per-RPC check alone cannot close the window between the check and the
//! request: a transition could commit in between. The in-process policy fence
//! closes it. Every dispatch holds a shared lease from its check until its
//! request has been sent, and [`apply_transparent_policy_fenced_if`], the
//! only way this build applies a transparent policy, takes the exclusive
//! side. A waiting transition blocks new leases, waits for in-flight requests
//! to drain, and only then commits, so no request authorized under the old
//! policy is sent after the new one applies. A transition made by another
//! process is outside the fence; the per-RPC check still bounds it to the
//! requests already in flight.

use std::future::Future;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use tokio::sync::RwLock;
use tonic::{transport::Channel, Status};
use zcash_client_backend::data_api::transparent_ledger::{
    AppliedTransparentPolicy, TransparentLedgerMode, TransparentLedgerWrite,
};
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, GetAddressUtxosReply, RawTransaction,
};
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{open_wallet_db_readonly_with_timeout, with_wallet_db_write_lock, SYNC_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

/// Shared by every public transparent lookup in flight; held exclusively by a
/// policy transition. Tokio's lock is fair: once a transition waits, new
/// leases queue behind it.
static POLICY_FENCE: RwLock<()> = RwLock::const_new(());

/// Durably applies `mode` as the wallet's transparent policy behind the fence,
/// if `still` holds for `db` when it is checked there.
///
/// Blocks new public lookups at once, waits up to `drain` for requests already
/// in flight, then checks `still` and commits. The check runs after those
/// lookups drained and before any other fenced transition can commit, so a
/// decision it makes, including one read from `db`, cannot be overtaken by a
/// concurrent transition. If the lookups do not drain in time, nothing is
/// applied and the error says so; the caller retries. Lookups resumed after
/// the transition re-check the new policy and are withheld unless it keeps
/// public authority under the generation they captured, which it never does.
///
/// Returns `None`, having applied nothing, when `still` does not hold. An
/// error from `still` also applies nothing.
pub(crate) async fn apply_transparent_policy_fenced_if(
    db: &mut WalletDatabase,
    mode: TransparentLedgerMode,
    drain: Duration,
    still: impl FnOnce(&WalletDatabase) -> Result<bool, SyncError>,
) -> Result<Option<AppliedTransparentPolicy>, SyncError> {
    let _fence = tokio::time::timeout(drain, POLICY_FENCE.write())
        .await
        .map_err(|_| SyncError::db("transparent policy: public lookups did not drain in time"))?;
    if !still(db)? {
        return Ok(None);
    }
    with_wallet_db_write_lock("sync_engine.transparent_policy.apply", || {
        db.apply_transparent_policy(mode)
    })
    .map(Some)
    .map_err(|error| SyncError::db(format!("apply_transparent_policy: {error}")))
}

/// [`apply_transparent_policy_fenced_if`] without a condition.
#[cfg(test)]
pub(crate) async fn apply_transparent_policy_fenced(
    db: &mut WalletDatabase,
    mode: TransparentLedgerMode,
    drain: Duration,
) -> Result<AppliedTransparentPolicy, SyncError> {
    match apply_transparent_policy_fenced_if(db, mode, drain, |_| Ok(true)).await? {
        Some(applied) => Ok(applied),
        None => unreachable!("an unconditional transition always applies"),
    }
}

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

    /// One public lookup the user asked for, on one transaction, whatever the
    /// wallet's transparent policy: the request itself is the consent. Only
    /// [`crate::wallet::sync_engine::transparent_details::enhance_publicly`]
    /// constructs it; no automatic path may.
    pub(crate) fn user_requested() -> Self {
        Self {
            lookups: PublicTransparentLookups::Allowed { generation: None },
            policy: None,
        }
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
    ///
    /// Holds a policy-fence lease from the check until `rpc` completes, so a
    /// fenced transition cannot commit between the two.
    pub(crate) async fn dispatch<F: Future>(&self, rpc: F) -> Result<Option<F::Output>, SyncError> {
        let _lease = POLICY_FENCE.read().await;
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

    /// A request in flight when a fenced transition starts is sent under the
    /// policy it was checked against, and the transition commits only after it.
    /// Without the fence, the transition would commit mid-request.
    #[tokio::test]
    async fn a_fenced_transition_waits_for_in_flight_lookups() {
        let (_dir, path, gate) = wallet();
        let (release, released) = tokio::sync::oneshot::channel::<()>();
        let in_flight = tokio::spawn({
            let gate = gate.clone();
            async move { gate.dispatch(async { released.await.unwrap() }).await }
        });
        // Let the dispatch take its lease and pass its check.
        tokio::time::sleep(Duration::from_millis(50)).await;

        let mut db =
            open_wallet_db_with_timeout(&path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
                .unwrap();
        let blocked = apply_transparent_policy_fenced(
            &mut db,
            TransparentLedgerMode::PrivateShadow,
            Duration::from_millis(100),
        )
        .await;
        assert!(blocked.is_err(), "the request is still in flight");
        assert!(
            gate.permits().unwrap(),
            "a transition that could not drain applies nothing"
        );

        release.send(()).unwrap();
        assert_eq!(in_flight.await.unwrap().unwrap(), Some(()));
        apply_transparent_policy_fenced(
            &mut db,
            TransparentLedgerMode::PrivateShadow,
            Duration::from_secs(5),
        )
        .await
        .unwrap();
        let sent = AtomicUsize::new(0);
        assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), None);
        assert_eq!(sent.load(Ordering::SeqCst), 0);
    }

    /// Once a transition waits, a new lookup cannot start ahead of it: it
    /// resumes after the commit and is withheld.
    #[tokio::test]
    async fn a_waiting_transition_blocks_new_lookups() {
        let (_dir, path, gate) = wallet();
        let (release, released) = tokio::sync::oneshot::channel::<()>();
        let in_flight = tokio::spawn({
            let gate = gate.clone();
            async move { gate.dispatch(async { released.await.unwrap() }).await }
        });
        tokio::time::sleep(Duration::from_millis(50)).await;

        let transition = tokio::spawn(async move {
            let mut db =
                open_wallet_db_with_timeout(&path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
                    .unwrap();
            apply_transparent_policy_fenced(
                &mut db,
                TransparentLedgerMode::PrivateShadow,
                Duration::from_secs(5),
            )
            .await
        });
        tokio::time::sleep(Duration::from_millis(50)).await;

        let sent = Arc::new(AtomicUsize::new(0));
        let late = tokio::spawn({
            let gate = gate.clone();
            let sent = sent.clone();
            async move { gate.dispatch(async move { rpc(&sent).await }).await }
        });
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert_eq!(
            sent.load(Ordering::SeqCst),
            0,
            "queued behind the transition"
        );

        release.send(()).unwrap();
        in_flight.await.unwrap().unwrap();
        transition.await.unwrap().unwrap();
        assert_eq!(late.await.unwrap().unwrap(), None);
        assert_eq!(
            sent.load(Ordering::SeqCst),
            0,
            "withheld under the new policy"
        );
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
