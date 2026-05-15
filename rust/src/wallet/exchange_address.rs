use rusqlite::OptionalExtension;
use transparent::keys::TransparentKeyScope;
use zcash_client_backend::{
    data_api::WalletWrite,
    wallet::{Exposure, TransparentAddressSource},
};
use zcash_keys::encoding::encode_transparent_address;
use zcash_protocol::consensus::NetworkConstants;

use crate::wallet::{
    db::{open_wallet_db_with_timeout, with_wallet_db_write_lock, WALLET_DB_BUSY_TIMEOUT},
    keys::parse_account_uuid,
    network::WalletNetwork,
};

const EPHEMERAL_KEY_SCOPE: i64 = 2;

#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(dead_code)]
pub(crate) struct ExchangeTransparentAddress {
    pub(crate) address: String,
    pub(crate) transparent_child_index: u32,
    pub(crate) exposed_at_height: u64,
}

#[allow(dead_code)]
pub(crate) fn reserve_exchange_transparent_address(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<ExchangeTransparentAddress, String> {
    with_wallet_db_write_lock(
        "exchange_address.reserve_exchange_transparent_address",
        || {
            let account_id = parse_account_uuid(account_uuid)?;
            let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
            let mut reserved = db
                .reserve_next_n_ephemeral_addresses(account_id, 1)
                .map_err(|e| format!("Failed to reserve exchange transparent address: {e}"))?;

            let (address, metadata) = reserved
                .pop()
                .ok_or_else(|| "No exchange transparent address was reserved".to_string())?;
            let source = metadata.source();
            let transparent_child_index = match source {
                TransparentAddressSource::Derived {
                    scope,
                    address_index,
                } if *scope == TransparentKeyScope::EPHEMERAL => address_index.index(),
                TransparentAddressSource::Derived { scope, .. } => {
                    return Err(format!(
                        "Reserved transparent address used unexpected key scope: {scope:?}"
                    ));
                }
            };

            let exposed_at_height = match metadata.exposure() {
                Exposure::Exposed { at_height, .. } => u32::from(at_height) as u64,
                other => {
                    return Err(format!(
                        "Reserved exchange transparent address was not marked exposed: {other:?}"
                    ));
                }
            };

            Ok(ExchangeTransparentAddress {
                address: encode_transparent_address(
                    &network.b58_pubkey_address_prefix(),
                    &network.b58_script_address_prefix(),
                    &address,
                ),
                transparent_child_index,
                exposed_at_height,
            })
        },
    )
}

#[allow(dead_code)]
pub(crate) fn release_exchange_transparent_address(
    db_path: &str,
    account_uuid: &str,
    address: &str,
) -> Result<bool, String> {
    with_wallet_db_write_lock(
        "exchange_address.release_exchange_transparent_address",
        || {
            let account_uuid = uuid::Uuid::parse_str(account_uuid)
                .map_err(|e| format!("Invalid account UUID: {e}"))?;
            let mut conn = rusqlite::Connection::open(db_path)
                .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
            conn.busy_timeout(WALLET_DB_BUSY_TIMEOUT)
                .map_err(|e| format!("Failed to configure wallet DB busy timeout: {e}"))?;
            let tx = conn
                .transaction()
                .map_err(|e| format!("Failed to start wallet DB transaction: {e}"))?;
            let released = release_exchange_transparent_address_inner(
                &tx,
                account_uuid.as_bytes().as_slice(),
                address,
            )?;
            tx.commit()
                .map_err(|e| format!("Failed to commit wallet DB transaction: {e}"))?;
            Ok(released)
        },
    )
}

#[allow(dead_code)]
pub(crate) fn release_unused_exchange_transparent_addresses(
    db_path: &str,
    account_uuid: &str,
) -> Result<u32, String> {
    with_wallet_db_write_lock(
        "exchange_address.release_unused_exchange_transparent_addresses",
        || {
            let account_uuid = uuid::Uuid::parse_str(account_uuid)
                .map_err(|e| format!("Invalid account UUID: {e}"))?;
            let mut conn = rusqlite::Connection::open(db_path)
                .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
            conn.busy_timeout(WALLET_DB_BUSY_TIMEOUT)
                .map_err(|e| format!("Failed to configure wallet DB busy timeout: {e}"))?;
            let tx = conn
                .transaction()
                .map_err(|e| format!("Failed to start wallet DB transaction: {e}"))?;
            let released = release_unused_exchange_transparent_addresses_inner(
                &tx,
                account_uuid.as_bytes().as_slice(),
            )?;
            tx.commit()
                .map_err(|e| format!("Failed to commit wallet DB transaction: {e}"))?;
            Ok(released)
        },
    )
}

fn release_exchange_transparent_address_inner(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
    address: &str,
) -> Result<bool, String> {
    let address_id = conn
        .query_row(
            "SELECT addresses.id
             FROM addresses
             JOIN accounts ON accounts.id = addresses.account_id
             WHERE accounts.uuid = ?1
               AND addresses.cached_transparent_receiver_address = ?2
               AND addresses.key_scope = ?3
               AND addresses.exposed_at_height IS NOT NULL",
            rusqlite::params![account_uuid, address, EPHEMERAL_KEY_SCOPE],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(|e| format!("Failed to query exchange transparent address: {e}"))?;
    let Some(address_id) = address_id else {
        return Ok(false);
    };
    if exchange_address_has_observed_output(conn, address_id)? {
        return Ok(false);
    }
    let updated = conn
        .execute(
            "UPDATE addresses
             SET exposed_at_height = NULL,
                 transparent_receiver_next_check_time = NULL
             WHERE id = ?1
               AND exposed_at_height IS NOT NULL",
            rusqlite::params![address_id],
        )
        .map_err(|e| format!("Failed to release exchange transparent address: {e}"))?;
    Ok(updated > 0)
}

fn release_unused_exchange_transparent_addresses_inner(
    conn: &rusqlite::Connection,
    account_uuid: &[u8],
) -> Result<u32, String> {
    let updated = conn
        .execute(
            "UPDATE addresses
             SET exposed_at_height = NULL,
                 transparent_receiver_next_check_time = NULL
             WHERE id IN (
                 SELECT addresses.id
                 FROM addresses
                 JOIN accounts ON accounts.id = addresses.account_id
                 WHERE accounts.uuid = ?1
                   AND addresses.key_scope = ?2
                   AND addresses.exposed_at_height IS NOT NULL
                   AND NOT EXISTS (
                       SELECT 1
                       FROM transparent_received_outputs
                       WHERE transparent_received_outputs.address_id = addresses.id
                   )
             )",
            rusqlite::params![account_uuid, EPHEMERAL_KEY_SCOPE],
        )
        .map_err(|e| format!("Failed to release unused exchange transparent addresses: {e}"))?;
    u32::try_from(updated)
        .map_err(|_| "Released exchange transparent address count overflowed u32".to_string())
}

fn exchange_address_has_observed_output(
    conn: &rusqlite::Connection,
    address_id: i64,
) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(
            SELECT 1 FROM transparent_received_outputs WHERE address_id = ?1
         )",
        rusqlite::params![address_id],
        |row| row.get::<_, i64>(0).map(|value| value != 0),
    )
    .map_err(|e| format!("Failed to check exchange transparent address outputs: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::{keys, sync};
    use rusqlite::params;

    const TIP_HEIGHT: u64 = 2_500_000;

    fn create_wallet() -> (tempfile::TempDir, String, String) {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let phrase = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&phrase).unwrap();
        let (account_uuid, _) = keys::init_db_and_create_account(
            db_path_str,
            WalletNetwork::Main,
            &seed,
            None,
            "exchange",
        )
        .unwrap();
        sync::update_chain_tip(db_path_str, WalletNetwork::Main, TIP_HEIGHT).unwrap();

        (temp_dir, db_path_str.to_string(), account_uuid)
    }

    #[test]
    fn reserves_distinct_ephemeral_addresses() {
        let (_temp_dir, db_path, account_uuid) = create_wallet();

        let first =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        let second =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();

        assert_ne!(first.address, second.address);
        assert_eq!(
            first.transparent_child_index + 1,
            second.transparent_child_index
        );
        assert_eq!(first.exposed_at_height, TIP_HEIGHT);
        assert_eq!(second.exposed_at_height, TIP_HEIGHT);
    }

    #[test]
    fn marks_reserved_address_as_ephemeral_and_exposed() {
        let (_temp_dir, db_path, account_uuid) = create_wallet();

        let reserved =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let uuid = uuid::Uuid::parse_str(&account_uuid).unwrap();
        let (key_scope, child_index, exposed_at_height): (i64, u32, u64) = conn
            .query_row(
                "SELECT addresses.key_scope,
                        addresses.transparent_child_index,
                        addresses.exposed_at_height
                 FROM addresses
                 JOIN accounts ON accounts.id = addresses.account_id
                 WHERE accounts.uuid = ?1
                   AND addresses.cached_transparent_receiver_address = ?2",
                params![uuid.as_bytes().as_slice(), reserved.address],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();

        assert_eq!(key_scope, 2);
        assert_eq!(child_index, reserved.transparent_child_index);
        assert_eq!(exposed_at_height, TIP_HEIGHT);
    }

    #[test]
    fn fails_when_ephemeral_gap_is_exhausted() {
        let (_temp_dir, db_path, account_uuid) = create_wallet();

        for _ in 0..10 {
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        }

        let err =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap_err();

        assert!(
            err.contains("gap limit") || err.contains("could not be safely reserved"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn releases_unused_reserved_address_for_reuse() {
        let (_temp_dir, db_path, account_uuid) = create_wallet();

        let first =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        assert!(
            release_exchange_transparent_address(&db_path, &account_uuid, &first.address).unwrap()
        );

        let second =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        assert_eq!(second.address, first.address);
        assert_eq!(
            second.transparent_child_index,
            first.transparent_child_index
        );
    }

    #[test]
    fn does_not_release_reserved_address_with_observed_output() {
        let (_temp_dir, db_path, account_uuid) = create_wallet();

        let first =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let uuid = uuid::Uuid::parse_str(&account_uuid).unwrap();
        let (account_id, address_id): (i64, i64) = conn
            .query_row(
                "SELECT accounts.id, addresses.id
                 FROM addresses
                 JOIN accounts ON accounts.id = addresses.account_id
                 WHERE accounts.uuid = ?1
                   AND addresses.cached_transparent_receiver_address = ?2",
                params![uuid.as_bytes().as_slice(), first.address],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, min_observed_height)
             VALUES (?1, ?2)",
            params![vec![7_u8; 32], TIP_HEIGHT],
        )
        .unwrap();
        let transaction_id = conn.last_insert_rowid();
        conn.execute(
            "INSERT INTO transparent_received_outputs (
                 transaction_id, output_index, account_id, address_id,
                 address, script, value_zat, max_observed_unspent_height
             )
             VALUES (?1, 0, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                transaction_id,
                account_id,
                address_id,
                first.address,
                Vec::<u8>::new(),
                1_i64,
                TIP_HEIGHT
            ],
        )
        .unwrap();

        assert!(
            !release_exchange_transparent_address(&db_path, &account_uuid, &first.address).unwrap()
        );

        let next =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        assert_ne!(next.address, first.address);
    }

    #[test]
    fn bulk_release_clears_only_unused_exposed_ephemeral_addresses() {
        let (_temp_dir, db_path, account_uuid) = create_wallet();

        let first =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        let second =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();

        let released =
            release_unused_exchange_transparent_addresses(&db_path, &account_uuid).unwrap();
        assert_eq!(released, 2);

        let next =
            reserve_exchange_transparent_address(&db_path, WalletNetwork::Main, &account_uuid)
                .unwrap();
        assert_eq!(next.address, first.address);

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let second_exposed: Option<u64> = conn
            .query_row(
                "SELECT exposed_at_height
                 FROM addresses
                 WHERE cached_transparent_receiver_address = ?1",
                params![second.address],
                |row| row.get::<_, Option<u64>>(0),
            )
            .unwrap();
        assert_eq!(second_exposed, None);
    }
}
