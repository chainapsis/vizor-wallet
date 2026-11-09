/// Read a display-only balance snapshot without scanning or wallet-summary work.
pub fn load_balance_cache(
    db_path: String,
    network: String,
    account_uuid: String,
) -> Result<Option<String>, String> {
    super::wallet::catch(|| {
        crate::wallet::keys::parse_network(&network)?;
        crate::wallet::balance_cache::load(&db_path, &network, &account_uuid)
    })
}

/// Persist a balance already accepted by the app. Never used to authorize spends.
pub fn save_balance_cache(
    db_path: String,
    network: String,
    account_uuid: String,
    payload: String,
) -> Result<(), String> {
    super::wallet::catch(|| {
        crate::wallet::keys::parse_network(&network)?;
        crate::wallet::balance_cache::save(&db_path, &network, &account_uuid, &payload)
    })
}
