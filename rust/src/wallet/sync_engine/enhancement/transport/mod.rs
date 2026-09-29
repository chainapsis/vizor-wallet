//! Shared cancellation-aware HTTPS transport for Enhance PIR and Status PIR.

mod cancellation;
mod enhance_pir;
mod status_pir;

pub(super) use cancellation::cancelable;
pub(super) use enhance_pir::client_protocol_error;
pub(crate) use status_pir::StatusPirTransport;

use bytes::Bytes;
use http::{Method, Request, StatusCode};
use http_body_util::{BodyExt, Full};
use hyper::body::{Body, Incoming};
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::{client::legacy::Client, rt::TokioExecutor};
use std::{future::Future, time::Duration};
use zakura_pir_enhance::transport::{self, BoundedBody};

use super::super::{lwd::DirectRouteConnector, SyncError};

pub(super) const HTTP_TIMEOUT: Duration = Duration::from_secs(120);
type DirectHttpsClient = Client<hyper_rustls::HttpsConnector<DirectRouteConnector>, Full<Bytes>>;

#[derive(Debug)]
pub(crate) enum RoutedHttpError {
    Cancelled,
    HttpStatus(u16),
    Failed(SyncError),
}

impl From<SyncError> for RoutedHttpError {
    fn from(error: SyncError) -> Self {
        Self::Failed(error)
    }
}

#[derive(Clone, Copy)]
enum RoutePolicy {
    WalletPreference,
    ForceDirect,
}

/// One transport per `run`, reused by every request it makes.
///
/// The pooled client lives here rather than being built per request: a hyper
/// `Client` owns its connection pool, so a fresh one per call throws the
/// keep-alive connection away and makes a batch of packed rows pay a TCP and
/// TLS handshake for the initialization fetch and again for every query.
///
/// Scoping it to the transport rather than a process-wide cache keeps idle
/// connections from outliving the sync. That is belt and braces only:
/// `routed_request` re-checks the route per request, and `DirectRouteIo` polls
/// the route lease on every read and write, so a pooled connection stays
/// route-policed for its whole life.
pub(crate) struct RoutedTransport<'a, F> {
    should_exit: &'a F,
    direct: DirectHttpsClient,
    route_policy: RoutePolicy,
}

impl<'a, F> RoutedTransport<'a, F> {
    pub(crate) fn new(should_exit: &'a F) -> Self {
        Self::with_route(should_exit, RoutePolicy::WalletPreference)
    }
    pub(in crate::wallet::sync_engine) fn new_direct(should_exit: &'a F) -> Self {
        Self::with_route(should_exit, RoutePolicy::ForceDirect)
    }
    fn with_route(should_exit: &'a F, route_policy: RoutePolicy) -> Self {
        let connector = HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_only()
            .enable_http1()
            .wrap_connector(DirectRouteConnector::new());
        Self {
            should_exit,
            route_policy,
            // Cheap: no connection is opened until the first request, and the
            // Tor route simply never uses it.
            direct: Client::builder(TokioExecutor::new()).build(connector),
        }
    }
}

/// Validated before route selection, so a plaintext endpoint is rejected on
/// every route rather than only the direct one. Tor conceals the client from
/// the service, but the exit-to-service hop is still the open network.
pub(super) fn secure_endpoint_uri(url: &str) -> Result<http::Uri, SyncError> {
    let uri = url
        .parse::<http::Uri>()
        .map_err(|error| SyncError::parse(format!("invalid private-service URL: {error}")))?;
    if uri.scheme_str() != Some("https") {
        return Err(SyncError::parse("private-service transport requires HTTPS"));
    }
    Ok(uri)
}

/// A single deadline covers route acquisition, headers, and body on both routes.
async fn routed_request(
    method: Method,
    url: &str,
    body: Vec<u8>,
    collector: BoundedBody,
    should_exit: &impl Fn() -> bool,
    direct: &DirectHttpsClient,
) -> Result<transport::ResponseBody, RoutedHttpError> {
    receive_response(
        routed_response(
            method,
            url,
            body,
            should_exit,
            direct,
            RoutePolicy::WalletPreference,
        ),
        collector,
        should_exit,
    )
    .await
}

async fn routed_response(
    method: Method,
    url: &str,
    body: Vec<u8>,
    should_exit: &impl Fn() -> bool,
    direct: &DirectHttpsClient,
    route_policy: RoutePolicy,
) -> Result<http::Response<Incoming>, RoutedHttpError> {
    if should_exit() {
        return Err(RoutedHttpError::Cancelled);
    }
    let uri = secure_endpoint_uri(url)?;
    if matches!(route_policy, RoutePolicy::WalletPreference)
        && crate::network_privacy::is_tor_desired()
    {
        let client = crate::network_privacy::tor_client_for_route(true, || should_exit())
            .await
            .map_err(|error| {
                if should_exit() {
                    RoutedHttpError::Cancelled
                } else {
                    RoutedHttpError::Failed(SyncError::net(format!(
                        "network privacy blocked private-service request: {error}"
                    )))
                }
            })?
            .ok_or_else(|| {
                RoutedHttpError::Failed(SyncError::net(
                    "Tor route changed before private-service request",
                ))
            })?;
        let request = async {
            match method {
                Method::GET => {
                    client
                        .http_get(
                            uri,
                            |builder| builder,
                            |incoming| async { Ok(incoming) },
                            0,
                            |_| None,
                        )
                        .await
                }
                Method::POST => {
                    client
                        .http_post(
                            uri,
                            |builder| {
                                builder
                                    .header(http::header::CONTENT_TYPE, "application/octet-stream")
                            },
                            Full::new(Bytes::from(body)),
                            |incoming| async { Ok(incoming) },
                            0,
                            |_| None,
                        )
                        .await
                }
                _ => unreachable!("private services use GET and POST only"),
            }
            .map_err(|error| SyncError::net(format!("private-service Tor request failed: {error}")))
        };
        // Returning Incoming from the Tor parser exposes headers without
        // polling the body. A malformed error body cannot erase its status.
        return Ok(request.await?);
    }

    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header(http::header::CONTENT_TYPE, "application/octet-stream")
        .body(Full::new(Bytes::from(body)))
        .map_err(|error| SyncError::parse(format!("build private-service request: {error}")))?;
    let response = direct.request(request).await.map_err(|error| {
        SyncError::net(format!("private-service HTTPS request failed: {error}"))
    })?;
    Ok(response)
}

/// Keep the deadline outside both phases; error bodies are never consumed.
pub(super) async fn receive_response<B, E>(
    headers: impl Future<Output = Result<http::Response<B>, E>>,
    collector: BoundedBody,
    should_exit: &impl Fn() -> bool,
) -> Result<transport::ResponseBody, RoutedHttpError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
    E: Into<RoutedHttpError>,
{
    await_request_with_cancel(
        async {
            let response = headers.await.map_err(Into::into)?;
            collect_response(response, collector).await
        },
        should_exit,
        "Enhance PIR request timed out",
    )
    .await
}

async fn collect_response<B>(
    response: http::Response<B>,
    collector: BoundedBody,
) -> Result<transport::ResponseBody, RoutedHttpError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
{
    if !response.status().is_success() {
        return Err(RoutedHttpError::HttpStatus(response.status().as_u16()));
    }
    Ok(read_body_limited(response.status(), response.into_body(), collector).await?)
}

pub(super) async fn await_request_with_cancel<T, E: Into<RoutedHttpError>>(
    request: impl Future<Output = Result<T, E>>,
    should_exit: &impl Fn() -> bool,
    timeout_message: &'static str,
) -> Result<T, RoutedHttpError> {
    if should_exit() {
        return Err(RoutedHttpError::Cancelled);
    }
    tokio::pin!(request);
    tokio::select! {
        biased;
        _ = super::super::watch_for_exit(should_exit) => Err(RoutedHttpError::Cancelled),
        result = tokio::time::timeout(HTTP_TIMEOUT, &mut request) => {
            result
                .map_err(|_| RoutedHttpError::Failed(SyncError::net(timeout_message)))?
                .map_err(Into::into)
        }
    }
}

async fn read_body_limited<B>(
    status: StatusCode,
    mut body: B,
    mut bytes: BoundedBody,
) -> Result<transport::ResponseBody, SyncError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
{
    debug_assert!(status.is_success());
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|error| {
            SyncError::net(format!("read private-service response body: {error}"))
        })?;
        if let Some(data) = frame.data_ref() {
            bytes.extend(data).map_err(client_protocol_error)?;
        }
    }
    Ok(bytes.finish())
}

impl<F: Fn() -> bool> RoutedTransport<'_, F> {
    /// Bounded bytes for protocols that supply their own decoding and limits.
    pub(crate) async fn bytes(
        &self,
        method: Method,
        url: &str,
        body: Vec<u8>,
        limit: usize,
    ) -> Result<Vec<u8>, RoutedHttpError> {
        await_request_with_cancel(
            async {
                let response = routed_response(
                    method,
                    url,
                    body,
                    self.should_exit,
                    &self.direct,
                    self.route_policy,
                )
                .await?;
                collect_bytes(response, limit).await
            },
            self.should_exit,
            "Private-service request timed out",
        )
        .await
    }
}

async fn collect_bytes<B>(
    response: http::Response<B>,
    limit: usize,
) -> Result<Vec<u8>, RoutedHttpError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
{
    if !response.status().is_success() {
        return Err(RoutedHttpError::HttpStatus(response.status().as_u16()));
    }
    let mut incoming = response.into_body();
    let mut bytes = Vec::new();
    while let Some(frame) = incoming.frame().await {
        let frame = frame.map_err(|_| SyncError::net("Read private-service body failed"))?;
        if let Some(data) = frame.data_ref() {
            if data.len() > limit.saturating_sub(bytes.len()) {
                return Err(SyncError::parse("Private-service body exceeds limit").into());
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok(bytes)
}

#[cfg(test)]
mod byte_tests {
    use super::*;
    #[tokio::test]
    async fn body_limits_and_http_status_survive_collection() {
        let response = || http::Response::new(Full::new(Bytes::from_static(b"1234")));
        assert_eq!(collect_bytes(response(), 4).await.unwrap(), b"1234");
        assert!(matches!(
            collect_bytes(response(), 3).await,
            Err(RoutedHttpError::Failed(_))
        ));
        let mut conflict = response();
        *conflict.status_mut() = StatusCode::CONFLICT;
        assert!(matches!(
            collect_bytes(conflict, 0).await,
            Err(RoutedHttpError::HttpStatus(409))
        ));
    }
    #[tokio::test]
    async fn unavailable_tor_never_opens_a_direct_socket_and_cancel_stops_requests() {
        let _guard = crate::network_privacy::test_route_policy::lock_route_policy();
        let _ = rustls::crypto::ring::default_provider().install_default();
        crate::network_privacy::begin_tor_enable();
        crate::network_privacy::fail_tor_enable();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!(
            "https://{}/v1/receiver/init",
            listener.local_addr().unwrap()
        );
        let active = || false;
        let route = RoutedTransport::new(&active);
        let result = route.bytes(Method::GET, &url, vec![], 1024).await;
        assert!(matches!(result, Err(RoutedHttpError::Failed(_))));
        assert!(
            tokio::time::timeout(Duration::from_millis(30), listener.accept())
                .await
                .is_err()
        );
        assert!(route
            .bytes(Method::GET, "http://127.0.0.1/", vec![], 1024)
            .await
            .is_err());
        let cancelled = || true;
        let route = RoutedTransport::new(&cancelled);
        assert!(matches!(
            route.bytes(Method::POST, &url, vec![1], 1024).await,
            Err(RoutedHttpError::Cancelled)
        ));
        assert!(route
            .bytes(Method::GET, "http://127.0.0.1/", vec![], 1024)
            .await
            .is_err());
    }
}
