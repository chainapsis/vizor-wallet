use secrecy::{ExposeSecret, SecretVec};

/// Wraps hotkey seed bytes and verifies they reconstruct for `network`.
///
/// Returns the seed as a `SecretVec` when it is accepted by `zcash_voting`.
///
/// # Errors
///
/// Returns an error if the seed bytes are not valid hotkey material for the
/// supplied voting network.
pub fn validated_hotkey_seed(
    hotkey_seed: Vec<u8>,
    network: zcash_voting::Network,
) -> Result<SecretVec<u8>, String> {
    let hotkey_secret = SecretVec::new(hotkey_seed);
    zcash_voting::VotingHotkey::from_stored_secret(hotkey_secret.expose_secret(), network)
        .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))?;
    Ok(hotkey_secret)
}

/// Validates and reconstructs a stored voting hotkey secret for `network`.
pub fn voting_hotkey_from_stored_secret(
    stored_hotkey_secret: Vec<u8>,
    network: zcash_voting::Network,
) -> Result<zcash_voting::VotingHotkey, String> {
    let stored_hotkey_secret = validated_hotkey_seed(stored_hotkey_secret, network)?;
    zcash_voting::VotingHotkey::from_stored_secret(stored_hotkey_secret.expose_secret(), network)
        .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validated_hotkey_seed_accepts_valid_secret() {
        let secret = vec![0xAB; 64];
        let validated =
            validated_hotkey_seed(secret.clone(), zcash_voting::Network::Regtest).unwrap();
        assert_eq!(validated.expose_secret(), secret.as_slice());
    }

    #[test]
    fn validated_hotkey_seed_rejects_short_secret() {
        let err = match validated_hotkey_seed(vec![1, 2, 3], zcash_voting::Network::Regtest) {
            Ok(_) => panic!("short secret should fail"),
            Err(err) => err,
        };
        assert!(err.contains("stored hotkey secret must be exactly 64 bytes"));
    }
}
