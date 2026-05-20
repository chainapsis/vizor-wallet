use serde::{Deserialize, Serialize};

use crate::types::VotingError;

/// Normalized outcome for probing a PIR endpoint's `/root` snapshot height.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PirSnapshotEndpointStatus {
    Matched,
    Behind,
    Ahead,
    MissingHeight,
    MalformedJson,
    NonSuccessStatus,
    TimeoutOrNetworkError,
}

/// Probe diagnostic for one configured PIR endpoint.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PirSnapshotEndpointDiagnostic {
    pub endpoint: String,
    pub status: PirSnapshotEndpointStatus,
    pub reported_height: Option<u64>,
    pub http_status_code: Option<u16>,
    pub message: Option<String>,
}

impl PirSnapshotEndpointDiagnostic {
    pub fn matched_at_height(&self, expected_snapshot_height: u64) -> bool {
        self.status == PirSnapshotEndpointStatus::Matched
            && self.reported_height == Some(expected_snapshot_height)
    }
}

/// Selected exact-height PIR endpoint plus diagnostics for every probe.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PirSnapshotResolution {
    pub endpoint: String,
    pub diagnostics: Vec<PirSnapshotEndpointDiagnostic>,
    pub selected_match_index: u64,
}

/// Build a normalized diagnostic from an already parsed height.
pub fn classify_pir_snapshot_height(
    endpoint: impl Into<String>,
    expected_snapshot_height: u64,
    reported_height: Option<u64>,
) -> PirSnapshotEndpointDiagnostic {
    let status = match reported_height {
        Some(height) if height == expected_snapshot_height => PirSnapshotEndpointStatus::Matched,
        Some(height) if height < expected_snapshot_height => PirSnapshotEndpointStatus::Behind,
        Some(_) => PirSnapshotEndpointStatus::Ahead,
        None => PirSnapshotEndpointStatus::MissingHeight,
    };

    PirSnapshotEndpointDiagnostic {
        endpoint: endpoint.into(),
        status,
        reported_height,
        http_status_code: None,
        message: None,
    }
}

/// Return all endpoints whose normalized probe exactly matches the round height.
pub fn matching_pir_snapshot_endpoints(
    diagnostics: &[PirSnapshotEndpointDiagnostic],
    expected_snapshot_height: u64,
) -> Vec<String> {
    diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.matched_at_height(expected_snapshot_height))
        .map(|diagnostic| diagnostic.endpoint.clone())
        .collect()
}

/// Select a PIR endpoint from normalized probe outcomes.
///
/// The selector only accepts exact-height matches. `match_index` lets callers
/// inject their own random index while keeping the crate logic deterministic.
pub fn select_pir_snapshot_endpoint(
    diagnostics: &[PirSnapshotEndpointDiagnostic],
    expected_snapshot_height: u64,
    match_index: u64,
) -> Result<PirSnapshotResolution, VotingError> {
    if diagnostics.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "no PIR endpoints configured".to_string(),
        });
    }

    let matches = matching_pir_snapshot_endpoints(diagnostics, expected_snapshot_height);
    if matches.is_empty() {
        return Err(VotingError::InvalidInput {
            message: format!(
                "no PIR endpoint matched snapshot height {}",
                expected_snapshot_height
            ),
        });
    }

    let selected_match_index = match_index % matches.len() as u64;
    Ok(PirSnapshotResolution {
        endpoint: matches[selected_match_index as usize].clone(),
        diagnostics: diagnostics.to_vec(),
        selected_match_index,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn diagnostic(
        endpoint: &str,
        status: PirSnapshotEndpointStatus,
        reported_height: Option<u64>,
    ) -> PirSnapshotEndpointDiagnostic {
        PirSnapshotEndpointDiagnostic {
            endpoint: endpoint.to_string(),
            status,
            reported_height,
            http_status_code: None,
            message: None,
        }
    }

    #[test]
    fn classifies_parsed_heights_relative_to_expected_height() {
        assert_eq!(
            classify_pir_snapshot_height("https://match.example.com", 100, Some(100)).status,
            PirSnapshotEndpointStatus::Matched
        );
        assert_eq!(
            classify_pir_snapshot_height("https://behind.example.com", 100, Some(99)).status,
            PirSnapshotEndpointStatus::Behind
        );
        assert_eq!(
            classify_pir_snapshot_height("https://ahead.example.com", 100, Some(101)).status,
            PirSnapshotEndpointStatus::Ahead
        );
        assert_eq!(
            classify_pir_snapshot_height("https://missing.example.com", 100, None).status,
            PirSnapshotEndpointStatus::MissingHeight
        );
    }

    #[test]
    fn selects_exact_height_match_by_injected_index() {
        let diagnostics = vec![
            diagnostic(
                "https://behind.example.com",
                PirSnapshotEndpointStatus::Behind,
                Some(99),
            ),
            diagnostic(
                "https://one.example.com",
                PirSnapshotEndpointStatus::Matched,
                Some(100),
            ),
            diagnostic(
                "https://two.example.com",
                PirSnapshotEndpointStatus::Matched,
                Some(100),
            ),
        ];

        let resolution = select_pir_snapshot_endpoint(&diagnostics, 100, 5).unwrap();

        assert_eq!(resolution.endpoint, "https://two.example.com");
        assert_eq!(resolution.selected_match_index, 1);
        assert_eq!(resolution.diagnostics, diagnostics);
    }

    #[test]
    fn excludes_matched_status_without_exact_reported_height() {
        let diagnostics = vec![
            diagnostic(
                "https://missing-height.example.com",
                PirSnapshotEndpointStatus::Matched,
                None,
            ),
            diagnostic(
                "https://wrong-height.example.com",
                PirSnapshotEndpointStatus::Matched,
                Some(101),
            ),
        ];

        let err = select_pir_snapshot_endpoint(&diagnostics, 100, 0).unwrap_err();
        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }

    #[test]
    fn errors_when_no_endpoints_are_configured() {
        let err = select_pir_snapshot_endpoint(&[], 100, 0).unwrap_err();
        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }

    #[test]
    fn errors_when_no_endpoint_matches_exact_height() {
        let diagnostics = vec![
            diagnostic(
                "https://behind.example.com",
                PirSnapshotEndpointStatus::Behind,
                Some(99),
            ),
            diagnostic(
                "https://ahead.example.com",
                PirSnapshotEndpointStatus::Ahead,
                Some(101),
            ),
        ];

        let err = select_pir_snapshot_endpoint(&diagnostics, 100, 0).unwrap_err();
        assert!(matches!(err, VotingError::InvalidInput { .. }));
    }
}
