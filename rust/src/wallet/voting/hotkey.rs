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
    zcash_voting::hotkey::voting_hotkey_from_seed(hotkey_secret.expose_secret(), network)
        .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))?;
    Ok(hotkey_secret)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_valid_random_hotkey_seed() {
        let seed =
            zcash_voting::hotkey::generate_random_voting_hotkey(zcash_voting::Network::Regtest)
                .unwrap();
        let validated =
            validated_hotkey_seed(seed.secret_seed().to_vec(), zcash_voting::Network::Regtest)
                .unwrap();
        assert_eq!(validated.expose_secret(), seed.secret_seed());
    }

    #[test]
    fn rejects_short_hotkey_seed() {
        let err = match validated_hotkey_seed(vec![1, 2, 3], zcash_voting::Network::Regtest) {
            Ok(_) => panic!("short hotkey seed unexpectedly validated"),
            Err(err) => err,
        };
        assert!(err.contains("seed must be at least 32 bytes"));
    }
}
