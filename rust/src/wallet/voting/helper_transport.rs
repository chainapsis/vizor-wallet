//! Route-aware helper transport for voting share traffic.
//!
//! `zcash_voting` owns the helper protocol and its retry policy but never dials
//! a socket; it asks the host for a [`HelperTransport`]. This is Vizor's
//! implementation, and its whole job is to put every helper request on the
//! route the user selected.
//!
//! The route is decided **per request** through
//! [`network_privacy::tor_client_for_route`], the same primitive the wallet's
//! gRPC path uses. That call waits out a bootstrap in flight and fails closed
//! when Tor is broken, so a helper request never silently downgrades to the
//! clearnet — a leaked voting request is worse than a failed one.
//!
//! Direct requests are made on a leased connection
//! ([`network_privacy::DirectRouteLease`]) so that enabling Tor drains and then
//! aborts them, exactly as it does for wallet sync.

use std::{
    future::Future,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::Duration,
};

use bytes::Bytes;
use http::{Method, Uri};
use http_body_util::{BodyExt, Full};
use hyper_util::client::legacy::connect::HttpConnector;
use zcash_voting::{
    ChainHttpRequest, ChainHttpResponse, ChainPostDispatch, ChainTransport, ChainTransportError,
    ChainTransportFuture, HelperFuture, HelperResponse, HelperTransport, HelperTransportError,
    HyperTransport, MAX_HELPER_RESPONSE_BYTES,
};

use crate::network_privacy;

tokio::task_local! {
    /// The complete request deadline, reused by the direct connector so a
    /// TCP or TLS timeout remains a definite pre-dispatch failure.
    static DIRECT_REQUEST_DEADLINE: Option<tokio::time::Instant>;
}

// The response ceiling is part of the helper protocol, so it comes from the
// SDK's transport contract rather than being chosen again here. Picking our own
// value would let the two drift silently.

/// Helper transport that follows the app's current network route.
pub struct VotingHelperTransport {
    direct: HyperTransport,
}

impl Default for VotingHelperTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl VotingHelperTransport {
    pub fn new() -> Self {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_or_http()
            .enable_http1()
            .enable_http2()
            .wrap_connector(DirectRouteConnector::new());
        Self {
            direct: HyperTransport::with_connector(ConnectDeadlineConnector::new(https)),
        }
    }

    /// Performs one helper request on the currently selected route.
    ///
    /// `timeout` covers connection setup, the response head, and the body read,
    /// because a helper that accepts a connection and then stalls is
    /// indistinguishable to the caller from one that never answered.
    async fn request(
        &self,
        method: Method,
        url: &str,
        body: Vec<u8>,
        timeout: Duration,
    ) -> Result<HelperResponse, HelperTransportError> {
        // Fails closed: a broken Tor route is an error, never a direct fallback.
        // A bootstrap in flight is waited out, but only inside this request's
        // own budget; nothing has been sent yet, so running out is a timeout.
        // Nothing has been dispatched when the wait runs out, so for a POST
        // this is a definite failure the SDK may retry, not an ambiguous one.
        let is_post = method == Method::POST;
        let started = tokio::time::Instant::now();
        let route = tokio::time::timeout(
            timeout,
            network_privacy::tor_client_for_route(true, || false),
        )
        .await
        .map_err(|_| classify_tor_outer_timeout(is_post, false))?
        .map_err(HelperTransportError::Transport)?;
        let remaining = timeout.saturating_sub(started.elapsed());
        if remaining.is_zero() {
            return Err(classify_tor_outer_timeout(is_post, false));
        }
        match route {
            Some(tor) => {
                self.request_over_tor(&tor, method, url, body, remaining)
                    .await
            }
            None => request_direct(&self.direct, method, url, body, remaining).await,
        }
    }

    async fn request_over_tor(
        &self,
        tor: &zcash_client_backend::tor::Client,
        method: Method,
        url: &str,
        body: Vec<u8>,
        timeout: Duration,
    ) -> Result<HelperResponse, HelperTransportError> {
        let uri: Uri = url
            .parse()
            .map_err(|error| HelperTransportError::Transport(format!("invalid URL: {error}")))?;
        let has_body = !body.is_empty();
        let is_post = method == Method::POST;
        let request_started = Arc::new(AtomicBool::new(false));
        let request_started_in_headers = request_started.clone();
        let apply_headers = move |builder: http::request::Builder| {
            // librustzcash invokes this only after the Tor stream and TLS
            // handshake are ready, immediately before constructing the HTTP
            // request. Until this flips, a timeout is definitely pre-dispatch.
            request_started_in_headers.store(true, Ordering::Release);
            if has_body {
                builder.header(http::header::CONTENT_TYPE, "application/json")
            } else {
                builder
            }
        };

        // Retries are the SDK's decision, not the transport's: it distinguishes
        // an ambiguous submission from a safe read. Ask arti for none.
        let response = tokio::time::timeout(timeout, async {
            match method {
                Method::POST => {
                    tor.http_post(
                        uri,
                        apply_headers,
                        Full::new(Bytes::from(body)),
                        collect_tor_body,
                        0,
                        |_| None,
                    )
                    .await
                }
                _ => {
                    tor.http_get(uri, apply_headers, collect_tor_body, 0, |_| None)
                        .await
                }
            }
        })
        .await
        .map_err(|_| classify_tor_outer_timeout(is_post, request_started.load(Ordering::Acquire)))?
        .map_err(|error| classify_tor_error(is_post, error))?;

        let status = response.status().as_u16();
        let content_type = response
            .headers()
            .get(http::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        Ok(HelperResponse::new(
            status,
            response.into_body(),
            content_type,
        ))
    }
}

/// Classifies Vizor's whole-request deadline when it beats librustzcash's
/// phase-specific Tor deadlines.
fn classify_tor_outer_timeout(is_post: bool, request_started: bool) -> HelperTransportError {
    if is_post && !request_started {
        HelperTransportError::Transport(
            "Tor helper connection timed out before request dispatch".to_string(),
        )
    } else {
        HelperTransportError::Timeout
    }
}

/// Runs a direct request and exposes its one absolute deadline to connection
/// setup. The connector's deadline starts just before the SDK's whole-request
/// timer, so an establishment timeout is returned through Hyper as a connect
/// error instead of racing the outer ambiguous timeout.
async fn request_direct(
    transport: &HyperTransport,
    method: Method,
    url: &str,
    body: Vec<u8>,
    timeout: Duration,
) -> Result<HelperResponse, HelperTransportError> {
    let deadline = tokio::time::Instant::now().checked_add(timeout);
    DIRECT_REQUEST_DEADLINE
        .scope(deadline, async move {
            if method == Method::POST {
                transport.post_json(url, body, timeout).await
            } else {
                transport.get(url, timeout).await
            }
        })
        .await
}

/// Separates Tor failures that prove a POST was never dispatched from failures
/// that can happen after the helper received some or all of its body.
fn classify_tor_error(
    is_post: bool,
    error: zcash_client_backend::tor::Error,
) -> HelperTransportError {
    use zcash_client_backend::tor::{
        http::{HttpError, TimeoutPhase},
        Error,
    };

    let message = error.to_string();
    if !is_post {
        return HelperTransportError::Transport(message);
    }
    let definitely_pre_dispatch = matches!(
        &error,
        Error::MissingTorDirectory
            | Error::Tor(_)
            | Error::Http(
                HttpError::NonHttpUrl
                    | HttpError::Http(_)
                    | HttpError::Spawn(_)
                    | HttpError::Tls(_)
                    | HttpError::Timeout(TimeoutPhase::Connect),
            )
    );
    if definitely_pre_dispatch {
        HelperTransportError::Transport(message)
    } else {
        HelperTransportError::Ambiguous(message)
    }
}

/// Reads a Tor response body under the shared size ceiling.
///
/// Collected frame by frame so an oversized body is refused while it streams,
/// rather than after it has already been buffered.
async fn collect_tor_body(
    mut body: hyper::body::Incoming,
) -> Result<Vec<u8>, zcash_client_backend::tor::Error> {
    collect_tor_body_with_limit(&mut body, MAX_HELPER_RESPONSE_BYTES, "helper").await
}

/// Reads a routed response body without buffering beyond the caller's limit.
async fn collect_tor_body_with_limit(
    body: &mut hyper::body::Incoming,
    max_response_bytes: usize,
    label: &str,
) -> Result<Vec<u8>, zcash_client_backend::tor::Error> {
    use zcash_client_backend::tor::http::HttpError;

    let mut collected: Vec<u8> = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(HttpError::from)?;
        if let Ok(data) = frame.into_data() {
            if collected.len().saturating_add(data.len()) > max_response_bytes {
                return Err(std::io::Error::other(format!(
                    "{label} response body exceeded {max_response_bytes} bytes"
                ))
                .into());
            }
            collected.extend_from_slice(&data);
        }
    }
    Ok(collected)
}

impl VotingHelperTransport {
    async fn chain_request_over_tor(
        &self,
        tor: &zcash_client_backend::tor::Client,
        method: Method,
        request: ChainHttpRequest,
        body: Vec<u8>,
        dispatch: Option<ChainPostDispatch>,
    ) -> Result<ChainHttpResponse, ChainTransportError> {
        let uri: Uri = request.url().parse().map_err(|error| {
            ChainTransportError::definitely_unsent(format!("invalid vote-chain URL: {error}"))
        })?;
        let is_post = method == Method::POST;
        let request_headers = request.headers().to_vec();
        let dispatch_for_headers = dispatch.clone();
        let apply_headers = move |mut builder: http::request::Builder| {
            for (name, value) in &request_headers {
                builder = builder.header(name, value);
            }
            if let Some(dispatch) = dispatch_for_headers.as_ref() {
                // librustzcash invokes this only after Tor connection and TLS
                // setup, immediately before it constructs the HTTP request.
                dispatch.mark_possible();
            }
            builder
        };
        let max_response_bytes = request.max_response_bytes();

        let response = tokio::time::timeout(request.timeout(), async {
            match method {
                Method::POST => {
                    tor.http_post(
                        uri,
                        apply_headers,
                        Full::new(Bytes::from(body)),
                        move |mut body| async move {
                            collect_tor_body_with_limit(&mut body, max_response_bytes, "vote-chain")
                                .await
                        },
                        0,
                        |_| None,
                    )
                    .await
                }
                _ => {
                    tor.http_get(
                        uri,
                        apply_headers,
                        move |mut body| async move {
                            collect_tor_body_with_limit(&mut body, max_response_bytes, "vote-chain")
                                .await
                        },
                        0,
                        |_| None,
                    )
                    .await
                }
            }
        })
        .await
        .map_err(|_| {
            if is_post
                && dispatch
                    .as_ref()
                    .is_some_and(ChainPostDispatch::is_possible)
            {
                ChainTransportError::possibly_dispatched("vote-chain request timed out")
            } else {
                ChainTransportError::definitely_unsent(
                    "vote-chain request timed out before dispatch",
                )
            }
        })?
        .map_err(|error| classify_tor_chain_error(is_post, dispatch.as_ref(), error))?;

        let status = response.status().as_u16();
        let content_type = response
            .headers()
            .get(http::header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        let headers = response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (name.as_str().to_string(), value.to_string()))
            })
            .collect();
        Ok(ChainHttpResponse::new(
            status,
            response.into_body(),
            content_type,
            headers,
        ))
    }
}

fn classify_tor_chain_error(
    is_post: bool,
    dispatch: Option<&ChainPostDispatch>,
    error: zcash_client_backend::tor::Error,
) -> ChainTransportError {
    let helper_classification = classify_tor_error(is_post, error);
    let message = helper_classification.to_string();
    let possibly_dispatched = is_post
        && (dispatch.is_some_and(ChainPostDispatch::is_possible)
            || matches!(helper_classification, HelperTransportError::Ambiguous(_)));
    if possibly_dispatched {
        ChainTransportError::possibly_dispatched(message)
    } else {
        ChainTransportError::definitely_unsent(message)
    }
}

impl HelperTransport for VotingHelperTransport {
    fn get<'a>(&'a self, url: &'a str, timeout: Duration) -> HelperFuture<'a> {
        Box::pin(async move { self.request(Method::GET, url, Vec::new(), timeout).await })
    }

    fn post_json<'a>(&'a self, url: &'a str, body: Vec<u8>, timeout: Duration) -> HelperFuture<'a> {
        Box::pin(async move { self.request(Method::POST, url, body, timeout).await })
    }
}

impl ChainTransport for VotingHelperTransport {
    fn chain_get<'a>(&'a self, request: ChainHttpRequest) -> ChainTransportFuture<'a> {
        Box::pin(async move {
            match network_privacy::tor_client_for_route(true, || false)
                .await
                .map_err(ChainTransportError::definitely_unsent)?
            {
                Some(tor) => {
                    self.chain_request_over_tor(&tor, Method::GET, request, Vec::new(), None)
                        .await
                }
                None => ChainTransport::chain_get(&self.direct, request).await,
            }
        })
    }

    fn chain_post_json<'a>(
        &'a self,
        request: ChainHttpRequest,
        json: Vec<u8>,
    ) -> ChainTransportFuture<'a> {
        Box::pin(async move {
            match network_privacy::tor_client_for_route(true, || false)
                .await
                .map_err(ChainTransportError::definitely_unsent)?
            {
                Some(tor) => {
                    self.chain_request_over_tor(&tor, Method::POST, request, json, None)
                        .await
                }
                None => ChainTransport::chain_post_json(&self.direct, request, json).await,
            }
        })
    }

    fn chain_post_json_with_dispatch<'a>(
        &'a self,
        request: ChainHttpRequest,
        json: Vec<u8>,
        dispatch: ChainPostDispatch,
    ) -> ChainTransportFuture<'a> {
        Box::pin(async move {
            match network_privacy::tor_client_for_route(true, || false)
                .await
                .map_err(ChainTransportError::definitely_unsent)?
            {
                Some(tor) => {
                    self.chain_request_over_tor(&tor, Method::POST, request, json, Some(dispatch))
                        .await
                }
                None => {
                    ChainTransport::chain_post_json_with_dispatch(
                        &self.direct,
                        request,
                        json,
                        dispatch,
                    )
                    .await
                }
            }
        })
    }
}

/// TCP connector whose connections are governed by a direct-route lease.
///
/// Mirrors the wallet gRPC connector: enabling Tor drains outstanding leases
/// and then aborts any connection still open on the old route.
#[derive(Clone)]
struct DirectRouteConnector {
    inner: HttpConnector,
}

impl DirectRouteConnector {
    fn new() -> Self {
        let mut inner = HttpConnector::new();
        inner.enforce_http(false);
        inner.set_nodelay(true);
        Self { inner }
    }
}

impl tower_service::Service<Uri> for DirectRouteConnector {
    type Response = network_privacy::DirectRouteIo<hyper_util::rt::TokioIo<tokio::net::TcpStream>>;
    type Error = Box<dyn std::error::Error + Send + Sync>;
    type Future = std::pin::Pin<
        Box<dyn std::future::Future<Output = Result<Self::Response, Self::Error>> + Send>,
    >;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        tower_service::Service::poll_ready(&mut self.inner, cx)
            .map(|result| result.map_err(|error| Box::new(error) as Self::Error))
    }

    fn call(&mut self, uri: Uri) -> Self::Future {
        let future = tower_service::Service::call(&mut self.inner, uri);
        let route = network_privacy::DirectRouteLease::new();
        Box::pin(async move {
            let mut future = Box::pin(future);
            let connected = std::future::poll_fn(|cx| {
                route.poll(cx, |cx| match future.as_mut().poll(cx) {
                    std::task::Poll::Ready(Ok(connected)) => std::task::Poll::Ready(Ok(connected)),
                    std::task::Poll::Ready(Err(error)) => {
                        std::task::Poll::Ready(Err(Box::new(error) as Self::Error))
                    }
                    std::task::Poll::Pending => std::task::Poll::Pending,
                })
            })
            .await?;
            Ok(route.into_io(connected))
        })
    }
}

/// Applies the request's absolute deadline to the complete TCP+TLS connector.
///
/// Wrapping the HTTPS connector, rather than only [`DirectRouteConnector`], is
/// important: a stalled TLS handshake is still known not to have dispatched
/// an HTTP request and must therefore remain safe for helper fallback.
#[derive(Clone)]
struct ConnectDeadlineConnector<C> {
    inner: C,
}

impl<C> ConnectDeadlineConnector<C> {
    fn new(inner: C) -> Self {
        Self { inner }
    }
}

impl<C, T, E> tower_service::Service<Uri> for ConnectDeadlineConnector<C>
where
    C: tower_service::Service<Uri, Response = T, Error = E> + Send,
    C::Future: Send + 'static,
    E: Into<Box<dyn std::error::Error + Send + Sync>>,
{
    type Response = T;
    type Error = Box<dyn std::error::Error + Send + Sync>;
    type Future =
        std::pin::Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        tower_service::Service::poll_ready(&mut self.inner, cx)
            .map(|result| result.map_err(Into::into))
    }

    fn call(&mut self, uri: Uri) -> Self::Future {
        let future = tower_service::Service::call(&mut self.inner, uri);
        let deadline = DIRECT_REQUEST_DEADLINE
            .try_with(|deadline| *deadline)
            .ok()
            .flatten();
        Box::pin(async move {
            match deadline {
                Some(deadline) => tokio::time::timeout_at(deadline, future)
                    .await
                    .map_err(|_| {
                        Box::new(std::io::Error::new(
                            std::io::ErrorKind::TimedOut,
                            "direct helper connection timed out before request dispatch",
                        )) as Self::Error
                    })?
                    .map_err(Into::into),
                None => future.await.map_err(Into::into),
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
        time::Duration,
    };

    use http::Method;
    use zcash_voting::{ChainPostDispatch, ChainTransportFailureKind, HelperTransportError};

    use super::{
        classify_tor_chain_error, classify_tor_error, classify_tor_outer_timeout,
        VotingHelperTransport,
    };

    #[test]
    fn tor_post_classification_distinguishes_pre_dispatch_failures() {
        use zcash_client_backend::tor::{
            http::{HttpError, TimeoutPhase},
            Error,
        };

        let request_build_error = http::Request::builder()
            .header("bad\nheader", "value")
            .body(())
            .unwrap_err();
        let definite = vec![
            Error::MissingTorDirectory,
            Error::Http(HttpError::NonHttpUrl),
            Error::Http(HttpError::Http(request_build_error)),
            Error::Http(HttpError::Tls(std::io::Error::other("tls failed"))),
            Error::Http(HttpError::Timeout(TimeoutPhase::Connect)),
        ];
        for error in definite {
            assert!(matches!(
                classify_tor_error(true, error),
                HelperTransportError::Transport(_)
            ));
        }

        let ambiguous = vec![
            Error::Http(HttpError::Timeout(TimeoutPhase::Request)),
            Error::Http(HttpError::Timeout(TimeoutPhase::ResponseBody)),
            Error::Http(HttpError::Json(
                serde_json::from_str::<serde_json::Value>("{").unwrap_err(),
            )),
            Error::Io(std::io::Error::other("response stream failed")),
        ];
        for error in ambiguous {
            assert!(matches!(
                classify_tor_error(true, error),
                HelperTransportError::Ambiguous(_)
            ));
        }
    }

    #[test]
    fn tor_get_failures_are_always_safe_to_retry() {
        assert!(matches!(
            classify_tor_error(false, zcash_client_backend::tor::Error::MissingTorDirectory),
            HelperTransportError::Transport(_)
        ));
    }

    #[test]
    fn chain_post_classification_honors_the_dispatch_boundary() {
        let dispatch = ChainPostDispatch::default();
        let before_dispatch = classify_tor_chain_error(
            true,
            Some(&dispatch),
            zcash_client_backend::tor::Error::MissingTorDirectory,
        );
        assert_eq!(
            before_dispatch.kind(),
            ChainTransportFailureKind::DefinitelyUnsent
        );

        dispatch.mark_possible();
        let after_dispatch = classify_tor_chain_error(
            true,
            Some(&dispatch),
            zcash_client_backend::tor::Error::MissingTorDirectory,
        );
        assert_eq!(
            after_dispatch.kind(),
            ChainTransportFailureKind::PossiblyDispatched
        );
    }

    #[test]
    fn tor_outer_timeout_preserves_pre_dispatch_post_classification() {
        assert!(matches!(
            classify_tor_outer_timeout(true, false),
            HelperTransportError::Transport(_)
        ));
        assert!(matches!(
            classify_tor_outer_timeout(true, true),
            HelperTransportError::Timeout
        ));
        assert!(matches!(
            classify_tor_outer_timeout(false, false),
            HelperTransportError::Timeout
        ));
    }

    #[tokio::test]
    async fn selected_direct_route_uses_sdk_hyper_transport() {
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0u8; 2048];
            let bytes_read = stream.read(&mut request).unwrap();
            assert!(request[..bytes_read].starts_with(b"POST "));
            stream
                .write_all(
                    b"HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
                )
                .unwrap();
        });

        let transport = VotingHelperTransport::new();
        let response = transport
            .request(
                Method::POST,
                &format!("http://{address}/shielded-vote/v1/shares"),
                br#"{"share_index":0}"#.to_vec(),
                Duration::from_secs(1),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), 201);
        assert_eq!(response.body(), b"{}");
        assert_eq!(response.content_type(), Some("application/json"));
        server.join().unwrap();
    }

    #[tokio::test]
    async fn direct_tls_timeout_is_definitely_pre_dispatch() {
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = thread::spawn(move || {
            let (_stream, _) = listener.accept().unwrap();
            // Accept TCP but never complete TLS. No HTTP bytes can have been
            // dispatched when the connector deadline expires.
            thread::sleep(Duration::from_millis(100));
        });
        let transport = VotingHelperTransport::new();

        let result = transport
            .request(
                Method::POST,
                &format!("https://{address}/shielded-vote/v1/shares"),
                br#"{"share_index":0}"#.to_vec(),
                Duration::from_millis(20),
            )
            .await;

        assert!(matches!(result, Err(HelperTransportError::Transport(_))));
        server.join().unwrap();
    }

    /// The route wait is charged to the same budget as the request. A
    /// helper call sized for seconds must not sit behind a Tor bootstrap for
    /// its full deadline; nothing has been dispatched, so it is a timeout.
    #[tokio::test]
    async fn route_resolution_is_bounded_by_the_request_timeout() {
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        crate::network_privacy::begin_tor_enable();
        let transport = VotingHelperTransport::new();

        let started = std::time::Instant::now();
        let result = transport
            .request(
                Method::GET,
                "https://helper.invalid/shielded-vote/v1/status",
                Vec::new(),
                Duration::from_millis(200),
            )
            .await;
        let waited = started.elapsed();

        assert!(
            matches!(result, Err(HelperTransportError::Timeout)),
            "{result:?}"
        );
        assert!(
            waited < Duration::from_secs(1),
            "the route wait outlived the request timeout: {waited:?}"
        );
    }

    /// A POST that never left the app is a definite pre-dispatch failure the
    /// SDK may retry, not an ambiguous submission.
    #[tokio::test]
    async fn route_wait_expiry_before_a_post_is_safe_to_retry() {
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        crate::network_privacy::begin_tor_enable();
        let transport = VotingHelperTransport::new();

        let result = transport
            .request(
                Method::POST,
                "https://helper.invalid/shielded-vote/v1/shares",
                br#"{"share_index":0}"#.to_vec(),
                Duration::from_millis(200),
            )
            .await;

        assert!(
            matches!(result, Err(HelperTransportError::Transport(_))),
            "{result:?}"
        );
    }
}
