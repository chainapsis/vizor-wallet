//! Private activation end to end, with fixtures only: a fenced transition to
//! `PrivateRequired`, recovery, per-account promotion, and the balance and
//! shielding paths reading the resulting authority.

use std::time::Duration;

use zcash_client_backend::data_api::transparent_ledger::{
    AccountLifecycle, RecoveryBlocker, TransparentAuthority,
};

use super::*;
use crate::wallet::sync::{
    get_shield_transparent_status, get_wallet_balance, TransparentBalanceAuthority,
};
use crate::wallet::sync_engine::enhancement::test_mode;
use crate::wallet::sync_engine::lwd::transparent_lookup::{
    apply_transparent_policy_fenced, TransparentLookupGate,
};

const VALUE: u64 = 2_000_000;

fn required() -> EnhancementPolicy {
    policy(TransparentLedgerMode::PrivateRequired)
}

/// Moves a wallet to `PrivateRequired` the only way this build applies a
/// transparent policy, and configures every handle opened on it for that
/// mode until the guard drops.
async fn activate(wallet: &mut Wallet) -> test_mode::ModeOverride {
    let mut db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    apply_transparent_policy_fenced(
        &mut db,
        TransparentLedgerMode::PrivateRequired,
        Duration::from_secs(5),
    )
    .await
    .unwrap();
    let guard = test_mode::set(&wallet.path, TransparentLedgerMode::PrivateRequired);
    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    guard
}

async fn run_required(wallet: &mut Wallet, source: &FixtureSource) -> RunOutcome {
    run(&mut wallet.db, required(), source, &|| false)
        .await
        .unwrap()
}

fn lifecycle(wallet: &Wallet, account: AccountUuid) -> AccountLifecycle {
    wallet.db.transparent_watch_set(account).unwrap().lifecycle
}

fn balance(wallet: &Wallet, uuid: &str) -> crate::wallet::sync::WalletBalance {
    get_wallet_balance(&wallet.path, NETWORK, uuid).unwrap()
}

/// Checkpoints every note commitment tree at `height`, as scanning would, so
/// that proposals can find an anchor.
fn checkpoint_trees(wallet: &mut Wallet, height: u32) {
    use shardtree::error::ShardTreeError;
    use zcash_client_backend::data_api::WalletCommitmentTrees;
    use zcash_client_sqlite::wallet::commitment_tree::Error;
    let height = BlockHeight::from_u32(height);
    wallet
        .db
        .with_sapling_tree_mut::<_, _, ShardTreeError<Error>>(|tree| tree.checkpoint(height))
        .unwrap();
    wallet
        .db
        .with_orchard_tree_mut::<_, _, ShardTreeError<Error>>(|tree| tree.checkpoint(height))
        .unwrap();
    wallet
        .db
        .with_ironwood_tree_mut::<_, _, ShardTreeError<Error>>(|tree| tree.checkpoint(height))
        .unwrap();
}

/// A qualified fixture holding one mined receive at the account's first
/// external address.
fn funded_source(wallet: &Wallet) -> FixtureSource {
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, external(wallet, 0), VALUE, 150))
        .qualified_in(&wallet.path, NETWORK);
    source
}

#[tokio::test]
async fn a_complete_qualified_account_is_promoted_and_authorizes_its_outputs() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1);
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);

    let snapshot = wallet
        .db
        .transparent_ledger_snapshot(wallet.account, crate::wallet::confirmations_policy())
        .unwrap();
    assert_eq!(snapshot.authority, TransparentAuthority::Private);
    let balance = balance(&wallet, &wallet.uuid);
    assert_eq!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(balance.transparent, VALUE);
    assert_eq!(balance.transparent_last_known, None);

    // The production shielding entry point selects the projected output.
    checkpoint_trees(&mut wallet, TIP);
    let status = get_shield_transparent_status(&wallet.path, NETWORK, &wallet.uuid).unwrap();
    assert!(status.can_shield, "{}", status.reason);

    // Promotion is idempotent: a later run keeps the account active.
    let RunOutcome::Finished(again) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(again.promoted, 0);
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
}

#[tokio::test]
async fn an_unqualified_source_never_promotes() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = FixtureSource::new(main_hash);
    source.receive(receive(1, external(&wallet, 0), VALUE, 150));

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 0);
    assert_complete(&wallet, &source);
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );

    let snapshot = wallet
        .db
        .transparent_ledger_snapshot(wallet.account, crate::wallet::confirmations_policy())
        .unwrap();
    assert_eq!(snapshot.authority, TransparentAuthority::Unavailable);
    assert!(snapshot.blockers.contains(&RecoveryBlocker::NotActivated));
    let balance = balance(&wallet, &wallet.uuid);
    assert_ne!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(balance.transparent, 0, "nothing is spendable");

    let status = get_shield_transparent_status(&wallet.path, NETWORK, &wallet.uuid).unwrap();
    assert!(!status.can_shield);
    assert!(
        status.reason.contains("transparent funds are unavailable"),
        "reports recovery, not an empty balance: {}",
        status.reason
    );
}

#[tokio::test]
async fn accounts_promote_independently() {
    let mut wallet = wallet();
    let other_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (other_uuid, _) =
        keys::add_account(&wallet.path, NETWORK, "other", &other_seed, Some(100)).unwrap();
    let other = keys::parse_account_uuid(&other_uuid).unwrap();
    // Adding an account queues its range for scanning; mark it scanned again.
    scan(&wallet.path, wallet.birthday, wallet.birthday, TIP, 0);
    let _mode = activate(&mut wallet).await;

    // The other account's first address cannot be checked by the source.
    let other_address = wallet
        .db
        .transparent_watch_set(other)
        .unwrap()
        .addresses
        .into_iter()
        .find(|watched| {
            matches!(
                watched.origin,
                WatchOrigin::Derived { scope, index }
                    if scope == TransparentKeyScope::EXTERNAL && index.index() == 0
            )
        })
        .unwrap()
        .address;
    let source = funded_source(&wallet);
    source.unsupported(other_address);

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1);
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
    assert_eq!(lifecycle(&wallet, other), AccountLifecycle::Candidate);
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_ne!(
        balance(&wallet, &other_uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );
}

#[tokio::test]
async fn lag_and_outage_pause_authority_without_fallback() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );

    // The chain advances while the source is down.
    scan(&wallet.path, wallet.birthday, TIP + 1, TIP + 1, 0);
    source.fail(Some(SourceError::Unavailable));
    assert_eq!(
        run_required(&mut wallet, &source).await,
        RunOutcome::SourceUnavailable
    );
    let paused = balance(&wallet, &wallet.uuid);
    assert_eq!(
        paused.transparent_authority,
        TransparentBalanceAuthority::LastKnown
    );
    assert_eq!(paused.transparent, 0);
    assert_eq!(paused.transparent_last_known, Some(VALUE));
    let status = get_shield_transparent_status(&wallet.path, NETWORK, &wallet.uuid).unwrap();
    assert!(!status.can_shield);
    assert!(
        status.reason.contains("transparent funds are unavailable"),
        "{}",
        status.reason
    );

    // Once the source covers the new tip, authority resumes.
    source.fail(None);
    run_required(&mut wallet, &source).await;
    let resumed = balance(&wallet, &wallet.uuid);
    assert_eq!(
        resumed.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(resumed.transparent, VALUE);
}

#[tokio::test]
async fn a_rewind_pauses_authority_until_recovery_covers_the_new_chain() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;

    // Blocks above 180 are replaced by a fork.
    with_wallet_db_write_lock("test.transparent_ledger.rewind", || {
        wallet.db.truncate_to_height(BlockHeight::from_u32(180))
    })
    .unwrap();
    scan(&wallet.path, wallet.birthday, 181, TIP, 1);
    assert_ne!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Active,
        "a rewind keeps activation"
    );

    source.rehash(|height| chain_hash(height, u8::from(height > 180)));
    run_required(&mut wallet, &source).await;
    let resumed = balance(&wallet, &wallet.uuid);
    assert_eq!(
        resumed.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(resumed.transparent, VALUE);
}

#[tokio::test]
async fn activation_stops_public_lookups_captured_before_it() {
    let mut wallet = wallet();
    let lookups = EnhancementPolicy::current(NETWORK)
        .public_transparent_lookups(&wallet.db)
        .unwrap();
    assert!(lookups.is_allowed());
    let gate = TransparentLookupGate::for_wallet(lookups, &wallet.path, NETWORK).unwrap();
    let _mode = activate(&mut wallet).await;

    let sent = std::sync::atomic::AtomicUsize::new(0);
    let dispatched = gate
        .dispatch(async { sent.fetch_add(1, std::sync::atomic::Ordering::SeqCst) })
        .await;
    // This build's Public policy handle cannot read the stricter policy, and
    // fails closed; either way nothing is sent.
    assert!(!matches!(dispatched, Ok(Some(_))));
    assert_eq!(sent.load(std::sync::atomic::Ordering::SeqCst), 0);

    // A handle configured for the durable policy resolves to withheld.
    let withheld = required().public_transparent_lookups(&wallet.db).unwrap();
    assert!(!withheld.is_allowed());
}
