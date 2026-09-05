use secrecy::SecretVec;
use zcash_voting::VotingError;
use zeroize::Zeroizing;

use crate::wallet::{keys, voting::network::voting_network};

fn invalid_input(message: impl Into<String>) -> VotingError {
    VotingError::InvalidInput {
        message: message.into(),
    }
}

/// Convert API bundle-size input into a validated voting bundle policy.
///
/// The normal `None` path selects the frozen policy used to reconstruct v1
/// bundles after voting sidecar loss. Explicit test or development overrides
/// select a custom policy outside that recovery contract.
pub(super) fn bundle_policy(
    max_real_notes_per_bundle: Option<u32>,
) -> Result<zcash_voting::BundlePolicy, VotingError> {
    match max_real_notes_per_bundle {
        None => Ok(zcash_voting::recoverable_bundle_policy_v1()),
        Some(max_real_notes_per_bundle) => {
            zcash_voting::BundlePolicy::from_optional_max_real_notes_per_bundle(Some(
                max_real_notes_per_bundle,
            ))
        }
    }
}

/// Derive a wallet seed from a BIP-39 mnemonic while zeroizing mnemonic bytes.
pub(super) fn seed_from_mnemonic(mnemonic: String) -> Result<SecretVec<u8>, VotingError> {
    let mnemonic = Zeroizing::new(mnemonic.into_bytes());
    keys::mnemonic_bytes_to_seed(mnemonic.as_slice()).map_err(invalid_input)
}

/// Parse local delegation inputs that do not require lightwalletd network I/O.
pub(super) fn delegation_static_inputs(
    network: &str,
    max_real_notes_per_bundle: Option<u32>,
) -> Result<(zcash_voting::Network, zcash_voting::BundlePolicy), VotingError> {
    let wallet_network = keys::parse_network(network).map_err(invalid_input)?;
    let voting_network = voting_network(wallet_network);
    let bundle_policy = bundle_policy(max_real_notes_per_bundle)?;
    Ok((voting_network, bundle_policy))
}
