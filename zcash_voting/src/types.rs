use subtle::CtOption;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum VotingError {
    #[error("Invalid input: {message}")]
    InvalidInput { message: String },
    #[error("Proof generation failed: {message}")]
    ProofFailed { message: String },
    #[error("Internal error: {message}")]
    Internal { message: String },
}

/// Unwrap a `CtOption`, returning a `VotingError` on `None`.
pub fn ct_option_to_result<T>(opt: CtOption<T>, msg: &str) -> Result<T, VotingError> {
    if opt.is_some().into() {
        Ok(opt.unwrap())
    } else {
        Err(VotingError::Internal {
            message: msg.to_string(),
        })
    }
}

/// Voting hotkey pair. secret_key must be 32 bytes (Pallas scalar).
#[derive(Clone, Debug)]
pub struct VotingHotkey {
    pub secret_key: Vec<u8>,
    pub public_key: Vec<u8>,
    pub address: String,
}

/// A shielded Orchard note from the wallet DB, containing all fields needed
/// for delegation proof construction and governance PCZT building.
#[derive(Clone, Debug)]
pub struct NoteInfo {
    /// Extracted note commitment (cmx), recomputed from note parts.
    pub commitment: Vec<u8>,
    /// Nullifier (32 bytes).
    pub nullifier: Vec<u8>,
    /// Note value in zatoshis.
    pub value: u64,
    /// Position in the note commitment tree.
    pub position: u64,
    /// Diversifier bytes (11 bytes).
    pub diversifier: Vec<u8>,
    /// Rho field (32 bytes, LE encoding of pallas::Base).
    pub rho: Vec<u8>,
    /// Random seed (32 bytes).
    pub rseed: Vec<u8>,
    /// Key scope: 0 = external, 1 = internal.
    pub scope: u32,
    /// Unified full viewing key string for this note's account.
    pub ufvk_str: String,
}

/// Parameters for a voting round, sourced from vote chain.
#[derive(Clone, Debug)]
pub struct VotingRoundParams {
    pub vote_round_id: String,
    pub snapshot_height: u64,
    pub ea_pk: Vec<u8>,
    pub nc_root: Vec<u8>,
    pub nullifier_imt_root: Vec<u8>,
}

/// Delegation action for Keystone signing.
#[derive(Clone, Debug)]
pub struct DelegationAction {
    pub action_bytes: Vec<u8>,
    pub rk: Vec<u8>,
    /// Governance nullifiers, always padded to 5.
    pub gov_nullifiers: Vec<Vec<u8>>,
    /// 32-byte governance commitment (VAN).
    pub van: Vec<u8>,
    /// 32-byte blinding factor used for VAN (must be persisted for later use).
    pub van_comm_rand: Vec<u8>,
    /// Nullifiers for zero-value padded notes (needed for circuit witness in later steps).
    pub dummy_nullifiers: Vec<Vec<u8>>,
    /// Constrained rho for the signed note (32 bytes). Spec §1.3.4.1.
    pub rho_signed: Vec<u8>,
    /// Extracted note commitments (cmx) for padded dummy notes.
    /// Needed for ZKP witness construction in later steps.
    pub padded_cmx: Vec<Vec<u8>>,
    /// Signed note nullifier (32 bytes). Public input to ZKP #1.
    pub nf_signed: Vec<u8>,
    /// Output note commitment (32 bytes). Public input to ZKP #1.
    pub cmx_new: Vec<u8>,
    /// Spend auth randomizer scalar (32 bytes). Needed for Keystone signing.
    pub alpha: Vec<u8>,
    /// Spend authorization signature over `sighash` (64 bytes), supplied after Keystone signing.
    pub spend_auth_sig: Option<Vec<u8>>,
    /// Signed note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_signed: Vec<u8>,
    /// Output note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_output: Vec<u8>,
}

/// Governance PCZT for Keystone signing.
///
/// Contains a serialized PCZT whose single Orchard action IS the governance
/// dummy action (spend of signed note → output to hotkey). The PCZT's rk and
/// ZIP-244 sighash are internally consistent, so Keystone's SpendAuth signature
/// will verify against them.
#[derive(Clone, Debug)]
pub struct GovernancePczt {
    /// Serialized PCZT bytes ready for UR-encoding and Keystone signing.
    pub pczt_bytes: Vec<u8>,
    /// Randomized verification key (32 bytes). Extracted from the PCZT spend action.
    pub rk: Vec<u8>,
    /// Spend auth randomizer scalar (32 bytes). Needed for ZKP witness.
    pub alpha: Vec<u8>,
    /// Signed note nullifier (32 bytes). Public input to ZKP #1.
    pub nf_signed: Vec<u8>,
    /// Output note commitment (32 bytes). Public input to ZKP #1.
    pub cmx_new: Vec<u8>,
    /// Governance nullifiers, always padded to 5.
    pub gov_nullifiers: Vec<Vec<u8>>,
    /// 32-byte governance commitment (VAN).
    pub van: Vec<u8>,
    /// 32-byte blinding factor used for VAN (must be persisted for later use).
    pub van_comm_rand: Vec<u8>,
    /// Nullifiers for zero-value padded notes (needed for circuit witness).
    pub dummy_nullifiers: Vec<Vec<u8>>,
    /// Constrained rho for the signed note (32 bytes). Spec §1.3.4.1.
    pub rho_signed: Vec<u8>,
    /// Extracted note commitments (cmx) for padded dummy notes.
    pub padded_cmx: Vec<Vec<u8>>,
    /// Signed note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_signed: Vec<u8>,
    /// Output note rseed (32 bytes). Needed for witness reconstruction.
    pub rseed_output: Vec<u8>,
    /// Canonical delegation action payload for cosmos chain submission.
    pub action_bytes: Vec<u8>,
    /// Index of the paired governance action whose spend and output produce
    /// `nf_signed`, `rk`, `alpha`, and `cmx_new`.
    /// (Actions are padded/shuffled by the Builder.)
    pub action_index: usize,
    /// Padded note secrets: N_padded * 64 bytes (32 rho + 32 rseed per padded note).
    /// Needed to thread Phase 1 randomness to Phase 2 (ZCA-74 fix).
    pub padded_note_secrets: Vec<(Vec<u8>, Vec<u8>)>,
    /// ZIP-244 sighash extracted from the PCZT (32 bytes).
    /// Both Keystone and non-Keystone paths sign this.
    pub pczt_sighash: Vec<u8>,
}

/// El Gamal ciphertext of a voting share.
///
/// SECURITY: `plaintext_value` and `randomness` are secret client-side fields.
/// Only `c1`, `c2`, and `share_index` may be sent to the helper server.
/// Leaking `randomness` lets the helper recover plaintext shares via
/// `v*G = C2 - r*pk`, breaking voter privacy. Do NOT derive `Serialize`
/// on this struct without skipping these fields.
#[derive(Clone, Debug)]
pub struct EncryptedShare {
    pub c1: Vec<u8>,
    pub c2: Vec<u8>,
    pub share_index: u32,
    /// Raw share value. SECRET — must not be sent over the network.
    pub plaintext_value: u64,
    /// El Gamal randomness `r` (32 bytes, LE pallas::Scalar repr).
    /// Deterministically derived from (sk, round_id, proposal_id, van_commitment, share_index)
    /// so the client can re-derive it after a crash. SECRET — must not be sent over the network.
    pub randomness: Vec<u8>,
}

/// Complete vote commitment bundle for submission to vote chain.
#[derive(Clone, Debug)]
pub struct VoteCommitmentBundle {
    pub van_nullifier: Vec<u8>,
    pub vote_authority_note_new: Vec<u8>,
    pub vote_commitment: Vec<u8>,
    pub proposal_id: u32,
    pub proof: Vec<u8>,
    /// Encrypted shares generated by the ZKP #2 builder (16 shares).
    /// These are the exact ciphertexts committed in the vote commitment hash
    /// and must be used for reveal-share payloads.
    pub enc_shares: Vec<EncryptedShare>,
    /// Tree anchor height used for the proof.
    pub anchor_height: u32,
    /// Voting round ID (hex string).
    pub vote_round_id: String,
    /// Poseidon hash of encrypted share coordinates (32 bytes).
    /// Intermediate value: vote_commitment = H(DOMAIN_VC, voting_round_id, shares_hash, proposal_id, vote_decision).
    pub shares_hash: Vec<u8>,
    /// Per-share blind factors (16 x 32 bytes, LE pallas::Base repr).
    /// Deterministically derived from (sk, round_id, proposal_id, van_commitment, share_index).
    pub share_blinds: Vec<Vec<u8>>,
    /// Pre-computed per-share Poseidon commitments (N x 32 bytes, LE pallas::Base repr).
    /// share_comm_i = Poseidon(blind_i, c1_i_x, c2_i_x, c1_i_y, c2_i_y).
    /// Sent as public inputs to ZKP #3; the helper only needs the primary blind.
    pub share_comms: Vec<Vec<u8>>,
    /// Compressed r_vpk (32 bytes) for sighash computation and signature verification.
    pub r_vpk_bytes: Vec<u8>,
    /// Spend-auth randomizer alpha_v (32 bytes, LE scalar repr).
    /// Needed to sign the TX2 sighash: rsk_v = ask_v.randomize(&alpha_v).
    pub alpha_v: Vec<u8>,
}

/// Wire-safe encrypted share — contains only the public ciphertext components.
/// Secrets (`plaintext_value`, `randomness`) are kept inside Rust and never cross the FFI boundary.
#[derive(Clone, Debug, PartialEq)]
pub struct WireEncryptedShare {
    pub c1: Vec<u8>,
    pub c2: Vec<u8>,
    pub share_index: u32,
}

impl From<&EncryptedShare> for WireEncryptedShare {
    fn from(s: &EncryptedShare) -> Self {
        Self {
            c1: s.c1.clone(),
            c2: s.c2.clone(),
            share_index: s.share_index,
        }
    }
}

impl From<EncryptedShare> for WireEncryptedShare {
    fn from(s: EncryptedShare) -> Self {
        Self {
            c1: s.c1,
            c2: s.c2,
            share_index: s.share_index,
        }
    }
}

/// Payload sent to helper server for delegated share submission.
#[derive(Clone, Debug)]
pub struct SharePayload {
    pub shares_hash: Vec<u8>,
    pub proposal_id: u32,
    pub vote_decision: u32,
    pub enc_share: WireEncryptedShare,
    pub tree_position: u64,
    /// All encrypted shares (public components only).
    pub all_enc_shares: Vec<WireEncryptedShare>,
    /// Pre-computed per-share Poseidon commitments (N x 32 bytes).
    /// Provided as public inputs to ZKP #3.
    pub share_comms: Vec<Vec<u8>>,
    /// Blind factor for this specific share (32 bytes, LE pallas::Base repr).
    /// Only the revealed share's blind is needed for ZKP #3.
    pub primary_blind: Vec<u8>,
}

/// A share delegation record from the local DB.
/// Tracks which helper servers received each share and its on-chain confirmation status.
#[derive(Clone, Debug)]
pub struct ShareDelegationRecord {
    pub round_id: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    /// JSON-decoded list of helper server URLs that received this share.
    pub sent_to_urls: Vec<String>,
    /// Pre-computed share reveal nullifier (32 bytes).
    pub nullifier: Vec<u8>,
    /// Whether the share has been confirmed on-chain.
    pub confirmed: bool,
    /// Unix seconds: when the helper should submit the share (0 = immediate).
    pub submit_at: u64,
    /// Unix seconds: when the share was delegated.
    pub created_at: u64,
}

/// Computed signature fields for cast-vote TX submission.
/// Returned by `sign_cast_vote` after ZKP #2 builds the vote commitment bundle.
/// The sighash is computed on-chain from the message fields; the client only
/// needs to provide the signature (which was signed over the same sighash).
#[derive(Clone, Debug)]
pub struct CastVoteSignature {
    /// Spend auth signature over the canonical sighash (64 bytes).
    pub vote_auth_sig: Vec<u8>,
}

/// All fields needed to submit a delegation TX to the chain.
/// Fields from DB (proof, rk, nf_signed, cmx_new, gov_comm, gov_nullifiers, alpha)
/// plus computed fields (spend_auth_sig, sighash).
#[derive(Clone, Debug)]
pub struct DelegationSubmissionData {
    pub proof: Vec<u8>,
    pub rk: Vec<u8>,
    pub nf_signed: Vec<u8>,
    pub cmx_new: Vec<u8>,
    pub gov_comm: Vec<u8>,
    pub gov_nullifiers: Vec<Vec<u8>>,
    pub alpha: Vec<u8>,
    pub vote_round_id: String,
    /// Spend auth signature over sighash (64 bytes). Computed from seed + alpha.
    pub spend_auth_sig: Vec<u8>,
    /// Canonical sighash (32 bytes). Blake2b-256 of domain-separated fields.
    pub sighash: Vec<u8>,
}

/// Result of real delegation proof generation (ZKP #1).
#[derive(Clone, Debug)]
pub struct DelegationProofResult {
    /// Halo2 proof bytes.
    pub proof: Vec<u8>,
    /// 12 public input field elements, each as 32-byte LE arrays.
    pub public_inputs: Vec<Vec<u8>>,
    /// Signed note nullifier (32 bytes) — the ZKP's nf_signed (v=0 note).
    pub nf_signed: Vec<u8>,
    /// Output note commitment (32 bytes) — the ZKP's cmx_new (v=0 note).
    pub cmx_new: Vec<u8>,
    /// 5 governance nullifiers (each 32 bytes).
    pub gov_nullifiers: Vec<Vec<u8>>,
    /// Governance commitment / VAN (32 bytes).
    pub van_comm: Vec<u8>,
    /// Randomized verification key (32 bytes, compressed).
    pub rk: Vec<u8>,
}

/// Result of pre-fetching PIR-backed IMT non-membership proofs for ZKP #1.
#[derive(Clone, Debug)]
pub struct DelegationPirPrecomputeResult {
    /// Number of nullifier proofs that were already cached for this bundle.
    pub cached_count: u32,
    /// Number of nullifier proofs fetched from the PIR server during this call.
    pub fetched_count: u32,
}

/// Merkle witness for a note in the Orchard commitment tree.
#[derive(Clone, Debug)]
pub struct WitnessData {
    pub note_commitment: Vec<u8>,
    pub position: u64,
    pub root: Vec<u8>,
    pub auth_path: Vec<Vec<u8>>,
}

/// Callback for proof generation progress reporting.
/// Swift implements this trait; Rust calls it during long-running operations.
pub trait ProofProgressReporter: Send + Sync {
    fn on_progress(&self, progress: f64);
}

/// No-op progress reporter for contexts where progress isn't observed.
pub struct NoopProgressReporter;

impl ProofProgressReporter for NoopProgressReporter {
    fn on_progress(&self, _progress: f64) {}
}

// --- Validation helpers ---

pub fn validate_32_bytes(v: &[u8], name: &str) -> Result<(), VotingError> {
    if v.len() != 32 {
        return Err(VotingError::InvalidInput {
            message: format!("{} must be 32 bytes, got {}", name, v.len()),
        });
    }
    Ok(())
}

pub fn validate_share_index(index: u32) -> Result<(), VotingError> {
    if index > 15 {
        return Err(VotingError::InvalidInput {
            message: format!("share_index must be 0..15, got {}", index),
        });
    }
    Ok(())
}

pub fn validate_vote_decision(decision: u32, num_options: u32) -> Result<(), VotingError> {
    if decision >= num_options {
        return Err(VotingError::InvalidInput {
            message: format!(
                "vote_decision must be in [0, {}), got {}",
                num_options, decision
            ),
        });
    }
    Ok(())
}

pub fn validate_notes(notes: &[NoteInfo]) -> Result<(), VotingError> {
    if notes.is_empty() || notes.len() > 5 {
        return Err(VotingError::InvalidInput {
            message: format!("notes must have 1..5 entries, got {}", notes.len()),
        });
    }
    for (i, note) in notes.iter().enumerate() {
        validate_32_bytes(&note.commitment, &format!("notes[{}].commitment", i))?;
        validate_32_bytes(&note.nullifier, &format!("notes[{}].nullifier", i))?;
    }
    Ok(())
}

pub fn validate_round_params(params: &VotingRoundParams) -> Result<(), VotingError> {
    validate_32_bytes(&params.ea_pk, "ea_pk")?;
    validate_32_bytes(&params.nc_root, "nc_root")?;
    validate_32_bytes(&params.nullifier_imt_root, "nullifier_imt_root")?;
    Ok(())
}

/// Validate any number of notes for a round (>0). Checks commitments/nullifiers.
/// Unlike `validate_notes` (which enforces 1-5 per bundle), this allows any count.
pub fn validate_notes_for_round(notes: &[NoteInfo]) -> Result<(), VotingError> {
    if notes.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "notes must not be empty".to_string(),
        });
    }
    for (i, note) in notes.iter().enumerate() {
        validate_32_bytes(&note.commitment, &format!("notes[{}].commitment", i))?;
        validate_32_bytes(&note.nullifier, &format!("notes[{}].nullifier", i))?;
    }
    Ok(())
}

/// Result of value-aware note bundling.
#[derive(Clone, Debug)]
pub struct ChunkResult {
    /// Surviving bundles (each with total >= BALLOT_DIVISOR, max 5 notes).
    pub bundles: Vec<Vec<NoteInfo>>,
    /// Effective voting weight after per-bundle VAN quantization
    /// (each bundle contributes floor(total/BALLOT_DIVISOR) * BALLOT_DIVISOR).
    pub eligible_weight: u64,
    /// Number of notes that were dropped (in bundles below BALLOT_DIVISOR).
    pub dropped_count: usize,
}

/// Split notes into value-aware bundles of up to 5 using sequential packing.
///
/// Algorithm:
/// 1. Sort notes by value DESC, then position ASC as tiebreaker
/// 2. Fill bundles sequentially to capacity (5 notes each)
/// 3. Drop bundles with total < BALLOT_DIVISOR
/// 4. Re-sort notes within each surviving bundle by position
/// 5. Sort surviving bundles by total value DESC (min position as tiebreaker)
///
/// Sequential packing concentrates high-value notes in early bundles, maximizing
/// per-bundle VAN weight and minimizing quantization loss. Dust notes naturally
/// end up in the last (smallest) bundle which gets dropped if below threshold.
/// Value-descending bundle order lets Keystone users sign the most valuable
/// bundles first and optionally skip the remaining low-value ones.
pub fn chunk_notes(notes: &[NoteInfo]) -> ChunkResult {
    use crate::governance::BALLOT_DIVISOR;

    if notes.is_empty() {
        return ChunkResult {
            bundles: vec![],
            eligible_weight: 0,
            dropped_count: 0,
        };
    }

    // Step 1: Sort by value DESC, then position ASC as tiebreaker
    let mut sorted = notes.to_vec();
    sorted.sort_by(|a, b| b.value.cmp(&a.value).then(a.position.cmp(&b.position)));

    // Step 2: Fill bundles sequentially to capacity (5 notes each)
    let mut bundle_notes: Vec<Vec<NoteInfo>> = Vec::new();
    let mut bundle_totals: Vec<u64> = Vec::new();

    for note in &sorted {
        // Start a new bundle if the current one is full or none exist
        if bundle_notes.is_empty() || bundle_notes.last().unwrap().len() >= 5 {
            bundle_notes.push(Vec::new());
            bundle_totals.push(0);
        }
        let last = bundle_notes.len() - 1;
        bundle_totals[last] += note.value;
        bundle_notes[last].push(note.clone());
    }

    // Step 3: Drop bundles with total < BALLOT_DIVISOR
    let total_notes: usize = bundle_notes.iter().map(|b| b.len()).sum();
    let mut surviving: Vec<(u64, Vec<NoteInfo>)> = Vec::new();
    let mut eligible_weight: u64 = 0;
    let mut surviving_notes: usize = 0;

    for (i, bundle) in bundle_notes.into_iter().enumerate() {
        if bundle_totals[i] >= BALLOT_DIVISOR {
            surviving_notes += bundle.len();
            // Quantize per bundle: VAN weight = floor(total / BALLOT_DIVISOR) * BALLOT_DIVISOR
            eligible_weight += (bundle_totals[i] / BALLOT_DIVISOR) * BALLOT_DIVISOR;
            surviving.push((bundle_totals[i], bundle));
        }
    }
    let dropped_count = total_notes - surviving_notes;

    // Step 5: Re-sort notes within each surviving bundle by position
    for (_, bundle) in &mut surviving {
        bundle.sort_by_key(|n| n.position);
    }

    // Step 6: Sort surviving bundles by total value DESC (min position as tiebreaker).
    // This ensures bundle 0 is always the most valuable, enabling users to skip
    // low-value trailing bundles during Keystone signing.
    surviving.sort_by(|a, b| {
        b.0.cmp(&a.0).then_with(|| {
            let a_pos = a.1.first().map(|n| n.position).unwrap_or(u64::MAX);
            let b_pos = b.1.first().map(|n| n.position).unwrap_or(u64::MAX);
            a_pos.cmp(&b_pos)
        })
    });
    let surviving: Vec<Vec<NoteInfo>> = surviving.into_iter().map(|(_, b)| b).collect();

    ChunkResult {
        bundles: surviving,
        eligible_weight,
        dropped_count,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_note(value: u64, position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![0x01; 32],
            nullifier: vec![0x02; 32],
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
    fn test_chunk_notes_all_valid() {
        // 5 notes each with 13M — all fit in 1 bundle (capacity 5)
        let notes: Vec<NoteInfo> = (0..5).map(|i| make_note(13_000_000, i)).collect();
        let result = chunk_notes(&notes);
        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.dropped_count, 0);
        // Quantized: bundle 0 (65M → 5×12.5M=62.5M) = 62.5M
        assert_eq!(result.eligible_weight, 62_500_000);
        // Bundle 0 has 5 notes
        assert_eq!(result.bundles[0].len(), 5);
    }

    #[test]
    fn test_chunk_notes_dust_dropped() {
        // 1 good note (13M) + 5 dust notes → sequential fill packs first 5 together.
        // Sorted DESC: 13M first, then 5 dust. Bundle 0 = [13M, 100, 100, 100, 100], bundle 1 = [100].
        // Bundle 0 survives (13M+400 ≥ 12.5M), bundle 1 dropped (100 < 12.5M).
        let notes = vec![
            make_note(13_000_000, 0),
            make_note(100, 1),
            make_note(100, 2),
            make_note(100, 3),
            make_note(100, 4),
            make_note(100, 5),
        ];
        let result = chunk_notes(&notes);
        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.dropped_count, 1);
        // Quantized: 13,000,400 → 1×12.5M = 12.5M
        assert_eq!(result.eligible_weight, 12_500_000);
        // Surviving bundle contains good note + 4 dust
        assert_eq!(result.bundles[0].len(), 5);
    }

    #[test]
    fn test_chunk_notes_all_dust_empty() {
        // All notes below threshold — no valid bundles
        let notes = vec![make_note(100, 0), make_note(200, 1), make_note(300, 2)];
        let result = chunk_notes(&notes);
        assert!(result.bundles.is_empty());
        assert_eq!(result.eligible_weight, 0);
        assert_eq!(result.dropped_count, 3);
    }

    #[test]
    fn test_chunk_notes_exact_threshold() {
        // Single note at exactly BALLOT_DIVISOR
        let notes = vec![make_note(12_500_000, 0)];
        let result = chunk_notes(&notes);
        assert_eq!(result.bundles.len(), 1);
        assert_eq!(result.eligible_weight, 12_500_000);
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
        // Notes added in random order should still have position-sorted bundles
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
        // 8 equal-value notes → 2 bundles with same total.
        // Tiebreaker: min position ASC, so bundle with positions 0-4 comes first.
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
        // Equal totals — tiebreaker is min position
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
        // Mix of high and low-value notes. Bundle 0 should be the most valuable.
        // 5 large notes (50M each, pos 10-14) + 5 medium notes (13M each, pos 0-4)
        // Bundle 0 (sorted by value DESC): [50M×5] = 250M
        // Bundle 1: [13M×5] = 65M
        // After value-DESC sort: bundle 0 (250M) before bundle 1 (65M).
        let mut notes = Vec::new();
        for i in 0..5 {
            notes.push(make_note(50_000_000, 10 + i));
        }
        for i in 0..5 {
            notes.push(make_note(13_000_000, i));
        }
        let result = chunk_notes(&notes);
        assert_eq!(result.bundles.len(), 2);
        let total_0: u64 = result.bundles[0].iter().map(|n| n.value).sum();
        let total_1: u64 = result.bundles[1].iter().map(|n| n.value).sum();
        assert_eq!(total_0, 250_000_000);
        assert_eq!(total_1, 65_000_000);
        assert!(
            total_0 > total_1,
            "bundle 0 must have higher total than bundle 1"
        );
        // Despite bundle 1 having earlier positions (0-4), bundle 0 (positions 10-14)
        // comes first because value takes priority over position.
    }

    #[test]
    fn test_chunk_notes_empty() {
        let result = chunk_notes(&[]);
        assert!(result.bundles.is_empty());
        assert_eq!(result.eligible_weight, 0);
        assert_eq!(result.dropped_count, 0);
    }

    #[test]
    fn test_chunk_notes_max_5_per_bundle() {
        let notes: Vec<NoteInfo> = (0..12).map(|i| make_note(15_000_000, i)).collect();
        let result = chunk_notes(&notes);
        for bundle in &result.bundles {
            assert!(
                bundle.len() <= 5,
                "bundle has {} notes, max is 5",
                bundle.len()
            );
        }
    }
}

pub fn validate_encrypted_shares(shares: &[WireEncryptedShare]) -> Result<(), VotingError> {
    for (i, share) in shares.iter().enumerate() {
        validate_32_bytes(&share.c1, &format!("enc_shares[{}].c1", i))?;
        validate_32_bytes(&share.c2, &format!("enc_shares[{}].c2", i))?;
        validate_share_index(share.share_index)?;
    }
    Ok(())
}
