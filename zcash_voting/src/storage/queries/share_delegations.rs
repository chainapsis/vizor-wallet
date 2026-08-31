use rusqlite::{named_params, Connection, OptionalExtension, TransactionBehavior};

use super::{load_ballot_intent, load_vote_choice_for_intent_check};
use crate::helper::url::{canonical_helper_url_list, canonicalize_helper_base_url};
use crate::share::{ShareAttemptCapacityPolicy, ShareDeliveryState};
use crate::types::{ShareDelegationRecord, VotingError};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ShareAttemptReservation {
    Started,
    AlreadyRecorded,
    PlacementCapacityReached,
    StaleGeneration,
}

pub(super) fn delete_for_replaced_vote(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    conn.execute(
        "DELETE FROM share_delegations
         WHERE round_id = :round_id
           AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index
           AND proposal_id = :proposal_id",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear stale share delegations: {}", e),
    })?;
    Ok(())
}

pub fn clear_stale_share_delegations_for_intent(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    proposal_id: u32,
    skipped: bool,
    choice: Option<u32>,
) -> Result<u64, VotingError> {
    let deleted_row_count = if skipped {
        conn.execute(
            "DELETE FROM share_delegations
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":proposal_id": proposal_id as i64,
            },
        )
    } else if let Some(choice) = choice {
        conn.execute(
            "DELETE FROM share_delegations
             WHERE round_id = :round_id
               AND wallet_id = :wallet_id
               AND proposal_id = :proposal_id
               AND NOT EXISTS (
                   SELECT 1 FROM votes
                   WHERE votes.round_id = share_delegations.round_id
                     AND votes.wallet_id = share_delegations.wallet_id
                     AND votes.bundle_index = share_delegations.bundle_index
                     AND votes.proposal_id = share_delegations.proposal_id
                     AND votes.choice = :choice
               )",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":proposal_id": proposal_id as i64,
                ":choice": choice as i64,
            },
        )
    } else {
        Ok(0)
    }
    .map_err(|e| VotingError::Internal {
        message: format!("failed to clear stale share delegations: {}", e),
    })?;
    Ok(deleted_row_count as u64)
}

/// Splits persisted helper identities into canonical entries and legacy
/// entries accepted by older schemas that no longer canonicalize. Legacy
/// entries are never contacted or counted, but rewrites preserve them verbatim
/// so recorded delivery history is not lost.
fn partition_stored_helper_urls(urls: &[String]) -> (Vec<String>, Vec<String>) {
    let mut canonical_urls = Vec::with_capacity(urls.len());
    let mut preserved_legacy_urls = Vec::new();
    for url in urls {
        match canonicalize_helper_base_url(url) {
            Ok(canonical_url) => {
                if !canonical_urls.contains(&canonical_url) {
                    canonical_urls.push(canonical_url);
                }
            }
            Err(_) => {
                if !preserved_legacy_urls.contains(url) {
                    preserved_legacy_urls.push(url.clone());
                }
            }
        }
    }
    (canonical_urls, preserved_legacy_urls)
}

fn parse_url_list(json: &str, name: &str) -> Result<Vec<String>, VotingError> {
    serde_json::from_str(json).map_err(|e| VotingError::Internal {
        message: format!("failed to deserialize {name}: {e}"),
    })
}

/// Serializes canonical entries followed by preserved legacy entries.
fn serialize_url_list(
    canonical_urls: &[String],
    preserved_legacy_urls: &[String],
    name: &str,
) -> Result<String, VotingError> {
    let stored_urls: Vec<&String> = canonical_urls
        .iter()
        .chain(preserved_legacy_urls.iter())
        .collect();
    serde_json::to_string(&stored_urls).map_err(|e| VotingError::Internal {
        message: format!("failed to serialize {name}: {e}"),
    })
}

/// Durably marks a helper POST as in flight before the request is dispatched.
///
/// The helper URL must canonicalize and belong to `placement_server_urls`.
/// Ballot intent and existing share state are validated before the row is
/// updated; callers may dispatch only after this returns `true`. Returns
/// `false` when this helper already has delivery state or accepted plus
/// in-flight configured helpers already reach `target_count`.
#[allow(clippy::too_many_arguments)]
pub fn add_attempting_server(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    server_url: &str,
    placement_server_urls: &[String],
    target_count: usize,
) -> Result<bool, VotingError> {
    match add_attempting_server_for_generation(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        server_url,
        placement_server_urls,
        target_count,
        ShareAttemptCapacityPolicy::EnforcePlacementTarget,
        None,
    )? {
        ShareAttemptReservation::Started => Ok(true),
        ShareAttemptReservation::AlreadyRecorded
        | ShareAttemptReservation::PlacementCapacityReached => Ok(false),
        ShareAttemptReservation::StaleGeneration => Err(missing_share_error(
            round_id,
            bundle_index,
            proposal_id,
            share_index,
        )),
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn add_attempting_server_for_generation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    server_url: &str,
    placement_server_urls: &[String],
    target_count: usize,
    capacity_policy: ShareAttemptCapacityPolicy,
    expected_nullifier: Option<&[u8]>,
) -> Result<ShareAttemptReservation, VotingError> {
    let placement_server_urls = canonical_helper_url_list(placement_server_urls)?;
    let server_url = canonicalize_helper_base_url(server_url)?;
    if !placement_server_urls.contains(&server_url) {
        return Err(VotingError::InvalidInput {
            message: "attempted helper must belong to the placement fleet".to_string(),
        });
    }
    loop {
        let current: Option<(String, String, String, bool, Vec<u8>)> = conn
            .query_row(
                "SELECT sent_to_urls, ambiguous_urls, attempting_urls, confirmed, nullifier
             FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id
               AND share_index = :share_index",
                named_params! {
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to read helper attempt state: {e}"),
            })?;
        let Some((sent_json, ambiguous_json, attempting_json, confirmed, nullifier)) = current
        else {
            return Ok(ShareAttemptReservation::StaleGeneration);
        };
        if expected_nullifier.is_some_and(|expected| expected != nullifier) {
            return Ok(ShareAttemptReservation::StaleGeneration);
        }
        ensure_share_matches_ballot_intent(conn, round_id, wallet_id, bundle_index, proposal_id)?;
        let (definitely_accepted_urls, _) =
            partition_stored_helper_urls(&parse_url_list(&sent_json, "sent_to_urls")?);
        let (outcome_unknown_urls, _) =
            partition_stored_helper_urls(&parse_url_list(&ambiguous_json, "ambiguous_urls")?);
        let (in_flight_urls, preserved_legacy_in_flight_urls) =
            partition_stored_helper_urls(&parse_url_list(&attempting_json, "attempting_urls")?);
        let mut state = ShareDeliveryState::from_url_lists(
            &definitely_accepted_urls,
            &outcome_unknown_urls,
            &in_flight_urls,
        )?;
        if confirmed
            || state.accepted_urls().contains(&server_url)
            || state.outcome_unknown_urls().contains(&server_url)
            || state.in_flight_urls().contains(&server_url)
        {
            return Ok(ShareAttemptReservation::AlreadyRecorded);
        }
        let reserved_placements = state
            .accepted_urls()
            .iter()
            .chain(state.in_flight_urls())
            .filter(|url| placement_server_urls.contains(url))
            .count();
        let placement_capacity_reached = match capacity_policy {
            ShareAttemptCapacityPolicy::EnforcePlacementTarget => {
                reserved_placements >= target_count
            }
            ShareAttemptCapacityPolicy::AllowRecoveryBeyondPlacementTarget => false,
        };
        if placement_capacity_reached {
            return Ok(ShareAttemptReservation::PlacementCapacityReached);
        }
        debug_assert!(state.begin(&server_url)?);
        let updated_attempting_json = serialize_url_list(
            state.in_flight_urls(),
            &preserved_legacy_in_flight_urls,
            "attempting_urls",
        )?;
        let updated = conn
            .execute(
                "UPDATE share_delegations SET attempting_urls = :updated_attempting_urls
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id
                   AND share_index = :share_index
                   AND confirmed = 0
                   AND nullifier = :observed_nullifier
                   AND sent_to_urls = :observed_sent_to_urls
                   AND ambiguous_urls = :observed_ambiguous_urls
                   AND attempting_urls = :observed_attempting_urls",
                named_params! {
                    ":updated_attempting_urls": updated_attempting_json,
                    ":observed_nullifier": nullifier,
                    ":observed_sent_to_urls": sent_json,
                    ":observed_ambiguous_urls": ambiguous_json,
                    ":observed_attempting_urls": attempting_json,
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
            )
            .map_err(|e| VotingError::Internal {
                message: format!("failed to record helper attempt: {e}"),
            })?;
        if updated == 1 {
            return Ok(ShareAttemptReservation::Started);
        }
        // A separate connection changed the delivery state after our read.
        // Reload and merge its stronger evidence instead of overwriting it.
    }
}

/// Clears an attempt with a definite non-acceptance so the helper remains
/// eligible for a later retry.
pub fn remove_attempting_server(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    server_url: &str,
) -> Result<(), VotingError> {
    if remove_attempting_server_for_generation(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        server_url,
        None,
    )? {
        Ok(())
    } else {
        Err(missing_share_error(
            round_id,
            bundle_index,
            proposal_id,
            share_index,
        ))
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn remove_attempting_server_for_generation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    server_url: &str,
    expected_nullifier: Option<&[u8]>,
) -> Result<bool, VotingError> {
    loop {
        let current: Option<(String, String, String, Vec<u8>)> = conn
            .query_row(
                "SELECT sent_to_urls, ambiguous_urls, attempting_urls, nullifier
             FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id
               AND share_index = :share_index",
                named_params! {
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!(
                    "failed to read helper delivery state before clearing attempt: {e}"
                ),
            })?;
        let Some((sent_json, ambiguous_json, attempting_json, nullifier)) = current else {
            return Ok(false);
        };
        if expected_nullifier.is_some_and(|expected| expected != nullifier) {
            return Ok(false);
        }
        ensure_share_matches_ballot_intent(conn, round_id, wallet_id, bundle_index, proposal_id)?;
        let stored_in_flight_urls: Vec<String> =
            serde_json::from_str(&attempting_json).map_err(|e| VotingError::Internal {
                message: format!("failed to deserialize attempting_urls: {e}"),
            })?;
        let (in_flight_urls, preserved_legacy_in_flight_urls) =
            partition_stored_helper_urls(&stored_in_flight_urls);
        let mut state = ShareDeliveryState::from_url_lists(&[], &[], &in_flight_urls)?;
        state.mark_definite_failure(server_url)?;
        let updated_attempting_json = serialize_url_list(
            state.in_flight_urls(),
            &preserved_legacy_in_flight_urls,
            "attempting_urls",
        )?;
        let updated = conn
            .execute(
                "UPDATE share_delegations SET attempting_urls = :updated_attempting_urls
         WHERE round_id = :round_id AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index AND proposal_id = :proposal_id
           AND share_index = :share_index
           AND nullifier = :observed_nullifier
           AND sent_to_urls = :observed_sent_to_urls
           AND ambiguous_urls = :observed_ambiguous_urls
           AND attempting_urls = :observed_attempting_urls",
                named_params! {
                    ":updated_attempting_urls": updated_attempting_json,
                    ":observed_nullifier": nullifier,
                    ":observed_sent_to_urls": sent_json,
                    ":observed_ambiguous_urls": ambiguous_json,
                    ":observed_attempting_urls": attempting_json,
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
            )
            .map_err(|e| VotingError::Internal {
                message: format!("failed to clear helper attempt: {e}"),
            })?;
        if updated == 1 {
            return Ok(true);
        }
        // A separate connection changed the delivery state after our read.
        // Retry against that stronger state instead of restoring stale lists.
    }
}

/// Creates or strengthens durable delivery evidence for one committed share.
///
/// This raw SQL helper is crate-internal because callers must provide a
/// nullifier that matches the persisted vote recovery bundle. Wallet
/// integrations should use `CommittedVote::submit_share_to_helpers`, which
/// derives that nullifier and owns journal-before-dispatch ordering.
///
/// All reported helper URLs must canonicalize. Existing evidence is merged
/// with definite acceptance taking precedence over outcome-unknown or
/// in-flight state; a conflicting nullifier leaves the row unchanged.
/// Returns the effective durable `submit_at`, which is write-once on conflict.
pub(crate) fn record_share_delegation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    ambiguous_urls: &[String],
    target_count: u32,
    nullifier: &[u8],
    submit_at: u64,
) -> Result<u64, VotingError> {
    record_share_delegation_inner(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        ambiguous_urls,
        target_count,
        nullifier,
        submit_at,
        &mut || {},
    )
}

/// Records delivery only while the owning vote still has the expected
/// commitment-bundle generation.
///
/// An immediate transaction acquires SQLite's write lock before the generation
/// is read. That lock is held through the share write, so another connection
/// cannot replace the vote between validation and delivery-row persistence.
#[allow(clippy::too_many_arguments)]
pub(crate) fn record_share_delegation_for_vote_generation(
    conn: &mut Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    ambiguous_urls: &[String],
    target_count: u32,
    nullifier: &[u8],
    submit_at: u64,
    expected_commitment_bundle_json: &str,
) -> Result<u64, VotingError> {
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("failed to lock committed vote for helper delivery: {e}"),
        })?;
    let current_commitment_bundle_json: Option<String> = tx
        .query_row(
            "SELECT commitment_bundle_json FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index,
                ":proposal_id": proposal_id,
            },
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read committed vote for helper delivery: {e}"),
        })?;
    if current_commitment_bundle_json.as_deref() != Some(expected_commitment_bundle_json) {
        return Err(VotingError::InvalidInput {
            message: format!(
                "committed vote changed before helper share delivery for round={round_id}, wallet={wallet_id}, bundle={bundle_index}, proposal={proposal_id}"
            ),
        });
    }

    let submit_at = record_share_delegation_inner(
        &tx,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        ambiguous_urls,
        target_count,
        nullifier,
        submit_at,
        &mut || {},
    )?;
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("failed to commit helper-share generation transaction: {e}"),
    })?;
    Ok(submit_at)
}

#[cfg(test)]
#[allow(clippy::too_many_arguments)]
pub(crate) fn record_share_delegation_with_after_read(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    ambiguous_urls: &[String],
    target_count: u32,
    nullifier: &[u8],
    submit_at: u64,
    after_read: &mut dyn FnMut(),
) -> Result<u64, VotingError> {
    record_share_delegation_inner(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        ambiguous_urls,
        target_count,
        nullifier,
        submit_at,
        after_read,
    )
}

#[allow(clippy::too_many_arguments)]
fn record_share_delegation_inner(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    ambiguous_urls: &[String],
    target_count: u32,
    nullifier: &[u8],
    submit_at: u64,
    after_read: &mut dyn FnMut(),
) -> Result<u64, VotingError> {
    ensure_share_matches_ballot_intent(conn, round_id, wallet_id, bundle_index, proposal_id)?;
    loop {
        let existing: Option<(String, String, String, u32, Vec<u8>)> = conn
            .query_row(
                "SELECT sent_to_urls, ambiguous_urls, attempting_urls, target_count, nullifier
             FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id
               AND share_index = :share_index",
                named_params! {
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to read existing share delivery: {e}"),
            })?;
        after_read();

        let Some((sent_json, ambiguous_json, attempting_json, existing_target, existing_nullifier)) =
            existing
        else {
            let state = ShareDeliveryState::from_url_lists(sent_to_urls, ambiguous_urls, &[])?;
            let definite_acceptance_json =
                serialize_url_list(state.accepted_urls(), &[], "sent_to_urls")?;
            let ambiguous_json =
                serialize_url_list(state.outcome_unknown_urls(), &[], "ambiguous_urls")?;
            let attempting_json = serialize_url_list(&[], &[], "attempting_urls")?;
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            let inserted_submit_at = conn
                .query_row(
                    "INSERT INTO share_delegations \
                     (round_id, wallet_id, bundle_index, proposal_id, share_index, sent_to_urls, ambiguous_urls, attempting_urls, target_count, nullifier, confirmed, submit_at, created_at) \
                     VALUES (:round_id, :wallet_id, :bundle_index, :proposal_id, :share_index, :sent_to_urls, :ambiguous_urls, :attempting_urls, :target_count, :nullifier, 0, :submit_at, :created_at) \
                     ON CONFLICT (round_id, wallet_id, bundle_index, proposal_id, share_index) DO NOTHING \
                     RETURNING submit_at",
                    named_params! {
                        ":round_id": round_id,
                        ":wallet_id": wallet_id,
                        ":bundle_index": bundle_index,
                        ":proposal_id": proposal_id,
                        ":share_index": share_index,
                        ":sent_to_urls": definite_acceptance_json,
                        ":ambiguous_urls": ambiguous_json,
                        ":attempting_urls": attempting_json,
                        ":target_count": target_count,
                        ":nullifier": nullifier,
                        ":submit_at": submit_at,
                        ":created_at": now,
                    },
                    |row| row.get(0),
                )
                .optional()
                .map_err(|e| VotingError::Internal {
                    message: format!("failed to record share delegation: {e}"),
                })?;
            if let Some(inserted_submit_at) = inserted_submit_at {
                return Ok(inserted_submit_at);
            }
            // Another connection inserted the row after our read. Reload it
            // and apply the normal merge and nullifier checks.
            continue;
        };
        if existing_nullifier != nullifier {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "share nullifier conflict for round={round_id}, wallet={wallet_id}, bundle={bundle_index}, proposal={proposal_id}, share={share_index}"
                ),
            });
        }
        let (definite_acceptance_urls, preserved_legacy_definite_acceptance_urls) =
            partition_stored_helper_urls(&parse_url_list(&sent_json, "sent_to_urls")?);
        let (outcome_unknown_urls, mut preserved_legacy_outcome_unknown_urls) =
            partition_stored_helper_urls(&parse_url_list(&ambiguous_json, "ambiguous_urls")?);
        let (in_flight_urls, mut preserved_legacy_in_flight_urls) =
            partition_stored_helper_urls(&parse_url_list(&attempting_json, "attempting_urls")?);
        let mut state = ShareDeliveryState::from_url_lists(
            &definite_acceptance_urls,
            &outcome_unknown_urls,
            &in_flight_urls,
        )?;
        state.merge_persisted_report(sent_to_urls, ambiguous_urls)?;
        preserved_legacy_outcome_unknown_urls
            .retain(|url| !preserved_legacy_definite_acceptance_urls.contains(url));
        preserved_legacy_in_flight_urls.retain(|url| {
            !preserved_legacy_definite_acceptance_urls.contains(url)
                && !preserved_legacy_outcome_unknown_urls.contains(url)
        });

        let updated_sent = serialize_url_list(
            state.accepted_urls(),
            &preserved_legacy_definite_acceptance_urls,
            "sent_to_urls",
        )?;
        let updated_ambiguous = serialize_url_list(
            state.outcome_unknown_urls(),
            &preserved_legacy_outcome_unknown_urls,
            "ambiguous_urls",
        )?;
        let updated_attempting = serialize_url_list(
            state.in_flight_urls(),
            &preserved_legacy_in_flight_urls,
            "attempting_urls",
        )?;
        let effective_target = existing_target.max(target_count);
        let effective_submit_at = conn
            .query_row(
                "UPDATE share_delegations \
                 SET sent_to_urls = :sent_to_urls, ambiguous_urls = :ambiguous_urls, \
                     attempting_urls = :attempting_urls, target_count = :target_count \
                 WHERE round_id = :round_id AND wallet_id = :wallet_id \
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id \
                   AND share_index = :share_index \
                   AND nullifier = :observed_nullifier \
                   AND sent_to_urls = :observed_sent_to_urls \
                   AND ambiguous_urls = :observed_ambiguous_urls \
                   AND attempting_urls = :observed_attempting_urls \
                   AND target_count = :observed_target_count \
                 RETURNING submit_at",
                named_params! {
                    ":sent_to_urls": updated_sent,
                    ":ambiguous_urls": updated_ambiguous,
                    ":attempting_urls": updated_attempting,
                    ":target_count": effective_target,
                    ":observed_nullifier": existing_nullifier,
                    ":observed_sent_to_urls": sent_json,
                    ":observed_ambiguous_urls": ambiguous_json,
                    ":observed_attempting_urls": attempting_json,
                    ":observed_target_count": existing_target,
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to record share delegation: {e}"),
            })?;
        if let Some(effective_submit_at) = effective_submit_at {
            return Ok(effective_submit_at);
        }
        // A separate connection strengthened the row after our read. Reload
        // and merge that evidence instead of overwriting it.
    }
}

/// Load all share delegations for a round.
pub fn get_share_delegations(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    load_share_delegations(
        conn,
        "SELECT bundle_index, proposal_id, share_index, sent_to_urls, ambiguous_urls, attempting_urls, target_count, nullifier, confirmed, submit_at, created_at, round_id \
         FROM share_delegations WHERE round_id = :round_id AND wallet_id = :wallet_id \
         ORDER BY proposal_id, share_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
}

/// Load one share delegation by its complete durable key.
#[allow(clippy::too_many_arguments)]
pub fn get_share_delegation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<Option<ShareDelegationRecord>, VotingError> {
    let mut shares = load_share_delegations(
        conn,
        "SELECT bundle_index, proposal_id, share_index, sent_to_urls, ambiguous_urls, attempting_urls, target_count, nullifier, confirmed, submit_at, created_at, round_id \
         FROM share_delegations \
         WHERE round_id = :round_id AND wallet_id = :wallet_id \
           AND bundle_index = :bundle_index AND proposal_id = :proposal_id \
           AND share_index = :share_index",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index,
            ":proposal_id": proposal_id,
            ":share_index": share_index,
        },
    )?;
    Ok(shares.pop())
}

/// Load only unconfirmed share delegations for a round.
pub fn get_unconfirmed_delegations(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    load_share_delegations(
        conn,
        "SELECT bundle_index, proposal_id, share_index, sent_to_urls, ambiguous_urls, attempting_urls, target_count, nullifier, confirmed, submit_at, created_at, round_id \
         FROM share_delegations WHERE round_id = :round_id AND wallet_id = :wallet_id AND confirmed = 0 \
         ORDER BY proposal_id, share_index",
        named_params! { ":round_id": round_id, ":wallet_id": wallet_id },
    )
}

/// Load each round with at least one unconfirmed helper share once.
pub fn pending_share_rounds(
    conn: &Connection,
    wallet_id: &str,
) -> Result<Vec<(String, Option<String>)>, VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT rounds.round_id, rounds.session_json
             FROM rounds
             WHERE rounds.wallet_id = :wallet_id
               AND EXISTS (
                   SELECT 1
                   FROM share_delegations
                   WHERE share_delegations.round_id = rounds.round_id
                     AND share_delegations.wallet_id = rounds.wallet_id
                     AND share_delegations.confirmed = 0
               )
             ORDER BY rounds.created_at DESC, rounds.round_id",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to prepare pending share round query: {e}"),
        })?;
    let pending_round_rows = stmt
        .query_map(named_params! { ":wallet_id": wallet_id }, |row| {
            Ok((row.get(0)?, row.get(1)?))
        })
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query pending share rounds: {e}"),
        })?;

    pending_round_rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read pending share round row: {e}"),
        })
}

fn load_share_delegations<P: rusqlite::Params>(
    conn: &Connection,
    sql: &str,
    params: P,
) -> Result<Vec<ShareDelegationRecord>, VotingError> {
    let mut stmt = conn.prepare(sql).map_err(|e| VotingError::Internal {
        message: format!("failed to prepare share delegation query: {}", e),
    })?;
    let share_delegation_rows = stmt
        .query_map(params, |row| {
            let definite_acceptance_json: String = row.get(3)?;
            let outcome_unknown_json: String = row.get(4)?;
            let in_flight_json: String = row.get(5)?;
            let target_count: u32 = row.get(6)?;
            let nullifier_blob: Vec<u8> = row.get(7)?;
            let confirmed_int: i32 = row.get(8)?;
            let persisted_round_id: String = row.get(11)?;
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, u32>(2)?,
                definite_acceptance_json,
                outcome_unknown_json,
                in_flight_json,
                target_count,
                nullifier_blob,
                confirmed_int != 0,
                row.get::<_, u64>(9)?,
                row.get::<_, u64>(10)?,
                persisted_round_id,
            ))
        })
        .map_err(|e| VotingError::Internal {
            message: format!("failed to query share delegations: {}", e),
        })?;

    let mut share_delegations = Vec::new();
    for share_delegation_row in share_delegation_rows {
        let (
            bundle_index,
            proposal_id,
            share_index,
            definite_acceptance_json,
            outcome_unknown_json,
            in_flight_json,
            target_count,
            nullifier,
            confirmed,
            submit_at,
            created_at,
            persisted_round_id,
        ) = share_delegation_row.map_err(|e| VotingError::Internal {
            message: format!("failed to read share delegation row: {}", e),
        })?;
        let sent_to_urls: Vec<String> =
            serde_json::from_str(&definite_acceptance_json).map_err(|e| VotingError::Internal {
                message: format!("failed to deserialize sent_to_urls: {}", e),
            })?;
        let ambiguous_urls: Vec<String> =
            serde_json::from_str(&outcome_unknown_json).map_err(|e| VotingError::Internal {
                message: format!("failed to deserialize ambiguous_urls: {}", e),
            })?;
        let attempting_urls: Vec<String> =
            serde_json::from_str(&in_flight_json).map_err(|e| VotingError::Internal {
                message: format!("failed to deserialize attempting_urls: {e}"),
            })?;
        let sent_to_urls = partition_stored_helper_urls(&sent_to_urls).0;
        let ambiguous_urls = partition_stored_helper_urls(&ambiguous_urls).0;
        let attempting_urls = partition_stored_helper_urls(&attempting_urls).0;
        let state =
            ShareDeliveryState::from_url_lists(&sent_to_urls, &ambiguous_urls, &attempting_urls)?;
        share_delegations.push(ShareDelegationRecord {
            round_id: persisted_round_id,
            bundle_index,
            proposal_id,
            share_index,
            sent_to_urls: state.accepted_urls().to_vec(),
            ambiguous_urls: state.outcome_unknown_urls().to_vec(),
            attempting_urls: state.in_flight_urls().to_vec(),
            target_count,
            nullifier,
            confirmed,
            submit_at,
            created_at,
        });
    }
    Ok(share_delegations)
}

/// Read the durable confirmation bit for one helper-share record.
pub fn share_is_confirmed(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<bool, VotingError> {
    share_is_confirmed_for_generation(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        None,
    )?
    .ok_or_else(|| missing_share_error(round_id, bundle_index, proposal_id, share_index))
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn share_is_confirmed_for_generation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    expected_nullifier: Option<&[u8]>,
) -> Result<Option<bool>, VotingError> {
    let current: Option<(bool, Vec<u8>)> = conn
        .query_row(
            "SELECT confirmed, nullifier FROM share_delegations
         WHERE round_id = :round_id AND wallet_id = :wallet_id
           AND bundle_index = :bundle_index AND proposal_id = :proposal_id
           AND share_index = :share_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index,
                ":proposal_id": proposal_id,
                ":share_index": share_index,
            },
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read helper-share confirmation: {e}"),
        })?;
    let Some((confirmed, nullifier)) = current else {
        return Ok(None);
    };
    if expected_nullifier.is_some_and(|expected| expected != nullifier) {
        return Ok(None);
    }
    ensure_share_matches_ballot_intent(conn, round_id, wallet_id, bundle_index, proposal_id)?;
    Ok(Some(confirmed))
}

/// Mark a share delegation as confirmed on-chain.
pub(crate) fn mark_share_confirmed(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    expected_nullifier: Option<&[u8]>,
) -> Result<bool, VotingError> {
    let current: Option<Vec<u8>> = conn
        .query_row(
            "SELECT nullifier FROM share_delegations
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id
               AND share_index = :share_index",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index,
                ":proposal_id": proposal_id,
                ":share_index": share_index,
            },
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("failed to read helper-share generation: {e}"),
        })?;
    let Some(nullifier) = current else {
        return Ok(false);
    };
    if expected_nullifier.is_some_and(|expected| expected != nullifier) {
        return Ok(false);
    }
    ensure_share_matches_ballot_intent(conn, round_id, wallet_id, bundle_index, proposal_id)?;
    let updated = conn
        .execute(
            "UPDATE share_delegations SET confirmed = 1 \
             WHERE round_id = :round_id AND wallet_id = :wallet_id \
             AND bundle_index = :bundle_index AND proposal_id = :proposal_id \
             AND share_index = :share_index AND nullifier = :expected_nullifier",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index,
                ":proposal_id": proposal_id,
                ":share_index": share_index,
                ":expected_nullifier": nullifier,
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("failed to mark share confirmed: {}", e),
        })?;
    Ok(updated == 1)
}

fn ensure_share_matches_ballot_intent(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<(), VotingError> {
    let intent = load_ballot_intent(conn, round_id, wallet_id, proposal_id, "share delegation")?;
    let Some((skipped, choice)) = intent else {
        return Ok(());
    };
    if skipped != 0 {
        return Err(VotingError::InvalidInput {
            message: format!(
                "cannot record share delegation for skipped proposal round={}, wallet={}, bundle={}, proposal={}",
                round_id, wallet_id, bundle_index, proposal_id
            ),
        });
    }
    let Some(choice) = choice else {
        return Err(VotingError::InvalidInput {
            message: format!(
                "ballot intent choice missing for round={}, wallet={}, proposal={}",
                round_id, wallet_id, proposal_id
            ),
        });
    };
    let vote_choice = load_vote_choice_for_intent_check(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        "share delegation",
    )?;
    if vote_choice == Some(choice) {
        return Ok(());
    }
    Err(VotingError::InvalidInput {
        message: format!(
            "share delegation conflicts with ballot intent for round={}, wallet={}, bundle={}, proposal={}",
            round_id, wallet_id, bundle_index, proposal_id
        ),
    })
}

/// Appends definite delivery evidence, supersedes weaker evidence for those
/// helpers, and makes the share immediately actionable.
#[allow(clippy::too_many_arguments)]
pub(crate) fn add_sent_servers_for_generation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
    expected_nullifier: Option<&[u8]>,
) -> Result<bool, VotingError> {
    update_sent_servers(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
        true,
        expected_nullifier,
    )
}

/// Append definite deliveries without changing their scheduled submit time.
pub fn add_sent_servers_preserving_schedule(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
) -> Result<(), VotingError> {
    if add_sent_servers_preserving_schedule_for_generation(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
        None,
    )? {
        Ok(())
    } else {
        Err(missing_share_error(
            round_id,
            bundle_index,
            proposal_id,
            share_index,
        ))
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn add_sent_servers_preserving_schedule_for_generation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
    expected_nullifier: Option<&[u8]>,
) -> Result<bool, VotingError> {
    update_sent_servers(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
        false,
        expected_nullifier,
    )
}

/// How [`merge_share_delegation_urls`] folds newly reported helpers into the
/// persisted delivery state.
enum HelperUrlMerge {
    /// Definite delivery evidence supersedes outcome-unknown state.
    DefiniteAcceptance,
    /// Outcome-unknown evidence cannot replace definite acceptance.
    OutcomeUnknown,
}

/// Shared read-modify-write for the per-share helper delivery lists. Every
/// merged helper also leaves `attempting_urls`, and legacy entries that no
/// longer canonicalize are preserved verbatim.
#[allow(clippy::too_many_arguments)]
fn merge_share_delegation_urls(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
    merge: HelperUrlMerge,
    reset_submit_at: bool,
    expected_nullifier: Option<&[u8]>,
) -> Result<bool, VotingError> {
    loop {
        let current: Option<(String, String, String, Vec<u8>)> = conn
            .query_row(
                "SELECT sent_to_urls, ambiguous_urls, attempting_urls, nullifier
             FROM share_delegations \
             WHERE round_id = :round_id AND wallet_id = :wallet_id \
             AND bundle_index = :bundle_index AND proposal_id = :proposal_id AND share_index = :share_index",
                named_params! {
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .optional()
            .map_err(|e| VotingError::Internal {
                message: format!("failed to read helper delivery state for update: {e}"),
            })?;
        let Some((sent_json, ambiguous_json, attempting_json, nullifier)) = current else {
            return Ok(false);
        };
        if expected_nullifier.is_some_and(|expected| expected != nullifier) {
            return Ok(false);
        }
        ensure_share_matches_ballot_intent(conn, round_id, wallet_id, bundle_index, proposal_id)?;
        let (definite_acceptance_urls, preserved_legacy_definite_acceptance_urls) =
            partition_stored_helper_urls(&parse_url_list(&sent_json, "sent_to_urls")?);
        let (outcome_unknown_urls, preserved_legacy_outcome_unknown_urls) =
            partition_stored_helper_urls(&parse_url_list(&ambiguous_json, "ambiguous_urls")?);
        let (in_flight_urls, preserved_legacy_in_flight_urls) =
            partition_stored_helper_urls(&parse_url_list(&attempting_json, "attempting_urls")?);
        let mut state = ShareDeliveryState::from_url_lists(
            &definite_acceptance_urls,
            &outcome_unknown_urls,
            &in_flight_urls,
        )?;
        for url in new_urls {
            match merge {
                HelperUrlMerge::DefiniteAcceptance => state.mark_accepted(url)?,
                HelperUrlMerge::OutcomeUnknown => state.mark_outcome_unknown(url)?,
            }
        }
        let updated_sent = serialize_url_list(
            state.accepted_urls(),
            &preserved_legacy_definite_acceptance_urls,
            "sent_to_urls",
        )?;
        let updated_ambiguous = serialize_url_list(
            state.outcome_unknown_urls(),
            &preserved_legacy_outcome_unknown_urls,
            "ambiguous_urls",
        )?;
        let updated_attempting = serialize_url_list(
            state.in_flight_urls(),
            &preserved_legacy_in_flight_urls,
            "attempting_urls",
        )?;
        let updated = conn
            .execute(
                "UPDATE share_delegations SET sent_to_urls = :sent_to_urls, ambiguous_urls = :ambiguous_urls, \
         attempting_urls = :attempting_urls, submit_at = iif(:reset_submit_at, 0, submit_at) \
         WHERE round_id = :round_id AND wallet_id = :wallet_id \
         AND bundle_index = :bundle_index AND proposal_id = :proposal_id AND share_index = :share_index \
         AND nullifier = :observed_nullifier \
         AND sent_to_urls = :observed_sent_to_urls \
         AND ambiguous_urls = :observed_ambiguous_urls \
         AND attempting_urls = :observed_attempting_urls",
                named_params! {
                    ":sent_to_urls": updated_sent,
                    ":ambiguous_urls": updated_ambiguous,
                    ":attempting_urls": updated_attempting,
                    ":reset_submit_at": reset_submit_at,
                    ":observed_nullifier": nullifier,
                    ":observed_sent_to_urls": sent_json,
                    ":observed_ambiguous_urls": ambiguous_json,
                    ":observed_attempting_urls": attempting_json,
                    ":round_id": round_id,
                    ":wallet_id": wallet_id,
                    ":bundle_index": bundle_index,
                    ":proposal_id": proposal_id,
                    ":share_index": share_index,
                },
            )
            .map_err(|e| VotingError::Internal {
                message: format!("failed to update helper delivery state: {e}"),
            })?;
        if updated == 1 {
            return Ok(true);
        }
        // A separate connection changed the delivery state after our read.
        // Reload and merge it instead of overwriting stronger evidence.
    }
}

#[allow(clippy::too_many_arguments)]
fn update_sent_servers(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
    reset_submit_at: bool,
    expected_nullifier: Option<&[u8]>,
) -> Result<bool, VotingError> {
    merge_share_delegation_urls(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
        HelperUrlMerge::DefiniteAcceptance,
        reset_submit_at,
        expected_nullifier,
    )
}

/// Append outcome-unknown helper attempts without overriding definite deliveries.
/// `reset_submit_at` makes overdue recovery immediately actionable; early
/// replenishment leaves the delayed schedule intact.
pub fn add_ambiguous_servers(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
    reset_submit_at: bool,
) -> Result<(), VotingError> {
    if add_ambiguous_servers_for_generation(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
        reset_submit_at,
        None,
    )? {
        Ok(())
    } else {
        Err(missing_share_error(
            round_id,
            bundle_index,
            proposal_id,
            share_index,
        ))
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn add_ambiguous_servers_for_generation(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
    reset_submit_at: bool,
    expected_nullifier: Option<&[u8]>,
) -> Result<bool, VotingError> {
    merge_share_delegation_urls(
        conn,
        round_id,
        wallet_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
        HelperUrlMerge::OutcomeUnknown,
        reset_submit_at,
        expected_nullifier,
    )
}

fn missing_share_error(
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> VotingError {
    VotingError::Internal {
        message: format!(
            "no share delegation found: round={round_id}, bundle={bundle_index}, proposal={proposal_id}, share={share_index}"
        ),
    }
}
