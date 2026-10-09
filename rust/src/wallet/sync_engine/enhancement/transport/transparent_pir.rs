//! Transparent PIR over the wallet's routed HTTPS transport.
//!
//! The reference adapter in `zakura_pir_transparent` retrieves through two
//! synchronous traits its caller supplies: [`FilterSource`] for the public
//! shard map and filters, and [`ShardTransport`] for init, manifests, setup and
//! private queries. Both halves here share one [`RoutedTransport`], so every
//! request takes the route the other private services take: HTTPS only, Tor
//! when the wallet wants it and the direct-route lease otherwise, no
//! User-Agent, and the sync's cancellation.
//!
//! The traits are synchronous and the route is async, so each request blocks on
//! the runtime handle. Callers run a pass inside `spawn_blocking`;
//! `Handle::block_on` panics on a runtime worker.
//!
//! Nothing is retried and no filter is memoized. wallet-pir's sync decides what
//! a refusal is worth, and a republished tail reuses its shard id with a new
//! filter. A shard-bound 429, or 503 without `retry-after`, is still the
//! service refusing for capacity: it is reported as wallet-pir's
//! [`Overloaded`], whose retries and backoff stay within the sync's caps. A
//! failure that says the service cannot be reached or is not serving (a
//! failed route or connection, a timeout, a public-route 429 or 5xx, or any
//! other 5xx) is recorded as an outage, so the caller stops instead of trying
//! every account. Logs name the route template, never a shard id, digest or
//! body.

use bytes::Bytes;
use http::{header::RETRY_AFTER, Method, StatusCode};
use http_body_util::BodyExt;
use hyper::body::Body;
use std::{
    fmt,
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};
use tokio::runtime::Handle;
use zakura_pir_transparent::{
    refusal, BoxError, FilterSource, Overloaded, ShardRequest, ShardTransport, Table,
};

use super::{routed_response, secure_endpoint_uri, RoutedHttpError, RoutedTransport};
use crate::wallet::sync_engine::{watch_for_exit, SyncError};

/// One request's bound, from dispatch through the last body byte.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

/// Error-body bytes read from a shard-bound refusal. A stale refusal's body
/// carries the service's map digest, a diagnostic; the status is the refusal,
/// so a longer or failed body costs only that digest.
const ERROR_BODY_LIMIT: usize = 4096;

/// Both transparent PIR transports over one routed HTTPS client.
///
/// One per pass: [`split`](Self::split) hands the adapter its two halves. Every
/// request is bounded by [`REQUEST_TIMEOUT`] and stops when `should_exit`
/// does. A successful body over `response_limit` fails the request.
pub(crate) struct TransparentPirHttp<'a, F> {
    route: RoutedTransport<'a, F>,
    /// The configured origin, without a trailing slash.
    origin: String,
    handle: Handle,
    response_limit: usize,
    /// Set once any request failed in a way that says the service is down or
    /// not serving.
    outage: AtomicBool,
    #[cfg(test)]
    observer: Option<RequestObserver>,
}

/// The public half: the shard map and filters.
pub(crate) struct PirFilters<'t, 'a, F> {
    http: &'t TransparentPirHttp<'a, F>,
}

/// The private half: init, manifests, setup and queries.
pub(crate) struct PirShards<'t, 'a, F> {
    http: &'t TransparentPirHttp<'a, F>,
}

impl<'a, F: Fn() -> bool> TransparentPirHttp<'a, F> {
    /// Builds the transport for `origin` on the wallet's preferred route.
    ///
    /// Refuses an origin that is not HTTPS, or that carries a query the service
    /// routes would be appended to.
    pub(crate) fn new(
        origin: &str,
        should_exit: &'a F,
        handle: Handle,
        response_limit: usize,
    ) -> Result<Self, SyncError> {
        if secure_endpoint_uri(origin)?.query().is_some() {
            return Err(SyncError::parse(
                "transparent PIR origin must not carry a query",
            ));
        }
        Ok(Self {
            route: RoutedTransport::new(should_exit),
            origin: origin.trim_end_matches('/').to_owned(),
            handle,
            response_limit,
            outage: AtomicBool::new(false),
            #[cfg(test)]
            observer: None,
        })
    }

    /// Whether a request failed because the service could not be reached or
    /// was not serving: the pass's failure is an outage, not this account's.
    pub(crate) fn outage(&self) -> bool {
        self.outage.load(Ordering::SeqCst)
    }

    /// The filter source and shard transport one pass hands the adapter.
    pub(crate) fn split(&mut self) -> (PirFilters<'_, 'a, F>, PirShards<'_, 'a, F>) {
        let http = &*self;
        (PirFilters { http }, PirShards { http })
    }

    #[cfg(test)]
    pub(crate) fn route_policy(&self) -> super::RoutePolicy {
        self.route.route_policy
    }

    /// Records every request; see [`RequestObserver`].
    #[cfg(test)]
    pub(crate) fn with_observer(mut self, observer: RequestObserver) -> Self {
        self.observer = Some(observer);
        self
    }

    /// Sends one request and returns its bytes with their cost, the bytes
    /// delivered. Refusals the sync acts on come back as wallet-pir's typed
    /// [`StaleRevision`](zakura_pir_transparent::StaleRevision) and
    /// [`Overloaded`].
    fn exchange(&self, route: Route<'_>) -> Result<(Vec<u8>, u64), BoxError> {
        let received = self.handle.block_on(self.send(route));
        let (method, template) = (route.method(), route.template());
        match &received {
            Ok(reply) => log::debug!(
                "transparent PIR {method} {template}: HTTP {}, {} bytes",
                reply.status.as_u16(),
                reply.body.len()
            ),
            Err(error) => log::debug!("transparent PIR {method} {template}: {}", error.name()),
        }
        if outage(route, &received) {
            self.outage.store(true, Ordering::SeqCst);
        }
        let bytes = classify(route, received?, self.response_limit)?;
        let cost = bytes.len() as u64;
        Ok((bytes, cost))
    }

    async fn send(&self, route: Route<'_>) -> Result<Received, PirHttpError> {
        let should_exit = self.route.should_exit;
        if should_exit() {
            return Err(PirHttpError::Cancelled);
        }
        let method = route.method();
        let path = route.path();
        let body = route.body();
        #[cfg(test)]
        let answer = self
            .observer
            .as_ref()
            .and_then(|observer| observer.observe(&method, &path, &body));
        let url = format!("{}{path}", self.origin);
        let exchange = async {
            #[cfg(test)]
            if let Some(response) = answer {
                return read(response, route, self.response_limit).await;
            }
            let response = routed_response(
                method,
                &url,
                body,
                should_exit,
                &self.route.direct,
                self.route.route_policy,
            )
            .await
            .map_err(|error| match error {
                RoutedHttpError::Cancelled => PirHttpError::Cancelled,
                RoutedHttpError::HttpStatus(status) => PirHttpError::Status(status),
                RoutedHttpError::Failed(error) => PirHttpError::Route(error),
            })?;
            read(response, route, self.response_limit).await
        };
        let received = tokio::select! {
            biased;
            _ = watch_for_exit(should_exit) => Err(PirHttpError::Cancelled),
            received = tokio::time::timeout(REQUEST_TIMEOUT, exchange) => {
                received.unwrap_or(Err(PirHttpError::Timeout))
            }
        };
        // Cancellation wins a tie: a stopping pass acts on no reply that raced it.
        if should_exit() {
            return Err(PirHttpError::Cancelled);
        }
        received
    }
}

impl<F: Fn() -> bool> FilterSource for PirFilters<'_, '_, F> {
    fn shard_map(&mut self) -> Result<(Vec<u8>, u64), BoxError> {
        self.http.exchange(Route::ShardMap)
    }

    fn filter(&mut self, shard_id: u64) -> Result<(Vec<u8>, u64), BoxError> {
        self.http.exchange(Route::Filter { shard_id })
    }
}

/// Keeps the trait's default concurrency of one, so the sync walks every
/// request in sequence and a batch is never sent.
impl<F: Fn() -> bool> ShardTransport for PirShards<'_, '_, F> {
    fn init(&mut self) -> Result<(Vec<u8>, u64), BoxError> {
        self.http.exchange(Route::Init)
    }

    fn manifest(&mut self, shard_id: u64, revision: &str) -> Result<(Vec<u8>, u64), BoxError> {
        self.http
            .exchange(Route::Shard(ShardRequest::Manifest { shard_id, revision }))
    }

    fn setup(
        &mut self,
        shard_id: u64,
        revision: &str,
        table: Table,
        segment: u32,
    ) -> Result<(Vec<u8>, u64), BoxError> {
        self.http.exchange(Route::Shard(ShardRequest::Setup {
            shard_id,
            revision,
            table,
            segment,
        }))
    }

    fn query(
        &mut self,
        shard_id: u64,
        revision: &str,
        table: Table,
        body: &[u8],
    ) -> Result<Vec<u8>, BoxError> {
        self.http
            .exchange(Route::Shard(ShardRequest::Query {
                shard_id,
                revision,
                table,
                body,
            }))
            .map(|(bytes, _)| bytes)
    }
}

/// One request, as the service routes it.
#[derive(Clone, Copy)]
enum Route<'r> {
    ShardMap,
    Filter { shard_id: u64 },
    Init,
    Shard(ShardRequest<'r>),
}

impl Route<'_> {
    /// Queries post their opaque body; everything else is a read.
    fn method(&self) -> Method {
        match self {
            Route::Shard(ShardRequest::Query { .. }) => Method::POST,
            _ => Method::GET,
        }
    }

    fn path(&self) -> String {
        match *self {
            Route::ShardMap => "/v1/filters/shards".to_owned(),
            Route::Filter { shard_id } => format!("/v1/filters/shards/{shard_id}/filter"),
            Route::Init => "/v1/shards/init".to_owned(),
            Route::Shard(request) => request.route(),
        }
    }

    /// The path with its shard id, revision and segment elided: all a log line
    /// may say about the request.
    fn template(&self) -> String {
        match *self {
            Route::ShardMap => "/v1/filters/shards".to_owned(),
            Route::Filter { .. } => "/v1/filters/shards/{id}/filter".to_owned(),
            Route::Init => "/v1/shards/init".to_owned(),
            Route::Shard(ShardRequest::Manifest { .. }) => {
                "/v1/shards/{id}/revisions/{rev}/manifest".to_owned()
            }
            Route::Shard(ShardRequest::Setup { table, .. }) => format!(
                "/v1/shards/{{id}}/revisions/{{rev}}/setup/{}/{{segment}}",
                table.as_str()
            ),
            Route::Shard(ShardRequest::Query { table, .. }) => format!(
                "/v1/shards/{{id}}/revisions/{{rev}}/query/{}",
                table.as_str()
            ),
        }
    }

    fn body(&self) -> Vec<u8> {
        match self {
            Route::Shard(ShardRequest::Query { body, .. }) => body.to_vec(),
            _ => Vec::new(),
        }
    }

    /// The shard revision a shard-bound request names, which a stale refusal
    /// reports back.
    fn binding(&self) -> Option<(u64, &str)> {
        match *self {
            Route::Shard(
                ShardRequest::Manifest { shard_id, revision }
                | ShardRequest::Setup {
                    shard_id, revision, ..
                }
                | ShardRequest::Query {
                    shard_id, revision, ..
                },
            ) => Some((shard_id, revision)),
            _ => None,
        }
    }
}

/// A reply as it arrived: its status, `retry-after` and the body read.
struct Received {
    status: StatusCode,
    retry_after: Option<String>,
    body: Vec<u8>,
    /// Whether `body` is the whole body. Only a success must be.
    whole: bool,
}

/// Reads a success up to `response_limit`, a shard-bound refusal's body up to
/// [`ERROR_BODY_LIMIT`], and no other error body.
async fn read<B>(
    response: http::Response<B>,
    route: Route<'_>,
    response_limit: usize,
) -> Result<Received, PirHttpError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: fmt::Display,
{
    let status = response.status();
    let retry_after = response
        .headers()
        .get(RETRY_AFTER)
        .and_then(|value| value.to_str().ok())
        .map(str::to_owned);
    let body = response.into_body();
    let (body, whole) = if status.is_success() {
        read_prefix(body, response_limit)
            .await
            .map_err(PirHttpError::Route)?
    } else if route.binding().is_some() {
        read_prefix(body, ERROR_BODY_LIMIT)
            .await
            .unwrap_or_default()
    } else {
        (Vec::new(), false)
    };
    Ok(Received {
        status,
        retry_after,
        body,
        whole,
    })
}

/// Reads at most `limit` bytes of `body`, and whether the body ended within them.
async fn read_prefix<B>(mut body: B, limit: usize) -> Result<(Vec<u8>, bool), SyncError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: fmt::Display,
{
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|error| {
            SyncError::net(format!("read transparent PIR response body: {error}"))
        })?;
        if let Some(data) = frame.data_ref() {
            let room = limit - bytes.len();
            if data.len() > room {
                bytes.extend_from_slice(&data[..room]);
                return Ok((bytes, false));
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok((bytes, true))
}

/// Whether `received` says the service is unreachable or not serving, rather
/// than refusing this request: a failed route or connection, a timeout, a 429
/// or 5xx on a public route (the sync does not retry those), or a 5xx on a
/// shard-bound one that is not a capacity refusal.
fn outage(route: Route<'_>, received: &Result<Received, PirHttpError>) -> bool {
    match received {
        Err(PirHttpError::Route(_) | PirHttpError::Timeout) => true,
        Err(_) => false,
        Ok(reply) => {
            let status = reply.status.as_u16();
            match route.binding() {
                None => status == 429 || reply.status.is_server_error(),
                Some(_) => reply.status.is_server_error() && !matches!(status, 502..=504),
            }
        }
    }
}

/// What a reply means to the sync: its bytes, a refusal it acts on, or a
/// failure it reports.
fn classify(
    route: Route<'_>,
    received: Received,
    response_limit: usize,
) -> Result<Vec<u8>, BoxError> {
    if received.status.is_success() {
        return if received.whole {
            Ok(received.body)
        } else {
            Err(PirHttpError::TooLarge(response_limit).into())
        };
    }
    let status = received.status.as_u16();
    let retry_after = received.retry_after.as_deref();
    let refused = match route.binding() {
        // A stale revision (409), or capacity (503 with a delay, or the edge's 502/504).
        // A 429, or a 503 without a delay, is capacity too; the sync's own backoff bounds it.
        Some((shard_id, revision)) => {
            refusal(status, retry_after, &received.body, shard_id, revision).or_else(|| {
                matches!(status, 429 | 503).then(|| {
                    Overloaded {
                        retry_after: retry_after
                            .and_then(|value| value.trim().parse().ok())
                            .map(Duration::from_secs),
                    }
                    .boxed()
                })
            })
        }
        // The map, filters and init name no revision, so only capacity applies.
        None => Overloaded::from_http(status, retry_after).map(Overloaded::boxed),
    };
    Err(refused.unwrap_or_else(|| PirHttpError::Status(status).into()))
}

/// A failure the service did not phrase as a refusal the sync acts on.
///
/// Carries no URL, shard id, digest or body text.
#[derive(Debug)]
enum PirHttpError {
    /// The pass is stopping: the request was not sent, or its reply is dropped.
    Cancelled,
    /// A status that is neither success nor a recognised refusal.
    Status(u16),
    /// A successful body longer than the transport's limit.
    TooLarge(usize),
    /// No whole reply within [`REQUEST_TIMEOUT`].
    Timeout,
    /// The route or connection failed.
    Route(SyncError),
}

impl PirHttpError {
    /// The variant, for log lines.
    fn name(&self) -> &'static str {
        match self {
            PirHttpError::Cancelled => "cancelled",
            PirHttpError::Status(_) => "status",
            PirHttpError::TooLarge(_) => "too large",
            PirHttpError::Timeout => "timed out",
            PirHttpError::Route(_) => "route failed",
        }
    }
}

impl fmt::Display for PirHttpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PirHttpError::Cancelled => write!(f, "transparent PIR request cancelled"),
            PirHttpError::Status(status) => {
                write!(f, "transparent PIR service returned HTTP {status}")
            }
            PirHttpError::TooLarge(limit) => {
                write!(f, "transparent PIR response exceeds {limit} bytes")
            }
            PirHttpError::Timeout => write!(f, "transparent PIR request timed out"),
            PirHttpError::Route(error) => write!(f, "transparent PIR request failed: {error}"),
        }
    }
}

impl std::error::Error for PirHttpError {}

/// One request as dispatched.
#[cfg(test)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ObservedRequest {
    pub(crate) method: Method,
    pub(crate) path: String,
    pub(crate) body: Vec<u8>,
}

#[cfg(test)]
type Answer = std::sync::Arc<
    dyn Fn(&ObservedRequest) -> http::Response<http_body_util::Full<Bytes>> + Send + Sync,
>;

/// Test view of every request a transport dispatches, which it answers in
/// place of the network, or only records on its way there. The transport is
/// HTTPS-only over public roots, so no in-process server can stand in for the
/// service; the observer sits after route construction and cancellation,
/// where the network would be.
#[cfg(test)]
#[derive(Clone)]
pub(crate) struct RequestObserver {
    requests: std::sync::Arc<std::sync::Mutex<Vec<ObservedRequest>>>,
    /// `None` sends every request on to the network.
    answer: Option<Answer>,
}

#[cfg(test)]
impl RequestObserver {
    pub(crate) fn answering(
        answer: impl Fn(&ObservedRequest) -> http::Response<http_body_util::Full<Bytes>>
            + Send
            + Sync
            + 'static,
    ) -> Self {
        Self {
            requests: Default::default(),
            answer: Some(std::sync::Arc::new(answer)),
        }
    }

    /// Records every request and lets it reach the network: the opt-in live
    /// test's view of the real service.
    pub(crate) fn recording() -> Self {
        Self {
            requests: Default::default(),
            answer: None,
        }
    }

    /// Every request dispatched so far, in order. Clones share the record.
    pub(crate) fn requests(&self) -> Vec<ObservedRequest> {
        self.requests.lock().unwrap().clone()
    }

    /// Records the request, and answers it unless this observer only records.
    pub(super) fn observe(
        &self,
        method: &Method,
        path: &str,
        body: &[u8],
    ) -> Option<http::Response<http_body_util::Full<Bytes>>> {
        let request = ObservedRequest {
            method: method.clone(),
            path: path.to_owned(),
            body: body.to_vec(),
        };
        let response = self.answer.as_ref().map(|answer| answer(&request));
        self.requests.lock().unwrap().push(request);
        response
    }
}

#[cfg(test)]
mod tests {
    use super::super::RoutePolicy;
    use super::*;
    use http_body_util::Full;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };
    use tokio::runtime::Runtime;
    use zakura_pir_transparent::StaleRevision;

    const ORIGIN: &str = "https://transparent-pir.example";
    const SHARD: u64 = 4242;
    const REVISION: &str = "5f0c2b9e7d41a8c36e19f0b2d47a5c8e9b1d3f6a2c4e8b0d7f9a1c3e5b7d9f0a";
    const QUERY: &[u8] = &[0xc3, 0x5a, 0x01, 0xfe];
    const LIMIT: usize = 1024;

    fn runtime() -> Runtime {
        let _ = rustls::crypto::ring::default_provider().install_default();
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .unwrap()
    }

    fn reply(status: u16, retry_after: Option<&str>, body: &[u8]) -> http::Response<Full<Bytes>> {
        let mut response = http::Response::builder().status(status);
        if let Some(retry_after) = retry_after {
            response = response.header(RETRY_AFTER, retry_after);
        }
        response
            .body(Full::new(Bytes::copy_from_slice(body)))
            .unwrap()
    }

    /// A transport whose observer answers every request.
    fn answered<'a, F: Fn() -> bool>(
        runtime: &Runtime,
        should_exit: &'a F,
        answer: impl Fn(&ObservedRequest) -> http::Response<Full<Bytes>> + Send + Sync + 'static,
    ) -> (TransparentPirHttp<'a, F>, RequestObserver) {
        let observer = RequestObserver::answering(answer);
        let http = TransparentPirHttp::new(ORIGIN, should_exit, runtime.handle().clone(), LIMIT)
            .unwrap()
            .with_observer(observer.clone());
        (http, observer)
    }

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum Kind {
        Public,
        ShardBound,
    }

    /// Every request a pass makes, once each, with whether it names a shard
    /// revision.
    fn every_route<F: Fn() -> bool>(
        http: &mut TransparentPirHttp<'_, F>,
    ) -> Vec<(Kind, Result<Vec<u8>, BoxError>)> {
        let (mut filters, mut shards) = http.split();
        let bytes = |result: Result<(Vec<u8>, u64), BoxError>| result.map(|(bytes, _)| bytes);
        vec![
            (Kind::Public, bytes(filters.shard_map())),
            (Kind::Public, bytes(filters.filter(SHARD))),
            (Kind::Public, bytes(shards.init())),
            (Kind::ShardBound, bytes(shards.manifest(SHARD, REVISION))),
            (
                Kind::ShardBound,
                bytes(shards.setup(SHARD, REVISION, Table::Directory, 3)),
            ),
            (
                Kind::ShardBound,
                bytes(shards.setup(SHARD, REVISION, Table::Pages, 0)),
            ),
            (
                Kind::ShardBound,
                shards.query(SHARD, REVISION, Table::Directory, QUERY),
            ),
            (
                Kind::ShardBound,
                shards.query(SHARD, REVISION, Table::Pages, QUERY),
            ),
        ]
    }

    fn failure(error: &BoxError) -> &PirHttpError {
        error
            .downcast_ref::<PirHttpError>()
            .unwrap_or_else(|| panic!("not a transport failure: {error}"))
    }

    #[test]
    fn plaintext_origins_are_refused() {
        let runtime = runtime();
        let exit = || false;
        for origin in [
            "http://transparent-pir.example",
            "ws://transparent-pir.example",
            "transparent-pir.example",
            "https://transparent-pir.example?route=1",
        ] {
            assert!(
                TransparentPirHttp::new(origin, &exit, runtime.handle().clone(), LIMIT).is_err(),
                "accepted {origin}"
            );
        }
        let http = TransparentPirHttp::new(
            "https://transparent-pir.example/",
            &exit,
            runtime.handle().clone(),
            LIMIT,
        )
        .unwrap();
        assert_eq!(http.origin, ORIGIN);
        assert_eq!(http.route_policy(), RoutePolicy::WalletPreference);
    }

    #[test]
    fn routes_match_the_service_paths() {
        let runtime = runtime();
        let exit = || false;
        let (mut http, observer) = answered(&runtime, &exit, |request| {
            reply(200, None, request.path.as_bytes())
        });
        {
            let (mut filters, mut shards) = http.split();
            assert!(!filters.uses_parents());
            assert_eq!(shards.concurrency(), 1);
            let (map, cost) = filters.shard_map().unwrap();
            assert_eq!(map, b"/v1/filters/shards");
            assert_eq!(cost, map.len() as u64);
            let (_, cost) = shards.init().unwrap();
            assert_eq!(cost, "/v1/shards/init".len() as u64);
        }
        let observed_before = observer.requests().len();
        let results = every_route(&mut http);

        let shard = format!("/v1/shards/{SHARD}/revisions/{REVISION}");
        let none: &[u8] = &[];
        let expected = [
            (Method::GET, "/v1/filters/shards".to_owned(), none),
            (
                Method::GET,
                format!("/v1/filters/shards/{SHARD}/filter"),
                none,
            ),
            (Method::GET, "/v1/shards/init".to_owned(), none),
            (Method::GET, format!("{shard}/manifest"), none),
            (Method::GET, format!("{shard}/setup/directory/3"), none),
            (Method::GET, format!("{shard}/setup/pages/0"), none),
            (Method::POST, format!("{shard}/query/directory"), QUERY),
            (Method::POST, format!("{shard}/query/pages"), QUERY),
        ];
        let observed = observer.requests().split_off(observed_before);
        assert_eq!(observed.len(), expected.len());
        for (((method, path, body), request), (_, result)) in
            expected.iter().zip(&observed).zip(results)
        {
            assert_eq!(&request.method, method);
            assert_eq!(&request.path, path);
            assert_eq!(request.body, body.to_vec());
            assert_eq!(result.unwrap(), path.as_bytes());
        }
    }

    #[test]
    fn a_409_is_a_stale_revision() {
        let runtime = runtime();
        let exit = || false;
        let (mut http, _) = answered(&runtime, &exit, |_| {
            reply(409, None, br#"{"error":"gone","map_sha256":"beef"}"#)
        });
        for (kind, result) in every_route(&mut http) {
            let error = result.unwrap_err();
            match kind {
                Kind::ShardBound => {
                    let stale = error
                        .downcast_ref::<StaleRevision>()
                        .unwrap_or_else(|| panic!("not stale: {error}"));
                    assert_eq!(stale.shard_id, SHARD);
                    assert_eq!(stale.revision, REVISION);
                    assert_eq!(stale.map_sha256.as_deref(), Some("beef"));
                }
                // Only a request naming a revision can find it stale.
                Kind::Public => {
                    assert!(matches!(failure(&error), PirHttpError::Status(409)));
                }
            }
        }
    }

    #[test]
    fn capacity_refusals_without_retry_after_stay_capacity_on_shard_routes() {
        let runtime = runtime();
        let exit = || false;
        // A shard-bound 429 or bare 503 is capacity, without a delay: the sync's
        // own bounded backoff applies. On the map, filters and init the sync
        // does not retry, so they are an outage of the whole service.
        for status in [429, 503] {
            let (mut bare, _) = answered(&runtime, &exit, move |_| reply(status, None, b""));
            for (kind, result) in every_route(&mut bare) {
                let error = result.unwrap_err();
                match kind {
                    Kind::ShardBound => {
                        let overloaded = error
                            .downcast_ref::<Overloaded>()
                            .unwrap_or_else(|| panic!("HTTP {status} is not capacity: {error}"));
                        assert_eq!(overloaded.retry_after, None);
                    }
                    Kind::Public => {
                        assert!(Overloaded::found_in(&error).is_none());
                        assert!(matches!(failure(&error), PirHttpError::Status(s) if *s == status));
                    }
                }
            }
            assert!(bare.outage(), "HTTP {status} on public routes is an outage");
        }

        let (mut delayed, _) = answered(&runtime, &exit, |_| reply(503, Some("7"), b""));
        for (_, result) in every_route(&mut delayed) {
            let error = result.unwrap_err();
            let overloaded = error
                .downcast_ref::<Overloaded>()
                .unwrap_or_else(|| panic!("not overloaded: {error}"));
            assert_eq!(overloaded.retry_after, Some(Duration::from_secs(7)));
        }
        let (mut limited, _) = answered(&runtime, &exit, |_| reply(429, Some("4"), b""));
        let (_, result) = every_route(&mut limited).pop().unwrap();
        let error = result.unwrap_err();
        assert_eq!(
            error.downcast_ref::<Overloaded>().unwrap().retry_after,
            Some(Duration::from_secs(4))
        );
    }

    #[test]
    fn only_unreachable_or_failing_services_are_outages() {
        let runtime = runtime();
        let exit = || false;
        // Shard-bound capacity refusals and ordinary failures are not outages.
        for (status, retry_after) in [
            (429, None),
            (503, None),
            (503, Some("7")),
            (502, None),
            (404, None),
            (409, None),
        ] {
            let (mut http, _) = answered(&runtime, &exit, move |request| {
                if request.path.contains("/revisions/") {
                    reply(status, retry_after, b"")
                } else {
                    reply(200, None, b"ok")
                }
            });
            let _ = every_route(&mut http);
            assert!(!http.outage(), "HTTP {status} on a shard route");
        }
        // A public 404 is a refusal, not an outage.
        let (mut missing, _) = answered(&runtime, &exit, |_| reply(404, None, b""));
        let (mut filters, _) = missing.split();
        assert!(filters.shard_map().is_err());
        assert!(!missing.outage());
        // A failing shard route is.
        let (mut failing, _) = answered(&runtime, &exit, |request| {
            if request.path.contains("/revisions/") {
                reply(500, None, b"")
            } else {
                reply(200, None, b"ok")
            }
        });
        let _ = every_route(&mut failing);
        assert!(failing.outage());
    }

    #[test]
    fn edge_failures_back_off_by_default() {
        let runtime = runtime();
        let exit = || false;
        for status in [502, 504] {
            let (mut http, observer) = answered(&runtime, &exit, move |_| reply(status, None, b""));
            let results = every_route(&mut http);
            // One request per call: the transport never retries.
            assert_eq!(observer.requests().len(), results.len());
            for (_, result) in results {
                let error = result.unwrap_err();
                let overloaded = error
                    .downcast_ref::<Overloaded>()
                    .unwrap_or_else(|| panic!("HTTP {status} is not overloaded: {error}"));
                assert_eq!(overloaded.retry_after, Some(Overloaded::EDGE_RETRY_AFTER));
            }
        }
        // Any other failure is reported once and not retried either, and is an
        // outage of the service.
        let (mut http, observer) = answered(&runtime, &exit, |_| reply(500, None, b""));
        for (_, result) in every_route(&mut http) {
            assert!(matches!(
                failure(&result.unwrap_err()),
                PirHttpError::Status(500)
            ));
        }
        assert_eq!(observer.requests().len(), 8);
        assert!(http.outage());
    }

    #[test]
    fn oversized_bodies_fail() {
        let runtime = runtime();
        let exit = || false;
        let (mut full, _) = answered(&runtime, &exit, |_| reply(200, None, &[7; LIMIT]));
        for (_, result) in every_route(&mut full) {
            assert_eq!(result.unwrap().len(), LIMIT);
        }

        let (mut over, _) = answered(&runtime, &exit, |_| reply(200, None, &[7; LIMIT + 1]));
        for (_, result) in every_route(&mut over) {
            assert!(matches!(
                failure(&result.unwrap_err()),
                PirHttpError::TooLarge(LIMIT)
            ));
        }

        // An error body is read only to its limit, and the status still decides
        // the refusal; the digest past the limit is lost, not the refusal.
        let long = format!(
            r#"{{"pad":"{}","map_sha256":"beef"}}"#,
            "x".repeat(ERROR_BODY_LIMIT)
        );
        let (mut refused, _) =
            answered(&runtime, &exit, move |_| reply(409, None, long.as_bytes()));
        for (kind, result) in every_route(&mut refused) {
            let error = result.unwrap_err();
            if kind == Kind::ShardBound {
                let stale = error.downcast_ref::<StaleRevision>().expect("stale");
                assert_eq!(stale.map_sha256, None);
            }
        }
    }

    #[test]
    fn a_cancelled_transport_sends_nothing() {
        let runtime = runtime();
        let exit = || true;
        let (mut http, observer) = answered(&runtime, &exit, |_| reply(200, None, b"{}"));
        for (_, result) in every_route(&mut http) {
            assert!(matches!(
                failure(&result.unwrap_err()),
                PirHttpError::Cancelled
            ));
        }
        assert!(observer.requests().is_empty());

        // A reply that races cancellation is dropped, and nothing follows it.
        let cancelled = Arc::new(AtomicBool::new(false));
        let exit = {
            let cancelled = cancelled.clone();
            move || cancelled.load(Ordering::SeqCst)
        };
        let (mut http, observer) = answered(&runtime, &exit, move |_| {
            cancelled.store(true, Ordering::SeqCst);
            reply(200, None, b"{}")
        });
        let results = every_route(&mut http);
        assert_eq!(observer.requests().len(), 1);
        for (_, result) in results {
            assert!(matches!(
                failure(&result.unwrap_err()),
                PirHttpError::Cancelled
            ));
        }
    }

    use super::super::test_log::log_lines;

    #[test]
    fn debug_log_lines_carry_only_route_templates() {
        let runtime = runtime();
        let body = format!("{SHARD}{REVISION}{}", hex::encode(QUERY));
        let lines = log_lines(|| {
            let exit = || false;
            let echo = body.clone();
            let (mut http, _) =
                answered(&runtime, &exit, move |_| reply(200, None, echo.as_bytes()));
            every_route(&mut http);
            let (mut refused, _) = answered(&runtime, &exit, |_| {
                reply(409, None, br#"{"map_sha256":"beef"}"#)
            });
            let (_, mut shards) = refused.split();
            shards.manifest(SHARD, REVISION).unwrap_err();
            let cancelled = || true;
            let (mut stopped, _) = answered(&runtime, &cancelled, |_| reply(200, None, b""));
            let (mut filters, _) = stopped.split();
            filters.filter(SHARD).unwrap_err();
        });

        let ok = format!("HTTP 200, {} bytes", body.len());
        let shard = "/v1/shards/{id}/revisions/{rev}";
        let expected = [
            format!("DEBUG transparent PIR GET /v1/filters/shards: {ok}"),
            format!("DEBUG transparent PIR GET /v1/filters/shards/{{id}}/filter: {ok}"),
            format!("DEBUG transparent PIR GET /v1/shards/init: {ok}"),
            format!("DEBUG transparent PIR GET {shard}/manifest: {ok}"),
            format!("DEBUG transparent PIR GET {shard}/setup/directory/{{segment}}: {ok}"),
            format!("DEBUG transparent PIR GET {shard}/setup/pages/{{segment}}: {ok}"),
            format!("DEBUG transparent PIR POST {shard}/query/directory: {ok}"),
            format!("DEBUG transparent PIR POST {shard}/query/pages: {ok}"),
            format!("DEBUG transparent PIR GET {shard}/manifest: HTTP 409, 21 bytes"),
            "DEBUG transparent PIR GET /v1/filters/shards/{id}/filter: cancelled".to_owned(),
        ];
        // The transport's own lines are exactly one per request, and nothing
        // logged on the requesting thread carries an identifier or a body.
        let transport = module_path!().trim_end_matches("::tests");
        let own: Vec<_> = lines
            .iter()
            .filter(|(target, _)| target == transport)
            .map(|(_, line)| line.clone())
            .collect();
        assert_eq!(own, expected);
        for (_, line) in &lines {
            for secret in [
                SHARD.to_string(),
                REVISION.to_owned(),
                hex::encode(QUERY),
                "beef".to_owned(),
                ORIGIN.to_owned(),
            ] {
                assert!(!line.contains(&secret), "{line:?} carries {secret:?}");
            }
        }
    }
}
