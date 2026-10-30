//! Whole syncs through the real transparent PIR client against wallet-pir's
//! shard server in process, with lightwalletd stood in for by the
//! request-recording fake.
//!
//! Each test runs alone in a fresh process ([`isolated_test`]): it sets the
//! process-wide private-queries preference, as the app does at startup, so
//! the sync's own policy selection runs private recovery, and it points every
//! private service the sync could reach without a test seam at a closed
//! loopback port, so nothing leaves the machine.
//!
//! [`isolated_test`]: crate::wallet::db::isolated_test

use transparent::address::TransparentAddress;
use zakura_pir_client::transparent::testing::{filter, shard};

use super::pir::{assert_private, BIRTHDAY, TOP};
use super::qualification::disclosing;
use super::shard_service::{noise, receive, script, spend, ShardService, ShardSpec, RECEIVED};
use super::*;
use crate::wallet::sync::{get_transaction_history, TransparentBalanceAuthority};
use crate::wallet::sync_engine::test_lwd::CapturingLwd;

use super::super::pir::test_transport;

const MAIN: WalletNetwork = WalletNetwork::Main;

/// A mainnet software wallet scanned from [`BIRTHDAY`] through [`TOP`], and
/// its account's first external transparent address.
struct Funded {
    _dir: tempfile::TempDir,
    path: String,
    uuid: String,
    address: TransparentAddress,
}

fn funded_wallet() -> Funded {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(&path, MAIN, &seed, Some(u64::from(BIRTHDAY)), "tpir")
            .unwrap();
    scan(&path, BIRTHDAY, BIRTHDAY, TOP, 0);
    let address =
        keys::software_account_first_external_transparent_receiver(MAIN, &seed, 0).unwrap();
    Funded {
        _dir: dir,
        path,
        uuid,
        address,
    }
}

/// The process as the app sets it up with private queries on, read from
/// storage; every private service without a test seam is a closed port.
fn private_process() {
    preference(true, true);
}

/// The process as the app sets it up: private queries `enabled`, and whether
/// that value was `confirmed` read from storage, through the setters the app
/// calls; every private service without a test seam is a closed port.
fn preference(enabled: bool, confirmed: bool) {
    crate::api::sync::set_enhance_pir_enabled(enabled);
    crate::api::sync::set_enhance_pir_preference_confirmed(confirmed);
    for name in [
        "VIZOR_ENHANCE_PIR_URL",
        "VIZOR_STATUS_PIR_URL",
        "VIZOR_TRANSPARENT_PIR_URL",
    ] {
        std::env::set_var(name, "https://127.0.0.1:1");
    }
}

/// Runs one whole sync of the wallet at `path` against `lwd`.
fn sync(path: &str, lwd: &CapturingLwd) -> Result<(), String> {
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let url = lwd.url.clone();
    runtime.block_on(crate::wallet::sync_engine::run_sync_inner(
        path,
        &url,
        MAIN,
        Arc::new(AtomicBool::new(false)),
        1,
        &std::sync::atomic::AtomicU8::new(1),
        None,
        false,
        |_| {},
    ))
}

/// Whole syncs a recovery needs at most in these tests: each sync makes one
/// recovery pass per account, so a window that grows waits for the next.
const SYNCS: usize = 4;

/// Runs [`SYNCS`] whole syncs of the wallet at `path` against `lwd`, as
/// successive blocks would, and returns the last one's result. Recovery runs
/// once per block, and `lwd`'s tip does not move, so each sync after the
/// first stands in for a new block.
fn syncs(path: &str, lwd: &CapturingLwd) -> Result<(), String> {
    let mut result = Ok(());
    for _ in 0..SYNCS {
        super::super::clear_recovery_tip(path);
        result = sync(path, lwd);
    }
    result
}

/// The address's public key hash: what no request may carry.
fn secret(address: &TransparentAddress) -> Vec<u8> {
    match address {
        TransparentAddress::PublicKeyHash(hash) => hash.to_vec(),
        TransparentAddress::ScriptHash(hash) => hash.to_vec(),
    }
}

/// Two receives and a spend of the first, across two sealed shards and a
/// live tail that ends at `tail_end`, at `tail_revision`, superseding
/// `supersedes` when it is not the first.
fn publication(
    address: TransparentAddress,
    tail_end: u64,
    tail_revision: u32,
    supersedes: String,
) -> Vec<ShardSpec> {
    let birthday = u64::from(BIRTHDAY);
    let mut first = noise(birthday - 100, birthday + 3, 1);
    first.push((script(address), receive(birthday + 2, 1)));
    let mut second = noise(birthday + 4, birthday + 6, 2);
    second.push((script(address), receive(birthday + 5, 2)));
    let mut tail = noise(birthday + 7, tail_end, 3);
    if tail_end >= birthday + 8 {
        tail.push((script(address), spend(birthday + 8, 3, 1)));
    }
    vec![
        ShardSpec::first(birthday - 100, birthday + 3, true, first),
        ShardSpec::first(birthday + 4, birthday + 6, true, second),
        ShardSpec {
            revision: tail_revision,
            supersedes,
            ..ShardSpec::first(birthday + 7, tail_end, false, tail)
        },
    ]
}

/// A whole private sync recovers the account's transparent funds through the
/// real transparent PIR client and wallet-pir's shard server: two receives in
/// sealed shards and a spend of one in the live tail. While the publication
/// stops short of the wallet's tip the balance is not current; once it
/// reaches the tip the balance is current and exact, and history holds the
/// recovered receives. Lightwalletd sees no transparent address or txid, and
/// no request to the service carries the account's address.
#[test]
fn a_whole_private_sync_recovers_funds_through_the_real_service() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "a_whole_private_sync_recovers_funds_through_the_real_service",
    ) {
        return;
    }
    private_process();
    let wallet = funded_wallet();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let lwd = runtime.block_on(CapturingLwd::start_at_tip(u64::from(TOP), main_hash(TOP).0));
    crate::api::sync::reconcile_transparent_policy(wallet.path.clone(), "main".into(), true)
        .expect("raise the wallet to private recovery");

    // The service lags the wallet by two blocks: nothing it says is current.
    let behind = ShardService::publish(&publication(
        wallet.address,
        u64::from(TOP) - 2,
        0,
        String::new(),
    ));
    let seam = test_transport::set(&wallet.path, behind.observer());
    let lagging = sync(&wallet.path, &lwd);
    let balance = get_wallet_balance(&wallet.path, MAIN, &wallet.uuid).unwrap();
    assert_ne!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current,
        "a publication short of the tip is not current: {balance:?} ({lagging:?})"
    );
    assert_eq!(balance.transparent, 0, "nothing is spendable yet");
    let mut requests = seam.seam.observer.requests();
    drop(seam);

    // The tail's next revision reaches the tip.
    let caught_up = ShardService::publish(&publication(
        wallet.address,
        u64::from(TOP),
        1,
        behind.digest(2),
    ));
    let seam = test_transport::set(&wallet.path, caught_up.observer());
    // The lagging service asked the wallet to wait; that delay passes.
    super::super::clear_holds(&wallet.path);
    syncs(&wallet.path, &lwd).expect("whole syncs complete");
    let balance = get_wallet_balance(&wallet.path, MAIN, &wallet.uuid).unwrap();
    assert_eq!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current,
        "{balance:?}"
    );
    assert_eq!(balance.transparent, RECEIVED, "one receive is spent");
    assert_eq!(balance.transparent_last_known, None);

    let history = get_transaction_history(&wallet.path, MAIN, None, &wallet.uuid).unwrap();
    let received: Vec<_> = history
        .iter()
        .filter(|row| row.tx_kind == "received")
        .map(|row| row.display_amount)
        .collect();
    assert_eq!(
        received,
        vec![RECEIVED, RECEIVED],
        "{:?}",
        history
            .iter()
            .map(|row| (&row.tx_kind, row.display_amount))
            .collect::<Vec<_>>()
    );

    requests.extend(seam.seam.observer.requests());
    assert!(
        requests
            .iter()
            .any(|request| request.method == "POST" && !request.body.is_empty()),
        "the account's pages were retrieved by private queries"
    );
    assert_private(&requests, &[secret(&wallet.address)]);
    assert_eq!(disclosing(&lwd), Vec::<String>::new());
}

/// The wallet's durable transparent ledger mode.
fn durable_mode(path: &str) -> Option<TransparentLedgerMode> {
    super::super::current_transparent_policy(path, MAIN)
        .unwrap()
        .map(|applied| applied.mode)
}

/// Private queries on, but the preference behind it could not be read from
/// storage (assumed private): the sync withholds every public transparent
/// lookup, yet never raises the wallet's durable policy. Only a confirmed
/// preference may (`may_raise`).
#[test]
fn an_unconfirmed_preference_withholds_public_lookups_without_raising_the_wallet() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "an_unconfirmed_preference_withholds_public_lookups_without_raising_the_wallet",
    ) {
        return;
    }
    preference(true, false);
    let wallet = funded_wallet();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let lwd = runtime.block_on(CapturingLwd::start_at_tip(u64::from(TOP), main_hash(TOP).0));
    let service = ShardService::publish(&publication(
        wallet.address,
        u64::from(TOP),
        0,
        String::new(),
    ));
    let seam = test_transport::set(&wallet.path, service.observer());
    let before = durable_mode(&wallet.path);
    assert_ne!(before, Some(TransparentLedgerMode::PrivateRequired));

    let _ = sync(&wallet.path, &lwd);

    assert_eq!(
        durable_mode(&wallet.path),
        before,
        "the policy was not raised"
    );
    assert_eq!(disclosing(&lwd), Vec::<String>::new());
    assert_private(&seam.seam.observer.requests(), &[secret(&wallet.address)]);
}

/// Turning private queries off lowers a wallet that required private
/// recovery to public, through the production toggle; the next sync never
/// contacts the transparent PIR service.
#[test]
fn turning_private_queries_off_lowers_the_wallet_and_stops_private_recovery() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "turning_private_queries_off_lowers_the_wallet_and_stops_private_recovery",
    ) {
        return;
    }
    preference(true, true);
    let wallet = funded_wallet();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let lwd = runtime.block_on(CapturingLwd::start_at_tip(u64::from(TOP), main_hash(TOP).0));
    crate::api::sync::reconcile_transparent_policy(wallet.path.clone(), "main".into(), true)
        .expect("raise the wallet to private recovery");
    assert_eq!(
        durable_mode(&wallet.path),
        Some(TransparentLedgerMode::PrivateRequired)
    );

    // The settings toggle: the preference first, then the wallet.
    crate::api::sync::set_enhance_pir_enabled(false);
    let lowered =
        crate::api::sync::reconcile_transparent_policy(wallet.path.clone(), "main".into(), false)
            .expect("lower the wallet to public")
            .expect("a wallet exists");
    assert_eq!(
        lowered.mode,
        crate::api::sync::ApiTransparentLedgerMode::Public
    );
    let service = ShardService::publish(&publication(
        wallet.address,
        u64::from(TOP),
        0,
        String::new(),
    ));
    let seam = test_transport::set(&wallet.path, service.observer());

    let _ = sync(&wallet.path, &lwd);

    assert_eq!(
        durable_mode(&wallet.path),
        Some(TransparentLedgerMode::Public)
    );
    assert_eq!(
        seam.seam.observer.requests(),
        Vec::new(),
        "a public wallet never contacts the transparent PIR service"
    );
}

/// What a private sync against a misbehaving service must leave: no current
/// transparent balance and nothing spendable, the stop reason `stop`, no
/// public transparent lookup, and no request to the service carrying the
/// account's address.
fn assert_unrecovered(
    wallet: &Funded,
    lwd: &CapturingLwd,
    requests: &[crate::wallet::sync_engine::enhancement::ObservedRequest],
    stop: Option<crate::wallet::sync::TransparentStopReason>,
) {
    let balance = get_wallet_balance(&wallet.path, MAIN, &wallet.uuid).unwrap();
    assert_ne!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current,
        "{balance:?}"
    );
    assert_eq!(balance.transparent, 0, "nothing is spendable: {balance:?}");
    assert_eq!(balance.transparent_stop, stop, "{balance:?}");
    assert_eq!(disclosing(lwd), Vec::<String>::new());
    assert_private(requests, &[secret(&wallet.address)]);
}

/// A private wallet, its fake lightwalletd at the wallet's tip, and the
/// publication that recovers its funds when nothing misbehaves.
fn private_wallet() -> (Funded, CapturingLwd, tokio::runtime::Runtime) {
    private_process();
    let wallet = funded_wallet();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let lwd = runtime.block_on(CapturingLwd::start_at_tip(u64::from(TOP), main_hash(TOP).0));
    crate::api::sync::reconcile_transparent_policy(wallet.path.clone(), "main".into(), true)
        .expect("raise the wallet to private recovery");
    (wallet, lwd, runtime)
}

/// Syncs the private wallet once against the real publication with each
/// reply passed through `tamper`, and checks that it was not recovered and
/// stopped for `stop`. `tampered` must report that a reply was rewritten.
fn misbehaving(
    tamper: impl Fn(
            &crate::wallet::sync_engine::enhancement::ObservedRequest,
            &mut http::response::Parts,
            &mut Vec<u8>,
        ) + Send
        + Sync
        + 'static,
    tampered: &AtomicBool,
    stop: Option<crate::wallet::sync::TransparentStopReason>,
) {
    let (wallet, lwd, _runtime) = private_wallet();
    let service = ShardService::publish(&publication(
        wallet.address,
        u64::from(TOP),
        0,
        String::new(),
    ));
    let seam = test_transport::set(&wallet.path, service.observer_with(tamper));
    let _ = sync(&wallet.path, &lwd);
    assert!(tampered.load(Ordering::SeqCst), "the fault was injected");
    assert_unrecovered(&wallet, &lwd, &seam.seam.observer.requests(), stop);
}

/// Replaces `from` with `to` in `body`, and records that it did.
fn replace(body: &mut Vec<u8>, from: &[u8], to: &[u8], tampered: &AtomicBool) {
    if let Some(at) = body.windows(from.len()).position(|window| window == from) {
        body.splice(at..at + from.len(), to.iter().copied());
        tampered.store(true, Ordering::SeqCst);
    }
}

static TAMPERED: AtomicBool = AtomicBool::new(false);

/// A shard map naming another chain is refused before any shard is read.
#[test]
fn a_shard_map_of_another_chain_recovers_nothing() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "a_shard_map_of_another_chain_recovers_nothing",
    ) {
        return;
    }
    misbehaving(
        |request, _, body| {
            if request.path == "/transparent/v1/filters/shards" {
                replace(
                    body,
                    filter::MAINNET_GENESIS_DISPLAY.as_bytes(),
                    "11".repeat(32).as_bytes(),
                    &TAMPERED,
                );
            }
        },
        &TAMPERED,
        None,
    );
}

/// A service on another schema is refused.
#[test]
fn a_service_on_another_schema_recovers_nothing() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "a_service_on_another_schema_recovers_nothing",
    ) {
        return;
    }
    misbehaving(
        |request, _, body| {
            if request.path == "/transparent/v1/shards/init" {
                replace(
                    body,
                    shard::manifest::SCHEMA.as_bytes(),
                    b"transparent-shard-v99",
                    &TAMPERED,
                );
            }
        },
        &TAMPERED,
        None,
    );
}

/// A truncated private query reply is not applied. (The account's few events
/// are inline in its directory rows, so no page is ever queried here.)
#[test]
fn a_malformed_query_reply_recovers_nothing() {
    if crate::wallet::db::isolated_test(module_path!(), "a_malformed_query_reply_recovers_nothing")
    {
        return;
    }
    misbehaving(
        |request, _, body| {
            if request.method == "POST" && request.path.ends_with("/query/directory") {
                body.truncate(body.len() / 2);
                TAMPERED.store(true, Ordering::SeqCst);
            }
        },
        &TAMPERED,
        None,
    );
}

/// A service that rate-limits every private query (429 with Retry-After)
/// leaves the balance unrecovered, and nothing falls back to public lookups.
#[test]
fn a_rate_limited_service_recovers_nothing() {
    if crate::wallet::db::isolated_test(module_path!(), "a_rate_limited_service_recovers_nothing") {
        return;
    }
    misbehaving(
        |request, parts, body| {
            if request.method == "POST" {
                parts.status = http::StatusCode::TOO_MANY_REQUESTS;
                parts.headers.insert(
                    http::header::RETRY_AFTER,
                    http::HeaderValue::from_static("30"),
                );
                body.clear();
                TAMPERED.store(true, Ordering::SeqCst);
            }
        },
        &TAMPERED,
        None,
    );
}

/// A publication whose sealed shard ends on a block the wallet does not hold
/// (a reorg across a finished shard) is not applied.
#[test]
fn a_sealed_shard_on_another_branch_recovers_nothing() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "a_sealed_shard_on_another_branch_recovers_nothing",
    ) {
        return;
    }
    let (wallet, lwd, _runtime) = private_wallet();
    // Shard 0 ends at BIRTHDAY + 3, on the other branch from BIRTHDAY + 1.
    let service = ShardService::publish_forked(
        &publication(wallet.address, u64::from(TOP), 0, String::new()),
        u64::from(BIRTHDAY) + 1,
    );
    let seam = test_transport::set(&wallet.path, service.observer());
    let _ = sync(&wallet.path, &lwd);
    assert_unrecovered(&wallet, &lwd, &seam.seam.observer.requests(), None);
}

/// A sealed shard the wallet recovered from, republished with other content
/// and no re-cut declared, withdraws the wallet's private authority.
#[test]
fn an_undeclared_rewrite_of_a_sealed_shard_withdraws_recovery() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "an_undeclared_rewrite_of_a_sealed_shard_withdraws_recovery",
    ) {
        return;
    }
    let (wallet, lwd, runtime) = private_wallet();
    let first = ShardService::publish(&publication(
        wallet.address,
        u64::from(TOP),
        0,
        String::new(),
    ));
    let seam = test_transport::set(&wallet.path, first.observer());
    syncs(&wallet.path, &lwd).expect("whole syncs complete");
    assert_eq!(
        get_wallet_balance(&wallet.path, MAIN, &wallet.uuid)
            .unwrap()
            .transparent_authority,
        TransparentBalanceAuthority::Current
    );
    let mut requests = seam.seam.observer.requests();
    drop(seam);

    // The chain moves on three blocks, so the next sync has a range to
    // recover. Sealed shard 1 gains an event it did not have, under the same
    // id and revision, and the tail extends to the new tip.
    let tip = TOP + 3;
    scan(&wallet.path, BIRTHDAY, TOP + 1, tip, 0);
    let later = runtime.block_on(CapturingLwd::start_at_tip(u64::from(tip), main_hash(tip).0));
    let mut rewritten = publication(wallet.address, u64::from(tip), 1, first.digest(2));
    rewritten[1]
        .events
        .extend(noise(u64::from(BIRTHDAY) + 4, u64::from(BIRTHDAY) + 6, 9));
    let second = ShardService::publish(&rewritten);
    assert_ne!(second.digest(1), first.digest(1));
    let seam = test_transport::set(&wallet.path, second.observer());
    let _ = syncs(&wallet.path, &later);
    requests.extend(seam.seam.observer.requests());
    assert_eq!(disclosing(&lwd), Vec::<String>::new());
    assert_unrecovered(
        &wallet,
        &later,
        &requests,
        Some(crate::wallet::sync::TransparentStopReason::Withdrawn),
    );
}

/// A publisher that re-cuts sealed history the wallet recovered from, and
/// declares it, keeps the wallet's funds and history: the two sealed shards
/// are merged into one wider shard, the tail is renumbered, and the next pass
/// over the re-cut map (the chain has moved on) leaves the balance current
/// and exact, the history unchanged, and no stop reason.
#[test]
fn a_declared_re_cut_of_sealed_history_keeps_the_wallet_current() {
    if crate::wallet::db::isolated_test(
        module_path!(),
        "a_declared_re_cut_of_sealed_history_keeps_the_wallet_current",
    ) {
        return;
    }
    let (wallet, lwd, runtime) = private_wallet();
    let first = ShardService::publish(&publication(
        wallet.address,
        u64::from(TOP),
        0,
        String::new(),
    ));
    let seam = test_transport::set(&wallet.path, first.observer());
    syncs(&wallet.path, &lwd).expect("whole syncs complete");
    let received = |path: &str| -> Vec<u64> {
        get_transaction_history(path, MAIN, None, &wallet.uuid)
            .unwrap()
            .into_iter()
            .filter(|row| row.tx_kind == "received")
            .map(|row| row.display_amount)
            .collect()
    };
    let before = received(&wallet.path);
    assert_eq!(before, vec![RECEIVED, RECEIVED]);
    let mut requests = seam.seam.observer.requests();
    drop(seam);

    // The chain moves on three blocks. The re-cut merges sealed shards 0
    // and 1 into one, from the first shard's start, and the tail, now shard
    // 1, extends to the new tip.
    let tip = TOP + 3;
    scan(&wallet.path, BIRTHDAY, TOP + 1, tip, 0);
    let later = runtime.block_on(CapturingLwd::start_at_tip(u64::from(tip), main_hash(tip).0));
    let [shard0, shard1, tail]: [ShardSpec; 3] =
        publication(wallet.address, u64::from(tip), 0, String::new())
            .try_into()
            .ok()
            .unwrap();
    // A re-cut shard that keeps its geometry is a new revision of what it
    // replaces, as is the renumbered tail.
    let mut merged_events = shard0.events;
    merged_events.extend(shard1.events);
    let merged = ShardSpec {
        revision: 1,
        supersedes: first.digest(0),
        ..ShardSpec::first(shard0.start, shard1.end, true, merged_events)
    };
    let tail = ShardSpec {
        revision: 1,
        supersedes: first.digest(2),
        ..tail
    };
    let recut = ShardService::publish_recut(&[merged, tail], &first, shard0.start);
    let seam = test_transport::set(&wallet.path, recut.observer());
    syncs(&wallet.path, &later).expect("whole syncs over the re-cut map complete");
    requests.extend(seam.seam.observer.requests());

    let balance = get_wallet_balance(&wallet.path, MAIN, &wallet.uuid).unwrap();
    assert_eq!(
        balance.transparent_authority,
        TransparentBalanceAuthority::Current,
        "{balance:?}"
    );
    assert_eq!(balance.transparent, RECEIVED, "{balance:?}");
    assert_eq!(balance.transparent_stop, None, "{balance:?}");
    assert_eq!(received(&wallet.path), before);
    assert_private(&requests, &[secret(&wallet.address)]);
    assert_eq!(disclosing(&lwd), Vec::<String>::new());
    assert_eq!(disclosing(&later), Vec::<String>::new());
}
