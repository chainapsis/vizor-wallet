use std::{
    path::{Path, PathBuf},
    sync::{Mutex, OnceLock},
};

use redb::{Database, ReadableDatabase, ReadableTable, TableDefinition};
use serde::{Deserialize, Serialize};

use crate::wallet::{keys, network::WalletNetwork};

pub(crate) const RECEIVE_CACHE_SIDECAR_SUFFIX: &str = ".receive.redb";
const CACHE_VERSION: u32 = 2;
const CACHE_TABLE: TableDefinition<&str, &str> = TableDefinition::new("transparent_receive");

#[cfg(any(target_os = "android", target_os = "ios"))]
const REDB_CACHE_SIZE_BYTES: usize = 256 * 1024;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
const REDB_CACHE_SIZE_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct CacheRecord {
    version: u32,
    network: String,
    dirty: bool,
    refreshed_scanned_height: Option<u64>,
    external_addresses: Vec<CachedExternalAddress>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct CachedExternalAddress {
    child_index: u32,
    address: String,
    has_received: bool,
}

pub(crate) fn sidecar_path(db_path: &str) -> PathBuf {
    PathBuf::from(format!("{db_path}{RECEIVE_CACHE_SIDECAR_SUFFIX}"))
}

pub(crate) fn get_clean_address(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<String>, String> {
    with_cache_lock(|| {
        let path = sidecar_path(db_path);
        if !path.exists() {
            return Ok(None);
        }

        let db = open_existing_db(&path)?;
        let read_txn = db
            .begin_read()
            .map_err(|e| format!("transparent receive cache read txn: {e}"))?;
        let table = match read_txn.open_table(CACHE_TABLE) {
            Ok(table) => table,
            Err(redb::TableError::TableDoesNotExist(_)) => return Ok(None),
            Err(e) => return Err(format!("transparent receive cache open table: {e}")),
        };
        let Some(value) = table
            .get(account_uuid)
            .map_err(|e| format!("transparent receive cache get: {e}"))?
        else {
            return Ok(None);
        };

        let Some(record) = clean_record_from_json(value.value(), network)? else {
            return Ok(None);
        };

        Ok(keys::first_unused_external_transparent_address(
            &record.as_external_transparent_addresses(),
        ))
    })
}

pub(crate) fn get_recent_addresses(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    limit: u32,
) -> Result<Option<Vec<String>>, String> {
    if limit == 0 {
        return Ok(Some(Vec::new()));
    }

    with_cache_lock(|| {
        let path = sidecar_path(db_path);
        if !path.exists() {
            return Ok(None);
        }

        let db = open_existing_db(&path)?;
        let read_txn = db
            .begin_read()
            .map_err(|e| format!("transparent receive cache read txn: {e}"))?;
        let table = match read_txn.open_table(CACHE_TABLE) {
            Ok(table) => table,
            Err(redb::TableError::TableDoesNotExist(_)) => return Ok(None),
            Err(e) => return Err(format!("transparent receive cache open table: {e}")),
        };
        let Some(value) = table
            .get(account_uuid)
            .map_err(|e| format!("transparent receive cache get: {e}"))?
        else {
            return Ok(None);
        };

        let Some(record) = clean_record_from_json(value.value(), network)? else {
            return Ok(None);
        };
        Ok(Some(keys::recent_external_transparent_addresses(
            &record.as_external_transparent_addresses(),
            limit.min(100) as usize,
        )))
    })
}

pub(crate) fn mark_account_dirty(db_path: &str, account_uuid: &str) -> Result<(), String> {
    with_cache_lock(|| {
        let path = sidecar_path(db_path);
        if !path.exists() {
            return Ok(());
        }

        let db = open_existing_db(&path)?;
        let write_txn = db
            .begin_write()
            .map_err(|e| format!("transparent receive cache write txn: {e}"))?;
        {
            let mut table = write_txn
                .open_table(CACHE_TABLE)
                .map_err(|e| format!("transparent receive cache open table: {e}"))?;
            let encoded_record = {
                let Some(value) = table
                    .get(account_uuid)
                    .map_err(|e| format!("transparent receive cache get: {e}"))?
                else {
                    return Ok(());
                };
                value.value().to_string()
            };
            let mut record: CacheRecord = serde_json::from_str(&encoded_record)
                .map_err(|e| format!("transparent receive cache decode: {e}"))?;
            record.dirty = true;
            let encoded = serde_json::to_string(&record)
                .map_err(|e| format!("transparent receive cache encode: {e}"))?;
            table
                .insert(account_uuid, encoded.as_str())
                .map_err(|e| format!("transparent receive cache insert: {e}"))?;
        }
        write_txn
            .commit()
            .map_err(|e| format!("transparent receive cache commit: {e}"))
    })
}

pub(crate) fn delete_account(db_path: &str, account_uuid: &str) -> Result<(), String> {
    with_cache_lock(|| {
        let path = sidecar_path(db_path);
        if !path.exists() {
            return Ok(());
        }

        let db = open_existing_db(&path)?;
        let write_txn = db
            .begin_write()
            .map_err(|e| format!("transparent receive cache write txn: {e}"))?;
        {
            let mut table = match write_txn.open_table(CACHE_TABLE) {
                Ok(table) => table,
                Err(redb::TableError::TableDoesNotExist(_)) => return Ok(()),
                Err(e) => return Err(format!("transparent receive cache open table: {e}")),
            };
            table
                .remove(account_uuid)
                .map_err(|e| format!("transparent receive cache remove: {e}"))?;
        }
        write_txn
            .commit()
            .map_err(|e| format!("transparent receive cache commit: {e}"))
    })
}

pub(crate) fn refresh_account_from_wallet_db(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    scanned_height: Option<u64>,
) -> Result<String, String> {
    let addresses = keys::get_external_transparent_receive_addresses_from_db(
        db_path,
        network,
        Some(account_uuid),
    )?;
    if let Err(e) =
        write_clean_addresses(db_path, network, account_uuid, &addresses, scanned_height)
    {
        log::warn!(
            "transparent receive cache: failed to write clean addresses for account {}: {}",
            account_uuid,
            e
        );
    }
    keys::first_unused_external_transparent_address(&addresses)
        .ok_or_else(|| "No unused external transparent receive address available".to_string())
}

pub(crate) fn refresh_all_from_wallet_db(
    db_path: &str,
    network: WalletNetwork,
    scanned_height: Option<u64>,
) -> Result<usize, String> {
    let account_uuids = keys::list_account_uuids_from_db(db_path)?;
    let mut refreshed = 0;
    for account_uuid in account_uuids {
        match refresh_account_cache_from_wallet_db(db_path, network, &account_uuid, scanned_height)
        {
            Ok(()) => refreshed += 1,
            Err(e) => log::warn!(
                "transparent receive cache: refresh failed for account {}: {}",
                account_uuid,
                e
            ),
        }
    }
    Ok(refreshed)
}

pub(crate) fn refresh_account_cache_from_wallet_db(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    scanned_height: Option<u64>,
) -> Result<(), String> {
    let addresses = keys::get_external_transparent_receive_addresses_from_db(
        db_path,
        network,
        Some(account_uuid),
    )?;
    write_clean_addresses(db_path, network, account_uuid, &addresses, scanned_height)
}

fn write_clean_addresses(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    addresses: &[keys::ExternalTransparentAddress],
    scanned_height: Option<u64>,
) -> Result<(), String> {
    let external_addresses = projected_external_addresses(addresses);

    write_record(
        db_path,
        account_uuid,
        &CacheRecord {
            version: CACHE_VERSION,
            network: network_cache_key(network).to_string(),
            dirty: false,
            refreshed_scanned_height: scanned_height,
            external_addresses,
        },
    )
}

fn projected_external_addresses(
    addresses: &[keys::ExternalTransparentAddress],
) -> Vec<CachedExternalAddress> {
    let first_unused_index = addresses
        .iter()
        .filter(|address| !address.address.is_empty() && !address.has_received)
        .map(|address| address.child_index)
        .min();

    let mut external_addresses = addresses
        .iter()
        .filter(|address| {
            !address.address.is_empty()
                && (address.has_received || Some(address.child_index) == first_unused_index)
        })
        .map(|address| CachedExternalAddress {
            child_index: address.child_index,
            address: address.address.clone(),
            has_received: address.has_received,
        })
        .collect::<Vec<_>>();
    external_addresses.sort_by_key(|address| address.child_index);
    external_addresses
}

fn write_record(db_path: &str, account_uuid: &str, record: &CacheRecord) -> Result<(), String> {
    let encoded = serde_json::to_string(record)
        .map_err(|e| format!("transparent receive cache encode: {e}"))?;
    with_cache_lock(|| {
        let path = sidecar_path(db_path);
        let db = open_or_create_db(&path)?;
        let write_txn = db
            .begin_write()
            .map_err(|e| format!("transparent receive cache write txn: {e}"))?;
        {
            let mut table = write_txn
                .open_table(CACHE_TABLE)
                .map_err(|e| format!("transparent receive cache open table: {e}"))?;
            table
                .insert(account_uuid, encoded.as_str())
                .map_err(|e| format!("transparent receive cache insert: {e}"))?;
        }
        write_txn
            .commit()
            .map_err(|e| format!("transparent receive cache commit: {e}"))
    })
}

fn open_existing_db(path: &Path) -> Result<Database, String> {
    let mut builder = Database::builder();
    builder.set_cache_size(REDB_CACHE_SIZE_BYTES);
    builder
        .open(path)
        .map_err(|e| format!("transparent receive cache open: {e}"))
}

fn open_or_create_db(path: &Path) -> Result<Database, String> {
    let mut builder = Database::builder();
    builder.set_cache_size(REDB_CACHE_SIZE_BYTES);
    builder
        .create(path)
        .map_err(|e| format!("transparent receive cache create/open: {e}"))
}

fn network_cache_key(network: WalletNetwork) -> &'static str {
    match network {
        WalletNetwork::Main => "main",
        WalletNetwork::Test => "test",
        WalletNetwork::Regtest => "regtest",
    }
}

fn clean_record_from_json(
    json: &str,
    network: WalletNetwork,
) -> Result<Option<CacheRecord>, String> {
    let record: CacheRecord =
        serde_json::from_str(json).map_err(|e| format!("transparent receive cache decode: {e}"))?;
    if record.version != CACHE_VERSION
        || record.network != network_cache_key(network)
        || record.dirty
    {
        return Ok(None);
    }
    Ok(Some(record))
}

impl CacheRecord {
    fn as_external_transparent_addresses(&self) -> Vec<keys::ExternalTransparentAddress> {
        self.external_addresses
            .iter()
            .map(|address| keys::ExternalTransparentAddress {
                child_index: address.child_index,
                address: address.address.clone(),
                has_received: address.has_received,
            })
            .collect()
    }
}

fn with_cache_lock<T>(operation: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    static CACHE_LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    let lock = CACHE_LOCK.get_or_init(|| Mutex::new(()));
    let _guard = match lock.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            log::error!("transparent receive cache lock poisoned; continuing");
            poisoned.into_inner()
        }
    };
    operation()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_cached_record(db_path: &str, account_uuid: &str) -> CacheRecord {
        let db = open_existing_db(&sidecar_path(db_path)).unwrap();
        let read_txn = db.begin_read().unwrap();
        let table = read_txn.open_table(CACHE_TABLE).unwrap();
        let value = table.get(account_uuid).unwrap().unwrap();
        serde_json::from_str(value.value()).unwrap()
    }

    #[test]
    fn clean_cache_roundtrip() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();

        assert_eq!(
            get_clean_address(db_path, WalletNetwork::Main, "account-1").unwrap(),
            None
        );

        write_clean_addresses(
            db_path,
            WalletNetwork::Main,
            "account-1",
            &[
                keys::ExternalTransparentAddress {
                    child_index: 0,
                    address: "t1used".to_string(),
                    has_received: true,
                },
                keys::ExternalTransparentAddress {
                    child_index: 1,
                    address: "t1exampleaddress".to_string(),
                    has_received: false,
                },
            ],
            Some(42),
        )
        .unwrap();

        assert_eq!(
            get_clean_address(db_path, WalletNetwork::Main, "account-1").unwrap(),
            Some("t1exampleaddress".to_string())
        );
        assert_eq!(
            get_clean_address(db_path, WalletNetwork::Test, "account-1").unwrap(),
            None
        );
    }

    #[test]
    fn recent_cache_returns_current_and_lower_external_addresses() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();

        write_clean_addresses(
            db_path,
            WalletNetwork::Main,
            "account-1",
            &[
                keys::ExternalTransparentAddress {
                    child_index: 0,
                    address: "t1child0".to_string(),
                    has_received: true,
                },
                keys::ExternalTransparentAddress {
                    child_index: 1,
                    address: "t1child1".to_string(),
                    has_received: true,
                },
                keys::ExternalTransparentAddress {
                    child_index: 2,
                    address: "t1child2".to_string(),
                    has_received: false,
                },
                keys::ExternalTransparentAddress {
                    child_index: 3,
                    address: "t1child3".to_string(),
                    has_received: false,
                },
            ],
            Some(42),
        )
        .unwrap();

        assert_eq!(
            get_recent_addresses(db_path, WalletNetwork::Main, "account-1", 3).unwrap(),
            Some(vec![
                "t1child2".to_string(),
                "t1child1".to_string(),
                "t1child0".to_string()
            ])
        );
    }

    #[test]
    fn clean_cache_stores_used_addresses_and_only_the_first_unused_address() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();

        write_clean_addresses(
            db_path,
            WalletNetwork::Main,
            "account-1",
            &[
                keys::ExternalTransparentAddress {
                    child_index: 0,
                    address: "t1child0".to_string(),
                    has_received: true,
                },
                keys::ExternalTransparentAddress {
                    child_index: 1,
                    address: "t1child1".to_string(),
                    has_received: true,
                },
                keys::ExternalTransparentAddress {
                    child_index: 2,
                    address: "t1child2".to_string(),
                    has_received: false,
                },
                keys::ExternalTransparentAddress {
                    child_index: 3,
                    address: "t1child3".to_string(),
                    has_received: false,
                },
                keys::ExternalTransparentAddress {
                    child_index: 4,
                    address: "t1child4".to_string(),
                    has_received: false,
                },
            ],
            Some(42),
        )
        .unwrap();

        let record = read_cached_record(db_path, "account-1");
        let cached = record
            .external_addresses
            .iter()
            .map(|address| {
                (
                    address.child_index,
                    address.address.as_str(),
                    address.has_received,
                )
            })
            .collect::<Vec<_>>();

        assert_eq!(
            cached,
            vec![
                (0, "t1child0", true),
                (1, "t1child1", true),
                (2, "t1child2", false),
            ]
        );
    }

    #[test]
    fn dirty_cache_is_not_returned() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();

        write_clean_addresses(
            db_path,
            WalletNetwork::Main,
            "account-1",
            &[keys::ExternalTransparentAddress {
                child_index: 0,
                address: "t1example".to_string(),
                has_received: false,
            }],
            None,
        )
        .unwrap();
        mark_account_dirty(db_path, "account-1").unwrap();

        assert_eq!(
            get_clean_address(db_path, WalletNetwork::Main, "account-1").unwrap(),
            None
        );
        assert_eq!(
            get_recent_addresses(db_path, WalletNetwork::Main, "account-1", 20).unwrap(),
            None
        );
    }

    #[test]
    fn delete_account_removes_cached_record() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();

        write_clean_addresses(
            db_path,
            WalletNetwork::Main,
            "account-1",
            &[keys::ExternalTransparentAddress {
                child_index: 0,
                address: "t1example".to_string(),
                has_received: false,
            }],
            None,
        )
        .unwrap();
        delete_account(db_path, "account-1").unwrap();

        assert_eq!(
            get_clean_address(db_path, WalletNetwork::Main, "account-1").unwrap(),
            None
        );
    }
}
