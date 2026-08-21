//! Smart note bundle planning for voting rounds.

#[allow(unused_imports)]
pub(crate) use crate::backend::{orchard, zcash_client_backend};
use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::{
    governance::{BALLOT_DIVISOR, BUNDLE_NOTE_SLOTS},
    types::{validate_notes_for_round, NoteInfo, SelectedNotes, VotingError},
};

/// Default full bundle size. Eligibility depends on quantized voting weight,
/// not on requiring this many real notes.
pub const MINIMUM_VOTING_NOTE_COUNT: usize = BUNDLE_NOTE_SLOTS;

/// Minimum quantized voting weight in zatoshi required before a wallet can vote.
pub const MINIMUM_VOTING_WEIGHT_ZATOSHI: u64 = BALLOT_DIVISOR;

/// Bundle count the privacy trim aims for when the drop budget allows it.
///
/// Bundle count is `ceil(note_count / BUNDLE_NOTE_SLOTS)`, so a holder whose
/// value sits in a few large notes plus a long dust tail emits many delegation
/// submissions that carry almost no voting weight. Trimming that tail shrinks
/// the observable submission count for exactly those holders.
pub const DEFAULT_MAX_PRIVACY_BUNDLES: usize = 2;

/// Default share of selected note value the privacy trim may discard, in basis
/// points. 100 bps is 1%.
pub const DEFAULT_PRIVACY_DROP_BPS: u32 = 100;

/// Maximum share of selected note value the privacy trim may discard, in basis
/// points. 500 bps is 5%.
pub const MAX_PRIVACY_DROP_BPS: u32 = 500;

/// Default absolute ceiling on raw note value discarded by the privacy trim.
///
/// One ZEC is 100,000,000 zatoshi, so this caps the default budget at 1,000 ZEC
/// even when 1% of the selected balance would be larger.
pub const DEFAULT_MAX_PRIVACY_DROP_ZATOSHI: u64 = 100_000_000_000;

/// Basis-point denominator. Kept explicit so the trim stays integer-only.
const BPS_DENOMINATOR: u128 = 10_000;

/// Controls how many real wallet notes are placed into each voting bundle.
///
/// Bundles with fewer than [`BUNDLE_NOTE_SLOTS`] real notes are still padded
/// later by the proof construction path. This policy only controls how many
/// selected wallet notes can appear in one real bundle.
///
/// Serialized with every round so the plan re-derives identically after an SDK
/// upgrade that changes the defaults.
///
/// # Persisted schema
///
/// Round storage does not serialize this type directly. It uses a strict,
/// versioned persistence DTO so a newly added policy field cannot silently
/// change an older round. Any extension here must add the corresponding field
/// to a new persisted schema version and define its conversion explicitly.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "UncheckedBundlePolicy")]
pub struct BundlePolicy {
    max_real_notes_per_bundle: usize,
    bundle_addition_threshold_zatoshi: Option<u64>,
    /// Missing from policies serialized before privacy trimming shipped.
    ///
    /// Treating absence as disabled preserves the behavior of those policies
    /// instead of silently applying the current trim defaults on deserialization.
    privacy_trim: Option<PrivacyTrimPolicy>,
}

/// Deserialization shape for [`BundlePolicy`].
///
/// Serde must not construct the public policy directly because doing so would
/// bypass the capacity and privacy-budget validation enforced by its builders.
#[derive(Deserialize)]
struct UncheckedBundlePolicy {
    max_real_notes_per_bundle: usize,
    bundle_addition_threshold_zatoshi: Option<u64>,
    #[serde(default)]
    privacy_trim: Option<PrivacyTrimPolicy>,
}

impl TryFrom<UncheckedBundlePolicy> for BundlePolicy {
    type Error = VotingError;

    fn try_from(value: UncheckedBundlePolicy) -> Result<Self, Self::Error> {
        let mut policy = Self::new(value.max_real_notes_per_bundle)?;
        if let Some(threshold) = value.bundle_addition_threshold_zatoshi {
            policy = policy.with_bundle_addition_threshold(threshold);
        }

        let Some(privacy_trim) = value.privacy_trim else {
            return Ok(policy.with_max_privacy_bundles(None));
        };

        Ok(policy
            .with_max_privacy_bundles(Some(privacy_trim.max_bundles))
            .with_privacy_drop_bps(privacy_trim.drop_bps)?
            .with_max_privacy_drop_zatoshi(privacy_trim.max_drop_zatoshi))
    }
}

/// Configuration for dropping a low-value bundle tail.
///
/// This is optional on [`BundlePolicy`]: `None` disables privacy trimming,
/// while `Some` keeps the target and both budget limits together.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PrivacyTrimPolicy {
    max_bundles: usize,
    drop_bps: u32,
    max_drop_zatoshi: Option<u64>,
}

impl Default for PrivacyTrimPolicy {
    fn default() -> Self {
        Self {
            max_bundles: DEFAULT_MAX_PRIVACY_BUNDLES,
            drop_bps: DEFAULT_PRIVACY_DROP_BPS,
            max_drop_zatoshi: Some(DEFAULT_MAX_PRIVACY_DROP_ZATOSHI),
        }
    }
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
                ..Self::default()
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

    /// Returns a copy of this policy with an explicit privacy bundle target.
    ///
    /// `None` disables the privacy trim entirely, which is what in-flight rounds
    /// created before the trim shipped must use so their persisted bundle rows
    /// still re-derive. A target of zero is treated as one because privacy
    /// trimming must preserve at least one eligible bundle.
    pub fn with_max_privacy_bundles(mut self, max_privacy_bundles: Option<usize>) -> Self {
        self.privacy_trim = max_privacy_bundles.map(|max_bundles| {
            let mut privacy_trim = self.privacy_trim.unwrap_or_default();
            privacy_trim.max_bundles = max_bundles;
            privacy_trim
        });
        self
    }

    /// Returns a copy of this policy with an explicit privacy drop budget, in
    /// basis points of total selected note value.
    ///
    /// This has no effect while privacy trimming is disabled.
    ///
    /// # Errors
    ///
    /// Returns [`VotingError::InvalidInput`] when `privacy_drop_bps` is greater
    /// than [`MAX_PRIVACY_DROP_BPS`] (5% of selected note value).
    pub fn with_privacy_drop_bps(mut self, privacy_drop_bps: u32) -> Result<Self, VotingError> {
        if privacy_drop_bps > MAX_PRIVACY_DROP_BPS {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "privacy_drop_bps must be <= {MAX_PRIVACY_DROP_BPS}, got {privacy_drop_bps}"
                ),
            });
        }
        if let Some(privacy_trim) = &mut self.privacy_trim {
            privacy_trim.drop_bps = privacy_drop_bps;
        }
        Ok(self)
    }

    /// Returns a copy of this policy with an absolute clamp on the privacy drop.
    ///
    /// The effective budget becomes `min(bps_budget, clamp)`. Passing `None`
    /// removes the default 1,000 ZEC ceiling. This has no effect while privacy
    /// trimming is disabled.
    pub fn with_max_privacy_drop_zatoshi(mut self, max_privacy_drop_zatoshi: Option<u64>) -> Self {
        if let Some(privacy_trim) = &mut self.privacy_trim {
            privacy_trim.max_drop_zatoshi = max_privacy_drop_zatoshi;
        }
        self
    }

    /// Returns the bundle count the privacy trim aims for, if it is enabled.
    pub fn max_privacy_bundles(self) -> Option<usize> {
        self.privacy_trim
            .map(|privacy_trim| privacy_trim.max_bundles)
    }

    /// Returns the privacy drop budget in basis points of selected note value.
    pub fn privacy_drop_bps(self) -> u32 {
        self.privacy_trim
            .map(|privacy_trim| privacy_trim.drop_bps)
            .unwrap_or(DEFAULT_PRIVACY_DROP_BPS)
    }

    /// Returns the optional absolute clamp on the privacy drop budget.
    pub fn max_privacy_drop_zatoshi(self) -> Option<u64> {
        self.privacy_trim
            .map(|privacy_trim| privacy_trim.max_drop_zatoshi)
            .unwrap_or(Some(DEFAULT_MAX_PRIVACY_DROP_ZATOSHI))
    }

    /// Returns the privacy drop budget in zatoshi for a given total note value.
    ///
    /// The budget is `total_value * privacy_drop_bps / 10_000`, further clamped
    /// by [`BundlePolicy::max_privacy_drop_zatoshi`] when one is set. Integer
    /// math throughout, so the returned budget never exceeds the intended share.
    fn privacy_drop_budget(self, total_value: u128) -> u128 {
        let Some(privacy_trim) = self.privacy_trim else {
            return 0;
        };
        let budget = total_value * u128::from(privacy_trim.drop_bps) / BPS_DENOMINATOR;
        match privacy_trim.max_drop_zatoshi {
            Some(clamp) => budget.min(u128::from(clamp)),
            None => budget,
        }
    }
}

impl Default for BundlePolicy {
    fn default() -> Self {
        Self {
            max_real_notes_per_bundle: BUNDLE_NOTE_SLOTS,
            bundle_addition_threshold_zatoshi: None,
            privacy_trim: Some(PrivacyTrimPolicy::default()),
        }
    }
}

/// What the privacy trim removed from a bundle plan.
///
/// Reported separately from the sub-ballot drop because the two mean different
/// things to a voter: sub-ballot notes were already worth zero ballots, while
/// these bundles carried selected note value that was excluded in exchange for
/// emitting fewer delegation submissions. [`PrivacyTrim::dropped_value`] is the
/// raw value of those notes, not their bundle-quantized voting weight.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct PrivacyTrim {
    /// Bundles removed to shrink the observable submission count.
    pub dropped_bundles: u32,
    /// Notes inside the removed bundles.
    pub dropped_notes: u32,
    /// Raw zatoshi value inside the removed bundles.
    #[serde(rename = "dropped_value_zatoshi")]
    pub dropped_value: u64,
}

impl PrivacyTrim {
    /// Returns whether the trim left the plan untouched.
    pub fn is_empty(self) -> bool {
        self.dropped_bundles == 0
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
    /// What the privacy trim removed, if anything.
    pub privacy_trim: PrivacyTrim,
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

/// Returns quantized zatoshi voting power under the current default policy.
///
/// This helper does not consult persisted round state. Use
/// [`voting_power_for_round`] when reporting power for an existing round.
pub fn voting_power(notes: &SelectedNotes) -> u64 {
    voting_power_with_policy(notes, BundlePolicy::default())
}

/// Returns quantized zatoshi voting power using the policy authoritative for
/// `round_id`.
///
/// Wallet setup persists the effective policy before this helper is used.
pub fn voting_power_for_round(
    notes: &SelectedNotes,
    voting_db: &crate::round::VotingDb,
    round_id: &str,
) -> Result<u64, VotingError> {
    let policy = voting_db.effective_bundle_policy(round_id, BundlePolicy::default())?;
    Ok(voting_power_with_policy(notes, policy))
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

/// Returns the eligibility status and the bundle plan it was derived from.
///
/// [`minimum_voting_eligibility_for_notes`] reports only the weight that
/// survives planning, so a wallet that also needs the privacy trim would have
/// to plan a second time to see it. Planning twice is how the reported weight
/// and the reported loss drift apart, and repeating the canonical
/// duplicate-nullifier collapse in the wallet is how they start describing
/// different note sets. Use this when both numbers are shown together.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] if any note row is malformed.
pub fn minimum_voting_eligibility_and_plan_for_notes(
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
/// 7. Drop trailing bundles down to the policy's privacy bundle target, while
///    the discarded value stays inside the policy's drop budget
///
/// Sequential packing concentrates high-value notes in early bundles, so dust
/// notes naturally end up in the last (smallest) bundles. Those either fall
/// below BALLOT_DIVISOR and drop for free in step 4, or become the cheapest
/// candidates for the step 7 privacy trim. Value-descending bundle order also
/// lets Keystone users sign the most valuable bundles first and optionally skip
/// the remaining low-value ones.
///
/// Note that this ordering is not chosen to minimize quantization loss; spreading
/// notes across bundles can recover slightly more weight. It is chosen so that
/// the low-value tail is contiguous and droppable.
pub fn chunk_notes_with_policy(notes: &[NoteInfo], policy: BundlePolicy) -> ChunkResult {
    if notes.is_empty() {
        return ChunkResult {
            bundles: vec![],
            eligible_weight: 0,
            dropped_count: 0,
            privacy_trim: PrivacyTrim::default(),
        };
    }

    // The privacy drop budget is a share of the balance the voter selected, so
    // it is measured against every note handed in, including notes that step 4
    // later drops for being worth zero ballots.
    let total_value: u128 = notes.iter().map(|note| u128::from(note.value)).sum();

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

    // Step 7: Privacy trim. Bundle count is `ceil(note_count / BUNDLE_NOTE_SLOTS)`,
    // so a holder whose value sits in a few large notes plus a long dust tail
    // emits many delegation submissions that carry almost no voting weight.
    // Bundles are value-DESC here, so the last one is always the cheapest way to
    // shed a submission, and popping greedily yields the smallest bundle count
    // reachable within the budget.
    let mut privacy_trim = PrivacyTrim::default();
    let mut privacy_dropped_value: u128 = 0;

    if let Some(max_privacy_bundles) = policy.max_privacy_bundles() {
        let budget = policy.privacy_drop_budget(total_value);
        // Keep at least one eligible bundle even if a zero target is configured.
        let max_privacy_bundles = max_privacy_bundles.max(1);
        while surviving.len() > max_privacy_bundles {
            let bundle_total = surviving.last().expect("bundle exists").0;
            let bundle_value = u128::from(bundle_total);
            if privacy_dropped_value + bundle_value > budget {
                break;
            }
            let (_, bundle) = surviving.pop().expect("bundle exists");
            privacy_dropped_value += bundle_value;
            privacy_trim.dropped_bundles += 1;
            privacy_trim.dropped_notes += bundle.len() as u32;
            // Safe: this bundle's quantized weight was added in step 4.
            eligible_weight -= (bundle_total / BALLOT_DIVISOR) * BALLOT_DIVISOR;
        }
        privacy_trim.dropped_value = u64::try_from(privacy_dropped_value).unwrap_or(u64::MAX);
    }

    ChunkResult {
        bundles: surviving.into_iter().map(|(_, b)| b).collect(),
        eligible_weight,
        dropped_count,
        privacy_trim,
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

    #[test]
    fn eligibility_and_plan_describe_the_same_bundle_set() {
        // The published pair exists so a wallet showing weight and withheld
        // value together gets both from one plan. Pin that they agree, and
        // that duplicate nullifiers collapse once for both.
        let big = 1_000 * BALLOT_DIVISOR;
        let mut notes: Vec<NoteInfo> = (0..3).map(|i| make_note(big, i)).collect();
        notes.extend((3..23).map(|i| make_note(big / 500, i)));
        notes.extend(notes.clone());

        let (eligibility, plan) =
            minimum_voting_eligibility_and_plan_for_notes(&notes, BundlePolicy::default()).unwrap();

        assert!(plan.privacy_trim.dropped_value > 0, "fixture must trim");
        assert_eq!(eligibility.eligible_weight, plan.eligible_weight);
        assert_eq!(
            eligibility.distinct_note_count,
            plan.bundles.iter().map(Vec::len).sum::<usize>()
        );
        assert_eq!(
            eligibility,
            minimum_voting_eligibility_for_notes(&notes, BundlePolicy::default()).unwrap(),
            "the pair must not report a different status than the single helper"
        );
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

    #[test]
    fn bundle_policy_rejects_privacy_drop_bps_above_max() {
        assert!(BundlePolicy::default()
            .with_privacy_drop_bps(MAX_PRIVACY_DROP_BPS)
            .is_ok());
        assert!(BundlePolicy::default()
            .with_privacy_drop_bps(MAX_PRIVACY_DROP_BPS + 1)
            .is_err());
    }

    #[test]
    fn bundle_policy_decodes_pre_privacy_trim_json_with_trimming_disabled() {
        let legacy = serde_json::json!({
            "max_real_notes_per_bundle": 3,
            "bundle_addition_threshold_zatoshi": 42
        });

        let policy: BundlePolicy = serde_json::from_value(legacy).unwrap();

        assert_eq!(policy.max_real_notes_per_bundle(), 3);
        assert_eq!(policy.bundle_addition_threshold(), Some(42));
        assert_eq!(policy.max_privacy_bundles(), None);
    }

    #[test]
    fn bundle_policy_json_round_trips_nested_privacy_trim_policy() {
        let policy = BundlePolicy::new(2)
            .unwrap()
            .with_max_privacy_bundles(Some(3))
            .with_privacy_drop_bps(75)
            .unwrap()
            .with_max_privacy_drop_zatoshi(Some(99));

        let json = serde_json::to_value(policy).unwrap();

        assert_eq!(json["privacy_trim"]["max_bundles"], 3);
        assert_eq!(json["privacy_trim"]["drop_bps"], 75);
        assert_eq!(json["privacy_trim"]["max_drop_zatoshi"], 99);
        assert_eq!(
            serde_json::from_value::<BundlePolicy>(json).unwrap(),
            policy
        );
    }

    #[test]
    fn bundle_policy_json_rejects_invalid_real_note_capacity() {
        for capacity in [0, BUNDLE_NOTE_SLOTS + 1] {
            let json = serde_json::json!({
                "max_real_notes_per_bundle": capacity,
                "bundle_addition_threshold_zatoshi": null,
                "privacy_trim": null
            });

            let error = serde_json::from_value::<BundlePolicy>(json).unwrap_err();
            assert!(
                error
                    .to_string()
                    .contains("max_real_notes_per_bundle must be in"),
                "{error}"
            );
        }
    }

    #[test]
    fn bundle_policy_json_rejects_privacy_drop_bps_above_max() {
        let json = serde_json::json!({
            "max_real_notes_per_bundle": BUNDLE_NOTE_SLOTS,
            "bundle_addition_threshold_zatoshi": null,
            "privacy_trim": {
                "max_bundles": 1,
                "drop_bps": MAX_PRIVACY_DROP_BPS + 1,
                "max_drop_zatoshi": null
            }
        });

        let error = serde_json::from_value::<BundlePolicy>(json).unwrap_err();
        assert!(
            error.to_string().contains("privacy_drop_bps must be <="),
            "{error}"
        );
    }

    const ZEC: u64 = 100_000_000;
    const WHALE_PROTECTION_THRESHOLD: u64 = 1_000 * ZEC;

    /// Builds a holder whose value is concentrated in `large_count` notes of
    /// `large_value`, followed by a long tail of equal dust notes.
    fn concentrated_notes_with_dust_tail(
        large_count: usize,
        large_value: u64,
        dust_count: usize,
        dust_value: u64,
    ) -> Vec<NoteInfo> {
        (0..large_count)
            .map(|i| make_note(large_value, i as u64))
            .chain((0..dust_count).map(|i| make_note(dust_value, (large_count + i) as u64)))
            .collect()
    }

    fn total_value(notes: &[NoteInfo]) -> u64 {
        notes.iter().map(|note| note.value).sum()
    }

    #[test]
    fn privacy_trim_collapses_concentrated_whale_with_dust_tail() {
        // 8 x 500 ZEC plus 190 dust notes of 0.1 ZEC: 4019 ZEC over 40 bundles.
        let notes = concentrated_notes_with_dust_tail(8, 500 * ZEC, 190, ZEC / 10);
        let balance = total_value(&notes);

        let untrimmed = chunk_notes_with_policy(
            &notes,
            BundlePolicy::default().with_max_privacy_bundles(None),
        );
        let trimmed = chunk_notes(&notes);

        // Exact counts, cross-checked against the standalone model in
        // scratchpad/sim2.py: 40 bundles collapse to 2 for 18.80 of 4019 ZEC,
        // well inside the 40.19 ZEC budget.
        assert_eq!(untrimmed.bundles.len(), 40);
        assert_eq!(trimmed.bundles.len(), DEFAULT_MAX_PRIVACY_BUNDLES);
        assert_eq!(trimmed.privacy_trim.dropped_value, 1_880_000_000);
        assert_eq!(
            trimmed.privacy_trim.dropped_bundles as usize,
            untrimmed.bundles.len() - trimmed.bundles.len()
        );
        // The budget is a hard ceiling, and the weight report stays consistent.
        assert!(u128::from(trimmed.privacy_trim.dropped_value) <= u128::from(balance) / 100);
        assert!(trimmed.eligible_weight < untrimmed.eligible_weight);
        assert!(trimmed.privacy_trim.dropped_notes > 0);
    }

    #[test]
    fn privacy_trim_leaves_whale_protection_bundles_intact() {
        // Same holder under vizor's 1000 ZEC per-bundle cap. The trim should
        // still shed the dust tail, but must not touch a full-weight bundle:
        // 1% of 4019 ZEC cannot pay for a bundle worth ~1000 ZEC.
        let notes = concentrated_notes_with_dust_tail(8, 500 * ZEC, 190, ZEC / 10);
        let policy =
            BundlePolicy::default().with_bundle_addition_threshold(WHALE_PROTECTION_THRESHOLD);

        let untrimmed = chunk_notes_with_policy(&notes, policy.with_max_privacy_bundles(None));
        let trimmed = chunk_notes_with_policy(&notes, policy);

        // Same model: the cap raises the untrimmed count to 42, and the trim
        // can only reach 4 because each surviving bundle holds ~1000 ZEC.
        assert_eq!(untrimmed.bundles.len(), 42);
        assert_eq!(trimmed.bundles.len(), 4);
        assert_eq!(trimmed.privacy_trim.dropped_value, 1_900_000_000);
        // Every large bundle survives; only sub-threshold tail bundles went.
        let surviving_big = trimmed
            .bundles
            .iter()
            .filter(|bundle| {
                bundle.iter().map(|note| note.value).sum::<u64>() > WHALE_PROTECTION_THRESHOLD / 2
            })
            .count();
        let untrimmed_big = untrimmed
            .bundles
            .iter()
            .filter(|bundle| {
                bundle.iter().map(|note| note.value).sum::<u64>() > WHALE_PROTECTION_THRESHOLD / 2
            })
            .count();
        assert_eq!(surviving_big, untrimmed_big);
        assert!(
            u128::from(trimmed.privacy_trim.dropped_value) <= u128::from(total_value(&notes)) / 100
        );
    }

    #[test]
    fn privacy_trim_leaves_uniform_note_whale_untouched() {
        // 200 x 50 ZEC: every bundle is worth 250 ZEC, far past a 100 ZEC budget.
        let notes: Vec<NoteInfo> = (0..200).map(|i| make_note(50 * ZEC, i as u64)).collect();

        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 40);
        assert_eq!(result.privacy_trim.dropped_bundles, 0);
        assert_eq!(result.privacy_trim.dropped_value, 0);
    }

    #[test]
    fn privacy_trim_leaves_small_uniform_balance_untouched() {
        // 50 x 0.125 ZEC form 10 bundles worth 0.625 ZEC each. The total
        // balance is 6.25 ZEC, so its 1% budget cannot pay for any bundle.
        let notes: Vec<NoteInfo> = (0..50).map(|i| make_note(ZEC / 8, i as u64)).collect();

        let result = chunk_notes(&notes);

        assert_eq!(result.bundles.len(), 10);
        assert_eq!(result.privacy_trim.dropped_bundles, 0);
        assert_eq!(result.privacy_trim.dropped_notes, 0);
        assert_eq!(result.privacy_trim.dropped_value, 0);
    }

    #[test]
    fn privacy_trim_leaves_large_uniform_bundles_untouched_under_whale_protection() {
        // 10 x 1000 ZEC under the 1000 ZEC cap: one note per bundle, and no
        // bundle is affordable within 1% of 10_000 ZEC.
        let notes: Vec<NoteInfo> = (0..10).map(|i| make_note(1_000 * ZEC, i as u64)).collect();
        let policy =
            BundlePolicy::default().with_bundle_addition_threshold(WHALE_PROTECTION_THRESHOLD);

        let result = chunk_notes_with_policy(&notes, policy);

        assert_eq!(result.bundles.len(), 10);
        assert_eq!(result.privacy_trim.dropped_bundles, 0);
    }

    #[test]
    fn privacy_trim_preserves_the_downstream_whale_protection_shape() {
        // Mirrors vizor-wallet's
        // `whale_protection_starts_new_bundle_when_addition_would_cross_threshold`,
        // which pins exact bundle counts and positions. Keeping it here means a
        // change to the trim cannot silently break that downstream assertion.
        let notes = vec![
            make_note(WHALE_PROTECTION_THRESHOLD, 1),
            make_note(400 * ZEC, 2),
            make_note(200 * ZEC, 3),
        ];

        let default_plan = chunk_notes(&notes);
        assert_eq!(default_plan.bundles[0].len(), 3);
        assert!(default_plan.privacy_trim.is_empty());

        let protected = chunk_notes_with_policy(
            &notes,
            BundlePolicy::default().with_bundle_addition_threshold(WHALE_PROTECTION_THRESHOLD),
        );
        let positions: Vec<Vec<u64>> = protected
            .bundles
            .iter()
            .map(|bundle| bundle.iter().map(|note| note.position).collect())
            .collect();

        assert_eq!(protected.bundles.len(), 2);
        assert!(positions.contains(&vec![1]));
        assert!(positions.contains(&vec![2, 3]));
        assert!(protected.privacy_trim.is_empty());
    }

    #[test]
    fn privacy_trim_is_a_no_op_at_or_below_the_bundle_target() {
        for bundle_count in 1..=DEFAULT_MAX_PRIVACY_BUNDLES {
            let notes: Vec<NoteInfo> = (0..bundle_count * BUNDLE_NOTE_SLOTS)
                .map(|i| make_note(BALLOT_DIVISOR, i as u64))
                .collect();

            let result = chunk_notes(&notes);

            assert_eq!(result.bundles.len(), bundle_count);
            assert_eq!(result.privacy_trim.dropped_bundles, 0);
            assert_eq!(result.privacy_trim.dropped_notes, 0);
            assert_eq!(result.privacy_trim.dropped_value, 0);
        }
    }

    #[test]
    fn privacy_trim_budget_boundary_is_inclusive() {
        // Three bundles of one note each. The tail bundle is priced exactly at
        // the 1% budget, then one zatoshi above it.
        let big = 1_000 * BALLOT_DIVISOR;
        let policy = BundlePolicy::new(1).unwrap();

        // total = 2 * big + tail, and we want tail == total / 100.
        // Solving: tail = 2 * big / 99 (integer division keeps tail <= budget).
        let tail = 2 * big / 99;
        let at_budget = vec![make_note(big, 0), make_note(big, 1), make_note(tail, 2)];
        let over_budget = vec![
            make_note(big, 0),
            make_note(big, 1),
            make_note(tail + 100, 2),
        ];

        let at = chunk_notes_with_policy(&at_budget, policy);
        let over = chunk_notes_with_policy(&over_budget, policy);

        assert_eq!(at.bundles.len(), 2, "a bundle exactly at budget is dropped");
        assert_eq!(at.privacy_trim.dropped_bundles, 1);
        assert_eq!(at.privacy_trim.dropped_value, tail);
        assert_eq!(over.bundles.len(), 3, "one zatoshi over budget is kept");
        assert_eq!(over.privacy_trim.dropped_bundles, 0);
    }

    #[test]
    fn privacy_trim_default_budget_is_capped_at_1000_zec() {
        // A 1,000,000 ZEC holder has a 10,000 ZEC percentage budget. The default
        // absolute ceiling limits the trim to one 1,000 ZEC bundle. Callers can
        // explicitly remove the ceiling or set a tighter one.
        let notes: Vec<NoteInfo> = (0..1_000)
            .map(|i| make_note(1_000 * ZEC, i as u64))
            .collect();
        let policy =
            BundlePolicy::default().with_bundle_addition_threshold(WHALE_PROTECTION_THRESHOLD);

        let default_capped = chunk_notes_with_policy(&notes, policy);
        let uncapped = chunk_notes_with_policy(&notes, policy.with_max_privacy_drop_zatoshi(None));
        let tighter_cap = chunk_notes_with_policy(
            &notes,
            policy.with_max_privacy_drop_zatoshi(Some(100 * ZEC)),
        );

        assert_eq!(default_capped.bundles.len(), 999);
        assert_eq!(default_capped.privacy_trim.dropped_bundles, 1);
        assert_eq!(
            default_capped.privacy_trim.dropped_value,
            DEFAULT_MAX_PRIVACY_DROP_ZATOSHI
        );
        assert_eq!(uncapped.bundles.len(), 990, "1% pays for ten bundles");
        assert_eq!(uncapped.privacy_trim.dropped_bundles, 10);
        assert_eq!(
            tighter_cap.bundles.len(),
            1_000,
            "a 100 ZEC cap blocks a 1,000 ZEC bundle"
        );
        assert_eq!(tighter_cap.privacy_trim.dropped_bundles, 0);
    }

    #[test]
    fn privacy_trim_never_drops_below_minimum_voting_eligibility() {
        // Worst case for the floor: a zero target and a budget large enough to
        // pay for everything. The trim must still leave one bundle standing,
        // so the voter stays eligible.
        //
        // Construct the oversize budget via private fields: the public setter
        // caps drop_bps at MAX_PRIVACY_DROP_BPS, which cannot cover dropping
        // every eligible bundle.
        let notes: Vec<NoteInfo> = (0..50)
            .map(|i| make_note(BALLOT_DIVISOR, i as u64))
            .collect();
        let policy = BundlePolicy {
            max_real_notes_per_bundle: BUNDLE_NOTE_SLOTS,
            bundle_addition_threshold_zatoshi: None,
            privacy_trim: Some(PrivacyTrimPolicy {
                max_bundles: 0,
                drop_bps: 10_000,
                max_drop_zatoshi: None,
            }),
        };

        let result = chunk_notes_with_policy(&notes, policy);
        let eligibility = minimum_voting_eligibility_for_notes(&notes, policy).unwrap();

        assert_eq!(result.bundles.len(), 1);
        assert!(result.eligible_weight >= MINIMUM_VOTING_WEIGHT_ZATOSHI);
        assert!(eligibility.is_eligible());
    }

    #[test]
    fn privacy_trim_reports_weight_consistently_with_surviving_bundles() {
        let notes = concentrated_notes_with_dust_tail(8, 500 * ZEC, 190, ZEC / 10);

        let result = chunk_notes(&notes);

        // eligible_weight must describe exactly the bundles that survived.
        let recomputed: u64 = result
            .bundles
            .iter()
            .map(|bundle| {
                let total: u64 = bundle.iter().map(|note| note.value).sum();
                (total / BALLOT_DIVISOR) * BALLOT_DIVISOR
            })
            .sum();
        assert_eq!(result.eligible_weight, recomputed);
    }

    #[test]
    fn privacy_trim_is_deterministic_across_repeated_planning() {
        // ensure_bundles re-derives the plan and requires identical bundle
        // identities, so the trim must be a pure function of notes and policy.
        let notes = concentrated_notes_with_dust_tail(8, 500 * ZEC, 190, ZEC / 10);

        let first = chunk_notes(&notes);
        let second = chunk_notes(&notes);
        let mut shuffled = notes.clone();
        shuffled.reverse();
        let third = chunk_notes(&shuffled);

        assert_eq!(first, second);
        assert_eq!(first, third, "input order must not change the plan");
    }
}
