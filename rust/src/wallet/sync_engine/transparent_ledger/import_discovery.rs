//! Private account discovery for a recovery-phrase import.
//!
//! Import checks the first transparent address of accounts 1 to 20 for
//! history from the birthday. Asking lightwalletd discloses those addresses,
//! so under private queries [`PrivateAccountDiscovery`] asks the transparent
//! PIR service instead, through `zakura_pir_client::transparent`'s
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

use std::collections::BTreeSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use transparent::address::TransparentAddress;
use zakura_pir_client::transparent::{
    discover_active_addresses, Discovery, DiscoveryLimits, Outcome, RecoveryError,
    TransparentPirHttp,
};

use super::pir::{
    origin_for, source_origin, MAX_PRIVATE_BYTES, MAX_QUERIES, MAX_RESPONSE_BYTES, MAX_SHARDS,
};
use crate::wallet::bounded_runtime::{run_detached, Detached};
use crate::wallet::network::WalletNetwork;
use crate::wallet::pir_config::{process_selection, SelectedServer};
use crate::wallet::sync_engine::enhancement::RoutedExchange;

/// Wall-clock bound on one discovery. A walk from Sapling activation
/// downloads about 50 filters, one at a time, over Tor when it is on.
pub(crate) const DISCOVERY_DEADLINE: Duration = Duration::from_secs(300);

/// The private discovery failed or did not finish; the user retries.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct PrivateDiscoveryFailed;

/// Which candidate addresses hold transparent history, from the transparent
/// PIR service.
pub(crate) struct PrivateAccountDiscovery {
    /// `None` off mainnet: private discovery is unavailable.
    origin: Option<String>,
    selection: &'static SelectedServer,
    generation: u64,
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
    /// the path keys only a test's transport and origin.
    pub(crate) fn new(db_path: &str, network: WalletNetwork) -> Self {
        // Read the generation first: a switch racing the origin capture also
        // revokes this discovery, rather than giving an old origin a new lease.
        let selection = process_selection();
        let generation = selection.generation();
        Self {
            origin: origin_for(network, source_origin(db_path)),
            selection,
            generation,
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
            origin: Some(super::pir::TEST_ORIGIN.to_owned()),
            selection: process_selection(),
            generation: process_selection().generation(),
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
        let selection = self.selection;
        let generation = self.generation;
        if selection.generation() != generation {
            return Err(PrivateDiscoveryFailed);
        }
        let Some(origin) = self.origin.clone() else {
            return Err(PrivateDiscoveryFailed);
        };
        #[cfg(test)]
        let Some(transport) = self.transport.clone() else {
            // No test reaches the live service by accident.
            return Err(PrivateDiscoveryFailed);
        };
        let deadline = Instant::now() + DISCOVERY_DEADLINE;
        let past_deadline =
            move || Instant::now() >= deadline || selection.generation() != generation;
        let cancel = Arc::new(AtomicBool::new(false));
        let stop = cancel.clone();
        let ran = run_detached(
            "transparent-pir-discovery",
            cancel,
            &past_deadline,
            move |io| {
                let exit = || {
                    stop.load(Ordering::SeqCst)
                        || Instant::now() >= deadline
                        || selection.generation() != generation
                };
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
                            shards: MAX_SHARDS,
                            queries: MAX_QUERIES,
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
        // A reply racing revocation is never an answer from the current server.
        if selection.generation() != generation {
            return Err(PrivateDiscoveryFailed);
        }
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
    use zakura_pir_client::transparent::Progress;

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

    #[tokio::test]
    async fn switching_servers_revokes_discovery_before_another_request() {
        use crate::wallet::sync_engine::enhancement::RequestObserver;
        for revoke in [false, true] {
            // A private selection keeps this test independent of other wallets.
            let selection: &'static SelectedServer = Box::leak(Box::new(SelectedServer::new()));
            selection.finish_switch(
                selection
                    .begin_switch(Some(super::super::pir::TEST_ORIGIN))
                    .unwrap()
                    .unwrap(),
            );
            let generation = selection.generation();
            let observer = RequestObserver::answering(move |request| {
                let (status, body) = if request.path == "/transparent/v1/filters/shards" {
                    // This valid map requires a second protocol request. The
                    // control below proves that the fixture reaches that step.
                    if revoke {
                        selection.finish_switch(selection.begin_switch(None).unwrap().unwrap());
                    }
                    (200, serde_json::to_vec(&serde_json::json!({
                        "genesis_hash": "00040fe8ec8471911baa1db1266ea15dd06b4a8a5c453883c000b031973dce08",
                        "network": "main", "profile": "zcash-transparent-range-v1",
                        "range_envelope_version": 1, "start_height": 1,
                        "seal": {"archive-wide": {"max_scripts": 1629038, "max_page_rows": 63488, "max_txids": 0}},
                        "shards": [{"shard_id": 0, "geometry": "archive-wide", "start_height": 1, "end_height": 20,
                            "parent_block_hash": "00".repeat(32), "terminal_block_hash": "33".repeat(32),
                            "filter_hash": "11".repeat(32), "scripts": 1, "page_rows": 1, "txids": 1,
                            "directory_segments": 1, "page_segments": 1, "manifest_digest": "22".repeat(32),
                            "revision": 0, "sealed": false}]
                    })).unwrap())
                } else {
                    (503, vec![])
                };
                http::Response::builder()
                    .status(status)
                    .body(http_body_util::Full::new(bytes::Bytes::from(body)))
                    .unwrap()
            });
            let seam =
                super::super::pir::test_transport::set("/discovery-revocation", observer.clone());
            let mut discovery =
                PrivateAccountDiscovery::new("/discovery-revocation", WalletNetwork::Main);
            discovery.selection = selection;
            discovery.generation = generation;
            let addresses = vec![TransparentAddress::PublicKeyHash([1; 20])];
            assert_eq!(
                discovery.active(1, addresses.clone()).await,
                Err(PrivateDiscoveryFailed)
            );
            assert_eq!(observer.requests().len(), if revoke { 1 } else { 2 });
            if revoke {
                assert_eq!(
                    discovery.active(1, addresses).await,
                    Err(PrivateDiscoveryFailed)
                );
                assert_eq!(
                    observer.requests().len(),
                    1,
                    "revoked discovery sends nothing else"
                );
            }
            drop(seam);
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
    async fn without_a_selected_server_there_is_no_private_discovery() {
        let discovery = PrivateAccountDiscovery::new("/nonexistent", WalletNetwork::Main);
        assert!(!discovery.is_available());
        assert_eq!(
            discovery
                .active(1, vec![TransparentAddress::PublicKeyHash([1; 20])])
                .await,
            Err(PrivateDiscoveryFailed)
        );
    }
}
