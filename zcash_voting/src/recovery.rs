//! Stable read-only recovery snapshot API.
//!
//! This module consolidates round-recovery reporting so wallet integrations can
//! fetch one typed snapshot instead of querying low-level storage tables.

use crate::{
    phases::{DelegationPhase, SharePhase, VotePhase, WorkflowPhase},
    round::VotingDb,
    share,
    storage::VoteRecord,
    types::{ShareDelegationRecord, VotingError},
};

/// Recoverable vote commitment bundle for one `(bundle_index, proposal_id)`.
pub use crate::wire::RecoverableCommitmentBundle;

/// Delegation recovery state for one bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationRecovery {
    pub bundle_index: u32,
    pub phase: DelegationPhase,
    pub tx_hash: Option<String>,
    pub van_leaf_position: Option<u32>,
}

impl DelegationRecovery {
    /// Returns the stable merged workflow phase used by wallet orchestration.
    pub fn workflow_phase(&self) -> WorkflowPhase {
        WorkflowPhase::for_delegation(self.phase)
    }
}

/// Vote recovery state for one vote key.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub choice: u32,
    pub phase: VotePhase,
    pub tx_hash: Option<String>,
    pub vc_tree_position: Option<u64>,
    pub has_commitment_bundle: bool,
}

impl VoteRecovery {
    /// Returns the stable merged workflow phase used by wallet orchestration.
    pub fn workflow_phase(&self) -> WorkflowPhase {
        WorkflowPhase::for_vote(self.phase)
    }
}

/// Share recovery state for one delegated share.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShareWorkflow {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub phase: SharePhase,
}

impl ShareWorkflow {
    /// Returns the stable merged workflow phase used by wallet orchestration.
    pub fn workflow_phase(&self) -> WorkflowPhase {
        WorkflowPhase::for_share(self.phase)
    }
}

/// Full read-only recovery snapshot for one round.
#[derive(Clone, Debug)]
pub struct RoundRecoverySnapshot {
    pub round_id: String,
    pub bundle_count: u32,
    pub delegation: Vec<DelegationRecovery>,
    pub votes: Vec<VoteRecovery>,
    pub commitment_bundles: Vec<RecoverableCommitmentBundle>,
    pub shares: Vec<ShareWorkflow>,
    pub share_delegations: Vec<ShareDelegationRecord>,
    pub unconfirmed_share_delegations: Vec<ShareDelegationRecord>,
}

/// Loads a recoverable commitment bundle row for one vote key.
///
/// If the bundle JSON exists but `vc_tree_position` is still NULL, this returns
/// `Some` with placeholder tree position `0` only when the vote transaction hash
/// has already been recorded; otherwise it returns `None`.
pub fn recoverable_commitment_bundle(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<RecoverableCommitmentBundle>, VotingError> {
    let fields = db.get_commitment_bundle_recovery_fields(round_id, bundle_index, proposal_id)?;
    let has_vote_tx_hash = db
        .get_vote_tx_hash(round_id, bundle_index, proposal_id)?
        .is_some();

    match fields {
        Some((Some(commitment_bundle_json), Some(position))) => {
            let vc_tree_position = u64::try_from(position).map_err(|_| VotingError::Internal {
                message: format!("stored vc_tree_position must be non-negative, got {position}"),
            })?;
            Ok(Some(RecoverableCommitmentBundle {
                bundle_index,
                proposal_id,
                commitment_bundle_json,
                vc_tree_position,
            }))
        }
        Some((Some(commitment_bundle_json), None)) if has_vote_tx_hash => {
            Ok(Some(RecoverableCommitmentBundle {
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

/// Loads the full recovery snapshot for one round.
pub fn round_snapshot(db: &VotingDb, round_id: &str) -> Result<RoundRecoverySnapshot, VotingError> {
    let bundle_count = db.get_bundle_count(round_id)?;
    let vote_rows = db.get_votes(round_id)?;

    let votes = build_vote_recovery_rows(db, round_id, &vote_rows)?;
    let mut commitment_bundles = Vec::new();
    for vote in &votes {
        if let Some(bundle) =
            recoverable_commitment_bundle(db, round_id, vote.bundle_index, vote.proposal_id)?
        {
            commitment_bundles.push(bundle);
        }
    }

    let delegation = db
        .delegation_phases(round_id)?
        .into_iter()
        .map(|(bundle_index, phase)| {
            Ok(DelegationRecovery {
                bundle_index,
                phase,
                tx_hash: db.get_delegation_tx_hash(round_id, bundle_index)?,
                van_leaf_position: db.load_van_position(round_id, bundle_index).ok(),
            })
        })
        .collect::<Result<Vec<_>, VotingError>>()?;

    let shares = db
        .share_phases(round_id)?
        .into_iter()
        .map(
            |(bundle_index, proposal_id, share_index, phase)| ShareWorkflow {
                bundle_index,
                proposal_id,
                share_index,
                phase,
            },
        )
        .collect();

    Ok(RoundRecoverySnapshot {
        round_id: round_id.to_string(),
        bundle_count,
        delegation,
        votes,
        commitment_bundles,
        shares,
        share_delegations: share::list(db, round_id)?,
        unconfirmed_share_delegations: share::unconfirmed(db, round_id)?,
    })
}

/// Clears recovery artifacts for one round while preserving ballot intent.
pub fn clear(db: &VotingDb, round_id: &str) -> Result<(), VotingError> {
    db.clear_recovery_state(round_id)
}

fn build_vote_recovery_rows(
    db: &VotingDb,
    round_id: &str,
    vote_rows: &[VoteRecord],
) -> Result<Vec<VoteRecovery>, VotingError> {
    use std::collections::BTreeMap;

    let choices = vote_rows
        .iter()
        .map(|row| ((row.bundle_index, row.proposal_id), row.choice))
        .collect::<BTreeMap<_, _>>();

    db.vote_phases(round_id)?
        .into_iter()
        .map(|(bundle_index, proposal_id, phase)| {
            let tx_hash = db.get_vote_tx_hash(round_id, bundle_index, proposal_id)?;
            let fields =
                db.get_commitment_bundle_recovery_fields(round_id, bundle_index, proposal_id)?;
            let (has_commitment_bundle, vc_tree_position) = match fields {
                Some((bundle_json, position)) => {
                    let vc_tree_position = position
                        .map(|position| {
                            u64::try_from(position).map_err(|_| VotingError::Internal {
                                message: format!(
                                    "stored vc_tree_position must be non-negative, got {position}"
                                ),
                            })
                        })
                        .transpose()?;
                    (bundle_json.is_some(), vc_tree_position)
                }
                None => (false, None),
            };

            let choice = choices
                .get(&(bundle_index, proposal_id))
                .copied()
                .ok_or_else(|| VotingError::Internal {
                    message: format!(
                        "vote phase exists without vote row for round={round_id}, bundle={bundle_index}, proposal={proposal_id}"
                    ),
                })?;

            Ok(VoteRecovery {
                bundle_index,
                proposal_id,
                choice,
                phase,
                tx_hash,
                vc_tree_position,
                has_commitment_bundle,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{round::RoundParams, storage::queries, types::NoteInfo};

    const ROUND_ID: &str = "3333333333333333333333333333333333333333333333333333333333333333";
    const WALLET_ID: &str = "wallet-recovery";

    #[test]
    fn recoverable_bundle_requires_vote_submission_when_position_missing() {
        let db = db_with_round(WALLET_ID);
        insert_vote(&db, 0, 1, 0, b"vote-0-1");
        store_commitment_bundle(&db, 0, 1, r#"{"bundle":"pending"}"#, None);

        assert!(recoverable_commitment_bundle(&db, ROUND_ID, 0, 1)
            .unwrap()
            .is_none());

        db.mark_vote_submitted(ROUND_ID, 0, 1, "vote-tx-0-1")
            .unwrap();
        let recovered = recoverable_commitment_bundle(&db, ROUND_ID, 0, 1)
            .unwrap()
            .unwrap();
        assert_eq!(recovered.vc_tree_position, 0);
    }

    #[test]
    fn round_snapshot_summarizes_mixed_state() {
        let db = db_with_round(WALLET_ID);
        db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();
        insert_vote(&db, 0, 1, 0, b"vote-0-1");
        insert_vote(&db, 1, 2, 1, b"vote-1-2");
        db.mark_vote_submitted(ROUND_ID, 1, 2, "vote-tx-1-2")
            .unwrap();
        store_commitment_bundle(&db, 1, 2, r#"{"bundle":"ok"}"#, Some(77));

        let snapshot = round_snapshot(&db, ROUND_ID).unwrap();

        assert_eq!(snapshot.bundle_count, 2);
        assert_eq!(snapshot.delegation.len(), 2);
        assert_eq!(snapshot.votes.len(), 2);
        assert!(snapshot.votes.iter().any(|vote| {
            vote.bundle_index == 1
                && vote.proposal_id == 2
                && vote.phase == VotePhase::Confirmed
                && vote.tx_hash.as_deref() == Some("vote-tx-1-2")
                && vote.vc_tree_position == Some(77)
                && vote.has_commitment_bundle
        }));
        assert_eq!(snapshot.commitment_bundles.len(), 1);
        assert_eq!(snapshot.commitment_bundles[0].vc_tree_position, 77);
    }

    #[test]
    fn round_snapshot_is_scoped_by_wallet_id() {
        let db = db_with_round(WALLET_ID);
        db.store_delegation_tx_hash(ROUND_ID, 0, "wallet-a-tx")
            .unwrap();

        db.set_wallet_id("wallet-recovery-other");
        db.create_round(crate::Network::Testnet, &round_params(), None)
            .unwrap();
        db.ensure_bundles(ROUND_ID, &[test_note_info(0)]).unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 0, "wallet-b-tx")
            .unwrap();

        db.set_wallet_id(WALLET_ID);
        let first = round_snapshot(&db, ROUND_ID).unwrap();
        db.set_wallet_id("wallet-recovery-other");
        let second = round_snapshot(&db, ROUND_ID).unwrap();

        assert_eq!(first.delegation[0].tx_hash.as_deref(), Some("wallet-a-tx"));
        assert_eq!(second.delegation[0].tx_hash.as_deref(), Some("wallet-b-tx"));
    }

    #[test]
    fn round_snapshot_survives_reopen_with_share_tracking() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let db_path = std::env::temp_dir().join(format!("zcash-voting-recovery-{unique}.sqlite"));
        let db_path_str = db_path.to_str().unwrap();

        let db = VotingDb::open(db_path_str).unwrap();
        db.set_wallet_id(WALLET_ID);
        db.create_round(crate::Network::Testnet, &round_params(), None)
            .unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db.store_delegation_tx_hash(ROUND_ID, 0, "delegation-tx-0")
            .unwrap();

        insert_vote(&db, 0, 1, 0, b"vote-0-1");
        db.mark_vote_submitted(ROUND_ID, 0, 1, "vote-tx-0-1")
            .unwrap();
        store_commitment_bundle(&db, 0, 1, r#"{"bundle":"ok"}"#, Some(9));
        db.record_share_delegation(
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            &[0x44; 32],
            1234,
        )
        .unwrap();

        drop(db);

        let reopened = VotingDb::open(db_path_str).unwrap();
        reopened.set_wallet_id(WALLET_ID);
        let snapshot = round_snapshot(&reopened, ROUND_ID).unwrap();

        assert!(snapshot
            .delegation
            .iter()
            .any(|d| d.bundle_index == 0 && d.tx_hash.as_deref() == Some("delegation-tx-0")));
        assert!(snapshot.votes.iter().any(|vote| vote.bundle_index == 0
            && vote.proposal_id == 1
            && vote.phase == VotePhase::Confirmed
            && vote.vc_tree_position == Some(9)
            && vote.has_commitment_bundle));
        assert_eq!(snapshot.share_delegations.len(), 1);
        assert_eq!(snapshot.unconfirmed_share_delegations.len(), 1);
        assert_eq!(
            snapshot.share_delegations[0].sent_to_urls,
            vec!["https://helper-a.example".to_string()]
        );
        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn clear_removes_recovery_artifacts_but_keeps_vote_rows() {
        let db = db_with_round(WALLET_ID);
        insert_vote(&db, 0, 1, 0, b"vote-0-1");
        db.mark_vote_submitted(ROUND_ID, 0, 1, "vote-tx-0-1")
            .unwrap();
        store_commitment_bundle(&db, 0, 1, r#"{"bundle":"ok"}"#, Some(11));
        db.record_share_delegation(
            ROUND_ID,
            0,
            1,
            0,
            &["https://helper-a.example".to_string()],
            &[0x44; 32],
            0,
        )
        .unwrap();

        clear(&db, ROUND_ID).unwrap();
        let snapshot = round_snapshot(&db, ROUND_ID).unwrap();

        assert_eq!(snapshot.votes.len(), 1);
        assert_eq!(snapshot.commitment_bundles.len(), 0);
        assert_eq!(snapshot.share_delegations.len(), 0);
        assert_eq!(snapshot.unconfirmed_share_delegations.len(), 0);
        assert!(snapshot.votes.iter().any(|vote| vote.bundle_index == 0
            && vote.proposal_id == 1
            && vote.tx_hash.is_none()
            && vote.vc_tree_position.is_none()
            && !vote.has_commitment_bundle));
    }

    #[test]
    fn recovery_records_expose_stable_workflow_phases() {
        let delegation = DelegationRecovery {
            bundle_index: 0,
            phase: DelegationPhase::Proved,
            tx_hash: None,
            van_leaf_position: None,
        };
        assert_eq!(delegation.workflow_phase(), WorkflowPhase::Signed);

        let vote = VoteRecovery {
            bundle_index: 0,
            proposal_id: 1,
            choice: 0,
            phase: VotePhase::Submitted,
            tx_hash: Some("vtx".to_string()),
            vc_tree_position: None,
            has_commitment_bundle: true,
        };
        assert_eq!(vote.workflow_phase(), WorkflowPhase::SubmittedVote);

        let share = ShareWorkflow {
            bundle_index: 0,
            proposal_id: 1,
            share_index: 0,
            phase: SharePhase::Submitted,
        };
        assert_eq!(share.workflow_phase(), WorkflowPhase::SubmittedShare);
    }

    fn db_with_round(wallet_id: &str) -> VotingDb {
        let db = VotingDb::open_in_memory().unwrap();
        db.set_wallet_id(wallet_id);
        db.create_round(crate::Network::Testnet, &round_params(), None)
            .unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        db
    }

    fn insert_vote(
        db: &VotingDb,
        bundle_index: u32,
        proposal_id: u32,
        choice: u32,
        commitment: &[u8],
    ) {
        queries::store_vote(
            &db.conn(),
            ROUND_ID,
            &db.wallet_id(),
            bundle_index,
            proposal_id,
            choice,
            commitment,
        )
        .unwrap();
    }

    fn store_commitment_bundle(
        db: &VotingDb,
        bundle_index: u32,
        proposal_id: u32,
        commitment_bundle_json: &str,
        vc_tree_position: Option<u64>,
    ) {
        let rows = db
            .conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = :commitment_bundle_json,
                        vc_tree_position = :vc_tree_position
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                 AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
                rusqlite::named_params! {
                    ":commitment_bundle_json": commitment_bundle_json,
                    ":vc_tree_position": vc_tree_position.map(|position| position as i64),
                    ":round_id": ROUND_ID,
                    ":wallet_id": db.wallet_id(),
                    ":bundle_index": bundle_index as i64,
                    ":proposal_id": proposal_id as i64,
                },
            )
            .unwrap();
        assert_eq!(rows, 1);
    }

    fn round_params() -> RoundParams {
        RoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_note_info(position: u64) -> NoteInfo {
        NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![position as u8 + 2; 32],
            value: crate::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}
