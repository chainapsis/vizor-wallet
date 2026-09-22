//! Receive-address issuance and historical address compatibility.
//!
//! New receive addresses contain only Orchard. The active receive address is
//! recorded separately from reserved swap addresses.
//! The library retains its own internal address generation and key material.

#[cfg(test)]
mod tests;

use rusqlite::OptionalExtension;
use zcash_client_backend::data_api::{Account, WalletRead, WalletWrite};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::{
    address::{Address, UnifiedAddress},
    keys::{ReceiverRequirement, UnifiedAddressRequest, UnifiedFullViewingKey},
};

use super::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_db_with_timeout,
        open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
};

/// The receiver set for every new receive or reserved address.
pub(crate) fn receive_address_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
        ReceiverRequirement::Omit,
    )
    .expect("valid Orchard-only receiver requirements")
}

/// Issue an Orchard-only address and persist receive changes atomically.
pub fn get_next_available_address(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    address_request: AddressRequestKind,
) -> Result<String, String> {
    let account_id = parse_account_uuid(account_uuid)?;
    with_wallet_db_write_lock("addresses.get_next_available_address", || {
        ensure_receive_table(db_path)?;
        let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let previous = if address_request == AddressRequestKind::Orchard {
            let account = db
                .get_account(account_id)
                .map_err(|e| e.to_string())?
                .ok_or("Account not found")?;
            let ufvk = account.ufvk().ok_or("Account does not have a UFVK")?;
            Some(current_receive_address(
                &db, db_path, network, account_id, ufvk,
            )?)
        } else {
            None
        };
        db.transactionally_with_extension(|db, ext| {
            let (ua, _) = db
                .get_next_available_address(account_id, receive_address_request())?
                .ok_or(rusqlite::Error::QueryReturnedNoRows)?;
            let address = ua.encode(&network);
            record_current_receive(ext, account_id, previous.as_deref().unwrap_or(&address))?;
            Ok::<_, zcash_client_sqlite::error::SqliteClientError>(address)
        })
        .map_err(|e| format!("Failed to issue receive address: {e}"))
    })
}

/// Shielded updates the active receive address; Orchard reserves an address.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AddressRequestKind {
    Shielded,
    Orchard,
}

pub fn parse_address_request_kind(request: &str) -> Result<AddressRequestKind, String> {
    match request {
        "shielded" => Ok(AddressRequestKind::Shielded),
        "orchard" => Ok(AddressRequestKind::Orchard),
        _ => Err(format!(
            "Unsupported address request '{request}'. Expected 'shielded' or 'orchard'."
        )),
    }
}

/// Identify receive addresses in wallets created before explicit receive tracking.
fn legacy_receive_request(ufvk: &UnifiedFullViewingKey) -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        if ufvk.sapling().is_some() {
            ReceiverRequirement::Require
        } else {
            ReceiverRequirement::Omit
        },
        ReceiverRequirement::Omit,
    )
    .expect("valid stored receive-address requirements")
}

/// Derive the initial display address from account keys without another DB read.
pub(crate) fn default_receive_address(
    ufvk: &UnifiedFullViewingKey,
    network: WalletNetwork,
) -> Result<String, String> {
    let (address, _) = ufvk
        .default_address(receive_address_request())
        .map_err(|e| format!("Failed to derive receive address: {e}"))?;
    orchard_projection(&address, network)
}

/// Read the latest receive address without promoting software swap reservations.
pub(crate) fn current_receive_address(
    db: &WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    ufvk: &UnifiedFullViewingKey,
) -> Result<String, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(WALLET_DB_BUSY_TIMEOUT))?;
    if receive_table_exists(&conn).map_err(|e| e.to_string())? {
        let address: Option<String> = conn
            .query_row(
                "SELECT address FROM ext_vizor_receive_addresses WHERE account_uuid = ?1",
                [account_id.expose_uuid().as_bytes().as_slice()],
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        if let Some(address) = address {
            return Ok(address);
        }
    }
    match db
        .get_last_generated_address_matching(account_id, legacy_receive_request(ufvk))
        .map_err(|e| format!("Failed to get last generated receive address: {e}"))?
    {
        Some(address) => orchard_projection(&address, network),
        None => {
            let (address, _) = ufvk
                .default_address(legacy_receive_request(ufvk))
                .map_err(|e| format!("Failed to derive legacy receive address: {e}"))?;
            orchard_projection(&address, network)
        }
    }
}

pub(crate) fn ensure_receive_table(db_path: &str) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS ext_vizor_receive_addresses (
        account_uuid BLOB PRIMARY KEY NOT NULL,
        address TEXT NOT NULL
    )",
    )
    .map_err(|e| e.to_string())
}

pub(crate) fn record_current_receive(
    ext: &zcash_client_sqlite::ExtensionTransaction<'_>,
    account_id: AccountUuid,
    address: &str,
) -> rusqlite::Result<()> {
    ext.execute(
        "INSERT INTO ext_vizor_receive_addresses (account_uuid, address) VALUES (?1, ?2)
         ON CONFLICT(account_uuid) DO UPDATE SET address = excluded.address",
        (account_id.expose_uuid().as_bytes().as_slice(), address),
    )?;
    Ok(())
}

fn receive_table_exists(conn: &rusqlite::Connection) -> rusqlite::Result<bool> {
    conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name = 'ext_vizor_receive_addresses' AND type = 'table')",
        [], |row| row.get(0),
    )
}

pub(crate) fn delete_account(conn: &rusqlite::Connection, uuid: &[u8]) -> Result<(), String> {
    if receive_table_exists(conn).map_err(|e| e.to_string())? {
        conn.execute(
            "DELETE FROM ext_vizor_receive_addresses WHERE account_uuid = ?1",
            [uuid],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Change only the receiver set, preserving the exact Orchard payment address.
pub(crate) fn orchard_projection(
    address: &UnifiedAddress,
    network: WalletNetwork,
) -> Result<String, String> {
    UnifiedAddress::from_receivers(address.orchard().copied(), None, None)
        .map(|address| address.encode(&network))
        .ok_or_else(|| "Receive address does not have an Orchard receiver".into())
}

/// Reconstruct the legacy Sapling+Orchard default for Gift Card validation.
pub(crate) fn legacy_default_address(
    ufvk: &UnifiedFullViewingKey,
) -> Result<UnifiedAddress, String> {
    let request = UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
    )
    .expect("valid legacy receiver requirements");
    ufvk.default_address(request)
        .map(|(address, _)| address)
        .map_err(|e| format!("Failed to derive historical address: {e}"))
}

/// Gift identities accept only the three default representations actually used
/// by Vizor, rather than arbitrary addresses sharing one receiver.
pub(crate) fn validate_gift_address(
    ufvk: &UnifiedFullViewingKey,
    network: WalletNetwork,
    candidate: &str,
) -> Result<(), String> {
    let (current, _) = ufvk
        .default_address(receive_address_request())
        .map_err(|e| format!("Failed to derive address: {e}"))?;
    if candidate == current.encode(&network) {
        return Ok(());
    }
    let legacy = legacy_default_address(ufvk)?;
    if candidate == legacy.encode(&network) || candidate == orchard_projection(&legacy, network)? {
        return Ok(());
    }
    Err("Gift Card address does not match its recovery phrase".into())
}

/// Compare a historical shielded output with its Orchard-only display address.
/// This is for output metadata lookup, not Gift Card identity validation.
pub(crate) fn same_orchard_receiver(network: WalletNetwork, first: &str, second: &str) -> bool {
    match (
        Address::decode(&network, first),
        Address::decode(&network, second),
    ) {
        (Some(Address::Unified(first)), Some(Address::Unified(second))) => {
            first.orchard().is_some() && first.orchard() == second.orchard()
        }
        _ => false,
    }
}
