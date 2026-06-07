//! PIR endpoint selection and client re-exports.
//!
//! Wallets use this module to select an exact-height PIR snapshot endpoint
//! before delegation PIR precomputation.

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
) -> Result<PirSnapshotResolution, crate::types::VotingError> {
    select_pir_snapshot_endpoint(diagnostics, snapshot_height, match_index)
}

pub use pir_client::{
    ImtProofData, PirClient, PirClientBlocking, Transport, TransportFuture, TransportResponse,
};
