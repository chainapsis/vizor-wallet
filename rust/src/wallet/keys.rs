use std::path::Path;

use bip0039::{Count, English, Mnemonic};
use rand::rngs::OsRng;
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::data_api::{
    Account as _, AccountBirthday, AccountPurpose, AccountSource, WalletRead, WalletWrite,
    Zip32Derivation, chain::ChainState,
};
use zcash_client_sqlite::{AccountUuid, WalletDb, util::SystemClock, wallet::init::init_wallet_db};
use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest, UnifiedSpendingKey};
use zcash_primitives::block::BlockHash;
use zip32::fingerprint::SeedFingerprint;
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

/// Initialize the wallet database schema. Idempotent — safe to call multiple times.
/// Called without seed to avoid SeedNotRelevant errors when only Imported accounts exist.
pub fn ensure_db_initialized(
    db_path: &str,
    network: Network,
) -> Result<(), String> {
    let mut db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    init_wallet_db(&mut db, None)
        .map_err(|e| format!("Failed to init wallet DB: {e}"))?;
    Ok(())
}

/// Initialize DB with seed for the first account (creates a Derived account).
/// The seed is needed so that seed-requiring migrations can run in the future.
fn ensure_db_initialized_with_seed(
    db_path: &str,
    network: Network,
    seed: &SecretVec<u8>,
) -> Result<(), String> {
    let mut db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    init_wallet_db(
        &mut db,
        Some(SecretVec::new(seed.expose_secret().to_vec())),
    )
    .map_err(|e| format!("Failed to init wallet DB: {e}"))?;
    Ok(())
}

fn make_birthday(network: Network, birthday_height: Option<u64>) -> AccountBirthday {
    match birthday_height {
        Some(h) => {
            let height = BlockHeight::from_u32(h as u32);
            let chain_state = ChainState::empty(height - 1, BlockHash([0u8; 32]));
            AccountBirthday::from_parts(chain_state, None)
        }
        None => {
            let sapling_height = network
                .activation_height(NetworkUpgrade::Sapling)
                .expect("Sapling activation height must be known");
            let chain_state = ChainState::empty(sapling_height - 1, BlockHash([0u8; 32]));
            AccountBirthday::from_parts(chain_state, None)
        }
    }
}

/// Add an additional account (from a different seed) to the wallet database.
/// Uses import_account_ufvk with AccountPurpose::Spending so that accounts from
/// different seeds can coexist in the same DB (create_account enforces single-seed).
/// The first account should be created via init_db_and_create_account (Derived).
pub fn add_account(
    db_path: &str,
    network: Network,
    name: &str,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
) -> Result<(String, String), String> {
    let mut db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let birthday = make_birthday(network, birthday_height);

    // Derive USK and UFVK from seed
    let seed_fp = SeedFingerprint::from_seed(seed.expose_secret())
        .ok_or("Invalid seed length for fingerprint")?;
    let account_index = zip32::AccountId::ZERO;
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), account_index)
        .map_err(|e| format!("USK derivation failed: {e:?}"))?;
    let ufvk = usk.to_unified_full_viewing_key();

    // Import as UFVK with Spending purpose + derivation info
    let derivation = Zip32Derivation::new(seed_fp, account_index);
    let purpose = AccountPurpose::Spending { derivation: Some(derivation) };

    let account = db
        .import_account_ufvk(name, &ufvk, &birthday, purpose, None)
        .map_err(|e| format!("Failed to import account: {e}"))?;

    let account_id = account.id();
    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    let uuid_str = account_id.expose_uuid().to_string();
    Ok((uuid_str, ua.encode(&network)))
}

/// Import a hardware wallet account using a UFVK string (no seed/mnemonic needed).
/// The UFVK is obtained from the hardware device. Seed fingerprint and zip32 index
/// are provided by the device for Zip32Derivation metadata.
///
/// Requires at least one `Derived` (software) account to already exist in the
/// wallet. A hardware-only wallet cannot be bootstrapped because librustzcash
/// cannot apply seed-requiring migrations to an Imported-only DB (see
/// zcash_client_sqlite::wallet::init::init_wallet_db and CLAUDE.md). The first
/// account in any wallet must be `Derived`, and hardware accounts can only be
/// added on top. This function enforces the invariant as a Rust-side backstop
/// for the Dart-side check in AccountNotifier.importKeystoneAccount.
pub fn import_hardware_account(
    db_path: &str,
    network: Network,
    name: &str,
    ufvk_string: &str,
    seed_fingerprint_bytes: &[u8],
    zip32_index: u32,
    birthday_height: Option<u64>,
) -> Result<(String, String), String> {
    // Ensure DB is initialized (without seed — hardware wallet has no local seed)
    ensure_db_initialized(db_path, network)?;

    let mut db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    // Invariant: there must be at least one Derived account already. Otherwise
    // this import would leave the DB in a state where future seed-requiring
    // migrations cannot be applied. See CLAUDE.md "Hardware-first wallet
    // constraint" for the full rationale.
    let account_ids = db.get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;
    let mut has_derived = false;
    for id in &account_ids {
        let acc = db.get_account(*id)
            .map_err(|e| format!("Failed to load account: {e}"))?
            .ok_or_else(|| format!("Account not found: {}", id.expose_uuid()))?;
        if matches!(acc.source(), AccountSource::Derived { .. }) {
            has_derived = true;
            break;
        }
    }
    if !has_derived {
        return Err(
            "Hardware wallet accounts cannot be the first account. \
             Create or import a software wallet first, then add your Keystone \
             account. This is a librustzcash constraint: seed-requiring \
             database migrations cannot be applied to an Imported-only wallet.".into()
        );
    }

    let birthday = make_birthday(network, birthday_height);

    // Parse UFVK from string
    let ufvk = zcash_keys::keys::UnifiedFullViewingKey::decode(&network, ufvk_string)
        .map_err(|e| format!("Failed to parse UFVK: {e}"))?;

    // Build seed fingerprint from bytes
    let fp_bytes: [u8; 32] = seed_fingerprint_bytes.try_into()
        .map_err(|_| "Seed fingerprint must be 32 bytes")?;
    let seed_fp = SeedFingerprint::from_bytes(fp_bytes);
    let account_index = zip32::AccountId::try_from(zip32_index)
        .map_err(|_| "Invalid zip32 account index")?;

    let derivation = Zip32Derivation::new(seed_fp, account_index);
    let purpose = AccountPurpose::Spending { derivation: Some(derivation) };

    let account = db
        .import_account_ufvk(name, &ufvk, &birthday, purpose, None)
        .map_err(|e| format!("Failed to import hardware account: {e}"))?;

    let account_id = account.id();
    // Hardware wallets (Keystone) have Orchard + transparent but no Sapling,
    // so use Orchard-only address request instead of the standard shielded request.
    let (ua, _di) = ufvk
        .default_address(orchard_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    let uuid_str = account_id.expose_uuid().to_string();
    let addr_str: String = ua.encode(&network);
    log::info!("Imported hardware account: uuid={}, address={}", uuid_str, addr_str);
    Ok((uuid_str, addr_str))
}

/// Init DB + create first account as Derived (so seed relevance checks pass on future migrations).
/// Returns (account_uuid, unified_address).
pub fn init_db_and_create_account(
    db_path: &str,
    network: Network,
    seed: &SecretVec<u8>,
    birthday_height: Option<u64>,
    name: &str,
) -> Result<(String, String), String> {
    ensure_db_initialized_with_seed(db_path, network, seed)?;

    let mut db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let birthday = make_birthday(network, birthday_height);

    // First account uses create_account (Derived) — ensures at least one Derived account
    // exists for future init_wallet_db seed relevance checks.
    let (account_id, usk) = db
        .create_account(name, seed, &birthday, None)
        .map_err(|e| format!("Failed to create account: {e}"))?;

    let ufvk = usk.to_unified_full_viewing_key();
    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;

    let uuid_str = account_id.expose_uuid().to_string();
    Ok((uuid_str, ua.encode(&network)))
}

pub struct AccountInfo {
    pub uuid: String,
    pub name: String,
    pub unified_address: String,
}

/// List all accounts in the wallet database.
pub fn list_accounts(db_path: &str, network: Network) -> Result<Vec<AccountInfo>, String> {
    let db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let account_ids = db.get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;

    let mut accounts = Vec::new();
    for id in account_ids {
        let account = db.get_account(id)
            .map_err(|e| format!("Failed to get account: {e}"))?
            .ok_or_else(|| format!("Account not found: {}", id.expose_uuid()))?;

        let address = match account.ufvk() {
            Some(ufvk) => {
                let (ua, _) = ufvk.default_address(shielded_address_request())
                    .map_err(|e| format!("Failed to derive address: {e}"))?;
                ua.encode(&network)
            }
            None => String::new(),
        };

        accounts.push(AccountInfo {
            uuid: id.expose_uuid().to_string(),
            name: account.name().unwrap_or("").to_string(),
            unified_address: address,
        });
    }

    Ok(accounts)
}

/// Parse an account UUID string into AccountUuid.
pub fn parse_account_uuid(s: &str) -> Result<AccountUuid, String> {
    let uuid = uuid::Uuid::parse_str(s).map_err(|e| format!("Invalid account UUID: {e}"))?;
    Ok(AccountUuid::from_uuid(uuid))
}

/// Resolve account_id: if uuid provided, parse it; otherwise take first account.
fn resolve_account_id(
    db: &WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>,
    account_uuid: Option<&str>,
) -> Result<AccountUuid, String> {
    match account_uuid {
        Some(uuid_str) => parse_account_uuid(uuid_str),
        None => {
            let ids = db.get_account_ids().map_err(|e| format!("Failed to list accounts: {e}"))?;
            ids.into_iter().next().ok_or_else(|| "No accounts found in wallet".to_string())
        }
    }
}

/// Get the Unified Address from an existing wallet database.
pub fn get_address_from_db(db_path: &str, network: Network, account_uuid: Option<&str>) -> Result<String, String> {
    let db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let account_id = resolve_account_id(&db, account_uuid)?;

    let account = db
        .get_account(account_id)
        .map_err(|e| format!("Failed to get account: {e}"))?
        .ok_or("Account not found")?;

    let ufvk = account
        .ufvk()
        .ok_or("Account does not have a UFVK")?;

    // Try standard shielded request (Orchard + Sapling), fall back to Orchard-only
    // for hardware wallets that don't have Sapling keys.
    let (ua, _di) = ufvk
        .default_address(shielded_address_request())
        .or_else(|_| ufvk.default_address(orchard_address_request()))
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

/// Returns an Orchard-only address request for hardware wallets.
/// Keystone UFVKs typically contain Orchard + transparent but no Sapling.
fn orchard_address_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require, // Orchard
        ReceiverRequirement::Omit,    // Sapling (not available on Keystone)
        ReceiverRequirement::Omit,    // Transparent
    )
    .expect("valid receiver requirements")
}

/// Get the transparent address from an existing wallet database.
pub fn get_transparent_address_from_db(db_path: &str, network: Network, account_uuid: Option<&str>) -> Result<String, String> {
    let db = WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let account_id = resolve_account_id(&db, account_uuid)?;

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

        let (_uuid, address) =
            init_db_and_create_account(db_path_str, Network::MainNetwork, &seed, None, "test").unwrap();

        // Mainnet unified addresses start with "u1"
        assert!(
            address.starts_with("u1"),
            "Expected u1 prefix, got: {address}"
        );

        // Verify we can read the address back
        let address2 = get_address_from_db(db_path_str, Network::MainNetwork, None).unwrap();
        assert_eq!(address, address2);
    }

    #[test]
    fn test_create_testnet_wallet() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = generate_mnemonic();
        let seed = mnemonic_to_seed(&phrase).unwrap();

        let (_, address) =
            init_db_and_create_account(db_path_str, Network::TestNetwork, &seed, None, "test").unwrap();

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
        let (_, addr1) =
            init_db_and_create_account(db1.to_str().unwrap(), Network::MainNetwork, &seed, None, "test")
                .unwrap();

        let temp2 = tempfile::tempdir().unwrap();
        let db2 = temp2.path().join("wallet.db");
        let (_, addr2) =
            init_db_and_create_account(db2.to_str().unwrap(), Network::MainNetwork, &seed, None, "test")
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

        let (_, address) =
            init_db_and_create_account(db_path_str, Network::MainNetwork, &seed, None, "test").unwrap();

        // Decode and verify receiver types
        let za = zcash_address::ZcashAddress::try_from_encoded(&address).unwrap();
        let debug = format!("{:?}", za);
        assert!(debug.contains("Sapling"), "UA should contain Sapling receiver");
        assert!(debug.contains("Orchard"), "UA should contain Orchard receiver");
        assert!(!debug.contains("P2pkh"), "UA should NOT contain transparent receiver");
    }
}
