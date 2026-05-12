use zcash_voting::Transport;

use crate::wallet::network::WalletNetwork;

static RUSTLS_PROVIDER: std::sync::OnceLock<()> = std::sync::OnceLock::new();

/// Install the Rustls crypto provider for direct Hyper/Rustls validation probes.
fn ensure_rustls_provider() {
    RUSTLS_PROVIDER.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

/// Validate the base URL used for vote commitment tree sync.
///
/// The upstream tree client appends the authenticated `round_id` to the path, so
/// this check keeps the Rust boundary limited to a well-formed base endpoint.
pub fn validate_tree_base_endpoint(base_url: &str, round_id: &str) -> Result<String, String> {
    validate_round_id(round_id)?;
    let endpoint = ParsedEndpoint::parse("vote-tree", base_url)?;
    Ok(endpoint.normalized_base_url)
}

/// Validate a PIR endpoint before any private proof queries are sent.
///
/// This fails closed unless `/root.height` exactly matches the round snapshot
/// and the endpoint identifies the expected voting network and round.
pub async fn validate_pir_endpoint(
    pir_server_url: &str,
    network: WalletNetwork,
    round_params: &zcash_voting::VotingRoundParams,
) -> Result<String, String> {
    validate_round_id(&round_params.vote_round_id)?;
    let endpoint = ParsedEndpoint::parse("PIR", pir_server_url)?;
    let root_url = endpoint.child_url("root");
    let expected_network_id = u64::from(network.voting_id());
    let expected_height = round_params.snapshot_height;
    let expected_round_id = round_params.vote_round_id.to_ascii_lowercase();

    ensure_rustls_provider();
    let transport = zcash_voting::HyperTransport::new();
    let response = transport
        .get(&root_url)
        .await
        .map_err(|e| format!("PIR endpoint validation failed: GET /root failed: {e}"))?;
    if response.status != 200 {
        return Err(format!(
            "PIR endpoint validation failed: GET /root returned HTTP {}",
            response.status
        ));
    }

    let root: serde_json::Value = serde_json::from_slice(&response.body)
        .map_err(|e| format!("PIR endpoint validation failed: malformed /root JSON: {e}"))?;
    let reported_height = json_u64(
        &root,
        &[
            "height",
            "root_height",
            "rootHeight",
            "snapshot_height",
            "snapshotHeight",
        ],
    )
    .ok_or_else(|| "PIR endpoint validation failed: /root did not include height".to_string())?;
    if reported_height != expected_height {
        return Err(format!(
            "PIR endpoint validation failed: /root height {reported_height} does not match round snapshot_height {expected_height}"
        ));
    }

    validate_pir_network_identity(&root, &endpoint, expected_network_id, network)?;
    validate_pir_round_identity(&root, &endpoint, &expected_round_id)?;

    Ok(endpoint.normalized_base_url)
}

/// Check that `/root` metadata or the endpoint path scopes this PIR server to
/// the expected Zcash voting network.
fn validate_pir_network_identity(
    root: &serde_json::Value,
    endpoint: &ParsedEndpoint,
    expected_network_id: u64,
    network: WalletNetwork,
) -> Result<(), String> {
    if let Some(reported) = json_u64(
        root,
        &[
            "network_id",
            "networkId",
            "voting_network_id",
            "votingNetworkId",
        ],
    ) {
        if reported == expected_network_id {
            return Ok(());
        }
        return Err(format!(
            "PIR endpoint validation failed: /root network_id {reported} does not match expected {expected_network_id}"
        ));
    }

    if let Some(reported) = json_string(root, &["network", "network_name", "networkName"]) {
        if network_name_matches(&reported, network) {
            return Ok(());
        }
        return Err(format!(
            "PIR endpoint validation failed: /root network {reported:?} does not match expected {:?}",
            network
        ));
    }

    if endpoint_has_network_identity(endpoint, expected_network_id, network) {
        return Ok(());
    }

    Err("PIR endpoint validation failed: endpoint did not identify the voting network".to_string())
}

/// Check that `/root` metadata or the endpoint path scopes this PIR server to
/// the exact voting round being proven.
fn validate_pir_round_identity(
    root: &serde_json::Value,
    endpoint: &ParsedEndpoint,
    expected_round_id: &str,
) -> Result<(), String> {
    if let Some(reported) = json_string(
        root,
        &["round_id", "roundId", "vote_round_id", "voteRoundId"],
    ) {
        if reported.eq_ignore_ascii_case(expected_round_id) {
            return Ok(());
        }
        return Err(format!(
            "PIR endpoint validation failed: /root round_id {reported:?} does not match expected {expected_round_id}"
        ));
    }

    if endpoint
        .path_segments
        .iter()
        .any(|segment| segment.eq_ignore_ascii_case(expected_round_id))
    {
        return Ok(());
    }

    Err("PIR endpoint validation failed: endpoint did not identify the voting round".to_string())
}

#[derive(Clone, Debug)]
struct ParsedEndpoint {
    normalized_base_url: String,
    path_segments: Vec<String>,
}

impl ParsedEndpoint {
    /// Parse and normalize endpoints without accepting URL features that could
    /// change the upstream request target after validation.
    fn parse(kind: &str, value: &str) -> Result<Self, String> {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            return Err(format!("{kind} endpoint validation failed: URL is empty"));
        }
        let (scheme, rest) = trimmed
            .split_once("://")
            .ok_or_else(|| format!("{kind} endpoint validation failed: URL has no scheme"))?;
        if scheme != "https" && scheme != "http" {
            return Err(format!(
                "{kind} endpoint validation failed: unsupported URL scheme {scheme:?}"
            ));
        }
        if rest.contains('#') || rest.contains('?') {
            return Err(format!(
                "{kind} endpoint validation failed: URL must not include query or fragment"
            ));
        }

        let authority_end = rest.find('/').unwrap_or(rest.len());
        let authority = &rest[..authority_end];
        if authority.is_empty() {
            return Err(format!(
                "{kind} endpoint validation failed: URL has no host"
            ));
        }
        if authority.contains('@') {
            return Err(format!(
                "{kind} endpoint validation failed: URL must not include user info"
            ));
        }

        let path = &rest[authority_end..];
        let path_segments = path
            .split('/')
            .filter(|segment| !segment.is_empty())
            .map(|segment| segment.to_string())
            .collect();
        let normalized_base_url = trimmed.trim_end_matches('/').to_string();
        Ok(Self {
            normalized_base_url,
            path_segments,
        })
    }

    fn child_url(&self, child: &str) -> String {
        format!("{}/{}", self.normalized_base_url, child)
    }
}

/// Round IDs are path material for tree/PIR endpoints, so validate them before
/// constructing any upstream request.
fn validate_round_id(round_id: &str) -> Result<(), String> {
    if round_id.len() == 64 && round_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(format!(
            "voting endpoint validation failed: round_id {round_id:?} must be 64 hex characters"
        ))
    }
}

fn json_u64(value: &serde_json::Value, keys: &[&str]) -> Option<u64> {
    keys.iter().find_map(|key| match value.get(*key)? {
        serde_json::Value::Number(number) => number.as_u64(),
        serde_json::Value::String(string) => string.parse::<u64>().ok(),
        _ => None,
    })
}

fn json_string(value: &serde_json::Value, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| match value.get(*key)? {
        serde_json::Value::String(string) => Some(string.clone()),
        serde_json::Value::Number(number) => Some(number.to_string()),
        _ => None,
    })
}

/// Accept endpoint paths that explicitly include network identity, for servers
/// whose `/root` response only carries snapshot/root data.
fn endpoint_has_network_identity(
    endpoint: &ParsedEndpoint,
    expected_network_id: u64,
    network: WalletNetwork,
) -> bool {
    let expected_id = expected_network_id.to_string();
    let expected_names = match network {
        WalletNetwork::Main => &["main", "mainnet"][..],
        WalletNetwork::Test => &["test", "testnet"][..],
        WalletNetwork::Regtest => &["regtest"][..],
    };

    endpoint.path_segments.windows(2).any(|pair| {
        let key = pair[0].to_ascii_lowercase();
        let value = pair[1].to_ascii_lowercase();
        matches!(
            key.as_str(),
            "network" | "net" | "network_id" | "network-id"
        ) && (value == expected_id || expected_names.contains(&value.as_str()))
    }) || endpoint.path_segments.iter().any(|segment| {
        let lower = segment.to_ascii_lowercase();
        lower == format!("network-{expected_id}")
            || lower == format!("net-{expected_id}")
            || expected_names.contains(&lower.as_str())
    })
}

/// Match both numeric voting IDs and conventional network names in metadata.
fn network_name_matches(reported: &str, network: WalletNetwork) -> bool {
    let reported = reported.to_ascii_lowercase();
    match network {
        WalletNetwork::Main => matches!(reported.as_str(), "1" | "main" | "mainnet"),
        WalletNetwork::Test => matches!(reported.as_str(), "0" | "test" | "testnet"),
        WalletNetwork::Regtest => matches!(reported.as_str(), "0" | "regtest"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn tree_endpoint_validation_rejects_unsafe_urls() {
        assert!(validate_tree_base_endpoint("https://node.example", ROUND_ID).is_ok());
        assert!(validate_tree_base_endpoint("ftp://node.example", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("https://user@node.example", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("https://node.example?x=1", ROUND_ID).is_err());
    }

    #[tokio::test]
    async fn pir_endpoint_validation_accepts_matching_root_metadata() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 100,
                "network_id": 0,
                "round_id": ROUND_ID,
                "root29": "unused-by-validation",
            })
            .to_string(),
        );

        let result =
            validate_pir_endpoint(&server_url, WalletNetwork::Test, &test_round_params()).await;

        assert_eq!(result.unwrap(), server_url);
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_accepts_scoped_path_identity() {
        let (server_url, request_path) =
            start_root_server(200, serde_json::json!({ "height": 100 }).to_string());
        let scoped_url = format!("{server_url}/network/0/round/{ROUND_ID}/");

        let result =
            validate_pir_endpoint(&scoped_url, WalletNetwork::Test, &test_round_params()).await;

        assert_eq!(
            result.unwrap(),
            format!("{server_url}/network/0/round/{ROUND_ID}")
        );
        assert_eq!(
            request_path.join().unwrap(),
            format!("/network/0/round/{ROUND_ID}/root")
        );
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_snapshot_height_mismatch() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 99,
                "network_id": 0,
                "round_id": ROUND_ID,
            })
            .to_string(),
        );

        let err = validate_pir_endpoint(&server_url, WalletNetwork::Test, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("height 99"));
        assert!(err.contains("snapshot_height 100"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_missing_identity() {
        let (server_url, request_path) =
            start_root_server(200, serde_json::json!({ "height": 100 }).to_string());

        let err = validate_pir_endpoint(&server_url, WalletNetwork::Test, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("did not identify the voting network"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[test]
    fn pir_identity_accepts_root_metadata() {
        let endpoint = ParsedEndpoint::parse("PIR", "https://pir.example").unwrap();
        let root = serde_json::json!({
            "height": 100,
            "network_id": 0,
            "round_id": ROUND_ID,
        });

        assert!(validate_pir_network_identity(&root, &endpoint, 0, WalletNetwork::Test).is_ok());
        assert!(validate_pir_round_identity(&root, &endpoint, ROUND_ID).is_ok());
    }

    #[test]
    fn pir_identity_accepts_scoped_endpoint_path() {
        let endpoint = ParsedEndpoint::parse(
            "PIR",
            &format!("https://pir.example/network/0/round/{ROUND_ID}"),
        )
        .unwrap();
        let root = serde_json::json!({ "height": 100 });

        assert!(validate_pir_network_identity(&root, &endpoint, 0, WalletNetwork::Test).is_ok());
        assert!(validate_pir_round_identity(&root, &endpoint, ROUND_ID).is_ok());
    }

    #[test]
    fn pir_identity_fails_closed_when_missing() {
        let endpoint = ParsedEndpoint::parse("PIR", "https://pir.example/snapshot").unwrap();
        let root = serde_json::json!({ "height": 100 });

        assert!(validate_pir_network_identity(&root, &endpoint, 0, WalletNetwork::Test).is_err());
        assert!(validate_pir_round_identity(&root, &endpoint, ROUND_ID).is_err());
    }

    fn start_root_server(status: u16, body: String) -> (String, thread::JoinHandle<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let request_path = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0u8; 2048];
            let len = stream.read(&mut request).unwrap();
            let request = String::from_utf8_lossy(&request[..len]);
            let path = request
                .lines()
                .next()
                .and_then(|line| line.split_whitespace().nth(1))
                .unwrap_or("/")
                .to_string();
            let response = format!(
                "HTTP/1.1 {status} OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            stream.write_all(response.as_bytes()).unwrap();
            path
        });
        (url, request_path)
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }
}
