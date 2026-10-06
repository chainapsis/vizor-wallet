//! Advisory payload-recovery diagnostics and refresh throttling.
//!
//! This process-global state is for UI reporting and request pacing only. It is
//! never authoritative for durable routing, persistence, or privacy decisions.

use std::time::{Duration, Instant};

const ROUTING_REFRESH_INTERVAL: Duration = Duration::from_secs(60);

#[derive(Clone, Copy, Default)]
pub(super) enum RecoveryPhase {
    #[default]
    Idle,
    WaitingForScanning,
    WaitingForSnapshot,
    Recovering,
    RetryingLater,
}

impl RecoveryPhase {
    fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "",
            Self::WaitingForScanning => "waiting_for_scanning",
            Self::WaitingForSnapshot => "waiting_for_snapshot",
            Self::Recovering => "recovering",
            Self::RetryingLater => "retrying_later",
        }
    }
}

#[derive(Default)]
struct ServiceState {
    wallet_db_path: String,
    phase: RecoveryPhase,
    last_routing_refresh: Option<Instant>,
}

static SERVICE: std::sync::Mutex<Option<ServiceState>> = std::sync::Mutex::new(None);

pub(in crate::wallet::sync_engine) fn begin_session(wallet_db_path: &str) {
    let mut state = SERVICE.lock().unwrap_or_else(|error| error.into_inner());
    if state
        .as_ref()
        .is_none_or(|state| state.wallet_db_path != wallet_db_path)
    {
        *state = Some(ServiceState {
            wallet_db_path: wallet_db_path.into(),
            ..Default::default()
        });
    }
    state.as_mut().expect("initialized above").phase = RecoveryPhase::Idle;
}

pub(super) fn set_phase(wallet_db_path: &str, phase: RecoveryPhase) {
    let mut state = SERVICE.lock().unwrap_or_else(|error| error.into_inner());
    if let Some(state) = state
        .as_mut()
        .filter(|state| state.wallet_db_path == wallet_db_path)
    {
        state.phase = phase;
    }
}

pub(super) fn routing_refresh_due(wallet_db_path: &str) -> bool {
    SERVICE
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .as_ref()
        .filter(|state| state.wallet_db_path == wallet_db_path)
        .and_then(|state| state.last_routing_refresh)
        .is_none_or(|refresh| refresh.elapsed() >= ROUTING_REFRESH_INTERVAL)
}

pub(super) fn mark_routing_refresh(wallet_db_path: &str) {
    if let Some(state) = SERVICE
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .as_mut()
        .filter(|state| state.wallet_db_path == wallet_db_path)
    {
        state.last_routing_refresh = Some(Instant::now());
    }
}

pub(in crate::wallet::sync_engine) fn phase(wallet_db_path: &str) -> String {
    SERVICE
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .as_ref()
        .filter(|state| state.wallet_db_path == wallet_db_path)
        .map(|state| state.phase.as_str().to_owned())
        .unwrap_or_default()
}
