use std::panic;

use secrecy::ExposeSecret;

use crate::wallet::keys;

/// Result of wallet creation, containing the mnemonic, unified address, and account UUID.
pub struct WalletCreationResult {
    pub mnemonic: String,
    pub unified_address: String,
    pub account_uuid: String,
}

/// Result of wallet import, containing the unified address and account UUID.
pub struct WalletImportResult {
    pub unified_address: String,
    pub account_uuid: String,
}

/// Result of adding an account to an existing wallet.
pub struct AccountCreationResult {
    pub account_uuid: String,
    pub unified_address: String,
}

/// Account info returned by list_accounts.
pub struct AccountInfo {
    pub uuid: String,
    pub name: String,
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

/// Get the latest block height from lightwalletd.
pub fn get_latest_block_height(lightwalletd_url: String) -> Result<u64, String> {
    catch(|| {
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(async {
            use tonic::transport::{ClientTlsConfig, Endpoint};
            use zcash_client_backend::proto::service::{
                compact_tx_streamer_client::CompactTxStreamerClient, ChainSpec,
            };

            let channel = Endpoint::from_shared(lightwalletd_url)
                .map_err(|e| format!("Invalid URL: {e}"))?
                .tls_config(ClientTlsConfig::new().with_webpki_roots())
                .map_err(|e| format!("TLS error: {e}"))?
                .connect()
                .await
                .map_err(|e| format!("gRPC connect failed: {e}"))?;

            let mut client = CompactTxStreamerClient::new(channel);
            let tip = client
                .get_latest_block(ChainSpec::default())
                .await
                .map_err(|e| format!("get_latest_block: {e}"))?
                .into_inner();

            Ok(tip.height)
        })
    })
}

/// Create a new Zcash wallet with a fresh mnemonic.
/// birthday_height should be the current chain tip (from get_latest_block_height).
pub fn create_wallet(network: String, db_path: String, birthday_height: Option<u64>) -> Result<WalletCreationResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let mnemonic = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&mnemonic)?;

        let (account_uuid, unified_address) = keys::init_db_and_create_account(&db_path, network, &seed, birthday_height)?;

        Ok(WalletCreationResult {
            mnemonic,
            unified_address,
            account_uuid,
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

        let (account_uuid, unified_address) =
            keys::init_db_and_create_account(&db_path, network, &seed, birthday_height)?;

        Ok(WalletImportResult { unified_address, account_uuid })
    })
}

/// Add an additional account to an existing wallet database.
pub fn add_account(
    db_path: String, network: String, name: String,
    mnemonic: String, birthday_height: Option<u64>,
) -> Result<AccountCreationResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let seed = keys::mnemonic_to_seed(&mnemonic)?;

        keys::ensure_db_initialized(&db_path, network, &seed)?;
        let (account_uuid, unified_address) =
            keys::add_account(&db_path, network, &name, &seed, birthday_height)?;

        Ok(AccountCreationResult { account_uuid, unified_address })
    })
}

/// List all accounts in the wallet database.
pub fn list_accounts(db_path: String, network: String) -> Result<Vec<AccountInfo>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let accounts = keys::list_accounts(&db_path, network)?;
        Ok(accounts.into_iter().map(|a| AccountInfo {
            uuid: a.uuid,
            name: a.name,
            unified_address: a.unified_address,
        }).collect())
    })
}

/// Get the Unified Address for a specific account (or first account if uuid is None).
pub fn get_unified_address(db_path: String, network: String, account_uuid: Option<String>) -> Result<String, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        keys::get_address_from_db(&db_path, network, account_uuid.as_deref())
    })
}

/// Generate a new 24-word BIP-39 mnemonic phrase.
#[flutter_rust_bridge::frb(sync)]
pub fn generate_mnemonic() -> String {
    keys::generate_mnemonic()
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

/// Derive seed bytes from a mnemonic phrase.
/// Returns 64 raw bytes. The caller should treat these as sensitive.
pub fn derive_seed(mnemonic: String) -> Result<Vec<u8>, String> {
    catch(|| {
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        Ok(seed.expose_secret().to_vec())
    })
}

/// Get the transparent address for a specific account (or first account if uuid is None).
pub fn get_transparent_address(db_path: String, network: String, account_uuid: Option<String>) -> Result<String, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        keys::get_transparent_address_from_db(&db_path, network, account_uuid.as_deref())
    })
}
