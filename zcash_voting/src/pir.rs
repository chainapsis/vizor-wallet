//! PIR endpoint selection and client re-exports.
//!
//! Wallets use this module to select an exact-height PIR snapshot endpoint
//! before delegation PIR precomputation. [`connect_pir_blocking`] /
//! [`connect_pir`] bind a caller-chosen URL to an explicit [`PirLayout`] for
//! the config/server layout handshake. Neither path hardcodes depth or
//! tier-split constants, and neither checks whether the URL appears in a
//! resolved config's advertised endpoint list.

use std::sync::Arc;

use crate::config::{validate_and_convert_pir_layout, PirLayout};
use crate::types::VotingError;

pub use crate::pir_snapshot::{
    classify_pir_snapshot_height, matching_pir_snapshot_endpoints, select_pir_snapshot_endpoint,
    PirSnapshotEndpointDiagnostic, PirSnapshotEndpointStatus, PirSnapshotResolution,
};

/// Candidate PIR endpoint URL.
pub type PirEndpoint = String;

/// Selects an exact-height PIR endpoint from already-probed diagnostics.
///
/// `match_index` lets callers inject deterministic or random selection without
/// making endpoint probing part of the core API.
pub fn select_pir_endpoint(
    diagnostics: &[PirSnapshotEndpointDiagnostic],
    snapshot_height: u64,
    match_index: u64,
) -> Result<PirSnapshotResolution, VotingError> {
    select_pir_snapshot_endpoint(diagnostics, snapshot_height, match_index)
}

pub use pir_client::{
    ImtProofData, PirClient, PirClientBlocking, Transport, TransportFuture, TransportResponse,
};
pub use pir_types::PirLayout as NegotiatedPirLayout;

/// Converts a wallet-config [`PirLayout`] into the PIR client's negotiated layout.
///
/// Rejects the legacy summary sentinel [`PirLayout::UNKNOWN`], inconsistent
/// geometry, and layouts below the YPIR row or item-size minima.
pub fn negotiated_pir_layout(layout: PirLayout) -> Result<NegotiatedPirLayout, VotingError> {
    if layout == PirLayout::UNKNOWN {
        return Err(VotingError::InvalidInput {
            message: "pir_layout is unknown; resolve a current dynamic voting config first"
                .to_string(),
        });
    }
    validate_and_convert_pir_layout(layout).map_err(|message| VotingError::InvalidInput {
        message: format!("invalid pir_layout: {message}"),
    })
}

/// Connects a blocking PIR client using an explicit layout and endpoint URL.
///
/// Does not check whether `endpoint_url` appears in a resolved config's
/// advertised endpoint list; callers pass a layout and URL they already chose
/// (for example after exact-height snapshot probing). Fails closed before any
/// private query when the layout is unknown or the config/server layout
/// handshake rejects the server. Layout mismatches surface as
/// [`VotingError::InvalidInput`]; other connect failures remain
/// [`VotingError::Internal`].
pub fn connect_pir_blocking(
    pir_layout: PirLayout,
    endpoint_url: &str,
    transport: Arc<dyn Transport>,
) -> Result<PirClientBlocking, VotingError> {
    let endpoint = normalize_endpoint_url(endpoint_url);
    if endpoint.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "PIR endpoint URL must not be empty".to_string(),
        });
    }
    let expected_layout = negotiated_pir_layout(pir_layout)?;
    PirClientBlocking::with_transport(&endpoint, expected_layout, transport)
        .map_err(map_pir_connect_error)
}

/// Connects an async PIR client using an explicit layout and endpoint URL.
///
/// See [`connect_pir_blocking`] for layout and URL rules.
pub async fn connect_pir(
    pir_layout: PirLayout,
    endpoint_url: &str,
    transport: Arc<dyn Transport>,
) -> Result<PirClient, VotingError> {
    let endpoint = normalize_endpoint_url(endpoint_url);
    if endpoint.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "PIR endpoint URL must not be empty".to_string(),
        });
    }
    let expected_layout = negotiated_pir_layout(pir_layout)?;
    PirClient::with_transport(&endpoint, expected_layout, transport)
        .await
        .map_err(map_pir_connect_error)
}

fn normalize_endpoint_url(url: &str) -> String {
    url.trim().trim_end_matches('/').to_string()
}

fn map_pir_connect_error(err: impl std::fmt::Display) -> VotingError {
    let detail = err.to_string();
    let message = format!("PIR connect failed: {detail}");
    // Config/server layout disagreement is a caller/config
    // incompatibility, not an unexpected internal failure.
    if detail.contains("PIR layout mismatch") {
        VotingError::InvalidInput { message }
    } else {
        VotingError::Internal { message }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{
        resolve_dynamic_voting_config, resolve_static_voting_config, ResolveVotingConfigOptions,
    };
    use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
    use ed25519_dalek::{Signer, SigningKey};
    use pir_types::{
        RootInfo, YpirScenario, COMPILED_PIR_LAYOUT, DATASET_VERSION, NULLIFIER_POOL, PIR_DEPTH,
        TIER0_LAYERS,
    };
    use serde_json::json;
    use std::collections::HashMap;
    use std::sync::Mutex;

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[derive(Default)]
    struct RecordingTransport {
        gets: Mutex<HashMap<String, TransportResponse>>,
        hits: Mutex<Vec<String>>,
        posts: Mutex<usize>,
    }

    impl RecordingTransport {
        fn matching_root() -> Self {
            let transport = Self::default();
            transport.insert_matching_assets(COMPILED_PIR_LAYOUT);
            transport
        }

        fn with_root_layout(layout: NegotiatedPirLayout) -> Self {
            let transport = Self::default();
            transport.insert_matching_assets(layout);
            transport
        }

        fn insert_matching_assets(&self, layout: NegotiatedPirLayout) {
            let rows = layout.tier1_rows().unwrap();
            let row_bytes = layout.tier1_row_bytes().unwrap();
            let item_bits = layout.tier1_item_bits().unwrap();
            let tier0_bytes = layout.tier0_bytes().unwrap();
            let root = RootInfo {
                zcash_network: pir_types::ZcashNetwork::Test,
                nullifier_pool: NULLIFIER_POOL.to_owned(),
                dataset_version: DATASET_VERSION,
                circuit_root: hex::encode([0u8; 32]),
                pir_root: hex::encode([0u8; 32]),
                num_ranges: 1,
                pir_layout: layout,
                pir_depth: layout.pir_depth,
                tier1_rows: rows,
                tier1_row_bytes: row_bytes,
                height: Some(100),
            };
            let tier1 = YpirScenario {
                num_items: rows,
                item_size_bits: item_bits,
            };
            let mut gets = self.gets.lock().unwrap();
            gets.insert("/tier0".to_string(), response(vec![0; tier0_bytes]));
            gets.insert(
                "/params/tier1".to_string(),
                response(serde_json::to_vec(&tier1).unwrap()),
            );
            gets.insert(
                "/root".to_string(),
                response(serde_json::to_vec(&root).unwrap()),
            );
        }

        fn count_hits(&self, path: &str) -> usize {
            self.hits
                .lock()
                .unwrap()
                .iter()
                .filter(|hit| hit.as_str() == path)
                .count()
        }

        fn post_count(&self) -> usize {
            *self.posts.lock().unwrap()
        }
    }

    impl Transport for RecordingTransport {
        fn get<'a>(&'a self, url: &'a str) -> TransportFuture<'a> {
            Box::pin(async move {
                let path = request_path(url);
                self.hits.lock().unwrap().push(path.to_owned());
                self.gets
                    .lock()
                    .unwrap()
                    .get(path)
                    .cloned()
                    .ok_or_else(|| anyhow::anyhow!("unexpected GET {path}"))
            })
        }

        fn post<'a>(&'a self, url: &'a str, _body: Vec<u8>) -> TransportFuture<'a> {
            Box::pin(async move {
                let path = request_path(url);
                self.hits.lock().unwrap().push(path.to_owned());
                *self.posts.lock().unwrap() += 1;
                Err(anyhow::anyhow!(
                    "unexpected POST {path}; layout handshake must fail before queries"
                ))
            })
        }
    }

    fn response(body: Vec<u8>) -> TransportResponse {
        TransportResponse {
            status: 200,
            headers: Vec::new(),
            body,
        }
    }

    fn request_path(url: &str) -> &str {
        let without_scheme = url.split_once("://").map(|(_, rest)| rest).unwrap_or(url);
        without_scheme
            .find('/')
            .map(|idx| &without_scheme[idx..])
            .unwrap_or("/")
    }

    fn expect_connect_err(result: Result<PirClientBlocking, VotingError>) -> VotingError {
        match result {
            Ok(_) => panic!("expected PIR connect failure"),
            Err(err) => err,
        }
    }

    fn compiled_wallet_layout() -> PirLayout {
        PirLayout {
            pir_depth: u32::try_from(COMPILED_PIR_LAYOUT.pir_depth).unwrap(),
            tier0_layers: u32::try_from(COMPILED_PIR_LAYOUT.tier0_layers).unwrap(),
            tier1_layers: u32::try_from(COMPILED_PIR_LAYOUT.tier1_layers).unwrap(),
        }
    }

    #[test]
    fn connect_rejects_unknown_layout_before_transport() {
        let transport = Arc::new(RecordingTransport::matching_root());

        let err = expect_connect_err(connect_pir_blocking(
            PirLayout::UNKNOWN,
            "https://pir.example.com",
            transport.clone(),
        ));

        assert!(matches!(err, VotingError::InvalidInput { .. }), "{err}");
        assert!(err.to_string().contains("pir_layout is unknown"), "{err}");
        assert_eq!(transport.count_hits("/root"), 0);
        assert_eq!(transport.post_count(), 0);
    }

    #[test]
    fn connect_rejects_unusable_ypir_layouts_before_transport() {
        for (layout, expected) in [
            (
                PirLayout {
                    pir_depth: 19,
                    tier0_layers: 10,
                    tier1_layers: 9,
                },
                "Tier 1 rows 1024 below YPIR minimum 2048",
            ),
            (
                PirLayout {
                    pir_depth: 19,
                    tier0_layers: 14,
                    tier1_layers: 5,
                },
                "Tier 1 item bits 24576 below YPIR minimum 28672",
            ),
            (
                PirLayout {
                    pir_depth: 19,
                    tier0_layers: 0,
                    tier1_layers: 19,
                },
                "PIR layout tiers must be non-zero",
            ),
        ] {
            let transport = Arc::new(RecordingTransport::matching_root());
            let err = expect_connect_err(connect_pir_blocking(
                layout,
                "https://pir.example.com",
                transport.clone(),
            ));

            assert!(matches!(err, VotingError::InvalidInput { .. }), "{err}");
            assert!(err.to_string().contains(expected), "{err}");
            assert_eq!(transport.count_hits("/tier0"), 0);
            assert_eq!(transport.count_hits("/params/tier1"), 0);
            assert_eq!(transport.count_hits("/root"), 0);
            assert_eq!(transport.post_count(), 0);
        }
    }

    #[test]
    fn connect_rejects_server_layout_mismatch_before_query() {
        let mismatched = NegotiatedPirLayout {
            pir_depth: PIR_DEPTH,
            tier0_layers: TIER0_LAYERS - 1,
            tier1_layers: COMPILED_PIR_LAYOUT.tier1_layers + 1,
        };
        let transport = Arc::new(RecordingTransport::with_root_layout(mismatched));

        let err = expect_connect_err(connect_pir_blocking(
            compiled_wallet_layout(),
            "https://pir.example.com/",
            transport.clone(),
        ));

        assert!(matches!(err, VotingError::InvalidInput { .. }), "{err}");
        assert!(err.to_string().contains("PIR layout mismatch"), "{err}");
        assert_eq!(transport.post_count(), 0);
    }

    #[test]
    fn connect_rejects_config_layout_mismatch_before_query() {
        let layout = PirLayout {
            pir_depth: 18,
            tier0_layers: 11,
            tier1_layers: 7,
        };
        let transport = Arc::new(RecordingTransport::matching_root());

        let err = expect_connect_err(connect_pir_blocking(
            layout,
            "https://pir.example.com",
            transport.clone(),
        ));

        assert!(matches!(err, VotingError::InvalidInput { .. }), "{err}");
        assert!(err.to_string().contains("PIR layout mismatch"), "{err}");
        assert_eq!(transport.post_count(), 0);
    }

    #[test]
    fn connect_succeeds_when_config_and_server_layouts_match() {
        let transport = Arc::new(RecordingTransport::matching_root());

        let _client = connect_pir_blocking(
            compiled_wallet_layout(),
            "https://pir.example.com/",
            transport.clone(),
        )
        .unwrap();

        assert_eq!(transport.count_hits("/tier0"), 1);
        assert_eq!(transport.count_hits("/params/tier1"), 1);
        assert_eq!(transport.count_hits("/root"), 1);
        assert_eq!(transport.post_count(), 0);
    }

    #[test]
    fn connect_accepts_caller_chosen_endpoint_url() {
        let transport = Arc::new(RecordingTransport::matching_root());

        let _client = connect_pir_blocking(
            compiled_wallet_layout(),
            "https://unlisted-pir.example.com/",
            transport.clone(),
        )
        .unwrap();

        assert_eq!(transport.count_hits("/tier0"), 1);
        assert_eq!(transport.count_hits("/params/tier1"), 1);
        assert_eq!(transport.count_hits("/root"), 1);
        assert_eq!(transport.post_count(), 0);
    }

    #[test]
    fn connect_rejects_empty_url() {
        let transport = Arc::new(RecordingTransport::matching_root());
        let err = expect_connect_err(connect_pir_blocking(
            compiled_wallet_layout(),
            "   ",
            transport.clone(),
        ));
        assert!(err.to_string().contains("must not be empty"), "{err}");
        assert_eq!(transport.count_hits("/root"), 0);
    }

    #[test]
    fn signed_static_to_dynamic_to_pir_connect_handshake() {
        let signing_key = SigningKey::from_bytes(&[7u8; 32]);
        let pubkey = signing_key.verifying_key().to_bytes();
        let static_bytes = json!({
            "static_config_version": 1,
            "dynamic_config_url": "https://example.com/dynamic.json",
            "trusted_keys": [{
                "key_id": "k1",
                "alg": "ed25519",
                "pubkey": BASE64.encode(pubkey),
                "notes": null
            }]
        })
        .to_string()
        .into_bytes();
        let source = "https://example.com/static.json";
        let resolved_static = resolve_static_voting_config(source, &static_bytes).unwrap();

        let ea_pk = [7u8; 32];
        let sig = signing_key.sign(&ea_pk).to_bytes();
        let dynamic_bytes = json!({
            "config_version": 1,
            "vote_servers": [{"url": "https://vote.example.com", "label": "vote"}],
            "pir_endpoints": [{"url": "https://pir.example.com", "label": "pir"}],
            "pir_layout": {
                "pir_depth": COMPILED_PIR_LAYOUT.pir_depth,
                "tier0_layers": COMPILED_PIR_LAYOUT.tier0_layers,
                "tier1_layers": COMPILED_PIR_LAYOUT.tier1_layers
            },
            "supported_versions": {
                "pir": ["v0"],
                "vote_protocol": "v0",
                "tally": "v0",
                "vote_server": "v1"
            },
            "rounds": {
                ROUND_ID: {
                    "auth_version": 1,
                    "ea_pk": BASE64.encode(ea_pk),
                    "signatures": [{
                        "key_id": "k1",
                        "alg": "ed25519",
                        "sig": BASE64.encode(sig)
                    }]
                }
            }
        })
        .to_string()
        .into_bytes();
        let resolved = resolve_dynamic_voting_config(
            resolved_static,
            &dynamic_bytes,
            ResolveVotingConfigOptions::default(),
        )
        .unwrap();

        assert_eq!(resolved.pir_layout, compiled_wallet_layout());
        assert_eq!(resolved.pir_endpoints[0].url, "https://pir.example.com");

        let matching = Arc::new(RecordingTransport::matching_root());
        let _client = connect_pir_blocking(
            resolved.pir_layout,
            "https://pir.example.com",
            matching.clone(),
        )
        .unwrap();
        assert_eq!(matching.post_count(), 0);

        let mismatched = Arc::new(RecordingTransport::with_root_layout(NegotiatedPirLayout {
            pir_depth: 18,
            tier0_layers: 11,
            tier1_layers: 7,
        }));
        let err = expect_connect_err(connect_pir_blocking(
            resolved.pir_layout,
            "https://pir.example.com",
            mismatched.clone(),
        ));
        assert!(matches!(err, VotingError::InvalidInput { .. }), "{err}");
        assert!(err.to_string().contains("PIR layout mismatch"), "{err}");
        assert_eq!(mismatched.post_count(), 0);
    }
}
