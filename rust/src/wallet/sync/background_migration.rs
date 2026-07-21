use super::migration;
use crate::wallet::{keys, network::WalletNetwork};
use std::sync::atomic::{AtomicBool, Ordering};
use zeroize::Zeroizing;

#[repr(u8)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum BackgroundMigrationAction {
    Complete,
    Wait,
    Sync,
    Advance,
    NeedsUserAction,
    RevokeAuthorization,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BackgroundMigrationInspection {
    pub action: BackgroundMigrationAction,
    pub phase: String,
    pub active_run_id: Option<String>,
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub next_scheduled_height: Option<u32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BackgroundMigrationCycleResult {
    pub inspection: BackgroundMigrationInspection,
    pub broadcasted_count: u32,
    pub cancelled: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct BackgroundMigrationDecisionInputs<'a> {
    pub phase: &'a str,
    pub has_active_run: bool,
    pub expected_run_matches: bool,
    pub scanned_height: u64,
    pub remote_tip_height: u64,
    pub next_scheduled_height: Option<u32>,
}

pub(crate) fn decide_background_migration_action(
    inputs: BackgroundMigrationDecisionInputs<'_>,
) -> BackgroundMigrationAction {
    if !inputs.has_active_run {
        return BackgroundMigrationAction::Complete;
    }

    if !inputs.expected_run_matches {
        return BackgroundMigrationAction::NeedsUserAction;
    }

    if inputs.scanned_height > inputs.remote_tip_height {
        return BackgroundMigrationAction::NeedsUserAction;
    }

    match inputs.phase {
        migration::PHASE_COMPLETE | migration::PHASE_NO_ORCHARD_FUNDS => {
            BackgroundMigrationAction::Complete
        }
        migration::PHASE_BROADCAST_SCHEDULED => {
            let Some(scheduled_height) = inputs.next_scheduled_height.map(u64::from) else {
                return BackgroundMigrationAction::NeedsUserAction;
            };

            if inputs.scanned_height >= scheduled_height {
                BackgroundMigrationAction::Advance
            } else if inputs.remote_tip_height >= scheduled_height {
                BackgroundMigrationAction::Sync
            } else {
                BackgroundMigrationAction::Wait
            }
        }
        migration::PHASE_WAITING_DENOM_CONFIRMATIONS
        | migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS
        | migration::PHASE_WAITING_FOR_SPENDABLE_ORCHARD
        | migration::PHASE_WAITING_FOR_IRONWOOD_SPENDABILITY => {
            if inputs.remote_tip_height > inputs.scanned_height {
                BackgroundMigrationAction::Sync
            } else {
                BackgroundMigrationAction::Advance
            }
        }
        migration::PHASE_READY_TO_MIGRATE
        | migration::PHASE_BROADCASTING
        | migration::PHASE_FAILED_RECOVERABLE => BackgroundMigrationAction::Advance,
        migration::PHASE_READY_TO_PREPARE
        | migration::PHASE_PAUSED
        | migration::PHASE_FAILED_TERMINAL
        | migration::PHASE_ABANDONED => BackgroundMigrationAction::NeedsUserAction,
        _ => BackgroundMigrationAction::NeedsUserAction,
    }
}

pub(crate) fn inspect_background_migration(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
) -> Result<BackgroundMigrationInspection, String> {
    if !keys::account_exists(db_path, network, account_uuid)? {
        return Ok(BackgroundMigrationInspection {
            action: BackgroundMigrationAction::RevokeAuthorization,
            phase: "account_missing".to_string(),
            active_run_id: None,
            scanned_height: 0,
            chain_tip_height: 0,
            next_scheduled_height: None,
        });
    }
    let status = migration::migration_status(db_path, network, account_uuid, 0, 0, 0, 0)?;
    let progress = super::get_sync_progress(db_path, network)?;
    let next_scheduled_height = status
        .active_run_id
        .as_deref()
        .map(|run_id| migration::next_scheduled_height(db_path, run_id))
        .transpose()?
        .flatten();
    let action = decide_background_migration_action(BackgroundMigrationDecisionInputs {
        phase: &status.phase,
        has_active_run: status.active_run_id.is_some(),
        expected_run_matches: status.active_run_id.as_deref() == Some(expected_run_id),
        scanned_height: progress.scanned_height,
        remote_tip_height: progress.chain_tip_height,
        next_scheduled_height,
    });

    Ok(BackgroundMigrationInspection {
        action,
        phase: status.phase,
        active_run_id: status.active_run_id,
        scanned_height: progress.scanned_height,
        chain_tip_height: progress.chain_tip_height,
        next_scheduled_height,
    })
}

#[allow(clippy::too_many_arguments)]
pub(crate) async fn run_background_migration_cycle(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
    pending_password: Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
    cancel: &AtomicBool,
) -> Result<BackgroundMigrationCycleResult, String> {
    let before = inspect_background_migration(db_path, network, account_uuid, expected_run_id)?;
    if cancel.load(Ordering::SeqCst) {
        return Ok(BackgroundMigrationCycleResult {
            inspection: before,
            broadcasted_count: 0,
            cancelled: true,
        });
    }
    if before.action != BackgroundMigrationAction::Advance {
        return Ok(BackgroundMigrationCycleResult {
            inspection: before,
            broadcasted_count: 0,
            cancelled: false,
        });
    }

    let result = super::send::broadcast_due_orchard_migration_transactions_for_run(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        expected_run_id,
        pending_password,
        pending_salt_base64,
        cancel,
    )
    .await?;
    let inspection = inspect_background_migration(db_path, network, account_uuid, expected_run_id)?;
    let cancelled = cancel.load(Ordering::SeqCst);

    Ok(BackgroundMigrationCycleResult {
        inspection,
        broadcasted_count: result.broadcasted_count,
        cancelled,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decide(
        phase: &str,
        scanned_height: u64,
        remote_tip_height: u64,
        next_scheduled_height: Option<u32>,
    ) -> BackgroundMigrationAction {
        decide_background_migration_action(BackgroundMigrationDecisionInputs {
            phase,
            has_active_run: true,
            expected_run_matches: true,
            scanned_height,
            remote_tip_height,
            next_scheduled_height,
        })
    }

    #[test]
    fn no_active_run_is_complete() {
        assert_eq!(
            decide_background_migration_action(BackgroundMigrationDecisionInputs {
                phase: migration::PHASE_READY_TO_PREPARE,
                has_active_run: false,
                expected_run_matches: true,
                scanned_height: 500,
                remote_tip_height: 500,
                next_scheduled_height: None,
            }),
            BackgroundMigrationAction::Complete
        );
    }

    #[test]
    fn scheduled_part_syncs_only_when_required_height_is_not_scanned() {
        assert_eq!(
            decide(migration::PHASE_BROADCAST_SCHEDULED, 504, 510, Some(505),),
            BackgroundMigrationAction::Sync
        );
        assert_eq!(
            decide(migration::PHASE_BROADCAST_SCHEDULED, 505, 510, Some(505),),
            BackgroundMigrationAction::Advance
        );
    }

    #[test]
    fn scheduled_part_waits_without_syncing_before_remote_tip_reaches_height() {
        assert_eq!(
            decide(migration::PHASE_BROADCAST_SCHEDULED, 500, 504, Some(505),),
            BackgroundMigrationAction::Wait
        );
    }

    #[test]
    fn confirmation_phase_syncs_new_blocks_then_checks_for_next_step() {
        assert_eq!(
            decide(migration::PHASE_WAITING_DENOM_CONFIRMATIONS, 500, 501, None,),
            BackgroundMigrationAction::Sync
        );
        assert_eq!(
            decide(
                migration::PHASE_WAITING_MIGRATION_CONFIRMATIONS,
                501,
                501,
                None,
            ),
            BackgroundMigrationAction::Advance
        );
    }

    #[test]
    fn ready_and_recoverable_runs_advance_without_another_signature() {
        assert_eq!(
            decide(migration::PHASE_READY_TO_MIGRATE, 500, 500, None,),
            BackgroundMigrationAction::Advance
        );
        assert_eq!(
            decide(migration::PHASE_FAILED_RECOVERABLE, 500, 500, None,),
            BackgroundMigrationAction::Advance
        );
    }

    #[test]
    fn terminal_paused_and_expiry_recovery_require_foreground_action() {
        for phase in [
            migration::PHASE_PAUSED,
            migration::PHASE_FAILED_TERMINAL,
            migration::PHASE_ABANDONED,
        ] {
            assert_eq!(
                decide(phase, 500, 500, None),
                BackgroundMigrationAction::NeedsUserAction
            );
        }
    }

    #[test]
    fn missing_schedule_and_unknown_phases_do_not_run_automatically() {
        assert_eq!(
            decide(migration::PHASE_BROADCAST_SCHEDULED, 500, 510, None,),
            BackgroundMigrationAction::NeedsUserAction
        );
        assert_eq!(
            decide("future_phase", 500, 510, None),
            BackgroundMigrationAction::NeedsUserAction
        );
    }

    #[test]
    fn inconsistent_chain_heights_do_not_run_automatically() {
        assert_eq!(
            decide(migration::PHASE_BROADCAST_SCHEDULED, 511, 510, Some(505),),
            BackgroundMigrationAction::NeedsUserAction
        );
    }

    #[test]
    fn stale_task_cannot_advance_a_replacement_run() {
        assert_eq!(
            decide_background_migration_action(BackgroundMigrationDecisionInputs {
                phase: migration::PHASE_BROADCAST_SCHEDULED,
                has_active_run: true,
                expected_run_matches: false,
                scanned_height: 510,
                remote_tip_height: 510,
                next_scheduled_height: Some(505),
            }),
            BackgroundMigrationAction::NeedsUserAction
        );
    }
}
