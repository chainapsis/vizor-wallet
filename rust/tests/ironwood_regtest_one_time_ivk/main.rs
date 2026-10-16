//! One-time IVK swaps on the Dockerized Ironwood regtest stack
//! (`scripts/ironwood-regtest`), driven through Vizor's API and sync engine.
//!
//! Real: the node, lightwalletd, signed Ironwood transactions, Vizor's wallet, sync and
//! swap API, and the receiver directory's routes and PIR, reached over HTTP. Simulated:
//! NEAR, whose payouts and refunds a payer wallet sends with the zero OVK; the directory's
//! indexer, which reads the node's raw blocks as the live one does; and time, which a mock
//! clock moves for the node and Vizor together. Debug builds of Vizor read the seams
//! these tests set (see `one_time_ivk` and `swap_private`).
//!
//! Each test resets the chain. Run them one at a time:
//! `cargo test --test ironwood_regtest_one_time_ivk -- --ignored --test-threads=1`.

mod chain;
mod directory;
mod near;
mod wallets;

use std::sync::{Mutex, MutexGuard};

use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};
use zcash_client_backend::wallet::OvkPolicy;

use chain::{internal_hash, Stack, DAY, HOUR, MINUTE, ZEC};
use directory::{zero_ovk_receivers, DirectoryServer, Indexer};
use near::Near;
use wallets::{broadcast, receiver_of, zero_ovk, IncomingSwap, Payer, RefundSwap, Wallet};

static STACK: Mutex<()> = Mutex::new(());

const PAYOUT: u64 = ZEC / 4;

/// The chain, the directory serving it, NEAR, and NEAR's payer, for one test.
struct World {
    stack: Stack,
    indexer: Indexer,
    directory: DirectoryServer,
    near: Near,
    payer: Payer,
    genesis: [u8; 32],
}

impl World {
    /// A fresh chain past Ironwood activation, a payer holding Ironwood notes, and a
    /// directory that Vizor is pointed at.
    fn start() -> Self {
        let stack = Stack::start();
        let directory = DirectoryServer::start();
        let genesis = stack.genesis_displayed();
        std::env::set_var("VIZOR_REGTEST_ONE_TIME_IVKS", "1");
        std::env::set_var("VIZOR_RECEIVER_PIR_URL", directory.origin());
        std::env::set_var("VIZOR_RECEIVER_PIR_GENESIS", &genesis);
        sync_api::set_near_swap_privacy_enabled(true);

        let payer = Payer::new(Wallet::import("NEAR", &wallet_api::generate_mnemonic(), 1));
        stack.fund_orchard(&[&payer.wallet.address], 10);
        stack.activate_ironwood();
        stack.mine(3);
        let mut world = Self {
            indexer: Indexer::new(stack.activation()),
            directory,
            near: Near::new(stack.now()),
            payer,
            genesis: internal_hash(&genesis),
            stack,
        };
        world.publish();
        // Several Ironwood notes, so payments need not wait for change.
        let own = world.payer.own_addresses(8);
        let split: Vec<(&str, u64)> = own.iter().map(|a| (a.as_str(), ZEC)).collect();
        world.payer.pay(&world.stack, &split, OvkPolicy::Sender);
        world.stack.mine(1);
        world
    }

    /// A new wallet whose birthday is the tip, synced.
    fn wallet(&mut self, name: &str) -> Wallet {
        let wallet = Wallet::import(name, &wallet_api::generate_mnemonic(), self.stack.tip());
        self.sync(&wallet);
        wallet
    }

    /// Republishes the directory two blocks below the tip, as the live indexer does.
    fn publish(&mut self) {
        let end = self.stack.tip().saturating_sub(2);
        if end < self.stack.activation() {
            return;
        }
        let sets = self.near.sets(self.stack.now());
        let publication = self
            .indexer
            .publication(&self.stack, end, &sets, self.genesis);
        self.directory.publish(publication);
    }

    /// Republishes the directory, then syncs `wallet` once, as the app's poll would.
    fn sync(&mut self, wallet: &Wallet) {
        self.publish();
        wallet.sync(&self.stack);
    }

    /// Syncs `wallet`, mining a block between syncs, until it holds `expected` or
    /// `rounds` syncs have run. Returns whether it holds `expected`.
    fn sync_until(&mut self, wallet: &Wallet, expected: u64, rounds: u32) -> bool {
        for round in 0..rounds {
            if round > 0 {
                self.stack.mine(1);
            }
            self.sync(wallet);
            if wallet.total() == expected {
                return true;
            }
        }
        false
    }

    /// Quotes an incoming swap on `wallet`, syncing while restored addresses are still
    /// being checked, as a user would retry.
    fn quote_incoming(&mut self, wallet: &Wallet, deadline_in: i64) -> IncomingSwap {
        self.quote_incoming_to(wallet, deadline_in, None)
    }

    /// [`Self::quote_incoming`], with NEAR's deposit address and memo given as `deposit`.
    fn quote_incoming_to(
        &mut self,
        wallet: &Wallet,
        deadline_in: i64,
        deposit: Option<(&str, &str)>,
    ) -> IncomingSwap {
        for _ in 0..4 {
            match wallet.quote_incoming_to(&self.stack, &mut self.near, deadline_in, deposit) {
                Ok(swap) => return swap,
                Err(e) => {
                    eprintln!("{} cannot quote yet: {e}", wallet.name);
                    self.stack.mine(1);
                    self.sync(wallet);
                }
            }
        }
        panic!("{} never quotes", wallet.name);
    }

    /// Quotes a ZEC-to-X swap on `wallet`, retrying like [`Self::quote_incoming`].
    fn quote_refund(&mut self, wallet: &Wallet, deadline_in: i64) -> RefundSwap {
        for _ in 0..4 {
            match wallet.quote_refund(&self.stack, &mut self.near, deadline_in) {
                Ok(swap) => return swap,
                Err(e) => {
                    eprintln!("{} cannot quote yet: {e}", wallet.name);
                    self.stack.mine(1);
                    self.sync(wallet);
                }
            }
        }
        panic!("{} never quotes", wallet.name);
    }

    /// Spends everything `wallet` holds with the app's send-max flow and checks that the
    /// node mined it, NEAR's payer received exactly the amount, and no one-time-key note
    /// is left unspent. A note the wallet credited but cannot spend fails here.
    fn spend_all(&mut self, wallet: &Wallet) {
        // Received notes need ten confirmations before they are spendable.
        self.stack.mine(10);
        self.publish();
        wallet.sync_settled(&self.stack);
        let held = wallet.unspent_one_time_value();
        assert!(
            held > 0,
            "{} holds one-time-key notes to spend",
            wallet.name
        );
        self.payer.wallet.sync_settled(&self.stack);
        let before = self.payer.wallet.total();
        let (sent, txid) = wallet.send_max(&self.stack, &self.payer.wallet.address);
        self.stack.mine(1);
        let mined = self
            .stack
            .rpc("getrawtransaction", serde_json::json!([txid, 1]));
        assert!(
            mined["confirmations"].as_u64().unwrap_or(0) >= 1,
            "the node mined {}'s spend of {held} zat in one-time-key notes",
            wallet.name
        );
        self.sync(wallet);
        self.payer.wallet.sync(&self.stack);
        assert_eq!(
            self.payer.wallet.total() - before,
            sent,
            "NEAR's payer received {}'s whole spend",
            wallet.name
        );
        assert_eq!(
            wallet.unspent_one_time_value(),
            0,
            "{} spent every one-time-key note",
            wallet.name
        );
        eprintln!("{} spent {held} zat in one-time-key notes", wallet.name);
    }

    /// Checks the mined funding transaction `txid` from the node's own view: its only
    /// transparent output pays exactly `amount` to the quoted `deposit` address.
    fn check_funding(&self, txid: &str, deposit: &str, amount: u64) {
        let tx = self
            .stack
            .rpc("getrawtransaction", serde_json::json!([txid, 1]));
        assert!(
            tx["confirmations"].as_u64().unwrap_or(0) >= 1,
            "the funding is mined"
        );
        let outputs: Vec<(String, u64)> = tx["vout"]
            .as_array()
            .expect("transparent outputs")
            .iter()
            .map(|out| {
                let address = out["scriptPubKey"]["addresses"][0]
                    .as_str()
                    .expect("an address")
                    .to_owned();
                (address, out["valueZat"].as_u64().expect("a value"))
            })
            .collect();
        assert_eq!(
            outputs,
            vec![(deposit.to_owned(), amount)],
            "the funding pays exactly the quoted deposit and nothing else in the clear"
        );
    }

    /// NEAR pays `value` to `address` with the zero OVK, in a block of its own.
    fn pay(&mut self, address: &str, value: u64) {
        self.payer.pay(&self.stack, &[(address, value)], zero_ovk());
        self.stack.mine(1);
    }

    /// NEAR pays `value` to `address` with the zero OVK, in a block of its own, with the
    /// payment's sibling leaf in the note commitment tree where `sibling` says. Applying a
    /// late find inserts the payment with its sibling's hash. Returns the position.
    fn pay_late(&mut self, address: &str, receiver: [u8; 43], value: u64, sibling: Sibling) -> u64 {
        // A payout has two actions, the payment and its change, in a shuffled order.
        let (base_odd, index) = match sibling {
            Sibling::OwnChangeAfter => (false, 0),
            Sibling::OwnChangeBefore => (false, 1),
            Sibling::EarlierBlock => (true, 0),
        };
        for _ in 0..12 {
            let base = self.indexer.tree_size(&self.stack, self.stack.tip());
            if (base % 2 == 1) != base_odd {
                // A three-action transaction moves the next block's tree size to the other
                // parity.
                let own = self.payer.own_addresses(2);
                let padding: Vec<(&str, u64)> =
                    own.iter().map(|a| (a.as_str(), ZEC / 100)).collect();
                self.payer.pay(&self.stack, &padding, OvkPolicy::Sender);
                self.stack.mine(1);
                continue;
            }
            // Built in a copy of the payer's wallet, so a draw in the wrong order leaves
            // nothing behind to resubmit.
            let tx = self
                .payer
                .build_detached(&self.stack, &[(address, value)], zero_ovk());
            let actions = zero_ovk_receivers(&tx);
            let at = actions
                .iter()
                .position(|r| r.as_ref() == Some(&receiver))
                .expect("the payment's action");
            if actions.len() != 2 || at != index {
                continue;
            }
            broadcast(&self.stack, &tx);
            self.stack.mine(1);
            self.indexer.tree_size(&self.stack, self.stack.tip());
            let position = *self
                .indexer
                .positions(&receiver)
                .last()
                .expect("the indexer saw the payment");
            assert_eq!(
                position,
                base + at as u64,
                "the payment is alone in its block"
            );
            eprintln!("late payment at position {position}, sibling {sibling:?}");
            return position;
        }
        panic!("no payout drew the {sibling:?} layout");
    }
}

/// Where a late payment's sibling leaf sits in the note commitment tree. Applying a late
/// find inserts the payment with that sibling's hash.
#[derive(Clone, Copy, Debug)]
enum Sibling {
    /// The payment's own change, to its right: the payment is at an even position.
    OwnChangeAfter,
    /// The payment's own change, to its left: the payment is at an odd position.
    OwnChangeBefore,
    /// The last output of an earlier block, to its left: an odd position.
    EarlierBlock,
}

/// Serializes the tests, which share one regtest stack, and prints Vizor's warnings,
/// such as a deferred restore sweep, to standard error (`E2E_LOG=info` for more).
fn lock() -> MutexGuard<'static, ()> {
    static LOGGER: StderrLogger = StderrLogger;
    let level = match std::env::var("E2E_LOG").as_deref() {
        Ok("info") => log::LevelFilter::Info,
        _ => log::LevelFilter::Warn,
    };
    if log::set_logger(&LOGGER).is_ok() {
        log::set_max_level(level);
    }
    STACK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Vizor's `log` records on standard error.
struct StderrLogger;

impl log::Log for StderrLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::max_level()
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            eprintln!("[{} {}] {}", record.level(), record.target(), record.args());
        }
    }

    fn flush(&self) {}
}

/// An incoming swap's payout is found while the wallet scans, and a restore of the seed
/// two days later finds it again through the receiver directory and can spend it.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn incoming_payout_is_found_live_and_by_a_later_restore() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    let swap = world.quote_incoming(&a, HOUR);
    world.stack.advance(20 * MINUTE);
    world.pay(&swap.address, PAYOUT);
    assert!(
        world.sync_until(&a, PAYOUT, 3),
        "A finds the payout while scanning"
    );
    a.observe_incoming(&world.stack, &swap, "SUCCESS", PAYOUT);
    world.stack.mine(12);
    world.sync(&a);

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    let lookups = world.directory.lookups();
    assert!(
        world.sync_until(&b, PAYOUT, 10),
        "B, restored from A's seed, finds the payout (holds {})",
        b.total()
    );
    assert!(
        world.directory.lookups() > lookups,
        "B looked the payout up in the directory"
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for the payout"
    );
    world.spend_all(&b);
}

/// One address paid twice in a row is credited twice while it scans. A third payment
/// three weeks later, after the key closed, is found only by Check swap history; here its
/// sibling leaf is its own change, to its right.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn address_paid_twice_then_late_beside_its_own_change_after() {
    late_payment(true, Sibling::OwnChangeAfter);
}

/// A late payment found by Check swap history, its sibling leaf its own change, to its left.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn late_payment_beside_its_own_change_before() {
    late_payment(false, Sibling::OwnChangeBefore);
}

/// A late payment found by Check swap history, its sibling leaf an earlier block's output.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn late_payment_beside_an_earlier_block() {
    late_payment(false, Sibling::EarlierBlock);
}

/// Pays an incoming swap's address (twice in a row when `twice`), lets its key close,
/// then pays it again three weeks later with the payment's sibling where `sibling` says,
/// and checks that only Check swap history finds that payment, and that it is spendable.
fn late_payment(twice: bool, sibling: Sibling) {
    let _guard = lock();
    let (mut world, a, held) = paid_late(twice, sibling);
    // The directory publishes two blocks below the tip, and a recheck before then misses
    // the payment.
    assert!(
        !world.sync_until(&a, held, 3),
        "the key closed, so only Check swap history finds a later payment"
    );
    a.check_swap_history();
    assert!(
        world.sync_until(&a, held, 10),
        "Check swap history finds the late payment (A holds {})",
        a.total()
    );
    world.spend_all(&a);
}

/// Check swap history runs once. Run before the directory has published a late payment, it
/// finishes without the payment, and only running it again finds it.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn check_swap_history_before_the_directory_publishes_needs_another_run() {
    let _guard = lock();
    let (mut world, a, held) = paid_late(false, Sibling::EarlierBlock);
    a.check_swap_history();
    assert!(
        !world.sync_until(&a, held, 4),
        "a check against a publication without the payment finishes without it"
    );
    a.check_swap_history();
    assert!(
        world.sync_until(&a, held, 10),
        "checking swap history again finds the late payment (A holds {})",
        a.total()
    );
    world.spend_all(&a);
}

/// A wallet whose swap address was paid (twice in a row when `twice`) and found, whose key
/// then closed, and which NEAR paid again three weeks later with the payment's sibling
/// where `sibling` says, just mined. Returns what the wallet holds once it finds that
/// payment too.
fn paid_late(twice: bool, sibling: Sibling) -> (World, Wallet, u64) {
    let mut world = World::start();
    let a = world.wallet("A");
    let swap = world.quote_incoming(&a, HOUR);
    world.stack.advance(20 * MINUTE);
    world.pay(&swap.address, PAYOUT);
    let mut paid = PAYOUT;
    if twice {
        world.pay(&swap.address, PAYOUT / 2);
        paid += PAYOUT / 2;
    }
    assert!(
        world.sync_until(&a, paid, 3),
        "A finds every payout while scanning"
    );
    a.observe_incoming(&world.stack, &swap, "SUCCESS", paid);
    world.stack.mine(12);
    world.sync(&a);

    world.stack.advance(21 * DAY);
    world.stack.mine(1);
    world.pay_late(&swap.address, swap.receiver, PAYOUT / 5, sibling);
    (world, a, paid + PAYOUT / 5)
}

/// Two devices on one seed: A gives NEAR a refund address for a swap it never funds, so no
/// funding memo tells B about it. B reserves a refund address two hours later, and only
/// NEAR's seen set, which the directory publishes, keeps B from giving NEAR the same one.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn a_second_device_skips_a_refund_address_the_first_gave_near() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let b = Wallet::import("B", &a.mnemonic, world.stack.tip());
    world.sync(&b);
    let first = world.quote_refund(&a, HOUR);

    world.stack.advance(2 * HOUR);
    world.stack.mine(1);
    world.sync(&b);
    let second = world.quote_refund(&b, HOUR);
    assert_ne!(
        second.index, first.index,
        "B skips the refund address A gave NEAR (A reserved {}, B reserved {})",
        first.index, second.index
    );
    assert_ne!(second.address, first.address);
}

/// A ZEC-to-X swap's refund is found while the refund key scans, and a restore two days
/// later recovers the key from the funding transaction's memo, finds the refund through
/// the receiver directory and can spend it.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn refund_is_found_live_and_by_a_later_restore() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    world
        .payer
        .pay(&world.stack, &[(&a.address, 2 * ZEC)], OvkPolicy::Sender);
    world.stack.mine(10);
    world.sync(&a);
    assert_eq!(a.total(), 2 * ZEC, "A holds its funding");

    let swap = world.quote_refund(&a, HOUR);
    a.fund_swap(&world.stack, &swap, ZEC / 2);
    world.stack.mine(1);
    world.sync(&a);
    let funded = a.total();
    assert!(funded < 2 * ZEC - ZEC / 2 + 1, "A paid the deposit");

    world.stack.advance(30 * MINUTE);
    world.pay(&swap.address, ZEC / 2);
    assert!(
        world.sync_until(&a, funded + ZEC / 2, 3),
        "A finds the refund while the refund key scans (holds {})",
        a.total()
    );
    a.observe_refund(&world.stack, &swap, "REFUNDED", ZEC / 2);
    world.stack.mine(12);
    world.sync(&a);

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    assert!(
        world.sync_until(&b, a.total(), 15),
        "B, restored from A's seed, finds the refund (holds {}, A holds {})",
        b.total(),
        a.total()
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for the refund"
    );
    world.spend_all(&b);
}

/// A ZEC-to-X swap whose refund key is not the account's first. A refund index bound to
/// another deposit is refused before anything is sent, the funding pays exactly the
/// quoted deposit and fee, and a seed restore recovers the key from the marker on the
/// funding change even after that change is spent. The restored wallet finds the
/// refund, spends it, and its next refund address skips every index the seed used.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn refund_funding_is_exact_and_a_restore_recovers_its_key_from_spent_change() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    world
        .payer
        .pay(&world.stack, &[(&a.address, 2 * ZEC)], OvkPolicy::Sender);
    world.stack.mine(10);
    world.sync(&a);
    // Two quotes A never funds take indices 0 and 1, so the funded key is index 2.
    let unfunded = world.quote_refund(&a, HOUR);
    world.quote_refund(&a, HOUR);
    let swap = world.quote_refund(&a, HOUR);
    assert_eq!(swap.index, 2, "the funded swap's refund key is index 2");
    let mismatched = sync_api::propose_swap_funding(
        a.db.clone(),
        chain::NETWORK.into(),
        a.account.clone(),
        "mismatched".into(),
        swap.deposit.clone(),
        ZEC / 2,
        unfunded.index,
    );
    assert!(
        mismatched.is_err(),
        "a refund index bound to another deposit is refused before anything is sent"
    );

    let before = a.total();
    let (fee, txid) = a.fund_swap(&world.stack, &swap, ZEC / 2);
    world.stack.mine(1);
    world.check_funding(&txid, &swap.deposit, ZEC / 2);
    world.sync(&a);
    assert_eq!(
        before - a.total(),
        ZEC / 2 + fee,
        "A paid exactly the deposit and the fee"
    );

    // A spends its change, so the marker naming the refund key is on a spent note.
    world.stack.mine(10);
    world.sync(&a);
    a.send_max(&world.stack, &world.payer.wallet.address);
    world.stack.mine(1);
    world.sync(&a);
    assert_eq!(a.total(), 0, "A spent its funding change");

    world.stack.advance(HOUR);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    for _ in 0..4 {
        world.sync(&b);
        world.stack.mine(1);
    }
    assert!(
        b.refund_key_indices().contains(&swap.index),
        "B recovered refund key {} from the spent change's marker (holds {:?})",
        swap.index,
        b.refund_key_indices()
    );
    world.pay(&swap.address, ZEC / 2);
    assert!(
        world.sync_until(&b, ZEC / 2, 5),
        "B finds the refund (holds {})",
        b.total()
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for its swap keys"
    );
    let next = world.quote_refund(&b, HOUR);
    assert!(
        next.index > swap.index,
        "B's next refund address, index {}, skips every index the seed used",
        next.index
    );
    world.spend_all(&b);
}

/// A swap funded with everything the wallet holds leaves a zero-value change note that
/// still carries the refund marker. The refund lands before the seed is restored, and the
/// restore recovers the key from that marker, finds the refund through the receiver
/// directory and can spend it.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn a_zero_value_refund_marker_restores_the_key() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    world
        .payer
        .pay(&world.stack, &[(&a.address, 2 * ZEC)], OvkPolicy::Sender);
    world.stack.mine(10);
    world.sync(&a);
    let swap = world.quote_refund(&a, HOUR);
    let (amount, _, txid) = a.fund_swap_with_everything(&world.stack, &swap);
    world.stack.mine(1);
    world.check_funding(&txid, &swap.deposit, amount);
    world.sync(&a);
    assert_eq!(a.total(), 0, "the funding change is worth nothing");

    world.stack.advance(30 * MINUTE);
    world.pay(&swap.address, amount);
    assert!(
        world.sync_until(&a, amount, 3),
        "A finds the refund while the refund key scans (holds {})",
        a.total()
    );
    world.stack.mine(12);
    world.sync(&a);

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    assert!(
        world.sync_until(&b, amount, 15),
        "B, restored from A's seed, finds the refund (holds {})",
        b.total()
    );
    assert!(
        b.refund_key_indices().contains(&swap.index),
        "B recovered the refund key from the zero-value marker"
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for the refund"
    );
    world.spend_all(&b);
}

/// Two software accounts in one Vizor wallet, the second added from another seed, quote
/// swaps whose keys sit at the same indices. NEAR pays both incoming addresses in one
/// transaction and refunds both swaps in another, with distinct values. Each account
/// receives only its own funds, a restore of each seed on its own finds that account's
/// funds and can spend them, and each account's next address advances independently.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn two_accounts_in_one_wallet_keep_their_swaps_apart() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    let a2 = a.add_account("A2", &wallet_api::generate_mnemonic(), birthday);
    world.payer.pay(
        &world.stack,
        &[(&a.address, ZEC), (&a2.address, ZEC)],
        OvkPolicy::Sender,
    );
    world.stack.mine(10);
    world.sync(&a);
    assert_eq!(
        (a.total(), a2.total()),
        (ZEC, ZEC),
        "each account holds its own funds"
    );

    let incoming = [
        world.quote_incoming(&a, HOUR),
        world.quote_incoming(&a2, HOUR),
    ];
    let refunds = [world.quote_refund(&a, HOUR), world.quote_refund(&a2, HOUR)];
    assert_eq!(
        (refunds[0].index, refunds[1].index),
        (0, 0),
        "both accounts' refund keys are their first"
    );
    assert_ne!(incoming[0].address, incoming[1].address);
    assert_ne!(refunds[0].address, refunds[1].address);
    a.fund_swap(&world.stack, &refunds[0], ZEC / 4);
    a2.fund_swap(&world.stack, &refunds[1], ZEC / 4);
    world.stack.mine(1);
    world.sync(&a);
    let funded = [a.total(), a2.total()];

    // NEAR pays both incoming addresses in one transaction, and refunds both swaps in
    // another, each account's amounts distinct from the other's.
    world.stack.advance(20 * MINUTE);
    let (payouts, refunded) = (
        [11 * ZEC / 100, 22 * ZEC / 100],
        [13 * ZEC / 100, 24 * ZEC / 100],
    );
    world.payer.pay(
        &world.stack,
        &[
            (&incoming[0].address, payouts[0]),
            (&incoming[1].address, payouts[1]),
        ],
        zero_ovk(),
    );
    world.payer.pay(
        &world.stack,
        &[
            (&refunds[0].address, refunded[0]),
            (&refunds[1].address, refunded[1]),
        ],
        zero_ovk(),
    );
    world.stack.mine(1);
    let expected = [
        funded[0] + payouts[0] + refunded[0],
        funded[1] + payouts[1] + refunded[1],
    ];
    for _ in 0..3 {
        world.sync(&a);
        if [a.total(), a2.total()] == expected {
            break;
        }
        world.stack.mine(1);
    }
    assert_eq!(
        [a.total(), a2.total()],
        expected,
        "each account received exactly its own payout and refund"
    );
    a.observe_incoming(&world.stack, &incoming[0], "SUCCESS", payouts[0]);
    a2.observe_incoming(&world.stack, &incoming[1], "SUCCESS", payouts[1]);
    a.observe_refund(&world.stack, &refunds[0], "REFUNDED", refunded[0]);
    a2.observe_refund(&world.stack, &refunds[1], "REFUNDED", refunded[1]);
    world.stack.mine(12);
    world.sync(&a);

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    let b2 = Wallet::import("B2", &a2.mnemonic, birthday);
    assert!(
        world.sync_until(&b, a.total(), 15),
        "B, restored from A's seed alone, holds A's funds (B {}, A {})",
        b.total(),
        a.total()
    );
    assert!(
        world.sync_until(&b2, a2.total(), 15),
        "B2, restored from A2's seed alone, holds A2's funds (B2 {}, A2 {})",
        b2.total(),
        a2.total()
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for A's swaps"
    );
    assert!(
        b2.early_restore_accepted(),
        "B2's restore scan looked for A2's swaps"
    );
    let next = [world.quote_refund(&a, HOUR), world.quote_refund(&a2, HOUR)];
    assert_eq!(
        (next[0].index, next[1].index),
        (1, 1),
        "each account's next refund address advances on its own"
    );
    world.spend_all(&b);
    world.spend_all(&b2);
}

/// NEAR swap privacy is turned off after an incoming swap and a ZEC-to-X swap were
/// quoted. Turning it off refuses new addresses but does not strand the ones NEAR
/// already holds: the swap is still funded with its refund marker, the payout and the
/// refund are found live, and a restore made while it is still off finds both and can
/// spend them. Private queries off refuses new addresses through the same check (see
/// `require_new_address`), which regtest cannot reach on its own.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn turning_swap_privacy_off_mid_swap_keeps_finding_its_funds() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    world
        .payer
        .pay(&world.stack, &[(&a.address, 2 * ZEC)], OvkPolicy::Sender);
    world.stack.mine(10);
    world.sync(&a);
    let incoming = world.quote_incoming(&a, HOUR);
    let refund = world.quote_refund(&a, HOUR);

    sync_api::set_near_swap_privacy_enabled(false);
    for refused in [
        a.quote_incoming(&world.stack, &mut world.near, HOUR).err(),
        a.quote_refund(&world.stack, &mut world.near, HOUR).err(),
    ] {
        let refused = refused.expect("no new address while swap privacy is off");
        assert!(refused.contains("NEAR swap privacy"), "{refused}");
    }
    let (_, txid) = a.fund_swap(&world.stack, &refund, ZEC / 2);
    world.stack.mine(1);
    world.check_funding(&txid, &refund.deposit, ZEC / 2);
    world.sync(&a);
    let funded = a.total();

    world.stack.advance(20 * MINUTE);
    world.pay(&incoming.address, PAYOUT);
    world.pay(&refund.address, ZEC / 2);
    assert!(
        world.sync_until(&a, funded + PAYOUT + ZEC / 2, 3),
        "A finds the payout and the refund with swap privacy off (holds {})",
        a.total()
    );
    a.observe_incoming(&world.stack, &incoming, "SUCCESS", PAYOUT);
    a.observe_refund(&world.stack, &refund, "REFUNDED", ZEC / 2);
    world.stack.mine(12);
    world.sync(&a);

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    assert!(
        world.sync_until(&b, a.total(), 15),
        "B, restored with swap privacy off, finds both (holds {}, A holds {})",
        b.total(),
        a.total()
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for both payments with swap privacy off"
    );
    world.spend_all(&b);
    sync_api::set_near_swap_privacy_enabled(true);
}

/// NEAR gives two incoming swaps the same deposit address with different memos. The
/// first swap's SUCCESS closes only its own key: the second keeps scanning and finds its
/// payout live after the first closed, and a restore finds both.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn incoming_swaps_sharing_a_deposit_address_keep_their_own_statuses() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    let first = world.quote_incoming_to(&a, HOUR, Some(("near-shared-deposit", "1")));
    let second = world.quote_incoming_to(&a, HOUR, Some(("near-shared-deposit", "2")));

    world.stack.advance(20 * MINUTE);
    world.pay(&first.address, PAYOUT);
    assert!(
        world.sync_until(&a, PAYOUT, 3),
        "A finds the first payout (holds {})",
        a.total()
    );
    a.observe_incoming(&world.stack, &first, "SUCCESS", PAYOUT);
    world.stack.mine(12);
    world.sync(&a);
    assert!(a.key_closed(&first.receiver), "the first swap's key closed");
    assert!(
        !a.key_closed(&second.receiver),
        "the first swap's SUCCESS left the second swap's key scanning"
    );

    world.pay(&second.address, PAYOUT / 2);
    assert!(
        world.sync_until(&a, PAYOUT + PAYOUT / 2, 3),
        "A finds the second payout live (holds {})",
        a.total()
    );
    a.observe_incoming(&world.stack, &second, "SUCCESS", PAYOUT / 2);
    world.stack.mine(12);
    world.sync(&a);
    assert!(
        a.key_closed(&second.receiver),
        "the second swap's key closed"
    );

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    assert!(
        world.sync_until(&b, a.total(), 15),
        "B, restored from A's seed, finds both payouts (holds {}, A holds {})",
        b.total(),
        a.total()
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for both payouts"
    );
    world.spend_all(&b);
}

/// NEAR pays two of A's incoming addresses in one transaction, and A spends both payouts
/// before restoring its seed on another device. The restore finds both notes through the
/// receiver directory after it already scanned the block that spent them, and must
/// count them as spent, not as funds it can send again.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn a_restore_after_two_payouts_in_one_transaction_were_spent_holds_nothing() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    let swaps = [
        world.quote_incoming(&a, HOUR),
        world.quote_incoming(&a, HOUR),
    ];
    let payouts = [PAYOUT, PAYOUT / 2];

    world.stack.advance(20 * MINUTE);
    world.payer.pay(
        &world.stack,
        &[
            (&swaps[0].address, payouts[0]),
            (&swaps[1].address, payouts[1]),
        ],
        zero_ovk(),
    );
    world.stack.mine(1);
    assert!(
        world.sync_until(&a, payouts[0] + payouts[1], 3),
        "A finds both payouts (holds {})",
        a.total()
    );
    for (swap, payout) in swaps.iter().zip(payouts) {
        a.observe_incoming(&world.stack, swap, "SUCCESS", payout);
    }
    world.stack.mine(12);
    world.sync(&a);
    world.spend_all(&a);
    assert_eq!(a.total(), 0, "A sent everything it held");

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    let mut rounds = 0;
    while b.one_time_notes() < 2 && rounds < 15 {
        if rounds > 0 {
            world.stack.mine(1);
        }
        world.sync(&b);
        rounds += 1;
    }
    assert_eq!(
        b.one_time_notes(),
        2,
        "B, restored from A's seed, finds both payouts"
    );
    assert_eq!(
        b.unspent_one_time_value(),
        0,
        "B counts A's spend of both payouts"
    );
    assert_eq!(b.total(), 0, "B holds nothing A already spent");
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for both payouts"
    );
}

/// A ZEC-to-X swap whose deposit NEAR reports as INCOMPLETE_DEPOSIT, which is not final.
/// The refund key keeps scanning three weeks past the quote's deadline, inside the 30
/// day completion limit, so NEAR's late refund of the underpayment is found live, and a
/// restore finds it too and can spend it.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn an_underpaid_swap_refunded_weeks_after_its_deadline_is_found_live() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    world
        .payer
        .pay(&world.stack, &[(&a.address, 2 * ZEC)], OvkPolicy::Sender);
    world.stack.mine(10);
    world.sync(&a);
    let swap = world.quote_refund(&a, HOUR);
    let receiver = receiver_of(&swap.address);
    a.fund_swap(&world.stack, &swap, ZEC / 2);
    world.stack.mine(1);
    world.sync(&a);
    let funded = a.total();

    world.stack.advance(30 * MINUTE);
    a.observe_refund(&world.stack, &swap, "INCOMPLETE_DEPOSIT", 0);
    world.stack.advance(21 * DAY);
    world.stack.mine(12);
    world.sync(&a);
    assert!(
        !a.key_closed(&receiver),
        "the refund key still scans three weeks after the deadline"
    );

    world.pay(&swap.address, ZEC / 2);
    assert!(
        world.sync_until(&a, funded + ZEC / 2, 3),
        "A finds the late refund live (holds {})",
        a.total()
    );
    a.observe_refund(&world.stack, &swap, "REFUNDED", ZEC / 2);
    world.stack.mine(12);
    world.sync(&a);
    assert!(a.key_closed(&receiver), "the refund key closed");

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    assert!(
        world.sync_until(&b, a.total(), 15),
        "B, restored from A's seed, finds the refund (holds {}, A holds {})",
        b.total(),
        a.total()
    );
    assert!(
        b.early_restore_accepted(),
        "B's restore scan looked for the refund"
    );
    world.spend_all(&b);
}

/// A wallet whose incoming swap NEAR paid out two days ago, found and settled, so a
/// restore of its seed from `birthday` has one payout to find. Returns the wallet and
/// `birthday`.
fn settled_payout(world: &mut World) -> (Wallet, u32) {
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    let swap = world.quote_incoming(&a, HOUR);
    world.stack.advance(20 * MINUTE);
    world.pay(&swap.address, PAYOUT);
    assert!(
        world.sync_until(&a, PAYOUT, 3),
        "A finds the payout while scanning"
    );
    a.observe_incoming(&world.stack, &swap, "SUCCESS", PAYOUT);
    world.stack.mine(12);
    world.sync(&a);
    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    (a, birthday)
}

/// A restore begins against a publication whose last block a reorg replaced before the
/// directory republished. The scan stores the new branch's block at that height, so the
/// wallet rejects the publication and leaves the paid key to restore sweeps, which find
/// the payout once the directory republishes on the new chain, counted once.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn a_reorg_replacing_the_publications_last_block_leaves_the_restore_to_sweeps() {
    let _guard = lock();
    let mut world = World::start();
    let (a, birthday) = settled_payout(&mut world);
    world.publish();
    let anchor = world.stack.tip() - 2;
    world.stack.reorg(anchor - 1);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    // Without a republish, B begins against the publication the reorg made stale.
    b.sync(&world.stack);
    assert_eq!(
        b.early_restore(),
        Some((anchor, 2)),
        "B's scan stored another block at the publication's last height"
    );
    assert!(
        world.sync_until(&b, PAYOUT, 15),
        "restore sweeps find the payout once the directory republishes (holds {})",
        b.total()
    );
    assert_eq!(b.one_time_notes(), 1, "B counts the payout once");
    world.spend_all(&b);
}

/// A restore's early restore is accepted and inserts the payout, then a reorg replaces
/// blocks between the payout and the publication's last block. The rewind makes the
/// publication provisional again and the rescan rejects it, since another block now sits
/// at its last height. The payout, below the fork, stays counted once through the
/// restore sweeps that follow, and B can spend it.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn a_reorg_below_an_accepted_publication_keeps_the_payout_once() {
    let _guard = lock();
    let mut world = World::start();
    let (a, birthday) = settled_payout(&mut world);
    let b = Wallet::import("B", &a.mnemonic, birthday);
    assert!(
        world.sync_until(&b, PAYOUT, 10),
        "B, restored from A's seed, finds the payout (holds {})",
        b.total()
    );
    let (anchor, state) = b.early_restore().expect("B began an early restore");
    assert_eq!(state, 1, "B's restore scan looked for the payout");

    world.stack.reorg(anchor - 1);
    for round in 0..6 {
        if round > 0 {
            world.stack.mine(1);
        }
        world.sync(&b);
        assert_eq!(b.total(), PAYOUT, "B holds the payout once (round {round})");
    }
    assert_eq!(
        b.early_restore(),
        Some((anchor, 2)),
        "the rescan rejected the publication whose last block the reorg replaced"
    );
    assert_eq!(b.one_time_notes(), 1, "B counts the payout once");
    world.spend_all(&b);
}

/// A restore made while the receiver directory is unreachable recovers the refund key
/// from the funding memo but cannot find the refund, which only the key's directory
/// sweep looks for. The sweep waits, and finds the refund once the directory is back.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn a_restore_during_a_directory_outage_finds_the_refund_once_it_returns() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    let birthday = world.stack.tip();
    world
        .payer
        .pay(&world.stack, &[(&a.address, 2 * ZEC)], OvkPolicy::Sender);
    world.stack.mine(10);
    world.sync(&a);
    let swap = world.quote_refund(&a, HOUR);
    a.fund_swap(&world.stack, &swap, ZEC / 2);
    world.stack.mine(1);
    world.pay(&swap.address, ZEC / 2);
    world.sync(&a);
    a.observe_refund(&world.stack, &swap, "REFUNDED", ZEC / 2);
    world.stack.mine(12);
    world.sync(&a);

    world.stack.advance(2 * DAY);
    world.stack.mine(1);
    // Nothing listens on the discard port, so every directory request fails at once.
    std::env::set_var("VIZOR_RECEIVER_PIR_URL", "http://127.0.0.1:9");
    let b = Wallet::import("B", &a.mnemonic, birthday);
    let lookups = world.directory.lookups();
    world.sync_until(&b, a.total(), 4);
    std::env::set_var("VIZOR_RECEIVER_PIR_URL", world.directory.origin());
    assert_eq!(
        world.directory.lookups(),
        lookups,
        "B never reached the directory"
    );
    assert!(
        !b.early_restore_accepted(),
        "B's early restore cannot begin without the directory, so sweeps take over"
    );
    assert!(
        b.refund_key_indices().contains(&swap.index),
        "B recovered the refund key from the funding memo"
    );
    assert_eq!(
        b.total(),
        a.total() - ZEC / 2,
        "B holds everything but the refund, which waits for the sweep"
    );
    assert!(
        world.sync_until(&b, a.total(), 4),
        "B finds the refund once the directory is back (holds {}, A holds {})",
        b.total(),
        a.total()
    );
    world.spend_all(&b);
}

/// A device that quoted a ZEC-to-X swap but did not send its funding, here a copy of its
/// database taken after the quote, meets the funding and NEAR's refund one block later
/// in the same scan batch. The refund key starts scanning at the funding block only once
/// that batch is scanned, so the device must rescan the blocks after it to find the
/// refund.
#[test]
#[ignore = "requires the Dockerized Ironwood zcashd/lightwalletd regtest stack"]
fn a_refund_key_that_starts_mid_batch_rescans_the_blocks_it_missed() {
    let _guard = lock();
    let mut world = World::start();
    let a = world.wallet("A");
    world
        .payer
        .pay(&world.stack, &[(&a.address, 2 * ZEC)], OvkPolicy::Sender);
    world.stack.mine(10);
    world.sync(&a);
    let swap = world.quote_refund(&a, HOUR);

    let other = a.copy_device("A copy");
    let (fee, _) = other.fund_swap(&world.stack, &swap, ZEC / 2);
    world.stack.mine(1);
    world.pay(&swap.address, ZEC / 2);
    assert!(
        world.sync_until(&a, 2 * ZEC - fee, 4),
        "A finds the refund after its key started mid-batch (holds {}, expected {})",
        a.total(),
        2 * ZEC - fee
    );
    world.spend_all(&a);
}
