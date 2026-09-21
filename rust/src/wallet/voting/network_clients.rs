//! Single construction boundary for network-capable voting SDK clients.
//! Every role uses the same process-wide transport. SDK defaults are direct;
//! injecting the chain transport alone does not configure the tree transport.

use super::route::VizorRoute;
use std::sync::{Arc, OnceLock};
use zcash_voting::{config::PirLayout, storage::VotingDb};
use zcash_voting::{
    ChainSubmissionClientConfig, ChainSubmissionFailure, HelperClient, HelperHealth,
    HyperTransport, PirFleet, RoundExecutor, VotingError,
};

pub(crate) type RoutedExecutor = RoundExecutor<Arc<HyperTransport<VizorRoute>>>;

pub(crate) fn routed_transport() -> Arc<HyperTransport<VizorRoute>> {
    static TRANSPORT: OnceLock<Arc<HyperTransport<VizorRoute>>> = OnceLock::new();
    TRANSPORT
        .get_or_init(|| Arc::new(HyperTransport::with_route(VizorRoute::new())))
        .clone()
}

pub(crate) fn helper_client(health: &HelperHealth) -> HelperClient {
    HelperClient::new(routed_transport(), health.clone())
}

pub(crate) fn pir_fleet(urls: &[String], layout: PirLayout) -> Result<Arc<PirFleet>, VotingError> {
    PirFleet::new(urls, layout, routed_transport()).map(Arc::new)
}

pub(crate) fn round_executor(
    database: Arc<VotingDb>,
    config: ChainSubmissionClientConfig,
    health: &HelperHealth,
) -> Result<RoutedExecutor, ChainSubmissionFailure> {
    RoundExecutor::with_transport(database, routed_transport(), config, helper_client(health))
        .map(|executor| executor.with_tree_transport(routed_transport()))
}

pub(crate) fn sync_vote_tree(db: &VotingDb, round_id: &str, url: &str) -> Result<u32, VotingError> {
    zcash_voting::precompute::sync_vote_tree_with(db, round_id, url, routed_transport())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn helper_factory_fails_closed_when_tor_is_unavailable() {
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        let server = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        server.set_nonblocking(true).unwrap();
        crate::network_privacy::begin_tor_enable();
        crate::network_privacy::fail_tor_enable();
        let result = helper_client(&HelperHealth::default())
            .preflight_fleet(&[format!("http://{}", server.local_addr().unwrap())])
            .await;
        assert!(result.is_err() || result.unwrap().ready_server_count() == 0);
        assert!(matches!(server.accept(), Err(e) if e.kind() == std::io::ErrorKind::WouldBlock));
    }

    // A supplemental source guard: it cannot prove routing, but catches the
    // SDK's default-direct constructors being reintroduced outside this factory.
    #[test]
    fn sdk_network_construction_stays_in_the_factory() {
        fn walk(dir: &std::path::Path, files: &mut Vec<std::path::PathBuf>) {
            for entry in std::fs::read_dir(dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    walk(&path, files);
                } else if path.extension().is_some_and(|ext| ext == "rs") {
                    files.push(path);
                }
            }
        }
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
        let mut files = Vec::new();
        walk(&root, &mut files);
        for path in files {
            if path.ends_with("voting/network_clients.rs") || path.ends_with("frb_generated.rs") {
                continue;
            }
            let source = std::fs::read_to_string(&path).unwrap();
            let code: String = source
                .lines()
                .filter(|line| !line.trim_start().starts_with("//"))
                .collect::<Vec<_>>()
                .join("\n")
                .chars()
                .filter(|ch| !ch.is_whitespace())
                .collect();
            for forbidden in [
                "HyperTransport::new(",
                "HyperTransport::default(",
                "RoundExecutor::new(",
                "RoundExecutor::with_transport(",
                "HelperClient::new(",
                "PirFleet::new(",
                "VoteTreeSync::new(",
                "VoteTreeSync::with_transport(",
                ".with_tree_transport(",
                "zcash_voting::precompute::sync_vote_tree(",
                "zcash_voting::precompute::sync_vote_tree_with(",
            ] {
                assert!(
                    !code.contains(forbidden),
                    "{} bypasses voting network factory: {forbidden}",
                    path.display()
                );
            }
            // route.rs has dedicated transport-level tests for its implementation.
            if !path.ends_with("voting/route.rs") {
                assert!(
                    !code.contains("HyperTransport::with_route("),
                    "{} constructs an SDK transport outside the factory",
                    path.display()
                );
            }
        }
    }
}
