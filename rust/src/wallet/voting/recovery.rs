use rusqlite::{named_params, OptionalExtension};

use super::{state::open_voting_db, vote::VoteRecord};

/// Stored commitment bundle recovery data for one `(bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommitmentBundleRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub commitment_bundle_json: String,
    pub vc_tree_position: u64,
}

/// Stored delegation transaction hash for one voting note bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationTxRecovery {
    pub bundle_index: u32,
    pub tx_hash: String,
}

/// Stored vote transaction hash for one `(bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteTxRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub tx_hash: String,
}

/// Stored helper-server share delegation state for retry/resume.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShareDelegationRecord {
    pub round_id: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub sent_to_urls: Vec<String>,
    pub nullifier: Vec<u8>,
    pub phase: String,
    pub confirmed: bool,
    pub submit_at: u64,
    pub created_at: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationWorkflowRecovery {
    pub bundle_index: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub van_leaf_position: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteWorkflowRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub vc_tree_position: Option<u64>,
    pub has_commitment_bundle: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShareWorkflowRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub phase: String,
}

/// Recovery summary for one round.
///
/// Resume semantics:
/// - A delegation bundle is complete once its `delegation_tx_hash` is stored.
/// - A vote is complete once its vote tx hash and/or commitment bundle recovery
///   fields exist for the same `(bundle_index, proposal_id)`.
/// - Share submission resumes from unconfirmed share delegations, preserving
///   the merged `sent_to_urls` history.
/// - `clear_recovery_state` is an explicit escape hatch for finalized or
///   abandoned rounds, not part of normal retry flow.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RoundRecoveryState {
    pub round_id: String,
    pub bundle_count: u32,
    pub delegation_workflows: Vec<DelegationWorkflowRecovery>,
    pub delegation_tx_hashes: Vec<DelegationTxRecovery>,
    pub votes: Vec<VoteRecord>,
    pub vote_workflows: Vec<VoteWorkflowRecovery>,
    pub vote_tx_hashes: Vec<VoteTxRecovery>,
    pub commitment_bundles: Vec<CommitmentBundleRecovery>,
    pub share_workflows: Vec<ShareWorkflowRecovery>,
    pub share_delegations: Vec<ShareDelegationRecord>,
    pub unconfirmed_share_delegations: Vec<ShareDelegationRecord>,
}

/// Loads the persisted recovery snapshot for a voting round.
///
/// The snapshot is keyed by `db_path`, `wallet_id`, and `round_id`, and includes
/// bundle-level delegation tx hashes, vote records, vote tx hashes, commitment
/// bundles, and share delegation retry state. Missing recovery rows are omitted
/// rather than synthesized.
///
/// # Errors
///
/// Returns an error if the voting sidecar database cannot be opened or any
/// recovery table query fails.
pub fn get_round_recovery_state(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<RoundRecoveryState, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    let bundle_count = voting_db
        .get_bundle_count(round_id)
        .map_err(|e| format!("get_bundle_count failed: {e}"))?;
    let votes = voting_db
        .get_votes(round_id)
        .map_err(|e| format!("get_votes failed: {e}"))?
        .into_iter()
        .map(|record| VoteRecord {
            proposal_id: record.proposal_id,
            bundle_index: record.bundle_index,
            choice: record.choice,
        })
        .collect::<Vec<_>>();

    let mut delegation_tx_hashes = Vec::new();
    for bundle_index in 0..bundle_count {
        if let Some(tx_hash) = voting_db
            .get_delegation_tx_hash(round_id, bundle_index)
            .map_err(|e| format!("get_delegation_tx_hash failed: {e}"))?
        {
            delegation_tx_hashes.push(DelegationTxRecovery {
                bundle_index,
                tx_hash,
            });
        }
    }

    let mut vote_tx_hashes = Vec::new();
    let mut commitment_bundles = Vec::new();
    for vote in &votes {
        let vote_tx_hash = voting_db
            .get_vote_tx_hash(round_id, vote.bundle_index, vote.proposal_id)
            .map_err(|e| format!("get_vote_tx_hash failed: {e}"))?;
        let has_vote_tx_hash = vote_tx_hash.is_some();
        if let Some(tx_hash) = vote_tx_hash {
            vote_tx_hashes.push(VoteTxRecovery {
                bundle_index: vote.bundle_index,
                proposal_id: vote.proposal_id,
                tx_hash,
            });
        }

        if let Some(bundle) = get_recoverable_commitment_bundle_from_db(
            &voting_db,
            round_id,
            vote.bundle_index,
            vote.proposal_id,
            has_vote_tx_hash,
        )? {
            commitment_bundles.push(bundle);
        }
    }

    let delegation_workflows = voting_db
        .delegation_phases(round_id)
        .map_err(|e| format!("load delegation phases failed: {e}"))?
        .into_iter()
        .map(|(bundle_index, phase)| {
            let tx_hash = voting_db
                .get_delegation_tx_hash(round_id, bundle_index)
                .map_err(|e| format!("load delegation tx hash failed: {e}"))?;
            Ok(DelegationWorkflowRecovery {
                bundle_index,
                phase: delegation_workflow_phase(phase).to_string(),
                tx_hash,
                van_leaf_position: voting_db.load_van_position(round_id, bundle_index).ok(),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let vote_workflows = voting_db
        .vote_phases(round_id)
        .map_err(|e| format!("load vote phases failed: {e}"))?
        .into_iter()
        .map(|(bundle_index, proposal_id, phase)| {
            let tx_hash = voting_db
                .get_vote_tx_hash(round_id, bundle_index, proposal_id)
                .map_err(|e| format!("load vote tx hash failed: {e}"))?;
            let (has_commitment_bundle, vc_tree_position) =
                load_vote_recovery_presence(&voting_db, round_id, bundle_index, proposal_id)?;
            Ok(VoteWorkflowRecovery {
                bundle_index,
                proposal_id,
                phase: vote_workflow_phase(phase).to_string(),
                tx_hash,
                vc_tree_position,
                has_commitment_bundle,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let share_workflows = voting_db
        .share_phases(round_id)
        .map_err(|e| format!("load share phases failed: {e}"))?
        .into_iter()
        .map(
            |(bundle_index, proposal_id, share_index, phase)| ShareWorkflowRecovery {
                bundle_index,
                proposal_id,
                share_index,
                phase: share_workflow_phase(phase).to_string(),
            },
        )
        .collect();
    let share_delegations = map_share_records(
        zcash_voting::share::list(&voting_db, round_id),
        "get_share_delegations",
    )?;
    let unconfirmed_share_delegations = map_share_records(
        zcash_voting::share::unconfirmed(&voting_db, round_id),
        "get_unconfirmed_delegations",
    )?;

    Ok(RoundRecoveryState {
        round_id: round_id.to_string(),
        bundle_count,
        delegation_workflows,
        delegation_tx_hashes,
        votes,
        vote_workflows,
        vote_tx_hashes,
        commitment_bundles,
        share_workflows,
        share_delegations,
        unconfirmed_share_delegations,
    })
}

/// Returns the stored vote transaction hash for one vote, when present.
///
/// `None` means no recovery hash has been persisted for the exact
/// `(round_id, bundle_index, proposal_id)` key.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_vote_tx_hash(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<String>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_vote_tx_hash(round_id, bundle_index, proposal_id)
        .map_err(|e| format!("get_vote_tx_hash failed: {e}"))
}

/// Returns the stored commitment bundle recovery payload for one vote.
///
/// The returned value preserves the caller-supplied `bundle_index` and
/// `proposal_id` alongside the stored bundle JSON and vote commitment tree
/// position.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_commitment_bundle(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<CommitmentBundleRecovery>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    let has_vote_tx_hash = voting_db
        .get_vote_tx_hash(round_id, bundle_index, proposal_id)
        .map_err(|e| format!("get_vote_tx_hash failed: {e}"))?
        .is_some();
    get_recoverable_commitment_bundle_from_db(
        &voting_db,
        round_id,
        bundle_index,
        proposal_id,
        has_vote_tx_hash,
    )
}

/// Lists all stored share delegation records for a round.
///
/// Returned records include both confirmed and unconfirmed shares.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_share_delegations(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    map_share_records(
        zcash_voting::share::list(&voting_db, round_id),
        "get_share_delegations",
    )
}

/// Lists share delegation records that still need confirmation.
///
/// A returned record may already have `sent_to_urls` populated; callers should
/// preserve that history when retrying helper submission.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or queried.
pub fn get_unconfirmed_share_delegations(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    map_share_records(
        zcash_voting::share::unconfirmed(&voting_db, round_id),
        "get_unconfirmed_delegations",
    )
}

/// Adds helper-server URLs to the sent history for one share delegation.
///
/// Existing URLs are preserved and duplicates are ignored by the storage layer.
/// The share delegation must already exist.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or the share record
/// cannot be updated.
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
///
/// This removes delegation tx hashes, vote tx hashes, commitment bundle recovery
/// data, and share delegation tracking for `round_id`. Use only after a round is
/// finalized or intentionally abandoned.
///
/// # Errors
///
/// Returns an error if the voting database cannot be opened or recovery state
/// cannot be cleared.
pub fn clear_recovery_state(db_path: &str, wallet_id: &str, round_id: &str) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .clear_recovery_state(round_id)
        .map_err(|e| format!("clear_recovery_state failed: {e}"))
}

fn map_share_records(
    records: Result<Vec<zcash_voting::ShareDelegationRecord>, zcash_voting::VotingError>,
    operation: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    Ok(records
        .map_err(|e| format!("{operation} failed: {e}"))?
        .into_iter()
        .map(share_record_from_upstream)
        .collect())
}

/// Reads commitment recovery without failing on rows whose vote tree position is
/// not known yet.
///
/// Committed votes persist recovery JSON before cast-vote confirmation provides
/// the vote commitment tree position. If no cast-vote tx hash was stored yet,
/// normal retry should rebuild the commitment instead of trying to reuse that
/// partial row. If a tx hash was stored, return the JSON with a placeholder
/// position so confirmation recovery can replace it with the chain value before
/// share submission.
fn get_recoverable_commitment_bundle_from_db(
    voting_db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    has_vote_tx_hash: bool,
) -> Result<Option<CommitmentBundleRecovery>, String> {
    let conn = voting_db.conn();
    let wallet_id = voting_db.wallet_id();
    let row = conn
        .query_row(
            "SELECT commitment_bundle_json, vc_tree_position FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
             AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| {
                Ok((
                    row.get::<_, Option<String>>(0)?,
                    row.get::<_, Option<i64>>(1)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("get raw commitment bundle failed: {e}"))?;

    match row {
        Some((Some(commitment_bundle_json), Some(position))) => {
            let vc_tree_position = u64::try_from(position).map_err(|_| {
                format!("stored vc_tree_position must be non-negative, got {position}")
            })?;
            Ok(Some(CommitmentBundleRecovery {
                bundle_index,
                proposal_id,
                commitment_bundle_json,
                vc_tree_position,
            }))
        }
        Some((Some(commitment_bundle_json), None)) if has_vote_tx_hash => {
            Ok(Some(CommitmentBundleRecovery {
                bundle_index,
                proposal_id,
                commitment_bundle_json,
                vc_tree_position: 0,
            }))
        }
        Some((Some(_), None)) => Ok(None),
        _ => Ok(None),
    }
}

/// Converts the upstream share record into the flat API-facing recovery type.
fn share_record_from_upstream(
    record: zcash_voting::ShareDelegationRecord,
) -> ShareDelegationRecord {
    ShareDelegationRecord {
        round_id: record.round_id,
        bundle_index: record.bundle_index,
        proposal_id: record.proposal_id,
        share_index: record.share_index,
        sent_to_urls: record.sent_to_urls,
        nullifier: record.nullifier,
        phase: if record.confirmed {
            "confirmed".to_string()
        } else {
            "submitted_share".to_string()
        },
        confirmed: record.confirmed,
        submit_at: record.submit_at,
        created_at: record.created_at,
    }
}

fn delegation_workflow_phase(phase: zcash_voting::phases::DelegationPhase) -> &'static str {
    match phase {
        zcash_voting::phases::DelegationPhase::Prepared => "prepared",
        zcash_voting::phases::DelegationPhase::PcztBuilt
        | zcash_voting::phases::DelegationPhase::Proved => "signed",
        zcash_voting::phases::DelegationPhase::Submitted => "submitted_delegation",
        zcash_voting::phases::DelegationPhase::Confirmed => "confirmed",
        _ => "prepared",
    }
}

fn vote_workflow_phase(phase: zcash_voting::phases::VotePhase) -> &'static str {
    match phase {
        zcash_voting::phases::VotePhase::Prepared => "prepared",
        zcash_voting::phases::VotePhase::Committed => "signed",
        zcash_voting::phases::VotePhase::Submitted => "submitted_vote",
        zcash_voting::phases::VotePhase::Confirmed => "confirmed",
        _ => "prepared",
    }
}

fn share_workflow_phase(phase: zcash_voting::phases::SharePhase) -> &'static str {
    match phase {
        zcash_voting::phases::SharePhase::Submitted => "submitted_share",
        zcash_voting::phases::SharePhase::Confirmed => "confirmed",
        _ => "submitted_share",
    }
}

fn load_vote_recovery_presence(
    db: &zcash_voting::storage::VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(bool, Option<u64>), String> {
    let conn = db.conn();
    let wallet_id = db.wallet_id();
    let fields: Option<(Option<String>, Option<i64>)> = conn
        .query_row(
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
        .optional()
        .map_err(|e| format!("load vote recovery fields failed: {e}"))?;

    let Some((bundle_json, position)) = fields else {
        return Ok((false, None));
    };
    let position = position
        .map(|position| {
            u64::try_from(position)
                .map_err(|_| format!("vc_tree_position must be non-negative, got {position}"))
        })
        .transpose()?;
    Ok((bundle_json.is_some(), position))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::voting::{state, workflow};
    use workflow::{
        mark_share_confirmed, mark_vote_confirmed, mark_vote_submitted, record_share_delegation,
    };

    const WALLET_ID: &str = "wallet-recovery";
    const ROUND_ID: &str = "round-recovery";

    #[test]
    fn vote_tx_hashes_are_isolated_by_bundle_and_proposal() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_vote(0, 2, 1, b"vote-0-2");
        fixture.insert_vote(1, 1, 1, b"vote-1-1");

        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "tx-0-1").unwrap();
        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 1, 1, "tx-1-1").unwrap();

        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .as_deref(),
            Some("tx-0-1")
        );
        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 2)
                .unwrap()
                .as_deref(),
            None
        );
        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 1, 1)
                .unwrap()
                .as_deref(),
            Some("tx-1-1")
        );
    }

    #[test]
    fn commitment_bundle_recovery_returns_exact_vote_key() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_vote(1, 1, 1, b"vote-1-1");
        fixture.insert_commitment_bundle(1, 1, r#"{"bundle":"one"}"#, Some(42));

        assert!(
            get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .is_none()
        );
        let recovery = get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 1, 1)
            .unwrap()
            .unwrap();

        assert_eq!(recovery.bundle_index, 1);
        assert_eq!(recovery.proposal_id, 1);
        assert_eq!(recovery.commitment_bundle_json, r#"{"bundle":"one"}"#);
        assert_eq!(recovery.vc_tree_position, 42);
    }

    #[test]
    fn vote_confirmation_records_tree_position_for_stored_recovery() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();
        let recovery_json = vote_recovery_json(0, 1, 0, 0);
        fixture.insert_commitment_bundle(0, 1, &recovery_json, None);

        mark_vote_confirmed(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            "vote-tx-0-1",
            1,
            2,
        )
        .unwrap();

        let recovery = get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
            .unwrap()
            .unwrap();
        assert_eq!(recovery.vc_tree_position, 2);
    }

    #[test]
    fn share_delegation_record_add_and_mark_confirmed_flow() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_commitment_bundle(0, 1, &vote_recovery_json(0, 1, 0, 0), Some(0));
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            1234,
        )
        .unwrap();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &[
                "https://helper-a.example".to_string(),
                "https://helper-b.example".to_string(),
            ],
            5678,
        )
        .unwrap();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &[
                "https://helper-a.example".to_string(),
                "https://helper-b.example".to_string(),
            ],
            5678,
        )
        .unwrap();

        let shares = get_share_delegations(fixture.path(), WALLET_ID, ROUND_ID).unwrap();
        assert_eq!(shares.len(), 1);
        assert_eq!(
            shares[0].sent_to_urls,
            vec![
                "https://helper-a.example".to_string(),
                "https://helper-b.example".to_string()
            ]
        );
        assert_eq!(shares[0].nullifier, expected_share_nullifier());
        assert_eq!(shares[0].submit_at, 5678);

        mark_share_confirmed(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, 0).unwrap();
        assert!(
            get_unconfirmed_share_delegations(fixture.path(), WALLET_ID, ROUND_ID)
                .unwrap()
                .is_empty()
        );
        assert!(mark_share_confirmed(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, 9).is_err());
    }

    #[test]
    fn add_sent_servers_merges_and_deduplicates_urls() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_commitment_bundle(0, 1, &vote_recovery_json(0, 1, 0, 0), Some(0));
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            1234,
        )
        .unwrap();

        add_sent_servers(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &[
                "https://helper-a.example".to_string(),
                "https://helper-c.example".to_string(),
            ],
        )
        .unwrap();

        let shares = get_share_delegations(fixture.path(), WALLET_ID, ROUND_ID).unwrap();
        assert_eq!(
            shares[0].sent_to_urls,
            vec![
                "https://helper-a.example".to_string(),
                "https://helper-c.example".to_string()
            ]
        );
        assert_eq!(shares[0].submit_at, 0);
    }

    #[test]
    fn round_recovery_state_summarizes_mixed_state() {
        let fixture = RecoveryFixture::new();
        fixture
            .db
            .store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_vote(1, 2, 1, b"vote-1-2");
        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 1, 2, "vote-tx-1-2").unwrap();
        fixture.insert_commitment_bundle(1, 2, &vote_recovery_json(1, 2, 1, 77), Some(77));
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            1,
            2,
            0,
            &["https://helper-a.example".to_string()],
            0,
        )
        .unwrap();

        let state = get_round_recovery_state(fixture.path(), WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(state.round_id, ROUND_ID);
        assert_eq!(state.bundle_count, 2);
        assert_eq!(state.delegation_tx_hashes.len(), 1);
        assert_eq!(state.votes.len(), 2);
        assert_eq!(state.vote_tx_hashes[0].tx_hash, "vote-tx-1-2");
        assert_eq!(state.commitment_bundles[0].vc_tree_position, 77);
        assert_eq!(state.share_delegations.len(), 1);
        assert_eq!(state.unconfirmed_share_delegations.len(), 1);
    }

    #[test]
    fn round_recovery_state_ignores_unsubmitted_bundle_without_position() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_commitment_bundle_without_position(0, 1, r#"{"bundle":"pending"}"#);

        let state = get_round_recovery_state(fixture.path(), WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(
            state.vote_workflows,
            vec![VoteWorkflowRecovery {
                bundle_index: 0,
                proposal_id: 1,
                phase: "signed".to_string(),
                tx_hash: None,
                vc_tree_position: None,
                has_commitment_bundle: true,
            }]
        );
        assert!(state.commitment_bundles.is_empty());
        assert!(
            get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn round_recovery_state_recovers_submitted_bundle_without_position() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();
        fixture.insert_commitment_bundle_without_position(0, 1, r#"{"bundle":"pending"}"#);

        let state = get_round_recovery_state(fixture.path(), WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(state.vote_tx_hashes.len(), 1);
        assert_eq!(
            state.vote_workflows,
            vec![VoteWorkflowRecovery {
                bundle_index: 0,
                proposal_id: 1,
                phase: "submitted_vote".to_string(),
                tx_hash: Some("vote-tx-0-1".to_string()),
                vc_tree_position: None,
                has_commitment_bundle: true,
            }]
        );
        assert_eq!(
            state.commitment_bundles,
            vec![CommitmentBundleRecovery {
                bundle_index: 0,
                proposal_id: 1,
                commitment_bundle_json: r#"{"bundle":"pending"}"#.to_string(),
                vc_tree_position: 0,
            }]
        );
        assert_eq!(
            get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .unwrap()
                .vc_tree_position,
            0
        );
    }

    #[test]
    fn round_recovery_state_survives_sidecar_reopen() {
        let fixture = RecoveryFixture::new();
        let RecoveryFixture {
            _temp_dir,
            db_path,
            db,
        } = fixture;
        let path = db_path.to_str().unwrap().to_string();

        workflow::mark_delegation_confirmed(&path, WALLET_ID, ROUND_ID, 0, "delegation-tx-0", 5)
            .unwrap();
        insert_vote(&db, 0, 1, 0, b"vote-0-1");
        let recovery_json = vote_recovery_json(0, 1, 0, 0);
        store_commitment_bundle_fixture(&db, 0, 1, &recovery_json, None);
        mark_vote_confirmed(&path, WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1", 5, 9).unwrap();
        record_share_delegation(
            &path,
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            1234,
        )
        .unwrap();
        add_sent_servers(
            &path,
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-b.example".to_string()],
        )
        .unwrap();

        drop(db);
        let state = get_round_recovery_state(&path, WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(state.bundle_count, 2);
        assert!(state
            .delegation_workflows
            .contains(&DelegationWorkflowRecovery {
                bundle_index: 0,
                phase: "confirmed".to_string(),
                tx_hash: Some("delegation-tx-0".to_string()),
                van_leaf_position: Some(5),
            }));
        assert_eq!(
            state.vote_workflows,
            vec![VoteWorkflowRecovery {
                bundle_index: 0,
                proposal_id: 1,
                phase: "confirmed".to_string(),
                tx_hash: Some("vote-tx-0-1".to_string()),
                vc_tree_position: Some(9),
                has_commitment_bundle: true,
            }]
        );
        assert_eq!(state.commitment_bundles[0].vc_tree_position, 9);
        assert_eq!(
            state.share_workflows,
            vec![ShareWorkflowRecovery {
                bundle_index: 0,
                proposal_id: 1,
                share_index: 0,
                phase: "submitted_share".to_string(),
            }]
        );
        assert_eq!(state.share_delegations.len(), 1);
        assert_eq!(
            state.share_delegations[0].sent_to_urls,
            vec![
                "https://helper-a.example".to_string(),
                "https://helper-b.example".to_string(),
            ]
        );
        assert_eq!(state.share_delegations[0].round_id, ROUND_ID);
        assert_eq!(state.share_delegations[0].bundle_index, 0);
        assert_eq!(state.share_delegations[0].proposal_id, 1);
        assert_eq!(state.share_delegations[0].share_index, 0);
        assert_eq!(
            state.share_delegations[0].nullifier,
            expected_share_nullifier()
        );
        assert_eq!(state.share_delegations[0].phase, "submitted_share");
        assert!(!state.share_delegations[0].confirmed);
        assert_eq!(state.share_delegations[0].submit_at, 0);
        assert_eq!(state.unconfirmed_share_delegations.len(), 1);
        assert_eq!(
            state.unconfirmed_share_delegations[0],
            state.share_delegations[0]
        );
    }

    #[test]
    fn recovery_writes_are_idempotent_and_reject_conflicts() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        fixture.insert_commitment_bundle(0, 1, &vote_recovery_json(0, 1, 0, 0), Some(0));

        workflow::mark_delegation_submitted(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            "delegation-tx-0",
        )
        .unwrap();
        workflow::mark_delegation_submitted(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            "delegation-tx-0",
        )
        .unwrap();
        assert!(workflow::mark_delegation_submitted(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            "delegation-tx-conflict",
        )
        .unwrap_err()
        .contains("delegation tx_hash conflict"));

        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();
        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();
        assert!(mark_vote_submitted(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            "vote-tx-conflict",
        )
        .unwrap_err()
        .contains("vote tx_hash conflict"));

        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            1234,
        )
        .unwrap();
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            1234,
        )
        .unwrap();
        fixture
            .db
            .conn()
            .execute(
                "UPDATE share_delegations SET nullifier = :nullifier
                 WHERE round_id = :round_id
                   AND wallet_id = :wallet_id
                   AND bundle_index = 0
                   AND proposal_id = 1
                   AND share_index = 0",
                rusqlite::named_params! {
                    ":nullifier": vec![0xEE_u8; 32],
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();
        assert!(record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            1234,
        )
        .unwrap_err()
        .contains("share nullifier conflict"));
    }

    #[test]
    fn recovery_state_is_scoped_by_wallet_id_for_account_switches() {
        let fixture = RecoveryFixture::new();
        fixture
            .db
            .store_delegation_tx_hash(ROUND_ID, 0, "account-1-delegation")
            .unwrap();

        let other_db = state::open_voting_db(fixture.path(), "wallet-recovery-other").unwrap();
        state::init_voting_round(&other_db, &test_round_params(), None).unwrap();
        other_db
            .ensure_bundles(ROUND_ID, &[test_note_info(0)])
            .unwrap();
        other_db
            .store_delegation_tx_hash(ROUND_ID, 0, "account-2-delegation")
            .unwrap();

        let first = get_round_recovery_state(fixture.path(), WALLET_ID, ROUND_ID).unwrap();
        let second =
            get_round_recovery_state(fixture.path(), "wallet-recovery-other", ROUND_ID).unwrap();

        assert_eq!(
            first.delegation_tx_hashes[0].tx_hash,
            "account-1-delegation"
        );
        assert_eq!(
            second.delegation_tx_hashes[0].tx_hash,
            "account-2-delegation"
        );
    }

    #[test]
    fn mark_vote_submitted_records_vote_tx_hash() {
        let fixture = RecoveryFixture::new();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");

        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();

        let votes = fixture.db.get_votes(ROUND_ID).unwrap();
        assert_eq!(votes.len(), 1);
        assert_eq!(votes[0].proposal_id, 1);
        assert_eq!(votes[0].bundle_index, 0);
        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .as_deref(),
            Some("vote-tx-0-1")
        );
    }

    #[test]
    fn clear_recovery_state_clears_recovery_columns_and_share_tracking() {
        let fixture = RecoveryFixture::new();
        fixture
            .db
            .store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        fixture.insert_vote(0, 1, 0, b"vote-0-1");
        mark_vote_submitted(fixture.path(), WALLET_ID, ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();
        fixture.insert_commitment_bundle(0, 1, &vote_recovery_json(0, 1, 0, 11), Some(11));
        record_share_delegation(
            fixture.path(),
            WALLET_ID,
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            0,
        )
        .unwrap();

        clear_recovery_state(fixture.path(), WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(
            fixture
                .db
                .get_delegation_tx_hash(ROUND_ID, 0)
                .unwrap()
                .as_deref(),
            None
        );
        assert_eq!(
            get_vote_tx_hash(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .as_deref(),
            None
        );
        assert!(
            get_commitment_bundle(fixture.path(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .is_none()
        );
        assert!(get_share_delegations(fixture.path(), WALLET_ID, ROUND_ID)
            .unwrap()
            .is_empty());
    }

    struct RecoveryFixture {
        _temp_dir: tempfile::TempDir,
        db_path: std::path::PathBuf,
        db: zcash_voting::storage::VotingDb,
    }

    impl RecoveryFixture {
        fn new() -> Self {
            let temp_dir = tempfile::tempdir().unwrap();
            let db_path = temp_dir.path().join("voting.sqlite");
            let db = state::open_voting_db(db_path.to_str().unwrap(), WALLET_ID).unwrap();
            state::init_voting_round(&db, &test_round_params(), None).unwrap();
            let notes: Vec<_> = (0..6).map(test_note_info).collect();
            db.ensure_bundles(ROUND_ID, &notes).unwrap();
            Self {
                _temp_dir: temp_dir,
                db_path,
                db,
            }
        }

        fn path(&self) -> &str {
            self.db_path.to_str().unwrap()
        }

        fn insert_vote(&self, bundle_index: u32, proposal_id: u32, choice: u32, commitment: &[u8]) {
            insert_vote(&self.db, bundle_index, proposal_id, choice, commitment);
        }

        fn insert_commitment_bundle(
            &self,
            bundle_index: u32,
            proposal_id: u32,
            commitment_bundle_json: &str,
            vc_tree_position: Option<u64>,
        ) {
            store_commitment_bundle_fixture(
                &self.db,
                bundle_index,
                proposal_id,
                commitment_bundle_json,
                vc_tree_position,
            );
        }

        fn insert_commitment_bundle_without_position(
            &self,
            bundle_index: u32,
            proposal_id: u32,
            commitment_bundle_json: &str,
        ) {
            self.insert_commitment_bundle(bundle_index, proposal_id, commitment_bundle_json, None);
        }
    }

    fn insert_vote(
        db: &zcash_voting::storage::VotingDb,
        bundle_index: u32,
        proposal_id: u32,
        choice: u32,
        commitment: &[u8],
    ) {
        let conn = db.conn();
        let wallet_id = db.wallet_id();
        zcash_voting::storage::queries::store_vote(
            &conn,
            ROUND_ID,
            &wallet_id,
            bundle_index,
            proposal_id,
            choice,
            commitment,
        )
        .unwrap();
    }

    fn store_commitment_bundle_fixture(
        db: &zcash_voting::storage::VotingDb,
        bundle_index: u32,
        proposal_id: u32,
        commitment_bundle_json: &str,
        vc_tree_position: Option<u64>,
    ) {
        let conn = db.conn();
        let wallet_id = db.wallet_id();
        let rows = conn
            .execute(
                "UPDATE votes SET commitment_bundle_json = :commitment_bundle_json,
                        vc_tree_position = :vc_tree_position
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                 AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":commitment_bundle_json": commitment_bundle_json,
                    ":vc_tree_position": vc_tree_position.map(|position| position as i64),
                    ":round_id": ROUND_ID,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index as i64,
                    ":proposal_id": proposal_id as i64,
                },
            )
            .unwrap();
        assert_eq!(rows, 1);
    }

    fn vote_recovery_json(
        bundle_index: u32,
        proposal_id: u32,
        vote_decision: u32,
        vc_tree_position: u64,
    ) -> String {
        serde_json::json!({
            "format": "zcash_voting_vote_recovery_v1",
            "vote_round_id": ROUND_ID,
            "bundle_index": bundle_index,
            "proposal_id": proposal_id,
            "vote_decision": vote_decision,
            "anchor_height": 100,
            "vc_tree_position": vc_tree_position,
            "single_share": false,
            "num_options": 2,
            "van_nullifier": vec![1u8; 32],
            "vote_authority_note_new": vec![2u8; 32],
            "vote_commitment": vec![3u8; 32],
            "proof": vec![4u8; 8],
            "shares_hash": vec![5u8; 32],
            "r_vpk": vec![6u8; 32],
            "alpha_v": vec![7u8; 32],
            "vote_auth_sig": vec![8u8; 64],
            "encrypted_shares": [{
                "c1": vec![9u8; 32],
                "c2": vec![10u8; 32],
                "share_index": 0,
                "plaintext_value": 1,
                "randomness": vec![11u8; 32],
            }],
            "share_blinds": [vec![12u8; 32]],
            "share_comms": [vec![13u8; 32]],
        })
        .to_string()
    }

    fn expected_share_nullifier() -> Vec<u8> {
        zcash_voting::share::compute_nullifier(&[3u8; 32], 0, &[12u8; 32])
            .unwrap()
            .to_vec()
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_note_info(position: u64) -> zcash_voting::NoteInfo {
        zcash_voting::NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: zcash_voting::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}
