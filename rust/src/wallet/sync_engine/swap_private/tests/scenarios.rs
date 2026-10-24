//! Seeded, model-based scenarios for private swap recovery. A world of one synthetic
//! chain, a receiver service published from it, a mocked NEAR 1Click provider and several
//! app wallets on the same seeds is driven by randomly chosen actions. An independent
//! model of what the chain pays to the seeds' one-time keys is checked against every
//! wallet after each step and again at quiescence, after enough mining and rounds.
//!
//! `VIZOR_SCENARIO_SEED`, `VIZOR_SCENARIO_ITERS` and `VIZOR_SCENARIO_STEPS` pick the runs.
//! `VIZOR_SCENARIO_KEEP` replays a seed with only the listed action indexes, which is what
//! a shrunk failure prints. `VIZOR_SCENARIO_SHRINK` bounds shrinking replays, and 0 turns
//! shrinking off.
//! Known product findings are counted as notes rather than failed, so the default lane
//! stays green while they are open. `VIZOR_SCENARIO_STRICT=1` fails on them too (see
//! [`World::note`]). `VIZOR_SCENARIO_MIX=stress` weights the actions toward multi-device
//! refunds, restores, deep reorgs and toggling, and `VIZOR_SCENARIO_MIX=toggle` toward
//! turning the feature on and off mid-round, across restarts and in quick succession
//! (see [`generate`]). `VIZOR_SCENARIO_AGE`
//! is the share of seeds, per mille, whose quiescence ends past the memo refund window
//! (see [`World::age`]). `VIZOR_SCENARIO_VERBOSE` prints the trace of passing seeds too.
use super::*;
use std::{
    collections::{BTreeMap, BTreeSet},
    panic::AssertUnwindSafe,
    sync::{
        atomic::{AtomicUsize, Ordering as AtomicOrdering},
        Arc, Mutex,
    },
};
use zakura_one_time_ivk::Purpose;
use zcash_primitives::transaction::Transaction;

mod directed;
mod toggles;

/// The seed every device restores, and a second seed some devices add as an account.
const MAIN: u8 = 4;
const SECOND: u8 = 5;
/// The seed of the account without an Orchard key.
const NO_ORCHARD: u8 = 9;
const MAX_DEVICES: usize = 5;
/// Longer than the library's longest lookup backoff, so deferred work is due again.
const PAST_BACKOFF: i64 = 50_000;

/// How long past its deadline a started quote keeps its slot without a fresh conclusive
/// status, as the library's `STARTED_STATUS_GRACE_SECONDS`.
const STARTED_STATUS_GRACE: i64 = 24 * 60 * 60;

/// How long a refund key with no local operation stays monitored past its funding, as the
/// library's `MEMO_REFUND_WINDOW`: seven days of 75-second blocks.
const MEMO_REFUND_WINDOW: u32 = 7 * 24 * 60 * 60 / 75;

/// A small deterministic generator (SplitMix64).
#[derive(Clone)]
pub(super) struct Rng(u64);

impl Rng {
    /// A generator for `seed`.
    pub(super) fn new(seed: u64) -> Self {
        Self(seed ^ 0x9e37_79b9_7f4a_7c15)
    }
    /// The next 64 random bits.
    pub(super) fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }
    /// A value in `0..n`, or 0 when `n` is 0.
    pub(super) fn below(&mut self, n: u64) -> u64 {
        if n == 0 {
            0
        } else {
            self.next() % n
        }
    }
    /// True with probability `per_mille / 1000`.
    pub(super) fn chance(&mut self, per_mille: u64) -> bool {
        self.below(1000) < per_mille
    }
}

/// What a held worker round's request waits for while the test acts.
#[derive(Clone, Copy, Debug)]
pub(super) enum During {
    Mine,
    Toggle,
    Cancel,
    Reorg,
}

/// How the provider answers an incoming quote request.
#[derive(Clone, Copy, Debug)]
pub(super) enum Reply {
    Accept,
    Reject,
    /// No answer reaches the wallet, so the outcome stays unknown.
    Timeout,
}

/// A provider status change that pays no ZEC.
#[derive(Clone, Copy, Debug)]
pub(super) enum Change {
    /// Incoming: refunded on the origin chain. Outgoing: success with no refund.
    Done,
    /// The provider fails the swap.
    Failed,
    /// An underpaid deposit, refunded around the deadline.
    Incomplete,
    /// Outgoing success without a reported refund amount.
    Unreported,
}

/// One scenario step. Entities are named by index modulo their current count, so a trace
/// stays executable after other steps are dropped while shrinking.
#[derive(Clone, Debug)]
pub(super) enum Action {
    Mine(u32),
    Reorg(u32),
    Sync {
        dev: usize,
        enhance: bool,
    },
    Enhance(usize),
    Round {
        dev: usize,
        fail: u64,
        upgrade: bool,
        lag: u32,
        recent: bool,
        seal: bool,
        false_hit: bool,
        seed: u64,
    },
    HeldRound {
        dev: usize,
        query: bool,
        nth: usize,
        during: During,
    },
    QuoteIn {
        dev: usize,
        acct: usize,
        reply: Reply,
        ttl: i64,
    },
    LateReply {
        quote: usize,
        accept: bool,
    },
    QuoteOut {
        dev: usize,
        acct: usize,
        ttl: i64,
    },
    Fund {
        quote: usize,
    },
    Deposit {
        quote: usize,
    },
    Payout {
        quote: usize,
        value: u64,
    },
    Refund {
        quote: usize,
        partial: bool,
        failed: bool,
    },
    Status {
        quote: usize,
        change: Change,
    },
    Poll {
        dev: usize,
        errors: u64,
    },
    Warp(i64),
    Toggle(usize),
    PrivateQueries(usize),
    Manual {
        dev: usize,
        bound: Option<u64>,
        cancel: Option<usize>,
    },
    Restore {
        back: u32,
        feature: bool,
    },
    AddAccount(usize),
    AddNoOrchard(usize),
    DeleteAccount {
        dev: usize,
        acct: usize,
    },
    /// An app restart on a device, which reopens its wallet (see [`World::restart`]).
    Restart(usize),
    /// A whole incoming swap: quote, deposit and payout.
    Swap {
        dev: usize,
        acct: usize,
        value: u64,
    },
    /// A whole outgoing swap: quote and funding, then `outcome` 0 no refund, 1 a small
    /// refund with success, 2 a full refund, 3 nothing yet.
    SwapOut {
        dev: usize,
        acct: usize,
        outcome: u8,
    },
    /// A round whose `nth` request of `class` (0 filters, 1 query, 2 witness, 3 a sealed
    /// shard's filter) is held while the feature turns off, with the app's worker
    /// cancellation when `cancel`, and back on at once when `back`.
    HeldToggle {
        dev: usize,
        class: u8,
        nth: usize,
        cancel: bool,
        back: bool,
    },
    /// `flips` reconciled toggles in quick succession, while a round starts when `round`.
    RapidToggle {
        dev: usize,
        flips: u8,
        round: bool,
    },
    /// Saves the feature as `feature`, reconciled or not as when the app dies first, then
    /// restarts the app and runs its first round.
    RestartToggle {
        dev: usize,
        feature: bool,
        reconcile: bool,
    },
    /// A settings history check whose `nth` query is held while the feature turns off, and
    /// back on at once when `back`.
    ManualToggle {
        dev: usize,
        nth: usize,
        back: bool,
    },
}

/// Which action weights [`generate`] uses, from `VIZOR_SCENARIO_MIX`.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Mix {
    Default,
    Stress,
    Toggle,
}

/// The mix `VIZOR_SCENARIO_MIX` names: `stress`, `toggle`, or the default.
fn mix() -> Mix {
    match std::env::var("VIZOR_SCENARIO_MIX").as_deref() {
        Ok("stress") => Mix::Stress,
        Ok("toggle") => Mix::Toggle,
        _ => Mix::Default,
    }
}

/// Draws `steps` actions from `seed`, independently of how they will play out. The stress
/// mix adds outgoing swaps, restores at more birthdays, deep and back-to-back reorgs and
/// toggles. The toggle mix replaces about a third of the draws with feature and Private
/// queries toggles, toggles while a filter, query or witness answer or a history check is
/// held, rapid toggles while a round starts, toggles across a restart and feature-off
/// restores. Both leave the default mix's draws for a seed unchanged.
pub(super) fn generate(seed: u64, steps: usize) -> Vec<Action> {
    let stress = mix() == Mix::Stress;
    let toggle = mix() == Mix::Toggle;
    let mut rng = Rng::new(seed);
    let mut actions = Vec::with_capacity(steps + 1);
    while actions.len() < steps {
        let dev = rng.below(8) as usize;
        let acct = rng.below(4) as usize;
        let quote = rng.below(16) as usize;
        let roll = rng.below(1000);
        if toggle && rng.chance(330) {
            actions.push(match rng.below(12) {
                0 | 1 => Action::Toggle(dev),
                2 => Action::PrivateQueries(dev),
                3 | 4 => Action::HeldToggle {
                    dev,
                    class: rng.below(4) as u8,
                    nth: rng.below(2) as usize,
                    cancel: rng.chance(500),
                    back: rng.chance(600),
                },
                5 => Action::RapidToggle {
                    dev,
                    flips: 2 + rng.below(4) as u8,
                    round: rng.chance(700),
                },
                6 => Action::RestartToggle {
                    dev,
                    feature: rng.chance(500),
                    reconcile: rng.chance(500),
                },
                7 => Action::ManualToggle {
                    dev,
                    nth: rng.below(2) as usize,
                    back: rng.chance(600),
                },
                8 => Action::Restore {
                    back: [0, 3, 20][rng.below(3) as usize],
                    feature: rng.chance(400),
                },
                9 => Action::HeldRound {
                    dev,
                    query: rng.chance(600),
                    nth: rng.below(3) as usize,
                    during: During::Toggle,
                },
                // Work in flight for the next toggle to cross.
                10 => Action::Swap {
                    dev,
                    acct,
                    value: 200_000 + 10_000 * rng.below(50),
                },
                _ => Action::QuoteIn {
                    dev,
                    acct,
                    reply: [Reply::Accept, Reply::Timeout][rng.below(2) as usize],
                    ttl: 600 + rng.below(7_200) as i64,
                },
            });
            continue;
        }
        if stress && rng.chance(160) {
            match rng.below(4) {
                0 => actions.push(Action::Reorg(8 + rng.below(13) as u32)),
                1 => {
                    actions.push(Action::Reorg(1 + rng.below(4) as u32));
                    actions.push(Action::Reorg(1 + rng.below(4) as u32));
                }
                2 => actions.push(Action::Restore {
                    back: [1, 3, 8, 15, 30][rng.below(5) as usize],
                    feature: rng.chance(750),
                }),
                _ => actions.push(Action::Toggle(dev)),
            }
            continue;
        }
        if rng.chance(if stress { 220 } else { 120 }) {
            actions.push(if rng.chance(if stress { 350 } else { 650 }) {
                Action::Swap {
                    dev,
                    acct,
                    value: 200_000 + 10_000 * rng.below(50),
                }
            } else {
                Action::SwapOut {
                    dev,
                    acct,
                    outcome: rng.below(4) as u8,
                }
            });
            continue;
        }
        let roll = roll % 995;
        let action = match roll {
            0..=89 => Action::Mine(1 + rng.below(3) as u32),
            90..=119 => Action::Reorg(1 + rng.below(6) as u32),
            120..=219 => Action::Sync {
                dev,
                enhance: rng.chance(700),
            },
            220..=239 => Action::Enhance(dev),
            240..=379 => Action::Round {
                dev,
                fail: [0, 0, 0, 100, 300][rng.below(5) as usize],
                upgrade: rng.chance(40),
                lag: [0, 0, 0, 1, 3][rng.below(5) as usize],
                recent: rng.chance(200),
                seal: rng.chance(150),
                false_hit: rng.chance(150),
                seed: rng.next(),
            },
            380..=409 => Action::HeldRound {
                dev,
                query: rng.chance(700),
                nth: rng.below(3) as usize,
                during: [During::Mine, During::Toggle, During::Cancel, During::Reorg]
                    [rng.below(4) as usize],
            },
            410..=519 => Action::QuoteIn {
                dev,
                acct,
                reply: [
                    Reply::Accept,
                    Reply::Accept,
                    Reply::Accept,
                    Reply::Reject,
                    Reply::Timeout,
                ][rng.below(5) as usize],
                ttl: 600 + rng.below(7_200) as i64,
            },
            520..=534 => Action::LateReply {
                quote,
                accept: rng.chance(700),
            },
            535..=574 => Action::QuoteOut {
                dev,
                acct,
                ttl: 600 + rng.below(7_200) as i64,
            },
            575..=599 => Action::Fund { quote },
            600..=649 => Action::Deposit { quote },
            650..=714 => Action::Payout {
                quote,
                value: 100_000 + 10_000 * rng.below(100),
            },
            715..=739 => Action::Refund {
                quote,
                partial: rng.chance(400),
                failed: rng.chance(200),
            },
            740..=769 => Action::Status {
                quote,
                change: [
                    Change::Done,
                    Change::Done,
                    Change::Failed,
                    Change::Incomplete,
                    Change::Unreported,
                ][rng.below(5) as usize],
            },
            770..=829 => Action::Poll {
                dev,
                errors: [0, 0, 300][rng.below(3) as usize],
            },
            830..=859 => Action::Warp([600, 3_600, 3 * 3_600, 2 * 86_400][rng.below(4) as usize]),
            860..=884 => Action::Toggle(dev),
            885..=894 => Action::PrivateQueries(dev),
            895..=924 => Action::Manual {
                dev,
                bound: rng.chance(400).then(|| 4 + rng.below(12)),
                cancel: rng.chance(300).then(|| rng.below(3) as usize),
            },
            925..=954 => Action::Restore {
                back: [0, 0, 5, 20][rng.below(4) as usize],
                feature: rng.chance(800),
            },
            955..=969 => Action::AddAccount(dev),
            970..=979 => Action::AddNoOrchard(dev),
            980..=989 => Action::DeleteAccount { dev, acct },
            990..=994 => Action::Restart(dev),
            _ => unreachable!(),
        };
        actions.push(action);
    }
    actions.truncate(steps);
    actions
}

/// A broken promise, with enough detail to triage it.
#[derive(Clone, Debug)]
pub(super) struct Violation {
    pub(super) kind: &'static str,
    pub(super) detail: String,
}

/// Builds a [`Violation`].
fn violation(kind: &'static str, detail: impl Into<String>) -> Violation {
    Violation {
        kind,
        detail: detail.into(),
    }
}

/// A payment the chain mined to one of a seed's one-time keys.
#[derive(Clone, Debug)]
struct Pay {
    seed: u8,
    receive: bool,
    index: u64,
    value: u64,
    height: u32,
    txid: [u8; 32],
    orphaned: bool,
}

/// A funding transaction a device broadcast for an outgoing swap.
struct Funding {
    seed: u8,
    refund: u64,
    tx: Transaction,
    raw: Vec<u8>,
    /// Where it is mined on the current chain. A reorg that drops it mines it again.
    height: u32,
    nullifiers: Vec<[u8; 32]>,
}

/// The provider's view of one quote and the device that asked for it.
#[derive(Clone, Debug)]
struct Quote {
    dev: usize,
    uuid: String,
    seed: u8,
    incoming: bool,
    index: u64,
    request: Option<String>,
    deposit: String,
    /// Unix seconds in the wallets' clock domain, shifted by every warp.
    deadline: i64,
    accepted: bool,
    started: bool,
    rejected: bool,
    funded: bool,
    status: &'static str,
    refunded: Option<u64>,
    amount_out: Option<u64>,
    omit_refund: bool,
    /// Zcash transactions the provider reports for this swap, in internal byte order.
    hashes: Vec<[u8; 32]>,
    /// Payments the provider owes and re-sends after a reorg drops them.
    owed: Vec<(u64, [u8; 32])>,
    /// The wallet said it no longer tracks this address, so the app stopped polling.
    released: bool,
    /// The owning device recorded a status saying the provider saw a deposit.
    funded_seen: bool,
}

impl Quote {
    /// A quote `dev` asked for on key `index`, before any answer or provider progress.
    fn new(
        dev: usize,
        uuid: String,
        seed: u8,
        incoming: bool,
        index: u64,
        deposit: String,
        deadline: i64,
    ) -> Self {
        Self {
            dev,
            uuid,
            seed,
            incoming,
            index,
            request: None,
            deposit,
            deadline,
            accepted: false,
            started: false,
            rejected: false,
            funded: false,
            status: "PENDING_DEPOSIT",
            refunded: None,
            amount_out: None,
            omit_refund: false,
            hashes: vec![],
            owed: vec![],
            released: false,
            funded_seen: false,
        }
    }

    /// Whether the provider has reported a final status.
    fn concluded(&self) -> bool {
        matches!(self.status, "SUCCESS" | "REFUNDED" | "FAILED")
    }
}

/// One seed account on a device.
struct Acct {
    account: Account,
    seed: u8,
    birthday: u32,
    /// Receive indexes this account reserved.
    reserved: BTreeSet<u64>,
}

/// One app install.
struct Device {
    wallet: Wallet,
    birthday: u32,
    feature: bool,
    queries: bool,
    ever_enabled: bool,
    accts: Vec<Acct>,
    no_orchard: bool,
    /// Ordinary sync could not follow a reorg, so the device is left out of later steps
    /// and checks. This also fails the run (see [`World::rewind_refused`]), unless the
    /// reorg replaced the block below the birthday, an open finding.
    broken: bool,
    /// The hash of the block below the birthday when the device was restored, whose tree
    /// state the wallet starts from.
    anchor: [u8; 32],
}

impl Device {
    /// Whether discovery runs: Private queries and NEAR swap privacy both on.
    fn discovery(&self) -> bool {
        self.feature && self.queries
    }
}

/// Fails a configurable share of receiver requests and counts every request.
struct Faulty<'a> {
    service: &'a Service,
    rng: Mutex<Rng>,
    fail: u64,
    requests: AtomicUsize,
}

impl Faulty<'_> {
    /// Counts a request and decides whether it fails.
    fn roll(&self) -> Result<(), session::Error> {
        self.requests.fetch_add(1, AtomicOrdering::SeqCst);
        if self.rng.lock().unwrap().chance(self.fail) {
            Err(session::Error::Transport("injected failure".into()))
        } else {
            Ok(())
        }
    }
}

impl Transport for Faulty<'_> {
    /// A public read that may fail.
    async fn get(&self, url: &str, limit: usize) -> Result<Vec<u8>, session::Error> {
        self.roll()?;
        self.service.get(url, limit).await
    }
    /// An encrypted query that may fail.
    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, session::Error> {
        self.roll()?;
        self.service.post(url, body, limit).await
    }
}

/// One credited one-time note as the wallet stores it.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(super) struct Note {
    pub(super) receive: bool,
    pub(super) index: u64,
    pub(super) txid: [u8; 32],
    pub(super) value: u64,
    pub(super) mined: bool,
    pub(super) spent: bool,
    pub(super) nf: [u8; 32],
}

/// Every one-time note `account` holds, mined or not.
pub(super) fn notes(wallet: &Wallet, account: &AccountUuid) -> Vec<Note> {
    let conn = rusqlite::Connection::open(&wallet.path).unwrap();
    let mut statement = conn
        .prepare(
            "SELECT k.purpose, k.key_index, t.txid, n.value, t.mined_height IS NOT NULL, n.nf,
                EXISTS(SELECT 1 FROM ironwood_received_note_spends s
                    JOIN transactions st ON st.id_tx = s.transaction_id
                    WHERE s.ironwood_received_note_id = n.id AND st.mined_height IS NOT NULL)
             FROM ironwood_received_notes n
             JOIN transactions t ON t.id_tx = n.transaction_id
             JOIN ironwood_one_time_keys k ON k.id = n.one_time_key_id
             JOIN accounts a ON a.id = n.account_id
             WHERE a.uuid = ?1",
        )
        .unwrap();
    statement
        .query_map([account.expose_uuid().as_bytes()], |r| {
            Ok(Note {
                receive: r.get::<_, u8>(0)? == 1,
                index: u64::from_be_bytes(r.get::<_, [u8; 8]>(1)?),
                txid: r.get(2)?,
                value: r.get::<_, i64>(3)? as u64,
                mined: r.get(4)?,
                nf: r.get(5)?,
                spent: r.get(6)?,
            })
        })
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap()
}

/// Rows in the per-account recovery table, which a wallet that never enabled the feature
/// must not have.
fn recovery_rows(wallet: &Wallet) -> i64 {
    rusqlite::Connection::open(&wallet.path)
        .unwrap()
        .query_row("SELECT COUNT(*) FROM ironwood_one_time_recovery", [], |r| {
            r.get(0)
        })
        .unwrap_or(0)
}

/// Every row the one-time feature keeps in `wallet`: its own tables, the receiver
/// descriptor cache and the notes its keys received, each as text and sorted, so a step
/// that must write nothing can be compared before and after.
pub(super) fn one_time_snapshot(wallet: &Wallet) -> Vec<String> {
    let conn = rusqlite::Connection::open(&wallet.path).unwrap();
    let mut queries: Vec<(String, String)> = conn
        .prepare(
            "SELECT name FROM sqlite_master WHERE type = 'table'
             AND (name LIKE 'ironwood_one_time%' OR name = 'ext_vizor_receiver_inventory')",
        )
        .unwrap()
        .query_map([], |r| r.get::<_, String>(0))
        .unwrap()
        .map(|name| {
            let name = name.unwrap();
            (name.clone(), format!("SELECT * FROM {name}"))
        })
        .collect();
    queries.push((
        "one-time notes".into(),
        "SELECT * FROM ironwood_received_notes WHERE one_time_key_id IS NOT NULL".into(),
    ));
    let mut rows = Vec::new();
    for (name, query) in queries {
        let mut statement = conn.prepare(&query).unwrap();
        let columns = statement.column_count();
        let mut table: Vec<String> = statement
            .query_map([], |r| {
                (0..columns)
                    .map(|i| r.get::<_, rusqlite::types::Value>(i))
                    .collect::<Result<Vec<_>, _>>()
            })
            .unwrap()
            .map(|row| format!("{name} {:?}", row.unwrap()))
            .collect();
        table.sort();
        rows.extend(table);
    }
    rows
}

/// The rows only one of two [`one_time_snapshot`]s holds, for a violation's detail.
fn snapshot_diff(before: &[String], after: &[String]) -> String {
    let gone: Vec<&String> = before.iter().filter(|r| !after.contains(r)).collect();
    let new: Vec<&String> = after.iter().filter(|r| !before.contains(r)).collect();
    format!("removed {gone:?}, added {new:?}")
}

/// Whether `account` holds a one-time receipt a reorg displaced or whose label is
/// disputed, which a round repairs even with the feature off. This covers more than the
/// library's own test, which also lets an expired displaced receipt go.
fn repair_owed(wallet: &Wallet, account: &AccountUuid) -> bool {
    rusqlite::Connection::open(&wallet.path)
        .unwrap()
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM ironwood_received_notes n
                 JOIN transactions t ON t.id_tx = n.transaction_id
                 JOIN accounts a ON a.id = n.account_id
                 WHERE a.uuid = ?1 AND n.one_time_key_id IS NOT NULL
                   AND (t.mined_height IS NULL OR n.commitment_tree_position IS NULL
                        OR EXISTS(SELECT 1 FROM ironwood_one_time_disputed_receipts d
                            WHERE d.note_id = n.id)))",
            [account.expose_uuid().as_bytes()],
            |r| r.get(0),
        )
        .unwrap()
}

/// Whether an error message reports wallet lock contention.
fn locked(message: &str) -> bool {
    message.contains("locked") || message.contains("busy")
}

/// The receive index the wallet's own payment evidence justifies, as issuance reads it.
fn evidence_high(wallet: &Wallet, account: &AccountUuid) -> Option<u64> {
    let conn = rusqlite::Connection::open(&wallet.path).unwrap();
    let high: Option<Vec<u8>> = conn
        .query_row(
            "SELECT MAX(k.key_index) FROM ironwood_one_time_keys k JOIN accounts a ON a.id = k.account_id
             WHERE a.uuid = ?1 AND k.purpose = 1 AND (k.prebirthday_height IS NOT NULL
                 OR EXISTS(SELECT 1 FROM ironwood_received_notes n JOIN transactions t ON t.id_tx = n.transaction_id
                     WHERE n.one_time_key_id = k.id AND t.mined_height IS NOT NULL))",
            [account.expose_uuid().as_bytes()],
            |r| r.get(0),
        )
        .unwrap();
    high.map(|b| u64::from_be_bytes(b.try_into().unwrap()))
}

/// Refund indexes `account` has registered with funding evidence.
fn funded_refunds(wallet: &Wallet, account: &AccountUuid) -> BTreeSet<u64> {
    funding_heights(wallet, account)
        .into_iter()
        .map(|(index, _)| index)
        .collect()
}

/// Each refund index `account` holds funding evidence for, with its funding height.
fn funding_heights(wallet: &Wallet, account: &AccountUuid) -> Vec<(u64, u32)> {
    let conn = rusqlite::Connection::open(&wallet.path).unwrap();
    let mut statement = conn
        .prepare(
            "SELECT k.key_index, k.funding_height FROM ironwood_one_time_keys k
             JOIN accounts a ON a.id = k.account_id
             WHERE a.uuid = ?1 AND k.purpose = 0 AND k.funding_height IS NOT NULL",
        )
        .unwrap();
    statement
        .query_map([account.expose_uuid().as_bytes()], |r| {
            Ok((u64::from_be_bytes(r.get::<_, [u8; 8]>(0)?), r.get(1)?))
        })
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap()
}

/// Whether receive key `index` of `account` has invalidated history or a payment candidate
/// unresolved, which keeps its reservation (the library's `RECEIVE_PENDING`).
fn receive_pending(wallet: &Wallet, account: &AccountUuid, index: u64) -> bool {
    rusqlite::Connection::open(&wallet.path)
        .unwrap()
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM ironwood_one_time_keys k JOIN accounts a ON a.id = k.account_id
             WHERE a.uuid = ?1 AND k.purpose = 1 AND k.key_index = ?2 AND (
                 EXISTS(SELECT 1 FROM ironwood_one_time_lookups l
                     WHERE l.one_time_key_id = k.id AND l.reasons & 4 != 0)
                 OR EXISTS(SELECT 1 FROM ironwood_one_time_payment_recovery p
                     WHERE p.one_time_key_id = k.id)))",
            rusqlite::params![account.expose_uuid().as_bytes(), index.to_be_bytes()],
            |r| r.get(0),
        )
        .unwrap()
}

/// The frontier of `account`'s unfinished manual job, if it has one: a paused job, or a
/// finished one that a rewind below its frontier reopened. A history check resumes such a
/// job rather than starting a new one (see the library's `check_one_time_history`), so it
/// keeps that frontier (spec MAN-4).
fn resumed_frontier(wallet: &Wallet, account: &AccountUuid) -> Option<u32> {
    use rusqlite::OptionalExtension as _;
    let (purpose, next, end, height): (u8, [u8; 8], Option<[u8; 8]>, Option<u32>) =
        rusqlite::Connection::open(&wallet.path)
            .unwrap()
            .query_row(
                "SELECT r.manual_purpose, r.manual_next, r.manual_end, r.manual_height
                 FROM ironwood_one_time_recovery r JOIN accounts a ON a.id = r.account_id
                 WHERE a.uuid = ?1",
                [account.expose_uuid().as_bytes()],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
            )
            .optional()
            .unwrap()?;
    let (end, height) = (u64::from_be_bytes(end?), height?);
    (purpose == 0 || u64::from_be_bytes(next) < end).then_some(height)
}

/// The refund indexes the worker still monitors for `account`.
fn monitored_refunds(wallet: &Wallet, account: &AccountUuid) -> BTreeSet<u64> {
    wallet
        .db()
        .one_time_receivers(*account)
        .unwrap()
        .1
        .iter()
        .filter(|w| w.key.purpose() == Purpose::Refund)
        .map(|w| w.key.index())
        .collect()
}

/// The earlier of now and the latest block time, which quote deadlines are compared with.
fn deadline_clock(wallet: &Wallet) -> i64 {
    let now = now();
    rusqlite::Connection::open(&wallet.path)
        .unwrap()
        .query_row(
            "SELECT MIN(?1, IFNULL((SELECT time FROM blocks ORDER BY height DESC LIMIT 1), ?1))",
            [now],
            |r| r.get(0),
        )
        .unwrap()
}

/// Moves every stored one-time timestamp and block time `secs` into the past, which is
/// the same as the wallet's clock jumping `secs` ahead.
pub(super) fn warp(wallet: &Wallet, secs: i64) {
    let conn = rusqlite::Connection::open(&wallet.path).unwrap();
    let tables: Vec<String> = conn
        .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'ironwood_one_time%'")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    for table in tables {
        let columns: Vec<String> = conn
            .prepare(&format!("SELECT name FROM pragma_table_info('{table}')"))
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        for column in columns
            .iter()
            .filter(|c| c.ends_with("_at") || *c == "deadline")
        {
            conn.execute(
                &format!("UPDATE {table} SET {column} = {column} - ?1 WHERE {column} > 0"),
                [secs],
            )
            .unwrap();
        }
    }
    conn.execute("UPDATE blocks SET time = time - ?1 WHERE time > 0", [secs])
        .unwrap();
}

/// Applies a device's switches to the process, as the app does at startup and on toggle.
fn apply(device: &Device) {
    crate::api::sync::set_enhance_pir_enabled(device.queries);
    crate::api::sync::set_near_swap_privacy_enabled(device.feature);
}

/// Whether an error message reports the account without an Orchard key.
fn mentions_orchard(message: &str) -> bool {
    message.contains("Orchard full viewing key") || message.contains("require an Orchard")
}

/// The display form of an internal-order transaction ID, as 1Click reports it.
fn display_txid(txid: &[u8; 32]) -> String {
    zcash_primitives::transaction::TxId::from_bytes(*txid).to_string()
}

/// Publication options for one round.
#[derive(Clone, PartialEq, Eq)]
struct Publication {
    version: u64,
    pir_end: u32,
    first: u32,
    sealed: Option<u32>,
    false_hit: Option<(u32, u64)>,
}

/// The whole simulated world.
pub(super) struct World {
    chain: Chain,
    version: u64,
    service: Option<(Publication, Arc<Service>)>,
    devices: Vec<Device>,
    pays: Vec<Pay>,
    fundings: Vec<Funding>,
    quotes: Vec<Quote>,
    deposits: u64,
    setup_end: u32,
    /// Open findings the run met (see [`World::note`]).
    pub(super) notes: std::cell::RefCell<BTreeMap<&'static str, usize>>,
    /// The first rewind ordinary sync refused, which the next check reports.
    rewind_refused: Option<String>,
    /// Quiescence ends by aging every funding past [`MEMO_REFUND_WINDOW`] (see
    /// [`World::age`]).
    ages: bool,
    /// How many times a device's database was reopened under a new path (see
    /// [`World::restart`]).
    reopens: usize,
}

impl World {
    /// A chain with ordinary funds for both seeds and one device on the main seed.
    pub(super) fn new() -> Self {
        let mut chain = Chain::new();
        let main = Wallet::new(MAIN, activation()).account().clone();
        let second = {
            let mut w = Wallet::new(MAIN, activation());
            w.add_account(SECOND, activation())
        };
        chain.pay(&main.parent(), 300_000_000, false);
        chain.pay(&second.parent(), 100_000_000, false);
        chain.mine(12);
        let setup_end = chain.tip();
        let mut world = Self {
            chain,
            version: 0,
            service: None,
            devices: vec![],
            pays: vec![],
            fundings: vec![],
            quotes: vec![],
            deposits: 0,
            setup_end,
            notes: Default::default(),
            rewind_refused: None,
            ages: false,
            reopens: 0,
        };
        world.add_device(activation(), true);
        world
    }

    /// Adds a device restored from the main seed at `birthday`.
    fn add_device(&mut self, birthday: u32, feature: bool) -> usize {
        let wallet = Wallet::new(MAIN, birthday);
        let account = wallet.account().clone();
        self.devices.push(Device {
            wallet,
            birthday,
            feature,
            queries: true,
            ever_enabled: false,
            accts: vec![Acct {
                account,
                seed: MAIN,
                birthday,
                reserved: BTreeSet::new(),
            }],
            no_orchard: false,
            broken: false,
            anchor: self.chain.hash(birthday - 1),
        });
        let dev = self.devices.len() - 1;
        apply(&self.devices[dev]);
        self.devices[dev].ever_enabled |= self.devices[dev].discovery();
        dev
    }

    /// Records an open product finding the run met. It is reported, and fails the run
    /// only with `VIZOR_SCENARIO_STRICT=1`.
    fn note(&self, what: &'static str) {
        *self.notes.borrow_mut().entry(what).or_default() += 1;
    }

    /// The account of seed `seed` on one device, for deriving keys.
    fn seed_account(&self, seed: u8) -> Account {
        let mut wallet = Wallet::new(MAIN, activation());
        if seed == MAIN {
            wallet.account().clone()
        } else {
            wallet.add_account(seed, activation())
        }
    }

    /// The receive or refund key `index` of `seed`.
    fn key(&self, seed: u8, receive: bool, index: u64) -> orchard::keys::FullViewingKey {
        let purpose = if receive {
            Purpose::Receive
        } else {
            Purpose::Refund
        };
        self.seed_account(seed).key(purpose, index)
    }

    /// The receiver service for `publication`, rebuilt only when it changes.
    fn service(&mut self, publication: Publication) -> Arc<Service> {
        if let Some((current, service)) = &self.service {
            if *current == publication {
                return service.clone();
            }
        }
        let extra: Vec<(u32, [u8; 43])> = publication
            .false_hit
            .map(|(height, index)| {
                vec![(
                    height,
                    self.seed_account(MAIN).receiver(Purpose::Receive, index),
                )]
            })
            .unwrap_or_default();
        let sealed: Vec<u32> = publication.sealed.into_iter().collect();
        let service = Service::publish_shards(
            &self.chain,
            &sealed,
            publication.pir_end,
            publication.first,
            self.chain.tip(),
            &extra,
        );
        self.service = Some((publication, service.clone()));
        service
    }

    /// The default publication: PIR through the tip and filters from activation.
    fn current(&self) -> Publication {
        Publication {
            version: self.version,
            pir_end: self.chain.tip(),
            first: activation(),
            sealed: None,
            false_hit: None,
        }
    }

    /// Notes that the chain changed, so the next round needs a new publication.
    fn changed(&mut self) {
        self.version += 1;
    }

    /// Mines `n` empty blocks.
    fn mine(&mut self, n: u32) {
        self.chain.mine(n);
        self.changed();
    }

    /// Replaces the last `depth` blocks with a longer branch. Funding transactions the
    /// reorg dropped are mined again, and the provider re-sends payouts it owes.
    fn reorg(&mut self, depth: u32) -> String {
        let tip = self.chain.tip();
        let fork = tip.saturating_sub(depth).max(self.setup_end);
        if fork >= tip {
            return "nothing to reorg".into();
        }
        self.chain.rewind(fork);
        self.changed();
        for pay in self.pays.iter_mut().filter(|p| p.height > fork) {
            pay.orphaned = true;
        }
        let mut remined = 0;
        for funding in self.fundings.iter_mut().filter(|f| f.height > fork) {
            funding.height = self.chain.mine_tx(&funding.tx);
            remined += 1;
        }
        let mut repaid = 0;
        for q in 0..self.quotes.len() {
            let owed: Vec<(u64, [u8; 32])> = self.quotes[q].owed.clone();
            for (value, txid) in owed {
                if self.pays.iter().any(|p| p.txid == txid && p.orphaned) {
                    let quote = &self.quotes[q];
                    let (seed, receive, index) = (quote.seed, quote.incoming, quote.index);
                    let new = self.pay(seed, receive, index, value);
                    let quote = &mut self.quotes[q];
                    quote.hashes.retain(|h| *h != txid);
                    quote.hashes.push(new);
                    quote.owed.retain(|(_, t)| *t != txid);
                    quote.owed.push((value, new));
                    repaid += 1;
                }
            }
        }
        while self.chain.tip() <= tip {
            self.chain.mine(1);
        }
        format!("fork at {fork}, re-mined {remined} fundings, re-sent {repaid} payouts")
    }

    /// Mines a NEAR payout or refund to one of `seed`'s keys and returns its transaction.
    fn pay(&mut self, seed: u8, receive: bool, index: u64, value: u64) -> [u8; 32] {
        let key = self.key(seed, receive, index);
        let (height, txid) = self.chain.pay_tx(&key, value, true);
        self.changed();
        self.pays.push(Pay {
            seed,
            receive,
            index,
            value,
            height,
            txid,
            orphaned: false,
        });
        txid
    }

    /// The highest receive index any branch ever paid for `seed`.
    fn ever_paid(&self, seed: u8) -> Option<u64> {
        self.pays
            .iter()
            .filter(|p| p.seed == seed && p.receive)
            .map(|p| p.index)
            .max()
    }

    /// Resolves a device slot.
    fn dev(&self, slot: usize) -> usize {
        let live: Vec<usize> = (0..self.devices.len())
            .filter(|d| !self.devices[*d].broken)
            .collect();
        if live.is_empty() {
            return slot % self.devices.len();
        }
        live[slot % live.len()]
    }

    /// Ordinary sync on `dev`, optionally with transaction enhancement.
    fn sync(&mut self, dev: usize, enhance: bool) -> String {
        apply(&self.devices[dev]);
        if self.devices[dev].broken {
            return "device left out after a refused rewind".into();
        }
        let rewound = match self.devices[dev].wallet.sync(&self.chain) {
            Ok(rewound) => rewound,
            Err(e) => {
                self.devices[dev].broken = true;
                let birthday = self.devices[dev].birthday;
                if self.chain.hash_at(birthday - 1) != Some(self.devices[dev].anchor) {
                    // The wallet's starting tree state is on the old branch, an open finding.
                    self.note("reorg-below-birthday");
                    return format!("reorg below the birthday, device left out: {e}");
                }
                self.rewind_refused
                    .get_or_insert_with(|| format!("device {dev}: {e}"));
                return format!("rewind refused, device left out: {e}");
            }
        };
        let mut line = format!("synced to {}", self.chain.tip());
        if let Some(height) = rewound {
            line += &format!(", rewound to {height}");
        }
        if enhance {
            line += &format!(", {}", self.enhance(dev));
        }
        line
    }

    /// Ordinary sync's status and public enhancement lanes on `dev`, against a node that
    /// serves every mined funding transaction and knows no other transaction.
    fn enhance(&mut self, dev: usize) -> String {
        use super::super::super::enhancement::{EnhancementPolicy, EnhancementSession};
        let served: Vec<([u8; 32], Vec<u8>, u64)> = self
            .fundings
            .iter()
            .flat_map(|f| {
                let txid = *f.tx.txid().as_ref();
                let mut reversed = txid;
                reversed.reverse();
                [
                    (txid, f.raw.clone(), u64::from(f.height)),
                    (reversed, f.raw.clone(), u64::from(f.height)),
                ]
            })
            .collect();
        let mut served = served;
        if served.is_empty() {
            // The fake answers "not found" only while it serves something.
            served.push(([0xee; 32], vec![], 0));
        }
        let wallet = &self.devices[dev].wallet;
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let lwd = runtime.block_on(
            crate::wallet::sync_engine::test_lwd::CapturingLwd::start_serving(
                served,
                u64::from(self.chain.tip()),
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
        // Status work answers from the chain: an orphaned transaction is not found.
        match runtime.block_on(session.run_checkpoint(&mut db, &mut client, None, &|| false)) {
            Ok(_) => format!("enhanced ({} fetches)", lwd.count("/GetTransaction")),
            Err(e) => format!("enhancement failed: {e:?}"),
        }
    }

    /// Whether a feature-off round on `dev` may make receiver requests and write, because
    /// a receipt a reorg displaced needs repair. Such a receipt counts even while its repair
    /// lookup is not due, since a round still queues catch-up for it. An account whose
    /// wallet still says enabled, as after the app died before reconciling a turn-off,
    /// lists every lookup until the round reconciles, so only its receipts count.
    fn repair_due(&self, dev: usize) -> bool {
        let device = &self.devices[dev];
        device.accts.iter().any(|a| {
            let state = device.wallet.state(&a.account);
            repair_owed(&device.wallet, &a.account.id)
                || (!(state.enabled && !device.discovery())
                    && (!state.lookups.is_empty() || !state.witnesses.is_empty()))
        })
    }

    /// Whether `dev` is off in its settings and in its wallet with no repair due, so a
    /// round must neither request nor write anything.
    fn inert(&self, dev: usize) -> bool {
        let device = &self.devices[dev];
        !device.discovery()
            && !self.repair_due(dev)
            && device
                .accts
                .iter()
                .all(|a| !device.wallet.state(&a.account).enabled)
    }

    /// Runs one worker round on `dev` and checks the feature-off and upgrade promises. A
    /// feature-off round with nothing to repair must leave every one-time row as it was.
    #[allow(clippy::too_many_arguments)]
    fn round(
        &mut self,
        dev: usize,
        fail: u64,
        upgrade: bool,
        publication: Publication,
        seed: u64,
        manual: Option<Option<u64>>,
    ) -> Result<String, Violation> {
        apply(&self.devices[dev]);
        let service = self.service(publication);
        let repair_due = self.repair_due(dev);
        let inert = manual.is_none() && self.inert(dev);
        let device = &self.devices[dev];
        let untouched = inert.then(|| one_time_snapshot(&device.wallet));
        let before: Vec<BTreeSet<(bool, u64)>> = device
            .accts
            .iter()
            .map(|a| device.wallet.queued(&a.account))
            .collect();
        if upgrade {
            service.serve_protocol("ironwood-receiver-inventory-v2");
        }
        let faulty = Faulty {
            service: &service,
            rng: Mutex::new(Rng::new(seed)),
            fail,
            requests: AtomicUsize::new(0),
        };
        let result = run_worker(
            &device.wallet.path,
            &faulty,
            manual,
            Duration::from_secs(45),
        );
        if upgrade {
            service.serve_supported();
        }
        let requests = faulty.requests.load(AtomicOrdering::SeqCst);
        // Repairing a receipt a reorg displaced is an intended exception.
        if !device.discovery() && manual.is_none() && requests > 0 && !repair_due {
            return Err(violation(
                "feature-off-requests",
                format!(
                    "a feature-off round with no repair work made {requests} receiver requests"
                ),
            ));
        }
        if let Some(before) = untouched {
            let after = one_time_snapshot(&device.wallet);
            if after != before {
                return Err(violation(
                    "feature-off-write",
                    format!(
                        "a feature-off round with no repair work wrote: {}",
                        snapshot_diff(&before, &after)
                    ),
                ));
            }
        }
        match &result {
            Err(RecoveryError::UpgradeRequired) => {
                for (acct, before) in device.accts.iter().zip(&before) {
                    let state = device.wallet.state(&acct.account);
                    if state.enabled && !state.upgrade_required {
                        return Err(violation(
                            "upgrade-flag",
                            "an upgrade outcome left an enabled account unflagged",
                        ));
                    }
                    let after = device.wallet.queued(&acct.account);
                    if !before.is_subset(&after) {
                        return Err(violation(
                            "upgrade-dropped-work",
                            format!("pending work before {before:?}, after {after:?}"),
                        ));
                    }
                }
            }
            Err(RecoveryError::Other(message)) if mentions_orchard(message) => {
                return Err(violation("no-orchard-blocks", message.clone()));
            }
            _ => {}
        }
        Ok(match result {
            Ok(round) => format!("ok, active {}, {requests} requests", round.active),
            Err(e) => format!("error: {e}, {requests} requests"),
        })
    }

    /// Picks a publication for a round's options.
    fn publication(
        &mut self,
        lag: u32,
        recent: bool,
        seal: bool,
        false_hit: bool,
        seed: u64,
    ) -> Publication {
        let tip = self.chain.tip();
        let pir_end = tip.saturating_sub(lag).max(activation());
        let first = if recent {
            tip.saturating_sub(3).max(activation())
        } else {
            activation()
        };
        let sealed = (seal && pir_end > activation() + 4)
            .then(|| activation() + (pir_end - activation()) / 2);
        let false_hit = false_hit.then(|| {
            let mut rng = Rng::new(seed);
            (
                first + rng.below(u64::from(tip - first + 1)) as u32,
                rng.below(8),
            )
        });
        Publication {
            version: self.version,
            pir_end,
            first,
            sealed,
            false_hit,
        }
    }

    /// Runs a round whose `nth` query or filter request is held while the test acts.
    fn held_round(
        &mut self,
        dev: usize,
        query: bool,
        nth: usize,
        during: During,
    ) -> Result<String, Violation> {
        apply(&self.devices[dev]);
        let publication = self.current();
        let service = self.service(publication);
        let class = if query { "query" } else { "filters" };
        let held = service.hold(class, service.count(class) + nth);
        let worker = self.devices[dev]
            .wallet
            .spawn(&service, None, Duration::from_secs(45));
        let mut line = String::new();
        if held.try_wait(Duration::from_secs(20)) {
            line = match during {
                During::Mine => {
                    self.mine(2);
                    self.sync(dev, false)
                }
                During::Toggle => {
                    self.devices[dev].feature = !self.devices[dev].feature;
                    self.toggled(dev)
                }
                During::Cancel => {
                    cancel_recovery();
                    "cancelled".into()
                }
                During::Reorg => {
                    let reorg = self.reorg(2);
                    format!("{reorg}; {}", self.sync(dev, false))
                }
            };
        } else {
            line += "no held request";
        }
        held.release();
        let result = worker
            .join()
            .map_err(|_| violation("panic", "worker thread panicked"))?;
        if let Err(RecoveryError::Other(message)) = &result {
            if mentions_orchard(message) {
                return Err(violation("no-orchard-blocks", message.clone()));
            }
        }
        Ok(format!(
            "{line}; round {:?}",
            result.map(|r| r.active).map_err(|e| e.to_string())
        ))
    }

    /// Reconciles `dev`'s switches into its wallet, as a settings change does.
    fn toggled(&mut self, dev: usize) -> String {
        let device = &mut self.devices[dev];
        apply(device);
        device.ever_enabled |= device.discovery();
        let result = crate::api::one_time_ivk::reconcile_swap_recovery(
            device.wallet.path.clone(),
            "main".into(),
        );
        format!(
            "feature {}, queries {}, reconcile {:?}",
            device.feature,
            device.queries,
            result.map_err(|e| e.message)
        )
    }

    /// Turns the feature on for `dev` if either switch is off, as the user does before a
    /// step that needs it.
    fn ensure_on(&mut self, dev: usize) {
        if !self.devices[dev].discovery() {
            self.devices[dev].feature = true;
            self.devices[dev].queries = true;
            self.toggled(dev);
        }
        apply(&self.devices[dev]);
    }

    /// With the feature off, the settings history check is refused and the status reports
    /// no check running.
    fn manual_refused(&self, dev: usize) -> Result<(), Violation> {
        let path = self.devices[dev].wallet.path.clone();
        if crate::api::one_time_ivk::check_swap_history(path.clone(), "main".into()).is_ok() {
            return Err(violation(
                "manual-while-off",
                "the history check started with the feature off",
            ));
        }
        let status =
            crate::api::one_time_ivk::get_swap_recovery_status(path, "main".into()).unwrap();
        if status.checking_history {
            return Err(violation(
                "manual-while-off",
                "the status reports a history check with the feature off",
            ));
        }
        Ok(())
    }

    /// The wallet of every account on `dev` says enabled exactly when its settings do.
    fn check_setting_applied(&self, dev: usize) -> Result<(), Violation> {
        let device = &self.devices[dev];
        for acct in &device.accts {
            let enabled = device.wallet.state(&acct.account).enabled;
            if enabled != device.discovery() {
                return Err(violation(
                    "toggle-state",
                    format!(
                        "device {dev} seed {} reads enabled {enabled} with the setting {}",
                        acct.seed,
                        device.discovery()
                    ),
                ));
            }
        }
        Ok(())
    }

    /// Restarts the app on `dev`: the worker stops, the process forgets its switches, the
    /// wallet database is reopened under a new path as a fresh process opens it, and
    /// startup applies the saved switches and reads the recovery status. Nothing
    /// reconciles before the next round, as at app start.
    pub(super) fn restart(&mut self, dev: usize) -> String {
        cancel_recovery();
        crate::api::sync::set_near_swap_privacy_enabled(false);
        crate::api::sync::set_enhance_pir_enabled(false);
        self.reopens += 1;
        let old = self.devices[dev].wallet.path.clone();
        let new = std::path::Path::new(&old)
            .with_file_name(format!("reopened-{}.db", self.reopens))
            .to_str()
            .unwrap()
            .to_owned();
        for suffix in ["", "-wal", "-shm"] {
            let from = format!("{old}{suffix}");
            if std::path::Path::new(&from).exists() {
                std::fs::rename(&from, format!("{new}{suffix}")).unwrap();
            }
        }
        self.devices[dev].wallet.path = new.clone();
        apply(&self.devices[dev]);
        let status = crate::api::one_time_ivk::get_swap_recovery_status(new, "main".into())
            .map(|s| (s.checking_history, s.upgrade_required))
            .map_err(|e| e.message);
        format!("restarted, status {status:?}")
    }

    /// Holds the `nth` request of `class` in a round on `dev`, after a new block and, for
    /// any class but block filters, a payment to I0 give the round work, turns the feature off
    /// while it waits, optionally cancelling the worker as the app's toggle does, and
    /// checks that the released answer writes nothing. With `back` the feature comes
    /// straight back on.
    fn held_toggle(
        &mut self,
        dev: usize,
        class: u8,
        nth: usize,
        cancel: bool,
        back: bool,
    ) -> Result<String, Violation> {
        self.ensure_on(dev);
        let class = ["filters", "query", "witness", "shard-filter"][usize::from(class % 4)];
        // Give the round something to hold: a new block for its filters, and for the
        // other classes a payment to I0, the address every account issues first.
        if class != "filters" {
            let seed = self.devices[dev].accts[0].seed;
            self.pay(seed, true, 0, 150_000);
        }
        self.mine(1);
        let synced = self.sync(dev, false);
        if self.devices[dev].broken {
            return Ok(synced);
        }
        // A sealed shard, so the round screens its lookups with the shard's filter.
        let publication = self.publication(0, false, class == "shard-filter", false, 0);
        let service = self.service(publication);
        let held = service.hold(class, service.count(class) + nth);
        let worker = self.devices[dev]
            .wallet
            .spawn(&service, None, Duration::from_secs(45));
        if !held.try_wait(Duration::from_secs(20)) {
            held.release();
            let result = worker
                .join()
                .map_err(|_| violation("panic", "worker thread panicked"))?;
            return Ok(format!(
                "no held {class} request; round {:?}",
                result.map(|r| r.active).map_err(|e| e.to_string())
            ));
        }
        self.devices[dev].feature = false;
        let mut line = self.toggled(dev);
        if cancel {
            cancel_recovery();
        }
        let repair = self.repair_due(dev);
        let before = one_time_snapshot(&self.devices[dev].wallet);
        held.release();
        let result = worker
            .join()
            .map_err(|_| violation("panic", "worker thread panicked"))?;
        if let Err(RecoveryError::Other(message)) = &result {
            if mentions_orchard(message) {
                return Err(violation("no-orchard-blocks", message.clone()));
            }
        }
        let after = one_time_snapshot(&self.devices[dev].wallet);
        if !repair && after != before {
            return Err(violation(
                "held-answer-written",
                format!(
                    "a held {class} answer released after turning off wrote: {}",
                    snapshot_diff(&before, &after)
                ),
            ));
        }
        line = format!(
            "held {class}, {line}, round {:?}",
            result.map(|r| r.active).map_err(|e| e.to_string())
        );
        if back {
            self.devices[dev].feature = true;
            line += &format!("; {}", self.toggled(dev));
        }
        Ok(line)
    }

    /// Flips NEAR swap privacy `flips` times in quick succession on `dev`, each flip
    /// reconciled and every second one draining the worker as the app's toggle does,
    /// optionally while a round, turned on first, is held at its inventory read. Nothing
    /// may fail on wallet lock contention, and the wallet ends matching the last setting.
    fn rapid_toggle(&mut self, dev: usize, flips: u8, round: bool) -> Result<String, Violation> {
        if round {
            // Only an admitted round overlaps the flips.
            self.ensure_on(dev);
        }
        apply(&self.devices[dev]);
        let publication = self.current();
        let service = self.service(publication);
        // The round's first inventory read is held until the flips are done, so the
        // round is mid-flight for all of them.
        let held = round.then(|| service.hold("inventory", service.count("inventory")));
        let worker = round.then(|| {
            self.devices[dev]
                .wallet
                .spawn(&service, None, Duration::from_secs(45))
        });
        if let Some(held) = &held {
            if !held.try_wait(Duration::from_secs(20)) {
                held.release();
                return Err(violation(
                    "harness",
                    "the round never reached its inventory read",
                ));
            }
        }
        for flip in 0..flips {
            let device = &mut self.devices[dev];
            device.feature = !device.feature;
            apply(device);
            device.ever_enabled |= device.discovery();
            let reconciled = crate::api::one_time_ivk::reconcile_swap_recovery(
                device.wallet.path.clone(),
                "main".into(),
            );
            if let Err(e) = reconciled {
                return Err(violation(
                    if locked(&e.message) {
                        "lock-contention"
                    } else {
                        "toggle-failed"
                    },
                    e.message,
                ));
            }
            if flip % 2 == 1 {
                cancel_recovery();
            }
        }
        let mut line = format!("{flips} flips, feature {}", self.devices[dev].feature);
        if let Some(held) = held {
            held.release();
        }
        if let Some(worker) = worker {
            let result = worker
                .join()
                .map_err(|_| violation("panic", "worker thread panicked"))?;
            if let Err(RecoveryError::Other(message)) = &result {
                if locked(message) {
                    return Err(violation("lock-contention", message.clone()));
                }
                if mentions_orchard(message) {
                    return Err(violation("no-orchard-blocks", message.clone()));
                }
            }
            line += &format!(
                ", round {:?}",
                result.map(|r| r.active).map_err(|e| e.to_string())
            );
        }
        self.check_setting_applied(dev)?;
        Ok(line)
    }

    /// Saves NEAR swap privacy as `feature` on `dev`, reconciled or, as when the app dies
    /// first, not, then restarts the app and runs its first round. That round applies the
    /// saved setting, and with the feature off it makes no receiver request and writes
    /// nothing beyond the setting unless repair is due (see [`World::round`]).
    fn restart_toggle(
        &mut self,
        dev: usize,
        feature: bool,
        reconcile: bool,
    ) -> Result<String, Violation> {
        self.devices[dev].feature = feature;
        let mut line = if reconcile {
            self.toggled(dev)
        } else {
            let device = &mut self.devices[dev];
            apply(device);
            device.ever_enabled |= device.discovery();
            format!("feature {feature} saved, not reconciled")
        };
        line += &format!("; {}", self.restart(dev));
        let publication = self.current();
        line += &format!("; {}", self.round(dev, 0, false, publication, 0, None)?);
        self.check_setting_applied(dev)?;
        Ok(line)
    }

    /// Mines a block, syncs `dev`, starts a settings history check and turns the feature
    /// off while its `nth` query is held, draining the worker as the app's toggle does.
    /// The held answer writes nothing, and a new check is refused. With `back` the
    /// feature comes straight back on, which resumes the saved job.
    fn manual_toggle(&mut self, dev: usize, nth: usize, back: bool) -> Result<String, Violation> {
        self.ensure_on(dev);
        // A check starts only once ordinary sync has reached the publication, and a new
        // block leaves every completed history short of it, so the check has queries.
        self.mine(1);
        let synced = self.sync(dev, false);
        if self.devices[dev].broken {
            return Ok(synced);
        }
        let publication = self.current();
        let service = self.service(publication);
        let held = service.hold("query", service.count("query") + nth);
        let worker = self.devices[dev]
            .wallet
            .spawn(&service, Some(None), Duration::from_secs(45));
        let arrived = held.try_wait(Duration::from_secs(20));
        let mut line = String::new();
        if arrived {
            self.devices[dev].feature = false;
            line = self.toggled(dev);
            cancel_recovery();
        }
        let repair = self.repair_due(dev);
        let before = one_time_snapshot(&self.devices[dev].wallet);
        held.release();
        let result = worker
            .join()
            .map_err(|_| violation("panic", "worker thread panicked"))?;
        if let Err(RecoveryError::Other(message)) = &result {
            if mentions_orchard(message) {
                return Err(violation("no-orchard-blocks", message.clone()));
            }
        }
        let line = format!(
            "manual held {arrived}, {line}, round {:?}",
            result.map(|r| r.active).map_err(|e| e.to_string())
        );
        if !arrived {
            return Ok(line);
        }
        let after = one_time_snapshot(&self.devices[dev].wallet);
        if !repair && after != before {
            return Err(violation(
                "held-answer-written",
                format!(
                    "a held history check answer released after turning off wrote: {}",
                    snapshot_diff(&before, &after)
                ),
            ));
        }
        self.manual_refused(dev)?;
        if back {
            self.devices[dev].feature = true;
            return Ok(format!("{line}; {}", self.toggled(dev)));
        }
        Ok(line)
    }

    /// Reserves an incoming address and runs the app's quote lifecycle against the provider.
    fn quote_in(
        &mut self,
        dev: usize,
        slot: usize,
        reply: Reply,
        ttl: i64,
    ) -> Result<String, Violation> {
        apply(&self.devices[dev]);
        let acct = slot % self.devices[dev].accts.len();
        let reserved = self.reserve_in(dev, acct, true)?;
        let index = match reserved {
            Ok(index) => index,
            Err(line) => return Ok(line),
        };
        let device = &self.devices[dev];
        let a = &device.accts[acct];
        let (path, uuid, seed) = (device.wallet.path.clone(), a.account.uuid.clone(), a.seed);
        let deadline = now() + ttl;
        let request = match crate::api::one_time_ivk::begin_receive_quote(
            path.clone(),
            "main".into(),
            uuid.clone(),
            index,
            deadline,
        ) {
            Ok(request) => request,
            Err(e) => return Ok(format!("reserved I{index}, begin refused: {}", e.message)),
        };
        self.deposits += 1;
        let deposit = format!("deposit-{}.near", self.deposits);
        let mut quote = Quote {
            request: Some(request.clone()),
            ..Quote::new(dev, uuid.clone(), seed, true, index, deposit, deadline - 60)
        };
        let line = match reply {
            Reply::Accept => self.accept(&mut quote),
            Reply::Reject => {
                quote.rejected = true;
                let result = crate::api::one_time_ivk::finish_receive_quote(
                    path,
                    "main".into(),
                    uuid,
                    request,
                    None,
                );
                format!("rejected: {:?}", result.map_err(|e| e.message))
            }
            Reply::Timeout => "timed out".into(),
        };
        self.quotes.push(quote);
        Ok(format!("I{index} quote {}: {line}", self.quotes.len() - 1))
    }

    /// Delivers an accepted quote answer and exposes it if the wallet still allows it.
    fn accept(&mut self, quote: &mut Quote) -> String {
        let path = self.devices[quote.dev].wallet.path.clone();
        let request = quote.request.clone().unwrap();
        let finished = crate::api::one_time_ivk::finish_receive_quote(
            path.clone(),
            "main".into(),
            quote.uuid.clone(),
            request.clone(),
            Some(crate::api::one_time_ivk::ReceiveDeposit {
                address: quote.deposit.clone(),
                memo: None,
                deadline_seconds: quote.deadline,
            }),
        );
        if let Err(e) = finished {
            return format!("finish refused: {}", e.message);
        }
        quote.accepted = true;
        match crate::api::one_time_ivk::start_receive_quote(
            path,
            "main".into(),
            quote.uuid.clone(),
            request,
        ) {
            Ok(_) => {
                quote.started = true;
                "accepted and shown".into()
            }
            Err(e) => format!("accepted, start refused: {}", e.message),
        }
    }

    /// Reserves an address on `dev`'s account `acct`, checking the window and reuse rules.
    /// On a full window it refreshes statuses once, as the app's limit handling asks, and
    /// fails if a slot the reuse rules free still stays blocked.
    fn reserve_in(
        &mut self,
        dev: usize,
        acct: usize,
        retry: bool,
    ) -> Result<Result<u64, String>, Violation> {
        let device = &self.devices[dev];
        let a = &device.accts[acct];
        let result = crate::api::one_time_ivk::reserve_swap_address(
            device.wallet.path.clone(),
            "main".into(),
            a.account.uuid.clone(),
            true,
            self.chain.tip().into(),
        );
        let address = match result {
            Ok(address) => address,
            Err(e) => {
                if mentions_orchard(&e.message) {
                    return Err(violation("no-orchard-blocks", e.message));
                }
                if e.kind == crate::api::one_time_ivk::ReceiveErrorKind::Limit {
                    if let Some(index) = self.reusable_slot(dev, acct) {
                        if retry {
                            self.poll(dev, 0)?;
                            return self.reserve_in(dev, acct, false);
                        }
                        return Err(violation(
                            "stalled-window",
                            format!("I{index} is unpaid and its quotes expired unfunded, yet reservation reports {}", e.message),
                        ));
                    }
                }
                return Ok(Err(format!("reserve refused: {}", e.message)));
            }
        };
        let index = address.reservation_index.unwrap();
        let seed = a.seed;
        let limit = self.ever_paid(seed).map_or(4, |h| h + 5);
        if index >= limit {
            return Err(violation(
                "window",
                format!("issued I{index}, but payments ever mined justify only below I{limit}"),
            ));
        }
        let own = evidence_high(&device.wallet, &a.account.id).map_or(4, |h| h + 5);
        if index >= own {
            return Err(violation(
                "window",
                format!("issued I{index} beyond the wallet's own evidence end I{own}"),
            ));
        }
        if notes(&device.wallet, &a.account.id)
            .iter()
            .any(|n| n.receive && n.index == index && n.mined)
        {
            return Err(violation(
                "reuse",
                format!("reissued paid address I{index}"),
            ));
        }
        let clock = deadline_clock(&device.wallet);
        if let Some(q) = self.quotes.iter().find(|q| {
            q.dev == dev
                && q.uuid == a.account.uuid
                && q.incoming
                && q.index == index
                && q.started
                && (q.deadline > clock || (q.funded_seen && !q.concluded()))
        }) {
            return Err(violation(
                "reuse",
                format!("reissued I{index} while quote {} holds it (deadline {}, clock {clock}, funded {})", q.deposit, q.deadline, q.funded),
            ));
        }
        self.devices[dev].accts[acct].reserved.insert(index);
        Ok(Ok(index))
    }

    /// A window slot of `dev`'s account `acct` that the reuse rules say is free: unpaid,
    /// with every quote on it expired, unfunded and not shown live, or started but without
    /// any funded status [`STARTED_STATUS_GRACE`] past its deadline while no payment to
    /// it is pending.
    fn reusable_slot(&self, dev: usize, acct: usize) -> Option<u64> {
        let device = &self.devices[dev];
        let a = &device.accts[acct];
        let end = evidence_high(&device.wallet, &a.account.id).map_or(4, |h| h + 5);
        let paid: BTreeSet<u64> = notes(&device.wallet, &a.account.id)
            .iter()
            .filter(|n| n.receive && n.mined)
            .map(|n| n.index)
            .collect();
        let clock = deadline_clock(&device.wallet);
        (0..end).find(|index| {
            !paid.contains(index)
                && self.quotes.iter().any(|q| {
                    q.dev == dev && q.uuid == a.account.uuid && q.incoming && q.index == *index
                })
                && self.quotes.iter().all(|q| {
                    !(q.dev == dev && q.uuid == a.account.uuid && q.incoming && q.index == *index)
                        || (!q.funded && q.deadline <= clock && q.status == "PENDING_DEPOSIT")
                        // The wallet's deadline is a minute after the provider's.
                        || (q.started
                            && !q.funded_seen
                            && q.deadline + 60 + STARTED_STATUS_GRACE <= clock
                            && !receive_pending(&device.wallet, &a.account.id, *index))
                })
        })
    }

    /// Reserves a refund key and records its quote, as a ZEC-to-X swap does before Review.
    fn quote_out(&mut self, dev: usize, slot: usize, ttl: i64) -> Result<String, Violation> {
        apply(&self.devices[dev]);
        let device = &self.devices[dev];
        let a = &device.accts[slot % device.accts.len()];
        let (path, uuid, seed) = (device.wallet.path.clone(), a.account.uuid.clone(), a.seed);
        let known = funded_refunds(&device.wallet, &a.account.id);
        let reserved = crate::api::one_time_ivk::reserve_swap_address(
            path.clone(),
            "main".into(),
            uuid.clone(),
            false,
            self.chain.tip().into(),
        );
        let index = match reserved {
            Ok(address) => address.refund_index.unwrap(),
            Err(e) if mentions_orchard(&e.message) => {
                return Err(violation("no-orchard-blocks", e.message))
            }
            Err(e) => return Ok(format!("refund reserve refused: {}", e.message)),
        };
        let birthday = self.devices[dev].accts[slot % self.devices[dev].accts.len()].birthday;
        let conn = rusqlite::Connection::open(&self.devices[dev].wallet.path).unwrap();
        // Whether this device stored the funding as mined, on whichever branch it follows.
        let mined_here = |f: &Funding| -> bool {
            conn.query_row(
                "SELECT EXISTS(SELECT 1 FROM transactions WHERE txid = ?1 AND mined_height IS NOT NULL)",
                [f.tx.txid().as_ref()],
                |r| r.get(0),
            )
            .unwrap()
        };
        // A device that has not scanned the funding's block may still reissue its key,
        // which is an accepted one-block race between devices.
        if let Some(f) = self
            .fundings
            .iter()
            .find(|f| f.seed == seed && f.refund == index && f.height >= birthday && mined_here(f))
        {
            // Another device funded this key in a block this device scanned. Its memo
            // registers the key even without a record of spending the funding's inputs,
            // which a later birthday or unrecovered one-time inputs lack.
            return Err(violation(
                "refund-reuse",
                format!(
                    "refund key R{index} was funded at {} in a block this device scanned; birthday {birthday}",
                    f.height,
                ),
            ));
        }
        if known.contains(&index)
            || self
                .quotes
                .iter()
                .any(|q| q.dev == dev && q.uuid == uuid && !q.incoming && q.index == index)
        {
            return Err(violation(
                "refund-reuse",
                format!("refund key R{index} was issued before"),
            ));
        }
        self.deposits += 1;
        // The deposit count, a marker byte, then 1 through 17.
        let mut hash: [u8; 20] = std::array::from_fn(|i| (i as u8).wrapping_sub(2));
        hash[..3].copy_from_slice(&[(self.deposits % 251) as u8, (self.deposits / 251) as u8, 77]);
        let deposit = zcash_keys::address::Address::Transparent(
            transparent::address::TransparentAddress::PublicKeyHash(hash),
        )
        .encode(&NETWORK);
        let deadline = now() + ttl;
        let recorded = crate::api::one_time_ivk::record_swap_refund_quote(
            path,
            "main".into(),
            uuid.clone(),
            index,
            deposit.clone(),
            deadline,
        );
        if let Err(e) = recorded {
            return Ok(format!("R{index} quote not recorded: {}", e.message));
        }
        self.quotes.push(Quote {
            accepted: true,
            started: true,
            ..Quote::new(dev, uuid, seed, false, index, deposit, deadline)
        });
        Ok(format!("R{index} quote {}", self.quotes.len() - 1))
    }

    /// Funds an outgoing quote with the app's send path and mines the funding transaction.
    fn fund(&mut self, q: usize) -> String {
        let quote = self.quotes[q].clone();
        if quote.incoming || quote.funded {
            return "not fundable".into();
        }
        let dev = quote.dev;
        if self.devices[dev].broken {
            return "device left out".into();
        }
        let line = self.sync(dev, false);
        let device = &self.devices[dev];
        let Some(acct) = device.accts.iter().find(|a| a.account.uuid == quote.uuid) else {
            return "account gone".into();
        };
        let account = acct.account.clone();
        let proposal = match crate::wallet::sync::propose_send_with_swap_refund(
            &device.wallet.path,
            NETWORK,
            &quote.uuid,
            "fund",
            &quote.deposit,
            5_000_000,
            quote.index,
        ) {
            Ok(p) => p,
            Err(e) => return format!("{line}; proposal refused: {e}"),
        };
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let lwd = runtime.block_on(
            crate::wallet::sync_engine::test_lwd::CapturingLwd::start_for_broadcast(u64::from(
                self.chain.tip(),
            )),
        );
        let sent = runtime.block_on(crate::wallet::sync::execute_proposal(
            &device.wallet.path,
            &lwd.url,
            proposal.proposal_id,
            "fund",
            account.seed(),
            None,
            None,
        ));
        match sent {
            Ok(result) if result.broadcasted_count == 1 => {}
            Ok(result) => return format!("{line}; not broadcast: {:?}", result.message),
            Err(e) => return format!("{line}; send failed: {e}"),
        }
        let (tx, raw) = device.wallet.last_built();
        let nullifiers = tx
            .ironwood_bundle()
            .map(|b| {
                b.actions()
                    .iter()
                    .map(|a| a.nullifier().to_bytes())
                    .collect()
            })
            .unwrap_or_default();
        let height = self.chain.mine_tx(&tx);
        self.changed();
        self.fundings.push(Funding {
            seed: quote.seed,
            refund: quote.index,
            tx,
            raw,
            height,
            nullifiers,
        });
        let quote = &mut self.quotes[q];
        quote.funded = true;
        quote.status = "PROCESSING";
        format!("{line}; funded R{} at {height}", quote.index)
    }

    /// Polls 1Click for every quote `dev` asked for and records each status, as the
    /// app's status refresh does for swaps with a private address.
    fn poll(&mut self, dev: usize, errors: u64) -> Result<String, Violation> {
        apply(&self.devices[dev]);
        let mut rng = Rng::new(self.quotes.len() as u64 ^ (dev as u64) << 32);
        let mut recorded = 0;
        let path = self.devices[dev].wallet.path.clone();
        let mut released = Vec::new();
        let mut seen = Vec::new();
        for (q, quote) in self
            .quotes
            .iter()
            .enumerate()
            .filter(|(_, q)| q.dev == dev && q.accepted && !q.released)
        {
            if rng.chance(errors) {
                continue;
            }
            let hashes: Vec<String> = quote.hashes.iter().map(display_txid).collect();
            let status = crate::api::one_time_ivk::SwapProviderStatus {
                status: quote.status.into(),
                swap_type: Some("EXACT_INPUT".into()),
                refunded_amount: if quote.omit_refund {
                    None
                } else {
                    Some(quote.refunded.unwrap_or(0).to_string())
                },
                amount_out: quote.amount_out.map(|v| v.to_string()),
                origin_tx_hashes: if quote.incoming {
                    vec![]
                } else {
                    hashes.clone()
                },
                destination_tx_hashes: if quote.incoming { hashes } else { vec![] },
            };
            match crate::api::one_time_ivk::observe_swap_status(
                path.clone(),
                "main".into(),
                quote.uuid.clone(),
                quote.incoming,
                quote.deposit.clone(),
                None,
                status,
                !quote.incoming && quote.funded,
                now(),
            ) {
                Ok(tracked) => {
                    recorded += 1;
                    if quote.funded && tracked {
                        seen.push(q);
                    }
                    if !tracked && quote.incoming {
                        released.push(q);
                    }
                }
                Err(e) if mentions_orchard(&e.message) => {
                    return Err(violation("no-orchard-blocks", e.message))
                }
                Err(_) => {}
            }
        }
        for q in seen {
            // Once a later quote reserved the same address, this quote's reservation was
            // released, and a late funded status no longer holds the address. The wallet
            // still records it for attribution, since the key is reserved again.
            let quote = &self.quotes[q];
            let reissued = self.quotes[q + 1..].iter().any(|later| {
                later.dev == quote.dev
                    && later.uuid == quote.uuid
                    && later.incoming
                    && later.index == quote.index
            });
            if !reissued {
                self.quotes[q].funded_seen = true;
            }
        }
        let clock = deadline_clock(&self.devices[dev].wallet);
        for q in released {
            let quote = &mut self.quotes[q];
            // The app stops refreshing a swap once the wallet released its address.
            quote.released = true;
            if quote.started && !quote.concluded() && (quote.deadline > clock || quote.funded_seen)
            {
                return Err(violation(
                    "live-quote-untracked",
                    format!("the wallet stopped tracking I{} while its quote {} is live (deadline {}, clock {clock}, funded {})", quote.index, quote.deposit, quote.deadline, quote.funded),
                ));
            }
        }
        Ok(format!("recorded {recorded} statuses"))
    }

    /// Runs the settings history check on `dev`, optionally cancelled mid-way.
    fn manual(
        &mut self,
        dev: usize,
        bound: Option<u64>,
        cancel: Option<usize>,
    ) -> Result<String, Violation> {
        apply(&self.devices[dev]);
        if !self.devices[dev].discovery() {
            return self
                .manual_refused(dev)
                .map(|()| "feature off, check refused".into());
        }
        let Some(nth) = cancel else {
            let publication = self.current();
            return self
                .round(dev, 0, false, publication, 0, Some(bound))
                .map(|r| format!("manual: {r}"));
        };
        let publication = self.current();
        let service = self.service(publication);
        let held = service.hold("query", service.count("query") + nth);
        let worker = self.devices[dev]
            .wallet
            .spawn(&service, Some(bound), Duration::from_secs(45));
        let arrived = held.try_wait(Duration::from_secs(20));
        if arrived {
            cancel_recovery();
        }
        held.release();
        let result = worker
            .join()
            .map_err(|_| violation("panic", "worker thread panicked"))?;
        let cancelled = crate::api::one_time_ivk::cancel_swap_history(
            self.devices[dev].wallet.path.clone(),
            "main".into(),
        );
        Ok(format!(
            "manual cancelled {arrived}: {:?}, cancel {:?}",
            result.map(|r| r.active).map_err(|e| e.to_string()),
            cancelled.map_err(|e| e.message)
        ))
    }

    /// Executes one action and returns what it did.
    fn act(&mut self, action: &Action) -> Result<String, Violation> {
        Ok(match *action {
            Action::Mine(n) => {
                self.mine(n);
                format!("tip {}", self.chain.tip())
            }
            Action::Reorg(depth) => self.reorg(depth),
            Action::Sync { dev, enhance } => {
                let dev = self.dev(dev);
                self.sync(dev, enhance)
            }
            Action::Enhance(dev) => {
                let dev = self.dev(dev);
                self.enhance(dev)
            }
            Action::Round {
                dev,
                fail,
                upgrade,
                lag,
                recent,
                seal,
                false_hit,
                seed,
            } => {
                let dev = self.dev(dev);
                let publication = self.publication(lag, recent, seal, false_hit, seed);
                self.round(dev, fail, upgrade, publication, seed, None)?
            }
            Action::HeldRound {
                dev,
                query,
                nth,
                during,
            } => {
                let dev = self.dev(dev);
                self.held_round(dev, query, nth, during)?
            }
            Action::QuoteIn {
                dev,
                acct,
                reply,
                ttl,
            } => {
                let dev = self.dev(dev);
                self.quote_in(dev, acct, reply, ttl)?
            }
            Action::LateReply { quote, accept } => {
                let Some(q) = self.pick(quote, |q| q.incoming && !q.accepted && !q.rejected) else {
                    return Ok("no pending reply".into());
                };
                apply(&self.devices[self.quotes[q].dev]);
                let mut copy = self.quotes[q].clone();
                let line = if accept {
                    let line = self.accept(&mut copy);
                    // A late answer must not expose a reservation another request started.
                    if copy.started {
                        if let Some(other) = self.quotes.iter().find(|o| {
                            o.dev == copy.dev
                                && o.uuid == copy.uuid
                                && o.incoming
                                && o.index == copy.index
                                && o.started
                                && o.request != copy.request
                                && o.deadline > deadline_clock(&self.devices[copy.dev].wallet)
                        }) {
                            return Err(violation(
                                "stale-reply",
                                format!(
                                    "a late answer exposed I{} while {} was live on it",
                                    copy.index, other.deposit
                                ),
                            ));
                        }
                    }
                    line
                } else {
                    copy.rejected = true;
                    let result = crate::api::one_time_ivk::finish_receive_quote(
                        self.devices[copy.dev].wallet.path.clone(),
                        "main".into(),
                        copy.uuid.clone(),
                        copy.request.clone().unwrap(),
                        None,
                    );
                    format!("late reject {:?}", result.map_err(|e| e.message))
                };
                self.quotes[q] = copy;
                format!("quote {q}: {line}")
            }
            Action::QuoteOut { dev, acct, ttl } => {
                let dev = self.dev(dev);
                self.quote_out(dev, acct, ttl)?
            }
            Action::Fund { quote } => {
                let Some(q) = self.pick(quote, |q| !q.incoming && !q.funded) else {
                    return Ok("nothing to fund".into());
                };
                self.fund(q)
            }
            Action::Deposit { quote } => {
                let Some(q) = self.pick(quote, |q| q.incoming && q.started && !q.funded) else {
                    return Ok("nothing to deposit".into());
                };
                let quote = &mut self.quotes[q];
                quote.funded = true;
                quote.status = "PROCESSING";
                format!("deposit for I{}", quote.index)
            }
            Action::Payout { quote, value } => {
                let Some(q) = self.pick(quote, |q| {
                    q.incoming && q.funded && q.status != "REFUNDED" && q.status != "FAILED"
                }) else {
                    return Ok("nothing to pay".into());
                };
                let (seed, index) = (self.quotes[q].seed, self.quotes[q].index);
                let txid = self.pay(seed, true, index, value);
                let quote = &mut self.quotes[q];
                quote.status = "SUCCESS";
                quote.amount_out = Some(quote.amount_out.unwrap_or(0) + value);
                quote.hashes.push(txid);
                quote.owed.push((value, txid));
                format!("paid {value} to I{index}")
            }
            Action::Refund {
                quote,
                partial,
                failed,
            } => {
                let Some(q) = self.pick(quote, |q| !q.incoming && q.funded && !q.concluded())
                else {
                    return Ok("nothing to refund".into());
                };
                let value = if partial { 40_000 } else { 4_900_000 };
                let (seed, index) = (self.quotes[q].seed, self.quotes[q].index);
                let txid = self.pay(seed, false, index, value);
                let quote = &mut self.quotes[q];
                quote.status = if partial {
                    "SUCCESS"
                } else if failed {
                    "FAILED"
                } else {
                    "REFUNDED"
                };
                quote.refunded = Some(value);
                quote.hashes.push(txid);
                quote.owed.push((value, txid));
                format!("refunded {value} to R{index} as {}", quote.status)
            }
            Action::Status { quote, change } => {
                let Some(q) = self.pick(quote, |q| q.accepted && !q.concluded()) else {
                    return Ok("no open quote".into());
                };
                let quote = &mut self.quotes[q];
                match (change, quote.incoming) {
                    (Change::Done, true) if quote.funded => quote.status = "REFUNDED",
                    (Change::Done, false) if quote.funded => {
                        quote.status = "SUCCESS";
                        quote.refunded = Some(0);
                    }
                    (Change::Failed, true) if quote.funded => quote.status = "FAILED",
                    (Change::Incomplete, _) if quote.funded => quote.status = "INCOMPLETE_DEPOSIT",
                    (Change::Unreported, false) if quote.funded => {
                        quote.status = "SUCCESS";
                        quote.omit_refund = true;
                    }
                    _ => return Ok("status unchanged".into()),
                }
                format!("quote {q} now {}", quote.status)
            }
            Action::Poll { dev, errors } => {
                let dev = self.dev(dev);
                self.poll(dev, errors)?
            }
            Action::Warp(secs) => {
                for device in &self.devices {
                    warp(&device.wallet, secs);
                }
                for quote in &mut self.quotes {
                    quote.deadline -= secs;
                }
                format!("clock +{secs}s")
            }
            Action::Toggle(dev) => {
                let dev = self.dev(dev);
                self.devices[dev].feature = !self.devices[dev].feature;
                self.toggled(dev)
            }
            Action::PrivateQueries(dev) => {
                let dev = self.dev(dev);
                self.devices[dev].queries = !self.devices[dev].queries;
                self.toggled(dev)
            }
            Action::Manual { dev, bound, cancel } => {
                let dev = self.dev(dev);
                self.manual(dev, bound, cancel)?
            }
            Action::Restore { back, feature } => {
                if self.devices.len() >= MAX_DEVICES {
                    return Ok("device limit".into());
                }
                let birthday = if back == 0 {
                    activation()
                } else {
                    (self.chain.tip() + 1)
                        .saturating_sub(back)
                        .max(activation())
                };
                let dev = self.add_device(birthday, feature);
                format!("device {dev} restored at {birthday}, feature {feature}")
            }
            Action::AddAccount(dev) => {
                let dev = self.dev(dev);
                let device = &mut self.devices[dev];
                let seed = if !device.accts.iter().any(|a| a.seed == MAIN) {
                    MAIN
                } else if !device.accts.iter().any(|a| a.seed == SECOND) {
                    SECOND
                } else {
                    return Ok("both seeds present".into());
                };
                let birthday = device.birthday;
                let account = device.wallet.add_account(seed, birthday);
                device.accts.push(Acct {
                    account,
                    seed,
                    birthday,
                    reserved: BTreeSet::new(),
                });
                format!("added seed {seed} at {birthday}")
            }
            Action::AddNoOrchard(dev) => {
                let dev = self.dev(dev);
                if self.devices[dev].no_orchard {
                    return Ok("already has one".into());
                }
                let birthday = self.devices[dev].birthday;
                self.devices[dev]
                    .wallet
                    .import_without_orchard(NO_ORCHARD, birthday, &self.chain);
                self.devices[dev].no_orchard = true;
                "imported an account without an Orchard key".into()
            }
            Action::DeleteAccount { dev, acct } => {
                let dev = self.dev(dev);
                let device = &mut self.devices[dev];
                if device.accts.len() < 2 {
                    return Ok("only one account".into());
                }
                let acct = acct % device.accts.len();
                let removed = device.accts.remove(acct);
                device.wallet.delete_account(&removed.account);
                format!("deleted seed {}", removed.seed)
            }
            Action::HeldToggle {
                dev,
                class,
                nth,
                cancel,
                back,
            } => {
                let dev = self.dev(dev);
                self.held_toggle(dev, class, nth, cancel, back)?
            }
            Action::RapidToggle { dev, flips, round } => {
                let dev = self.dev(dev);
                self.rapid_toggle(dev, flips, round)?
            }
            Action::RestartToggle {
                dev,
                feature,
                reconcile,
            } => {
                let dev = self.dev(dev);
                self.restart_toggle(dev, feature, reconcile)?
            }
            Action::ManualToggle { dev, nth, back } => {
                let dev = self.dev(dev);
                self.manual_toggle(dev, nth, back)?
            }
            Action::Restart(dev) => {
                let dev = self.dev(dev);
                self.restart(dev)
            }
            Action::Swap { dev, acct, value } => {
                let dev = self.dev(dev);
                let before = self.quotes.len();
                let line = self.quote_in(dev, acct, Reply::Accept, 3_600)?;
                if self.quotes.len() == before || !self.quotes[before].started {
                    return Ok(line);
                }
                let (seed, index) = (self.quotes[before].seed, self.quotes[before].index);
                let txid = self.pay(seed, true, index, value);
                let quote = &mut self.quotes[before];
                quote.funded = true;
                quote.status = "SUCCESS";
                quote.amount_out = Some(value);
                quote.hashes.push(txid);
                quote.owed.push((value, txid));
                let paid = format!("paid {value} to I{index}");
                format!("{line}; {paid}")
            }
            Action::SwapOut { dev, acct, outcome } => {
                let dev = self.dev(dev);
                let before = self.quotes.len();
                let line = self.quote_out(dev, acct, 3_600)?;
                if self.quotes.len() == before {
                    return Ok(line);
                }
                let funded = self.fund(before);
                if !self.quotes[before].funded {
                    return Ok(format!("{line}; {funded}"));
                }
                let result = match outcome {
                    0 => {
                        let quote = &mut self.quotes[before];
                        quote.status = "SUCCESS";
                        quote.refunded = Some(0);
                        "success, no refund".to_string()
                    }
                    1 | 2 => {
                        let partial = outcome == 1;
                        let value = if partial { 40_000 } else { 4_900_000 };
                        let (seed, index) = (self.quotes[before].seed, self.quotes[before].index);
                        let txid = self.pay(seed, false, index, value);
                        let quote = &mut self.quotes[before];
                        quote.status = if partial { "SUCCESS" } else { "REFUNDED" };
                        quote.refunded = Some(value);
                        quote.hashes.push(txid);
                        quote.owed.push((value, txid));
                        format!("refunded {value}")
                    }
                    _ => "pending".to_string(),
                };
                format!("{line}; {funded}; {result}")
            }
        })
    }

    /// The `slot`th quote satisfying `filter`, if any.
    fn pick(&self, slot: usize, filter: impl Fn(&Quote) -> bool) -> Option<usize> {
        let candidates: Vec<usize> = (0..self.quotes.len())
            .filter(|q| filter(&self.quotes[*q]))
            .collect();
        (!candidates.is_empty()).then(|| candidates[slot % candidates.len()])
    }

    /// Whether `dev`'s scanned tip is on the current chain.
    fn on_chain(&self, dev: usize) -> bool {
        let Some(block) = self.devices[dev].wallet.db().block_fully_scanned().unwrap() else {
            return true;
        };
        Some(block.block_hash().0) == self.chain.hash_at(u32::from(block.block_height()))
    }

    /// Promises checked after every step: credit only real payments, nothing orphaned
    /// once a wallet followed the reorg, and no recovery state on wallets that never
    /// enabled the feature.
    pub(super) fn check_step(&self) -> Result<(), Violation> {
        if let Some(refused) = &self.rewind_refused {
            return Err(violation("ordinary-rewind-refused", refused.clone()));
        }
        for (dev, device) in self.devices.iter().enumerate() {
            if device.broken {
                continue;
            }
            if !device.ever_enabled && recovery_rows(&device.wallet) > 0 {
                return Err(violation(
                    "feature-off-state",
                    format!("device {dev} never enabled the feature but has recovery rows"),
                ));
            }
            let synced = self.on_chain(dev);
            for acct in &device.accts {
                for note in notes(&device.wallet, &acct.account.id)
                    .iter()
                    .filter(|n| n.mined)
                {
                    let pay = self.pays.iter().find(|p| {
                        p.seed == acct.seed
                            && p.txid == note.txid
                            && p.receive == note.receive
                            && p.index == note.index
                    });
                    let Some(pay) = pay else {
                        return Err(violation(
                            "phantom-credit",
                            format!("device {dev} credits {note:?}, which no chain paid"),
                        ));
                    };
                    if pay.value != note.value {
                        return Err(violation(
                            "phantom-credit",
                            format!(
                                "device {dev} credits {} for a {} payment",
                                note.value, pay.value
                            ),
                        ));
                    }
                    if pay.orphaned && synced {
                        return Err(violation(
                            "orphan-credit",
                            format!(
                                "device {dev} still credits {} to {}{} from an orphaned block",
                                note.value,
                                if note.receive { "I" } else { "R" },
                                note.index
                            ),
                        ));
                    }
                }
            }
        }
        Ok(())
    }

    /// The canonical payments `acct` on `dev` must eventually hold, with the keys they pay.
    fn expected(&self, dev: usize, acct: &Acct) -> BTreeSet<(bool, u64, [u8; 32], u64)> {
        let canonical: Vec<&Pay> = self
            .pays
            .iter()
            .filter(|p| !p.orphaned && p.seed == acct.seed)
            .collect();
        // The seed walk: receive indexes in order until four empties follow the last paid.
        let paid: BTreeSet<u64> = canonical
            .iter()
            .filter(|p| p.receive)
            .map(|p| p.index)
            .collect();
        let mut reachable = BTreeSet::new();
        let (mut index, mut empties) = (0u64, 0);
        while empties < 4 {
            if paid.contains(&index) {
                reachable.insert(index);
                empties = 0;
            } else {
                empties += 1;
            }
            index += 1;
        }
        reachable.extend(acct.reserved.iter().copied());
        let local: BTreeSet<u64> = funded_refunds(&self.devices[dev].wallet, &acct.account.id);
        // Every funding at or after the birthday names its refund key in a memo on the
        // account's own change, whatever its inputs.
        let memos: BTreeSet<u64> = self
            .fundings
            .iter()
            .filter(|f| f.seed == acct.seed && f.height >= acct.birthday)
            .map(|f| f.refund)
            .collect();
        canonical
            .iter()
            .filter(|p| p.height >= acct.birthday)
            .filter(|p| {
                if p.receive {
                    reachable.contains(&p.index)
                } else {
                    memos.contains(&p.index) || local.contains(&p.index)
                }
            })
            .map(|p| (p.receive, p.index, p.txid, p.value))
            .collect()
    }

    /// Settles the world: the provider finishes what it owes, time passes beyond every
    /// backoff, every wallet syncs and runs rounds until nothing changes, then the
    /// automatic promises, a settings history check and the exact credit are checked.
    pub(super) fn quiesce(&mut self) -> Result<(), Violation> {
        // A paused device stays inert until it is turned back on (see `World::round`).
        if mix() == Mix::Toggle {
            for dev in 0..self.devices.len() {
                if self.devices[dev].discovery() || self.devices[dev].broken {
                    continue;
                }
                for _ in 0..2 {
                    let publication = self.current();
                    self.round(dev, 0, false, publication, 0, None)?;
                }
                self.manual_refused(dev)?;
            }
        }
        // Re-enabling must resume whatever a paused device missed.
        for dev in 0..self.devices.len() {
            if !self.devices[dev].discovery() {
                self.devices[dev].feature = true;
                self.devices[dev].queries = true;
                self.toggled(dev);
            }
        }
        for q in 0..self.quotes.len() {
            let quote = self.quotes[q].clone();
            if !quote.funded || quote.concluded() {
                continue;
            }
            if quote.incoming {
                let txid = self.pay(quote.seed, true, quote.index, 1_000_000 + q as u64);
                let quote = &mut self.quotes[q];
                quote.status = "SUCCESS";
                quote.amount_out = Some(quote.amount_out.unwrap_or(0) + 1_000_000 + q as u64);
                quote.hashes.push(txid);
            } else {
                let quote = &mut self.quotes[q];
                quote.status = "SUCCESS";
                quote.refunded = Some(0);
            }
        }
        self.mine(1);
        for device in &self.devices {
            warp(&device.wallet, PAST_BACKOFF);
        }
        for quote in &mut self.quotes {
            quote.deadline -= PAST_BACKOFF;
        }
        self.mine(1);
        for dev in 0..self.devices.len() {
            self.sync(dev, true);
            self.poll(dev, 0)?;
        }
        for dev in 0..self.devices.len() {
            if self.devices[dev].broken {
                continue;
            }
            let mut last = None;
            for _ in 0..12 {
                let publication = self.current();
                self.round(dev, 0, false, publication, 0, None)?;
                let device = &self.devices[dev];
                let snapshot: Vec<_> = device
                    .accts
                    .iter()
                    .map(|a| {
                        (
                            device.wallet.queued(&a.account),
                            notes(&device.wallet, &a.account.id),
                            device.wallet.state(&a.account).restore_next,
                        )
                    })
                    .collect();
                if last.as_ref() == Some(&snapshot) {
                    break;
                }
                last = Some(snapshot);
            }
        }
        self.check_step()?;
        for dev in 0..self.devices.len() {
            let device = &self.devices[dev];
            if !device.discovery() || device.broken {
                continue;
            }
            for acct in &device.accts {
                let state = device.wallet.state(&acct.account);
                let queued = device.wallet.queued(&acct.account);
                if !state.restore_complete
                    || !queued.is_empty()
                    || !state.witnesses.is_empty()
                    || state.upgrade_required
                {
                    return Err(violation(
                        "stuck",
                        format!(
                            "device {dev} seed {}: restore complete {}, next {}, queued {queued:?}, witnesses {}, upgrade {}",
                            acct.seed, state.restore_complete, state.restore_next, state.witnesses.len(), state.upgrade_required
                        ),
                    ));
                }
                let credited: BTreeSet<(bool, u64, [u8; 32], u64)> =
                    notes(&device.wallet, &acct.account.id)
                        .iter()
                        .filter(|n| n.mined)
                        .map(|n| (n.receive, n.index, n.txid, n.value))
                        .collect();
                let expected = self.expected(dev, acct);
                let keys: BTreeSet<(bool, u64)> = expected.iter().map(|e| (e.0, e.1)).collect();
                for (receive, index) in &keys {
                    // The key's first canonical payment, which automatic recovery must find
                    // itself. Later payments to it are repeats, promised only to the
                    // history check below, so finding one of them is no excuse.
                    let Some(first) = self
                        .pays
                        .iter()
                        .filter(|p| {
                            !p.orphaned
                                && p.seed == acct.seed
                                && p.receive == *receive
                                && p.index == *index
                        })
                        .min_by_key(|p| p.height)
                    else {
                        continue;
                    };
                    if first.height < acct.birthday {
                        continue;
                    }
                    // A refund key this device funded retires once its own swap ends, so
                    // a payment for another device's swap reusing it is only promised to
                    // the history check. Such reuse already fails as `refund-reuse`.
                    let own: Vec<&Quote> = self
                        .quotes
                        .iter()
                        .filter(|q| {
                            q.dev == dev
                                && q.uuid == acct.account.uuid
                                && !q.incoming
                                && q.index == *index
                        })
                        .collect();
                    let promised = *receive
                        || own.is_empty()
                        || self.pays.iter().any(|p| {
                            !p.orphaned
                                && !p.receive
                                && p.seed == acct.seed
                                && p.index == *index
                                && own.iter().any(|q| q.hashes.contains(&p.txid))
                        });
                    if !promised {
                        continue;
                    }
                    // For a refund key with swaps of its own, the first refund one of them
                    // reported. Another device's swap on the same key is the accepted race.
                    let first = if *receive || own.is_empty() {
                        first
                    } else {
                        self.pays
                            .iter()
                            .filter(|p| {
                                !p.orphaned
                                    && !p.receive
                                    && p.seed == acct.seed
                                    && p.index == *index
                                    && own.iter().any(|q| q.hashes.contains(&p.txid))
                            })
                            .min_by_key(|p| p.height)
                            .unwrap_or(first)
                    };
                    if !credited.contains(&(*receive, *index, first.txid, first.value)) {
                        let monitored: Vec<String> = device
                            .wallet
                            .db()
                            .one_time_receivers(acct.account.id)
                            .unwrap()
                            .1
                            .iter()
                            .map(|w| format!("{:?}{}", w.key.purpose(), w.key.index()))
                            .collect();
                        return Err(violation(
                            "first-payment-missed",
                            format!(
                                "device {dev} seed {} birthday {} has no automatic credit for the first payment of {}{index}, {} at {}; funded refunds {:?}, monitored {monitored:?}, all notes {:?}",
                                acct.seed,
                                acct.birthday,
                                if *receive { "I" } else { "R" },
                                first.value,
                                first.height,
                                funded_refunds(&device.wallet, &acct.account.id),
                                notes(&device.wallet, &acct.account.id),
                            ),
                        ));
                    }
                }
                self.check_retired(dev, acct)?;
            }
        }
        for dev in 0..self.devices.len() {
            if !self.devices[dev].discovery() || self.devices[dev].broken {
                continue;
            }
            let resumed: Vec<Option<u32>> = self.devices[dev]
                .accts
                .iter()
                .map(|a| resumed_frontier(&self.devices[dev].wallet, &a.account.id))
                .collect();
            self.history_check(dev)?;
            // A payment after a resumed check's frontier needs a new search, which must
            // find it.
            if self.only_missed_after_frontier(dev, &resumed) {
                self.history_check(dev)?;
            }
            let device = &self.devices[dev];
            for acct in &device.accts {
                if let Some(manual) = device.wallet.state(&acct.account).manual {
                    if manual.active {
                        return Err(violation(
                            "manual-stuck",
                            format!(
                                "device {dev} seed {}: the history check is still running after 12 rounds: {manual:?}",
                                acct.seed
                            ),
                        ));
                    }
                }
            }
            for acct in &device.accts {
                let expected = self.expected(dev, acct);
                let credited: BTreeSet<(bool, u64, [u8; 32], u64)> =
                    notes(&device.wallet, &acct.account.id)
                        .iter()
                        .filter(|n| n.mined)
                        .map(|n| (n.receive, n.index, n.txid, n.value))
                        .collect();
                if credited != expected {
                    let missing: Vec<_> = expected
                        .difference(&credited)
                        .map(|(r, i, _, v)| format!("{}{i}:{v}", if *r { "I" } else { "R" }))
                        .collect();
                    let extra: Vec<_> = credited
                        .difference(&expected)
                        .map(|(r, i, _, v)| format!("{}{i}:{v}", if *r { "I" } else { "R" }))
                        .collect();
                    return Err(violation(
                        "credit-mismatch",
                        format!("device {dev} seed {} birthday {}: missing {missing:?}, extra {extra:?}", acct.seed, acct.birthday),
                    ));
                }
                let revealed: BTreeSet<[u8; 32]> = self
                    .fundings
                    .iter()
                    .flat_map(|f| f.nullifiers.iter().copied())
                    .collect();
                for note in notes(&device.wallet, &acct.account.id)
                    .iter()
                    .filter(|n| n.mined)
                {
                    if note.spent != revealed.contains(&note.nf) {
                        return Err(violation(
                            "spend-state",
                            format!(
                                "device {dev}: {}{} spent {} but the chain says {}",
                                if note.receive { "I" } else { "R" },
                                note.index,
                                note.spent,
                                revealed.contains(&note.nf)
                            ),
                        ));
                    }
                }
            }
        }
        self.check_balances()?;
        self.check_issuance()?;
        if self.ages {
            self.age()?;
        }
        Ok(())
    }

    /// Runs the settings history check on `dev` until no account's manual job is active,
    /// for at most 12 rounds.
    fn history_check(&mut self, dev: usize) -> Result<(), Violation> {
        for _ in 0..12 {
            let publication = self.current();
            self.round(dev, 0, false, publication, 0, Some(None))?;
            let device = &self.devices[dev];
            if device.accts.iter().all(|a| {
                !device
                    .wallet
                    .state(&a.account)
                    .manual
                    .is_some_and(|m| m.active)
            }) {
                break;
            }
        }
        Ok(())
    }

    /// Whether the history check on `dev` missed some credit, and every credit it missed
    /// is a repeat payment mined after the frontier its account's check resumed under, as
    /// `resumed` lists them per account (see [`resumed_frontier`]). Such a check need not
    /// find those (spec MAN-4). First payments stay owed to automatic recovery.
    fn only_missed_after_frontier(&self, dev: usize, resumed: &[Option<u32>]) -> bool {
        let device = &self.devices[dev];
        let mut missed = false;
        for (acct, resumed) in device.accts.iter().zip(resumed) {
            let credited: BTreeSet<(bool, u64, [u8; 32], u64)> =
                notes(&device.wallet, &acct.account.id)
                    .iter()
                    .filter(|n| n.mined)
                    .map(|n| (n.receive, n.index, n.txid, n.value))
                    .collect();
            for (receive, index, txid, _) in self.expected(dev, acct).difference(&credited) {
                let to_key = |p: &&Pay| {
                    !p.orphaned && p.seed == acct.seed && (p.receive, p.index) == (*receive, *index)
                };
                let Some(pay) = self.pays.iter().filter(to_key).find(|p| p.txid == *txid) else {
                    return false;
                };
                let repeat = self
                    .pays
                    .iter()
                    .filter(to_key)
                    .any(|p| p.height < pay.height);
                if !repeat || !resumed.is_some_and(|frontier| pay.height > frontier) {
                    return false;
                }
                missed = true;
            }
        }
        missed
    }

    /// Mines past every funding's [`MEMO_REFUND_WINDOW`] and settles every device again,
    /// after which refund keys learned only from memos must have retired too.
    fn age(&mut self) -> Result<(), Violation> {
        let Some(last) = self.fundings.iter().map(|f| f.height).max() else {
            return Ok(());
        };
        let target = last + MEMO_REFUND_WINDOW + 1;
        if self.chain.tip() < target {
            self.mine(target - self.chain.tip());
        }
        for dev in 0..self.devices.len() {
            if !self.devices[dev].discovery() || self.devices[dev].broken {
                continue;
            }
            self.sync(dev, false);
            for _ in 0..4 {
                let publication = self.current();
                self.round(dev, 0, false, publication, 0, None)?;
            }
        }
        self.check_step()?;
        for dev in 0..self.devices.len() {
            if !self.devices[dev].discovery() || self.devices[dev].broken {
                continue;
            }
            for acct in &self.devices[dev].accts {
                self.check_retired(dev, acct)?;
            }
        }
        Ok(())
    }

    /// Refund keys this device funded retire once every local operation is conclusive, and
    /// keys it learned only from a funding memo once filters have checked more than
    /// [`MEMO_REFUND_WINDOW`] past the funding.
    fn check_retired(&self, dev: usize, acct: &Acct) -> Result<(), Violation> {
        let device = &self.devices[dev];
        let monitored = monitored_refunds(&device.wallet, &acct.account.id);
        let orphaned = |index: u64| {
            notes(&device.wallet, &acct.account.id)
                .iter()
                .any(|n| !n.receive && n.index == index && !n.mined)
        };
        for quote in self
            .quotes
            .iter()
            .filter(|q| q.dev == dev && q.uuid == acct.account.uuid && !q.incoming && q.funded)
        {
            // A `SUCCESS` without a refunded amount expects no refund, so it is conclusive
            // too.
            if quote.concluded() && monitored.contains(&quote.index) {
                if orphaned(quote.index) {
                    // A refund the reorg replaced leaves its old note unmined, which keeps
                    // the key in repair, an open finding.
                    self.note("refund-key-kept-by-orphaned-receipt");
                    continue;
                }
                return Err(violation(
                    "refund-not-retired",
                    format!(
                        "device {dev} still monitors R{} after {} with refund {:?}",
                        quote.index, quote.status, quote.refunded
                    ),
                ));
            }
        }
        // A key learned from another device's funding memo has no local operation, so it
        // cannot learn the swap ended. It retires after NEAR's refund window.
        let frontier = device
            .wallet
            .state(&acct.account)
            .filter_frontier
            .map_or(0, |point| u32::from(point.height));
        for (index, funded) in funding_heights(&device.wallet, &acct.account.id) {
            let local = self.quotes.iter().any(|q| {
                q.dev == dev && q.uuid == acct.account.uuid && !q.incoming && q.index == index
            });
            if local || !monitored.contains(&index) || frontier <= funded + MEMO_REFUND_WINDOW {
                continue;
            }
            if orphaned(index) {
                self.note("refund-key-kept-by-orphaned-receipt");
                continue;
            }
            return Err(violation(
                "memo-refund-key-not-retired",
                format!(
                    "device {dev} still monitors memo-learned R{index} funded at {funded} with filters through {frontier}"
                ),
            ));
        }
        Ok(())
    }

    /// Devices on the same seed and birthday agree on the ordinary part of their balance,
    /// and every balance covers its unspent one-time notes.
    fn check_balances(&self) -> Result<(), Violation> {
        let mut ordinary: BTreeMap<(u8, u32), (usize, u64)> = BTreeMap::new();
        for (dev, device) in self.devices.iter().enumerate() {
            if device.broken {
                continue;
            }
            for acct in &device.accts {
                let balance = device.wallet.balance(&acct.account);
                // Unmined one-time notes, such as a payout a reorg orphaned, count as
                // pending exactly like orphaned ordinary notes do.
                let one_time: u64 = notes(&device.wallet, &acct.account.id)
                    .iter()
                    .filter(|n| !n.spent)
                    .map(|n| n.value)
                    .sum();
                let Some(rest) = balance.checked_sub(one_time) else {
                    return Err(violation("balance", format!("device {dev} balance {balance} is below its unspent one-time notes {one_time}")));
                };
                match ordinary.get(&(acct.seed, acct.birthday)) {
                    Some((other, value)) if *value != rest => {
                        return Err(violation(
                            "balance",
                            format!("seed {} birthday {}: device {dev} has {rest} outside one-time notes, device {other} has {value}", acct.seed, acct.birthday),
                        ));
                    }
                    Some(_) => {}
                    None => {
                        ordinary.insert((acct.seed, acct.birthday), (dev, rest));
                    }
                }
            }
        }
        Ok(())
    }

    /// At quiescence every enabled account can reserve a receive address, unless every
    /// window slot is legitimately held.
    fn check_issuance(&mut self) -> Result<(), Violation> {
        for dev in 0..self.devices.len() {
            if !self.devices[dev].discovery() || self.devices[dev].broken {
                continue;
            }
            apply(&self.devices[dev]);
            for acct in 0..self.devices[dev].accts.len() {
                match self.reserve_in(dev, acct, true)? {
                    Ok(_) => {}
                    Err(line) if line.contains("No swap address is free") => {}
                    Err(line) => {
                        return Err(violation(
                            "issuance-stuck",
                            format!("device {dev} account {acct}: {line}"),
                        ));
                    }
                }
            }
        }
        Ok(())
    }
}

/// How one scenario ended.
pub(super) struct Outcome {
    pub(super) trace: Vec<String>,
    pub(super) failure: Option<(usize, Violation)>,
    pub(super) notes: BTreeMap<&'static str, usize>,
}

/// Runs the actions of `seed` whose indexes `keep` lists (all when `None`), then quiesces.
pub(super) fn run(seed: u64, steps: usize, keep: Option<&BTreeSet<usize>>) -> Outcome {
    let actions = generate(seed, steps);
    let mut trace = Vec::new();
    let world = std::panic::catch_unwind(World::new);
    let Ok(mut world) = world else {
        return Outcome {
            trace,
            failure: Some((0, violation("panic", "world setup panicked"))),
            notes: BTreeMap::new(),
        };
    };
    // Aging mines thousands of blocks, so `VIZOR_SCENARIO_AGE` picks the share of seeds
    // (per mille) that pay for it, from a stream apart from the actions.
    world.ages = Rng::new(seed ^ 0xa9e).chance(setting("VIZOR_SCENARIO_AGE", 0));
    // Every scenario starts from a synced first device whose seed walk has run.
    let prologue = std::panic::catch_unwind(AssertUnwindSafe(|| {
        world.sync(0, false);
        let publication = world.current();
        world.round(0, 0, false, publication, 0, None)
    }));
    if !matches!(prologue, Ok(Ok(_))) {
        return Outcome {
            trace,
            failure: Some((0, violation("panic", "prologue failed"))),
            notes: BTreeMap::new(),
        };
    }
    for (i, action) in actions.iter().enumerate() {
        if keep.is_some_and(|k| !k.contains(&i)) {
            continue;
        }
        let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
            let line = world.act(action)?;
            world.check_step()?;
            Ok::<_, Violation>(line)
        }));
        let result = result.unwrap_or_else(|panic| {
            let message = panic
                .downcast_ref::<String>()
                .cloned()
                .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_default();
            Err(violation("panic", message))
        });
        match result {
            Ok(line) => trace.push(format!("{i:>3} {action:?} => {line}")),
            Err(v) => {
                trace.push(format!(
                    "{i:>3} {action:?} => VIOLATION {}: {}",
                    v.kind, v.detail
                ));
                return Outcome {
                    trace,
                    failure: Some((i, v)),
                    notes: world.notes.into_inner(),
                };
            }
        }
    }
    let result = std::panic::catch_unwind(AssertUnwindSafe(|| world.quiesce()))
        .unwrap_or_else(|_| Err(violation("panic", "quiescence panicked")));
    if let Err(v) = result {
        trace.push(format!("quiescence => VIOLATION {}: {}", v.kind, v.detail));
        return Outcome {
            trace,
            failure: Some((steps, v)),
            notes: world.notes.into_inner(),
        };
    }
    trace.push("quiescence => ok".into());
    Outcome {
        trace,
        failure: None,
        notes: world.notes.into_inner(),
    }
}

/// Drops actions while the same kind of violation persists, within `budget` replays.
fn shrink(seed: u64, steps: usize, kind: &'static str, budget: usize) -> BTreeSet<usize> {
    let mut keep: BTreeSet<usize> = (0..steps).collect();
    let mut replays = 0;
    // Remove halves, then quarters, and so on, then single actions from the end.
    let mut chunk = steps.div_ceil(2);
    while chunk >= 1 && replays < budget {
        let indexes: Vec<usize> = keep.iter().copied().collect();
        let mut start = 0;
        while start < indexes.len() && replays < budget {
            let candidate: BTreeSet<usize> = keep
                .iter()
                .copied()
                .filter(|i| !indexes[start..(start + chunk).min(indexes.len())].contains(i))
                .collect();
            replays += 1;
            if run(seed, steps, Some(&candidate))
                .failure
                .is_some_and(|(_, v)| v.kind == kind)
            {
                keep = candidate;
            }
            start += chunk;
        }
        if chunk == 1 {
            break;
        }
        chunk = chunk.div_ceil(2);
    }
    keep
}

/// Reads a numeric setting from the environment.
fn setting(name: &str, default: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

/// The command that replays one seed's scenario in a fresh shell: every setting that
/// changes its actions or checks, with only the actions `keep` lists when given.
fn reproducer(seed: u64, steps: usize, keep: Option<&BTreeSet<usize>>) -> String {
    let mut env = vec![
        format!("VIZOR_SCENARIO_SEED={seed}"),
        "VIZOR_SCENARIO_ITERS=1".into(),
        format!("VIZOR_SCENARIO_STEPS={steps}"),
    ];
    match mix() {
        Mix::Default => {}
        Mix::Stress => env.push("VIZOR_SCENARIO_MIX=stress".into()),
        Mix::Toggle => env.push("VIZOR_SCENARIO_MIX=toggle".into()),
    }
    let age = setting("VIZOR_SCENARIO_AGE", 0);
    if age > 0 {
        env.push(format!("VIZOR_SCENARIO_AGE={age}"));
    }
    if std::env::var("VIZOR_SCENARIO_STRICT").as_deref() == Ok("1") {
        env.push("VIZOR_SCENARIO_STRICT=1".into());
    }
    if let Some(keep) = keep {
        let list: Vec<String> = keep.iter().map(|i| i.to_string()).collect();
        env.push(format!("VIZOR_SCENARIO_KEEP={}", list.join(",")));
    }
    format!(
        "{} cargo test --lib swap_private::tests::scenarios::random_scenarios -- --nocapture",
        env.join(" ")
    )
}

/// Runs `iters` seeded scenarios and panics with a reproducer on the first new violation.
fn run_many(default_iters: u64, default_steps: u64) {
    let base = setting("VIZOR_SCENARIO_SEED", 0x5eed);
    let iters = setting("VIZOR_SCENARIO_ITERS", default_iters);
    let steps = setting("VIZOR_SCENARIO_STEPS", default_steps) as usize;
    // Only the long run shrinks by default.
    let budget = setting(
        "VIZOR_SCENARIO_SHRINK",
        if default_iters > 10 { 24 } else { 0 },
    ) as usize;
    let strict = std::env::var("VIZOR_SCENARIO_STRICT").as_deref() == Ok("1");
    let keep: Option<BTreeSet<usize>> = std::env::var("VIZOR_SCENARIO_KEEP")
        .ok()
        .map(|v| v.split(',').filter_map(|i| i.trim().parse().ok()).collect());
    let mut failures = Vec::new();
    let mut notes: BTreeMap<&'static str, usize> = BTreeMap::new();
    for i in 0..iters {
        let seed = base + i;
        let started = std::time::Instant::now();
        let outcome = run(seed, steps, keep.as_ref());
        for (k, v) in &outcome.notes {
            *notes.entry(k).or_default() += v;
        }
        let found: Vec<&str> = outcome.notes.keys().copied().collect();
        // A violation in the same run is reported below, with its reproducer.
        if strict && !found.is_empty() && outcome.failure.is_none() {
            println!(
                "scenario seed {seed}: FINDING {found:?}\n{}",
                outcome.trace.join("\n")
            );
            println!("reproduce: {}", reproducer(seed, steps, keep.as_ref()));
            failures.push(format!("seed {seed}: findings {found:?}"));
            continue;
        }
        let Some((step, v)) = outcome.failure else {
            println!(
                "scenario seed {seed}: ok in {:.1}s",
                started.elapsed().as_secs_f64()
            );
            if std::env::var("VIZOR_SCENARIO_VERBOSE").is_ok() {
                println!("{}", outcome.trace.join("\n"));
            }
            continue;
        };
        println!(
            "scenario seed {seed}: VIOLATION {} at step {step} in {:.1}s: {}{}\n{}",
            v.kind,
            started.elapsed().as_secs_f64(),
            v.detail,
            if found.is_empty() {
                String::new()
            } else {
                format!(" (also FINDING {found:?})")
            },
            outcome.trace.join("\n")
        );
        let repro = if keep.is_none() && budget > 0 {
            let kept = shrink(seed, steps, v.kind, budget);
            let shrunk = run(seed, steps, Some(&kept));
            println!(
                "shrunk to {} actions:\n{}",
                kept.len(),
                shrunk.trace.join("\n")
            );
            reproducer(seed, steps, Some(&kept))
        } else {
            reproducer(seed, steps, keep.as_ref())
        };
        println!("reproduce: {repro}");
        failures.push(format!("seed {seed}: {} ({})", v.kind, v.detail));
    }
    println!("scenario notes: {notes:?}");
    assert!(
        failures.is_empty(),
        "scenario violations:\n{}",
        failures.join("\n")
    );
}

/// Runs `test` in its own process, including when it is ignored, because the worker's
/// cancellation state and the app's switches are process wide.
pub(super) fn isolated(test: &str) -> bool {
    let name = format!("wallet::sync_engine::swap_private::tests::scenarios::{test}");
    const MARKER: &str = "VIZOR_TEST_PROCESS";
    if std::env::var(MARKER).as_deref() == Ok(name.as_str()) {
        return false;
    }
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            name.as_str(),
            "--test-threads=1",
            "--include-ignored",
            "--nocapture",
        ])
        .env(MARKER, &name)
        .output()
        .expect("start isolated test process");
    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("{stdout}");
    assert!(
        output.status.success() && stdout.contains("1 passed; 0 failed"),
        "isolated {name} failed:\n{}",
        String::from_utf8_lossy(&output.stderr),
    );
    true
}

/// A few short seeded scenarios, small enough for every test run.
#[test]
fn random_scenarios() {
    if isolated("random_scenarios") {
        return;
    }
    run_many(2, 20);
}

/// Many longer seeded scenarios. Set `VIZOR_SCENARIO_ITERS` and `VIZOR_SCENARIO_SEED` to
/// spread a large run over processes.
#[test]
#[ignore = "long randomized run"]
fn random_scenarios_long() {
    if isolated("random_scenarios_long") {
        return;
    }
    run_many(100, 40);
}
