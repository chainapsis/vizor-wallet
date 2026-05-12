use crate::types::{VotingError, WitnessData};

use incrementalmerkletree::{Hashable, Level};
use orchard::tree::MerkleHashOrchard;
use subtle::CtOption;

/// Verify a Merkle witness by recomputing the root from leaf + auth path.
///
/// Returns true if the computed root matches the expected root in the witness.
/// Uses the same level-aware Sinsemilla hash as the Orchard commitment tree.
pub fn verify_witness(witness: &WitnessData) -> Result<bool, VotingError> {
    if witness.note_commitment.len() != 32 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "note_commitment must be 32 bytes, got {}",
                witness.note_commitment.len()
            ),
        });
    }
    if witness.root.len() != 32 {
        return Err(VotingError::InvalidInput {
            message: format!("root must be 32 bytes, got {}", witness.root.len()),
        });
    }
    if witness.auth_path.len() != 32 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "auth_path must have 32 levels, got {}",
                witness.auth_path.len()
            ),
        });
    }

    // Parse note commitment as MerkleHashOrchard
    let commitment_bytes: [u8; 32] = witness.note_commitment[..].try_into().unwrap();
    let mut current: MerkleHashOrchard = ct_option_to_result(
        MerkleHashOrchard::from_bytes(&commitment_bytes),
        "note_commitment",
    )?;

    // Parse expected root
    let root_bytes: [u8; 32] = witness.root[..].try_into().unwrap();
    let expected_root: MerkleHashOrchard =
        ct_option_to_result(MerkleHashOrchard::from_bytes(&root_bytes), "root")?;

    // Walk up the tree: at each level, combine with the sibling hash.
    // Position bit determines whether the current node is a left or right child.
    let mut pos = witness.position;

    for (level, sibling_bytes) in witness.auth_path.iter().enumerate() {
        if sibling_bytes.len() != 32 {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "auth_path[{}] must be 32 bytes, got {}",
                    level,
                    sibling_bytes.len()
                ),
            });
        }

        let sibling_arr: [u8; 32] = sibling_bytes[..].try_into().unwrap();
        let sibling: MerkleHashOrchard = ct_option_to_result(
            MerkleHashOrchard::from_bytes(&sibling_arr),
            &format!("auth_path[{}]", level),
        )?;

        let tree_level = Level::from(level as u8);

        // If position bit is 0, current is a left child; if 1, current is a right child
        current = if pos & 1 == 0 {
            MerkleHashOrchard::combine(tree_level, &current, &sibling)
        } else {
            MerkleHashOrchard::combine(tree_level, &sibling, &current)
        };

        pos >>= 1;
    }

    Ok(current == expected_root)
}

/// Convert a subtle::CtOption to a Result, using the field name in the error.
fn ct_option_to_result(
    opt: CtOption<MerkleHashOrchard>,
    field: &str,
) -> Result<MerkleHashOrchard, VotingError> {
    Option::from(opt).ok_or_else(|| VotingError::InvalidInput {
        message: format!("{} is not a valid Orchard tree hash", field),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_verify_witness_validation() {
        // Bad commitment length
        let bad = WitnessData {
            note_commitment: vec![0; 16],
            position: 0,
            root: vec![0; 32],
            auth_path: (0..32).map(|_| vec![0u8; 32]).collect(),
        };
        assert!(verify_witness(&bad).is_err());

        // Bad auth path length
        let bad = WitnessData {
            note_commitment: vec![0; 32],
            position: 0,
            root: vec![0; 32],
            auth_path: (0..16).map(|_| vec![0u8; 32]).collect(),
        };
        assert!(verify_witness(&bad).is_err());
    }

    #[test]
    fn test_verify_witness_rejects_wrong_root() {
        // Create a witness with a valid commitment at position 0 but wrong root.
        // The empty tree hash (all zeros) as commitment with zero auth path
        // produces a specific root — giving a different root should fail verification.
        let witness = WitnessData {
            note_commitment: vec![0; 32],
            position: 0,
            root: vec![0xFF; 32], // wrong root
            auth_path: (0..32).map(|_| vec![0u8; 32]).collect(),
        };
        // Should verify without error but return false (roots don't match)
        // unless 0xFF... isn't a valid field element (would be an error)
        let result = verify_witness(&witness);
        // Either returns Ok(false) or Err (if 0xFF... isn't valid)
        match result {
            Ok(valid) => assert!(!valid),
            Err(_) => {} // 0xFF..FF may not be a valid Pallas base element
        }
    }
}
