//! Enhance-PIR protocol adapter.

use http::Method;
use zakura_pir_enhance::{
    transport::{self, Transport},
    ClientError,
};

use crate::wallet::sync_engine::SyncError;

use super::{routed_request, RoutedTransport};
use crate::wallet::sync_engine::enhancement::payload::private_pir::client_transport_error;

impl<F: Fn() -> bool> Transport for RoutedTransport<'_, F> {
    async fn execute(
        &self,
        request: transport::Request,
    ) -> Result<transport::ResponseBody, ClientError> {
        let response_body = request.response_body();
        let response = routed_request(
            match request.method {
                transport::Method::Get => Method::GET,
                transport::Method::Post => Method::POST,
            },
            &request.url,
            request.body,
            response_body,
            self.should_exit,
            &self.direct,
        )
        .await;
        if (self.should_exit)() {
            return Err(ClientError::Cancelled);
        }
        response.map_err(client_transport_error)
    }
}

pub(in crate::wallet::sync_engine::enhancement) fn client_protocol_error(
    error: ClientError,
) -> SyncError {
    SyncError::parse(format!("Enhance PIR: {error}"))
}
