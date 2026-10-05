//! Transparent mode selection, handle adoption, and durable transitions.
//!
//! Every test selects through its arguments or the per-wallet seam; none
//! changes the process-wide preference, development flag, or confirmation.

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
    // So does a handle on a transaction the caller holds, such as the
    // stored-transaction check's.
    assert!(!crate::wallet::sync::hardware_authority::stored_mined(
        &path,
        NETWORK,
        &hardware_tx(vec![])
    )
    .unwrap());
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
    .unwrap_err();
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

#[tokio::test]
async fn startup_never_demotes() {
    let (_dir, path, _db) = main_wallet();
    for stricter in [
        TransparentLedgerMode::PrivateShadow,
        TransparentLedgerMode::PrivateRequired,
    ] {
        // Startup passes only `true`, in either build.
        for build_flag in [false, true] {
            apply_on(&path, MAIN, stricter);
            let before = applied(&path, MAIN);
            let changed = set_transparent_policy(&path, MAIN, true, build_flag)
                .await
                .unwrap();
            let after = applied(&path, MAIN);
            match changed {
                // The only change startup makes is a raise, from a flag build.
                Some(raised) => {
                    assert!(build_flag && stricter != TransparentLedgerMode::PrivateRequired);
                    assert_eq!(raised.mode, TransparentLedgerMode::PrivateRequired);
                    assert_eq!(after, raised);
                }
                None => assert_eq!(after, before),
            }
        }
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
    for build_flag in [false, true] {
        for stricter in [
            TransparentLedgerMode::PrivateShadow,
            TransparentLedgerMode::PrivateRequired,
        ] {
            apply_on(&path, MAIN, stricter);
            let before = applied(&path, MAIN);
            let lowered = set_transparent_policy(&path, MAIN, false, build_flag)
                .await
                .unwrap();
            let expected = AppliedTransparentPolicy {
                mode: TransparentLedgerMode::Public,
                generation: before.generation + 1,
            };
            assert_eq!(lowered, Some(expected));
            assert_eq!(applied(&path, MAIN), expected);
            // Already public: nothing to lower.
            assert_eq!(
                set_transparent_policy(&path, MAIN, false, build_flag)
                    .await
                    .unwrap(),
                None
            );
            assert_eq!(applied(&path, MAIN), expected);
        }
    }
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn a_failed_store_on_disable_raises_again() {
    let (_dir, path, _db) = main_wallet();
    let start = applied(&path, MAIN).generation;
    // Enabled in a flag build.
    let raised = set_transparent_policy(&path, MAIN, true, true)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(raised.mode, TransparentLedgerMode::PrivateRequired);
    // Disable lowers before saving the setting.
    let lowered = set_transparent_policy(&path, MAIN, false, true)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(lowered.mode, TransparentLedgerMode::Public);
    // The save failed, so the setting is still on: raising again takes its
    // selection from the arguments, not from the live preference already
    // turned off.
    let again = set_transparent_policy(&path, MAIN, true, true)
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
    for (private_queries, build_flag) in [(true, true), (true, false), (false, true)] {
        assert_eq!(
            runtime
                .block_on(set_transparent_policy(
                    &path,
                    MAIN,
                    private_queries,
                    build_flag
                ))
                .unwrap(),
            None
        );
    }
    // The bridge entry point reports no change. With `true` it selects from
    // the process-wide flag, which no test sets.
    for private_queries in [true, false] {
        assert!(!crate::api::sync::reconcile_transparent_policy(
            path.clone(),
            "main".into(),
            private_queries
        )
        .unwrap());
    }
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
}

/// The fence itself, including giving up after the drain bound, is covered
/// in `lwd::transparent_lookup`; this checks that reconciliation goes
/// through it. Real time: the fence is shared by every test in the process.
#[tokio::test]
async fn reconcile_waits_for_public_lookups_to_drain() {
    let (_dir, path, db) = main_wallet();
    apply_on(&path, MAIN, TransparentLedgerMode::PrivateShadow);
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

    let transition = tokio::spawn({
        let path = path.clone();
        async move { set_transparent_policy(&path, MAIN, false, false).await }
    });
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(applied(&path, MAIN), before, "still waiting for the lookup");

    release.send(()).unwrap();
    assert_eq!(
        in_flight.await.unwrap().unwrap(),
        Some(()),
        "sent under the policy it was checked against"
    );
    let lowered = transition.await.unwrap().unwrap().unwrap();
    assert_eq!(lowered.mode, TransparentLedgerMode::Public);
    // Lookups captured under the old policy are withheld from then on.
    let sent = AtomicUsize::new(0);
    assert_eq!(gate.dispatch(rpc(&sent)).await.unwrap(), None);
    assert_eq!(sent.load(Ordering::SeqCst), 0);
}

#[tokio::test]
async fn a_default_build_with_the_setting_on_writes_nothing_and_sends_nothing() {
    let (_dir, path, mut db) = main_wallet();
    let before = applied(&path, MAIN);
    // Private queries on, development flag off.
    let default_build = EnhancementPolicy::for_inputs(MAIN, true, false);
    assert_eq!(
        default_build.transparent_mode(),
        TransparentLedgerMode::Public
    );

    // Startup reconciliation and the coordinator.
    assert_eq!(
        set_transparent_policy(&path, MAIN, true, false)
            .await
            .unwrap(),
        None
    );
    // Startup decides before opening the wallet, so it never touches one: not
    // even a file that is not a wallet fails it.
    let not_a_wallet = format!("{path}.other");
    std::fs::write(&not_a_wallet, b"not a wallet").unwrap();
    assert_eq!(
        set_transparent_policy(&not_a_wallet, MAIN, true, false)
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
        &mut db,
        &path,
        MAIN,
        default_build,
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
        default_build.public_transparent_lookups(&db).unwrap(),
        PublicTransparentLookups::Allowed {
            generation: Some(before.generation)
        }
    );
}
