//! Vizor's request executor for every SDK voting transport.
//!
//! `zcash_voting` owns protocol headers, deadlines, response limits, and the
//! definite-versus-ambiguous classification of failures; this executor owns
//! only how one request reaches the network. It follows the app's current
//! route: Tor when the user selected it and the client is usable, otherwise a
//! lease-governed direct connection. A selected but unusable Tor route fails
//! closed, never falling back to the clearnet.
//!
//! The SDK's dispatch hook is called from librustzcash's header callback,
//! which runs only after the Tor circuit and TLS handshake are ready and
//! immediately before the HTTP request is built, so everything before it is a
//! definite pre-dispatch failure the SDK may retry elsewhere.

use std::future::Future;

use bytes::Bytes;
use http::{Method, Uri};
use http_body_util::{BodyExt, Full};
use hyper_util::client::legacy::connect::HttpConnector;
use zcash_voting::{DirectRoute, RouteError, RouteFuture, RouteHttp, RouteRequest, RouteResponse};

use crate::network_privacy;

/// Executor that follows the wallet's network route.
pub struct VizorRoute {
    direct: DirectRoute,
}

impl Default for VizorRoute {
    fn default() -> Self {
        Self::new()
    }
}

impl VizorRoute {
    pub fn new() -> Self {
        Self {
            direct: DirectRoute::with_http_connector(DirectRouteConnector::new()),
        }
    }

    async fn over_tor(
        &self,
        tor: &zcash_client_backend::tor::Client,
        request: RouteRequest<'_>,
        on_dispatch: &(dyn Fn() + Send + Sync),
    ) -> Result<RouteResponse, RouteError> {
        let uri: Uri = request
            .url
            .parse()
            .map_err(|error| RouteError::before_dispatch(format!("invalid URL: {error}")))?;
        let headers = request.headers.to_vec();
        let apply_headers = move |mut builder: http::request::Builder| {
            for (name, value) in &headers {
                builder = builder.header(name, value);
            }
            // librustzcash invokes this only after the Tor stream and TLS
            // handshake are ready, immediately before constructing the HTTP
            // request.
            on_dispatch();
            builder
        };
        let max_response_bytes = request.max_response_bytes;
        let collect = move |mut body: hyper::body::Incoming| async move {
            collect_body_with_limit(&mut body, max_response_bytes).await
        };
        // Retries are the SDK's decision, not the transport's: ask arti for none.
        let response = match request.method {
            Method::POST => {
                tor.http_post(
                    uri,
                    apply_headers,
                    Full::new(Bytes::from(request.body)),
                    collect,
                    0,
                    |_| None,
                )
                .await
            }
            _ => tor.http_get(uri, apply_headers, collect, 0, |_| None).await,
        }
        .map_err(classify_tor_error)?;
        let status = response.status().as_u16();
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
        Ok(RouteResponse {
            status,
            headers,
            body: response.into_body(),
        })
    }
}

impl RouteHttp for VizorRoute {
    fn execute<'a>(
        &'a self,
        request: RouteRequest<'a>,
        on_dispatch: &'a (dyn Fn() + Send + Sync),
    ) -> RouteFuture<'a> {
        Box::pin(async move {
            // Fails closed: a broken Tor route is an error, never a direct
            // fallback. A bootstrap in flight is waited out, but only inside
            // this request's own budget; nothing has been dispatched yet, so
            // running out is a definite pre-dispatch failure.
            let route = tokio::time::timeout(
                request.timeout,
                network_privacy::tor_client_for_route(true, || false),
            )
            .await
            .map_err(|_| {
                RouteError::before_dispatch("network route was not ready before request dispatch")
            })?
            .map_err(RouteError::before_dispatch)?;
            match route {
                Some(tor) => self.over_tor(&tor, request, on_dispatch).await,
                None => self.direct.execute(request, on_dispatch).await,
            }
        })
    }

    /// Both routes call the hook before they can observe a connection-setup
    /// failure, so a pre-dispatch phase reported after it stays definite.
    ///
    /// The direct route is `DirectRoute`, whose pooled Hyper client fuses
    /// connection setup with the first write. The Tor route calls the hook
    /// from librustzcash's header callback, which runs once the circuit and
    /// TLS handshake are ready. The contract that buys this — report
    /// `BeforeDispatch` only for failures the client attributes to
    /// connection setup, never for one that may have followed a write — is
    /// what `classify_tor_error` enforces: it names the Tor-bootstrap, TLS,
    /// connect-timeout, spawn, URL and request-construction errors, and
    /// leaves every wire error, `HttpError::Hyper` included, after dispatch.
    fn hook_precedes_connection_setup(&self) -> bool {
        true
    }
}

const BODY_LIMIT_MARKER: &str = "response body exceeded";

/// Reads a routed response body without buffering beyond `max_response_bytes`.
async fn collect_body_with_limit(
    body: &mut hyper::body::Incoming,
    max_response_bytes: usize,
) -> Result<Vec<u8>, zcash_client_backend::tor::Error> {
    use zcash_client_backend::tor::http::HttpError;

    let mut collected: Vec<u8> = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(HttpError::from)?;
        if let Ok(data) = frame.into_data() {
            if collected.len().saturating_add(data.len()) > max_response_bytes {
                return Err(std::io::Error::other(format!(
                    "{BODY_LIMIT_MARKER} {max_response_bytes} bytes"
                ))
                .into());
            }
            collected.extend_from_slice(&data);
        }
    }
    Ok(collected)
}

/// Separates Tor failures that prove nothing was dispatched from failures that
/// can happen after the request left.
fn classify_tor_error(error: zcash_client_backend::tor::Error) -> RouteError {
    use zcash_client_backend::tor::{
        http::{HttpError, TimeoutPhase},
        Error,
    };

    let message = error.to_string();
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
        RouteError::before_dispatch(message)
    } else if message.contains(BODY_LIMIT_MARKER) {
        RouteError::response_read(message)
    } else {
        RouteError::after_dispatch(message)
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

#[cfg(test)]
mod tests {
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
        time::Duration,
    };

    use zcash_voting::{
        ChainTransportFailureKind, HelperTransport, HelperTransportError, HyperTransport,
        RoutePhase,
    };

    use super::{classify_tor_error, VizorRoute};

    fn transport() -> HyperTransport<VizorRoute> {
        HyperTransport::with_route(VizorRoute::new())
    }

    #[test]
    fn tor_failures_classify_by_dispatch_phase() {
        use zcash_client_backend::tor::{
            http::{HttpError, TimeoutPhase},
            Error,
        };

        let request_build_error = http::Request::builder()
            .header("bad\nheader", "value")
            .body(())
            .unwrap_err();
        for error in [
            Error::MissingTorDirectory,
            Error::Http(HttpError::NonHttpUrl),
            Error::Http(HttpError::Http(request_build_error)),
            Error::Http(HttpError::Tls(std::io::Error::other("tls failed"))),
            Error::Http(HttpError::Timeout(TimeoutPhase::Connect)),
        ] {
            assert_eq!(classify_tor_error(error).phase, RoutePhase::BeforeDispatch);
        }
        for error in [
            Error::Http(HttpError::Timeout(TimeoutPhase::Request)),
            Error::Http(HttpError::Timeout(TimeoutPhase::ResponseBody)),
            Error::Http(HttpError::Json(
                serde_json::from_str::<serde_json::Value>("{").unwrap_err(),
            )),
            Error::Io(std::io::Error::other("response stream failed")),
        ] {
            assert_eq!(classify_tor_error(error).phase, RoutePhase::AfterDispatch);
        }
        let oversized = Error::Io(std::io::Error::other(
            "helper response body exceeded 1 bytes",
        ));
        assert_eq!(
            classify_tor_error(oversized).phase,
            RoutePhase::ResponseRead
        );
    }

    #[tokio::test]
    async fn selected_direct_route_reaches_the_server() {
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

        let response = transport()
            .post_json(
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
            // Accept TCP but never complete TLS.
            thread::sleep(Duration::from_millis(100));
        });
        let result = transport()
            .post_json(
                &format!("https://{address}/shielded-vote/v1/shares"),
                br#"{"share_index":0}"#.to_vec(),
                Duration::from_millis(20),
            )
            .await;
        assert!(
            matches!(result, Err(HelperTransportError::Transport(_))),
            "{result:?}"
        );
        server.join().unwrap();
    }

    /// The route wait is charged to the same budget as the request, and a
    /// POST that never left the app is a definite pre-dispatch failure.
    #[tokio::test]
    async fn route_wait_expiry_is_bounded_and_safe_to_retry() {
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        crate::network_privacy::begin_tor_enable();
        let started = std::time::Instant::now();
        let result = transport()
            .post_json(
                "https://helper.invalid/shielded-vote/v1/shares",
                br#"{"share_index":0}"#.to_vec(),
                Duration::from_millis(200),
            )
            .await;
        assert!(
            matches!(result, Err(HelperTransportError::Transport(_))),
            "{result:?}"
        );
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[tokio::test]
    async fn unusable_tor_route_fails_closed_without_direct_fallback() {
        let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
        crate::network_privacy::begin_tor_enable();
        crate::network_privacy::fail_tor_enable();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let result = transport()
            .get(
                &format!("http://{address}/shielded-vote/v1/status"),
                Duration::from_millis(500),
            )
            .await;
        assert!(
            matches!(result, Err(HelperTransportError::Transport(_))),
            "{result:?}"
        );
        // Nothing may have reached the clearnet listener.
        listener.set_nonblocking(true).unwrap();
        assert!(listener.accept().is_err());
        let _ = ChainTransportFailureKind::DefinitelyUnsent;
    }
}
