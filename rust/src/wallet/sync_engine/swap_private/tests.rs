//! Exercises the app worker against production filter encoding and encrypted PIR.
//! Payments are real Ironwood notes in a synthetic Mainnet chain that real app wallets
//! scan. Each test runs in its own process because the worker's admission and
//! cancellation state, and the app's feature settings, are process wide.
use super::*;
use std::collections::BTreeSet;
use zakura_one_time_ivk::Purpose;

/// Reruns the calling test alone in a child process and returns from it in this one (see
/// [`crate::wallet::db::isolated_test`]).
macro_rules! isolated {
    ($test:ident) => {
        if crate::wallet::db::isolated_test(module_path!(), stringify!($test)) {
            return;
        }
    };
}

mod fixture;
mod scenarios;
use fixture::*;

const RECEIVE: bool = true;

/// Runs near-head negative/positive hints and unavailable-history catch-up through the app worker.
#[test]
fn worker_filters_and_direct_catchup_use_real_pir() {
    isolated!(worker_filters_and_direct_catchup_use_real_pir);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let mut total_bytes = Vec::new();
    for mode in 0..4 {
        chain.mine(2);
        wallet.scan(&chain);
        let tip = chain.tip();
        // A deliberately overinclusive hint exercises the same path as a GCS false positive.
        let extra = if mode == 2 {
            vec![(tip, account.receiver(Purpose::Receive, 0))]
        } else {
            vec![]
        };
        let first = if mode == 3 { tip } else { activation() };
        let service = Service::publish(&chain, tip, first, tip, &extra);
        wallet.recover(&service).unwrap();
        let state = wallet.state(&account);
        assert!(state.restore_complete);
        assert!(state.lookups.is_empty());
        assert_eq!(service.queries(), [4, 0, 1, 4][mode], "mode {mode}");
        total_bytes.push(service.bytes());
        if mode == 3 {
            assert!(service.filter_requests().is_empty());
        }
    }
    assert!(total_bytes[1] < total_bytes[3]);
    println!(
        "receiver body bytes: initial={}, negative={}, positive={}, expired-history={}",
        total_bytes[0], total_bytes[1], total_bytes[2], total_bytes[3]
    );
}

/// Holds the filter download and then the PIR answer while ordinary sync scans more
/// than three further blocks each time. Sync never waits, discovery stays pending, and
/// releasing the answers credits the payment without another block or a manual action.
#[test]
fn held_filter_and_pir_responses_leave_ordinary_sync_running() {
    isolated!(held_filter_and_pir_responses_leave_ordinary_sync_running);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(wallet.state(&account).restore_complete);

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    wallet.scan(&chain);
    let published = chain.tip();
    let service = Service::publish(&chain, published, activation(), published, &[]);
    let filters = service.hold("filters", 0);
    let query = service.hold("query", 0);
    let worker = wallet.spawn(&service, None, Duration::from_secs(45));

    filters.wait();
    chain.mine(4);
    wallet.scan(&chain);
    assert_eq!(
        wallet.scanned(),
        published + 4,
        "ordinary sync committed four blocks"
    );
    assert!(!worker.is_finished());
    assert!(
        wallet.queued(&account).is_empty(),
        "no hint has been applied yet"
    );
    assert_eq!(wallet.one_time_unspent(&account), 0);
    filters.release();

    query.wait();
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 0)]));
    chain.mine(4);
    wallet.scan(&chain);
    assert_eq!(wallet.scanned(), published + 8);
    assert!(!worker.is_finished());
    assert_eq!(
        wallet.one_time_unspent(&account),
        0,
        "pending, not complete"
    );
    query.release();

    worker.join().unwrap().unwrap();
    let state = wallet.state(&account);
    // Paying I0 exposed I4. Its first lookup needs history through ordinary sync's
    // tip, which this publication has not reached, so it waits for the next one.
    assert!(state.witnesses.is_empty());
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 4)]));
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert_eq!(service.queries(), 1);
    assert_eq!(service.count("witness"), 1);
    service.report("held near-head hint, one paid lookup");
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(wallet.queued(&account).is_empty());
}

/// A short gap downloads filters and queries only the positive address. A long gap
/// queries unfinished addresses directly, skips a completed address and still answers a
/// queued positive for one. The settings action later finds the skipped repeat.
#[test]
fn route_choice_follows_measured_costs_and_skips_completed_addresses() {
    isolated!(route_choice_follows_measured_costs_and_skips_completed_addresses);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let receive = |index| account.key(Purpose::Receive, index);
    chain.mine(2);
    chain.pay(&receive(0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let restore = Service::at_tip(&chain);
    wallet.recover(&restore).unwrap();
    let state = wallet.state(&account);
    assert!(state.restore_complete);
    assert_eq!(state.restore_next, 5);
    assert_eq!(restore.queries(), 5);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    restore.report("seed restore: five lookups, one paid page and its proof");

    // Short gap: one block pays I2. Filters are cheaper and only the positive is queried.
    let frontier = chain.tip();
    chain.pay(&receive(2), 2_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let short = Service::at_tip(&chain);
    short.trace(&wallet, &account);
    wallet.recover(&short).unwrap();
    // Paying I2 moves the window to I6, so I5 and I6 get their first history checks.
    assert_eq!(
        short.traced(),
        [(RECEIVE, 2, 0), (RECEIVE, 5, 0), (RECEIVE, 6, 0)],
        "only the positive and newly exposed addresses are queried"
    );
    assert_eq!(
        short.filter_requests(),
        [format!("{}/1", frontier + 1), format!("{}/1", frontier + 2)]
    );
    assert_eq!(short.queries(), 3);
    assert_eq!(wallet.one_time_unspent(&account), 3_000_000);
    short.report("short gap, filter route: two filters, three lookups, one proof");

    // A live hint for completed I0 that PIR has not published yet stays queued.
    let repeat = chain.pay(&receive(0), 700_000, true);
    wallet.scan(&chain);
    let lagging = Service::publish(&chain, repeat - 1, activation(), repeat, &[]);
    wallet.recover(&lagging).unwrap();
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 0)]));
    assert_eq!(lagging.queries(), 0);
    assert_eq!(wallet.one_time_unspent(&account), 3_000_000);

    // Long offline gap: a repeat to completed I2 and a first payment to lookahead I3.
    // Neither is in the gap's first block, which the cost check samples and applies.
    chain.mine(10);
    chain.pay(&receive(2), 900_000, true);
    chain.pay(&receive(3), 400_000, true);
    chain.mine(6_000);
    wallet.scan(&chain);
    let direct_count = wallet.db().one_time_direct_query_count(account.id).unwrap();
    let long = Service::at_tip(&chain);
    long.trace(&wallet, &account);
    wallet.recover(&long).unwrap();
    // The queued I0 positive rereads its saved page 0 cursor, then reads the repeat on
    // page 1. Then unfinished I1, the I3..I6 lookahead, and I7, which I3's payment
    // exposed. Never completed I2.
    assert_eq!(
        long.traced(),
        [
            (RECEIVE, 0, 0),
            (RECEIVE, 0, 1),
            (RECEIVE, 1, 0),
            (RECEIVE, 3, 0),
            (RECEIVE, 4, 0),
            (RECEIVE, 5, 0),
            (RECEIVE, 6, 0),
            (RECEIVE, 7, 0),
        ]
    );
    assert_eq!(
        direct_count, 5,
        "I1 and I3 to I6 before I3's payment is known"
    );
    // Only the one-block sample was downloaded before the cost check chose direct queries.
    assert_eq!(long.filter_requests(), [format!("{}/1", repeat + 1)]);
    let sample = long
        .requests_of("filters")
        .first()
        .map(|(_, response)| *response)
        .unwrap();
    let gap = chain.tip() - repeat;
    let (setup, query) = direct_cost(long.inventory(), repeat).unwrap();
    assert!(!filters_cheaper(gap, sample, 0, direct_count, setup, query));
    assert_eq!(
        wallet.one_time_unspent(&account),
        3_000_000 + 700_000 + 400_000
    );
    assert_eq!(
        wallet.state(&account).skipped_through,
        Some(chain.tip().into())
    );
    let line = long.report("long gap, direct route");
    println!(
        "long gap of {gap} blocks: filter estimate {} bytes ({sample} per block), direct actual {}",
        u64::from(gap) * sample as u64,
        long.bytes()
    );
    assert!(line.contains("filters: 1 requests"));

    // The settings action reads completed addresses too and finds the skipped repeat.
    let manual = Service::at_tip(&chain);
    wallet
        .recover_with(&manual, Some(None), Duration::from_secs(45))
        .unwrap();
    assert_eq!(
        wallet.one_time_unspent(&account),
        3_000_000 + 700_000 + 400_000 + 900_000
    );
    assert!(!wallet.state(&account).manual.unwrap().active);
    manual.report("manual history check over every known address");
}

/// The seconds clock the app's quote calls use.
fn now() -> i64 {
    one_time_ivk::now().unwrap()
}

/// Builds, broadcasts and stores a proposal with the app's send path, against a
/// lightwalletd that reports `tip` and accepts the broadcast.
fn execute(wallet: &Wallet, account: &fixture::Account, proposal: u64, flow: &str, tip: u32) {
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let lwd = runtime.block_on(
        crate::wallet::sync_engine::test_lwd::CapturingLwd::start_for_broadcast(u64::from(tip)),
    );
    let result = runtime
        .block_on(crate::wallet::sync::execute_proposal(
            &wallet.path,
            &lwd.url,
            proposal,
            flow,
            account.seed(),
            None,
            None,
        ))
        .unwrap();
    assert_eq!(result.broadcasted_count, 1, "{:?}", result.message);
    assert_eq!(lwd.count("/SendTransaction"), 1);
}

/// A NEAR payout with two pages, a second receive and a small refund to a key learned
/// from the app's own funding memo are credited through the worker after page, proof
/// and spend checks, and the app's send path spends them. A second device restored from
/// the same seed learns the refund key through ordinary public enhancement of the
/// funding transaction and admits the same payments as already spent, so its balance
/// matches instead of resurrecting the spent notes.
#[test]
fn paid_receipts_are_credited_spent_and_not_resurrected_on_another_device() {
    isolated!(paid_receipts_are_credited_spent_and_not_resurrected_on_another_device);
    enable_feature();
    let mut chain = Chain::new();
    let mut phone = Wallet::new(4, activation());
    let account = phone.account().clone();
    chain.pay(&account.parent(), 21_000_000, false);
    chain.mine(12);
    phone.scan(&chain);
    phone.recover(&Service::at_tip(&chain)).unwrap();
    assert!(phone.state(&account).restore_complete);

    // The phone reserves a refund key, records the quote and funds the swap with the
    // refund memo through the app's FFI and send path.
    let reserved = crate::api::one_time_ivk::reserve_swap_address(
        phone.path.clone(),
        "main".into(),
        account.uuid.clone(),
        false,
        chain.tip().into(),
    )
    .unwrap();
    let refund = reserved.refund_index.unwrap();
    let deposit = zcash_keys::address::Address::Transparent(
        transparent::address::TransparentAddress::PublicKeyHash([23; 20]),
    )
    .encode(&NETWORK);
    crate::api::one_time_ivk::record_swap_refund_quote(
        phone.path.clone(),
        "main".into(),
        account.uuid.clone(),
        refund,
        deposit.clone(),
        now() + 3_600,
    )
    .unwrap();
    let funding = crate::wallet::sync::propose_send_with_swap_refund(
        &phone.path,
        NETWORK,
        &account.uuid,
        "fund",
        &deposit,
        20_000_000,
        refund,
    )
    .unwrap();
    execute(&phone, &account, funding.proposal_id, "fund", chain.tip());
    let (funding_tx, funding_raw) = phone.last_built();
    let funded_at = chain.mine_tx(&funding_tx);

    // NEAR pays receive I0 twice, receive I1 once and a small refund to the refund key.
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.pay(&account.key(Purpose::Receive, 0), 1_100_000, true);
    chain.pay(&account.key(Purpose::Receive, 1), 500_000, true);
    chain.pay(&account.key(Purpose::Refund, refund), 300_000, true);
    chain.mine(12);
    phone.scan(&chain);
    assert_eq!(
        phone.one_time_unspent(&account),
        0,
        "ordinary sync never credits them"
    );
    let before = phone.balance(&account);
    let service = Service::at_tip(&chain);
    phone.recover(&service).unwrap();
    let state = phone.state(&account);
    assert!(state.lookups.is_empty() && state.witnesses.is_empty());
    assert_eq!(phone.one_time_unspent(&account), 2_900_000);
    assert_eq!(phone.balance(&account), before + 2_900_000);
    let deltas: Vec<i64> = phone
        .history(&account)
        .iter()
        .map(|t| t.account_balance_delta)
        .collect();
    for value in [1_000_000, 1_100_000, 500_000, 300_000] {
        assert!(deltas.contains(&value), "history shows {value}: {deltas:?}");
    }
    service.report("paid recovery: two receive pages, one receive and one refund, with proofs");

    // The recovered notes are spendable through the app's ordinary send path.
    let ordinary = phone.balance(&account) - 2_900_000;
    let to = zcash_keys::address::Address::Unified(
        zcash_keys::address::UnifiedAddress::from_receivers(
            Some(
                orchard::keys::FullViewingKey::from(
                    &orchard::keys::SpendingKey::from_bytes([7; 32]).unwrap(),
                )
                .address_at(0u32, orchard::keys::Scope::External),
            ),
            None,
            None,
        )
        .unwrap(),
    )
    .encode(&NETWORK);
    // Send the maximum, which needs every recovered note including the 300,000
    // refund: the receive notes and ordinary funds alone fall short.
    let amount =
        crate::wallet::sync::estimate_send_max(&phone.path, NETWORK, &account.uuid, &to, None)
            .unwrap()
            .amount_zatoshi;
    assert!(amount > ordinary + 2_600_000, "max {amount}");
    let spend = crate::wallet::sync::propose_send(
        &phone.path,
        NETWORK,
        &account.uuid,
        "spend",
        &to,
        amount,
        None,
    )
    .unwrap();
    let before = phone.balance(&account);
    execute(&phone, &account, spend.proposal_id, "spend", chain.tip());
    let (spend_tx, _) = phone.last_built();
    chain.mine_tx(&spend_tx);
    chain.mine(3);
    phone.scan(&chain);
    assert_eq!(phone.one_time_unspent(&account), 0);
    let refund_receipts = phone.refund_receipts(&account);
    assert_eq!(refund_receipts.len(), 1);
    let (refund_nf, refund_spent) = refund_receipts[0];
    assert!(refund_spent, "the phone records its refund receipt spent");
    let revealed: Vec<[u8; 32]> = spend_tx
        .ironwood_bundle()
        .unwrap()
        .actions()
        .iter()
        .map(|action| action.nullifier().to_bytes())
        .collect();
    assert!(
        revealed.contains(&refund_nf),
        "the mined spend reveals the refund nullifier"
    );
    assert_eq!(phone.balance(&account), before - amount - spend.fee_zatoshi);
    assert!(phone
        .history(&account)
        .iter()
        .any(|t| t.account_balance_delta == -((amount + spend.fee_zatoshi) as i64)));

    // A second device restored from the seed scans the whole chain, including the
    // phone's spend, before it knows any one-time key.
    let final_service = Service::at_tip(&chain);
    let mut unenhanced = Wallet::new(4, activation());
    unenhanced.scan(&chain);
    unenhanced.recover(&final_service).unwrap();
    let account_without_memo = unenhanced.account().clone();
    assert_eq!(
        unenhanced.one_time_received(&account_without_memo),
        2_600_000,
        "without the funding memo the refund key stays unknown"
    );
    assert!(!unenhanced
        .queued(&account_without_memo)
        .contains(&(false, refund)));
    let mut desktop = Wallet::new(4, activation());
    let other = desktop.account().clone();
    desktop.scan(&chain);
    assert_eq!(desktop.one_time_received(&other), 0);
    let enhanced = enhance_publicly(&desktop, funding_tx.txid(), &funding_raw, funded_at, &chain);
    let final_service = Service::at_tip(&chain);
    desktop.recover(&final_service).unwrap();
    let state = desktop.state(&other);
    assert!(state.restore_complete && state.lookups.is_empty() && state.witnesses.is_empty());
    assert_eq!(state.restore_next, 6, "I0 and I1 paid, then four empties");
    assert_eq!(desktop.one_time_received(&other), 2_900_000);
    assert_eq!(
        desktop.one_time_unspent(&other),
        phone.one_time_unspent(&account),
        "spent receipts stay spent"
    );
    assert_eq!(desktop.balance(&other), phone.balance(&account));
    assert_eq!(
        desktop.refund_receipts(&other),
        [(refund_nf, true)],
        "the refund spent on the phone is recovered as spent"
    );
    let line = final_service
        .report("second-device restore: seed walk, memo-derived refund, pages and proofs");
    println!("receiver bytes enhancement: {enhanced} bytes of funding transaction for the refund memo; {line}");
}

/// Runs the app's public enhancement lane for `txid`, as ordinary sync does after
/// scanning, against a lightwalletd that serves the raw transaction. Returns the raw
/// transaction size the response carried.
fn enhance_publicly(
    wallet: &Wallet,
    txid: zcash_primitives::transaction::TxId,
    raw: &[u8],
    height: u32,
    chain: &Chain,
) -> usize {
    use super::super::enhancement::{EnhancementPolicy, EnhancementSession};
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let mut reversed = *txid.as_ref();
    reversed.reverse();
    let lwd = runtime.block_on(
        crate::wallet::sync_engine::test_lwd::CapturingLwd::start_serving(
            vec![
                (*txid.as_ref(), raw.to_vec(), u64::from(height)),
                (reversed, raw.to_vec(), u64::from(height)),
            ],
            u64::from(chain.tip()),
            |_| {},
        ),
    );
    let mut session = EnhancementSession::with_policy(
        NETWORK,
        &wallet.path,
        EnhancementPolicy::for_preference(NETWORK, false),
    );
    let mut db = wallet.db();
    let mut client = lwd.client.clone();
    runtime
        .block_on(session.run_payload_recovery(&mut db, &mut client, None, &|| false))
        .unwrap();
    assert!(lwd.count("/GetTransaction") >= 1);
    raw.len()
}

/// Turning the feature off while a lookup is in flight, or cancelling the worker as lock,
/// background, transport changes and wallet mutations do, rejects the held answer
/// without settling it as empty. Known funds stay, a paused round makes no request, and
/// the next round after re-enabling or restarting resumes the saved work.
#[test]
fn toggle_and_cancellation_reject_held_answers_and_resume() {
    isolated!(toggle_and_cancellation_reject_held_answers_and_resume);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let receive = |index| account.key(Purpose::Receive, index);
    chain.pay(&receive(0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);

    // Toggle off while I1's answer is held.
    chain.pay(&receive(1), 500_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("query", 0);
    let worker = wallet.spawn(&service, None, Duration::from_secs(45));
    held.wait();
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 1)]));
    crate::api::sync::set_near_swap_privacy_enabled(false);
    crate::api::one_time_ivk::reconcile_swap_recovery(wallet.path.clone(), "main".into()).unwrap();
    held.release();
    worker.join().unwrap().unwrap();
    assert!(!wallet.state(&account).enabled);
    assert_eq!(
        wallet.one_time_unspent(&account),
        1_000_000,
        "known funds remain"
    );
    assert!(wallet.balance(&account) >= 1_000_000);
    let paused = Service::at_tip(&chain);
    wallet.recover(&paused).unwrap();
    assert_eq!(
        paused.count("inventory"),
        0,
        "a paused feature makes no receiver request"
    );

    // Re-enabling resumes the saved obligation.
    enable_feature();
    crate::api::one_time_ivk::reconcile_swap_recovery(wallet.path.clone(), "main".into()).unwrap();
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_500_000);

    // Cancellation while I2's answer is held, as lock, background, transport changes
    // and wallet mutations request it.
    chain.pay(&receive(2), 700_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("query", 0);
    let worker = wallet.spawn(&service, None, Duration::from_secs(45));
    held.wait();
    cancel_recovery();
    held.release();
    let error = worker.join().unwrap().unwrap_err().to_string();
    assert!(error.contains("cancelled"), "{error}");
    assert_eq!(wallet.one_time_unspent(&account), 1_500_000);
    assert!(
        wallet.queued(&account).contains(&(RECEIVE, 2)),
        "the stale answer was not settled as empty"
    );
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 2_200_000);
}

/// Two software accounts share one filter download per range but keep their own
/// cursors, queues and time budgets. A held lookup that exhausts the first account's
/// budget leaves its work pending while the second account still finishes, and neither
/// account is credited with the other's payment.
#[test]
fn accounts_share_filter_downloads_but_not_cursors_budgets_or_credit() {
    isolated!(accounts_share_filter_downloads_but_not_cursors_budgets_or_credit);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let created = wallet.account().clone();
    let added = wallet.add_account(5, activation());
    // The worker visits software accounts in the wallet's account order.
    let order = one_time_ivk::software_accounts(&wallet.db()).unwrap();
    let (first, second) = if order[0] == created.id {
        (created, added)
    } else {
        (added, created)
    };
    assert_eq!(order, [first.id, second.id]);
    chain.mine(2);
    wallet.scan(&chain);
    let restore = Service::at_tip(&chain);
    wallet.recover(&restore).unwrap();
    assert_eq!(
        restore.queries(),
        8,
        "each account walks its own four empties"
    );
    assert_eq!(
        restore.count("public"),
        2,
        "payment and witness setup are shared"
    );
    assert!(wallet.state(&first).restore_complete && wallet.state(&second).restore_complete);

    let frontier = chain.tip();
    chain.pay(&first.key(Purpose::Receive, 0), 1_000_000, true);
    chain.pay(&second.key(Purpose::Receive, 0), 2_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    // The first account's lookup outlasts its slice of a nine second round.
    let held = service.hold("query", 0);
    let worker = wallet.spawn(&service, None, Duration::from_secs(9));
    held.wait();
    let error = worker.join().unwrap().unwrap_err().to_string();
    assert!(error.contains("pending"), "{error}");
    assert_eq!(
        service.filter_requests(),
        [format!("{}/1", frontier + 1), format!("{}/2", frontier + 2)],
        "both accounts matched the same downloaded filters"
    );
    for account in [&first, &second] {
        assert_eq!(
            wallet
                .state(account)
                .filter_frontier
                .map(|f| u32::from(f.height)),
            Some(chain.tip())
        );
    }
    assert_eq!(wallet.queued(&first), BTreeSet::from([(RECEIVE, 0)]));
    assert!(wallet.queued(&second).is_empty());
    assert_eq!(wallet.one_time_unspent(&first), 0);
    assert_eq!(wallet.one_time_unspent(&second), 2_000_000);
    held.release();

    let next = Service::at_tip(&chain);
    next.trace(&wallet, &first);
    wallet.recover(&next).unwrap();
    assert_eq!(
        next.traced(),
        [(RECEIVE, 0, 0), (RECEIVE, 4, 0)],
        "only the first account's pending lookup, then the address its payment exposed"
    );
    assert_eq!(next.queries(), 2, "the second account has nothing left");
    assert_eq!(wallet.one_time_unspent(&first), 1_000_000);
    assert_eq!(wallet.one_time_unspent(&second), 2_000_000);
}

/// Seed restore through the app worker crosses an unpaid hole, resets its empty count at
/// each authenticated payment and stops after four true empties. Issuance through the
/// app's FFI then recycles the hole and never derives past the payment-backed window.
#[test]
fn seed_restore_walks_holes_and_issuance_recycles_within_the_window() {
    isolated!(seed_restore_walks_holes_and_issuance_recycles_within_the_window);
    enable_feature();
    let mut chain = Chain::new();
    let seed = Wallet::new(4, activation()).account().clone();
    chain.pay(&seed.key(Purpose::Receive, 0), 1_000_000, true);
    chain.pay(&seed.key(Purpose::Receive, 2), 2_000_000, true);
    chain.pay(&seed.key(Purpose::Receive, 2), 300_000, true);
    chain.mine(12);
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.trace(&wallet, &account);
    wallet.recover(&service).unwrap();
    let state = wallet.state(&account);
    assert!(state.restore_complete);
    assert_eq!(
        state.restore_next, 7,
        "I0 paid, I1 empty, I2 paid, I3 to I6 empty"
    );
    assert_eq!(
        service.traced(),
        [
            (RECEIVE, 0, 0),
            (RECEIVE, 1, 0),
            (RECEIVE, 2, 0),
            (RECEIVE, 2, 1),
            (RECEIVE, 3, 0),
            (RECEIVE, 4, 0),
            (RECEIVE, 5, 0),
            (RECEIVE, 6, 0),
        ],
        "seven addresses, one query per page"
    );
    assert_eq!(wallet.one_time_unspent(&account), 3_300_000);
    service.report("seed restore across a hole: seven addresses, eight pages, three proofs");

    let reserve = || {
        crate::api::one_time_ivk::reserve_swap_address(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            true,
            chain.tip().into(),
        )
    };
    let begin = |index| {
        crate::api::one_time_ivk::begin_receive_quote(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            index,
            now() + 3_600,
        )
        .unwrap()
    };
    let finish = |request, accepted| {
        crate::api::one_time_ivk::finish_receive_quote(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            request,
            accepted,
        )
        .unwrap()
    };
    assert_eq!(
        reserve().unwrap().reservation_index,
        Some(1),
        "the hole is issued first"
    );
    // A definitively rejected quote releases the hole for reuse.
    finish(begin(1), None);
    assert_eq!(reserve().unwrap().reservation_index, Some(1));
    for expected in [1, 3, 4, 5, 6] {
        let index = reserve().unwrap().reservation_index.unwrap();
        assert_eq!(index, expected);
        let request = begin(index);
        finish(
            request.clone(),
            Some(crate::api::one_time_ivk::ReceiveDeposit {
                address: format!("deposit-{index}.near"),
                memo: None,
                deadline_seconds: now() + 3_600,
            }),
        );
        crate::api::one_time_ivk::start_receive_quote(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            request,
        )
        .unwrap();
    }
    let full = reserve().err().unwrap();
    assert!(
        full.message.contains("No swap address is free"),
        "{}",
        full.message
    );
}

/// The settings action searches past the four-empty stop up to an explicit bound, but an
/// unbounded check reads only known addresses. A pause keeps the cursor, the check
/// reports busy until it ends, and a later check resumes from the cursor.
#[test]
fn manual_history_check_honours_bounds_and_resumes_after_pause() {
    isolated!(manual_history_check_honours_bounds_and_resumes_after_pause);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let path = wallet.path.clone();
    let status =
        || crate::api::one_time_ivk::get_swap_recovery_status(path.clone(), "main".into()).unwrap();
    let checking = || status().checking_history;
    chain.pay(&account.key(Purpose::Receive, 9), 900_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.state(&account).restore_next, 4);
    assert_eq!(wallet.one_time_unspent(&account), 0);
    assert!(!checking());
    assert!(!status().manual_check_active);

    let known = Service::at_tip(&chain);
    wallet
        .recover_with(&known, Some(None), Duration::from_secs(45))
        .unwrap();
    assert_eq!(
        known.queries(),
        0,
        "known addresses were already checked through it"
    );
    assert_eq!(
        wallet.one_time_unspent(&account),
        0,
        "known addresses stop before I9"
    );
    assert!(!wallet.state(&account).manual.unwrap().active);

    // An explicit bound of ten addresses, paused on its third new lookup (I6).
    let bounded = Service::at_tip(&chain);
    let held = bounded.hold("query", 2);
    let worker = wallet.spawn(&bounded, Some(Some(10)), Duration::from_secs(45));
    held.wait();
    assert!(checking());
    assert!(
        status().manual_check_active,
        "the saved job is the user's check, which the app can offer to pause"
    );
    cancel_recovery();
    held.release();
    assert!(worker.join().unwrap().is_err());
    crate::api::one_time_ivk::cancel_swap_history(wallet.path.clone(), "main".into()).unwrap();
    let manual = wallet.state(&account).manual.unwrap();
    assert!(!manual.active);
    assert_eq!(manual.receive_end, 10);
    assert_eq!(
        manual.next, 6,
        "the cursor stays on the interrupted address"
    );
    assert!(!checking());
    assert!(!status().manual_check_active);

    let resumed = Service::at_tip(&chain);
    resumed.trace(&wallet, &account);
    wallet
        .recover_with(&resumed, Some(Some(10)), Duration::from_secs(45))
        .unwrap();
    let manual = wallet.state(&account).manual.unwrap();
    assert!(!manual.active);
    assert_eq!(
        resumed.traced(),
        [
            (RECEIVE, 6, 0),
            (RECEIVE, 7, 0),
            (RECEIVE, 8, 0),
            (RECEIVE, 9, 0),
            (RECEIVE, 10, 0),
            (RECEIVE, 11, 0),
            (RECEIVE, 12, 0),
            (RECEIVE, 13, 0),
        ],
        "I6 through I9, not again from I0 or I4, then the lookahead I9's payment exposed"
    );
    assert_eq!(wallet.one_time_unspent(&account), 900_000);
    assert!(!checking());
    resumed.report(
        "resumed manual check: four lookups, one paid page and its proof, then the new lookahead",
    );
}

/// An authenticated payment before the selected birthday advances the seed walk without
/// being credited. Vizor has no in-place birthday-lowering action. Its earlier-birthday
/// path is restoring the seed from that birthday, which credits the payment.
#[test]
fn prebirthday_payment_advances_restore_without_credit_until_an_earlier_restore() {
    isolated!(prebirthday_payment_advances_restore_without_credit_until_an_earlier_restore);
    enable_feature();
    let mut chain = Chain::new();
    let seed = Wallet::new(4, activation()).account().clone();
    chain.pay(&seed.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(12);
    let birthday = chain.tip() + 1;
    chain.mine(3);
    let mut late = Wallet::new(4, birthday);
    let account = late.account().clone();
    late.scan(&chain);
    let service = Service::at_tip(&chain);
    late.recover(&service).unwrap();
    let state = late.state(&account);
    assert!(state.restore_complete);
    assert_eq!(
        state.restore_next, 5,
        "the prebirthday payment counts as used"
    );
    assert_eq!(late.one_time_received(&account), 0, "but is not credited");

    let mut early = Wallet::new(4, activation());
    let account = early.account().clone();
    early.scan(&chain);
    early.recover(&service).unwrap();
    assert_eq!(early.one_time_unspent(&account), 1_000_000);
}

/// A service speaking a newer inventory protocol stops the round with an upgrade
/// outcome instead of deferring forever. The wallet keeps its pending work, the app
/// reports the update state, and a supported publication resumes and clears it.
#[test]
fn unsupported_service_requires_an_upgrade_and_keeps_pending_work() {
    isolated!(unsupported_service_requires_an_upgrade_and_keeps_pending_work);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let status = || {
        crate::api::one_time_ivk::get_swap_recovery_status(wallet.path.clone(), "main".into())
            .unwrap()
    };

    let newer = Service::at_tip(&chain);
    newer.serve_protocol("ironwood-receiver-inventory-v2");
    let error = wallet.recover(&newer).unwrap_err();
    assert!(matches!(error, RecoveryError::UpgradeRequired), "{error}");
    let error = crate::api::one_time_ivk::ReceiveError::from(error);
    assert_eq!(
        error.kind,
        crate::api::one_time_ivk::ReceiveErrorKind::UpgradeRequired
    );
    assert_eq!(newer.queries(), 0);
    assert_eq!(newer.count("chunk"), 0, "the head alone was refused");
    let state = wallet.state(&account);
    assert!(state.upgrade_required);
    assert!(state.lookups.is_empty(), "no work is exposed meanwhile");
    assert!(status().upgrade_required);
    assert!(
        wallet.queued(&account).contains(&(RECEIVE, 0)),
        "the pending seed walk is kept"
    );

    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!status().upgrade_required);
    assert!(wallet.state(&account).restore_complete);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// History before the recent tier lives in sealed shards with receiver filters. For a
/// restore's handful of addresses the filters cost less than reading each shard blind,
/// so only the address the filter matches reads the sealed shard, and the payment in it
/// is credited. The wallet keeps the verified descriptors for the next capture, and a
/// corrupted saved value only costs a full capture.
#[test]
fn sealed_shards_use_filters_and_inventory_descriptors_persist() {
    isolated!(sealed_shards_use_filters_and_inventory_descriptors_persist);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(2);
    let sealed = chain.tip();
    chain.mine(2);
    wallet.scan(&chain);
    let service = Service::publish_shards(
        &chain,
        &[sealed],
        chain.tip(),
        activation(),
        chain.tip(),
        &[],
    );
    assert!(shard_filters_cheaper(service.inventory(), 5));
    assert!(!shard_filters_cheaper(service.inventory(), 0));
    service.trace(&wallet, &account);
    wallet.recover(&service).unwrap();
    assert!(wallet.state(&account).restore_complete);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert_eq!(
        service.count("shard-filter"),
        1,
        "one filter serves every address"
    );
    // I0 matches the sealed shard's filter and reads both shards. I1 to I4 skip it.
    assert_eq!(
        service.traced(),
        [
            (RECEIVE, 0, 0),
            (RECEIVE, 0, 0),
            (RECEIVE, 1, 0),
            (RECEIVE, 2, 0),
            (RECEIVE, 3, 0),
            (RECEIVE, 4, 0),
        ]
    );
    service.report("sealed shard with filter, recent tier");

    let path = wallet.path.clone();
    let saved = || {
        rusqlite::Connection::open(&path)
            .unwrap()
            .query_row(
                "SELECT descriptors FROM ext_vizor_receiver_inventory WHERE id = 0",
                [],
                |r| r.get::<_, Vec<u8>>(0),
            )
            .unwrap()
    };
    assert!(!saved().is_empty(), "the verified descriptors were saved");
    rusqlite::Connection::open(&path)
        .unwrap()
        .execute(
            "UPDATE ext_vizor_receiver_inventory SET descriptors = x'00'",
            [],
        )
        .unwrap();
    chain.pay(&account.key(Purpose::Receive, 1), 500_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let next = Service::publish_shards(
        &chain,
        &[sealed],
        chain.tip(),
        activation(),
        chain.tip(),
        &[],
    );
    wallet.recover(&next).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_500_000);
    assert!(
        saved().len() > 1,
        "a full capture replaced the corrupted value"
    );
}

/// A round screens every account's due lookups against each sealed shard's filter
/// together, so each filter is traversed once per round rather than once per address.
#[test]
fn a_round_traverses_each_sealed_shard_filter_once() {
    isolated!(a_round_traverses_each_sealed_shard_filter_once);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    let first = chain.tip();
    chain.mine(2);
    let second = chain.tip();
    chain.mine(2);
    wallet.scan(&chain);
    let publish = |chain: &Chain| {
        Service::publish_shards(
            chain,
            &[first, second],
            chain.tip(),
            activation(),
            chain.tip(),
            &[],
        )
    };
    let restore = publish(&chain);
    let round = wallet.recover(&restore).unwrap();
    assert!(wallet.state(&account).restore_complete);
    // I0 to I3 skip both sealed shards and read only the recent tier.
    assert_eq!(restore.queries(), 4);
    assert_eq!(restore.count("shard-filter"), 2);
    assert_eq!(round.filter_traversals, 2, "one traversal per sealed shard");

    // With nothing due, the next round reads no filter.
    let idle = publish(&chain);
    let round = wallet.recover(&idle).unwrap();
    assert_eq!(idle.queries(), 0);
    assert_eq!(round.filter_traversals, 0);
}

/// A sealed shard's filter download that never answers costs each round one bounded
/// wait, not the round. Lookups read the sealed shards over PIR, the round requests no
/// filter again, and a restore longer than one round keeps progressing the same way.
#[test]
fn a_stalled_shard_filter_falls_back_to_pir_in_every_round() {
    isolated!(a_stalled_shard_filter_falls_back_to_pir_in_every_round);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    let mut sealed = Vec::new();
    for _ in 0..6 {
        chain.mine(2);
        sealed.push(chain.tip());
    }
    chain.mine(2);
    wallet.scan(&chain);
    let service =
        Service::publish_shards(&chain, &sealed, chain.tip(), activation(), chain.tip(), &[]);
    assert!(shard_filters_cheaper(service.inventory(), 1));
    // No filter download ever answers. PIR stays healthy.
    let _held: Vec<_> = (0..4).map(|n| service.hold("shard-filter", n)).collect();

    // Reading seven shards blind for each of five addresses outlasts one round's steps.
    let budget = Duration::from_secs(20);
    let mut rounds = 0;
    while !wallet.state(&account).restore_complete {
        rounds += 1;
        assert!(rounds <= 4, "the restore keeps progressing");
        wallet.recover_with(&service, None, budget).unwrap();
        assert!(
            service.count("shard-filter") <= rounds,
            "at most one stalled download per round"
        );
    }
    assert!(service.count("shard-filter") >= 2, "later rounds try again");
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// Sealed-shard filters that each download within the per-request timeout, but together
/// take longer than the round, share one filter budget. Past it the round reads the
/// remaining shards over PIR, so every round commits progress and the restore finishes.
#[test]
fn slow_shard_filters_share_one_budget_and_leave_time_for_pir() {
    isolated!(slow_shard_filters_share_one_budget_and_leave_time_for_pir);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    let mut sealed = Vec::new();
    for _ in 0..7 {
        chain.mine(2);
        sealed.push(chain.tip());
    }
    chain.mine(2);
    wallet.scan(&chain);
    let service =
        Service::publish_shards(&chain, &sealed, chain.tip(), activation(), chain.tip(), &[]);
    assert!(shard_filters_cheaper(service.inventory(), 1));
    // Every filter answers, each well inside the per-request timeout, but seven of them
    // take longer than the whole round.
    service.delay("shard-filter", Duration::from_secs(3));
    let budget = Duration::from_secs(20);

    let mut rounds = 0;
    while !wallet.state(&account).restore_complete {
        rounds += 1;
        assert!(rounds <= 6, "the restore keeps progressing");
        let before = (service.count("shard-filter"), service.queries());
        wallet.recover_with(&service, None, budget).unwrap();
        assert!(
            service.count("shard-filter") - before.0 <= 3,
            "filters stop once their budget is spent"
        );
        assert!(service.queries() > before.1, "every round reads PIR");
    }
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// Rolling block filters ahead of a lagging PIR publication that never answer draw on
/// the same round budget as sealed-shard filters. One stalled request ends filter work
/// for the round, so the other accounts skip theirs, and drain still runs in time to
/// credit a payment over direct PIR.
#[test]
fn stalled_rolling_filters_leave_every_account_time_to_drain() {
    isolated!(stalled_rolling_filters_leave_every_account_time_to_drain);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let first = wallet.account().clone();
    for seed in 5..11 {
        wallet.add_account(seed, activation());
    }
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(wallet.state(&first).restore_complete);

    chain.pay(&first.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    let published = chain.tip();
    chain.mine(2);
    wallet.scan(&chain);
    // PIR lags two blocks behind the rolling filters, whose requests never answer.
    let service = Service::publish(&chain, published, activation(), chain.tip(), &[]);
    let _held: Vec<_> = (0..16).map(|n| service.hold("filters", n)).collect();

    // Seven accounts waiting two seconds each would outlast this ten second round.
    wallet
        .recover_with(&service, None, Duration::from_secs(10))
        .unwrap();
    assert_eq!(
        service.count("filters"),
        1,
        "one stalled request ends filter work"
    );
    assert_eq!(wallet.one_time_unspent(&first), 1_000_000);
}

/// A history check against a publication the wallet has not scanned yet reports that
/// it is waiting for sync, a kind of its own the app can show honestly, rather than a
/// failure.
#[test]
fn a_history_check_ahead_of_sync_waits_for_sync() {
    isolated!(a_history_check_ahead_of_sync_waits_for_sync);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    chain.mine(2);
    wallet.scan(&chain);
    chain.mine(2);
    let error = wallet
        .recover_with(
            &Service::at_tip(&chain),
            Some(None),
            Duration::from_secs(45),
        )
        .unwrap_err();
    assert!(matches!(error, RecoveryError::NotCaughtUp), "{error}");
    let error = crate::api::one_time_ivk::ReceiveError::from(error);
    assert_eq!(
        error.kind,
        crate::api::one_time_ivk::ReceiveErrorKind::WaitingForSync
    );
}

/// A fresh wallet's birthday is the chain tip, so a service publishing a block or two
/// behind ends below any block the wallet stores. A history check reports that the
/// service is behind, not that sync is, while automatic rounds keep waiting. Once the
/// service publishes past the birthday, the check starts.
#[test]
fn a_history_check_behind_the_birthday_waits_for_the_service() {
    isolated!(a_history_check_behind_the_birthday_waits_for_the_service);
    enable_feature();
    let mut chain = Chain::new();
    chain.mine(3);
    let birthday = chain.tip() + 1;
    let mut wallet = Wallet::new(4, birthday);
    let account = wallet.account().clone();
    chain.mine(3);
    wallet.scan(&chain);
    let behind = Service::publish(&chain, birthday - 1, activation(), chain.tip(), &[]);
    assert!(wallet.recover(&behind).unwrap().active);
    let error = wallet
        .recover_with(&behind, Some(None), Duration::from_secs(45))
        .unwrap_err();
    assert!(matches!(error, RecoveryError::ReceiverBehind), "{error}");
    let error = crate::api::one_time_ivk::ReceiveError::from(error);
    assert_eq!(
        error.kind,
        crate::api::one_time_ivk::ReceiveErrorKind::WaitingForService
    );
    assert!(wallet.state(&account).manual.is_none());

    let caught_up = Service::publish(&chain, birthday, activation(), chain.tip(), &[]);
    wallet
        .recover_with(&caught_up, Some(None), Duration::from_secs(45))
        .unwrap();
    assert!(wallet.state(&account).manual.is_some());
}

/// A history check against a publication whose end block differs from the one the
/// wallet scanned at that height is a retryable failure, not a wait for either side.
#[test]
fn a_history_check_on_another_fork_fails_for_retry() {
    isolated!(a_history_check_on_another_fork_fails_for_retry);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    let mut fork = Chain::new();
    fork.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    fork.mine(1);
    assert_eq!(fork.tip(), chain.tip());
    let other = Service::at_tip(&fork);
    assert!(wallet.recover(&other).unwrap().active);
    let error = wallet
        .recover_with(&other, Some(None), Duration::from_secs(45))
        .unwrap_err();
    assert!(matches!(error, RecoveryError::Other(_)), "{error}");
    assert_eq!(
        crate::api::one_time_ivk::ReceiveError::from(error).kind,
        crate::api::one_time_ivk::ReceiveErrorKind::Other
    );
}

/// An account with ZIP 32 metadata but no Orchard key, as an unbackfilled hardware import
/// can be, is not a software account. Recovery, the status read and issuance keep working
/// for the wallet's other accounts, with the feature off and on.
#[test]
fn an_account_without_an_orchard_key_leaves_other_accounts_working() {
    isolated!(an_account_without_an_orchard_key_leaves_other_accounts_working);
    let mut chain = Chain::new();
    chain.mine(3);
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    // The birthday is one past activation, so the account starts from activation's tree.
    wallet.import_without_orchard(9, activation() + 1, &chain);
    assert_eq!(
        one_time_ivk::software_accounts(&wallet.db()).unwrap(),
        [account.id]
    );
    let path = wallet.path.clone();
    let status =
        || crate::api::one_time_ivk::get_swap_recovery_status(path.clone(), "main".into()).unwrap();

    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!status().checking_history);

    enable_feature();
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert!(!status().checking_history);
    let reserved = crate::api::one_time_ivk::reserve_swap_address(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        true,
        chain.tip().into(),
    )
    .map_err(|e| e.message)
    .unwrap();
    assert_eq!(reserved.reservation_index, Some(1));
}

/// With the feature off, a round on a wallet with nothing due only reads it: no write
/// lock, no receiver request, and no reported work, so the app can stop scheduling
/// rounds. An account still enabled from before the setting changed gets one round that
/// disables it.
#[test]
fn feature_off_rounds_without_work_take_no_lock_or_request() {
    isolated!(feature_off_rounds_without_work_take_no_lock_or_request);
    let mut chain = Chain::new();
    chain.mine(3);
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    wallet.add_account(5, activation());
    wallet.scan(&chain);

    // Another writer holds the wallet lock for the whole round.
    let off = Service::at_tip(&chain);
    let round = crate::wallet::db::with_wallet_db_write_lock("test.writer", || {
        let worker = wallet.spawn(&off, None, Duration::from_secs(45));
        let (done, result) = std::sync::mpsc::channel();
        std::thread::spawn(move || done.send(worker.join().unwrap()).unwrap());
        result.recv_timeout(Duration::from_secs(20))
    })
    .expect("the round waited for the wallet write lock")
    .unwrap();
    assert!(!round.active);
    assert_eq!(off.bytes(), 0, "no receiver request");
    assert!(
        !crate::api::one_time_ivk::run_swap_recovery(wallet.path.clone(), "main".into()).unwrap()
    );

    // An account left enabled is disabled by the next round, which then reports no work.
    enable_feature();
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(wallet.state(&account).enabled);
    crate::api::sync::set_near_swap_privacy_enabled(false);
    let disabling = Service::at_tip(&chain);
    assert!(!wallet.recover(&disabling).unwrap().active);
    assert!(!wallet.state(&account).enabled);
    assert_eq!(disabling.bytes(), 0);
}

/// With the feature off and nothing due, the production entry point returns before it
/// builds a Tokio runtime or an HTTPS client. So it also returns from inside a runtime,
/// where starting another one would panic.
#[test]
fn feature_off_idle_entry_point_builds_no_runtime() {
    isolated!(feature_off_idle_entry_point_builds_no_runtime);
    let mut chain = Chain::new();
    chain.mine(3);
    let mut wallet = Wallet::new(4, activation());
    wallet.scan(&chain);
    let path = wallet.path.clone();
    let had_work = tokio::runtime::Builder::new_current_thread()
        .build()
        .unwrap()
        .block_on(async move { crate::api::one_time_ivk::run_swap_recovery(path, "main".into()) })
        .unwrap();
    assert!(!had_work);
}

/// With the feature off, no app entry point commits to a wallet that never enabled it:
/// the round, the production entry point, the status read, reconciling the setting,
/// pausing a history check, and a provider status for an ordinary swap. So no recovery
/// rows exist, and ordinary scanning pays no per-account one-time work.
#[test]
fn feature_off_entry_points_leave_the_wallet_untouched() {
    isolated!(feature_off_entry_points_leave_the_wallet_untouched);
    use crate::api::one_time_ivk as api;
    let mut chain = Chain::new();
    chain.mine(3);
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    wallet.add_account(5, activation());
    wallet.scan(&chain);
    let path = wallet.path.clone();
    let main = || "main".to_string();
    // The first API call runs the app's migrations.
    api::get_swap_recovery_status(path.clone(), main()).unwrap();
    let watcher = rusqlite::Connection::open(&path).unwrap();
    let version = || {
        watcher
            .query_row("PRAGMA data_version", [], |r| r.get::<_, i64>(0))
            .unwrap()
    };
    let before = version();

    assert!(!wallet.recover(&Service::at_tip(&chain)).unwrap().active);
    assert!(!api::run_swap_recovery(path.clone(), main()).unwrap());
    api::get_swap_recovery_status(path.clone(), main()).unwrap();
    api::reconcile_swap_recovery(path.clone(), main()).unwrap();
    api::cancel_swap_history(path.clone(), main()).unwrap();
    // The wallet tracks no operation for an ordinary deposit address.
    let tracked = api::observe_swap_status(
        path.clone(),
        main(),
        account.uuid.clone(),
        RECEIVE,
        "ordinary-deposit.near".into(),
        None,
        api::SwapProviderStatus {
            status: "SUCCESS".into(),
            swap_type: None,
            refunded_amount: None,
            amount_out: Some("100000".into()),
            origin_tx_hashes: vec![],
            destination_tx_hashes: vec![],
        },
        true,
        now(),
    )
    .unwrap();
    assert!(!tracked);
    assert_eq!(version(), before, "an entry point committed a write");
    let rows: i64 = watcher
        .query_row("SELECT COUNT(*) FROM ironwood_one_time_recovery", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(rows, 0);

    chain.mine(2);
    wallet.scan(&chain);
    assert_eq!(wallet.scanned(), chain.tip());
}

/// The inventory descriptor cache writes nothing for a cancelled worker and never
/// recreates a wallet database that a reset deleted while a capture was in flight.
#[test]
fn descriptor_cache_never_recreates_a_reset_wallet() {
    isolated!(descriptor_cache_never_recreates_a_reset_wallet);
    let wallet = Wallet::new(4, activation());
    let store = DescriptorTable::new(&wallet.path, CANCEL.load(Ordering::SeqCst));
    store.save(b"first");
    assert_eq!(store.load().as_deref(), Some(&b"first"[..]));
    cancel_recovery();
    store.save(b"cancelled");
    assert_eq!(store.load().as_deref(), Some(&b"first"[..]));

    let current = DescriptorTable::new(&wallet.path, CANCEL.load(Ordering::SeqCst));
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", wallet.path));
    }
    current.save(b"after reset");
    assert_eq!(current.load(), None);
    assert!(!std::path::Path::new(&wallet.path).exists());
}
