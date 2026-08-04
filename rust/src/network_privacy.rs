//! Process-wide network privacy policy.
//!
//! The desired route is changed before Tor bootstrapping begins. Every
//! policy-aware network client therefore fails closed while Tor is starting or
//! after bootstrap failure instead of silently using a direct connection.

use std::{
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicU8, Ordering},
        OnceLock, RwLock,
    },
    time::Duration,
};

use zcash_client_backend::tor::{Client as TorClient, Timeouts as TorTimeouts};

const STATUS_DIRECT: u8 = 0;
const STATUS_BOOTSTRAPPING: u8 = 1;
const STATUS_READY: u8 = 2;
const STATUS_FAILED: u8 = 3;

static TOR_DESIRED: AtomicBool = AtomicBool::new(false);
static TOR_STATUS: AtomicU8 = AtomicU8::new(STATUS_DIRECT);
static TOR_CLIENT: OnceLock<RwLock<Option<TorClient>>> = OnceLock::new();
static TOR_INIT_LOCK: OnceLock<tokio::sync::Mutex<()>> = OnceLock::new();

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NetworkPrivacyStatus {
    Direct,
    Bootstrapping,
    Ready,
    Failed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RouteDecision {
    Direct,
    TorShared,
    TorIsolated,
}

fn client_slot() -> &'static RwLock<Option<TorClient>> {
    TOR_CLIENT.get_or_init(|| RwLock::new(None))
}

fn init_lock() -> &'static tokio::sync::Mutex<()> {
    TOR_INIT_LOCK.get_or_init(|| tokio::sync::Mutex::new(()))
}

pub fn is_tor_desired() -> bool {
    TOR_DESIRED.load(Ordering::Acquire)
}

pub fn status() -> NetworkPrivacyStatus {
    match TOR_STATUS.load(Ordering::Acquire) {
        STATUS_BOOTSTRAPPING => NetworkPrivacyStatus::Bootstrapping,
        STATUS_READY => NetworkPrivacyStatus::Ready,
        STATUS_FAILED => NetworkPrivacyStatus::Failed,
        _ => NetworkPrivacyStatus::Direct,
    }
}

/// Immediately changes the process policy to fail-closed Tor mode without
/// waiting for the previous transport to stop or for Tor to bootstrap.
/// Runtime toggles call this synchronously before their first `await`, so no
/// new policy-aware request can race onto clearnet during teardown.
pub fn begin_tor_enable() {
    TOR_DESIRED.store(true, Ordering::Release);
    TOR_STATUS.store(STATUS_BOOTSTRAPPING, Ordering::Release);
    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
    log::info!("network privacy: Tor requested; direct requests blocked");
}

pub async fn enable_tor(tor_directory: &Path) -> Result<NetworkPrivacyStatus, String> {
    TOR_DESIRED.store(true, Ordering::Release);

    let _init_guard = init_lock().lock().await;
    if !is_tor_desired() {
        return Ok(NetworkPrivacyStatus::Direct);
    }
    if status() == NetworkPrivacyStatus::Ready
        && client_slot()
            .read()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .is_some()
    {
        return Ok(NetworkPrivacyStatus::Ready);
    }
    TOR_STATUS.store(STATUS_BOOTSTRAPPING, Ordering::Release);

    if let Err(error) = tokio::fs::create_dir_all(tor_directory).await {
        set_tor_failed();
        return Err(format!("Create Tor data directory: {error}"));
    }

    // Sapling proving parameters are tens of megabytes and routinely take
    // longer than the backend's one-minute HTTP body default over Tor. Keep
    // connect/header deadlines strict, but allow streaming bodies enough time
    // to complete without holding them in memory.
    let timeouts = TorTimeouts::default().with_response_body(Duration::from_secs(15 * 60));
    let client = match TorClient::create_with_timeouts(tor_directory, |_| {}, timeouts).await {
        Ok(client) => client,
        Err(error) => {
            set_tor_failed();
            return Err(format!("Bootstrap Tor: {error}"));
        }
    };

    if !is_tor_desired() {
        return Ok(NetworkPrivacyStatus::Direct);
    }

    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(client);
    TOR_STATUS.store(STATUS_READY, Ordering::Release);
    log::info!("network privacy: Tor is ready");
    Ok(NetworkPrivacyStatus::Ready)
}

pub fn disable_tor() {
    TOR_DESIRED.store(false, Ordering::Release);
    TOR_STATUS.store(STATUS_DIRECT, Ordering::Release);
    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
    log::info!("network privacy: direct route enabled");
}

fn set_tor_failed() {
    *client_slot()
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner()) = None;
    if is_tor_desired() {
        TOR_STATUS.store(STATUS_FAILED, Ordering::Release);
    }
}

fn route_decision(
    tor_desired: bool,
    tor_status: NetworkPrivacyStatus,
    has_client: bool,
    isolated: bool,
) -> Result<RouteDecision, &'static str> {
    if !tor_desired {
        return Ok(RouteDecision::Direct);
    }
    if tor_status != NetworkPrivacyStatus::Ready || !has_client {
        return Err(match tor_status {
            NetworkPrivacyStatus::Bootstrapping => "Tor is still connecting",
            NetworkPrivacyStatus::Failed => "Tor connection failed",
            _ => "Tor is enabled but unavailable",
        });
    }
    Ok(if isolated {
        RouteDecision::TorIsolated
    } else {
        RouteDecision::TorShared
    })
}

pub(crate) fn tor_client_for_route(isolated: bool) -> Result<Option<TorClient>, String> {
    let client = client_slot()
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone();
    match route_decision(is_tor_desired(), status(), client.is_some(), isolated) {
        Ok(RouteDecision::Direct) => Ok(None),
        Ok(RouteDecision::TorShared) => Ok(client),
        Ok(RouteDecision::TorIsolated) => Ok(client.map(|client| client.isolated_client())),
        Err(error) => Err(error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::{route_decision, NetworkPrivacyStatus, RouteDecision};

    #[test]
    fn direct_route_does_not_require_a_tor_client() {
        assert_eq!(
            route_decision(false, NetworkPrivacyStatus::Direct, false, false),
            Ok(RouteDecision::Direct)
        );
    }

    #[test]
    fn tor_bootstrap_and_failure_are_fail_closed() {
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Bootstrapping, false, false),
            Err("Tor is still connecting")
        );
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Failed, false, false),
            Err("Tor connection failed")
        );
    }

    #[test]
    fn ready_tor_selects_shared_or_isolated_routes() {
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Ready, true, false),
            Ok(RouteDecision::TorShared)
        );
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Ready, true, true),
            Ok(RouteDecision::TorIsolated)
        );
    }

    #[test]
    fn ready_status_without_a_client_is_still_fail_closed() {
        assert_eq!(
            route_decision(true, NetworkPrivacyStatus::Ready, false, false),
            Err("Tor is enabled but unavailable")
        );
    }
}
