//! Smart note bundle planning for voting rounds.

use std::collections::HashSet;

use crate::{
    governance::{BALLOT_DIVISOR, BUNDLE_NOTE_SLOTS},
    types::{validate_notes_for_round, NoteInfo, SelectedNotes, VotingError},
};

/// Default full bundle size. Eligibility depends on quantized voting weight,
/// not on requiring this many real notes.
pub const MINIMUM_VOTING_NOTE_COUNT: usize = BUNDLE_NOTE_SLOTS;

/// Minimum quantized voting weight in zatoshi required before a wallet can vote.
pub const MINIMUM_VOTING_WEIGHT_ZATOSHI: u64 = BALLOT_DIVISOR;

/// Controls how many real wallet notes are placed into each voting bundle.
///
/// Bundles with fewer than [`BUNDLE_NOTE_SLOTS`] real notes are still padded
/// later by the proof construction path. This policy only controls how many
/// selected wallet notes can appear in one real bundle.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BundlePolicy {
    max_real_notes_per_bundle: usize,
    bundle_addition_threshold_zatoshi: Option<u64>,
}

impl BundlePolicy {
    /// Builds a bundle policy with an explicit real-note capacity.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when `max_real_notes_per_bundle` is
    /// outside `1..=BUNDLE_NOTE_SLOTS`.
    pub fn new(max_real_notes_per_bundle: usize) -> Result<Self, VotingError> {
        if (1..=BUNDLE_NOTE_SLOTS).contains(&max_real_notes_per_bundle) {
            Ok(Self {
                max_real_notes_per_bundle,
                bundle_addition_threshold_zatoshi: None,
            })
        } else {
            Err(VotingError::InvalidInput {
                message: format!(
                    "max_real_notes_per_bundle must be in 1..={BUNDLE_NOTE_SLOTS}, got {max_real_notes_per_bundle}"
                ),
            })
        }
    }

    /// Builds a policy from an optional caller override.
    ///
    /// `None` selects the default policy, so SDK boundary layers can expose this
    /// as an optional setting without forcing most callers to think about it.
    pub fn from_optional_max_real_notes_per_bundle(
        max_real_notes_per_bundle: Option<u32>,
    ) -> Result<Self, VotingError> {
        match max_real_notes_per_bundle {
            Some(value) => {
                let value = usize::try_from(value).map_err(|_| VotingError::InvalidInput {
                    message: format!(
                        "max_real_notes_per_bundle must be in 1..={BUNDLE_NOTE_SLOTS}, got {value}"
                    ),
                })?;
                Self::new(value)
            }
            None => Ok(Self::default()),
        }
    }

    /// Returns the real-note capacity used by the bundler.
    pub fn max_real_notes_per_bundle(self) -> usize {
        self.max_real_notes_per_bundle
    }

    /// Returns a copy of this policy with an additive bundle value threshold.
    ///
    /// When a bundle already has at least one note, the bundler starts a new
    /// bundle before adding another note that would push the current bundle's
    /// total over `threshold_zatoshi`. A single note above the threshold is still
    /// allowed as its own bundle.
    pub fn with_bundle_addition_threshold(mut self, threshold_zatoshi: u64) -> Self {
        self.bundle_addition_threshold_zatoshi = Some(threshold_zatoshi);
        self
    }

    /// Returns the optional threshold used when deciding whether to add a note
    /// to the current bundle.
    pub fn bundle_addition_threshold(self) -> Option<u64> {
        self.bundle_addition_threshold_zatoshi
    }
}

impl Default for BundlePolicy {
    fn default() -> Self {
        Self {
            max_real_notes_per_bundle: BUNDLE_NOTE_SLOTS,
            bundle_addition_threshold_zatoshi: None,
        }
    }
}

/// Result of value-aware note bundling.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ChunkResult {
    /// Surviving bundles, each with total >= BALLOT_DIVISOR.
    pub bundles: Vec<Vec<NoteInfo>>,
    /// Effective voting weight after per-bundle VAN quantization
    /// (each bundle contributes floor(total/BALLOT_DIVISOR) * BALLOT_DIVISOR).
    pub eligible_weight: u64,
    /// Number of notes that were dropped (in bundles below BALLOT_DIVISOR).
    pub dropped_count: usize,
}

/// Read-only result of checking the minimum voting eligibility rule.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MinimumVotingEligibility {
    pub distinct_note_count: usize,
    pub eligible_weight: u64,
}

impl MinimumVotingEligibility {
    /// Returns whether the note set satisfies the minimum voting rule.
    pub fn is_eligible(self) -> bool {
        self.eligible_weight >= MINIMUM_VOTING_WEIGHT_ZATOSHI
    }
}

/// Returns quantized zatoshi voting power for the selected note set.
pub fn voting_power(notes: &SelectedNotes) -> u64 {
    voting_power_with_policy(notes, BundlePolicy::default())
}

/// Returns quantized zatoshi voting power under an explicit bundle policy.
pub fn voting_power_with_policy(notes: &SelectedNotes, policy: BundlePolicy) -> u64 {
    let note_infos = notes.voting_note_infos();
    minimum_voting_eligibility_for_notes(&note_infos, policy)
        .map(|status| status.eligible_weight)
        .unwrap_or(0)
}

/// Returns whether `notes` satisfy the minimum voting rule under `policy`.
///
/// The weight uses the same smart bundle quantization used for delegation
/// setup. Distinct note count is reported for diagnostics, but bundle padding
/// means it is not itself an eligibility requirement.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] if any note row is malformed.
pub fn minimum_voting_eligibility_for_notes(
    notes: &[NoteInfo],
    policy: BundlePolicy,
) -> Result<MinimumVotingEligibility, VotingError> {
    let (eligibility, _) = minimum_voting_eligibility_and_plan_for_notes(notes, policy)?;
    Ok(eligibility)
}

/// Validates the minimum voting rule under `policy`.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] if notes are malformed or if the note
/// set does not include enough quantized voting weight.
pub fn validate_minimum_voting_eligibility_for_notes(
    notes: &[NoteInfo],
    policy: BundlePolicy,
) -> Result<MinimumVotingEligibility, VotingError> {
    let eligibility = minimum_voting_eligibility_for_notes(notes, policy)?;
    if eligibility.is_eligible() {
        Ok(eligibility)
    } else {
        Err(minimum_voting_eligibility_error(eligibility))
    }
}

pub(crate) fn minimum_voting_eligibility_and_plan_for_notes(
    notes: &[NoteInfo],
    policy: BundlePolicy,
) -> Result<(MinimumVotingEligibility, ChunkResult), VotingError> {
    if notes.is_empty() {
        return Ok((
            MinimumVotingEligibility {
                distinct_note_count: 0,
                eligible_weight: 0,
            },
            chunk_notes_with_policy(notes, policy),
        ));
    }
    let plan = canonical_note_bundle_plan_for_notes(notes, policy)?;
    let surviving_note_count = plan.bundles.iter().map(Vec::len).sum();
    let eligibility = MinimumVotingEligibility {
        distinct_note_count: surviving_note_count,
        eligible_weight: plan.eligible_weight,
    };
    Ok((eligibility, plan))
}

pub(crate) fn minimum_voting_eligibility_error(
    eligibility: MinimumVotingEligibility,
) -> VotingError {
    VotingError::InvalidInput {
        message: format!(
            "minimum voting eligibility requires at least one eligible voting bundle with {MINIMUM_VOTING_WEIGHT_ZATOSHI} zatoshi voting weight; selected {} distinct notes across eligible bundles with {} zatoshi eligible bundle weight",
            eligibility.distinct_note_count, eligibility.eligible_weight
        ),
    }
}

/// Returns the canonical bundle plan for wallet-facing round APIs.
///
/// Duplicate nullifiers are collapsed before chunking so eligibility checks and
/// bundle construction cannot disagree about whether a note is spendable once.
pub(crate) fn canonical_note_bundle_plan_for_notes(
    notes: &[NoteInfo],
    policy: BundlePolicy,
) -> Result<ChunkResult, VotingError> {
    validate_notes_for_round(notes)?;
    let distinct_notes = distinct_notes_by_nullifier(notes);
    Ok(chunk_notes_with_policy(&distinct_notes, policy))
}

fn distinct_notes_by_nullifier(notes: &[NoteInfo]) -> Vec<NoteInfo> {
    let mut seen = HashSet::new();
    notes
        .iter()
        .filter(|note| seen.insert(note.nullifier.as_slice()))
        .cloned()
        .collect()
}

/// Split notes into value-aware bundles using the default policy.
pub fn chunk_notes(notes: &[NoteInfo]) -> ChunkResult {
    chunk_notes_with_policy(notes, BundlePolicy::default())
}

/// Split notes into value-aware bundles using sequential packing.
///
/// Algorithm:
/// 1. Sort notes by value DESC, then position ASC as tiebreaker
/// 2. Fill bundles sequentially to policy capacity
/// 3. Start a new bundle when adding a note would exceed the optional threshold
/// 4. Drop bundles with total < BALLOT_DIVISOR
/// 5. Re-sort notes within each surviving bundle by position
/// 6. Sort surviving bundles by total value DESC (min position as tiebreaker)
///
/// Sequential packing concentrates high-value notes in early bundles, maximizing
/// per-bundle VAN weight and minimizing quantization loss. Dust notes naturally
/// end up in the last (smallest) bundle which gets dropped if below threshold.
/// Value-descending bundle order lets Keystone users sign the most valuable
/// bundles first and optionally skip the remaining low-value ones.
pub fn chunk_notes_with_policy(notes: &[NoteInfo], policy: BundlePolicy) -> ChunkResult {
    if notes.is_empty() {
        return ChunkResult {
            bundles: vec![],
            eligible_weight: 0,
            dropped_count: 0,
        };
    }

    // Step 1: Sort by value DESC, then position ASC as tiebreaker.
    let mut sorted = notes.to_vec();
    sorted.sort_by(|a, b| b.value.cmp(&a.value).then(a.position.cmp(&b.position)));

    // Step 2: Fill bundles sequentially to the configured real-note capacity,
    // starting a new bundle when another note would cross the value threshold.
    let mut bundle_notes: Vec<Vec<NoteInfo>> = Vec::new();
    let mut bundle_totals: Vec<u64> = Vec::new();
    let max_real_notes = policy.max_real_notes_per_bundle();
    let bundle_addition_threshold = policy.bundle_addition_threshold();

    for note in sorted {
        let needs_new_bundle = match bundle_notes.last() {
            Some(bundle) if bundle.len() >= max_real_notes => true,
            Some(bundle) if !bundle.is_empty() => bundle_addition_would_exceed_threshold(
                *bundle_totals.last().expect("bundle total exists"),
                note.value,
                bundle_addition_threshold,
            ),
            Some(_) => false,
            None => true,
        };
        if needs_new_bundle {
            bundle_notes.push(Vec::new());
            bundle_totals.push(0);
        }
        let last = bundle_notes.len() - 1;
        bundle_totals[last] += note.value;
        bundle_notes[last].push(note);
    }

    // Step 4: Drop bundles with total < BALLOT_DIVISOR.
    let total_notes: usize = bundle_notes.iter().map(|b| b.len()).sum();
    let mut surviving: Vec<(u64, Vec<NoteInfo>)> = Vec::new();
    let mut eligible_weight: u64 = 0;
    let mut surviving_notes: usize = 0;

    for (i, bundle) in bundle_notes.into_iter().enumerate() {
        if bundle_totals[i] >= BALLOT_DIVISOR {
            surviving_notes += bundle.len();
            eligible_weight += (bundle_totals[i] / BALLOT_DIVISOR) * BALLOT_DIVISOR;
            surviving.push((bundle_totals[i], bundle));
        }
    }
    let dropped_count = total_notes - surviving_notes;

    for (_, bundle) in &mut surviving {
        bundle.sort_by_key(|n| n.position);
    }

    // Sort surviving bundles by total value DESC. Use min position as a
    // deterministic tiebreaker for equal-value bundles.
    surviving.sort_by(|a, b| {
        b.0.cmp(&a.0).then_with(|| {
            let a_pos = a.1.first().map(|n| n.position).unwrap_or(u64::MAX);
            let b_pos = b.1.first().map(|n| n.position).unwrap_or(u64::MAX);
            a_pos.cmp(&b_pos)
        })
    });

    ChunkResult {
        bundles: surviving.into_iter().map(|(_, b)| b).collect(),
        eligible_weight,
        dropped_count,
    }
}

fn bundle_addition_would_exceed_threshold(
    current_total: u64,
    note_value: u64,
    threshold: Option<u64>,
) -> bool {
    match threshold {
        Some(threshold) => current_total
            .checked_add(note_value)
            .map_or(true, |total| total > threshold),
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::NoteRef;
    use zcash_client_backend::proto::service::TreeState;

    fn make_note(value: u64, position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![position as u8; 32],
            value,
            position,
            diversifier: vec![0; 11],
            rho: vec![0; 32],
            rseed: vec![0; 32],
            scope: 0,
            ufvk_str: String::new(),
        }
    }

    fn test_note_ref(value_zatoshi: u64, voting_weight_zatoshi: u64, position: u64) -> NoteRef {
        NoteRef {
            pool: "orchard".to_string(),
            txid_hex: hex::encode([position as u8; 32]),
            output_index: position as u32,
            value_zatoshi,
            voting_weight_zatoshi,
            commitment: vec![0x01; 32],
            nullifier: vec![position as u8; 32],
            diversifier: vec![0x03; 11],
            rho: vec![0x04; 32],
            rseed: vec![0x05; 32],
            scope: 0,
            ufvk_str: String::new(),
            commitment_tree_position: position,
            mined_height: 1,
            anchor_height: 100,
        }
    }

    fn placeholder_tree_state(snapshot_height: u64) -> TreeState {
        TreeState {
            network: "test".to_string(),
            height: snapshot_height,
            hash: String::new(),
            time: 0,
            sapling_tree: String::new(),
            orchard_tree: String::new(),
            ironwood_tree: String::new(),
        }
    }

    #[test]
    fn voting_power_uses_smart_bundle_quantization() {
        let small_note_value = (BALLOT_DIVISOR / BUNDLE_NOTE_SLOTS as u64) + 1;
        let selected = SelectedNotes {
            notes: (0..BUNDLE_NOTE_SLOTS)
                .map(|position| {
                    test_note_ref(small_note_value, small_note_value, position as u64 + 1)
                })
                .collect(),
            snapshot_height: 100,
            anchor_tree_state: placeholder_tree_state(100),
        };

        assert_eq!(voting_power(&selected), BALLOT_DIVISOR);
    }

    #[test]
    fn voting_power_uses_custom_bundle_policy() {
        let selected = SelectedNotes {
            notes: (0..BUNDLE_NOTE_SLOTS)
                .map(|position| test_note_ref(13_000_000, 13_000_000, position as u64))
                .collect(),
            snapshot_height: 100,
            anchor_tree_state: placeholder_tree_state(100),
        };
        let policy = BundlePolicy::new(1).unwrap();

        assert_eq!(
            voting_power_with_policy(&selected, policy),
            BUNDLE_NOTE_SLOTS as u64 * BALLOT_DIVISOR
        );
    }

    #[test]
    fn voting_power_returns_zero_for_invalid_selected_notes() {
        let selected = SelectedNotes {
            notes: vec![NoteRef {
                commitment: vec![0x01; 31],
                ..test_note_ref(BALLOT_DIVISOR, BALLOT_DIVISOR, 1)
            }],
            snapshot_height: 100,
            anchor_tree_state: placeholder_tree_state(100),
        };

        assert_eq!(
            voting_power_with_policy(&selected, BundlePolicy::new(1).unwrap()),
            0
        );
    }

    #[test]
    fn minimum_voting_eligibility_accepts_five_notes_at_threshold() {
        let notes: Vec<NoteInfo> = (0..BUNDLE_NOTE_SLOTS)
            .map(|i| make_note(BALLOT_DIVISOR / BUNDLE_NOTE_SLOTS as u64, i as u64))
            .collect();

        let status =
            validate_minimum_voting_eligibility_for_notes(&notes, BundlePolicy::default()).unwrap();

        assert!(status.is_eligible());
        assert_eq!(status.distinct_note_count, BUNDLE_NOTE_SLOTS);
        assert_eq!(status.eligible_weight, BALLOT_DIVISOR);
    }

    #[test]
    fn minimum_voting_eligibility_accepts_underfilled_padded_bundle() {
        let notes = vec![
            make_note(BALLOT_DIVISOR / 2, 0),
            make_note(BALLOT_DIVISOR / 2, 1),
        ];

        let status =
            validate_minimum_voting_eligibility_for_notes(&notes, BundlePolicy::default()).unwrap();

        assert!(status.is_eligible());
        assert_eq!(status.distinct_note_count, 2);
        assert_eq!(status.eligible_weight, BALLOT_DIVISOR);
    }

    #[test]
    fn minimum_voting_eligibility_rejects_many_notes_without_threshold_bundle() {
        let notes: Vec<NoteInfo> = (0..20).map(|i| make_note(2_000_000, i)).collect();

        let status = minimum_voting_eligibility_for_notes(&notes, BundlePolicy::default()).unwrap();
        let err = validate_minimum_voting_eligibility_for_notes(&notes, BundlePolicy::default())
            .unwrap_err();

        assert!(!status.is_eligible());
        assert_eq!(status.distinct_note_count, 0);
        assert_eq!(status.eligible_weight, 0);
        assert!(err
            .to_string()
            .contains("at least one eligible voting bundle"));

        let plan = chunk_notes(&notes);
        assert!(plan.bundles.is_empty());
        assert_eq!(plan.dropped_count, 20);
        assert_eq!(plan.eligible_weight, 0);
    }

    #[test]
    fn minimum_voting_eligibility_reports_empty_notes_as_ineligible_status() {
        let status = minimum_voting_eligibility_for_notes(&[], BundlePolicy::default()).unwrap();

        assert!(!status.is_eligible());
        assert_eq!(status.distinct_note_count, 0);
        assert_eq!(status.eligible_weight, 0);
    }

    #[test]
    fn minimum_voting_eligibility_accepts_single_large_note() {
        let notes = vec![make_note(BALLOT_DIVISOR * 4, 0)];

        let status =
            validate_minimum_voting_eligibility_for_notes(&notes, BundlePolicy::default()).unwrap();

        assert!(status.is_eligible());
        assert_eq!(status.distinct_note_count, 1);
        assert_eq!(status.eligible_weight, BALLOT_DIVISOR * 4);
    }

    #[test]
    fn minimum_voting_eligibility_deduplicates_notes_by_nullifier() {
        let note = make_note(BALLOT_DIVISOR, 0);
        let notes = vec![note; BUNDLE_NOTE_SLOTS];

        let status = minimum_voting_eligibility_for_notes(&notes, BundlePolicy::default()).unwrap();

        assert!(status.is_eligible());
        assert_eq!(status.distinct_note_count, 1);
        assert_eq!(status.eligible_weight, BALLOT_DIVISOR);
    }

    #[test]
    fn minimum_voting_eligibility_counts_only_surviving_bundle_notes() {
        let mut notes = vec![make_note(BALLOT_DIVISOR, 0)];
        notes.extend((1..BUNDLE_NOTE_SLOTS).map(|i| make_note(100, i as u64)));

        let status =
            minimum_voting_eligibility_for_notes(&notes, BundlePolicy::new(1).unwrap()).unwrap();

        assert!(status.is_eligible());
        assert_eq!(status.distinct_note_count, 1);
        assert_eq!(status.eligible_weight, BALLOT_DIVISOR);
    }

    #[test]
    fn test_chunk_notes_all_valid() {
        let notes: Vec<NoteInfo> = (0..BUNDLE_NOTE_SLOTS)
            .map(|i| make_note(13_000_000, i as u64))
            .collect();
        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.dropped_count, 0);
        let total = BUNDLE_NOTE_SLOTS as u64 * 13_000_000;
        assert_eq!(
            result.eligible_weight,
            (total / BALLOT_DIVISOR) * BALLOT_DIVISOR
        );
        assert_eq!(result.bundles[0].len(), BUNDLE_NOTE_SLOTS);
    }

    #[test]
    fn test_chunk_notes_dust_dropped() {
        let mut notes = vec![make_note(13_000_000, 0)];
        notes.extend((1..=BUNDLE_NOTE_SLOTS).map(|i| make_note(100, i as u64)));
        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.dropped_count, 1);
        assert_eq!(result.eligible_weight, 12_500_000);
        assert_eq!(result.bundles[0].len(), BUNDLE_NOTE_SLOTS);
    }

    #[test]
    fn test_chunk_notes_all_dust_empty() {
        let notes = vec![make_note(100, 0), make_note(200, 1), make_note(300, 2)];
        let result = chunk_notes(&notes);

        assert!(result.bundles.is_empty());
        assert_eq!(result.eligible_weight, 0);
        assert_eq!(result.dropped_count, 3);
    }

    #[test]
    fn test_chunk_notes_exact_threshold() {
        let notes = vec![make_note(BALLOT_DIVISOR, 0)];
        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.eligible_weight, BALLOT_DIVISOR);
        assert_eq!(result.dropped_count, 0);
    }

    #[test]
    fn test_chunk_notes_single_note() {
        let notes = vec![make_note(50_000_000, 42)];
        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.bundles[0].len(), 1);
        assert_eq!(result.bundles[0][0].position, 42);
        assert_eq!(result.eligible_weight, 50_000_000);
    }

    #[test]
    fn test_chunk_notes_deterministic() {
        let notes: Vec<NoteInfo> = (0..7)
            .map(|i| make_note(15_000_000 + i * 1_000_000, i))
            .collect();
        let r1 = chunk_notes(&notes);
        let r2 = chunk_notes(&notes);

        assert_eq!(r1.bundles.len(), r2.bundles.len());
        for (b1, b2) in r1.bundles.iter().zip(r2.bundles.iter()) {
            let p1: Vec<u64> = b1.iter().map(|n| n.position).collect();
            let p2: Vec<u64> = b2.iter().map(|n| n.position).collect();
            assert_eq!(p1, p2, "bundle positions must be deterministic");
        }
    }

    #[test]
    fn test_chunk_notes_position_ordering_within_bundles() {
        let notes = vec![
            make_note(20_000_000, 5),
            make_note(20_000_000, 1),
            make_note(20_000_000, 3),
            make_note(20_000_000, 7),
            make_note(20_000_000, 2),
        ];
        let result = chunk_notes(&notes);

        for bundle in &result.bundles {
            for window in bundle.windows(2) {
                assert!(
                    window[0].position < window[1].position,
                    "notes within bundle must be sorted by position"
                );
            }
        }
    }

    #[test]
    fn test_chunk_notes_bundles_sorted_by_value_desc() {
        let notes: Vec<NoteInfo> = (0..8).map(|i| make_note(15_000_000, i)).collect();
        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 2);
        let totals: Vec<u64> = result
            .bundles
            .iter()
            .map(|b| b.iter().map(|n| n.value).sum())
            .collect();
        assert!(
            totals[0] >= totals[1],
            "bundle 0 total ({}) must be >= bundle 1 total ({})",
            totals[0],
            totals[1]
        );

        let min_positions: Vec<u64> = result
            .bundles
            .iter()
            .map(|b| b.first().unwrap().position)
            .collect();
        assert!(
            min_positions[0] < min_positions[1],
            "equal-total bundles should be ordered by min position"
        );
    }

    #[test]
    fn test_chunk_notes_largest_bundle_first() {
        let mut notes = Vec::new();
        for i in 0..BUNDLE_NOTE_SLOTS {
            notes.push(make_note(50_000_000, 10 + i as u64));
        }
        for i in 0..BUNDLE_NOTE_SLOTS {
            notes.push(make_note(13_000_000, i as u64));
        }
        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 2);
        let total_0: u64 = result.bundles[0].iter().map(|n| n.value).sum();
        let total_1: u64 = result.bundles[1].iter().map(|n| n.value).sum();
        assert_eq!(total_0, BUNDLE_NOTE_SLOTS as u64 * 50_000_000);
        assert_eq!(total_1, BUNDLE_NOTE_SLOTS as u64 * 13_000_000);
        assert!(
            total_0 > total_1,
            "bundle 0 must have higher total than bundle 1"
        );
    }

    #[test]
    fn test_chunk_notes_empty() {
        let result = chunk_notes(&[]);

        assert!(result.bundles.is_empty());
        assert_eq!(result.eligible_weight, 0);
        assert_eq!(result.dropped_count, 0);
    }

    #[test]
    fn test_chunk_notes_default_capacity_per_bundle() {
        let notes: Vec<NoteInfo> = (0..12).map(|i| make_note(15_000_000, i)).collect();
        let result = chunk_notes(&notes);

        for bundle in &result.bundles {
            assert!(
                bundle.len() <= BUNDLE_NOTE_SLOTS,
                "bundle has {} notes, max is {}",
                bundle.len(),
                BUNDLE_NOTE_SLOTS
            );
        }
    }

    #[test]
    fn test_chunk_notes_one_real_note_per_bundle() {
        let notes: Vec<NoteInfo> = (0..BUNDLE_NOTE_SLOTS)
            .map(|i| make_note(13_000_000, i as u64))
            .collect();
        let policy = BundlePolicy::new(1).unwrap();

        let result = chunk_notes_with_policy(&notes, policy);

        assert_eq!(result.bundles.len(), BUNDLE_NOTE_SLOTS);
        assert_eq!(result.dropped_count, 0);
        assert_eq!(
            result.eligible_weight,
            BUNDLE_NOTE_SLOTS as u64 * BALLOT_DIVISOR
        );
        assert!(result.bundles.iter().all(|bundle| bundle.len() == 1));
    }

    #[test]
    fn test_chunk_notes_custom_capacity_drops_sub_threshold_tail() {
        let notes = vec![
            make_note(13_000_000, 0),
            make_note(13_000_000, 1),
            make_note(100, 2),
            make_note(100, 3),
            make_note(100, 4),
        ];
        let policy = BundlePolicy::new(2).unwrap();

        let result = chunk_notes_with_policy(&notes, policy);

        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.bundles[0].len(), 2);
        assert_eq!(result.dropped_count, 3);
        assert_eq!(result.eligible_weight, 25_000_000);
    }

    #[test]
    fn test_chunk_notes_starts_new_bundle_when_addition_would_exceed_threshold() {
        let threshold = 500 * BALLOT_DIVISOR;
        let notes = vec![
            make_note(500 * BALLOT_DIVISOR, 0),
            make_note(400 * BALLOT_DIVISOR, 1),
            make_note(200 * BALLOT_DIVISOR, 2),
        ];
        let policy = BundlePolicy::default().with_bundle_addition_threshold(threshold);

        let result = chunk_notes_with_policy(&notes, policy);
        let bundle_positions: Vec<Vec<u64>> = result
            .bundles
            .iter()
            .map(|bundle| bundle.iter().map(|note| note.position).collect())
            .collect();

        assert_eq!(result.bundles.len(), 3);
        assert_eq!(result.dropped_count, 0);
        assert_eq!(result.eligible_weight, 1_100 * BALLOT_DIVISOR);
        assert!(bundle_positions.contains(&vec![0]));
        assert!(bundle_positions.contains(&vec![1]));
        assert!(bundle_positions.contains(&vec![2]));
    }

    #[test]
    fn test_chunk_notes_keeps_exact_threshold_bundle_together() {
        let threshold = 500 * BALLOT_DIVISOR;
        let notes = vec![
            make_note(250 * BALLOT_DIVISOR, 0),
            make_note(200 * BALLOT_DIVISOR, 1),
            make_note(50 * BALLOT_DIVISOR, 2),
        ];
        let policy = BundlePolicy::default().with_bundle_addition_threshold(threshold);

        let result = chunk_notes_with_policy(&notes, policy);

        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.dropped_count, 0);
        assert_eq!(result.eligible_weight, 500 * BALLOT_DIVISOR);
        assert_eq!(result.bundles[0].len(), 3);
    }

    #[test]
    fn test_chunk_notes_does_not_split_small_notes_when_bundle_stays_under_threshold() {
        let threshold = 500 * BALLOT_DIVISOR;
        let notes: Vec<NoteInfo> = (0..(BUNDLE_NOTE_SLOTS * 2))
            .map(|i| make_note(100 * BALLOT_DIVISOR, i as u64))
            .collect();
        let policy = BundlePolicy::default().with_bundle_addition_threshold(threshold);

        let result = chunk_notes_with_policy(&notes, policy);

        assert_eq!(result.bundles.len(), 2);
        assert_eq!(result.dropped_count, 0);
        assert_eq!(result.eligible_weight, 1_000 * BALLOT_DIVISOR);
        assert!(result
            .bundles
            .iter()
            .all(|bundle| bundle.len() == BUNDLE_NOTE_SLOTS));
    }

    #[test]
    fn test_chunk_notes_splits_near_threshold_notes() {
        let threshold = 500 * BALLOT_DIVISOR;
        let notes: Vec<NoteInfo> = (0..BUNDLE_NOTE_SLOTS)
            .map(|i| make_note(499 * BALLOT_DIVISOR, i as u64))
            .collect();
        let policy = BundlePolicy::default().with_bundle_addition_threshold(threshold);

        let result = chunk_notes_with_policy(&notes, policy);

        assert_eq!(result.bundles.len(), BUNDLE_NOTE_SLOTS);
        assert_eq!(result.dropped_count, 0);
        assert_eq!(
            result.eligible_weight,
            (499 * BUNDLE_NOTE_SLOTS as u64) * BALLOT_DIVISOR
        );
        assert!(result.bundles.iter().all(|bundle| bundle.len() == 1));
    }

    #[test]
    fn test_chunk_notes_keeps_single_oversized_note_as_single_bundle() {
        let threshold = 500 * BALLOT_DIVISOR;
        let notes = vec![
            make_note(1_000 * BALLOT_DIVISOR, 0),
            make_note(100 * BALLOT_DIVISOR, 1),
        ];
        let policy = BundlePolicy::default().with_bundle_addition_threshold(threshold);

        let result = chunk_notes_with_policy(&notes, policy);
        let bundle_positions: Vec<Vec<u64>> = result
            .bundles
            .iter()
            .map(|bundle| bundle.iter().map(|note| note.position).collect())
            .collect();

        assert_eq!(result.bundles.len(), 2);
        assert_eq!(result.dropped_count, 0);
        assert_eq!(result.eligible_weight, 1_100 * BALLOT_DIVISOR);
        assert!(bundle_positions.contains(&vec![0]));
        assert!(bundle_positions.contains(&vec![1]));
    }

    #[test]
    fn bundle_policy_rejects_invalid_real_note_capacity() {
        assert!(BundlePolicy::new(0).is_err());
        assert!(BundlePolicy::new(BUNDLE_NOTE_SLOTS + 1).is_err());
        assert!(BundlePolicy::from_optional_max_real_notes_per_bundle(None).is_ok());
        assert!(BundlePolicy::from_optional_max_real_notes_per_bundle(Some(999)).is_err());
    }
}
