//! Directed scenarios for promises the random harness reaches rarely or not at all.
use super::*;

/// Runs the world's default round on `dev` and fails on any violation.
fn settle(world: &mut World, dev: usize) {
    for _ in 0..4 {
        let publication = world.current();
        world.round(dev, 0, false, publication, 0, false).unwrap();
    }
}

impl World {
    /// A new world whose first device has synced and settled.
    fn ready() -> Self {
        let mut world = Self::new();
        world.sync(0, false);
        settle(&mut world, 0);
        world
    }
}

/// The value of `dev`'s mined one-time notes on its first account, per key.
fn credited(world: &World, dev: usize) -> Vec<Note> {
    let device = &world.devices[dev];
    let mut notes: Vec<Note> = notes(&device.wallet, &device.accts[0].account.id)
        .into_iter()
        .filter(|n| n.mined)
        .collect();
    notes.sort();
    notes
}

/// A payout credited before a reorg that drops its block, and paid again on the new
/// branch, ends up credited exactly once from the new branch, and the balance follows.
#[test]
fn a_reorged_payout_is_credited_once_from_the_new_branch() {
    if isolated("directed::a_reorged_payout_is_credited_once_from_the_new_branch") {
        return;
    }
    let mut world = World::ready();
    let line = world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 700_000,
        })
        .unwrap();
    assert!(line.contains("paid 700000 to I0"), "{line}");
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    let before = credited(&world, 0);
    assert_eq!(before.len(), 1);
    let ordinary = world.devices[0]
        .wallet
        .balance(&world.devices[0].accts[0].account)
        - 700_000;
    let reorg = world.reorg(3);
    assert!(reorg.contains("re-sent 1 payouts"), "{reorg}");
    world.sync(0, true);
    world.check_step().unwrap();
    settle(&mut world, 0);
    world.check_step().unwrap();
    let after = credited(&world, 0);
    assert_eq!(after.len(), 1, "{after:?}");
    assert_ne!(
        after[0].txid, before[0].txid,
        "the new branch's payout is credited"
    );
    assert_eq!(after[0].value, 700_000);
    // The orphaned note stays stored unmined. Like an orphaned ordinary payment (see
    // `an_orphaned_ordinary_payment_stays_pending`), it counts as pending but never as
    // spendable.
    world.mine(12);
    world.sync(0, true);
    settle(&mut world, 0);
    let account = &world.devices[0].accts[0].account;
    let wallet = &world.devices[0].wallet;
    let b = crate::api::sync::get_balance(wallet.path.clone(), "main".into(), account.uuid.clone())
        .unwrap();
    assert_eq!(
        b.spendable,
        ordinary + 700_000,
        "only the new branch's payout is spendable"
    );
    assert_eq!(
        b.total,
        ordinary + 1_400_000,
        "the orphaned note still shows as pending"
    );
}

/// Deleting an account and adding the same seed back recovers its one-time payments
/// like a restore at its birthday. Its unfunded quotes are forgotten, which is intended.
#[test]
fn a_deleted_and_readded_account_recovers_like_a_restore() {
    if isolated("directed::a_deleted_and_readded_account_recovers_like_a_restore") {
        return;
    }
    let mut world = World::new();
    world.act(&Action::AddAccount(0)).unwrap();
    world.sync(0, false);
    settle(&mut world, 0);
    let line = world
        .act(&Action::Swap {
            dev: 0,
            acct: 1,
            value: 400_000,
        })
        .unwrap();
    assert!(line.contains("paid 400000"), "{line}");
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    let second = |world: &World| {
        let device = &world.devices[0];
        let acct = device.accts.iter().find(|a| a.seed == SECOND).unwrap();
        notes(&device.wallet, &acct.account.id)
            .into_iter()
            .filter(|n| n.mined)
            .count()
    };
    assert_eq!(second(&world), 1);
    world
        .act(&Action::DeleteAccount { dev: 0, acct: 1 })
        .unwrap();
    world.act(&Action::AddAccount(0)).unwrap();
    world.sync(0, false);
    settle(&mut world, 0);
    assert_eq!(
        second(&world),
        1,
        "the re-added account found its payment again"
    );
    world.check_step().unwrap();
}

/// The funding device retires a refund key once its swap ended with no refund or its
/// refund arrived. A second device that learned the same keys from funding memos keeps
/// monitoring each one until filters have checked [`MEMO_REFUND_WINDOW`] past its funding,
/// then retires it too.
#[test]
fn local_refund_keys_retire_when_conclusive_and_memo_learned_ones_after_the_window() {
    if isolated(
        "directed::local_refund_keys_retire_when_conclusive_and_memo_learned_ones_after_the_window",
    ) {
        return;
    }
    let mut world = World::new();
    world.add_device(activation(), true);
    world.sync(0, false);
    settle(&mut world, 0);
    for outcome in [0, 2] {
        let line = world
            .act(&Action::SwapOut {
                dev: 0,
                acct: 0,
                outcome,
            })
            .unwrap();
        assert!(line.contains("funded"), "{line}");
        // Change from the first funding needs confirmations before the second.
        world.mine(12);
        world.sync(0, false);
    }
    for dev in [0, 1] {
        world.sync(dev, true);
        world.poll(dev, 0).unwrap();
        settle(&mut world, dev);
    }
    let monitored = |world: &World, dev: usize| {
        let device = &world.devices[dev];
        monitored_refunds(&device.wallet, &device.accts[0].account.id)
    };
    assert!(
        monitored(&world, 0).is_empty(),
        "{:?}",
        monitored(&world, 0)
    );
    assert_eq!(monitored(&world, 1), BTreeSet::from([0, 1]));
    for dev in [0, 1] {
        assert_eq!(
            credited(&world, dev).iter().filter(|n| !n.receive).count(),
            1
        );
    }
    let funded: Vec<u32> = world.fundings.iter().filter_map(|f| f.height).collect();
    assert_eq!(funded.len(), 2);
    // With filters through one block short of a window past R1's funding, only R0 is
    // older.
    world.mine(funded[1] + MEMO_REFUND_WINDOW - 1 - world.chain.tip());
    world.sync(1, false);
    settle(&mut world, 1);
    assert_eq!(monitored(&world, 1), BTreeSet::from([1]));
    world.mine(1);
    world.sync(1, false);
    settle(&mut world, 1);
    assert!(
        monitored(&world, 1).is_empty(),
        "{:?}",
        monitored(&world, 1)
    );
}

/// A started quote that never gets another provider status keeps its slot for 24 hours
/// past its deadline, then releases it while its address is unpaid.
#[test]
fn a_started_quote_without_any_status_releases_its_slot_a_day_later() {
    if isolated("directed::a_started_quote_without_any_status_releases_its_slot_a_day_later") {
        return;
    }
    let mut world = World::ready();
    for _ in 0..4 {
        let line = world.quote_in(0, 0, Reply::Accept, 3_600).unwrap();
        assert!(line.contains("accepted and shown"), "{line}");
    }
    // The app's reservation call, without the harness's status refresh on `Limit`.
    let reserve = |world: &mut World| {
        world
            .reserve(0, 0, true)
            .unwrap()
            .map(|address| address.reservation_index)
            .map_err(|e| e.kind)
    };
    world.act(&Action::Warp(3_600 + 23 * 3_600)).unwrap();
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    assert_eq!(
        reserve(&mut world),
        Err(crate::api::one_time_ivk::ReceiveErrorKind::Limit),
        "23 hours past the deadline the slots are still held"
    );
    world.act(&Action::Warp(2 * 3_600)).unwrap();
    world.mine(1);
    world.sync(0, false);
    assert_eq!(
        reserve(&mut world),
        Ok(Some(0)),
        "25 hours past the deadline the lowest slot is free"
    );
}

/// A receipt a reorg moved is repaired. The same payment transaction mined again a block
/// later, after an unrelated output that shifts its tree position, is placed again with
/// its new height and position, keeps its single credit and is spendable again.
#[test]
fn a_receipt_a_reorg_moved_is_placed_again() {
    if isolated("directed::a_receipt_a_reorg_moved_is_placed_again") {
        return;
    }
    let mut world = World::ready();
    // A real payment to I0 from another seed, so a reorg can mine the same transaction.
    let mut payer = Wallet::new(SECOND, activation());
    payer.sync(&world.chain).unwrap();
    let fvk = world.key(MAIN, true, 0);
    let receiver = fvk.address_at(0u32, orchard::keys::Scope::External);
    let address = zcash_keys::address::Address::Unified(
        zcash_keys::address::UnifiedAddress::from_receivers(Some(receiver), None, None).unwrap(),
    )
    .to_zcash_address(&NETWORK)
    .to_string();
    let proposal = crate::wallet::sync::propose_send(
        &payer.path,
        NETWORK,
        &payer.account().uuid,
        "pay",
        &address,
        500_000,
        None,
    )
    .unwrap();
    super::super::execute(
        &payer,
        payer.account(),
        proposal.proposal_id,
        "pay",
        world.chain.tip(),
    );
    let (tx, _) = payer.last_built();
    let (height, txid) = world.chain.mine_indexed_tx(&tx, &fvk);
    world.changed();
    world.pays.push(Pay {
        seed: MAIN,
        receive: true,
        index: 0,
        value: 500_000,
        height,
        txid,
        orphaned: false,
    });
    world.mine(12);
    world.sync(0, false);
    settle(&mut world, 0);
    let account = world.devices[0].accts[0].account.clone();
    let placed = |world: &World| -> Vec<(Option<u32>, Option<i64>)> {
        rusqlite::Connection::open(&world.devices[0].wallet.path)
            .unwrap()
            .prepare(
                "SELECT t.mined_height, n.commitment_tree_position FROM ironwood_received_notes n
                 JOIN transactions t ON t.id_tx = n.transaction_id
                 WHERE n.one_time_key_id IS NOT NULL AND t.txid = ?1",
            )
            .unwrap()
            .query_map([txid], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap()
    };
    let spendable = |world: &World| {
        let wallet = &world.devices[0].wallet;
        crate::api::sync::get_balance(wallet.path.clone(), "main".into(), account.uuid.clone())
            .unwrap()
            .spendable
    };
    let before = placed(&world);
    assert_eq!(before.len(), 1, "the payment is credited once");
    assert_eq!(before[0].0, Some(height));
    let funded = spendable(&world);

    // A reorg mines the same transaction a block later, behind another output.
    let tip = world.chain.tip();
    let stranger = world.key(SECOND, true, 7);
    world.chain.rewind(height - 1);
    world.chain.pay(&stranger, 100_000, false);
    let (moved, again) = world.chain.mine_indexed_tx(&tx, &fvk);
    assert_eq!(again, txid, "the same transaction");
    world.pays.last_mut().unwrap().height = moved;
    while world.chain.tip() <= tip + 12 {
        world.chain.mine(1);
    }
    world.changed();
    world.sync(0, true);
    assert!(
        repair_owed(&world.devices[0].wallet, &account.id),
        "the receipt was displaced"
    );
    assert!(
        spendable(&world) < funded,
        "a displaced receipt is not spendable"
    );

    settle(&mut world, 0);
    world.check_step().unwrap();
    let after = placed(&world);
    assert_eq!(after.len(), 1, "still credited once: {after:?}");
    assert_eq!(after[0].0, Some(moved), "placed at the new height");
    assert!(
        after[0].1.is_some() && after[0].1 != before[0].1,
        "placed at its new tree position: {before:?} then {after:?}"
    );
    assert!(
        !repair_owed(&world.devices[0].wallet, &account.id),
        "nothing is left to repair"
    );
    assert_eq!(spendable(&world), funded, "spendable again");
}

/// A device restored with a birthday after the note that funded a
/// swap, but before the funding transaction itself, has no record of spending its own
/// note. It still learns the refund key from the funding memo and credits the refund.
#[test]
fn a_restore_between_funding_input_and_funding_recovers_the_refund() {
    if isolated("directed::a_restore_between_funding_input_and_funding_recovers_the_refund") {
        return;
    }
    let mut world = World::ready();
    let birthday = world.chain.tip() - 2;
    let restored = world.add_device(birthday, true);
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 2,
        })
        .unwrap();
    assert!(line.contains("refunded 4900000"), "{line}");
    world.mine(1);
    world.sync(restored, true);
    settle(&mut world, restored);
    let device = &world.devices[restored];
    let account = &device.accts[0].account.id;
    assert_eq!(
        funded_refunds(&device.wallet, account),
        BTreeSet::from([0]),
        "the memo names R0"
    );
    assert_eq!(
        credited(&world, restored)
            .iter()
            .filter(|n| !n.receive)
            .count(),
        1
    );
}

/// Open finding. After a reorg the provider pays a refund again in a new transaction. The
/// first refund note stays stored unmined, which keeps the key in repair, so the refund
/// key never retires even though its swap ended and its refund arrived. The library
/// ends that repair once the receipt's transaction has expired, which it learns from the
/// raw transaction.
#[test]
#[ignore = "needs the receipt's raw transaction bytes, which Vizor does not store"]
fn a_refund_replaced_by_a_reorg_still_retires() {
    if isolated("directed::a_refund_replaced_by_a_reorg_still_retires") {
        return;
    }
    let mut world = World::ready();
    world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 1,
        })
        .unwrap();
    world.mine(1);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    settle(&mut world, 0);
    let reorg = world.reorg(3);
    assert!(reorg.contains("re-sent 1 payouts"), "{reorg}");
    world.mine(12);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    settle(&mut world, 0);
    let device = &world.devices[0];
    let monitored = monitored_refunds(&device.wallet, &device.accts[0].account.id);
    assert!(monitored.is_empty(), "R0 still monitored: {monitored:?}");
}

/// The desktop hands out I0 and R0 to its swaps. The phone sees I0 paid through filters
/// and R0 funded through the memo, so it hands out I1 and R1 rather than linking its swaps
/// to the desktop's.
#[test]
fn addresses_another_device_used_are_not_handed_out() {
    if isolated("directed::addresses_another_device_used_are_not_handed_out") {
        return;
    }
    let mut world = World::ready();
    let phone = world.add_device(activation(), true);
    world.sync(phone, false);
    settle(&mut world, phone);
    let line = world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 700_000,
        })
        .unwrap();
    assert!(line.contains("paid 700000 to I0"), "{line}");
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 0,
        })
        .unwrap();
    assert!(
        line.contains("R0 quote") && line.contains("funded"),
        "{line}"
    );
    world.mine(1);
    world.sync(phone, true);
    settle(&mut world, phone);
    assert_eq!(world.reserve_in(phone, 0, false).unwrap(), Ok(1));
    let line = world.quote_out(phone, 0, 3_600).unwrap();
    assert!(line.starts_with("R1 quote"), "{line}");
}

/// A history check that finished stays finished through the rewind an account import
/// makes, so the next check starts fresh at a new frontier. A repeat payout mined after
/// the first check's frontier is credited by rounds either way.
#[test]
fn a_finished_history_check_stays_finished_after_a_rewind() {
    if isolated("directed::a_finished_history_check_stays_finished_after_a_rewind") {
        return;
    }
    let mut world = World::ready();
    let account = world.devices[0].accts[0].account.id;
    world.history_check(0).unwrap();
    assert_eq!(resumed_frontier(&world.devices[0].wallet, &account), None);
    world.act(&Action::AddNoOrchard(0)).unwrap();
    assert_eq!(
        resumed_frontier(&world.devices[0].wallet, &account),
        None,
        "the import's rewind left the check finished"
    );
    world.sync(0, false);
    world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 670_000,
        })
        .unwrap();
    let line = world
        .act(&Action::Payout {
            quote: 0,
            value: 890_000,
        })
        .unwrap();
    assert_eq!(line, "paid 890000 to I0");
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    let values: Vec<u64> = credited(&world, 0).iter().map(|n| n.value).collect();
    assert_eq!(values.len(), 2, "rounds credit the repeat: {values:?}");
    world.history_check(0).unwrap();
    assert_eq!(resumed_frontier(&world.devices[0].wallet, &account), None);
    world.quiesce().unwrap();
}

/// Whether `dev`'s first account has the use marker.
fn used(world: &World, dev: usize) -> bool {
    let device = &world.devices[dev];
    device.wallet.state(&device.accts[0].account).used
}

/// A second device restored with NEAR swap privacy off, whose account never used a
/// one-time address, makes no receiver request in rounds or filter steps while the other
/// device's incoming swap pays this seed. Turning the feature on puts the account in the
/// set, and the next rounds credit the payout from history.
#[test]
fn an_unused_device_with_the_feature_off_stays_silent() {
    if isolated("directed::an_unused_device_with_the_feature_off_stays_silent") {
        return;
    }
    let mut world = World::ready();
    let phone = world.add_device(activation(), false);
    let line = world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 700_000,
        })
        .unwrap();
    assert!(line.contains("paid 700000 to I0"), "{line}");
    world.mine(1);
    let line = world
        .act(&Action::Sync {
            dev: phone,
            enhance: true,
            step: true,
        })
        .unwrap();
    assert!(line.ends_with("needs round false, 0 requests"), "{line}");
    for _ in 0..3 {
        let publication = world.current();
        let line = world.round(phone, 0, false, publication, 0, false).unwrap();
        assert_eq!(line, "ok, more false, wait None, 0 requests");
    }
    let device = &world.devices[phone];
    let state = device.wallet.state(&device.accts[0].account);
    assert!(!state.enabled && !state.used);
    assert!(credited(&world, phone).is_empty());

    world.toggle(phone);
    settle(&mut world, phone);
    let found: Vec<(bool, u64, u64)> = credited(&world, phone)
        .iter()
        .map(|n| (n.receive, n.index, n.value))
        .collect();
    assert_eq!(found, [(true, 0, 700_000)]);
    assert!(used(&world, phone), "the found payout marks the account");
}

/// A device that never turned NEAR swap privacy on stays out of the set while the other
/// device's incoming swap pays this seed. The other device then funds an outgoing swap,
/// which this device stores from the mempool, unmined: its refund memo marks nothing.
/// Once the funding is mined, ordinary sync from compact blocks, without fetching the
/// transaction again, accepts the memo. That marks the
/// account used, registers R0 with its bootstrap lookup, and the device then credits
/// both the payout and the refund while still issuing no address.
#[test]
fn a_refund_memo_activates_an_account() {
    if isolated("directed::a_refund_memo_activates_an_account") {
        return;
    }
    let mut world = World::ready();
    let phone = world.add_device(activation(), false);
    world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 700_000,
        })
        .unwrap();
    world.mine(1);
    world.sync(phone, false);
    settle(&mut world, phone);
    assert!(credited(&world, phone).is_empty(), "outside the set");

    let line = world.quote_out(0, 0, 3_600).unwrap();
    assert!(line.starts_with("R0 quote"), "{line}");
    let line = world.fund(world.quotes.len() - 1, true);
    assert!(
        line.contains("funding R0 waits unmined, stored by 1 devices"),
        "{line}"
    );
    let account = world.devices[phone].accts[0].account.clone();
    world.sync(phone, false);
    settle(&mut world, phone);
    world.check_step().unwrap();
    assert!(!used(&world, phone), "an unmined memo marks nothing");
    assert!(funded_refunds(&world.devices[phone].wallet, &account.id).is_empty());
    assert!(world.devices[phone].wallet.queued(&account).is_empty());

    world.mine(1);
    world.sync(phone, false);
    world.check_step().unwrap();
    assert!(
        used(&world, phone),
        "the mined funding's memo marks the account"
    );
    assert_eq!(
        funded_refunds(&world.devices[phone].wallet, &account.id),
        BTreeSet::from([0])
    );
    assert!(
        world.devices[phone]
            .wallet
            .queued(&account)
            .contains(&(false, 0)),
        "R0's bootstrap lookup is queued"
    );
    let line = world
        .act(&Action::Refund {
            quote: 0,
            partial: false,
            failed: false,
        })
        .unwrap();
    assert!(line.contains("refunded 4900000 to R0"), "{line}");
    world.mine(1);
    world.sync(phone, true);
    settle(&mut world, phone);
    let found: Vec<(bool, u64, u64)> = credited(&world, phone)
        .iter()
        .map(|n| (n.receive, n.index, n.value))
        .collect();
    assert_eq!(found, [(false, 0, 4_900_000), (true, 0, 700_000)]);
    let refused = world.reserve_in(phone, 0, false).unwrap();
    assert!(refused.is_err_and(|e| e.contains("NEAR swap privacy")));
}

/// A second device learns R0 from the other device's funding memo when it syncs the
/// funding, which queues R0's bootstrap lookup. Before any round runs it, a reorg forks
/// below that lookup's target, and the provider pays the refund again on the new branch.
/// The device credits only the new branch's refund, once.
#[test]
fn a_rewind_below_a_pending_bootstrap_credits_the_new_branch() {
    if isolated("directed::a_rewind_below_a_pending_bootstrap_credits_the_new_branch") {
        return;
    }
    let mut world = World::ready();
    world.mine(6);
    let phone = world.add_device(activation(), true);
    world.sync(phone, false);
    settle(&mut world, phone);
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 2,
        })
        .unwrap();
    assert!(line.contains("refunded 4900000"), "{line}");
    world.sync(phone, true);
    let target = || -> u32 {
        rusqlite::Connection::open(&world.devices[phone].wallet.path)
            .unwrap()
            .query_row(
                "SELECT MIN(l.target_height) FROM ironwood_one_time_lookups l
                 JOIN ironwood_one_time_keys k ON k.id = l.one_time_key_id
                 WHERE k.purpose = 0 AND k.key_index = ?1 AND l.read_complete = 0",
                [0u64.to_be_bytes()],
                |r| r.get(0),
            )
            .unwrap()
    };
    let pending = target();
    let reorg = world.reorg(4);
    let fork = world.chain.tip() - 5;
    assert!(reorg.contains("re-sent 1 payouts"), "{reorg}");
    assert!(
        pending > fork,
        "the bootstrap through {pending} is above the fork at {fork}"
    );
    world.sync(phone, true);
    world.check_step().unwrap();
    settle(&mut world, phone);
    world.check_step().unwrap();
    let refunds: Vec<Note> = credited(&world, phone)
        .into_iter()
        .filter(|n| !n.receive)
        .collect();
    assert_eq!(refunds.len(), 1, "{refunds:?}");
    let canonical = world
        .pays
        .iter()
        .find(|p| !p.receive && !p.orphaned)
        .unwrap();
    assert_eq!(refunds[0].txid, canonical.txid);
}

/// Turning NEAR swap privacy off stops new addresses. The account handed out I0 and R0,
/// so it is used and stays in the set: a quote already reserved is still shown when its
/// late reply arrives, its payout and an open swap's refund are credited while off, and
/// once back on the paid and held addresses aren't issued again.
#[test]
fn turning_the_feature_off_stops_only_new_addresses() {
    if isolated("directed::turning_the_feature_off_stops_only_new_addresses") {
        return;
    }
    let mut world = World::ready();
    let line = world.quote_in(0, 0, Reply::Timeout, 3_600).unwrap();
    assert!(
        line.starts_with("I0 ") && line.contains("timed out"),
        "{line}"
    );
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 3,
        })
        .unwrap();
    assert!(line.contains("funded R0"), "{line}");
    world.toggle(0);
    for incoming in [true, false] {
        let refused = world.reserve(0, 0, incoming).unwrap();
        assert!(refused.is_err_and(|e| e.message.contains("NEAR swap privacy")));
    }
    let line = world
        .act(&Action::LateReply {
            quote: 0,
            accept: true,
        })
        .unwrap();
    assert!(line.contains("accepted and shown"), "{line}");
    for action in [
        Action::Deposit { quote: 0 },
        Action::Payout {
            quote: 0,
            value: 300_000,
        },
        Action::Refund {
            quote: 0,
            partial: true,
            failed: false,
        },
    ] {
        world.act(&action).unwrap();
    }
    world.mine(1);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    settle(&mut world, 0);
    let found: Vec<(bool, u64, u64)> = credited(&world, 0)
        .iter()
        .map(|n| (n.receive, n.index, n.value))
        .collect();
    assert_eq!(found, [(false, 0, 40_000), (true, 0, 300_000)]);
    world.toggle(0);
    assert_eq!(world.reserve_in(0, 0, false).unwrap(), Ok(1));
    world.quiesce().unwrap();
}

/// Three accounts at one frontier match one shared filter download, and each credits only
/// its own payout. A hardware account in the same wallet gets no one-time state.
#[test]
fn three_accounts_share_one_filter_download() {
    if isolated("directed::three_accounts_share_one_filter_download") {
        return;
    }
    let mut world = World::new();
    world.act(&Action::AddAccount(0)).unwrap();
    let third = world.devices[0].wallet.add_account(THIRD, activation());
    world.devices[0]
        .accts
        .push(Acct::new(third, THIRD, activation()));
    let ufvk =
        zcash_keys::keys::UnifiedSpendingKey::from_seed(&NETWORK, &[7; 32], zip32::AccountId::ZERO)
            .unwrap()
            .to_unified_full_viewing_key()
            .encode(&NETWORK);
    crate::wallet::keys::import_hardware_account(
        &world.devices[0].wallet.path,
        NETWORK,
        "Keystone",
        &ufvk,
        &[7; 32],
        0,
        Some(u64::from(activation())),
        crate::wallet::keys::HardwareSignerKind::Keystone,
    )
    .unwrap();
    world.sync(0, false);
    settle(&mut world, 0);
    let frontier = world.chain.tip();
    for (seed, value) in [(MAIN, 400_000), (SECOND, 500_000), (THIRD, 600_000)] {
        world.pay(seed, true, 0, value);
    }
    world.mine(1);
    world.sync(0, false);
    let publication = world.current();
    let service = world.service(publication.clone());
    world.round(0, 0, false, publication, 0, false).unwrap();
    let shared = format!("{}/", frontier + 1);
    let ranges = service.filter_requests();
    assert_eq!(
        ranges.iter().filter(|r| r.starts_with(&shared)).count(),
        1,
        "{ranges:?}"
    );
    settle(&mut world, 0);
    let device = &world.devices[0];
    let mut software = Vec::new();
    for (acct, value) in device.accts.iter().zip([400_000, 500_000, 600_000]) {
        let found: Vec<(u64, u64)> = mined_credit(&device.wallet, &acct.account.id)
            .iter()
            .map(|c| (c.1, c.3))
            .collect();
        assert_eq!(found, [(0, value)], "seed {}", acct.seed);
        software.push(acct.account.id.expose_uuid().as_bytes().to_vec());
    }
    let conn = rusqlite::Connection::open(&device.wallet.path).unwrap();
    for table in ["ironwood_one_time_keys", "ironwood_one_time_recovery"] {
        let owners: Vec<Vec<u8>> = conn
            .prepare(&format!(
                "SELECT DISTINCT a.uuid FROM {table} t JOIN accounts a ON a.id = t.account_id"
            ))
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        assert!(owners.iter().all(|o| software.contains(o)), "{table}");
    }
}

/// A device restored with a birthday after I0 to I4 were paid ignores those payments, so
/// its seed walk stops at I3 and it misses a later payout to I5. That's the accepted
/// limit of a late birthday. It still credits the refund of a swap funded after its
/// birthday.
#[test]
fn a_late_birthday_hides_a_payment_past_ignored_ones() {
    if isolated("directed::a_late_birthday_hides_a_payment_past_ignored_ones") {
        return;
    }
    let mut world = World::ready();
    for index in 0..5 {
        world.pay(MAIN, true, index, 100_000);
    }
    let late = world.add_device(world.chain.tip() + 1, true);
    world.pay(MAIN, true, 5, 700_000);
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 2,
        })
        .unwrap();
    assert!(line.contains("refunded 4900000"), "{line}");
    world.mine(1);
    world.sync(late, true);
    settle(&mut world, late);
    let state = world.devices[late]
        .wallet
        .state(&world.devices[late].accts[0].account);
    assert_eq!(
        state.filter_frontier.map(|f| u32::from(f.height)),
        Some(world.chain.tip())
    );
    let found: Vec<(bool, u64, u64)> = credited(&world, late)
        .iter()
        .map(|n| (n.receive, n.index, n.value))
        .collect();
    assert_eq!(found, [(false, 0, 4_900_000)]);
    world.history_check(late).unwrap();
    assert_eq!(
        credited(&world, late).len(),
        1,
        "a history check doesn't find I5"
    );
}

/// A device restored after a payment to I0 ignores it: no credit and no evidence for
/// issuance. A later payment to I1, inside the walk's first four indexes, is credited,
/// and I0 can be handed out again, as the plan accepts.
#[test]
fn a_below_birthday_payment_is_ignored_next_to_an_eligible_one() {
    if isolated("directed::a_below_birthday_payment_is_ignored_next_to_an_eligible_one") {
        return;
    }
    let mut world = World::ready();
    world.pay(MAIN, true, 0, 100_000);
    let late = world.add_device(world.chain.tip() + 1, true);
    world.pay(MAIN, true, 1, 700_000);
    world.mine(1);
    world.sync(late, false);
    settle(&mut world, late);
    world.check_step().unwrap();
    let found: Vec<(bool, u64, u64)> = credited(&world, late)
        .iter()
        .map(|n| (n.receive, n.index, n.value))
        .collect();
    assert_eq!(found, [(true, 1, 700_000)]);
    assert_eq!(world.reserve_in(late, 0, false).unwrap(), Ok(0));
}

/// A dense prefix: after the account's first walk, I0 to I11 are paid in twelve blocks in
/// a row and filter ranges end after three heights, so payments sit on both sides of each
/// page boundary. Rounds run while they report more work, follow the pages to the tip and
/// walk the receive window past every payment.
#[test]
fn a_dense_prefix_is_walked_to_the_end() {
    if isolated("directed::a_dense_prefix_is_walked_to_the_end") {
        return;
    }
    let mut world = World::ready();
    let frontier = world.chain.tip();
    for index in 0..12 {
        world.pay(MAIN, true, index, 100_000 + index);
    }
    world.mine(1);
    world.sync(0, false);
    let service = world.service(world.current());
    service.cap_ranges(3);
    let path = world.devices[0].wallet.path.clone();
    for round in 0.. {
        assert!(round < 20, "rounds still report more work");
        if !run_worker(&path, &*service, false, None, Duration::from_secs(45))
            .unwrap()
            .more
        {
            break;
        }
    }
    let ranges = service.filter_requests();
    let pages = ranges
        .iter()
        .filter(|r| r.split('/').next().unwrap().parse::<u32>().unwrap() > frontier)
        .count();
    assert!(pages > 1, "{ranges:?}");
    let state = world.devices[0]
        .wallet
        .state(&world.devices[0].accts[0].account);
    assert_eq!(
        state.filter_frontier.map(|f| u32::from(f.height)),
        Some(world.chain.tip())
    );
    let indexes: Vec<u64> = credited(&world, 0).iter().map(|n| n.index).collect();
    assert_eq!(indexes, (0..12).collect::<Vec<_>>());
}

/// A device finds a direct payment to I0, whose walk enrolls I1 to I4. A reorg then drops
/// I0, which nobody pays again. A later payment to I4, past the four empties a walk from
/// scratch would stop at, is still credited, since enrollment outlasts the reorg.
#[test]
fn a_reorg_keeps_an_enrolled_address_watched() {
    if isolated("directed::a_reorg_keeps_an_enrolled_address_watched") {
        return;
    }
    let mut world = World::ready();
    world
        .act(&Action::DirectPay {
            second: false,
            index: 0,
        })
        .unwrap();
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    world.check_step().unwrap();
    assert_eq!(credited(&world, 0).len(), 1);
    let account = world.devices[0].accts[0].account.id;
    assert!(receive_end(&world.devices[0].wallet, &account) >= 5);
    let reorg = world.reorg(3);
    assert!(reorg.contains("re-sent 0 payouts"), "{reorg}");
    world.sync(0, false);
    settle(&mut world, 0);
    world.check_step().unwrap();
    assert!(credited(&world, 0).is_empty(), "I0 was orphaned");

    world.pay(MAIN, true, 4, 400_000);
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    let found: Vec<(bool, u64, u64)> = credited(&world, 0)
        .iter()
        .map(|n| (n.receive, n.index, n.value))
        .collect();
    assert_eq!(found, [(true, 4, 400_000)]);
    world.quiesce().unwrap();
}

/// A device restored after the only payment to I0 ignores it entirely: rounds finish its
/// walk without storing a candidate, reading a witness or setting the use marker, and
/// later rounds don't read the old record again. A later payment to the same I0, after
/// the birthday, is credited alone and marks the account.
#[test]
fn an_old_payment_alone_leaves_no_trace() {
    if isolated("directed::an_old_payment_alone_leaves_no_trace") {
        return;
    }
    let mut world = World::ready();
    world.pay(MAIN, true, 0, 100_000);
    let late = world.add_device(world.chain.tip() + 1, true);
    world.mine(1);
    world.sync(late, false);
    let service = world.service(world.current());
    settle(&mut world, late);
    world.check_step().unwrap();
    let account = world.devices[late].accts[0].account.clone();
    let wallet = &world.devices[late].wallet;
    assert!(candidates(wallet, &account.id).is_empty());
    let state = wallet.state(&account);
    assert!(!state.used && state.restore_complete);
    assert!(wallet.queued(&account).is_empty(), "every lookup completed");
    let queries = service.queries();
    assert!(queries > 0, "the walk read I0's history");
    settle(&mut world, late);
    assert_eq!(
        service.queries(),
        queries,
        "the old record isn't read again"
    );

    world.pay(MAIN, true, 0, 900_000);
    world.mine(1);
    world.sync(late, false);
    settle(&mut world, late);
    world.check_step().unwrap();
    let found: Vec<(bool, u64, u64)> = credited(&world, late)
        .iter()
        .map(|n| (n.receive, n.index, n.value))
        .collect();
    assert_eq!(found, [(true, 0, 900_000)]);
    assert!(used(&world, late));
}

/// A history check the app stops after it started leaves every account's job saved,
/// with NEAR swap privacy off. After a restart, ordinary rounds carry each job to its
/// end, and they find the payment the check was for.
#[test]
fn an_interrupted_history_check_finishes_through_rounds_and_a_restart() {
    if isolated("directed::an_interrupted_history_check_finishes_through_rounds_and_a_restart") {
        return;
    }
    let mut world = World::new();
    world.toggle(0);
    world.act(&Action::AddAccount(0)).unwrap();
    world.pay(SECOND, true, 0, 600_000);
    world.mine(1);
    world.sync(0, false);
    let line = world.manual(0, Some((0, false))).unwrap();
    assert!(line.starts_with("manual stopped true"), "{line}");
    assert!(world.devices[0].accts.iter().all(|a| a.job));
    world.check_step().unwrap();
    world.restart(0);
    world.check_step().unwrap();
    for _ in 0..8 {
        if !world.devices[0].accts.iter().any(|a| a.job) {
            break;
        }
        settle(&mut world, 0);
        world.check_step().unwrap();
    }
    let device = &world.devices[0];
    for acct in &device.accts {
        assert!(!acct.job, "seed {}'s job ended", acct.seed);
        let (_, active, finished, _) = manual_job(&device.wallet, &acct.account.id);
        assert!(!active && finished, "seed {}", acct.seed);
    }
    let second = device.accts.iter().find(|a| a.seed == SECOND).unwrap();
    let found: Vec<(u64, u64)> = mined_credit(&device.wallet, &second.account.id)
        .iter()
        .map(|c| (c.1, c.3))
        .collect();
    assert_eq!(found, [(0, 600_000)]);
}

/// Seed 400046: a refund a reorg orphans stays stored unmined on the device that saw it.
/// Once its unknown expiry passes, 40 blocks after it was first seen, the balance drops
/// it, so a device restored afterwards, which never saw it, must agree on the rest.
#[test]
fn an_expired_orphaned_refund_keeps_balances_equal() {
    if isolated("directed::an_expired_orphaned_refund_keeps_balances_equal") {
        return;
    }
    let mut world = World::ready();
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 1,
        })
        .unwrap();
    assert!(line.contains("refunded 40000"), "{line}");
    world.mine(1);
    world.sync(0, true);
    settle(&mut world, 0);
    let reorg = world.reorg(3);
    assert!(reorg.contains("re-sent 1 payouts"), "{reorg}");
    world.sync(0, true);
    settle(&mut world, 0);
    let device = &world.devices[0];
    let orphaned = notes(&device.wallet, &device.accts[0].account.id)
        .into_iter()
        .filter(|n| !n.mined)
        .count();
    assert_eq!(orphaned, 1, "device 0 keeps the orphaned refund unmined");
    world.mine(45);
    world.add_device(activation(), true);
    world.quiesce().unwrap();
}
