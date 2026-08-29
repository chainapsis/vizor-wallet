//! Helper-server REST client for share submission and status polling.
//!
//! This is the protocol mapper for the three helper endpoints the voting
//! workflow uses. It owns URL construction, response decoding, retry rules, and
//! health bookkeeping; the socket work belongs to a caller-supplied
//! [`HelperTransport`].
//!
//! Retry behavior differs per endpoint by design:
//!
//! | Call | Endpoint | Retries |
//! |---|---|---|
//! | [`HelperClient::preflight`] | `GET /status` | none |
//! | [`HelperClient::share_status`] | `GET /share-status/{round_id}/{share_id}` | transient failures |
//! | [`HelperClient::submit_share`] | `POST /shares` | transient failures, **never an ambiguous failure** |
//! | [`HelperClient::resubmit_share`] | `POST /shares` | none |
//!
//! A share POST that times out, fails after response headers arrive, or returns
//! a successful but unusable response may already have been accepted, so
//! retrying it on the same helper risks a duplicate. Moving to the next helper
//! is both safer and faster.

use std::{collections::HashMap, sync::Arc, time::Duration};

use serde_json::Value;
use tokio::task::JoinSet;

use crate::{
    helper::{
        health::HelperHealth,
        transport::{
            HelperResponse, HelperTransport, HelperTransportError, MAX_HELPER_RESPONSE_BYTES,
        },
        url::canonicalize_helper_base_url,
    },
    share_policy::{
        SHARE_HELPER_POST_TIMEOUT_MILLISECONDS, SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS,
        SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS,
    },
    types::{validate_vote_round_id_bytes, VotingError},
    wire::VoteShareWire,
};

/// Default per-request deadline for helper share-status calls.
pub const HELPER_STATUS_TIMEOUT_SECONDS: u64 = 5;
/// Default backoff delays between helper retry attempts, in milliseconds.
pub const HELPER_RETRY_DELAYS_MS: &[u64] = &[200, 600];

/// Confirmation state a helper reports for one share.
///
/// The helper protocol defines exactly these two global on-chain states.
/// Anything else — an error envelope or a proxy's HTML page — is
/// [`HelperError::Decode`], which the tracking layer scores as a helper
/// failure. `Pending` says nothing about whether this individual helper stored
/// the share.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShareStatus {
    Pending,
    Confirmed,
}

/// Outcome a helper reports for one share submission.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ShareSubmissionStatus {
    Queued,
    Duplicate,
}

/// A helper request that did not produce a usable answer.
#[derive(Clone, Debug)]
pub enum HelperError {
    /// The caller supplied a request that cannot be dispatched safely.
    InvalidRequest { message: String },
    /// The request never completed. Carries the ambiguity of a timeout.
    Transport(HelperTransportError),
    /// The helper answered with a non-2xx status.
    ///
    /// Response bodies are intentionally excluded because they are controlled
    /// by the helper and may contain secrets or log-injection payloads.
    Status { status: u16 },
    /// The helper answered, but not with something this protocol understands.
    Decode { message: String },
    /// A successful share submission returned an unusable protocol response.
    ///
    /// The helper may already have queued the share, so the submission must not
    /// be retried against that helper. Tracking retains it as outcome-unknown
    /// and polls the helper for a definitive status instead.
    AmbiguousSubmissionResponse { message: String },
    /// The overall delivery deadline elapsed before a request was dispatched.
    ///
    /// This is a definite local outcome: the helper did not receive the share,
    /// so the error is neither ambiguous nor charged against helper health.
    DeadlineExceeded,
    /// The caller asked to stop before the request finished.
    Cancelled,
}

impl HelperError {
    /// Returns true when the same helper may safely be tried again.
    ///
    /// An ambiguous failure is excluded from the submission path by
    /// [`HelperClient::submit_share`] rather than here, because it *is*
    /// retryable for an idempotent GET.
    fn is_transient(&self) -> bool {
        match self {
            Self::Transport(_) => true,
            Self::Status { status } => matches!(status, 429 | 500 | 502 | 503 | 504),
            Self::InvalidRequest { .. }
            | Self::Decode { .. }
            | Self::AmbiguousSubmissionResponse { .. }
            | Self::DeadlineExceeded
            | Self::Cancelled => false,
        }
    }

    /// Returns true when the helper may have processed the request.
    pub fn is_ambiguous(&self) -> bool {
        matches!(
            self,
            Self::Transport(
                HelperTransportError::Timeout
                    | HelperTransportError::Ambiguous(_)
                    | HelperTransportError::Response(_)
            ) | Self::AmbiguousSubmissionResponse { .. }
        ) || matches!(self, Self::Status { status } if (500..=599).contains(status))
    }
}

impl std::fmt::Display for HelperError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidRequest { message } => write!(f, "invalid helper request: {message}"),
            Self::Transport(error) => write!(f, "{error}"),
            Self::Status { status } => write!(f, "helper returned HTTP {status}"),
            Self::Decode { message } => write!(f, "helper response was not usable: {message}"),
            Self::AmbiguousSubmissionResponse { message } => {
                write!(f, "helper submission outcome is unknown: {message}")
            }
            Self::DeadlineExceeded => {
                write!(
                    f,
                    "helper delivery deadline elapsed before request dispatch"
                )
            }
            Self::Cancelled => write!(f, "helper request cancelled"),
        }
    }
}

impl std::error::Error for HelperError {}

/// Timeouts and backoff for helper requests.
#[derive(Clone, Debug)]
pub struct HelperClientConfig {
    /// Deadline for status GETs.
    request_timeout: Duration,
    /// Deadline for initial and recovery share POSTs.
    post_timeout: Duration,
    /// Initial window for collecting helper readiness responses.
    preflight_soft_timeout: Duration,
    /// Absolute deadline for the helper readiness race.
    preflight_hard_timeout: Duration,
    retry_delays: Vec<Duration>,
}

impl Default for HelperClientConfig {
    fn default() -> Self {
        Self {
            request_timeout: Duration::from_secs(HELPER_STATUS_TIMEOUT_SECONDS),
            post_timeout: Duration::from_millis(SHARE_HELPER_POST_TIMEOUT_MILLISECONDS),
            preflight_soft_timeout: Duration::from_millis(
                SHARE_HELPER_PREFLIGHT_SOFT_TIMEOUT_MILLISECONDS,
            ),
            preflight_hard_timeout: Duration::from_millis(
                SHARE_HELPER_PREFLIGHT_HARD_TIMEOUT_MILLISECONDS,
            ),
            retry_delays: HELPER_RETRY_DELAYS_MS
                .iter()
                .map(|ms| Duration::from_millis(*ms))
                .collect(),
        }
    }
}

impl HelperClientConfig {
    /// Sets the complete status-request deadline.
    ///
    /// The duration must be nonzero and representable by Tokio's monotonic
    /// clock.
    pub fn with_request_timeout(mut self, timeout: Duration) -> Result<Self, VotingError> {
        require_valid_duration(timeout, "request_timeout")?;
        self.request_timeout = timeout;
        Ok(self)
    }

    /// Sets the complete helper POST deadline.
    ///
    /// The duration must be nonzero and representable by Tokio's monotonic
    /// clock.
    pub fn with_post_timeout(mut self, timeout: Duration) -> Result<Self, VotingError> {
        require_valid_duration(timeout, "post_timeout")?;
        self.post_timeout = timeout;
        Ok(self)
    }

    /// Sets the initial and absolute readiness-race deadlines.
    ///
    /// Both durations must be nonzero and representable by Tokio's monotonic
    /// clock. The soft timeout must not exceed the hard timeout. Pending probes
    /// stay alive after the soft timeout when too few helpers are ready.
    pub fn with_preflight_timeouts(
        mut self,
        soft_timeout: Duration,
        hard_timeout: Duration,
    ) -> Result<Self, VotingError> {
        require_valid_duration(soft_timeout, "preflight_soft_timeout")?;
        require_valid_duration(hard_timeout, "preflight_hard_timeout")?;
        if soft_timeout > hard_timeout {
            return Err(VotingError::InvalidInput {
                message: "preflight_soft_timeout must not exceed preflight_hard_timeout"
                    .to_string(),
            });
        }
        self.preflight_soft_timeout = soft_timeout;
        self.preflight_hard_timeout = hard_timeout;
        Ok(self)
    }

    /// Sets at most two retry backoffs, for at most three total attempts.
    ///
    /// Every delay must be nonzero and representable by Tokio's monotonic
    /// clock.
    pub fn with_retry_delays(mut self, retry_delays: Vec<Duration>) -> Result<Self, VotingError> {
        if retry_delays.len() > HELPER_RETRY_DELAYS_MS.len() {
            return Err(VotingError::InvalidInput {
                message: format!(
                    "retry_delays supports at most {} backoffs",
                    HELPER_RETRY_DELAYS_MS.len()
                ),
            });
        }
        for (index, delay) in retry_delays.iter().copied().enumerate() {
            require_valid_duration(delay, &format!("retry_delays[{index}]"))?;
        }
        self.retry_delays = retry_delays;
        Ok(self)
    }

    /// Disables retries, leaving one request attempt per operation.
    pub fn without_retries(mut self) -> Self {
        self.retry_delays.clear();
        self
    }
}

fn require_valid_duration(duration: Duration, name: &str) -> Result<(), VotingError> {
    if duration.is_zero() {
        return Err(VotingError::InvalidInput {
            message: format!("{name} must be nonzero"),
        });
    }
    if tokio::time::Instant::now().checked_add(duration).is_none() {
        return Err(VotingError::InvalidInput {
            message: format!("{name} is too large for Tokio's monotonic clock"),
        });
    }
    Ok(())
}

/// REST client for helper-server share endpoints.
pub struct HelperClient {
    transport: Arc<dyn HelperTransport>,
    health: HelperHealth,
    config: HelperClientConfig,
}

impl HelperClient {
    /// Creates a client with default timeouts and backoff.
    pub fn new(transport: Arc<dyn HelperTransport>, health: HelperHealth) -> Self {
        Self::with_config(transport, health, HelperClientConfig::default())
    }

    /// Creates a client with explicit timeouts and backoff.
    pub fn with_config(
        transport: Arc<dyn HelperTransport>,
        health: HelperHealth,
        config: HelperClientConfig,
    ) -> Self {
        Self {
            transport,
            health,
            config,
        }
    }

    /// Returns the shared health tracker.
    pub fn health(&self) -> &HelperHealth {
        &self.health
    }

    /// Probes helper readiness without failing the voting flow.
    ///
    /// A helper is ready only when `GET /status` succeeds and reports
    /// `{"status":"ok"}`. Every failure mode collapses to `false`; readiness is
    /// advisory, so an unreachable helper is simply not ready.
    ///
    /// All valid probes start together. Pending probes stay alive past the soft
    /// timeout until `target_count` distinct canonical helpers are ready, every
    /// probe completes, or the hard timeout expires. Equivalent accepted URL
    /// spellings share one probe and readiness result. Results preserve caller
    /// order and use canonical URLs for valid inputs; probes still pending when
    /// the race ends are reported as not ready. A zero target still
    /// canonicalizes the result list but never starts a probe.
    pub async fn preflight(
        &self,
        server_urls: &[String],
        target_count: u32,
    ) -> Vec<(String, bool)> {
        let mut results = Vec::with_capacity(server_urls.len());
        let mut probe_groups: Vec<(String, Vec<usize>)> = Vec::with_capacity(server_urls.len());
        let mut probe_indices: HashMap<String, usize> = HashMap::with_capacity(server_urls.len());

        for server_url in server_urls {
            match canonicalize_helper_base_url(server_url) {
                Ok(canonical) => {
                    let result_index = results.len();
                    results.push((canonical.clone(), false));
                    if let Some(&probe_index) = probe_indices.get(&canonical) {
                        probe_groups[probe_index].1.push(result_index);
                        continue;
                    }
                    let Ok(url) = join_helper_url(&canonical, &["status"]) else {
                        continue;
                    };
                    probe_indices.insert(canonical, probe_groups.len());
                    probe_groups.push((url, vec![result_index]));
                }
                Err(_) => results.push((server_url.clone(), false)),
            }
        }

        let target_count = usize::try_from(target_count).unwrap_or(usize::MAX);
        if target_count == 0 {
            return results;
        }
        let started = tokio::time::Instant::now();
        let Some(soft_deadline) = started.checked_add(self.config.preflight_soft_timeout) else {
            return results;
        };
        let Some(hard_deadline) = started.checked_add(self.config.preflight_hard_timeout) else {
            return results;
        };
        let mut probes = JoinSet::new();
        for (url, result_indices) in probe_groups {
            let transport = Arc::clone(&self.transport);
            probes.spawn(async move {
                let ready = Self::probe(transport, &url, hard_deadline).await;
                (result_indices, ready)
            });
        }
        let mut ready_count = 0usize;
        let mut soft_elapsed = false;
        while !probes.is_empty() {
            if soft_elapsed && ready_count >= target_count {
                break;
            }
            let deadline = if soft_elapsed {
                hard_deadline
            } else {
                soft_deadline
            };
            match tokio::time::timeout_at(deadline, probes.join_next()).await {
                Ok(Some(Ok((result_indices, ready)))) => {
                    for index in result_indices {
                        results[index].1 = ready;
                    }
                    ready_count += usize::from(ready);
                }
                Ok(Some(Err(_))) => {}
                Ok(None) => break,
                Err(_) if !soft_elapsed => soft_elapsed = true,
                Err(_) => break,
            }
        }
        probes.abort_all();
        results
    }

    async fn probe(
        transport: Arc<dyn HelperTransport>,
        url: &str,
        hard_deadline: tokio::time::Instant,
    ) -> bool {
        let timeout = hard_deadline.saturating_duration_since(tokio::time::Instant::now());
        if timeout.is_zero() {
            return false;
        }
        let Ok(Ok(response)) =
            tokio::time::timeout_at(hard_deadline, transport.get(url, timeout)).await
        else {
            return false;
        };
        if !response.is_success() || validate_json_response(&response).is_err() {
            return false;
        }
        json_field(&response, "status")
            .map(|status| status.trim().eq_ignore_ascii_case("ok"))
            .unwrap_or(false)
    }

    /// Reads one helper's confirmation state for a share.
    ///
    /// `share_id` is the share reveal nullifier in lowercase hex, as produced
    /// by [`crate::share::compute_nullifier`]. `cancel` is checked before every
    /// attempt and before every backoff, so a lifecycle-owned poll can stop
    /// without opening another connection.
    ///
    /// This records helper health as a side effect: a usable answer is a
    /// success, anything else a failure. `now_seconds` is the request's wall
    /// time at invocation; scoring advances it by the monotonic time spent on
    /// the complete request and its retries. Invalid helper URLs, round IDs,
    /// and share IDs return [`HelperError::InvalidRequest`] before network I/O
    /// or health scoring.
    pub async fn share_status(
        &self,
        server_url: &str,
        round_id: &str,
        share_id: &str,
        now_seconds: u64,
        cancel: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<ShareStatus, HelperError> {
        let server_url = canonicalize_helper_base_url(server_url).map_err(invalid_request)?;
        let round_id = normalize_round_id(round_id).map_err(invalid_request)?;
        let share_id = validate_hex_path_segment(share_id, "share_id").map_err(invalid_request)?;
        let url = join_helper_url(&server_url, &["share-status", &round_id, &share_id])
            .map_err(invalid_request)?;

        let request_started = tokio::time::Instant::now();
        let result = self
            .with_retry(cancel, true, None, |_| {
                let url = url.clone();
                async move {
                    let response = self
                        .get(&url, self.config.request_timeout)
                        .await
                        .map_err(HelperError::Transport)?;
                    let response = require_success(response)?;
                    validate_json_response(&response)?;
                    parse_share_status(&response)
                }
            })
            .await;

        self.score(&server_url, &result, now_seconds, request_started);
        result
    }

    /// Posts one share to a helper for the first time.
    ///
    /// Transient failures are retried, but an ambiguous failure is **never**
    /// retried against the same helper: the share may already be queued there.
    /// This includes a timeout, a 5xx response, a failure to finish reading a
    /// response after its headers arrived, and a successful response whose
    /// submission status is missing or unusable. Cancellation can suppress a
    /// later attempt, but does not replace the result of a completed POST.
    /// Malformed local JSON and invalid helper URLs return
    /// [`HelperError::InvalidRequest`] without network I/O or health scoring.
    /// `now_seconds` is the request's wall time at invocation; health scoring
    /// advances it by the monotonic time spent completing the operation.
    pub async fn submit_share(
        &self,
        server_url: &str,
        share_wire_json: &str,
        now_seconds: u64,
        cancel: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<ShareSubmissionStatus, HelperError> {
        self.submit_share_with_timeout(
            server_url,
            share_wire_json,
            now_seconds,
            cancel,
            self.config.post_timeout,
            None,
        )
        .await
    }

    /// Posts one share while capping every transport attempt to `timeout` and
    /// the time remaining before `deadline`, when supplied.
    ///
    /// Initial fan-out uses this to shrink the final request to the time left
    /// in its overall delivery budget, and passes its overall `deadline` so a
    /// retry backoff that cannot complete in time returns the definite error
    /// it is holding instead of sleeping into the deadline.
    pub(crate) async fn submit_share_with_timeout(
        &self,
        server_url: &str,
        share_wire_json: &str,
        now_seconds: u64,
        cancel: &(dyn Fn() -> bool + Send + Sync),
        timeout: Duration,
        deadline: Option<tokio::time::Instant>,
    ) -> Result<ShareSubmissionStatus, HelperError> {
        if timeout.is_zero() {
            return Err(HelperError::InvalidRequest {
                message: "share submission timeout must be nonzero".to_string(),
            });
        }
        let server_url = canonicalize_helper_base_url(server_url).map_err(invalid_request)?;
        let body = validate_share_body(share_wire_json)?;
        let request_started = tokio::time::Instant::now();
        let result = self
            .post_share(
                &server_url,
                body,
                cancel,
                false,
                timeout.min(self.config.post_timeout),
                deadline,
            )
            .await;
        self.score(&server_url, &result, now_seconds, request_started);
        result
    }

    /// Re-posts a share to a helper during overdue recovery.
    ///
    /// One transport attempt only. A timeout here is ambiguous, and the caller
    /// — which is already walking a randomized helper order — is better placed
    /// than this client to decide whether to try elsewhere or wait. Once the
    /// POST completes, late cancellation does not replace its result. Malformed
    /// local JSON and invalid helper URLs return [`HelperError::InvalidRequest`]
    /// without network I/O or health scoring. `now_seconds` is the request's
    /// wall time at invocation; health scoring advances it by the monotonic
    /// time spent completing the operation.
    pub async fn resubmit_share(
        &self,
        server_url: &str,
        share_wire_json: &str,
        now_seconds: u64,
        cancel: &(dyn Fn() -> bool + Send + Sync),
    ) -> Result<ShareSubmissionStatus, HelperError> {
        let server_url = canonicalize_helper_base_url(server_url).map_err(invalid_request)?;
        let body = validate_share_body(share_wire_json)?;
        let request_started = tokio::time::Instant::now();
        let result = self
            .post_share(
                &server_url,
                body,
                cancel,
                true,
                self.config.post_timeout,
                None,
            )
            .await;
        self.score(&server_url, &result, now_seconds, request_started);
        result
    }

    #[allow(clippy::too_many_arguments)]
    async fn post_share(
        &self,
        server_url: &str,
        body: Vec<u8>,
        cancel: &(dyn Fn() -> bool + Send + Sync),
        single_attempt: bool,
        post_timeout: Duration,
        deadline: Option<tokio::time::Instant>,
    ) -> Result<ShareSubmissionStatus, HelperError> {
        let url = join_helper_url(server_url, &["shares"]).map_err(invalid_request)?;

        if single_attempt {
            if cancel() {
                return Err(HelperError::Cancelled);
            }
            return self
                .post_json(&url, body, post_timeout)
                .await
                .and_then(parse_submission_response);
        }

        self.with_retry(cancel, false, deadline, |remaining| {
            let url = url.clone();
            let body = body.clone();
            let attempt_timeout = remaining
                .map(|remaining| post_timeout.min(remaining))
                .unwrap_or(post_timeout);
            async move {
                let response = self.post_json(&url, body, attempt_timeout).await?;
                parse_submission_response(response)
            }
        })
        .await
    }

    /// Enforces the client deadline even when a custom transport ignores the
    /// timeout argument supplied through the trait.
    async fn get(
        &self,
        url: &str,
        timeout: Duration,
    ) -> Result<HelperResponse, HelperTransportError> {
        let deadline = tokio::time::Instant::now()
            .checked_add(timeout)
            .ok_or(HelperTransportError::Timeout)?;
        tokio::time::timeout_at(deadline, self.transport.get(url, timeout))
            .await
            .map_err(|_| HelperTransportError::Timeout)?
    }

    /// Enforces the client deadline around the complete custom transport
    /// future. A POST timeout remains outcome-unknown to the caller.
    async fn post_json(
        &self,
        url: &str,
        body: Vec<u8>,
        timeout: Duration,
    ) -> Result<HelperResponse, HelperError> {
        if timeout.is_zero() {
            return Err(HelperError::InvalidRequest {
                message: "share submission attempt timeout must be nonzero".to_string(),
            });
        }
        let deadline = tokio::time::Instant::now()
            .checked_add(timeout)
            .ok_or(HelperError::Transport(HelperTransportError::Timeout))?;
        tokio::time::timeout_at(deadline, self.transport.post_json(url, body, timeout))
            .await
            .map_err(|_| HelperError::Transport(HelperTransportError::Timeout))?
            .map_err(HelperError::Transport)
    }

    /// Runs `operation` with the configured backoff.
    ///
    /// `retry_ambiguous` decides whether an outcome-unknown failure counts as
    /// retryable on the same helper. It is true for idempotent reads and false
    /// for submissions.
    ///
    /// Before each attempt, `operation` receives the time remaining until
    /// `deadline`. An elapsed deadline before attempt zero returns
    /// [`HelperError::DeadlineExceeded`] without dispatching a request. A
    /// backoff sleep that would reach the deadline is skipped and the held
    /// error is returned instead: the caller cancels the whole future at that
    /// deadline, and a definite failure must not be converted into an unknown
    /// outcome by cancellation during a sleep.
    async fn with_retry<T, F, Fut>(
        &self,
        cancel: &(dyn Fn() -> bool + Send + Sync),
        retry_ambiguous: bool,
        deadline: Option<tokio::time::Instant>,
        operation: F,
    ) -> Result<T, HelperError>
    where
        F: Fn(Option<Duration>) -> Fut,
        Fut: std::future::Future<Output = Result<T, HelperError>>,
    {
        let attempts = self.config.retry_delays.len();
        let mut held_error = None;
        for attempt in 0..=attempts {
            if cancel() {
                return Err(HelperError::Cancelled);
            }
            let remaining = deadline
                .map(|deadline| deadline.saturating_duration_since(tokio::time::Instant::now()));
            if remaining.is_some_and(|remaining| remaining.is_zero()) {
                return Err(held_error.take().unwrap_or(HelperError::DeadlineExceeded));
            }
            match operation(remaining).await {
                Ok(value) => return Ok(value),
                Err(error) => {
                    let retryable =
                        error.is_transient() && (retry_ambiguous || !error.is_ambiguous());
                    if attempt == attempts || !retryable {
                        return Err(error);
                    }
                    if cancel() {
                        return Err(HelperError::Cancelled);
                    }
                    let delay = self.config.retry_delays[attempt];
                    let Some(wake_at) = tokio::time::Instant::now().checked_add(delay) else {
                        return Err(error);
                    };
                    if deadline.is_some_and(|deadline| wake_at >= deadline) {
                        return Err(error);
                    }
                    tokio::time::sleep_until(wake_at).await;
                    if cancel() {
                        return Err(HelperError::Cancelled);
                    }
                    held_error = Some(error);
                }
            }
        }
        // The loop above always returns; this keeps the compiler happy without
        // an unreachable panic in a network path.
        Err(HelperError::Decode {
            message: "helper retry loop exited without a result".to_string(),
        })
    }

    /// Applies one request's outcome to the helper's health score.
    ///
    /// A cancellation or pre-dispatch deadline is not the helper's fault and is
    /// not scored. Failure timestamps use completion time so slow requests do
    /// not consume their own cooldown while still in flight.
    fn score<T>(
        &self,
        server_url: &str,
        result: &Result<T, HelperError>,
        now_seconds: u64,
        request_started: tokio::time::Instant,
    ) {
        match result {
            Ok(_) => self.health.record_success(server_url),
            Err(
                HelperError::InvalidRequest { .. }
                | HelperError::Cancelled
                | HelperError::DeadlineExceeded,
            ) => {}
            Err(_) => self.health.record_failure(
                server_url,
                now_seconds.saturating_add(request_started.elapsed().as_secs()),
            ),
        }
    }
}

fn validate_share_body(share_wire_json: &str) -> Result<Vec<u8>, HelperError> {
    // Parse into the closed wire schema before health scoring or network I/O.
    // Re-serialization ensures the transport receives only approved fields.
    let share =
        VoteShareWire::from_json(share_wire_json).map_err(|_| HelperError::InvalidRequest {
            message: "share body does not match the vote-share wire schema".to_string(),
        })?;
    share
        .to_json()
        .map(String::into_bytes)
        .map_err(|_| HelperError::InvalidRequest {
            message: "share body does not match the vote-share wire schema".to_string(),
        })
}

fn invalid_request(error: VotingError) -> HelperError {
    HelperError::InvalidRequest {
        message: error.to_string(),
    }
}

fn require_success(response: HelperResponse) -> Result<HelperResponse, HelperError> {
    if response.is_success() {
        return Ok(response);
    }
    Err(HelperError::Status {
        status: response.status(),
    })
}

fn validate_json_response(response: &HelperResponse) -> Result<(), HelperError> {
    if response.body().len() > MAX_HELPER_RESPONSE_BYTES {
        return Err(HelperError::Decode {
            message: format!("helper response exceeds {MAX_HELPER_RESPONSE_BYTES} byte limit"),
        });
    }
    let is_json = response.content_type().is_some_and(|content_type| {
        content_type
            .split(';')
            .next()
            .is_some_and(|media_type| media_type.trim().eq_ignore_ascii_case("application/json"))
    });
    if !is_json {
        return Err(HelperError::Decode {
            message: "helper response Content-Type must be application/json".to_string(),
        });
    }
    Ok(())
}

fn json_field(response: &HelperResponse, field: &str) -> Option<String> {
    if response.body().len() > MAX_HELPER_RESPONSE_BYTES {
        return None;
    }
    let value: Value = serde_json::from_slice(response.body()).ok()?;
    value.get(field)?.as_str().map(str::to_string)
}

fn parse_share_status(response: &HelperResponse) -> Result<ShareStatus, HelperError> {
    match json_field(response, "status").as_deref() {
        Some("confirmed") => Ok(ShareStatus::Confirmed),
        Some("pending") => Ok(ShareStatus::Pending),
        // The endpoint has only the two global confirmation states. Anything
        // else is a broken or incompatible response.
        Some(_) => Err(HelperError::Decode {
            message: "unexpected helper share status".to_string(),
        }),
        None => Err(HelperError::Decode {
            message: "helper share status response has no status field".to_string(),
        }),
    }
}

fn parse_submission_response(
    response: HelperResponse,
) -> Result<ShareSubmissionStatus, HelperError> {
    let response = require_success(response)?;
    validate_json_response(&response).map_err(|error| {
        HelperError::AmbiguousSubmissionResponse {
            message: error.to_string(),
        }
    })?;
    match json_field(&response, "status").as_deref() {
        Some("queued") => Ok(ShareSubmissionStatus::Queued),
        Some("duplicate") => Ok(ShareSubmissionStatus::Duplicate),
        Some(_) => Err(HelperError::AmbiguousSubmissionResponse {
            message: "unexpected helper share submit status".to_string(),
        }),
        None => Err(HelperError::AmbiguousSubmissionResponse {
            message: "helper share submit response has no status field".to_string(),
        }),
    }
}

/// Normalizes a vote round id to the lowercase hex form used in helper routes.
///
/// Accepts 64 hex characters or a 32-byte base64 string, matching what wallet
/// config and vote-server responses may carry. The decoded bytes must be a
/// canonical Pallas base-field element, matching the voting-circuit round-id
/// representation.
pub fn normalize_round_id(value: &str) -> Result<String, VotingError> {
    use base64::Engine as _;

    let trimmed = value.trim();
    if trimmed.len() == 64 && trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
        let bytes = hex::decode(trimmed).map_err(|error| VotingError::InvalidInput {
            message: format!("round_id is not valid hex: {error}"),
        })?;
        validate_vote_round_id_bytes(&bytes)?;
        return Ok(hex::encode(bytes));
    }
    if let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(trimmed) {
        if bytes.len() == 32 {
            validate_vote_round_id_bytes(&bytes)?;
            return Ok(hex::encode(bytes));
        }
    }
    Err(VotingError::InvalidInput {
        message: "round_id must be 64 hex characters or a 32-byte base64 string".to_string(),
    })
}

/// Validates and normalizes a 32-byte hex path segment.
///
/// Share ids reach this client from persisted state and go straight into a URL
/// path. Restricting them to hex keeps a corrupted or hostile value from
/// escaping its segment.
fn validate_hex_path_segment(value: &str, field: &str) -> Result<String, VotingError> {
    let trimmed = value.trim();
    if trimmed.len() == 64 && trimmed.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(trimmed.to_ascii_lowercase());
    }
    Err(VotingError::InvalidInput {
        message: format!("{field} must be 64 hex characters"),
    })
}

/// API path prefix every vote-sdk helper endpoint lives under.
///
/// Configured helper URLs are bare origins (optionally with a mount path), so
/// the prefix belongs here rather than in each wallet's configuration.
const HELPER_API_PREFIX: [&str; 2] = ["shielded-vote", "v1"];

/// Appends the API prefix and path segments to a helper base URL.
///
/// Any path already present on the base URL is preserved, so a helper mounted
/// under a sub-path keeps it.
fn join_helper_url(base_url: &str, segments: &[&str]) -> Result<String, VotingError> {
    let mut url = canonicalize_helper_base_url(base_url)?;
    for segment in HELPER_API_PREFIX.iter().chain(segments.iter()) {
        url.push('/');
        url.push_str(segment);
    }
    Ok(url)
}

#[cfg(test)]
mod tests {
    use std::{
        collections::{HashMap, VecDeque},
        sync::Mutex,
    };

    use base64::Engine as _;

    use super::*;
    use crate::{
        backend::pasta_curves::{
            group::{ff::PrimeField, Group, GroupEncoding},
            pallas,
        },
        helper::transport::HelperFuture,
    };

    type Reply = Result<HelperResponse, HelperTransportError>;

    #[derive(Default)]
    struct MockTransport {
        gets: Mutex<HashMap<String, VecDeque<Reply>>>,
        posts: Mutex<HashMap<String, VecDeque<Reply>>>,
        calls: Mutex<Vec<String>>,
        timeouts: Mutex<Vec<(String, Duration)>>,
        get_delays: Mutex<HashMap<String, VecDeque<Duration>>>,
        post_delays: Mutex<HashMap<String, VecDeque<Duration>>>,
    }

    impl MockTransport {
        fn queue_get(&self, url: &str, reply: Reply) {
            self.gets
                .lock()
                .unwrap()
                .entry(url.to_string())
                .or_default()
                .push_back(reply);
        }

        fn queue_post(&self, url: &str, reply: Reply) {
            self.posts
                .lock()
                .unwrap()
                .entry(url.to_string())
                .or_default()
                .push_back(reply);
        }

        fn queue_get_after(&self, url: &str, delay: Duration, reply: Reply) {
            self.queue_get(url, reply);
            self.get_delays
                .lock()
                .unwrap()
                .entry(url.to_string())
                .or_default()
                .push_back(delay);
        }

        fn queue_post_after(&self, url: &str, delay: Duration, reply: Reply) {
            self.queue_post(url, reply);
            self.post_delays
                .lock()
                .unwrap()
                .entry(url.to_string())
                .or_default()
                .push_back(delay);
        }

        fn call_count(&self, needle: &str) -> usize {
            self.calls
                .lock()
                .unwrap()
                .iter()
                .filter(|call| call.contains(needle))
                .count()
        }

        fn timeout_for(&self, url: &str) -> Duration {
            self.timeouts
                .lock()
                .unwrap()
                .iter()
                .find(|(requested_url, _)| requested_url == url)
                .map(|(_, timeout)| *timeout)
                .unwrap_or_else(|| panic!("no request recorded for {url}"))
        }

        fn timeouts_for(&self, url: &str) -> Vec<Duration> {
            self.timeouts
                .lock()
                .unwrap()
                .iter()
                .filter_map(|(requested_url, timeout)| (requested_url == url).then_some(*timeout))
                .collect()
        }

        fn take(
            &self,
            table: &Mutex<HashMap<String, VecDeque<Reply>>>,
            method: &str,
            url: &str,
        ) -> Reply {
            self.calls.lock().unwrap().push(format!("{method} {url}"));
            table
                .lock()
                .unwrap()
                .get_mut(url)
                .and_then(VecDeque::pop_front)
                .unwrap_or_else(|| {
                    Err(HelperTransportError::Transport(format!(
                        "no canned {method} response for {url}"
                    )))
                })
        }
    }

    impl HelperTransport for MockTransport {
        fn get<'a>(&'a self, url: &'a str, timeout: Duration) -> HelperFuture<'a> {
            self.timeouts
                .lock()
                .unwrap()
                .push((url.to_string(), timeout));
            let delay = self
                .get_delays
                .lock()
                .unwrap()
                .get_mut(url)
                .and_then(VecDeque::pop_front)
                .unwrap_or_default();
            let reply = self.take(&self.gets, "GET", url);
            Box::pin(async move {
                tokio::time::sleep(delay).await;
                reply
            })
        }

        fn post_json<'a>(
            &'a self,
            url: &'a str,
            _body: Vec<u8>,
            timeout: Duration,
        ) -> HelperFuture<'a> {
            self.timeouts
                .lock()
                .unwrap()
                .push((url.to_string(), timeout));
            let delay = self
                .post_delays
                .lock()
                .unwrap()
                .get_mut(url)
                .and_then(VecDeque::pop_front)
                .unwrap_or_default();
            let reply = self.take(&self.posts, "POST", url);
            Box::pin(async move {
                tokio::time::sleep(delay).await;
                reply
            })
        }
    }

    fn helper() -> &'static str {
        "https://helper.example"
    }

    fn status_url() -> String {
        format!(
            "{}/shielded-vote/v1/share-status/{}/{}",
            helper(),
            "01".repeat(32),
            "cd".repeat(32)
        )
    }

    fn post_url() -> String {
        format!("{}/shielded-vote/v1/shares", helper())
    }

    fn json_status(status: &str) -> Reply {
        Ok(HelperResponse::json(
            200,
            format!(r#"{{"status":"{status}"}}"#).into_bytes(),
        ))
    }

    fn http_status(status: u16) -> Reply {
        Ok(HelperResponse::json(status, b"{}".to_vec()))
    }

    fn encoded_point(multiplier: u64) -> Vec<u8> {
        (pallas::Point::generator() * pallas::Scalar::from(multiplier))
            .to_bytes()
            .to_vec()
    }

    fn encoded_field(value: u64) -> String {
        base64::engine::general_purpose::STANDARD.encode(pallas::Base::from(value).to_repr())
    }

    fn valid_share_json() -> String {
        VoteShareWire {
            vote_round_id: "01".repeat(32),
            shares_hash: encoded_field(1),
            proposal_id: 1,
            vote_decision: 0,
            encrypted_share: crate::WireEncryptedShare {
                c1: encoded_point(2),
                c2: encoded_point(3),
                share_index: 0,
            },
            share_index: 0,
            vc_tree_position: 1,
            share_comms: (0..crate::share_policy::VOTE_COMMITMENT_SHARE_COUNT)
                .map(|index| encoded_field(index as u64 + 10))
                .collect(),
            primary_blind: encoded_field(4),
            submit_at: 0,
        }
        .to_json()
        .unwrap()
    }

    fn client_with(transport: Arc<MockTransport>) -> HelperClient {
        HelperClient::new(transport, HelperHealth::default())
    }

    fn never_cancel() -> impl Fn() -> bool {
        || false
    }

    #[test]
    fn round_id_accepts_hex_and_base64() {
        let bytes = pallas::Base::from(10).to_repr();
        let hex_id = hex::encode(bytes).to_uppercase();
        assert_eq!(normalize_round_id(&hex_id).unwrap(), hex::encode(bytes));

        use base64::Engine as _;
        let base64_id = base64::engine::general_purpose::STANDARD.encode(bytes);
        assert_eq!(normalize_round_id(&base64_id).unwrap(), hex::encode(bytes));
    }

    #[test]
    fn round_id_rejects_other_encodings() {
        assert!(normalize_round_id("not-a-round").is_err());
        assert!(normalize_round_id(&"ab".repeat(16)).is_err());
        assert!(normalize_round_id(&"ff".repeat(32)).is_err());
        let noncanonical_base64 = base64::engine::general_purpose::STANDARD.encode([0xff_u8; 32]);
        assert!(normalize_round_id(&noncanonical_base64).is_err());
    }

    #[test]
    fn helper_config_rejects_invalid_durations_and_excessive_retries() {
        assert!(HelperClientConfig::default()
            .with_post_timeout(Duration::ZERO)
            .is_err());
        assert!(HelperClientConfig::default()
            .with_request_timeout(Duration::ZERO)
            .is_err());
        assert!(HelperClientConfig::default()
            .with_preflight_timeouts(Duration::ZERO, Duration::from_secs(1))
            .is_err());
        assert!(HelperClientConfig::default()
            .with_preflight_timeouts(Duration::from_secs(1), Duration::ZERO)
            .is_err());
        assert!(HelperClientConfig::default()
            .with_preflight_timeouts(Duration::from_secs(2), Duration::from_secs(1))
            .is_err());
        assert!(HelperClientConfig::default()
            .with_retry_delays(vec![Duration::from_millis(1); 3])
            .is_err());
        assert!(HelperClientConfig::default()
            .with_retry_delays(vec![Duration::ZERO])
            .is_err());
        assert!(HelperClientConfig::default()
            .with_post_timeout(Duration::MAX)
            .is_err());
        assert!(HelperClientConfig::default()
            .with_request_timeout(Duration::MAX)
            .is_err());
        assert!(HelperClientConfig::default()
            .with_preflight_timeouts(Duration::from_secs(1), Duration::MAX)
            .is_err());
        assert!(HelperClientConfig::default()
            .with_preflight_timeouts(Duration::MAX, Duration::MAX)
            .is_err());
        assert!(HelperClientConfig::default()
            .with_retry_delays(vec![Duration::MAX])
            .is_err());

        HelperClientConfig::default()
            .with_request_timeout(Duration::from_secs(1))
            .unwrap()
            .with_post_timeout(Duration::from_secs(1))
            .unwrap()
            .with_preflight_timeouts(Duration::from_secs(1), Duration::from_secs(2))
            .unwrap()
            .with_retry_delays(vec![Duration::from_millis(1)])
            .unwrap();
    }

    #[test]
    fn hex_path_segment_rejects_traversal() {
        assert!(validate_hex_path_segment("../../admin", "share_id").is_err());
        assert!(validate_hex_path_segment("", "share_id").is_err());
        assert!(validate_hex_path_segment("00FF", "share_id").is_err());
        assert!(validate_hex_path_segment(&"ab".repeat(33), "share_id").is_err());
        assert_eq!(
            validate_hex_path_segment(&"00FF".repeat(16), "share_id").unwrap(),
            "00ff".repeat(16)
        );
    }

    #[test]
    fn url_join_preserves_base_path() {
        assert_eq!(
            join_helper_url("https://helper.example", &["shares"]).unwrap(),
            "https://helper.example/shielded-vote/v1/shares"
        );
        assert_eq!(
            join_helper_url("https://helper.example", &["share-status", "ab", "cd"]).unwrap(),
            "https://helper.example/shielded-vote/v1/share-status/ab/cd"
        );
        // A helper mounted under a sub-path keeps it.
        assert_eq!(
            join_helper_url("https://helper.example/vote/", &["shares"]).unwrap(),
            "https://helper.example/vote/shielded-vote/v1/shares"
        );
    }

    #[test]
    fn url_join_rejects_non_http_schemes() {
        assert!(join_helper_url("file:///etc/passwd", &["shares"]).is_err());
        assert!(join_helper_url("", &["shares"]).is_err());
    }

    #[test]
    fn out_of_protocol_status_is_a_decode_failure_not_a_state() {
        let response = HelperResponse::json(200, br#"{"status":"not_found"}"#.to_vec());
        let error = parse_share_status(&response).unwrap_err();
        assert!(matches!(error, HelperError::Decode { .. }));
        // Decode failures are not transient: repeating an incompatible answer
        // does not provide a usable confirmation state.
        assert!(!error.is_transient());
        assert!(!error.is_ambiguous());
    }

    #[test]
    fn transient_classification_matches_helper_retry_rules() {
        assert!(HelperError::Transport(HelperTransportError::Timeout).is_transient());
        assert!(HelperError::Transport(HelperTransportError::Timeout).is_ambiguous());
        let response_failure =
            HelperError::Transport(HelperTransportError::Response("truncated body".to_string()));
        assert!(response_failure.is_transient());
        assert!(response_failure.is_ambiguous());
        let unusable_submission = HelperError::AmbiguousSubmissionResponse {
            message: "missing status".to_string(),
        };
        assert!(!unusable_submission.is_transient());
        assert!(unusable_submission.is_ambiguous());
        for status in [429u16, 500, 502, 503, 504] {
            let error = HelperError::Status { status };
            assert!(error.is_transient());
            assert_eq!(error.is_ambiguous(), status != 429);
        }
        for status in [400u16, 404, 409, 507, 508] {
            let error = HelperError::Status { status };
            assert!(!error.is_transient());
            assert_eq!(error.is_ambiguous(), (500..=599).contains(&status));
        }
        for status in 500u16..=599 {
            assert!(HelperError::Status { status }.is_ambiguous());
        }
        for status in [429u16, 499, 600] {
            assert!(!HelperError::Status { status }.is_ambiguous());
        }
        assert!(!HelperError::DeadlineExceeded.is_transient());
        assert!(!HelperError::DeadlineExceeded.is_ambiguous());
        assert!(!HelperError::Cancelled.is_transient());
    }

    #[test]
    fn oversized_http_error_keeps_status_semantics_without_formatting_the_body() {
        let error = require_success(HelperResponse::json(
            503,
            vec![b'x'; MAX_HELPER_RESPONSE_BYTES + 1],
        ))
        .unwrap_err();

        assert!(error.is_transient());
        assert!(error.is_ambiguous());
        match error {
            HelperError::Status { status } => assert_eq!(status, 503),
            other => panic!("unexpected error: {other}"),
        }
    }

    #[test]
    fn helper_controlled_diagnostics_are_not_exposed() {
        let reflected_secret = "primary_blind=wallet-secret";
        let status_error = require_success(HelperResponse::json(
            400,
            format!("first line\n\u{1b}[31m{reflected_secret}\u{1b}[0m").into_bytes(),
        ))
        .unwrap_err();
        let rendered = status_error.to_string();
        assert_eq!(rendered, "helper returned HTTP 400");
        assert!(!rendered.contains(reflected_secret));
        assert!(!rendered.contains('\n'));
        assert!(!rendered.contains('\u{1b}'));

        let attacker_status = format!("{reflected_secret}{}", "x".repeat(8_192));
        let response = HelperResponse::json(
            200,
            serde_json::to_vec(&serde_json::json!({ "status": attacker_status })).unwrap(),
        );
        let status_error = parse_share_status(&response).unwrap_err();
        let rendered = status_error.to_string();
        assert_eq!(
            rendered,
            "helper response was not usable: unexpected helper share status"
        );
        assert!(!rendered.contains(reflected_secret));

        let submission_error = parse_submission_response(response).unwrap_err();
        let rendered = submission_error.to_string();
        assert_eq!(
            rendered,
            "helper submission outcome is unknown: unexpected helper share submit status"
        );
        assert!(!rendered.contains(reflected_secret));
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_canonicalizes_urls_and_requires_json_ok() {
        let transport = Arc::new(MockTransport::default());
        transport.queue_get(
            "https://helper.example/shielded-vote/v1/status",
            json_status("OK"),
        );
        transport.queue_get(
            "https://not-ready.example/shielded-vote/v1/status",
            Ok(HelperResponse::new(
                200,
                br#"{"status":"ok"}"#.to_vec(),
                Some("text/plain".to_string()),
            )),
        );
        let client = client_with(transport.clone());

        let results = client
            .preflight(
                &[
                    "https://helper.example/".to_string(),
                    "file:///etc/passwd".to_string(),
                    "https://not-ready.example".to_string(),
                ],
                1,
            )
            .await;

        assert_eq!(
            results,
            vec![
                ("https://helper.example".to_string(), true),
                ("file:///etc/passwd".to_string(), false),
                ("https://not-ready.example".to_string(), false),
            ]
        );
        assert_eq!(transport.call_count("GET"), 2);
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_keeps_slow_probes_alive_until_the_target_is_ready() {
        let transport = Arc::new(MockTransport::default());
        let url = "https://slow.example/shielded-vote/v1/status";
        transport.queue_get_after(url, Duration::from_secs(3), json_status("ok"));
        let config = HelperClientConfig::default()
            .with_preflight_timeouts(Duration::from_secs(2), Duration::from_secs(5))
            .unwrap();
        let client = HelperClient::with_config(transport, HelperHealth::default(), config);
        let started = tokio::time::Instant::now();

        let results = client
            .preflight(&["https://slow.example".to_string()], 1)
            .await;

        assert_eq!(results, vec![("https://slow.example".to_string(), true)]);
        assert_eq!(started.elapsed(), Duration::from_secs(3));
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_counts_equivalent_urls_as_one_ready_helper() {
        let transport = Arc::new(MockTransport::default());
        let canonical_url = "https://helper.example/shielded-vote/v1/status";
        let slow_url = "https://slow.example/shielded-vote/v1/status";
        // The second canned reply makes the old duplicate-probe behavior
        // falsely satisfy the target at the soft deadline.
        transport.queue_get(canonical_url, json_status("ok"));
        transport.queue_get(canonical_url, json_status("ok"));
        transport.queue_get_after(slow_url, Duration::from_secs(3), json_status("ok"));
        let config = HelperClientConfig::default()
            .with_preflight_timeouts(Duration::from_secs(2), Duration::from_secs(5))
            .unwrap();
        let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);
        let started = tokio::time::Instant::now();

        let results = client
            .preflight(
                &[
                    "https://helper.example".to_string(),
                    "https://helper.example/".to_string(),
                    "https://slow.example".to_string(),
                ],
                2,
            )
            .await;

        assert_eq!(
            results,
            vec![
                ("https://helper.example".to_string(), true),
                ("https://helper.example".to_string(), true),
                ("https://slow.example".to_string(), true),
            ]
        );
        assert_eq!(transport.call_count(canonical_url), 1);
        assert_eq!(started.elapsed(), Duration::from_secs(3));
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_stops_at_the_soft_window_when_enough_helpers_are_ready() {
        let transport = Arc::new(MockTransport::default());
        transport.queue_get(
            "https://fast.example/shielded-vote/v1/status",
            json_status("ok"),
        );
        transport.queue_get_after(
            "https://slow.example/shielded-vote/v1/status",
            Duration::from_secs(4),
            json_status("ok"),
        );
        let config = HelperClientConfig::default()
            .with_preflight_timeouts(Duration::from_secs(2), Duration::from_secs(5))
            .unwrap();
        let client = HelperClient::with_config(transport, HelperHealth::default(), config);
        let started = tokio::time::Instant::now();

        let results = client
            .preflight(
                &[
                    "https://fast.example".to_string(),
                    "https://slow.example".to_string(),
                ],
                1,
            )
            .await;

        assert_eq!(
            results,
            vec![
                ("https://fast.example".to_string(), true),
                ("https://slow.example".to_string(), false),
            ]
        );
        assert_eq!(started.elapsed(), Duration::from_secs(2));
    }

    #[tokio::test(start_paused = true)]
    async fn preflight_stops_slow_helpers_at_the_hard_deadline() {
        let transport = Arc::new(MockTransport::default());
        transport.queue_get_after(
            "https://slow.example/shielded-vote/v1/status",
            Duration::from_secs(6),
            json_status("ok"),
        );
        let config = HelperClientConfig::default()
            .with_preflight_timeouts(Duration::from_secs(2), Duration::from_secs(5))
            .unwrap();
        let client = HelperClient::with_config(transport, HelperHealth::default(), config);
        let started = tokio::time::Instant::now();

        let results = client
            .preflight(&["https://slow.example".to_string()], 1)
            .await;

        assert_eq!(results, vec![("https://slow.example".to_string(), false)]);
        assert_eq!(started.elapsed(), Duration::from_secs(5));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn preflight_with_zero_target_does_not_open_connections() {
        let transport = Arc::new(MockTransport::default());
        let client = client_with(transport.clone());
        let mut server_urls = vec!["file:///etc/passwd".to_string()];
        server_urls.extend((0..256).map(|index| format!("HTTPS://HELPER-{index}.EXAMPLE/")));

        let results = client.preflight(&server_urls, 0).await;

        assert_eq!(results.len(), server_urls.len());
        assert_eq!(results[0], ("file:///etc/passwd".to_string(), false));
        assert_eq!(results[1], ("https://helper-0.example".to_string(), false));
        assert_eq!(
            results.last(),
            Some(&("https://helper-255.example".to_string(), false))
        );
        assert_eq!(transport.call_count("GET"), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn share_status_retries_transient_gets_and_scores_final_success() {
        let transport = Arc::new(MockTransport::default());
        let url = status_url();
        transport.queue_get(&url, http_status(503));
        transport.queue_get(&url, json_status("pending"));
        let client = client_with(transport.clone());

        let status = client
            .share_status(
                helper(),
                &"01".repeat(32),
                &"cd".repeat(32),
                10,
                &never_cancel(),
            )
            .await
            .unwrap();

        assert_eq!(status, ShareStatus::Pending);
        assert_eq!(transport.call_count(&url), 2);
        assert_eq!(client.health().failure_count(helper()), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn local_route_validation_is_invalid_request_without_dispatch_or_scoring() {
        let transport = Arc::new(MockTransport::default());
        let client = client_with(transport.clone());

        let status_errors = [
            client
                .share_status(
                    "file:///tmp/helper",
                    &"01".repeat(32),
                    &"cd".repeat(32),
                    10,
                    &never_cancel(),
                )
                .await
                .unwrap_err(),
            client
                .share_status(
                    helper(),
                    &"ff".repeat(32),
                    &"cd".repeat(32),
                    10,
                    &never_cancel(),
                )
                .await
                .unwrap_err(),
            client
                .share_status(helper(), &"01".repeat(32), "../share", 10, &never_cancel())
                .await
                .unwrap_err(),
        ];
        for error in status_errors {
            assert!(matches!(error, HelperError::InvalidRequest { .. }));
        }

        let submit_error = client
            .submit_share(
                "file:///tmp/helper",
                &valid_share_json(),
                10,
                &never_cancel(),
            )
            .await
            .unwrap_err();
        assert!(matches!(submit_error, HelperError::InvalidRequest { .. }));

        let resubmit_error = client
            .resubmit_share(
                "file:///tmp/helper",
                &valid_share_json(),
                10,
                &never_cancel(),
            )
            .await
            .unwrap_err();
        assert!(matches!(resubmit_error, HelperError::InvalidRequest { .. }));

        assert_eq!(transport.call_count("GET"), 0);
        assert_eq!(transport.call_count("POST"), 0);
        assert_eq!(client.health().failure_count(helper()), 0);
        assert_eq!(client.health().failure_count("file:///tmp/helper"), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn submit_retries_definite_throttling_but_not_ambiguous_failures() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post(&url, http_status(429));
        transport.queue_post(&url, json_status("queued"));
        let client = client_with(transport.clone());

        let status = client
            .submit_share(helper(), &valid_share_json(), 10, &never_cancel())
            .await
            .unwrap();

        assert_eq!(status, ShareSubmissionStatus::Queued);
        assert_eq!(transport.call_count(&url), 2);

        for error in [
            HelperTransportError::Timeout,
            HelperTransportError::Response("response body ended early".to_string()),
        ] {
            let transport = Arc::new(MockTransport::default());
            transport.queue_post(&url, Err(error));
            transport.queue_post(&url, json_status("queued"));
            let client = client_with(transport.clone());

            let error = client
                .submit_share(helper(), &valid_share_json(), 10, &never_cancel())
                .await
                .unwrap_err();

            assert!(error.is_ambiguous());
            assert_eq!(transport.call_count(&url), 1);
        }

        let transport = Arc::new(MockTransport::default());
        transport.queue_post(&url, http_status(503));
        transport.queue_post(&url, json_status("queued"));
        let client = client_with(transport.clone());

        let error = client
            .submit_share(helper(), &valid_share_json(), 10, &never_cancel())
            .await
            .unwrap_err();

        assert!(matches!(error, HelperError::Status { status: 503, .. }));
        assert!(error.is_ambiguous());
        assert_eq!(transport.call_count(&url), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn unusable_successful_submission_is_ambiguous_and_not_retried() {
        for (body, content_type) in [
            (b"not json".to_vec(), Some("application/json".to_string())),
            (br#"{}"#.to_vec(), Some("application/json".to_string())),
            (
                br#"{"status":"accepted"}"#.to_vec(),
                Some("application/json".to_string()),
            ),
            (br#"{"status":"queued"}"#.to_vec(), None),
            (
                br#"{"status":"queued"}"#.to_vec(),
                Some("text/plain".to_string()),
            ),
            (
                vec![b' '; MAX_HELPER_RESPONSE_BYTES + 1],
                Some("application/json".to_string()),
            ),
        ] {
            let transport = Arc::new(MockTransport::default());
            let url = post_url();
            transport.queue_post(&url, Ok(HelperResponse::new(200, body, content_type)));
            transport.queue_post(&url, json_status("queued"));
            let client = client_with(transport.clone());

            let error = client
                .submit_share(helper(), &valid_share_json(), 10, &never_cancel())
                .await
                .unwrap_err();

            assert!(matches!(
                error,
                HelperError::AmbiguousSubmissionResponse { .. }
            ));
            assert_eq!(transport.call_count(&url), 1);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn late_cancellation_preserves_ambiguous_submission_errors() {
        for reply in [
            Err(HelperTransportError::Timeout),
            Err(HelperTransportError::Response(
                "response body ended early".to_string(),
            )),
            http_status(503),
        ] {
            let transport = Arc::new(MockTransport::default());
            let url = post_url();
            transport.queue_post(&url, reply);
            transport.queue_post(&url, json_status("queued"));
            let cancel_after_request = || transport.call_count(&url) > 0;
            let client = client_with(transport.clone());

            let error = client
                .submit_share(helper(), &valid_share_json(), 10, &cancel_after_request)
                .await
                .unwrap_err();

            assert!(error.is_ambiguous());
            assert_eq!(transport.call_count(&url), 1);
            assert_eq!(client.health().failure_count(helper()), 1);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn cancellation_suppresses_a_pending_retry() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post(&url, http_status(429));
        transport.queue_post(&url, json_status("queued"));
        let cancel_after_request = || transport.call_count(&url) > 0;
        let client = client_with(transport.clone());

        let error = client
            .submit_share(helper(), &valid_share_json(), 10, &cancel_after_request)
            .await
            .unwrap_err();

        assert!(matches!(error, HelperError::Cancelled));
        assert_eq!(transport.call_count(&url), 1);
        assert_eq!(client.health().failure_count(helper()), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn cancellation_before_request_is_not_scored() {
        let transport = Arc::new(MockTransport::default());
        let client = client_with(transport.clone());
        let always_cancel = || true;

        let error = client
            .share_status(
                helper(),
                &"01".repeat(32),
                &"cd".repeat(32),
                10,
                &always_cancel,
            )
            .await
            .unwrap_err();

        assert!(matches!(error, HelperError::Cancelled));
        assert_eq!(transport.call_count("GET"), 0);
        assert_eq!(client.health().failure_count(helper()), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn resubmit_makes_one_attempt_and_preserves_its_result() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post(&url, Err(HelperTransportError::Timeout));
        transport.queue_post(&url, json_status("queued"));
        let cancel_after_request = || transport.call_count(&url) > 0;
        let client = client_with(transport.clone());

        let error = client
            .resubmit_share(helper(), &valid_share_json(), 10, &cancel_after_request)
            .await
            .unwrap_err();

        assert!(error.is_ambiguous());
        assert_eq!(transport.call_count(&url), 1);
        assert_eq!(client.health().failure_count(helper()), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn client_enforces_deadline_when_custom_transport_ignores_it() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post_after(&url, Duration::from_secs(2), json_status("queued"));
        let config = HelperClientConfig::default()
            .with_post_timeout(Duration::from_secs(1))
            .unwrap()
            .without_retries();
        let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);
        let started = tokio::time::Instant::now();

        let error = client
            .submit_share(helper(), &valid_share_json(), 10, &never_cancel())
            .await
            .unwrap_err();

        assert!(matches!(
            error,
            HelperError::Transport(HelperTransportError::Timeout)
        ));
        assert_eq!(started.elapsed(), Duration::from_secs(1));
        assert_eq!(transport.call_count(&url), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn slow_failure_starts_health_cooldown_at_completion() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post_after(&url, Duration::ZERO, http_status(400));
        transport.queue_post_after(&url, Duration::ZERO, http_status(400));
        transport.queue_post_after(&url, Duration::from_secs(31), json_status("queued"));
        let config = HelperClientConfig::default()
            .with_post_timeout(Duration::from_secs(30))
            .unwrap();
        let client = HelperClient::with_config(transport, HelperHealth::default(), config);

        for _ in 0..2 {
            client
                .submit_share(helper(), &valid_share_json(), 100, &never_cancel())
                .await
                .unwrap_err();
        }
        let started = tokio::time::Instant::now();
        let error = client
            .submit_share(helper(), &valid_share_json(), 100, &never_cancel())
            .await
            .unwrap_err();

        assert!(matches!(
            error,
            HelperError::Transport(HelperTransportError::Timeout)
        ));
        assert_eq!(started.elapsed(), Duration::from_secs(30));
        let servers = vec![helper().to_string(), "https://healthy.example".to_string()];
        assert_eq!(
            client.health().candidate_servers(&servers, 130),
            vec!["https://healthy.example".to_string(), helper().to_string()]
        );
        assert_eq!(
            client.health().candidate_servers(&servers, 159),
            vec!["https://healthy.example".to_string(), helper().to_string(),]
        );
        assert_eq!(client.health().candidate_servers(&servers, 160), servers);
    }

    #[tokio::test(start_paused = true)]
    async fn expired_delivery_deadline_does_not_dispatch_or_score() {
        let transport = Arc::new(MockTransport::default());
        let client = client_with(transport.clone());

        let error = client
            .submit_share_with_timeout(
                helper(),
                &valid_share_json(),
                10,
                &never_cancel(),
                Duration::from_secs(1),
                Some(tokio::time::Instant::now()),
            )
            .await
            .unwrap_err();

        assert!(matches!(error, HelperError::DeadlineExceeded));
        assert!(!error.is_ambiguous());
        assert_eq!(transport.call_count("POST"), 0);
        assert_eq!(client.health().failure_count(helper()), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn zero_submission_timeout_does_not_dispatch_or_score() {
        let transport = Arc::new(MockTransport::default());
        let client = client_with(transport.clone());

        let error = client
            .submit_share_with_timeout(
                helper(),
                &valid_share_json(),
                10,
                &never_cancel(),
                Duration::ZERO,
                Some(tokio::time::Instant::now() + Duration::from_secs(1)),
            )
            .await
            .unwrap_err();

        assert!(matches!(error, HelperError::InvalidRequest { .. }));
        assert!(!error.is_ambiguous());
        assert_eq!(transport.call_count("POST"), 0);
        assert_eq!(client.health().failure_count(helper()), 0);

        let error = client
            .post_json(&post_url(), valid_share_json().into_bytes(), Duration::ZERO)
            .await
            .unwrap_err();
        assert!(matches!(error, HelperError::InvalidRequest { .. }));
        assert_eq!(transport.call_count("POST"), 0);
    }

    #[tokio::test(start_paused = true)]
    async fn every_retry_is_capped_to_the_remaining_delivery_deadline() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post_after(
            &url,
            Duration::from_secs(1),
            Err(HelperTransportError::Transport(
                "connect refused".to_string(),
            )),
        );
        transport.queue_post_after(&url, Duration::from_secs(5), json_status("queued"));
        let config = HelperClientConfig::default()
            .with_post_timeout(Duration::from_secs(10))
            .unwrap()
            .with_retry_delays(vec![Duration::from_millis(200)])
            .unwrap();
        let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);
        let started = tokio::time::Instant::now();
        let deadline = started + Duration::from_secs(3);

        let error = client
            .submit_share_with_timeout(
                helper(),
                &valid_share_json(),
                10,
                &never_cancel(),
                Duration::from_secs(10),
                Some(deadline),
            )
            .await
            .unwrap_err();

        assert!(matches!(
            error,
            HelperError::Transport(HelperTransportError::Timeout)
        ));
        assert_eq!(started.elapsed(), Duration::from_secs(3));
        assert_eq!(
            transport.timeouts_for(&url),
            vec![Duration::from_secs(3), Duration::from_millis(1_800)]
        );
    }

    #[tokio::test(start_paused = true)]
    async fn retry_backoff_does_not_turn_a_definite_failure_ambiguous() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post_after(
            &url,
            Duration::from_millis(2_900),
            Err(HelperTransportError::Transport(
                "connect refused".to_string(),
            )),
        );
        transport.queue_post(&url, json_status("queued"));
        let config = HelperClientConfig::default()
            .with_post_timeout(Duration::from_secs(10))
            .unwrap()
            .with_retry_delays(vec![Duration::from_millis(200)])
            .unwrap();
        let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);
        let started = tokio::time::Instant::now();

        let error = client
            .submit_share_with_timeout(
                helper(),
                &valid_share_json(),
                10,
                &never_cancel(),
                Duration::from_secs(10),
                Some(started + Duration::from_secs(3)),
            )
            .await
            .unwrap_err();

        assert!(matches!(
            error,
            HelperError::Transport(HelperTransportError::Transport(_))
        ));
        assert_eq!(started.elapsed(), Duration::from_millis(2_900));
        assert_eq!(transport.call_count(&url), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn retries_without_an_overall_deadline_keep_the_configured_timeout() {
        let transport = Arc::new(MockTransport::default());
        let url = post_url();
        transport.queue_post(
            &url,
            Err(HelperTransportError::Transport(
                "connect refused".to_string(),
            )),
        );
        transport.queue_post(&url, json_status("queued"));
        let config = HelperClientConfig::default()
            .with_post_timeout(Duration::from_secs(10))
            .unwrap()
            .with_retry_delays(vec![Duration::from_millis(200)])
            .unwrap();
        let client = HelperClient::with_config(transport.clone(), HelperHealth::default(), config);

        client
            .submit_share(helper(), &valid_share_json(), 10, &never_cancel())
            .await
            .unwrap();

        assert_eq!(
            transport.timeouts_for(&url),
            vec![Duration::from_secs(10), Duration::from_secs(10)]
        );
    }

    #[tokio::test(start_paused = true)]
    async fn invalid_share_bodies_are_not_sent_or_scored() {
        let transport = Arc::new(MockTransport::default());
        let client = client_with(transport.clone());
        client.health().record_failure(helper(), 1);

        let valid: Value = serde_json::from_str(&valid_share_json()).unwrap();
        let mut unknown_field = valid.clone();
        unknown_field
            .as_object_mut()
            .unwrap()
            .insert("all_enc_shares".to_string(), serde_json::json!([]));
        let mut nested_unknown_field = valid.clone();
        nested_unknown_field["enc_share"]["plaintext_value"] = serde_json::json!(42);
        let mut short_ciphertext = valid.clone();
        short_ciphertext["enc_share"]["c1"] =
            serde_json::json!(base64::engine::general_purpose::STANDARD.encode([0_u8; 31]));
        let mut mismatched_index = valid.clone();
        mismatched_index["share_index"] = serde_json::json!(1);
        let mut too_few_commitments = valid.clone();
        too_few_commitments["share_comms"]
            .as_array_mut()
            .unwrap()
            .pop();
        let mut too_many_commitments = valid.clone();
        too_many_commitments["share_comms"]
            .as_array_mut()
            .unwrap()
            .push(serde_json::json!(encoded_field(99)));
        let mut noncanonical_shares_hash = valid.clone();
        noncanonical_shares_hash["shares_hash"] =
            serde_json::json!(base64::engine::general_purpose::STANDARD.encode([0xff_u8; 32]));
        let mut noncanonical_field = valid.clone();
        noncanonical_field["primary_blind"] =
            serde_json::json!(base64::engine::general_purpose::STANDARD.encode([0xff_u8; 32]));
        let mut malformed_c1 = valid.clone();
        malformed_c1["enc_share"]["c1"] =
            serde_json::json!(base64::engine::general_purpose::STANDARD.encode([0xff_u8; 32]));
        let mut malformed_c2 = valid.clone();
        malformed_c2["enc_share"]["c2"] =
            serde_json::json!(base64::engine::general_purpose::STANDARD.encode([0xff_u8; 32]));
        let identity =
            base64::engine::general_purpose::STANDARD.encode(pallas::Point::identity().to_bytes());
        let mut identity_c1 = valid.clone();
        identity_c1["enc_share"]["c1"] = serde_json::json!(identity.clone());
        let mut identity_c2 = valid.clone();
        identity_c2["enc_share"]["c2"] = serde_json::json!(identity);
        let mut unsafe_integer = valid.clone();
        unsafe_integer["submit_at"] = serde_json::json!(0x20_0000_0000_0000_u64);
        let duplicate_field = valid_share_json().replacen(
            r#""proposal_id":1"#,
            r#""proposal_id":1,"proposal_id":1"#,
            1,
        );
        let mut oversized = valid_share_json();
        oversized.push_str(&" ".repeat(5_000));

        let invalid_bodies = [
            "not json".to_string(),
            "null".to_string(),
            "{}".to_string(),
            "[]".to_string(),
            serde_json::to_string(&unknown_field).unwrap(),
            serde_json::to_string(&nested_unknown_field).unwrap(),
            serde_json::to_string(&short_ciphertext).unwrap(),
            serde_json::to_string(&mismatched_index).unwrap(),
            serde_json::to_string(&too_few_commitments).unwrap(),
            serde_json::to_string(&too_many_commitments).unwrap(),
            serde_json::to_string(&noncanonical_shares_hash).unwrap(),
            serde_json::to_string(&noncanonical_field).unwrap(),
            serde_json::to_string(&malformed_c1).unwrap(),
            serde_json::to_string(&malformed_c2).unwrap(),
            serde_json::to_string(&identity_c1).unwrap(),
            serde_json::to_string(&identity_c2).unwrap(),
            serde_json::to_string(&unsafe_integer).unwrap(),
            duplicate_field,
            oversized,
        ];
        for body in invalid_bodies {
            let error = client
                .submit_share(helper(), &body, 10, &never_cancel())
                .await
                .unwrap_err();
            assert!(
                matches!(error, HelperError::InvalidRequest { .. }),
                "{body}"
            );
            assert!(!error.is_ambiguous());
        }

        let resubmit_error = client
            .resubmit_share(helper(), "not json", 10, &never_cancel())
            .await
            .unwrap_err();

        assert!(matches!(resubmit_error, HelperError::InvalidRequest { .. }));
        assert!(!resubmit_error.is_ambiguous());
        assert_eq!(transport.call_count("POST"), 0);
        assert_eq!(client.health().failure_count(helper()), 1);

        transport.queue_post(&post_url(), http_status(400));
        client
            .resubmit_share(helper(), &valid_share_json(), 10, &never_cancel())
            .await
            .unwrap_err();
        assert_eq!(transport.call_count("POST"), 1);
        assert_eq!(client.health().failure_count(helper()), 2);
    }

    #[tokio::test(start_paused = true)]
    async fn out_of_protocol_tree_position_is_not_sent_or_scored() {
        let transport = Arc::new(MockTransport::default());
        let client = client_with(transport.clone());
        client.health().record_failure(helper(), 1);
        let mut body: Value = serde_json::from_str(&valid_share_json()).unwrap();
        body["tree_position"] = serde_json::json!(u64::from(u32::MAX) + 1);

        let error = client
            .submit_share(
                helper(),
                &serde_json::to_string(&body).unwrap(),
                10,
                &never_cancel(),
            )
            .await
            .unwrap_err();

        assert!(matches!(error, HelperError::InvalidRequest { .. }));
        assert!(!error.is_ambiguous());
        assert_eq!(transport.call_count("POST"), 0);
        assert_eq!(client.health().failure_count(helper()), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn defaults_use_distinct_status_and_post_deadlines() {
        let transport = Arc::new(MockTransport::default());
        let status_url = status_url();
        let post_url = post_url();
        transport.queue_get(&status_url, json_status("pending"));
        transport.queue_post(&post_url, json_status("queued"));
        let client = client_with(transport.clone());

        client
            .share_status(
                helper(),
                &"01".repeat(32),
                &"cd".repeat(32),
                10,
                &never_cancel(),
            )
            .await
            .unwrap();
        client
            .submit_share(helper(), &valid_share_json(), 10, &never_cancel())
            .await
            .unwrap();

        assert_eq!(
            transport.timeout_for(&status_url),
            Duration::from_secs(HELPER_STATUS_TIMEOUT_SECONDS)
        );
        assert_eq!(
            transport.timeout_for(&post_url),
            Duration::from_millis(SHARE_HELPER_POST_TIMEOUT_MILLISECONDS)
        );
    }
}
