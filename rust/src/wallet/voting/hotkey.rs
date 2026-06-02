use zeroize::Zeroizing;

/// Reconstructs a voting hotkey from stored opaque hotkey bytes.
///
/// Returns the typed hotkey accepted by `zcash_voting`.
///
/// # Errors
///
/// Returns an error if the stored bytes are not valid hotkey material for the
/// supplied voting network.
pub fn voting_hotkey_from_stored_secret(
    stored_hotkey_secret: Vec<u8>,
    network: zcash_voting::Network,
) -> Result<zcash_voting::VotingHotkey, String> {
    let stored_hotkey_secret = Zeroizing::new(stored_hotkey_secret);
    zcash_voting::VotingHotkey::from_stored_secret(stored_hotkey_secret.as_slice(), network)
        .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_valid_stored_hotkey_secret() {
        let hotkey =
            zcash_voting::hotkey::generate_random_voting_hotkey(zcash_voting::Network::Regtest)
                .unwrap();
        let validated = voting_hotkey_from_stored_secret(
            hotkey.stored_secret().to_vec(),
            zcash_voting::Network::Regtest,
        )
        .unwrap();
        assert_eq!(validated.stored_secret(), hotkey.stored_secret());
    }

    #[test]
    fn rejects_short_stored_hotkey_secret() {
        let err =
            match voting_hotkey_from_stored_secret(vec![1, 2, 3], zcash_voting::Network::Regtest) {
                Ok(_) => panic!("short hotkey secret unexpectedly validated"),
                Err(err) => err,
            };
        assert!(err.contains("stored hotkey secret must be at least 32 bytes"));
    }
}
