//! Receive-address issuance and historical address compatibility.
//!
//! New receive addresses contain only Orchard. Reading or recognizing an old
//! address must retain its original receiver identity without rewriting the DB.
//! The library retains its own internal address generation and key material.

#[cfg(test)]
mod tests;

use rusqlite::OptionalExtension;
use zcash_client_backend::data_api::{WalletRead, WalletWrite};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::{
    address::{Address, UnifiedAddress},
    keys::{ReceiverRequirement, UnifiedAddressRequest, UnifiedFullViewingKey},
};

use super::{
    db::{
        open_readonly_conn_with_timeout, open_wallet_db_with_timeout, with_wallet_db_write_lock,
        WalletDatabase, READ_DB_BUSY_TIMEOUT, WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
};

/// The receiver set for all newly issued Vizor receive addresses.
pub(crate) fn receive_address_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
        ReceiverRequirement::Omit,
    )
    .expect("valid Orchard-only receiver requirements")
}

/// Issue the next Orchard-only address through the existing serialized DB write path.
pub fn get_next_available_address(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    _address_request: AddressRequestKind,
) -> Result<String, String> {
    let account_id = parse_account_uuid(account_uuid)?;
    let req = receive_address_request();

    let (ua, _) = with_wallet_db_write_lock("addresses.get_next_available_address", || {
        let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        db.get_next_available_address(account_id, req)
            .map_err(|e| format!("{e}"))?
            .ok_or_else(|| "No address available".to_string())
    })?;
    Ok(ua.encode(&network))
}

/// Retained API values; both use the same receive-address policy for new issuance.
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

/// Read both historical Sapling + Orchard and new Orchard-only receive addresses.
pub(crate) fn current_receive_address(
    db: &WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
) -> Result<String, String> {
    let request = UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Allow,
        ReceiverRequirement::Omit,
    )
    .expect("valid receive-address lookup");
    let address = db
        .get_last_generated_address_matching(account_id, request)
        .map_err(|e| format!("Failed to get last generated receive address: {e}"))?;
    let address = match address {
        Some(address) => address,
        None => stored_default_address(db_path, network, account_id)?,
    };
    orchard_projection(&address, network)
}

fn stored_default_address(
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
) -> Result<UnifiedAddress, String> {
    // Account creation stores the default before pre-generating transparent gap
    // addresses. Exposure height is mutable when historical transparent funds
    // are found, so it cannot identify that original row.
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))?;
    let encoded: Option<String> = conn
        .query_row(
            "SELECT a.address FROM addresses a
             JOIN accounts acct ON acct.id = a.account_id
             WHERE acct.uuid = ?1 AND a.key_scope = 0
               AND a.diversifier_index_be IS NOT NULL
             ORDER BY a.id LIMIT 1",
            [account_id.expose_uuid().as_bytes().as_slice()],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("Failed to read stored default address: {e}"))?;
    match encoded
        .as_deref()
        .and_then(|s| Address::decode(&network, s))
    {
        Some(Address::Unified(address)) if address.has_orchard() => Ok(address),
        _ => Err("No stored Orchard receive address".into()),
    }
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

/// Reconstruct a pre-VZR-160 identity, never for new address issuance.
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
