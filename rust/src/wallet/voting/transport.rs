//! Route-policy-aware network transports for voting.
//!
//! What this replaces is the SDK's URL-taking convenience layer. A helper that
//! takes a `&str` endpoint dials its own clearnet socket, which silently
//! overrides the user's chosen route; the `_on` / injected-transport forms let
//! Vizor open the connection instead, so a Tor wallet keeps its route and a
//! half-bootstrapped Tor fails closed.
//!
//! The split of responsibility that follows from opening our own sockets:
//!
//! - Vizor decides which route applies right now and refuses to proceed when Tor
//!   is wanted but unusable.
//! - Vizor retries the **dial**, because only the side that opens the socket sees
//!   a connect failure.
//! - `zcash_voting` owns the transports (`HyperTransport` / `TorTransport`) and
//!   all **RPC** retry (`anchor_tree_state_with_retry_on`), so no lightwalletd
//!   retry policy is duplicated here.

use std::{sync::Arc, time::Duration};

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

/// Fetches the voting snapshot anchor over the user's selected route.
///
/// # Errors
///
/// Returns an error if the route policy blocks the request, if the channel
/// cannot be opened within [`LWD_DIAL_ATTEMPTS`], or if lightwalletd does not
/// answer within the SDK's retry budget.
pub(crate) async fn fetch_snapshot_tree_state(
    lightwalletd_url: &str,
    snapshot_height: u64,
) -> Result<TreeState, String> {
    // Fail closed before spending any dial attempts. An unusable Tor route will
    // not become usable inside a backoff schedule, unlike the transient connect
    // failures the loop below exists for.
    crate::network_privacy::tor_client_for_route(false)?;

    let mut last_error = None;
    for attempt in 1..=LWD_DIAL_ATTEMPTS {
        match sync_engine::open_lwd_channel(lightwalletd_url).await {
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

/// Resolves the PIR transport for the user's selected route.
///
/// Tor mode gets a shared circuit, matching the rest of the app's foreground
/// HTTP: a PIR query already hides which nullifier it looks up, so a per-query
/// circuit would buy nothing and cost a fresh circuit per note.
///
/// A `None` route is direct *by request*, not by fallback — `tor_client_for_route`
/// has already failed closed if Tor was wanted and unusable. Keeping that arm
/// spelled out here, rather than behind an SDK helper that takes an
/// `Option<TorClient>`, is deliberate: absence of a Tor client silently selecting
/// clearnet is the same shape of bug as an endpoint URL silently dialling it.
///
/// # Errors
///
/// Returns an error while Tor is the desired route but not usable, so callers
/// fail closed instead of querying PIR directly.
pub(crate) fn policy_aware_pir_transport() -> Result<Arc<dyn zcash_voting::Transport>, String> {
    Ok(match crate::network_privacy::tor_client_for_route(false)? {
        Some(tor) => Arc::new(zcash_voting::TorTransport::new(tor)),
        None => Arc::new(zcash_voting::HyperTransport::new()),
    })
}

#[cfg(test)]
mod tests {
    use super::{fetch_snapshot_tree_state, policy_aware_pir_transport, LWD_DIAL_RETRY_BASE_DELAY};
    use crate::network_privacy::test_route_policy::lock_route_policy;
    use std::time::Instant;

    const UNREACHABLE_LWD: &str = "https://lightwalletd.invalid:9067";

    #[test]
    fn direct_route_yields_a_pir_transport() {
        let _policy = lock_route_policy();
        crate::network_privacy::disable_tor();

        policy_aware_pir_transport().expect("direct route needs no Tor client");
    }

    #[test]
    fn pir_transport_fails_closed_while_tor_is_unavailable() {
        let _policy = lock_route_policy();
        crate::network_privacy::begin_tor_enable();

        let error = policy_aware_pir_transport()
            .map(|_| ())
            .expect_err("Tor without a client must not connect");

        assert!(error.contains("Tor"), "{error}");
    }

    #[tokio::test]
    async fn snapshot_tree_state_fails_closed_while_tor_is_unavailable() {
        let _policy = lock_route_policy();
        crate::network_privacy::begin_tor_enable();

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
