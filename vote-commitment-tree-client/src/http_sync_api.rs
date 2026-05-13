//! HTTP endpoint mapping for [`TreeSyncApi`] against a running Zally chain node.
//!
//! Maps the three trait methods to per-round REST endpoints:
//! - `get_tree_state()`        → `GET /shielded-vote/v1/commitment-tree/{round_id}/latest`
//! - `get_root_at_height(h)`   → `GET /shielded-vote/v1/commitment-tree/{round_id}/{h}`
//! - `get_block_commitments()` → `GET /shielded-vote/v1/commitment-tree/{round_id}/leaves?from_height=X&to_height=Y`

use std::sync::Arc;

use pasta_curves::Fp;
use vote_commitment_tree::sync_api::{BlockCommitmentsPage, TreeState, TreeSyncApi};

use crate::transport::{Transport, TransportError, TransportResponse};
use crate::types::{
    QueryCommitmentLeavesResponse, QueryCommitmentTreeResponse, QueryLatestTreeResponse,
};

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

/// Errors from the HTTP sync API.
#[derive(Debug, thiserror::Error)]
pub enum HttpSyncError {
    #[error("transport request failed: {0}")]
    Transport(#[from] TransportError),

    #[error("HTTP request to {url} returned status {status}: {body}")]
    HttpStatus {
        url: String,
        status: u16,
        body: String,
    },

    #[error("JSON parse error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("parse error: {0}")]
    Parse(#[from] crate::types::ParseError),

    #[error("server returned no tree state")]
    NoTreeState,
}

// ---------------------------------------------------------------------------
// HttpTreeSyncApi
// ---------------------------------------------------------------------------

/// HTTP-based implementation of [`TreeSyncApi`] for remote chain sync.
///
/// Uses an injected blocking transport so this crate can own URL construction
/// and JSON parsing without selecting an HTTP stack for library consumers.
/// Each instance is scoped to a specific voting round via `round_id`
/// (hex-encoded in URL paths).
pub struct HttpTreeSyncApi {
    transport: Arc<dyn Transport>,
    /// Base URL of the chain's REST API (e.g. `http://localhost:1317`).
    base_url: String,
    /// Hex-encoded round ID for per-round tree endpoints.
    round_id: String,
}

impl HttpTreeSyncApi {
    /// Create a new HTTP sync API client for a specific voting round.
    ///
    /// `base_url` should be the root of the chain's REST API, without a trailing
    /// slash (e.g. `http://localhost:1317`). `round_id` is the hex-encoded
    /// voting round identifier.
    pub fn new(
        base_url: impl Into<String>,
        round_id: impl Into<String>,
        transport: Arc<dyn Transport>,
    ) -> Self {
        Self {
            base_url: base_url.into(),
            round_id: round_id.into(),
            transport,
        }
    }

    fn get_json<T: serde::de::DeserializeOwned>(&self, url: String) -> Result<T, HttpSyncError> {
        let response = self.transport.get(&url)?;
        let body = self.success_body(&url, response)?;
        serde_json::from_slice(&body).map_err(HttpSyncError::Json)
    }

    fn success_body(
        &self,
        url: &str,
        response: TransportResponse,
    ) -> Result<Vec<u8>, HttpSyncError> {
        if (200..300).contains(&response.status) {
            Ok(response.body)
        } else {
            Err(HttpSyncError::HttpStatus {
                url: url.to_string(),
                status: response.status,
                body: String::from_utf8_lossy(&response.body).into_owned(),
            })
        }
    }
}

impl TreeSyncApi for HttpTreeSyncApi {
    type Error = HttpSyncError;

    fn get_tree_state(&self) -> Result<TreeState, Self::Error> {
        let url = format!(
            "{}/shielded-vote/v1/commitment-tree/{}/latest",
            self.base_url, self.round_id
        );
        let resp: QueryLatestTreeResponse = self.get_json(url)?;
        resp.tree
            .ok_or(HttpSyncError::NoTreeState)?
            .into_tree_state()
            .map_err(HttpSyncError::Parse)
    }

    fn get_root_at_height(&self, height: u32) -> Result<Option<Fp>, Self::Error> {
        let url = format!(
            "{}/shielded-vote/v1/commitment-tree/{}/{}",
            self.base_url, self.round_id, height
        );
        let resp: QueryCommitmentTreeResponse = self.get_json(url)?;
        match resp.tree {
            Some(state) => {
                let ts = state.into_tree_state().map_err(HttpSyncError::Parse)?;
                Ok(Some(ts.root))
            }
            None => Ok(None),
        }
    }

    fn get_block_commitments(
        &self,
        from_height: u32,
        to_height: u32,
    ) -> Result<BlockCommitmentsPage, Self::Error> {
        let url = format!(
            "{}/shielded-vote/v1/commitment-tree/{}/leaves?from_height={}&to_height={}",
            self.base_url, self.round_id, from_height, to_height
        );
        let resp: QueryCommitmentLeavesResponse = self.get_json(url)?;
        resp.into_block_commitments_page()
            .map_err(HttpSyncError::Parse)
    }
}
