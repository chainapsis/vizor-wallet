use ff::PrimeField;
use halo2_gadgets::poseidon::primitives::{self as poseidon, ConstantLength, P128Pow5T3};
use pasta_curves::pallas;

use crate::types::VotingError;

/// Maximum proposal authority — the default for a fresh delegation.
/// Bitmask where each bit authorizes voting on the corresponding proposal.
/// Full authority is 2^16 - 1 = 65535. Only bits 1–15 are usable (proposal
/// IDs are 1-indexed); bit 0 is the circuit sentinel, permanently set.
pub(crate) const MAX_PROPOSAL_AUTHORITY: u64 = 65535;

/// Ballot divisor in zatoshi.
///
/// Must match `delegation::circuit::BALLOT_DIVISOR`. One ballot is this many
/// zatoshi, and bundle weights are quantized down to this boundary.
pub const BALLOT_DIVISOR: u64 = 12_500_000;

/// Domain tag for Vote Authority Notes.
/// Prepended as the first Poseidon input in van_comm for domain separation.
pub(crate) const DOMAIN_VAN: u64 = 0;

/// Protocol identifier for governance authorization, encoded as a little-endian
/// Pallas field element. Used to derive the nullifier domain for this application.
fn gov_auth_domain_tag() -> pallas::Base {
    string_domain_tag(b"governance authorization")
}

/// Domain tag for governance alternate nullifiers.
fn gov_null_domain_tag() -> pallas::Base {
    string_domain_tag(b"governance nullifier")
}

/// Encode a short ASCII domain tag as a little-endian Pallas field element.
fn string_domain_tag(tag: &[u8]) -> pallas::Base {
    assert!(
        tag.len() < 32 && tag.is_ascii(),
        "domain tags must be short ASCII strings"
    );
    let mut bytes = [0u8; 32];
    bytes[..tag.len()].copy_from_slice(tag);
    pallas::Base::from_repr(bytes).unwrap()
}

/// Poseidon hash of two field elements (ConstantLength<2>, width 3, rate 2).
/// Matches `orchard/src/delegation/imt.rs:poseidon_hash_2`.
fn poseidon_hash_2(a: pallas::Base, b: pallas::Base) -> pallas::Base {
    poseidon::Hash::<_, P128Pow5T3, ConstantLength<2>, 3, 2>::init().hash([a, b])
}

/// Derive the nullifier domain for a voting round (ZIP §Nullifier Domains).
///
/// `dom = Poseidon("governance authorization", vote_round_id)`
///
/// Matches `voting-circuits/src/delegation/imt.rs:derive_nullifier_domain`.
pub fn compute_nullifier_domain(vote_round_id: &[u8]) -> Result<Vec<u8>, VotingError> {
    let vri_fp = bytes_to_fp(vote_round_id)?;
    let dom = poseidon_hash_2(gov_auth_domain_tag(), vri_fp);
    Ok(fp_to_bytes(dom))
}

/// Convert a 32-byte slice to a Pallas base field element.
pub fn bytes_to_fp(bytes: &[u8]) -> Result<pallas::Base, VotingError> {
    let arr: [u8; 32] = bytes.try_into().map_err(|_| VotingError::InvalidInput {
        message: format!("expected 32 bytes, got {}", bytes.len()),
    })?;
    Option::from(pallas::Base::from_repr(arr)).ok_or_else(|| VotingError::InvalidInput {
        message: "bytes are not a valid Pallas field element".to_string(),
    })
}

/// Convert a Pallas base field element to 32 bytes.
fn fp_to_bytes(fp: pallas::Base) -> Vec<u8> {
    let repr: [u8; 32] = fp.to_repr();
    repr.to_vec()
}

/// Derive alternate nullifier (ZIP §Alternate Nullifier Derivation).
///
/// `nf_dom = Poseidon("governance nullifier", nk, dom, nf^old)`
///
/// where `dom` is the nullifier domain (see [`compute_nullifier_domain`]).
/// Single Poseidon call with ConstantLength<4> (2 permutations at rate=2).
/// Matches `voting-circuits/src/delegation/imt.rs:gov_null_hash`.
pub fn derive_gov_nullifier(
    nk: &[u8],
    dom: &[u8],
    note_nullifier: &[u8],
) -> Result<Vec<u8>, VotingError> {
    let nk_fp = bytes_to_fp(nk)?;
    let dom_fp = bytes_to_fp(dom)?;
    let nf_fp = bytes_to_fp(note_nullifier)?;

    let gov_null = poseidon::Hash::<_, P128Pow5T3, ConstantLength<4>, 3, 2>::init().hash([
        gov_null_domain_tag(),
        nk_fp,
        dom_fp,
        nf_fp,
    ]);

    Ok(fp_to_bytes(gov_null))
}

/// Construct a Vote Authority Note (governance commitment, per spec §1.3.3).
///
/// ```text
/// num_ballots = total_weight / BALLOT_DIVISOR
/// van_comm_core = Poseidon(DOMAIN_VAN, g_d_new_x, pk_d_new_x, num_ballots, vote_round_id, MAX_PROPOSAL_AUTHORITY)
/// van_comm = Poseidon(van_comm_core, van_comm_rand)
/// ```
///
/// The VAN hashes `num_ballots` (ballot count after floor-division by
/// BALLOT_DIVISOR), NOT the raw zatoshi `total_weight`.
///
/// First hash is ConstantLength<6>, second is ConstantLength<2>.
/// Matches `orchard/src/delegation/circuit.rs:van_commitment_hash`.
pub fn construct_van(
    g_d_new_x: &[u8],
    pk_d_new_x: &[u8],
    total_weight: u64,
    vote_round_id: &[u8],
    van_comm_rand: &[u8],
) -> Result<Vec<u8>, VotingError> {
    let num_ballots = total_weight / BALLOT_DIVISOR;
    if num_ballots == 0 {
        return Err(VotingError::InvalidInput {
            message: "total_weight must yield at least 1 ballot (>= 12_500_000 zatoshi)"
                .to_string(),
        });
    }

    // Parse all inputs into Pallas field elements for Poseidon.
    let g_d = bytes_to_fp(g_d_new_x)?;
    let pk_d = bytes_to_fp(pk_d_new_x)?;
    let num_ballots_base = pallas::Base::from(num_ballots);
    let vri = bytes_to_fp(vote_round_id)?;
    let rcm = bytes_to_fp(van_comm_rand)?;

    // Step 1: Hash the 6 core VAN fields into a single digest (ConstantLength<6>).
    // This binds the VAN to a specific hotkey address (g_d, pk_d), ballot count,
    // voting round, and full proposal authority. DOMAIN_VAN=0 provides domain
    // separation from Vote Commitments (DOMAIN_VC=1) in the shared commitment tree.
    let van_comm_core = poseidon::Hash::<_, P128Pow5T3, ConstantLength<6>, 3, 2>::init().hash([
        pallas::Base::from(DOMAIN_VAN),
        g_d,
        pk_d,
        num_ballots_base,
        vri,
        pallas::Base::from(MAX_PROPOSAL_AUTHORITY),
    ]);

    // Step 2: Fold in the blinding factor (ConstantLength<2>).
    // van_comm_rand hides the VAN preimage so observers can't brute-force
    // the hotkey or ballot count from the on-chain commitment.
    let van_comm = poseidon_hash_2(van_comm_core, rcm);

    Ok(fp_to_bytes(van_comm))
}

/// Compute constrained rho (spec §1.3.4.1, condition 3).
///
/// `rho_signed = Poseidon(cmx_1, cmx_2, cmx_3, cmx_4, cmx_5, van_comm, vote_round_id)`
///
/// ConstantLength<7>, matching `orchard/src/delegation/circuit.rs:rho_binding_hash`.
pub fn compute_rho_binding(
    cmx_1: &[u8],
    cmx_2: &[u8],
    cmx_3: &[u8],
    cmx_4: &[u8],
    cmx_5: &[u8],
    van_comm: &[u8],
    vote_round_id: &[u8],
) -> Result<Vec<u8>, VotingError> {
    let c1 = bytes_to_fp(cmx_1)?;
    let c2 = bytes_to_fp(cmx_2)?;
    let c3 = bytes_to_fp(cmx_3)?;
    let c4 = bytes_to_fp(cmx_4)?;
    let c5 = bytes_to_fp(cmx_5)?;
    let gc = bytes_to_fp(van_comm)?;
    let vri = bytes_to_fp(vote_round_id)?;

    let rho = poseidon::Hash::<_, P128Pow5T3, ConstantLength<7>, 3, 2>::init()
        .hash([c1, c2, c3, c4, c5, gc, vri]);

    Ok(fp_to_bytes(rho))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_derive_gov_nullifier_deterministic() {
        let nk = [0x01u8; 32];
        let vri = [0x02u8; 32];
        let nf = [0x03u8; 32];
        let dom = compute_nullifier_domain(&vri).unwrap();

        let result1 = derive_gov_nullifier(&nk, &dom, &nf).unwrap();
        let result2 = derive_gov_nullifier(&nk, &dom, &nf).unwrap();

        assert_eq!(result1.len(), 32);
        assert_eq!(result1, result2, "gov nullifier must be deterministic");
    }

    #[test]
    fn test_derive_gov_nullifier_not_trivial() {
        let nk = [0x01u8; 32];
        let vri = [0x02u8; 32];
        let nf = [0x03u8; 32];
        let dom = compute_nullifier_domain(&vri).unwrap();

        let result = derive_gov_nullifier(&nk, &dom, &nf).unwrap();
        // Should not be all zeros or all same byte
        assert_ne!(result, vec![0x00; 32]);
        assert_ne!(result, vec![0xAA; 32]); // not the old mock
    }

    #[test]
    fn test_derive_gov_nullifier_is_domain_tagged() {
        let nk = [0x01u8; 32];
        let vri = [0x02u8; 32];
        let nf = [0x03u8; 32];
        let dom = compute_nullifier_domain(&vri).unwrap();

        let tagged = derive_gov_nullifier(&nk, &dom, &nf).unwrap();
        let raw_three_input = poseidon::Hash::<_, P128Pow5T3, ConstantLength<3>, 3, 2>::init()
            .hash([
                bytes_to_fp(&nk).unwrap(),
                bytes_to_fp(&dom).unwrap(),
                bytes_to_fp(&nf).unwrap(),
            ]);

        assert_ne!(
            tagged,
            fp_to_bytes(raw_three_input),
            "governance nullifiers must include the voting-circuits domain tag"
        );
    }

    #[test]
    fn test_derive_gov_nullifier_different_inputs_different_outputs() {
        let nk = [0x01u8; 32];
        let vri = [0x02u8; 32];
        let nf1 = [0x03u8; 32];
        let nf2 = [0x04u8; 32];
        let dom = compute_nullifier_domain(&vri).unwrap();

        let result1 = derive_gov_nullifier(&nk, &dom, &nf1).unwrap();
        let result2 = derive_gov_nullifier(&nk, &dom, &nf2).unwrap();

        assert_ne!(
            result1, result2,
            "different nullifiers must produce different gov nullifiers"
        );
    }

    #[test]
    fn test_construct_van_deterministic() {
        let g_d = [0x10u8; 32];
        let pk_d = [0x20u8; 32];
        let vri = [0x05u8; 32];
        let rcm = [0x06u8; 32];

        let result1 = construct_van(&g_d, &pk_d, 15_000_000, &vri, &rcm).unwrap();
        let result2 = construct_van(&g_d, &pk_d, 15_000_000, &vri, &rcm).unwrap();

        assert_eq!(result1.len(), 32);
        assert_eq!(result1, result2, "VAN must be deterministic");
    }

    #[test]
    fn test_construct_van_not_trivial() {
        let g_d = [0x10u8; 32];
        let pk_d = [0x20u8; 32];
        let vri = [0x05u8; 32];
        let rcm = [0x06u8; 32];

        let result = construct_van(&g_d, &pk_d, 15_000_000, &vri, &rcm).unwrap();
        assert_ne!(result, vec![0x00; 32]);
        assert_ne!(result, vec![0xBB; 32]); // not the old mock
    }

    #[test]
    fn test_construct_van_below_one_ballot() {
        let g_d = [0x10u8; 32];
        let pk_d = [0x20u8; 32];
        let vri = [0x05u8; 32];
        let rcm = [0x06u8; 32];

        // Zero weight
        assert!(construct_van(&g_d, &pk_d, 0, &vri, &rcm).is_err());
        // Below one ballot (< BALLOT_DIVISOR)
        assert!(construct_van(&g_d, &pk_d, 12_499_999, &vri, &rcm).is_err());
    }

    #[test]
    fn test_construct_van_different_rand_different_output() {
        let g_d = [0x10u8; 32];
        let pk_d = [0x20u8; 32];
        let vri = [0x05u8; 32];
        let rcm1 = [0x06u8; 32];
        let rcm2 = [0x07u8; 32];

        let result1 = construct_van(&g_d, &pk_d, 15_000_000, &vri, &rcm1).unwrap();
        let result2 = construct_van(&g_d, &pk_d, 15_000_000, &vri, &rcm2).unwrap();

        assert_ne!(
            result1, result2,
            "different randomness must produce different VAN"
        );
    }

    /// Known-answer test vectors for governance nullifier and VAN.
    /// These values are deterministic for the given inputs. If this test breaks,
    /// the Poseidon formula or input ordering has diverged from the spec.
    /// Cross-reference: voting-circuits/src/delegation/imt.rs:gov_null_hash,
    ///                  orchard/src/delegation/circuit.rs:van_commitment_hash.
    #[test]
    fn test_known_answer_gov_nullifier() {
        let nk = [0x01u8; 32];
        let vri = [0x02u8; 32];
        let nf = [0x03u8; 32];
        let dom = compute_nullifier_domain(&vri).unwrap();

        let result = derive_gov_nullifier(&nk, &dom, &nf).unwrap();
        // Formula: dom = Poseidon("governance authorization", vri),
        // then gov_null = Poseidon("governance nullifier", nk, dom, nf).
        let expected =
            hex::decode("1802353bdf71910a86644c87495da3ee281ab2017c6c5bdcff965d80d5709427")
                .unwrap();
        assert_eq!(
            result, expected,
            "gov nullifier known-answer mismatch — formula may have diverged from voting-circuits"
        );
    }

    #[test]
    fn test_known_answer_van() {
        let g_d = [0x10u8; 32];
        let pk_d = [0x20u8; 32];
        let vri = [0x05u8; 32];
        let rcm = [0x06u8; 32];

        // total_weight = 15_000_000 → num_ballots = 1 (after / BALLOT_DIVISOR)
        let result = construct_van(&g_d, &pk_d, 15_000_000, &vri, &rcm).unwrap();
        let expected =
            hex::decode("60658dfc1b7ae3bd06b713ffc6e3c05c369547b10c4a392bd2d45f06fdd2b82d")
                .unwrap();
        assert_eq!(
            result, expected,
            "VAN known-answer mismatch — formula may have diverged from orchard reference"
        );
    }

    #[test]
    fn test_invalid_length_inputs() {
        let dom = compute_nullifier_domain(&[0u8; 32]).unwrap();
        assert!(derive_gov_nullifier(&[0u8; 31], &dom, &[0u8; 32]).is_err());
        assert!(derive_gov_nullifier(&[0u8; 32], &[0u8; 31], &[0u8; 32]).is_err());
        assert!(derive_gov_nullifier(&[0u8; 32], &dom, &[0u8; 31]).is_err());

        assert!(construct_van(&[0u8; 31], &[0u8; 32], 15_000_000, &[0u8; 32], &[0u8; 32]).is_err());
        assert!(construct_van(&[0u8; 32], &[0u8; 31], 15_000_000, &[0u8; 32], &[0u8; 32]).is_err());
    }

    #[test]
    fn test_compute_rho_binding_deterministic() {
        let cmx1 = [0x01u8; 32];
        let cmx2 = [0x02u8; 32];
        let cmx3 = [0x03u8; 32];
        let cmx4 = [0x04u8; 32];
        let cmx5 = [0x0Au8; 32];
        let gov = [0x05u8; 32];
        let vri = [0x06u8; 32];

        let r1 = compute_rho_binding(&cmx1, &cmx2, &cmx3, &cmx4, &cmx5, &gov, &vri).unwrap();
        let r2 = compute_rho_binding(&cmx1, &cmx2, &cmx3, &cmx4, &cmx5, &gov, &vri).unwrap();

        assert_eq!(r1.len(), 32);
        assert_eq!(r1, r2, "rho_binding must be deterministic");
    }

    #[test]
    fn test_compute_rho_binding_different_cmx() {
        let cmx1 = [0x01u8; 32];
        let cmx2 = [0x02u8; 32];
        let cmx3 = [0x03u8; 32];
        let cmx4 = [0x04u8; 32];
        let cmx5 = [0x0Au8; 32];
        let gov = [0x05u8; 32];
        let vri = [0x06u8; 32];

        let base = compute_rho_binding(&cmx1, &cmx2, &cmx3, &cmx4, &cmx5, &gov, &vri).unwrap();

        // Changing any cmx should change the output
        let alt1 =
            compute_rho_binding(&[0x11u8; 32], &cmx2, &cmx3, &cmx4, &cmx5, &gov, &vri).unwrap();
        let alt2 =
            compute_rho_binding(&cmx1, &[0x12u8; 32], &cmx3, &cmx4, &cmx5, &gov, &vri).unwrap();
        let alt3 =
            compute_rho_binding(&cmx1, &cmx2, &[0x13u8; 32], &cmx4, &cmx5, &gov, &vri).unwrap();
        let alt4 =
            compute_rho_binding(&cmx1, &cmx2, &cmx3, &[0x14u8; 32], &cmx5, &gov, &vri).unwrap();
        let alt5 =
            compute_rho_binding(&cmx1, &cmx2, &cmx3, &cmx4, &[0x15u8; 32], &gov, &vri).unwrap();

        assert_ne!(base, alt1, "changing cmx_1 must change rho");
        assert_ne!(base, alt2, "changing cmx_2 must change rho");
        assert_ne!(base, alt3, "changing cmx_3 must change rho");
        assert_ne!(base, alt4, "changing cmx_4 must change rho");
        assert_ne!(base, alt5, "changing cmx_5 must change rho");
    }

    #[test]
    fn test_known_answer_rho_binding() {
        let cmx1 = [0x01u8; 32];
        let cmx2 = [0x02u8; 32];
        let cmx3 = [0x03u8; 32];
        let cmx4 = [0x04u8; 32];
        let cmx5 = [0x0Au8; 32];
        let gov = [0x05u8; 32];
        let vri = [0x06u8; 32];

        let result = compute_rho_binding(&cmx1, &cmx2, &cmx3, &cmx4, &cmx5, &gov, &vri).unwrap();

        // This is a regression test: if the hash changes, the formula has diverged.
        assert_eq!(
            result,
            vec![
                0x36, 0xfe, 0x8d, 0x03, 0x0e, 0xb6, 0xe2, 0xe6, 0x89, 0xc3, 0x31, 0x1a, 0x9f, 0x45,
                0x17, 0xb8, 0x31, 0xb5, 0x46, 0xe6, 0xbc, 0x2f, 0x4e, 0xe2, 0x62, 0x7c, 0x86, 0xbe,
                0x7a, 0x80, 0x67, 0x1e,
            ],
            "rho_binding known-answer regression"
        );
    }
}
