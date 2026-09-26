//! Status-PIR adapter with its shorter deadline and conflict semantics.

use http::Method;
use http_body_util::BodyExt;
use std::{sync::atomic::Ordering, time::Duration};

use super::{routed_response, RoutedTransport};

const STATUS_REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

impl<F> RoutedTransport<'_, F> {
    /// Returns and clears a 409/410 observed by the status adapter.
    ///
    /// The upstream status transport error vocabulary collapses HTTP failures
    /// to `Unavailable`; this adapter-local marker preserves only the typed
    /// distinction needed for one session refresh.
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
                self.route_policy,
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
            _ = crate::wallet::sync_engine::watch_for_exit(self.should_exit) => {
                Err(Error::Cancelled)
            },
            result = tokio::time::timeout(STATUS_REQUEST_TIMEOUT, request) => {
                result.map_err(|_| Error::Timeout)?
            }
        }
    }
}
