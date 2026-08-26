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
use http::{Method, Request, Uri};
use http_body_util::{BodyExt, Full, Limited};
use hyper_util::{
    client::legacy::{connect::HttpConnector, Client},
    rt::TokioExecutor,
};
use zcash_voting::{
    HelperFuture, HelperResponse, HelperTransport, HelperTransportError, MAX_HELPER_RESPONSE_BYTES,
};

use crate::network_privacy;

// The response ceiling is part of the helper protocol, so it comes from the
// SDK's transport contract rather than being chosen again here. Picking our own
// value would let the two drift silently.

type DirectBody = Full<Bytes>;
type DirectClient = Client<hyper_rustls::HttpsConnector<DirectRouteConnector>, DirectBody>;

/// Helper transport that follows the app's current network route.
pub struct VotingHelperTransport {
    direct: DirectClient,
}

impl Default for VotingHelperTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl VotingHelperTransport {
    pub fn new() -> Self {
        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_or_http()
            .enable_http1()
            .enable_http2()
            .wrap_connector(DirectRouteConnector::new());
        Self {
            direct: Client::builder(TokioExecutor::new()).build(https),
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
            None => self.request_direct(method, url, body, timeout).await,
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
        .map_err(|error| HelperTransportError::Transport(error.to_string()))?;

        Ok(HelperResponse {
            status: response.status().as_u16(),
            body: response.into_body(),
        })
    }

    async fn request_direct(
        &self,
        method: Method,
        url: &str,
        body: Vec<u8>,
        timeout: Duration,
    ) -> Result<HelperResponse, HelperTransportError> {
        let has_body = !body.is_empty();
        let builder = Request::builder().method(method).uri(url);
        let builder = if has_body {
            builder.header(http::header::CONTENT_TYPE, "application/json")
        } else {
            builder
        };
        let request = builder
            .body(Full::new(Bytes::from(body)))
            .map_err(|error| {
                HelperTransportError::Transport(format!("build helper request: {error}"))
            })?;

        let response = with_timeout(timeout, self.direct.request(request))
            .await?
            .map_err(|error| {
                HelperTransportError::Transport(format!("send helper request: {error}"))
            })?;
        let status = response.status().as_u16();
        let body = with_timeout(
            timeout,
            Limited::new(response.into_body(), MAX_HELPER_RESPONSE_BYTES).collect(),
        )
        .await?
        .map_err(|error| {
            HelperTransportError::Transport(format!(
                "read helper response body (limit {MAX_HELPER_RESPONSE_BYTES} bytes): {error}"
            ))
        })?
        .to_bytes()
        .to_vec();

        Ok(HelperResponse { status, body })
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
