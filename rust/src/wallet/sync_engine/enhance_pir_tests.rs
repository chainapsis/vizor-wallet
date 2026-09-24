//! Exercises the production scheduler with the real v7 client and a scripted
//! service. Storage is faked here: wallet record authentication has its own tests.
use super::*;
use base64::Engine;
use sha2::{Digest, Sha256};
use std::{
    cell::{Cell, RefCell},
    collections::VecDeque,
};
use zakura_pir_enhance::{types::*, AcceptedAnchor, GenerationAcceptance};
use zcash_client_backend::data_api::enhance_pir::{EnhancePirWork, IronwoodEnhanceRequestId};
use zcash_primitives::transaction::TxId;

struct Service {
    manifest: RefCell<Manifest>,
    statuses: RefCell<VecDeque<Option<u16>>>,
    init_count: Cell<usize>,
    session_count: Cell<usize>,
    posts: RefCell<Vec<QueryBinding>>,
    cancelled: Cell<bool>,
    cancel_on_refresh: Cell<bool>,
    fail_refresh: Cell<bool>,
}

impl Service {
    fn new(statuses: impl IntoIterator<Item = Option<u16>>) -> Self {
        let coverage = Lifecycle::default()
            .coverage(100, Geometry::default())
            .unwrap();
        let shard = &coverage.shards[0];
        let public = public_params(shard.logical_rows);
        let manifest = Manifest {
            recovery_epoch: 0,
            placement_revision: 1,
            domain_recovery_epochs: [(0, "0".into())].into(),
            schema_version: SCHEMA_VERSION,
            protocol_revision: PROTOCOL_REVISION.into(),
            network: "main".into(),
            pool: "ironwood".into(),
            generation: 1,
            anchor_height: 3428143,
            anchor_block_hash: "42".repeat(32),
            geometry: Geometry::default(),
            sessions: vec![SessionRef {
                shard_id: shard.id,
                public_params_sha256: hex::encode(Sha256::digest(&public)),
                parameter_id: parameter_id(shard.logical_rows).unwrap(),
            }],
            unit_identities: [(
                shard.id,
                shard
                    .units
                    .iter()
                    .map(|unit| UnitIdentity {
                        recovery_epoch: 0,
                        table: "enhance".into(),
                        shard_id: shard.id,
                        local_row_start: unit.local_row_start,
                        allocated_rows: unit.allocated_rows,
                        setup_sha256: hex::encode(Sha256::digest(setup_seed(shard.id))),
                        parameter_id: unit_parameter_id(unit.allocated_rows).unwrap(),
                        content_sha256: "00".repeat(32),
                    })
                    .collect(),
            )]
            .into(),
            coverage,
        };
        manifest.validate().unwrap();
        Self {
            manifest: RefCell::new(manifest),
            statuses: RefCell::new(statuses.into_iter().collect()),
            init_count: Cell::new(0),
            session_count: Cell::new(0),
            posts: RefCell::new(vec![]),
            cancelled: Cell::new(false),
            cancel_on_refresh: Cell::new(false),
            fail_refresh: Cell::new(false),
        }
    }
}

fn public_params(rows: u64) -> Vec<u8> {
    let params = parameters(rows).unwrap();
    let (rlwe, _) = ipir_sp::params_for_simplepir_profile(
        rows,
        ITEM_SIZE_BITS,
        ipir_sp::SimplePirProfile::P16Q48,
    )
    .unwrap();
    vec![0; params.db_cols / rlwe.d * ipir_sp::modulus_switch::published_c1_len(rlwe.d, rlwe.q)]
}

impl transport::Transport for Service {
    async fn execute(
        &self,
        request: transport::Request,
    ) -> Result<transport::ResponseBody, ClientError> {
        assert!(!self.cancelled.get(), "network dispatch after cancellation");
        let bytes = if request.url.ends_with("/init") {
            self.init_count.set(self.init_count.get() + 1);
            if self.init_count.get() > 1 {
                if self.fail_refresh.get() {
                    return Err(ClientError::HttpStatus(503));
                }
                // Rotate routing while keeping the anchor and coverage unchanged.
                self.manifest.borrow_mut().generation += 1;
                if self.cancel_on_refresh.get() {
                    self.cancelled.set(true);
                }
            }
            serde_json::to_vec(&*self.manifest.borrow()).unwrap()
        } else if request.url.contains("/session/") {
            self.session_count.set(self.session_count.get() + 1);
            let m = self.manifest.borrow();
            let shard = &m.coverage.shards[0];
            assert!(request
                .url
                .ends_with(&hex::encode(m.session_id(shard.id).unwrap())));
            serde_json::to_vec(&ShardSession {
                session_id: hex::encode(m.session_id(shard.id).unwrap()),
                generation: m.generation,
                shard_id: shard.id,
                params: parameters(shard.logical_rows).unwrap(),
                public_params_base64: base64::engine::general_purpose::STANDARD
                    .encode(public_params(shard.logical_rows)),
            })
            .unwrap()
        } else {
            assert!(request.url.ends_with("/query"));
            let binding = QueryBinding::decode(&request.body).unwrap();
            self.posts.borrow_mut().push(binding.clone());
            if let Some(Some(status)) = self.statuses.borrow_mut().pop_front() {
                return Err(ClientError::HttpStatus(status));
            }
            let m = self.manifest.borrow();
            assert_eq!(
                binding.generation, m.generation,
                "query did not rebind to refreshed routing"
            );
            let params = parameters(m.coverage.shards[0].logical_rows).unwrap();
            let mut response = binding.encode();
            response.resize(
                HEADER_BYTES
                    + params.db_cols / params.poly_len
                        * ipir_sp::modulus_switch::response_body_len(
                            params.poly_len,
                            params.q_prime_1,
                        ),
                0,
            );
            response
        };
        let mut body = request.response_body();
        body.extend(&bytes)?;
        Ok(body.finish())
    }
}

#[derive(Clone, Copy)]
enum Anchor {
    Accepted,
    Waiting,
    Mismatch,
}
struct Wallet {
    pending: Vec<EnhancePirRequest>,
    applied: Vec<u64>,
    reads: Cell<usize>,
    refreshed_anchor: Anchor,
}
impl Wallet {
    fn new(positions: &[u64]) -> Self {
        Self {
            pending: positions
                .iter()
                .map(|&p| {
                    EnhancePirRequest::new(
                        p.into(),
                        IronwoodEnhanceRequestId::new(TxId::from_bytes([7; 32]), p as u32),
                    )
                })
                .collect(),
            applied: vec![],
            reads: Cell::new(0),
            refreshed_anchor: Anchor::Accepted,
        }
    }
}
impl RecoveryWallet for Wallet {
    fn work(&self) -> Result<PreparedWork, EnhancePirRunError> {
        self.reads.set(self.reads.get() + 1);
        Ok(PreparedWork::new(
            self.pending.iter().copied().map(EnhancePirWork::Query),
        ))
    }
    fn accept(&self, _: WalletNetwork, m: &Manifest) -> Result<Acceptance, EnhancePirRunError> {
        if m.generation > 1 {
            match self.refreshed_anchor {
                Anchor::Waiting => return Ok(Acceptance::WaitingForScanning),
                Anchor::Mismatch => return Ok(Acceptance::Mismatch),
                Anchor::Accepted => (),
            }
        }
        let acceptance = GenerationAcceptance::new(
            "main",
            3428143,
            AcceptedAnchor::new(m.anchor_height, [0x42; 32], m.coverage.records),
            ClientResourceLimits::new(MAX_LOGICAL_ROWS),
        );
        acceptance.validate(m)?;
        Ok(Acceptance::Accepted(acceptance))
    }
    fn apply(
        &mut self,
        request: EnhancePirRequest,
        _: &EnhanceRecord,
    ) -> Result<EnhancePirStoreResult, EnhancePirRunError> {
        assert!(
            self.pending.contains(&request),
            "replayed an already committed request"
        );
        self.pending.retain(|r| *r != request);
        self.applied.push(u64::from(request.position()));
        Ok(EnhancePirStoreResult::Stored)
    }
}
fn sync() -> EnhancePirSync {
    let mut sync = EnhancePirSync::new(WalletNetwork::Main, true, "scripted-pir-wallet");
    sync.endpoint = Some("https://example.test".into());
    sync
}

#[tokio::test]
async fn stale_routing_refreshes_equal_coverage_and_retries_only_unfinished_work() {
    for status in [409, 410] {
        let service = Service::new([None, Some(status), None]);
        let mut wallet = Wallet::new(&[0, 33]);
        let mut sync = sync();
        sync.run_queries(&mut wallet, &service, &|| false)
            .await
            .unwrap();
        assert!(wallet.pending.is_empty());
        assert_eq!(wallet.applied, [0, 33]);
        assert_eq!(service.init_count.get(), 2);
        assert_eq!(service.posts.borrow().len(), 3);
        assert_eq!(
            service.session_count.get(),
            1,
            "unchanged material should be reused"
        );
        assert_eq!(sync.session.as_ref().unwrap().generation().generation, 2);
        assert!(wallet.reads.get() >= 3);
        let posts = service.posts.borrow();
        assert_ne!(
            posts[1].request_id, posts[2].request_id,
            "retry must have a fresh binding"
        );
    }
}

#[tokio::test]
async fn repeated_stale_routing_stops_after_one_retry_and_keeps_work() {
    let service = Service::new([Some(409), Some(410)]);
    let mut wallet = Wallet::new(&[0]);
    assert!(sync()
        .run_queries(&mut wallet, &service, &|| false)
        .await
        .is_err());
    assert_eq!(service.posts.borrow().len(), 2);
    assert_eq!(service.init_count.get(), 2);
    assert_eq!(wallet.pending.len(), 1);
    assert!(wallet.applied.is_empty());
}

#[tokio::test]
async fn unaccepted_refresh_never_dispatches_a_retry() {
    for anchor in [Anchor::Waiting, Anchor::Mismatch] {
        let service = Service::new([Some(409)]);
        let mut wallet = Wallet::new(&[0]);
        wallet.refreshed_anchor = anchor;
        let result = sync().run_queries(&mut wallet, &service, &|| false).await;
        assert_eq!(result.is_ok(), matches!(anchor, Anchor::Waiting));
        assert_eq!(service.posts.borrow().len(), 1);
        assert_eq!(wallet.pending.len(), 1);
    }
}

#[tokio::test]
async fn cancellation_during_refresh_prevents_rebinding_and_retry() {
    let service = Service::new([Some(409)]);
    service.cancel_on_refresh.set(true);
    let mut wallet = Wallet::new(&[0]);
    let mut sync = sync();
    assert!(matches!(
        sync.run_queries(&mut wallet, &service, &|| service.cancelled.get())
            .await,
        Err(EnhancePirRunError::ExitRequested)
    ));
    assert_eq!(service.posts.borrow().len(), 1);
    assert_eq!(wallet.pending.len(), 1);
    assert_eq!(sync.session.as_ref().unwrap().generation().generation, 1);
}

#[tokio::test]
async fn failed_refresh_keeps_unfinished_work_without_another_query() {
    let service = Service::new([Some(409)]);
    service.fail_refresh.set(true);
    let mut wallet = Wallet::new(&[0]);
    assert!(sync()
        .run_queries(&mut wallet, &service, &|| false)
        .await
        .is_err());
    assert_eq!(service.posts.borrow().len(), 1);
    assert_eq!(wallet.pending.len(), 1);
}

// Obtain the opaque protocol body collector through its supported Request API.
async fn collector() -> BoundedBody {
    struct Capture(RefCell<Option<BoundedBody>>);
    impl transport::Transport for Capture {
        async fn execute(
            &self,
            request: transport::Request,
        ) -> Result<transport::ResponseBody, ClientError> {
            self.0.replace(Some(request.response_body()));
            Err(ClientError::Cancelled)
        }
    }
    let capture = Capture(RefCell::new(None));
    let _ = PendingClient::fetch(&capture, "https://example.test").await;
    capture.0.into_inner().unwrap()
}

#[tokio::test(start_paused = true)]
async fn error_status_does_not_read_truncated_or_stalled_body() {
    for status in [409, 410] {
        for stalled in [false, true] {
            let polled = Cell::new(false);
            let stream = futures::stream::poll_fn(|_| {
                polled.set(true);
                if stalled {
                    std::task::Poll::Pending
                } else {
                    std::task::Poll::Ready(Some(Err::<hyper::body::Frame<Bytes>, _>("truncated")))
                }
            });
            let response = http::Response::builder()
                .status(status)
                .body(http_body_util::StreamBody::new(stream))
                .unwrap();
            let started = tokio::time::Instant::now();
            let result = receive_response(
                std::future::ready(Ok::<_, SyncError>(response)),
                collector().await,
                &|| false,
            )
            .await;
            assert!(matches!(result, Err(EnhancePirRunError::HttpStatus(s)) if s == status));
            assert!(!polled.get());
            assert_eq!(tokio::time::Instant::now(), started);
        }
    }
}

#[tokio::test(start_paused = true)]
async fn headers_and_body_share_one_deadline() {
    let collector = collector().await;
    let request = async {
        tokio::time::sleep(Duration::from_secs(100)).await; // response headers
        let stream = futures::stream::once(async {
            tokio::time::sleep(Duration::from_secs(100)).await;
            Ok::<_, std::convert::Infallible>(hyper::body::Frame::data(Bytes::from_static(b"ok")))
        })
        .boxed();
        Ok::<_, SyncError>(http::Response::new(http_body_util::StreamBody::new(stream)))
    };
    let started = tokio::time::Instant::now();
    assert!(matches!(
        receive_response(request, collector, &|| false).await,
        Err(EnhancePirRunError::Failed(_))
    ));
    assert_eq!(tokio::time::Instant::now() - started, HTTP_TIMEOUT);
}

#[tokio::test]
async fn cancellation_wins_over_an_available_error_status() {
    let response = http::Response::builder()
        .status(409)
        .body(Full::new(Bytes::new()))
        .unwrap();
    assert!(matches!(
        receive_response(
            std::future::ready(Ok::<_, SyncError>(response)),
            collector().await,
            &|| true,
        )
        .await,
        Err(EnhancePirRunError::ExitRequested)
    ));
}

#[tokio::test]
async fn successful_bodies_are_collected_and_invalid_bodies_are_rejected() {
    let response = http::Response::new(Full::new(Bytes::from_static(b"response")));
    let result = receive_response(
        std::future::ready(Ok::<_, SyncError>(response)),
        collector().await,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(result.as_ref(), b"response");

    let oversized = http::Response::new(Full::new(Bytes::from(vec![
        0;
        transport::MAX_MANIFEST_BYTES
            + 1
    ])));
    assert!(receive_response(
        std::future::ready(Ok::<_, SyncError>(oversized)),
        collector().await,
        &|| false
    )
    .await
    .is_err());
    let truncated =
        http_body_util::StreamBody::new(futures::stream::iter([
            Err::<hyper::body::Frame<Bytes>, _>("truncated successful response"),
        ]));
    assert!(receive_response(
        std::future::ready(Ok::<_, SyncError>(http::Response::new(truncated))),
        collector().await,
        &|| false
    )
    .await
    .is_err());
}

#[tokio::test(start_paused = true)]
async fn cancellation_interrupts_a_stalled_success_body() {
    let cancelled = Cell::new(false);
    let body = http_body_util::StreamBody::new(futures::stream::pending::<
        Result<hyper::body::Frame<Bytes>, &'static str>,
    >());
    let collector = collector().await;
    let started = tokio::time::Instant::now();
    let should_exit = || cancelled.get();
    let request = receive_response(
        std::future::ready(Ok::<_, SyncError>(http::Response::new(body))),
        collector,
        &should_exit,
    );
    let cancel = async {
        tokio::time::sleep(Duration::from_secs(1)).await;
        cancelled.set(true);
    };
    let (result, ()) = tokio::join!(request, cancel);
    assert!(matches!(result, Err(EnhancePirRunError::ExitRequested)));
    assert!(tokio::time::Instant::now() - started < HTTP_TIMEOUT);
}
