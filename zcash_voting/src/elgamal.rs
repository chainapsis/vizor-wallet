use ff::{Field, PrimeField};
use group::GroupEncoding;
use pasta_curves::pallas;
use rand::rngs::OsRng;

use crate::types::{validate_32_bytes, EncryptedShare, VotingError};

/// Encrypt each share under `ea_pk` using additively homomorphic El Gamal
/// on the Pallas curve with **SpendAuthG** as the generator.
///
/// Protocol requires exactly 16 shares (§3.3.1).
///
/// For each share value `v` with randomness `r`:
/// - C1 = r * G
/// - C2 = v * G + r * ea_pk
///
/// Returns compressed Pallas points (32 bytes each): x-coordinate LE with
/// the sign of y in the high bit of byte 31. To extract both coordinates
/// (for `shares_hash` / circuit constraints), decompress the point to
/// recover (x, y).
pub fn encrypt_shares(shares: &[u64], ea_pk: &[u8]) -> Result<Vec<EncryptedShare>, VotingError> {
    validate_32_bytes(ea_pk, "ea_pk")?;

    if shares.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "shares must not be empty".to_string(),
        });
    }

    if shares.len() > 16 {
        return Err(VotingError::InvalidInput {
            message: format!("at most 16 shares supported, got {}", shares.len()),
        });
    }

    // Decode ea_pk from compressed Pallas point bytes.
    let pk_point = decode_pallas_point(ea_pk, "ea_pk")?;

    // SpendAuthG — the generator hardcoded in the ZKP #2 circuit.
    let g = pallas::Point::from(voting_circuits::vote_proof::spend_auth_g_affine());

    let mut encrypted = Vec::with_capacity(shares.len());
    for (i, &value) in shares.iter().enumerate() {
        let mut share = encrypt_single(value, &g, &pk_point)?;
        share.share_index = i as u32;
        encrypted.push(share);
    }

    Ok(encrypted)
}

/// Encrypt a single share value, returning an `EncryptedShare` with index 0.
/// Caller sets the correct `share_index` afterwards.
fn encrypt_single(
    share_value: u64,
    g: &pallas::Point,
    ea_pk: &pallas::Point,
) -> Result<EncryptedShare, VotingError> {
    // Generate random scalar r.
    let r = pallas::Scalar::random(OsRng);

    // v as a Pallas scalar.
    let v = pallas::Scalar::from(share_value);

    // C1 = r * G
    let c1 = g * r;
    // C2 = v * G + r * ea_pk
    let c2 = g * v + ea_pk * r;

    Ok(EncryptedShare {
        c1: c1.to_bytes().to_vec(),
        c2: c2.to_bytes().to_vec(),
        share_index: 0,
        plaintext_value: share_value,
        randomness: r.to_repr().to_vec(),
    })
}

/// Decode a 32-byte compressed Pallas point, returning an error with context on failure.
fn decode_pallas_point(bytes: &[u8], name: &str) -> Result<pallas::Point, VotingError> {
    let mut arr = [0u8; 32];
    arr.copy_from_slice(bytes);
    let affine: Option<pallas::Affine> = pallas::Affine::from_bytes(&arr).into();
    let affine = affine.ok_or_else(|| VotingError::InvalidInput {
        message: format!("{} is not a valid compressed Pallas point", name),
    })?;
    Ok(pallas::Point::from(affine))
}

#[cfg(test)]
mod tests {
    use super::*;
    use ff::Field;
    use group::{Curve, Group};
    use pasta_curves::arithmetic::CurveAffine;

    /// Generate a random El Gamal keypair: (sk, pk) where pk = sk * G.
    fn keygen() -> (pallas::Scalar, pallas::Point) {
        let g = pallas::Point::from(voting_circuits::vote_proof::spend_auth_g_affine());
        let sk = pallas::Scalar::random(OsRng);
        let pk = g * sk;
        (sk, pk)
    }

    /// Decrypt: plaintext_point = C2 - sk * C1
    fn decrypt(sk: &pallas::Scalar, c1_bytes: &[u8], c2_bytes: &[u8]) -> pallas::Point {
        let c1 = decode_pallas_point(c1_bytes, "c1").expect("valid c1");
        let c2 = decode_pallas_point(c2_bytes, "c2").expect("valid c2");
        c2 - c1 * sk
    }

    #[test]
    fn test_roundtrip_encrypt_decrypt() {
        let (sk, pk) = keygen();
        let pk_bytes = pk.to_bytes().to_vec();
        let g = pallas::Point::from(voting_circuits::vote_proof::spend_auth_g_affine());

        for &value in &[0u64, 1, 42, 1000, u64::MAX >> 1] {
            let result = encrypt_shares(&[value], &pk_bytes).unwrap();
            let share = &result[0];

            // Decrypt: C2 - sk * C1 should equal v * G.
            let decrypted_point = decrypt(&sk, &share.c1, &share.c2);
            let expected_point = g * pallas::Scalar::from(value);
            assert_eq!(
                decrypted_point, expected_point,
                "round-trip failed for value {}",
                value
            );
        }
    }

    #[test]
    fn test_spend_auth_g_consistency() {
        let g_affine = voting_circuits::vote_proof::spend_auth_g_affine();
        let g = pallas::Point::from(g_affine);

        // SpendAuthG must not be the identity.
        assert!(!bool::from(g.is_identity()));

        // Verify it matches the value used by the circuit helper.
        let g_from_circuit = {
            // Encrypt value=1 with known randomness=1 via the circuit helper,
            // then C1 should equal G (since r=1 → C1 = 1*G = G).
            let r = pallas::Base::one();
            let v = pallas::Base::one();
            let pk = pallas::Point::identity(); // pk=0 simplifies C2
            let (c1_x, _c2_x, _c1_y, _c2_y) =
                voting_circuits::vote_proof::elgamal_encrypt(v, r, pk);
            c1_x
        };

        // Our G's x-coordinate should match.
        let our_g_x = *g.to_affine().coordinates().unwrap().x();
        assert_eq!(our_g_x, g_from_circuit);
    }

    #[test]
    fn test_cross_validation_with_circuit_helper() {
        // Use deterministic "randomness" by manually encrypting with known scalar.
        let g = pallas::Point::from(voting_circuits::vote_proof::spend_auth_g_affine());
        let (_, pk) = keygen();

        let share_value = 42u64;
        let r_scalar = pallas::Scalar::from(7u64);
        let v_scalar = pallas::Scalar::from(share_value);

        // Our encryption.
        let c1 = g * r_scalar;
        let c2 = g * v_scalar + pk * r_scalar;
        let c1_x = *c1.to_affine().coordinates().unwrap().x();
        let c2_x = *c2.to_affine().coordinates().unwrap().x();

        let c1_y = *c1.to_affine().coordinates().unwrap().y();
        let c2_y = *c2.to_affine().coordinates().unwrap().y();

        // Circuit helper encryption.
        // It uses pallas::Base for randomness and value, and calls base_to_scalar internally.
        let r_base = pallas::Base::from(7u64);
        let v_base = pallas::Base::from(share_value);
        let (circuit_c1_x, circuit_c2_x, circuit_c1_y, circuit_c2_y) =
            voting_circuits::vote_proof::elgamal_encrypt(v_base, r_base, pk);

        assert_eq!(c1_x, circuit_c1_x, "C1.x must match circuit helper");
        assert_eq!(c2_x, circuit_c2_x, "C2.x must match circuit helper");
        assert_eq!(c1_y, circuit_c1_y, "C1.y must match circuit helper");
        assert_eq!(c2_y, circuit_c2_y, "C2.y must match circuit helper");
    }

    #[test]
    fn test_shares_hash_consistency() {
        // Encrypt 16 shares, compute shares_hash, verify against circuit helper.
        let (_, pk) = keygen();
        let pk_bytes = pk.to_bytes().to_vec();

        let shares_input: Vec<u64> = (0..16).map(|i| 1u64 << i.min(30)).collect();
        let result = encrypt_shares(&shares_input, &pk_bytes).unwrap();
        assert_eq!(result.len(), 16);

        // Decompress ciphertext points to extract full (x, y) coordinates.
        let mut c1_x = [pallas::Base::zero(); 16];
        let mut c2_x = [pallas::Base::zero(); 16];
        let mut c1_y = [pallas::Base::zero(); 16];
        let mut c2_y = [pallas::Base::zero(); 16];
        for (i, share) in result.iter().enumerate() {
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&share.c1);
            let c1_affine: pallas::Affine =
                Option::from(pallas::Affine::from_bytes(&arr)).expect("c1 is a valid Pallas point");
            let c1_coords = c1_affine.coordinates().unwrap();
            c1_x[i] = *c1_coords.x();
            c1_y[i] = *c1_coords.y();

            arr.copy_from_slice(&share.c2);
            let c2_affine: pallas::Affine =
                Option::from(pallas::Affine::from_bytes(&arr)).expect("c2 is a valid Pallas point");
            let c2_coords = c2_affine.coordinates().unwrap();
            c2_x[i] = *c2_coords.x();
            c2_y[i] = *c2_coords.y();
        }

        // Use synthetic blinds for testing.
        let blinds: [pallas::Base; 16] =
            core::array::from_fn(|i| pallas::Base::from(1001u64 + i as u64));

        // Compute shares_hash using the circuit helper.
        let hash = voting_circuits::vote_proof::shares_hash(blinds, c1_x, c2_x, c1_y, c2_y);

        // Verify it's not zero (sanity).
        assert_ne!(hash, pallas::Base::zero());

        // Verify determinism: same inputs → same hash.
        let hash2 = voting_circuits::vote_proof::shares_hash(blinds, c1_x, c2_x, c1_y, c2_y);
        assert_eq!(hash, hash2);
    }

    #[test]
    fn test_zero_value_encryption() {
        let (_, pk) = keygen();
        let pk_bytes = pk.to_bytes().to_vec();

        let result = encrypt_shares(&[0], &pk_bytes).unwrap();
        let share = &result[0];

        // For v=0: C2 = 0*G + r*pk = r*pk.
        // Decode C1 = r*G, so C2 should equal (r/1) * pk if we know r.
        let mut r_arr = [0u8; 32];
        r_arr.copy_from_slice(&share.randomness);
        let r = pallas::Scalar::from_repr(r_arr).unwrap();

        let c2 = decode_pallas_point(&share.c2, "c2").unwrap();
        let expected_c2 = pk * r;
        assert_eq!(c2, expected_c2, "C2 for v=0 must equal r*pk");
    }

    #[test]
    fn test_output_format() {
        let (_, pk) = keygen();
        let pk_bytes = pk.to_bytes().to_vec();

        let shares_input: Vec<u64> = (0..16).map(|i| 1u64 << i.min(30)).collect();
        let result = encrypt_shares(&shares_input, &pk_bytes).unwrap();
        for share in &result {
            assert_eq!(share.c1.len(), 32, "c1 must be 32 bytes");
            assert_eq!(share.c2.len(), 32, "c2 must be 32 bytes");
            assert_eq!(share.randomness.len(), 32, "randomness must be 32 bytes");
        }
    }

    #[test]
    fn test_encrypt_shares_rejects_more_than_16() {
        let (_, pk) = keygen();
        let pk_bytes = pk.to_bytes().to_vec();
        let too_many: Vec<u64> = (0..17).collect();
        assert!(encrypt_shares(&too_many, &pk_bytes).is_err());
    }

    #[test]
    fn test_encrypt_shares_rejects_empty() {
        let (_, pk) = keygen();
        let pk_bytes = pk.to_bytes().to_vec();
        assert!(encrypt_shares(&[], &pk_bytes).is_err());
    }

    #[test]
    fn test_encrypt_shares_bad_ea_pk() {
        assert!(encrypt_shares(&[1], &[0xEA; 16]).is_err());
    }

    #[test]
    fn test_encrypt_shares_invalid_point_ea_pk() {
        // 32 bytes of 0xFF is extremely unlikely to be a valid Pallas point.
        assert!(encrypt_shares(&[1], &[0xFF; 32]).is_err());
    }
}
