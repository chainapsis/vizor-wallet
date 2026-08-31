//! Route-aware helper transport for voting share traffic.
//!
//! `zcash_voting` owns the helper protocol and its retry policy but never dials
//! a socket; it asks the host for a [`HelperTransport`]. This is Vizor's
//! implementation, and its whole job is to put every helper request on the
//! route the user selected.
//!
//! The route is decided **per request** through
//! [`network_privacy::tor_client_for_route`], the same primitive the wallet's
//! gRPC path uses. That call fails closed while Tor is starting or broken, so a
//! helper request never silently downgrades to the clearnet — a leaked voting
//! request is worse than a failed one.
//!
//! Direct requests are made on a leased connection
//! ([`network_privacy::DirectRouteLease`]) so that enabling Tor drains and then
//! aborts them, exactly as it does for wallet sync.

use std::{future::Future, time::Duration};

use bytes::Bytes;
use http::{Method, Uri};
use http_body_util::{BodyExt, Full};
use hyper_util::client::legacy::connect::HttpConnector;
use zcash_voting::{
    HelperFuture, HelperResponse, HelperTransport, HelperTransportError, HyperTransport,
    MAX_HELPER_RESPONSE_BYTES,
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
        // Fails closed: a broken or half-started Tor route is an error here,
        // never a fallback to a direct connection.
        match network_privacy::tor_client_for_route(true)
            .map_err(HelperTransportError::Transport)?
        {
            Some(tor) => {
                self.request_over_tor(&tor, method, url, body, timeout)
                    .await
            }
            None => request_direct(&self.direct, method, url, body, timeout).await,
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
        let apply_headers = move |builder: http::request::Builder| {
            if has_body {
                builder.header(http::header::CONTENT_TYPE, "application/json")
            } else {
                builder
            }
        };

        // Retries are the SDK's decision, not the transport's: it distinguishes
        // an ambiguous submission from a safe read. Ask arti for none.
        let response = with_timeout(timeout, async {
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
        .await?
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

/// Applies the caller's deadline, reporting expiry as an ambiguous timeout.
async fn with_timeout<T>(
    timeout: Duration,
    future: impl std::future::Future<Output = T>,
) -> Result<T, HelperTransportError> {
    tokio::time::timeout(timeout, future)
        .await
        .map_err(|_| HelperTransportError::Timeout)
}

/// Reads a Tor response body under the shared size ceiling.
///
/// Collected frame by frame so an oversized body is refused while it streams,
/// rather than after it has already been buffered.
async fn collect_tor_body(
    mut body: hyper::body::Incoming,
) -> Result<Vec<u8>, zcash_client_backend::tor::Error> {
    use zcash_client_backend::tor::http::HttpError;

    let mut collected: Vec<u8> = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(HttpError::from)?;
        if let Ok(data) = frame.into_data() {
            if collected.len().saturating_add(data.len()) > MAX_HELPER_RESPONSE_BYTES {
                return Err(std::io::Error::other(format!(
                    "helper response body exceeded {MAX_HELPER_RESPONSE_BYTES} bytes"
                ))
                .into());
            }
            collected.extend_from_slice(&data);
        }
    }
    Ok(collected)
}

impl HelperTransport for VotingHelperTransport {
    fn get<'a>(&'a self, url: &'a str, timeout: Duration) -> HelperFuture<'a> {
        Box::pin(async move { self.request(Method::GET, url, Vec::new(), timeout).await })
    }

    fn post_json<'a>(&'a self, url: &'a str, body: Vec<u8>, timeout: Duration) -> HelperFuture<'a> {
        Box::pin(async move { self.request(Method::POST, url, body, timeout).await })
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
    use zcash_voting::HelperTransportError;

    use super::{classify_tor_error, VotingHelperTransport};

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
}
