//! The only path for requests that send a transparent address, script, or txid
//! to public lightwalletd.
//!
//! The raw RPC helpers are private to `lwd`, so a lane can reach them only
//! through [`TransparentLookupGate`], which re-checks authorization
//! immediately before each individual RPC.
//!
//! A per-RPC check alone cannot close the window between the check and the
//! request: a transition could commit in between. The in-process policy fence
//! closes it. Each wallet database has its own fence, so a transition on one
//! wallet never waits for another's lookups. Every dispatch holds a shared
//! lease from its check until its request has been handed to the transport,
//! and [`apply_transparent_policy_fenced_if`], the only way this build applies
//! a transparent policy, takes the exclusive side. A waiting transition blocks
//! new leases, waits for in-flight requests to be sent, and only then commits,
//! so no request authorized under the old policy is sent after the new one
//! applies. A gate given its transport ([`TransparentLookupGate::with_transport`],
//! or the sync's registered one) observes the hand-off with
//! [`DispatchSignalService`] and releases its lease there, never waiting for a
//! slow response; without one, the lease lasts until the call returns. Waits
//! are bounded on both sides: a lookup that cannot get its lease in
//! [`LEASE_WAIT`] is withheld, and a transition gives up, applying nothing,
//! when lookups do not drain or the wallet write lock is not free within its
//! drain budget. A transition made by another process is outside the fence;
//! the per-RPC check still bounds it to the requests already in flight.

use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, LazyLock, Mutex, PoisonError};
use std::time::{Duration, Instant};

use tokio::sync::{OwnedRwLockReadGuard, RwLock};
use tonic::{transport::Channel, Status};
use zcash_client_backend::data_api::transparent_ledger::{
    AppliedTransparentPolicy, TransparentLedgerMode, TransparentLedgerWrite,
};
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, GetAddressUtxosReply, RawTransaction,
};
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;

use super::dispatch_signal::{DispatchSignalService, Dispatched};
use crate::wallet::{
    db::{
        open_wallet_db_readonly_with_timeout, with_wallet_db_write_lock_until, SYNC_DB_BUSY_TIMEOUT,
    },
    network::WalletNetwork,
};

/// How long a lookup waits for its lease. A transition drains for at most its
/// own budget, then commits at once, so a lookup queued behind it gets its
/// lease well within this; one that does not is withheld.
pub(crate) const LEASE_WAIT: Duration = Duration::from_secs(45);

/// One fence per wallet database path, shared by every public transparent
/// lookup on that wallet and held exclusively by its policy transition.
/// Tokio's lock is fair: once a transition waits, new leases queue behind it.
/// Entries nobody holds are dropped as others are added.
static POLICY_FENCES: LazyLock<Mutex<HashMap<String, Arc<RwLock<()>>>>> =
    LazyLock::new(Default::default);

/// The fence of the wallet at `db_path`, or of pre-database lookups.
fn fence(key: &str) -> Arc<RwLock<()>> {
    let mut fences = POLICY_FENCES.lock().unwrap_or_else(PoisonError::into_inner);
    fences.retain(|_, fence| Arc::strong_count(fence) > 1);
    fences.entry(key.to_owned()).or_default().clone()
}

/// The transport the running sync's lookups on each wallet go over, so their
/// gates can release their leases at hand-off. Registered for the sync's
/// lifetime by [`register_sync_transport`].
static SYNC_TRANSPORTS: LazyLock<Mutex<HashMap<String, Channel>>> = LazyLock::new(Default::default);

/// Keeps a sync transport registered until dropped.
pub(crate) struct SyncTransport(String);

impl Drop for SyncTransport {
    fn drop(&mut self) {
        SYNC_TRANSPORTS
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .remove(&self.0);
    }
}

/// Registers `transport`, the one the sync built its lightwalletd client on,
/// for the gates of the sync's lanes on the wallet at `db_path`
/// ([`TransparentLookupGate::for_sync`]).
pub(crate) fn register_sync_transport(db_path: &str, transport: Channel) -> SyncTransport {
    SYNC_TRANSPORTS
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .insert(db_path.to_owned(), transport);
    SyncTransport(db_path.to_owned())
}

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
///
/// `db` is a handle on the wallet at `db_path`, whose fence the transition
/// takes, as do lookups made before that wallet's database existed. The wallet
/// write lock is taken with
/// whatever remains of `drain`, never waited on without bound while the fence
/// holds lookups back.
pub(crate) async fn apply_transparent_policy_fenced_if(
    db: &mut WalletDatabase,
    db_path: &str,
    mode: TransparentLedgerMode,
    drain: Duration,
    still: impl FnOnce(&WalletDatabase) -> Result<bool, SyncError>,
) -> Result<Option<AppliedTransparentPolicy>, SyncError> {
    let deadline = Instant::now() + drain;
    let drained = || SyncError::db("transparent policy: public lookups did not drain in time");
    let wallet = fence(db_path);
    let _wallet = tokio::time::timeout_at(deadline.into(), wallet.write())
        .await
        .map_err(|_| drained())?;
    if !still(db)? {
        return Ok(None);
    }
    with_wallet_db_write_lock_until("sync_engine.transparent_policy.apply", deadline, || {
        db.apply_transparent_policy(mode)
    })
    .map_err(|error| SyncError::db(format!("transparent policy: {error}")))?
    .map(Some)
    .map_err(|error| SyncError::db(format!("apply_transparent_policy: {error}")))
}

/// [`apply_transparent_policy_fenced_if`] without a condition.
#[cfg(test)]
pub(crate) async fn apply_transparent_policy_fenced(
    db: &mut WalletDatabase,
    db_path: &str,
    mode: TransparentLedgerMode,
    drain: Duration,
) -> Result<AppliedTransparentPolicy, SyncError> {
    match apply_transparent_policy_fenced_if(db, db_path, mode, drain, |_| Ok(true)).await? {
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
    /// The fence of the wallet these lookups are about.
    fence: Arc<RwLock<()>>,
    /// The transport the caller's client was built on, when known: lookups
    /// then go over it with a dispatch signal and release their lease at
    /// hand-off.
    transport: Option<Channel>,
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
        Ok(Self {
            lookups,
            policy,
            fence: fence(db_path),
            transport: None,
        })
    }

    /// [`Self::for_wallet`] for a lane of the running sync: its lookups go
    /// over the transport the sync registered for the wallet, if any.
    pub(crate) fn for_sync(
        lookups: PublicTransparentLookups,
        db_path: &str,
        network: WalletNetwork,
    ) -> Result<Self, SyncError> {
        let gate = Self::for_wallet(lookups, db_path, network)?;
        let transport = SYNC_TRANSPORTS
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(db_path)
            .cloned();
        Ok(match transport {
            Some(transport) => gate.with_transport(transport),
            None => gate,
        })
    }

    /// Sends this gate's lookups over `transport`, the one the caller's
    /// client was built on, releasing each lease once its request is handed
    /// to it.
    pub(crate) fn with_transport(mut self, transport: Channel) -> Self {
        self.transport = Some(transport);
        self
    }

    /// One public lookup the user asked for, on one transaction, whatever the
    /// wallet's transparent policy: the request itself is the consent. Only
    /// [`crate::wallet::sync_engine::transparent_details::enhance_publicly`]
    /// constructs it; no automatic path may.
    pub(crate) fn user_requested(db_path: &str) -> Self {
        Self {
            lookups: PublicTransparentLookups::Allowed { generation: None },
            policy: None,
            fence: fence(db_path),
            transport: None,
        }
    }

    /// Gates lookups made before the wallet database at `db_path` exists, as
    /// for a first account's import. Only the captured mode applies; the
    /// lookups take that wallet's fence, so only its own transition waits for
    /// them.
    pub(crate) fn pre_database(lookups: PublicTransparentLookups, db_path: &str) -> Self {
        Self {
            lookups,
            policy: None,
            fence: fence(db_path),
            transport: None,
        }
    }

    /// [`Self::pre_database`] for a test, on a fence of its own.
    #[cfg(test)]
    pub(crate) fn pre_db(lookups: PublicTransparentLookups) -> Self {
        Self::pre_database(lookups, &format!("test-pre-db-{}", uuid::Uuid::new_v4()))
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

    /// A lease on this gate's fence, if lookups are still authorized once it
    /// is held; `None` means withheld, including when no lease is free within
    /// [`LEASE_WAIT`].
    async fn lease(&self) -> Result<Option<OwnedRwLockReadGuard<()>>, SyncError> {
        let Ok(lease) = tokio::time::timeout(LEASE_WAIT, self.fence.clone().read_owned()).await
        else {
            log::info!("transparent lookup: a policy transition held the fence; withheld");
            return Ok(None);
        };
        if !self.permits()? {
            return Ok(None);
        }
        #[cfg(test)]
        test_hooks::dispatched();
        Ok(Some(lease))
    }

    /// Runs `rpc` only if lookups are still authorized. `rpc` is lazy, so the
    /// check precedes the request on the wire; `None` means withheld.
    ///
    /// Holds a policy-fence lease from the check until `rpc` completes, so a
    /// fenced transition cannot commit between the two.
    pub(crate) async fn dispatch<F: Future>(&self, rpc: F) -> Result<Option<F::Output>, SyncError> {
        let Some(_lease) = self.lease().await? else {
            return Ok(None);
        };
        Ok(Some(rpc.await))
    }

    /// Runs the call `rpc` builds over this gate's transport with a dispatch
    /// signal, releasing the lease once the request has been handed to the
    /// transport, or when the call ends first. Without a transport, the call
    /// runs on `client` under [`Self::dispatch`].
    async fn dispatch_signalled<'c, T, Plain, Signalled>(
        &self,
        client: &'c mut CompactTxStreamerClient<Channel>,
        plain: impl FnOnce(&'c mut CompactTxStreamerClient<Channel>) -> Plain,
        signalled: impl FnOnce(CompactTxStreamerClient<DispatchSignalService<Channel>>) -> Signalled,
    ) -> Result<Option<T>, SyncError>
    where
        Plain: Future<Output = T>,
        Signalled: Future<Output = T>,
    {
        let Some(transport) = self.transport.clone() else {
            return self.dispatch(plain(client)).await;
        };
        let Some(lease) = self.lease().await? else {
            return Ok(None);
        };
        let (dispatched, sent) = Dispatched::new();
        let call = signalled(CompactTxStreamerClient::new(DispatchSignalService::new(
            transport, dispatched,
        )));
        Ok(Some(release_at_hand_off(lease, sent, call).await))
    }

    /// `GetAddressUtxosStream` for `addresses` from `start_height`.
    pub(crate) async fn address_utxos(
        &self,
        client: &mut CompactTxStreamerClient<Channel>,
        addresses: Vec<String>,
        start_height: BlockHeight,
    ) -> Result<Option<tonic::Streaming<GetAddressUtxosReply>>, SyncError> {
        let request = addresses.clone();
        self.dispatch_signalled(
            client,
            |client| super::get_address_utxos_stream(client, addresses, start_height),
            |mut client| async move {
                super::get_address_utxos_stream(&mut client, request, start_height).await
            },
        )
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
        let request = address.clone();
        self.dispatch_signalled(
            client,
            |client| super::get_taddress_txids(client, address, start_height, end_height),
            |mut client| async move {
                super::get_taddress_txids(&mut client, request, start_height, end_height).await
            },
        )
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
        self.dispatch_signalled(
            client,
            |client| super::get_transaction_payload(client, txid),
            |mut client| async move { super::get_transaction_payload(&mut client, txid).await },
        )
        .await
    }
}

/// Awaits `call`, holding `lease` until `sent` fires: when the request has
/// been handed to the transport. A signal dropped without firing proves no
/// hand-off, so the lease is then kept until the call returns, as without a
/// transport.
async fn release_at_hand_off<F: Future>(
    lease: OwnedRwLockReadGuard<()>,
    sent: tokio::sync::oneshot::Receiver<()>,
    call: F,
) -> F::Output {
    let mut lease = Some(lease);
    let mut sent = Some(sent);
    tokio::pin!(call);
    loop {
        tokio::select! {
            biased;
            output = &mut call => return output,
            handed_off = async { sent.as_mut().expect("polled only while armed").await },
                if sent.is_some() =>
            {
                sent = None;
                if handed_off.is_ok() {
                    lease = None;
                }
            }
        }
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
    async fn a_stricter_durable_policy_withholds() {
        let (_dir, path, gate) = wallet();
        apply(&path, TransparentLedgerMode::PrivateRequired);
        let sent = AtomicUsize::new(0);
        // The Public read handle resolves under the stricter policy, which
        // withholds the lookup.
        assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), None);
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
            &path,
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
            &path,
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
                &path,
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

    /// A transition on one wallet never waits for another wallet's lookups.
    #[tokio::test]
    async fn fences_are_per_wallet() {
        let (_dir, path, _) = wallet();
        let (_other_dir, _other_path, other) = wallet();
        let (release, released) = tokio::sync::oneshot::channel::<()>();
        let in_flight = tokio::spawn({
            let other = other.clone();
            async move { other.dispatch(async { released.await.unwrap() }).await }
        });
        tokio::time::sleep(Duration::from_millis(50)).await;
        let mut db =
            open_wallet_db_with_timeout(&path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
                .unwrap();
        apply_transparent_policy_fenced(
            &mut db,
            &path,
            TransparentLedgerMode::PrivateShadow,
            Duration::from_secs(2),
        )
        .await
        .expect("the other wallet's lookup does not hold this wallet's fence");
        release.send(()).unwrap();
        assert_eq!(in_flight.await.unwrap().unwrap(), Some(()));
    }

    /// A lookup made before a wallet's database existed holds only that
    /// wallet's fence: another wallet's transition never waits for it, but its
    /// own does.
    #[tokio::test]
    async fn pre_database_lookups_fence_only_their_wallet() {
        let (_dir, path, _) = wallet();
        let (_other_dir, other_path, _) = wallet();
        let importing = TransparentLookupGate::pre_database(
            PublicTransparentLookups::Allowed { generation: None },
            &other_path,
        );
        let (release, released) = tokio::sync::oneshot::channel::<()>();
        let in_flight =
            tokio::spawn(
                async move { importing.dispatch(async { released.await.unwrap() }).await },
            );
        tokio::time::sleep(Duration::from_millis(50)).await;

        let mut db =
            open_wallet_db_with_timeout(&path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
                .unwrap();
        apply_transparent_policy_fenced(
            &mut db,
            &path,
            TransparentLedgerMode::PrivateShadow,
            Duration::from_secs(2),
        )
        .await
        .expect("another wallet's import does not hold this wallet's fence");
        let mut other =
            open_wallet_db_with_timeout(&other_path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
                .unwrap();
        assert!(apply_transparent_policy_fenced(
            &mut other,
            &other_path,
            TransparentLedgerMode::PrivateShadow,
            Duration::from_millis(200),
        )
        .await
        .is_err());
        release.send(()).unwrap();
        assert_eq!(in_flight.await.unwrap().unwrap(), Some(()));
    }

    /// A lookup over its transport releases its lease once the request is
    /// sent: a transition commits while the response is still slow to come.
    /// Without the transport the same transition cannot drain.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_lease_ends_at_hand_off_not_at_a_slow_response() {
        use crate::wallet::sync_engine::test_lwd::CapturingLwd;
        use std::sync::atomic::AtomicBool;

        let (_dir, path, gate) = wallet();
        let received = Arc::new(AtomicBool::new(false));
        let lwd = CapturingLwd::start_with(Vec::new(), 0, {
            let received = received.clone();
            move |request| {
                if request.ends_with("/GetTransaction") {
                    received.store(true, Ordering::SeqCst);
                    std::thread::sleep(Duration::from_millis(4000));
                }
            }
        })
        .await;
        let txid = TxId::from_bytes([0x5c; 32]);
        // Unsignalled first: its transition applies nothing, so the gate's
        // captured authority still holds for the signalled lookup.
        for (signalled, drains) in [(false, false), (true, true)] {
            received.store(false, Ordering::SeqCst);
            let gate = if signalled {
                gate.clone().with_transport(lwd.channel.clone())
            } else {
                gate.clone()
            };
            // Opened first, so the transition starts as soon as the request
            // arrives, well inside the slow response.
            let mut db =
                open_wallet_db_with_timeout(&path, WalletNetwork::Regtest, SYNC_DB_BUSY_TIMEOUT)
                    .unwrap();
            let mut client = lwd.client.clone();
            let lookup = tokio::spawn(async move { gate.transaction(&mut client, txid).await });
            while !received.load(Ordering::SeqCst) {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
            let transition = apply_transparent_policy_fenced(
                &mut db,
                &path,
                TransparentLedgerMode::PrivateShadow,
                Duration::from_millis(2000),
            )
            .await;
            assert_eq!(transition.is_ok(), drains, "signalled: {signalled}");
            // The lookup itself completes either way, answered "not found".
            let answered = lookup.await.unwrap().unwrap();
            assert!(matches!(answered, Some(Err(_))), "{answered:?}");
        }
    }

    /// A dispatch signal dropped without firing is no hand-off: the lease is
    /// kept until the call returns.
    #[tokio::test]
    async fn a_dropped_signal_keeps_the_lease_until_the_call_returns() {
        let held = Arc::new(RwLock::new(()));
        let lease = held.clone().read_owned().await;
        let (dispatched, sent) = Dispatched::new();
        drop(dispatched);
        let (finish, finished) = tokio::sync::oneshot::channel::<()>();
        let call = tokio::spawn(release_at_hand_off(lease, sent, async {
            finished.await.unwrap()
        }));
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(held.try_write().is_err(), "the lease is still held");
        finish.send(()).unwrap();
        call.await.unwrap();
        assert!(held.try_write().is_ok());

        // A fired signal releases it while the call still runs.
        let lease = held.clone().read_owned().await;
        let (dispatched, sent) = Dispatched::new();
        let (finish, finished) = tokio::sync::oneshot::channel::<()>();
        let call = tokio::spawn(release_at_hand_off(lease, sent, async {
            finished.await.unwrap()
        }));
        dispatched.fire();
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(held.try_write().is_ok(), "released at hand-off");
        finish.send(()).unwrap();
        call.await.unwrap();
    }

    /// A lookup that cannot get its lease within the bound is withheld,
    /// never sent.
    #[tokio::test(start_paused = true)]
    async fn a_lookup_behind_a_held_fence_is_withheld_after_its_bound() {
        let (_dir, path, gate) = wallet();
        let held = fence(&path);
        let _transition = held.write().await;
        let sent = AtomicUsize::new(0);
        assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), None);
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
