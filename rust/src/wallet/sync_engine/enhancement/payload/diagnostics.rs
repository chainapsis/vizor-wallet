//! Advisory payload-recovery diagnostics and refresh throttling.
//!
//! This process-global state is for UI reporting and request pacing only. It is
//! never authoritative for durable routing, persistence, or privacy decisions.

use std::{
    collections::HashMap,
    sync::{LazyLock, Mutex},
    time::{Duration, Instant},
};

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
    phase: RecoveryPhase,
    last_routing_refresh: Option<Instant>,
}

static SERVICE: LazyLock<Mutex<HashMap<String, ServiceState>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub(in crate::wallet::sync_engine) fn begin_session(wallet_db_path: &str) {
    let mut state = SERVICE.lock().unwrap_or_else(|error| error.into_inner());
    state.entry(wallet_db_path.into()).or_default().phase = RecoveryPhase::Idle;
}

pub(super) fn set_phase(wallet_db_path: &str, phase: RecoveryPhase) {
    let mut state = SERVICE.lock().unwrap_or_else(|error| error.into_inner());
    if let Some(state) = state.get_mut(wallet_db_path) {
        state.phase = phase;
    }
}

pub(super) fn routing_refresh_due(wallet_db_path: &str) -> bool {
    SERVICE
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .get(wallet_db_path)
        .and_then(|state| state.last_routing_refresh)
        .is_none_or(|refresh| refresh.elapsed() >= ROUTING_REFRESH_INTERVAL)
}

pub(super) fn mark_routing_refresh(wallet_db_path: &str) {
    if let Some(state) = SERVICE
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .get_mut(wallet_db_path)
    {
        state.last_routing_refresh = Some(Instant::now());
    }
}

pub(in crate::wallet::sync_engine) fn phase(wallet_db_path: &str) -> String {
    SERVICE
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .get(wallet_db_path)
        .map(|state| state.phase.as_str().to_owned())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn temporary_wallets_preserve_main_wallet_phase_and_refresh_budget() {
        let main = format!("main-{}", uuid::Uuid::new_v4());
        let gift = format!("gift-{}", uuid::Uuid::new_v4());
        begin_session(&main);
        set_phase(&main, RecoveryPhase::WaitingForSnapshot);
        mark_routing_refresh(&main);
        begin_session(&gift);
        set_phase(&gift, RecoveryPhase::Recovering);
        assert_eq!(phase(&main), "waiting_for_snapshot");
        assert!(!routing_refresh_due(&main));
        assert!(routing_refresh_due(&gift));
        mark_routing_refresh(&gift);
        begin_session(&gift);
        assert!(!routing_refresh_due(&gift));
        assert_eq!(phase(&main), "waiting_for_snapshot");
        let mut states = SERVICE.lock().unwrap();
        states.remove(&main);
        states.remove(&gift);
    }
}
