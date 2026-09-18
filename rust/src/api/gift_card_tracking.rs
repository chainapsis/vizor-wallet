//! Dedicated sender-side observer API. Dart owns the lifecycle queue; the Rust
//! lock also excludes overlapping FFI calls against the observer database.
pub use crate::wallet::gift_card_tracking::GiftCardUsageEvidence;
use crate::wallet::{gift_card_tracking as tracking, keys};

pub fn register_gift_card_observer(
    db_path: String,
    network: String,
    mnemonic_bytes: Vec<u8>,
    address: String,
    birthday_height: u64,
) -> Result<String, String> {
    let secret = zeroize::Zeroizing::new(mnemonic_bytes);
    let _guard = tracking::OPERATIONS
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    keys::register_gift_card_observer(
        &db_path,
        keys::parse_network(&network)?,
        &secret,
        &address,
        birthday_height,
    )
}

pub fn sync_gift_card_observers(
    db_path: String,
    network: String,
    lightwalletd_url: String,
) -> Result<(), String> {
    let _guard = tracking::OPERATIONS
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    super::sync::run_payment_link_claim_sync(
        format!("gift-card-observer:{db_path}"),
        db_path,
        lightwalletd_url,
        network,
        false,
        None,
    )
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_gift_card_observer_sync(db_path: String) {
    tracking::cancel_lookups();
    super::sync::cancel_payment_link_claim_sync(format!("gift-card-observer:{db_path}"));
}

pub async fn inspect_gift_card_usage(
    db_path: String,
    account_uuid: String,
    funding_txids: String,
    expected_funding_zatoshi: u64,
    lightwalletd_url: String,
) -> Result<GiftCardUsageEvidence, String> {
    let epoch = tracking::lookup_epoch();
    let mut evidence = {
        let _guard = tracking::OPERATIONS
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        tracking::inspect(
            &db_path,
            &account_uuid,
            &funding_txids,
            expected_funding_zatoshi,
        )?
    };
    if evidence.reason.as_deref() == Some("fundingNotObserved") {
        evidence.reason = Some(
            tracking::cancellable_lookup(
                epoch,
                crate::wallet::sync_engine::gift_card_funding_reason(
                    &lightwalletd_url,
                    &funding_txids,
                    evidence.verified_height,
                ),
            )
            .await?,
        );
    }
    Ok(evidence)
}

pub fn remove_gift_card_observer(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<(), String> {
    let _guard = tracking::OPERATIONS
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    tracking::remove(&db_path, keys::parse_network(&network)?, &account_uuid)
}

pub fn list_gift_card_observers(db_path: String) -> Result<Vec<String>, String> {
    let _guard = tracking::OPERATIONS
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    if !std::path::Path::new(&db_path).exists() {
        return Ok(vec![]);
    }
    let conn = crate::wallet::db::open_readonly_conn_with_timeout(&db_path, None)?;
    let mut stmt = conn
        .prepare("SELECT uuid FROM accounts")
        .map_err(|e| e.to_string())?;
    let ids = stmt
        .query_map([], |r| r.get::<_, Vec<u8>>(0))
        .map_err(|e| e.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    ids.into_iter()
        .map(|id| {
            uuid::Uuid::from_slice(&id)
                .map(|id| id.to_string())
                .map_err(|e| e.to_string())
        })
        .collect()
}
