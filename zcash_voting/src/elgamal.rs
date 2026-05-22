use ff::{Field, PrimeField};
use group::{Group, GroupEncoding};
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

    // Reject the identity point: with ea_pk = O, C2 = v*G + r*O = v*G, so every
    // share's plaintext is recoverable by anyone (no secret key needed). Pallas
    // has cofactor 1, so the identity is the only degenerate public key.
    if bool::from(pk_point.is_identity()) {
        return Err(VotingError::InvalidInput {
            message: "ea_pk must not be the identity point".to_string(),
        });
    }

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
    fn test_encryption_formula_matches_returned_randomness() {
        let g = pallas::Point::from(voting_circuits::vote_proof::spend_auth_g_affine());
        let (_, pk) = keygen();
        let pk_bytes = pk.to_bytes().to_vec();

        let share_value = 42u64;
        let share = encrypt_shares(&[share_value], &pk_bytes).unwrap().remove(0);

        let mut r_arr = [0u8; 32];
        r_arr.copy_from_slice(&share.randomness);
        let r = pallas::Scalar::from_repr(r_arr).unwrap();
        let v = pallas::Scalar::from(share_value);

        assert_eq!(decode_pallas_point(&share.c1, "c1").unwrap(), g * r);
        assert_eq!(
            decode_pallas_point(&share.c2, "c2").unwrap(),
            g * v + pk * r
        );
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

    #[test]
    fn test_encrypt_shares_rejects_identity_ea_pk() {
        // The identity point is a valid encoding but a degenerate public key:
        // C2 = v*G + r*O = v*G would expose every share's plaintext.
        let identity_bytes = pallas::Point::identity().to_bytes().to_vec();
        assert!(encrypt_shares(&[1], &identity_bytes).is_err());
    }
}
