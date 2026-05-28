use rusqlite::{named_params, OptionalExtension, Transaction};
use zcash_voting::storage::queries;

/// Lifecycle phase for one recoverable voting artifact, not the whole round.
///
/// Values are serialized through [`WorkflowPhase::as_str`] and consumed by Dart
/// recovery code. Keep those strings stable unless the Dart constants are
/// updated at the same time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WorkflowPhase {
    /// Durable row exists, but no submitted transaction hash has been recorded.
    ///
    /// For delegation this means a `bundles` row exists. For votes this means a
    /// `votes` row exists. The artifact may still need local proof/signing or
    /// network submission work.
    Prepared,
    /// Local signing/recovery material exists, but the artifact has not been
    /// submitted to the chain.
    ///
    /// For delegation this is inferred from signed delegation fields in
    /// `bundles`. For votes this is inferred from `commitment_bundle_json`
    /// existing without a submitted vote transaction hash.
    Signed,
    /// The delegation transaction hash is stored, but `van_leaf_position` has
    /// not been recovered from the chain event yet.
    SubmittedDelegation,
    /// The cast-vote transaction hash is stored and the vote row is marked
    /// submitted, but vote confirmation data is still incomplete.
    SubmittedVote,
    /// The share was submitted to a helper server, but that helper has not
    /// confirmed it yet.
    SubmittedShare,
    /// The artifact has both submission and confirmation/recovery data.
    ///
    /// Delegation has `delegation_tx_hash` and `van_leaf_position`. Votes have
    /// `tx_hash`, `submitted = 1`, `vc_tree_position`, and
    /// `commitment_bundle_json`. Shares have `confirmed = true`.
    Confirmed,
}

impl WorkflowPhase {
    /// Returns the stable API string for this phase.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Prepared => "prepared",
            Self::Signed => "signed",
            Self::SubmittedDelegation => "submitted_delegation",
            Self::SubmittedVote => "submitted_vote",
            Self::SubmittedShare => "submitted_share",
            Self::Confirmed => "confirmed",
        }
    }
}

fn workflow_phase_from_delegation(phase: zcash_voting::phases::DelegationPhase) -> WorkflowPhase {
    match phase {
        zcash_voting::phases::DelegationPhase::Prepared => WorkflowPhase::Prepared,
        zcash_voting::phases::DelegationPhase::PcztBuilt
        | zcash_voting::phases::DelegationPhase::Proved => WorkflowPhase::Signed,
        zcash_voting::phases::DelegationPhase::Submitted => WorkflowPhase::SubmittedDelegation,
        zcash_voting::phases::DelegationPhase::Confirmed => WorkflowPhase::Confirmed,
        _ => WorkflowPhase::Prepared,
    }
}

/// Derived lifecycle state for one delegation bundle.
///
/// The record is keyed by `(round_id, wallet_id, bundle_index)` in storage; the
/// caller supplies `round_id`, and `wallet_id` comes from the open voting DB.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationWorkflowRecord {
    /// Bundle index within the round.
    pub bundle_index: u32,
    /// Phase derived from `bundles` columns.
    pub phase: WorkflowPhase,
    /// Stored delegation transaction hash, when the bundle has been submitted.
    pub tx_hash: Option<String>,
    /// Vote Authority Note leaf position, when chain confirmation was recorded.
    pub van_leaf_position: Option<u32>,
}

/// Derived lifecycle state for one vote commitment.
///
/// The record is keyed by `(round_id, wallet_id, bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteWorkflowRecord {
    /// Bundle index within the round.
    pub bundle_index: u32,
    /// Proposal identifier within the round.
    pub proposal_id: u32,
    /// Phase derived from `votes` columns.
    pub phase: WorkflowPhase,
    /// Stored cast-vote transaction hash, when the vote has been submitted.
    pub tx_hash: Option<String>,
    /// Vote commitment tree position, when confirmation/recovery data exists.
    pub vc_tree_position: Option<u64>,
    /// Whether `votes.commitment_bundle_json` is present.
    pub has_commitment_bundle: bool,
}

/// Derived lifecycle state for one helper-server share delegation.
///
/// The record is keyed by
/// `(round_id, wallet_id, bundle_index, proposal_id, share_index)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShareWorkflowRecord {
    /// Bundle index within the round.
    pub bundle_index: u32,
    /// Proposal identifier within the round.
    pub proposal_id: u32,
    /// Share index inside the vote commitment's share payloads.
    pub share_index: u32,
    /// Phase derived from `share_delegations.confirmed`.
    pub phase: WorkflowPhase,
}

/// Loads derived delegation workflow records for one round.
///
/// Returns records sorted by `bundle_index`. Missing bundle rows are omitted
/// rather than synthesized.
///
/// # Errors
///
/// Returns an error if the database query cannot be prepared, executed, or read.
pub fn delegation_workflows(
    db: &zcash_voting::storage::VotingDb,
    round_id: &str,
) -> Result<Vec<DelegationWorkflowRecord>, String> {
    db.delegation_phases(round_id)
        .map_err(|e| format!("load delegation phases failed: {e}"))?
        .into_iter()
        .map(|(bundle_index, phase)| {
            let tx_hash = db
                .get_delegation_tx_hash(round_id, bundle_index)
                .map_err(|e| format!("load delegation tx hash failed: {e}"))?;
            let van_leaf_position = db.load_van_position(round_id, bundle_index).ok();
            Ok(DelegationWorkflowRecord {
                bundle_index,
                phase: workflow_phase_from_delegation(phase),
                tx_hash,
                van_leaf_position,
            })
        })
        .collect()
}

/// Loads derived vote workflow records for one round.
///
/// Returns records sorted by `(bundle_index, proposal_id)`. Missing vote rows
/// are omitted rather than synthesized.
///
/// # Errors
///
/// Returns an error if the database query cannot be prepared, executed, or read.
pub fn vote_workflows(
    db: &zcash_voting::storage::VotingDb,
    round_id: &str,
) -> Result<Vec<VoteWorkflowRecord>, String> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    let mut stmt = conn
        .prepare(
            "SELECT bundle_index, proposal_id, submitted, tx_hash,
                    vc_tree_position, commitment_bundle_json
             FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
             ORDER BY bundle_index, proposal_id",
        )
        .map_err(|e| format!("prepare vote workflow query failed: {e}"))?;
    let rows = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| {
                let submitted = row.get::<_, i64>(2)? != 0;
                let tx_hash: Option<String> = row.get(3)?;
                let vc_tree_position: Option<i64> = row.get(4)?;
                let commitment_bundle_json: Option<String> = row.get(5)?;
                Ok(VoteWorkflowRecord {
                    bundle_index: row.get::<_, i64>(0)? as u32,
                    proposal_id: row.get::<_, i64>(1)? as u32,
                    phase: vote_phase(
                        submitted,
                        tx_hash.as_deref(),
                        vc_tree_position,
                        commitment_bundle_json.as_deref(),
                    ),
                    tx_hash,
                    vc_tree_position: vc_tree_position.map(|v| v as u64),
                    has_commitment_bundle: commitment_bundle_json.is_some(),
                })
            },
        )
        .map_err(|e| format!("query vote workflow failed: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("read vote workflow row failed: {e}"))
}

/// Loads derived helper-share workflow records for one round.
///
/// Returns records sorted by `(bundle_index, proposal_id, share_index)`.
///
/// # Errors
///
/// Returns an error if the database query cannot be prepared, executed, or read.
pub fn share_workflows(
    db: &zcash_voting::storage::VotingDb,
    round_id: &str,
) -> Result<Vec<ShareWorkflowRecord>, String> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    let mut stmt = conn
        .prepare(
            "SELECT bundle_index, proposal_id, share_index, confirmed
             FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id
             ORDER BY bundle_index, proposal_id, share_index",
        )
        .map_err(|e| format!("prepare share workflow query failed: {e}"))?;
    let rows = stmt
        .query_map(
            named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
            |row| {
                Ok(ShareWorkflowRecord {
                    bundle_index: row.get::<_, i64>(0)? as u32,
                    proposal_id: row.get::<_, i64>(1)? as u32,
                    share_index: row.get::<_, i64>(2)? as u32,
                    phase: if row.get::<_, i64>(3)? != 0 {
                        WorkflowPhase::Confirmed
                    } else {
                        WorkflowPhase::SubmittedShare
                    },
                })
            },
        )
        .map_err(|e| format!("query share workflow failed: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("read share workflow row failed: {e}"))
}

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

/// Persists signed vote commitment recovery data after signing succeeds.
///
/// Stores `commitment_bundle_json` for the vote key. The vote commitment tree
/// position is not known until the cast-vote transaction is confirmed on-chain,
/// so `vc_tree_position` is intentionally left unset here.
///
/// # Errors
///
/// Returns an error if the vote row is missing, the transaction cannot be
/// committed, or existing commitment JSON conflicts with the requested value.
pub fn store_signed_vote_commitment(
    db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    commitment_bundle_json: &str,
) -> Result<(), String> {
    let mut conn = db.conn();
    let wallet_id = db.wallet_id();
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin signed vote transaction failed: {e}"))?;
    let (stored_json, _) =
        load_vote_recovery_fields(&tx, round_id, &wallet_id, bundle_index, proposal_id)?;
    check_text_conflict(
        stored_json.as_deref(),
        commitment_bundle_json,
        "vote commitment_bundle_json",
    )?;
    tx.execute(
        "UPDATE votes SET commitment_bundle_json = :json
         WHERE round_id = :round_id AND wallet_id = :wallet_id
         AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
        named_params! {
            ":json": commitment_bundle_json,
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
    )
    .map_err(|e| format!("store signed vote commitment failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit signed vote transaction failed: {e}"))
}

/// Marks a vote as submitted by storing its tx hash and `submitted = 1`.
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
    queries::store_vote_tx_hash(&tx, round_id, wallet_id, bundle_index, proposal_id, tx_hash)
        .map_err(|e| format!("store_vote_tx_hash failed: {e}"))?;
    queries::mark_vote_submitted(&tx, round_id, wallet_id, bundle_index, proposal_id)
        .map_err(|e| format!("mark_vote_submitted failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit vote submitted transaction failed: {e}"))
}

/// Marks a vote as confirmed and persists all vote recovery fields atomically.
///
/// Stores the vote tx hash, `submitted = 1`, VAN position, vote commitment tree
/// position, and commitment bundle JSON. Repeated calls with identical data are
/// accepted; any conflicting existing value is rejected.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the vote row is missing,
/// the transaction cannot be committed, `vc_tree_position` does not fit SQLite's
/// signed integer representation, or stored data conflicts.
#[allow(clippy::too_many_arguments)]
pub fn mark_vote_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
    van_position: u32,
    vc_tree_position: u64,
    commitment_bundle_json: &str,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    let mut conn = db.conn();
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin vote confirmed transaction failed: {e}"))?;
    let stored_hash =
        queries::get_vote_tx_hash(&tx, round_id, wallet_id, bundle_index, proposal_id)
            .map_err(|e| format!("get_vote_tx_hash failed: {e}"))?;
    check_text_conflict(stored_hash.as_deref(), tx_hash, "vote tx_hash")?;
    let (stored_json, stored_position) =
        load_vote_recovery_fields(&tx, round_id, wallet_id, bundle_index, proposal_id)?;
    check_text_conflict(
        stored_json.as_deref(),
        commitment_bundle_json,
        "vote commitment_bundle_json",
    )?;
    check_vote_position_conflict(stored_position, vc_tree_position)?;
    queries::store_vote_tx_hash(&tx, round_id, wallet_id, bundle_index, proposal_id, tx_hash)
        .map_err(|e| format!("store_vote_tx_hash failed: {e}"))?;
    queries::mark_vote_submitted(&tx, round_id, wallet_id, bundle_index, proposal_id)
        .map_err(|e| format!("mark_vote_submitted failed: {e}"))?;
    queries::store_van_position(&tx, round_id, wallet_id, bundle_index, van_position)
        .map_err(|e| format!("store_van_position failed: {e}"))?;
    queries::store_commitment_bundle(
        &tx,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        commitment_bundle_json,
        vc_tree_position,
    )
    .map_err(|e| format!("store_commitment_bundle failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit vote confirmed transaction failed: {e}"))
}

/// Records helper-server share submission state for retry/recovery.
///
/// The write is atomic. Repeated calls for the same share key may update
/// sent-server history, but the stored nullifier must not change.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the transaction cannot be
/// committed, the upstream share write fails, or an existing nullifier conflicts.
#[allow(clippy::too_many_arguments)]
pub fn record_share_delegation(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    nullifier: &[u8],
    submit_at: u64,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    let mut conn = db.conn();
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin share delegation transaction failed: {e}"))?;
    let stored_nullifier = load_share_nullifier(
        &tx,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
    )?;
    check_blob_conflict(stored_nullifier.as_deref(), nullifier, "share nullifier")?;
    queries::record_share_delegation(
        &tx,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        nullifier,
        submit_at,
    )
    .map_err(|e| format!("record_share_delegation failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit share delegation transaction failed: {e}"))
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
    let mut conn = db.conn();
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin share confirmed transaction failed: {e}"))?;
    queries::mark_share_confirmed(
        &tx,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
    )
    .map_err(|e| format!("mark_share_confirmed failed: {e}"))?;
    tx.commit()
        .map_err(|e| format!("commit share confirmed transaction failed: {e}"))
}

/// Derives the vote phase from `votes` submission and recovery columns.
fn vote_phase(
    submitted: bool,
    tx_hash: Option<&str>,
    vc_tree_position: Option<i64>,
    commitment_bundle_json: Option<&str>,
) -> WorkflowPhase {
    if submitted
        && tx_hash.is_some()
        && vc_tree_position.is_some()
        && commitment_bundle_json.is_some()
    {
        WorkflowPhase::Confirmed
    } else if submitted && tx_hash.is_some() {
        WorkflowPhase::SubmittedVote
    } else if commitment_bundle_json.is_some() {
        WorkflowPhase::Signed
    } else {
        WorkflowPhase::Prepared
    }
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

/// Loads a stored helper-share nullifier, if the share row already exists.
fn load_share_nullifier(
    tx: &Transaction<'_>,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<Option<Vec<u8>>, String> {
    tx.query_row(
        "SELECT nullifier FROM share_delegations
         WHERE round_id = :round_id AND wallet_id = :wallet_id
         AND bundle_index = :bundle_index AND proposal_id = :proposal_id
         AND share_index = :share_index",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
            ":share_index": share_index as i64,
        },
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| format!("load share nullifier failed: {e}"))
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

/// Accepts missing or matching binary fields and rejects conflicting values.
fn check_blob_conflict(
    existing: Option<&[u8]>,
    requested: &[u8],
    field: &str,
) -> Result<(), String> {
    if let Some(existing) = existing {
        if existing != requested {
            return Err(format!("{field} conflict"));
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
