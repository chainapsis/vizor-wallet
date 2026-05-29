use rusqlite::{named_params, OptionalExtension, Transaction};
use zcash_voting::storage::queries;

/// Marks a delegation bundle as submitted by storing its transaction hash.
///
/// The write is atomic and idempotent for the same `tx_hash`. A different
/// existing hash for the same `(round_id, wallet_id, bundle_index)` is rejected.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the transaction cannot
/// be committed, the bundle row is missing, or an existing hash conflicts.
pub fn mark_delegation_submitted(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    let mut conn = db.conn();
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin delegation submitted transaction failed: {e}"))?;
    let stored = queries::get_delegation_tx_hash(&tx, round_id, wallet_id, bundle_index)
        .map_err(|e| format!("get_delegation_tx_hash failed: {e}"))?;
    check_text_conflict(stored.as_deref(), tx_hash, "delegation tx_hash")?;
    queries::store_delegation_tx_hash(&tx, round_id, wallet_id, bundle_index, tx_hash)
        .map_err(|e| format!("store_delegation_tx_hash failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit delegation submitted transaction failed: {e}"))
}

/// Marks a delegation bundle as confirmed by storing its tx hash and VAN leaf.
///
/// The write is atomic and idempotent for the same `tx_hash` and
/// `van_leaf_position`. Conflicting existing values are rejected.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the bundle row is
/// missing, the transaction cannot be committed, or stored data conflicts.
pub fn mark_delegation_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
    van_leaf_position: u32,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    let mut conn = db.conn();
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin delegation confirmed transaction failed: {e}"))?;
    let stored_hash = queries::get_delegation_tx_hash(&tx, round_id, wallet_id, bundle_index)
        .map_err(|e| format!("get_delegation_tx_hash failed: {e}"))?;
    check_text_conflict(stored_hash.as_deref(), tx_hash, "delegation tx_hash")?;
    check_i64_conflict(
        load_bundle_i64(&tx, round_id, wallet_id, bundle_index, "van_leaf_position")?,
        i64::from(van_leaf_position),
        "delegation van_leaf_position",
    )?;
    queries::store_delegation_tx_hash(&tx, round_id, wallet_id, bundle_index, tx_hash)
        .map_err(|e| format!("store_delegation_tx_hash failed: {e}"))?;
    queries::store_van_position(&tx, round_id, wallet_id, bundle_index, van_leaf_position)
        .map_err(|e| format!("store_van_position failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit delegation confirmed transaction failed: {e}"))
}

/// Marks a vote as submitted by storing its tx hash.
///
/// The write is atomic and idempotent for the same `tx_hash`. A different
/// existing hash for the same vote key is rejected.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the vote row is missing,
/// the transaction cannot be committed, or an existing hash conflicts.
pub fn mark_vote_submitted(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    let mut conn = db.conn();
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin vote submitted transaction failed: {e}"))?;
    let stored = queries::get_vote_tx_hash(&tx, round_id, wallet_id, bundle_index, proposal_id)
        .map_err(|e| format!("get_vote_tx_hash failed: {e}"))?;
    check_text_conflict(stored.as_deref(), tx_hash, "vote tx_hash")?;
    queries::record_vote_submission(&tx, round_id, wallet_id, bundle_index, proposal_id, tx_hash)
        .map_err(|e| format!("record_vote_submission failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit vote submitted transaction failed: {e}"))
}

/// Marks a vote as confirmed and persists the confirmation fields.
///
/// Stores the vote tx hash, VAN position, and vote commitment tree position.
/// Repeated calls with identical data are accepted; any
/// conflicting existing value is rejected.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the vote row is missing,
/// the transaction cannot be committed, `vc_tree_position` does not fit SQLite's
/// signed integer representation, or stored data conflicts.
pub fn mark_vote_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
    van_position: u32,
    vc_tree_position: u64,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    {
        let mut conn = db.conn();
        let tx = conn
            .transaction()
            .map_err(|e| format!("begin vote confirmed transaction failed: {e}"))?;
        let stored_hash =
            queries::get_vote_tx_hash(&tx, round_id, wallet_id, bundle_index, proposal_id)
                .map_err(|e| format!("get_vote_tx_hash failed: {e}"))?;
        check_text_conflict(stored_hash.as_deref(), tx_hash, "vote tx_hash")?;
        let (_, stored_position) =
            load_vote_recovery_fields(&tx, round_id, wallet_id, bundle_index, proposal_id)?;
        check_vote_position_conflict(stored_position, vc_tree_position)?;
        queries::record_vote_submission(
            &tx,
            round_id,
            wallet_id,
            bundle_index,
            proposal_id,
            tx_hash,
        )
        .map_err(|e| format!("record_vote_submission failed: {e}"))?;
        queries::store_van_position(&tx, round_id, wallet_id, bundle_index, van_position)
            .map_err(|e| format!("store_van_position failed: {e}"))?;
        tx.commit()
            .map_err(|e| format!("commit vote confirmed transaction failed: {e}"))?;
    }
    zcash_voting::vote::record_vc_position(
        &db,
        round_id,
        bundle_index,
        proposal_id,
        vc_tree_position,
    )
    .map_err(|e| format!("record_vc_position failed: {e}"))
}

/// Records helper-server share submission state for retry/recovery.
///
/// The shared voting crate reconstructs the share payload and nullifier from the
/// stored vote recovery bundle, so callers only provide helper delivery state.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened or the upstream share
/// write fails.
#[allow(clippy::too_many_arguments)]
pub fn record_share_delegation(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    submit_at: u64,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::record(
        &db,
        round_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        submit_at,
    )
    .map_err(|e| format!("record_share_delegation failed: {e}"))?;
    Ok(())
}

/// Marks a helper-server share delegation as confirmed.
///
/// The write is atomic for the exact `(round_id, wallet_id, bundle_index,
/// proposal_id, share_index)` key.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the transaction cannot be
/// committed, or the upstream confirmation update fails.
pub fn mark_share_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::confirm(&db, round_id, bundle_index, proposal_id, share_index)
        .map_err(|e| format!("mark_share_confirmed failed: {e}"))?;
    Ok(())
}

/// Loads one nullable integer column from a bundle row inside an existing tx.
///
/// The `column` argument must be a trusted static column name, not user input.
fn load_bundle_i64(
    tx: &Transaction<'_>,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    column: &str,
) -> Result<Option<i64>, String> {
    let sql = format!(
        "SELECT {column} FROM bundles
         WHERE round_id = :round_id AND wallet_id = :wallet_id AND bundle_index = :bundle_index"
    );
    tx.query_row(
        &sql,
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
        },
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| format!("load bundle field failed: {e}"))?
    .ok_or_else(|| format!("bundle_index {bundle_index} not found"))
}

/// Loads nullable vote recovery fields for conflict checks inside a transaction.
fn load_vote_recovery_fields(
    tx: &Transaction<'_>,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(Option<String>, Option<i64>), String> {
    tx.query_row(
        "SELECT commitment_bundle_json, vc_tree_position FROM votes
         WHERE round_id = :round_id AND wallet_id = :wallet_id
         AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .map_err(|e| {
        format!(
            "vote row not found for bundle_index {bundle_index}, proposal_id {proposal_id}: {e}"
        )
    })
}

/// Accepts missing or matching text fields and rejects conflicting values.
fn check_text_conflict(existing: Option<&str>, requested: &str, field: &str) -> Result<(), String> {
    if let Some(existing) = existing {
        if existing != requested {
            return Err(format!(
                "{field} conflict: stored {existing}, requested {requested}"
            ));
        }
    }
    Ok(())
}

/// Accepts missing or matching integer fields and rejects conflicting values.
fn check_i64_conflict(existing: Option<i64>, requested: i64, field: &str) -> Result<(), String> {
    if let Some(existing) = existing {
        if existing != requested {
            return Err(format!(
                "{field} conflict: stored {existing}, requested {requested}"
            ));
        }
    }
    Ok(())
}

/// Accepts missing or matching vote tree positions.
///
/// Older builds stored `0` as a pre-confirmation placeholder because the
/// position was not yet available. Treat that value as unset when replacing it
/// with the chain-confirmed position.
fn check_vote_position_conflict(existing: Option<i64>, requested: u64) -> Result<(), String> {
    let requested = i64::try_from(requested)
        .map_err(|_| format!("vc_tree_position {requested} does not fit in i64"))?;
    match existing {
        None | Some(0) => Ok(()),
        Some(existing) if existing == requested => Ok(()),
        Some(existing) => Err(format!(
            "vote vc_tree_position conflict: stored {existing}, requested {requested}"
        )),
    }
}
