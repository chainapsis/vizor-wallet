use serde::{Deserialize, Serialize};

use crate::types::{chunk_notes, NoteInfo, VotingError};

/// FFI and JSON friendly note input for vote-authority bundling.
///
/// This mirrors `NoteInfo` intentionally. It is not a redacted network type.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BundleNote {
    pub commitment: Vec<u8>,
    pub nullifier: Vec<u8>,
    pub value: u64,
    pub position: u64,
    pub diversifier: Vec<u8>,
    pub rho: Vec<u8>,
    pub rseed: Vec<u8>,
    pub scope: u32,
    pub ufvk_str: String,
}

impl From<BundleNote> for NoteInfo {
    fn from(note: BundleNote) -> Self {
        Self {
            commitment: note.commitment,
            nullifier: note.nullifier,
            value: note.value,
            position: note.position,
            diversifier: note.diversifier,
            rho: note.rho,
            rseed: note.rseed,
            scope: note.scope,
            ufvk_str: note.ufvk_str,
        }
    }
}

impl From<&BundleNote> for NoteInfo {
    fn from(note: &BundleNote) -> Self {
        note.clone().into()
    }
}

impl From<NoteInfo> for BundleNote {
    fn from(note: NoteInfo) -> Self {
        Self {
            commitment: note.commitment,
            nullifier: note.nullifier,
            value: note.value,
            position: note.position,
            diversifier: note.diversifier,
            rho: note.rho,
            rseed: note.rseed,
            scope: note.scope,
            ufvk_str: note.ufvk_str,
        }
    }
}

impl From<&NoteInfo> for BundleNote {
    fn from(note: &NoteInfo) -> Self {
        note.clone().into()
    }
}

/// Result of note bundling with a stable JSON schema.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BundlePlan {
    pub bundles: Vec<Vec<BundleNote>>,
    pub eligible_weight: u64,
    pub dropped_count: u64,
}

/// Plan note bundles using the crate's canonical `chunk_notes` algorithm.
pub fn plan_note_bundles(notes: &[BundleNote]) -> BundlePlan {
    let note_infos: Vec<NoteInfo> = notes.iter().map(NoteInfo::from).collect();
    plan_note_info_bundles(&note_infos)
}

/// Plan note bundles from existing `NoteInfo` values.
pub fn plan_note_info_bundles(notes: &[NoteInfo]) -> BundlePlan {
    let result = chunk_notes(notes);
    BundlePlan {
        bundles: result
            .bundles
            .iter()
            .map(|bundle| bundle.iter().map(BundleNote::from).collect())
            .collect(),
        eligible_weight: result.eligible_weight,
        dropped_count: result.dropped_count as u64,
    }
}

/// Decode notes JSON, run canonical bundling, and return the plan as JSON.
pub fn plan_note_bundles_json(notes_json: &str) -> Result<String, VotingError> {
    let notes: Vec<BundleNote> =
        serde_json::from_str(notes_json).map_err(|e| VotingError::InvalidInput {
            message: format!("invalid bundle notes JSON: {}", e),
        })?;
    serde_json::to_string(&plan_note_bundles(&notes)).map_err(|e| VotingError::Internal {
        message: format!("failed to encode bundle plan JSON: {}", e),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn note(value: u64, position: u64) -> BundleNote {
        BundleNote {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uview-test".to_string(),
        }
    }

    #[test]
    fn bundle_plan_matches_chunk_notes_ordering() {
        let notes = vec![
            note(50_000_000, 10),
            note(13_000_000, 0),
            note(50_000_000, 12),
            note(13_000_000, 1),
            note(50_000_000, 11),
            note(13_000_000, 2),
            note(50_000_000, 14),
            note(13_000_000, 3),
            note(50_000_000, 13),
            note(13_000_000, 4),
        ];

        let plan = plan_note_bundles(&notes);

        assert_eq!(plan.bundles.len(), 2);
        assert_eq!(plan.eligible_weight, 312_500_000);
        assert_eq!(plan.dropped_count, 0);
        assert_eq!(
            plan.bundles[0]
                .iter()
                .map(|note| note.position)
                .collect::<Vec<_>>(),
            vec![10, 11, 12, 13, 14]
        );
        assert_eq!(
            plan.bundles[1]
                .iter()
                .map(|note| note.position)
                .collect::<Vec<_>>(),
            vec![0, 1, 2, 3, 4]
        );
    }

    #[test]
    fn bundle_plan_drops_underweight_tail_bundle() {
        let notes = vec![
            note(13_000_000, 0),
            note(100, 1),
            note(100, 2),
            note(100, 3),
            note(100, 4),
            note(100, 5),
        ];

        let plan = plan_note_bundles(&notes);

        assert_eq!(plan.bundles.len(), 1);
        assert_eq!(plan.eligible_weight, 12_500_000);
        assert_eq!(plan.dropped_count, 1);
    }

    #[test]
    fn bundle_plan_json_has_stable_schema() {
        let notes_json = serde_json::to_string(&vec![
            note(13_000_000, 5),
            note(13_000_000, 1),
            note(13_000_000, 3),
        ])
        .unwrap();

        let plan_json = plan_note_bundles_json(&notes_json).unwrap();
        let plan: BundlePlan = serde_json::from_str(&plan_json).unwrap();

        assert_eq!(plan.eligible_weight, 37_500_000);
        assert_eq!(plan.dropped_count, 0);
        assert_eq!(
            plan.bundles[0]
                .iter()
                .map(|note| note.position)
                .collect::<Vec<_>>(),
            vec![1, 3, 5]
        );
    }
}
