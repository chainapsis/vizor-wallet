//! Public transaction-status source construction.

use std::future::{ready, Ready};

use tonic::transport::Channel;
use zakura_transaction_status::{
    lightwalletd::LightwalletdSource, StatusError, StatusObservation, StatusRequest, StatusSession,
    StatusSource,
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
    gated(
        LightwalletdSource::new(
            move || -> Ready<Result<CompactTxStreamerClient<Channel>, StatusError>> {
                ready(Ok(client))
            },
            should_exit,
        ),
        gate,
    )
}

/// Wraps a public source so `gate` authorizes each observation, since every
/// one sends a txid. A withheld observation reports `Cancelled`, which the
/// status lane resolves against the gate; a policy read failure reports
/// `LocalStorage`.
pub(crate) fn gated<S: StatusSource>(inner: S, gate: TransparentLookupGate) -> impl StatusSource {
    GatedSource { inner, gate }
}

struct GatedSource<S> {
    inner: S,
    gate: TransparentLookupGate,
}

struct GatedSession<T> {
    inner: T,
    gate: TransparentLookupGate,
}

impl<S: StatusSource> StatusSource for GatedSource<S> {
    type Session = GatedSession<S::Session>;

    async fn open(self) -> Result<Self::Session, StatusError> {
        Ok(GatedSession {
            inner: self.inner.open().await?,
            gate: self.gate,
        })
    }
}

impl<T: StatusSession> StatusSession for GatedSession<T> {
    async fn observe(&mut self, request: StatusRequest) -> Result<StatusObservation, StatusError> {
        match self.gate.dispatch(self.inner.observe(request)).await {
            Ok(Some(observation)) => observation,
            Ok(None) => Err(StatusError::Cancelled),
            Err(error) => {
                log::warn!("public status withheld; policy check failed: {error}");
                Err(StatusError::LocalStorage)
            }
        }
    }
}
