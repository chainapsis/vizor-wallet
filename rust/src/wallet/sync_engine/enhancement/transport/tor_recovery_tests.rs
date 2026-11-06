use std::io;

use zcash_client_backend::tor::http::{HttpError, TimeoutPhase};

use super::{stream_open_recovery, StatusCode, TorError};

#[test]
fn http_statuses_and_ambiguous_transport_failures_never_recover() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::begin_tor_enable();
    assert!(crate::network_privacy::is_tor_desired());
    for status in [
        StatusCode::OK,
        StatusCode::FOUND,
        StatusCode::UNAUTHORIZED,
        StatusCode::TOO_MANY_REQUESTS,
        StatusCode::SERVICE_UNAVAILABLE,
    ] {
        assert!(stream_open_recovery(Ok(status), &|| false).is_none());
    }
    let errors = [
        TorError::Http(HttpError::Tls(io::Error::new(
            io::ErrorKind::NotFound,
            "TLS is not a pre-HTTP DNS failure",
        ))),
        TorError::Http(HttpError::Timeout(TimeoutPhase::Connect)),
        TorError::Http(HttpError::Timeout(TimeoutPhase::Request)),
        TorError::Http(HttpError::Timeout(TimeoutPhase::ResponseBody)),
        TorError::Io(io::Error::new(io::ErrorKind::NotFound, "unrelated IO")),
        TorError::Io(io::Error::new(
            io::ErrorKind::TimedOut,
            "unrelated IO timeout",
        )),
        TorError::MissingTorDirectory,
    ];
    for error in &errors {
        assert!(stream_open_recovery(Err(error), &|| false).is_none());
    }
}
