//! Receive-address issuance and historical address compatibility.
//!
//! Exposed receive addresses contain only Orchard. Software receive issuance
//! retains Sapling internally to distinguish it from reserved swap addresses.
//! The library retains its own internal address generation and key material.

#[cfg(test)]
mod tests;

use zcash_client_backend::data_api::{Account, WalletRead, WalletWrite};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::{
    address::{Address, UnifiedAddress},
    keys::{ReceiverRequirement, UnifiedAddressRequest, UnifiedFullViewingKey},
};

use super::{
    db::{
        open_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
};

/// The receiver set exposed by Vizor and stored for reserved addresses.
pub(crate) fn receive_address_request() -> UnifiedAddressRequest {
    UnifiedAddressRequest::custom(
        ReceiverRequirement::Require,
        ReceiverRequirement::Omit,
        ReceiverRequirement::Omit,
    )
    .expect("valid Orchard-only receiver requirements")
}

/// Preserve the stored receive/reservation distinction, exposing only Orchard.
pub fn get_next_available_address(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    address_request: AddressRequestKind,
) -> Result<String, String> {
    let account_id = parse_account_uuid(account_uuid)?;

    let (ua, _) = with_wallet_db_write_lock("addresses.get_next_available_address", || {
        let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let account = db
            .get_account(account_id)
            .map_err(|e| format!("Failed to get account: {e}"))?
            .ok_or("Account not found")?;
        let ufvk = account.ufvk().ok_or("Account does not have a UFVK")?;
        let req = match address_request {
            AddressRequestKind::Shielded => stored_receive_request(ufvk),
            AddressRequestKind::Orchard => receive_address_request(),
        };
        db.get_next_available_address(account_id, req)
            .map_err(|e| format!("{e}"))?
            .ok_or_else(|| "No address available".to_string())
    })?;
    orchard_projection(&ua, network)
}

/// Shielded renews a receive address with the account's stored receiver set.
/// Orchard uses Orchard-only storage for reservations and hardware receive.
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

/// Preserve the existing software receive-address discriminator in stored rows.
fn stored_receive_request(ufvk: &UnifiedFullViewingKey) -> UnifiedAddressRequest {
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
/// Unlike the standalone Gift Card address, this retains the legacy index.
pub(crate) fn default_receive_address(
    ufvk: &UnifiedFullViewingKey,
    network: WalletNetwork,
) -> Result<String, String> {
    let (address, _) = ufvk
        .default_address(stored_receive_request(ufvk))
        .map_err(|e| format!("Failed to derive receive address: {e}"))?;
    orchard_projection(&address, network)
}

/// Read the latest receive address without promoting software swap reservations.
pub(crate) fn current_receive_address(
    db: &WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    ufvk: &UnifiedFullViewingKey,
) -> Result<String, String> {
    match db
        .get_last_generated_address_matching(account_id, stored_receive_request(ufvk))
        .map_err(|e| format!("Failed to get last generated receive address: {e}"))?
    {
        Some(address) => orchard_projection(&address, network),
        None => default_receive_address(ufvk, network),
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
