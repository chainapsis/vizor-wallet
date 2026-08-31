//! Transport seam for helper-server HTTP requests.
//!
//! Helper share submission and status polling are the only outbound requests
//! this crate makes to vote helper servers. Like PIR and tree sync, the actual
//! socket work belongs to the host wallet: it already owns the network route
//! (a direct connection, a proxy, a pool, or Tor), and a crate-owned client
//! would silently override that choice.
//!
//! Hosts that want plain HTTPS with no extra work can use the bundled
//! [`HyperTransport`](crate::HyperTransport), which implements this trait.
//! Hosts with a custom Hyper connector can inject it through
//! [`HyperTransport::with_http_connector`](crate::HyperTransport::with_http_connector)
//! and keep the SDK's request, timeout, body-limit, and error-classification
//! behavior. Hosts using a non-Hyper HTTP stack, such as an application-owned
//! Tor client, implement [`HelperTransport`] on their own client and pass it
//! in; nothing in this module chooses a network route.
//!
//! # Why this is not [`crate::Transport`]
//!
//! The PIR transport takes no timeout and reports every failure the same way.
//! Helper retry rules depend on both: a share POST that times out **may have
//! been accepted**, so it must never be retried against the same helper, while
//! a refused connection is safe to retry. [`HelperTransportError`] preserves
//! that distinction for higher-level helper clients.

use std::{future::Future, pin::Pin, time::Duration};

/// Largest helper response body any transport should accept.
///
/// Helper payloads are small JSON documents, so this bounds what a hostile or
/// broken helper can make a wallet allocate. It is a property of the helper
/// protocol rather than of any one host, so implementors of [`HelperTransport`]
/// should enforce *this* value instead of choosing their own.
pub const MAX_HELPER_RESPONSE_BYTES: usize = 256 * 1024;

/// Failure of a single helper request attempt.
///
/// The split exists so callers can tell an *ambiguous* outcome from a
/// *definite* one. Only [`HelperTransportError::Transport`] is safe to retry
/// against the same helper for a non-idempotent request.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HelperTransportError {
    /// The deadline passed with no response.
    ///
    /// The request may still have reached the helper and been accepted. Treat
    /// this as ambiguous: never retry a submission on the same helper after it.
    Timeout,
    /// The request was dispatched, but no response headers were received.
    ///
    /// The helper may already have accepted a submission before the connection
    /// failed. Treat this as ambiguous and never retry a submission against
    /// the same helper.
    Ambiguous(String),
    /// Response headers arrived, but the complete response body could not be
    /// read.
    ///
    /// The helper may already have accepted a submission. Treat this as
    /// ambiguous in the same way as a timeout.
    Response(String),
    /// The request definitively failed before a response was produced (DNS,
    /// connect, TLS, or a host-imposed route block).
    Transport(String),
}

impl std::fmt::Display for HelperTransportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Timeout => write!(f, "helper request timed out"),
            Self::Ambiguous(message) => {
                write!(f, "helper request outcome is unknown: {message}")
            }
            Self::Response(message) => {
                write!(f, "helper response failed after headers arrived: {message}")
            }
            Self::Transport(message) => write!(f, "helper request failed: {message}"),
        }
    }
}

impl std::error::Error for HelperTransportError {}

/// One helper HTTP response.
///
/// `status` is reported as-is; the client layer decides which codes are
/// retryable, so a transport must not turn a 5xx into an error.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HelperResponse {
    status: u16,
    body: Vec<u8>,
    content_type: Option<String>,
}

impl HelperResponse {
    /// Builds a response with explicit HTTP metadata.
    ///
    /// Higher-level clients validate the body limit and require JSON content
    /// for protocol responses. Keeping construction here prevents callers
    /// from accidentally omitting metadata when adapting another HTTP stack.
    pub fn new(status: u16, body: Vec<u8>, content_type: Option<String>) -> Self {
        Self {
            status,
            body,
            content_type,
        }
    }

    /// Builds an `application/json` response.
    pub fn json(status: u16, body: Vec<u8>) -> Self {
        Self::new(status, body, Some("application/json".to_string()))
    }

    /// Returns the HTTP status code.
    pub fn status(&self) -> u16 {
        self.status
    }

    /// Returns the complete response body.
    pub fn body(&self) -> &[u8] {
        &self.body
    }

    /// Returns the response content type, when supplied by the transport.
    pub fn content_type(&self) -> Option<&str> {
        self.content_type.as_deref()
    }

    /// Returns true for a 2xx status.
    pub fn is_success(&self) -> bool {
        (200..300).contains(&self.status)
    }

    /// Returns the attacker-controlled body as UTF-8, replacing invalid
    /// sequences lossily.
    ///
    /// Callers must not place this text in logs, telemetry, or crash reports
    /// without strict escaping, truncation, and an explicit privacy review.
    pub fn body_text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }
}

/// Boxed future returned by [`HelperTransport`] methods.
pub type HelperFuture<'a> =
    Pin<Box<dyn Future<Output = Result<HelperResponse, HelperTransportError>> + Send + 'a>>;

/// Host-owned HTTP transport for helper-server requests.
///
/// Implementations must honor `timeout` for the *complete* request including
/// connection setup and body read, and must bound the response body so a
/// hostile helper cannot force an unbounded allocation.
///
/// An implementation that routes over Tor must fail with
/// [`HelperTransportError::Transport`] rather than falling back to a direct
/// connection when the route is unavailable: leaking a voting request onto the
/// clearnet is worse than failing the request.
pub trait HelperTransport: Send + Sync {
    /// Performs a GET request.
    fn get<'a>(&'a self, url: &'a str, timeout: Duration) -> HelperFuture<'a>;

    /// Performs a POST request with a JSON body.
    ///
    /// Implementations are responsible for setting `Content-Type:
    /// application/json`.
    fn post_json<'a>(&'a self, url: &'a str, body: Vec<u8>, timeout: Duration) -> HelperFuture<'a>;
}

impl<T: HelperTransport + ?Sized> HelperTransport for std::sync::Arc<T> {
    fn get<'a>(&'a self, url: &'a str, timeout: Duration) -> HelperFuture<'a> {
        (**self).get(url, timeout)
    }

    fn post_json<'a>(&'a self, url: &'a str, body: Vec<u8>, timeout: Duration) -> HelperFuture<'a> {
        (**self).post_json(url, body, timeout)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn success_range_matches_http_semantics() {
        for status in [200u16, 201, 204, 299] {
            assert!(HelperResponse::json(status, Vec::new()).is_success());
        }
        for status in [199u16, 300, 404, 500] {
            assert!(!HelperResponse::json(status, Vec::new()).is_success());
        }
    }

    #[test]
    fn body_text_replaces_invalid_utf8() {
        let response = HelperResponse::json(200, vec![0xff, 0xfe]);
        assert_eq!(response.body_text(), "��");
    }
}
