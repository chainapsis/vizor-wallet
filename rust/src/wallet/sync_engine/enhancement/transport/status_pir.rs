//! Status-PIR adapter with its shorter deadline and conflict semantics.

use http::Method;
use http_body_util::BodyExt;
use std::{
    sync::atomic::{AtomicBool, AtomicU16, Ordering},
    time::Duration,
};

use super::{routed_response, RoutedTransport};

const STATUS_REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

/// Status-specific adapter state layered over the protocol-neutral HTTP route.
pub(crate) struct StatusPirTransport<'a, F> {
    route: RoutedTransport<'a, F>,
    session_error: AtomicU16,
    /// A complete query envelope matched the request; only then can the
    /// client's malformed result describe decrypted row contents.
    query_reply: AtomicBool,
}

impl<'a, F> StatusPirTransport<'a, F> {
    pub(crate) fn new(should_exit: &'a F) -> Self {
        Self {
            route: RoutedTransport::new(should_exit),
            session_error: AtomicU16::new(0),
            query_reply: AtomicBool::new(false),
        }
    }

    /// Returns and clears whether the last query received a complete body
    /// bound to its request. Setup reads and failed envelopes do not qualify.
    /// The status source uses this to distinguish row errors from failures
    /// before any readable row arrived.
    pub(in crate::wallet::sync_engine) fn take_status_query_reply(&self) -> bool {
        self.query_reply.swap(false, Ordering::SeqCst)
    }

    /// Returns and clears a 409/410 observed by the status adapter.
    ///
    /// The upstream status transport error vocabulary collapses HTTP failures
    /// to `Unavailable`; this adapter-local marker preserves only the typed
    /// distinction needed for one session refresh.
    pub(in crate::wallet::sync_engine) fn take_status_session_conflict(&self) -> bool {
        matches!(self.session_error.swap(0, Ordering::SeqCst), 409 | 410)
    }
}

impl<F: Fn() -> bool + Sync> zakura_pir_client::status::transport::Transport
    for StatusPirTransport<'_, F>
{
    async fn get(
        &self,
        url: &str,
        max_bytes: usize,
    ) -> Result<Vec<u8>, zakura_pir_client::status::Error> {
        self.status_request(Method::GET, url, Vec::new(), max_bytes)
            .await
    }

    async fn post(
        &self,
        url: &str,
        body: Vec<u8>,
        max_bytes: usize,
    ) -> Result<Vec<u8>, zakura_pir_client::status::Error> {
        self.status_request(Method::POST, url, body, max_bytes)
            .await
    }
}

impl<F: Fn() -> bool> StatusPirTransport<'_, F> {
    async fn status_request(
        &self,
        method: Method,
        url: &str,
        body: Vec<u8>,
        max_bytes: usize,
    ) -> Result<Vec<u8>, zakura_pir_client::status::Error> {
        use zakura_pir_client::status::Error;

        self.session_error.store(0, Ordering::SeqCst);
        self.query_reply.store(false, Ordering::SeqCst);
        let query_header = if method == Method::POST {
            Some(
                body.get(..zakura_pir_client::status::HEADER_BYTES)
                    .ok_or(Error::Unavailable)?
                    .to_vec(),
            )
        } else {
            None
        };
        let request = async {
            let response = routed_response(
                method,
                url,
                body,
                self.route.should_exit,
                &self.route.direct,
            )
            .await
            .map_err(|_| Error::Unavailable)?;
            match response.status().as_u16() {
                status @ (409 | 410) => {
                    self.session_error.store(status, Ordering::SeqCst);
                    return Err(Error::Unavailable);
                }
                _ if !response.status().is_success() => return Err(Error::Unavailable),
                _ => {}
            }

            let bytes = read_status_body(response.into_body(), max_bytes).await?;
            if let Some(header) = query_header {
                if !query_reply_matches(&header, &bytes, max_bytes) {
                    return Err(Error::Unavailable);
                }
                self.query_reply.store(true, Ordering::SeqCst);
            }
            Ok(bytes)
        };

        tokio::select! {
            biased;
            _ = crate::wallet::sync_engine::watch_for_exit(self.route.should_exit) => {
                Err(Error::Cancelled)
            },
            result = tokio::time::timeout(STATUS_REQUEST_TIMEOUT, request) => {
                result.map_err(|_| Error::Timeout)?
            }
        }
    }
}

/// Collects a bounded HTTP body. A size refusal is an envelope failure,
/// before the private client can read any decrypted row.
async fn read_status_body<B>(
    mut incoming: B,
    max_bytes: usize,
) -> Result<Vec<u8>, zakura_pir_client::status::Error>
where
    B: hyper::body::Body<Data = bytes::Bytes> + Unpin,
{
    use zakura_pir_client::status::Error;
    let mut bytes = Vec::new();
    while let Some(frame) = incoming.frame().await {
        let frame = frame.map_err(|_| Error::Unavailable)?;
        if let Some(data) = frame.data_ref() {
            if data.len() > max_bytes.saturating_sub(bytes.len()) {
                return Err(Error::Unavailable);
            }
            bytes.extend_from_slice(data);
        }
    }
    Ok(bytes)
}

fn query_reply_matches(header: &[u8], bytes: &[u8], expected_bytes: usize) -> bool {
    bytes.len() == expected_bytes && bytes.get(..header.len()) == Some(header)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bytes::Bytes;
    use http_body_util::Full;
    use zakura_pir_client::status::{Error, HEADER_BYTES};

    #[tokio::test]
    async fn status_session_failures_in_oversized_response_bodies_are_retryable() {
        assert_eq!(
            read_status_body(Full::new(Bytes::from_static(&[0; 6])), 5).await,
            Err(Error::Unavailable)
        );
        assert_eq!(
            read_status_body(Full::new(Bytes::from_static(&[0; 5])), 5).await,
            Ok(vec![0; 5])
        );
    }

    #[test]
    fn only_a_complete_bound_response_qualifies_as_a_row_reply() {
        let header = vec![7; HEADER_BYTES];
        let valid = vec![7; HEADER_BYTES + 8];
        assert!(query_reply_matches(&header, &valid, valid.len()));
        assert!(!query_reply_matches(
            &header,
            &valid[..valid.len() - 1],
            valid.len()
        ));
        assert!(!query_reply_matches(
            &header,
            &vec![7; valid.len() + 1],
            valid.len()
        ));
        let mut wrong_binding = valid.clone();
        wrong_binding[0] ^= 1;
        assert!(!query_reply_matches(&header, &wrong_binding, valid.len()));
        assert!(!query_reply_matches(&header, &[], valid.len()));
    }
}
