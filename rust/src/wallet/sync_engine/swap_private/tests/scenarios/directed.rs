//! Directed scenarios for promises the random harness reaches rarely or not at all.
use super::*;

/// Runs the world's default round on `dev` and fails on any violation.
fn settle(world: &mut World, dev: usize) {
    for _ in 0..4 {
        let publication = world.current();
        world.round(dev, 0, false, publication, 0, None).unwrap();
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
/// monitoring each one until filters have checked more than [`MEMO_REFUND_WINDOW`] past
/// its funding, then retires it too.
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
    let funded: Vec<u32> = world.fundings.iter().map(|f| f.height).collect();
    assert_eq!(funded.len(), 2);
    // With filters through exactly one window past R1's funding, only R0 is older.
    world.mine(funded[1] + MEMO_REFUND_WINDOW - world.chain.tip());
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

/// Private addresses need both Private queries and NEAR swap privacy.
#[test]
fn private_addresses_need_both_switches() {
    if isolated("directed::private_addresses_need_both_switches") {
        return;
    }
    let mut world = World::ready();
    world.devices[0].queries = false;
    world.toggled(0);
    let refused = world.reserve_in(0, 0, false).unwrap();
    assert!(refused.is_err_and(|e| e.contains("Enable Private queries")));
    world.devices[0].queries = true;
    world.toggled(0);
    assert_eq!(world.reserve_in(0, 0, false).unwrap(), Ok(0));
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
    let reserve = |world: &World| {
        let device = &world.devices[0];
        crate::api::one_time_ivk::reserve_swap_address(
            device.wallet.path.clone(),
            "main".into(),
            device.accts[0].account.uuid.clone(),
            true,
            world.chain.tip().into(),
        )
        .map(|address| address.reservation_index)
        .map_err(|e| e.kind)
    };
    world.act(&Action::Warp(3_600 + 23 * 3_600)).unwrap();
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    assert_eq!(
        reserve(&world),
        Err(crate::api::one_time_ivk::ReceiveErrorKind::Limit),
        "23 hours past the deadline the slots are still held"
    );
    world.act(&Action::Warp(2 * 3_600)).unwrap();
    world.mine(1);
    world.sync(0, false);
    assert_eq!(
        reserve(&world),
        Ok(Some(0)),
        "25 hours past the deadline the lowest slot is free"
    );
}

/// With the feature off, a receipt a reorg displaced still gets repair lookups, so the
/// round makes receiver requests. This is intended. Here the provider pays again in a
/// new transaction, which a paused account does not admit: the history read finishes,
/// the old receipt stays unmined and nothing new is credited until the feature is back
/// on. Once the read is done, rounds make no request.
#[test]
fn a_feature_off_round_reads_a_replaced_receipts_history() {
    if isolated("directed::a_feature_off_round_reads_a_replaced_receipts_history") {
        return;
    }
    let mut world = World::ready();
    world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 500_000,
        })
        .unwrap();
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    let account = world.devices[0].accts[0].account.clone();
    assert_eq!(credited(&world, 0).len(), 1, "the receipt is credited");
    world.devices[0].feature = false;
    world.toggled(0);
    let reorg = world.reorg(3);
    assert!(reorg.contains("re-sent 1 payouts"), "{reorg}");
    world.mine(12);
    world.sync(0, true);
    assert!(
        repair_owed(&world.devices[0].wallet, &account.id),
        "the reorg displaced the receipt"
    );
    assert!(
        !world.devices[0].wallet.state(&account).lookups.is_empty(),
        "repair is due while the feature is off"
    );
    // The first feature-off round reads the displaced receipt's history. Once that
    // repair is done a round has no work and makes no request.
    let mut repaired = false;
    for round in 0..3 {
        let publication = world.current();
        let service = world.service(publication);
        let requests = service.count("inventory") + service.queries();
        let result = run_worker(
            &world.devices[0].wallet.path,
            &*service,
            None,
            Duration::from_secs(45),
        );
        let active = match result {
            Ok(r) => r.active,
            Err(e) => panic!("round {round}: {e}"),
        };
        let made = service.count("inventory") + service.queries() - requests;
        if round == 0 {
            assert!(active, "the first round has repair work");
            assert!(service.queries() > 0, "it queried the receipt's key");
        }
        if !active {
            assert_eq!(made, 0, "round {round}: no work, no request");
            repaired = true;
        }
        world.check_step().unwrap();
    }
    assert!(repaired, "the history read finished");
    assert!(
        world.devices[0].wallet.state(&account).lookups.is_empty(),
        "no repair is left"
    );
    let notes = notes(&world.devices[0].wallet, &account.id);
    assert_eq!(
        notes.len(),
        1,
        "the replacement is not admitted while off: {notes:?}"
    );
    assert!(!notes[0].mined, "the replaced receipt stays unmined");
}

/// With the feature off, a receipt a reorg moved is repaired. The same payment
/// transaction mined again a block later, after an unrelated output that shifts its tree
/// position, is placed again with its new height and position, keeps its single credit
/// and is spendable again, all without turning the feature back on.
#[test]
fn a_feature_off_round_restores_a_receipt_a_reorg_moved() {
    if isolated("directed::a_feature_off_round_restores_a_receipt_a_reorg_moved") {
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

    // Off. A reorg mines the same transaction a block later, behind another output.
    world.devices[0].feature = false;
    world.toggled(0);
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

    for round in 0..4 {
        let publication = world.current();
        let service = world.service(publication);
        let result = run_worker(
            &world.devices[0].wallet.path,
            &*service,
            None,
            Duration::from_secs(45),
        );
        assert!(
            result.is_ok(),
            "round {round}: {:?}",
            result.map(|r| r.active).map_err(|e| e.to_string())
        );
        world.check_step().unwrap();
    }
    assert!(!world.devices[0].discovery(), "the feature stayed off");
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

/// Control for the reorg test: an ordinary payment whose block a reorg drops, and which
/// is not mined again, also stays in the pending total and never becomes spendable. So a
/// lingering orphaned value is not specific to one-time receipts.
#[test]
fn an_orphaned_ordinary_payment_stays_pending() {
    if isolated("directed::an_orphaned_ordinary_payment_stays_pending") {
        return;
    }
    let mut world = World::new();
    world.sync(0, false);
    let account = world.devices[0].accts[0].account.clone();
    let before = world.devices[0].wallet.balance(&account);
    world.chain.pay(&account.parent(), 700_000, false);
    world.changed();
    world.mine(1);
    world.sync(0, false);
    assert_eq!(world.devices[0].wallet.balance(&account), before + 700_000);
    world.reorg(3);
    world.mine(12);
    world.sync(0, true);
    let wallet = &world.devices[0].wallet;
    let b = crate::api::sync::get_balance(wallet.path.clone(), "main".into(), account.uuid.clone())
        .unwrap();
    assert_eq!(b.spendable, before);
    assert_eq!(b.total, before + 700_000);
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

/// Outside the one-time feature, a wallet restored a few blocks below
/// the tip follows a shallow reorg that forks inside its scanned range, with an unrelated
/// Ironwood output in the block the reorg drops, so the commitment tree changes above the
/// fork. The wallet used to refuse every rewind, even to the safe height it reported.
#[test]
fn a_recent_restore_follows_a_shallow_reorg_over_an_ironwood_output() {
    if isolated("directed::a_recent_restore_follows_a_shallow_reorg_over_an_ironwood_output") {
        return;
    }
    let mut world = World::new();
    world.mine(4);
    let birthday = world.chain.tip() - 3;
    let restored = world.add_device(birthday, false);
    let stranger = world.key(SECOND, true, 7);
    world.chain.pay(&stranger, 100_000, false);
    world.changed();
    world.sync(restored, false);
    world.reorg(2);
    let line = world.sync(restored, false);
    assert!(!world.devices[restored].broken, "{line}");
}

/// Open finding outside the one-time feature. A wallet restored a block below the tip
/// starts from the tree state below its birthday. A reorg that replaces that block leaves
/// the stored starting state on the old branch, so the wallet refuses the new branch's
/// blocks even after rewinding as far as it can.
#[test]
#[ignore = "a reorg below a recent birthday leaves the wallet unable to scan"]
fn a_recent_restore_follows_a_reorg_below_its_birthday() {
    if isolated("directed::a_recent_restore_follows_a_reorg_below_its_birthday") {
        return;
    }
    let mut world = World::new();
    world.mine(4);
    let birthday = world.chain.tip();
    let restored = world.add_device(birthday, false);
    world.sync(restored, false);
    // A two-block reorg whose new branch has an unrelated Ironwood output below the
    // birthday, so the tree state there changes.
    let stranger = world.key(SECOND, true, 7);
    world.chain.rewind(birthday - 2);
    world.chain.pay(&stranger, 100_000, false);
    world.mine(3);
    let line = world.sync(restored, false);
    assert!(!world.devices[restored].broken, "{line}");
}

/// The restored device of
/// [`a_restore_between_funding_input_and_funding_recovers_the_refund`] must learn that the
/// phone already funded refund key R0, so its own next ZEC deposit quote does not reserve
/// R0 again and link the two swaps.
#[test]
fn a_restored_device_never_reuses_a_funded_refund_key() {
    if isolated("directed::a_restored_device_never_reuses_a_funded_refund_key") {
        return;
    }
    let mut world = World::new();
    world.act(&Action::AddAccount(0)).unwrap();
    world.sync(0, false);
    settle(&mut world, 0);
    let birthday = world.chain.tip() - 2;
    let restored = world.add_device(birthday, true);
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
    world.sync(restored, true);
    settle(&mut world, restored);
    let before = world.quotes.len();
    let line = world.quote_out(restored, 0, 3_600).unwrap();
    assert_eq!(
        world.quotes.len(),
        before + 1,
        "the restored device recorded a refund quote: {line}"
    );
    let quote = &world.quotes[before];
    assert!(quote.dev == restored && !quote.incoming);
    assert_eq!(
        quote.index, 1,
        "the restored device reserved R1, not R0: {line}"
    );
}

/// The toggle seed 3000213, shrunk to ten actions. Its history check finishes, then the
/// rewind that importing an account makes reopens it. The next check resumes it under
/// its first frontier, so it misses the repeat I0 payment mined after that (spec MAN-4),
/// which the harness took for a credit mismatch. A new check then finds it.
#[test]
fn a_history_check_reopened_by_a_rewind_keeps_its_frontier() {
    if isolated("directed::a_history_check_reopened_by_a_rewind_keeps_its_frontier") {
        return;
    }
    let mut world = World::new();
    world.sync(0, false);
    let publication = world.current();
    world.round(0, 0, false, publication, 0, None).unwrap();
    let account = world.devices[0].accts[0].account.id;
    let held = |dev, class, nth, cancel| Action::HeldToggle {
        dev,
        class,
        nth,
        cancel,
        back: true,
    };
    let mut frontier = None;
    for (step, action) in [
        Action::Manual {
            dev: 3,
            bound: None,
            cancel: None,
        },
        Action::Status {
            quote: 8,
            change: Change::Done,
        },
        held(7, 3, 1, false),
        Action::AddNoOrchard(0),
        held(6, 0, 0, true),
        Action::Enhance(7),
        Action::Swap {
            dev: 3,
            acct: 2,
            value: 670_000,
        },
        Action::Payout {
            quote: 3,
            value: 890_000,
        },
        Action::QuoteOut {
            dev: 3,
            acct: 2,
            ttl: 6435,
        },
        held(6, 3, 0, false),
    ]
    .iter()
    .enumerate()
    {
        world.act(action).unwrap();
        world.check_step().unwrap();
        let reopened = resumed_frontier(&world.devices[0].wallet, &account);
        match step {
            0 => {
                assert_eq!(reopened, None, "the check finished");
                frontier = Some(world.chain.tip());
            }
            3 => assert_eq!(reopened, frontier, "the import's rewind reopened the check"),
            _ => {}
        }
    }
    let frontier = frontier.unwrap();
    let repeat = world.pays.last().unwrap();
    assert!(repeat.receive && repeat.index == 0 && repeat.height > frontier);
    let repeat = repeat.txid;
    let paid = |world: &World| credited(world, 0).iter().any(|n| n.txid == repeat);
    assert!(!paid(&world), "only a history check finds the repeat");

    world.history_check(0).unwrap();
    assert!(!paid(&world), "the resumed check stops at its frontier");
    assert!(world.only_missed_after_frontier(0, &[Some(frontier)]));
    world.history_check(0).unwrap();
    assert!(paid(&world), "a new check finds the repeat");
    world.quiesce().unwrap();
}
