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
}
