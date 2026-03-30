use crate::wallet::keys;

/// Result of wallet creation, containing the mnemonic and unified address.
pub struct WalletCreationResult {
    pub mnemonic: String,
    pub unified_address: String,
}

/// Result of wallet import, containing the unified address.
pub struct WalletImportResult {
    pub unified_address: String,
}

/// Create a new Zcash wallet with a fresh mnemonic.
///
/// Returns the mnemonic phrase and the derived Unified Address.
/// The mnemonic must be securely stored by the caller (Dart side).
pub fn create_wallet(network: String, db_path: String) -> Result<WalletCreationResult, String> {
    let network = keys::parse_network(&network)?;
    let mnemonic = keys::generate_mnemonic();
    let seed = keys::mnemonic_to_seed(&mnemonic)?;

    let unified_address = keys::init_db_and_create_account(&db_path, network, &seed, None)?;

    Ok(WalletCreationResult {
        mnemonic,
        unified_address,
    })
}

/// Import an existing wallet from a mnemonic phrase.
///
/// Optionally specify a birthday height for faster sync.
pub fn import_wallet(
    mnemonic: String,
    birthday_height: Option<u64>,
    network: String,
    db_path: String,
) -> Result<WalletImportResult, String> {
    let network = keys::parse_network(&network)?;
    let seed = keys::mnemonic_to_seed(&mnemonic)?;

    let unified_address =
        keys::init_db_and_create_account(&db_path, network, &seed, birthday_height)?;

    Ok(WalletImportResult { unified_address })
}

/// Get the Unified Address for the wallet.
pub fn get_unified_address(db_path: String, network: String) -> Result<String, String> {
    let network = keys::parse_network(&network)?;
    keys::get_address_from_db(&db_path, network)
}

/// Check if a wallet database exists at the given path.
#[flutter_rust_bridge::frb(sync)]
pub fn wallet_exists(db_path: String) -> bool {
    keys::wallet_exists(&db_path)
}

/// Validate a mnemonic phrase (checks word count and validity).
#[flutter_rust_bridge::frb(sync)]
pub fn validate_mnemonic(mnemonic: String) -> bool {
    keys::mnemonic_to_seed(&mnemonic).is_ok()
}
