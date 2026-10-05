//! Suite bookkeeping: the ownership map, the authored case manifest, per
//! checkpoint observations, and the bridge to the independent oracle
//! (`scripts/e2e/transparent_history_oracle.py`).
//!
//! Everything written here is public chain data or non-secret associations:
//! addresses, scripts, txids, authored intent. Never mnemonics or keys.

use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    process::Command,
};

use serde::Serialize;
use serde_json::{json, Value};

use crate::{
    chain::Chain,
    keys::{Party, Scope},
    vizor::Observation,
};

/// The expectation profile this run qualifies: `public` (transparent
/// discovery through lightwalletd) or `private` (transparent PIR recovery,
/// `PrivateRequired`). Each names the oracle module
/// `scripts/e2e/transparent_history_profile_<profile>.py`. Set once per
/// process, before the run, by the test that runs it.
static PROFILE: std::sync::OnceLock<&'static str> = std::sync::OnceLock::new();

/// The profile this run qualifies; `public` until one is set.
pub fn profile() -> &'static str {
    PROFILE.get().copied().unwrap_or("public")
}

/// Selects the run's profile. Once per process.
pub fn set_profile(profile: &'static str) {
    assert!(
        matches!(profile, "public" | "private"),
        "unknown profile {profile}"
    );
    assert!(
        PROFILE.set(profile).is_ok() || self::profile() == profile,
        "the profile is already {}",
        self::profile()
    );
}

pub const REQUIRED_CASES: [&str; 13] = [
    "H01", "H02", "H03", "H04", "H05", "H06", "H07", "H08", "H09", "H10", "H11", "H12", "H13",
];

#[derive(Serialize, Clone)]
pub struct Owner {
    pub wallet: String,
    pub account: String,
    pub scope: String,
    pub index: u32,
    pub address: String,
}

/// Authored attribution for components the oracle cannot read from the
/// chain: shielded inputs and outputs. Written from construction intent,
/// never from Vizor output.
#[derive(Serialize, Default, Clone)]
pub struct Attribution {
    /// Every shielded input and output belongs to this account, except the
    /// external amounts below.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shielded_owner: Option<String>,
    /// Explicit owned shielded net per account (zatoshis), when known exactly.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub shielded_net: BTreeMap<String, i64>,
    #[serde(skip_serializing_if = "is_zero")]
    pub external_shielded_out: u64,
    #[serde(skip_serializing_if = "is_zero")]
    pub external_shielded_in: u64,
}

fn is_zero(v: &u64) -> bool {
    *v == 0
}

#[derive(Serialize, Clone)]
pub struct TxRecord {
    pub case: String,
    /// Display-order txid.
    pub txid: String,
    /// `V` Vizor, `S` harness signer, `Z` zcashd faucet, `M` miner (coinbase).
    pub builder: String,
    /// Closed vocabulary the profiles key on (see the oracle README section).
    pub intent: String,
    pub attribution: Attribution,
    /// Application records the reference wallet retains for this tx (H11).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retained_record: Option<String>,
    /// Extra authored facts (e.g. linked TEX leg, conflicted outpoint).
    #[serde(skip_serializing_if = "Value::is_null")]
    pub links: Value,
}

#[derive(Serialize, Clone)]
pub struct CaseRecord {
    pub id: String,
    pub title: String,
    /// Checkpoint label -> variants asserted there (R, N, O, fault variants).
    pub checkpoints: BTreeMap<String, Vec<String>>,
    /// H04 compares retained and restored views of these cases' V-built txs.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub source_cases: Vec<String>,
    pub notes: Vec<String>,
}

/// How much evidence a variant has when observed: `complete` (settled sync),
/// `pre_enrichment` (GetTransaction held), or `fault` (injected transport
/// faults: lightwalletd in the public profile, the transparent PIR service in
/// the private one).
pub const VARIANT_KINDS: [(&str, &str); 5] = [
    ("N_pre", "pre_enrichment"),
    ("N_cut", "fault"),
    ("N_utxo_fail", "fault"),
    ("N_lag", "fault"),
    ("N_pir_fail", "fault"),
];

pub struct Suite {
    pub out: PathBuf,
    pub ownership: BTreeMap<String, Owner>,
    pub cases: BTreeMap<String, CaseRecord>,
    pub txs: Vec<TxRecord>,
    pub checkpoints: Vec<Value>,
    /// (checkpoint, oracle compare exit status, summary JSON).
    pub results: Vec<(String, i32, Value)>,
}

pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}

fn oracle_path() -> PathBuf {
    repo_root()
        .join("scripts")
        .join("e2e")
        .join("transparent_history_oracle.py")
}

pub fn write_json(path: &Path, value: &impl Serialize) {
    std::fs::write(path, serde_json::to_vec_pretty(value).unwrap())
        .unwrap_or_else(|e| panic!("write {}: {e}", path.display()));
}

impl Suite {
    pub fn new() -> Self {
        let out = std::env::var("TH_OUT_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                repo_root()
                    .join("rust")
                    .join("target")
                    .join("transparent-history-cases")
                    .join(format!(
                        "run-{}",
                        std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap()
                            .as_secs()
                    ))
            });
        std::fs::create_dir_all(&out).unwrap();
        eprintln!("[suite] output: {}", out.display());
        Suite {
            out,
            ownership: BTreeMap::new(),
            cases: BTreeMap::new(),
            txs: Vec::new(),
            checkpoints: Vec::new(),
            results: Vec::new(),
        }
    }

    pub fn own(&mut self, party: &Party, scope: Scope, indices: std::ops::Range<u32>) {
        for index in indices {
            self.ownership.insert(
                party.script_hex(scope, index),
                Owner {
                    wallet: party.wallet.into(),
                    account: party.name.into(),
                    scope: scope.label().into(),
                    index,
                    address: party.address(scope, index),
                },
            );
        }
    }

    pub fn case(&mut self, id: &str, title: &str, checkpoints: &[(&str, &[&str])]) {
        self.cases.insert(
            id.into(),
            CaseRecord {
                id: id.into(),
                title: title.into(),
                checkpoints: checkpoints
                    .iter()
                    .map(|(c, v)| (c.to_string(), v.iter().map(|v| v.to_string()).collect()))
                    .collect(),
                source_cases: Vec::new(),
                notes: Vec::new(),
            },
        );
    }

    pub fn note(&mut self, case: &str, note: impl Into<String>) {
        if let Some(c) = self.cases.get_mut(case) {
            c.notes.push(note.into());
        }
    }

    pub fn tx(
        &mut self,
        case: &str,
        txid: &str,
        builder: &str,
        intent: &str,
        attribution: Attribution,
    ) {
        self.tx_full(case, txid, builder, intent, attribution, None, Value::Null);
    }

    pub fn tx_full(
        &mut self,
        case: &str,
        txid: &str,
        builder: &str,
        intent: &str,
        attribution: Attribution,
        retained_record: Option<&str>,
        links: Value,
    ) {
        eprintln!("[{case}] {builder} {intent} {txid}");
        self.txs.push(TxRecord {
            case: case.into(),
            txid: txid.into(),
            builder: builder.into(),
            intent: intent.into(),
            attribution,
            retained_record: retained_record.map(str::to_string),
            links,
        });
    }

    fn write_inputs(&self) {
        write_json(
            &self.out.join("ownership.json"),
            &json!({"network": "regtest", "scripts": self.ownership}),
        );
        write_json(
            &self.out.join("cases.json"),
            &json!({
                "profile": profile(),
                "required_cases": REQUIRED_CASES,
                "variant_kinds": VARIANT_KINDS.iter().cloned().collect::<BTreeMap<_, _>>(),
                "cases": self.cases,
                "txs": self.txs,
                "checkpoints": self.checkpoints,
            }),
        );
    }

    fn oracle(&self, args: &[&str]) -> (i32, String) {
        let output = Command::new("python3")
            .arg(oracle_path())
            .args(args)
            .output()
            .expect("run oracle");
        let text = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        (output.status.code().unwrap_or(-1), text)
    }

    /// Records a checkpoint: the oracle derives expectations from the live
    /// chain right now, then compares the observation against them.
    pub fn checkpoint(&mut self, chain: &Chain, observation: Observation) {
        let label = observation.checkpoint.clone();
        self.checkpoints.push(json!({
            "label": label,
            "tip": observation.tip,
            "tip_hash": observation.tip_hash,
        }));
        self.write_inputs();
        let observed = self.out.join(format!("observed-{label}.json"));
        write_json(&observed, &observation);
        let expected = self.out.join(format!("expected-{label}.json"));
        let (status, text) = self.oracle(&[
            "derive",
            "--rpc",
            &chain.rpc_url(),
            "--ownership",
            self.out.join("ownership.json").to_str().unwrap(),
            "--cases",
            self.out.join("cases.json").to_str().unwrap(),
            "--checkpoint",
            &label,
            "--profile",
            profile(),
            "--out",
            expected.to_str().unwrap(),
        ]);
        assert_eq!(status, 0, "oracle derive {label} failed:\n{text}");
        // The ownership negative control needs the live chain, so derive it now.
        if label == "final" {
            let mutated = self.out.join("expected-final-wrong-ownership.json");
            let (status, text) = self.oracle(&[
                "derive",
                "--rpc",
                &chain.rpc_url(),
                "--ownership",
                self.out.join("ownership.json").to_str().unwrap(),
                "--cases",
                self.out.join("cases.json").to_str().unwrap(),
                "--checkpoint",
                &label,
                "--profile",
                profile(),
                "--mutate-ownership",
                "--out",
                mutated.to_str().unwrap(),
            ]);
            assert_eq!(
                status, 0,
                "oracle derive (mutated ownership) failed:\n{text}"
            );
        }
        let report = self.out.join(format!("report-{label}.json"));
        let (status, text) = self.oracle(&[
            "compare",
            "--expected",
            expected.to_str().unwrap(),
            "--observed",
            observed.to_str().unwrap(),
            "--report",
            report.to_str().unwrap(),
        ]);
        eprintln!("[checkpoint {label}] oracle compare exit={status}\n{text}");
        let summary: Value = std::fs::read(&report)
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or(Value::Null);
        self.results.push((label, status, summary));
    }

    /// Hands the live chain to the Flutter layer: app-layer expectations from
    /// the oracle (fresh restore), plus a 0600 env file in the runner's
    /// private directory with the runtime mnemonics. The runner deletes it as
    /// soon as it has read it; nothing under `out` contains a mnemonic.
    pub fn handoff(&mut self, chain: &Chain, dir: &Path, a0: &Party, a1: &Party) {
        self.write_inputs();
        let ui = self.out.join("expected-ui.json");
        let (status, text) = self.oracle(&[
            "derive",
            "--rpc",
            &chain.rpc_url(),
            "--ownership",
            self.out.join("ownership.json").to_str().unwrap(),
            "--cases",
            self.out.join("cases.json").to_str().unwrap(),
            "--checkpoint",
            "flutter",
            "--profile",
            profile(),
            "--out",
            self.out.join("expected-flutter.json").to_str().unwrap(),
            "--ui-out",
            ui.to_str().unwrap(),
        ]);
        assert_eq!(status, 0, "oracle derive (flutter) failed:\n{text}");
        use base64::Engine as _;
        let encoded = base64::engine::general_purpose::STANDARD.encode(std::fs::read(&ui).unwrap());
        let path = dir.join("handoff.env");
        let body = format!(
            "TH_LWD_URL='{}'\nTH_RPC_URL='{}'\nTH_A0_MNEMONIC='{}'\nTH_A1_MNEMONIC='{}'\nTH_EXPECTED_UI='{}'\n",
            chain.lwd_url(),
            chain.rpc_url(),
            a0.mnemonic,
            a1.mnemonic,
            encoded
        );
        {
            use std::io::Write as _;
            #[cfg(unix)]
            use std::os::unix::fs::OpenOptionsExt as _;
            let mut options = std::fs::OpenOptions::new();
            options.write(true).create(true).truncate(true);
            #[cfg(unix)]
            options.mode(0o600);
            options
                .open(&path)
                .and_then(|mut f| f.write_all(body.as_bytes()))
                .expect("write handoff");
        }
        eprintln!("[handoff] chain handed to the Flutter layer");
    }

    /// Writes the manifest, runs the suite-level gate (all required cases
    /// evaluated, negative controls fail), and returns the gate's exit status.
    pub fn finish(&mut self, chain: &Chain) -> i32 {
        self.write_inputs();
        let (status, text) = self.oracle(&[
            "manifest",
            "--rpc",
            &chain.rpc_url(),
            "--out-dir",
            self.out.to_str().unwrap(),
            "--repo",
            repo_root().to_str().unwrap(),
        ]);
        eprintln!("[manifest] exit={status}\n{text}");
        assert_eq!(status, 0, "manifest failed");
        let (status, text) = self.oracle(&["gate", "--out-dir", self.out.to_str().unwrap()]);
        eprintln!("[gate] exit={status}\n{text}");
        status
    }
}
