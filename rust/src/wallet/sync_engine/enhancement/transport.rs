//! Shared cancellation-aware HTTPS transport for Enhance PIR and Status PIR.

use bytes::Bytes;
use http::{Method, Request, StatusCode};
use http_body_util::{BodyExt, Full};
use hyper::body::{Body, Incoming};
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::{client::legacy::Client, rt::TokioExecutor};
use std::{
    future::Future,
    sync::atomic::{AtomicU16, Ordering},
    time::Duration,
};
use zakura_pir_enhance::{
    transport::{self, BoundedBody},
    ClientError,
};

use super::{
    super::{lwd::DirectRouteConnector, SyncError},
    private_pir::{client_transport_error, EnhancePirRunError},
};

pub(super) const HTTP_TIMEOUT: Duration = Duration::from_secs(120);
type DirectHttpsClient = Client<hyper_rustls::HttpsConnector<DirectRouteConnector>, Full<Bytes>>;

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
pub(in crate::wallet::sync_engine) struct RoutedTransport<'a, F> {
    should_exit: &'a F,
    direct: DirectHttpsClient,
    direct_only: bool,
    status_session_error: AtomicU16,
}

impl<'a, F> RoutedTransport<'a, F> {
    pub(in crate::wallet::sync_engine) fn new(should_exit: &'a F) -> Self {
        Self::with_route(should_exit, false)
    }
    pub(in crate::wallet::sync_engine) fn new_direct(should_exit: &'a F) -> Self {
        Self::with_route(should_exit, true)
    }
    fn with_route(should_exit: &'a F, direct_only: bool) -> Self {
        let connector = HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_only()
            .enable_http1()
            .wrap_connector(DirectRouteConnector::new());
        Self {
            should_exit,
            direct_only,
            status_session_error: AtomicU16::new(0),
            // Cheap: no connection is opened until the first request, and the
            // Tor route simply never uses it.
            direct: Client::builder(TokioExecutor::new()).build(connector),
        }
    }
}

impl<F> RoutedTransport<'_, F> {
    pub(in crate::wallet::sync_engine) fn take_status_session_conflict(&self) -> bool {
        matches!(
            self.status_session_error.swap(0, Ordering::SeqCst),
            409 | 410
        )
    }
}

impl<F: Fn() -> bool + Sync> zakura_pir_status::transport::Transport for RoutedTransport<'_, F> {
    async fn get(&self, url: &str, max_bytes: usize) -> Result<Vec<u8>, zakura_pir_status::Error> {
        self.status_request(Method::GET, url, Vec::new(), max_bytes)
            .await
    }

    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        max_bytes: usize,
    ) -> Result<Vec<u8>, zakura_pir_status::Error> {
        self.status_request(Method::POST, url, body, max_bytes)
            .await
    }
}

impl<F: Fn() -> bool> RoutedTransport<'_, F> {
    async fn status_request(
        &self,
        method: Method,
        url: &str,
        body: Vec<u8>,
        max_bytes: usize,
    ) -> Result<Vec<u8>, zakura_pir_status::Error> {
        use zakura_pir_status::Error;
        self.status_session_error.store(0, Ordering::SeqCst);
        let request = async {
            let response = routed_response(
                method,
                url,
                body,
                self.should_exit,
                &self.direct,
                self.direct_only,
            )
            .await
            .map_err(|_| Error::Unavailable)?;
            match response.status().as_u16() {
                status @ (409 | 410) => {
                    self.status_session_error.store(status, Ordering::SeqCst);
                    return Err(Error::Unavailable);
                }
                _ if !response.status().is_success() => return Err(Error::Unavailable),
                _ => {}
            }
            let mut incoming = response.into_body();
            let mut bytes = Vec::new();
            while let Some(frame) = incoming.frame().await {
                let frame = frame.map_err(|_| Error::Unavailable)?;
                if let Some(data) = frame.data_ref() {
                    if data.len() > max_bytes.saturating_sub(bytes.len()) {
                        return Err(Error::Malformed);
                    }
                    bytes.extend_from_slice(data);
                }
            }
            Ok(bytes)
        };
        tokio::select! {
            biased;
            _ = super::super::watch_for_exit(self.should_exit) => Err(Error::Cancelled),
            result = tokio::time::timeout(Duration::from_secs(20), request) => {
                result.map_err(|_| Error::Timeout)?
            }
        }
    }
}

impl<F: Fn() -> bool> transport::Transport for RoutedTransport<'_, F> {
    async fn execute(
        &self,
        request: transport::Request,
    ) -> Result<transport::ResponseBody, ClientError> {
        let collector = request.response_body();
        let response = routed_request(
            match request.method {
                transport::Method::Get => Method::GET,
                transport::Method::Post => Method::POST,
            },
            &request.url,
            request.body,
            collector,
            self.should_exit,
            &self.direct,
        )
        .await;
        if (self.should_exit)() {
            return Err(ClientError::Cancelled);
        }
        response.map_err(client_transport_error)
    }
}
pub(super) fn client_protocol_error(error: ClientError) -> SyncError {
    SyncError::parse(format!("Enhance PIR: {error}"))
}

/// Validated before route selection, so a plaintext endpoint is rejected on
/// every route rather than only the direct one. Tor conceals the client from
/// the service, but the exit-to-service hop is still the open network.
pub(super) fn secure_endpoint_uri(url: &str) -> Result<http::Uri, SyncError> {
    let uri = url
        .parse::<http::Uri>()
        .map_err(|error| SyncError::parse(format!("invalid Enhance PIR URL: {error}")))?;
    if uri.scheme_str() != Some("https") {
        return Err(SyncError::parse("Enhance PIR transport requires HTTPS"));
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
) -> Result<transport::ResponseBody, EnhancePirRunError> {
    receive_response(
        routed_response(method, url, body, should_exit, direct, false),
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
    direct_only: bool,
) -> Result<http::Response<Incoming>, EnhancePirRunError> {
    if should_exit() {
        return Err(EnhancePirRunError::ExitRequested);
    }
    let uri = secure_endpoint_uri(url)?;
    if !direct_only && crate::network_privacy::is_tor_desired() {
        let client = crate::network_privacy::tor_client_for_route(true, || should_exit())
            .await
            .map_err(|error| {
                if should_exit() {
                    EnhancePirRunError::ExitRequested
                } else {
                    EnhancePirRunError::Failed(SyncError::net(format!(
                        "network privacy blocked Enhance PIR: {error}"
                    )))
                }
            })?
            .ok_or_else(|| {
                EnhancePirRunError::Failed(SyncError::net(
                    "Tor route changed before Enhance PIR request",
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
                _ => unreachable!("Enhance PIR uses GET and POST only"),
            }
            .map_err(|error| SyncError::net(format!("Enhance PIR Tor request failed: {error}")))
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
        .map_err(|error| SyncError::parse(format!("build Enhance PIR request: {error}")))?;
    let response = direct
        .request(request)
        .await
        .map_err(|error| SyncError::net(format!("Enhance PIR HTTPS request failed: {error}")))?;
    Ok(response)
}

/// Keep the deadline outside both phases; error bodies are never consumed.
pub(super) async fn receive_response<B, E>(
    headers: impl Future<Output = Result<http::Response<B>, E>>,
    collector: BoundedBody,
    should_exit: &impl Fn() -> bool,
) -> Result<transport::ResponseBody, EnhancePirRunError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
    E: Into<EnhancePirRunError>,
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
) -> Result<transport::ResponseBody, EnhancePirRunError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: std::fmt::Display,
{
    if !response.status().is_success() {
        return Err(EnhancePirRunError::HttpStatus(response.status().as_u16()));
    }
    Ok(read_body_limited(response.status(), response.into_body(), collector).await?)
}

pub(super) async fn await_request_with_cancel<T, E: Into<EnhancePirRunError>>(
    request: impl Future<Output = Result<T, E>>,
    should_exit: &impl Fn() -> bool,
    timeout_message: &'static str,
) -> Result<T, EnhancePirRunError> {
    if should_exit() {
        return Err(EnhancePirRunError::ExitRequested);
    }
    tokio::pin!(request);
    tokio::select! {
        biased;
        _ = super::super::watch_for_exit(should_exit) => Err(EnhancePirRunError::ExitRequested),
        result = tokio::time::timeout(HTTP_TIMEOUT, &mut request) => {
            result
                .map_err(|_| EnhancePirRunError::Failed(SyncError::net(timeout_message)))?
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
        let frame = frame
            .map_err(|error| SyncError::net(format!("read Enhance PIR response body: {error}")))?;
        if let Some(data) = frame.data_ref() {
            bytes.extend(data).map_err(client_protocol_error)?;
        }
    }
    Ok(bytes.finish())
}
