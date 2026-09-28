use rust_lib_zcash_wallet::{
    api::wallet::{gift_mnemonic_from_entropy, gift_mnemonic_to_entropy, validate_gift_address},
    wallet::{keys, network::WalletNetwork},
};
use secrecy::ExposeSecret;

#[test]
fn legacy_whitespace_preserves_the_funded_wallet_but_requires_v2_sharing() {
    for length in [16, 20, 24, 28, 32] {
        let entropy = vec![0; length];
        let canonical = gift_mnemonic_from_entropy(entropy.clone()).unwrap();
        let original_seed = keys::mnemonic_to_seed(&canonical).unwrap();
        let address =
            keys::derive_gift_address(WalletNetwork::Main, &original_seed, 0).unwrap();

        for separator in ["  ", "\t", "\n"] {
            let legacy = canonical.replace(' ', separator);
            let restored_seed = keys::mnemonic_to_seed(&legacy).unwrap();
            assert_eq!(original_seed.expose_secret(), restored_seed.expose_secret());
            validate_gift_address(legacy.clone(), "main".into(), address.clone()).unwrap();
            assert!(gift_mnemonic_to_entropy(legacy.clone()).is_err());

            // This normalization is for validation only. Dart retains the legacy
            // string in the v2 share URI, recovery record, and claim-cache key.
            let normalized = legacy.split_whitespace().collect::<Vec<_>>().join(" ");
            assert_eq!(gift_mnemonic_to_entropy(normalized).unwrap(), entropy);
            assert!(validate_gift_address(legacy, "main".into(), format!("{address}x")).is_err());
        }
    }
}
