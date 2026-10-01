//! Isolated Docker regtest chain: pinned zcashd + lightwalletd, own config,
//! mining to chosen addresses. Copied from the pattern in
//! `src/wallet/sync_engine/transparent_recovery_regtest.rs`; it never touches
//! the developer's shared `scripts/regtest` stack.

use std::{
    fs,
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    process::Command,
    time::{Duration, Instant},
};

use base64::Engine as _;
use rust_lib_zcash_wallet::api::wallet as wallet_api;
use serde_json::{json, Value};

pub const ZCASHD_IMAGE: &str =
    "electriccoinco/zcashd@sha256:40cdcad6c32da8bedacf77caba149198c7674f79aeced4043128ffb3e967efba";
pub const LIGHTWALLETD_IMAGE: &str = "electriccoinco/lightwalletd@sha256:a3dfb04b4054b78ae3107dcc804c3a15a6e38d1f0dfcadeac48da482dd1d3448";

const RPC_USER: &str = "history";
const RPC_PASSWORD: &str = "history";

/// Branch ids activated at height 1, matching `scripts/regtest/zcash.conf` and
/// `WalletNetwork::Regtest` (everything through NU6.2 at height 1, NU6.3 off).
const NUPARAMS: [&str; 9] = [
    "5ba81b19", "76b809bb", "2bb40e60", "f5b9230b", "e9ff75a6", "c2d6d0b4", "c8e71055", "4dec4df0",
    "5437f330",
];

fn docker(args: &[&str]) -> Result<String, String> {
    let result = Command::new("docker")
        .args(args)
        .output()
        .map_err(|e| format!("docker {args:?}: {e}"))?;
    if !result.status.success() {
        return Err(format!(
            "docker {args:?}: {}\n{}",
            String::from_utf8_lossy(&result.stderr),
            String::from_utf8_lossy(&result.stdout)
        ));
    }
    Ok(String::from_utf8_lossy(&result.stdout).trim().to_string())
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .and_then(|l| l.local_addr())
        .map(|a| a.port())
        .expect("free local port")
}

pub struct Chain {
    dir: tempfile::TempDir,
    pub node: String,
    pub lwd: String,
    pub rpc_port: u16,
    pub lwd_port: u16,
    keep: bool,
}

impl Drop for Chain {
    fn drop(&mut self) {
        if self.keep {
            eprintln!(
                "[chain] keeping containers {} / {} (TH_KEEP_CHAIN=1)",
                self.node, self.lwd
            );
            return;
        }
        for name in [&self.lwd, &self.node] {
            let _ = Command::new("docker").args(["rm", "-f", name]).output();
        }
    }
}

impl Chain {
    /// Starts zcashd, mines `coinbase_blocks` blocks to `coinbase_to` (a t-addr),
    /// then mines `mature_blocks` to zcashd's own wallet (the faucet Z), then
    /// starts lightwalletd.
    pub fn start(coinbase_to: &str, coinbase_blocks: u32, mature_blocks: u32) -> Self {
        let suffix = uuid::Uuid::new_v4().simple().to_string();
        let keep = std::env::var("TH_KEEP_CHAIN").as_deref() == Ok("1");
        let chain = Chain {
            // /tmp works as a Docker Desktop bind mount on macOS and Linux.
            dir: tempfile::Builder::new()
                .prefix("vizor-th-chain-")
                .tempdir_in("/tmp")
                .expect("chain tempdir"),
            node: format!("vizor-th-node-{}", &suffix[..12]),
            lwd: format!("vizor-th-lwd-{}", &suffix[..12]),
            rpc_port: free_port(),
            lwd_port: free_port(),
            keep,
        };
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(chain.dir.path(), fs::Permissions::from_mode(0o777)).unwrap();
        }
        chain.write_config(Some(coinbase_to));
        let mount = format!("{}:/work", chain.dir.path().display());
        let rpc_map = format!("127.0.0.1:{}:18232", chain.rpc_port);
        let lwd_map = format!("127.0.0.1:{}:9067", chain.lwd_port);
        docker(&[
            "run",
            "-d",
            "--name",
            &chain.node,
            "--platform",
            "linux/amd64",
            "-p",
            &rpc_map,
            "-p",
            &lwd_map,
            "-v",
            &mount,
            "--entrypoint",
            "zcashd",
            ZCASHD_IMAGE,
            "-conf=/work/zcash.conf",
            "-datadir=/work",
            "-printtoconsole",
        ])
        .expect("start zcashd");
        chain.wait_rpc();
        chain.generate(coinbase_blocks);
        // Restart so later blocks pay zcashd's own wallet (the faucet).
        docker(&["stop", &chain.node]).expect("stop zcashd");
        chain.write_config(None);
        docker(&["start", &chain.node]).expect("restart zcashd");
        chain.wait_rpc();
        chain.generate(mature_blocks);
        fs::write(
            chain.dir.path().join("lightwalletd.conf"),
            format!(
                "rpcuser={RPC_USER}\nrpcpassword={RPC_PASSWORD}\nrpcconnect=127.0.0.1\nrpcport=18232\n"
            ),
        )
        .unwrap();
        let network = format!("container:{}", chain.node);
        docker(&[
            "run",
            "-d",
            "--name",
            &chain.lwd,
            "--platform",
            "linux/amd64",
            "--network",
            &network,
            "-v",
            &mount,
            "--entrypoint",
            "lightwalletd",
            LIGHTWALLETD_IMAGE,
            "--no-tls-very-insecure",
            "--grpc-bind-addr",
            "0.0.0.0:9067",
            "--zcash-conf-path",
            "/work/lightwalletd.conf",
            "--data-dir",
            "/work/lwd",
            "--log-file",
            "/dev/stdout",
        ])
        .expect("start lightwalletd");
        chain.wait_lwd_tip();
        chain
    }

    fn write_config(&self, miner: Option<&str>) {
        let mut config = format!(
            "regtest=1\nserver=1\nlisten=0\ndiscover=0\ndnsseed=0\ntxindex=1\n\
             experimentalfeatures=1\nlightwalletd=1\ninsightexplorer=1\n\
             rpcuser={RPC_USER}\nrpcpassword={RPC_PASSWORD}\nrpcport=18232\n\
             rpcbind=0.0.0.0\nrpcallowip=0.0.0.0/0\n\
             allowdeprecated=z_getnewaddress\nallowdeprecated=getnewaddress\n\
             i-am-aware-zcashd-will-be-replaced-by-zebrad-and-zallet-in-2025=1\n\
             txunpaidactionlimit=50\n"
        );
        // Only fully paid (ZIP 317) transactions enter blocks. This lets the
        // reorg case keep a re-queued receive out of the replacement chain by
        // deprioritising it. Every builder in the suite pays ZIP 317 fees.
        config.push_str("blockunpaidactionlimit=0\n");
        for branch in NUPARAMS {
            config.push_str(&format!("nuparams={branch}:1\n"));
        }
        if let Some(address) = miner {
            config.push_str(&format!("mineraddress={address}\nminetolocalwallet=0\n"));
        }
        fs::write(self.dir.path().join("zcash.conf"), config).unwrap();
    }

    fn wait_rpc(&self) {
        let deadline = Instant::now() + Duration::from_secs(180);
        loop {
            if self.rpc("getblockcount", json!([])).is_ok() {
                return;
            }
            assert!(
                Instant::now() < deadline,
                "zcashd RPC startup timed out: {}",
                docker(&["logs", "--tail", "40", &self.node]).unwrap_or_default()
            );
            std::thread::sleep(Duration::from_millis(500));
        }
    }

    pub fn lwd_url(&self) -> String {
        format!("http://127.0.0.1:{}", self.lwd_port)
    }

    pub fn rpc_url(&self) -> String {
        format!(
            "http://{RPC_USER}:{RPC_PASSWORD}@127.0.0.1:{}",
            self.rpc_port
        )
    }

    /// Minimal JSON-RPC over HTTP/1.1 (zcashd closes the connection per call).
    pub fn rpc(&self, method: &str, params: Value) -> Result<Value, String> {
        let body =
            json!({"jsonrpc": "1.0", "id": "th", "method": method, "params": params}).to_string();
        let auth =
            base64::engine::general_purpose::STANDARD.encode(format!("{RPC_USER}:{RPC_PASSWORD}"));
        let mut stream = TcpStream::connect(("127.0.0.1", self.rpc_port))
            .map_err(|e| format!("rpc connect: {e}"))?;
        stream.set_read_timeout(Some(Duration::from_secs(300))).ok();
        let request = format!(
            "POST / HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Basic {auth}\r\n\
             Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream
            .write_all(request.as_bytes())
            .map_err(|e| format!("rpc write: {e}"))?;
        let mut response = Vec::new();
        stream
            .read_to_end(&mut response)
            .map_err(|e| format!("rpc read: {e}"))?;
        let response = String::from_utf8_lossy(&response);
        let body = response
            .split_once("\r\n\r\n")
            .map(|(_, b)| b)
            .ok_or_else(|| format!("rpc {method}: malformed response {response}"))?;
        let value: Value =
            serde_json::from_str(body.trim()).map_err(|e| format!("rpc {method}: {e}: {body}"))?;
        if !value["error"].is_null() {
            return Err(format!("rpc {method}: {}", value["error"]));
        }
        Ok(value["result"].clone())
    }

    pub fn rpc_ok(&self, method: &str, params: Value) -> Value {
        self.rpc(method, params)
            .unwrap_or_else(|e| panic!("zcashd {method}: {e}"))
    }

    pub fn tip(&self) -> u64 {
        self.rpc_ok("getblockcount", json!([])).as_u64().unwrap()
    }

    pub fn tip_hash(&self) -> String {
        self.rpc_ok("getbestblockhash", json!([]))
            .as_str()
            .unwrap()
            .to_string()
    }

    fn generate(&self, blocks: u32) -> Vec<String> {
        let mut hashes = Vec::new();
        // Small batches keep each RPC well inside the HTTP timeout under emulation.
        let mut left = blocks;
        while left > 0 {
            let step = left.min(50);
            let result = self.rpc_ok("generate", json!([step]));
            hashes.extend(
                result
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|h| h.as_str().unwrap().to_string()),
            );
            left -= step;
        }
        hashes
    }

    /// Mines `blocks` blocks and waits until lightwalletd serves the new tip.
    pub fn mine(&self, blocks: u32) -> Vec<String> {
        let hashes = self.generate(blocks);
        self.wait_lwd_tip();
        hashes
    }

    /// Waits until lightwalletd reports zcashd's current tip.
    pub fn wait_lwd_tip(&self) {
        let target = self.tip();
        let deadline = Instant::now() + Duration::from_secs(180);
        loop {
            if wallet_api::get_latest_block_height(self.lwd_url(), "regtest".into()).ok()
                == Some(target)
            {
                return;
            }
            assert!(
                Instant::now() < deadline,
                "lightwalletd did not reach tip {target}: {}",
                docker(&["logs", "--tail", "40", &self.lwd]).unwrap_or_default()
            );
            std::thread::sleep(Duration::from_millis(300));
        }
    }

    /// Waits for an async z_* operation and returns its txid.
    pub fn wait_operation(&self, opid: &str) -> String {
        let deadline = Instant::now() + Duration::from_secs(600);
        loop {
            let result = self.rpc_ok("z_getoperationresult", json!([[opid]]));
            if let Some(op) = result.as_array().and_then(|a| a.first()) {
                match op["status"].as_str() {
                    Some("success") => {
                        return op["result"]["txid"].as_str().unwrap().to_string();
                    }
                    Some("failed") => panic!("zcashd operation {opid} failed: {op}"),
                    _ => {}
                }
            }
            assert!(
                Instant::now() < deadline,
                "zcashd operation {opid} timed out"
            );
            std::thread::sleep(Duration::from_millis(500));
        }
    }

    pub fn in_mempool(&self, txid: &str) -> bool {
        self.rpc_ok("getrawmempool", json!([]))
            .as_array()
            .unwrap()
            .iter()
            .any(|t| t.as_str() == Some(txid))
    }

    /// Waits until zcashd's mempool holds `txid` (a broadcast reached the node).
    pub fn wait_mempool(&self, txid: &str) {
        let deadline = Instant::now() + Duration::from_secs(60);
        while !self.in_mempool(txid) {
            assert!(
                Instant::now() < deadline,
                "transaction {txid} never reached zcashd's mempool"
            );
            std::thread::sleep(Duration::from_millis(300));
        }
    }

    pub fn mined_height(&self, txid: &str) -> Option<u64> {
        let tx = self.rpc("getrawtransaction", json!([txid, 1])).ok()?;
        let hash = tx["blockhash"].as_str()?;
        let header = self.rpc_ok("getblockheader", json!([hash]));
        if header["confirmations"].as_i64().unwrap_or(-1) < 0 {
            return None;
        }
        header["height"].as_u64()
    }

    /// Mines one block at a time until `txid` is mined; fails fast if it never is.
    pub fn mine_until_mined(&self, txid: &str) -> u64 {
        for _ in 0..3 {
            self.mine(1);
            if let Some(height) = self.mined_height(txid) {
                return height;
            }
        }
        panic!("transaction {txid} was not mined (unpaid actions or rejected?)");
    }

    pub fn container_logs(&self) -> String {
        format!(
            "--- zcashd ---\n{}\n--- lightwalletd ---\n{}",
            docker(&["logs", "--tail", "60", &self.node]).unwrap_or_default(),
            docker(&["logs", "--tail", "60", &self.lwd]).unwrap_or_default()
        )
    }
}
