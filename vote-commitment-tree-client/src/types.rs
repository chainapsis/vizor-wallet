//! JSON deserialization types matching the Go chain's REST API responses.
//!
//! The chain uses `encoding/json.Marshal` on protobuf-generated types, so:
//! - Field names are snake_case (from proto `json` tags)
//! - `[]byte` fields are base64-encoded strings
//! - `uint64` fields are JSON numbers
//! - `omitempty` means zero/nil fields may be absent

use base64::prelude::*;
use ff::PrimeField;
use pasta_curves::Fp;
use serde::Deserialize;

use vote_commitment_tree::sync_api::{BlockCommitments, BlockCommitmentsPage, TreeState};
use vote_commitment_tree::MerkleHashVote;

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

/// Errors from parsing chain JSON responses into domain types.
#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("missing field: {0}")]
    MissingField(&'static str),

    #[error("base64 decode error: {0}")]
    Base64(#[from] base64::DecodeError),

    #[error("invalid Fp encoding ({context}): expected 32 bytes, got {len}")]
    InvalidFpLength { context: &'static str, len: usize },

    #[error("non-canonical Fp encoding ({context})")]
    NonCanonicalFp { context: &'static str },
}

// ---------------------------------------------------------------------------
// Raw JSON shapes (1:1 with Go JSON output)
// ---------------------------------------------------------------------------

/// Matches Go `CommitmentTreeState` JSON serialization.
#[derive(Debug, Deserialize)]
pub(crate) struct ChainTreeState {
    #[serde(default)]
    pub next_index: u64,
    /// Base64-encoded 32-byte Pallas Fp (little-endian).
    #[serde(default)]
    pub root: Option<String>,
    #[serde(default)]
    pub height: u64,
}

/// Matches Go `BlockCommitments` JSON serialization.
#[derive(Debug, Deserialize)]
pub(crate) struct ChainBlockCommitments {
    #[serde(default)]
    pub height: u64,
    #[serde(default)]
    pub start_index: u64,
    /// Each entry is a base64-encoded 32-byte Pallas Fp (little-endian).
    #[serde(default)]
    pub leaves: Vec<String>,
    /// Base64-encoded 32-byte Pallas Fp root after this block.
    #[serde(default)]
    pub root: Option<String>,
}

/// `GET /zally/v1/commitment-tree/latest` response.
#[derive(Debug, Deserialize)]
pub(crate) struct QueryLatestTreeResponse {
    pub tree: Option<ChainTreeState>,
}

/// `GET /zally/v1/commitment-tree/{height}` response.
#[derive(Debug, Deserialize)]
pub(crate) struct QueryCommitmentTreeResponse {
    pub tree: Option<ChainTreeState>,
}

/// `GET /zally/v1/commitment-tree/leaves` response.
#[derive(Debug, Deserialize)]
pub(crate) struct QueryCommitmentLeavesResponse {
    #[serde(default)]
    pub blocks: Vec<ChainBlockCommitments>,
    #[serde(default)]
    pub next_from_height: u64,
}

// ---------------------------------------------------------------------------
// Conversions: raw JSON → domain types
// ---------------------------------------------------------------------------

/// Decode a base64 string into a 32-byte array representing a Pallas Fp element.
fn decode_fp_base64(b64: &str, context: &'static str) -> Result<Fp, ParseError> {
    let bytes = BASE64_STANDARD.decode(b64)?;
    if bytes.len() != 32 {
        return Err(ParseError::InvalidFpLength {
            context,
            len: bytes.len(),
        });
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Option::from(Fp::from_repr(arr)).ok_or(ParseError::NonCanonicalFp { context })
}

impl ChainTreeState {
    /// Convert to the domain `TreeState`.
    pub fn into_tree_state(self) -> Result<TreeState, ParseError> {
        let root = match &self.root {
            Some(b64) if !b64.is_empty() => decode_fp_base64(b64, "tree_state.root")?,
            _ => Fp::zero(),
        };
        Ok(TreeState {
            next_index: self.next_index,
            root,
            height: self.height as u32,
        })
    }
}

impl ChainBlockCommitments {
    /// Convert to the domain `BlockCommitments`.
    pub fn into_block_commitments(self) -> Result<BlockCommitments, ParseError> {
        let mut leaves = Vec::with_capacity(self.leaves.len());
        for (i, b64) in self.leaves.iter().enumerate() {
            let fp = decode_fp_base64(b64, "block_commitments.leaf")?;
            leaves.push(MerkleHashVote::from_fp(fp));
            let _ = i; // suppress unused warning in non-debug
        }
        Ok(BlockCommitments {
            height: self.height as u32,
            start_index: self.start_index,
            leaves,
            root: decode_fp_base64(
                self.root
                    .as_deref()
                    .ok_or(ParseError::MissingField("block_commitments.root"))?,
                "block_commitments.root",
            )?,
        })
    }
}

impl QueryCommitmentLeavesResponse {
    /// Convert to the domain `BlockCommitmentsPage`.
    pub fn into_block_commitments_page(self) -> Result<BlockCommitmentsPage, ParseError> {
        let blocks = self
            .blocks
            .into_iter()
            .map(ChainBlockCommitments::into_block_commitments)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(BlockCommitmentsPage {
            blocks,
            next_from_height: self.next_from_height as u32,
        })
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_tree_state_full() {
        // Fp::zero() is all-zero bytes → base64 of 32 zero bytes
        let zero_b64 = BASE64_STANDARD.encode([0u8; 32]);
        let json = format!(
            r#"{{"tree":{{"next_index":42,"root":"{}","height":10}}}}"#,
            zero_b64
        );
        let resp: QueryLatestTreeResponse = serde_json::from_str(&json).unwrap();
        let state = resp.tree.unwrap().into_tree_state().unwrap();
        assert_eq!(state.next_index, 42);
        assert_eq!(state.height, 10);
        assert_eq!(state.root, Fp::zero());
    }

    #[test]
    fn parse_tree_state_missing_root() {
        let json = r#"{"tree":{"next_index":0,"height":0}}"#;
        let resp: QueryLatestTreeResponse = serde_json::from_str(json).unwrap();
        let state = resp.tree.unwrap().into_tree_state().unwrap();
        assert_eq!(state.root, Fp::zero());
    }

    #[test]
    fn parse_tree_state_null_tree() {
        let json = r#"{"tree":null}"#;
        let resp: QueryLatestTreeResponse = serde_json::from_str(json).unwrap();
        assert!(resp.tree.is_none());
    }

    #[test]
    fn parse_block_commitments_with_leaves() {
        // Fp::from(1) = [1, 0, 0, ..., 0] (32 bytes LE)
        let one_bytes = Fp::from(1).to_repr();
        let one_b64 = BASE64_STANDARD.encode(one_bytes);
        let json = format!(
            r#"{{"blocks":[{{"height":5,"start_index":0,"leaves":["{}","{}"],"root":"{}"}}],"next_from_height":9}}"#,
            one_b64, one_b64, one_b64
        );
        let resp: QueryCommitmentLeavesResponse = serde_json::from_str(&json).unwrap();
        let page = resp.into_block_commitments_page().unwrap();
        assert_eq!(page.next_from_height, 9);
        assert_eq!(page.blocks.len(), 1);
        let block = &page.blocks[0];
        assert_eq!(block.height, 5);
        assert_eq!(block.start_index, 0);
        assert_eq!(block.leaves.len(), 2);
        assert_eq!(block.leaves[0].inner(), Fp::from(1));
        assert_eq!(block.root, Fp::from(1));
    }

    #[test]
    fn parse_empty_blocks() {
        let json = r#"{"blocks":[],"next_from_height":0}"#;
        let resp: QueryCommitmentLeavesResponse = serde_json::from_str(json).unwrap();
        let page = resp.into_block_commitments_page().unwrap();
        assert!(page.blocks.is_empty());
        assert_eq!(page.next_from_height, 0);
    }

    #[test]
    fn parse_omitted_blocks_field() {
        // Go's omitempty may omit the blocks field entirely.
        let json = r#"{}"#;
        let resp: QueryCommitmentLeavesResponse = serde_json::from_str(json).unwrap();
        let page = resp.into_block_commitments_page().unwrap();
        assert!(page.blocks.is_empty());
        assert_eq!(page.next_from_height, 0);
    }

    #[test]
    fn parse_block_commitments_rejects_missing_root() {
        let one_b64 = BASE64_STANDARD.encode(Fp::from(1).to_repr());
        let json = format!(
            r#"{{"blocks":[{{"height":5,"start_index":0,"leaves":["{}"]}}]}}"#,
            one_b64
        );
        let resp: QueryCommitmentLeavesResponse = serde_json::from_str(&json).unwrap();
        let err = resp.into_block_commitments_page().unwrap_err();
        assert!(matches!(
            err,
            ParseError::MissingField("block_commitments.root")
        ));
    }

    #[test]
    fn decode_fp_rejects_short_base64() {
        let short = BASE64_STANDARD.encode([0u8; 16]);
        let err = decode_fp_base64(&short, "test").unwrap_err();
        assert!(matches!(err, ParseError::InvalidFpLength { len: 16, .. }));
    }

    #[test]
    fn decode_fp_rejects_non_canonical() {
        // All 0xFF bytes is larger than the Pallas modulus → non-canonical.
        let bad = BASE64_STANDARD.encode([0xFF; 32]);
        let err = decode_fp_base64(&bad, "test").unwrap_err();
        assert!(matches!(err, ParseError::NonCanonicalFp { .. }));
    }
}
