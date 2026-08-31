use std::collections::{BTreeMap, BTreeSet};

use rusqlite::{named_params, Connection, OptionalExtension, TransactionBehavior};

use crate::{
    helper::url::canonical_helper_url_list,
    round::VotingDb,
    session::{classify_ballot_intents, Decision},
    share::ShareOperationScope,
    share_policy::{
        plan_share_submissions_with_preferred_servers, round_immediate_share_key,
        share_submission_random_bytes_required, share_submission_target_count, ImmediateShareKey,
        ShareSubmissionPlan, SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER,
        VOTE_COMMITMENT_SHARE_COUNT,
    },
    types::{SharePayload, VotingError},
};

use super::{
    os_random_bytes, ShareDeliveryPlan, ShareDeliveryPlanningParams, SharePlacementGuarantee,
};

const PLAN_FORMAT_VERSION: u32 = 1;

#[allow(clippy::too_many_arguments)]
pub(crate) fn prepare_share_delivery_plan(
    db: &VotingDb,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    expected_commitment_bundle_json: &str,
    payloads: &[SharePayload],
    params: ShareDeliveryPlanningParams<'_>,
) -> Result<ShareDeliveryPlan, VotingError> {
    let wallet_id = db.wallet_id();
    let mut conn = db.conn();
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| VotingError::Internal {
            message: format!("begin helper-share plan transaction failed: {e}"),
        })?;
    let commitment_bundle_json: String = tx
        .query_row(
            "SELECT commitment_bundle_json FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("load committed vote for helper-share planning failed: {e}"),
        })?
        .flatten()
        .ok_or_else(|| VotingError::InvalidInput {
            message: "committed vote is missing durable helper recovery material".to_string(),
        })?;
    if commitment_bundle_json != expected_commitment_bundle_json {
        return Err(VotingError::InvalidInput {
            message: "committed vote changed before helper-share planning; recover the current committed vote"
                .to_string(),
        });
    }

    let (immediate_key, immediate_position) = derive_immediate_share(
        &tx,
        round_id,
        &wallet_id,
        bundle_index,
        proposal_id,
        params.proposal_ids,
        payloads,
    )?;
    validate_round_immediate_plans(&tx, round_id, &wallet_id, immediate_key)?;

    if let Some(existing) = load_plan_with_conn(
        &tx,
        round_id,
        &wallet_id,
        bundle_index,
        proposal_id,
        &commitment_bundle_json,
    )? {
        validate_share_delivery_plan(
            &existing,
            params.fleet.configured_server_urls(),
            payloads.len(),
        )?;
        validate_immediate_plan(&existing, immediate_position)?;
        tx.commit().map_err(|e| VotingError::Internal {
            message: format!("commit helper-share plan read transaction failed: {e}"),
        })?;
        return Ok(existing);
    }

    let required = share_submission_random_bytes_required(
        payloads.len(),
        params.fleet.ranked_server_urls().len(),
        params.now_seconds,
        params.vote_end_time_seconds,
        params.last_moment_buffer_seconds,
        payloads.len() == 1,
    );
    let submit_at_random_bytes = os_random_bytes(required.submit_at_random_bytes);
    let server_random_bytes = os_random_bytes(required.server_random_bytes);
    let planned = plan_share_submissions_with_preferred_servers(
        payloads.len(),
        params.fleet.ranked_server_urls(),
        params.fleet.ready_server_count(),
        params.now_seconds,
        params.vote_end_time_seconds,
        params.last_moment_buffer_seconds,
        payloads.len() == 1,
        immediate_position,
        &submit_at_random_bytes,
        &server_random_bytes,
    )?;

    let has_legacy_rows: bool = tx
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM share_delegations
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                   AND bundle_index = :bundle_index AND proposal_id = :proposal_id
             )",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| row.get(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("inspect legacy helper-share delivery failed: {e}"),
        })?;
    let plan = ShareDeliveryPlan {
        configured_server_urls: params.fleet.configured_server_urls().to_vec(),
        share_plans: planned,
        placement_guarantee: if has_legacy_rows {
            SharePlacementGuarantee::LegacyBestEffort
        } else {
            SharePlacementGuarantee::Strict
        },
    };
    validate_share_delivery_plan(&plan, params.fleet.configured_server_urls(), payloads.len())?;
    let fleet_json =
        serde_json::to_string(&plan.configured_server_urls).map_err(|e| VotingError::Internal {
            message: format!("serialize helper-share planning fleet failed: {e}"),
        })?;
    let plans_json =
        serde_json::to_string(&plan.share_plans).map_err(|e| VotingError::Internal {
            message: format!("serialize helper-share plan failed: {e}"),
        })?;
    tx.execute(
        "INSERT OR IGNORE INTO helper_share_plans
         (round_id, wallet_id, bundle_index, proposal_id, commitment_bundle_json,
          configured_server_urls_json, share_plans_json, format_version,
          placement_guarantee, created_at)
         VALUES (:round_id, :wallet_id, :bundle_index, :proposal_id,
                 :commitment_bundle_json, :fleet_json, :plans_json, :format_version,
                 :placement_guarantee, strftime('%s','now'))",
        named_params! {
            ":round_id": round_id,
            ":wallet_id": wallet_id,
            ":bundle_index": bundle_index as i64,
            ":proposal_id": proposal_id as i64,
            ":commitment_bundle_json": commitment_bundle_json,
            ":fleet_json": fleet_json,
            ":plans_json": plans_json,
            ":format_version": PLAN_FORMAT_VERSION as i64,
            ":placement_guarantee": guarantee_name(plan.placement_guarantee),
        },
    )
    .map_err(|e| VotingError::Internal {
        message: format!("persist helper-share plan failed: {e}"),
    })?;
    let persisted = load_plan_with_conn(
        &tx,
        round_id,
        &wallet_id,
        bundle_index,
        proposal_id,
        &commitment_bundle_json,
    )?
    .ok_or_else(|| VotingError::Internal {
        message: "newly persisted helper-share plan was not found".to_string(),
    })?;
    validate_share_delivery_plan(
        &persisted,
        params.fleet.configured_server_urls(),
        payloads.len(),
    )?;
    validate_immediate_plan(&persisted, immediate_position)?;
    validate_round_immediate_plans(&tx, round_id, &wallet_id, immediate_key)?;
    tx.commit().map_err(|e| VotingError::Internal {
        message: format!("commit helper-share plan transaction failed: {e}"),
    })?;
    Ok(persisted)
}

#[allow(clippy::too_many_arguments)]
fn derive_immediate_share(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    proposal_ids: &[u32],
    payloads: &[SharePayload],
) -> Result<(Option<ImmediateShareKey>, Option<u32>), VotingError> {
    if proposal_ids.is_empty() {
        return Err(VotingError::InvalidInput {
            message: "helper-share planning requires the round's complete proposal roster"
                .to_string(),
        });
    }

    let intents = load_ballot_intents_with_conn(conn, round_id, wallet_id)?;
    let classification = classify_ballot_intents(proposal_ids, &intents)?;
    if !classification.open_proposals.is_empty() {
        return Err(VotingError::InvalidInput {
            message: format!(
                "helper-share planning requires terminal decisions for proposals {:?}",
                classification.open_proposals
            ),
        });
    }
    let durable_roster = intents.keys().copied().collect::<BTreeSet<_>>();
    if classification.roster != durable_roster {
        return Err(VotingError::InvalidInput {
            message: "proposal roster does not exactly match the round's durable ballot intents"
                .to_string(),
        });
    }
    if !matches!(intents.get(&proposal_id), Some(Decision::Choice(_))) {
        return Err(VotingError::InvalidInput {
            message: format!(
                "committed proposal {proposal_id} is not a chosen member of the round roster"
            ),
        });
    }

    let immediate_key =
        immediate_key_for_choices(conn, round_id, wallet_id, &classification.choice_proposals)?;
    let immediate_position =
        immediate_position_for_commitment(immediate_key, bundle_index, proposal_id, payloads)?;

    Ok((immediate_key, immediate_position))
}

fn immediate_key_for_choices(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    choice_proposals: &[u32],
) -> Result<Option<ImmediateShareKey>, VotingError> {
    let highest_bundle_index = conn
        .query_row(
            "SELECT MAX(bundle_index) FROM bundles
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
            },
            |row| row.get::<_, Option<i64>>(0),
        )
        .map_err(|e| VotingError::Internal {
            message: format!("derive immediate helper share from bundle roster failed: {e}"),
        })?
        .map(|index| index as u32);
    Ok(round_immediate_share_key(
        highest_bundle_index,
        choice_proposals,
    ))
}

fn immediate_position_for_commitment(
    immediate_key: Option<ImmediateShareKey>,
    bundle_index: u32,
    proposal_id: u32,
    payloads: &[SharePayload],
) -> Result<Option<u32>, VotingError> {
    match immediate_key {
        Some(key) if key.bundle_index == bundle_index && key.proposal_id == proposal_id => {
            Ok(Some(
                payloads
                    .iter()
                    .position(|payload| payload.enc_share.share_index == key.share_index)
                    .ok_or_else(|| VotingError::InvalidInput {
                        message: format!(
                            "derived immediate share index {} is not present in the committed vote",
                            key.share_index
                        ),
                    })?
                    .try_into()
                    .map_err(|_| VotingError::InvalidInput {
                        message: "immediate share position exceeds u32".to_string(),
                    })?,
            ))
        }
        _ => Ok(None),
    }
}

fn load_ballot_intents_with_conn(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
) -> Result<BTreeMap<u32, Decision>, VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT proposal_id, skipped, choice FROM ballot_intent
             WHERE round_id = :round_id AND wallet_id = :wallet_id
             ORDER BY proposal_id",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("prepare helper-share ballot intents failed: {e}"),
        })?;
    let rows = stmt
        .query_map(
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
            },
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, Option<i64>>(2)?,
                ))
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("query helper-share ballot intents failed: {e}"),
        })?;

    let mut intents = BTreeMap::new();
    for row in rows {
        let (proposal_id, skipped, choice) = row.map_err(|e| VotingError::Internal {
            message: format!("read helper-share ballot intent failed: {e}"),
        })?;
        let decision = if skipped != 0 {
            Decision::Skipped
        } else {
            Decision::Choice(choice.ok_or_else(|| VotingError::Internal {
                message: format!(
                    "chosen proposal {proposal_id} is missing its durable ballot choice"
                ),
            })? as u32)
        };
        intents.insert(proposal_id as u32, decision);
    }
    Ok(intents)
}

fn validate_round_immediate_plans(
    conn: &Connection,
    round_id: &str,
    wallet_id: &str,
    expected: Option<ImmediateShareKey>,
) -> Result<(), VotingError> {
    let mut stmt = conn
        .prepare(
            "SELECT bundle_index, proposal_id, share_plans_json
             FROM helper_share_plans
             WHERE round_id = :round_id AND wallet_id = :wallet_id",
        )
        .map_err(|e| VotingError::Internal {
            message: format!("prepare round helper-share plans failed: {e}"),
        })?;
    let rows = stmt
        .query_map(
            named_params! {
                ":round_id": round_id,
                ":wallet_id": wallet_id,
            },
            |row| {
                Ok((
                    row.get::<_, i64>(0)? as u32,
                    row.get::<_, i64>(1)? as u32,
                    row.get::<_, String>(2)?,
                ))
            },
        )
        .map_err(|e| VotingError::Internal {
            message: format!("query round helper-share plans failed: {e}"),
        })?;

    let mut marked = Vec::new();
    let mut expected_plan_present = false;
    for row in rows {
        let (bundle_index, proposal_id, plans_json) = row.map_err(|e| VotingError::Internal {
            message: format!("read round helper-share plan failed: {e}"),
        })?;
        let plans: Vec<ShareSubmissionPlan> =
            serde_json::from_str(&plans_json).map_err(|e| VotingError::InvalidInput {
                message: format!("persisted helper-share plan is invalid JSON: {e}"),
            })?;
        expected_plan_present |= expected
            .is_some_and(|key| key.bundle_index == bundle_index && key.proposal_id == proposal_id);
        marked.extend(
            plans
                .iter()
                .enumerate()
                .filter(|(_, plan)| plan.immediate)
                .map(|(share_index, _)| ImmediateShareKey {
                    bundle_index,
                    proposal_id,
                    share_index: share_index as u32,
                }),
        );
    }

    if marked.len() > 1 {
        return Err(VotingError::InvalidInput {
            message: "persisted helper-share plans designate more than one round-immediate share"
                .to_string(),
        });
    }
    let actual = marked.first().copied();
    if actual.is_some_and(|actual| Some(actual) != expected)
        || (expected_plan_present && actual != expected)
    {
        return Err(VotingError::InvalidInput {
            message: "persisted round-immediate helper share does not match durable ballot intent"
                .to_string(),
        });
    }
    Ok(())
}

pub(crate) fn load_share_delivery_plan(
    db: &VotingDb,
    scope: &ShareOperationScope,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    handle_commitment_bundle_json: &str,
    current_fleet: &[String],
    payloads: &[SharePayload],
) -> Result<(ShareDeliveryPlan, String), VotingError> {
    let conn = db.conn();
    let commitment_bundle_json: String = conn
        .query_row(
            "SELECT commitment_bundle_json FROM votes
             WHERE round_id = :round_id AND wallet_id = :wallet_id
               AND bundle_index = :bundle_index AND proposal_id = :proposal_id",
            named_params! {
                ":round_id": round_id,
                ":wallet_id": scope.wallet_id(),
                ":bundle_index": bundle_index as i64,
                ":proposal_id": proposal_id as i64,
            },
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("load committed vote for helper-share submission failed: {e}"),
        })?
        .flatten()
        .ok_or_else(|| VotingError::InvalidInput {
            message: "committed vote is missing durable helper recovery material".to_string(),
        })?;
    validate_handle_generation(handle_commitment_bundle_json, &commitment_bundle_json)?;
    let plan = load_plan_with_conn(
        &conn,
        round_id,
        scope.wallet_id(),
        bundle_index,
        proposal_id,
        &commitment_bundle_json,
    )?
    .ok_or_else(|| VotingError::InvalidInput {
        message: "helper-share delivery must be prepared before submission".to_string(),
    })?;
    validate_share_delivery_plan(&plan, current_fleet, payloads.len())?;
    let intents = load_ballot_intents_with_conn(&conn, round_id, scope.wallet_id())?;
    if !matches!(intents.get(&proposal_id), Some(Decision::Choice(_))) {
        return Err(VotingError::InvalidInput {
            message: format!(
                "committed proposal {proposal_id} is no longer a chosen member of the round"
            ),
        });
    }
    let choice_proposals = intents
        .iter()
        .filter_map(|(&proposal_id, decision)| {
            matches!(decision, Decision::Choice(_)).then_some(proposal_id)
        })
        .collect::<Vec<_>>();
    let immediate_key =
        immediate_key_for_choices(&conn, round_id, scope.wallet_id(), &choice_proposals)?;
    validate_round_immediate_plans(&conn, round_id, scope.wallet_id(), immediate_key)?;
    let immediate_position =
        immediate_position_for_commitment(immediate_key, bundle_index, proposal_id, payloads)?;
    validate_immediate_plan(&plan, immediate_position)?;
    Ok((plan, commitment_bundle_json))
}

fn validate_handle_generation(
    handle_commitment_bundle_json: &str,
    current_commitment_bundle_json: &str,
) -> Result<(), VotingError> {
    if handle_commitment_bundle_json == current_commitment_bundle_json {
        return Ok(());
    }
    Err(stale_handle_error())
}

fn stale_handle_error() -> VotingError {
    VotingError::InvalidInput {
        message: "committed vote changed before helper-share submission; recover the current committed vote"
            .to_string(),
    }
}

fn load_plan_with_conn(
    conn: &rusqlite::Connection,
    round_id: &str,
    wallet_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    expected_commitment_bundle_json: &str,
) -> Result<Option<ShareDeliveryPlan>, VotingError> {
    let row = conn
        .query_row(
            "SELECT commitment_bundle_json, configured_server_urls_json,
                    share_plans_json, format_version, placement_guarantee
               FROM helper_share_plans
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
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, u32>(3)?,
                    row.get::<_, String>(4)?,
                ))
            },
        )
        .optional()
        .map_err(|e| VotingError::Internal {
            message: format!("load helper-share plan failed: {e}"),
        })?;
    let Some((generation, fleet_json, plans_json, format_version, guarantee)) = row else {
        return Ok(None);
    };
    if generation != expected_commitment_bundle_json {
        return Err(VotingError::InvalidInput {
            message: "persisted helper-share plan belongs to a different committed vote generation"
                .to_string(),
        });
    }
    if format_version != PLAN_FORMAT_VERSION {
        return Err(VotingError::Internal {
            message: format!("unsupported helper-share plan format version {format_version}"),
        });
    }
    let configured_server_urls =
        serde_json::from_str(&fleet_json).map_err(|e| VotingError::Internal {
            message: format!("decode persisted helper-share planning fleet failed: {e}"),
        })?;
    let share_plans = serde_json::from_str(&plans_json).map_err(|e| VotingError::Internal {
        message: format!("decode persisted helper-share plan failed: {e}"),
    })?;
    let placement_guarantee = match guarantee.as_str() {
        "strict" => SharePlacementGuarantee::Strict,
        "legacy_best_effort" => SharePlacementGuarantee::LegacyBestEffort,
        _ => {
            return Err(VotingError::Internal {
                message: format!("unknown helper-share placement guarantee {guarantee}"),
            })
        }
    };
    Ok(Some(ShareDeliveryPlan {
        configured_server_urls,
        share_plans,
        placement_guarantee,
    }))
}

pub(crate) fn validate_share_delivery_plan(
    plan: &ShareDeliveryPlan,
    configured_server_urls: &[String],
    share_count: usize,
) -> Result<Vec<String>, VotingError> {
    if plan.share_plans.len() != share_count {
        return Err(VotingError::InvalidInput {
            message: format!(
                "persisted helper-share plan count {} does not match committed share count {share_count}",
                plan.share_plans.len()
            ),
        });
    }
    let configured = canonical_helper_url_list(configured_server_urls)?;
    if configured.is_empty() || configured.len() != configured_server_urls.len() {
        return Err(VotingError::InvalidInput {
            message: "configured helper fleet must be nonempty and canonically distinct"
                .to_string(),
        });
    }
    let planned_fleet = canonical_helper_url_list(&plan.configured_server_urls)?;
    let same_fleet =
        BTreeSet::from_iter(planned_fleet.iter()) == BTreeSet::from_iter(configured.iter());
    if planned_fleet.len() != plan.configured_server_urls.len() || !same_fleet {
        return Err(VotingError::InvalidInput {
            message: "current helper fleet does not match the persisted helper-share plan"
                .to_string(),
        });
    }
    let expected_target = share_submission_target_count(configured.len());
    let mut assignments = BTreeMap::<String, usize>::new();
    for (share_index, share_plan) in plan.share_plans.iter().enumerate() {
        let targets = canonical_helper_url_list(&share_plan.target_servers)?;
        let target_count = usize::try_from(share_plan.target_count).unwrap_or(usize::MAX);
        if targets.len() != share_plan.target_servers.len()
            || targets.len() != target_count
            || target_count != expected_target
        {
            return Err(VotingError::InvalidInput {
                message: format!("helper-share plan {share_index} has an invalid target set"),
            });
        }
        if let Some(url) = targets.iter().find(|url| !configured.contains(url)) {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "helper-share plan {share_index} targets helper removed from current configuration: {url}"
                ),
            });
        }
        for url in targets {
            *assignments.entry(url).or_default() += 1;
        }
    }
    if share_count == VOTE_COMMITMENT_SHARE_COUNT && configured.len() >= 2 {
        if let Some((url, count)) = assignments
            .iter()
            .find(|(_, count)| **count > SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER)
        {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "persisted helper-share plan assigns {count} shares to {url}, exceeding the initial maximum of {SHARE_HELPER_MAX_INITIAL_SHARES_PER_SERVER}"
                ),
            });
        }
    }
    Ok(configured)
}

fn validate_immediate_plan(
    plan: &ShareDeliveryPlan,
    immediate_position: Option<u32>,
) -> Result<(), VotingError> {
    if let Some((index, _)) = plan
        .share_plans
        .iter()
        .enumerate()
        .find(|(_, plan)| plan.immediate && plan.submit_at != 0)
    {
        return Err(VotingError::InvalidInput {
            message: format!(
                "persisted helper-share plan {index} marks an immediate share with nonzero submit_at"
            ),
        });
    }
    let marked = plan
        .share_plans
        .iter()
        .enumerate()
        .filter_map(|(index, plan)| plan.immediate.then_some(index as u32))
        .collect::<Vec<_>>();
    if marked.as_slice() == immediate_position.as_slice() {
        Ok(())
    } else {
        Err(VotingError::InvalidInput {
            message: "persisted helper-share immediate designation does not match this request"
                .to_string(),
        })
    }
}

fn guarantee_name(guarantee: SharePlacementGuarantee) -> &'static str {
    match guarantee {
        SharePlacementGuarantee::Strict => "strict",
        SharePlacementGuarantee::LegacyBestEffort => "legacy_best_effort",
    }
}
