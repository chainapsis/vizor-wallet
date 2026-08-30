use std::{
    collections::{HashSet, VecDeque},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::Duration,
};

use tokio::task::JoinSet;

use crate::helper::client::{HelperClient, HelperError, ShareStatus};

use super::{
    SHARE_STATUS_CANCEL_CHECK_MILLISECONDS, SHARE_STATUS_MAX_CONCURRENT_POLLS,
    SHARE_STATUS_POLL_BUDGET_MILLISECONDS,
};

/// Configured-fleet evidence observed while polling one share.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum ShareStatusOutcome {
    /// The required distinct configured helpers reported confirmation.
    ConfiguredHelperQuorumObserved,
    /// Polling ended without the required configured-helper quorum.
    ConfiguredHelperQuorumNotObserved,
    /// The caller stopped polling before further evidence could be collected.
    Cancelled,
}

fn record_completed_poll(
    joined: Result<(String, Result<ShareStatus, HelperError>), tokio::task::JoinError>,
    in_flight: &mut HashSet<String>,
    confirmations: &mut usize,
    required_confirmations: usize,
) -> bool {
    let Ok((server_url, outcome)) = joined else {
        return false;
    };
    in_flight.remove(&server_url);
    if matches!(outcome, Ok(ShareStatus::Confirmed)) {
        *confirmations += 1;
    }
    *confirmations == required_confirmations
}

pub(super) async fn finish_expired_polls(
    polls: &mut JoinSet<(String, Result<ShareStatus, HelperError>)>,
    in_flight: &mut HashSet<String>,
    confirmations: &mut usize,
    required_confirmations: usize,
    client: &HelperClient,
    failure_time: u64,
) -> bool {
    polls.abort_all();
    let mut quorum_observed = false;
    while let Some(joined) = polls.join_next().await {
        quorum_observed |=
            record_completed_poll(joined, in_flight, confirmations, required_confirmations);
    }
    if !quorum_observed {
        for server_url in in_flight.drain() {
            client.health().record_failure(&server_url, failure_time);
        }
    }
    quorum_observed
}

/// Polls helpers for the share's global on-chain confirmation state.
///
/// At most [`SHARE_STATUS_MAX_CONCURRENT_POLLS`] requests run concurrently and
/// the complete quorum search is capped by
/// [`SHARE_STATUS_POLL_BUDGET_MILLISECONDS`]. Reaching the quorum, caller
/// cancellation, or budget expiry aborts every outstanding request. Helpers
/// still in flight at budget expiry are degraded so later passes prefer other
/// configured endpoints.
pub(super) async fn poll_share_helpers(
    client: &HelperClient,
    round_id: &str,
    share_id: &str,
    server_urls: &[String],
    now_seconds: u64,
    cancel: &(dyn Fn() -> bool + Send + Sync),
) -> ShareStatusOutcome {
    poll_share_helpers_with_budget(
        client,
        round_id,
        share_id,
        server_urls,
        now_seconds,
        cancel,
        SHARE_STATUS_POLL_BUDGET_MILLISECONDS,
    )
    .await
}

pub(super) async fn poll_share_helpers_with_budget(
    client: &HelperClient,
    round_id: &str,
    share_id: &str,
    server_urls: &[String],
    now_seconds: u64,
    cancel: &(dyn Fn() -> bool + Send + Sync),
    poll_budget_milliseconds: u64,
) -> ShareStatusOutcome {
    const REQUIRED_CONFIRMATIONS: usize = 2;
    let required_confirmations = REQUIRED_CONFIRMATIONS.min(server_urls.len());
    if required_confirmations == 0 {
        return ShareStatusOutcome::ConfiguredHelperQuorumNotObserved;
    }

    let mut remaining = VecDeque::from(client.health().candidate_servers(server_urls, now_seconds));
    let mut polls = JoinSet::new();
    let mut in_flight = HashSet::new();
    let task_cancelled = Arc::new(AtomicBool::new(false));
    let deadline = tokio::time::Instant::now() + Duration::from_millis(poll_budget_milliseconds);
    let mut confirmations = 0usize;

    loop {
        // Drain already-completed work before observing cancellation so a late
        // cancellation cannot replace definite confirmation evidence.
        while let Some(joined) = polls.try_join_next() {
            if record_completed_poll(
                joined,
                &mut in_flight,
                &mut confirmations,
                required_confirmations,
            ) {
                task_cancelled.store(true, Ordering::Relaxed);
                polls.abort_all();
                return ShareStatusOutcome::ConfiguredHelperQuorumObserved;
            }
        }
        if polls.is_empty() && remaining.is_empty() {
            return ShareStatusOutcome::ConfiguredHelperQuorumNotObserved;
        }
        if cancel() {
            task_cancelled.store(true, Ordering::Relaxed);
            polls.abort_all();
            return ShareStatusOutcome::Cancelled;
        }

        let now = tokio::time::Instant::now();
        if now >= deadline {
            // Abort first, then drain the set. Tasks that completed before the
            // abort retain their own status and health result; only tasks that
            // actually abort remain in `in_flight` for manual degradation.
            let failure_time = now_seconds.saturating_add(poll_budget_milliseconds.div_ceil(1_000));
            if finish_expired_polls(
                &mut polls,
                &mut in_flight,
                &mut confirmations,
                required_confirmations,
                client,
                failure_time,
            )
            .await
            {
                return ShareStatusOutcome::ConfiguredHelperQuorumObserved;
            }
            return ShareStatusOutcome::ConfiguredHelperQuorumNotObserved;
        }

        while polls.len() < SHARE_STATUS_MAX_CONCURRENT_POLLS {
            let Some(server_url) = remaining.pop_front() else {
                break;
            };
            in_flight.insert(server_url.clone());
            let client = client.clone();
            let round_id = round_id.to_string();
            let share_id = share_id.to_string();
            let task_cancelled = Arc::clone(&task_cancelled);
            polls.spawn(async move {
                let outcome = client
                    .share_status(&server_url, &round_id, &share_id, now_seconds, &|| {
                        task_cancelled.load(Ordering::Relaxed)
                    })
                    .await;
                (server_url, outcome)
            });
        }

        if polls.is_empty() {
            return ShareStatusOutcome::ConfiguredHelperQuorumNotObserved;
        }

        let cancel_check = now + Duration::from_millis(SHARE_STATUS_CANCEL_CHECK_MILLISECONDS);
        let wait_deadline = deadline.min(cancel_check);
        let joined = tokio::select! {
            biased;
            joined = polls.join_next() => joined,
            _ = tokio::time::sleep_until(wait_deadline) => continue,
        };
        let Some(joined) = joined else {
            continue;
        };
        if record_completed_poll(
            joined,
            &mut in_flight,
            &mut confirmations,
            required_confirmations,
        ) {
            task_cancelled.store(true, Ordering::Relaxed);
            polls.abort_all();
            return ShareStatusOutcome::ConfiguredHelperQuorumObserved;
        }
    }
}
