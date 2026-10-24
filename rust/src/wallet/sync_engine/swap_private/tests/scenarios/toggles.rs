//! Directed scenarios for turning NEAR swap privacy on and off: with work pending, in
//! the middle of a round or a history check, across an app restart, with a private swap
//! open, with several kinds of accounts and in quick succession.
use super::*;
use crate::api::one_time_ivk as api;

/// A world whose first device has synced and settled with the feature on.
fn world() -> World {
    let mut world = World::new();
    world.sync(0, false);
    settle(&mut world, 0);
    world
}

/// Runs four default rounds on `dev`, failing on any violation.
fn settle(world: &mut World, dev: usize) {
    for _ in 0..4 {
        let publication = world.current();
        world.round(dev, 0, false, publication, 0, None).unwrap();
    }
}

/// Turns NEAR swap privacy on `dev` on or off and reconciles its wallet, as the
/// settings toggle does.
fn set_feature(world: &mut World, dev: usize, on: bool) {
    world.devices[dev].feature = on;
    world.toggled(dev);
}

/// One default round on `dev` through a counting transport: its outcome and how many
/// receiver requests it made.
fn counted_round(world: &mut World, dev: usize) -> (Result<Round, RecoveryError>, usize) {
    apply(&world.devices[dev]);
    let publication = world.current();
    let service = world.service(publication);
    let counting = Faulty {
        service: &service,
        rng: Mutex::new(Rng::new(0)),
        fail: 0,
        requests: AtomicUsize::new(0),
    };
    let result = run_worker(
        &world.devices[dev].wallet.path,
        &counting,
        None,
        Duration::from_secs(45),
    );
    (result, counting.requests.load(AtomicOrdering::SeqCst))
}

/// The mined one-time notes of account `acct` on `dev` as (receive, index, value).
fn credited(world: &World, dev: usize, acct: usize) -> BTreeSet<(bool, u64, u64)> {
    let device = &world.devices[dev];
    notes(&device.wallet, &device.accts[acct].account.id)
        .into_iter()
        .filter(|n| n.mined)
        .map(|n| (n.receive, n.index, n.value))
        .collect()
}

/// The quote index of the `I{index}` quote line `quote_in` returned.
fn quote_of(line: &str) -> usize {
    line.split("quote ")
        .nth(1)
        .and_then(|rest| rest.split(':').next())
        .and_then(|n| n.trim().parse().ok())
        .unwrap_or_else(|| panic!("not a quote line: {line}"))
}

/// The provider sees a deposit for quote `q`, by its index in the world's quotes.
fn deposit(world: &mut World, q: usize) {
    let quote = &mut world.quotes[q];
    assert!(
        quote.incoming && quote.started && !quote.funded,
        "{quote:?}"
    );
    quote.funded = true;
    quote.status = "PROCESSING";
}

/// The provider pays out `value` for the deposited incoming quote `q`, by its index in
/// the world's quotes, as [`Action::Payout`] does.
fn payout(world: &mut World, q: usize, value: u64) {
    let (seed, index) = (world.quotes[q].seed, world.quotes[q].index);
    assert!(world.quotes[q].funded);
    let txid = world.pay(seed, true, index, value);
    let quote = &mut world.quotes[q];
    quote.status = "SUCCESS";
    quote.amount_out = Some(quote.amount_out.unwrap_or(0) + value);
    quote.hashes.push(txid);
    quote.owed.push((value, txid));
}

/// What turning the feature off and on must keep on one account.
#[derive(Debug, PartialEq)]
struct Kept {
    /// Every one-time note with its spend state.
    notes: Vec<Note>,
    /// Every derived key as (purpose, index, receiver).
    keys: BTreeSet<(u8, u64, Vec<u8>)>,
    /// The seed walk, receive window and filter frontier, as stored.
    progress: Vec<rusqlite::types::Value>,
    /// Keys whose history lookup completed, with the height it completed through.
    completed: BTreeSet<(u8, u64, u32)>,
    /// Receive indexes a live reservation holds.
    reserved: BTreeSet<u64>,
    /// Refund indexes with funding evidence.
    funded: BTreeSet<u64>,
}

impl Kept {
    /// Reads what account `acct` on `dev` keeps.
    fn of(world: &World, dev: usize, acct: usize) -> Self {
        let device = &world.devices[dev];
        let account = &device.accts[acct].account.id;
        let uuid = account.expose_uuid().as_bytes().to_vec();
        let conn = rusqlite::Connection::open(&device.wallet.path).unwrap();
        let index = |bytes: [u8; 8]| u64::from_be_bytes(bytes);
        let keys = conn
            .prepare(
                "SELECT k.purpose, k.key_index, k.receiver FROM ironwood_one_time_keys k
                 JOIN accounts a ON a.id = k.account_id WHERE a.uuid = ?1",
            )
            .unwrap()
            .query_map([&uuid], |r| Ok((r.get(0)?, index(r.get(1)?), r.get(2)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let progress = conn
            .query_row(
                "SELECT r.restore_next, r.restore_gap, r.restore_done, r.receive_end,
                     r.filter_height, r.filter_hash, r.skipped_height
                 FROM ironwood_one_time_recovery r JOIN accounts a ON a.id = r.account_id
                 WHERE a.uuid = ?1",
                [&uuid],
                |r| {
                    (0..7)
                        .map(|i| r.get::<_, rusqlite::types::Value>(i))
                        .collect::<Result<Vec<_>, _>>()
                },
            )
            .unwrap();
        let completed = conn
            .prepare(
                "SELECT k.purpose, k.key_index, l.done_height FROM ironwood_one_time_lookups l
                 JOIN ironwood_one_time_keys k ON k.id = l.one_time_key_id
                 JOIN accounts a ON a.id = k.account_id
                 WHERE a.uuid = ?1 AND l.read_complete = 1 AND l.done_height IS NOT NULL",
            )
            .unwrap()
            .query_map([&uuid], |r| Ok((r.get(0)?, index(r.get(1)?), r.get(2)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let reserved = conn
            .prepare(
                "SELECT k.key_index FROM ironwood_one_time_keys k
                 JOIN accounts a ON a.id = k.account_id
                 WHERE a.uuid = ?1 AND k.purpose = 1
                   AND k.reserved_at IS NOT NULL AND k.released_at IS NULL",
            )
            .unwrap()
            .query_map([&uuid], |r| Ok(index(r.get(0)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        let mut notes = notes(&device.wallet, account);
        notes.sort();
        Self {
            notes,
            keys,
            progress,
            completed,
            reserved,
            funded: funded_refunds(&device.wallet, account),
        }
    }
}

/// Answers public reads but fails every encrypted query, so a round defers its lookups.
struct FailingQueries<'a>(&'a Service);

impl Transport for FailingQueries<'_> {
    /// A public read from the service.
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, session::Error> {
        self.0.get(url, limit).await
    }
    /// An encrypted query that always fails.
    async fn post(
        &self,
        _url: &str,
        _body: Vec<u8>,
        _limit: usize,
    ) -> Result<Vec<u8>, session::Error> {
        Err(session::Error::Transport("injected failure".into()))
    }
}

/// Off to on with work already pending: a credited receipt a reorg displaced while the
/// feature was off, a live reservation, and a payment whose lookup failed and was
/// deferred. Turning the feature back on resumes all of it. Each payment is credited
/// exactly once from the current branch, and the held and paid addresses are not issued
/// again.
#[test]
fn off_to_on_resumes_pending_work_once() {
    if isolated("toggles::off_to_on_resumes_pending_work_once") {
        return;
    }
    let mut world = world();
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
    assert_eq!(credited(&world, 0, 0), BTreeSet::from([(true, 0, 700_000)]));

    // I1 is quoted, deposited and paid, but every encrypted query of the next round fails,
    // so its lookup is deferred rather than settled as empty.
    let line = world.quote_in(0, 0, Reply::Accept, 3 * 86_400).unwrap();
    assert!(line.starts_with("I1 ") && line.contains("shown"), "{line}");
    deposit(&mut world, 1);
    payout(&mut world, 1, 300_000);
    world.sync(0, false);
    let publication = world.current();
    let service = world.service(publication);
    let failed = run_worker(
        &world.devices[0].wallet.path,
        &FailingQueries(&service),
        None,
        Duration::from_secs(45),
    );
    assert!(failed.is_err(), "the failed query fails the round");
    let account = world.devices[0].accts[0].account.clone();
    assert!(world.devices[0]
        .wallet
        .queued(&account)
        .contains(&(true, 1)));
    let attempts: i64 = rusqlite::Connection::open(&world.devices[0].wallet.path)
        .unwrap()
        .query_row(
            "SELECT l.attempts FROM ironwood_one_time_lookups l
             JOIN ironwood_one_time_keys k ON k.id = l.one_time_key_id
             WHERE k.purpose = 1 AND k.key_index = ?1",
            [1u64.to_be_bytes()],
            |r| r.get(0),
        )
        .unwrap();
    assert!(attempts > 0, "the lookup is deferred");
    // I2 is a live started quote, so its reservation is held.
    let line = world.quote_in(0, 0, Reply::Accept, 3 * 86_400).unwrap();
    assert!(line.starts_with("I2 ") && line.contains("shown"), "{line}");

    // Off. A reorg then displaces I0's credited receipt and drops I1's payout, and the
    // provider pays both again on the new branch.
    set_feature(&mut world, 0, false);
    let reorg = world.reorg(3);
    assert!(reorg.contains("re-sent 2 payouts"), "{reorg}");
    world.mine(1);
    world.sync(0, true);
    assert!(repair_owed(&world.devices[0].wallet, &account.id));
    for _ in 0..2 {
        let (result, _) = counted_round(&mut world, 0);
        result.unwrap();
        world.check_step().unwrap();
    }
    let reserved = Kept::of(&world, 0, 0).reserved;
    assert!(
        reserved.contains(&2),
        "the live reservation survives: {reserved:?}"
    );

    // On again: every pending piece resumes once its backoff passes.
    set_feature(&mut world, 0, true);
    assert_eq!(Kept::of(&world, 0, 0).reserved, reserved);
    world.act(&Action::Warp(PAST_BACKOFF)).unwrap();
    world.mine(1);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    settle(&mut world, 0);
    world.check_step().unwrap();
    assert_eq!(
        credited(&world, 0, 0),
        BTreeSet::from([(true, 0, 700_000), (true, 1, 300_000)]),
        "each payment is credited once"
    );
    let current: BTreeSet<[u8; 32]> = world
        .pays
        .iter()
        .filter(|p| !p.orphaned)
        .map(|p| p.txid)
        .collect();
    let device = &world.devices[0];
    for note in notes(&device.wallet, &account.id)
        .iter()
        .filter(|n| n.mined)
    {
        assert!(
            current.contains(&note.txid),
            "{note:?} is from the new branch"
        );
    }
    assert_eq!(
        world.reserve_in(0, 0, false).unwrap(),
        Ok(3),
        "paid I0 and I1 and the held I2 are not issued again"
    );
    world.quiesce().unwrap();
}

/// On to off in the middle of a round: whichever request is held, a block filter batch,
/// a sealed shard's filter, an encrypted payment query or a witness read, turning the
/// feature off rejects its
/// answer, both through the wallet's fence alone and with the app's worker cancellation.
/// Nothing new is written, the pending payment stays queued, and from then on the wallet
/// is inert through sync, rounds and every app entry point: no receiver request and no
/// change to any one-time row. Turning the feature back on credits the payment once.
#[test]
fn on_to_off_mid_round_rejects_held_answers_and_stays_inert() {
    if isolated("toggles::on_to_off_mid_round_rejects_held_answers_and_stays_inert") {
        return;
    }
    // A held filter must reach the round however long this thread takes to release it.
    super::super::super::UNBOUNDED_FILTER_WAITS.store(true, AtomicOrdering::SeqCst);
    for class in ["filters", "shard-filter", "query", "witness"] {
        for cancel in [false, true] {
            let mut world = world();
            world
                .act(&Action::Swap {
                    dev: 0,
                    acct: 0,
                    value: 700_000,
                })
                .unwrap();
            world.mine(1);
            world.sync(0, false);
            // A sealed shard, so the round screens its lookups with the shard's filter.
            let publication = world.publication(0, false, class == "shard-filter", false, 0);
            let service = world.service(publication);
            let nth = service.count(class);
            let held = service.hold(class, nth);
            let worker = world.devices[0]
                .wallet
                .spawn(&service, None, Duration::from_secs(45));
            held.wait();
            set_feature(&mut world, 0, false);
            if cancel {
                cancel_recovery();
            }
            let account = world.devices[0].accts[0].account.clone();
            let before = one_time_snapshot(&world.devices[0].wallet);
            // A shard filter may be fetched for a later lookup after the payment's own.
            let credited_before = credited(&world, 0, 0);
            held.release();
            let result = worker.join().unwrap();
            // A filter the round stopped waiting for is never answered, which would let
            // this pass without delivering the answer it means to reject.
            assert!(
                service.requests_of(class)[nth].1 > 0,
                "{class} cancel {cancel}: the held answer was delivered to the round"
            );
            if cancel {
                assert!(
                    result
                        .as_ref()
                        .is_err_and(|e| e.to_string().contains("cancelled")),
                    "{class}: {:?}",
                    result.map(|r| r.active)
                );
            }
            let after = one_time_snapshot(&world.devices[0].wallet);
            assert_eq!(
                before,
                after,
                "{class} cancel {cancel}: {}",
                snapshot_diff(&before, &after)
            );
            assert_eq!(
                credited(&world, 0, 0),
                credited_before,
                "{class}: nothing more credited"
            );
            if class == "query" {
                assert!(
                    world.devices[0]
                        .wallet
                        .queued(&account)
                        .contains(&(true, 0)),
                    "the rejected answer was not settled as empty"
                );
            }

            // Inert: ordinary sync, rounds and the app's entry points request and write
            // nothing.
            let path = world.devices[0].wallet.path.clone();
            let untouched = |world: &World, step: &str| {
                let now = one_time_snapshot(&world.devices[0].wallet);
                assert!(
                    now == after,
                    "{class} cancel {cancel}: {step} wrote while off: {}",
                    snapshot_diff(&after, &now)
                );
            };
            for _ in 0..3 {
                world.mine(1);
                world.sync(0, true);
                untouched(&world, "ordinary sync");
                let (result, requests) = counted_round(&mut world, 0);
                assert!(!result.unwrap().active, "{class}: no work while off");
                assert_eq!(requests, 0, "{class}: no receiver request while off");
                untouched(&world, "a round");
                assert!(!api::run_swap_recovery(path.clone(), "main".into()).unwrap());
                untouched(&world, "the production round");
                let status = api::get_swap_recovery_status(path.clone(), "main".into()).unwrap();
                assert!(!status.checking_history && !status.upgrade_required);
                for incoming in [true, false] {
                    let refused = api::reserve_swap_address(
                        path.clone(),
                        "main".into(),
                        account.uuid.clone(),
                        incoming,
                        world.chain.tip().into(),
                    );
                    assert!(refused.is_err(), "issuance is paused");
                }
                untouched(&world, "a reservation");
                assert!(api::check_swap_history(path.clone(), "main".into()).is_err());
                api::reconcile_swap_recovery(path.clone(), "main".into()).unwrap();
                untouched(&world, "reconciling");
            }

            set_feature(&mut world, 0, true);
            settle(&mut world, 0);
            world.check_step().unwrap();
            assert_eq!(
                credited(&world, 0, 0),
                BTreeSet::from([(true, 0, 700_000)]),
                "{class} cancel {cancel}: credited once after turning back on"
            );
        }
    }
}

/// On, off, on keeps everything the feature knew: notes, keys, the receive window, the
/// seed walk and filter progress, completed history lookups, live reservations and funded
/// refund keys, with nothing reissued. Payments that arrive while it is off are found
/// once it is back on, as far as the design allows: a payout to an address this device
/// reserved and a payout to an address another device issued in this device's lookahead
/// automatically, and a repeat payment to a completed address automatically when the
/// round reads filters, or else by the history check.
#[test]
fn on_off_on_keeps_state_and_recovers_payments_made_while_off() {
    if isolated("toggles::on_off_on_keeps_state_and_recovers_payments_made_while_off") {
        return;
    }
    let mut world = world();
    world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 500_000,
        })
        .unwrap();
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 1,
        })
        .unwrap();
    assert!(line.contains("refunded 40000"), "{line}");
    world.mine(12);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    settle(&mut world, 0);
    let other = world.add_device(activation(), true);
    world.sync(other, true);
    settle(&mut world, other);
    let line = world.quote_in(0, 0, Reply::Accept, 3 * 86_400).unwrap();
    assert!(line.starts_with("I1 ") && line.contains("shown"), "{line}");
    let i1 = quote_of(&line);

    // Toggling alone changes nothing the feature keeps.
    let kept = Kept::of(&world, 0, 0);
    assert!(
        kept.reserved.contains(&1) && kept.funded.contains(&0),
        "{kept:?}"
    );
    for _ in 0..3 {
        set_feature(&mut world, 0, false);
        assert_eq!(Kept::of(&world, 0, 0), kept, "off keeps it");
        set_feature(&mut world, 0, true);
        assert_eq!(Kept::of(&world, 0, 0), kept, "on keeps it");
    }

    // Payments arrive while this device is off.
    set_feature(&mut world, 0, false);
    deposit(&mut world, i1);
    payout(&mut world, i1, 300_000);
    world.mine(1);
    world.sync(other, true);
    settle(&mut world, other);
    let line = world
        .act(&Action::Swap {
            dev: other,
            acct: 0,
            value: 200_000,
        })
        .unwrap();
    assert!(line.contains("paid 200000 to I2"), "{line}");
    world.pay(MAIN, true, 0, 123_000);
    world.mine(1);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    for _ in 0..2 {
        let (_, requests) = counted_round(&mut world, 0);
        assert_eq!(requests, 0, "no receiver request while off");
    }
    assert_eq!(
        Kept::of(&world, 0, 0).notes,
        kept.notes,
        "nothing is credited while off"
    );

    // Back on: all three are found automatically.
    set_feature(&mut world, 0, true);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    settle(&mut world, 0);
    world.check_step().unwrap();
    let now = credited(&world, 0, 0);
    for payment in [(true, 1, 300_000), (true, 2, 200_000)] {
        assert!(now.contains(&payment), "{payment:?} missing from {now:?}");
    }
    // Over this short gap, querying the few unfinished addresses directly costs less than
    // the filters, and direct catch-up never reads the completed I0 again. So the repeat
    // is found automatically only when filters win, and otherwise by the history check.
    if !now.contains(&(true, 0, 123_000)) {
        let publication = world.current();
        world
            .round(0, 0, false, publication, 0, Some(None))
            .unwrap();
        assert!(credited(&world, 0, 0).contains(&(true, 0, 123_000)));
    }
    let after = Kept::of(&world, 0, 0);
    assert!(after.keys.is_superset(&kept.keys), "no key is lost");
    assert!(
        after.funded.is_superset(&kept.funded),
        "no refund key is lost"
    );
    for note in &kept.notes {
        assert!(after
            .notes
            .iter()
            .any(|n| n.txid == note.txid && n.index == note.index));
    }
    assert_eq!(
        world.reserve_in(0, 0, false).unwrap(),
        Ok(3),
        "paid I0, I1 and I2 are not issued again"
    );
    let line = world.quote_out(0, 0, 3_600).unwrap();
    assert!(
        line.starts_with("R1 quote"),
        "the funded R0 is not issued again: {line}"
    );
    world.quiesce().unwrap();
}

/// A repeat payment to a completed address made while the feature is off, and outside
/// the rolling filter window once it is back on, is not found by automatic catch-up,
/// which never reads completed addresses again. That is the design's limit. The settings
/// history check finds it.
#[test]
fn a_repeat_outside_the_filter_window_while_off_needs_the_history_check() {
    if isolated("toggles::a_repeat_outside_the_filter_window_while_off_needs_the_history_check") {
        return;
    }
    let mut world = world();
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
    set_feature(&mut world, 0, false);
    world.pay(MAIN, true, 0, 123_000);
    world.mine(8);
    world.sync(0, false);
    set_feature(&mut world, 0, true);
    // Filters now start three blocks below the tip, after the repeat.
    for seed in 0..4 {
        let publication = world.publication(0, true, false, false, seed);
        world.round(0, 0, false, publication, seed, None).unwrap();
    }
    assert_eq!(credited(&world, 0, 0), BTreeSet::from([(true, 0, 500_000)]));
    let publication = world.publication(0, true, false, false, 9);
    world
        .round(0, 0, false, publication, 9, Some(None))
        .unwrap();
    assert_eq!(
        credited(&world, 0, 0),
        BTreeSet::from([(true, 0, 500_000), (true, 0, 123_000)]),
        "the history check finds the repeat"
    );
}

/// The setting survives an app restart in both directions, with the wallet database
/// reopened in each state. A turn-off is honoured after restart, and so is one the app
/// saved but died before applying to the wallet: the first round applies it without a
/// receiver request. A turn-on the app died before applying is applied by the first
/// round, which then recovers the payment that arrived while the feature was off. Known
/// state survives every restart.
#[test]
fn the_setting_survives_a_restart_in_either_direction() {
    if isolated("toggles::the_setting_survives_a_restart_in_either_direction") {
        return;
    }
    let mut world = world();
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
    let line = world.quote_in(0, 0, Reply::Accept, 3 * 86_400).unwrap();
    let i1 = quote_of(&line);
    let kept = Kept::of(&world, 0, 0);

    for reconcile in [true, false] {
        // On to off across a restart.
        world.devices[0].feature = false;
        if reconcile {
            world.toggled(0);
        } else {
            apply(&world.devices[0]);
        }
        world.restart(0);
        assert_eq!(
            world.devices[0]
                .wallet
                .state(&world.devices[0].accts[0].account)
                .enabled,
            !reconcile,
            "the wallet says on until something reconciles"
        );
        let (result, requests) = counted_round(&mut world, 0);
        assert!(!result.unwrap().active);
        assert_eq!(requests, 0, "reconcile {reconcile}: no receiver request");
        world.check_setting_applied(0).unwrap();
        let path = world.devices[0].wallet.path.clone();
        assert!(api::reserve_swap_address(
            path.clone(),
            "main".into(),
            kept_uuid(&world),
            true,
            world.chain.tip().into(),
        )
        .is_err());
        world.restart(0);
        let untouched = one_time_snapshot(&world.devices[0].wallet);
        let (_, requests) = counted_round(&mut world, 0);
        assert_eq!(requests, 0);
        assert_eq!(one_time_snapshot(&world.devices[0].wallet), untouched);
        assert_eq!(Kept::of(&world, 0, 0), kept, "off and restarted keeps it");

        // Off to on across a restart, with a payment made while off.
        if !reconcile {
            deposit(&mut world, i1);
            payout(&mut world, i1, 300_000);
            world.mine(1);
            world.sync(0, true);
        }
        world.devices[0].feature = true;
        if reconcile {
            world.toggled(0);
        } else {
            apply(&world.devices[0]);
        }
        world.restart(0);
        if reconcile {
            assert_eq!(Kept::of(&world, 0, 0), kept, "on and restarted keeps it");
        }
        world.poll(0, 0).unwrap();
        settle(&mut world, 0);
        world.check_setting_applied(0).unwrap();
    }
    assert!(
        credited(&world, 0, 0).contains(&(true, 1, 300_000)),
        "the payment made while off is found after the restart"
    );
    world.quiesce().unwrap();
}

/// The uuid of the first account on the first device.
fn kept_uuid(world: &World) -> String {
    world.devices[0].accts[0].account.uuid.clone()
}

/// Turning the feature off while private swaps are open pauses issuance for them too: no
/// new address or quote, and a late quote reply cannot be shown. Status polling goes on
/// and is recorded, so an expired unpaid quote still frees its address and a payout and
/// a refund are attributed. An ordinary swap is never touched. After turning back on the
/// payout and refund are credited, the open swap's address is not issued again, and the
/// expired one's is reused.
#[test]
fn turning_off_with_private_swaps_open() {
    if isolated("toggles::turning_off_with_private_swaps_open") {
        return;
    }
    let mut world = world();
    let line = world.quote_in(0, 0, Reply::Accept, 2 * 3_600).unwrap();
    assert!(line.starts_with("I0 "), "{line}");
    let live = quote_of(&line);
    let line = world.quote_in(0, 0, Reply::Accept, 600).unwrap();
    assert!(line.starts_with("I1 "), "{line}");
    let expiring = quote_of(&line);
    let line = world.quote_in(0, 0, Reply::Timeout, 2 * 3_600).unwrap();
    assert!(
        line.starts_with("I2 ") && line.contains("timed out"),
        "{line}"
    );
    let late = quote_of(&line);
    let line = world
        .act(&Action::SwapOut {
            dev: 0,
            acct: 0,
            outcome: 3,
        })
        .unwrap();
    assert!(line.contains("funded R0"), "{line}");
    let refund = world.quotes.len() - 1;

    // Valid quote inputs while the feature is on: the reserved slot of the timed-out
    // quote, which reserving resumes, two reserved refund keys and a real deposit
    // address. The quotes above show a reserved slot begins a quote while on.
    let path = world.devices[0].wallet.path.clone();
    let uuid = kept_uuid(&world);
    let reserve = |incoming: bool| {
        api::reserve_swap_address(
            path.clone(),
            "main".into(),
            uuid.clone(),
            incoming,
            world.chain.tip().into(),
        )
        .map_err(|e| e.message)
        .unwrap()
    };
    let slot = reserve(true).reservation_index.unwrap();
    assert_eq!(slot, 2, "the timed-out quote's draft is resumed");
    let deposit_address = zcash_keys::address::Address::Transparent(
        transparent::address::TransparentAddress::PublicKeyHash([9; 20]),
    )
    .encode(&NETWORK);
    let first = reserve(false).refund_index.unwrap();
    api::record_swap_refund_quote(
        path.clone(),
        "main".into(),
        uuid.clone(),
        first,
        deposit_address.clone(),
        now() + 600,
    )
    .map_err(|e| e.message)
    .expect("a reserved refund key records its quote while on");
    let second = reserve(false).refund_index.unwrap();
    assert!(second > first);

    set_feature(&mut world, 0, false);
    for incoming in [true, false] {
        let refused = api::reserve_swap_address(
            path.clone(),
            "main".into(),
            uuid.clone(),
            incoming,
            world.chain.tip().into(),
        );
        assert!(refused.is_err_and(|e| e.message.contains("Enable Private queries")));
    }
    // The same valid inputs are refused once the feature is off.
    let begun =
        api::begin_receive_quote(path.clone(), "main".into(), uuid.clone(), slot, now() + 600);
    assert!(
        begun.is_err_and(|e| e.message.contains("Enable Private queries")),
        "a reserved slot begins no quote while off"
    );
    let recorded = api::record_swap_refund_quote(
        path.clone(),
        "main".into(),
        uuid.clone(),
        second,
        deposit_address.clone(),
        now() + 600,
    );
    assert!(
        recorded.is_err_and(|e| e.message.contains("disabled")),
        "a reserved refund key records no quote while off"
    );
    let line = world
        .act(&Action::LateReply {
            quote: 0,
            accept: true,
        })
        .unwrap();
    assert!(
        line.contains("start refused"),
        "a late reply is not shown: {line}"
    );
    assert!(!world.quotes[late].started);

    // Polling goes on: the expired quote frees its address, the payout and refund are
    // attributed.
    world.act(&Action::Warp(900)).unwrap();
    world.mine(1);
    world.sync(0, false);
    // The first status after the deadline frees the address, and the next poll learns it.
    world.poll(0, 0).unwrap();
    world.poll(0, 0).unwrap();
    assert!(
        world.quotes[expiring].released,
        "the expired quote's address is free"
    );
    assert!(
        !world.quotes[live].released,
        "the live quote is still tracked"
    );
    deposit(&mut world, live);
    payout(&mut world, live, 300_000);
    world
        .act(&Action::Refund {
            quote: 0,
            partial: true,
            failed: false,
        })
        .unwrap();
    assert_eq!(world.quotes[refund].status, "SUCCESS");
    world.mine(1);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    assert!(!world.quotes[live].released);

    // An ordinary swap's status never reaches the wallet's records.
    let untouched = one_time_snapshot(&world.devices[0].wallet);
    let tracked = api::observe_swap_status(
        path.clone(),
        "main".into(),
        uuid.clone(),
        true,
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
    assert_eq!(one_time_snapshot(&world.devices[0].wallet), untouched);
    assert!(
        credited(&world, 0, 0).is_empty(),
        "nothing is credited while off"
    );

    set_feature(&mut world, 0, true);
    world.sync(0, true);
    world.poll(0, 0).unwrap();
    settle(&mut world, 0);
    world.check_step().unwrap();
    assert_eq!(
        credited(&world, 0, 0),
        BTreeSet::from([(true, 0, 300_000), (false, 0, 40_000)])
    );
    assert_eq!(
        world.reserve_in(0, 0, false).unwrap(),
        Ok(1),
        "the expired, unpaid I1 is reused and the paid I0 is not"
    );
    let line = world.quote_out(0, 0, 3_600).unwrap();
    let index: u64 = line
        .strip_prefix('R')
        .and_then(|rest| rest.split(' ').next())
        .and_then(|n| n.parse().ok())
        .unwrap_or_else(|| panic!("no refund quote: {line}"));
    assert!(
        index > first,
        "recorded refund keys are not issued again: {line}"
    );
    world.quiesce().unwrap();
}

/// With a second software account, an account without an Orchard key and a Keystone
/// account in one wallet, every toggle reaches each software account alike and leaves
/// the other two without any one-time state, so the hardware account never gets the
/// feature. Each software account keeps its own payments, and one paid while the
/// feature is off is credited only to its own account once it is back on.
#[test]
fn toggles_reach_each_software_account_and_never_a_hardware_one() {
    if isolated("toggles::toggles_reach_each_software_account_and_never_a_hardware_one") {
        return;
    }
    let mut world = World::new();
    world.act(&Action::AddAccount(0)).unwrap();
    world.act(&Action::AddNoOrchard(0)).unwrap();
    let ufvk =
        zcash_keys::keys::UnifiedSpendingKey::from_seed(&NETWORK, &[7; 32], zip32::AccountId::ZERO)
            .unwrap()
            .to_unified_full_viewing_key()
            .encode(&NETWORK);
    let (hardware, _) = crate::wallet::keys::import_hardware_account(
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
    for acct in [0, 1] {
        let line = world
            .act(&Action::Swap {
                dev: 0,
                acct,
                value: 400_000 + 200_000 * acct as u64,
            })
            .unwrap();
        assert!(line.contains("to I0"), "{line}");
    }
    world.mine(1);
    world.sync(0, false);
    settle(&mut world, 0);
    let line = world.quote_in(0, 1, Reply::Accept, 3 * 86_400).unwrap();
    assert!(line.starts_with("I1 "), "{line}");
    let second = quote_of(&line);
    let first = Kept::of(&world, 0, 0);

    let path = world.devices[0].wallet.path.clone();
    let others = |world: &World| {
        let conn = rusqlite::Connection::open(&world.devices[0].wallet.path).unwrap();
        let known: Vec<Vec<u8>> = world.devices[0]
            .accts
            .iter()
            .map(|a| a.account.id.expose_uuid().as_bytes().to_vec())
            .collect();
        let rows = |table: &str| -> i64 {
            let mut statement = conn
                .prepare(&format!(
                    "SELECT a.uuid FROM {table} t JOIN accounts a ON a.id = t.account_id"
                ))
                .unwrap();
            statement
                .query_map([], |r| r.get::<_, Vec<u8>>(0))
                .unwrap()
                .filter(|uuid| !known.contains(uuid.as_ref().unwrap()))
                .count() as i64
        };
        rows("ironwood_one_time_keys") + rows("ironwood_one_time_recovery")
    };
    for on in [false, true, false, true] {
        set_feature(&mut world, 0, on);
        world.check_setting_applied(0).unwrap();
        assert_eq!(others(&world), 0, "on {on}: hardware and no-Orchard state");
        let refused = api::reserve_swap_address(
            path.clone(),
            "main".into(),
            hardware.clone(),
            true,
            world.chain.tip().into(),
        );
        assert!(
            refused.is_err(),
            "the hardware account never gets an address"
        );
        if !on && world.quotes[second].status == "PENDING_DEPOSIT" {
            deposit(&mut world, second);
            payout(&mut world, second, 300_000);
            world.mine(1);
            world.sync(0, true);
        }
        let (result, requests) = counted_round(&mut world, 0);
        if let Err(RecoveryError::Other(message)) = &result {
            assert!(!mentions_orchard(message), "{message}");
        }
        if !on {
            assert_eq!(requests, 0, "no receiver request while off");
        }
        world.poll(0, 0).unwrap();
    }
    settle(&mut world, 0);
    world.check_step().unwrap();
    assert_eq!(credited(&world, 0, 0), BTreeSet::from([(true, 0, 400_000)]));
    assert_eq!(
        credited(&world, 0, 1),
        BTreeSet::from([(true, 0, 600_000), (true, 1, 300_000)])
    );
    assert_eq!(
        Kept::of(&world, 0, 0).notes,
        first.notes,
        "the first account is untouched"
    );
    assert_eq!(others(&world), 0);
    world.quiesce().unwrap();
}

/// Rapid toggling: on, off and on again in quick succession while an admitted round, and
/// then two at once, wait at their inventory read, with the app's worker drain on some
/// flips. No call fails on
/// wallet lock contention, the wallet always ends on the last setting, nothing is stuck,
/// and the pending payment is credited exactly once. The production entry point admits
/// one round at a time.
#[test]
fn rapid_toggles_while_rounds_start_leave_nothing_stuck() {
    if isolated("toggles::rapid_toggles_while_rounds_start_leave_nothing_stuck") {
        return;
    }
    let mut world = world();
    world.act(&Action::AddAccount(0)).unwrap();
    world.sync(0, false);
    settle(&mut world, 0);
    world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 700_000,
        })
        .unwrap();
    world.mine(1);
    world.sync(0, false);
    for i in 0..8u8 {
        let line = world.rapid_toggle(0, 2 + i % 4, true).unwrap();
        println!("rapid toggle {i}: {line}");
        world.check_step().unwrap();
        if i % 3 == 0 {
            // Two admitted rounds, both held at their inventory read, overlap the flips.
            world.ensure_on(0);
            let publication = world.current();
            let service = world.service(publication);
            let first = service.count("inventory");
            let holds: Vec<_> = (0..2)
                .map(|k| service.hold("inventory", first + k))
                .collect();
            // Each worker starts once the one before it is held, so each takes its own
            // hold.
            let workers: Vec<_> = holds
                .iter()
                .map(|held| {
                    let worker =
                        world.devices[0]
                            .wallet
                            .spawn(&service, None, Duration::from_secs(45));
                    held.wait();
                    worker
                })
                .collect();
            // Three flips through the wallet alone, without the app's worker drain, so
            // the rounds go on after their release and must not undo the last setting.
            for on in [false, true, false] {
                set_feature(&mut world, 0, on);
            }
            for held in &holds {
                held.release();
            }
            for worker in workers {
                if let Err(e) = worker.join().unwrap() {
                    assert!(!locked(&e.to_string()), "{e}");
                }
            }
            world.check_setting_applied(0).unwrap();
        }
    }
    // While a round is admitted, the production entry point refuses another. With the
    // feature on and work due, nothing short-circuits before admission.
    world.ensure_on(0);
    world.check_setting_applied(0).unwrap();
    super::super::super::RUNNING.store(true, AtomicOrdering::SeqCst);
    let busy = api::run_swap_recovery(world.devices[0].wallet.path.clone(), "main".into());
    super::super::super::RUNNING.store(false, AtomicOrdering::SeqCst);
    assert!(
        busy.as_ref()
            .is_err_and(|e| e.message.contains("already running")),
        "{:?}",
        busy.map_err(|e| e.message)
    );

    world.ensure_on(0);
    world.check_setting_applied(0).unwrap();
    settle(&mut world, 0);
    world.check_step().unwrap();
    assert_eq!(credited(&world, 0, 0), BTreeSet::from([(true, 0, 700_000)]));
    let account = world.devices[0].accts[0].account.clone();
    assert!(world.devices[0].wallet.queued(&account).is_empty());
    world.quiesce().unwrap();
}

/// An answer held while the feature turns off and straight back on is still rejected:
/// both changes fence the round that asked, so the round reads the payment again under
/// the new setting and credits it once.
#[test]
fn an_answer_held_across_off_and_on_is_rejected() {
    if isolated("toggles::an_answer_held_across_off_and_on_is_rejected") {
        return;
    }
    let mut world = world();
    world
        .act(&Action::Swap {
            dev: 0,
            acct: 0,
            value: 700_000,
        })
        .unwrap();
    world.mine(1);
    world.sync(0, false);
    let publication = world.current();
    let service = world.service(publication);
    let account = world.devices[0].accts[0].account.clone();
    service.trace(&world.devices[0].wallet, &account);
    let held = service.hold("query", service.count("query"));
    let worker = world.devices[0]
        .wallet
        .spawn(&service, None, Duration::from_secs(45));
    held.wait();
    set_feature(&mut world, 0, false);
    set_feature(&mut world, 0, true);
    held.release();
    worker.join().unwrap().unwrap();
    let first_page = service
        .traced()
        .iter()
        .filter(|q| **q == (true, 0, 0))
        .count();
    assert_eq!(
        first_page,
        2,
        "the old answer was rejected, so the round read I0's first page again: {:?}",
        service.traced()
    );
    settle(&mut world, 0);
    world.check_step().unwrap();
    assert_eq!(credited(&world, 0, 0), BTreeSet::from([(true, 0, 700_000)]));
}

/// Turning the feature off while the settings history check is mid-run stops it
/// cleanly: the held answer writes nothing, a new check is refused, and the status stops
/// reporting a check. The saved job keeps its place: turned back on, it resumes and
/// finds the repeat payment only it can find. Pausing it while off keeps it paused after
/// turning back on, until the next check resumes it.
#[test]
fn turning_off_mid_history_check_stops_it_cleanly() {
    if isolated("toggles::turning_off_mid_history_check_stops_it_cleanly") {
        return;
    }
    for pause in [false, true] {
        let mut world = world();
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
        // A repeat payment outside the filter window, which only the check finds.
        world.pay(MAIN, true, 0, 123_000);
        world.mine(8);
        world.sync(0, false);
        for seed in 0..2 {
            let publication = world.publication(0, true, false, false, seed);
            world.round(0, 0, false, publication, seed, None).unwrap();
        }
        assert_eq!(credited(&world, 0, 0), BTreeSet::from([(true, 0, 500_000)]));

        let publication = world.publication(0, true, false, false, 5);
        let service = world.service(publication);
        let held = service.hold("query", service.count("query"));
        let worker = world.devices[0]
            .wallet
            .spawn(&service, Some(None), Duration::from_secs(45));
        held.wait();
        set_feature(&mut world, 0, false);
        cancel_recovery();
        let before = one_time_snapshot(&world.devices[0].wallet);
        held.release();
        let result = worker.join().unwrap();
        assert!(result.is_err_and(|e| e.to_string().contains("cancelled")));
        assert_eq!(one_time_snapshot(&world.devices[0].wallet), before);
        world.manual_refused(0).unwrap();
        let account = world.devices[0].accts[0].account.clone();
        let saved = world.devices[0].wallet.state(&account).manual;
        assert!(
            saved.is_some_and(|m| m.active),
            "the job keeps its place: {saved:?}"
        );
        let path = world.devices[0].wallet.path.clone();
        if pause {
            api::cancel_swap_history(path.clone(), "main".into()).unwrap();
        }
        assert_eq!(
            one_time_snapshot(&world.devices[0].wallet) == before,
            !pause
        );

        set_feature(&mut world, 0, true);
        let status = api::get_swap_recovery_status(path, "main".into()).unwrap();
        assert_eq!(status.checking_history, !pause, "pause {pause}");
        for seed in 10..14 {
            let publication = world.publication(0, true, false, false, seed);
            world.round(0, 0, false, publication, seed, None).unwrap();
        }
        let found = credited(&world, 0, 0).contains(&(true, 0, 123_000));
        assert_eq!(
            found, !pause,
            "pause {pause}: the resumed job finds the repeat"
        );
        if pause {
            let publication = world.publication(0, true, false, false, 20);
            world
                .round(0, 0, false, publication, 20, Some(None))
                .unwrap();
            assert!(credited(&world, 0, 0).contains(&(true, 0, 123_000)));
        }
        let manual = world.devices[0].wallet.state(&account).manual;
        assert!(
            manual.is_some_and(|m| !m.active),
            "pause {pause}: the history check finished: {manual:?}"
        );
        world.check_step().unwrap();
    }
}

/// Turning the feature off while an owned receipt needs repair, and then meeting a
/// receiver service that needs a newer app, does not strand the repair. Feature-off
/// rounds keep trying while the repair is owed, and the first compatible publication
/// clears the update request and finishes the repair with the feature still off. A
/// paused wallet with an update request but nothing to repair makes no request at all.
///
/// Accepted limitation: while an update is required the wallet hides the owed repair,
/// so a feature-off round finds no work and never reaches the publication that would
/// clear the request. It is rare, and fixing it needs a library change.
#[test]
#[ignore = "accepted known limitation: rare, and resuming the repair needs a library change"]
fn an_update_request_while_off_does_not_strand_repair() {
    if isolated("toggles::an_update_request_while_off_does_not_strand_repair") {
        return;
    }
    let mut world = world();
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
    set_feature(&mut world, 0, false);
    let reorg = world.reorg(3);
    assert!(reorg.contains("re-sent 1 payouts"), "{reorg}");
    world.mine(12);
    world.sync(0, true);
    assert!(repair_owed(&world.devices[0].wallet, &account.id));

    let publication = world.current();
    let line = world.round(0, 0, true, publication, 0, None).unwrap();
    assert!(line.contains("newer app"), "{line}");
    assert!(world.devices[0].wallet.state(&account).upgrade_required);

    // The service is compatible again: the next feature-off round captures it.
    let (result, requests) = counted_round(&mut world, 0);
    assert!(
        result.unwrap().active,
        "the owed repair keeps the round running"
    );
    assert!(requests > 0, "it asks the service again");
    settle(&mut world, 0);
    let state = world.devices[0].wallet.state(&account);
    assert!(
        !state.upgrade_required,
        "a compatible publication clears the request"
    );
    assert!(
        state.lookups.is_empty() && state.witnesses.is_empty(),
        "the repair finished"
    );
    world.check_step().unwrap();

    // With nothing to repair, an update request while off costs no request.
    set_feature(&mut world, 0, true);
    settle(&mut world, 0);
    let publication = world.current();
    world.round(0, 0, true, publication, 0, None).unwrap();
    assert!(world.devices[0].wallet.state(&account).upgrade_required);
    set_feature(&mut world, 0, false);
    for _ in 0..2 {
        let (result, requests) = counted_round(&mut world, 0);
        assert!(!result.unwrap().active);
        assert_eq!(requests, 0, "a paused wallet with nothing owed stays inert");
    }
    set_feature(&mut world, 0, true);
    settle(&mut world, 0);
    assert!(!world.devices[0].wallet.state(&account).upgrade_required);
    world.quiesce().unwrap();
}
