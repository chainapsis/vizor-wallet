use std::path::Path;

use bip0039::{Count, English, Mnemonic};
use rand::rngs::OsRng;
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::data_api::{
    Account as _, AccountBirthday, WalletRead, WalletWrite,
    chain::ChainState,
};
use zcash_client_sqlite::{WalletDb, util::SystemClock, wallet::init::init_wallet_db};
use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, Network, NetworkUpgrade, Parameters};

/// Generate a new 24-word BIP-39 mnemonic phrase.
pub fn generate_mnemonic() -> String {
    let mnemonic = Mnemonic::<English>::generate(Count::Words24);
    mnemonic.phrase().to_string()
}

/// Convert a mnemonic phrase to a 64-byte seed wrapped in SecretVec.
/// The seed is zeroized from memory when the SecretVec is dropped.
pub fn mnemonic_to_seed(phrase: &str) -> Result<SecretVec<u8>, String> {
    let mnemonic = Mnemonic::<English>::from_phrase(phrase)
        .map_err(|e| format!("Invalid mnemonic: {e}"))?;
    Ok(SecretVec::new(mnemonic.to_seed("").to_vec()))
}

/// Parse network string to Network enum.
pub fn parse_network(network: &str) -> Result<Network, String> {
    match network {
        "main" => Ok(Network::MainNetwork),
        "test" => Ok(Network::TestNetwork),
        _ => Err(format!("Unknown network: {network}")),
    }
}

/// Initialize the wallet database and create an account from a seed.
/// Returns the Unified Address string.
pub fn init_db_and_create_account(
    db_path: &str,
    network: Network,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
) -> Result<String, String> {
    let mut db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    init_wallet_db(
        &mut db,
        Some(SecretVec::new(seed.expose_secret().to_vec())),
    )
    .map_err(|e| format!("Failed to init wallet DB: {e}"))?;

    let birthday = match birthday_height {
        Some(h) => {
            let height = BlockHeight::from_u32(h as u32);
            let prior_height = height - 1;
            let chain_state = ChainState::empty(prior_height, BlockHash([0u8; 32]));
            AccountBirthday::from_parts(chain_state, None)
        }
        None => {
            // For new wallets, use Sapling activation as default
            let sapling_height = network
                .activation_height(NetworkUpgrade::Sapling)
                .expect("Sapling activation height must be known");
            let chain_state =
                ChainState::empty(sapling_height - 1, BlockHash([0u8; 32]));
            AccountBirthday::from_parts(chain_state, None)
        }
    };

    let (_account_id, usk) = db
        .create_account("default", &seed, &birthday, None)
        .map_err(|e| format!("Failed to create account: {e}"))?;

    let ufvk = usk.to_unified_full_viewing_key();
    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    Ok(ua.encode(&network))
}

/// Get the Unified Address from an existing wallet database.
pub fn get_address_from_db(db_path: &str, network: Network) -> Result<String, String> {
    let db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let accounts = db
        .get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;

    let account_id = accounts
        .into_iter()
        .next()
        .ok_or("No accounts found in wallet")?;

    let account = db
        .get_account(account_id)
        .map_err(|e| format!("Failed to get account: {e}"))?
        .ok_or("Account not found")?;

    let ufvk = account
        .ufvk()
        .ok_or("Account does not have a UFVK")?;

    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    Ok(ua.encode(&network))
}

/// Returns the standard shielded address request (Orchard + Sapling, no transparent).
/// This matches the behavior of zodl/Zashi wallets.
fn shielded_address_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require, // Orchard
        ReceiverRequirement::Require, // Sapling
        ReceiverRequirement::Omit,    // Transparent
    )
    .expect("valid receiver requirements")
}

/// Get the transparent address from an existing wallet database.
pub fn get_transparent_address_from_db(db_path: &str, network: Network) -> Result<String, String> {
    let db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let accounts = db
        .get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;

    let account_id = accounts
        .into_iter()
        .next()
        .ok_or("No accounts found in wallet")?;

    let account = db
        .get_account(account_id)
        .map_err(|e| format!("Failed to get account: {e}"))?
        .ok_or("Account not found")?;

    let ufvk = account
        .ufvk()
        .ok_or("Account does not have a UFVK")?;

    let transparent_req = UnifiedAddressRequest::custom(
        ReceiverRequirement::Omit,    // Orchard
        ReceiverRequirement::Omit,    // Sapling
        ReceiverRequirement::Require, // Transparent
    )
    .map_err(|_| "Failed to create transparent address request")?;

    let (ua, _di) = ufvk
        .default_address(transparent_req)
        .map_err(|e| format!("Failed to derive transparent address: {e}"))?;

    Ok(ua.encode(&network))
}

/// Validate that a wallet database exists and has at least one account.
pub fn wallet_exists(db_path: &str) -> bool {
    Path::new(db_path).exists()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_mnemonic_is_24_words() {
        let phrase = generate_mnemonic();
        let words: Vec<&str> = phrase.split_whitespace().collect();
        assert_eq!(words.len(), 24);
    }

    #[test]
    fn test_mnemonic_to_seed_roundtrip() {
        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();
        assert_eq!(seed.expose_secret().len(), 64);
    }

    #[test]
    fn test_invalid_mnemonic() {
        let result = mnemonic_to_seed("invalid words here");
        assert!(result.is_err());
    }

    #[test]
    fn test_parse_network() {
        assert!(matches!(parse_network("main"), Ok(Network::MainNetwork)));
        assert!(matches!(parse_network("test"), Ok(Network::TestNetwork)));
        assert!(parse_network("invalid").is_err());
    }

    #[test]
    fn test_create_wallet_and_get_address() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let address =
            init_db_and_create_account(db_path_str, Network::MainNetwork, &seed, None).unwrap();

        // Mainnet unified addresses start with "u1"
        assert!(
            address.starts_with("u1"),
            "Expected u1 prefix, got: {address}"
        );

        // Verify we can read the address back
        let address2 = get_address_from_db(db_path_str, Network::MainNetwork).unwrap();
        assert_eq!(address, address2);
    }

    #[test]
    fn test_create_testnet_wallet() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let address =
            init_db_and_create_account(db_path_str, Network::TestNetwork, &seed, None).unwrap();

        assert!(
            address.starts_with("utest1"),
            "Expected utest1 prefix, got: {address}"
        );
    }

    #[test]
    fn test_deterministic_address_from_same_seed() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
        let seed = mnemonic_to_seed(phrase).unwrap();

        let temp1 = tempfile::tempdir().unwrap();
        let db1 = temp1.path().join("wallet.db");
        let addr1 =
            init_db_and_create_account(db1.to_str().unwrap(), Network::MainNetwork, &seed, None)
                .unwrap();

        let temp2 = tempfile::tempdir().unwrap();
        let db2 = temp2.path().join("wallet.db");
        let addr2 =
            init_db_and_create_account(db2.to_str().unwrap(), Network::MainNetwork, &seed, None)
                .unwrap();

        assert_eq!(addr1, addr2, "Same seed should produce same address");
    }

    #[test]
    fn test_shielded_address_has_sapling_and_orchard_only() {
        // Verify our address uses Sapling+Orchard receivers (no transparent),
        // matching zodl/Zashi wallet behavior.
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let address =
            init_db_and_create_account(db_path_str, Network::MainNetwork, &seed, None).unwrap();

        // Decode and verify receiver types
        let za = zcash_address::ZcashAddress::try_from_encoded(&address).unwrap();
        let debug = format!("{:?}", za);
        assert!(debug.contains("Sapling"), "UA should contain Sapling receiver");
        assert!(debug.contains("Orchard"), "UA should contain Orchard receiver");
        assert!(!debug.contains("P2pkh"), "UA should NOT contain transparent receiver");
    }
}
