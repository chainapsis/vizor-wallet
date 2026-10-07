//! Qualification: the coordinator through the Rust API that FRB exposes,
//! across the lifecycle a wallet moves through (public, shadow, private
//! activation, promotion, restart), with request capture on every lane that
//! could disclose a transparent address, script, outpoint, or txid.
//!
//! Recovery runs against the trusted fixture source: under `PrivateRequired`
//! the coordinator qualifies its revisions as it applies them, as it does the
//! transparent PIR source's, and a shadow run only observes. The last test
//! also drives the real transparent PIR source, with the transport's request
//! observer standing in for the service. Nothing here reaches the live
//! service or qualifies production private authority.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use transparent::keys::TransparentKeyScope;
use zcash_client_backend::data_api::{
    transparent_ledger::{AccountLifecycle, RecoveryBlocker, WatchOrigin},
    wallet::decrypt_and_store_transaction,
};
use zcash_keys::encoding::AddressCodec;
use zcash_primitives::transaction::Transaction;

use super::super::pir::{test_transport, TransparentPirSource};
use super::activation::checkpoint_trees;
use super::pir::{
    assert_private, main_wallet, service, shard_map, MainWallet, BIRTHDAY, INIT, MAP, TOP,
};
use super::*;
use crate::wallet::sync::{get_shield_transparent_status, get_transaction_history};
use crate::wallet::sync::{TransactionFeeState, TransparentStopReason};
use crate::wallet::sync_engine::enhancement::{EnhancementSession, RoutePolicy};
use crate::wallet::sync_engine::test_lwd::CapturingLwd;
use crate::wallet::sync_engine::transparent_recovery_tests::{downloaded, legacy_transaction};
use crate::wallet::sync_engine::{
    address_discovery, ephemeral_checks, refresh_utxos, store_transparent_outputs,
    transparent_followup, TransparentAccountSelection,
};

/// Where public discovery found the legacy receipt.
const LEGACY_HEIGHT: u32 = 150;
/// Where public discovery found the mainnet lane wallet's legacy receipt.
const MAIN_LEGACY_HEIGHT: u32 = BIRTHDAY + 5;

/// Lightwalletd calls that disclose a transparent address, script, outpoint,
/// or txid.
const DISCLOSING_RPCS: &[&str] = &[
    "/GetAddressUtxos",
    "/GetAddressUtxosStream",
    "/GetTaddressTxids",
    "/GetTaddressTransactions",
    "/GetTaddressBalance",
    "/GetTaddressBalanceStream",
    "/GetTransaction",
];

fn disclosing(lwd: &CapturingLwd) -> Vec<String> {
    lwd.requests()
        .into_iter()
        .filter(|path| DISCLOSING_RPCS.iter().any(|rpc| path.ends_with(rpc)))
        .collect()
}

/// A receipt to the account's first external address, as a real transaction
/// so that its payload can be stored and replayed.
fn receipt(wallet: &Wallet, prevout_tag: u8) -> Transaction {
    legacy_transaction(
        OutPoint::new([prevout_tag; 32], 0),
        external(wallet, 0),
        VALUE,
    )
}

/// The receive event a private source reports for `tx`, mined at `height`.
fn reported_at(address: TransparentAddress, tx: &Transaction, height: u32) -> ReceiveEvent {
    ReceiveEvent {
        // Neither the fixture nor the transparent PIR source carries metadata.
        metadata: None,
        outpoint: OutPoint::new(*tx.txid().as_ref(), 0),
        address,
        value: Zatoshis::const_from_u64(VALUE),
        coinbase: false,
        mined_height: BlockHeight::from_u32(height),
    }
}

fn reported(wallet: &Wallet, tx: &Transaction) -> ReceiveEvent {
    reported_at(external(wallet, 0), tx, LEGACY_HEIGHT)
}

/// Stores `tx` the way public discovery does: the UTXO refresh records the
/// output, and payload retrieval stores the transaction.
fn store_publicly(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    uuid: &str,
    tx: &Transaction,
    height: u32,
) {
    store_transparent_outputs(db, &[downloaded(uuid, tx, height)]).unwrap();
    store_payload(db, network, tx, height);
}

fn store_payload(db: &mut WalletDatabase, network: WalletNetwork, tx: &Transaction, height: u32) {
    decrypt_and_store_transaction(&network, db, tx, Some(BlockHeight::from_u32(height))).unwrap();
}

fn replay_payload(wallet: &mut Wallet, tx: &Transaction) {
    store_payload(&mut wallet.db, NETWORK, tx, LEGACY_HEIGHT);
}

/// A wallet whose transparent receipt was found by public discovery.
fn legacy_wallet() -> (Wallet, Transaction) {
    let mut wallet = wallet();
    let tx = receipt(&wallet, 0xaa);
    store_publicly(&mut wallet.db, NETWORK, &wallet.uuid, &tx, LEGACY_HEIGHT);
    complete_public_history(&mut wallet);
    (wallet, tx)
}

/// Records what a public sync completes before its public transparent
/// history counts as complete: initial address discovery, and every spend
/// search due for the outputs it stored.
fn complete_public_history(wallet: &mut Wallet) {
    use zcash_client_backend::data_api::{TransactionDataRequest, WalletWrite};
    address_discovery::record_initial_discovery_for_test(&wallet.path, wallet.account, TIP);
    let requests = wallet.db.transaction_data_requests().unwrap();
    for TransactionDataRequest::TransactionsInvolvingAddress(request) in requests {
        if let Some(end) = request.block_range_end() {
            wallet
                .db
                .transactionally(|tx| tx.notify_address_checked(request, end - 1))
                .unwrap();
        }
    }
}

/// History rows for `tx`, as `(kind, amount, fee state, provisional)`.
fn history_rows(
    wallet: &Wallet,
    tx: &Transaction,
) -> Vec<(String, u64, TransactionFeeState, bool)> {
    let txid = hex::encode(tx.txid().as_ref());
    get_transaction_history(&wallet.path, NETWORK, None, &wallet.uuid)
        .unwrap()
        .into_iter()
        .filter(|row| row.txid_hex == txid)
        .map(|row| {
            (
                row.tx_kind,
                row.display_amount,
                row.fee_state,
                row.provisional,
            )
        })
        .collect()
}

fn can_shield(wallet: &Wallet) -> (bool, String) {
    let status = get_shield_transparent_status(&wallet.path, NETWORK, &wallet.uuid).unwrap();
    (status.can_shield, status.reason)
}

fn assert_current(wallet: &Wallet, value: u64) {
    let balance = balance(wallet, &wallet.uuid);
    assert_eq!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(balance.transparent, value);
    assert_eq!(balance.transparent_last_known, None);
}

fn assert_last_known(wallet: &Wallet, value: u64) {
    let balance = balance(wallet, &wallet.uuid);
    assert_eq!(
        balance.transparent_authority,
        TransparentBalanceAuthority::LastKnown
    );
    assert_eq!(balance.transparent, 0, "nothing is spendable");
    assert_eq!(balance.transparent_last_known, Some(value));
    let (can_shield, reason) = can_shield(wallet);
    assert!(!can_shield);
    assert!(
        reason.contains("transparent funds are unavailable"),
        "reports recovery, not an empty balance: {reason}"
    );
}

/// A run an hour later, when every hold set now has lapsed.
fn after_the_hold() -> Instant {
    now() + HOLD
}

/// Public discovery, then shadow recovery, then activation and promotion:
/// the balance stays public and exact until activation, is last-known until
/// the account is promoted, and is the same amount once it is.
#[tokio::test]
async fn public_to_shadow_to_private_keeps_the_same_funds_and_history() {
    let (mut wallet, tx) = legacy_wallet();
    assert_current(&wallet, VALUE);
    let public_history = history_rows(&wallet, &tx);
    assert_eq!(public_history.len(), 1);

    // Shadow recovery reports the same receipt without touching production,
    // and only observes: even a trusted source's revisions stay unqualified.
    apply_policy(&wallet.path, TransparentLedgerMode::PrivateShadow);
    let source = FixtureSource::new(main_hash);
    source.receive(reported(&wallet, &tx)).trust();
    let before = production_dump(&wallet.path);
    let RunOutcome::Finished(shadow_stats) = recover(&mut wallet, &source).await else {
        panic!("shadow recovery finishes");
    };
    assert_eq!(shadow_stats.qualified, 0);
    assert_complete(&wallet, &source);
    assert_eq!(production_dump(&wallet.path), before);
    assert_current(&wallet, VALUE);

    // Activation stops public authority at once; the prior amount is shown
    // as last-known until the account is promoted.
    let _mode = activate(&mut wallet).await;
    assert_last_known(&wallet, VALUE);
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert!(
        stats.qualified > 0,
        "the trusted source's revision qualified"
    );
    assert_eq!(stats.promoted, 1);
    assert_current(&wallet, VALUE);
    checkpoint_trees(&mut wallet, TIP);
    let (can_shield, reason) = can_shield(&wallet);
    assert!(can_shield, "{reason}");
    // Promotion adds no row and keeps the receipt's kind and amount. Public
    // discovery left the receipt provisional with an unknown fee: its input's
    // parent was still queued for retrieval and could have been the account's
    // own. Complete private coverage shows the account made no spend in it,
    // so the entry settles as a plain receive.
    let private_history = history_rows(&wallet, &tx);
    assert_eq!(private_history.len(), 1);
    assert_eq!(
        (&private_history[0].0, private_history[0].1),
        (&public_history[0].0, public_history[0].1)
    );
    assert_eq!(public_history[0].2, TransactionFeeState::Unknown);
    assert!(public_history[0].3);
    assert_eq!(private_history[0].2, TransactionFeeState::NotApplicable);
    assert!(!private_history[0].3);
}

/// A mined legacy UTXO the private source never reports is an unexplained
/// discrepancy: promotion stays blocked, and since retrying cannot explain
/// it, the account is held and shows recovery stopped, with the prior amount
/// for context. Once the source reports it, the run after the hold promotes.
#[tokio::test]
async fn an_unreported_legacy_utxo_blocks_promotion() {
    let (mut wallet, tx) = legacy_wallet();
    let _mode = activate(&mut wallet).await;
    let source = FixtureSource::new(main_hash);
    source.trust();

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 0);
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );
    let snapshot = wallet
        .db
        .transparent_ledger_snapshot(wallet.account, crate::wallet::confirmations_policy())
        .unwrap();
    assert!(
        snapshot
            .blockers
            .contains(&RecoveryBlocker::LegacyDiscrepancy),
        "{:?}",
        snapshot.blockers
    );
    assert_eq!(
        recovery_hold(&wallet.path, wallet.account),
        Some(HoldCause::LegacyDiscrepancy)
    );
    let stopped = balance(&wallet, &wallet.uuid);
    assert_eq!(
        stopped.transparent_authority,
        TransparentBalanceAuthority::Stopped
    );
    assert_eq!(
        stopped.transparent_stop,
        Some(TransparentStopReason::LegacyDiscrepancy)
    );
    assert_eq!(stopped.transparent, 0, "nothing is spendable");
    assert_eq!(stopped.transparent_last_known, Some(VALUE));
    assert!(!can_shield(&wallet).0);

    // Once the source reports it, the discrepancy is explained.
    source.receive(reported(&wallet, &tx));
    let RunOutcome::Finished(stats) = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        None,
        after_the_hold,
        &|| false,
    )
    .await
    .unwrap() else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1);
    assert_current(&wallet, VALUE);
}

/// Shadow evidence survives activation, but only promotion's own recheck
/// makes it authoritative: once the chain has advanced, promotion refuses
/// until a trusted pass covers the new tip.
#[tokio::test]
async fn shadow_state_is_reused_only_after_revalidation() {
    let (mut wallet, tx) = legacy_wallet();
    apply_policy(&wallet.path, TransparentLedgerMode::PrivateShadow);
    let source = FixtureSource::new(main_hash);
    source.receive(reported(&wallet, &tx)).trust();
    recover(&mut wallet, &source).await;
    let _mode = activate(&mut wallet).await;

    // The chain advanced after the shadow run: its coverage no longer
    // reaches the tip, so promotion refuses.
    scan(&wallet.path, wallet.birthday, TIP + 1, TIP + 1, 0);
    let blocked = with_wallet_db_write_lock("test.transparent_ledger.promote", || {
        wallet.db.promote_transparent_account(wallet.account)
    });
    assert!(
        matches!(
            blocked,
            Err(SqliteClientError::TransparentPromotionBlocked(_))
        ),
        "{blocked:?}"
    );
    assert_last_known(&wallet, VALUE);

    // A fresh pass covers the new tip, and promotion follows.
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1);
    assert_current(&wallet, VALUE);
}

/// Shadow coverage at the current tip is reused, but a shadow run only
/// observes, so its revision is unqualified and promotion refuses. One
/// trusted pass at the same tip replays that revision, which qualifies it,
/// and the account is promoted.
#[tokio::test]
async fn shadow_coverage_at_the_current_tip_promotes_after_one_trusted_pass() {
    let (mut wallet, tx) = legacy_wallet();
    apply_policy(&wallet.path, TransparentLedgerMode::PrivateShadow);
    let source = FixtureSource::new(main_hash);
    source.receive(reported(&wallet, &tx)).trust();
    recover(&mut wallet, &source).await;
    let revisions = count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions");
    let _mode = activate(&mut wallet).await;

    let blocked = with_wallet_db_write_lock("test.transparent_ledger.promote", || {
        wallet.db.promote_transparent_account(wallet.account)
    });
    assert!(
        matches!(
            &blocked,
            Err(SqliteClientError::TransparentPromotionBlocked(blockers))
                if blockers.contains(&RecoveryBlocker::UnqualifiedRevision)
        ),
        "{blocked:?}"
    );
    assert_last_known(&wallet, VALUE);

    let calls = source.calls();
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(source.calls(), calls + 1, "one pass was enough");
    assert_eq!((stats.qualified, stats.promoted), (1, 1));
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions"),
        revisions,
        "the shadow revision was qualified, not replaced"
    );
    assert_current(&wallet, VALUE);
}

/// An activation interrupted before recovery, or during it, resumes under the
/// stricter policy: after a restart nothing reverts to public authority, and a
/// later run promotes.
#[tokio::test]
async fn interrupted_activation_resumes_under_the_stricter_policy() {
    let (mut wallet, tx) = legacy_wallet();
    let _mode = activate(&mut wallet).await;
    let source = FixtureSource::new(main_hash);
    source.receive(reported(&wallet, &tx)).trust();

    // The run is cancelled while the source answers its first call.
    let exit = Arc::new(AtomicBool::new(false));
    let flag = exit.clone();
    source.on_call(move || flag.store(true, Ordering::SeqCst));
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        None,
        now,
        &|| exit.load(Ordering::SeqCst),
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::Exited);
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );

    // Restart: fresh handles on the same file.
    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    assert_last_known(&wallet, VALUE);
    let lookups = EnhancementPolicy::current(NETWORK)
        .public_transparent_lookups(&wallet.db)
        .unwrap();
    assert!(
        !lookups.is_allowed(),
        "the durable policy withholds lookups"
    );

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1);
    assert_current(&wallet, VALUE);
}

/// Every production table except Vizor's mined-history evidence. Replaying a
/// commit re-applies the transaction's placement, and that trigger records
/// the transaction as once mined; it only guards resubmission.
fn dump_without_mined_history(path: &str) -> Vec<(String, Vec<String>)> {
    production_dump(path)
        .into_iter()
        .filter(|(table, _)| table != "vizor_mined_transactions")
        .collect()
}

/// Promotion is durable: a restarted wallet keeps private authority without a
/// source call, and a later run changes nothing.
#[tokio::test]
async fn private_authority_survives_restart() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    assert_current(&wallet, VALUE);
    let before = dump_without_mined_history(&wallet.path);

    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
    assert_current(&wallet, VALUE);

    let restarted = funded_source(&wallet);
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &restarted).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 0);
    assert_eq!(
        dump_without_mined_history(&wallet.path),
        before,
        "a replayed pass is idempotent"
    );
    assert_current(&wallet, VALUE);
}

/// What a user can see of one transaction: its balance, visible history, and
/// the rows that back them.
fn observed(
    wallet: &Wallet,
    tx: &Transaction,
) -> (u64, Vec<(String, u64, TransactionFeeState, bool)>, i64, i64) {
    let txid = tx.txid();
    (
        balance(wallet, &wallet.uuid).transparent,
        history_rows(wallet, tx),
        count(
            &wallet.path,
            &format!(
                "SELECT COUNT(*) FROM transactions WHERE txid = x'{}'",
                hex::encode(txid.as_ref())
            ),
        ),
        count(
            &wallet.path,
            "SELECT COUNT(*) FROM transparent_received_outputs",
        ),
    )
}

/// Both discovery orders, and a payload replayed afterwards, reach the same
/// balance, history, and rows: one transaction and one output.
#[tokio::test]
async fn both_discovery_orders_and_payload_replay_agree() {
    // Ledger first, then the payload.
    let mut ledger_first = wallet();
    let tx = receipt(&ledger_first, 0xbb);
    let _mode = activate(&mut ledger_first).await;
    let source = FixtureSource::new(main_hash);
    source.receive(reported(&ledger_first, &tx)).trust();
    run_required(&mut ledger_first, &source).await;
    replay_payload(&mut ledger_first, &tx);
    let a = observed(&ledger_first, &tx);

    // Payload first, then the ledger.
    let mut payload_first = wallet();
    let tx_b = receipt(&payload_first, 0xbb);
    let _mode_b = activate(&mut payload_first).await;
    replay_payload(&mut payload_first, &tx_b);
    let source_b = FixtureSource::new(main_hash);
    source_b.receive(reported(&payload_first, &tx_b)).trust();
    run_required(&mut payload_first, &source_b).await;
    let b = observed(&payload_first, &tx_b);

    assert_eq!(a.0, VALUE);
    assert_eq!(a.1.len(), 1, "one history row: {:?}", a.1);
    assert_eq!((a.2, a.3), (1, 1), "one transaction and one output");
    assert_eq!(a, b);

    // Replaying the payload again changes nothing.
    replay_payload(&mut payload_first, &tx_b);
    assert_eq!(observed(&payload_first, &tx_b), b);
}

/// Adding an account rescans from its birthday. That rewind clips every
/// account's coverage, so an active account pauses at its last-known amount
/// and stays active; the next recovery pass restores it, and the new account
/// is recovered and promoted on its own. Deleting the new account leaves the
/// active one current.
#[tokio::test]
async fn account_changes_pause_authority_only_until_the_next_pass() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    assert_current(&wallet, VALUE);

    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (other_uuid, _) =
        keys::add_account(&wallet.path, NETWORK, "other", &seed, Some(100)).unwrap();
    let other = keys::parse_account_uuid(&other_uuid).unwrap();
    scan(&wallet.path, wallet.birthday, wallet.birthday, TIP, 0);
    assert_eq!(lifecycle(&wallet, other), AccountLifecycle::Candidate);
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
    // The rescan un-mined the receipt and dropped its coverage, so nothing is
    // spendable. The snapshot then reports a last-known amount of 0 with no
    // chain point instead of the prior amount.
    let paused = balance(&wallet, &wallet.uuid);
    assert_ne!(
        paused.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(paused.transparent, 0);
    assert!(!can_shield(&wallet).0);
    assert_ne!(
        balance(&wallet, &other_uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1, "only the new account is promoted");
    assert_current(&wallet, VALUE);
    assert_eq!(lifecycle(&wallet, other), AccountLifecycle::Active);

    keys::delete_account(&wallet.path, NETWORK, &other_uuid).unwrap();
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
    assert_current(&wallet, VALUE);
}

/// Incomplete transparent recovery gates transparent inputs only. A send to a
/// transparent address is funded from shielded pools, so it is refused for
/// lack of shielded funds, never as "transparent funds are unavailable". The
/// library's own tests cover such an unshielding succeeding.
#[tokio::test]
async fn incomplete_recovery_does_not_gate_shielded_funded_sends() {
    let (mut wallet, _tx) = legacy_wallet();
    let _mode = activate(&mut wallet).await;
    assert_last_known(&wallet, VALUE);
    checkpoint_trees(&mut wallet, TIP);

    let recipient = external(&wallet, 1).encode(&NETWORK);
    let refused = crate::wallet::sync::propose_send(
        &wallet.path,
        NETWORK,
        &wallet.uuid,
        "qualification-unshield",
        &recipient,
        10_000,
        None,
    )
    .err()
    .expect("the wallet has no shielded funds");
    assert!(
        !refused.contains("transparent funds are unavailable")
            && !refused.contains("TransparentAuthorityUnavailable"),
        "a shielded-funded send is not gated on transparent recovery: {refused}"
    );
}

/// `account`'s first external address, from its watch set.
fn first_external(db: &WalletDatabase, account: AccountUuid) -> TransparentAddress {
    db.transparent_watch_set(account)
        .unwrap()
        .addresses
        .into_iter()
        .find_map(|watched| match watched.origin {
            WatchOrigin::Derived { scope, index }
                if scope == TransparentKeyScope::EXTERNAL && index.index() == 0 =>
            {
                Some(watched.address)
            }
            _ => None,
        })
        .expect("the first external address is watched")
}

/// The key or script hash of every address `account` watches: what a request
/// carrying one of its scripts would carry.
fn watched_hashes(db: &WalletDatabase, account: AccountUuid) -> Vec<Vec<u8>> {
    db.transparent_watch_set(account)
        .unwrap()
        .addresses
        .into_iter()
        .map(|watched| match watched.address {
            TransparentAddress::PublicKeyHash(hash) | TransparentAddress::ScriptHash(hash) => {
                hash.to_vec()
            }
        })
        .collect()
}

/// Imports a Ledger account into the mainnet wallet at `path`. Returns its
/// UUID text.
fn import_main_ledger(path: &str) -> String {
    use secrecy::ExposeSecret;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let ufvk = zcash_keys::keys::UnifiedSpendingKey::from_seed(
        &WalletNetwork::Main,
        seed.expose_secret(),
        zip32::AccountId::ZERO,
    )
    .unwrap()
    .to_unified_full_viewing_key();
    let fingerprint = zip32::fingerprint::SeedFingerprint::from_seed(seed.expose_secret())
        .unwrap()
        .to_bytes();
    keys::import_hardware_account(
        path,
        WalletNetwork::Main,
        "Ledger",
        &ufvk.encode(&WalletNetwork::Main),
        &fingerprint,
        0,
        Some(u64::from(BIRTHDAY)),
        HardwareSignerKind::Ledger,
    )
    .unwrap()
    .0
}

/// A mainnet wallet with a Ledger account beside its software one, scanned
/// through [`TOP`], and a legacy receipt to the software account's first
/// external address stored the way public discovery stores it, which leaves
/// public follow-on work queued. Returns the wallet, that address, and the
/// receipt.
fn lane_wallet() -> (MainWallet, TransparentAddress, Transaction) {
    let wallet = main_wallet(1);
    let (uuid, account) = wallet.accounts[0].clone();
    import_main_ledger(&wallet.path);
    let floor: u32 = count(&wallet.path, "SELECT MIN(birthday_height) FROM accounts")
        .try_into()
        .unwrap();
    scan(&wallet.path, floor, floor, TOP, 0);
    let mut db =
        open_wallet_db_with_timeout(&wallet.path, WalletNetwork::Main, SYNC_DB_BUSY_TIMEOUT)
            .unwrap();
    let address = first_external(&db, account);
    let tx = legacy_transaction(OutPoint::new([0xaa; 32], 0), address, VALUE);
    store_publicly(&mut db, WalletNetwork::Main, &uuid, &tx, MAIN_LEGACY_HEIGHT);
    (wallet, address, tx)
}

/// Lightwalletd answering any request that reaches it with a payment to
/// `address`, at a tip of [`TOP`].
async fn lightwalletd_paying(address: TransparentAddress) -> CapturingLwd {
    let mut history_tx = Vec::new();
    legacy_transaction(OutPoint::new([0xcc; 32], 0), address, VALUE)
        .write(&mut history_tx)
        .unwrap();
    CapturingLwd::start_with(history_tx, u64::from(TOP), |_| {}).await
}

/// A mainnet wallet in a build with the development flag and private queries
/// on, with public follow-on work queued before activation and a Ledger
/// account beside the software one: startup, every sync lane, import,
/// preview, the private recovery follow-up with the real transparent PIR
/// source, and the iOS observe ABI either withhold or fail closed, send
/// lightwalletd nothing that discloses a transparent address, script,
/// outpoint, or txid, and leave the queued work durable. The source's
/// requests use only the service's routes and carry no script. Turning
/// private queries off then sends public UTXO lookups again: the capture
/// would have seen a disclosure.
#[tokio::test(flavor = "multi_thread")]
async fn an_activated_wallet_discloses_nothing_through_any_lane_including_the_pir_source() {
    const MAIN: WalletNetwork = WalletNetwork::Main;
    let _route = crate::network_privacy::test_route_policy::lock_route_policy();
    let (wallet, address, tx) = lane_wallet();
    let path = wallet.path.clone();
    let (uuid, account) = wallet.accounts[0].clone();

    let queued = || count(&path, "SELECT COUNT(*) FROM tx_retrieval_queue");
    let unchecked_history = || count(&path, "SELECT COUNT(*) FROM transparent_spend_search_queue");
    let (queued_before, history_before) = (queued(), unchecked_history());
    assert!(
        queued_before > 0,
        "the payload left public follow-on work queued"
    );

    // The development flag with private queries on, read from storage.
    let mode = test_mode::set(&path, TransparentLedgerMode::PrivateRequired);
    let required = EnhancementPolicy::for_preference(MAIN, false)
        .with_transparent_mode(TransparentLedgerMode::PrivateRequired);

    // Startup reconciles the setting: it raises the wallet, which sends
    // nothing anywhere.
    let raised = set_transparent_policy(&path, MAIN, true, true)
        .await
        .unwrap()
        .expect("startup raises the public wallet");
    assert_eq!(raised.mode, TransparentLedgerMode::PrivateRequired);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();

    // A trusted recovery promotes the software account; the Ledger account
    // pauses.
    let fixture = FixtureSource::new(main_hash);
    fixture
        .receive(reported_at(address, &tx, MAIN_LEGACY_HEIGHT))
        .trust();
    let RunOutcome::Finished(stats) = run(
        &mut db,
        &path,
        MAIN,
        required,
        &fixture,
        Some(account),
        now,
        &|| false,
    )
    .await
    .unwrap() else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.promoted, stats.paused_ledger), (1, 1));
    let current = || get_wallet_balance(&path, MAIN, &uuid).unwrap();
    assert_eq!(
        (current().transparent_authority, current().transparent),
        (TransparentBalanceAuthority::Current, VALUE)
    );

    let mut lwd = lightwalletd_paying(address).await;
    let tip = BlockHeight::from_u32(TOP);

    // Both a default build's captured policy and the flag build's: once the
    // wallet is raised, its durable policy withholds lookups in every build.
    for policy in [EnhancementPolicy::current(MAIN), required] {
        let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();

        // Sync: address discovery, the restored ephemeral check, the UTXO
        // refresh, and the deferred refresh of inactive accounts.
        address_discovery::run(
            &mut lwd.client,
            &mut db,
            &path,
            &lwd.url,
            MAIN,
            policy,
            tip,
            &|| false,
        )
        .await
        .unwrap();
        assert!(!address_discovery::run_restored_ephemeral(
            &mut lwd.client,
            &mut db,
            &path,
            &lwd.url,
            MAIN,
            policy,
            tip,
            &|| false,
        )
        .await
        .unwrap());
        for selection in [
            TransparentAccountSelection::All,
            TransparentAccountSelection::Except(&uuid),
        ] {
            let mut received = false;
            let refreshed = refresh_utxos(
                &mut lwd.client,
                &path,
                &mut db,
                MAIN,
                policy,
                tip,
                selection,
                None,
                &mut received,
                None,
                &|| false,
            )
            .await
            .unwrap();
            assert!(refreshed.withheld);
            assert!(!received);
        }

        // Enhancement: queued payloads, parents, status, and address history,
        // then the ZIP 320 ephemeral checks.
        let mut session = EnhancementSession::with_policy(MAIN, &path, policy);
        let _ = session
            .run_payload_recovery(&mut db, &mut lwd.client, None, &|| false)
            .await;
        let _ = session
            .run_checkpoint(&mut db, &mut lwd.client, None, &|| false)
            .await;
        let mut changed = false;
        ephemeral_checks::run(
            &lwd.url,
            &mut db,
            &path,
            MAIN,
            policy,
            tip,
            &mut changed,
            &|| false,
        )
        .await
        .unwrap();
        assert!(!changed);
    }

    // Import into the existing wallet: account discovery and the balance
    // preview, each on its own runtime as FRB runs them.
    let mnemonic = keys::generate_mnemonic();
    let (url, wallet_path) = (lwd.url.clone(), path.clone());
    let (discovered, preview) = tokio::task::spawn_blocking(move || {
        use crate::api::wallet;
        let discovered = wallet::discover_software_wallet_import_accounts(
            mnemonic.clone(),
            String::new(),
            None,
            "main".into(),
            wallet_path.clone(),
            url.clone(),
            false,
        );
        let preview = wallet::preview_software_account_transparent_balance(
            mnemonic,
            String::new(),
            "main".into(),
            wallet_path,
            url,
            0,
            false,
        );
        (discovered, preview)
    })
    .await
    .unwrap();
    assert!(discovered.unwrap().accounts.is_empty());
    let preview = preview.expect_err("a withheld preview is not a balance");
    assert!(preview.contains("unavailable"), "{preview}");

    // The private recovery follow-up of a completed sync, with the real
    // transparent PIR source. The service publishes a map and its schema
    // and refuses the rest, so the pass fails after its first filter.
    let seam = test_transport::set(
        &path,
        service(Arc::new(Mutex::new(shard_map(BIRTHDAY - 100)))),
    );
    let events = Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    let source = TransparentPirSource::new(&path, MAIN);
    let mut followup_db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    transparent_followup(
        &mut followup_db,
        &path,
        MAIN,
        required,
        &source,
        Some(account),
        &|| false,
        &progress,
        (u64::from(TOP), u64::from(TOP) + 1),
    )
    .await;
    drop(source);
    {
        let events = events.lock().unwrap();
        assert_eq!(events.len(), 1, "completion is reported again");
        assert!(events[0].is_complete && events[0].has_new_tx);
    }
    // The deferred refresh after it is withheld too.
    let mut received = false;
    let deferred = refresh_utxos(
        &mut lwd.client,
        &path,
        &mut followup_db,
        MAIN,
        required,
        tip,
        TransparentAccountSelection::Except(&uuid),
        None,
        &mut received,
        None,
        &|| false,
    )
    .await
    .unwrap();
    assert!(deferred.withheld && !received);

    // The iOS observe ABI, on its own runtime.
    let (url, wallet_path, txid) = (lwd.url.clone(), path.clone(), *tx.txid().as_ref());
    let observed = tokio::task::spawn_blocking(move || {
        let url = std::ffi::CString::new(url).unwrap();
        let wallet_path = std::ffi::CString::new(wallet_path).unwrap();
        let network = std::ffi::CString::new("main").unwrap();
        let mut output = crate::ffi::CLightwalletdTransactionObservation {
            state: 99,
            mined_height: 99,
        };
        let code = crate::ffi::zcash_lightwalletd_observe_transaction(
            url.as_ptr(),
            wallet_path.as_ptr(),
            network.as_ptr(),
            txid.as_ptr(),
            txid.len(),
            &mut output,
            std::ptr::null(),
        );
        (code, output.state)
    })
    .await
    .unwrap();
    assert_eq!(observed, (crate::ffi::STATUS_RESULT_UNSUPPORTED, 99));

    assert_eq!(disclosing(&lwd), Vec::<String>::new());
    assert_eq!(queued(), queued_before, "queued work stays durable");
    assert_eq!(unchecked_history(), history_before);
    assert_eq!(
        (current().transparent_authority, current().transparent),
        (TransparentBalanceAuthority::Current, VALUE)
    );

    // The source sent only service routes, on the wallet's route, and no
    // script or txid: the map, the schema, and the one filter it refused.
    let requests = seam.seam.observer.requests();
    let paths: Vec<_> = requests
        .iter()
        .map(|request| request.path.as_str())
        .collect();
    assert_eq!(paths[..2], [MAP, INIT]);
    assert_eq!(requests.len(), 3, "one filter, then the pass failed");
    assert_eq!(seam.seam.routes(), [RoutePolicy::WalletPreference]);
    let mut secrets = watched_hashes(&db, account);
    secrets.push(txid.to_vec());
    assert_private(&requests, &secrets);

    // Positive control: turning private queries off lowers the wallet in
    // every build, and the next UTXO refresh discloses its addresses.
    let lowered = set_transparent_policy(&path, MAIN, false, true)
        .await
        .unwrap()
        .expect("toggle-off lowers the private wallet");
    assert_eq!(lowered.mode, TransparentLedgerMode::Public);
    drop(mode);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let mut received = false;
    let refreshed = refresh_utxos(
        &mut lwd.client,
        &path,
        &mut db,
        MAIN,
        EnhancementPolicy::for_inputs(MAIN, false, true),
        tip,
        TransparentAccountSelection::All,
        None,
        &mut received,
        None,
        &|| false,
    )
    .await
    .unwrap();
    assert!(!refreshed.withheld);
    assert!(
        lwd.requests()
            .iter()
            .any(|path| path.ends_with("/GetAddressUtxos")
                || path.ends_with("/GetAddressUtxosStream")),
        "the control sends public UTXO lookups"
    );
}

/// The window before a flag build raises the wallet: private queries are on
/// but not yet read from storage, so nothing may raise the wallet, and its
/// durable policy is still `Public`. As for a new wallet before its first
/// follow-up, only the policy each lane captured withholds its lookups.
///
/// Under the flag build's policy, Ledger discovery, the UTXO refresh and the
/// deferred refresh, ephemeral checks, import discovery and the preview, the
/// follow-up with the real transparent PIR source, and the iOS observe ABI
/// send lightwalletd nothing that discloses a transparent address, script,
/// outpoint, or txid. The follow-up does not raise the wallet, so it sends the
/// service nothing, creates no companion, and reports nothing again. The
/// queued work stays durable.
#[cfg(not(ironwood_masquerade))]
#[tokio::test(flavor = "multi_thread")]
async fn a_flag_build_discloses_nothing_before_it_raises_the_wallet() {
    use crate::api::wallet::{
        discover_used_software_accounts, import_gate, preview_transparent_balance_for_addresses,
    };
    const MAIN: WalletNetwork = WalletNetwork::Main;
    let _route = crate::network_privacy::test_route_policy::lock_route_policy();
    let (wallet, address, tx) = lane_wallet();
    let path = wallet.path.clone();
    let (uuid, account) = wallet.accounts[0].clone();
    let queued = || count(&path, "SELECT COUNT(*) FROM tx_retrieval_queue");
    let unchecked_history = || count(&path, "SELECT COUNT(*) FROM transparent_spend_search_queue");
    let (queued_before, history_before) = (queued(), unchecked_history());
    assert!(queued_before > 0);
    let before = applied(&path, MAIN);
    assert_eq!(before.mode, TransparentLedgerMode::Public);

    // The development flag with private queries on, the preference unread.
    let _mode = test_mode::select(&path, TransparentLedgerMode::PrivateRequired, false);
    let flag = EnhancementPolicy::for_inputs(MAIN, true, true);
    assert_eq!(
        flag.transparent_mode(),
        TransparentLedgerMode::PrivateRequired
    );
    let mut lwd = lightwalletd_paying(address).await;
    let tip = BlockHeight::from_u32(TOP);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();

    // Sync: address discovery, the restored ephemeral check, and the UTXO
    // refresh.
    address_discovery::run(
        &mut lwd.client,
        &mut db,
        &path,
        &lwd.url,
        MAIN,
        flag,
        tip,
        &|| false,
    )
    .await
    .unwrap();
    assert!(!address_discovery::run_restored_ephemeral(
        &mut lwd.client,
        &mut db,
        &path,
        &lwd.url,
        MAIN,
        flag,
        tip,
        &|| false,
    )
    .await
    .unwrap());
    let mut received = false;
    let refreshed = refresh_utxos(
        &mut lwd.client,
        &path,
        &mut db,
        MAIN,
        flag,
        tip,
        TransparentAccountSelection::All,
        None,
        &mut received,
        None,
        &|| false,
    )
    .await
    .unwrap();
    assert!(refreshed.withheld && !received);

    // Payload recovery and the status and history checkpoint, under the flag
    // build's transparent mode. Its private payload and status routes would
    // reach the live services, so these run with public routes instead, which
    // only adds requests lightwalletd could see.
    let public_routes = EnhancementPolicy::for_preference(MAIN, false)
        .with_transparent_mode(TransparentLedgerMode::PrivateRequired);
    let mut session = EnhancementSession::with_policy(MAIN, &path, public_routes);
    let _ = session
        .run_payload_recovery(&mut db, &mut lwd.client, None, &|| false)
        .await;
    let _ = session
        .run_checkpoint(&mut db, &mut lwd.client, None, &|| false)
        .await;
    let mut changed = false;
    ephemeral_checks::run(
        &lwd.url,
        &mut db,
        &path,
        MAIN,
        flag,
        tip,
        &mut changed,
        &|| false,
    )
    .await
    .unwrap();
    assert!(!changed);

    // Import into this wallet and as a first account: discovery and preview.
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    for first_account in [false, true] {
        let gate = import_gate(MAIN, &path, first_account, flag).unwrap();
        assert!(!gate.is_allowed());
        assert!(discover_used_software_accounts(
            MAIN,
            &seed,
            Some(u64::from(BIRTHDAY)),
            &lwd.url,
            &gate
        )
        .await
        .is_empty());
        let addresses = keys::software_account_transparent_addresses(MAIN, &seed, 0, 2).unwrap();
        assert!(
            preview_transparent_balance_for_addresses(&lwd.url, addresses, &gate)
                .await
                .is_err(),
            "a withheld preview is not a balance"
        );
    }

    // The private recovery follow-up with the real source, then the deferred
    // refresh after it.
    let seam = test_transport::set(
        &path,
        service(Arc::new(Mutex::new(shard_map(BIRTHDAY - 100)))),
    );
    let events = Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    let source = TransparentPirSource::new(&path, MAIN);
    transparent_followup(
        &mut db,
        &path,
        MAIN,
        flag,
        &source,
        Some(account),
        &|| false,
        &progress,
        (u64::from(TOP), u64::from(TOP) + 1),
    )
    .await;
    drop(source);
    assert!(
        events.lock().unwrap().is_empty(),
        "nothing is reported again"
    );
    assert!(seam.seam.observer.requests().is_empty());
    assert!(!std::path::Path::new(&format!("{path}.tpir")).exists());
    let mut received = false;
    let deferred = refresh_utxos(
        &mut lwd.client,
        &path,
        &mut db,
        MAIN,
        flag,
        tip,
        TransparentAccountSelection::Except(&uuid),
        None,
        &mut received,
        None,
        &|| false,
    )
    .await
    .unwrap();
    assert!(deferred.withheld && !received);

    // The iOS observe ABI, on its own runtime.
    let (url, wallet_path, txid) = (lwd.url.clone(), path.clone(), tx.txid());
    let observed = tokio::task::spawn_blocking(move || {
        let mut output = crate::ffi::CLightwalletdTransactionObservation {
            state: 99,
            mined_height: 99,
        };
        let code = crate::ffi::observe_public_transaction(
            &url,
            &wallet_path,
            MAIN,
            flag,
            txid,
            &mut output,
            None,
        );
        (code, output.state)
    })
    .await
    .unwrap();
    assert_eq!(observed, (crate::ffi::STATUS_RESULT_UNSUPPORTED, 99));

    assert_eq!(disclosing(&lwd), Vec::<String>::new());
    assert_eq!(applied(&path, MAIN), before, "nothing raised the wallet");
    assert_eq!(queued(), queued_before, "queued work stays durable");
    assert_eq!(unchecked_history(), history_before);
}
