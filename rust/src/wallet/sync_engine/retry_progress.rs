use super::{CheckingProgress, SyncEventKind, SyncProgressEvent};

/// Each attempt measures only its remaining scan work. Keep the completed
/// portion of this sync session when a transient failure starts another attempt.
#[derive(Default)]
pub(super) struct RetryProgress {
    attempt_base: f64,
    completed: f64,
    checking: Option<CheckingProgress>,
}

impl RetryProgress {
    /// Carry ordinary scan progress forward. Additional scans have their own
    /// queue-based Checking progress, so no tail percentage needs reserving.
    pub(super) fn start_attempt(&mut self) {
        self.attempt_base = self.completed;
    }

    pub(super) fn checking_cycle(&self) -> u32 {
        self.checking.map_or(0, |checking| checking.cycle)
    }

    pub(super) fn main_scan_complete(&self) -> bool {
        self.completed >= 1.0
    }

    /// Map attempt-local progress and its download target into this session.
    pub(super) fn report(&mut self, mut event: SyncProgressEvent) -> SyncProgressEvent {
        if event.kind != SyncEventKind::Progress {
            event.checking = None;
        } else if let Some(checking) = event.checking {
            // Each discovered queue reports its own fraction. Retries and new
            // work may lower it; the cycle resets only the UI interpolation.
            self.checking = Some(checking);
        } else if let Some(checking) = self.checking {
            // Retry preparation precedes queue discovery. Keep the stage and
            // committed fraction, without interpolating the previous batch.
            event.checking = Some(CheckingProgress {
                cycle: checking.cycle,
                percentage: checking.percentage,
                display_target_percentage: checking.percentage,
            });
            event.display_target_blocks = 0;
        }
        let remaining = 1.0 - self.attempt_base;
        event.percentage = self.attempt_base + remaining * event.percentage.clamp(0.0, 1.0);
        event.display_target_percentage =
            self.attempt_base + remaining * event.display_target_percentage.clamp(0.0, 1.0);
        if event.checking.is_some() {
            // The main scan stays finished; Checking alone measures the work
            // discovered after it. Do not make ETA/other consumers see a rewind.
            event.percentage = 1.0;
            event.display_target_percentage = 1.0;
        }
        // A download target is an estimate, not completed work. Carry forward
        // only reported progress, including across multiple failed attempts.
        self.completed = self.completed.max(event.percentage);
        event
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::sync_engine::{preparation_progress_event, scan_queue_progress_event};

    fn scan(percentage: f64, target: f64) -> SyncProgressEvent {
        SyncProgressEvent {
            percentage,
            display_target_percentage: target,
            display_target_blocks: 100,
            phase: "scan".into(),
            ..preparation_progress_event(3_500_000, "chain_prepare", 0, 0)
        }
    }

    fn checking(cycle: u32, percentage: f64, target: f64) -> SyncProgressEvent {
        SyncProgressEvent {
            checking: Some(CheckingProgress {
                cycle,
                percentage,
                display_target_percentage: target,
            }),
            ..scan(1.0, 1.0)
        }
    }

    #[test]
    fn checking_retry_preserves_preparation_then_measures_new_queue_without_accumulation() {
        let mut progress = RetryProgress::default();
        progress.start_attempt();
        progress.report(scan(1.0, 1.0));
        progress.report(checking(1, 0.75, 0.9));
        progress.start_attempt();
        let prep = progress.report(preparation_progress_event(100, "chain_prepare", 0, 0));
        let carried = prep.checking.unwrap();
        assert_eq!(carried.cycle, 1);
        assert_eq!(carried.percentage, 0.75);
        assert_eq!(carried.display_target_percentage, 0.75);
        assert_eq!(prep.display_target_blocks, 0);
        assert_eq!(prep.percentage, 1.0);

        let mut cycle = progress.checking_cycle();
        let queue = progress.report(scan_queue_progress_event(
            &mut cycle,
            progress.main_scan_complete(),
            200,
            1000,
            Some(800),
        ));
        assert_eq!(queue.checking.unwrap().cycle, 2);
        assert_eq!(queue.checking.unwrap().percentage, 0.0);
        assert_eq!(queue.remaining_scan_blocks, Some(200));
        assert_eq!(queue.pending_scan_start_height, Some(800));
        let after = progress.report(checking(cycle, 0.5, 0.8));
        assert_eq!(after.checking.unwrap().percentage, 0.5);
        assert_eq!(after.checking.unwrap().display_target_percentage, 0.8);
        assert_eq!(after.percentage, 1.0);

        // Another preparation failure must keep the latest authoritative
        // fraction; restarting before queue discovery does not fabricate work.
        progress.start_attempt();
        let prep = progress.report(preparation_progress_event(1000, "chain_prepare", 0, 0));
        assert_eq!(prep.checking.unwrap().cycle, 2);
        assert_eq!(prep.checking.unwrap().percentage, 0.5);
        let done = progress.report(SyncProgressEvent {
            kind: SyncEventKind::Completed,
            is_syncing: false,
            ..scan(1.0, 1.0)
        });
        assert!(done.checking.is_none());
    }

    #[test]
    fn retry_after_checking_drains_starts_new_measurement_only_if_work_remains() {
        let mut progress = RetryProgress::default();
        progress.report(checking(1, 1.0, 1.0));
        progress.start_attempt();
        let prep = progress.report(preparation_progress_event(1000, "chain_prepare", 0, 0));
        assert_eq!(prep.checking.unwrap().percentage, 1.0);
        let mut cycle = progress.checking_cycle();
        let empty = progress.report(scan_queue_progress_event(&mut cycle, true, 0, 1000, None));
        assert_eq!(empty.checking.unwrap().cycle, 1);
        assert_eq!(empty.checking.unwrap().percentage, 1.0);
        let remaining = progress.report(scan_queue_progress_event(
            &mut cycle,
            true,
            100,
            1000,
            Some(900),
        ));
        assert_eq!(remaining.checking.unwrap().cycle, 2);
        assert_eq!(remaining.checking.unwrap().percentage, 0.0);
        assert_eq!(
            progress
                .report(checking(cycle, 0.5, 0.8))
                .checking
                .unwrap()
                .percentage,
            0.5
        );
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
        assert_eq!(preparation.kind, SyncEventKind::Progress);

        // 100 blocks out of the remaining 10,000 finish after the retry.
        // The UI must advance from 46.36%, not stay there until 44% of
        // the remaining work has been scanned.
        let after = progress.report(scan(0.01, 0.02));
        assert!((after.percentage - 0.4456).abs() < 1e-12);
        assert!((after.display_target_percentage - 0.4512).abs() < 1e-12);
        assert_eq!(after.display_target_blocks, 100);
        assert_eq!(after.kind, SyncEventKind::Progress);
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
    fn retry_after_main_scan_drains_uses_checking_instead_of_a_tail_budget() {
        let mut progress = RetryProgress::default();
        progress.start_attempt();
        let drained = progress.report(scan(1.0, 1.0));
        assert_eq!(drained.kind, SyncEventKind::Progress);
        assert!(progress.main_scan_complete());
        for _ in 0..3 {
            progress.start_attempt();
            let prep = progress.report(preparation_progress_event(1000, "chain_prepare", 0, 0));
            assert_eq!(prep.percentage, 1.0);
            let mut cycle = progress.checking_cycle();
            let queue = progress.report(scan_queue_progress_event(
                &mut cycle,
                progress.main_scan_complete(),
                100,
                1000,
                Some(900),
            ));
            assert_eq!(queue.checking.unwrap().percentage, 0.0);
            let repair = progress.report(checking(cycle, 0.5, 0.8));
            assert_eq!(repair.percentage, 1.0);
            assert_eq!(repair.checking.unwrap().percentage, 0.5);
            assert_eq!(repair.checking.unwrap().display_target_percentage, 0.8);
        }
    }

    #[test]
    fn retry_during_main_scan_does_not_enter_checking_and_empty_queue_does_not_start_it() {
        let mut progress = RetryProgress::default();
        progress.report(scan(0.5, 0.8));
        progress.start_attempt();
        let mut cycle = progress.checking_cycle();
        let queue = progress.report(scan_queue_progress_event(
            &mut cycle,
            progress.main_scan_complete(),
            100,
            1000,
            Some(900),
        ));
        assert!(queue.checking.is_none());
        assert_eq!(queue.percentage, 0.5);
        progress.report(scan(1.0, 1.0));
        progress.start_attempt();
        let empty = progress.report(scan_queue_progress_event(
            &mut cycle,
            progress.main_scan_complete(),
            0,
            1000,
            None,
        ));
        assert!(empty.checking.is_none());
        assert_eq!(empty.percentage, 1.0);
        assert_eq!(empty.kind, SyncEventKind::Progress);
    }

    #[test]
    fn retry_preserves_completion_and_does_not_complete_on_scan_progress_alone() {
        let mut progress = RetryProgress::default();
        progress.report(scan(0.5, 0.5));
        progress.start_attempt();
        let scanned = progress.report(scan(1.0, 1.0));
        assert_eq!(scanned.percentage, 1.0);
        assert_eq!(scanned.kind, SyncEventKind::Progress);
        let done = progress.report(SyncProgressEvent {
            kind: SyncEventKind::Completed,
            is_syncing: false,
            ..scan(1.0, 1.0)
        });
        assert_eq!(done.percentage, 1.0);
        assert_eq!(done.kind, SyncEventKind::Completed);
        assert!(!done.is_syncing);
    }
}
