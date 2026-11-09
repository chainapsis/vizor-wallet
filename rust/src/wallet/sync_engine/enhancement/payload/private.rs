//! Stateful private Enhance PIR session handling.
//!
//! [`RoutedPayloadEnhancement`] retains accepted routing, refresh throttling,
//! deferred-failure state, and rediscovery attempts for one full sync. The
//! sibling scheduler owns transport selection; this module never converts a
//! private failure or suspension into public transaction-ID retrieval.
use super::super::content_failures;
use super::{
    super::{
        super::SyncError,
        transport::{client_protocol_error, RoutedHttpError},
    },
    coordinator::{EnhancementEffects, RecoveryWallet, RoutedWork},
    diagnostics::{mark_routing_refresh, routing_refresh_due, set_phase, RecoveryPhase},
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::pir_config::{client_origin, PirProduct};
use futures::StreamExt;
use std::collections::BTreeSet;
use zakura_pir_client::enhance::transport::{self, PendingClient};
use zakura_pir_client::enhance::wallet::{Acceptance, PreparedWork};
use zakura_pir_client::enhance::{ClientError, Manifest, RECORDS_PER_ROW};
use zcash_client_backend::data_api::enhance_pir::{
    EnhancePirStoreResult, IronwoodEnhanceDiscoveryRequest,
};
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;
use zcash_protocol::zip318::BlockSpacing;
/// The Enhance PIR endpoint: the selected wallet PIR server.
///
/// With no server selected the endpoint is empty. Private Enhance stays
/// enabled, so the empty endpoint fails URI validation before any request and
/// the sync defers exactly as for an unreachable service. It never turns
/// into public transaction retrieval.
fn enhance_endpoint() -> String {
    client_origin(PirProduct::Enhance).unwrap_or_default()
}

/// The rediscovery cover size in 75-second blocks, about two hours.
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

#[cfg(test)]
fn client_transport_error(error: EnhancePirRunError) -> ClientError {
    match error {
        EnhancePirRunError::ExitRequested => ClientError::Cancelled,
        EnhancePirRunError::HttpStatus(status) => ClientError::HttpStatus(status),
        EnhancePirRunError::Failed(error) => ClientError::Transport(error.to_string()),
    }
}

fn is_stale_routing_status(status: u16) -> bool {
    matches!(status, 409 | 410)
}

/// A cover range of up to [`REDISCOVERY_COVER_BLOCKS`] reference blocks containing
/// `height`. `draw_offset(cover)` (uniform below the cover size) shifts the window past
/// the target so it is not always the range endpoint; `tip` caps the end at known chain
/// state. The size follows the tip's spacing, not the target's, so a window that spans
/// NU7 activation does not tell on which side of it the target lies.
pub(super) fn rediscovery_cover_range(
    network: WalletNetwork,
    height: BlockHeight,
    tip: Option<BlockHeight>,
    draw_offset: impl FnOnce(u32) -> u32,
) -> (BlockHeight, BlockHeight) {
    let height = u32::from(height);
    let tip = tip.map_or(height, |tip| u32::from(tip).max(height));
    let cover = REDISCOVERY_COVER_BLOCKS
        * BlockSpacing::for_network(&network)
            .blocks_per_reference_block(BlockHeight::from_u32(tip));
    let end = height
        .saturating_add(draw_offset(cover).min(cover - 1))
        .min(tip);
    let start = end.saturating_sub(cover - 1);
    (BlockHeight::from_u32(start), BlockHeight::from_u32(end))
}

pub(super) fn random_rediscovery_offset(cover: u32) -> u32 {
    use rand::Rng;
    rand::thread_rng().gen_range(0..cover)
}

pub(in crate::wallet::sync_engine) struct RoutedPayloadEnhancement {
    network: WalletNetwork,
    pub(super) db_path: String,
    pub(super) endpoint: Option<String>,
    pending_routing: Option<PendingClient>,
    pub(super) accepted_routing: Option<transport::Client>,
    pub(super) private_failed_for_sync: bool,
    rediscovery_attempts: Vec<IronwoodEnhanceDiscoveryRequest>,
    /// The private work this drain may ask: the queries and rediscovery jobs
    /// that existed when its drain point began. Work a status, history or
    /// Enhance reply created since waits for the next block.
    pub(in crate::wallet::sync_engine) snapshot: Option<content_failures::PrivateWork>,
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
impl From<RoutedHttpError> for EnhancePirRunError {
    fn from(error: RoutedHttpError) -> Self {
        match error {
            RoutedHttpError::Cancelled => Self::ExitRequested,
            RoutedHttpError::HttpStatus(status) => Self::HttpStatus(status),
            RoutedHttpError::Failed(error) => Self::Failed(error),
        }
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
            endpoint: (enabled && network == WalletNetwork::Main).then(enhance_endpoint),
            pending_routing: None,
            accepted_routing: None,
            private_failed_for_sync: false,
            rediscovery_attempts: Vec::new(),
            snapshot: None,
        }
    }
    /// Test seam for a private Enhance endpoint on a network without one.
    #[cfg(test)]
    pub(in crate::wallet::sync_engine) fn set_endpoint(&mut self, endpoint: &str) {
        self.endpoint = Some(endpoint.to_owned());
    }

    pub(in crate::wallet::sync_engine) fn enabled(&self) -> bool {
        self.endpoint.is_some()
    }
    pub(super) fn private_work_enabled(&self) -> bool {
        self.enabled() && !self.private_failed_for_sync
    }
    pub(in crate::wallet::sync_engine) fn defer(&mut self) {
        self.private_failed_for_sync = true;
        set_phase(&self.db_path, RecoveryPhase::RetryingLater);
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
            self.pending_routing = None;
        }
        let session_refresh_due = self
            .accepted_routing
            .as_ref()
            .is_some_and(|routing| routing.refresh_due());
        if (force || uncovered || session_refresh_due)
            && self.pending_routing.is_none()
            && (force || session_refresh_due || routing_refresh_due(&self.db_path))
        {
            mark_routing_refresh(&self.db_path);
            self.pending_routing = Some(
                PendingClient::fetch(route, self.endpoint.as_deref().expect("enabled")).await?,
            );
        }
        let Some(pending) = self.pending_routing.as_ref() else {
            return Ok(self.accepted_routing.is_some());
        };
        match self.acceptance(db, pending.generation())? {
            Acceptance::Accepted(acceptance) => {
                if should_exit() {
                    return Err(EnhancePirRunError::ExitRequested);
                }
                let pending = self.pending_routing.take().expect("pending routing");
                if let Some(accepted_routing) = self.accepted_routing.as_mut() {
                    if !routing_is_current_or_newer(
                        accepted_routing.generation(),
                        pending.generation(),
                    ) {
                        set_phase(&self.db_path, RecoveryPhase::RetryingLater);
                        return Ok(!force);
                    }
                    accepted_routing.accept_routing(pending, &acceptance)?;
                } else {
                    self.accepted_routing = Some(pending.accept(&acceptance)?);
                }
                Ok(true)
            }
            Acceptance::WaitingForScanning => {
                set_phase(&self.db_path, RecoveryPhase::WaitingForScanning);
                Ok(false)
            }
            Acceptance::Mismatch => {
                self.pending_routing = None;
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
            if self.rediscovery_attempts.contains(&request) {
                continue;
            }
            self.rediscovery_attempts.push(request);
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
        let work = db
            .work()?
            .askable(&self.db_path, self.snapshot.as_ref())
            .prepared();
        if work.query_count() == 0 {
            return Ok(());
        }
        // Always revalidate after scans and rewinds, including cached coverage.
        if let Some(accepted_routing) = &self.accepted_routing {
            match self.acceptance(db, accepted_routing.generation())? {
                Acceptance::Accepted(_) => {}
                Acceptance::WaitingForScanning => {
                    set_phase(&self.db_path, RecoveryPhase::WaitingForScanning);
                    return Ok(());
                }
                Acceptance::Mismatch => {
                    self.accepted_routing = None;
                    self.pending_routing = None;
                    return Err(SyncError::parse("snapshot anchor mismatch").into());
                }
            }
        }
        let uncovered = self.accepted_routing.as_ref().is_none_or(|routing| {
            work.positions()
                .any(|position| position >= routing.generation().coverage.records)
        });
        set_phase(
            &self.db_path,
            if uncovered {
                RecoveryPhase::WaitingForSnapshot
            } else {
                RecoveryPhase::Recovering
            },
        );
        // Refresh is opportunistic: it must not suppress already accepted coverage.
        let refresh = self
            .refresh_routing(db, route, uncovered, false, should_exit)
            .await
            .map(|_| ());
        if !retain_coverage_on_refresh_failure(refresh, self.accepted_routing.is_some())? {
            self.pending_routing = None;
            set_phase(&self.db_path, RecoveryPhase::RetryingLater);
        }
        if self.accepted_routing.is_none() {
            return Ok(());
        }
        for attempt in 0..=1 {
            // Re-read after a partial batch: successfully stored rows are no
            // longer pending, and only the durable remainder is retried. Rows
            // that failed on content stay out of the retry, as an honest
            // reply would have completed them.
            let work = db
                .work()?
                .askable(&self.db_path, self.snapshot.as_ref())
                .prepared();
            if work.query_count() == 0 {
                break;
            }
            // Rejected before any network I/O when the batch exceeds the
            // client's input limit.
            let stale_status = {
                let accepted_routing = self.accepted_routing.as_mut().expect("checked above");
                match accepted_routing.query_batch(route, work.positions()) {
                    Err(ClientError::HttpStatus(status)) if is_stale_routing_status(status) => {
                        Some(status)
                    }
                    Err(error) => return Err(error.into()),
                    Ok(results) => {
                        futures::pin_mut!(results);
                        let mut stale = None;
                        let mut unreadable = BTreeSet::new();
                        // A request outcome inside the batch defers the
                        // rest of the sync once the batch has been asked to
                        // its end. The client stops dispatch on HTTP 429/503;
                        // stale routing and cancellation also stop below.
                        let mut refused = None;
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
                                Err(ClientError::Cancelled) => {
                                    return Err(EnhancePirRunError::ExitRequested)
                                }
                                // The reply arrived for this session, but its
                                // row, or this record in it, did not decode: a
                                // content failure, which a service could aim
                                // at chosen rows. Count it against the
                                // requests of its transaction in that row,
                                // once per row, and keep going so the rest of
                                // the batch is asked exactly as an honest
                                // reply would have it.
                                Err(error) if is_unreadable(&error) => {
                                    report_unreadable(
                                        db,
                                        &self.db_path,
                                        &work,
                                        result.position,
                                        &mut unreadable,
                                    )?;
                                    continue;
                                }
                                // A request outcome: the service chose it
                                // without knowing which row was asked.
                                Err(error) => {
                                    refused.get_or_insert(error);
                                    continue;
                                }
                                Ok(record) => record,
                            };
                            for (request, record) in work.map_record(result.position, record) {
                                match db.apply(request, &record)? {
                                    // The wallet rolled the record back and
                                    // counted it; it stops asking after three.
                                    // Like an unreadable record, it does not
                                    // stop the rest of the batch.
                                    EnhancePirStoreResult::Rejected => {
                                        content_failures::enhance(&self.db_path, [request]);
                                        log::warn!(
                                            "sync: a private Ironwood enhancement record failed wallet authentication"
                                        );
                                    }
                                    // Mixed transaction under a private transparent
                                    // policy: financial facts are kept and the
                                    // transparent details stay pending. Never a
                                    // retry or a public fallback.
                                    EnhancePirStoreResult::PrivateDetailsUnsupported => {
                                        log::info!(
                                            "sync: transparent details of a mixed transaction are unavailable under the private transparent policy"
                                        );
                                    }
                                    _ => {}
                                }
                            }
                        }
                        if let Some(error) = refused {
                            return Err(error.into());
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
            "sync: private recovery has {} active queries, {} rediscovery jobs, {} suspended obligations",
            remaining.query_count(),
            remaining.rediscover.len(),
            remaining.suspended
        );
        Ok(())
    }
}
/// Whether a row result failed on content: the reply matched the session,
/// but its row did not decrypt (`Pir`) or decode, or a record in it did not
/// (`Response`). A body over the size limit, or a reply whose length or
/// session binding does not match, is a request outcome like an HTTP
/// refusal, a transport or JSON error, or a rotated generation: the service
/// chooses those without knowing which row was asked.
fn is_unreadable(error: &ClientError) -> bool {
    match error {
        ClientError::Row(error) => match error.as_ref() {
            ClientError::Pir(_) => true,
            ClientError::Response(message) => !is_envelope_failure(message),
            _ => false,
        },
        // A record of a decoded row.
        ClientError::Response(_) => true,
        _ => false,
    }
}

/// `ClientError::Response` messages the Enhance client gives a row reply
/// before it reads the row: the body size, the framing and binding header,
/// and the expected length. The client has no typed error for these.
fn is_envelope_failure(message: &str) -> bool {
    matches!(
        message,
        "HTTP body exceeds limit"
            | "invalid query framing"
            | "PIR response binding or length mismatch"
            | "invalid PIR dimensions"
            | "unqualified native column count"
    )
}

/// Reports the requests whose record at `position` arrived but did not decode:
/// for each transaction with a request there, every request of that
/// transaction in the position's row, as the wallet counts content failures
/// per row reply. `reported` holds the (transaction, row) pairs already
/// counted in this batch, so a row with several bad records counts once.
fn report_unreadable(
    db: &mut impl RecoveryWallet,
    db_path: &str,
    work: &PreparedWork,
    position: u64,
    reported: &mut BTreeSet<(TxId, u64)>,
) -> Result<(), EnhancePirRunError> {
    let row = position / RECORDS_PER_ROW as u64;
    for ((txid, batch_row), requests) in work.batches_by_tx_and_row() {
        if batch_row == row
            && requests
                .iter()
                .any(|request| u64::from(request.position()) == position)
            && reported.insert((txid, row))
        {
            log::warn!("sync: a private Ironwood enhancement record did not decode");
            db.record_unreadable(&requests)?;
            content_failures::enhance(db_path, requests);
        }
    }
    Ok(())
}

/// A bad candidate cannot invalidate a separately revalidated current session.
/// Cancellation always wins, even when old coverage remains usable. A local
/// database failure is never a bad candidate: it is returned so the sync fails
/// instead of continuing on stale coverage.
fn retain_coverage_on_refresh_failure(
    refresh: Result<(), EnhancePirRunError>,
    has_coverage: bool,
) -> Result<bool, EnhancePirRunError> {
    match refresh {
        Ok(()) => Ok(true),
        Err(EnhancePirRunError::Failed(error))
            if has_coverage && !matches!(error, SyncError::Db(_)) =>
        {
            log::warn!("sync: snapshot refresh failed; retaining accepted coverage: {error}");
            Ok(false)
        }
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::super::super::transport::{await_request_with_cancel, secure_endpoint_uri};
    use super::super::diagnostics::{
        begin_session, mark_routing_refresh, phase, routing_refresh_due,
    };
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
    fn only_a_row_that_fails_to_decode_is_unreadable() {
        let row = |error| ClientError::Row(Arc::new(error));
        for unreadable in [
            row(ClientError::Pir("decryption failed".into())),
            row(ClientError::Response("short row".into())),
            ClientError::Response("invalid record flags".into()),
        ] {
            assert!(is_unreadable(&unreadable), "{unreadable}");
        }
        for refused in [
            row(ClientError::Response("HTTP body exceeds limit".into())),
            row(ClientError::Response("invalid query framing".into())),
            row(ClientError::Response(
                "PIR response binding or length mismatch".into(),
            )),
            row(ClientError::Transport("connection reset".into())),
            row(ClientError::HttpStatus(500)),
            row(ClientError::Generation("session rotated".into())),
            row(ClientError::Json(
                serde_json::from_str::<u8>("x").unwrap_err(),
            )),
            ClientError::HttpStatus(503),
            ClientError::Transport("connection reset".into()),
        ] {
            assert!(!is_unreadable(&refused), "{refused}");
        }
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
    fn refresh_db_failure_is_never_masked_by_coverage() {
        for covered in [false, true] {
            let result = retain_coverage_on_refresh_failure(
                Err(EnhancePirRunError::Failed(SyncError::Db(
                    "disk full".into(),
                ))),
                covered,
            );
            assert!(
                matches!(result, Err(EnhancePirRunError::Failed(SyncError::Db(_)))),
                "covered={covered}: a local write failure must surface, got {result:?}"
            );
        }
    }

    #[test]
    fn every_route_requires_an_https_endpoint() {
        assert!(secure_endpoint_uri("https://wallet-pir.example").is_ok());
        for url in [
            "http://enhance-pir.valargroup.dev",
            "http://127.0.0.1:8080",
            "enhance-pir.valargroup.dev",
            "not a url",
            "",
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

    const NU7_ACTIVATION: u32 = 3_543_405;

    fn cover_range(
        network: WalletNetwork,
        height: u32,
        tip: Option<u32>,
        offset: u32,
    ) -> (u32, u32) {
        let (start, end) = rediscovery_cover_range(
            network,
            BlockHeight::from_u32(height),
            tip.map(BlockHeight::from_u32),
            |_| offset,
        );
        (u32::from(start), u32::from(end))
    }

    #[test]
    fn rediscovery_cover_range_hides_the_target_position() {
        // About two hours of blocks in either era.
        for (h, tip, cover) in [
            (1_000, 2_000, REDISCOVERY_COVER_BLOCKS),
            (
                NU7_ACTIVATION + 1_000,
                NU7_ACTIVATION + 2_000,
                3 * REDISCOVERY_COVER_BLOCKS,
            ),
        ] {
            let mut target_positions = std::collections::HashSet::new();
            for offset in 0..cover {
                let (start, end) = cover_range(WalletNetwork::Main, h, Some(tip), offset);
                assert!(start <= h && h <= end, "offset {offset}");
                assert_eq!(end - start, cover - 1);
                assert!(start >= h - (cover - 1));
                target_positions.insert(end - h);
            }
            assert_eq!(target_positions.len(), cover as usize);
            // Out-of-range offsets are clamped to the cover size.
            assert_eq!(
                cover_range(WalletNetwork::Main, h, Some(tip), u32::MAX),
                (h, h + cover - 1),
            );
        }
    }

    #[test]
    fn rediscovery_cover_size_follows_the_tip_spacing() {
        let sizes = |h, tip| {
            let mut covers = Vec::new();
            rediscovery_cover_range(
                WalletNetwork::Main,
                BlockHeight::from_u32(h),
                Some(BlockHeight::from_u32(tip)),
                |cover| {
                    covers.push(cover);
                    0
                },
            );
            covers
        };
        // A target before activation with a later tip gets the wider window, the
        // same as a target just after it, so a window across activation does not
        // tell the two apart.
        assert_eq!(sizes(NU7_ACTIVATION - 10, NU7_ACTIVATION - 1), vec![100]);
        assert_eq!(sizes(NU7_ACTIVATION - 10, NU7_ACTIVATION + 500), vec![300]);
        assert_eq!(sizes(NU7_ACTIVATION + 10, NU7_ACTIVATION + 500), vec![300]);
        assert_eq!(
            cover_range(
                WalletNetwork::Main,
                NU7_ACTIVATION + 10,
                Some(NU7_ACTIVATION + 500),
                0
            ),
            (NU7_ACTIVATION - 289, NU7_ACTIVATION + 10),
        );
        // Regtest leaves NU7 unscheduled.
        assert_eq!(
            cover_range(WalletNetwork::Regtest, 1_000, Some(2_000), 0),
            (901, 1_000)
        );
        for cover in [100, 300] {
            assert!(random_rediscovery_offset(cover) < cover);
        }
    }

    #[test]
    fn rediscovery_cover_range_never_passes_the_known_tip() {
        let network = WalletNetwork::Regtest;
        assert_eq!(cover_range(network, 1_000, Some(1_010), 50), (911, 1_010));
        assert_eq!(cover_range(network, 1_000, None, 50), (901, 1_000));
        // A tip below the target (stale chain state) never excludes the target.
        assert_eq!(cover_range(network, 1_000, Some(900), 50), (901, 1_000));
        assert_eq!(cover_range(network, 50, None, 0), (0, 50));
    }

    #[test]
    fn refresh_is_rate_limited_across_foreground_sessions() {
        begin_session("refresh-test");
        assert!(routing_refresh_due("refresh-test"));
        mark_routing_refresh("refresh-test");
        begin_session("refresh-test");
        assert!(!routing_refresh_due("refresh-test"));
        begin_session("new-wallet");
        assert!(routing_refresh_due("new-wallet"));
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

        assert!(matches!(result, Err(RoutedHttpError::Cancelled)));
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
