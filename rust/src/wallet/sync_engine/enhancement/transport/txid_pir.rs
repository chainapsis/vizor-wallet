//! Txid display PIR over the wallet's routed HTTPS transport.
//!
//! [`TxidPirHttp`] is the [`TxidTransport`] a display lookup sends through:
//! HTTPS only, Tor when the wallet wants it and the direct-route lease
//! otherwise, no User-Agent, and the caller's cancellation. It shares
//! [`RoutedTransport`] with the other private services.
//!
//! The trait is synchronous and the route is async, so each request blocks on
//! the runtime handle. Callers run a lookup inside `spawn_blocking`;
//! `Handle::block_on` panics on a runtime worker.
//!
//! Nothing is retried here; the client decides what a refusal is worth. A
//! success over the request's limit fails the request, and error bodies are
//! never read. Logs name the route template, never a shard id, digest, body
//! or the origin.

use bytes::Bytes;
use http::header::RETRY_AFTER;
use http_body_util::BodyExt;
use hyper::body::Body;
use std::{fmt, time::Duration};
use tokio::runtime::Handle;

use super::{routed_response, secure_endpoint_uri, RoutedHttpError, RoutedTransport};
use crate::wallet::sync_engine::transparent_details::client::{
    TxidReply, TxidRequest, TxidTransport, TxidTransportError,
};
use crate::wallet::sync_engine::{watch_for_exit, SyncError};

/// One request's bound, from dispatch through the last body byte.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// The `x-txid-map-sha256` header the map carries.
const MAP_DIGEST_HEADER: &str = "x-txid-map-sha256";

/// The txid display transport over one routed HTTPS client. One per lookup
/// batch; every request is bounded by [`REQUEST_TIMEOUT`] and stops when
/// `should_exit` does.
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

    async fn exchange(&self, request: &TxidRequest) -> Result<TxidReply, TxidTransportError> {
        let should_exit = self.route.should_exit;
        if should_exit() {
            return Err(TxidTransportError::Cancelled);
        }
        let method = request.method();
        let path = request.path();
        #[cfg(test)]
        let answer = self
            .observer
            .as_ref()
            .and_then(|observer| observer.observe(&method, &path, &request.body));
        let url = format!("{}{path}", self.origin);
        let limit = request.limit;
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
                RoutedHttpError::Cancelled => TxidTransportError::Cancelled,
                // `routed_response` returns headers of every status.
                RoutedHttpError::HttpStatus(_) | RoutedHttpError::Failed(_) => {
                    TxidTransportError::Failed
                }
            })?;
            read(response, limit).await
        };
        let received = tokio::select! {
            biased;
            _ = watch_for_exit(should_exit) => Err(TxidTransportError::Cancelled),
            received = tokio::time::timeout(REQUEST_TIMEOUT, exchange) => {
                received.unwrap_or(Err(TxidTransportError::Timeout))
            }
        };
        // Cancellation wins a tie: a stopping lookup acts on no reply that
        // raced it.
        if should_exit() {
            return Err(TxidTransportError::Cancelled);
        }
        received
    }
}

impl<F: Fn() -> bool> TxidTransport for TxidPirHttp<'_, F> {
    fn send(&mut self, request: TxidRequest) -> Result<TxidReply, TxidTransportError> {
        let received = self.handle.block_on(self.exchange(&request));
        let (method, template) = (request.method(), request.template());
        match &received {
            Ok(reply) => log::debug!(
                "txid PIR {method} {template}: HTTP {}, {} bytes",
                reply.status,
                reply.body.len()
            ),
            Err(error) => log::debug!("txid PIR {method} {template}: {}", name(*error)),
        }
        received
    }
}

fn name(error: TxidTransportError) -> &'static str {
    match error {
        TxidTransportError::Cancelled => "cancelled",
        TxidTransportError::TooLarge => "too large",
        TxidTransportError::Timeout => "timed out",
        TxidTransportError::Failed => "route failed",
    }
}

/// Reads a success up to `limit`; an error status keeps only its headers.
async fn read<B>(response: http::Response<B>, limit: usize) -> Result<TxidReply, TxidTransportError>
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
    let retry_after = header(RETRY_AFTER.as_str())
        .and_then(|value| value.trim().parse::<u64>().ok())
        .map(Duration::from_secs);
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

async fn read_limited<B>(mut body: B, limit: usize) -> Result<Vec<u8>, TxidTransportError>
where
    B: Body<Data = Bytes> + Unpin,
    B::Error: fmt::Display,
{
    let mut bytes = Vec::new();
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(|_| TxidTransportError::Failed)?;
        if let Some(data) = frame.data_ref() {
            if bytes.len() + data.len() > limit {
                return Err(TxidTransportError::TooLarge);
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
    use crate::wallet::sync_engine::transparent_details::client::{DisplayTable, Tier, TxidRoute};
    use http::Method;
    use http_body_util::Full;
    use std::sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    };
    use tokio::runtime::Runtime;

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

    fn query(limit: usize) -> TxidRequest {
        TxidRequest {
            route: TxidRoute::Query {
                tier: Tier::Archive,
                shard_id: 4,
                digest: "cd".repeat(32),
                table: DisplayTable::Directory(0),
            },
            body: vec![0xc3, 0x5a],
            limit,
        }
    }

    fn answered<'a, F: Fn() -> bool>(
        runtime: &Runtime,
        should_exit: &'a F,
        answer: impl Fn(&ObservedRequest) -> http::Response<Full<Bytes>> + Send + Sync + 'static,
    ) -> (TxidPirHttp<'a, F>, RequestObserver) {
        let observer = RequestObserver::answering(answer);
        let http = TxidPirHttp::new(ORIGIN, should_exit, runtime.handle().clone())
            .unwrap()
            .with_observer(observer.clone());
        (http, observer)
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
    fn replies_carry_status_retry_after_digest_and_bounded_bodies() {
        let runtime = runtime();
        let exit = || false;
        let (mut http, observer) = answered(&runtime, &exit, |request| {
            if request.method == Method::POST {
                reply(200, &[], &[7; 8])
            } else {
                reply(
                    503,
                    &[("retry-after", "7"), (MAP_DIGEST_HEADER, "beef")],
                    b"busy",
                )
            }
        });
        let ok = http.send(query(8)).unwrap();
        assert_eq!((ok.status, ok.body.len()), (200, 8));
        assert_eq!(
            http.send(query(7)).unwrap_err(),
            TxidTransportError::TooLarge
        );
        let refused = http
            .send(TxidRequest {
                route: TxidRoute::Map,
                body: Vec::new(),
                limit: 64,
            })
            .unwrap();
        assert_eq!(refused.status, 503);
        assert_eq!(refused.retry_after, Some(Duration::from_secs(7)));
        assert_eq!(refused.map_sha256.as_deref(), Some("beef"));
        assert!(refused.body.is_empty(), "error bodies are not read");
        let requests = observer.requests();
        assert_eq!(requests.len(), 3);
        assert_eq!(requests[0].body, vec![0xc3, 0x5a]);
        assert_eq!(requests[2].path, "/v1/txid/shards");
    }

    #[test]
    fn a_cancelled_transport_sends_nothing_and_drops_racing_replies() {
        let runtime = runtime();
        let exit = || true;
        let (mut http, observer) = answered(&runtime, &exit, |_| reply(200, &[], b""));
        assert_eq!(
            http.send(query(8)).unwrap_err(),
            TxidTransportError::Cancelled
        );
        assert!(observer.requests().is_empty());

        let cancelled = Arc::new(AtomicBool::new(false));
        let exit = {
            let cancelled = cancelled.clone();
            move || cancelled.load(Ordering::SeqCst)
        };
        let (mut http, observer) = answered(&runtime, &exit, move |_| {
            cancelled.store(true, Ordering::SeqCst);
            reply(200, &[], b"")
        });
        assert_eq!(
            http.send(query(8)).unwrap_err(),
            TxidTransportError::Cancelled
        );
        assert_eq!(observer.requests().len(), 1);
    }
}
