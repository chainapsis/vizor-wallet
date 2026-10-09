//! Client of the host-owned, case-local Zakura control. No shared stack startup.

use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddrV4, TcpStream};
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    schema_version: u32,
    scenario_id: String,
    run_id: String,
    worker_id: u32,
    case_index: u32,
    namespace: String,
    context_path: PathBuf,
    lightwalletd_port: u16,
    primary_proxy_port: u16,
    zcashd_rpc_port: u16,
    regtest_ironwood_activation_height: u32,
}

pub struct IsolatedControl {
    manifest: Manifest,
    wallet_root: PathBuf,
    next_source: u32,
}

impl IsolatedControl {
    pub fn from_environment() -> Option<Self> {
        let Some(encoded) = std::env::var_os("VIZOR_E2E_CASE_MANIFEST") else {
            assert!(
                std::env::var_os("VIZOR_E2E_NAMESPACE").is_none(),
                "an isolated namespace requires its case manifest"
            );
            return None;
        };
        let encoded = encoded.into_string().expect("ASCII case manifest");
        let namespace = std::env::var("VIZOR_E2E_NAMESPACE").expect("case namespace");
        let wallet_root = PathBuf::from(
            std::env::var_os("VIZOR_E2E_RUST_TEMP_ROOT").expect("owned Rust wallet temporary root"),
        );
        Some(
            Self::parse(&encoded, &namespace, wallet_root)
                .expect("valid isolated Rust case environment"),
        )
    }

    fn parse(encoded: &str, namespace: &str, wallet_root: PathBuf) -> Result<Self, String> {
        if encoded.len() > 2048 {
            return Err("case manifest exceeds its byte budget".into());
        }
        let manifest: Manifest = serde_json::from_str(encoded).map_err(|e| e.to_string())?;
        let ports = [
            manifest.lightwalletd_port,
            manifest.primary_proxy_port,
            manifest.zcashd_rpc_port,
        ];
        if manifest.schema_version != 1
            || !manifest.scenario_id.starts_with("rust.")
            || manifest.run_id.len() != 10
            || !manifest
                .run_id
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            || manifest.worker_id > 1_000_000
            || manifest.case_index > 1_000_000
            || manifest.namespace
                != format!(
                    "vizor_{}_w{}_{}",
                    manifest.run_id, manifest.worker_id, manifest.case_index
                )
            || manifest.namespace != namespace
            || ports.contains(&0)
            || ports[0] == ports[1]
            || ports[0] == ports[2]
            || ports[1] == ports[2]
            || manifest.regtest_ironwood_activation_height != 1
            || !manifest.context_path.is_absolute()
            || manifest.context_path.file_name().and_then(|s| s.to_str())
                != Some("native-context.json")
            || manifest
                .context_path
                .parent()
                .map(|p| p.join("wallet-temp"))
                != Some(wallet_root.clone())
            || !wallet_root.is_dir()
            || wallet_root.canonicalize().map_err(|e| e.to_string())? != wallet_root
        {
            return Err(
                "manifest/namespace/ports/profile/wallet root do not match this Rust case".into(),
            );
        }
        Ok(Self {
            manifest,
            wallet_root,
            next_source: 1,
        })
    }

    pub fn lightwalletd_url(&self) -> String {
        format!("http://127.0.0.1:{}", self.manifest.lightwalletd_port)
    }

    pub fn wallet_root(&self) -> &Path {
        &self.wallet_root
    }

    pub fn preflight(&self) {
        use rust_lib_zcash_wallet::api::{simple, wallet};
        simple::configure_regtest_ironwood_activation_height(1).expect("case consensus profile");
        let raw = self.request("GET", "/status", None);
        let observed = wallet::get_chain_upgrade_status(self.lightwalletd_url(), "regtest".into())
            .expect("owned lightwalletd preflight");
        assert_eq!(raw["zcashdHeight"].as_u64(), Some(observed.tip_height));
        assert_eq!(raw["lightwalletdHeight"], raw["zcashdHeight"]);
        assert_eq!(raw["ironwoodActivationHeight"].as_u64(), Some(1));
        assert_eq!(observed.nu6_3_activation_height, Some(1));
        assert!(observed.ironwood_active_at_tip);
    }

    pub fn mine(&self, blocks: u32) {
        self.request("POST", "/mine", Some(json!({"blocks": blocks})));
    }

    pub fn fund(&mut self, address: &str, amount: &str) -> String {
        let zatoshi = parse_zatoshi(amount).expect("exact positive funding amount");
        let source = self.next_source;
        self.next_source = source.checked_add(1).expect("funding source height");
        let result = self.request(
            "POST",
            "/fund-confirmed",
            Some(json!({
                "address": address, "amount_zatoshi": zatoshi, "source_height": source,
                "recipient_pool": "ironwood", "confirmations": 10,
            })),
        );
        assert_eq!(result["amount_zatoshi"].as_u64(), Some(zatoshi));
        assert_eq!(result["pool"].as_str(), Some("ironwood"));
        assert_eq!(result["source_height"].as_u64(), Some(u64::from(source)));
        assert_eq!(result["confirmations"].as_u64(), Some(10));
        result["txid_hex"]
            .as_str()
            .filter(|txid| txid.len() == 64 && txid.bytes().all(|b| b.is_ascii_hexdigit()))
            .expect("direct inclusion oracle transaction id")
            .to_string()
    }

    fn request(&self, method: &str, path: &str, payload: Option<Value>) -> Value {
        // The port is a validated integer from the original host manifest; no
        // proxy, redirect, filesystem receipt or node-wallet RPC is consulted.
        let address = SocketAddrV4::new(Ipv4Addr::LOCALHOST, self.manifest.zcashd_rpc_port);
        let mut stream = TcpStream::connect_timeout(&address.into(), Duration::from_secs(5))
            .expect("connect original case control");
        stream
            .set_read_timeout(Some(Duration::from_secs(120)))
            .unwrap();
        stream
            .set_write_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let body = payload
            .map(|v| serde_json::to_vec(&v).unwrap())
            .unwrap_or_default();
        write!(stream, "{method} {path} HTTP/1.0\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len()).unwrap();
        stream.write_all(&body).unwrap();
        let mut output = Vec::new();
        stream
            .take(2 * 1024 * 1024 + 8193)
            .read_to_end(&mut output)
            .expect("bounded control response");
        assert!(
            output.len() <= 2 * 1024 * 1024 + 8192,
            "control response exceeded its budget"
        );
        let boundary = output
            .windows(4)
            .position(|v| v == b"\r\n\r\n")
            .expect("HTTP response headers");
        assert!(boundary <= 8192, "control headers exceeded their budget");
        let headers = std::str::from_utf8(&output[..boundary]).expect("HTTP response headers");
        assert_eq!(
            headers
                .lines()
                .next()
                .and_then(|line| line.split_whitespace().nth(1)),
            Some("200"),
            "original case control operation failed: {headers}"
        );
        serde_json::from_slice(&output[boundary + 4..]).expect("control JSON response")
    }
}

fn parse_zatoshi(amount: &str) -> Result<u64, &'static str> {
    let mut parts = amount.split('.');
    let whole = parts.next().ok_or("missing whole amount")?;
    let fraction = parts.next().unwrap_or("");
    if whole.is_empty()
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || fraction.len() > 8
        || !fraction.bytes().all(|b| b.is_ascii_digit())
        || parts.next().is_some()
    {
        return Err("amount must be an unsigned decimal with at most eight fractional digits");
    }
    let fraction_digits = fraction.len() as u32;
    let whole: u64 = whole.parse().map_err(|_| "amount overflow")?;
    let fraction: u64 = if fraction.is_empty() {
        0
    } else {
        fraction.parse().map_err(|_| "amount overflow")?
    };
    let value = whole
        .checked_mul(100_000_000)
        .and_then(|v| {
            fraction
                .checked_mul(10u64.pow(8 - fraction_digits))
                .and_then(|f| v.checked_add(f))
        })
        .ok_or("amount overflow")?;
    if value == 0 || value > 2_100_000_000_000_000 {
        return Err("amount outside the monetary range");
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::{parse_zatoshi, IsolatedControl};
    use serde_json::{json, Value};

    fn manifest() -> (tempfile::TempDir, Value, std::path::PathBuf) {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().canonicalize().unwrap();
        let wallet = root.join("wallet-temp");
        std::fs::create_dir(&wallet).unwrap();
        let manifest = json!({
            "schema_version": 1, "scenario_id": "rust.receive.sync",
            "run_id": "a1b2c3d4e5", "worker_id": 2, "case_index": 1,
            "namespace": "vizor_a1b2c3d4e5_w2_1", "context_path": root.join("native-context.json"),
            "lightwalletd_port": 29067, "primary_proxy_port": 29068, "zcashd_rpc_port": 28232,
            "regtest_ironwood_activation_height": 1,
        });
        (directory, manifest, wallet)
    }

    #[test]
    fn validated_manifest_routes_only_to_its_owned_endpoint_and_wallet_root() {
        let (_directory, manifest, wallet) = manifest();
        let control = IsolatedControl::parse(
            &manifest.to_string(),
            "vizor_a1b2c3d4e5_w2_1",
            wallet.clone(),
        )
        .unwrap();
        assert_eq!(control.lightwalletd_url(), "http://127.0.0.1:29067");
        assert_eq!(control.wallet_root(), wallet);
    }

    #[test]
    fn malformed_or_mismatched_manifest_never_selects_the_legacy_stack() {
        let (_directory, original, wallet) = manifest();
        for (field, value) in [
            ("schema_version", json!(2)),
            ("scenario_id", json!("flutter.macos.import-sync")),
            ("run_id", json!("not-a-run")),
            ("namespace", json!("other")),
            ("worker_id", json!(1_000_001)),
            ("case_index", json!(-1)),
            ("lightwalletd_port", json!(0)),
            ("zcashd_rpc_port", json!(29067)),
            ("regtest_ironwood_activation_height", json!(500)),
            ("unknown", json!(true)),
        ] {
            let mut manifest = original.clone();
            manifest[field] = value;
            assert!(
                IsolatedControl::parse(
                    &manifest.to_string(),
                    "vizor_a1b2c3d4e5_w2_1",
                    wallet.clone()
                )
                .is_err(),
                "{field}"
            );
        }
        assert!(IsolatedControl::parse(&original.to_string(), "other", wallet.clone()).is_err());
        assert!(IsolatedControl::parse(
            &original.to_string(),
            "vizor_a1b2c3d4e5_w2_1",
            wallet.parent().unwrap().to_path_buf()
        )
        .is_err());
    }

    #[test]
    fn funding_amounts_are_exact_integer_zatoshis() {
        for (amount, expected) in [
            ("1.0", 100_000_000),
            ("1.25", 125_000_000),
            ("0.00000001", 1),
            ("1.60000000", 160_000_000),
        ] {
            assert_eq!(parse_zatoshi(amount), Ok(expected));
        }
    }

    #[test]
    fn imprecise_signed_nonfinite_and_overflow_amounts_are_rejected() {
        for amount in [
            "0",
            "-1",
            "+1",
            "1e2",
            "NaN",
            "0.000000001",
            ".5",
            "1.2.3",
            "999999999999999999999999",
            "21000000.00000001",
        ] {
            assert!(parse_zatoshi(amount).is_err(), "{amount}");
        }
    }
}
