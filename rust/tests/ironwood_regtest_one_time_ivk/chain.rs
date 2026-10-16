//! The Dockerized Ironwood regtest node (`scripts/ironwood-regtest`): its harness
//! scripts, its JSON-RPC, and a mock clock that Vizor's one-time IVK clock follows.

use std::{
    io::{Read, Write},
    net::TcpStream,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use base64::Engine as _;
use rust_lib_zcash_wallet::api::{simple as simple_api, wallet as wallet_api};
use serde_json::{json, Value};

pub const NETWORK: &str = "regtest";
pub const MINUTE: i64 = 60;
pub const HOUR: i64 = 60 * MINUTE;
pub const DAY: i64 = 24 * HOUR;
pub const ZEC: u64 = 100_000_000;

/// Vizor's debug-only clock offset for one-time IVK lifecycles (see `one_time_ivk::now`).
const CLOCK_OFFSET_ENV: &str = "VIZOR_E2E_CLOCK_OFFSET_SECS";

/// The regtest node and lightwalletd, with a clock the test moves.
pub struct Stack {
    activation: u32,
    rpc_port: u16,
    lightwalletd_url: String,
    /// Seconds the chain's clock, and Vizor's, run ahead of the wall clock.
    offset: i64,
}

impl Stack {
    /// Resets the chain and starts the node on a mock clock, before Ironwood activates.
    pub fn start() -> Self {
        let activation = env_or("IRONWOOD_ACTIVATION_HEIGHT", 500);
        simple_api::configure_regtest_ironwood_activation_height(activation)
            .expect("the regtest activation height");
        run_harness("reset.sh", &[], &[]);
        // `setmocktime` needs the node started with `-mocktime`; `mine` keeps the node's
        // clock on the test's.
        let clock = format!("-mocktime={}", wall_now());
        run_harness("up.sh", &[], &[("IRONWOOD_ZCASHD_CLOCK_ARG", &clock)]);
        let stack = Self {
            activation,
            rpc_port: env_or("IRONWOOD_ZCASHD_RPC_PORT", 19232),
            lightwalletd_url: format!(
                "http://127.0.0.1:{}",
                env_or::<u16>("IRONWOOD_LIGHTWALLETD_PORT", 19067)
            ),
            offset: 0,
        };
        std::env::set_var(CLOCK_OFFSET_ENV, "0");
        stack
    }

    /// lightwalletd's URL, which Vizor syncs from.
    pub fn lightwalletd_url(&self) -> String {
        self.lightwalletd_url.clone()
    }

    /// The height Ironwood (NU6.3) activates at.
    pub fn activation(&self) -> u32 {
        self.activation
    }

    /// The chain's clock, which Vizor's one-time IVK clock also reads.
    pub fn now(&self) -> i64 {
        wall_now() + self.offset
    }

    /// Moves the chain's clock, and Vizor's with it, `secs` forward. Blocks mined after
    /// this carry the new time.
    pub fn advance(&mut self, secs: i64) {
        self.offset += secs;
        std::env::set_var(CLOCK_OFFSET_ENV, self.offset.to_string());
    }

    /// The node's chain tip height.
    pub fn tip(&self) -> u32 {
        u32::try_from(
            self.rpc("getblockcount", json!([]))
                .as_u64()
                .expect("a height"),
        )
        .expect("a regtest height")
    }

    /// Mines `blocks` at the chain's clock and waits for lightwalletd to serve them.
    pub fn mine(&self, blocks: u32) {
        self.rpc("setmocktime", json!([self.now()]));
        self.rpc("generate", json!([blocks]));
        let tip = self.tip();
        let deadline = Instant::now() + Duration::from_secs(120);
        loop {
            let served =
                wallet_api::get_latest_block_height(self.lightwalletd_url(), NETWORK.into());
            if matches!(served, Ok(height) if height >= u64::from(tip)) {
                return;
            }
            assert!(
                Instant::now() < deadline,
                "lightwalletd did not reach {tip}: {served:?}"
            );
            std::thread::sleep(Duration::from_millis(200));
        }
    }

    /// Funds each of `addresses` with one pre-activation Orchard note from the node's
    /// faucet, splitting `zec` evenly, and mines 10 blocks.
    pub fn fund_orchard(&self, addresses: &[&str], zec: u64) {
        let destinations = serde_json::to_string(addresses).expect("addresses encode");
        // The faucet shields this many 6.25 ZEC coinbase outputs first.
        let coinbase = (zec / 6 + 1).to_string();
        let notes = addresses.len().to_string();
        run_harness(
            "fund-orchard.sh",
            &[&destinations, &zec.to_string(), "10", &coinbase, &notes],
            &[],
        );
    }

    /// Mines up to Ironwood activation.
    pub fn activate_ironwood(&self) {
        self.rpc("setmocktime", json!([self.now()]));
        run_harness("activate-ironwood.sh", &[], &[]);
    }

    /// The block hash at `height`, in internal byte order.
    pub fn block_hash(&self, height: u32) -> [u8; 32] {
        internal_hash(
            self.rpc("getblockhash", json!([height]))
                .as_str()
                .expect("a hash"),
        )
    }

    /// The genesis block hash as `getblockhash` displays it.
    pub fn genesis_displayed(&self) -> String {
        self.rpc("getblockhash", json!([0]))
            .as_str()
            .expect("a hash")
            .to_owned()
    }

    /// The raw block at `height`.
    pub fn raw_block(&self, height: u32) -> Vec<u8> {
        let block = self.rpc("getblock", json!([height.to_string(), 0]));
        hex::decode(block.as_str().expect("block hex")).expect("valid block hex")
    }

    /// Broadcasts a raw transaction, returning its txid as the node displays it.
    pub fn send_raw(&self, tx: &[u8]) -> String {
        self.rpc("sendrawtransaction", json!([hex::encode(tx)]))
            .as_str()
            .expect("a txid")
            .to_owned()
    }

    /// Calls the node's JSON-RPC, panicking on an RPC error.
    pub fn rpc(&self, method: &str, params: Value) -> Value {
        let body = json!({"jsonrpc": "1.0", "id": "vizor-e2e", "method": method, "params": params})
            .to_string();
        let auth = base64::engine::general_purpose::STANDARD.encode("zcash:zcash");
        let mut stream =
            TcpStream::connect(("127.0.0.1", self.rpc_port)).expect("the node's RPC port");
        stream
            .set_read_timeout(Some(Duration::from_secs(300)))
            .expect("a read timeout");
        write!(
            stream,
            "POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Basic {auth}\r\n\
             Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        )
        .expect("the RPC request writes");
        let mut response = Vec::new();
        stream.read_to_end(&mut response).expect("the RPC response");
        let start = response
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .expect("an HTTP response")
            + 4;
        let reply: Value = serde_json::from_slice(&response[start..]).unwrap_or_else(|e| {
            panic!(
                "{method}: unreadable reply ({e}): {}",
                String::from_utf8_lossy(&response)
            )
        });
        assert!(reply["error"].is_null(), "{method}: {}", reply["error"]);
        reply["result"].clone()
    }
}

/// Runs a harness script from `scripts/ironwood-regtest` with extra environment, returning
/// its standard output.
pub fn run_harness(script: &str, args: &[&str], env: &[(&str, &str)]) -> String {
    let root = repo_root();
    let path = root.join("scripts/ironwood-regtest").join(script);
    let output = Command::new(&path)
        .args(args)
        .envs(env.iter().copied())
        .current_dir(&root)
        .output()
        .unwrap_or_else(|e| panic!("{script}: {e}"));
    assert!(
        output.status.success(),
        "{script} failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8_lossy(&output.stdout).into_owned()
}

/// A hash the node displays, in internal byte order.
pub fn internal_hash(displayed: &str) -> [u8; 32] {
    let mut bytes: [u8; 32] = hex::decode(displayed)
        .expect("hash hex")
        .try_into()
        .expect("a 32-byte hash");
    bytes.reverse();
    bytes
}

/// The wall clock in Unix seconds.
fn wall_now() -> i64 {
    i64::try_from(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("after the epoch")
            .as_secs(),
    )
    .expect("fits")
}

/// The environment variable `name` parsed as `T`, or `default` when unset or invalid.
fn env_or<T: std::str::FromStr>(name: &str, default: T) -> T {
    std::env::var(name)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

/// The Vizor repository root, one level above the Rust crate.
fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("the repository root")
        .to_path_buf()
}
