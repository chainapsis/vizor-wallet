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

/// Fetch lightwalletd-backed delegation inputs after local validation succeeds.
pub(super) async fn resolve_delegation_lwd_inputs(
    lightwalletd_url: &str,
    round_params: zcash_voting::wire::VotingRoundParams,
    round_name: &str,
    voting_network: zcash_voting::Network,
) -> Result<zcash_voting::delegate::DelegationLwdInputs, String> {
    zcash_voting::delegate::gather_delegation_lwd_inputs(
        zcash_voting::delegate::ResolveDelegationLwdParams {
            lightwalletd_url,
            network: voting_network,
            round_params,
            round_name,
        },
    )
    .await
    .map_err(|e| e.to_string())
}

/// Build the common `PrepareDelegationBundleParams` shape for wallet-layer
/// delegation helpers from API-owned inputs.
pub(super) fn prepare_delegation_bundle_params<'a>(
    lwd: zcash_voting::delegate::DelegationLwdInputs,
    session_json: Option<&'a str>,
    account_uuid: &'a str,
    voting_hotkey: &'a zcash_voting::VotingHotkey,
    bundle_index: u32,
    bundle_policy: zcash_voting::BundlePolicy,
) -> zcash_voting::delegate::PrepareDelegationBundleParams<'a> {
    zcash_voting::delegate::PrepareDelegationBundleParams {
        lwd,
        session_json,
        account_uuid,
        voting_hotkey,
        bundle_index,
        bundle_policy,
    }
}
