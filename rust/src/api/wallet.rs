use std::panic;

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

/// Catches panics and converts them to Result<T, String>.
fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(format!("Rust panic: {msg}"))
        }
    }
}

/// Create a new Zcash wallet with a fresh mnemonic.
pub fn create_wallet(network: String, db_path: String) -> Result<WalletCreationResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let mnemonic = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&mnemonic)?;

        let unified_address = keys::init_db_and_create_account(&db_path, network, &seed, None)?;

        Ok(WalletCreationResult {
            mnemonic,
            unified_address,
        })
    })
}

/// Import an existing wallet from a mnemonic phrase.
pub fn import_wallet(
    mnemonic: String,
    birthday_height: Option<u64>,
    network: String,
    db_path: String,
) -> Result<WalletImportResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let seed = keys::mnemonic_to_seed(&mnemonic)?;

        let unified_address =
            keys::init_db_and_create_account(&db_path, network, &seed, birthday_height)?;

        Ok(WalletImportResult { unified_address })
    })
}

/// Get the Unified Address for the wallet.
pub fn get_unified_address(db_path: String, network: String) -> Result<String, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        keys::get_address_from_db(&db_path, network)
    })
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

/// Get the transparent address for the wallet (separate from the shielded UA).
pub fn get_transparent_address(db_path: String, network: String) -> Result<String, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        keys::get_transparent_address_from_db(&db_path, network)
    })
}
