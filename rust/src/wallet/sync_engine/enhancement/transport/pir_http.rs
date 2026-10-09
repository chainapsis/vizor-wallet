//! Transparent PIR and txid display PIR over the wallet's routed HTTPS
//! transport.
//!
//! [`RoutedExchange`] is the raw [`HttpExchange`] `zakura_pir_transparent`
//! sends both services through. It shares [`RoutedTransport`] with the other
//! private services: HTTPS only, Tor when the wallet wants it and the
//! direct-route lease otherwise, no User-Agent, and the caller's
//! cancellation. The library owns the routes, their body limits and what
//! every status means; this sends what it is asked, reads at most the
//! request's limits, and never retries.
//!
//! The trait is synchronous and the route is async, so each request blocks on
//! the runtime handle. Callers run on a blocking thread; `Handle::block_on`
//! panics on a runtime worker.
//!
//! Logs name the service, the method and the route template, never a shard
//! id, digest, body or the origin.

use bytes::Bytes;
use http::{header::RETRY_AFTER, Method};
use http_body_util::BodyExt;
use hyper::body::Body;
use std::{fmt, time::Duration};
use tokio::runtime::Handle;
use zakura_pir_transparent::{HttpExchange, HttpFailure, HttpMethod, HttpReply, HttpRequest};

use super::{routed_response, secure_endpoint_uri, RoutedHttpError, RoutedTransport};
use crate::wallet::sync_engine::{watch_for_exit, SyncError};

/// The `x-txid-map-sha256` header the txid display map carries.
const MAP_DIGEST_HEADER: &str = "x-txid-map-sha256";

/// One PIR service's origin over one routed HTTPS client. Every request is
/// bounded by the service's deadline, from dispatch through the last body
/// byte, and stops when `should_exit` does.
pub(crate) struct RoutedExchange<'a, F> {
    route: RoutedTransport<'a, F>,
    /// The service's name in log lines.
    service: &'static str,
    /// The configured origin, without a trailing slash.
    origin: String,
    handle: Handle,
    timeout: Duration,
    #[cfg(test)]
    observer: Option<RequestObserver>,
}

impl<'a, F: Fn() -> bool> RoutedExchange<'a, F> {
    /// Transparent PIR at `origin`.
    pub(crate) fn transparent(
        origin: &str,
        should_exit: &'a F,
        handle: Handle,
    ) -> Result<Self, SyncError> {
        Self::new(
            "transparent PIR",
            origin,
            should_exit,
            handle,
            Duration::from_secs(60),
        )
    }

    /// Txid display PIR at `origin`.
    pub(crate) fn txid(
        origin: &str,
        should_exit: &'a F,
        handle: Handle,
    ) -> Result<Self, SyncError> {
        Self::new(
            "txid PIR",
            origin,
            should_exit,
            handle,
            Duration::from_secs(30),
        )
    }

    /// Builds the exchange for `origin` on the wallet's preferred route.
    ///
    /// Refuses an origin that is not HTTPS, or that carries a query the
    /// service routes would be appended to.
    fn new(
        service: &'static str,
        origin: &str,
        should_exit: &'a F,
        handle: Handle,
        timeout: Duration,
    ) -> Result<Self, SyncError> {
        if secure_endpoint_uri(origin)?.query().is_some() {
            return Err(SyncError::parse(format!(
                "{service} origin must not carry a query"
            )));
        }
        Ok(Self {
            route: RoutedTransport::new(should_exit),
            service,
            origin: origin.trim_end_matches('/').to_owned(),
            handle,
            timeout,
            #[cfg(test)]
            observer: None,
        })
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

    async fn exchange(&self, request: &HttpRequest) -> Result<HttpReply, HttpFailure> {
        let should_exit = self.route.should_exit;
        if should_exit() {
            return Err(HttpFailure::Cancelled);
        }
        let method = match request.method {
            HttpMethod::Get => Method::GET,
            HttpMethod::Post => Method::POST,
        };
        #[cfg(test)]
        let answer = self
            .observer
            .as_ref()
            .and_then(|observer| observer.observe(&method, &request.path, &request.body));
        let url = format!("{}{}", self.origin, request.path);
        let exchange = async {
            #[cfg(test)]
            if let Some(response) = answer {
                return read(response, request).await;
            }
            let response = routed_response(
                method,
                &url,
                request.body.clone(),
                should_exit,
                &self.route.direct,
                self.route.route_policy,
            )
            .await
            .map_err(|error| match error {
                RoutedHttpError::Cancelled => HttpFailure::Cancelled,
                // `routed_response` returns headers of every status.
                RoutedHttpError::HttpStatus(_) | RoutedHttpError::Failed(_) => {
                    HttpFailure::Unreachable
                }
            })?;
            read(response, request).await
        };
        let received = tokio::select! {
            biased;
            _ = watch_for_exit(should_exit) => Err(HttpFailure::Cancelled),
            received = tokio::time::timeout(self.timeout, exchange) => {
                received.unwrap_or(Err(HttpFailure::Timeout))
            }
        };
        // Cancellation wins a tie: a stopping caller acts on no reply that
        // raced it.
        if should_exit() {
            return Err(HttpFailure::Cancelled);
        }
        received
    }
}

impl<F: Fn() -> bool> HttpExchange for RoutedExchange<'_, F> {
    fn send(&self, request: &HttpRequest) -> Result<HttpReply, HttpFailure> {
        let received = self.handle.block_on(self.exchange(request));
        let (service, method, template) =
            (self.service, request.method.as_str(), &request.template);
        match &received {
            Ok(reply) => log::debug!(
                "{service} {method} {template}: HTTP {}, {} bytes",
                reply.status,
                reply.body.len()
            ),
            Err(failure) => log::debug!("{service} {method} {template}: {failure}"),
        }
        received
    }
}

/// Reads a success up to the request's limit, an error body up to its error
/// limit, and the two headers the library reads.
async fn read<B>(
    response: http::Response<B>,
    request: &HttpRequest,
) -> Result<HttpReply, HttpFailure>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: fmt::Display,
{
    let status = response.status();
    let header = |name: &str| {
        response
            .headers()
            .get(name)
            .and_then(|value| value.to_str().ok())
            .map(str::to_owned)
    };
    let retry_after = header(RETRY_AFTER.as_str());
    let map_sha256 = header(MAP_DIGEST_HEADER);
    let body = response.into_body();
    let body = if status.is_success() {
        match read_prefix(body, request.limit).await? {
            (bytes, true) => bytes,
            (_, false) => return Err(HttpFailure::TooLarge),
        }
    } else if request.error_limit > 0 {
        // The status is the refusal; a body that fails costs only its detail.
        read_prefix(body, request.error_limit)
            .await
            .map(|(bytes, _)| bytes)
            .unwrap_or_default()
    } else {
        Vec::new()
    };
    Ok(HttpReply {
        status: status.as_u16(),
        retry_after,
        map_sha256,
        body,
    })
}

/// Reads at most `limit` bytes of `body`, and whether the body ended within
/// them.
async fn read_prefix<B>(mut body: B, limit: usize) -> Result<(Vec<u8>, bool), HttpFailure>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: fmt::Display,
{
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|_| HttpFailure::Unreachable)?;
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

/// Test view of every request an exchange dispatches, which it answers in
/// place of the network, or only records on its way there. The exchange is
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
    fn observe(
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
impl ObservedRequest {
    /// The request as the library sent it, for a fake service's answer.
    pub(crate) fn http_method(&self) -> HttpMethod {
        if self.method == Method::POST {
            HttpMethod::Post
        } else {
            HttpMethod::Get
        }
    }
}

/// `reply` as the network would deliver it.
#[cfg(test)]
pub(crate) fn response(reply: HttpReply) -> http::Response<http_body_util::Full<Bytes>> {
    let mut response = http::Response::builder().status(reply.status);
    if let Some(retry_after) = &reply.retry_after {
        response = response.header(RETRY_AFTER, retry_after);
    }
    if let Some(map_sha256) = &reply.map_sha256 {
        response = response.header(MAP_DIGEST_HEADER, map_sha256);
    }
    response
        .body(http_body_util::Full::new(Bytes::from(reply.body)))
        .unwrap()
}

#[cfg(test)]
mod tests {
    use super::super::RoutePolicy;
    use super::*;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };
    use tokio::runtime::Runtime;

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

    fn reply(
        status: u16,
        headers: &[(&str, &str)],
        body: &[u8],
    ) -> http::Response<http_body_util::Full<Bytes>> {
        let mut response = http::Response::builder().status(status);
        for (name, value) in headers {
            response = response.header(*name, *value);
        }
        response
            .body(http_body_util::Full::new(Bytes::copy_from_slice(body)))
            .unwrap()
    }

    fn request(method: HttpMethod, error_limit: usize) -> HttpRequest {
        HttpRequest {
            method,
            path: format!("/v1/shards/{SHARD}/revisions/{REVISION}/query/directory"),
            template: "/v1/shards/{id}/revisions/{rev}/query/directory".to_owned(),
            body: QUERY.to_vec(),
            limit: LIMIT,
            error_limit,
        }
    }

    /// An exchange whose observer answers every request.
    fn answered<'a, F: Fn() -> bool>(
        runtime: &Runtime,
        should_exit: &'a F,
        answer: impl Fn(&ObservedRequest) -> http::Response<http_body_util::Full<Bytes>>
            + Send
            + Sync
            + 'static,
    ) -> (RoutedExchange<'a, F>, RequestObserver) {
        let observer = RequestObserver::answering(answer);
        let exchange = RoutedExchange::transparent(ORIGIN, should_exit, runtime.handle().clone())
            .unwrap()
            .with_observer(observer.clone());
        (exchange, observer)
    }

    #[test]
    fn plaintext_origins_are_refused_and_the_wallet_route_is_used() {
        let runtime = runtime();
        let exit = || false;
        for origin in [
            "http://transparent-pir.example",
            "ws://transparent-pir.example",
            "transparent-pir.example",
            "https://transparent-pir.example?route=1",
        ] {
            assert!(
                RoutedExchange::transparent(origin, &exit, runtime.handle().clone()).is_err(),
                "accepted {origin}"
            );
            assert!(
                RoutedExchange::txid(origin, &exit, runtime.handle().clone()).is_err(),
                "accepted {origin}"
            );
        }
        let exchange = RoutedExchange::txid(
            "https://transparent-pir.example/",
            &exit,
            runtime.handle().clone(),
        )
        .unwrap();
        assert_eq!(exchange.origin, ORIGIN);
        assert_eq!(exchange.route_policy(), RoutePolicy::WalletPreference);
    }

    #[test]
    fn requests_and_replies_cross_unchanged() {
        let runtime = runtime();
        let exit = || false;
        let (exchange, observer) = answered(&runtime, &exit, |request| {
            reply(
                200,
                &[("retry-after", "7"), (MAP_DIGEST_HEADER, "beef")],
                &request.body,
            )
        });
        let received = exchange.send(&request(HttpMethod::Post, 0)).unwrap();
        assert_eq!(
            received,
            HttpReply {
                status: 200,
                retry_after: Some("7".to_owned()),
                map_sha256: Some("beef".to_owned()),
                body: QUERY.to_vec(),
            }
        );
        let sent = observer.requests();
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0].method, Method::POST);
        assert_eq!(sent[0].path, request(HttpMethod::Post, 0).path);
        assert_eq!(sent[0].body, QUERY);
    }

    #[test]
    fn bodies_are_read_to_their_limits() {
        let runtime = runtime();
        let exit = || false;
        let (full, _) = answered(&runtime, &exit, |_| reply(200, &[], &[7; LIMIT]));
        assert_eq!(
            full.send(&request(HttpMethod::Get, 0)).unwrap().body.len(),
            LIMIT
        );
        let (over, _) = answered(&runtime, &exit, |_| reply(200, &[], &[7; LIMIT + 1]));
        assert_eq!(
            over.send(&request(HttpMethod::Get, 0)),
            Err(HttpFailure::TooLarge)
        );
        // An error body is read only to its limit, and only when asked for;
        // its status always arrives.
        let (refused, _) = answered(&runtime, &exit, |_| reply(409, &[], &[7; 64]));
        assert_eq!(
            refused.send(&request(HttpMethod::Get, 16)).unwrap(),
            HttpReply {
                status: 409,
                body: vec![7; 16],
                ..HttpReply::default()
            }
        );
        assert!(refused
            .send(&request(HttpMethod::Get, 0))
            .unwrap()
            .body
            .is_empty());
    }

    #[test]
    fn a_cancelled_exchange_sends_nothing_and_drops_racing_replies() {
        let runtime = runtime();
        let exit = || true;
        let (exchange, observer) = answered(&runtime, &exit, |_| reply(200, &[], b"{}"));
        assert_eq!(
            exchange.send(&request(HttpMethod::Get, 0)),
            Err(HttpFailure::Cancelled)
        );
        assert!(observer.requests().is_empty());

        let cancelled = Arc::new(AtomicBool::new(false));
        let exit = {
            let cancelled = cancelled.clone();
            move || cancelled.load(Ordering::SeqCst)
        };
        let (exchange, observer) = answered(&runtime, &exit, move |_| {
            cancelled.store(true, Ordering::SeqCst);
            reply(200, &[], b"{}")
        });
        for _ in 0..2 {
            assert_eq!(
                exchange.send(&request(HttpMethod::Get, 0)),
                Err(HttpFailure::Cancelled)
            );
        }
        assert_eq!(observer.requests().len(), 1);
    }

    use super::super::test_log::log_lines;

    #[test]
    fn debug_log_lines_carry_only_route_templates() {
        let runtime = runtime();
        let body = format!("{SHARD}{REVISION}{}", hex::encode(QUERY));
        let lines = log_lines(|| {
            let exit = || false;
            let echo = body.clone();
            let (exchange, _) =
                answered(&runtime, &exit, move |_| reply(200, &[], echo.as_bytes()));
            exchange.send(&request(HttpMethod::Post, 0)).unwrap();
            let (refused, _) = answered(&runtime, &exit, |_| {
                reply(409, &[], br#"{"map_sha256":"beef"}"#)
            });
            refused.send(&request(HttpMethod::Get, 4096)).unwrap();
            let cancelled = || true;
            let (stopped, _) = answered(&runtime, &cancelled, |_| reply(200, &[], b""));
            stopped.send(&request(HttpMethod::Get, 0)).unwrap_err();
        });

        let template = "/v1/shards/{id}/revisions/{rev}/query/directory";
        let expected = [
            format!(
                "DEBUG transparent PIR POST {template}: HTTP 200, {} bytes",
                body.len()
            ),
            format!("DEBUG transparent PIR GET {template}: HTTP 409, 21 bytes"),
            format!("DEBUG transparent PIR GET {template}: cancelled"),
        ];
        // The exchange's own lines are exactly one per request, and nothing
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
