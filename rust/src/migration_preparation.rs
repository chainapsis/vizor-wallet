//! Platform-neutral execution core for mobile Ironwood migration preparation.
//!
//! Platform adapters are responsible only for converting their native inputs
//! and outputs. Operation ownership, foreground-sync exclusion, state
//! interpretation, sync execution, and denomination advancement live here so
//! iOS and Android use the same state machine.

use std::fmt;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};

use zeroize::Zeroizing;

use crate::api::sync::SYNC_RUNNING;
use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::SyncProgressEvent;
use crate::wallet::{sync, sync_engine};

const MIGRATION_PREPARATION_SYNC_MODE: u8 = 2;
const STOPPED_SYNC_MODE: u8 = 0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MigrationPreparationState {
    WaitingForDenominationPreparation = 0,
    ProofReady = 1,
    NeedsUserAction = 2,
    Cancelled = 3,
    Inactive = 4,
    WaitingForPreparedNoteAnchor = 5,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MigrationPreparationProgress {
    pub state: MigrationPreparationState,
    pub confirmation_count: u32,
    pub confirmation_target: u32,
    pub completed_stage_count: u32,
    pub total_stage_count: u32,
}

impl MigrationPreparationProgress {
    fn inactive() -> Self {
        Self {
            state: MigrationPreparationState::Inactive,
            confirmation_count: 0,
            confirmation_target: 0,
            completed_stage_count: 0,
            total_stage_count: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MigrationPreparationError {
    NoActiveOperation,
    SyncAlreadyRunning,
    InvalidCredential,
    Execution(String),
}

impl fmt::Display for MigrationPreparationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NoActiveOperation => {
                formatter.write_str("Migration preparation has no active operation")
            }
            Self::SyncAlreadyRunning => {
                formatter.write_str("Another wallet sync is already running")
            }
            Self::InvalidCredential => {
                formatter.write_str("Migration preparation credential must be 64 hexadecimal bytes")
            }
            Self::Execution(message) => formatter.write_str(message),
        }
    }
}

impl std::error::Error for MigrationPreparationError {}

struct MigrationPreparationControl {
    cancel: Arc<AtomicBool>,
    desired_sync_mode: AtomicU8,
}

impl MigrationPreparationControl {
    fn new() -> Self {
        Self {
            cancel: Arc::new(AtomicBool::new(false)),
            desired_sync_mode: AtomicU8::new(MIGRATION_PREPARATION_SYNC_MODE),
        }
    }

    fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
        self.desired_sync_mode
            .store(STOPPED_SYNC_MODE, Ordering::SeqCst);
    }
}

struct MigrationPreparationOperation {
    active: Mutex<Option<Arc<MigrationPreparationControl>>>,
}

impl MigrationPreparationOperation {
    const fn new() -> Self {
        Self {
            active: Mutex::new(None),
        }
    }

    fn begin(&self) -> bool {
        let mut active = self
            .active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if active.is_some() {
            return false;
        }
        *active = Some(Arc::new(MigrationPreparationControl::new()));
        true
    }

    fn cancel(&self) -> bool {
        let active = self
            .active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let Some(control) = active.as_ref() else {
            return false;
        };
        control.cancel();
        true
    }

    fn end(&self) {
        let control = self
            .active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take();
        if let Some(control) = control {
            control.cancel();
        }
    }

    fn control(&self) -> Option<Arc<MigrationPreparationControl>> {
        self.active
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .as_ref()
            .cloned()
    }
}

static MIGRATION_PREPARATION_OPERATION: MigrationPreparationOperation =
    MigrationPreparationOperation::new();

struct SyncRunningGuard;

impl SyncRunningGuard {
    fn acquire() -> Result<Self, MigrationPreparationError> {
        SYNC_RUNNING
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map(|_| Self)
            .map_err(|_| MigrationPreparationError::SyncAlreadyRunning)
    }
}

impl Drop for SyncRunningGuard {
    fn drop(&mut self) {
        SYNC_RUNNING.store(false, Ordering::SeqCst);
    }
}

pub fn begin_operation() -> bool {
    MIGRATION_PREPARATION_OPERATION.begin()
}

pub fn cancel_operation() -> bool {
    MIGRATION_PREPARATION_OPERATION.cancel()
}

pub fn end_operation() {
    MIGRATION_PREPARATION_OPERATION.end();
}

pub fn is_sync_running() -> bool {
    SYNC_RUNNING.load(Ordering::SeqCst)
}

pub fn run_sync(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    progress_callback: impl Fn(SyncProgressEvent) + Send + Sync,
) -> Result<(), MigrationPreparationError> {
    let control = MIGRATION_PREPARATION_OPERATION
        .control()
        .ok_or(MigrationPreparationError::NoActiveOperation)?;
    let _sync_guard = SyncRunningGuard::acquire()?;
    let runtime = current_thread_runtime()?;

    runtime
        .block_on(sync_engine::run_sync_inner(
            db_path,
            lightwalletd_url,
            network,
            control.cancel.clone(),
            MIGRATION_PREPARATION_SYNC_MODE,
            &control.desired_sync_mode,
            false,
            progress_callback,
        ))
        .map_err(MigrationPreparationError::Execution)
}

pub fn inspect(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
) -> Result<MigrationPreparationProgress, MigrationPreparationError> {
    let status = sync::migration_status(db_path, network, account_uuid, 0, 0, 0, 0)
        .map_err(MigrationPreparationError::Execution)?;
    if status.active_run_id.as_deref() != Some(expected_run_id) {
        return Ok(MigrationPreparationProgress::inactive());
    }
    progress_for_status(db_path, network, &status)
}

#[allow(clippy::too_many_arguments)]
pub fn advance(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
    credential: Zeroizing<Vec<u8>>,
    salt_base64: &str,
) -> Result<MigrationPreparationProgress, MigrationPreparationError> {
    let control = MIGRATION_PREPARATION_OPERATION
        .control()
        .ok_or(MigrationPreparationError::NoActiveOperation)?;
    if !is_valid_credential(&credential) {
        return Err(MigrationPreparationError::InvalidCredential);
    }
    let runtime = current_thread_runtime()?;
    runtime
        .block_on(sync::advance_orchard_migration_preparation_for_run(
            db_path,
            lightwalletd_url,
            network,
            account_uuid,
            expected_run_id,
            credential,
            salt_base64,
            control.cancel.as_ref(),
        ))
        .map_err(MigrationPreparationError::Execution)?;

    let status = sync::migration_status(db_path, network, account_uuid, 0, 0, 0, 0)
        .map_err(MigrationPreparationError::Execution)?;
    if status
        .active_run_id
        .as_deref()
        .is_some_and(|id| id != expected_run_id)
    {
        return Err(MigrationPreparationError::Execution(
            "Ironwood migration preparation run changed".to_string(),
        ));
    }

    let mut progress = progress_for_status(db_path, network, &status)?;
    if control.cancel.load(Ordering::SeqCst) {
        progress.state = MigrationPreparationState::Cancelled;
    }
    Ok(progress)
}

fn current_thread_runtime() -> Result<tokio::runtime::Runtime, MigrationPreparationError> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|error| {
            MigrationPreparationError::Execution(format!(
                "Create migration preparation runtime: {error}"
            ))
        })
}

fn is_valid_credential(credential: &[u8]) -> bool {
    credential.len() == 64 && credential.iter().all(u8::is_ascii_hexdigit)
}

fn progress_for_status(
    db_path: &str,
    network: WalletNetwork,
    status: &sync::MigrationStatus,
) -> Result<MigrationPreparationProgress, MigrationPreparationError> {
    if status.active_run_id.is_none() {
        return Ok(MigrationPreparationProgress::inactive());
    }
    let scanned_height = sync::get_sync_progress(db_path, network)
        .and_then(|progress| {
            u32::try_from(progress.scanned_height)
                .map_err(|_| "Migration scanned height exceeds u32".to_string())
        })
        .map_err(MigrationPreparationError::Execution)?;

    Ok(MigrationPreparationProgress {
        state: classify_state(
            &status.phase,
            status.signed_child_pczt_count,
            status.next_action_height,
            scanned_height,
        ),
        confirmation_count: status.denomination_confirmation_count,
        confirmation_target: status.denomination_confirmation_target,
        completed_stage_count: status.denomination_split_completed_count,
        total_stage_count: status.denomination_split_total_count,
    })
}

fn classify_state(
    phase: &str,
    signed_child_pczt_count: u32,
    next_action_height: Option<u32>,
    scanned_height: u32,
) -> MigrationPreparationState {
    match phase {
        "waiting_denom_confirmations" => {
            MigrationPreparationState::WaitingForDenominationPreparation
        }
        "ready_to_migrate" if signed_child_pczt_count > 0 => match next_action_height {
            Some(height) if height <= scanned_height => MigrationPreparationState::ProofReady,
            Some(_) => MigrationPreparationState::WaitingForPreparedNoteAnchor,
            None => MigrationPreparationState::NeedsUserAction,
        },
        "broadcast_scheduled" | "broadcasting" | "waiting_migration_confirmations" | "complete" => {
            MigrationPreparationState::Inactive
        }
        _ => MigrationPreparationState::NeedsUserAction,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operation_owns_cancel_across_sync_and_advance() {
        let operation = MigrationPreparationOperation::new();
        assert!(operation.begin());
        assert!(!operation.begin());

        let sync_control = operation.control().unwrap();
        let advance_control = operation.control().unwrap();
        assert!(Arc::ptr_eq(&sync_control, &advance_control));
        assert!(!sync_control.cancel.load(Ordering::Relaxed));
        assert_eq!(
            sync_control.desired_sync_mode.load(Ordering::SeqCst),
            MIGRATION_PREPARATION_SYNC_MODE
        );

        let unrelated_sync_cancel = AtomicBool::new(false);
        unrelated_sync_cancel.store(true, Ordering::Relaxed);
        assert!(!sync_control.cancel.load(Ordering::Relaxed));

        assert!(operation.cancel());
        assert!(sync_control.cancel.load(Ordering::Relaxed));
        assert!(advance_control.cancel.load(Ordering::Relaxed));
        assert_eq!(
            sync_control.desired_sync_mode.load(Ordering::SeqCst),
            STOPPED_SYNC_MODE
        );

        operation.end();
        assert!(operation.control().is_none());
        assert!(!operation.cancel());

        assert!(operation.begin());
        let next_control = operation.control().unwrap();
        assert!(!Arc::ptr_eq(&sync_control, &next_control));
        assert!(!next_control.cancel.load(Ordering::Relaxed));
        operation.end();
    }

    #[test]
    fn state_mapping_distinguishes_anchor_wait_from_proof_readiness() {
        assert_eq!(
            classify_state("ready_to_migrate", 1, Some(2_000), 1_999),
            MigrationPreparationState::WaitingForPreparedNoteAnchor
        );
        assert_eq!(
            classify_state("ready_to_migrate", 1, Some(2_000), 2_000),
            MigrationPreparationState::ProofReady
        );
        assert_eq!(
            classify_state("ready_to_migrate", 1, None, 2_000),
            MigrationPreparationState::NeedsUserAction
        );
    }

    #[test]
    fn state_mapping_keeps_completed_or_foreground_owned_runs_inactive() {
        for phase in [
            "broadcast_scheduled",
            "broadcasting",
            "waiting_migration_confirmations",
            "complete",
        ] {
            assert_eq!(
                classify_state(phase, 0, None, 0),
                MigrationPreparationState::Inactive
            );
        }
        assert_eq!(
            classify_state("waiting_denom_confirmations", 0, None, 0),
            MigrationPreparationState::WaitingForDenominationPreparation
        );
        assert_eq!(
            classify_state("ready_to_migrate", 0, Some(0), 0),
            MigrationPreparationState::NeedsUserAction
        );
    }

    #[test]
    fn invalid_credentials_are_rejected_before_execution() {
        assert!(!is_valid_credential(&[b'a'; 63]));
        assert!(!is_valid_credential(&[b'a'; 65]));
        assert!(!is_valid_credential(&[b'g'; 64]));
        assert!(!is_valid_credential(&[0; 64]));
        assert!(is_valid_credential(&[b'a'; 64]));
        assert!(is_valid_credential(&[b'F'; 64]));
    }
}
