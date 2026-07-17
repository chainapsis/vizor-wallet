use std::panic;

use crate::wallet::{keys, network::WalletNetwork, transparent_receive_cache};
use tonic::{transport::Channel, Request};
use zcash_client_backend::proto::service::{
    self, compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

const SOFTWARE_ACCOUNT_DISCOVERY_MAX_INDEX: u32 = 20;
const SOFTWARE_ACCOUNT_DISCOVERY_BATCHES: &[(u32, u32)] = &[(1, 4), (5, 9), (10, 14), (15, 20)];
const SOFTWARE_ACCOUNT_BALANCE_PREVIEW_ADDRESSES_PER_SCOPE: u32 = 20;

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

/// Result of software mnemonic import with ZIP32 account discovery.
pub struct SoftwareWalletImportWithDiscoveryResult {
    pub accounts: Vec<SoftwareWalletImportAccount>,
    pub did_import_primary_account: bool,
}

/// A higher ZIP32 software account that can be imported by user choice.
pub struct SoftwareWalletDiscoveredAccount {
    pub zip32_account_index: u32,
    pub first_transparent_address: String,
}

/// Software account discovery result for an import attempt.
pub struct SoftwareWalletImportDiscoveryResult {
    pub primary_account_already_exists: bool,
    pub accounts: Vec<SoftwareWalletDiscoveredAccount>,
}

/// A software account created by mnemonic import.
pub struct SoftwareWalletImportAccount {
    pub account_uuid: String,
    pub unified_address: String,
    pub zip32_account_index: u32,
    pub name: String,
    pub is_seed_anchor: bool,
}

/// Account info returned by list_accounts.
pub struct AccountInfo {
    pub uuid: String,
    pub name: String,
    pub unified_address: String,
    pub is_seed_anchor: bool,
    pub is_hardware: bool,
}

/// Sensitive metadata for explicit encrypted wallet export flows.
pub struct AccountExportMetadata {
    pub zip32_account_index: Option<u32>,
    pub hardware_ufvk: Option<String>,
    pub seed_fingerprint: Option<Vec<u8>>,
}

/// Connected lightwalletd chain state relevant to Ironwood rollout decisions.
pub struct ChainUpgradeStatus {
    pub network: String,
    pub lightwalletd_chain_name: String,
    pub tip_height: u64,
    pub lightwalletd_reported_height: u64,
    pub lightwalletd_estimated_height: u64,
    pub lightwalletd_consensus_branch_id: String,
    pub lightwalletd_upgrade_name: String,
    pub lightwalletd_upgrade_height: u64,
    pub nu6_3_activation_height: Option<u64>,
    pub ironwood_active_at_tip: bool,
    pub endpoint_matches_network: bool,
}

/// Chain upgrade activation state computed from a known chain tip height.
pub struct ChainUpgradeActivationStatus {
    pub network: String,
    pub tip_height: u64,
    pub nu6_3_activation_height: Option<u64>,
    pub ironwood_active_at_tip: bool,
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

fn parse_network_and_migrate(db_path: &str, network: &str) -> Result<WalletNetwork, String> {
    let network = keys::parse_network(network)?;
    keys::ensure_db_migrated_once(db_path, network)?;
    Ok(network)
}

fn network_name(network: WalletNetwork) -> &'static str {
    match network {
        WalletNetwork::Main => "main",
        WalletNetwork::Test => "test",
        WalletNetwork::Regtest => "regtest",
    }
}

fn block_height_from_u64(height: u64) -> Result<BlockHeight, String> {
    let height = u32::try_from(height)
        .map_err(|_| format!("block height {height} exceeds supported range"))?;
    Ok(BlockHeight::from_u32(height))
}

fn is_ironwood_active_at_height(network: WalletNetwork, height: u64) -> Result<bool, String> {
    Ok(network.is_nu_active(NetworkUpgrade::Nu6_3, block_height_from_u64(height)?))
}

fn nu6_3_activation_height(network: WalletNetwork) -> Option<u64> {
    network
        .activation_height(NetworkUpgrade::Nu6_3)
        .map(|height| u32::from(height) as u64)
}

/// Get the latest block height from lightwalletd.
pub fn get_latest_block_height(lightwalletd_url: String) -> Result<u64, String> {
    catch(|| {
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(async {
            let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
                .await
                .map_err(|e| e.to_string())?;
            let tip = crate::wallet::sync_engine::get_latest_block(&mut client)
                .await
                .map_err(|e| e.to_string())?;

            Ok(tip.height)
        })
    })
}

/// Get the lightwalletd chain name ("main" or "test") for endpoint validation.
pub fn get_lightwalletd_chain_name(lightwalletd_url: String) -> Result<String, String> {
    catch(|| {
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(async {
            use zcash_client_backend::proto::service::Empty;

            let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
                .await
                .map_err(|e| e.to_string())?;
            let info = tokio::time::timeout(
                std::time::Duration::from_secs(10),
                client.get_lightd_info(Empty {}),
            )
            .await
            .map_err(|_| "get_lightd_info: timed out waiting for response".to_string())?
            .map_err(|e| format!("get_lightd_info: {e}"))?
            .into_inner();

            Ok(info.chain_name)
        })
    })
}

/// Get the connected chain upgrade state used to decide whether Ironwood is active.
pub fn get_chain_upgrade_status(
    lightwalletd_url: String,
    network: String,
) -> Result<ChainUpgradeStatus, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(async {
            use zcash_client_backend::proto::service::Empty;

            let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
                .await
                .map_err(|e| e.to_string())?;
            let tip = crate::wallet::sync_engine::get_latest_block(&mut client)
                .await
                .map_err(|e| e.to_string())?;
            let info = tokio::time::timeout(
                std::time::Duration::from_secs(10),
                client.get_lightd_info(Empty {}),
            )
            .await
            .map_err(|_| "get_lightd_info: timed out waiting for response".to_string())?
            .map_err(|e| format!("get_lightd_info: {e}"))?
            .into_inner();

            let expected_network = network_name(network).to_string();
            Ok(ChainUpgradeStatus {
                network: expected_network.clone(),
                endpoint_matches_network: info.chain_name == expected_network,
                lightwalletd_chain_name: info.chain_name,
                tip_height: tip.height,
                lightwalletd_reported_height: info.block_height,
                lightwalletd_estimated_height: info.estimated_height,
                lightwalletd_consensus_branch_id: info.consensus_branch_id,
                lightwalletd_upgrade_name: info.upgrade_name,
                lightwalletd_upgrade_height: info.upgrade_height,
                nu6_3_activation_height: nu6_3_activation_height(network),
                ironwood_active_at_tip: is_ironwood_active_at_height(network, tip.height)?,
            })
        })
    })
}

/// Compute chain upgrade activation state from a known chain tip height.
pub fn get_chain_upgrade_status_at_height(
    network: String,
    tip_height: u64,
) -> Result<ChainUpgradeActivationStatus, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        Ok(ChainUpgradeActivationStatus {
            network: network_name(network).to_string(),
            tip_height,
            nu6_3_activation_height: nu6_3_activation_height(network),
            ironwood_active_at_tip: is_ironwood_active_at_height(network, tip_height)?,
        })
    })
}

/// Create a new Zcash wallet with a fresh mnemonic.
/// birthday_height should be the current chain tip (from get_latest_block_height).
pub fn create_wallet(
    network: String,
    db_path: String,
    birthday_height: Option<u64>,
    account_name: Option<String>,
) -> Result<WalletCreationResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let mnemonic = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let name = account_name.as_deref().unwrap_or("Account 1");

        let (account_uuid, unified_address) =
            keys::init_db_and_create_account(&db_path, network, &seed, birthday_height, name)?;

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
    account_name: Option<String>,
) -> Result<WalletImportResult, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let name = account_name.as_deref().unwrap_or("Account 1");

        let (account_uuid, unified_address) =
            keys::init_db_and_create_account(&db_path, network, &seed, birthday_height, name)?;

        Ok(WalletImportResult {
            unified_address,
            account_uuid,
        })
    })
}

/// Add an additional account to an existing wallet database.
pub fn add_account(
    db_path: String,
    network: String,
    name: String,
    mnemonic: String,
    birthday_height: Option<u64>,
) -> Result<AccountCreationResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let seed = keys::mnemonic_to_seed(&mnemonic)?;

        // DB is already initialized by the first account — do not call ensure_db_initialized
        // with a different seed (seed fingerprint mismatch would cause an error).
        let (account_uuid, unified_address) =
            keys::add_account(&db_path, network, &name, &seed, birthday_height)?;

        Ok(AccountCreationResult {
            account_uuid,
            unified_address,
        })
    })
}

/// Discover higher ZIP32 software accounts with transparent history that are
/// not already present in the wallet DB for this mnemonic.
pub fn discover_software_wallet_import_accounts(
    mnemonic: String,
    birthday_height: Option<u64>,
    network: String,
    db_path: String,
    lightwalletd_url: String,
    is_first_wallet_account: bool,
) -> Result<SoftwareWalletImportDiscoveryResult, String> {
    catch(|| {
        let network = if is_first_wallet_account {
            keys::parse_network(&network)?
        } else {
            parse_network_and_migrate(&db_path, &network)?
        };
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let existing_seed_accounts = if is_first_wallet_account {
            None
        } else {
            Some(keys::existing_software_seed_account_state(
                &db_path, network, &seed,
            )?)
        };
        let primary_account_already_exists = existing_seed_accounts
            .as_ref()
            .is_some_and(|state| state.contains(0));

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let discovered_accounts = rt.block_on(discover_used_software_accounts(
            network,
            &seed,
            birthday_height,
            &lightwalletd_url,
        ));

        let accounts = discovered_accounts
            .into_iter()
            .filter(|account| {
                !existing_seed_accounts
                    .as_ref()
                    .is_some_and(|state| state.contains(account.zip32_account_index))
            })
            .collect();

        Ok(SoftwareWalletImportDiscoveryResult {
            primary_account_already_exists,
            accounts,
        })
    })
}

/// Preview the spendable transparent UTXO balance for a software ZIP32 account.
///
/// This does not import the account or touch the wallet DB. It checks a bounded
/// standard BIP44 transparent address range so the onboarding modal can update
/// balance rows after discovery has already returned.
pub fn preview_software_account_transparent_balance(
    mnemonic: String,
    network: String,
    lightwalletd_url: String,
    zip32_account_index: u32,
) -> Result<u64, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let addresses = keys::software_account_transparent_addresses(
            network,
            &seed,
            zip32_account_index,
            SOFTWARE_ACCOUNT_BALANCE_PREVIEW_ADDRESSES_PER_SCOPE,
        )?;

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        rt.block_on(preview_transparent_balance_for_addresses(
            &lightwalletd_url,
            addresses,
        ))
    })
}

/// Import a software mnemonic. `account'=0` must be imported successfully;
/// higher account indices are imported only when selected by the caller.
pub fn import_software_wallet_with_account_discovery(
    mnemonic: String,
    birthday_height: Option<u64>,
    network: String,
    db_path: String,
    first_account_name: Option<String>,
    is_first_wallet_account: bool,
    next_account_number: u32,
    additional_account_indices: Vec<u32>,
) -> Result<SoftwareWalletImportWithDiscoveryResult, String> {
    catch(|| {
        let network = if is_first_wallet_account {
            keys::parse_network(&network)?
        } else {
            parse_network_and_migrate(&db_path, &network)?
        };
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let first_account_number = next_account_number.max(1);
        let first_name = first_account_name
            .filter(|name| !name.trim().is_empty())
            .unwrap_or_else(|| format!("Account {first_account_number}"));
        let mut additional_account_indices = additional_account_indices;
        additional_account_indices.retain(|index| *index != 0);
        additional_account_indices.sort_unstable();
        additional_account_indices.dedup();

        import_discovered_software_wallet_accounts(
            network,
            &db_path,
            &seed,
            birthday_height,
            first_name,
            is_first_wallet_account,
            first_account_number,
            additional_account_indices,
        )
    })
}

/// Import exactly one software ZIP32 account for encrypted wallet-link imports.
///
/// Account 0 remains a Derived seed-anchor when it is the first wallet account.
/// If the first selected account is a higher ZIP32 index, the wallet is
/// initialized without a seed and that selected account is imported by UFVK so
/// the mobile import matches the user's selection instead of silently adding
/// account 0.
pub fn import_software_account_at_index(
    mnemonic: String,
    birthday_height: Option<u64>,
    network: String,
    db_path: String,
    name: String,
    zip32_account_index: u32,
    is_first_wallet_account: bool,
) -> Result<SoftwareWalletImportAccount, String> {
    catch(|| {
        let network = if is_first_wallet_account && zip32_account_index == 0 {
            keys::parse_network(&network)?
        } else {
            parse_network_and_migrate(&db_path, &network)?
        };
        let seed = keys::mnemonic_to_seed(&mnemonic)?;

        let (account_uuid, unified_address, is_seed_anchor) = if is_first_wallet_account {
            if zip32_account_index == 0 {
                let (account_uuid, unified_address) = keys::init_db_and_create_account(
                    &db_path,
                    network,
                    &seed,
                    birthday_height,
                    &name,
                )?;
                (account_uuid, unified_address, true)
            } else {
                let (account_uuid, unified_address) = keys::add_account_at_index(
                    &db_path,
                    network,
                    &name,
                    &seed,
                    birthday_height,
                    zip32_account_index,
                )?;
                (account_uuid, unified_address, false)
            }
        } else {
            let existing_seed_accounts =
                keys::existing_software_seed_account_state(&db_path, network, &seed)?;
            if existing_seed_accounts.contains(zip32_account_index) {
                return Err(keys::DUPLICATE_SOFTWARE_ACCOUNT_MESSAGE.to_string());
            }
            if existing_seed_accounts.has_derived_account {
                let (account_uuid, unified_address) = keys::import_derived_account_at_index(
                    &db_path,
                    network,
                    &seed,
                    birthday_height,
                    &name,
                    zip32_account_index,
                )?;
                (account_uuid, unified_address, true)
            } else {
                let (account_uuid, unified_address) = keys::add_account_at_index(
                    &db_path,
                    network,
                    &name,
                    &seed,
                    birthday_height,
                    zip32_account_index,
                )?;
                (account_uuid, unified_address, false)
            }
        };

        Ok(SoftwareWalletImportAccount {
            account_uuid,
            unified_address,
            zip32_account_index,
            name,
            is_seed_anchor,
        })
    })
}

pub fn is_software_wallet_link_account_imported(
    mnemonic: String,
    network: String,
    db_path: String,
    zip32_account_index: u32,
) -> Result<bool, String> {
    catch(|| {
        if !keys::wallet_exists(&db_path) {
            return Ok(false);
        }
        let network = parse_network_and_migrate(&db_path, &network)?;
        let seed = keys::mnemonic_to_seed(&mnemonic)?;
        let existing_seed_accounts =
            keys::existing_software_seed_account_state(&db_path, network, &seed)?;
        Ok(existing_seed_accounts.contains(zip32_account_index))
    })
}

fn import_discovered_software_wallet_accounts(
    network: WalletNetwork,
    db_path: &str,
    seed: &secrecy::SecretVec<u8>,
    birthday_height: Option<u64>,
    first_name: String,
    is_first_wallet_account: bool,
    first_account_number: u32,
    discovered_indices: Vec<u32>,
) -> Result<SoftwareWalletImportWithDiscoveryResult, String> {
    let existing_seed_accounts = if is_first_wallet_account {
        None
    } else {
        Some(keys::existing_software_seed_account_state(
            db_path, network, seed,
        )?)
    };
    let primary_already_exists = existing_seed_accounts
        .as_ref()
        .is_some_and(|state| state.contains(0));
    let import_as_derived = is_first_wallet_account
        || existing_seed_accounts
            .as_ref()
            .is_some_and(|state| state.has_derived_account);

    let mut accounts = Vec::new();
    let mut did_import_primary_account = false;
    if primary_already_exists {
        log::info!(
            "software account discovery: account 0 already exists for this mnemonic; scanning for higher accounts"
        );
    }

    if !primary_already_exists {
        let (account_uuid, unified_address) = if is_first_wallet_account {
            keys::init_db_and_create_account(db_path, network, seed, birthday_height, &first_name)?
        } else if import_as_derived {
            keys::import_derived_account_at_index(
                db_path,
                network,
                seed,
                birthday_height,
                &first_name,
                0,
            )?
        } else {
            keys::add_account_at_index(db_path, network, &first_name, seed, birthday_height, 0)?
        };

        accounts.push(SoftwareWalletImportAccount {
            account_uuid,
            unified_address,
            zip32_account_index: 0,
            name: first_name,
            is_seed_anchor: import_as_derived,
        });
        did_import_primary_account = true;
    }

    let mut next_name_number =
        first_account_number + if did_import_primary_account { 1 } else { 0 };
    let mut missing_account_import_error = None;
    for account_index in discovered_indices {
        if existing_seed_accounts
            .as_ref()
            .is_some_and(|state| state.contains(account_index))
        {
            log::info!(
                "software account discovery: account {account_index} already exists for this mnemonic"
            );
            continue;
        }

        let name = format!("Account {next_name_number}");
        let import_result = if import_as_derived {
            keys::import_derived_account_at_index(
                db_path,
                network,
                seed,
                birthday_height,
                &name,
                account_index,
            )
        } else {
            keys::add_account_at_index(
                db_path,
                network,
                &name,
                seed,
                birthday_height,
                account_index,
            )
        };

        match import_result {
            Ok((account_uuid, unified_address)) => {
                accounts.push(SoftwareWalletImportAccount {
                    account_uuid,
                    unified_address,
                    zip32_account_index: account_index,
                    name,
                    is_seed_anchor: import_as_derived,
                });
                next_name_number += 1;
            }
            Err(e) => {
                log::warn!(
                    "software account discovery: failed to import account {account_index}: {e}"
                );
                if e != keys::DUPLICATE_SOFTWARE_ACCOUNT_MESSAGE
                    && missing_account_import_error.is_none()
                {
                    missing_account_import_error = Some(e);
                }
            }
        }
    }

    if accounts.is_empty() {
        if let Some(error) = missing_account_import_error {
            return Err(error);
        }
        if existing_seed_accounts
            .as_ref()
            .is_some_and(|state| !state.is_empty())
        {
            return Err(keys::DUPLICATE_SOFTWARE_ACCOUNT_MESSAGE.to_string());
        }
    }

    Ok(SoftwareWalletImportWithDiscoveryResult {
        accounts,
        did_import_primary_account,
    })
}

async fn discover_used_software_accounts(
    network: WalletNetwork,
    seed: &secrecy::SecretVec<u8>,
    birthday_height: Option<u64>,
    lightwalletd_url: &str,
) -> Vec<SoftwareWalletDiscoveredAccount> {
    let start_height = discovery_start_height(network, birthday_height);
    let mut client = match crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url).await {
        Ok(client) => client,
        Err(e) => {
            log::warn!("software account discovery: could not open lightwalletd channel: {e}");
            return Vec::new();
        }
    };
    let tip = match crate::wallet::sync_engine::get_latest_block(&mut client).await {
        Ok(tip) => tip.height,
        Err(e) => {
            log::warn!("software account discovery: could not get chain tip: {e}");
            return Vec::new();
        }
    };
    if tip < start_height {
        log::warn!(
            "software account discovery: birthday height {start_height} is above chain tip {tip}"
        );
        return Vec::new();
    }

    let mut discovered = Vec::new();
    for &(start, end) in SOFTWARE_ACCOUNT_DISCOVERY_BATCHES {
        let mut found_in_batch = false;
        for account_index in start..=end.min(SOFTWARE_ACCOUNT_DISCOVERY_MAX_INDEX) {
            if let Some(account) = discover_software_account_at_index(
                &mut client,
                network,
                seed,
                account_index,
                start_height,
                tip,
            )
            .await
            {
                discovered.push(account);
                found_in_batch = true;
            }
        }
        if !found_in_batch {
            break;
        }
    }

    discovered
}

async fn discover_software_account_at_index(
    client: &mut CompactTxStreamerClient<Channel>,
    network: WalletNetwork,
    seed: &secrecy::SecretVec<u8>,
    account_index: u32,
    start_height: u64,
    tip_height: u64,
) -> Option<SoftwareWalletDiscoveredAccount> {
    let address = match keys::software_account_first_external_transparent_address(
        network,
        seed,
        account_index,
    ) {
        Ok(address) => address,
        Err(e) => {
            log::warn!(
                    "software account discovery: could not derive account {account_index} transparent address: {e}"
                );
            return None;
        }
    };

    let mut stream = match crate::wallet::sync_engine::get_taddress_txids(
        client,
        address.clone(),
        start_height,
        tip_height,
    )
    .await
    {
        Ok(stream) => stream,
        Err(e) => {
            log::warn!(
                "software account discovery: failed to query account {account_index} address {address} from {start_height} to {tip_height}: {e}"
            );
            return None;
        }
    };

    match crate::wallet::sync_engine::next_stream_message(
        &mut stream,
        "software account discovery get_taddress_txids stream",
    )
    .await
    {
        Ok(Some(_)) => {
            log::info!(
                "software account discovery: account {account_index} has transparent history"
            );
            Some(SoftwareWalletDiscoveredAccount {
                zip32_account_index: account_index,
                first_transparent_address: address,
            })
        }
        Ok(None) => None,
        Err(e) => {
            log::warn!(
                "software account discovery: failed while reading account {account_index} address {address} from {start_height} to {tip_height}: {e}"
            );
            None
        }
    }
}

fn discovery_start_height(network: WalletNetwork, birthday_height: Option<u64>) -> u64 {
    birthday_height.unwrap_or_else(|| {
        network
            .activation_height(NetworkUpgrade::Sapling)
            .map(|h| u32::from(h) as u64)
            .unwrap_or(0)
    })
}

async fn preview_transparent_balance_for_addresses(
    lightwalletd_url: &str,
    addresses: Vec<String>,
) -> Result<u64, String> {
    if addresses.is_empty() {
        return Ok(0);
    }

    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;
    let mut stream = client
        .get_address_utxos_stream(Request::new(service::GetAddressUtxosArg {
            addresses,
            start_height: 0,
            max_entries: 0,
        }))
        .await
        .map_err(|e| format!("get_address_utxos_stream: {e}"))?
        .into_inner();

    let mut balance = 0u64;
    while let Some(reply) = stream
        .message()
        .await
        .map_err(|e| format!("get_address_utxos_stream message: {e}"))?
    {
        let value = u64::try_from(reply.value_zat)
            .map_err(|_| format!("invalid transparent UTXO value: {}", reply.value_zat))?;
        balance = balance
            .checked_add(value)
            .ok_or_else(|| "transparent balance preview overflow".to_string())?;
    }

    Ok(balance)
}

/// Import a hardware wallet account using a UFVK (no mnemonic/seed needed).
pub fn import_hardware_account(
    db_path: String,
    network: String,
    name: String,
    ufvk_string: String,
    seed_fingerprint: Vec<u8>,
    zip32_index: u32,
    birthday_height: Option<u64>,
) -> Result<AccountCreationResult, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let (account_uuid, unified_address) = keys::import_hardware_account(
            &db_path,
            network,
            &name,
            &ufvk_string,
            &seed_fingerprint,
            zip32_index,
            birthday_height,
        )?;
        Ok(AccountCreationResult {
            account_uuid,
            unified_address,
        })
    })
}

/// List all accounts in the wallet database.
pub fn list_accounts(db_path: String, network: String) -> Result<Vec<AccountInfo>, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let accounts = keys::list_accounts(&db_path, network)?;
        Ok(accounts
            .into_iter()
            .map(|a| AccountInfo {
                uuid: a.uuid,
                name: a.name,
                unified_address: a.unified_address,
                is_seed_anchor: a.is_seed_anchor,
                is_hardware: a.is_hardware,
            })
            .collect())
    })
}

pub fn get_account_export_metadata(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<AccountExportMetadata, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        let metadata = keys::get_account_export_metadata(&db_path, network, &account_uuid)?;
        Ok(AccountExportMetadata {
            zip32_account_index: metadata.zip32_account_index,
            hardware_ufvk: metadata.hardware_ufvk,
            seed_fingerprint: metadata.seed_fingerprint,
        })
    })
}

/// Delete an account from the wallet database.
pub fn delete_account(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<(), String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        keys::delete_account(&db_path, network, &account_uuid)?;
        if let Err(e) = transparent_receive_cache::delete_account(&db_path, &account_uuid) {
            log::warn!(
                "transparent receive cache: failed to delete account {}: {}",
                account_uuid,
                e
            );
        }
        Ok(())
    })
}

/// Get the Unified Address for a specific account (or first account if uuid is None).
pub fn get_unified_address(
    db_path: String,
    network: String,
    account_uuid: Option<String>,
) -> Result<String, String> {
    catch(|| {
        let network = parse_network_and_migrate(&db_path, &network)?;
        keys::get_address_from_db(&db_path, network, account_uuid.as_deref())
    })
}

/// Generate a new 24-word BIP-39 mnemonic phrase.
#[flutter_rust_bridge::frb(sync)]
pub fn generate_mnemonic() -> String {
    keys::generate_mnemonic()
}

/// Get the BIP-39 English word list used for mnemonic validation.
#[flutter_rust_bridge::frb(sync)]
pub fn mnemonic_word_list() -> Vec<String> {
    keys::mnemonic_word_list()
}

/// Check if a wallet database exists at the given path.
#[flutter_rust_bridge::frb(sync)]
pub fn wallet_exists(db_path: String) -> bool {
    keys::wallet_exists(&db_path)
}

/// Ensure an existing wallet database has the schema required by this build.
pub fn ensure_wallet_db_migrated(db_path: String, network: String) -> Result<(), String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        keys::ensure_db_migrated_once(&db_path, network)
    })
}

/// Validate a mnemonic phrase (checks word count and validity).
#[flutter_rust_bridge::frb(sync)]
pub fn validate_mnemonic(mnemonic: String) -> bool {
    keys::mnemonic_to_seed(&mnemonic).is_ok()
}

/// Get the next transparent receive address for a specific account.
///
/// This is read-only: it returns the first tracked external transparent address
/// that has not received a transparent output.
pub fn get_transparent_receive_address(
    db_path: String,
    network: String,
    account_uuid: Option<String>,
) -> Result<String, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        if let Some(account_uuid) = account_uuid.as_deref() {
            match transparent_receive_cache::get_clean_address(&db_path, network, account_uuid) {
                Ok(Some(address)) => return Ok(address),
                Ok(None) => {}
                Err(e) => log::warn!("transparent receive cache: read failed: {e}"),
            }
        }

        keys::ensure_db_migrated_once(&db_path, network)?;
        match account_uuid.as_deref() {
            Some(account_uuid) => transparent_receive_cache::refresh_account_from_wallet_db(
                &db_path,
                network,
                account_uuid,
                None,
            ),
            None => keys::get_transparent_receive_address_from_db(&db_path, network, None),
        }
    })
}

pub fn get_recent_transparent_receive_addresses(
    db_path: String,
    network: String,
    account_uuid: Option<String>,
    limit: u32,
) -> Result<Vec<String>, String> {
    catch(|| {
        let network = keys::parse_network(&network)?;
        if let Some(account_uuid) = account_uuid.as_deref() {
            match transparent_receive_cache::get_recent_addresses(
                &db_path,
                network,
                account_uuid,
                limit,
            ) {
                Ok(Some(addresses)) => return Ok(addresses),
                Ok(None) => {}
                Err(e) => log::warn!("transparent receive cache: recent read failed: {e}"),
            }
        }

        keys::ensure_db_migrated_once(&db_path, network)?;
        if let Some(account_uuid) = account_uuid.as_deref() {
            match transparent_receive_cache::refresh_account_cache_from_wallet_db(
                &db_path,
                network,
                account_uuid,
                None,
            ) {
                Ok(()) => match transparent_receive_cache::get_recent_addresses(
                    &db_path,
                    network,
                    account_uuid,
                    limit,
                ) {
                    Ok(Some(addresses)) => return Ok(addresses),
                    Ok(None) => {}
                    Err(e) => log::warn!(
                        "transparent receive cache: recent read after refresh failed: {e}"
                    ),
                },
                Err(e) => log::warn!(
                    "transparent receive cache: recent refresh failed for account {}: {}",
                    account_uuid,
                    e
                ),
            }
        }

        keys::get_recent_transparent_receive_addresses_from_db(
            &db_path,
            network,
            account_uuid.as_deref(),
            limit,
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ironwood_activation_status_follows_nu6_3_height() {
        for network in [WalletNetwork::Main, WalletNetwork::Test] {
            let activation = nu6_3_activation_height(network).expect("NU6.3 activation height");
            assert!(activation > 0);
            assert!(!is_ironwood_active_at_height(network, activation - 1).unwrap());
            assert!(is_ironwood_active_at_height(network, activation).unwrap());
            assert!(is_ironwood_active_at_height(network, activation + 1).unwrap());
        }
    }

    #[test]
    fn chain_upgrade_status_at_height_reports_ironwood_activation() {
        let activation = nu6_3_activation_height(WalletNetwork::Main).unwrap();

        let before =
            get_chain_upgrade_status_at_height("main".to_string(), activation - 1).unwrap();
        assert_eq!(before.network, "main");
        assert_eq!(before.tip_height, activation - 1);
        assert_eq!(before.nu6_3_activation_height, Some(activation));
        assert!(!before.ironwood_active_at_tip);

        let at_activation =
            get_chain_upgrade_status_at_height("main".to_string(), activation).unwrap();
        assert_eq!(at_activation.tip_height, activation);
        assert!(at_activation.ironwood_active_at_tip);
    }

    #[test]
    fn regtest_ironwood_activation_status_uses_local_activation_height() {
        let activation = u32::MAX as u64;
        assert_eq!(
            nu6_3_activation_height(WalletNetwork::Regtest),
            Some(activation)
        );
        assert!(!is_ironwood_active_at_height(WalletNetwork::Regtest, activation - 1).unwrap());
        assert!(is_ironwood_active_at_height(WalletNetwork::Regtest, activation).unwrap());
    }

    #[test]
    fn test_reimport_existing_mnemonic_adds_only_missing_higher_accounts() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();
        let mnemonic = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&mnemonic).unwrap();

        keys::init_db_and_create_account(
            db_path_str,
            WalletNetwork::Main,
            &seed,
            None,
            "Account 1",
        )
        .unwrap();

        let result = import_discovered_software_wallet_accounts(
            WalletNetwork::Main,
            db_path_str,
            &seed,
            None,
            "Account 2".to_string(),
            false,
            2,
            vec![1],
        )
        .unwrap();

        assert!(!result.did_import_primary_account);
        assert_eq!(result.accounts.len(), 1);
        assert_eq!(result.accounts[0].zip32_account_index, 1);
        assert_eq!(result.accounts[0].name, "Account 2");
        assert!(result.accounts[0].is_seed_anchor);

        let state =
            keys::existing_software_seed_account_state(db_path_str, WalletNetwork::Main, &seed)
                .unwrap();
        assert!(state.contains(0));
        assert!(state.contains(1));
        assert!(state.has_derived_account);
    }

    #[test]
    fn test_reimport_existing_mnemonic_without_new_accounts_keeps_duplicate_error() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();
        let mnemonic = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&mnemonic).unwrap();

        keys::init_db_and_create_account(
            db_path_str,
            WalletNetwork::Main,
            &seed,
            None,
            "Account 1",
        )
        .unwrap();

        let error = match import_discovered_software_wallet_accounts(
            WalletNetwork::Main,
            db_path_str,
            &seed,
            None,
            "Account 2".to_string(),
            false,
            2,
            vec![],
        ) {
            Ok(_) => panic!("same mnemonic without missing accounts should fail"),
            Err(error) => error,
        };

        assert_eq!(error, keys::DUPLICATE_SOFTWARE_ACCOUNT_MESSAGE);
    }

    #[test]
    fn test_software_wallet_link_imported_preflight_matches_existing_index() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();
        let mnemonic = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&mnemonic).unwrap();

        keys::init_db_and_create_account(
            db_path_str,
            WalletNetwork::Main,
            &seed,
            None,
            "Account 1",
        )
        .unwrap();

        assert!(is_software_wallet_link_account_imported(
            mnemonic.clone(),
            "main".to_string(),
            db_path_str.to_string(),
            0,
        )
        .unwrap());
        assert!(!is_software_wallet_link_account_imported(
            mnemonic,
            "main".to_string(),
            db_path_str.to_string(),
            1,
        )
        .unwrap());
    }
}
