use super::state::open_voting_db;

/// Loads the persisted recovery snapshot for a voting round.
pub fn get_round_recovery_state(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<zcash_voting::recovery::RoundRecoverySnapshot, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::recovery::round_snapshot(&voting_db, round_id)
        .map_err(|e| format!("round_snapshot failed: {e}"))
}

/// Adds helper-server URLs to the sent history for one share delegation.
pub fn add_sent_servers(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::add_sent_servers(
        &voting_db,
        round_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
    )
    .map_err(|e| format!("add_sent_servers failed: {e}"))
}

/// Clears retry/recovery artifacts for a voting round.
pub fn clear_recovery_state(db_path: &str, wallet_id: &str, round_id: &str) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::recovery::clear(&voting_db, round_id)
        .map_err(|e| format!("clear_recovery_state failed: {e}"))
}
