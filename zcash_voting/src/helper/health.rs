//! Local health scoring for helper servers.
//!
//! This is an **ordering hint, not a block list**. Voting recovery has to keep
//! making progress even when every helper is flaky, so a degraded helper is
//! moved to the back of the candidate list rather than removed. Only when at
//! least one healthy helper exists does demotion have any effect at all.
//!
//! Scores are process-local and deliberately not persisted: they describe the
//! current network moment, not a durable judgement about an operator. A wallet
//! restart starts everyone even.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use crate::helper::url::canonicalize_helper_base_url;

/// Consecutive failures before a helper enters cooldown.
pub const HELPER_FAILURE_THRESHOLD: u32 = 3;
/// Seconds a helper stays demoted after crossing the failure threshold.
pub const HELPER_COOLDOWN_SECONDS: u64 = 30;

#[derive(Clone, Copy, Debug, Default)]
struct HelperState {
    consecutive_failures: u32,
    opened_at: Option<u64>,
}

/// Tracks helper servers that repeatedly fail during share submission or
/// recovery.
///
/// Cheap to clone: clones share one score table, so a client and a tracking
/// loop can hold the same view.
#[derive(Clone, Debug)]
pub struct HelperHealth {
    failure_threshold: u32,
    cooldown_seconds: u64,
    states: Arc<Mutex<HashMap<String, HelperState>>>,
}

impl Default for HelperHealth {
    fn default() -> Self {
        Self::new(HELPER_FAILURE_THRESHOLD, HELPER_COOLDOWN_SECONDS)
    }
}

impl HelperHealth {
    /// Creates a tracker with explicit thresholds.
    ///
    /// A `failure_threshold` of zero is raised to one; a helper that can be
    /// demoted before it has failed would make the ordering meaningless.
    pub fn new(failure_threshold: u32, cooldown_seconds: u64) -> Self {
        Self {
            failure_threshold: failure_threshold.max(1),
            cooldown_seconds,
            states: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Returns helper URLs ordered by current health.
    ///
    /// Caller order is preserved within the healthy and degraded groups. If
    /// **every** helper is degraded the input order is returned unchanged, so a
    /// wallet whose whole helper set is struggling still tries all of them
    /// instead of stalling.
    ///
    /// Accepted URL spellings are compared by their canonical helper identity,
    /// while returned values retain the caller's spelling. This expires elapsed
    /// cooldowns before ordering. [`Self::record_failure`] performs the same
    /// expiry before scoring a later failure.
    pub fn candidate_servers(&self, server_urls: &[String], now_seconds: u64) -> Vec<String> {
        if server_urls.is_empty() {
            return Vec::new();
        }

        let mut available = Vec::new();
        let mut degraded = Vec::new();
        for url in server_urls {
            if self.is_available(url, now_seconds) {
                available.push(url.clone());
            } else {
                degraded.push(url.clone());
            }
        }

        if available.is_empty() {
            return server_urls.to_vec();
        }
        available.extend(degraded);
        available
    }

    /// Clears any degraded state for a helper that answered successfully.
    pub fn record_success(&self, server_url: &str) {
        let server_url = helper_identity_key(server_url);
        if let Ok(mut states) = self.states.lock() {
            states.remove(&server_url);
        }
    }

    /// Records one helper failure, opening a cooldown at the threshold.
    ///
    /// Failures during an active cooldown do not extend it: readmission remains
    /// anchored to when the helper first crossed the threshold. A failure after
    /// expiry immediately opens a fresh cooldown.
    pub fn record_failure(&self, server_url: &str, now_seconds: u64) {
        let server_url = helper_identity_key(server_url);
        if let Ok(mut states) = self.states.lock() {
            let state = states.entry(server_url).or_default();
            self.expire_cooldown_if_elapsed(state, now_seconds);
            state.consecutive_failures = state.consecutive_failures.saturating_add(1);
            if state.consecutive_failures >= self.failure_threshold && state.opened_at.is_none() {
                state.opened_at = Some(now_seconds);
            }
        }
    }

    /// Returns the current consecutive-failure count for a helper.
    ///
    /// Exposed for diagnostics and tests; scheduling decisions should go
    /// through [`HelperHealth::candidate_servers`].
    pub fn failure_count(&self, server_url: &str) -> u32 {
        let server_url = helper_identity_key(server_url);
        self.states
            .lock()
            .ok()
            .and_then(|states| {
                states
                    .get(&server_url)
                    .map(|state| state.consecutive_failures)
            })
            .unwrap_or(0)
    }

    /// Returns true when a helper is not currently in cooldown.
    ///
    /// On cooldown expiry the helper is re-admitted at `failure_threshold - 1`
    /// rather than a clean slate, so one further failure demotes it again
    /// immediately instead of granting it a fresh run of attempts.
    fn is_available(&self, server_url: &str, now_seconds: u64) -> bool {
        let server_url = helper_identity_key(server_url);
        let Ok(mut states) = self.states.lock() else {
            return true;
        };
        let Some(state) = states.get_mut(&server_url) else {
            return true;
        };
        self.expire_cooldown_if_elapsed(state, now_seconds);
        state.opened_at.is_none()
    }

    /// Expires an elapsed cooldown and prepares the helper for immediate
    /// re-demotion on its next failure.
    fn expire_cooldown_if_elapsed(&self, state: &mut HelperState, now_seconds: u64) {
        let Some(opened_at) = state.opened_at else {
            return;
        };
        if now_seconds.saturating_sub(opened_at) < self.cooldown_seconds {
            return;
        }
        state.opened_at = None;
        state.consecutive_failures = self.failure_threshold.saturating_sub(1);
    }
}

fn helper_identity_key(server_url: &str) -> String {
    canonicalize_helper_base_url(server_url).unwrap_or_else(|_| server_url.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn urls(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn healthy_helpers_keep_caller_order() {
        let health = HelperHealth::default();
        let servers = urls(&["https://a.example", "https://b.example"]);
        assert_eq!(health.candidate_servers(&servers, 0), servers);
    }

    #[test]
    fn degraded_helper_is_demoted_not_removed() {
        let health = HelperHealth::default();
        let servers = urls(&["https://a.example", "https://b.example"]);
        for _ in 0..HELPER_FAILURE_THRESHOLD {
            health.record_failure("https://a.example", 100);
        }

        assert_eq!(
            health.candidate_servers(&servers, 100),
            urls(&["https://b.example", "https://a.example"])
        );
    }

    #[test]
    fn equivalent_url_spellings_share_one_health_identity() {
        let health = HelperHealth::default();
        for _ in 0..HELPER_FAILURE_THRESHOLD {
            health.record_failure("HTTPS://A.Example:443/", 100);
        }

        assert_eq!(
            health.failure_count("https://a.example"),
            HELPER_FAILURE_THRESHOLD
        );
        assert_eq!(
            health.candidate_servers(&urls(&["https://a.example/", "https://b.example"]), 100),
            urls(&["https://b.example", "https://a.example/"])
        );

        health.record_success("https://a.example");
        assert_eq!(health.failure_count("https://a.example/"), 0);
    }

    #[test]
    fn invalid_urls_keep_their_exact_health_identity() {
        let health = HelperHealth::new(1, HELPER_COOLDOWN_SECONDS);
        health.record_failure("not a url", 100);

        assert_eq!(health.failure_count("not a url"), 1);
        assert_eq!(health.failure_count("not a url "), 0);
    }

    #[test]
    fn all_helpers_degraded_still_returns_every_candidate() {
        let health = HelperHealth::default();
        let servers = urls(&["https://a.example", "https://b.example"]);
        for server in &servers {
            for _ in 0..HELPER_FAILURE_THRESHOLD {
                health.record_failure(server, 100);
            }
        }

        // Original order, unchanged: with nothing healthy to promote, demotion
        // would only stall recovery.
        assert_eq!(health.candidate_servers(&servers, 100), servers);
    }

    #[test]
    fn success_clears_accumulated_failures() {
        let health = HelperHealth::default();
        health.record_failure("https://a.example", 10);
        health.record_failure("https://a.example", 11);
        health.record_success("https://a.example");

        assert_eq!(health.failure_count("https://a.example"), 0);
    }

    #[test]
    fn cooldown_expiry_readmits_one_failure_below_threshold() {
        let health = HelperHealth::default();
        let servers = urls(&["https://a.example", "https://b.example"]);
        for _ in 0..HELPER_FAILURE_THRESHOLD {
            health.record_failure("https://a.example", 100);
        }

        let after_cooldown = 100 + HELPER_COOLDOWN_SECONDS;
        assert_eq!(health.candidate_servers(&servers, after_cooldown), servers);
        assert_eq!(
            health.failure_count("https://a.example"),
            HELPER_FAILURE_THRESHOLD - 1
        );

        // One more failure re-opens the cooldown immediately.
        health.record_failure("https://a.example", after_cooldown);
        assert_eq!(
            health.candidate_servers(&servers, after_cooldown),
            urls(&["https://b.example", "https://a.example"])
        );
    }

    #[test]
    fn repeated_failures_do_not_extend_cooldown() {
        let health = HelperHealth::default();
        let servers = urls(&["https://a.example", "https://b.example"]);
        for _ in 0..HELPER_FAILURE_THRESHOLD {
            health.record_failure("https://a.example", 100);
        }
        health.record_failure("https://a.example", 110);
        health.record_failure("https://a.example", 120);

        assert_eq!(
            health.candidate_servers(&servers, 129),
            urls(&["https://b.example", "https://a.example"])
        );
        assert_eq!(health.candidate_servers(&servers, 130), servers);
    }

    #[test]
    fn failure_after_elapsed_cooldown_reopens_immediately() {
        let health = HelperHealth::default();
        let servers = urls(&["https://a.example", "https://b.example"]);
        for _ in 0..HELPER_FAILURE_THRESHOLD {
            health.record_failure("https://a.example", 100);
        }

        health.record_failure("https://a.example", 130);

        assert_eq!(
            health.failure_count("https://a.example"),
            HELPER_FAILURE_THRESHOLD
        );
        assert_eq!(
            health.candidate_servers(&servers, 130),
            urls(&["https://b.example", "https://a.example"])
        );
        assert_eq!(
            health.candidate_servers(&servers, 159),
            urls(&["https://b.example", "https://a.example"])
        );
        assert_eq!(health.candidate_servers(&servers, 160), servers);
    }

    #[test]
    fn zero_threshold_is_raised_so_unfailed_helpers_stay_healthy() {
        let health = HelperHealth::new(0, HELPER_COOLDOWN_SECONDS);
        let servers = urls(&["https://a.example", "https://b.example"]);
        assert_eq!(health.candidate_servers(&servers, 0), servers);
    }

    #[test]
    fn empty_input_returns_empty() {
        let health = HelperHealth::default();
        assert!(health.candidate_servers(&[], 0).is_empty());
    }
}
