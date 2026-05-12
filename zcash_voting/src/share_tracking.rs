//! Share tracking utilities.
//!
//! Pre-computes the share reveal nullifier so the client can poll
//! `GET /api/v1/share-status/{roundId}/{nullifier}` without waiting
//! for the helper to run ZKP #3.

use ff::PrimeField;
use pasta_curves::pallas;

use crate::types::ct_option_to_result;
use crate::VotingError;

/// Compute the share reveal nullifier from client-known inputs.
///
/// The nullifier is `Poseidon(domain_tag_share_spend, vote_commitment, share_index, blind)`.
/// See `voting_circuits::share_reveal::circuit::share_nullifier_hash`.
///
/// # Arguments
/// - `vote_commitment`: 32-byte LE pallas::Base — the VC leaf hash from ZKP #2.
/// - `share_index`: Which of the 16 shares (0..15).
/// - `primary_blind`: 32-byte LE pallas::Base — the blind factor for this share.
pub fn compute_share_nullifier(
    vote_commitment: &[u8],
    share_index: u32,
    primary_blind: &[u8],
) -> Result<Vec<u8>, VotingError> {
    if vote_commitment.len() != 32 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "vote_commitment must be 32 bytes, got {}",
                vote_commitment.len()
            ),
        });
    }
    if primary_blind.len() != 32 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "primary_blind must be 32 bytes, got {}",
                primary_blind.len()
            ),
        });
    }
    if share_index > 15 {
        return Err(VotingError::InvalidInput {
            message: format!("share_index must be 0..15, got {}", share_index),
        });
    }

    let vc = ct_option_to_result(
        pallas::Base::from_repr(vote_commitment.try_into().expect("checked length above")),
        "invalid vote_commitment field element",
    )?;

    let blind = ct_option_to_result(
        pallas::Base::from_repr(primary_blind.try_into().expect("checked length above")),
        "invalid primary_blind field element",
    )?;

    let share_index_fp = pallas::Base::from(share_index as u64);

    let nullifier = voting_circuits::share_reveal::share_nullifier_hash(vc, share_index_fp, blind);

    Ok(nullifier.to_repr().to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_share_nullifier_basic() {
        // Use zero values to verify the function runs without panicking.
        let vc = [0u8; 32];
        let blind = [0u8; 32];
        let result = compute_share_nullifier(&vc, 0, &blind);
        assert!(result.is_ok());
        let nf = result.unwrap();
        assert_eq!(nf.len(), 32);
    }

    #[test]
    fn test_compute_share_nullifier_deterministic() {
        let vc = [1u8; 32];
        let blind = [2u8; 32];
        // pallas::Base::from_repr may return None for values >= field modulus,
        // but small byte patterns are always valid.
        let r1 = compute_share_nullifier(&vc, 5, &blind);
        let r2 = compute_share_nullifier(&vc, 5, &blind);
        assert!(r1.is_ok());
        assert_eq!(r1.unwrap(), r2.unwrap());
    }

    #[test]
    fn test_compute_share_nullifier_different_index() {
        let vc = [1u8; 32];
        let blind = [2u8; 32];
        let r0 = compute_share_nullifier(&vc, 0, &blind).unwrap();
        let r1 = compute_share_nullifier(&vc, 1, &blind).unwrap();
        assert_ne!(
            r0, r1,
            "different share indices must produce different nullifiers"
        );
    }

    #[test]
    fn test_compute_share_nullifier_bad_lengths() {
        let short = [0u8; 16];
        let ok = [0u8; 32];
        assert!(compute_share_nullifier(&short, 0, &ok).is_err());
        assert!(compute_share_nullifier(&ok, 0, &short).is_err());
    }

    #[test]
    fn test_compute_share_nullifier_bad_index() {
        let vc = [0u8; 32];
        let blind = [0u8; 32];
        assert!(compute_share_nullifier(&vc, 16, &blind).is_err());
    }
}
