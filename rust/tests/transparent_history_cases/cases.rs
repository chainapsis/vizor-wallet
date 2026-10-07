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
            let alice: Vec<Vec<u8>> = suite
                .ownership
                .iter()
                .filter(|(_, owner)| owner.wallet == "alice")
                .map(|(script, _)| hex::decode(script).expect("hex script"))
                .collect();
            publisher.watch(&alice);
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
    /// view, which H13 asserts as the delayed-publication fault).
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
        let (n_seq, n_seq_first) =
            VizorWallet::import_sequential("N_seq", &self.chain, &self.a0, &self.a1);
        let n_seq_result = n_seq.settle().err().or(n_seq_first);
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
    /// every private query.
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

/// lightwalletd methods that name a transparent subject: an address, or a
/// txid (`GetTransaction`).
const TRANSPARENT_SUBJECT_METHODS: &[&str] = &[
    "GetAddressUtxos",
    "GetAddressUtxosStream",
    "GetTaddressTxids",
    "GetTaddressTransactions",
    "GetTaddressBalance",
    "GetTaddressBalanceStream",
    "GetTransaction",
];

/// The app layer's lightwalletd requests by method, and how many named a
/// transparent subject.
fn lightwalletd_summary(requests: &[RequestRecord]) -> serde_json::Value {
    let mut methods = BTreeMap::<&str, usize>::new();
    for request in requests {
        *methods.entry(request.method.as_str()).or_default() += 1;
    }
    let named = requests
        .iter()
        .filter(|r| TRANSPARENT_SUBJECT_METHODS.contains(&r.method.as_str()))
        .count();
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
