//! Route-policy-aware lightwalletd access for voting snapshot anchors.
//!
//! What this replaces is the SDK's URL-taking convenience layer. A helper that
//! takes a `&str` endpoint dials its own clearnet socket, which silently
//! overrides the user's chosen route; the `_on` / injected-client form lets
//! Vizor open the connection instead, so a Tor wallet keeps its route, a
//! bootstrapping Tor is waited for, and a broken Tor fails closed.
//!
//! The split of responsibility that follows from opening our own sockets:
//!
//! - Vizor decides which route applies right now and refuses to proceed when Tor
//!   is wanted but unusable.
//! - Vizor retries the **dial**, because only the side that opens the socket sees
//!   a connect failure.
//! - `zcash_voting` owns all **RPC** retry (`anchor_tree_state_with_retry_on`),
//!   so no lightwalletd retry policy is duplicated here.

use std::time::Duration;

use zcash_client_backend::proto::service::TreeState;

use crate::wallet::sync_engine;

/// Dial attempts before the anchor fetch gives up.
///
/// Retrying the dial is Vizor's job, not the SDK's: Vizor opens the socket, so
/// only Vizor sees a connect failure. Matching the three attempts the SDK's own
/// URL-taking helper used keeps a flaky network from costing the warm-up on its
/// first stumble. Once a channel is up, all RPC retry belongs to
/// `anchor_tree_state_with_retry_on`, so the two budgets do not compound.
const LWD_DIAL_ATTEMPTS: u32 = 3;
const LWD_DIAL_RETRY_BASE_DELAY: Duration = Duration::from_millis(500);
/// How long a snapshot fetch waits for a Tor bootstrap before giving up. Short
/// on purpose: the voting work around it is awaited by the destructive drain.
const SNAPSHOT_ROUTE_WAIT: Duration = Duration::from_secs(20);

/// Fetches the voting snapshot anchor over the user's selected route.
///
/// # Errors
///
/// Returns an error if the route policy blocks the request, if Tor is still
/// bootstrapping after [`SNAPSHOT_ROUTE_WAIT`], if the channel cannot be opened
/// within [`LWD_DIAL_ATTEMPTS`], or if lightwalletd does not answer within the
/// SDK's retry budget.
pub(crate) async fn fetch_snapshot_tree_state(
    lightwalletd_url: &str,
    snapshot_height: u64,
) -> Result<TreeState, String> {
    // Resolve the route before spending any dial attempts: a broken Tor route
    // fails closed without consuming one. A bootstrap in flight is waited out,
    // but only briefly — this runs inside voting work the destructive drain
    // has to await, so account deletion must not sit behind the bootstrap's
    // full deadline.
    let route_deadline = tokio::time::Instant::now() + SNAPSHOT_ROUTE_WAIT;
    let route_wait_expired = || tokio::time::Instant::now() >= route_deadline;
    crate::network_privacy::tor_client_for_route(false, route_wait_expired).await?;

    let mut last_error = None;
    for attempt in 1..=LWD_DIAL_ATTEMPTS {
        match sync_engine::open_lwd_channel_with_cancel(lightwalletd_url, route_wait_expired).await
        {
            Ok(mut client) => {
                return zcash_voting::lwd::anchor_tree_state_with_retry_on(
                    &mut client,
                    snapshot_height,
                )
                .await
                .map_err(|error| error.to_string());
            }
            Err(error) => {
                last_error = Some(error.to_string());
                if attempt < LWD_DIAL_ATTEMPTS {
                    tokio::time::sleep(LWD_DIAL_RETRY_BASE_DELAY * attempt).await;
                }
            }
        }
    }

    Err(last_error.unwrap_or_else(|| "lightwalletd dial failed".to_string()))
}

#[cfg(test)]
mod tests {
    use super::{fetch_snapshot_tree_state, LWD_DIAL_RETRY_BASE_DELAY};
    use crate::network_privacy::test_route_policy::lock_route_policy;
    use std::time::Instant;

    const UNREACHABLE_LWD: &str = "https://lightwalletd.invalid:9067";

    #[tokio::test]
    async fn snapshot_tree_state_fails_closed_while_tor_is_unavailable() {
        let _policy = lock_route_policy();
        crate::network_privacy::begin_tor_enable();
        // A resolved failure, not a bootstrap in flight (which is waited out).
        crate::network_privacy::fail_tor_enable();

        let started = Instant::now();
        let error = fetch_snapshot_tree_state(UNREACHABLE_LWD, 1)
            .await
            .expect_err("Tor without a client must not reach lightwalletd");

        assert!(error.contains("Tor"), "{error}");
        // A policy failure is not transient, so it must short-circuit ahead of
        // the dial retries rather than waiting out their backoff schedule.
        let elapsed = started.elapsed();
        assert!(
            elapsed < LWD_DIAL_RETRY_BASE_DELAY,
            "fail-closed took {elapsed:?}, so it burned dial retries"
        );
    }
}
