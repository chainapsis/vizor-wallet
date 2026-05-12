use zcash_voting::Transport;

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
/// This fails closed unless `/root.height` exactly matches the round snapshot.
/// The voting round configuration authenticates the expected snapshot height;
/// optional `/root` identity fields such as `network_id` or `round_id` are
/// diagnostics only and are intentionally not part of the protocol check.
pub async fn validate_pir_endpoint(
    pir_server_url: &str,
    round_params: &zcash_voting::VotingRoundParams,
) -> Result<String, String> {
    let endpoint = ParsedEndpoint::parse("PIR", pir_server_url)?;
    let root_url = endpoint.child_url("root");
    let expected_height = round_params.snapshot_height;

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
    let reported_height = root_height_from_agreeing_aliases(
        &root,
        &[
            "height",
            "root_height",
            "rootHeight",
            "snapshot_height",
            "snapshotHeight",
        ],
    )
    .map_err(|e| format!("PIR endpoint validation failed: {e}"))?
    .ok_or_else(|| "PIR endpoint validation failed: /root did not include height".to_string())?;
    if reported_height < expected_height {
        return Err(format!(
            "PIR endpoint validation failed: /root height {reported_height} is behind round snapshot_height {expected_height}"
        ));
    }
    if reported_height > expected_height {
        return Err(format!(
            "PIR endpoint validation failed: /root height {reported_height} is ahead of round snapshot_height {expected_height}"
        ));
    }

    Ok(endpoint.normalized_base_url)
}

#[derive(Clone, Debug)]
struct ParsedEndpoint {
    normalized_base_url: String,
    url: url::Url,
}

impl ParsedEndpoint {
    /// Parse and normalize endpoints without accepting URL features that could
    /// change the upstream request target after validation.
    fn parse(kind: &str, value: &str) -> Result<Self, String> {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            return Err(format!("{kind} endpoint validation failed: URL is empty"));
        }
        let mut url = url::Url::parse(trimmed)
            .map_err(|e| format!("{kind} endpoint validation failed: malformed URL: {e}"))?;
        if url.cannot_be_a_base() {
            return Err(format!(
                "{kind} endpoint validation failed: URL must be a base URL"
            ));
        }
        if url.scheme() != "https" && url.scheme() != "http" {
            return Err(format!(
                "{kind} endpoint validation failed: unsupported URL scheme {:?}",
                url.scheme()
            ));
        }
        if url.query().is_some() || url.fragment().is_some() {
            return Err(format!(
                "{kind} endpoint validation failed: URL must not include query or fragment"
            ));
        }
        if url.host_str().is_none() {
            return Err(format!(
                "{kind} endpoint validation failed: URL has no host"
            ));
        }
        if !url.username().is_empty() || url.password().is_some() {
            return Err(format!(
                "{kind} endpoint validation failed: URL must not include user info"
            ));
        }
        {
            let mut segments = url
                .path_segments_mut()
                .map_err(|_| format!("{kind} endpoint validation failed: URL path is invalid"))?;
            segments.pop_if_empty();
        }
        let normalized_base_url = normalized_base_url(&url);
        Ok(Self {
            normalized_base_url,
            url,
        })
    }

    fn child_url(&self, child: &str) -> String {
        let mut url = self.url.clone();
        {
            let mut segments = url
                .path_segments_mut()
                .expect("validated HTTP(S) endpoint URLs can be path bases");
            segments.pop_if_empty();
            segments.push(child);
        }
        url.to_string()
    }
}

fn normalized_base_url(url: &url::Url) -> String {
    let value = url.to_string();
    value.trim_end_matches('/').to_string()
}

/// Round IDs are path material for tree endpoints, so validate them before
/// constructing any upstream tree request.
fn validate_round_id(round_id: &str) -> Result<(), String> {
    if round_id.len() == 64 && round_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(format!(
            "voting endpoint validation failed: round_id {round_id:?} must be 64 hex characters"
        ))
    }
}

/// Parse PIR `/root` height aliases, failing closed if any present alias is
/// malformed or disagrees with another present alias.
fn root_height_from_agreeing_aliases(
    value: &serde_json::Value,
    keys: &[&str],
) -> Result<Option<u64>, String> {
    let mut first: Option<(&str, u64)> = None;
    for key in keys {
        let Some(raw) = value.get(*key) else {
            continue;
        };
        let height = match raw {
            serde_json::Value::Number(number) => number
                .as_u64()
                .ok_or_else(|| format!("/root field {key:?} is not a valid u64 height"))?,
            serde_json::Value::String(string) => string
                .parse::<u64>()
                .map_err(|_| format!("/root field {key:?} is not a valid u64 height"))?,
            _ => {
                return Err(format!("/root field {key:?} is not a valid u64 height"));
            }
        };
        if let Some((first_key, first_height)) = first {
            // Conflicting aliases make the endpoint ambiguous; do not let key
            // order decide which unauthenticated `/root` height to trust.
            if height != first_height {
                return Err(format!(
                    "/root height fields disagree: {first_key:?}={first_height}, {key:?}={height}"
                ));
            }
        } else {
            first = Some((key, height));
        }
    }
    Ok(first.map(|(_, height)| height))
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
        assert!(validate_tree_base_endpoint("", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("ftp://node.example", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("http://node.example", ROUND_ID).is_ok());
        assert!(validate_tree_base_endpoint("https://user@node.example", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("https://node.example?x=1", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("https://node.example/#frag", ROUND_ID).is_err());
    }

    #[test]
    fn tree_endpoint_validation_rejects_invalid_round_id() {
        assert!(validate_tree_base_endpoint("https://node.example", "not-a-round-id").is_err());
    }

    #[test]
    fn tree_endpoint_validation_normalizes_base_urls() {
        assert_eq!(
            validate_tree_base_endpoint(" HTTPS://NODE.EXAMPLE/base/ ", ROUND_ID).unwrap(),
            "https://node.example/base"
        );
        assert_eq!(
            validate_tree_base_endpoint("https://node.example/", ROUND_ID).unwrap(),
            "https://node.example"
        );
        assert_eq!(
            validate_tree_base_endpoint("https://node.example/a/../b/", ROUND_ID).unwrap(),
            "https://node.example/b"
        );
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

        let result = validate_pir_endpoint(&server_url, &test_round_params()).await;

        assert_eq!(result.unwrap(), server_url);
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_unsupported_scheme() {
        let err = validate_pir_endpoint("ftp://pir.example", &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("unsupported URL scheme"));
    }

    #[tokio::test]
    async fn pir_endpoint_validation_appends_root_to_normalized_base_path() {
        let (server_url, request_path) =
            start_root_server(200, serde_json::json!({ "height": 100 }).to_string());
        let endpoint = format!("{server_url}/pir/");

        let result = validate_pir_endpoint(&endpoint, &test_round_params()).await;

        assert_eq!(result.unwrap(), format!("{server_url}/pir"));
        assert_eq!(request_path.join().unwrap(), "/pir/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_accepts_height_only_root_metadata() {
        let (server_url, request_path) =
            start_root_server(200, serde_json::json!({ "height": 100 }).to_string());

        let result = validate_pir_endpoint(&server_url, &test_round_params()).await;

        assert_eq!(result.unwrap(), server_url);
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_accepts_matching_height_aliases() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 100,
                "root_height": "100",
                "rootHeight": 100,
                "snapshot_height": "100",
                "snapshotHeight": 100,
            })
            .to_string(),
        );

        let result = validate_pir_endpoint(&server_url, &test_round_params()).await;

        assert_eq!(result.unwrap(), server_url);
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_conflicting_height_aliases() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 100,
                "snapshot_height": 101,
            })
            .to_string(),
        );

        let err = validate_pir_endpoint(&server_url, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("height fields disagree"));
        assert!(err.contains("\"height\"=100"));
        assert!(err.contains("\"snapshot_height\"=101"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_malformed_height_alias() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 100,
                "snapshot_height": "not-a-height",
            })
            .to_string(),
        );

        let err = validate_pir_endpoint(&server_url, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("field \"snapshot_height\" is not a valid u64 height"));
        assert_eq!(request_path.join().unwrap(), "/root");
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

        let err = validate_pir_endpoint(&server_url, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("height 99"));
        assert!(err.contains("behind"));
        assert!(err.contains("snapshot_height 100"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_ahead_snapshot_height() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 101,
                "network_id": 0,
                "round_id": ROUND_ID,
            })
            .to_string(),
        );

        let err = validate_pir_endpoint(&server_url, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("height 101"));
        assert!(err.contains("ahead"));
        assert!(err.contains("snapshot_height 100"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_non_success_status() {
        let (server_url, request_path) =
            start_root_server(503, serde_json::json!({ "height": 100 }).to_string());

        let err = validate_pir_endpoint(&server_url, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("HTTP 503"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_malformed_root_json() {
        let (server_url, request_path) = start_root_server(200, "{".to_string());

        let err = validate_pir_endpoint(&server_url, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("malformed /root JSON"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_missing_root_height() {
        let (server_url, request_path) =
            start_root_server(200, serde_json::json!({ "root29": "unused" }).to_string());

        let err = validate_pir_endpoint(&server_url, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("did not include height"));
        assert_eq!(request_path.join().unwrap(), "/root");
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
