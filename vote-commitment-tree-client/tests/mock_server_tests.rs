//! Transport-level tests for [`HttpTreeSyncApi`].
//!
//! These keep the client crate's library path independent of any concrete HTTP
//! stack while still exercising the full URL mapping, JSON parsing, and
//! `TreeClient.sync()` integration.

#![cfg(feature = "http")]

use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex},
};

use base64::prelude::*;
use ff::PrimeField;
use pasta_curves::Fp;

use vote_commitment_tree::{TreeClient, TreeSyncApi};
use vote_commitment_tree_client::{
    http_sync_api::{HttpSyncError, HttpTreeSyncApi},
    transport::{Transport, TransportError, TransportResponse},
};

const BASE_URL: &str = "http://node.example";
const TEST_ROUND: &str = "aabbccdd";

#[derive(Default)]
struct MockTransport {
    responses: Mutex<HashMap<String, VecDeque<TransportResponse>>>,
    calls: Mutex<Vec<String>>,
}

impl MockTransport {
    fn with_responses(
        responses: impl IntoIterator<Item = (String, TransportResponse)>,
    ) -> Arc<Self> {
        let transport = Arc::new(Self::default());
        {
            let mut map = transport.responses.lock().unwrap();
            for (url, response) in responses {
                map.entry(url).or_default().push_back(response);
            }
        }
        transport
    }

    fn assert_called(&self, url: &str) {
        let calls = self.calls.lock().unwrap();
        assert!(calls.iter().any(|call| call == url), "expected GET {url}");
    }
}

impl Transport for MockTransport {
    fn get(&self, url: &str) -> Result<TransportResponse, TransportError> {
        self.calls.lock().unwrap().push(url.to_string());
        self.responses
            .lock()
            .unwrap()
            .get_mut(url)
            .and_then(VecDeque::pop_front)
            .ok_or_else(|| TransportError::Request(format!("unexpected GET {url}")))
    }
}

fn api(transport: Arc<MockTransport>) -> HttpTreeSyncApi {
    HttpTreeSyncApi::new(BASE_URL, TEST_ROUND, transport)
}

fn latest_url() -> String {
    format!("{BASE_URL}/shielded-vote/v1/commitment-tree/{TEST_ROUND}/latest")
}

fn root_url(height: u32) -> String {
    format!("{BASE_URL}/shielded-vote/v1/commitment-tree/{TEST_ROUND}/{height}")
}

fn leaves_url(from_height: u32, to_height: u32) -> String {
    format!(
        "{BASE_URL}/shielded-vote/v1/commitment-tree/{TEST_ROUND}/leaves?from_height={from_height}&to_height={to_height}"
    )
}

fn json_response(body: String) -> TransportResponse {
    TransportResponse {
        status: 200,
        body: body.into_bytes(),
    }
}

fn status_response(status: u16, body: &str) -> TransportResponse {
    TransportResponse {
        status,
        body: body.as_bytes().to_vec(),
    }
}

fn fp_to_b64(x: u64) -> String {
    BASE64_STANDARD.encode(Fp::from(x).to_repr())
}

fn fp_bytes_to_b64(fp: Fp) -> String {
    BASE64_STANDARD.encode(fp.to_repr())
}

fn fp(x: u64) -> Fp {
    Fp::from(x)
}

#[test]
fn get_tree_state_parses_response() {
    let root_b64 = fp_bytes_to_b64(fp(42));
    let transport = MockTransport::with_responses([(
        latest_url(),
        json_response(format!(
            r#"{{"tree":{{"next_index":10,"root":"{}","height":5}}}}"#,
            root_b64
        )),
    )]);

    let state = api(transport.clone()).get_tree_state().unwrap();
    assert_eq!(state.next_index, 10);
    assert_eq!(state.height, 5);
    assert_eq!(state.root, fp(42));
    transport.assert_called(&latest_url());
}

#[test]
fn get_root_at_height_parses_response() {
    let root_b64 = fp_bytes_to_b64(fp(99));
    let transport = MockTransport::with_responses([(
        root_url(7),
        json_response(format!(
            r#"{{"tree":{{"next_index":3,"root":"{}","height":7}}}}"#,
            root_b64
        )),
    )]);

    let root = api(transport).get_root_at_height(7).unwrap();
    assert_eq!(root, Some(fp(99)));
}

#[test]
fn get_root_at_height_null_tree() {
    let transport = MockTransport::with_responses([(
        root_url(999),
        json_response(r#"{"tree":null}"#.to_string()),
    )]);

    let root = api(transport).get_root_at_height(999).unwrap();
    assert!(root.is_none());
}

#[test]
fn get_block_commitments_parses_response() {
    let body = format!(
        r#"{{"blocks":[{{"height":5,"start_index":0,"leaves":["{}","{}"],"root":"{}"}}],"next_from_height":12}}"#,
        fp_to_b64(100),
        fp_to_b64(200),
        fp_to_b64(999),
    );
    let transport = MockTransport::with_responses([(leaves_url(1, 10), json_response(body))]);

    let page = api(transport).get_block_commitments(1, 10).unwrap();
    let blocks = page.blocks;
    assert_eq!(page.next_from_height, 12);
    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].height, 5);
    assert_eq!(blocks[0].start_index, 0);
    assert_eq!(blocks[0].leaves.len(), 2);
    assert_eq!(blocks[0].leaves[0].inner(), fp(100));
    assert_eq!(blocks[0].leaves[1].inner(), fp(200));
    assert_eq!(blocks[0].root, fp(999));
}

#[test]
fn get_block_commitments_empty() {
    let transport = MockTransport::with_responses([(
        leaves_url(1, 10),
        json_response(r#"{"blocks":[]}"#.to_string()),
    )]);

    let page = api(transport).get_block_commitments(1, 10).unwrap();
    assert!(page.blocks.is_empty());
    assert_eq!(page.next_from_height, 0);
}

#[test]
fn full_sync_pipeline() {
    let mut tree_server = vote_commitment_tree::MemoryTreeServer::empty();
    tree_server.append(fp(10)).unwrap();
    tree_server.checkpoint(1).unwrap();
    let root_at_1 = tree_server.root_at_height(1).unwrap();

    tree_server.append(fp(20)).unwrap();
    tree_server.append(fp(30)).unwrap();
    tree_server.checkpoint(2).unwrap();
    let root_at_2 = tree_server.root_at_height(2).unwrap();

    let transport = MockTransport::with_responses([
        (
            latest_url(),
            json_response(format!(
                r#"{{"tree":{{"next_index":3,"root":"{}","height":2}}}}"#,
                fp_bytes_to_b64(root_at_2),
            )),
        ),
        (
            leaves_url(0, 2),
            json_response(format!(
                r#"{{"blocks":[{{"height":1,"start_index":0,"leaves":["{}"],"root":"{}"}},{{"height":2,"start_index":1,"leaves":["{}","{}"],"root":"{}"}}]}}"#,
                fp_to_b64(10),
                fp_bytes_to_b64(root_at_1),
                fp_to_b64(20),
                fp_to_b64(30),
                fp_bytes_to_b64(root_at_2),
            )),
        ),
        (
            root_url(1),
            json_response(format!(
                r#"{{"tree":{{"next_index":1,"root":"{}","height":1}}}}"#,
                fp_bytes_to_b64(root_at_1),
            )),
        ),
        (
            root_url(2),
            json_response(format!(
                r#"{{"tree":{{"next_index":3,"root":"{}","height":2}}}}"#,
                fp_bytes_to_b64(root_at_2),
            )),
        ),
    ]);

    let api = api(transport);
    let mut client = TreeClient::empty();
    client.mark_position(0);
    client.mark_position(1);
    client.sync(&api).unwrap();

    assert_eq!(client.size(), 3);
    assert_eq!(client.last_synced_height(), Some(2));
    assert_eq!(client.root_at_height(1), Some(root_at_1));
    assert_eq!(client.root_at_height(2), Some(root_at_2));
    assert_eq!(client.root(), root_at_2);
    assert!(client.witness(0, 2).unwrap().verify(fp(10), root_at_2));
    assert!(client.witness(1, 2).unwrap().verify(fp(20), root_at_2));
}

#[test]
fn full_sync_uses_paginated_leaf_responses() {
    let mut tree_server = vote_commitment_tree::MemoryTreeServer::empty();
    tree_server.append(fp(10)).unwrap();
    tree_server.checkpoint(1).unwrap();
    let root_at_1 = tree_server.root_at_height(1).unwrap();

    tree_server.append(fp(20)).unwrap();
    tree_server.checkpoint(2).unwrap();
    let root_at_2 = tree_server.root_at_height(2).unwrap();

    let transport = MockTransport::with_responses([
        (
            latest_url(),
            json_response(format!(
                r#"{{"tree":{{"next_index":2,"root":"{}","height":2}}}}"#,
                fp_bytes_to_b64(root_at_2),
            )),
        ),
        (
            leaves_url(0, 2),
            json_response(format!(
                r#"{{"blocks":[{{"height":1,"start_index":0,"leaves":["{}"],"root":"{}"}}],"next_from_height":2}}"#,
                fp_to_b64(10),
                fp_bytes_to_b64(root_at_1),
            )),
        ),
        (
            leaves_url(2, 2),
            json_response(format!(
                r#"{{"blocks":[{{"height":2,"start_index":1,"leaves":["{}"],"root":"{}"}}]}}"#,
                fp_to_b64(20),
                fp_bytes_to_b64(root_at_2),
            )),
        ),
    ]);

    let api = api(transport.clone());
    let mut client = TreeClient::empty();
    client.sync(&api).unwrap();

    transport.assert_called(&leaves_url(0, 2));
    transport.assert_called(&leaves_url(2, 2));
    assert_eq!(client.size(), 2);
    assert_eq!(client.last_synced_height(), Some(2));
    assert_eq!(client.root(), root_at_2);
}

#[test]
fn incremental_sync() {
    let mut tree_server = vote_commitment_tree::MemoryTreeServer::empty();
    tree_server.append(fp(10)).unwrap();
    tree_server.checkpoint(1).unwrap();
    let root_at_1 = tree_server.root_at_height(1).unwrap();

    tree_server.append(fp(20)).unwrap();
    tree_server.append(fp(30)).unwrap();
    tree_server.checkpoint(2).unwrap();
    let root_at_2 = tree_server.root_at_height(2).unwrap();

    let transport = MockTransport::with_responses([
        (
            latest_url(),
            json_response(format!(
                r#"{{"tree":{{"next_index":1,"root":"{}","height":1}}}}"#,
                fp_bytes_to_b64(root_at_1),
            )),
        ),
        (
            latest_url(),
            json_response(format!(
                r#"{{"tree":{{"next_index":3,"root":"{}","height":2}}}}"#,
                fp_bytes_to_b64(root_at_2),
            )),
        ),
        (
            leaves_url(0, 1),
            json_response(format!(
                r#"{{"blocks":[{{"height":1,"start_index":0,"leaves":["{}"],"root":"{}"}}]}}"#,
                fp_to_b64(10),
                fp_bytes_to_b64(root_at_1),
            )),
        ),
        (
            root_url(1),
            json_response(format!(
                r#"{{"tree":{{"next_index":1,"root":"{}","height":1}}}}"#,
                fp_bytes_to_b64(root_at_1),
            )),
        ),
        (
            leaves_url(2, 2),
            json_response(format!(
                r#"{{"blocks":[{{"height":2,"start_index":1,"leaves":["{}","{}"],"root":"{}"}}]}}"#,
                fp_to_b64(20),
                fp_to_b64(30),
                fp_bytes_to_b64(root_at_2),
            )),
        ),
        (
            root_url(2),
            json_response(format!(
                r#"{{"tree":{{"next_index":3,"root":"{}","height":2}}}}"#,
                fp_bytes_to_b64(root_at_2),
            )),
        ),
    ]);

    let api = api(transport);
    let mut client = TreeClient::empty();
    client.mark_position(0);
    client.sync(&api).unwrap();
    assert_eq!(client.size(), 1);
    assert_eq!(client.last_synced_height(), Some(1));

    client.mark_position(1);
    client.sync(&api).unwrap();
    assert_eq!(client.size(), 3);
    assert_eq!(client.last_synced_height(), Some(2));
    assert_eq!(client.root(), root_at_2);
    assert!(client.witness(0, 2).unwrap().verify(fp(10), root_at_2));
    assert!(client.witness(1, 2).unwrap().verify(fp(20), root_at_2));
}

#[test]
fn server_error_propagates() {
    let transport = MockTransport::with_responses([(
        latest_url(),
        status_response(500, "internal server error"),
    )]);

    let result = api(transport).get_tree_state();
    assert!(matches!(
        result,
        Err(HttpSyncError::HttpStatus { status: 500, .. })
    ));
}

#[test]
fn empty_tree_sync() {
    let transport = MockTransport::with_responses([(
        latest_url(),
        json_response(format!(
            r#"{{"tree":{{"next_index":0,"root":"{}","height":0}}}}"#,
            fp_bytes_to_b64(fp(0)),
        )),
    )]);

    let api = api(transport);
    let mut client = TreeClient::empty();
    client.sync(&api).unwrap();
    assert_eq!(client.size(), 0);
    assert_eq!(client.last_synced_height(), None);
}

#[test]
fn witness_hex_roundtrip() {
    let mut tree_server = vote_commitment_tree::MemoryTreeServer::empty();
    tree_server.append(fp(42)).unwrap();
    tree_server.checkpoint(1).unwrap();
    let root = tree_server.root_at_height(1).unwrap();

    let transport = MockTransport::with_responses([
        (
            latest_url(),
            json_response(format!(
                r#"{{"tree":{{"next_index":1,"root":"{}","height":1}}}}"#,
                fp_bytes_to_b64(root),
            )),
        ),
        (
            leaves_url(0, 1),
            json_response(format!(
                r#"{{"blocks":[{{"height":1,"start_index":0,"leaves":["{}"],"root":"{}"}}]}}"#,
                fp_to_b64(42),
                fp_bytes_to_b64(root),
            )),
        ),
        (
            root_url(1),
            json_response(format!(
                r#"{{"tree":{{"next_index":1,"root":"{}","height":1}}}}"#,
                fp_bytes_to_b64(root),
            )),
        ),
    ]);

    let api = api(transport);
    let mut client = TreeClient::empty();
    client.mark_position(0);
    client.sync(&api).unwrap();

    let witness_hex = hex::encode(client.witness(0, 1).unwrap().to_bytes());
    let decoded_bytes = hex::decode(&witness_hex).unwrap();
    let decoded_path = vote_commitment_tree::MerklePath::from_bytes(&decoded_bytes).unwrap();
    assert!(decoded_path.verify(fp(42), root));
}
