//! Stateless transaction submission routing.
//!
//! Managed mainnet providers are attempted one provider at a time. All of a
//! provider's regional endpoints receive the same transaction concurrently,
//! and the first accepted response completes the submission. The configured
//! sync provider is always the final provider fallback.

use std::{
    future::Future,
    sync::{Arc, LazyLock},
};

use futures::{stream::FuturesUnordered, StreamExt};
use sha2::{Digest, Sha256};
use zcash_client_backend::proto::service::SendResponse;

use crate::wallet::sync::send_rejection_is_already_accepted;

use super::lwd::{open_lwd_channel, send_transaction_with_status};

const ROUTE_DOMAIN: &[u8] = b"vizor-lightwalletd-submission-v1";

// Managed regional tasks outlive the short-lived runtimes used by several FFI
// and FRB entrypoints. This lets every region finish after the first accepted
// response is returned to the caller.
static SUBMISSION_RUNTIME: LazyLock<Result<tokio::runtime::Runtime, String>> =
    LazyLock::new(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .thread_name("vizor-tx-submission")
            .enable_all()
            .build()
            .map_err(|error| format!("transaction submission runtime unavailable: {error}"))
    });

// Keep these URLs aligned with the managed presets in rpc_endpoint_config.dart.
const STARDUST_ENDPOINTS: &[&str] = &[
    "https://us.zec.stardust.rest:443",
    "https://eu.zec.stardust.rest:443",
    "https://eu2.zec.stardust.rest:443",
    "https://jp.zec.stardust.rest:443",
];

const ZEC_ROCKS_ENDPOINTS: &[&str] = &[
    "https://zec.rocks:443",
    "https://na.zec.rocks:443",
    "https://sa.zec.rocks:443",
    "https://eu.zec.rocks:443",
    "https://ap.zec.rocks:443",
];

const MANAGED_PROVIDERS: &[Provider] = &[
    Provider {
        id: "stardust",
        endpoints: STARDUST_ENDPOINTS,
    },
    Provider {
        id: "zec-rocks",
        endpoints: ZEC_ROCKS_ENDPOINTS,
    },
];

/// Selects whether submission may use Vizor's managed provider catalog.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SubmissionMode {
    /// Rank managed providers by transaction ID and keep the configured
    /// endpoint or provider as the final fallback.
    ProviderAware,
    /// Submit only to the configured endpoint. Custom endpoints use this mode.
    CurrentOnly,
}

pub(crate) fn submission_mode(managed_submission_routing: bool) -> SubmissionMode {
    // Routing intent cannot be inferred from the URL because a custom endpoint
    // may reuse a built-in provider URL.
    if managed_submission_routing {
        SubmissionMode::ProviderAware
    } else {
        SubmissionMode::CurrentOnly
    }
}

/// One endpoint failure that contributed to an inconclusive submission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SubmissionFailure {
    pub(crate) endpoint: String,
    pub(crate) message: String,
}

pub(crate) fn submission_failures_message(failures: &[SubmissionFailure]) -> String {
    failures
        .iter()
        .map(|failure| format!("{}: {}", failure.endpoint, failure.message))
        .collect::<Vec<_>>()
        .join("; ")
}

/// The caller-relevant result of submitting a transaction.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum SubmissionOutcome {
    /// A server accepted the transaction, or reported that it already had it.
    Accepted {
        endpoint: String,
        code: i32,
        message: String,
    },
    /// A server definitively rejected the transaction and no earlier attempt
    /// had an ambiguous transport result.
    Rejected {
        endpoint: String,
        code: i32,
        message: String,
    },
    /// No `SendTransaction` RPC was started successfully.
    NotSubmitted { failures: Vec<SubmissionFailure> },
    /// At least one `SendTransaction` RPC may have reached a server, but no
    /// accepted response was observed.
    Indeterminate { failures: Vec<SubmissionFailure> },
}

#[derive(Clone, Copy, Debug)]
struct Provider {
    id: &'static str,
    endpoints: &'static [&'static str],
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct TargetGroup {
    provider_id: Option<&'static str>,
    endpoints: Vec<String>,
}

#[derive(Debug)]
enum EndpointAttempt {
    Accepted { code: i32, message: String },
    Rejected { code: i32, message: String },
    NotSubmitted { message: String },
    Indeterminate { message: String },
}

#[derive(Debug)]
enum GroupOutcome {
    Accepted {
        endpoint: String,
        code: i32,
        message: String,
    },
    Rejected {
        endpoint: String,
        code: i32,
        message: String,
    },
    NotSubmitted {
        failures: Vec<SubmissionFailure>,
    },
    Indeterminate {
        failures: Vec<SubmissionFailure>,
    },
}

/// Submits exactly `raw_transaction`; routing uses the protocol-order
/// `transaction_id` bytes only as a deterministic provider-order key.
pub(crate) async fn submit_transaction(
    configured_url: &str,
    mode: SubmissionMode,
    transaction_id: [u8; 32],
    raw_transaction: &[u8],
) -> SubmissionOutcome {
    submit_transaction_while(
        configured_url,
        mode,
        transaction_id,
        raw_transaction,
        || true,
    )
    .await
}

/// As [`submit_transaction`], but does not start another provider group after
/// `should_continue` returns false. Requests already started within a group
/// are not cancelled.
pub(crate) async fn submit_transaction_while<ShouldContinue>(
    configured_url: &str,
    mode: SubmissionMode,
    transaction_id: [u8; 32],
    raw_transaction: &[u8],
    should_continue: ShouldContinue,
) -> SubmissionOutcome
where
    ShouldContinue: Fn() -> bool,
{
    if mode == SubmissionMode::CurrentOnly {
        return submit_current_with(configured_url.to_string(), |endpoint| async move {
            submit_to_endpoint(&endpoint, raw_transaction).await
        })
        .await;
    }

    let plan = submission_plan(configured_url, mode, &transaction_id, MANAGED_PROVIDERS);
    let raw_transaction: Arc<[u8]> = Arc::from(raw_transaction.to_vec());

    dispatch_while_with(
        &plan,
        raw_transaction,
        should_continue,
        |endpoint, raw_transaction| async move {
            submit_to_endpoint(&endpoint, &raw_transaction).await
        },
    )
    .await
}

/// Resolves the same provider and regional endpoint order used for submission
/// from the protocol-order transaction ID bytes.
/// Each inner vector is one provider group whose endpoints may be queried
/// concurrently; outer groups must be attempted sequentially.
pub(crate) fn resolve_submission_endpoint_groups(
    configured_url: &str,
    mode: SubmissionMode,
    transaction_id: [u8; 32],
) -> Vec<Vec<String>> {
    submission_plan(configured_url, mode, &transaction_id, MANAGED_PROVIDERS)
        .into_iter()
        .map(|group| group.endpoints)
        .collect()
}

fn submission_plan(
    configured_url: &str,
    mode: SubmissionMode,
    transaction_id: &[u8; 32],
    providers: &'static [Provider],
) -> Vec<TargetGroup> {
    if mode == SubmissionMode::CurrentOnly {
        return vec![configured_target(configured_url)];
    }

    let configured_provider = providers
        .iter()
        .position(|provider| provider.endpoints.contains(&configured_url));
    let mut ordered: Vec<(usize, Provider)> = providers.iter().copied().enumerate().collect();
    ordered.sort_by(|(left_index, left), (right_index, right)| {
        provider_score(transaction_id, right.id)
            .cmp(&provider_score(transaction_id, left.id))
            .then_with(|| left.id.cmp(right.id))
            .then_with(|| left_index.cmp(right_index))
    });

    if let Some(configured_index) = configured_provider {
        ordered.sort_by_key(|(index, _)| *index == configured_index);
    }

    let mut plan: Vec<_> = ordered
        .into_iter()
        .map(|(_, provider)| TargetGroup {
            provider_id: Some(provider.id),
            endpoints: provider
                .endpoints
                .iter()
                .map(|endpoint| (*endpoint).to_string())
                .collect(),
        })
        .collect();

    // A recognized managed provider is already represented by its full group.
    // Community presets are not automatic targets, but the user's configured
    // community URL remains the final one-endpoint fallback.
    if configured_provider.is_none() {
        plan.push(configured_target(configured_url));
    }

    plan
}

fn configured_target(configured_url: &str) -> TargetGroup {
    TargetGroup {
        provider_id: None,
        endpoints: vec![configured_url.to_string()],
    }
}

fn provider_score(transaction_id: &[u8; 32], provider_id: &str) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(ROUTE_DOMAIN);
    hasher.update(transaction_id);
    hasher.update([0]);
    hasher.update(provider_id.as_bytes());
    hasher.finalize().into()
}

async fn submit_to_endpoint(endpoint: &str, raw_transaction: &[u8]) -> EndpointAttempt {
    let mut client = match open_lwd_channel(endpoint).await {
        Ok(client) => client,
        Err(error) => {
            let message = error.to_string();
            log::warn!("transaction submission did not connect to {endpoint}: {message}");
            return EndpointAttempt::NotSubmitted { message };
        }
    };

    match send_transaction_with_status(&mut client, raw_transaction).await {
        Ok(response) => classify_send_response(response),
        Err(error) => {
            let message = error.to_string();
            log::warn!("transaction submission to {endpoint} was indeterminate: {message}");
            EndpointAttempt::Indeterminate { message }
        }
    }
}

fn classify_send_response(response: SendResponse) -> EndpointAttempt {
    if response.error_code == 0 {
        EndpointAttempt::Accepted {
            code: response.error_code,
            message: response.error_message,
        }
    } else if send_rejection_is_already_accepted(&response.error_message) {
        EndpointAttempt::Accepted {
            code: response.error_code,
            message: response.error_message,
        }
    } else {
        EndpointAttempt::Rejected {
            code: response.error_code,
            message: response.error_message,
        }
    }
}

async fn submit_current_with<F, Fut>(endpoint: String, attempt: F) -> SubmissionOutcome
where
    F: FnOnce(String) -> Fut,
    Fut: Future<Output = EndpointAttempt>,
{
    let result = attempt(endpoint.clone()).await;
    match result {
        EndpointAttempt::Accepted { code, message } => SubmissionOutcome::Accepted {
            endpoint,
            code,
            message,
        },
        EndpointAttempt::Rejected { code, message } => SubmissionOutcome::Rejected {
            endpoint,
            code,
            message,
        },
        EndpointAttempt::NotSubmitted { message } => SubmissionOutcome::NotSubmitted {
            failures: vec![SubmissionFailure { endpoint, message }],
        },
        EndpointAttempt::Indeterminate { message } => SubmissionOutcome::Indeterminate {
            failures: vec![SubmissionFailure { endpoint, message }],
        },
    }
}

#[cfg(test)]
async fn dispatch_with<F, Fut>(
    plan: &[TargetGroup],
    raw_transaction: Arc<[u8]>,
    attempt: F,
) -> SubmissionOutcome
where
    F: Fn(String, Arc<[u8]>) -> Fut,
    Fut: Future<Output = EndpointAttempt> + Send + 'static,
{
    dispatch_while_with(plan, raw_transaction, || true, attempt).await
}

async fn dispatch_while_with<ShouldContinue, F, Fut>(
    plan: &[TargetGroup],
    raw_transaction: Arc<[u8]>,
    should_continue: ShouldContinue,
    attempt: F,
) -> SubmissionOutcome
where
    ShouldContinue: Fn() -> bool,
    F: Fn(String, Arc<[u8]>) -> Fut,
    Fut: Future<Output = EndpointAttempt> + Send + 'static,
{
    let mut failures = Vec::new();
    let mut ambiguity_seen = false;

    for group in plan {
        if !should_continue() {
            break;
        }
        log::info!(
            "transaction submission trying {} endpoint(s) for {}",
            group.endpoints.len(),
            group.provider_id.unwrap_or("configured endpoint")
        );

        match submit_to_group(group, Arc::clone(&raw_transaction), &attempt).await {
            GroupOutcome::Accepted {
                endpoint,
                code,
                message,
            } => {
                return SubmissionOutcome::Accepted {
                    endpoint,
                    code,
                    message,
                };
            }
            GroupOutcome::Rejected {
                endpoint,
                code,
                message,
            } => {
                if !ambiguity_seen {
                    return SubmissionOutcome::Rejected {
                        endpoint,
                        code,
                        message,
                    };
                }

                failures.push(SubmissionFailure {
                    endpoint,
                    message: format!("rejected with code {code}: {message}"),
                });
                return SubmissionOutcome::Indeterminate { failures };
            }
            GroupOutcome::NotSubmitted {
                failures: group_failures,
            } => failures.extend(group_failures),
            GroupOutcome::Indeterminate {
                failures: group_failures,
            } => {
                ambiguity_seen = true;
                failures.extend(group_failures);
            }
        }
    }

    if ambiguity_seen {
        SubmissionOutcome::Indeterminate { failures }
    } else {
        SubmissionOutcome::NotSubmitted { failures }
    }
}

async fn submit_to_group<F, Fut>(
    group: &TargetGroup,
    raw_transaction: Arc<[u8]>,
    attempt: &F,
) -> GroupOutcome
where
    F: Fn(String, Arc<[u8]>) -> Fut,
    Fut: Future<Output = EndpointAttempt> + Send + 'static,
{
    let runtime = match &*SUBMISSION_RUNTIME {
        Ok(runtime) => runtime,
        Err(message) => {
            return GroupOutcome::NotSubmitted {
                failures: group
                    .endpoints
                    .iter()
                    .map(|endpoint| SubmissionFailure {
                        endpoint: endpoint.clone(),
                        message: message.clone(),
                    })
                    .collect(),
            };
        }
    };
    let mut attempts = FuturesUnordered::new();
    for (index, endpoint) in group.endpoints.iter().cloned().enumerate() {
        let attempt_future = attempt(endpoint.clone(), Arc::clone(&raw_transaction));
        let task = runtime.spawn(attempt_future);
        attempts.push(async move {
            let result = match task.await {
                Ok(result) => result,
                Err(error) => EndpointAttempt::Indeterminate {
                    message: format!("submission task failed: {error}"),
                },
            };
            (index, endpoint, result)
        });
    }

    let mut rejections = Vec::new();
    let mut not_submitted = Vec::new();
    let mut indeterminate = Vec::new();

    while let Some((index, endpoint, result)) = attempts.next().await {
        match result {
            EndpointAttempt::Accepted { code, message } => {
                // The remaining tasks stay on the process-wide submission
                // runtime and finish independently of the caller's runtime.
                return GroupOutcome::Accepted {
                    endpoint,
                    code,
                    message,
                };
            }
            EndpointAttempt::Rejected { code, message } => {
                rejections.push((index, endpoint, code, message));
            }
            EndpointAttempt::NotSubmitted { message } => {
                not_submitted.push((index, SubmissionFailure { endpoint, message }));
            }
            EndpointAttempt::Indeterminate { message } => {
                indeterminate.push((index, SubmissionFailure { endpoint, message }));
            }
        }
    }

    if !indeterminate.is_empty() {
        for (index, endpoint, code, message) in rejections {
            indeterminate.push((
                index,
                SubmissionFailure {
                    endpoint,
                    message: format!("rejected with code {code}: {message}"),
                },
            ));
        }
        indeterminate.extend(not_submitted);
        indeterminate.sort_by_key(|(index, _)| *index);
        return GroupOutcome::Indeterminate {
            failures: indeterminate
                .into_iter()
                .map(|(_, failure)| failure)
                .collect(),
        };
    }

    if !rejections.is_empty() {
        rejections.sort_by_key(|(index, _, _, _)| *index);
        let (_, endpoint, code, message) = rejections.remove(0);
        return GroupOutcome::Rejected {
            endpoint,
            code,
            message,
        };
    }

    not_submitted.sort_by_key(|(index, _)| *index);
    GroupOutcome::NotSubmitted {
        failures: not_submitted
            .into_iter()
            .map(|(_, failure)| failure)
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use std::{
        cell::Cell,
        collections::{HashMap, HashSet},
        rc::Rc,
        sync::{mpsc, Arc, Mutex},
        time::Duration,
    };

    use tokio::sync::{Barrier, Semaphore};

    use super::*;

    const COMMUNITY_ENDPOINT: &str = "https://z3.deepikaw.xyz:443";

    fn test_plan(configured_url: &str, mode: SubmissionMode, txid_byte: u8) -> Vec<TargetGroup> {
        submission_plan(configured_url, mode, &[txid_byte; 32], MANAGED_PROVIDERS)
    }

    fn provider_ids(plan: &[TargetGroup]) -> Vec<Option<&'static str>> {
        plan.iter().map(|target| target.provider_id).collect()
    }

    #[test]
    fn managed_endpoints_are_unique() {
        let mut endpoints = HashSet::new();
        for provider in MANAGED_PROVIDERS {
            assert!(
                !provider.endpoints.is_empty(),
                "{} has no endpoints",
                provider.id
            );
            for endpoint in provider.endpoints {
                assert!(
                    endpoints.insert(*endpoint),
                    "managed endpoint appears more than once: {endpoint}"
                );
            }
        }
    }

    #[test]
    fn current_only_uses_exact_configured_url() {
        let configured_url = STARDUST_ENDPOINTS[0];
        let plan = test_plan(configured_url, SubmissionMode::CurrentOnly, 1);

        assert_eq!(plan, vec![configured_target(configured_url)]);
    }

    #[test]
    fn configured_managed_provider_is_last() {
        let stardust_plan = test_plan(STARDUST_ENDPOINTS[0], SubmissionMode::ProviderAware, 2);
        assert_eq!(
            provider_ids(&stardust_plan),
            vec![Some("zec-rocks"), Some("stardust")]
        );

        let rocks_plan = test_plan(ZEC_ROCKS_ENDPOINTS[2], SubmissionMode::ProviderAware, 3);
        assert_eq!(
            provider_ids(&rocks_plan),
            vec![Some("stardust"), Some("zec-rocks")]
        );
    }

    #[test]
    fn community_endpoint_is_only_the_final_fallback() {
        let plan = test_plan(COMMUNITY_ENDPOINT, SubmissionMode::ProviderAware, 4);

        assert_eq!(plan.len(), 3);
        assert!(plan[0].provider_id.is_some());
        assert!(plan[1].provider_id.is_some());
        assert_eq!(plan[2], configured_target(COMMUNITY_ENDPOINT));
        assert!(plan[..2]
            .iter()
            .flat_map(|target| target.endpoints.iter())
            .all(|endpoint| endpoint != COMMUNITY_ENDPOINT));
    }

    #[test]
    fn provider_order_is_stable_and_txid_dependent() {
        const THIRD_ENDPOINTS: &[&str] = &["https://third.example:443"];
        const PROVIDERS: &[Provider] = &[
            Provider {
                id: "stardust",
                endpoints: STARDUST_ENDPOINTS,
            },
            Provider {
                id: "zec-rocks",
                endpoints: ZEC_ROCKS_ENDPOINTS,
            },
            Provider {
                id: "third",
                endpoints: THIRD_ENDPOINTS,
            },
        ];

        let first = submission_plan(
            COMMUNITY_ENDPOINT,
            SubmissionMode::ProviderAware,
            &[0; 32],
            PROVIDERS,
        );
        let repeated = submission_plan(
            COMMUNITY_ENDPOINT,
            SubmissionMode::ProviderAware,
            &[0; 32],
            PROVIDERS,
        );
        assert_eq!(first, repeated);

        let first_ids = provider_ids(&first[..3]);
        assert!((1..=u8::MAX).any(|byte| {
            let candidate = submission_plan(
                COMMUNITY_ENDPOINT,
                SubmissionMode::ProviderAware,
                &[byte; 32],
                PROVIDERS,
            );
            provider_ids(&candidate[..3]) != first_ids
        }));
    }

    #[test]
    fn classifies_success_duplicate_and_rejection() {
        assert!(matches!(
            classify_send_response(SendResponse {
                error_code: 0,
                error_message: "txid".to_string(),
            }),
            EndpointAttempt::Accepted {
                code: 0,
                message
            } if message == "txid"
        ));
        assert!(matches!(
            classify_send_response(SendResponse {
                error_code: -25,
                error_message: "TXN-ALREADY-IN-MEMPOOL".to_string(),
            }),
            EndpointAttempt::Accepted {
                code: -25,
                message
            } if message == "TXN-ALREADY-IN-MEMPOOL"
        ));
        assert!(matches!(
            classify_send_response(SendResponse {
                error_code: 18,
                error_message: "bad-txns-inputs-spent".to_string(),
            }),
            EndpointAttempt::Rejected { code: 18, .. }
        ));
    }

    #[tokio::test]
    async fn all_regions_start_concurrently_with_identical_bytes() {
        let group = TargetGroup {
            provider_id: Some("test"),
            endpoints: vec!["one".to_string(), "two".to_string(), "three".to_string()],
        };
        let barrier = Arc::new(Barrier::new(group.endpoints.len()));
        let seen = Arc::new(Mutex::new(Vec::new()));
        let expected = Arc::<[u8]>::from(vec![1, 2, 3, 4]);
        let result = dispatch_with(&[group], Arc::clone(&expected), {
            let barrier = Arc::clone(&barrier);
            let seen = Arc::clone(&seen);
            move |endpoint, raw_transaction| {
                let barrier = Arc::clone(&barrier);
                let seen = Arc::clone(&seen);
                async move {
                    seen.lock()
                        .expect("seen lock")
                        .push((endpoint.clone(), raw_transaction.to_vec()));
                    barrier.wait().await;
                    if endpoint == "two" {
                        EndpointAttempt::Accepted {
                            code: 0,
                            message: String::new(),
                        }
                    } else {
                        EndpointAttempt::NotSubmitted {
                            message: "offline".to_string(),
                        }
                    }
                }
            }
        })
        .await;

        assert!(matches!(result, SubmissionOutcome::Accepted { .. }));
        let seen = seen.lock().expect("seen lock");
        assert_eq!(seen.len(), 3);
        assert!(seen.iter().all(|(_, bytes)| bytes == expected.as_ref()));
    }

    #[test]
    fn regional_attempts_finish_after_callers_runtime_drops() {
        let group = TargetGroup {
            provider_id: Some("test"),
            endpoints: vec![
                "accepted".to_string(),
                "remaining-one".to_string(),
                "remaining-two".to_string(),
            ],
        };
        let barrier = Arc::new(Barrier::new(group.endpoints.len()));
        let permits = Arc::new(Semaphore::new(0));
        let (completed_tx, completed_rx) = mpsc::channel();

        let result = {
            let caller_runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("build caller runtime");
            caller_runtime.block_on(dispatch_with(&[group], Arc::from(vec![1]), {
                let barrier = Arc::clone(&barrier);
                let permits = Arc::clone(&permits);
                move |endpoint, _| {
                    let barrier = Arc::clone(&barrier);
                    let permits = Arc::clone(&permits);
                    let completed_tx = completed_tx.clone();
                    async move {
                        barrier.wait().await;
                        if endpoint == "accepted" {
                            EndpointAttempt::Accepted {
                                code: 0,
                                message: String::new(),
                            }
                        } else {
                            permits.acquire().await.expect("submission permit").forget();
                            completed_tx.send(endpoint).expect("record completion");
                            EndpointAttempt::NotSubmitted {
                                message: "offline".to_string(),
                            }
                        }
                    }
                }
            }))
        };

        assert!(matches!(result, SubmissionOutcome::Accepted { .. }));
        permits.add_permits(2);
        let mut completed = vec![
            completed_rx
                .recv_timeout(Duration::from_secs(2))
                .expect("first remaining region completed"),
            completed_rx
                .recv_timeout(Duration::from_secs(2))
                .expect("second remaining region completed"),
        ];
        completed.sort();
        assert_eq!(completed, ["remaining-one", "remaining-two"]);
    }

    #[tokio::test]
    async fn providers_are_attempted_sequentially() {
        let plan = test_plan(STARDUST_ENDPOINTS[0], SubmissionMode::ProviderAware, 7);
        let calls = Arc::new(Mutex::new(Vec::new()));
        let result = dispatch_with(&plan, Arc::from(vec![9]), {
            let calls = Arc::clone(&calls);
            move |endpoint, _| {
                let calls = Arc::clone(&calls);
                async move {
                    calls.lock().expect("calls lock").push(endpoint.clone());
                    if ZEC_ROCKS_ENDPOINTS.contains(&endpoint.as_str()) {
                        EndpointAttempt::NotSubmitted {
                            message: "offline".to_string(),
                        }
                    } else {
                        EndpointAttempt::Accepted {
                            code: 0,
                            message: String::new(),
                        }
                    }
                }
            }
        })
        .await;

        assert!(matches!(result, SubmissionOutcome::Accepted { .. }));
        let calls = calls.lock().expect("calls lock");
        let first_stardust = calls
            .iter()
            .position(|endpoint| STARDUST_ENDPOINTS.contains(&endpoint.as_str()))
            .expect("stardust fallback attempted");
        assert_eq!(first_stardust, ZEC_ROCKS_ENDPOINTS.len());
    }

    #[tokio::test]
    async fn fallback_provider_is_not_started_after_stop() {
        let plan = vec![
            configured_target("first"),
            configured_target("must-not-run"),
        ];
        let calls = Arc::new(Mutex::new(Vec::new()));
        let result = dispatch_while_with(
            &plan,
            Arc::from(vec![1]),
            {
                let calls = Arc::clone(&calls);
                move || calls.lock().expect("calls lock").is_empty()
            },
            {
                let calls = Arc::clone(&calls);
                move |endpoint, _| {
                    let calls = Arc::clone(&calls);
                    async move {
                        calls.lock().expect("calls lock").push(endpoint);
                        EndpointAttempt::NotSubmitted {
                            message: "offline".to_string(),
                        }
                    }
                }
            },
        )
        .await;

        assert!(matches!(
            result,
            SubmissionOutcome::NotSubmitted { failures } if failures.len() == 1
        ));
        assert_eq!(calls.lock().expect("calls lock").as_slice(), ["first"]);
    }

    #[tokio::test]
    async fn definite_rejection_stops_without_fallback() {
        let plan = vec![
            configured_target("first"),
            configured_target("must-not-run"),
        ];
        let calls = Arc::new(Mutex::new(Vec::new()));
        let result = dispatch_with(&plan, Arc::from(vec![1]), {
            let calls = Arc::clone(&calls);
            move |endpoint, _| {
                let calls = Arc::clone(&calls);
                async move {
                    calls.lock().expect("calls lock").push(endpoint);
                    EndpointAttempt::Rejected {
                        code: 18,
                        message: "invalid".to_string(),
                    }
                }
            }
        })
        .await;

        assert_eq!(
            result,
            SubmissionOutcome::Rejected {
                endpoint: "first".to_string(),
                code: 18,
                message: "invalid".to_string(),
            }
        );
        assert_eq!(calls.lock().expect("calls lock").as_slice(), ["first"]);
    }

    #[tokio::test]
    async fn all_pre_send_failures_are_not_submitted() {
        let plan = vec![configured_target("first"), configured_target("second")];
        let result = dispatch_with(&plan, Arc::from(vec![1]), |endpoint, _| async move {
            EndpointAttempt::NotSubmitted {
                message: format!("cannot connect to {endpoint}"),
            }
        })
        .await;

        assert!(matches!(
            result,
            SubmissionOutcome::NotSubmitted { failures } if failures.len() == 2
        ));
    }

    #[tokio::test]
    async fn ambiguity_can_be_resolved_by_later_acceptance() {
        let plan = vec![configured_target("first"), configured_target("second")];
        let outcomes = Arc::new(Mutex::new(HashMap::from([
            (
                "first".to_string(),
                EndpointAttempt::Indeterminate {
                    message: "timeout".to_string(),
                },
            ),
            (
                "second".to_string(),
                EndpointAttempt::Accepted {
                    code: -25,
                    message: "already in mempool".to_string(),
                },
            ),
        ])));
        let result = dispatch_with(&plan, Arc::from(vec![1]), move |endpoint, _| {
            let outcome = outcomes
                .lock()
                .expect("outcomes lock")
                .remove(&endpoint)
                .expect("endpoint outcome");
            std::future::ready(outcome)
        })
        .await;

        assert_eq!(
            result,
            SubmissionOutcome::Accepted {
                endpoint: "second".to_string(),
                code: -25,
                message: "already in mempool".to_string(),
            }
        );
    }

    #[tokio::test]
    async fn ambiguity_taints_later_rejection() {
        let plan = vec![configured_target("first"), configured_target("second")];
        let outcomes = Arc::new(Mutex::new(HashMap::from([
            (
                "first".to_string(),
                EndpointAttempt::Indeterminate {
                    message: "timeout".to_string(),
                },
            ),
            (
                "second".to_string(),
                EndpointAttempt::Rejected {
                    code: 18,
                    message: "invalid".to_string(),
                },
            ),
        ])));
        let result = dispatch_with(&plan, Arc::from(vec![1]), move |endpoint, _| {
            let outcome = outcomes
                .lock()
                .expect("outcomes lock")
                .remove(&endpoint)
                .expect("endpoint outcome");
            std::future::ready(outcome)
        })
        .await;

        assert!(matches!(
            result,
            SubmissionOutcome::Indeterminate { failures }
                if failures.len() == 2
                    && failures[0].endpoint == "first"
                    && failures[1].endpoint == "second"
        ));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn current_only_uses_the_callers_runtime() {
        let called = Rc::new(Cell::new(false));
        let result = submit_current_with(COMMUNITY_ENDPOINT.to_string(), {
            let called = Rc::clone(&called);
            move |endpoint| async move {
                assert_eq!(endpoint, COMMUNITY_ENDPOINT);
                called.set(true);
                EndpointAttempt::Accepted {
                    code: 0,
                    message: String::new(),
                }
            }
        })
        .await;

        assert!(called.get());
        assert_eq!(
            result,
            SubmissionOutcome::Accepted {
                endpoint: COMMUNITY_ENDPOINT.to_string(),
                code: 0,
                message: String::new(),
            }
        );
    }
}
