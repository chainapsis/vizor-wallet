//! Observes when a request has been handed to the transport.
//!
//! [`DispatchSignalService`] wraps a channel for one call. It fires its
//! [`Dispatched`] signal once hyper has consumed the whole request body, the
//! point after which the request can reach the server without any further
//! action from this process. A body dropped before its end never fires the
//! signal, so a caller waiting on it falls back to the response.

use std::{
    pin::Pin,
    sync::{Arc, Mutex, PoisonError},
    task::{Context, Poll},
};

use bytes::Bytes;
use http_body::{Body as HttpBody, Frame, SizeHint};
use tokio::sync::oneshot;
use tonic::body::Body;
use tower_service::Service;

/// Fires once when a request body has been handed to the transport.
pub(crate) struct Dispatched(Option<oneshot::Sender<()>>);

impl Dispatched {
    /// A signal and the receiver that resolves when it fires. The receiver
    /// errors if the signal is dropped without firing.
    pub(crate) fn new() -> (Self, oneshot::Receiver<()>) {
        let (sender, receiver) = oneshot::channel();
        (Self(Some(sender)), receiver)
    }

    /// A signal nobody observes.
    pub(crate) fn unobserved() -> Self {
        Self(None)
    }

    /// Fires the signal now, standing in for a transport in tests.
    #[cfg(test)]
    pub(crate) fn fire(mut self) {
        self.fire_once();
    }

    fn fire_once(&mut self) {
        if let Some(sender) = self.0.take() {
            let _ = sender.send(());
        }
    }
}

/// Wraps the first request's body so that it fires `dispatched` at its end.
/// Later requests through the same service pass through unchanged.
#[derive(Clone)]
pub(crate) struct DispatchSignalService<S> {
    inner: S,
    dispatched: Arc<Mutex<Option<Dispatched>>>,
}

impl<S> DispatchSignalService<S> {
    pub(crate) fn new(inner: S, dispatched: Dispatched) -> Self {
        Self {
            inner,
            dispatched: Arc::new(Mutex::new(Some(dispatched))),
        }
    }
}

impl<S> Service<http::Request<Body>> for DispatchSignalService<S>
where
    S: Service<http::Request<Body>>,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = S::Future;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: http::Request<Body>) -> Self::Future {
        let dispatched = self
            .dispatched
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take();
        let request = match dispatched {
            Some(dispatched) => request.map(|inner| Body::new(SignalBody { inner, dispatched })),
            None => request,
        };
        self.inner.call(request)
    }
}

struct SignalBody {
    inner: Body,
    dispatched: Dispatched,
}

impl HttpBody for SignalBody {
    type Data = Bytes;
    type Error = tonic::Status;

    fn poll_frame(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        let frame = Pin::new(&mut self.inner).poll_frame(cx);
        match &frame {
            // The transport stops polling a body that reports its end, so the
            // last frame may be the final poll.
            Poll::Ready(Some(Ok(_))) if self.inner.is_end_stream() => self.dispatched.fire_once(),
            Poll::Ready(None) => self.dispatched.fire_once(),
            _ => {}
        }
        frame
    }

    fn is_end_stream(&self) -> bool {
        self.inner.is_end_stream()
    }

    fn size_hint(&self) -> SizeHint {
        self.inner.size_hint()
    }
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;

    use futures::future::{ready, Ready};
    use http_body_util::BodyExt;

    use super::*;

    /// Returns the request it receives, so the test plays hyper's part and
    /// decides how much of the body to consume.
    struct Transport;

    impl Service<http::Request<Body>> for Transport {
        type Response = http::Request<Body>;
        type Error = Infallible;
        type Future = Ready<Result<Self::Response, Infallible>>;

        fn poll_ready(&mut self, _: &mut Context<'_>) -> Poll<Result<(), Infallible>> {
            Poll::Ready(Ok(()))
        }

        fn call(&mut self, request: http::Request<Body>) -> Self::Future {
            ready(Ok(request))
        }
    }

    fn request(chunks: &'static [&'static [u8]]) -> http::Request<Body> {
        let frames = futures::stream::iter(
            chunks
                .iter()
                .map(|chunk| Ok::<_, tonic::Status>(Frame::data(Bytes::from_static(chunk)))),
        );
        http::Request::new(Body::new(http_body_util::StreamBody::new(frames)))
    }

    #[tokio::test]
    async fn fires_only_after_the_whole_body_is_consumed() {
        let (dispatched, mut fired) = Dispatched::new();
        let mut service = DispatchSignalService::new(Transport, dispatched);
        let mut body = service
            .call(request(&[b"first", b"second"]))
            .await
            .unwrap()
            .into_body();
        body.frame().await.unwrap().unwrap();
        assert!(fired.try_recv().is_err(), "fired before the body ended");
        while body.frame().await.is_some() {}
        fired.try_recv().unwrap();
    }

    #[tokio::test]
    async fn a_body_dropped_before_its_end_never_fires() {
        let (dispatched, fired) = Dispatched::new();
        let mut service = DispatchSignalService::new(Transport, dispatched);
        let mut body = service
            .call(request(&[b"first", b"second"]))
            .await
            .unwrap()
            .into_body();
        body.frame().await.unwrap().unwrap();
        drop(body);
        assert!(fired.await.is_err());
    }

    #[tokio::test]
    async fn only_the_first_request_carries_the_signal() {
        let (dispatched, mut fired) = Dispatched::new();
        let mut service = DispatchSignalService::new(Transport, dispatched);
        let first = service.call(request(&[b"one"])).await.unwrap();
        let second = service.call(request(&[b"two"])).await.unwrap();
        second.into_body().collect().await.unwrap();
        assert!(
            fired.try_recv().is_err(),
            "a later request fired the signal"
        );
        first.into_body().collect().await.unwrap();
        fired.try_recv().unwrap();
    }
}
