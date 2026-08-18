use std::collections::BTreeMap;

use super::db::open_voting_db;

/// Plan one complete vote submission's helper share timing and targets.
///
/// Loads every selected proposal's confirmed vote and recovery bundle inside
/// the wallet layer so secret share values never cross the API boundary.
/// Exactly one submission-wide largest share is returned first with
/// `submit_at` set to `now_seconds`; remaining shares retain the crate's
/// randomized schedules and helper targets.
///
/// # Errors
///
/// Returns an error if the voting database cannot be read, any selected vote
/// is missing or unconfirmed, recovery material is missing, or crate policy
/// rejects the supplied timing or server inputs.
pub fn plan_vote_share_submissions(
    db_path: &str,
    account_uuid: &str,
    round_id: &str,
    server_urls: &[String],
    now_seconds: u64,
    vote_end_time_seconds: u64,
    last_moment_buffer_seconds: Option<u64>,
) -> Result<Vec<zcash_voting::wire::VoteShareSubmissionPlan>, String> {
    let db = open_voting_db(db_path, account_uuid)?;
    let snapshot = zcash_voting::recovery::round_snapshot(&db, round_id)
        .map_err(|e| format!("round_snapshot failed: {e}"))?;
    let selected_proposals = db
        .ballot_intents(round_id)
        .map_err(|e| format!("ballot_intents failed: {e}"))?
        .into_iter()
        .filter_map(|(proposal_id, decision)| match decision {
            zcash_voting::session::Decision::Choice(choice) => Some((proposal_id, choice)),
            zcash_voting::session::Decision::Skipped => None,
        })
        .collect::<Vec<_>>();
    if selected_proposals.is_empty() {
        return Err("vote submission contains no selected proposals".to_string());
    }

    let votes = snapshot
        .votes
        .into_iter()
        .map(|vote| ((vote.bundle_index, vote.proposal_id), vote))
        .collect::<BTreeMap<_, _>>();
    let mut bundles = Vec::new();
    for bundle_index in 0..snapshot.bundle_count {
        for &(proposal_id, choice) in &selected_proposals {
            let vote = votes.get(&(bundle_index, proposal_id)).ok_or_else(|| {
                format!("missing vote for bundle={bundle_index} proposal={proposal_id}")
            })?;
            if vote.choice != choice {
                return Err(format!(
                    "vote choice does not match ballot intent for bundle={bundle_index} proposal={proposal_id}"
                ));
            }
            if vote.phase != zcash_voting::phases::VotePhase::Confirmed {
                return Err(format!(
                    "vote bundle={} proposal={} must be confirmed before share planning",
                    vote.bundle_index, vote.proposal_id
                ));
            }
            bundles.push(
                zcash_voting::vote::recovery_bundle(
                    &db,
                    round_id,
                    vote.bundle_index,
                    vote.proposal_id,
                )
                .map_err(|e| format!("load vote recovery failed: {e}"))?
                .ok_or_else(|| {
                    format!(
                        "missing vote recovery for bundle={} proposal={}",
                        vote.bundle_index, vote.proposal_id
                    )
                })?,
            );
        }
    }

    zcash_voting::share::plan_vote_share_submissions(
        &bundles,
        server_urls,
        now_seconds,
        vote_end_time_seconds,
        last_moment_buffer_seconds,
        true,
    )
    .map_err(|e| e.to_string())
}
