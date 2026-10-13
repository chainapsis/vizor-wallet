//! Private account discovery for a recovery-phrase import.
//!
//! Import checks the first transparent address of accounts 1 to 20 for
//! history from the birthday. Asking lightwalletd discloses those addresses,
//! so under private queries [`PrivateAccountDiscovery`] asks the transparent
//! PIR service instead, through `zakura_pir_transparent`'s
//! `discover_active_addresses`: it downloads every filter from the birthday's
//! shard to the publication's end and confirms each filter match by private
//! retrieval, so a false positive never offers an empty account. Nothing is
//! stored, and no companion or wallet is opened; the wallet may not exist yet.
//!
//! The service learns the birthday's shard, which shards matched any
//! candidate, false positives included, and timing; the per-account recovery
//! of the accounts the user imports follows at once and can be linked to it.
//!
//! A discovery runs through [`run_detached`], on a thread and runtime of its
//! own as a recovery pass does, and stops at [`DISCOVERY_DEADLINE`]. It
//! succeeds only when every candidate is covered through the publication's
//! end; anything else is a failure the user retries, never a shorter list.
//! The library follows a pass its query or byte budget stopped with one over
//! the candidates it did not confirm, since a heavily used address spends the
//! budget on its own history.
//! Logs carry outcome and variant names, never addresses or adapter text.
//!
//! Debug builds on regtest under the transparent history harness's switch
//! (see [`regtest_private_e2e`]) can lower a pass's query and shard budgets
//! (`ZCASH_E2E_REGTEST_DISCOVERY_MAX_QUERIES`, `..._MAX_SHARDS`), so a small
//! chain reaches the budget stop and the library's next pass. Release builds never read them.

use std::collections::BTreeSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use transparent::address::TransparentAddress;
use zakura_pir_transparent::{
    discover_active_addresses, Discovery, DiscoveryLimits, Outcome, RecoveryError,
    TransparentPirHttp,
};

use super::pir::{
    origin_for, origin_override, MAX_PRIVATE_BYTES, MAX_QUERIES, MAX_RESPONSE_BYTES, MAX_SHARDS,
};
use crate::wallet::bounded_runtime::{run_detached, Detached};
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::enhancement::{regtest_private_e2e, RoutedExchange};

/// Wall-clock bound on one discovery. A walk from Sapling activation
/// downloads about 50 filters, one at a time, over Tor when it is on.
pub(crate) const DISCOVERY_DEADLINE: Duration = Duration::from_secs(300);

/// Replaces [`MAX_QUERIES`] for each discovery pass; see [`pass_limits`].
const MAX_QUERIES_OVERRIDE_ENV: &str = "ZCASH_E2E_REGTEST_DISCOVERY_MAX_QUERIES";
/// Replaces [`MAX_SHARDS`] for each discovery pass; see [`pass_limits`].
const MAX_SHARDS_OVERRIDE_ENV: &str = "ZCASH_E2E_REGTEST_DISCOVERY_MAX_SHARDS";

/// The shard and query budgets of each discovery pass on `network`:
/// [`MAX_SHARDS`] and [`MAX_QUERIES`], except in a debug build on regtest
/// under [`regtest_private_e2e`], where the harness may lower them. Release
/// builds never read the overrides.
fn pass_limits(network: WalletNetwork) -> (usize, u64) {
    let harness = cfg!(debug_assertions) && regtest_private_e2e(network);
    pass_limits_from(|name| {
        if harness {
            std::env::var(name).ok()
        } else {
            None
        }
    })
}

/// [`pass_limits`] with the overrides read through `read`. A missing,
/// unparsable or zero value keeps the default.
fn pass_limits_from(read: impl Fn(&str) -> Option<String>) -> (usize, u64) {
    let positive = |name| {
        read(name)
            .and_then(|value| value.trim().parse::<u64>().ok())
            .filter(|&value| value > 0)
    };
    let shards = positive(MAX_SHARDS_OVERRIDE_ENV)
        .and_then(|value| usize::try_from(value).ok())
        .unwrap_or(MAX_SHARDS);
    let queries = positive(MAX_QUERIES_OVERRIDE_ENV).unwrap_or(MAX_QUERIES);
    (shards, queries)
}

/// The private discovery failed or did not finish; the user retries.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct PrivateDiscoveryFailed;

/// Which candidate addresses hold transparent history, from the transparent
/// PIR service.
pub(crate) struct PrivateAccountDiscovery {
    /// `None` off mainnet: private discovery is unavailable.
    origin: Option<String>,
    /// Shard-map entries and private queries one pass may use.
    limits: (usize, u64),
    #[cfg(test)]
    transport: Option<super::pir::test_transport::Seam>,
    #[cfg(test)]
    canned: Option<Canned>,
}

/// A test's answer in place of the service, with the requests it was asked.
#[cfg(test)]
pub(crate) type Canned = (
    Result<BTreeSet<usize>, PrivateDiscoveryFailed>,
    Arc<std::sync::Mutex<Vec<(u64, Vec<TransparentAddress>)>>>,
);

impl PrivateAccountDiscovery {
    /// Discovery for an import into the wallet at `db_path`, existing or not:
    /// the path keys only the test transport.
    pub(crate) fn new(db_path: &str, network: WalletNetwork) -> Self {
        #[cfg(not(test))]
        let _ = db_path;
        Self {
            origin: origin_for(network, origin_override(|name| std::env::var(name).ok())),
            limits: pass_limits(network),
            #[cfg(test)]
            transport: super::pir::test_transport::get(db_path),
            #[cfg(test)]
            canned: None,
        }
    }

    /// A discovery that answers `answer` without any request, recording each
    /// floor and candidate list it was asked.
    #[cfg(test)]
    pub(crate) fn canned(answer: Result<BTreeSet<usize>, PrivateDiscoveryFailed>) -> Self {
        Self {
            origin: Some(super::pir::DEFAULT_MAINNET_ORIGIN.to_owned()),
            limits: (MAX_SHARDS, MAX_QUERIES),
            transport: None,
            canned: Some((answer, Default::default())),
        }
    }

    /// The floors and candidate lists a canned discovery was asked.
    #[cfg(test)]
    pub(crate) fn asked(&self) -> Vec<(u64, Vec<TransparentAddress>)> {
        self.canned.as_ref().map_or_else(Vec::new, |(_, asked)| {
            asked
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clone()
        })
    }

    /// Whether this network has a transparent PIR service.
    pub(crate) fn is_available(&self) -> bool {
        self.origin.is_some()
    }

    /// The indices into `addresses` of those holding a receive or a spend at
    /// or above `floor`, through the publication's end.
    pub(crate) async fn active(
        &self,
        floor: u64,
        addresses: Vec<TransparentAddress>,
    ) -> Result<BTreeSet<usize>, PrivateDiscoveryFailed> {
        #[cfg(test)]
        if let Some((answer, asked)) = &self.canned {
            asked
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .push((floor, addresses));
            return answer.clone();
        }
        let Some(origin) = self.origin.clone() else {
            return Err(PrivateDiscoveryFailed);
        };
        #[cfg(test)]
        let Some(transport) = self.transport.clone() else {
            // No test reaches the live service by accident.
            return Err(PrivateDiscoveryFailed);
        };
        let (max_shards, max_queries) = self.limits;
        let deadline = Instant::now() + DISCOVERY_DEADLINE;
        let past_deadline = move || Instant::now() >= deadline;
        let cancel = Arc::new(AtomicBool::new(false));
        let stop = cancel.clone();
        let ran = run_detached(
            "transparent-pir-discovery",
            cancel,
            &past_deadline,
            move |io| {
                let exit = || stop.load(Ordering::SeqCst) || Instant::now() >= deadline;
                let result = (|| {
                    let exchange = RoutedExchange::transparent(&origin, &exit, io)
                        .map_err(|_| "transport refused the origin")?;
                    #[cfg(test)]
                    let exchange = transport.attach(exchange);
                    let mut http = TransparentPirHttp::new(exchange, MAX_RESPONSE_BYTES);
                    let result = {
                        let (mut filters, mut shards) = http.split();
                        // The caller chose the candidates; the script limit is
                        // theirs.
                        let limits = DiscoveryLimits {
                            scripts: addresses.len(),
                            shards: max_shards,
                            queries: max_queries,
                            private_bytes: MAX_PRIVATE_BYTES,
                        };
                        discover_active_addresses(
                            &addresses,
                            floor,
                            &limits,
                            &mut filters,
                            &mut shards,
                        )
                    };
                    Ok(interpret(result, http.outage()))
                })();
                result.unwrap_or_else(|name: &str| {
                    log::warn!("private account discovery: {name}");
                    Err(PrivateDiscoveryFailed)
                })
            },
        )
        .await;
        match ran {
            Detached::Returned(result) => result,
            Detached::NotStarted => {
                log::error!("private account discovery: could not start");
                Err(PrivateDiscoveryFailed)
            }
            Detached::Panicked => {
                log::error!("private account discovery: panicked");
                Err(PrivateDiscoveryFailed)
            }
            Detached::Abandoned => {
                log::warn!("private account discovery: abandoned past its deadline");
                Err(PrivateDiscoveryFailed)
            }
        }
    }
}

/// The candidates with history, from a discovery's result. `outage` says a
/// failure was the service being unreachable or not serving.
pub(crate) fn interpret(
    result: Result<Discovery, RecoveryError>,
    outage: bool,
) -> Result<BTreeSet<usize>, PrivateDiscoveryFailed> {
    match result {
        Ok(Discovery { active, progress }) => match progress.outcome {
            Outcome::Complete => Ok(active.into_iter().collect()),
            Outcome::More => {
                log::warn!("private account discovery: budget reached with nothing new confirmed");
                Err(PrivateDiscoveryFailed)
            }
            outcome => {
                log::warn!("private account discovery: incomplete ({outcome:?})");
                Err(PrivateDiscoveryFailed)
            }
        },
        Err(error) => {
            let name = match error {
                RecoveryError::Failure(_) if outage => "service unavailable",
                RecoveryError::Invalid(_) => "invalid",
                RecoveryError::Failure(_) => "failure",
                RecoveryError::PublicationChanged => "publication changed",
            };
            log::warn!("private account discovery: failed ({name})");
            Err(PrivateDiscoveryFailed)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zakura_pir_transparent::Progress;

    fn discovery(active: Vec<usize>, outcome: Outcome) -> Result<Discovery, RecoveryError> {
        Ok(Discovery {
            active,
            progress: Progress {
                covered_through: 3_500_000,
                outcome,
            },
        })
    }

    #[test]
    fn only_a_complete_discovery_answers() {
        assert_eq!(
            interpret(discovery(vec![0, 6], Outcome::Complete), false),
            Ok(BTreeSet::from([0, 6]))
        );
        for outcome in [
            Outcome::More,
            Outcome::Behind,
            Outcome::Overloaded,
            Outcome::Stalled,
        ] {
            assert_eq!(
                interpret(discovery(vec![0], outcome), false),
                Err(PrivateDiscoveryFailed),
                "{outcome:?}"
            );
        }
        for (error, outage) in [
            (RecoveryError::Invalid("x".into()), false),
            (RecoveryError::Failure("x".into()), false),
            (RecoveryError::Failure("x".into()), true),
            (RecoveryError::PublicationChanged, false),
        ] {
            assert_eq!(interpret(Err(error), outage), Err(PrivateDiscoveryFailed));
        }
    }

    #[test]
    fn the_harness_may_lower_a_pass_budget_and_nothing_else() {
        assert_eq!(pass_limits_from(|_| None), (MAX_SHARDS, MAX_QUERIES));
        let read = |queries: &'static str, shards: &'static str| {
            move |name: &str| match name {
                MAX_QUERIES_OVERRIDE_ENV => Some(queries.to_owned()),
                MAX_SHARDS_OVERRIDE_ENV => Some(shards.to_owned()),
                _ => None,
            }
        };
        assert_eq!(pass_limits_from(read("1", "8")), (8, 1));
        assert_eq!(pass_limits_from(read(" 3 ", "")), (MAX_SHARDS, 3));
        for bad in ["0", "-1", "many", ""] {
            assert_eq!(
                pass_limits_from(read(bad, bad)),
                (MAX_SHARDS, MAX_QUERIES),
                "{bad:?}"
            );
        }
        // Off regtest the overrides are never read, whatever the environment.
        for network in [WalletNetwork::Main, WalletNetwork::Test] {
            assert_eq!(pass_limits(network), (MAX_SHARDS, MAX_QUERIES));
        }
    }

    #[tokio::test]
    async fn off_mainnet_there_is_no_private_discovery() {
        let discovery = PrivateAccountDiscovery::new("/nonexistent", WalletNetwork::Test);
        assert!(!discovery.is_available());
        assert_eq!(
            discovery
                .active(1, vec![TransparentAddress::PublicKeyHash([1; 20])])
                .await,
            Err(PrivateDiscoveryFailed)
        );
    }

    #[tokio::test]
    async fn without_a_test_transport_nothing_is_sent() {
        let discovery = PrivateAccountDiscovery::new("/nonexistent", WalletNetwork::Main);
        assert!(discovery.is_available());
        assert_eq!(
            discovery
                .active(1, vec![TransparentAddress::PublicKeyHash([1; 20])])
                .await,
            Err(PrivateDiscoveryFailed)
        );
    }
}
