//! Protocol-neutral cancellation for request futures.

use tonic::Status;

use crate::wallet::sync_engine::{watch_for_exit, SyncError};

/// Checks cancellation before dispatch, while awaiting, and after completion.
///
/// Dropping the request future interrupts an in-flight wait. Once cancellation
/// wins, no queued request is allowed to survive into the next dispatch.
pub(in crate::wallet::sync_engine::enhancement) async fn cancelable<T, E: CancelError>(
    request: impl std::future::Future<Output = Result<T, E>>,
    should_exit: &impl Fn() -> bool,
) -> Result<T, E> {
    if should_exit() {
        return Err(E::cancelled());
    }
    let result = tokio::select! {
        biased;
        _ = watch_for_exit(should_exit) => return Err(E::cancelled()),
        result = request => result,
    };
    if should_exit() {
        return Err(E::cancelled());
    }
    result
}

pub(in crate::wallet::sync_engine::enhancement) trait CancelError {
    fn cancelled() -> Self;
}

impl CancelError for SyncError {
    fn cancelled() -> Self {
        Self::other("enhancement cancelled")
    }
}

impl CancelError for Status {
    fn cancelled() -> Self {
        Self::cancelled("enhancement cancelled")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

    #[tokio::test]
    async fn cancellation_prevents_the_next_dispatch() {
        let cancelled = AtomicBool::new(false);
        let dispatched = AtomicUsize::new(0);
        let exit = || cancelled.load(Ordering::SeqCst);

        let first = cancelable(
            async {
                dispatched.fetch_add(1, Ordering::SeqCst);
                cancelled.store(true, Ordering::SeqCst);
                Ok::<_, SyncError>(())
            },
            &exit,
        )
        .await;
        assert!(first.is_err());

        let second = cancelable(
            async {
                dispatched.fetch_add(1, Ordering::SeqCst);
                Ok::<_, SyncError>(())
            },
            &exit,
        )
        .await;
        assert!(second.is_err());
        assert_eq!(dispatched.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn cancellation_drops_a_waiting_request() {
        let cancelled = AtomicBool::new(false);
        let exit = || cancelled.load(Ordering::SeqCst);
        let request = cancelable(std::future::pending::<Result<(), SyncError>>(), &exit);
        let cancel = async {
            tokio::task::yield_now().await;
            cancelled.store(true, Ordering::SeqCst);
        };
        let (result, _) = tokio::join!(request, cancel);
        assert!(result.is_err());
    }
}
