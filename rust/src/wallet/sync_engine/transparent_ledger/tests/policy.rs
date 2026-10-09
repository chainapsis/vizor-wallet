//! Transparent mode selection, durable policy resolution, and durable transitions.
//!
//! Every test selects through its arguments or the per-wallet seam; none
//! changes the process-wide preference or confirmation.

use std::sync::atomic::AtomicUsize;
use std::time::Duration;

use super::super::pir::{test_transport, TransparentPirSource};
use super::activation::hardware_tx;
use super::pir::refusing;
use super::*;
use crate::wallet::db::{
    open_wallet_db_for_read_with_timeout, open_wallet_db_readonly_with_timeout, wallet_db_on,
};
use crate::wallet::sync_engine::enhancement::{may_raise, PublicTransparentLookups};
use crate::wallet::sync_engine::lwd::transparent_lookup::TransparentLookupGate;
use crate::wallet::sync_engine::transparent_followup;

const MAIN: WalletNetwork = WalletNetwork::Main;

/// Applies `mode` directly, as another connection or an earlier build would.
fn apply_on(path: &str, network: WalletNetwork, mode: TransparentLedgerMode) {
    let mut db = open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    with_wallet_db_write_lock("test.transparent_ledger.policy", || {
        db.apply_transparent_policy(mode)
    })
    .unwrap();
}

/// Counts how often a lookup actually runs.
async fn rpc(sent: &AtomicUsize) {
    sent.fetch_add(1, Ordering::SeqCst);
}

#[tokio::test]
async fn openers_never_run_weaker_than_the_durable_policy() {
    // No selection for this wallet: every opener selects `Public`.
    let mut wallet = wallet();
    let path = wallet.path.clone();
    let other = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (second, _) = keys::add_account(&path, NETWORK, "second", &other, Some(100)).unwrap();
    apply_on(&path, NETWORK, TransparentLedgerMode::PrivateRequired);
    let before = applied(&path, NETWORK);
    let required = TransparentLedgerMode::PrivateRequired;

    for db in [
        open_wallet_db_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap(),
        open_wallet_db_for_read_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap(),
        open_wallet_db_readonly_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap(),
    ] {
        assert_eq!(db.transparent_ledger_mode().unwrap(), required);
    }
    let conn = rusqlite::Connection::open(&path).unwrap();
    assert_eq!(
        wallet_db_on(&conn, &path, NETWORK)
            .transparent_ledger_mode()
            .unwrap(),
        required
    );
    // Hardware broadcast authorization opens its own handle under its
    // reservation. It reaches the input check, which refuses an input no
    // private authority covers, instead of failing on the conflict.
    let sent = AtomicUsize::new(0);
    let error = crate::wallet::sync::hardware_authority::dispatch(
        &path,
        NETWORK,
        &hardware_tx(vec![OutPoint::new([7; 32], 0)]),
        &[],
        TIP.into(),
        |_| rpc(&sent),
    )
    .await
    .unwrap_err()
    .to_string();
    assert!(
        error.contains("Transparent funds are unavailable"),
        "{error}"
    );
    assert!(!error.contains("cannot operate"), "{error}");
    assert_eq!(sent.load(Ordering::SeqCst), 0);
    // Account deletion, on a handle over its own transaction, still works.
    keys::delete_account(&path, NETWORK, &second).unwrap();

    // An operation configured with a captured `Public` mode, on a handle
    // opened before the transition, adopts too, and withholds lookups
    // instead of failing.
    let public = policy(TransparentLedgerMode::Public);
    public.configure_db(&mut wallet.db);
    assert_eq!(wallet.db.transparent_ledger_mode().unwrap(), required);
    assert_eq!(
        public.public_transparent_lookups(&wallet.db).unwrap(),
        PublicTransparentLookups::Withheld
    );
    // So does the balance read, which opens through the same openers.
    crate::wallet::sync::get_wallet_balance(&path, NETWORK, &wallet.uuid).unwrap();

    // Opening never writes the policy.
    assert_eq!(applied(&path, NETWORK), before);
}

/// Handles opened while the wallet is public follow a `PrivateRequired`
/// policy another connection applies afterwards, at their next read, with no
/// caller adoption: balances read private, public lookups are withheld, and
/// status work is never public. Nothing they read writes the policy, and an
/// explicit lowering by another connection is followed back.
#[tokio::test]
async fn handles_opened_before_another_connection_raises_follow_it() {
    use zcash_client_backend::data_api::status::{TransactionStatusRead, TransactionStatusWork};

    let mut wallet = wallet();
    let path = wallet.path.clone();
    let public = policy(TransparentLedgerMode::Public);
    public.configure_db(&mut wallet.db);
    let mut reader =
        open_wallet_db_for_read_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let mut readonly =
        open_wallet_db_readonly_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    public.configure_db(&mut reader);
    public.configure_db(&mut readonly);
    let captured = public.public_transparent_lookups(&wallet.db).unwrap();
    assert!(matches!(
        captured,
        PublicTransparentLookups::Allowed {
            generation: Some(_)
        }
    ));

    apply_on(&path, NETWORK, TransparentLedgerMode::PrivateRequired);
    let raised = applied(&path, NETWORK);
    for db in [&wallet.db, &reader, &readonly] {
        assert_eq!(
            db.transparent_ledger_mode().unwrap(),
            TransparentLedgerMode::PrivateRequired
        );
        assert_eq!(
            public.public_transparent_lookups(db).unwrap(),
            PublicTransparentLookups::Withheld
        );
        assert!(!captured.still_allowed(db).unwrap());
        assert!(!db
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|work| matches!(work, TransactionStatusWork::Public(_))));
    }
    let balance = crate::wallet::sync::read_wallet_balances(
        &mut wallet.db,
        &path,
        NETWORK,
        &[wallet.account],
    )
    .unwrap()
    .pop()
    .unwrap();
    assert!(balance.transparent_private);
    // Reading never wrote the policy.
    assert_eq!(applied(&path, NETWORK), raised);

    // Only an explicit transition lowers it; the handles follow it back, and
    // authority captured before the raise stays revoked.
    apply_on(&path, NETWORK, TransparentLedgerMode::Public);
    for db in [&wallet.db, &reader, &readonly] {
        assert_eq!(
            db.transparent_ledger_mode().unwrap(),
            TransparentLedgerMode::Public
        );
        assert!(!captured.still_allowed(db).unwrap());
    }
}

#[tokio::test]
async fn startup_never_demotes() {
    let (_dir, path, _db) = main_wallet();
    apply_on(&path, MAIN, TransparentLedgerMode::PrivateRequired);
    let before = applied(&path, MAIN);
    // Startup passes only `true`; repeated reconciliation never demotes.
    for _ in [0, 1] {
        let changed = set_transparent_policy(&path, MAIN, true).await.unwrap();
        assert_eq!(changed, None);
        assert_eq!(applied(&path, MAIN), before);
    }
}

#[tokio::test]
async fn an_unconfirmed_preference_withholds_lookups_but_never_raises() {
    let mut wallet = wallet();
    let before = applied(&wallet.path, NETWORK);
    let _unconfirmed =
        test_mode::select(&wallet.path, TransparentLedgerMode::PrivateRequired, false);

    // Handles and the captured policy are private for the launch.
    let reopened =
        open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    assert_eq!(
        reopened.transparent_ledger_mode().unwrap(),
        TransparentLedgerMode::PrivateRequired
    );
    let required = policy(TransparentLedgerMode::PrivateRequired);
    let lookups = required.public_transparent_lookups(&reopened).unwrap();
    assert_eq!(lookups, PublicTransparentLookups::Withheld);
    let gate = TransparentLookupGate::for_wallet(lookups, &wallet.path, NETWORK).unwrap();
    let sent = AtomicUsize::new(0);
    assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), None);
    assert_eq!(sent.load(Ordering::SeqCst), 0);

    // But nothing raises the durable policy.
    assert!(!may_raise(&wallet.path, NETWORK));
    let source = unavailable();
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required,
        &source,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::NotEnabled);
    assert_eq!(applied(&wallet.path, NETWORK), before);
}

#[tokio::test]
async fn an_explicit_off_lowers_to_public_in_every_build() {
    let (_dir, path, _db) = main_wallet();
    for _ in [0, 1] {
        apply_on(&path, MAIN, TransparentLedgerMode::PrivateRequired);
        let before = applied(&path, MAIN);
        let lowered = set_transparent_policy(&path, MAIN, false).await.unwrap();
        let expected = AppliedTransparentPolicy {
            mode: TransparentLedgerMode::Public,
            generation: before.generation + 1,
        };
        assert_eq!(lowered, Some(expected));
        assert_eq!(applied(&path, MAIN), expected);
        // Already public: nothing to lower.
        assert_eq!(
            set_transparent_policy(&path, MAIN, false).await.unwrap(),
            None
        );
        assert_eq!(applied(&path, MAIN), expected);
    }
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn explicit_reenable_after_lowering_advances_policy_generation() {
    let (_dir, path, _db) = main_wallet();
    let start = applied(&path, MAIN).generation;
    // Enabled by private queries on supported mainnet.
    let raised = set_transparent_policy(&path, MAIN, true)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(raised.mode, TransparentLedgerMode::PrivateRequired);
    // An explicit opt-out lowers the policy.
    let lowered = set_transparent_policy(&path, MAIN, false)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(lowered.mode, TransparentLedgerMode::Public);
    // Re-enabling takes its selection from the arguments, independently of
    // the live preference left off by the earlier opt-out.
    let again = set_transparent_policy(&path, MAIN, true)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        again,
        AppliedTransparentPolicy {
            mode: TransparentLedgerMode::PrivateRequired,
            generation: start + 3,
        }
    );
    // Handles opened with the live selection keep the restored policy.
    assert_eq!(
        open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT)
            .unwrap()
            .transparent_ledger_mode()
            .unwrap(),
        TransparentLedgerMode::PrivateRequired
    );
}

#[test]
fn reconcile_without_a_wallet_creates_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    for private_queries in [true, false] {
        assert_eq!(
            runtime
                .block_on(set_transparent_policy(&path, MAIN, private_queries))
                .unwrap(),
            None
        );
    }
    // The bridge entry point reports no change. With `true` it selects from
    // the supported network and the explicit preference.
    for private_queries in [true, false] {
        assert_eq!(
            crate::api::sync::reconcile_transparent_policy(
                path.clone(),
                "main".into(),
                private_queries
            )
            .unwrap(),
            None
        );
    }
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
}

#[test]
fn the_policy_opener_never_creates_a_wallet() {
    use super::super::policy::open_policy_wallet;

    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    assert!(open_policy_wallet(&path, MAIN).unwrap().is_none());
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
    // An existing wallet opens.
    let (_wallet_dir, wallet_path, _db) = main_wallet();
    assert!(open_policy_wallet(&wallet_path, MAIN).unwrap().is_some());
}

#[tokio::test]
async fn the_bridge_reports_the_applied_policy_and_generation() {
    use crate::api::sync::{ApiAppliedTransparentPolicy, ApiTransparentLedgerMode};

    let (_dir, path, _db) = main_wallet();
    apply_on(&path, MAIN, TransparentLedgerMode::PrivateRequired);
    let before = applied(&path, MAIN);
    let lowered = tokio::task::spawn_blocking({
        let path = path.clone();
        move || crate::api::sync::reconcile_transparent_policy(path, "main".into(), false)
    })
    .await
    .unwrap()
    .unwrap();
    assert_eq!(
        lowered,
        Some(ApiAppliedTransparentPolicy {
            mode: ApiTransparentLedgerMode::Public,
            generation: before.generation + 1,
        })
    );
    let reconcile_off = |path: String| {
        tokio::task::spawn_blocking(move || {
            crate::api::sync::reconcile_transparent_policy(path, "main".into(), false)
        })
    };
    // Already public: nothing applied, and the resulting policy is still
    // reported, so a caller holding a stale private policy replaces it.
    assert_eq!(
        reconcile_off(path.clone()).await.unwrap().unwrap(),
        lowered.map(|applied| ApiAppliedTransparentPolicy { ..applied })
    );
    // Another connection raises and lowers it meanwhile: the same-mode
    // reconcile reports that connection's newer generation.
    apply_on(&path, MAIN, TransparentLedgerMode::PrivateRequired);
    apply_on(&path, MAIN, TransparentLedgerMode::Public);
    assert_eq!(
        reconcile_off(path.clone()).await.unwrap().unwrap(),
        Some(ApiAppliedTransparentPolicy {
            mode: ApiTransparentLedgerMode::Public,
            generation: before.generation + 3,
        })
    );
    // Only a missing wallet reports none, and nothing is created.
    let missing = format!("{path}.missing");
    assert_eq!(reconcile_off(missing.clone()).await.unwrap().unwrap(), None);
    assert!(!std::path::Path::new(&missing).exists());
}

/// The fence itself, including giving up after the drain bound, is covered
/// in `lwd::transparent_lookup`; this checks that reconciliation goes
/// through it. Real time: the fence is shared by every test in the process.
#[tokio::test]
async fn reconcile_waits_for_public_lookups_to_drain() {
    let (_dir, path, db) = main_wallet();
    let before = applied(&path, MAIN);
    let lookups = policy(TransparentLedgerMode::Public)
        .public_transparent_lookups(&db)
        .unwrap();
    let gate = TransparentLookupGate::for_wallet(lookups, &path, MAIN).unwrap();
    let (release, released) = tokio::sync::oneshot::channel::<()>();
    let in_flight = tokio::spawn({
        let gate = gate.clone();
        async move { gate.dispatch(async { released.await.unwrap() }).await }
    });
    tokio::time::sleep(Duration::from_millis(50)).await;

    // Startup raises the policy, which must wait.
    let transition = tokio::spawn({
        let path = path.clone();
        async move { set_transparent_policy(&path, MAIN, true).await }
    });
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(applied(&path, MAIN), before, "still waiting for the lookup");

    release.send(()).unwrap();
    assert_eq!(
        in_flight.await.unwrap().unwrap(),
        Some(()),
        "sent under the policy it was checked against"
    );
    let raised = transition.await.unwrap().unwrap().unwrap();
    assert_eq!(raised.mode, TransparentLedgerMode::PrivateRequired);
    // Lookups captured under the old policy are withheld from then on.
    let sent = AtomicUsize::new(0);
    assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), None);
    assert_eq!(sent.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn private_queries_off_writes_nothing_and_sends_no_private_requests() {
    let (_dir, path, mut db) = main_wallet();
    let before = applied(&path, MAIN);
    // Private queries off: no private source is selected.
    let public_queries = EnhancementPolicy::for_preference(MAIN, false);
    assert_eq!(
        public_queries.transparent_mode(),
        TransparentLedgerMode::Public
    );

    // Startup reconciliation and the coordinator.
    assert_eq!(
        set_transparent_policy(&path, MAIN, false).await.unwrap(),
        None
    );
    // An unsupported network does not select private recovery or open the
    // wallet, even when private queries is on.
    let not_a_wallet = format!("{path}.other");
    std::fs::write(&not_a_wallet, b"not a wallet").unwrap();
    assert_eq!(
        set_transparent_policy(&not_a_wallet, WalletNetwork::Test, true)
            .await
            .unwrap(),
        None
    );
    assert_eq!(std::fs::read(&not_a_wallet).unwrap(), b"not a wallet");
    // The sync's follow-up with the production source, whose transport would
    // record any request in place of the service.
    let seam = test_transport::set(&path, refusing());
    let source = TransparentPirSource::new(&path, MAIN);
    let events = std::sync::Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    transparent_followup(
        1,
        &mut db,
        &path,
        MAIN,
        public_queries,
        &source,
        None,
        &|| false,
        &progress,
        (0, 0),
    )
    .await;
    drop(source);

    assert_eq!(applied(&path, MAIN), before);
    assert!(
        events.lock().unwrap().is_empty(),
        "completion is not reported again"
    );
    assert!(
        seam.seam.observer.requests().is_empty(),
        "no private request"
    );
    assert!(!std::path::Path::new(&format!("{path}.tpir")).exists());
    // Transparent lookups stay public.
    assert_eq!(
        public_queries.public_transparent_lookups(&db).unwrap(),
        PublicTransparentLookups::Allowed {
            generation: Some(before.generation)
        }
    );
}

/// A `Public` selection over a durably private wallet reads under the durable
/// `PrivateRequired`, but never recovers: only a handle configured
/// `PrivateRequired` runs the source, and its trusted commits qualify.
#[tokio::test]
async fn a_public_selection_over_a_private_wallet_does_not_recover() {
    let qualified = |path: &str| count(path, "SELECT COUNT(*) FROM tpir_qualified_revisions");
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    let public = policy(TransparentLedgerMode::Public);
    let mut configured =
        open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    public.configure_db(&mut configured);
    assert_eq!(
        configured.transparent_ledger_mode().unwrap(),
        TransparentLedgerMode::PrivateRequired,
        "the durable policy governs the Public handle's reads"
    );

    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        public,
        &source,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::NotEnabled);
    assert_eq!(source.calls(), 0);
    assert_eq!(qualified(&wallet.path), 0);

    // Configured `PrivateRequired`, the same source's commits qualify.
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert!(stats.commits > 0);
    assert_eq!((stats.qualified, stats.promoted), (stats.commits, 1));
    assert_eq!(qualified(&wallet.path), 1);
}

/// Writes a stand-in companion for `wallet`'s account, as a private pass
/// would leave behind, and returns its path.
fn companion_file(wallet: &Wallet) -> std::path::PathBuf {
    let path = super::super::pir::companion_path(
        &wallet.path,
        wallet.account,
        "https://companion.invalid",
    );
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, b"companion").unwrap();
    path
}

/// Records `received` as public discovery would.
fn discover_publicly(wallet: &Wallet, received: &ReceiveEvent) {
    let output = zcash_client_backend::wallet::WalletTransparentOutput::from_parts(
        received.outpoint.clone(),
        transparent::bundle::TxOut::new(received.value, received.address.script().into()),
        Some(received.mined_height),
        Some(wallet.account),
        Some(TransparentKeyScope::EXTERNAL),
        None,
    )
    .unwrap();
    open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT)
        .unwrap()
        .put_received_transparent_utxo(&output)
        .unwrap();
}

/// A wallet whose account private recovery activated with one receive only
/// the publication reported, and a companion for it.
async fn recovered_wallet() -> (Wallet, ReceiveEvent, std::path::PathBuf) {
    let mut wallet = wallet();
    let mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, VALUE);
    let companion = companion_file(&wallet);
    // The preference is off from here on, as after a toggle-off.
    drop(mode);
    let received = receive(1, external(&wallet, 0), VALUE, 150);
    (wallet, received, companion)
}

/// Turning private queries off forgets what private recovery alone told the
/// wallet, so a publication's receive no longer counts as public funds, and
/// deletes the companion that recorded it as held. Public discovery then
/// rebuilds whatever is real.
#[tokio::test]
async fn lowering_forgets_private_ledger_facts_and_their_companions() {
    let (wallet, received, companion) = recovered_wallet().await;
    let ledger_facts = "SELECT
        (SELECT COUNT(*) FROM tpir_receive_events)
      + (SELECT COUNT(*) FROM tpir_coverage)
      + (SELECT COUNT(*) FROM tpir_output_origins WHERE origin = 2)";
    assert!(count(&wallet.path, ledger_facts) > 0);

    let lowered = set_transparent_policy(&wallet.path, NETWORK, false)
        .await
        .unwrap();
    assert_eq!(lowered.unwrap().mode, TransparentLedgerMode::Public);

    assert!(!companion.exists());
    assert_eq!(count(&wallet.path, ledger_facts), 0);
    assert_eq!(
        count(
            &wallet.path,
            "SELECT COUNT(*) FROM transparent_received_outputs"
        ),
        0
    );
    let public = balance(&wallet, &wallet.uuid);
    assert_eq!(public.transparent, 0);
    assert_eq!(
        public.transparent_authority,
        TransparentBalanceAuthority::Current
    );

    // Public discovery finds what is real again.
    discover_publicly(&wallet, &received);
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, VALUE);
    // A second forget, as at the next sync start, removes none of it.
    let again = forget_private_ledger(&wallet.path, NETWORK)
        .unwrap()
        .unwrap();
    assert!(again.removed_nothing(), "{again:?}");
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, VALUE);
}

/// Nothing is forgotten while a companion survives, because a companion that
/// outlived the facts would make a later private run skip them. The policy
/// is public all the same, and the next attempt, as at sync start, finishes.
#[cfg(unix)]
#[tokio::test]
async fn a_companion_that_cannot_be_deleted_defers_forgetting() {
    use std::os::unix::fs::PermissionsExt as _;

    let (wallet, _, companion) = recovered_wallet().await;
    let dir = companion.parent().unwrap().to_owned();
    /// Makes the directory writable again, also when the test fails.
    struct Restore(std::path::PathBuf);
    impl Drop for Restore {
        fn drop(&mut self) {
            let _ = std::fs::set_permissions(&self.0, std::fs::Permissions::from_mode(0o700));
        }
    }
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o500)).unwrap();
    let restore = Restore(dir.clone());

    set_transparent_policy(&wallet.path, NETWORK, false)
        .await
        .unwrap();
    assert_eq!(
        applied(&wallet.path, NETWORK).mode,
        TransparentLedgerMode::Public
    );
    assert!(companion.exists());
    assert!(count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events") > 0);
    assert!(forget_private_ledger(&wallet.path, NETWORK).is_err());
    assert!(count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events") > 0);

    drop(restore);
    let forgotten = forget_private_ledger(&wallet.path, NETWORK)
        .unwrap()
        .unwrap();
    assert!(!forgotten.removed_nothing(), "{forgotten:?}");
    assert!(!companion.exists());
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events"),
        0
    );
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, 0);
}

/// A wallet still private keeps its facts and companions: only a public
/// policy is forgotten.
#[tokio::test]
async fn a_private_wallet_is_not_forgotten() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    let companion = companion_file(&wallet);
    let events = count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events");
    assert!(events > 0);

    assert_eq!(forget_private_ledger(&wallet.path, NETWORK).unwrap(), None);
    assert!(companion.exists());
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events"),
        events
    );
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, VALUE);
}

/// A wallet that never recovered privately, as in every default build, is
/// only read, and no companion directory is made.
#[tokio::test]
async fn a_wallet_that_never_recovered_privately_has_nothing_to_forget() {
    let wallet = wallet();
    let forgotten = forget_private_ledger(&wallet.path, NETWORK)
        .unwrap()
        .unwrap();
    assert!(forgotten.removed_nothing(), "{forgotten:?}");
    assert!(!super::super::pir::companion_dir(&wallet.path).exists());
    // A missing wallet stays missing.
    let dir = tempfile::tempdir().unwrap();
    let missing = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    assert_eq!(forget_private_ledger(&missing, NETWORK).unwrap(), None);
    assert!(!std::path::Path::new(&missing).exists());
}
