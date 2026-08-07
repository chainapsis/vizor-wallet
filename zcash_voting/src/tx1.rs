//! Compact effecting data for the Ironwood delegation signing transaction.
//!
//! TX1 remains a PCZT-only signing artifact. This encoding carries only the
//! fields needed to reconstruct its V6 shielded signature digest.
//!
//! Version 1 fixes the remaining profile to NU6.3, zero lock and expiry,
//! absent transparent, Sapling, and Orchard bundles, and one Ironwood V3
//! bundle with flags `0x07`, a positive 1-zatoshi value balance, and two
//! actions. V6 signatures do not commit to the shielded anchor.

use crate::VotingError;

/// Version byte for the current TX1 effects encoding.
pub const TX1_EFFECTS_VERSION: u8 = 1;
/// Number of Ironwood actions in the current TX1 construction.
pub const TX1_ACTION_COUNT: usize = 2;
/// Length of an Orchard/Ironwood encrypted note ciphertext.
pub const TX1_ENC_CIPHERTEXT_LEN: usize = 580;
/// Length of an Orchard/Ironwood outgoing ciphertext.
pub const TX1_OUT_CIPHERTEXT_LEN: usize = 80;
/// Length of one encoded Ironwood action's effecting data.
pub const TX1_ACTION_EFFECTS_LEN: usize =
    (5 * 32) + TX1_ENC_CIPHERTEXT_LEN + TX1_OUT_CIPHERTEXT_LEN;
/// Length of a versioned TX1 effects payload.
pub const TX1_EFFECTS_LEN: usize = 1 + (TX1_ACTION_COUNT * TX1_ACTION_EFFECTS_LEN);

/// Validates the framing shared by wallet and chain implementations.
///
/// This does not parse or validate the individual action fields.
pub fn validate_tx1_effects(effects: &[u8]) -> Result<(), VotingError> {
    if effects.len() != TX1_EFFECTS_LEN {
        return Err(VotingError::InvalidInput {
            message: format!(
                "tx1_effects must be {TX1_EFFECTS_LEN} bytes, got {}",
                effects.len()
            ),
        });
    }
    if effects[0] != TX1_EFFECTS_VERSION {
        return Err(VotingError::InvalidInput {
            message: format!(
                "unsupported tx1_effects version: expected {TX1_EFFECTS_VERSION}, got {}",
                effects[0]
            ),
        });
    }
    Ok(())
}

/// Encodes two finalized Ironwood actions as:
///
/// `version || (cv_net || nullifier || rk || cmx || ephemeral_key ||
/// enc_ciphertext || out_ciphertext) * 2`.
pub(crate) fn encode_tx1_effects(
    actions: &[pczt::orchard::Action],
) -> Result<Vec<u8>, VotingError> {
    if actions.len() != TX1_ACTION_COUNT {
        return Err(VotingError::Internal {
            message: format!(
                "delegation TX1 must contain {TX1_ACTION_COUNT} Ironwood actions, got {}",
                actions.len()
            ),
        });
    }

    let mut effects = Vec::with_capacity(TX1_EFFECTS_LEN);
    effects.push(TX1_EFFECTS_VERSION);

    for (index, action) in actions.iter().enumerate() {
        let cv_net = action
            .cv_net()
            .as_ref()
            .ok_or_else(|| VotingError::Internal {
                message: format!("TX1 action {index} is missing cv_net after IO finalization"),
            })?;
        let cmx = action
            .output()
            .cmx()
            .as_ref()
            .ok_or_else(|| VotingError::Internal {
                message: format!("TX1 action {index} is missing cmx after IO finalization"),
            })?;
        let enc_ciphertext = action
            .output()
            .enc_ciphertext()
            .clone()
            .into_encrypted()
            .ok_or_else(|| VotingError::Internal {
                message: format!(
                    "TX1 action {index} carries memo plaintext instead of encrypted ciphertext"
                ),
            })?;
        if enc_ciphertext.len() != TX1_ENC_CIPHERTEXT_LEN {
            return Err(VotingError::Internal {
                message: format!(
                    "TX1 action {index} enc_ciphertext must be {TX1_ENC_CIPHERTEXT_LEN} bytes, got {}",
                    enc_ciphertext.len()
                ),
            });
        }
        let out_ciphertext = action.output().out_ciphertext();
        if out_ciphertext.len() != TX1_OUT_CIPHERTEXT_LEN {
            return Err(VotingError::Internal {
                message: format!(
                    "TX1 action {index} out_ciphertext must be {TX1_OUT_CIPHERTEXT_LEN} bytes, got {}",
                    out_ciphertext.len()
                ),
            });
        }

        effects.extend_from_slice(cv_net);
        effects.extend_from_slice(action.spend().nullifier());
        effects.extend_from_slice(action.spend().rk());
        effects.extend_from_slice(cmx);
        effects.extend_from_slice(action.output().ephemeral_key());
        effects.extend_from_slice(&enc_ciphertext);
        effects.extend_from_slice(out_ciphertext);
    }

    validate_tx1_effects(&effects)?;
    Ok(effects)
}

#[cfg(test)]
pub(crate) fn placeholder_tx1_effects() -> Vec<u8> {
    let mut effects = vec![0; TX1_EFFECTS_LEN];
    effects[0] = TX1_EFFECTS_VERSION;
    effects
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
    use orchard::primitives::redpallas::{Signature, SpendAuth, VerificationKey};
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct Tx1EffectsFixture {
        format: String,
        transaction_version: u32,
        consensus_branch_id: String,
        lock_time: u32,
        expiry_height: u32,
        bundle_version: u32,
        bundle_flags: u8,
        value_balance_zat: i64,
        action_count: usize,
        action_index: usize,
        tx1_effects: String,
        sighash: String,
        rk: String,
        signed_note_nullifier: String,
        cmx_new: String,
        spend_auth_sig: String,
    }

    fn decode_array<const N: usize>(value: &str) -> [u8; N] {
        BASE64_STANDARD
            .decode(value)
            .unwrap()
            .try_into()
            .unwrap_or_else(|value: Vec<u8>| panic!("expected {N} bytes, got {}", value.len()))
    }

    #[test]
    fn validates_only_the_versioned_fixed_length_frame() {
        let effects = placeholder_tx1_effects();
        assert!(validate_tx1_effects(&effects).is_ok());

        assert!(validate_tx1_effects(&effects[..effects.len() - 1]).is_err());

        let mut unsupported = effects;
        unsupported[0] = TX1_EFFECTS_VERSION + 1;
        assert!(validate_tx1_effects(&unsupported).is_err());
    }

    #[test]
    fn fixture_matches_the_fixed_tx1_profile_and_signed_action() {
        let fixture: Tx1EffectsFixture = serde_json::from_str(include_str!(
            "../test-vectors/delegation_tx1_effects_v1.json"
        ))
        .unwrap();

        assert_eq!(fixture.format, "ironwood_tx1_effects_v1");
        assert_eq!(fixture.transaction_version, 6);
        assert_eq!(
            fixture.consensus_branch_id,
            format!(
                "{:08x}",
                u32::from(zcash_protocol::consensus::BranchId::Nu6_3)
            )
        );
        assert_eq!(fixture.lock_time, 0);
        assert_eq!(fixture.expiry_height, 0);
        assert_eq!(fixture.bundle_version, 3);
        assert_eq!(fixture.bundle_flags, 0x07);
        assert_eq!(fixture.value_balance_zat, 1);
        assert_eq!(fixture.action_count, TX1_ACTION_COUNT);
        assert!(fixture.action_index < TX1_ACTION_COUNT);

        let effects = BASE64_STANDARD.decode(&fixture.tx1_effects).unwrap();
        validate_tx1_effects(&effects).unwrap();
        let action_start = 1 + (fixture.action_index * TX1_ACTION_EFFECTS_LEN);
        assert_eq!(
            &effects[action_start + 32..action_start + 64],
            &decode_array::<32>(&fixture.signed_note_nullifier)
        );
        let rk = decode_array::<32>(&fixture.rk);
        assert_eq!(&effects[action_start + 64..action_start + 96], &rk);
        assert_eq!(
            &effects[action_start + 96..action_start + 128],
            &decode_array::<32>(&fixture.cmx_new)
        );

        let sighash = decode_array::<32>(&fixture.sighash);
        let signature = Signature::<SpendAuth>::from(decode_array::<64>(&fixture.spend_auth_sig));
        VerificationKey::<SpendAuth>::try_from(rk)
            .unwrap()
            .verify(&sighash, &signature)
            .unwrap();
    }
}
