//! Public transaction-status source construction.

use tonic::transport::Channel;
use zakura_transaction_status::{
    StatusError, StatusObservation, StatusRequest, StatusSession, StatusSource,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;

use crate::wallet::sync_engine::TransparentLookupGate;

pub(crate) fn lightwalletd_source<'a, F>(
    client: CompactTxStreamerClient<Channel>,
    gate: TransparentLookupGate,
    should_exit: &'a F,
) -> impl StatusSource + 'a
where
    F: Fn() -> bool + Sync + 'a,
{
    Lightwalletd {
        client,
        gate,
        should_exit,
    }
}

struct Lightwalletd<'a, F> {
    client: CompactTxStreamerClient<Channel>,
    gate: TransparentLookupGate,
    should_exit: &'a F,
}

impl<F: Fn() -> bool + Sync> StatusSource for Lightwalletd<'_, F> {
    type Session = Self;

    async fn open(self) -> Result<Self::Session, StatusError> {
        if (self.should_exit)() {
            Err(StatusError::Cancelled)
        } else {
            Ok(self)
        }
    }
}

impl<F: Fn() -> bool + Sync> StatusSession for Lightwalletd<'_, F> {
    async fn observe(&mut self, request: StatusRequest) -> Result<StatusObservation, StatusError> {
        map_gate(
            self.gate
                .observe_status(&mut self.client, request, self.should_exit)
                .await,
        )
    }
}

fn map_gate(
    result: Result<
        Option<Result<StatusObservation, StatusError>>,
        crate::wallet::sync_engine::SyncError,
    >,
) -> Result<StatusObservation, StatusError> {
    match result {
        Ok(Some(observation)) => observation,
        Ok(None) => Err(StatusError::Cancelled),
        Err(error) => {
            log::warn!("public status withheld; policy check failed: {error}");
            Err(StatusError::LocalStorage)
        }
    }
}

/// Wraps a public source so `gate` authorizes each observation, since every
/// one sends a txid. A withheld observation reports `Cancelled`, which the
/// status lane resolves against the gate; a policy read failure reports
/// `LocalStorage`.
#[cfg(test)]
pub(crate) fn gated<S: StatusSource>(inner: S, gate: TransparentLookupGate) -> impl StatusSource {
    GatedSource { inner, gate }
}

#[cfg(test)]
struct GatedSource<S> {
    inner: S,
    gate: TransparentLookupGate,
}

#[cfg(test)]
struct GatedSession<T> {
    inner: T,
    gate: TransparentLookupGate,
}

#[cfg(test)]
impl<S: StatusSource> StatusSource for GatedSource<S> {
    type Session = GatedSession<S::Session>;

    async fn open(self) -> Result<Self::Session, StatusError> {
        Ok(GatedSession {
            inner: self.inner.open().await?,
            gate: self.gate,
        })
    }
}

#[cfg(test)]
impl<T: StatusSession> StatusSession for GatedSession<T> {
    async fn observe(&mut self, request: StatusRequest) -> Result<StatusObservation, StatusError> {
        map_gate(self.gate.dispatch(self.inner.observe(request)).await)
    }
}
