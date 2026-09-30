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

#[tokio::test]
async fn reopened_public_handle_displays_durable_private_authority() {
    let mut wallet = wallet();
    let mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    drop(mode); // Simulate restart: this build opens Public handles again.
    let current = balance(&wallet, &wallet.uuid);
    assert_eq!(
        current.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(current.transparent, VALUE);
    wallet
        .db
        .update_chain_tip(BlockHeight::from_u32(TIP + 1))
        .unwrap();
    let stale = balance(&wallet, &wallet.uuid);
    assert_eq!(
        stale.transparent_authority,
        TransparentBalanceAuthority::LastKnown
    );
    assert_eq!(stale.transparent, 0);
    assert_eq!(stale.transparent_last_known, Some(VALUE));
}

#[tokio::test]
async fn reopened_public_handle_never_labels_candidate_funds_current() {
    let mut wallet = wallet();
    let mode = activate(&mut wallet).await;
    let source = FixtureSource::new(main_hash);
    source.receive(receive(1, external(&wallet, 0), VALUE, 150));
    run_required(&mut wallet, &source).await;
    drop(mode);
    let b = balance(&wallet, &wallet.uuid);
    assert_ne!(
        b.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(b.transparent, 0);
}

// Authorization tests use finalized transaction effects; signature/proof validation
// remains in the PCZT preparation layer before this shared dispatch boundary.
fn hardware_tx(inputs: Vec<OutPoint>) -> zcash_primitives::transaction::Transaction {
    use transparent::{
        address::Script,
        bundle::{Authorized, Bundle, TxIn, TxOut},
    };
    use zcash_primitives::transaction::{TransactionData, TxVersion};
    TransactionData::<zcash_primitives::transaction::Authorized>::from_parts(
        TxVersion::V5,
        zcash_protocol::consensus::BranchId::Nu5,
        0,
        BlockHeight::from_u32(1000),
        Some(Bundle {
            vin: inputs
                .into_iter()
                .map(|p| TxIn::from_parts(p, Script::default(), u32::MAX))
                .collect(),
            vout: vec![TxOut::new(
                Zatoshis::const_from_u64(10_000),
                Script::default(),
            )],
            authorization: Authorized,
        }),
        None,
        None,
        None,
    )
    .freeze()
    .unwrap()
}

#[tokio::test]
async fn hardware_authority_blocks_revocation_and_preserves_inputs_on_rejection() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    let funding = receive(1, external(&wallet, 0), VALUE, 150);
    let tx = hardware_tx(vec![funding.outpoint]);
    let before = snapshot_for_hardware(&wallet);
    let other = rusqlite::Connection::open(&wallet.path).unwrap();
    other.busy_timeout(Duration::ZERO).unwrap();
    let result = crate::wallet::sync::hardware_authority::dispatch(
        &wallet.path,
        NETWORK,
        &tx,
        &[],
        TIP.into(),
        async {
            // A concurrent policy/recovery/rewind writer cannot commit after
            // authorization but before the bounded submission finishes.
            assert!(other
                .execute(
                    "UPDATE tpir_meta SET policy_generation = policy_generation",
                    []
                )
                .is_err());
            Err::<(), _>("definite rejection")
        },
    )
    .await
    .unwrap();
    assert_eq!(result, Err("definite rejection"));
    assert_eq!(snapshot_for_hardware(&wallet), before);
    assert_eq!(
        count(
            &wallet.path,
            &format!(
                "SELECT COUNT(*) FROM transactions WHERE txid=x'{}'",
                hex::encode(tx.txid().as_ref())
            )
        ),
        0
    );
    other
        .execute(
            "UPDATE tpir_meta SET policy_generation = policy_generation",
            [],
        )
        .unwrap();
}

fn snapshot_for_hardware(
    wallet: &Wallet,
) -> zcash_client_backend::data_api::transparent_ledger::TransparentLedgerSnapshot<AccountUuid> {
    wallet
        .db
        .transparent_ledger_snapshot(wallet.account, crate::wallet::confirmations_policy())
        .unwrap()
}

#[tokio::test]
async fn hardware_authority_withholds_stale_or_withdrawn_inputs_before_dispatch() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    let tx = hardware_tx(vec![receive(1, external(&wallet, 0), VALUE, 150).outpoint]);
    let sent = std::cell::Cell::new(0);
    wallet
        .db
        .update_chain_tip(BlockHeight::from_u32(TIP + 1))
        .unwrap();
    assert!(crate::wallet::sync::hardware_authority::dispatch(
        &wallet.path,
        NETWORK,
        &tx,
        &[],
        (TIP + 1).into(),
        async {
            sent.set(sent.get() + 1);
        }
    )
    .await
    .is_err());
    wallet
        .db
        .update_chain_tip(BlockHeight::from_u32(TIP))
        .unwrap();
    source.replace_events(vec![], vec![]);
    run_required(&mut wallet, &source).await;
    assert!(crate::wallet::sync::hardware_authority::dispatch(
        &wallet.path,
        NETWORK,
        &tx,
        &[],
        TIP.into(),
        async {
            sent.set(sent.get() + 1);
        }
    )
    .await
    .is_err());
    assert_eq!(sent.get(), 0);
}

#[tokio::test]
async fn hardware_authority_cancellation_releases_writer_reservation() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    let tx = hardware_tx(vec![receive(1, external(&wallet, 0), VALUE, 150).outpoint]);
    let mut dispatch = Box::pin(crate::wallet::sync::hardware_authority::dispatch(
        &wallet.path,
        NETWORK,
        &tx,
        &[],
        TIP.into(),
        std::future::pending::<()>(),
    ));
    assert!(futures::poll!(&mut dispatch).is_pending());
    let other = rusqlite::Connection::open(&wallet.path).unwrap();
    other.busy_timeout(Duration::ZERO).unwrap();
    assert!(other
        .execute(
            "UPDATE tpir_meta SET policy_generation = policy_generation",
            []
        )
        .is_err());
    drop(dispatch);
    other
        .execute(
            "UPDATE tpir_meta SET policy_generation = policy_generation",
            [],
        )
        .unwrap();
}

#[tokio::test]
async fn hardware_authority_admits_only_existing_chained_outputs() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    let parent = hardware_tx(vec![]);
    let child = hardware_tx(vec![OutPoint::new(*parent.txid().as_ref(), 0)]);
    assert_eq!(
        crate::wallet::sync::hardware_authority::dispatch(
            &wallet.path,
            NETWORK,
            &child,
            &[&parent],
            TIP.into(),
            async { true },
        )
        .await
        .unwrap(),
        true
    );
    let invalid = hardware_tx(vec![OutPoint::new(*parent.txid().as_ref(), 1)]);
    assert!(crate::wallet::sync::hardware_authority::dispatch(
        &wallet.path,
        NETWORK,
        &invalid,
        &[&parent],
        TIP.into(),
        async { panic!("withheld") },
    )
    .await
    .is_err());
}

#[tokio::test]
async fn hardware_authority_withholds_the_real_send_transaction_rpc_when_stale() {
    use crate::wallet::sync_engine::{send_transaction_with_status, test_lwd::CapturingLwd};
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    let tx = hardware_tx(vec![receive(1, external(&wallet, 0), VALUE, 150).outpoint]);
    let mut raw = Vec::new();
    tx.write(&mut raw).unwrap();
    let mut lwd = CapturingLwd::start(Vec::new()).await;
    // The capturing service records transport requests; it does not relay or
    // validate the fixture's synthetic signatures. This checks the real RPC
    // future's polling boundary independently of PCZT proof/signature tests.
    let before = snapshot_for_hardware(&wallet);
    let _response = crate::wallet::sync::hardware_authority::dispatch(
        &wallet.path,
        NETWORK,
        &tx,
        &[],
        TIP.into(),
        send_transaction_with_status(&mut lwd.client, &raw),
    )
    .await
    .unwrap();
    assert_eq!(lwd.count("/SendTransaction"), 1);
    assert_eq!(snapshot_for_hardware(&wallet), before);
    wallet
        .db
        .update_chain_tip(BlockHeight::from_u32(TIP + 1))
        .unwrap();
    assert!(crate::wallet::sync::hardware_authority::dispatch(
        &wallet.path,
        NETWORK,
        &tx,
        &[],
        (TIP + 1).into(),
        send_transaction_with_status(&mut lwd.client, &raw),
    )
    .await
    .is_err());
    assert_eq!(
        lwd.count("/SendTransaction"),
        1,
        "stale authority never polls the RPC"
    );
}

/// History of projected activity: discovery found the effects, not the
/// transactions, so a debit is shown as a provisional net amount.
#[tokio::test]
async fn projected_history_shows_a_known_debit_with_change_as_provisional() {
    use crate::wallet::sync::{get_transaction_history, TransactionFeeState};

    const CHANGE: u64 = 600_000;
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    let funding = receive(1, external(&wallet, 0), VALUE, 150);
    let change = derived(&wallet, TransparentKeyScope::INTERNAL, 0);
    source
        .spend(spend(3, &funding, 170))
        .receive(receive(3, change, CHANGE, 170));

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1);

    let history = get_transaction_history(&wallet.path, NETWORK, None, &wallet.uuid).unwrap();
    let rows = |tag: u8| {
        let txid = hex::encode([tag; 32]);
        history
            .iter()
            .filter(|tx| tx.txid_hex == txid)
            .collect::<Vec<_>>()
    };

    let received = rows(1);
    assert_eq!(received.len(), 1);
    assert_eq!(received[0].tx_kind, "received");
    assert_eq!(received[0].display_amount, VALUE);
    assert_eq!(received[0].fee_state, TransactionFeeState::NotApplicable);
    assert!(received[0].details_complete);
    assert!(!received[0].provisional);

    // The change is not a receive, and the debit is not a payment amount.
    let sent = rows(3);
    assert_eq!(sent.len(), 1, "one row for the debit, none for its change");
    assert_eq!(sent[0].tx_kind, "sent");
    assert_eq!(sent[0].display_amount, VALUE - CHANGE);
    assert_eq!(sent[0].display_pool, "unknown");
    assert_eq!(sent[0].fee_state, TransactionFeeState::Unknown);
    assert_eq!(sent[0].fee, 0);
    assert!(!sent[0].details_complete);
    assert!(sent[0].provisional);

    let detail = crate::wallet::sync::get_transaction_detail(
        &wallet.path,
        NETWORK,
        &wallet.uuid,
        &sent[0].txid_hex,
        "sent",
    )
    .unwrap();
    assert!(!detail.details_complete);
    assert!(detail.provisional);
    assert_eq!(detail.primary_address, None, "no recipient is invented");
}
