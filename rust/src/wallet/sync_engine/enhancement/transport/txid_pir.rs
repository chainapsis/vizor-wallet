//! Txid display PIR over the wallet's routed HTTPS transport.
//!
//! [`TxidPirHttp`] is the [`TxidTransport`] wallet-pir's txid display client
//! (re-exported by `zakura_pir_transparent`) sends through: HTTPS only, Tor
//! when the wallet wants it and the direct-route lease otherwise, no
//! User-Agent, and the caller's cancellation. It shares [`RoutedTransport`]
//! with the other private services.
//!
//! The trait is synchronous and the route is async, so each request blocks on
//! the runtime handle. Callers run a lookup inside `spawn_blocking`;
//! `Handle::block_on` panics on a runtime worker.
//!
//! Nothing is retried here; the client interprets every status itself. A
//! success over its route's bound fails the request, and error bodies are
//! never read. Logs name the route template, never a shard id, digest, body
//! or the origin.

use bytes::Bytes;
use http::{header::RETRY_AFTER, Method};
use http_body_util::BodyExt;
use hyper::body::Body;
use std::{fmt, time::Duration};
use tokio::runtime::Handle;
use zakura_pir_transparent::{TransportError, TxidReply, TxidRequest, TxidTransport};

use super::{routed_response, secure_endpoint_uri, RoutedHttpError, RoutedTransport};
use crate::wallet::sync_engine::{watch_for_exit, SyncError};

/// One request's bound, from dispatch through the last body byte.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// The `x-txid-map-sha256` header the map carries.
const MAP_DIGEST_HEADER: &str = "x-txid-map-sha256";

/// Largest successful body of a request with `template`. Queries are bounded
/// by every segment's answer of the widest supported geometry.
fn response_limit(template: &str) -> usize {
    match template {
        "/v1/txid/init" => 256 << 10,
        "/v1/txid/shards" => 4 << 20,
        template if template.ends_with("/manifest") => 1 << 20,
        template if template.contains("/setup/") => 1 << 20,
        _ => 8 << 20,
    }
}

/// Why a request delivered no reply. Its name is the transport error's text,
/// which carries no URL, body or identifier.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum TxidHttpFailure {
    /// The lookup is stopping: nothing was sent, or the reply is dropped.
    Cancelled,
    /// A successful body exceeded its route's bound.
    TooLarge,
    /// No whole reply within [`REQUEST_TIMEOUT`].
    Timeout,
    /// The route or connection failed.
    Failed,
}

impl TxidHttpFailure {
    pub(crate) fn name(self) -> &'static str {
        match self {
            TxidHttpFailure::Cancelled => "cancelled",
            TxidHttpFailure::TooLarge => "too large",
            TxidHttpFailure::Timeout => "timed out",
            TxidHttpFailure::Failed => "route failed",
        }
    }
}

/// The txid display transport over one routed HTTPS client. Every request is
/// bounded by [`REQUEST_TIMEOUT`] and stops when `should_exit` does.
pub(crate) struct TxidPirHttp<'a, F> {
    route: RoutedTransport<'a, F>,
    /// The configured origin, without a trailing slash.
    origin: String,
    handle: Handle,
    #[cfg(test)]
    observer: Option<super::RequestObserver>,
}

impl<'a, F: Fn() -> bool> TxidPirHttp<'a, F> {
    /// Builds the transport for `origin` on the wallet's preferred route.
    ///
    /// Refuses an origin that is not HTTPS, or that carries a query the
    /// service routes would be appended to.
    pub(crate) fn new(origin: &str, should_exit: &'a F, handle: Handle) -> Result<Self, SyncError> {
        if secure_endpoint_uri(origin)?.query().is_some() {
            return Err(SyncError::parse("txid PIR origin must not carry a query"));
        }
        Ok(Self {
            route: RoutedTransport::new(should_exit),
            origin: origin.trim_end_matches('/').to_owned(),
            handle,
            #[cfg(test)]
            observer: None,
        })
    }

    #[cfg(test)]
    pub(crate) fn route_policy(&self) -> super::RoutePolicy {
        self.route.route_policy
    }

    /// Records every request; see [`super::RequestObserver`].
    #[cfg(test)]
    pub(crate) fn with_observer(mut self, observer: super::RequestObserver) -> Self {
        self.observer = Some(observer);
        self
    }

    async fn exchange(&self, request: &TxidRequest) -> Result<TxidReply, TxidHttpFailure> {
        let should_exit = self.route.should_exit;
        if should_exit() {
            return Err(TxidHttpFailure::Cancelled);
        }
        let method = Method::from_bytes(request.method.as_str().as_bytes())
            .map_err(|_| TxidHttpFailure::Failed)?;
        let path = request.path();
        #[cfg(test)]
        let answer = self
            .observer
            .as_ref()
            .and_then(|observer| observer.observe(&method, path, &request.body));
        let url = format!("{}{path}", self.origin);
        let limit = response_limit(request.template());
        let exchange = async {
            #[cfg(test)]
            if let Some(response) = answer {
                return read(response, limit).await;
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
                RoutedHttpError::Cancelled => TxidHttpFailure::Cancelled,
                // `routed_response` returns headers of every status.
                RoutedHttpError::HttpStatus(_) | RoutedHttpError::Failed(_) => {
                    TxidHttpFailure::Failed
                }
            })?;
            read(response, limit).await
        };
        let received = tokio::select! {
            biased;
            _ = watch_for_exit(should_exit) => Err(TxidHttpFailure::Cancelled),
            received = tokio::time::timeout(REQUEST_TIMEOUT, exchange) => {
                received.unwrap_or(Err(TxidHttpFailure::Timeout))
            }
        };
        // Cancellation wins a tie: a stopping lookup acts on no reply that
        // raced it.
        if should_exit() {
            return Err(TxidHttpFailure::Cancelled);
        }
        received
    }
}

impl<F: Fn() -> bool> TxidTransport for TxidPirHttp<'_, F> {
    fn send(&mut self, request: TxidRequest) -> Result<TxidReply, TransportError> {
        let received = self.handle.block_on(self.exchange(&request));
        let (method, template) = (request.method.as_str(), request.template());
        match &received {
            Ok(reply) => log::debug!(
                "txid PIR {method} {template}: HTTP {}, {} bytes",
                reply.status,
                reply.body.len()
            ),
            Err(failure) => log::debug!("txid PIR {method} {template}: {}", failure.name()),
        }
        received.map_err(|failure| TransportError(failure.name().to_owned()))
    }
}

/// Reads a success up to `limit`; an error status keeps only its headers.
async fn read<B>(response: http::Response<B>, limit: usize) -> Result<TxidReply, TxidHttpFailure>
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
    let body = if status.is_success() {
        read_limited(response.into_body(), limit).await?
    } else {
        Vec::new()
    };
    Ok(TxidReply {
        status: status.as_u16(),
        retry_after,
        map_sha256,
        body,
    })
}

async fn read_limited<B>(mut body: B, limit: usize) -> Result<Vec<u8>, TxidHttpFailure>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: fmt::Display,
{
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|_| TxidHttpFailure::Failed)?;
        if let Some(data) = frame.data_ref() {
            if bytes.len() + data.len() > limit {
                return Err(TxidHttpFailure::TooLarge);
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::super::{ObservedRequest, RequestObserver, RoutePolicy};
    use super::*;
    use http_body_util::Full;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };
    use tokio::runtime::Runtime;
    use zakura_pir_transparent::{TxidDisplayClient, TxidError};

    const ORIGIN: &str = "https://transparent-pir.example";

    fn runtime() -> Runtime {
        let _ = rustls::crypto::ring::default_provider().install_default();
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .unwrap()
    }

    fn reply(status: u16, headers: &[(&str, &str)], body: &[u8]) -> http::Response<Full<Bytes>> {
        let mut response = http::Response::builder().status(status);
        for (name, value) in headers {
            response = response.header(*name, *value);
        }
        response
            .body(Full::new(Bytes::copy_from_slice(body)))
            .unwrap()
    }

    /// One lookup through the transport, its observer answering.
    fn lookup(
        should_exit: &dyn Fn() -> bool,
        answer: impl Fn(&ObservedRequest) -> http::Response<Full<Bytes>> + Send + Sync + 'static,
    ) -> (Result<(), TxidError>, RequestObserver) {
        let runtime = runtime();
        let observer = RequestObserver::answering(answer);
        let mut http = TxidPirHttp::new(ORIGIN, &should_exit, runtime.handle().clone())
            .unwrap()
            .with_observer(observer.clone());
        let found = TxidDisplayClient::new().lookup(&mut http, [7; 32], 3_460_000, &|| false);
        (found.map(|_| ()), observer)
    }

    #[test]
    fn plaintext_origins_are_refused_and_the_wallet_route_is_used() {
        let runtime = runtime();
        let exit = || false;
        for origin in [
            "http://transparent-pir.example",
            "transparent-pir.example",
            "https://transparent-pir.example?route=1",
        ] {
            assert!(
                TxidPirHttp::new(origin, &exit, runtime.handle().clone()).is_err(),
                "accepted {origin}"
            );
        }
        let http = TxidPirHttp::new(
            "https://transparent-pir.example/",
            &exit,
            runtime.handle().clone(),
        )
        .unwrap();
        assert_eq!(http.origin, ORIGIN);
        assert_eq!(http.route_policy(), RoutePolicy::WalletPreference);
    }

    #[test]
    fn replies_carry_status_and_retry_after_to_the_client() {
        let (found, observer) = lookup(&|| false, |_| reply(503, &[("retry-after", "7")], b"busy"));
        assert_eq!(
            found.unwrap_err(),
            TxidError::Unavailable {
                retry_after: Some(Duration::from_secs(7))
            }
        );
        let requests = observer.requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(
            (requests[0].method.as_str(), requests[0].path.as_str()),
            ("GET", "/v1/txid/init")
        );
    }

    #[test]
    fn oversized_bodies_fail_as_transport_errors() {
        let (found, _) = lookup(&|| false, |_| reply(200, &[], &vec![b' '; (256 << 10) + 1]));
        assert!(
            matches!(found, Err(TxidError::Transport(ref error)) if error.0 == "too large"),
            "{found:?}"
        );
    }

    #[test]
    fn a_cancelled_transport_sends_nothing_and_drops_racing_replies() {
        let (found, observer) = lookup(&|| true, |_| reply(200, &[], b"{}"));
        assert!(matches!(found, Err(TxidError::Transport(_))), "{found:?}");
        assert!(observer.requests().is_empty());

        let cancelled = Arc::new(AtomicBool::new(false));
        let exit = {
            let cancelled = cancelled.clone();
            move || cancelled.load(Ordering::SeqCst)
        };
        let (found, observer) = lookup(&exit, move |_| {
            cancelled.store(true, Ordering::SeqCst);
            reply(200, &[], b"{}")
        });
        assert!(found.is_err());
        assert_eq!(observer.requests().len(), 1);
    }
}
