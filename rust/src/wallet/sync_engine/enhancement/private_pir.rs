//! Stateful private Enhance PIR session handling.
//!
//! [`RoutedPayloadEnhancement`] retains accepted routing, refresh throttling,
//! deferred-failure state, and rediscovery attempts for one full sync. The
//! sibling scheduler owns transport selection; this module never converts a
//! private failure or suspension into public transaction-ID retrieval.
use super::{
    super::SyncError,
    scheduler::{EnhancementEffects, RecoveryWallet, RoutedWork},
    transport::client_protocol_error,
};
use crate::wallet::network::WalletNetwork;
use futures::StreamExt;
use std::time::{Duration, Instant};
use zakura_pir_enhance::transport::{self, PendingClient};
use zakura_pir_enhance::wallet::Acceptance;
use zakura_pir_enhance::{ClientError, Manifest};
use zcash_client_backend::data_api::enhance_pir::{
    EnhancePirStoreResult, IronwoodEnhanceDiscoveryRequest,
};
use zcash_protocol::consensus::BlockHeight;
const DEFAULT_MAINNET_ENDPOINT: &str = "https://enhance-pir.valargroup.dev";
const ENDPOINT_ENV: &str = "VIZOR_ENHANCE_PIR_URL";
const LEGACY_ENDPOINT_ENV: &str = "VIZOR_MEMO_PIR_URL";
const REDISCOVERY_COVER_BLOCKS: u32 = 100;
fn routing_is_current_or_newer(current: &Manifest, candidate: &Manifest) -> bool {
    current_or_newer_routing_revision(
        (current.generation, current.recovery_epoch),
        (candidate.generation, candidate.recovery_epoch),
    )
}

fn current_or_newer_routing_revision(current: (u64, u64), candidate: (u64, u64)) -> bool {
    candidate.0 >= current.0 && candidate.1 >= current.1
}

pub(super) fn client_transport_error(error: EnhancePirRunError) -> ClientError {
    match error {
        EnhancePirRunError::ExitRequested => ClientError::Cancelled,
        EnhancePirRunError::HttpStatus(status) => ClientError::HttpStatus(status),
        EnhancePirRunError::Failed(error) => ClientError::Transport(error.to_string()),
    }
}

fn is_stale_routing_status(status: u16) -> bool {
    matches!(status, 409 | 410)
}

pub(super) fn rediscovery_cover_start(height: BlockHeight) -> BlockHeight {
    BlockHeight::from_u32(
        u32::from(height).saturating_sub(REDISCOVERY_COVER_BLOCKS.saturating_sub(1)),
    )
}

pub(in crate::wallet::sync_engine) struct RoutedPayloadEnhancement {
    network: WalletNetwork,
    db_path: String,
    pub(super) endpoint: Option<String>,
    pending_session: Option<PendingClient>,
    pub(super) session: Option<transport::Client>,
    pub(super) deferred: bool,
    attempted_discovery: Vec<IronwoodEnhanceDiscoveryRequest>,
}
#[derive(Debug)]
pub(in crate::wallet::sync_engine) enum EnhancePirRunError {
    ExitRequested,
    HttpStatus(u16),
    Failed(SyncError),
}
impl From<SyncError> for EnhancePirRunError {
    fn from(e: SyncError) -> Self {
        Self::Failed(e)
    }
}
impl From<ClientError> for EnhancePirRunError {
    fn from(e: ClientError) -> Self {
        match e {
            ClientError::Cancelled => Self::ExitRequested,
            e => Self::Failed(client_protocol_error(e)),
        }
    }
}
impl RoutedPayloadEnhancement {
    pub(in crate::wallet::sync_engine) fn new(
        network: WalletNetwork,
        enabled: bool,
        db_path: &str,
    ) -> Self {
        Self {
            network,
            db_path: db_path.into(),
            endpoint: (enabled && network == WalletNetwork::Main).then(|| {
                std::env::var(ENDPOINT_ENV)
                    .or_else(|_| std::env::var(LEGACY_ENDPOINT_ENV))
                    .unwrap_or_else(|_| DEFAULT_MAINNET_ENDPOINT.into())
            }),
            pending_session: None,
            session: None,
            deferred: false,
            attempted_discovery: Vec::new(),
        }
    }
    pub(in crate::wallet::sync_engine) fn enabled(&self) -> bool {
        self.endpoint.is_some()
    }
    pub(super) fn private_work_enabled(&self) -> bool {
        self.enabled() && !self.deferred
    }
    pub(in crate::wallet::sync_engine) fn defer(&mut self) {
        self.deferred = true;
        set_phase(&self.db_path, "retrying_later");
    }
    fn acceptance(
        &self,
        db: &impl RecoveryWallet,
        generation: &Manifest,
    ) -> Result<Acceptance, EnhancePirRunError> {
        db.accept(self.network, generation)
    }
    /// Fetch routing without discarding an accepted session on a transient
    /// refresh failure. A rejected row query forces this path past the normal
    /// refresh timer; every candidate is checked against the scanned wallet.
    async fn refresh_routing(
        &mut self,
        db: &impl RecoveryWallet,
        route: &impl transport::Transport,
        uncovered: bool,
        force: bool,
        should_exit: &impl Fn() -> bool,
    ) -> Result<bool, EnhancePirRunError> {
        if force {
            self.pending_session = None;
        }
        let session_refresh_due = self.session.as_ref().is_some_and(|s| s.refresh_due());
        if (force || uncovered || session_refresh_due)
            && self.pending_session.is_none()
            && (force || session_refresh_due || refresh_due(&self.db_path))
        {
            mark_refresh(&self.db_path);
            self.pending_session = Some(
                PendingClient::fetch(route, self.endpoint.as_deref().expect("enabled")).await?,
            );
        }
        let Some(pending) = self.pending_session.as_ref() else {
            return Ok(self.session.is_some());
        };
        match self.acceptance(db, pending.generation())? {
            Acceptance::Accepted(acceptance) => {
                if should_exit() {
                    return Err(EnhancePirRunError::ExitRequested);
                }
                let pending = self.pending_session.take().expect("pending");
                if let Some(session) = self.session.as_mut() {
                    if !routing_is_current_or_newer(session.generation(), pending.generation()) {
                        set_phase(&self.db_path, "retrying_later");
                        return Ok(!force);
                    }
                    session.accept_routing(pending, &acceptance)?;
                } else {
                    self.session = Some(pending.accept(&acceptance)?);
                }
                Ok(true)
            }
            Acceptance::WaitingForScanning => {
                set_phase(&self.db_path, "waiting_for_scanning");
                Ok(false)
            }
            Acceptance::Mismatch => {
                self.pending_session = None;
                Err(SyncError::parse("snapshot anchor mismatch").into())
            }
        }
    }
    pub(super) async fn run_private<W: RecoveryWallet, E: EnhancementEffects<W>>(
        &mut self,
        db: &mut W,
        route: &impl transport::Transport,
        effects: &mut E,
        work: &RoutedWork,
        should_exit: &impl Fn() -> bool,
    ) -> Result<(), EnhancePirRunError> {
        for request in work.prepared().rediscover {
            // Partial reconstruction can leave active jobs at the same height.
            // Retry those on the next foreground poll, not every scan batch.
            if self.attempted_discovery.contains(&request) {
                continue;
            }
            self.attempted_discovery.push(request);
            if should_exit() {
                return Err(EnhancePirRunError::ExitRequested);
            }
            effects.rediscover(db, request, should_exit).await?;
        }
        self.run_queries(db, route, should_exit).await
    }

    /// An ordinary PIR failure defers retries until a new full-sync session.
    pub(super) fn defer_after(&mut self, error: EnhancePirRunError) {
        self.defer();
        match error {
            EnhancePirRunError::HttpStatus(status) => log::warn!(
                "sync: private Ironwood enhancement returned HTTP {status}; queued work will retry on a later sync"
            ),
            error => log::warn!(
                "sync: private Ironwood enhancement failed; queued work will retry on a later sync: {error:?}"
            ),
        }
    }

    pub(super) async fn run_queries(
        &mut self,
        db: &mut impl RecoveryWallet,
        route: &impl transport::Transport,
        should_exit: &impl Fn() -> bool,
    ) -> Result<(), EnhancePirRunError> {
        if should_exit() {
            return Err(EnhancePirRunError::ExitRequested);
        }
        let work = db.work()?.prepared();
        if work.query_count() == 0 {
            return Ok(());
        }
        // Always revalidate after scans and rewinds, including cached coverage.
        if let Some(session) = &self.session {
            match self.acceptance(db, session.generation())? {
                Acceptance::Accepted(_) => {}
                Acceptance::WaitingForScanning => {
                    set_phase(&self.db_path, "waiting_for_scanning");
                    return Ok(());
                }
                Acceptance::Mismatch => {
                    self.session = None;
                    self.pending_session = None;
                    return Err(SyncError::parse("snapshot anchor mismatch").into());
                }
            }
        }
        let uncovered = self.session.as_ref().is_none_or(|session| {
            work.positions()
                .any(|p| p >= session.generation().coverage.records)
        });
        set_phase(
            &self.db_path,
            if uncovered {
                "waiting_for_snapshot"
            } else {
                "recovering"
            },
        );
        // Refresh is opportunistic: it must not suppress already accepted coverage.
        let refresh = self
            .refresh_routing(db, route, uncovered, false, should_exit)
            .await
            .map(|_| ());
        if !retain_coverage_on_refresh_failure(refresh, self.session.is_some())? {
            self.pending_session = None;
            set_phase(&self.db_path, "retrying_later");
        }
        if self.session.is_none() {
            return Ok(());
        }
        for attempt in 0..=1 {
            // Re-read after a partial batch: successfully stored rows are no
            // longer pending, and only the durable remainder is retried.
            let work = db.work()?.prepared();
            if work.query_count() == 0 {
                break;
            }
            // Rejected before any network I/O when the batch exceeds the
            // client's input limit.
            let stale_status = {
                let session = self.session.as_mut().expect("checked above");
                match session.query_batch(route, work.positions()) {
                    Err(ClientError::HttpStatus(status)) if is_stale_routing_status(status) => {
                        Some(status)
                    }
                    Err(error) => return Err(error.into()),
                    Ok(results) => {
                        futures::pin_mut!(results);
                        let mut stale = None;
                        while let Some(result) = results.next().await {
                            if should_exit() {
                                return Err(EnhancePirRunError::ExitRequested);
                            }
                            let record = match result.record {
                                Err(ClientError::OutsideCoverage(_)) => continue,
                                Err(ClientError::HttpStatus(status))
                                    if is_stale_routing_status(status) =>
                                {
                                    stale = Some(status);
                                    break;
                                }
                                result => result?,
                            };
                            for (request, record) in work.map_record(result.position, record) {
                                let result = db.apply(request, &record)?;
                                if result == EnhancePirStoreResult::Rejected {
                                    return Err(SyncError::parse(
                                        "PIR record failed wallet authentication",
                                    )
                                    .into());
                                }
                            }
                        }
                        stale
                    }
                }
            };
            let Some(status) = stale_status else {
                break;
            };
            if attempt == 1 {
                return Err(ClientError::HttpStatus(status).into());
            }
            log::info!(
                "sync: Enhance PIR routing became stale (HTTP {status}); refreshing and retrying unfinished work"
            );
            if !self
                .refresh_routing(db, route, true, true, should_exit)
                .await?
            {
                return Ok(());
            }
        }
        let remaining = db.work()?.prepared();
        log::info!(
            "sync: private recovery has {} active queries, {} rediscovery jobs, and {} suspended obligations",
            remaining.query_count(),
            remaining.rediscover.len(),
            remaining.suspended
        );
        Ok(())
    }
}
/// A bad candidate cannot invalidate a separately revalidated current session.
/// Cancellation always wins, even when old coverage remains usable.
fn retain_coverage_on_refresh_failure(
    refresh: Result<(), EnhancePirRunError>,
    has_coverage: bool,
) -> Result<bool, EnhancePirRunError> {
    match refresh {
        Ok(()) => Ok(true),
        Err(EnhancePirRunError::Failed(error)) if has_coverage => {
            log::warn!("sync: snapshot refresh failed; retaining accepted coverage: {error}");
            Ok(false)
        }
        Err(error) => Err(error),
    }
}

#[derive(Default)]
struct ServiceState {
    path: String,
    phase: String,
    last_refresh: Option<Instant>,
}
static SERVICE: std::sync::Mutex<Option<ServiceState>> = std::sync::Mutex::new(None);
pub(in crate::wallet::sync_engine) fn begin_session(path: &str) {
    let mut state = SERVICE.lock().unwrap_or_else(|e| e.into_inner());
    if state.as_ref().is_none_or(|s| s.path != path) {
        *state = Some(ServiceState {
            path: path.into(),
            ..Default::default()
        });
    }
    state.as_mut().unwrap().phase.clear();
}
fn set_phase(path: &str, phase: &str) {
    let mut state = SERVICE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(state) = state.as_mut().filter(|s| s.path == path) {
        state.phase = phase.into();
    }
}
fn refresh_due(path: &str) -> bool {
    SERVICE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .filter(|s| s.path == path)
        .and_then(|s| s.last_refresh)
        .is_none_or(|t| t.elapsed() >= Duration::from_secs(60))
}
fn mark_refresh(path: &str) {
    if let Some(state) = SERVICE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_mut()
        .filter(|s| s.path == path)
    {
        state.last_refresh = Some(Instant::now());
    }
}
pub(in crate::wallet::sync_engine) fn phase(path: &str) -> String {
    SERVICE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .filter(|s| s.path == path)
        .map(|s| s.phase.clone())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::super::transport::{await_request_with_cancel, secure_endpoint_uri};
    use super::*;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };

    struct StaticTransport(Vec<u8>);
    impl transport::Transport for StaticTransport {
        async fn execute(
            &self,
            request: transport::Request,
        ) -> Result<transport::ResponseBody, ClientError> {
            let mut body = request.response_body();
            body.extend(&self.0)?;
            Ok(body.finish())
        }
    }

    #[test]
    fn routing_refresh_accepts_equal_revision_and_never_downgrades() {
        let current = (37, 0);
        assert!(current_or_newer_routing_revision(current, (38, 0)));
        assert!(current_or_newer_routing_revision(current, (37, 1)));
        assert!(current_or_newer_routing_revision(current, current));
        assert!(!current_or_newer_routing_revision(current, (36, 0)));
        assert!(!current_or_newer_routing_revision((37, 1), (37, 0)));
    }

    #[test]
    fn routed_http_status_is_preserved_for_recovery() {
        for status in [409, 410, 429, 502] {
            assert!(matches!(
                client_transport_error(EnhancePirRunError::HttpStatus(status)),
                ClientError::HttpStatus(actual) if actual == status
            ));
        }
        assert!(is_stale_routing_status(409));
        assert!(is_stale_routing_status(410));
        assert!(!is_stale_routing_status(429));
        assert!(!is_stale_routing_status(502));
    }

    #[test]
    fn refresh_failure_preserves_coverage_but_never_swallows_cancellation() {
        for message in [
            "initialization HTTP failure",
            "snapshot anchor mismatch",
            "invalid setup",
        ] {
            let failure = || Err(EnhancePirRunError::Failed(SyncError::parse(message)));
            assert!(!retain_coverage_on_refresh_failure(failure(), true).unwrap());
            assert!(retain_coverage_on_refresh_failure(failure(), false).is_err());
        }
        for covered in [false, true] {
            assert!(matches!(
                retain_coverage_on_refresh_failure(Err(EnhancePirRunError::ExitRequested), covered),
                Err(EnhancePirRunError::ExitRequested)
            ));
            assert!(retain_coverage_on_refresh_failure(Ok(()), covered).unwrap());
        }
    }

    #[test]
    fn every_route_requires_an_https_endpoint() {
        assert!(secure_endpoint_uri(DEFAULT_MAINNET_ENDPOINT).is_ok());
        for url in [
            "http://enhance-pir.valargroup.dev",
            "http://127.0.0.1:8080",
            "enhance-pir.valargroup.dev",
            "not a url",
        ] {
            assert!(secure_endpoint_uri(url).is_err(), "accepted {url}");
        }
    }

    #[test]
    fn only_mainnet_is_enabled() {
        assert!(RoutedPayloadEnhancement::new(WalletNetwork::Main, true, "test").enabled());
        assert!(!RoutedPayloadEnhancement::new(WalletNetwork::Main, false, "test").enabled());
        assert!(!RoutedPayloadEnhancement::new(WalletNetwork::Test, true, "test").enabled());
        assert!(!RoutedPayloadEnhancement::new(WalletNetwork::Regtest, true, "test").enabled());
    }

    #[test]
    fn rediscovery_uses_a_trailing_hundred_block_cover_range() {
        assert_eq!(
            rediscovery_cover_start(BlockHeight::from_u32(1_000)),
            BlockHeight::from_u32(901),
        );
        assert_eq!(
            rediscovery_cover_start(BlockHeight::from_u32(50)),
            BlockHeight::from_u32(0),
        );
    }

    #[test]
    fn refresh_is_rate_limited_across_foreground_sessions() {
        begin_session("refresh-test");
        assert!(refresh_due("refresh-test"));
        mark_refresh("refresh-test");
        begin_session("refresh-test");
        assert!(!refresh_due("refresh-test"));
        begin_session("new-wallet");
        assert!(refresh_due("new-wallet"));
        assert_eq!(phase("refresh-test"), "");
    }

    #[tokio::test]
    async fn cancellation_drops_an_in_flight_pir_request() {
        let cancelled = Arc::new(AtomicBool::new(false));
        let flip = cancelled.clone();
        let should_exit = || cancelled.load(Ordering::Acquire);
        let cancelling = tokio::spawn(async move {
            tokio::task::yield_now().await;
            flip.store(true, Ordering::Release);
        });

        let result = await_request_with_cancel(
            std::future::pending::<Result<(), SyncError>>(),
            &should_exit,
            "unused timeout",
        )
        .await;

        assert!(matches!(result, Err(EnhancePirRunError::ExitRequested)));
        cancelling.await.unwrap();
    }

    #[tokio::test]
    async fn malformed_initialization_response_is_rejected() {
        let result = PendingClient::fetch(
            &StaticTransport(b"not a valid initialization document".to_vec()),
            "https://example.test",
        )
        .await;

        assert!(matches!(result, Err(ClientError::Json(_))));
    }
}
