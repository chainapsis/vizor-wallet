use super::{SyncProgressEvent, TAIL_REPAIR_MAX_START_PERCENTAGE};

/// Each attempt measures only its remaining scan work. Keep the completed
/// portion of this sync session when a transient failure starts another attempt.
#[derive(Default)]
pub(super) struct RetryProgress {
    attempt_base: f64,
    completed: f64,
}

impl RetryProgress {
    /// Carry completed scan work forward, leaving room for unfinished repairs.
    pub(super) fn start_attempt(&mut self) {
        // A drained scan can still queue repairs and fail before completion.
        // Reuse the tail-repair allowance instead of pinning the retry at 100%.
        self.completed = if self.completed < 1.0 {
            self.completed
        } else {
            TAIL_REPAIR_MAX_START_PERCENTAGE
        };
        self.attempt_base = self.completed;
    }

    /// Map attempt-local progress and its download target into this session.
    pub(super) fn report(&mut self, mut event: SyncProgressEvent) -> SyncProgressEvent {
        let remaining = 1.0 - self.attempt_base;
        event.percentage = self.attempt_base + remaining * event.percentage.clamp(0.0, 1.0);
        event.display_target_percentage =
            self.attempt_base + remaining * event.display_target_percentage.clamp(0.0, 1.0);
        // A download target is an estimate, not completed work. Carry forward
        // only reported progress, including across multiple failed attempts.
        self.completed = self.completed.max(event.percentage);
        event
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::sync_engine::preparation_progress_event;

    fn scan(percentage: f64, target: f64) -> SyncProgressEvent {
        SyncProgressEvent {
            percentage,
            display_target_percentage: target,
            display_target_blocks: 100,
            phase: "scan".into(),
            ..preparation_progress_event(3_500_000, "chain_prepare", 0, 0)
        }
    }

    #[test]
    fn retry_reports_newly_scanned_work_above_previous_progress() {
        let mut progress = RetryProgress::default();
        progress.start_attempt();
        let before = progress.report(scan(0.44, 0.45));
        assert_eq!(before.percentage, 0.44);
        progress.start_attempt();
        let preparation =
            progress.report(preparation_progress_event(3_500_000, "chain_prepare", 0, 0));
        assert_eq!(preparation.percentage, before.percentage);
        assert!(!preparation.is_complete);

        // 100 blocks out of the remaining 10,000 finish after the retry.
        // The UI must advance from 46.36%, not stay there until 44% of
        // the remaining work has been scanned.
        let after = progress.report(scan(0.01, 0.02));
        assert!((after.percentage - 0.4456).abs() < 1e-12);
        assert!((after.display_target_percentage - 0.4512).abs() < 1e-12);
        assert_eq!(after.display_target_blocks, 100);
        assert!(!after.is_complete);
    }

    #[test]
    fn repeated_retries_carry_completed_work_but_not_speculative_targets() {
        let mut progress = RetryProgress::default();
        progress.start_attempt();
        progress.report(scan(0.5, 0.9));
        progress.start_attempt();
        assert_eq!(progress.report(scan(0.2, 0.4)).percentage, 0.6);
        progress.start_attempt();
        assert_eq!(progress.report(scan(0.5, 0.5)).percentage, 0.8);
        // A fresh run has its own progress budget.
        let mut fresh = RetryProgress::default();
        fresh.start_attempt();
        assert_eq!(fresh.report(scan(0.1, 0.2)).percentage, 0.1);
    }

    #[test]
    fn retry_after_scan_drains_leaves_room_for_unfinished_repairs() {
        let mut progress = RetryProgress::default();
        progress.start_attempt();
        let drained = progress.report(scan(1.0, 1.0));
        assert_eq!(drained.percentage, 1.0);
        assert!(!drained.is_complete);

        // Repair scanning can fail after the original scan queue drained.
        progress.report(scan(0.95, 0.96));
        let mut previous_repair_percentage = TAIL_REPAIR_MAX_START_PERCENTAGE;
        for _ in 0..3 {
            progress.start_attempt();
            let preparation =
                progress.report(preparation_progress_event(3_500_000, "chain_prepare", 0, 0));
            assert_eq!(preparation.percentage, previous_repair_percentage);
            let repair = progress.report(scan(0.5, 0.8));
            assert!(preparation.percentage < repair.percentage);
            assert!(repair.percentage < repair.display_target_percentage);
            assert!(repair.display_target_percentage < 1.0);
            assert!(repair.is_syncing);
            assert!(!repair.is_complete);
            previous_repair_percentage = repair.percentage;
        }

        let done = progress.report(SyncProgressEvent {
            is_complete: true,
            is_syncing: false,
            ..scan(1.0, 1.0)
        });
        assert_eq!(done.percentage, 1.0);
        assert_eq!(done.display_target_percentage, 1.0);
        assert!(done.is_complete);
        assert!(!done.is_syncing);
    }

    #[test]
    fn retry_preserves_completion_and_does_not_complete_on_scan_progress_alone() {
        let mut progress = RetryProgress::default();
        progress.report(scan(0.5, 0.5));
        progress.start_attempt();
        let scanned = progress.report(scan(1.0, 1.0));
        assert_eq!(scanned.percentage, 1.0);
        assert!(!scanned.is_complete);
        let done = progress.report(SyncProgressEvent {
            is_complete: true,
            is_syncing: false,
            ..scan(1.0, 1.0)
        });
        assert_eq!(done.percentage, 1.0);
        assert!(done.is_complete);
        assert!(!done.is_syncing);
    }
}
