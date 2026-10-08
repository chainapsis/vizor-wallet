//! Status-PIR adapter with its shorter deadline and conflict semantics.

use http::Method;
use std::{
    sync::atomic::{AtomicBool, Ordering},
    time::Duration,
};

use super::{collect_bytes, routed_response, RoutedHttpError, RoutedTransport};
use crate::wallet::sync_engine::SyncError;

const STATUS_REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

/// Status-specific adapter state layered over the protocol-neutral HTTP route.
pub(crate) struct StatusPirTransport<'a, F> {
    route: RoutedTransport<'a, F>,
    session_conflict: AtomicBool,
}

impl<'a, F> StatusPirTransport<'a, F> {
    pub(crate) fn new(should_exit: &'a F) -> Self {
        Self {
            route: RoutedTransport::new(should_exit),
            session_conflict: AtomicBool::new(false),
        }
    }

    pub(crate) fn new_direct(should_exit: &'a F) -> Self {
        Self {
            route: RoutedTransport::new_direct(should_exit),
            session_conflict: AtomicBool::new(false),
        }
    }

    /// Returns and clears a session conflict (see `RoutedHttpError::is_session_conflict`)
    /// observed by the status adapter.
    ///
    /// The upstream status transport error vocabulary collapses HTTP failures
    /// to `Unavailable`; this adapter-local marker preserves only the typed
    /// distinction needed for one session refresh.
    pub(in crate::wallet::sync_engine) fn take_status_session_conflict(&self) -> bool {
        self.session_conflict.swap(false, Ordering::SeqCst)
    }
}

impl<F: Fn() -> bool + Sync> zakura_pir_status::transport::Transport for StatusPirTransport<'_, F> {
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

impl<F: Fn() -> bool> StatusPirTransport<'_, F> {
    async fn status_request(
        &self,
        method: Method,
        url: &str,
        body: Vec<u8>,
        max_bytes: usize,
    ) -> Result<Vec<u8>, zakura_pir_status::Error> {
        use zakura_pir_status::Error;

        self.session_conflict.store(false, Ordering::SeqCst);
        let request = async {
            let response = routed_response(
                method,
                url,
                body,
                self.route.should_exit,
                &self.route.direct,
                self.route.route_policy,
            )
            .await
            .map_err(|_| Error::Unavailable)?;
            collect_bytes(response, max_bytes)
                .await
                .map_err(|error| match error {
                    RoutedHttpError::Failed(SyncError::Parse(_)) => Error::Malformed,
                    error => {
                        if error.is_session_conflict() {
                            self.session_conflict.store(true, Ordering::SeqCst);
                        }
                        Error::Unavailable
                    }
                })
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
