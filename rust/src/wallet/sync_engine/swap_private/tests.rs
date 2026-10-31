//! Exercises the app worker against production filter encoding and encrypted PIR.
//! Payments are real Ironwood notes in a synthetic Mainnet chain that real app wallets
//! scan. Each test runs in its own process because the worker's admission and
//! cancellation state, and the app's feature settings, are process wide.
use super::*;
use std::collections::BTreeSet;
use zakura_one_time_ivk::Purpose;
use zcash_protocol::memo::MemoBytes;

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
    let worker = wallet.spawn(&service, false, Duration::from_secs(45));

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
    // Paying I0 exposed I4. Its bootstrap lookup reaches the wallet's scanned tip, past
    // this publication, so the next one runs it.
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 4)]));
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert_eq!(
        service.queries(),
        2,
        "a directory query, then the record and its proof"
    );
    service.report("held near-head hint, one paid lookup");
    let next = Service::at_tip(&chain);
    wallet.recover(&next).unwrap();
    assert!(wallet.queued(&account).is_empty());
    assert_eq!(next.queries(), 1);
}

/// A short gap downloads one filter range from the marker and queries only the positive
/// address. A long gap inside the filter window does the same, and finds a repeat payment
/// to a paid address and a first payment to a lookahead one. The settings action finds
/// nothing more.
#[test]
fn filters_continue_the_marker_and_find_repeat_payments() {
    isolated!(filters_continue_the_marker_and_find_repeat_payments);
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
    assert_eq!(
        restore.queries(),
        6,
        "five directory queries and I0's record"
    );
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    restore.report("seed restore: five lookups, one paid record and its proof");

    // Short gap: one block pays I2. Only the positive is queried.
    let frontier = chain.tip();
    chain.pay(&receive(2), 2_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let short = Service::at_tip(&chain);
    short.trace(&wallet, &account);
    let round = wallet.recover(&short).unwrap();
    assert!(!round.more);
    assert_eq!(
        short.traced(),
        [
            (RECEIVE, 2, None),
            (RECEIVE, 2, Some(0)),
            (RECEIVE, 5, None),
            (RECEIVE, 6, None)
        ],
        "the positive, then the bootstrap of each address its payment exposed"
    );
    assert_eq!(short.filter_requests(), [format!("{}/2", frontier + 1)]);
    assert_eq!(wallet.one_time_unspent(&account), 3_000_000);
    short.report("short gap, filter route: one range, one lookup, one proof");

    // A live hint for completed I0 that PIR has not published yet stays queued.
    let repeat = chain.pay(&receive(0), 700_000, true);
    wallet.scan(&chain);
    let lagging = Service::publish(&chain, repeat - 1, activation(), repeat, &[]);
    wallet.recover(&lagging).unwrap();
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 0)]));
    assert_eq!(lagging.queries(), 0);
    assert_eq!(wallet.one_time_unspent(&account), 3_000_000);

    // Long offline gap inside the filter window: a repeat to paid I2 and a first payment
    // to lookahead I3. One range finds both.
    chain.mine(10);
    chain.pay(&receive(2), 900_000, true);
    chain.pay(&receive(3), 400_000, true);
    chain.mine(6_000);
    wallet.scan(&chain);
    let long = Service::at_tip(&chain);
    wallet.recover(&long).unwrap();
    assert_eq!(
        wallet.one_time_unspent(&account),
        3_000_000 + 700_000 + 400_000 + 900_000
    );
    assert_eq!(
        wallet
            .state(&account)
            .filter_frontier
            .map(|f| u32::from(f.height)),
        Some(chain.tip())
    );
    long.report("long gap, filter route");

    // The settings action reads every known address again and finds nothing new.
    let manual = Service::at_tip(&chain);
    wallet
        .recover_with(&manual, true, Duration::from_secs(45))
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

/// A swap deposit the app funded and the chain mined.
struct Funding {
    tx: zcash_primitives::transaction::Transaction,
    raw: Vec<u8>,
    height: u32,
    refund: u64,
    fee: u64,
}

/// Funds a NEAR swap of `amount` to a transparent deposit address made from `deposit`,
/// as the app does. It estimates the fee, reserves a refund key, records the quote,
/// proposes with the refund memo, then builds, broadcasts and mines the transaction.
/// The estimate must equal the fee the proposal pays.
fn fund(
    wallet: &Wallet,
    account: &fixture::Account,
    chain: &mut Chain,
    deposit: u8,
    amount: u64,
) -> Funding {
    let deposit = zcash_keys::address::Address::Transparent(
        transparent::address::TransparentAddress::PublicKeyHash([deposit; 20]),
    )
    .encode(&NETWORK);
    let estimate = crate::wallet::sync::estimate_fee_with_swap_refund(
        &wallet.path,
        NETWORK,
        &account.uuid,
        &deposit,
        amount,
    )
    .unwrap();
    // A round first reads the account's history, as the app's would.
    wallet.recover(&Service::at_tip(chain)).unwrap();
    let reserved = crate::api::one_time_ivk::reserve_swap_address(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        false,
        chain.tip().into(),
    )
    .unwrap();
    let refund = reserved.refund_index.unwrap();
    crate::api::one_time_ivk::record_swap_refund_quote(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        refund,
        deposit.clone(),
        now() + 3_600,
    )
    .unwrap();
    let flow = format!("fund-{deposit}");
    let proposal = crate::wallet::sync::propose_send_with_swap_refund(
        &wallet.path,
        NETWORK,
        &account.uuid,
        &flow,
        &deposit,
        amount,
        refund,
    )
    .unwrap();
    assert_eq!(
        estimate, proposal.fee_zatoshi,
        "the estimate is the fee paid"
    );
    execute(wallet, account, proposal.proposal_id, &flow, chain.tip());
    let (tx, raw) = wallet.last_built();
    let height = chain.mine_tx(&tx);
    Funding {
        tx,
        raw,
        height,
        refund,
        fee: proposal.fee_zatoshi,
    }
}

/// The value and memo of each change output of `funding` that `wallet` decrypts with its
/// internal keys, read from the mined transaction itself.
fn change_outputs(wallet: &Wallet, funding: &Funding) -> Vec<(u64, MemoBytes)> {
    use zcash_client_backend::data_api::WalletRead as _;
    let ufvks = wallet.db().get_unified_full_viewing_keys().unwrap();
    zcash_client_backend::decrypt_transaction(
        &NETWORK,
        Some(funding.height.into()),
        None,
        &funding.tx,
        &ufvks,
    )
    .ironwood_outputs()
    .iter()
    .filter(|output| output.transfer_type() == zcash_client_backend::TransferType::AccountInternal)
    .map(|output| (output.note().0.value().inner(), output.memo().clone()))
    .collect()
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
    let funding = fund(&phone, &account, &mut chain, 23, 20_000_000);
    let refund = funding.refund;

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
    // Finding the payments widened the receive window, and a chained round reads the
    // new addresses' lookups.
    phone.recover(&service).unwrap();
    let state = phone.state(&account);
    assert!(state.lookups.is_empty());
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
    let enhanced = enhance_publicly(
        &desktop,
        funding.tx.txid(),
        &funding.raw,
        funding.height,
        &chain,
    );
    // The memo's refund key ends the fresh state, so filters walk all history and the
    // lookups their hits queue run over the following rounds.
    let final_service = Service::at_tip(&chain);
    desktop.settle(&final_service, 4);
    let state = desktop.state(&other);
    assert!(state.restore_complete && state.lookups.is_empty());
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

/// Private swap funding manages change like an ordinary send. A wallet with the four
/// Ironwood notes a real wallet had funds three small deposits, each from one note with
/// one change output, and keeps four notes.
#[test]
fn private_funding_keeps_the_note_count_of_an_ordinary_send() {
    isolated!(private_funding_keeps_the_note_count_of_an_ordinary_send);
    enable_feature();
    let mut chain = Chain::new();
    let mut phone = Wallet::new(4, activation());
    let account = phone.account().clone();
    for value in [128_520_000, 128_480_000, 128_450_000, 78_491_250] {
        chain.pay(&account.parent(), value, false);
    }
    chain.mine(12);
    phone.scan(&chain);
    phone.recover(&Service::at_tip(&chain)).unwrap();

    for deposit in 0..3 {
        let before = phone.notes(&account);
        let funding = fund(&phone, &account, &mut chain, 30 + deposit, 800_000);
        chain.mine(12);
        phone.scan(&chain);
        let after = phone.notes(&account);
        let change = change_outputs(&phone, &funding);
        let spent = before.len() + change.len() - after.len();
        assert_eq!(
            (spent, change.len(), after.len()),
            (1, 1, 4),
            "deposit {deposit}: one input, one change, four notes left; {before:?} -> {after:?}"
        );
        assert_eq!(funding.fee, 15_000);
        assert_eq!(
            before.iter().sum::<u64>() - after.iter().sum::<u64>(),
            800_000 + funding.fee
        );
    }
}

/// A deposit from a wallet with one note splits its change toward four notes, as an
/// ordinary send does, and every change output carries the refund memo. Values and the
/// higher fee of four outputs balance, and the estimate matches. The phone and a second
/// device restored from the seed each register the refund key once and credit a refund
/// paid to it once.
#[test]
fn split_private_funding_repeats_the_refund_memo_and_recovers_it_once() {
    isolated!(split_private_funding_repeats_the_refund_memo_and_recovers_it_once);
    enable_feature();
    let mut chain = Chain::new();
    let mut phone = Wallet::new(4, activation());
    let account = phone.account().clone();
    chain.pay(&account.parent(), 128_500_000, false);
    chain.mine(12);
    phone.scan(&chain);
    phone.recover(&Service::at_tip(&chain)).unwrap();

    // `fund` checks the estimate against the proposal, and the proposal succeeds only
    // after `verify_refund_funding_proposal` accepts it.
    let funding = fund(&phone, &account, &mut chain, 40, 800_000);
    let memo =
        MemoBytes::from_bytes(&zakura_one_time_ivk::swap::RefundMemo::new(funding.refund).encode())
            .unwrap();
    let change = change_outputs(&phone, &funding);
    assert_eq!(change.len(), 4, "{change:?}");
    assert!(change
        .iter()
        .all(|(value, m)| *m == memo && *value >= 10_000_000));
    // One spend and four outputs pad to four Ironwood actions, plus the deposit.
    assert_eq!(funding.fee, 25_000);
    assert_eq!(
        change.iter().map(|(value, _)| value).sum::<u64>() + 800_000 + funding.fee,
        128_500_000
    );
    chain.mine(12);
    phone.scan(&chain);
    assert_eq!(phone.notes(&account).len(), 4);

    chain.pay(&account.key(Purpose::Refund, funding.refund), 300_000, true);
    chain.mine(12);
    phone.scan(&chain);
    phone.recover(&Service::at_tip(&chain)).unwrap();
    // Only the funded refund index is registered. Nothing is prepared ahead.
    assert_eq!(
        phone.refund_keys(&account),
        [(funding.refund, Some(funding.height))]
    );
    assert_eq!(phone.refund_receipts(&account).len(), 1);
    assert_eq!(phone.one_time_unspent(&account), 300_000);

    let mut desktop = Wallet::new(4, activation());
    let other = desktop.account().clone();
    desktop.scan(&chain);
    enhance_publicly(
        &desktop,
        funding.tx.txid(),
        &funding.raw,
        funding.height,
        &chain,
    );
    assert_eq!(desktop.notes_with_memo(&other, &memo), 4);
    desktop.recover(&Service::at_tip(&chain)).unwrap();
    let state = desktop.state(&other);
    assert!(state.restore_complete && state.lookups.is_empty());
    assert_eq!(
        desktop.refund_keys(&other),
        [(funding.refund, Some(funding.height))]
    );
    assert_eq!(desktop.refund_receipts(&other).len(), 1);
    assert_eq!(desktop.one_time_received(&other), 300_000);
    assert_eq!(desktop.balance(&other), phone.balance(&account));
}

/// Turning NEAR swap privacy off while a lookup is in flight leaves discovery running, so
/// the held answer is still credited. Cancelling the worker, as lock, background,
/// transport changes and wallet mutations do, rejects the held answer without settling
/// it as empty, and the next round resumes the saved work.
#[test]
fn toggle_keeps_held_answers_and_cancellation_rejects_them() {
    isolated!(toggle_keeps_held_answers_and_cancellation_rejects_them);
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
    let worker = wallet.spawn(&service, false, Duration::from_secs(45));
    held.wait();
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 1)]));
    crate::api::sync::set_near_swap_privacy_enabled(false);
    held.release();
    worker.join().unwrap().unwrap();
    assert!(wallet.state(&account).enabled);
    assert_eq!(wallet.one_time_unspent(&account), 1_500_000);

    // Cancellation while I2's answer is held, as lock, background, transport changes
    // and wallet mutations request it.
    chain.pay(&receive(2), 700_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("query", 0);
    let worker = wallet.spawn(&service, false, Duration::from_secs(45));
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
fn accounts_share_a_filter_range_but_not_cursors_budgets_or_credit() {
    isolated!(accounts_share_a_filter_range_but_not_cursors_budgets_or_credit);
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
    assert_eq!(restore.count("public"), 1, "the directory setup is shared");
    assert!(wallet.state(&first).restore_complete && wallet.state(&second).restore_complete);

    let frontier = chain.tip();
    chain.pay(&first.key(Purpose::Receive, 0), 1_000_000, true);
    chain.pay(&second.key(Purpose::Receive, 0), 2_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    // The first account's lookup stalls, and so does its second attempt.
    service.stall("query", 0);
    service.stall("query", 1);
    let error = wallet
        .recover_with(&service, false, Duration::from_secs(9))
        .unwrap_err()
        .to_string();
    assert!(error.contains("stalled"), "{error}");
    assert_eq!(
        service.filter_requests(),
        [format!("{}/3", frontier + 1)],
        "both accounts matched the same downloaded range"
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

    wallet.retry_now();
    let next = Service::at_tip(&chain);
    next.trace(&wallet, &first);
    wallet.recover(&next).unwrap();
    // Then the bootstrap of the address its payment exposed.
    assert_eq!(
        next.traced(),
        [
            (RECEIVE, 0, None),
            (RECEIVE, 0, Some(0)),
            (RECEIVE, 4, None)
        ],
        "only the first account's pending lookup"
    );
    assert_eq!(next.queries(), 3, "the second account has nothing left");
    assert_eq!(wallet.one_time_unspent(&first), 1_000_000);
    assert_eq!(wallet.one_time_unspent(&second), 2_000_000);
}

/// The active account's work goes first in a round, so a stall there holds back no other
/// account, and it is the active account's lookup that stays pending.
#[test]
fn the_active_accounts_work_goes_first() {
    isolated!(the_active_accounts_work_goes_first);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let created = wallet.account().clone();
    let added = wallet.add_account(5, activation());
    let order = one_time_ivk::software_accounts(&wallet.db()).unwrap();
    let (first, second) = if order[0] == created.id {
        (created, added)
    } else {
        (added, created)
    };
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    chain.pay(&first.key(Purpose::Receive, 0), 1_000_000, true);
    chain.pay(&second.key(Purpose::Receive, 0), 2_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    // The first lookup sent, and its second attempt, stall. The active second account
    // sends it.
    service.stall("query", 0);
    service.stall("query", 1);
    assert!(wallet
        .recover_active(&service, &second, Duration::from_secs(9))
        .is_err());
    assert_eq!(wallet.queued(&second), BTreeSet::from([(RECEIVE, 0)]));
    assert!(wallet.queued(&first).is_empty());
    assert_eq!(wallet.one_time_unspent(&first), 1_000_000);
    assert_eq!(wallet.one_time_unspent(&second), 0);
}

/// A round that stops at its step limit with due work left reports more, and the one
/// that finishes the work doesn't. A lookup the service refused waits out its retry
/// delay, which the next round reports instead of running it.
#[test]
fn rounds_report_runnable_work_and_why_the_rest_waits() {
    isolated!(rounds_report_runnable_work_and_why_the_rest_waits);
    let mut chain = Chain::new();
    let seed = Wallet::new(4, activation()).account().clone();
    // Seven paid addresses and four empties take eleven lookups, which one round runs
    // while its time lasts.
    for index in 0..7 {
        chain.pay(&seed.key(Purpose::Receive, index), 100_000, true);
    }
    chain.mine(2);
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    wallet.scan(&chain);
    let first = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(first.changed && !first.more && first.wait.is_none());
    assert!(wallet.state(&account).restore_complete);
    assert_eq!(wallet.one_time_unspent(&account), 700_000);

    chain.pay(&account.key(Purpose::Receive, 7), 500_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let refusing = Service::at_tip(&chain);
    refusing.fail("query", 0, || session::Error::Transport("HTTP 503".into()));
    assert!(wallet.recover(&refusing).is_err());
    let deferred = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!deferred.more);
    assert_eq!(deferred.wait, Some(Wait::Backoff));
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 7)]));
}

/// A lookup still arriving when its account's slice and the whole round are up finishes
/// and is recorded, and so do filters still arriving past the filter budget. Budgets
/// only stop new requests.
#[test]
fn transfers_still_arriving_finish_past_the_round_budgets() {
    isolated!(transfers_still_arriving_finish_past_the_round_budgets);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    // A quiet block that one filter covers without any PIR query. The filter takes
    // longer than the round's whole filter budget.
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.delay("filters", Duration::from_millis(1500));
    wallet
        .recover_with(&service, false, Duration::from_secs(3))
        .unwrap();
    assert_eq!(service.count("filters"), 1);
    assert_eq!(service.queries(), 0, "no direct queries replaced it");

    // A lookup step that takes longer than the whole round finishes and is recorded.
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.delay("query", Duration::from_secs(2));
    let round = wallet
        .recover_with(&service, false, Duration::from_secs(1))
        .unwrap();
    assert!(round.more && round.changed);
    assert_eq!(service.queries(), 2, "I0's directory query and record");
    assert!(!wallet.queued(&account).contains(&(RECEIVE, 0)));
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// No lookup step starts once the round's time is up. One already started reads every
/// record it needs and is recorded, and the rest waits for the next round without a retry
/// delay.
#[test]
fn no_step_starts_after_the_round_deadline() {
    isolated!(no_step_starts_after_the_round_deadline);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    // Two payments to one address take two records.
    let paid = account.key(Purpose::Receive, 0);
    chain.pay(&paid, 1_000_000, true);
    chain.pay(&paid, 500_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.delay("query", Duration::from_millis(1500));
    let round = wallet
        .recover_with(&service, false, Duration::from_secs(1))
        .unwrap();
    assert!(round.more);
    assert_eq!(service.queries(), 3, "I0's step, and not I4's bootstrap");

    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_500_000);
}

/// Filter work that runs past the whole round leaves lookups and witnesses no time, so the
/// next round skips filters and they get their turn, and the round after that downloads
/// filters again.
#[test]
fn filters_that_overran_a_round_wait_for_lookups() {
    isolated!(filters_that_overran_a_round_wait_for_lookups);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    // I0's payment is found, but its lookup is refused and waits.
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let refusing = Service::at_tip(&chain);
    refusing.fail("query", 0, || session::Error::Transport("HTTP 503".into()));
    assert!(wallet.recover(&refusing).is_err());
    wallet.retry_now();

    // Every range now takes longer than a whole round.
    chain.mine(1);
    wallet.scan(&chain);
    let slow = Service::at_tip(&chain);
    slow.delay("filters", Duration::from_secs(4));
    let budget = Duration::from_secs(3);
    let overran = wallet.recover_with(&slow, false, budget).unwrap();
    assert!(overran.more);
    assert_eq!((slow.count("filters"), slow.queries()), (1, 0));

    let skipped = wallet.recover_with(&slow, false, budget).unwrap();
    assert_eq!(slow.count("filters"), 1, "no filters this round");
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert!(skipped.more, "the filter gap is still open");

    chain.mine(1);
    wallet.scan(&chain);
    let next = Service::at_tip(&chain);
    wallet.recover_with(&next, false, budget).unwrap();
    assert_eq!(next.count("filters"), 1, "filters run again");
}

/// An account with no filter marker, as after a correction, takes a complete check
/// instead of reading filters from activation, even with activation inside the filter
/// window and a birthday near the tip below which the wallet has no blocks to check a
/// range against. The check moves the marker to the publication's end.
#[test]
fn an_account_without_a_marker_takes_a_complete_check() {
    isolated!(an_account_without_a_marker_takes_a_complete_check);
    let mut chain = Chain::new();
    chain.mine(1_300);
    let birthday = chain.tip() - 5;
    let mut wallet = Wallet::new(4, birthday);
    let account = wallet.account().clone();
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    wallet.clear_marker(&account);
    chain.mine(3);
    wallet.scan(&chain);

    let service = Service::at_tip(&chain);
    let round = wallet.recover(&service).unwrap();
    assert_eq!((round.more, round.wait), (false, None));
    assert!(
        service.filter_requests().is_empty(),
        "no range from activation"
    );
    assert_eq!(service.queries(), 4, "one lookup per watched address");
    assert_eq!(frontier(&wallet, &account), Some(chain.tip()));
}

/// A slow head request that fails past the round's deadline still makes the next round
/// skip filters, so a pending lookup runs.
#[test]
fn a_slow_failing_filter_head_still_yields_the_next_round() {
    isolated!(a_slow_failing_filter_head_still_yields_the_next_round);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let refusing = Service::at_tip(&chain);
    refusing.fail("query", 0, || session::Error::Transport("HTTP 503".into()));
    assert!(wallet.recover(&refusing).is_err());
    wallet.retry_now();

    let slow = Service::at_tip(&chain);
    slow.delay("head", Duration::from_secs(4));
    for n in 0..2 {
        slow.fail("head", n, || session::Error::Transport("HTTP 503".into()));
    }
    let budget = Duration::from_secs(3);
    let _ = wallet.recover_with(&slow, false, budget);
    assert_eq!(wallet.one_time_unspent(&account), 0, "no time was left");
    let _ = wallet.recover_with(&slow, false, budget);
    assert_eq!(slow.count("head"), 1, "the next round skipped filters");
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// A filter step reads one range per marker and commits each for the accounts at that
/// marker, so accounts at different markers don't owe a round.
#[test]
fn a_filter_step_reads_a_range_per_marker() {
    isolated!(a_filter_step_reads_a_range_per_marker);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let first = wallet.account().clone();
    let second = wallet.add_account(5, activation());
    chain.mine(2);
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    let behind = chain.tip();
    chain.mine(3);
    wallet.scan(&chain);
    assert!(!wallet.step(&Service::at_tip(&chain)).unwrap().needs_round);
    let ahead = chain.tip();
    wallet.set_marker(&second, &chain, behind);
    chain.mine(2);
    wallet.scan(&chain);

    let service = Service::at_tip(&chain);
    assert!(!wallet.step(&service).unwrap().needs_round);
    assert_eq!(
        service.filter_requests(),
        [
            format!("{}/{}", behind + 1, chain.tip() - behind),
            format!("{}/2", ahead + 1)
        ]
    );
    assert_eq!(frontier(&wallet, &second), Some(chain.tip()));
    assert_eq!(frontier(&wallet, &first), Some(chain.tip()));
}

/// The end of `account`'s filter coverage, if it has one.
fn frontier(wallet: &Wallet, account: &Account) -> Option<u32> {
    wallet
        .state(account)
        .filter_frontier
        .map(|f| u32::from(f.height))
}

/// An address a payment exposes gets one bootstrap lookup over the history filters
/// already passed, which finds a payment to it there. Later rounds only move filters
/// forward and never re-check that history.
#[test]
fn an_exposed_address_is_bootstrapped_once_and_never_rechecked() {
    isolated!(an_exposed_address_is_bootstrapped_once_and_never_rechecked);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    // I4 is paid before I0 exposes it, so filters can't match it.
    chain.pay(&account.key(Purpose::Receive, 4), 400_000, true);
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.trace(&wallet, &account);
    wallet.recover(&service).unwrap();
    assert_eq!(
        service.traced(),
        [
            (RECEIVE, 0, None),
            (RECEIVE, 0, Some(0)),
            (RECEIVE, 4, None),
            (RECEIVE, 4, Some(0)),
            (RECEIVE, 5, None),
            (RECEIVE, 6, None),
            (RECEIVE, 7, None),
            (RECEIVE, 8, None),
        ],
        "I0's hit, then one bootstrap for each address the payments exposed"
    );
    assert_eq!(wallet.one_time_unspent(&account), 1_400_000);

    let frontier = chain.tip();
    chain.mine(1);
    wallet.scan(&chain);
    let quiet = Service::at_tip(&chain);
    wallet.recover(&quiet).unwrap();
    assert_eq!(quiet.queries(), 0);
    assert_eq!(quiet.filter_requests(), [format!("{}/1", frontier + 1)]);
}

/// A reorg moves the account's marker back to the fork, so the next round reads filters
/// on the new branch from there and finds a payment only that branch mined.
#[test]
fn a_reorg_moves_the_marker_back_and_filters_read_the_new_branch() {
    isolated!(a_reorg_moves_the_marker_back_and_filters_read_the_new_branch);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(10);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(frontier(&wallet, &account), Some(chain.tip()));

    let fork = chain.tip() - 3;
    chain.rewind(fork);
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(4);
    assert!(wallet.sync(&chain).unwrap().is_some());
    let marker = frontier(&wallet, &account).unwrap();
    assert!(marker <= fork, "the marker moved back to the fork");

    let service = Service::at_tip(&chain);
    wallet.recover(&service).unwrap();
    assert_eq!(
        service.filter_requests(),
        [format!("{}/{}", marker + 1, chain.tip() - marker)]
    );
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert_eq!(frontier(&wallet, &account), Some(chain.tip()));
}

/// An account whose frontier is below the receiver's filter window takes a complete
/// check, while the other account still takes filters from its own frontier inside it.
#[test]
fn an_account_below_the_window_leaves_the_other_on_filters() {
    isolated!(an_account_below_the_window_leaves_the_other_on_filters);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let low = wallet.account().clone();
    let high = wallet.add_account(5, activation());
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let start = chain.tip();
    wallet.clear_marker(&low);

    chain.pay(&low.key(Purpose::Receive, 1), 500_000, true);
    chain.pay(&high.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::publish(&chain, chain.tip(), start + 1, chain.tip(), &[]);
    wallet.recover(&service).unwrap();
    assert_eq!(
        service.filter_requests(),
        [format!("{}/{}", start + 1, chain.tip() - start)],
        "one range from the frontier inside the window"
    );
    assert_eq!(wallet.one_time_unspent(&low), 500_000);
    assert_eq!(wallet.one_time_unspent(&high), 1_000_000);
    for account in [&low, &high] {
        assert_eq!(frontier(&wallet, account), Some(chain.tip()));
    }
}

/// An offline gap that starts below the receiver's filter window takes a complete check
/// with no filter download, which finds the payment in it.
#[test]
fn a_gap_beyond_the_window_takes_a_complete_check() {
    isolated!(a_gap_beyond_the_window_takes_a_complete_check);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let start = chain.tip();

    chain.pay(&account.key(Purpose::Receive, 1), 500_000, true);
    chain.mine(5);
    wallet.scan(&chain);
    let service = Service::publish(&chain, chain.tip(), start + 2, chain.tip(), &[]);
    wallet.recover(&service).unwrap();
    assert!(service.filter_requests().is_empty());
    assert_eq!(
        service.queries(),
        7,
        "I0 to I3 and I1's record, then the bootstraps of I4 and I5, which it exposed"
    );
    assert_eq!(wallet.one_time_unspent(&account), 500_000);
    assert_eq!(frontier(&wallet, &account), Some(chain.tip()));
}

/// A range the service ends early leaves the rest for the next round, which continues
/// from the account's marker, so chained rounds reach the tip within the window.
#[test]
fn short_ranges_continue_from_the_marker_in_chained_rounds() {
    isolated!(short_ranges_continue_from_the_marker_in_chained_rounds);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let start = chain.tip() + 1;

    chain.mine(20);
    chain.pay(&account.key(Purpose::Receive, 1), 500_000, true);
    chain.mine(9);
    wallet.scan(&chain);
    let service = Service::publish(&chain, chain.tip(), start, chain.tip(), &[]);
    service.cap_ranges(10);
    assert!(
        wallet.recover(&service).unwrap().more,
        "the range ended early"
    );
    wallet.settle(&service, 4);
    let froms: Vec<u32> = service
        .filter_requests()
        .iter()
        .map(|r| r.split('/').next().unwrap().parse().unwrap())
        .collect();
    assert_eq!(froms, [start, start + 10, start + 20]);
    assert_eq!(wallet.one_time_unspent(&account), 500_000);
    assert_eq!(frontier(&wallet, &account), Some(chain.tip()));
}

/// A filter step reads the head and one range, with no inventory or lookup. Its hit
/// queues a lookup, which makes a round due, and the round runs the lookup without
/// downloading the range again.
#[test]
fn a_filter_step_hit_leads_to_a_round_that_runs_the_lookup() {
    isolated!(a_filter_step_hit_leads_to_a_round_that_runs_the_lookup);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let path = wallet.path.clone();
    let due = || {
        crate::api::one_time_ivk::get_swap_recovery_status(path.clone(), "main".into())
            .unwrap()
            .round_due
    };

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    assert!(!due());
    let service = Service::at_tip(&chain);
    assert!(!wallet.step(&service).unwrap().needs_round);
    assert_eq!(
        ["inventory", "head", "filters", "query"].map(|c| service.count(c)),
        [0, 1, 1, 0]
    );
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 0)]));
    assert!(due(), "the hit owes a round");
    assert_eq!(frontier(&wallet, &account), Some(chain.tip()));

    let round = Service::at_tip(&chain);
    wallet.recover(&round).unwrap();
    assert!(round.filter_requests().is_empty());
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// A filter step owes a round when one range doesn't reach the scanned tip, when the
/// head serves another history revision, when an account's frontier is just below the
/// window, and when a range disagrees with the wallet's chain. Inside the window it
/// covers the rest and owes nothing.
#[test]
fn a_filter_step_owes_a_round_for_what_one_range_cannot_cover() {
    isolated!(a_filter_step_owes_a_round_for_what_one_range_cannot_cover);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let start = chain.tip() + 1;
    chain.mine(3);
    wallet.scan(&chain);

    let capped = Service::at_tip(&chain);
    capped.cap_ranges(1);
    assert!(wallet.step(&capped).unwrap().needs_round);
    assert_eq!(capped.filter_requests(), [format!("{start}/3")]);
    assert_eq!(frontier(&wallet, &account), Some(start));

    let revised = Service::at_tip(&chain);
    revised.serve_revision(1);
    assert!(wallet.step(&revised).unwrap().needs_round);
    assert!(revised.filter_requests().is_empty());

    let late = Service::publish(&chain, chain.tip(), start + 2, chain.tip(), &[]);
    assert!(wallet.step(&late).unwrap().needs_round);
    assert!(late.filter_requests().is_empty());

    let inside = Service::at_tip(&chain);
    assert!(!wallet.step(&inside).unwrap().needs_round);
    assert_eq!(inside.filter_requests(), [format!("{}/2", start + 1)]);
    assert_eq!(frontier(&wallet, &account), Some(chain.tip()));

    // The range ends at the scanned tip, below the head's.
    let covered = chain.tip();
    chain.mine(1);
    wallet.scan(&chain);
    chain.mine(1);
    let forked = Service::at_tip(&chain);
    forked.fork_filters_through(covered + 1);
    assert!(wallet.step(&forked).unwrap().needs_round);
    assert_eq!(frontier(&wallet, &account), Some(covered));
}
/// A filter step and a round share one admission through the app's entry points. A step
/// held on its first request makes a round refuse, and a held round makes a step refuse.
/// Admission is released after a step succeeds, is cancelled or fails on the wallet.
#[test]
fn a_filter_step_and_a_round_share_one_admission() {
    isolated!(a_filter_step_and_a_round_share_one_admission);
    enable_feature();
    let mut chain = Chain::new();
    chain.mine(2);
    let mut wallet = Wallet::new(4, activation());
    wallet.scan(&chain);
    let path = wallet.path.clone();
    let runtime = || {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
    };
    let admitted = || RUNNING.load(Ordering::SeqCst);
    // Without a server a step succeeds at once.
    assert!(
        !runtime()
            .block_on(filter_step(&path, NETWORK))
            .unwrap()
            .needs_round
    );
    assert!(!admitted());

    // A service that accepts connections and never answers holds every request.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let origin = format!("https://{}", listener.local_addr().unwrap());
    std::env::set_var("VIZOR_RECEIVER_PIR_URL", origin);
    let (arrived, connected) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut held = Vec::new();
        for stream in listener.incoming() {
            held.push(stream);
            let _ = arrived.send(());
        }
    });
    let connection = || {
        connected
            .recv_timeout(Duration::from_secs(30))
            .expect("the worker connected");
        while connected.try_recv().is_ok() {}
    };

    let step = {
        let path = path.clone();
        std::thread::spawn(move || runtime().block_on(filter_step(&path, NETWORK)))
    };
    connection();
    let refused = runtime()
        .block_on(recover(&path, NETWORK, false, None))
        .unwrap_err();
    assert!(refused.to_string().contains("already running"), "{refused}");
    cancel_recovery();
    let cancelled = step.join().unwrap().unwrap_err();
    assert!(cancelled.contains("cancelled"), "{cancelled}");
    assert!(!admitted());

    let round = {
        let path = path.clone();
        std::thread::spawn(move || {
            runtime()
                .block_on(recover(&path, NETWORK, false, None))
                .map_err(|e| e.to_string())
        })
    };
    connection();
    let refused = runtime().block_on(filter_step(&path, NETWORK)).unwrap_err();
    assert!(refused.contains("already running"), "{refused}");
    cancel_recovery();
    assert!(round.join().unwrap().is_err());
    assert!(!admitted());

    let missing = format!("{path}.missing");
    assert!(runtime().block_on(filter_step(&missing, NETWORK)).is_err());
    assert!(!admitted());
}

/// A step cancelled while its filter range is held commits nothing when the range
/// arrives: the account's coverage and queue stay as they were.
#[test]
fn a_step_cancelled_while_its_range_is_held_commits_nothing() {
    isolated!(a_step_cancelled_while_its_range_is_held_commits_nothing);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let start = frontier(&wallet, &account);

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("filters", 0);
    let result = std::thread::scope(|scope| {
        let step = scope.spawn(|| wallet.step(&service));
        held.wait();
        cancel_recovery();
        held.release();
        step.join().unwrap()
    });
    let error = result.unwrap_err();
    assert!(error.contains("cancelled"), "{error}");
    assert_eq!(frontier(&wallet, &account), start);
    assert!(wallet.queued(&account).is_empty());
}

/// A filter step whose head or range request fails owes a round, so filters that stay
/// unavailable while PIR works don't stall detection: the round's complete check finds
/// the payment.
#[test]
fn a_failing_filter_step_owes_a_round_that_checks_completely() {
    isolated!(a_failing_filter_step_owes_a_round_that_checks_completely);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let refusing = || session::Error::Transport("HTTP 503".into());
    let ranges = Service::at_tip(&chain);
    ranges.fail("filters", 0, refusing);
    assert!(wallet.step(&ranges).unwrap().needs_round);
    let service = Service::at_tip(&chain);
    for n in 0..3 {
        service.fail("head", n, refusing);
    }
    assert!(wallet.step(&service).unwrap().needs_round);
    assert!(wallet.queued(&account).is_empty(), "no filter matched");
    wallet.recover(&service).unwrap();
    assert!(service.filter_requests().is_empty());
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// Beginning a quote enables recovery on that account only. An unused account stays
/// disabled, with NEAR swap privacy off and on.
#[test]
fn a_quote_on_one_of_two_accounts_enables_only_that_one() {
    use crate::api::one_time_ivk as api;
    isolated!(a_quote_on_one_of_two_accounts_enables_only_that_one);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let reserve = |wallet: &Wallet| {
        api::reserve_swap_address(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            RECEIVE,
            chain.tip().into(),
        )
    };
    let index = reserve(&wallet).map_err(|e| e.message).unwrap();
    let index = index.reservation_index.unwrap();
    // Adding an account rewinds the wallet. A round with the toggle off reads the
    // reserved address again, on the used account only.
    let other = wallet.add_account(5, activation());
    wallet.sync(&chain).unwrap();
    wallet.in_use = false;
    crate::api::sync::set_near_swap_privacy_enabled(false);
    wallet.settle(&Service::at_tip(&chain), 4);
    let begin = || {
        api::begin_receive_quote(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            index,
            now() + 3_600,
        )
        .map_err(|e| e.message)
        .unwrap()
    };
    begin();
    assert!(!wallet.state(&other).enabled);
    enable_feature();
    begin();
    assert!(wallet.state(&account).enabled);
    assert!(!wallet.state(&other).enabled);
}

/// Asking for an address on one of two disabled accounts enables that account only. Its
/// first address waits for that address's own lookup.
#[test]
fn asking_for_an_address_enables_only_that_account() {
    isolated!(asking_for_an_address_enables_only_that_account);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    let other = wallet.add_account(5, activation());
    chain.mine(2);
    wallet.scan(&chain);
    assert!(!wallet.state(&account).enabled && !wallet.state(&other).enabled);
    let error = crate::api::one_time_ivk::reserve_swap_address(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        RECEIVE,
        chain.tip().into(),
    )
    .map(|_| ())
    .unwrap_err();
    assert_eq!(
        error.kind,
        crate::api::one_time_ivk::ReceiveErrorKind::ReceiveHistory
    );
    assert!(wallet.state(&account).enabled);
    assert!(!wallet.state(&other).enabled);
}

/// The app's recovery status for `wallet`.
fn status(wallet: &Wallet) -> crate::api::one_time_ivk::SwapRecoveryStatus {
    crate::api::one_time_ivk::get_swap_recovery_status(wallet.path.clone(), "main".into()).unwrap()
}

/// With NEAR swap privacy off and no used account, a round and a filter step make no
/// receiver request and enable nothing, and no round is due.
#[test]
fn with_the_toggle_off_unused_accounts_make_no_requests() {
    isolated!(with_the_toggle_off_unused_accounts_make_no_requests);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let round = wallet.recover(&service).unwrap();
    assert!(!wallet.step(&service).unwrap().needs_round);
    assert_eq!(service.bytes(), 0, "no receiver request");
    assert!(!round.checked && !round.more && round.wait.is_none());
    let work =
        crate::api::one_time_ivk::get_swap_recovery_status(wallet.path.clone(), "main".into())
            .unwrap();
    assert!(!work.round_due);
    assert!(!wallet.state(&account).enabled);
}

/// Turning NEAR swap privacy on enables every software account at the next round.
#[test]
fn turning_the_toggle_on_enables_every_account_at_the_next_round() {
    isolated!(turning_the_toggle_on_enables_every_account_at_the_next_round);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    let other = wallet.add_account(5, activation());
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!wallet.state(&account).enabled && !wallet.state(&other).enabled);

    enable_feature();
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    for account in [&account, &other] {
        let state = wallet.state(account);
        assert!(state.enabled && state.restore_complete);
    }
}

/// An account that handed out an address keeps being queried after NEAR swap privacy is
/// turned off, and an account that never used one stops.
#[test]
fn a_used_account_stays_watched_with_the_toggle_off_and_an_unused_one_stops() {
    isolated!(a_used_account_stays_watched_with_the_toggle_off_and_an_unused_one_stops);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    let other = wallet.add_account(5, activation());
    chain.mine(2);
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    let reserved = crate::api::one_time_ivk::reserve_swap_address(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        RECEIVE,
        chain.tip().into(),
    )
    .map_err(|e| e.message)
    .unwrap();
    assert_eq!(reserved.reservation_index, Some(0));
    assert!(wallet.state(&account).used && !wallet.state(&other).used);

    crate::api::sync::set_near_swap_privacy_enabled(false);
    let start = frontier(&wallet, &other);
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.pay(&other.key(Purpose::Receive, 0), 2_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert_eq!(wallet.one_time_unspent(&other), 0);
    assert_eq!(frontier(&wallet, &other), start);
}

/// With NEAR swap privacy off, a history check covers every software account. A check
/// the app stopped mid-way, as when it quits, keeps each account's job, and automatic
/// rounds resume the jobs until they end. Afterwards only the account the check found a
/// payment for is used and still queried.
#[test]
fn a_history_check_covers_every_account_until_it_ends() {
    isolated!(a_history_check_covers_every_account_until_it_ends);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    let other = wallet.add_account(5, activation());
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(2);
    wallet.scan(&chain);

    let service = Service::at_tip(&chain);
    let held = service.hold("query", 0);
    let worker = wallet.spawn(&service, true, Duration::from_secs(45));
    held.wait();
    cancel_recovery();
    held.release();
    assert!(worker.join().unwrap().is_err());
    for account in [&account, &other] {
        assert!(wallet.state(account).manual.unwrap().active);
    }
    assert!(status(&wallet).manual_check_active);

    wallet.settle(&Service::at_tip(&chain), 6);
    for account in [&account, &other] {
        assert!(!wallet.state(account).manual.unwrap().active);
    }
    assert!(!status(&wallet).checking_history);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert!(wallet.state(&account).used && !wallet.state(&other).used);

    let start = frontier(&wallet, &other);
    chain.pay(&account.key(Purpose::Receive, 1), 500_000, true);
    chain.pay(&other.key(Purpose::Receive, 0), 2_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    assert_eq!(wallet.one_time_unspent(&account), 1_500_000);
    assert_eq!(wallet.one_time_unspent(&other), 0);
    assert_eq!(frontier(&wallet, &other), start);
}

/// A history check that fails after starting its jobs says so, and the jobs keep
/// running: a later round finishes them. One that fails before starting, as a refused
/// start or a capture the wallet can't accept, doesn't.
#[test]
fn a_history_check_says_whether_it_failed_after_starting_its_jobs() {
    isolated!(a_history_check_says_whether_it_failed_after_starting_its_jobs);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    chain.mine(1);
    let ahead = wallet
        .recover_with(&Service::at_tip(&chain), true, Duration::from_secs(45))
        .unwrap_err();
    assert!(matches!(ahead, RecoveryError::NotCaughtUp), "{ahead}");
    assert_eq!(
        crate::api::one_time_ivk::ReceiveError::from(ahead).history_started,
        None
    );
    assert!(wallet.state(&account).manual.is_none());

    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.fail("query", 0, tor_failure);
    service.fail("query", 1, tor_failure);
    let failed = wallet
        .recover_with(&service, true, Duration::from_secs(45))
        .unwrap_err();
    assert!(matches!(failed, RecoveryError::Started(_)), "{failed}");
    let error = crate::api::one_time_ivk::ReceiveError::from(failed);
    assert_eq!(error.history_started, Some(true));
    assert!(error.message.contains("remote hostname lookup failure"));
    assert!(wallet.state(&account).manual.unwrap().active);

    wallet.retry_now();
    wallet.settle(&Service::at_tip(&chain), 4);
    assert!(!wallet.state(&account).manual.unwrap().active);
}

/// A history check whose jobs started, then whose publication the wallet rewound below
/// before the round could accept it for an account, reports a wait for sync that doesn't
/// claim the check never started.
#[test]
fn a_history_check_rewound_after_starting_waits_for_sync() {
    isolated!(a_history_check_rewound_after_starting_waits_for_sync);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    chain.mine(2);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("head", 0);
    let worker = wallet.spawn(&service, true, Duration::from_secs(45));
    held.wait();
    let mut db = wallet.db();
    zcash_client_backend::data_api::WalletWrite::truncate_to_height(
        &mut db,
        (chain.tip() - 1).into(),
    )
    .unwrap();
    drop(db);
    held.release();
    let error = worker.join().unwrap().unwrap_err();
    assert!(
        matches!(&error, RecoveryError::Started(inner)
        if matches!(**inner, RecoveryError::NotCaughtUp)),
        "{error}"
    );
    let error = crate::api::one_time_ivk::ReceiveError::from(error);
    assert_eq!(error.history_started, Some(true));
    assert_eq!(
        error.kind,
        crate::api::one_time_ivk::ReceiveErrorKind::WaitingForSync
    );
    assert!(!error.message.contains("not started"), "{}", error.message);
}

/// The app's history check reports a failure before its jobs started as not started.
#[test]
fn the_app_reports_a_history_check_without_a_server_as_not_started() {
    isolated!(the_app_reports_a_history_check_without_a_server_as_not_started);
    let mut chain = Chain::new();
    chain.mine(2);
    let mut wallet = Wallet::new(4, activation());
    wallet.scan(&chain);
    let error = crate::api::one_time_ivk::check_swap_history(wallet.path.clone(), "main".into())
        .map(|_| ())
        .unwrap_err();
    assert!(
        error.message.contains("No private query server"),
        "{}",
        error.message
    );
    assert_eq!(error.history_started, Some(false));
}

/// A history check starts every account's job or none. When the second account can't
/// accept the publication, the first account's job doesn't start either, and the check
/// fails with a wait the app retries.
#[test]
fn a_history_check_starts_every_job_or_none() {
    isolated!(a_history_check_starts_every_job_or_none);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let created = wallet.account().clone();
    let added = wallet.add_account(5, activation());
    let order = one_time_ivk::software_accounts(&wallet.db()).unwrap();
    let (first, second) = if order[0] == created.id {
        (created, added)
    } else {
        (added, created)
    };
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    // The second account saw a correction this publication predates.
    rusqlite::Connection::open(&wallet.path)
        .unwrap()
        .execute(
            "UPDATE ironwood_one_time_recovery SET history_revision = X'0000000000000001'
             WHERE account_id = (SELECT id FROM accounts WHERE uuid = ?1)",
            [second.id.expose_uuid().as_bytes().as_slice()],
        )
        .unwrap();

    let error = wallet
        .recover_with(&Service::at_tip(&chain), true, Duration::from_secs(45))
        .unwrap_err();
    assert!(matches!(error, RecoveryError::NotCaughtUp), "{error}");
    assert_eq!(
        crate::api::one_time_ivk::ReceiveError::from(error).kind,
        crate::api::one_time_ivk::ReceiveErrorKind::WaitingForSync
    );
    for account in [&first, &second] {
        assert!(wallet.state(account).manual.is_none());
    }
}

/// Turning NEAR swap privacy off while an unused account's seed walk is unfinished takes
/// the account out of the set, so its walk no longer holds the history check's status,
/// and a history check runs to its end.
#[test]
fn toggle_off_during_an_unused_walk_lets_a_history_check_finish() {
    isolated!(toggle_off_during_an_unused_walk_lets_a_history_check_finish);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("query", 1);
    let worker = wallet.spawn(&service, false, Duration::from_secs(45));
    held.wait();
    cancel_recovery();
    held.release();
    assert!(worker.join().unwrap().is_err());
    assert!(!wallet.state(&account).restore_complete);
    assert!(status(&wallet).checking_history);

    crate::api::sync::set_near_swap_privacy_enabled(false);
    assert!(
        !status(&wallet).checking_history,
        "the unused account left the set"
    );
    wallet
        .recover_with(&Service::at_tip(&chain), true, Duration::from_secs(45))
        .unwrap();
    assert!(!wallet.state(&account).manual.unwrap().active);
    assert!(!status(&wallet).checking_history);
}

/// Whether the app owes a round, as it reads it.
fn due(wallet: &Wallet) -> bool {
    crate::api::one_time_ivk::get_swap_recovery_status(wallet.path.clone(), "main".into())
        .unwrap()
        .round_due
}

/// An account in the set that isn't enabled yet makes a round due. The round that enables
/// it registers its keys and reads their bootstrap lookups, which settles it.
#[test]
fn an_account_the_set_gains_owes_the_round_that_enables_it() {
    isolated!(an_account_the_set_gains_owes_the_round_that_enables_it);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    assert!(due(&wallet));
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(wallet.state(&account).enabled);
    assert!(!due(&wallet));
}

/// An account outside the set whose first use lands while a round runs isn't covered by
/// that round. The use puts it back in the set, so the next round covers it from its
/// marker.
#[test]
fn an_excluded_accounts_first_use_during_a_round_is_covered_next() {
    isolated!(an_excluded_accounts_first_use_during_a_round_is_covered_next);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    wallet.in_use = false;
    let account = wallet.account().clone();
    let other = wallet.add_account(5, activation());
    chain.mine(2);
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    let index = crate::api::one_time_ivk::reserve_swap_address(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        RECEIVE,
        chain.tip().into(),
    )
    .map_err(|e| e.message)
    .unwrap()
    .reservation_index
    .unwrap();
    crate::api::sync::set_near_swap_privacy_enabled(false);
    let excluded = frontier(&wallet, &other);

    chain.pay(&account.key(Purpose::Receive, index), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("query", 0);
    let worker = wallet.spawn(&service, false, Duration::from_secs(45));
    held.wait();
    // The other account hands out its next address, its first use.
    wallet
        .db()
        .prepare_receive_reservation(other.id, now())
        .unwrap()
        .unwrap();
    assert!(wallet.state(&other).used);
    held.release();
    worker.join().unwrap().unwrap();
    assert_eq!(frontier(&wallet, &other), excluded);

    chain.mine(1);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(frontier(&wallet, &other), Some(chain.tip()));
}

/// A payment found over a block the scan didn't cover for spends waits for a rescan of
/// it. A history check and every later round report that it awaits admission, so the app
/// starts sync, and the account doesn't read as ready until the rescan admits it.
#[test]
fn a_round_that_queues_a_rescan_reports_it() {
    isolated!(a_round_that_queues_a_rescan_reports_it);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let tip = chain.tip();
    // The tip was stored without spend coverage, as blocks scanned before the journal
    // existed are.
    rusqlite::Connection::open(&wallet.path)
        .unwrap()
        .execute(
            "UPDATE ironwood_journal_coverage SET end_height = ?1 WHERE end_height > ?1",
            [tip],
        )
        .unwrap();
    // A history check reports it, and so does a later round, from durable state.
    let manual = wallet
        .recover_with(&Service::at_tip(&chain), true, Duration::from_secs(45))
        .unwrap();
    assert!(manual.awaiting_admission);
    let round = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(round.awaiting_admission && !round.more);
    assert_eq!(wallet.one_time_unspent(&account), 0, "admission waits");
    assert!(wallet.scanned() < tip, "the tip is queued again");
    let readiness = |wallet: &Wallet| {
        crate::api::one_time_ivk::get_swap_account_readiness(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
        )
        .unwrap()
    };
    let waiting = readiness(&wallet);
    assert!(waiting.awaiting_admission, "not ready while it waits");
    assert!(!waiting.lookups && !waiting.seed_walk);

    wallet.rescan_from(&chain, tip);
    let round = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!round.awaiting_admission);
    assert!(!readiness(&wallet).awaiting_admission);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// A round is due while a lookup is queued, as a filter hit queues one, or while the
/// account's marker is more than 10 blocks below the scanned tip, and the round that
/// reads them clears it.
#[test]
fn a_round_is_due_for_queued_lookups_or_a_lagging_marker() {
    isolated!(a_round_is_due_for_queued_lookups_or_a_lagging_marker);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!due(&wallet));

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    assert!(!due(&wallet), "filters haven't read the payment yet");
    wallet.step(&Service::at_tip(&chain)).unwrap();
    assert!(due(&wallet), "the hit queued a lookup");
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert!(!due(&wallet));

    chain.mine(10);
    wallet.scan(&chain);
    assert!(!due(&wallet), "ten blocks behind is close enough");
    chain.mine(1);
    wallet.scan(&chain);
    assert!(due(&wallet), "the marker lags");
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!due(&wallet));
}

/// A receive address is handed out only once its own lookup completed and filters were
/// read within 10 blocks of the chain tip. Until then issuance asks for a round. A refund
/// index needs no lookup. When another device pays the next receive address, the round
/// that finds the payment moves issuance past it.
#[test]
fn issuance_waits_for_fresh_history_and_moves_past_a_paid_address() {
    isolated!(issuance_waits_for_fresh_history_and_moves_past_a_paid_address);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    let reserve = |wallet: &Wallet, incoming, tip: u32| {
        crate::api::one_time_ivk::reserve_swap_address(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            incoming,
            tip.into(),
        )
    };
    let history = crate::api::one_time_ivk::ReceiveErrorKind::ReceiveHistory;
    let error = reserve(&wallet, true, chain.tip()).map(|_| ()).unwrap_err();
    assert_eq!(error.kind, history, "I0's lookup hasn't run");
    let refund = reserve(&wallet, false, chain.tip()).unwrap();
    assert_eq!(refund.refund_index, Some(0), "no lookup needed");

    wallet.recover(&Service::at_tip(&chain)).unwrap();
    chain.mine(11);
    wallet.scan(&chain);
    let error = reserve(&wallet, true, chain.tip()).map(|_| ()).unwrap_err();
    assert_eq!(error.kind, history, "filters are 11 blocks behind");
    assert!(due(&wallet));

    // Another device pays I0, the next receive address.
    chain.pay(&account.key(Purpose::Receive, 0), 500_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    assert_eq!(wallet.one_time_unspent(&account), 500_000);
    let next = reserve(&wallet, true, chain.tip()).unwrap();
    assert_eq!(next.reservation_index, Some(1));
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
            (RECEIVE, 0, None),
            (RECEIVE, 0, Some(0)),
            (RECEIVE, 1, None),
            (RECEIVE, 2, None),
            (RECEIVE, 2, Some(0)),
            (RECEIVE, 2, Some(1)),
            (RECEIVE, 3, None),
            (RECEIVE, 4, None),
            (RECEIVE, 5, None),
            (RECEIVE, 6, None),
        ],
        "one directory query per address, then one query per record"
    );
    assert_eq!(wallet.one_time_unspent(&account), 3_300_000);
    service.report("seed restore across a hole: seven addresses, three records and proofs");

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

/// A service speaking a newer inventory protocol stops the round with an upgrade
/// outcome instead of deferring forever. The wallet keeps its pending work, the app
/// reports the update state, and a supported publication resumes and clears it.
#[test]
fn unsupported_service_requires_an_upgrade_and_keeps_pending_work() {
    isolated!(unsupported_service_requires_an_upgrade_and_keeps_pending_work);
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
    assert!(!state.restore_complete, "the pending seed walk is kept");

    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!status().upgrade_required);
    assert!(wallet.state(&account).restore_complete);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// The error a broken Tor circuit gives a receiver request.
fn tor_failure() -> session::Error {
    session::Error::Transport(
        "network: private-service Tor request failed: tor: remote hostname lookup failure".into(),
    )
}

/// A receiver request that fails in transit gets a second attempt within the round, so
/// one bad circuit costs a request rather than the round. A request that fails twice
/// still fails the round and leaves its lookup pending.
#[test]
fn a_request_that_fails_in_transit_is_retried_once_within_the_round() {
    isolated!(a_request_that_fails_in_transit_is_retried_once_within_the_round);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let receive = |index| account.key(Purpose::Receive, index);
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    chain.pay(&receive(0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.fail("inventory", 0, tor_failure);
    service.fail("query", 0, tor_failure);
    assert!(wallet.recover(&service).unwrap().changed);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert!(wallet.queued(&account).is_empty());
    assert_eq!(service.count("inventory"), 2);
    assert_eq!(
        service.queries(),
        4,
        "I0's directory twice and its record, then the bootstrap of I4"
    );

    chain.pay(&receive(1), 500_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.fail("query", 0, tor_failure);
    service.fail("query", 1, tor_failure);
    let error = wallet.recover(&service).unwrap_err().to_string();
    assert!(error.contains("remote hostname lookup failure"), "{error}");
    assert_eq!(service.queries(), 2, "one retry, then the round fails");
    assert_eq!(wallet.queued(&account), BTreeSet::from([(RECEIVE, 1)]));
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// An HTTP status answer or an unsupported format is the service's answer, which a
/// second attempt would not change, so neither is retried.
#[test]
fn status_answers_and_unsupported_formats_are_not_retried() {
    isolated!(status_answers_and_unsupported_formats_are_not_retried);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    chain.mine(2);
    wallet.scan(&chain);

    let refusing = Service::at_tip(&chain);
    refusing.fail("inventory", 0, || {
        session::Error::Transport("HTTP 503".into())
    });
    assert!(wallet.recover(&refusing).is_err());
    assert_eq!(refusing.count("inventory"), 1);

    let refusing = Service::at_tip(&chain);
    refusing.fail("query", 0, || session::Error::Transport("HTTP 404".into()));
    assert!(wallet.recover(&refusing).is_err());
    assert_eq!(refusing.queries(), 1);

    let newer = Service::at_tip(&chain);
    newer.fail("query", 0, || session::Error::Unsupported);
    let error = wallet.recover(&newer).unwrap_err();
    assert!(matches!(error, RecoveryError::UpgradeRequired), "{error}");
    assert_eq!(newer.queries(), 1);
}

/// A history check reads every address again from its history start, so it finds a
/// payment an earlier answer left out instead of skipping an address already checked.
#[test]
fn a_history_check_finds_a_payment_an_earlier_answer_left_out() {
    isolated!(a_history_check_finds_a_payment_an_earlier_answer_left_out);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let key = account.key(Purpose::Receive, 0);
    let paid = chain.pay(&key, 500_000, false);
    chain.mine(2);
    wallet.scan(&chain);
    wallet.settle(&Service::at_tip(&chain), 4);
    assert_eq!(
        wallet.one_time_unspent(&account),
        0,
        "the directory left it out"
    );

    chain.index(paid, &key);
    let service = Service::at_tip(&chain);
    wallet
        .recover_with(&service, true, Duration::from_secs(45))
        .unwrap();
    wallet.settle(&service, 4);
    assert_eq!(wallet.one_time_unspent(&account), 500_000);
}

/// Switching to another Receiver server forgets the history the old one gave, so its
/// answers, such as a payment it left out, aren't trusted. The same server again changes
/// nothing.
#[test]
fn a_new_receiver_server_forgets_the_old_ones_history() {
    isolated!(a_new_receiver_server_forgets_the_old_ones_history);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    let adopt = |wallet: &Wallet, origin: &str| {
        adopt_server(&wallet.path, NETWORK, CANCEL.load(Ordering::SeqCst), origin).unwrap()
    };
    adopt(&wallet, "https://a.example");
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(wallet.state(&account).filter_frontier.is_some());
    adopt(&wallet, "https://a.example");
    assert!(wallet.state(&account).filter_frontier.is_some());
    adopt(&wallet, "https://b.example");
    let state = wallet.state(&account);
    assert!(state.filter_frontier.is_none() && state.round_due);
}

/// A lookup whose request is lost in transit, retry included, isn't backed off: it stays
/// due, so the next round reads it at once rather than after the backoff an outage built.
#[test]
fn a_lookup_lost_in_transit_stays_due() {
    isolated!(a_lookup_lost_in_transit_stays_due);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    chain.pay(&account.key(Purpose::Receive, 0), 500_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let lost = Service::at_tip(&chain);
    lost.fail("query", 0, tor_failure);
    lost.fail("query", 1, tor_failure);
    assert!(wallet.recover(&lost).is_err());
    let next = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(next.wait, None);
    assert_eq!(wallet.one_time_unspent(&account), 500_000);
}

/// A request that fails in transit after its round was cancelled is not retried.
#[test]
fn a_cancelled_round_does_not_retry_a_failed_request() {
    isolated!(a_cancelled_round_does_not_retry_a_failed_request);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let held = service.hold("query", 0);
    service.fail("query", 0, tor_failure);
    let worker = wallet.spawn(&service, false, Duration::from_secs(45));
    held.wait();
    cancel_recovery();
    held.release();
    let error = worker.join().unwrap().unwrap_err().to_string();
    assert!(error.contains("cancelled"), "{error}");
    assert_eq!(service.queries(), 1);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(wallet.state(&account).restore_complete);
}

/// A payout a lookup found arrives with its proof and is credited at once, so a failing
/// lookup for another address can't hold it back.
#[test]
fn a_found_payment_is_credited_before_further_lookups() {
    isolated!(a_found_payment_is_credited_before_further_lookups);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let receive = |index| account.key(Purpose::Receive, index);
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();

    chain.pay(&receive(1), 500_000, true);
    chain.pay(&receive(2), 700_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    service.fail("query", 2, || session::Error::Transport("HTTP 503".into()));
    assert!(wallet.recover(&service).is_err());
    assert_eq!(
        service.queries(),
        3,
        "I1's directory and record, then I2's directory, refused"
    );
    assert_eq!(wallet.one_time_unspent(&account), 500_000);
    assert!(wallet.queued(&account).contains(&(RECEIVE, 2)));
}

/// History before the recent tier lives in sealed shards with receiver filters. For a
/// restore's handful of addresses the filters cost less than reading each shard blind,
/// so only the address the filter matches reads the sealed shard, and the payment in it
/// is credited. The wallet keeps the verified descriptors for the next capture, and a
/// corrupted saved value only costs a full capture.
#[test]
fn sealed_shards_use_filters_and_inventory_descriptors_persist() {
    isolated!(sealed_shards_use_filters_and_inventory_descriptors_persist);
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
            (RECEIVE, 0, None),
            (RECEIVE, 0, Some(0)),
            (RECEIVE, 0, None),
            (RECEIVE, 1, None),
            (RECEIVE, 2, None),
            (RECEIVE, 3, None),
            (RECEIVE, 4, None),
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
    for n in 0..4 {
        service.stall("shard-filter", n);
    }

    // Reading seven shards blind for each of five addresses, at 200 ms a query, outlasts
    // one round.
    service.delay("query", Duration::from_millis(200));
    let budget = Duration::from_secs(6);
    let mut rounds = 0;
    while !wallet.state(&account).restore_complete {
        rounds += 1;
        assert!(rounds <= 5, "the restore keeps progressing");
        wallet.recover_with(&service, false, budget).unwrap();
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
        wallet.recover_with(&service, false, budget).unwrap();
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
    for n in 0..16 {
        service.stall("filters", n);
    }

    // Seven accounts each waiting for a stall would outlast this ten second round.
    wallet
        .recover_with(&service, false, Duration::from_secs(10))
        .unwrap();
    assert_eq!(
        service.count("filters"),
        1,
        "one stalled request ends filter work"
    );
    assert_eq!(wallet.one_time_unspent(&first), 1_000_000);
}

/// A round that finds nothing new reports no change, so the app reloads nothing, while
/// one that credits a payout does. Both report the service as checked.
#[test]
fn only_a_round_that_records_results_reports_a_change() {
    isolated!(only_a_round_that_records_results_reports_a_change);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    assert!(wallet.recover(&service).unwrap().changed, "the seed walk");
    assert!(wallet.state(&account).restore_complete);

    // The same publication again, then two empty blocks found through filters.
    let again = wallet.recover(&service).unwrap();
    assert!(again.checked && !again.changed);
    chain.mine(2);
    wallet.scan(&chain);
    let service = Service::at_tip(&chain);
    let quiet = wallet.recover(&service).unwrap();
    assert!(quiet.checked && !quiet.changed && !quiet.more);
    assert_eq!(quiet.wait, None);
    assert_eq!(service.queries(), 0);

    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let paid = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(paid.checked && paid.changed);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
}

/// An automatic round that cannot accept the receiver's inventory, because the wallet
/// has not scanned its end or the service ends below the wallet birthday, waits without
/// reporting the service as checked.
#[test]
fn a_round_waiting_at_capture_does_not_check_the_service() {
    isolated!(a_round_waiting_at_capture_does_not_check_the_service);
    let mut chain = Chain::new();
    chain.mine(3);
    let birthday = chain.tip() + 1;
    let mut wallet = Wallet::new(4, birthday);
    chain.mine(3);
    wallet.scan(&chain);
    let behind = Service::publish(&chain, birthday - 1, activation(), chain.tip(), &[]);
    let round = wallet.recover(&behind).unwrap();
    assert!(!round.checked && !round.changed && !round.more);
    assert_eq!(round.wait, Some(Wait::Publication));

    chain.mine(2);
    let unscanned = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(!unscanned.checked && !unscanned.changed && !unscanned.more);
    assert_eq!(unscanned.wait, Some(Wait::Sync));
    wallet.scan(&chain);
    assert!(wallet.recover(&Service::at_tip(&chain)).unwrap().checked);
}

/// A history check against a publication the wallet has not scanned yet reports that
/// it is waiting for sync, a kind of its own the app can show honestly, rather than a
/// failure.
#[test]
fn a_history_check_ahead_of_sync_waits_for_sync() {
    isolated!(a_history_check_ahead_of_sync_waits_for_sync);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    chain.mine(2);
    wallet.scan(&chain);
    chain.mine(2);
    let error = wallet
        .recover_with(&Service::at_tip(&chain), true, Duration::from_secs(45))
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
    let mut chain = Chain::new();
    chain.mine(3);
    let birthday = chain.tip() + 1;
    let mut wallet = Wallet::new(4, birthday);
    let account = wallet.account().clone();
    chain.mine(3);
    wallet.scan(&chain);
    let behind = Service::publish(&chain, birthday - 1, activation(), chain.tip(), &[]);
    assert!(!wallet.recover(&behind).unwrap().checked);
    let error = wallet
        .recover_with(&behind, true, Duration::from_secs(45))
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
        .recover_with(&caught_up, true, Duration::from_secs(45))
        .unwrap();
    assert!(wallet.state(&account).manual.is_some());
}

/// A history check against a publication whose end block differs from the one the
/// wallet scanned at that height is a retryable failure, not a wait for either side.
#[test]
fn a_history_check_on_another_fork_fails_for_retry() {
    isolated!(a_history_check_on_another_fork_fails_for_retry);
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
    assert!(!wallet.recover(&other).unwrap().checked);
    let error = wallet
        .recover_with(&other, true, Duration::from_secs(45))
        .unwrap_err();
    assert!(matches!(error, RecoveryError::Other(_)), "{error}");
    assert_eq!(
        crate::api::one_time_ivk::ReceiveError::from(error).kind,
        crate::api::one_time_ivk::ReceiveErrorKind::Other
    );
}

/// An account with ZIP 32 metadata but no Orchard key, as an unbackfilled hardware import
/// can be, is not a software account. Recovery, the status read and issuance keep working
/// for the wallet's other accounts, with NEAR swap privacy off and on.
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
    // A second round reads the bootstrap of the address I0's payment exposed.
    wallet.recover(&Service::at_tip(&chain)).unwrap();
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

/// With NEAR swap privacy off, rounds still cover accounts that used one-time addresses
/// and credit payouts to addresses handed out earlier, on each account. Only new
/// reservations are refused.
#[test]
fn discovery_runs_with_the_toggle_off() {
    isolated!(discovery_runs_with_the_toggle_off);
    crate::api::sync::set_enhance_pir_enabled(true);
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    let second = wallet.add_account(5, activation());
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.pay(&second.key(Purpose::Receive, 1), 400_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    let round = wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert!(round.checked && round.changed);
    assert!(wallet.state(&account).enabled && wallet.state(&second).enabled);
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    assert_eq!(wallet.one_time_unspent(&second), 400_000);
    let refused = crate::api::one_time_ivk::reserve_swap_address(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        RECEIVE,
        chain.tip().into(),
    )
    .err()
    .unwrap();
    assert!(
        refused.message.contains("NEAR swap privacy"),
        "{}",
        refused.message
    );
}

/// Private queries don't gate one-time addresses: with them off, rounds credit payouts and
/// NEAR swap privacy alone allows a new reservation.
#[test]
fn discovery_and_issuance_run_with_private_queries_off() {
    isolated!(discovery_and_issuance_run_with_private_queries_off);
    crate::api::sync::set_enhance_pir_enabled(false);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.pay(&account.key(Purpose::Receive, 0), 1_000_000, true);
    chain.mine(1);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    assert_eq!(wallet.one_time_unspent(&account), 1_000_000);
    let reserved = crate::api::one_time_ivk::reserve_swap_address(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        RECEIVE,
        chain.tip().into(),
    )
    .map_err(|e| e.message)
    .unwrap();
    assert_eq!(reserved.reservation_index, Some(1));
}

/// Turning NEAR swap privacy off after reserving an address only blocks new ones. The
/// quote for the reserved address still begins, finishes and starts.
#[test]
fn a_reserved_quote_finishes_after_the_toggle_turns_off() {
    use crate::api::one_time_ivk as api;
    isolated!(a_reserved_quote_finishes_after_the_toggle_turns_off);
    enable_feature();
    let mut chain = Chain::new();
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    chain.mine(2);
    wallet.scan(&chain);
    wallet.recover(&Service::at_tip(&chain)).unwrap();
    let reserve = || {
        api::reserve_swap_address(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            RECEIVE,
            chain.tip().into(),
        )
    };
    let index = reserve()
        .map_err(|e| e.message)
        .unwrap()
        .reservation_index
        .unwrap();

    crate::api::sync::set_near_swap_privacy_enabled(false);
    assert!(reserve().is_err(), "a new address needs the toggle");
    let request = api::begin_receive_quote(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        index,
        now() + 3_600,
    )
    .map_err(|e| e.message)
    .unwrap();
    api::finish_receive_quote(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        request.clone(),
        Some(api::ReceiveDeposit {
            address: "deposit.near".into(),
            memo: None,
            deadline_seconds: now() + 3_600,
        }),
    )
    .map_err(|e| e.message)
    .unwrap();
    let deposit = api::start_receive_quote(
        wallet.path.clone(),
        "main".into(),
        account.uuid.clone(),
        request,
    )
    .map_err(|e| e.message)
    .unwrap();
    assert_eq!(deposit.address, "deposit.near");
}

/// Without a selected private query server, an automatic round waits instead of failing,
/// through the worker and the app's entry point alike, and touches no receiver. A history
/// check the user starts says why it can't run, and a second round is refused while one
/// runs.
#[test]
fn without_a_server_the_round_waits() {
    isolated!(without_a_server_the_round_waits);
    let mut chain = Chain::new();
    chain.mine(3);
    let mut wallet = Wallet::new(4, activation());
    wallet.scan(&chain);
    assert_eq!(
        crate::wallet::pir_config::client_origin(PirProduct::Receiver),
        None
    );
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let round = runtime
        .block_on(recover(&wallet.path, NETWORK, false, None))
        .unwrap();
    assert!(!round.checked && !round.changed && !round.more);
    assert_eq!(round.wait, Some(Wait::Server));
    let round =
        crate::api::one_time_ivk::run_swap_recovery(wallet.path.clone(), "main".into()).unwrap();
    assert!(!round.checked && !round.changed && !round.more);
    assert_eq!(
        round.wait,
        Some(crate::api::one_time_ivk::SwapRecoveryWait::Server)
    );
    let error = runtime
        .block_on(recover(&wallet.path, NETWORK, true, None))
        .unwrap_err();
    assert!(
        error.to_string().contains("No private query server"),
        "{error}"
    );
    // While a round is admitted, the app's entry point refuses another before anything
    // else, server or not.
    RUNNING.store(true, Ordering::SeqCst);
    let busy = crate::api::one_time_ivk::run_swap_recovery(wallet.path.clone(), "main".into());
    RUNNING.store(false, Ordering::SeqCst);
    assert!(busy.is_err_and(|e| e.message.contains("already running")));
}

/// A status record expects ZEC whenever the wallet's NEAR normalizer does: a payout, a
/// refund on FAILED or REFUNDED, a partial refund on SUCCESS and an exact-output SUCCESS
/// without a reported amount, but not a SUCCESS that reports no refund.
#[test]
fn status_records_expect_zec_as_the_normalizer_does() {
    isolated!(status_records_expect_zec_as_the_normalizer_does);
    use crate::api::one_time_ivk as api;
    let mut chain = Chain::new();
    chain.mine(3);
    let mut wallet = Wallet::new(4, activation());
    let account = wallet.account().clone();
    wallet.scan(&chain);
    let expects = |incoming, status: &str, swap_type: Option<&str>, refunded: Option<&str>| {
        api::observe_swap_status(
            wallet.path.clone(),
            "main".into(),
            account.uuid.clone(),
            incoming,
            "deposit.near".into(),
            None,
            api::SwapProviderStatus {
                status: status.into(),
                swap_type: swap_type.map(Into::into),
                refunded_amount: refunded.map(Into::into),
                amount_out: None,
                origin_tx_hashes: vec![],
                destination_tx_hashes: vec![],
            },
            true,
            now(),
        )
        .unwrap()
        .receipt_expected
    };
    assert!(expects(RECEIVE, "SUCCESS", None, None));
    assert!(!expects(RECEIVE, "FAILED", None, None));
    assert!(expects(!RECEIVE, "FAILED", None, None));
    assert!(expects(!RECEIVE, "SUCCESS", None, Some("2500")));
    assert!(expects(!RECEIVE, "SUCCESS", Some("EXACT_OUTPUT"), None));
    assert!(!expects(
        !RECEIVE,
        "SUCCESS",
        Some("EXACT_OUTPUT"),
        Some("0")
    ));
    assert!(!expects(!RECEIVE, "PROCESSING", None, None));
}

/// Reading the status, pausing a history check and a provider status for an ordinary swap
/// commit nothing to a wallet that never ran a round, so no recovery rows exist and
/// ordinary scanning keeps working.
#[test]
fn read_only_entry_points_leave_the_wallet_untouched() {
    isolated!(read_only_entry_points_leave_the_wallet_untouched);
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

    api::get_swap_recovery_status(path.clone(), main()).unwrap();
    api::cancel_swap_history(path.clone(), main()).unwrap();
    // The wallet tracks no operation for an ordinary deposit address.
    let record = api::observe_swap_status(
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
    assert!(!record.tracked && record.receipt_expected);
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
