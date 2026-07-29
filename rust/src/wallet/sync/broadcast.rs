use std::time::Duration;

use reqwest::redirect::Policy;
use serde::Deserialize;
use serde_json::json;
use url::{Host, Url};
use zcash_client_backend::proto::service::SendResponse;

const TRANSACTION_RELAY_TIMEOUT: Duration = Duration::from_secs(15);
const TRANSACTION_RELAY_MAX_RESPONSE_BYTES: usize = 64 * 1024;

pub(super) struct TransactionRelayClient {
    client: reqwest::Client,
    endpoint: Url,
}

impl TransactionRelayClient {
    pub(super) fn new(endpoint: &str) -> Result<Self, String> {
        Self::new_with_timeout(endpoint, TRANSACTION_RELAY_TIMEOUT)
    }

    fn new_with_timeout(endpoint: &str, timeout: Duration) -> Result<Self, String> {
        let endpoint = validate_transaction_relay_url(endpoint)?;
        // Native background preparation can reach this path before FRB init.
        let _ = rustls::crypto::ring::default_provider().install_default();
        let client = reqwest::Client::builder()
            .redirect(Policy::none())
            .timeout(timeout)
            .build()
            .map_err(|e| format!("Build transaction relay client: {e}"))?;
        Ok(Self { client, endpoint })
    }

    /// Submits only the locally created denomination transaction. Confirmation
    /// and all later migration transactions remain on their existing paths.
    pub(super) async fn send_raw_transaction(
        &self,
        raw_tx: &[u8],
        expected_txid_hex: &str,
    ) -> Result<(), String> {
        validate_txid_hex(expected_txid_hex, "Expected transaction ID")?;
        let mut response = self
            .client
            .post(self.endpoint.clone())
            .json(&json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendrawtransaction",
                "params": [hex::encode(raw_tx)],
            }))
            .send()
            .await
            .map_err(|e| format!("Transaction relay request failed: {e}"))?;

        if !response.status().is_success() {
            return Err(format!(
                "Transaction relay returned HTTP {}",
                response.status().as_u16()
            ));
        }

        if response
            .content_length()
            .is_some_and(|length| length > TRANSACTION_RELAY_MAX_RESPONSE_BYTES as u64)
        {
            return Err("Transaction relay response exceeded 64 KiB".to_string());
        }
        let mut body = Vec::new();
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|e| format!("Read transaction relay response: {e}"))?
        {
            if body.len().saturating_add(chunk.len()) > TRANSACTION_RELAY_MAX_RESPONSE_BYTES {
                return Err("Transaction relay response exceeded 64 KiB".to_string());
            }
            body.extend_from_slice(&chunk);
        }
        let response: JsonRpcResponse = serde_json::from_slice(&body)
            .map_err(|e| format!("Transaction relay returned malformed JSON: {e}"))?;
        response.accept(expected_txid_hex)
    }
}

#[derive(Deserialize)]
struct JsonRpcResponse {
    jsonrpc: Option<String>,
    id: Option<serde_json::Value>,
    result: Option<serde_json::Value>,
    error: Option<JsonRpcError>,
}

#[derive(Deserialize)]
struct JsonRpcError {
    code: i64,
    message: String,
}

impl JsonRpcResponse {
    fn accept(self, expected_txid_hex: &str) -> Result<(), String> {
        if self.jsonrpc.as_deref() != Some("2.0") || self.id != Some(json!(1)) {
            return Err("Transaction relay returned an invalid JSON-RPC envelope".to_string());
        }

        match (self.result, self.error) {
            (Some(result), None) => {
                let returned_txid = result.as_str().ok_or_else(|| {
                    "Transaction relay returned a non-string transaction ID".to_string()
                })?;
                validate_txid_hex(returned_txid, "Returned transaction ID")?;
                if !returned_txid.eq_ignore_ascii_case(expected_txid_hex) {
                    return Err(format!(
                        "Transaction relay returned transaction ID {returned_txid}, expected {expected_txid_hex}"
                    ));
                }
                Ok(())
            }
            (None, Some(error)) if send_rejection_is_already_accepted(&error.message) => Ok(()),
            (None, Some(error)) => Err(format!(
                "Transaction relay rejected broadcast: {} (code {})",
                error.message, error.code
            )),
            _ => Err("Transaction relay returned an ambiguous JSON-RPC response".to_string()),
        }
    }
}

pub(super) fn validate_transaction_relay_url(endpoint: &str) -> Result<Url, String> {
    let url = Url::parse(endpoint).map_err(|e| format!("Invalid transaction relay URL: {e}"))?;
    if !url.username().is_empty() || url.password().is_some() {
        return Err("Transaction relay URL must not contain credentials".to_string());
    }

    match url.scheme() {
        "https" => {}
        "http" if relay_host_is_loopback(&url) => {}
        "http" => {
            return Err(
                "Transaction relay URL must use HTTPS unless it targets loopback".to_string(),
            )
        }
        _ => return Err("Transaction relay URL must use HTTPS".to_string()),
    }
    Ok(url)
}

fn relay_host_is_loopback(url: &Url) -> bool {
    match url.host() {
        Some(Host::Domain(host)) => host.eq_ignore_ascii_case("localhost"),
        Some(Host::Ipv4(address)) => address.is_loopback(),
        Some(Host::Ipv6(address)) => address.is_loopback(),
        None => false,
    }
}

fn validate_txid_hex(txid: &str, label: &str) -> Result<(), String> {
    if txid.len() != 64 || !txid.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(format!("{label} must be 32-byte hexadecimal"));
    }
    Ok(())
}

pub(super) fn send_response_rejection_error(resp: &SendResponse) -> Option<String> {
    if resp.error_code == 0 || send_rejection_is_already_accepted(&resp.error_message) {
        return None;
    }

    Some(format!(
        "Broadcast rejected: {} (code {})",
        resp.error_message, resp.error_code
    ))
}

pub(super) fn send_rejection_is_already_accepted(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("transaction was committed to the best chain")
        || message.contains("already in mempool")
        || message.contains("already have transaction")
        || message.contains("transaction already in block chain")
        || message.contains("transaction is already in state")
        || message.contains("transaction already exists")
        || message.contains("txn-already-known")
        || message.contains("txn-already-in-mempool")
        || message.contains("already known")
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::{
        io::{Read, Write},
        net::TcpListener,
        sync::mpsc,
        thread,
    };

    const TXID: &str = "838813428b78712263511ed5c6fb9a108c939038a440b74f72bee6caedf602fd";

    struct MockResponse {
        status: u16,
        headers: Vec<(&'static str, String)>,
        body: String,
        delay: Duration,
    }

    fn spawn_mock_server(response: MockResponse) -> (String, mpsc::Receiver<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind mock relay");
        let address = listener.local_addr().expect("mock relay address");
        let (request_tx, request_rx) = mpsc::channel();
        thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept mock relay request");
            stream
                .set_read_timeout(Some(Duration::from_secs(2)))
                .expect("set read timeout");
            let mut request = Vec::new();
            let mut buffer = [0u8; 4096];
            let mut expected_len = None;
            loop {
                let read = stream.read(&mut buffer).expect("read mock relay request");
                if read == 0 {
                    break;
                }
                request.extend_from_slice(&buffer[..read]);
                if expected_len.is_none() {
                    if let Some(header_end) =
                        request.windows(4).position(|window| window == b"\r\n\r\n")
                    {
                        let headers = String::from_utf8_lossy(&request[..header_end]);
                        let content_length = headers
                            .lines()
                            .find_map(|line| {
                                line.split_once(':').and_then(|(name, value)| {
                                    name.eq_ignore_ascii_case("content-length").then(|| {
                                        value.trim().parse::<usize>().expect("content length")
                                    })
                                })
                            })
                            .unwrap_or(0);
                        expected_len = Some(header_end + 4 + content_length);
                    }
                }
                if expected_len.is_some_and(|length| request.len() >= length) {
                    break;
                }
            }
            let _ = request_tx.send(String::from_utf8(request).expect("UTF-8 mock request"));
            if !response.delay.is_zero() {
                thread::sleep(response.delay);
            }
            let reason = match response.status {
                200 => "OK",
                302 => "Found",
                500 => "Internal Server Error",
                _ => "Test",
            };
            let mut headers = format!(
                "HTTP/1.1 {} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n",
                response.status,
                reason,
                response.body.len()
            );
            for (name, value) in response.headers {
                headers.push_str(&format!("{name}: {value}\r\n"));
            }
            let _ = stream.write_all(format!("{headers}\r\n{}", response.body).as_bytes());
        });
        (format!("http://{address}"), request_rx)
    }

    fn rpc_response(body: impl Into<String>) -> MockResponse {
        MockResponse {
            status: 200,
            headers: Vec::new(),
            body: body.into(),
            delay: Duration::ZERO,
        }
    }

    fn send_response(error_code: i32, error_message: &str) -> SendResponse {
        SendResponse {
            error_code,
            error_message: error_message.to_string(),
        }
    }

    #[test]
    fn send_response_success_is_accepted_even_when_message_contains_txid() {
        let resp = send_response(
            0,
            "838813428b78712263511ed5c6fb9a108c939038a440b74f72bee6caedf602fd",
        );

        assert_eq!(send_response_rejection_error(&resp), None);
    }

    #[test]
    fn duplicate_send_responses_are_accepted() {
        for message in [
            "transaction was committed to the best chain",
            "already in mempool",
            "already have transaction",
            "transaction already in block chain",
            "failed to validate tx: WtxId(\"private\"), error: transaction is already in state",
            "transaction already exists",
            "txn-already-known",
            "txn-already-in-mempool",
            "already known",
            "Error: TXN-ALREADY-IN-MEMPOOL from node",
        ] {
            let resp = send_response(-25, message);

            assert_eq!(send_response_rejection_error(&resp), None, "{message}");
        }
    }

    #[test]
    fn unrelated_send_rejections_remain_fatal() {
        for message in [
            "bad-txns-inputs-spent",
            "",
            "mandatory-script-verify-flag-failed",
        ] {
            let resp = send_response(18, message);

            assert_eq!(
                send_response_rejection_error(&resp),
                Some(format!("Broadcast rejected: {message} (code 18)")),
                "{message}"
            );
        }
    }

    #[tokio::test]
    async fn relay_submits_exact_raw_transaction_and_checks_txid() {
        let (url, request) = spawn_mock_server(rpc_response(format!(
            r#"{{"jsonrpc":"2.0","id":1,"result":"{TXID}"}}"#
        )));
        let client = TransactionRelayClient::new(&url).expect("valid loopback relay");

        client
            .send_raw_transaction(&[0xde, 0xad, 0xbe, 0xef], TXID)
            .await
            .expect("relay accepts transaction");

        let request = request.recv().expect("captured relay request");
        let body = request.split("\r\n\r\n").nth(1).expect("request body");
        let body: serde_json::Value = serde_json::from_str(body).expect("JSON request body");
        assert_eq!(
            body,
            json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sendrawtransaction",
                "params": ["deadbeef"],
            })
        );
    }

    #[tokio::test]
    async fn relay_accepts_duplicate_rejection() {
        let (url, _) = spawn_mock_server(rpc_response(
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-27,"message":"transaction is already in state"}}"#,
        ));
        TransactionRelayClient::new(&url)
            .expect("valid relay")
            .send_raw_transaction(&[1], TXID)
            .await
            .expect("duplicate is accepted-equivalent");
    }

    #[tokio::test]
    async fn relay_rejects_mismatched_txid_and_ambiguous_envelopes() {
        let other_txid = "118813428b78712263511ed5c6fb9a108c939038a440b74f72bee6caedf602fd";
        let (url, _) = spawn_mock_server(rpc_response(format!(
            r#"{{"jsonrpc":"2.0","id":1,"result":"{other_txid}"}}"#
        )));
        let error = TransactionRelayClient::new(&url)
            .expect("valid relay")
            .send_raw_transaction(&[1], TXID)
            .await
            .expect_err("mismatched txid is rejected");
        assert!(error.contains("expected"), "{error}");

        let (url, _) = spawn_mock_server(rpc_response(format!(
            r#"{{"jsonrpc":"2.0","id":1,"result":"{TXID}","error":{{"code":-1,"message":"ambiguous"}}}}"#
        )));
        let error = TransactionRelayClient::new(&url)
            .expect("valid relay")
            .send_raw_transaction(&[1], TXID)
            .await
            .expect_err("ambiguous response is rejected");
        assert!(error.contains("ambiguous"), "{error}");
    }

    #[tokio::test]
    async fn relay_rejects_redirects_and_times_out() {
        let (redirect_target, redirected_request) = spawn_mock_server(rpc_response(format!(
            r#"{{"jsonrpc":"2.0","id":1,"result":"{TXID}"}}"#
        )));
        let (url, _) = spawn_mock_server(MockResponse {
            status: 302,
            headers: vec![("Location", redirect_target)],
            body: String::new(),
            delay: Duration::ZERO,
        });
        let error = TransactionRelayClient::new(&url)
            .expect("valid relay")
            .send_raw_transaction(&[1], TXID)
            .await
            .expect_err("redirect is rejected");
        assert!(error.contains("HTTP 302"), "{error}");
        assert!(redirected_request.try_recv().is_err());

        let (url, _) = spawn_mock_server(MockResponse {
            status: 200,
            headers: Vec::new(),
            body: format!(r#"{{"jsonrpc":"2.0","id":1,"result":"{TXID}"}}"#),
            delay: Duration::from_millis(200),
        });
        let error = TransactionRelayClient::new_with_timeout(&url, Duration::from_millis(25))
            .expect("valid relay")
            .send_raw_transaction(&[1], TXID)
            .await
            .expect_err("slow relay times out");
        assert!(error.contains("request failed"), "{error}");
    }

    #[tokio::test]
    async fn relay_rejects_oversized_responses() {
        let (url, _) = spawn_mock_server(rpc_response(
            "x".repeat(TRANSACTION_RELAY_MAX_RESPONSE_BYTES + 1),
        ));
        let error = TransactionRelayClient::new(&url)
            .expect("valid relay")
            .send_raw_transaction(&[1], TXID)
            .await
            .expect_err("oversized response is rejected");
        assert!(error.contains("exceeded 64 KiB"), "{error}");
    }

    #[test]
    fn relay_url_requires_https_except_for_loopback_and_rejects_credentials() {
        for url in [
            "http://example.com",
            "ftp://example.com",
            "https://user@example.com",
            "https://user:secret@example.com",
        ] {
            assert!(TransactionRelayClient::new(url).is_err(), "{url}");
        }

        for url in [
            "https://relay.example.com",
            "http://localhost:18232",
            "http://127.0.0.1:18232",
            "http://[::1]:18232",
        ] {
            TransactionRelayClient::new(url).unwrap_or_else(|error| panic!("{url}: {error}"));
        }
    }
}
