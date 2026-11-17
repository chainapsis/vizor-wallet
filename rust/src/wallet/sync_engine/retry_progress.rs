use super::{CheckingProgress, SyncEventKind, SyncProgressEvent};

/// What a sync session carries from one attempt to the next. Each attempt
/// reports its sync job's fraction, which already includes the work earlier
/// attempts finished (`progress_work::JobProgress`); this keeps whether the
/// main scan finished and the Checking stage, which lives only in memory.
#[derive(Default)]
pub(super) struct RetryProgress {
    completed: f64,
    checking: Option<CheckingProgress>,
}

impl RetryProgress {
    pub(super) fn checking_cycle(&self) -> u32 {
        self.checking.map_or(0, |checking| checking.cycle)
    }

    pub(super) fn main_scan_complete(&self) -> bool {
        self.completed >= 1.0
    }

    /// Carry the Checking stage across attempts and note completed scan work.
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
    use crate::wallet::sync_engine::progress_work::{JobProgress, StoredProgressJob};
    use crate::wallet::sync_engine::{preparation_progress_event, scan_queue_progress_event};

    /// A job that has finished `fraction` of 1,000 work units.
    fn job(fraction: f64) -> JobProgress {
        let (mut job, _) = JobProgress::start(StoredProgressJob::unmeasured(), 1_000.0, 0.0);
        job.observe_after_batch(1_000.0 * fraction, 1_000.0 * (1.0 - fraction));
        job
    }

    fn prepare(tip: u64, fraction: f64) -> SyncProgressEvent {
        preparation_progress_event(tip, "chain_prepare", 0, 0, fraction, "job")
    }

    fn scan(percentage: f64, target: f64) -> SyncProgressEvent {
        SyncProgressEvent {
            percentage,
            display_target_percentage: target,
            display_target_blocks: 100,
            phase: "scan".into(),
            ..prepare(3_500_000, 0.0)
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
        progress.report(scan(1.0, 1.0));
        progress.report(checking(1, 0.75, 0.9));
        let prep = progress.report(prepare(100, 1.0));
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
            &job(1.0),
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
        let prep = progress.report(prepare(1000, 1.0));
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
        let prep = progress.report(prepare(1000, 1.0));
        assert_eq!(prep.checking.unwrap().percentage, 1.0);
        let mut cycle = progress.checking_cycle();
        let empty = progress.report(scan_queue_progress_event(
            &mut cycle,
            true,
            0,
            1000,
            None,
            &job(1.0),
        ));
        assert_eq!(empty.checking.unwrap().cycle, 1);
        assert_eq!(empty.checking.unwrap().percentage, 1.0);
        let remaining = progress.report(scan_queue_progress_event(
            &mut cycle,
            true,
            100,
            1000,
            Some(900),
            &job(1.0),
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
    fn a_retry_reports_the_job_fraction_without_carrying_it_twice() {
        let mut progress = RetryProgress::default();
        let before = progress.report(scan(0.44, 0.45));
        assert_eq!(before.percentage, 0.44);
        // The retry resumes the stored job, so its preparation already reads
        // the fraction reached, and its batches continue from there.
        let preparation = progress.report(prepare(3_500_000, 0.44));
        assert_eq!(preparation.percentage, before.percentage);
        assert_eq!(preparation.kind, SyncEventKind::Progress);
        let after = progress.report(scan(0.4456, 0.4512));
        assert_eq!(after.percentage, 0.4456);
        assert_eq!(after.display_target_percentage, 0.4512);
        assert_eq!(after.display_target_blocks, 100);
        // A download target is not finished work.
        let mut targeted = RetryProgress::default();
        targeted.report(scan(0.9, 1.0));
        assert!(!targeted.main_scan_complete());
    }

    #[test]
    fn retry_after_main_scan_drains_uses_checking_instead_of_a_tail_budget() {
        let mut progress = RetryProgress::default();
        let drained = progress.report(scan(1.0, 1.0));
        assert_eq!(drained.kind, SyncEventKind::Progress);
        assert!(progress.main_scan_complete());
        for _ in 0..3 {
            let prep = progress.report(prepare(1000, 1.0));
            assert_eq!(prep.percentage, 1.0);
            let mut cycle = progress.checking_cycle();
            let queue = progress.report(scan_queue_progress_event(
                &mut cycle,
                progress.main_scan_complete(),
                100,
                1000,
                Some(900),
                &job(1.0),
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
        let mut cycle = progress.checking_cycle();
        let queue = progress.report(scan_queue_progress_event(
            &mut cycle,
            progress.main_scan_complete(),
            100,
            1000,
            Some(900),
            &job(0.5),
        ));
        assert!(queue.checking.is_none());
        assert_eq!(queue.percentage, 0.5);
        progress.report(scan(1.0, 1.0));
        let empty = progress.report(scan_queue_progress_event(
            &mut cycle,
            progress.main_scan_complete(),
            0,
            1000,
            None,
            &job(1.0),
        ));
        assert!(empty.checking.is_none());
        assert_eq!(empty.percentage, 1.0);
        assert_eq!(empty.kind, SyncEventKind::Progress);
    }

    #[test]
    fn retry_preserves_completion_and_does_not_complete_on_scan_progress_alone() {
        let mut progress = RetryProgress::default();
        progress.report(scan(0.5, 0.5));
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
