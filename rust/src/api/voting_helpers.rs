use secrecy::SecretVec;
use zeroize::Zeroizing;

use crate::wallet::{keys, voting::network::voting_network};

/// Convert API bundle-size input into a validated voting bundle policy.
pub(super) fn bundle_policy(
    max_real_notes_per_bundle: Option<u32>,
) -> Result<zcash_voting::BundlePolicy, String> {
    zcash_voting::BundlePolicy::from_optional_max_real_notes_per_bundle(max_real_notes_per_bundle)
        .map_err(|e| e.to_string())
}

/// Derive a wallet seed from a BIP-39 mnemonic while zeroizing mnemonic bytes.
pub(super) fn seed_from_mnemonic(mnemonic: String) -> Result<SecretVec<u8>, String> {
    let mnemonic = Zeroizing::new(mnemonic.into_bytes());
    keys::mnemonic_bytes_to_seed(mnemonic.as_slice())
}

/// Parse local delegation inputs that do not require lightwalletd network I/O.
pub(super) fn delegation_static_inputs(
    network: &str,
    max_real_notes_per_bundle: Option<u32>,
) -> Result<(zcash_voting::Network, zcash_voting::BundlePolicy), String> {
    let wallet_network = keys::parse_network(network)?;
    let voting_network = voting_network(wallet_network);
    let bundle_policy = bundle_policy(max_real_notes_per_bundle)?;
    Ok((voting_network, bundle_policy))
}
