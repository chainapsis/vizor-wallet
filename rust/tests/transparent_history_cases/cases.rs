//! H01-H13 scenarios on one isolated chain. Case definitions are
//! mode-independent: they build chain facts and author intent/attribution;
//! all expected values come from the oracle and the selected profile.
//!
//! Address plan (index -> case), so every case's outputs stay distinct:
//!   A0 external: 0 H03, 1 H03 coinbase, 2 H01, 3-4 H02, 5-6 H05, 7-9 H06,
//!                10-11 H07, 12 H09, 13/15/16/17 H12, 14 H03 (later index)
//!   A0 internal: 0 H01, 1 H02, 2-3 H05, 4-5 H06 (S-built change)
//!   A1 external: 0 H05, 1-2 H06;  A1 internal: 0 H05
//!   B external:  0 H05 input, 1 H08, 2 H12 reorg source, 3 H10, 4-5 H12,
//!                6 H01, 7 H02, 8 H09, 9 H05 change
//!   C external:  0 H02, 1-2 H05;  D external: 0 H11 swap deposit
//!   F external:  0.. one per shielded funding note (Z -> F, then S -> A0 Orchard)
//!   B external:  10 N_spend's send (private profile)
//!   E (erin, one seed): external 0 of ZIP 32 accounts 1 (four receives), 2
//!                and 6 (one each), N_discover (private profile)

use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
    time::{Duration, Instant},
};

use serde_json::json;

use crate::{
    chain::Chain,
    faucet::Faucet,
    keys::{tex_address, Party, Scope},
    proxy::{Proxy, RequestRecord},
    publication::Publisher,
    report::{Attribution, Suite},
    signer::{self, Coin, Out},
    vizor::{GiftCard, Observation, VizorWallet},
};

const ZEC: u64 = 100_000_000;

/// N_discover: the ZIP 32 accounts of erin's seed that receive transparent
/// funds, and how many receives each gets at its first external address. The
/// first spends the discovery pass's query budget on pages of its own; the
/// others span two discovery batches.
const ERIN_FUNDED: [(u32, u32); 3] = [(1, 4), (2, 1), (6, 1)];

/// Import discovery's query budget for N_discover: the directory phase
/// alone spends it, so the account with pages stops the pass.
const DISCOVERY_MAX_QUERIES: &str = "1";

fn erin_name(account: u32) -> &'static str {
    match account {
        0 => "E0",
        1 => "E1",
        2 => "E2",
        6 => "E6",
        _ => "E?",
    }
}

pub struct Ctx {
    pub chain: Chain,
    pub faucet: Faucet,
    pub suite: Suite,
    pub a0: Party,
    pub a1: Party,
    pub b: Party,
    pub c: Party,
    pub d: Party,
    /// Harness-only funder: Z pays it transparently and S moves its coins
    /// into Alice's Orchard notes (zcashd never touches Orchard).
    pub f: Party,
    /// N_discover's seed (private profile): ZIP 32 account 0, which holds
    /// nothing, then the accounts [`ERIN_FUNDED`] names.
    pub erin: Vec<(u32, Party)>,
    pub r: VizorWallet,
    enabled: BTreeSet<String>,
    timings: Vec<(String, Duration)>,
}

fn owner_shielded(account: &str) -> Attribution {
    Attribution {
        shielded_owner: Some(account.into()),
        ..Default::default()
    }
}

fn shielded_net(account: &str, value: i64) -> Attribution {
    Attribution {
        shielded_net: BTreeMap::from([(account.to_string(), value)]),
        ..Default::default()
    }
}

/// The output of `txid` paying `address`.
fn coin_for(chain: &Chain, txid: &str, address: &str) -> Coin {
    let tx = chain.rpc_ok("getrawtransaction", json!([txid, 1]));
    let index = tx["vout"]
        .as_array()
        .unwrap()
        .iter()
        .position(|v| v["scriptPubKey"]["addresses"][0].as_str() == Some(address))
        .unwrap_or_else(|| panic!("{txid} pays nothing to {address}"));
    signer::coin_at(chain, txid, index as u32)
}

impl Ctx {
    pub fn new() -> Self {
        let a0 = Party::generate("A0", "alice");
        let a1 = Party::generate("A1", "alice");
        let b = Party::generate("B", "bob");
        let c = Party::generate("C", "carol");
        let d = Party::generate("D", "swap-provider");
        let f = Party::generate("F", "harness");
        let e0 = Party::generate("E0", "erin");
        let erin: Vec<(u32, Party)> = ERIN_FUNDED
            .iter()
            .map(|&(account, _)| (account, e0.sibling(erin_name(account), account)))
            .collect();
        let erin = std::iter::once((0, e0)).chain(erin).collect::<Vec<_>>();
        let mut suite = Suite::new();
        for (party, external, internal, ephemeral) in [
            (&a0, 30, 20, 20),
            (&a1, 30, 20, 20),
            (&b, 12, 0, 0),
            (&c, 6, 0, 0),
            (&d, 3, 0, 0),
            (&f, 12, 0, 0),
        ] {
            suite.own(party, Scope::External, 0..external);
            suite.own(party, Scope::Internal, 0..internal);
            suite.own(party, Scope::Ephemeral, 0..ephemeral);
        }
        for (_, party) in &erin {
            suite.own(party, Scope::External, 0..1);
        }
        let enabled: BTreeSet<String> = std::env::var("TH_CASES")
            .map(|v| v.split(',').map(|s| s.trim().to_uppercase()).collect())
            .unwrap_or_else(|_| {
                crate::report::REQUIRED_CASES
                    .iter()
                    .map(|s| s.to_string())
                    .collect()
            });
        let started = Instant::now();
        // H03's coinbase: block 1 pays A0 external index 1.
        let chain = Chain::start(&a0.address(Scope::External, 1), 1, 150);
        if crate::report::profile() == "private" {
            // The private profile's transparent PIR service. Vizor reads its
            // origin on every sync (debug builds only); no request it receives
            // may carry one of Alice's scripts.
            let publisher = crate::publication::install(Publisher::start(
                chain.rpc_port,
                &suite.out.join("publication"),
            ));
            // Alice's scripts, and the discovery candidates of erin's seed.
            let watched: Vec<Vec<u8>> = suite
                .ownership
                .iter()
                .filter(|(_, owner)| owner.wallet == "alice")
                .map(|(script, _)| hex::decode(script).expect("hex script"))
                .chain((1..=20).map(|account| {
                    let candidate = erin[0].1.sibling("E", account);
                    hex::decode(candidate.script_hex(Scope::External, 0)).expect("hex script")
                }))
                .collect();
            publisher.watch(&watched);
            std::env::set_var("VIZOR_TRANSPARENT_PIR_URL", publisher.url());
        }
        let faucet = Faucet::new(&chain);
        let r = VizorWallet::import("R", &chain, &a0, &a1);
        let mut ctx = Ctx {
            chain,
            faucet,
            suite,
            a0,
            a1,
            b,
            c,
            d,
            f,
            erin,
            r,
            enabled,
            timings: Vec::new(),
        };
        ctx.timings.push(("chain+faucet".into(), started.elapsed()));
        ctx
    }

    fn on(&self, case: &str) -> bool {
        self.enabled.contains(case)
    }

    fn mine(&self, blocks: u32) {
        self.chain.mine(blocks);
    }

    fn settle_r(&self) {
        if let Err(e) = self.r.settle() {
            panic!("R sync failed: {e}\n{}", self.chain.container_logs());
        }
    }

    fn timed(&mut self, label: &str, f: impl FnOnce(&mut Self)) {
        let started = Instant::now();
        f(self);
        let elapsed = started.elapsed();
        eprintln!("[timing] {label}: {:.1}s", elapsed.as_secs_f64());
        self.timings.push((label.into(), elapsed));
    }

    /// Z pays an A0 transparent address; mining is left to the caller.
    fn fund_a0(&mut self, case: &str, index: u32, value: u64) -> String {
        let address = self.a0.address(Scope::External, index);
        let txid = self.faucet.pay(&self.chain, &[(&address, value)]);
        self.suite
            .tx(case, &txid, "Z", "funding_t", Attribution::default());
        txid
    }

    pub fn run(&mut self) {
        self.suite.case(
            "H01",
            "Transparent-only send",
            &[("final", &["N", "N_seq", "O"])],
        );
        self.suite.case(
            "H02",
            "Several inputs or recipients",
            &[("final", &["N", "N_seq", "O"])],
        );
        self.suite.case(
            "H03",
            "Ordinary transparent receive",
            &[("final", &["R", "N", "N_seq", "O"])],
        );
        self.suite.case(
            "H04",
            "Retained local transaction",
            &[("final", &["R", "N", "N_seq", "O"])],
        );
        self.suite.cases.get_mut("H04").unwrap().source_cases =
            vec!["H07".into(), "H08".into(), "H10".into(), "H11".into()];
        self.suite
            .case("H05", "Shared funding", &[("final", &["N", "N_seq", "O"])]);
        self.suite.case(
            "H06",
            "Self/cross-account transfer",
            &[("final", &["R", "N", "N_seq"])],
        );
        self.suite.case(
            "H07",
            "Owned shielding/unshielding",
            &[("final", &["R", "N", "N_seq", "O"])],
        );
        self.suite.case(
            "H08",
            "External transparent unshielding",
            &[("final", &["R", "N", "N_seq"])],
        );
        self.suite.case(
            "H09",
            "Other mixed-pool transaction",
            &[("final", &["N", "N_seq"])],
        );
        self.suite.case(
            "H10",
            "TEX/multi-step operation",
            &[("final", &["R", "N", "N_seq"])],
        );
        self.suite.case(
            "H11",
            "Swap/gift-card operation",
            &[("final", &["R", "N", "N_seq"])],
        );
        self.suite.case(
            "H12",
            "Pending/expired/conflicted",
            &[
                ("pending", &["R", "N_pending"]),
                ("pre_reorg", &["R"]),
                ("final", &["R", "N", "N_seq"]),
            ],
        );
        if crate::report::profile() == "private" {
            // Faults of the private source: a lagging publication and failing
            // private queries. N_pre stays, but private mode holds no
            // enrichment, so its snapshot follows the whole first sync.
            self.suite.case(
                "H13",
                "Incomplete coverage",
                &[
                    ("final_pre", &["N_pre"]),
                    ("h13_lag", &["N_lag"]),
                    ("h13_pir_fail", &["N_pir_fail"]),
                ],
            );
        } else {
            self.suite.case(
                "H13",
                "Incomplete coverage",
                &[
                    ("final_pre", &["N_pre"]),
                    ("h13_cut", &["N_cut"]),
                    ("h13_utxo_fail", &["N_utxo_fail"]),
                ],
            );
        }
        if crate::report::profile() == "private" {
            // Private-only variants: each runs after H13, so none changes
            // the chain an earlier checkpoint reads.
            for (case, checkpoint, variants) in [
                (
                    "H13",
                    "h13_recovered",
                    &["N_lag_settled", "N_pir_fail_settled"][..],
                ),
                ("H13", "toggle", &["N_toggle"][..]),
                ("H13", "restart", &["N_restart"][..]),
                ("H03", "discover", &["N_discover"][..]),
                ("H07", "spend", &["N_spend"][..]),
            ] {
                self.suite.cases.get_mut(case).unwrap().checkpoints.insert(
                    checkpoint.into(),
                    variants.iter().map(|v| v.to_string()).collect(),
                );
            }
        }
        for case in crate::report::REQUIRED_CASES {
            if !self.on(case) {
                self.suite.note(case, "not run: excluded by TH_CASES");
            }
        }

        self.timed("funding", |ctx| ctx.fund_all());
        if self.on("H03") {
            self.timed("H03", |ctx| ctx.h03());
        }
        if self.on("H01") {
            self.timed("H01", |ctx| ctx.h01());
        }
        if self.on("H02") {
            self.timed("H02", |ctx| ctx.h02());
        }
        if self.on("H05") {
            self.timed("H05", |ctx| ctx.h05());
        }
        if self.on("H06") {
            self.timed("H06 (S)", |ctx| ctx.h06_s());
        }
        if self.on("H09") {
            self.timed("H09", |ctx| ctx.h09());
        }
        self.mine(1);
        self.settle_r();
        if self.on("H07") {
            self.timed("H07", |ctx| ctx.h07());
        }
        if self.on("H06") {
            self.timed("H06 (V)", |ctx| ctx.h06_v());
        }
        if self.on("H08") {
            self.timed("H08", |ctx| ctx.h08());
        }
        if self.on("H10") {
            self.timed("H10", |ctx| ctx.h10());
        }
        if self.on("H11") {
            self.timed("H11", |ctx| ctx.h11());
        }
        if self.on("H12") {
            self.timed("H12", |ctx| ctx.h12());
        }
        self.timed("final", |ctx| ctx.final_checkpoint());
        if self.on("H13") {
            if crate::report::profile() == "private" {
                self.timed("H13", |ctx| ctx.h13_private());
            } else {
                self.timed("H13", |ctx| ctx.h13());
            }
        }
        if crate::report::profile() == "private" {
            // The variants that leave the chain alone, then N_discover (new
            // blocks, no transaction of Alice's), then N_spend (Alice's).
            if self.on("H13") {
                self.timed("N_toggle", |ctx| ctx.n_toggle());
                self.timed("N_restart", |ctx| ctx.n_restart());
            }
            if self.on("H03") {
                self.timed("N_discover", |ctx| ctx.n_discover());
            }
            if self.on("H07") {
                self.timed("N_spend", |ctx| ctx.n_spend());
            }
        }
    }

    fn fund_all(&mut self) {
        let mut plan: Vec<(&str, u8, u32, u64)> = Vec::new(); // (case, party, index, value)
        if self.on("H01") {
            plan.push(("H01", 0, 2, 3 * ZEC));
        }
        if self.on("H02") {
            plan.extend([
                ("H02", 0, 3, ZEC),
                ("H02", 0, 3, 3 * ZEC / 2),
                ("H02", 0, 4, 2 * ZEC),
            ]);
        }
        if self.on("H05") {
            plan.extend([
                ("H05", 0, 5, 3 * ZEC),
                ("H05", 2, 0, 2 * ZEC),
                ("H05", 0, 6, 12 * ZEC / 10),
                ("H05", 1, 0, 18 * ZEC / 10),
            ]);
        }
        if self.on("H06") {
            plan.extend([("H06", 0, 7, 2 * ZEC), ("H06", 0, 9, 2 * ZEC)]);
        }
        if self.on("H07") {
            plan.push(("H07", 0, 10, 13 * ZEC / 10));
        }
        if self.on("H09") {
            plan.push(("H09", 0, 12, 2 * ZEC));
        }
        if self.on("H12") {
            plan.push(("H12", 2, 2, ZEC));
        }
        for chunk in plan.chunks(5) {
            for (case, party, index, value) in chunk {
                let party = match party {
                    0 => &self.a0,
                    1 => &self.a1,
                    _ => &self.b,
                };
                let address = party.address(Scope::External, *index);
                let txid = self.faucet.pay(&self.chain, &[(&address, *value)]);
                self.suite
                    .tx(case, &txid, "Z", "funding_t", Attribution::default());
            }
            self.mine(1);
        }
        // Shielded notes for the V-built cases: several, so consecutive V
        // sends do not wait on change confirmations. Z pays the funder F
        // transparently; S moves each coin into an Orchard note for A0.
        let shielded_cases: Vec<&str> = ["H06", "H07", "H08", "H10", "H11", "H11", "H12"]
            .into_iter()
            .filter(|c| self.on(c))
            .collect();
        let mut coins = Vec::new();
        for (index, case) in shielded_cases.iter().enumerate() {
            let address = self.f.address(Scope::External, index as u32);
            let txid = self
                .faucet
                .pay(&self.chain, &[(&address, 3 * ZEC + ZEC / 1000)]);
            coins.push((*case, index as u32, txid, address));
        }
        self.mine(1);
        let orchard = signer::orchard_receiver(&self.r.unified_address("A0"));
        for (case, index, funding, address) in coins {
            let coin = coin_for(&self.chain, &funding, &address);
            let built = signer::send(
                &self.chain,
                &[(coin, &self.f, Scope::External, index)],
                &[Out::Orchard(orchard, 3 * ZEC)],
                Some(&self.f.taddr(Scope::External, index)),
            );
            self.suite.tx(
                case,
                &built.txid,
                "S",
                "funding_shielded",
                shielded_net("A0", 3 * ZEC as i64),
            );
        }
        self.mine(1);
        // External notes need six confirmations before Vizor spends them.
        self.mine(6);
        self.settle_r();
    }

    fn txid_of_coinbase(&self, height: u64) -> String {
        let hash = self.chain.rpc_ok("getblockhash", json!([height]));
        let block = self.chain.rpc_ok("getblock", json!([hash]));
        block["tx"][0].as_str().unwrap().to_string()
    }

    /// H03: Z pays A0 at index 0 and at index 14 (beyond the initial gap, so
    /// a restore must extend discovery); block 1's coinbase paid index 1.
    fn h03(&mut self) {
        let coinbase = self.txid_of_coinbase(1);
        self.suite.tx(
            "H03",
            &coinbase,
            "M",
            "coinbase_receive",
            Attribution::default(),
        );
        for index in [0, 14] {
            let address = self.a0.address(Scope::External, index);
            let value = if index == 0 {
                7 * ZEC / 10
            } else {
                9 * ZEC / 10
            };
            let txid = self.faucet.pay(&self.chain, &[(&address, value)]);
            self.suite
                .tx("H03", &txid, "Z", "t_receive", Attribution::default());
        }
        self.mine(1);
        self.settle_r();
    }

    fn funding_coin(&self, case: &str, party: &Party, index: u32) -> Vec<Coin> {
        let address = party.address(Scope::External, index);
        self.suite
            .txs
            .iter()
            .filter(|t| t.case == case && t.intent == "funding_t")
            .filter_map(|t| {
                let tx = self.chain.rpc_ok("getrawtransaction", json!([t.txid, 1]));
                tx["vout"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|v| v["scriptPubKey"]["addresses"][0].as_str() == Some(&address))
                    .then(|| coin_for(&self.chain, &t.txid, &address))
            })
            .collect()
    }

    /// H01: S spends one A0 coin to B with change to A0's internal chain.
    fn h01(&mut self) {
        let coin = self.funding_coin("H01", &self.a0, 2).remove(0);
        let built = signer::send(
            &self.chain,
            &[(coin, &self.a0, Scope::External, 2)],
            &[Out::T(self.b.taddr(Scope::External, 6), 125 * ZEC / 100)],
            Some(&self.a0.taddr(Scope::Internal, 0)),
        );
        self.suite
            .tx("H01", &built.txid, "S", "t_send", Attribution::default());
        self.mine(1);
        self.settle_r();
    }

    /// H02: three A0 inputs (two at the same reused address) to B and C.
    fn h02(&mut self) {
        let mut inputs = Vec::new();
        for coin in self.funding_coin("H02", &self.a0, 3) {
            inputs.push((coin, &self.a0, Scope::External, 3));
        }
        for coin in self.funding_coin("H02", &self.a0, 4) {
            inputs.push((coin, &self.a0, Scope::External, 4));
        }
        assert_eq!(inputs.len(), 3, "H02 needs three A0 inputs");
        let built = signer::send(
            &self.chain,
            &inputs,
            &[
                Out::T(self.b.taddr(Scope::External, 7), 11 * ZEC / 10),
                Out::T(self.c.taddr(Scope::External, 0), 22 * ZEC / 10),
            ],
            Some(&self.a0.taddr(Scope::Internal, 1)),
        );
        self.suite.tx(
            "H02",
            &built.txid,
            "S",
            "t_send_multi",
            Attribution::default(),
        );
        self.mine(1);
        self.settle_r();
    }

    /// H05: A0 + B inputs -> C (change to both); A0 + A1 inputs -> C.
    fn h05(&mut self) {
        let a0_coin = self.funding_coin("H05", &self.a0, 5).remove(0);
        let b_coin = self.funding_coin("H05", &self.b, 0).remove(0);
        let built = signer::send(
            &self.chain,
            &[
                (a0_coin, &self.a0, Scope::External, 5),
                (b_coin, &self.b, Scope::External, 0),
            ],
            &[
                Out::T(self.c.taddr(Scope::External, 1), 4 * ZEC),
                Out::T(self.a0.taddr(Scope::Internal, 2), ZEC / 2),
            ],
            Some(&self.b.taddr(Scope::External, 9)),
        );
        self.suite.tx(
            "H05",
            &built.txid,
            "S",
            "shared_funding",
            Attribution::default(),
        );
        let a0_coin = self.funding_coin("H05", &self.a0, 6).remove(0);
        let a1_coin = self.funding_coin("H05", &self.a1, 0).remove(0);
        let built = signer::send(
            &self.chain,
            &[
                (a0_coin, &self.a0, Scope::External, 6),
                (a1_coin, &self.a1, Scope::External, 0),
            ],
            &[
                Out::T(self.c.taddr(Scope::External, 2), 25 * ZEC / 10),
                Out::T(self.a0.taddr(Scope::Internal, 3), ZEC / 5),
            ],
            Some(&self.a1.taddr(Scope::Internal, 0)),
        );
        self.suite.tx(
            "H05",
            &built.txid,
            "S",
            "shared_funding",
            Attribution::default(),
        );
        self.mine(1);
        self.settle_r();
    }

    /// H06 (S): A0 t -> another A0 t; A0 t -> A1 t.
    fn h06_s(&mut self) {
        let coin = self.funding_coin("H06", &self.a0, 7).remove(0);
        let built = signer::send(
            &self.chain,
            &[(coin, &self.a0, Scope::External, 7)],
            &[Out::T(self.a0.taddr(Scope::External, 8), 12 * ZEC / 10)],
            Some(&self.a0.taddr(Scope::Internal, 4)),
        );
        self.suite.tx(
            "H06",
            &built.txid,
            "S",
            "self_transfer",
            Attribution::default(),
        );
        let coin = self.funding_coin("H06", &self.a0, 9).remove(0);
        let built = signer::send(
            &self.chain,
            &[(coin, &self.a0, Scope::External, 9)],
            &[Out::T(self.a1.taddr(Scope::External, 1), ZEC)],
            Some(&self.a0.taddr(Scope::Internal, 5)),
        );
        self.suite.tx(
            "H06",
            &built.txid,
            "S",
            "cross_account_t",
            Attribution::default(),
        );
        self.mine(1);
        self.settle_r();
    }

    /// H09: one A0 transparent input -> A0 Orchard output + B transparent output.
    fn h09(&mut self) {
        let coin = self.funding_coin("H09", &self.a0, 12).remove(0);
        let orchard = signer::orchard_receiver(&self.r.unified_address("A0"));
        let built = signer::send(
            &self.chain,
            &[(coin, &self.a0, Scope::External, 12)],
            &[Out::Orchard(orchard, 7 * ZEC / 10)],
            Some(&self.b.taddr(Scope::External, 8)),
        );
        self.suite.tx(
            "H09",
            &built.txid,
            "S",
            "mixed_pool",
            shielded_net("A0", 7 * ZEC as i64 / 10),
        );
        self.mine(1);
        self.settle_r();
    }

    fn v_mined(&mut self, txids: &[String]) {
        self.mine(1);
        for txid in txids {
            assert!(
                self.chain.mined_height(txid).is_some(),
                "V transaction {txid} was not mined"
            );
        }
        // Change notes need the trusted confirmation depth before the next V send.
        self.mine(3);
        self.settle_r();
    }

    /// H07: V shields A0's transparent funds, then unshields to A0's own t-addr.
    fn h07(&mut self) {
        let shield = self.r.shield("A0");
        for txid in &shield {
            self.suite
                .tx("H07", txid, "V", "shield", owner_shielded("A0"));
        }
        self.v_mined(&shield);
        let to = self.a0.address(Scope::External, 11);
        let unshield = self.r.send("A0", &to, 8 * ZEC / 10);
        for txid in &unshield {
            self.suite
                .tx("H07", txid, "V", "unshield_self", owner_shielded("A0"));
        }
        self.v_mined(&unshield);
    }

    /// H06 (V): A0 shielded -> A1 transparent address.
    fn h06_v(&mut self) {
        let to = self.a1.address(Scope::External, 2);
        let txids = self.r.send("A0", &to, ZEC / 2);
        for txid in &txids {
            self.suite.tx(
                "H06",
                txid,
                "V",
                "cross_account_from_shielded",
                owner_shielded("A0"),
            );
        }
        self.v_mined(&txids);
    }

    /// H08: A0 shielded -> B's transparent address.
    fn h08(&mut self) {
        let to = self.b.address(Scope::External, 1);
        let txids = self.r.send("A0", &to, 4 * ZEC / 10);
        for txid in &txids {
            self.suite.tx(
                "H08",
                txid,
                "V",
                "shielded_to_external_t",
                owner_shielded("A0"),
            );
        }
        self.v_mined(&txids);
    }

    /// H10: V TEX send to B (both legs), then funds returned to the ephemeral address.
    fn h10(&mut self) {
        let tex = tex_address(&self.b.taddr(Scope::External, 3));
        let txids = self.r.send("A0", &tex, 3 * ZEC / 10);
        assert_eq!(txids.len(), 2, "TEX send must build two legs: {txids:?}");
        self.suite.tx_full(
            "H10",
            &txids[0],
            "V",
            "tex_leg1",
            owner_shielded("A0"),
            None,
            json!({"other_leg": txids[1]}),
        );
        self.suite.tx_full(
            "H10",
            &txids[1],
            "V",
            "tex_leg2",
            Attribution::default(),
            None,
            json!({"other_leg": txids[0]}),
        );
        self.v_mined(&txids);
        let leg1 = self.chain.rpc_ok("getrawtransaction", json!([txids[0], 1]));
        let ephemeral = leg1["vout"][0]["scriptPubKey"]["addresses"][0]
            .as_str()
            .unwrap()
            .to_string();
        let txid = self
            .faucet
            .pay(&self.chain, &[(&ephemeral, 25 * ZEC / 100)]);
        self.suite
            .tx("H10", &txid, "Z", "tex_return", Attribution::default());
        self.mine(1);
        self.settle_r();
    }

    /// H11: gift card create (A0) and claim (into A1) through Vizor's paths;
    /// a swap simulated as a V send to a transparent deposit address. The
    /// application records exist only in the Flutter layer (see README).
    fn h11(&mut self) {
        let card = GiftCard::generate();
        let birthday = self.chain.tip();
        let gift = ZEC / 2;
        let reserve = 10_000;
        let txids = self.r.send("A0", &card.address, gift + reserve);
        for txid in &txids {
            self.suite.tx_full(
                "H11",
                txid,
                "V",
                "gift_card_create",
                Attribution {
                    shielded_owner: Some("A0".into()),
                    external_shielded_out: gift + reserve,
                    ..Default::default()
                },
                Some("gift_card_create"),
                json!(null),
            );
        }
        self.v_mined(&txids);
        let claim = card.claim(&self.chain, birthday, &self.r.unified_address("A1"), gift);
        self.chain.wait_mempool(&claim);
        self.suite.tx_full(
            "H11",
            &claim,
            "V",
            "gift_card_claim",
            shielded_net("A1", gift as i64),
            Some("gift_card_claim"),
            json!(null),
        );
        let deposit = self.d.address(Scope::External, 0);
        let swap = self.r.send("A0", &deposit, 35 * ZEC / 100);
        for txid in &swap {
            self.suite.tx_full(
                "H11",
                txid,
                "V",
                "swap_deposit",
                owner_shielded("A0"),
                Some("swap_deposit"),
                json!(null),
            );
        }
        let mut all = swap.clone();
        all.push(claim);
        self.v_mined(&all);
    }

    /// H12: pending (unmined Z -> A0, unmined V shield), expired (proxy drops a
    /// V send), conflicted (proxy withholds a V shield of U while S spends U),
    /// reorg (invalidateblock drops a mined receive).
    fn h12(&mut self) {
        // Pending.
        self.fund_a0("H12", 17, 6 * ZEC / 10);
        self.mine(1);
        self.settle_r();
        let address = self.a0.address(Scope::External, 13);
        let pending_receive = self.faucet.pay(&self.chain, &[(&address, 45 * ZEC / 100)]);
        self.suite.tx(
            "H12",
            &pending_receive,
            "Z",
            "pending_receive",
            Attribution::default(),
        );
        let shield = self.r.shield("A0");
        for txid in &shield {
            self.chain.wait_mempool(txid);
            self.suite
                .tx("H12", txid, "V", "pending_shield", owner_shielded("A0"));
        }
        let r_result = self.r.settle().err();
        let n = VizorWallet::import("N_pending", &self.chain, &self.a0, &self.a1);
        let n_result = n.settle().err();
        checkpoint(
            &self.chain,
            &mut self.suite,
            "pending",
            &[(&self.r, "R"), (&n, "N_pending")],
            BTreeMap::from([
                ("R".to_string(), r_result),
                ("N_pending".to_string(), n_result),
            ]),
        );
        drop(n);
        self.mine(1);
        assert!(self.chain.mined_height(&pending_receive).is_some());
        self.mine(3);
        self.settle_r();

        // Expired: the proxy accepts but never forwards a V send.
        self.r.proxy.swallow_next_sends(1);
        let to = self.b.address(Scope::External, 4);
        let expired = self.r.send("A0", &to, ZEC / 5);
        let swallowed = self.r.proxy.swallowed();
        for txid in &expired {
            let raw = swallowed
                .iter()
                .find(|(t, _)| t == txid)
                .map(|(_, raw)| hex::encode(raw))
                .expect("swallowed send");
            assert!(!self.chain.in_mempool(txid), "swallowed tx reached zcashd");
            self.suite.tx_full(
                "H12",
                txid,
                "V",
                "expired_send",
                owner_shielded("A0"),
                None,
                json!({"raw_hex": raw}),
            );
        }

        // Conflicted: U is funded, a V shield of U is withheld, S spends U.
        let funding = self.fund_a0("H12", 15, 11 * ZEC / 10);
        self.mine(1);
        self.settle_r();
        self.r.proxy.swallow_next_sends(1);
        let withheld = self.r.shield("A0");
        let swallowed = self.r.proxy.swallowed();
        for txid in &withheld {
            let raw = swallowed
                .iter()
                .find(|(t, _)| t == txid)
                .map(|(_, raw)| hex::encode(raw))
                .expect("swallowed shield");
            self.suite.tx_full(
                "H12",
                txid,
                "V",
                "conflicted_shield",
                owner_shielded("A0"),
                None,
                json!({"raw_hex": raw, "conflicts_with_outpoint": format!("{funding}:U")}),
            );
        }
        let u = coin_for(&self.chain, &funding, &self.a0.address(Scope::External, 15));
        let spend = signer::send(
            &self.chain,
            &[(u, &self.a0, Scope::External, 15)],
            &[],
            Some(&self.b.taddr(Scope::External, 5)),
        );
        self.suite.tx(
            "H12",
            &spend.txid,
            "S",
            "conflicting_spend",
            Attribution::default(),
        );
        self.mine(1);
        // Past both withheld transactions' expiry (tip + 41).
        self.mine(45);
        self.settle_r();

        // Reorg: S pays A0 from B; the block is invalidated and the receive
        // is kept out of the replacement chain.
        let source = self.funding_coin("H12", &self.b, 2).remove(0);
        let receive = signer::send(
            &self.chain,
            &[(source, &self.b, Scope::External, 2)],
            &[],
            Some(&self.a0.taddr(Scope::External, 16)),
        );
        self.suite.tx(
            "H12",
            &receive.txid,
            "S",
            "reorged_receive",
            Attribution::default(),
        );
        let height = self.chain.mine_until_mined(&receive.txid);
        let r_result = self.r.settle().err();
        checkpoint(
            &self.chain,
            &mut self.suite,
            "pre_reorg",
            &[(&self.r, "R")],
            BTreeMap::from([("R".to_string(), r_result)]),
        );
        let hash = self.chain.rpc_ok("getblockhash", json!([height]));
        self.chain.rpc_ok("invalidateblock", json!([hash]));
        let _ = self.chain.rpc(
            "prioritisetransaction",
            json!([receive.txid, 0, -100_000_000i64]),
        );
        self.mine(2);
        let status = self.chain.mined_height(&receive.txid);
        self.suite.note(
            "H12",
            format!(
                "reorg: receive {} after invalidateblock({height}): {}",
                &receive.txid[..12],
                match status {
                    Some(h) => format!("re-mined at {h}"),
                    None => "kept out of the replacement chain".into(),
                }
            ),
        );
        self.settle_r();
    }

    /// Final checkpoint: R (settled), O (R reopened), N (fresh restore; its
    /// first sync runs with GetTransaction held to expose the pre-enrichment
    /// view, which H13 asserts as the delayed-publication fault), and N_seq
    /// (fresh restore with A0 synced alone before A1 is added).
    fn final_checkpoint(&mut self) {
        let r_result = self.r.settle().err();
        let o = self.r.reopen("O", &self.chain);
        let o_result = o.settle().err();
        let n = VizorWallet::import("N", &self.chain, &self.a0, &self.a1);
        n.proxy.hold_get_transaction();
        let (pre_views, pre_requests, pre_held) = std::thread::scope(|scope| {
            let handle = scope.spawn(|| n.sync());
            let deadline = Instant::now() + Duration::from_secs(120);
            while n.proxy.held_now() == 0 && Instant::now() < deadline && !handle.is_finished() {
                std::thread::sleep(Duration::from_millis(200));
            }
            let held = n.proxy.held_now();
            // Let the engine reach the held request before snapshotting.
            std::thread::sleep(Duration::from_millis(1500));
            let views = n.observe_all();
            let requests = n.proxy.take_requests();
            n.proxy.release_get_transaction();
            let _ = handle.join();
            (views, requests, held)
        });
        self.suite.note(
            "H13",
            format!(
                "delayed GetTransaction: {pre_held} request(s) held at the pre-enrichment snapshot"
            ),
        );
        let observation = Observation {
            checkpoint: "final_pre".into(),
            tip: self.chain.tip(),
            tip_hash: self.chain.tip_hash(),
            views: pre_views
                .into_iter()
                .map(|mut v| {
                    v.variant = "N_pre".into();
                    v
                })
                .collect(),
            requests: BTreeMap::from([("N_pre".to_string(), pre_requests)]),
            sync_results: BTreeMap::new(),
        };
        if self.on("H13") {
            self.suite.checkpoint(&self.chain, observation);
        }
        let n_result = n.settle().err();
        // N_seq: the same fresh restore, with A0 synced alone before A1 is
        // added, so adding an account rewinds a synced wallet.
        let n_seq = VizorWallet::import_sequential("N_seq", &self.chain, &self.a0, &self.a1);
        let n_seq_result = n_seq.settle().err();
        checkpoint(
            &self.chain,
            &mut self.suite,
            "final",
            &[(&self.r, "R"), (&o, "O"), (&n, "N"), (&n_seq, "N_seq")],
            BTreeMap::from([
                ("R".to_string(), r_result),
                ("O".to_string(), o_result),
                ("N".to_string(), n_result),
                ("N_seq".to_string(), n_seq_result),
            ]),
        );
    }

    /// H13: fresh restores under transport faults.
    fn h13(&mut self) {
        let cut = VizorWallet::import("N_cut", &self.chain, &self.a0, &self.a1);
        cut.proxy.cut_taddress_txids_after(Some(0));
        let cut_result = cut.sync().err();
        checkpoint(
            &self.chain,
            &mut self.suite,
            "h13_cut",
            &[(&cut, "N_cut")],
            BTreeMap::from([("N_cut".to_string(), cut_result)]),
        );
        let fail = VizorWallet::import("N_utxo_fail", &self.chain, &self.a0, &self.a1);
        fail.proxy.fail_address_utxos(true);
        let fail_result = fail.sync().err();
        checkpoint(
            &self.chain,
            &mut self.suite,
            "h13_utxo_fail",
            &[(&fail, "N_utxo_fail")],
            BTreeMap::from([("N_utxo_fail".to_string(), fail_result)]),
        );
    }

    /// H13 (private profile): fresh restores while the transparent PIR
    /// service lags the chain by 60 blocks (H12's activity unpublished; the
    /// sync waits out the coordinator's budget for it), then while it fails
    /// every private query. Once both faults clear, each restore settles and
    /// must recover: current authority and the chain's ledger, UTXO set and
    /// balance (N_lag_settled, N_pir_fail_settled).
    fn h13_private(&mut self) {
        let publisher = crate::publication::global().expect("the private profile's publisher");
        let lag = VizorWallet::import("N_lag", &self.chain, &self.a0, &self.a1);
        publisher.set_lag(60);
        let lag_result = lag.sync().err();
        publisher.set_lag(0);
        checkpoint(
            &self.chain,
            &mut self.suite,
            "h13_lag",
            &[(&lag, "N_lag")],
            BTreeMap::from([("N_lag".to_string(), lag_result)]),
        );
        let fail = VizorWallet::import("N_pir_fail", &self.chain, &self.a0, &self.a1);
        publisher.fail_queries(true);
        let fail_result = fail.sync().err();
        publisher.fail_queries(false);
        checkpoint(
            &self.chain,
            &mut self.suite,
            "h13_pir_fail",
            &[(&fail, "N_pir_fail")],
            BTreeMap::from([("N_pir_fail".to_string(), fail_result)]),
        );
        let lag_result = lag.settle_retrying().err();
        let fail_result = fail.settle_retrying().err();
        checkpoint(
            &self.chain,
            &mut self.suite,
            "h13_recovered",
            &[(&lag, "N_lag_settled"), (&fail, "N_pir_fail_settled")],
            BTreeMap::from([
                ("N_lag_settled".to_string(), lag_result),
                ("N_pir_fail_settled".to_string(), fail_result),
            ]),
        );
    }

    /// N_toggle (private profile): a public restore raised to private
    /// recovery and lowered again; see [`VizorWallet::import_toggled`].
    fn n_toggle(&mut self) {
        let (_wallet, findings) =
            VizorWallet::import_toggled("N_toggle", &self.chain, &self.a0, &self.a1);
        self.suite.verdict(
            "toggle",
            "H13",
            "N_toggle",
            findings.problems,
            findings.notes,
        );
    }

    /// N_restart (private profile): a private restore, recovered, then,
    /// once the chain has moved past its private ledger, synced from a fresh
    /// process (this test binary's `restart_child`) that never sets the
    /// private-queries preference, as a launch before Dart applies it. The
    /// stored `PrivateRequired` policy must hold: every account stays
    /// private, its transparent recovery is stopped as not selected rather
    /// than answered publicly, and no request to the wallet's lightwalletd
    /// proxy names a transparent subject. (With the tip unmoved the private
    /// ledger still covers it and authority stays current.)
    fn n_restart(&mut self) {
        let wallet = VizorWallet::import("N_restart", &self.chain, &self.a0, &self.a1);
        let mut problems = Vec::new();
        let mut notes = Vec::new();
        if let Err(e) = wallet.settle_retrying() {
            problems.push(format!("before the restart: sync failed: {e}"));
        }
        for account in &wallet.accounts {
            match wallet.balance(account.name) {
                Ok(b) if b.transparent_private && b.transparent_authority == "current" => {}
                other => problems.push(format!(
                    "before the restart: {} has not recovered privately: {other:?}",
                    account.name
                )),
            }
        }
        // Past the private ledger's coverage: only recovery could make the
        // restarted process's transparent balances current again.
        self.mine(1);
        let _ = wallet.proxy.take_requests();
        let publisher = crate::publication::global().expect("the private profile's publisher");
        let private_queries = |counts: BTreeMap<String, usize>| -> usize {
            counts
                .iter()
                .filter(|(route, _)| route.starts_with("POST "))
                .map(|(_, n)| n)
                .sum()
        };
        let queries_before = private_queries(publisher.route_counts());
        let out = self.suite.out.join("restart-child.json");
        let _ = std::fs::remove_file(&out);
        let accounts = wallet
            .accounts
            .iter()
            .map(|a| format!("{}={}", a.name, a.uuid))
            .collect::<Vec<_>>()
            .join(",");
        let status = std::process::Command::new(std::env::current_exe().expect("test binary"))
            .args([
                "--ignored",
                "--exact",
                "restart_child",
                "--nocapture",
                "--test-threads=1",
            ])
            .env("TH_RESTART_DB", &wallet.db)
            .env("TH_RESTART_LWD", &wallet.proxy.url)
            .env("TH_RESTART_ACCOUNTS", accounts)
            .env("TH_RESTART_OUT", &out)
            .status();
        let queries = private_queries(publisher.route_counts()) - queries_before;
        match status {
            Ok(status) if status.success() => {}
            other => problems.push(format!("the restarted process failed: {other:?}")),
        }
        let result: serde_json::Value = std::fs::read(&out)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or(serde_json::Value::Null);
        for (index, sync) in result["syncs"].as_array().into_iter().flatten().enumerate() {
            if !sync.is_null() {
                problems.push(format!("restarted sync {}: {sync}", index + 1));
            }
        }
        for account in &wallet.accounts {
            let b = &result["balances"][account.name];
            if b["transparent_private"] != json!(true) {
                problems.push(format!(
                    "{}: the restarted process does not keep it private: {b}",
                    account.name
                ));
            }
            if b["transparent_authority"] != json!("stopped")
                || b["transparent_stop"] != json!("opt_out_unfinished")
            {
                problems.push(format!(
                    "{}: expected recovery stopped, the wallet still private, in a process with private queries unset: {b}",
                    account.name
                ));
            }
            notes.push(format!("{} after the restart: {b}", account.name));
        }
        let requests = wallet.proxy.take_requests();
        let named = crate::proxy::transparent_subject_count(&requests);
        notes.push(format!(
            "restarted process: {} lightwalletd requests, {named} with a transparent subject; {queries} transparent PIR queries",
            requests.len()
        ));
        if requests.is_empty() {
            problems
                .push("the restarted process sent lightwalletd nothing: it did not sync".into());
        }
        if named > 0 {
            problems.push(format!(
                "the restarted process sent {named} requests naming a transparent subject"
            ));
        }
        self.suite
            .verdict("restart", "H13", "N_restart", problems, notes);
    }

    /// N_discover (private profile): erin's seed, whose accounts 1, 2 and 6
    /// hold only transparent funds, restored through onboarding's discovery
    /// (`discover_software_wallet_import_accounts`, then
    /// `import_software_wallet_with_account_discovery`) with private queries
    /// on. Import discovery's query budget is lowered
    /// ([`DISCOVERY_MAX_QUERIES`], debug builds on regtest only) so account
    /// 1's history stops the first pass; the continuation must still find
    /// every funded account. The restored wallet then recovers privately:
    /// each account's transparent balance must be current and match zcashd's
    /// address index. lightwalletd must see no transparent subject.
    fn n_discover(&mut self) {
        let publisher = crate::publication::global().expect("the private profile's publisher");
        let mut problems = Vec::new();
        let mut notes = Vec::new();
        for (account, receives) in ERIN_FUNDED {
            let address = self.erin_party(account).address(Scope::External, 0);
            for receive in 0..receives {
                let value = ZEC / 10 * (u64::from(receive) + 1) + u64::from(account) * 1_000;
                self.faucet.pay(&self.chain, &[(&address, value)]);
            }
        }
        self.mine(1);
        self.mine(3);
        publisher.catch_up();
        let proxy = Proxy::start(&self.chain.lwd_url());
        let scratch = tempfile::tempdir().expect("discovery dir");
        let db = scratch.path().join("zcash_wallet.db");
        // One discovery at the default budget, then one at the lowered
        // budget. A complete pass over the same candidates and publication
        // always does the same private work, and the library runs every
        // continuation pass inside one call over the shard map it already
        // has. So a lowered run whose private work differs from the default
        // run's had a pass its budget stopped, and since only a further pass
        // turns that stop into a complete answer, finding the same accounts
        // proves the continuation ran.
        const WORK: [(&str, &str); 4] = [
            ("manifests", "/manifest"),
            ("setups", "/setup/"),
            ("directory queries", "/query/directory"),
            ("page queries", "/query/pages"),
        ];
        let discover = |budget: Option<&str>| {
            let before = publisher.route_counts();
            if let Some(budget) = budget {
                std::env::set_var("ZCASH_E2E_REGTEST_DISCOVERY_MAX_QUERIES", budget);
            }
            let result =
                rust_lib_zcash_wallet::api::wallet::discover_software_wallet_import_accounts(
                    self.erin[0].1.mnemonic.clone(),
                    String::new(),
                    Some(1),
                    "regtest".into(),
                    db.to_string_lossy().into(),
                    proxy.url.clone(),
                    true,
                );
            std::env::remove_var("ZCASH_E2E_REGTEST_DISCOVERY_MAX_QUERIES");
            let after = publisher.route_counts();
            let grew = |pattern: &str| -> usize {
                after
                    .iter()
                    .filter(|(route, _)| route.contains(pattern) && !route.contains("/txid/"))
                    .map(|(route, n)| n - before.get(route).copied().unwrap_or(0))
                    .sum()
            };
            let found: Result<Vec<u32>, String> =
                result.map(|r| r.accounts.iter().map(|a| a.zip32_account_index).collect());
            (found, WORK.map(|(_, pattern)| grew(pattern)))
        };
        let describe = |work: &[usize; 4]| {
            WORK.iter()
                .zip(work)
                .map(|((name, _), n)| format!("{n} {name}"))
                .collect::<Vec<_>>()
                .join(", ")
        };
        let funded: Vec<u32> = ERIN_FUNDED.iter().map(|&(account, _)| account).collect();
        let (baseline, baseline_work) = discover(None);
        notes.push(format!(
            "discovery at the default budget: {baseline:?}, {}",
            describe(&baseline_work)
        ));
        let (budgeted, work) = discover(Some(DISCOVERY_MAX_QUERIES));
        notes.push(format!(
            "discovery at query budget {DISCOVERY_MAX_QUERIES}: {budgeted:?}, {}",
            describe(&work)
        ));
        if baseline.as_ref() != Ok(&funded) {
            problems.push(format!(
                "discovery at the default budget found {baseline:?}, the funded accounts are {funded:?}"
            ));
        }
        if work == baseline_work {
            problems.push(format!(
                "the lowered budget did the default budget's private work ({}): no pass was stopped by its budget, so the continuation was not exercised",
                describe(&work)
            ));
        }
        let found = match budgeted {
            Ok(found) => found,
            Err(e) => {
                problems.push(format!("discovery at the lowered budget failed: {e}"));
                Vec::new()
            }
        };
        if found != funded {
            problems.push(format!(
                "discovery at the lowered budget found accounts {found:?}, the funded accounts are {funded:?}"
            ));
        }
        match VizorWallet::import_discovered(
            "N_discover",
            proxy,
            &self.erin[0].1,
            &found,
            erin_name,
        ) {
            Ok(wallet) => {
                if let Err(e) = wallet.settle_retrying() {
                    problems.push(format!("sync failed: {e}"));
                }
                for (account, _) in ERIN_FUNDED {
                    let name = erin_name(account);
                    if !wallet.accounts.iter().any(|a| a.name == name) {
                        problems.push(format!("{name} was not imported"));
                        continue;
                    }
                    let address = self.erin_party(account).address(Scope::External, 0);
                    let utxos = self
                        .chain
                        .rpc_ok("getaddressutxos", json!([{ "addresses": [address] }]));
                    let chain_total: u64 = utxos
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|u| u["satoshis"].as_u64().unwrap())
                        .sum();
                    match wallet.balance(name) {
                        Ok(b) if b.transparent_authority == "current"
                            && b.transparent == chain_total => {}
                        other => problems.push(format!(
                            "{name}: transparent balance is not current at zcashd's {chain_total}: {other:?}"
                        )),
                    }
                }
                let requests = wallet.proxy.take_requests();
                let named = crate::proxy::transparent_subject_count(&requests);
                notes.push(format!(
                    "discovery, import and sync: {} lightwalletd requests, {named} with a transparent subject",
                    requests.len()
                ));
                if named > 0 {
                    problems.push(format!(
                        "{named} lightwalletd requests named a transparent subject"
                    ));
                }
            }
            Err(e) => problems.push(format!("import of the discovered accounts failed: {e}")),
        }
        self.suite
            .verdict("discover", "H03", "N_discover", problems, notes);
    }

    fn erin_party(&self, account: u32) -> &Party {
        &self
            .erin
            .iter()
            .find(|(index, _)| *index == account)
            .expect("an erin account")
            .1
    }

    /// N_spend (private profile): a fresh private restore (policy raised
    /// before its first sync) shields what it recovered of both accounts'
    /// transparent funds and sends from A1's shielded funds to B through
    /// Vizor's production paths; each transaction must be mined, and the
    /// restore's activity and balances must match the oracle (H07's
    /// checkpoint `spend`).
    fn n_spend(&mut self) {
        let n = VizorWallet::import("N_spend", &self.chain, &self.a0, &self.a1);
        if let Err(e) = n.settle_retrying() {
            panic!("N_spend sync failed: {e}\n{}", self.chain.container_logs());
        }
        let built_by = json!({"built_by": "N_spend"});
        let mut shields = Vec::new();
        for account in ["A0", "A1"] {
            for txid in n.shield(account) {
                self.suite.tx_full(
                    "H07",
                    &txid,
                    "V",
                    "shield",
                    owner_shielded(account),
                    None,
                    built_by.clone(),
                );
                shields.push(txid);
            }
        }
        self.n_mined(&n, &shields);
        let to = self.b.address(Scope::External, 10);
        let sent = n.send("A1", &to, ZEC);
        for txid in &sent {
            self.suite.tx_full(
                "H07",
                txid,
                "V",
                "shielded_to_external_t",
                owner_shielded("A1"),
                None,
                built_by.clone(),
            );
        }
        self.n_mined(&n, &sent);
        let result = n.settle().err();
        checkpoint(
            &self.chain,
            &mut self.suite,
            "spend",
            &[(&n, "N_spend")],
            BTreeMap::from([("N_spend".to_string(), result)]),
        );
    }

    /// Mines `txids`, which `wallet` built, past the trusted confirmation
    /// depth, and settles `wallet`.
    fn n_mined(&self, wallet: &VizorWallet, txids: &[String]) {
        self.mine(1);
        for txid in txids {
            assert!(
                self.chain.mined_height(txid).is_some(),
                "{} transaction {txid} was not mined",
                wallet.label
            );
        }
        self.mine(3);
        if let Err(e) = wallet.settle_retrying() {
            panic!("{} sync failed: {e}", wallet.label);
        }
    }

    pub fn finish(&mut self) -> i32 {
        std::fs::write(
            self.suite.out.join("chain.env"),
            format!(
                "TH_CHAIN_NODE={}\nTH_CHAIN_LWD={}\nTH_CHAIN_DIR={}\n",
                self.chain.node,
                self.chain.lwd,
                self.chain.data_dir().display()
            ),
        )
        .unwrap();
        // The private app layer reaches lightwalletd through a recording
        // proxy, so its requests are checked like the Rust layer's.
        let mut app_proxy = None;
        if let Ok(dir) = std::env::var("TH_FLUTTER_HANDOFF_DIR") {
            // An unmined receive the app's mempool observer should show as
            // in progress (H12 pending, app layer).
            if self.on("H12") {
                let address = self.a0.address(Scope::External, 18);
                let txid = self.faucet.pay(&self.chain, &[(&address, 33 * ZEC / 100)]);
                self.suite
                    .tx("H12", &txid, "Z", "pending_receive", Attribution::default());
            }
            let tpir_url = crate::publication::global().map(Publisher::url);
            app_proxy = tpir_url.map(|_| Proxy::start(&self.chain.lwd_url()));
            let lwd_url = app_proxy
                .as_ref()
                .map_or_else(|| self.chain.lwd_url(), |proxy| proxy.url.clone());
            self.suite.handoff(
                &self.chain,
                Path::new(&dir),
                &lwd_url,
                &self.a0,
                &self.a1,
                tpir_url,
            );
        }
        for (label, elapsed) in &self.timings {
            eprintln!("[timing] {label}: {:.1}s", elapsed.as_secs_f64());
        }
        crate::report::write_json(
            &self.suite.out.join("timings.json"),
            &self
                .timings
                .iter()
                .map(|(l, d)| (l.clone(), d.as_secs_f64()))
                .collect::<BTreeMap<_, _>>(),
        );
        let status = self.suite.finish(&self.chain);
        match crate::publication::global() {
            Some(publisher) => {
                // Every request the transparent PIR service received, by
                // route, and every privacy violation (which fails the run).
                let path = self.suite.out.join("pir-requests.json");
                let violations = publisher.privacy_violations();
                let mut requests = json!({
                    "origin": publisher.url(),
                    "routes": publisher.route_counts(),
                    "violations": violations,
                });
                crate::report::write_json(&path, &requests);
                for violation in &violations {
                    eprintln!("[tpir] privacy violation: {violation}");
                }
                let mut status = if violations.is_empty() {
                    status
                } else {
                    status.max(1)
                };
                if let Ok(dir) = std::env::var("TH_FLUTTER_HANDOFF_DIR") {
                    let (routes, mut violations) =
                        serve_app_layer(publisher, Path::new(&dir), status);
                    let lightwalletd = app_proxy.as_ref().map(|proxy| {
                        let summary = lightwalletd_summary(&proxy.take_requests());
                        let named = summary["with_transparent_subject"].as_u64().unwrap_or(0);
                        if named > 0 {
                            violations.push(format!(
                                "{named} lightwalletd requests named a transparent subject"
                            ));
                        }
                        summary
                    });
                    for violation in &violations {
                        eprintln!("[tpir] app layer privacy violation: {violation}");
                    }
                    if !violations.is_empty() {
                        status = status.max(1);
                    }
                    requests["app"] = json!({
                        "routes": routes,
                        "violations": violations,
                        "lightwalletd": lightwalletd,
                    });
                    crate::report::write_json(&path, &requests);
                }
                status
            }
            None => status,
        }
    }
}

/// The app layer's lightwalletd requests by method, and how many named a
/// transparent subject.
fn lightwalletd_summary(requests: &[RequestRecord]) -> serde_json::Value {
    let mut methods = BTreeMap::<&str, usize>::new();
    for request in requests {
        *methods.entry(request.method.as_str()).or_default() += 1;
    }
    let named = crate::proxy::transparent_subject_count(requests);
    json!({
        "requests": requests.len(),
        "with_transparent_subject": named,
        "methods": methods,
    })
}

/// Longest the Rust layer serves the app layer for a runner that never says
/// it is done.
const APP_LAYER_SERVICE_LIMIT: Duration = Duration::from_secs(3 * 60 * 60);

/// Keeps the transparent PIR service up for the app layer once the Rust
/// layer is done: the final publication on the same origin, H13's faults
/// cleared, and a fresh request record. Writes `tpir-ready` (holding the Rust
/// layer's status) to the runner's handoff directory `dir`, then serves
/// until the runner creates `tpir-stop` there, removes the directory, or
/// [`APP_LAYER_SERVICE_LIMIT`] passes. Returns the app layer's requests by
/// route and its privacy violations, which include the positive controls: an
/// app that made no private query is a violation.
fn serve_app_layer(
    publisher: &Publisher,
    dir: &Path,
    rust_status: i32,
) -> (BTreeMap<String, usize>, Vec<String>) {
    publisher.set_lag(0);
    publisher.fail_queries(false);
    publisher.catch_up();
    publisher.reset_requests();
    std::fs::write(dir.join("tpir-ready"), format!("{rust_status}\n"))
        .expect("tell the runner the transparent PIR service is ready");
    eprintln!(
        "[tpir] serving the app layer on {} until the runner stops it",
        publisher.url()
    );
    let deadline = Instant::now() + APP_LAYER_SERVICE_LIMIT;
    while dir.is_dir() && !dir.join("tpir-stop").exists() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_secs(1));
    }
    let counts = publisher.route_counts();
    eprintln!(
        "[tpir] app layer: {} requests",
        counts.values().sum::<usize>()
    );
    (counts, publisher.privacy_violations())
}

/// Observes every wallet, then has the oracle derive and compare.
fn checkpoint(
    chain: &Chain,
    suite: &mut Suite,
    label: &str,
    wallets: &[(&VizorWallet, &str)],
    sync_results: BTreeMap<String, Option<String>>,
) {
    let mut views = Vec::new();
    let mut requests = BTreeMap::new();
    for (wallet, variant) in wallets {
        for mut view in wallet.observe_all() {
            view.variant = variant.to_string();
            views.push(view);
        }
        requests.insert(variant.to_string(), wallet.proxy.take_requests());
    }
    let observation = Observation {
        checkpoint: label.into(),
        tip: chain.tip(),
        tip_hash: chain.tip_hash(),
        views,
        requests,
        sync_results,
    };
    suite.checkpoint(chain, observation);
}
