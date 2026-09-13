//! One switch for SDK voting observability, and the debug logging it feeds.
//!
//! The SDK collects per-stage timings and outcomes only for callers that opt in
//! through a `*_with_report` entry point and hand it
//! [`zcash_voting::ObservabilityOptions`]; `None` disables collection at the
//! source, so a disabled build starts no timers and retains no records.
//!
//! Every Vizor call site reads [`VOTING_OBSERVABILITY_ENABLED`] through
//! [`options`] rather than deciding for itself, so collection cannot end up on
//! for one entry point and off for the next — a half-instrumented run is worse
//! than an uninstrumented one, because the gaps read as fast stages.
//!
//! Rendering is the SDK's own [`std::fmt::Display`], not a local printer: stage
//! names are SDK-authored, errors are reduced to a stable category, endpoints
//! appear as a configured ordinal, and detailed records and free-form error
//! text are omitted. No URL, address, or error message reaches these lines.

use std::sync::Mutex;

use zcash_voting::{
    ObservabilityOptions, ObservationOutcome, OperationObservability, OperationReport,
};

/// The single switch for SDK voting observability.
///
/// Debug builds collect; release builds do not. Collection costs a timer and a
/// bounded record buffer per invocation — noise next to proving, but not free —
/// and the reports are a debugging aid rather than a product feature. Flip this
/// one constant to change every voting call site at once.
pub const VOTING_OBSERVABILITY_ENABLED: bool = cfg!(debug_assertions);

/// Options for a `*_with_report` entry point, or `None` when collection is off.
pub fn options() -> Option<ObservabilityOptions> {
    // Keep the expanded helper trace for a 3-bundle, 37-proposal vote; the
    // SDK's 4,096-record default truncates this workload.
    VOTING_OBSERVABILITY_ENABLED.then(|| ObservabilityOptions {
        max_records: 262_144,
        max_summary_groups: 131_072,
        ..ObservabilityOptions::default()
    })
}

/// The transport `api` installs so snapshots can also reach Dart.
///
/// A callback rather than a type because `wallet` does not depend on `api`:
/// the FRB-facing struct lives up there, and flattening the SDK snapshot into
/// it is that layer's job. Borrowing the SDK type here keeps exactly one
/// definition of these fields in the crate.
type Observer = Box<dyn Fn(&str, &OperationObservability) + Send + Sync>;

static OBSERVER: Mutex<Option<Observer>> = Mutex::new(None);

/// Installs, or with `None` removes, the transport for snapshots.
///
/// Replacing an observer drops the previous one, closing whatever stream it
/// held: a second registration is a deliberate hand-over, not a duplicate.
pub fn set_observer(observer: Option<Observer>) {
    *OBSERVER.lock().unwrap_or_else(|poison| poison.into_inner()) = observer;
}

/// Hands one snapshot to the installed transport, if there is one.
fn emit(context: &str, observability: &OperationObservability) {
    let observer = OBSERVER.lock().unwrap_or_else(|poison| poison.into_inner());
    if let Some(observer) = observer.as_ref() {
        observer(context, observability);
    }
}

/// Buffers and atomically publishes the full SDK snapshot after the run finishes.
/// The domain result is deliberately excluded: it can contain signed payloads.
fn save_snapshot(
    directory: &std::path::Path,
    snapshot: &OperationObservability,
) -> std::io::Result<std::path::PathBuf> {
    use std::io::Write;
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    std::fs::create_dir_all(directory)?;
    let path = directory.join(format!(
        "{}-{}-{}.json",
        snapshot.started_at_unix_us,
        std::process::id(),
        SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    // Publish only complete JSON so a concurrent reader never sees a partial report.
    let pending_path = path.with_extension("json.partial");
    let file = options.open(&pending_path)?;
    let mut file = std::io::BufWriter::with_capacity(256 * 1024, file);
    serde_json::to_writer_pretty(&mut file, snapshot)?;
    file.write_all(b"\n")?;
    file.flush()?;
    drop(file);
    std::fs::rename(&pending_path, &path)?;
    Ok(path)
}

/// Renders the error category of every record that did not succeed.
///
/// The SDK's `Display` prints summaries, and `ObservationSummary` carries an
/// outcome but no `error_kind` — so a failed stage renders with no reason
/// attached, which is exactly the case worth reading. `error_kind` lives on
/// `ObservationRecord`, is collected already, and is a stable category rather
/// than free-form error text, so surfacing it leaks nothing.
///
/// Restricted to outcomes that denote a problem. `Unfinished` is excluded: it
/// is the normal state of work still in flight when the snapshot was taken,
/// and including it would bury real failures. `PossiblyDispatched` is kept
/// because an ambiguous submission is precisely what an operator must see.
pub fn failure_lines(observability: &OperationObservability) -> Vec<String> {
    observability
        .records
        .iter()
        .filter(|record| {
            matches!(
                record.outcome,
                ObservationOutcome::Failed
                    | ObservationOutcome::Rejected
                    | ObservationOutcome::PossiblyDispatched
            )
        })
        .map(|record| {
            let mut line = record.stage.to_string();
            if let Some(bundle) = record.attribution.bundle_index {
                line.push_str(&format!(" bundle={bundle}"));
            }
            if let Some(proposal) = record.attribution.proposal_id {
                line.push_str(&format!(" proposal={proposal}"));
            }
            if let Some(share) = record.attribution.share_index {
                line.push_str(&format!(" share={share}"));
            }
            line.push_str(&format!(
                ": {} error_kind={}",
                record.outcome,
                record.error_kind.as_deref().unwrap_or("-")
            ));
            if let Some(status) = record.http_status {
                line.push_str(&format!(" http_status={status}"));
            }
            if let Some(endpoint) = record.endpoint_index {
                line.push_str(&format!(" endpoint={endpoint}"));
            }
            if let Some(attempt) = record.attempt {
                line.push_str(&format!(" attempt={attempt}"));
            }
            line.push_str(&format!(" elapsed_us={}", record.elapsed_us));
            line
        })
        .collect()
}

/// Unwraps an SDK [`OperationReport`], reporting its snapshot when one came back.
///
/// `context` names the Vizor path that asked; the SDK's own operation name is
/// already inside the snapshot. The snapshot is queued before the caller applies `?`; exporting and
/// rendering happen on a bounded diagnostic worker, never on the voting
/// completion path. Domain results are returned unchanged even if export fails.
pub fn report<T>(context: &str, report: OperationReport<T>) -> T {
    let (result, observability) = report.into_parts();
    if let Some(observability) = observability {
        // Diagnostics must never hold up vote completion. A bounded worker
        // limits retained snapshots when disk or a consumer is unusually slow.
        let job = ExportJob {
            context: context.to_owned(),
            observability,
        };
        match exporter().as_ref() {
            Some(exporter) => {
                if exporter.submit(job).is_err() {
                    log::warn!("[VOTING_OBS] diagnostic export queue full or unavailable; snapshot dropped");
                }
            }
            None => log::warn!("[VOTING_OBS] diagnostic exporter unavailable; snapshot dropped"),
        }
    }
    result
}

struct ExportJob {
    context: String,
    observability: OperationObservability,
}

/// One process-lifetime worker; dropping a test worker closes its queue and
/// joins it. No wallet database or secure-storage writes occur on this worker.
struct ReportExporter {
    sender: Option<std::sync::mpsc::SyncSender<ExportJob>>,
    worker: Option<std::thread::JoinHandle<()>>,
}

impl ReportExporter {
    fn start(process: impl Fn(ExportJob) + Send + 'static) -> std::io::Result<Self> {
        let (sender, receiver) = std::sync::mpsc::sync_channel(4);
        let worker = std::thread::Builder::new()
            .name("voting-diagnostics".into())
            .spawn(move || {
                while let Ok(job) = receiver.recv() {
                    process(job);
                }
            })?;
        Ok(Self {
            sender: Some(sender),
            worker: Some(worker),
        })
    }

    fn submit(&self, job: ExportJob) -> Result<(), std::sync::mpsc::TrySendError<ExportJob>> {
        self.sender
            .as_ref()
            .expect("exporter is alive")
            .try_send(job)
    }
}

impl Drop for ReportExporter {
    fn drop(&mut self) {
        self.sender.take();
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

fn exporter() -> &'static Option<ReportExporter> {
    static EXPORTER: std::sync::OnceLock<Option<ReportExporter>> = std::sync::OnceLock::new();
    EXPORTER.get_or_init(|| ReportExporter::start(export_snapshot).ok())
}

fn export_snapshot(job: ExportJob) {
    let context = job.context.as_str();
    let observability = job.observability;
    let directory = std::env::temp_dir().join("vizor-voting-observability");
    match save_snapshot(&directory, &observability) {
        Ok(path) => log::info!("[VOTING_OBS] {context}: report={}", path.display()),
        Err(error) => log::warn!("[VOTING_OBS] {context}: could not save report: {error}"),
    }
    // One record per rendered line, not one record for the whole report.
    // os_log truncates a single message at ~1018 characters with a `<…>`
    // marker, and the renderer sorts summaries by stage name, so a long
    // report loses whichever stages sort last — `vote::*` before anything
    // else. Per-line records keep every stage. The Dart stream has no such
    // limit and still receives the report as one block.
    for line in observability.to_string().lines() {
        log::info!("[VOTING_OBS] {context}: {line}");
    }
    // Warn level so a failure stands out against the summary rows, and
    // survives any future tightening of the log filter above Info.
    for line in failure_lines(&observability) {
        log::warn!("[VOTING_OBS] {context}: FAILED {line}");
    }
    emit(context, &observability);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn export_job() -> ExportJob {
        ExportJob {
            context: "test".into(),
            observability: serde_json::from_value(serde_json::json!({
                "operation": "test", "started_at_unix_us": 123, "round_id": null,
                "elapsed_us": 42, "outcome": "succeeded", "records": [], "summaries": [],
                "records_dropped": 0, "summary_updates_dropped": 0, "active_stages_dropped": 0
            }))
            .unwrap(),
        }
    }

    #[test]
    fn slow_export_is_bounded_and_does_not_block_submission() {
        let (entered_tx, entered_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let (finished_tx, finished_rx) = std::sync::mpsc::channel();
        let first = std::cell::Cell::new(true);
        let exporter = ReportExporter::start(move |_| {
            if first.replace(false) {
                entered_tx.send(()).unwrap();
                release_rx.recv().unwrap();
            }
            finished_tx.send(()).unwrap();
        })
        .unwrap();
        assert!(exporter.submit(export_job()).is_ok());
        entered_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .unwrap();
        // The worker is held: all of these calls must return without waiting.
        for _ in 0..4 {
            assert!(exporter.submit(export_job()).is_ok());
        }
        let full = matches!(
            exporter.submit(export_job()),
            Err(std::sync::mpsc::TrySendError::Full(_))
        );
        release_tx.send(()).unwrap();
        drop(exporter); // closes the queue, drains admitted reports and joins
        assert!(full);
        assert_eq!(finished_rx.iter().count(), 5);
    }

    #[test]
    fn large_snapshot_round_trips_through_buffered_export() {
        let mut snapshot = export_job().observability;
        let record: zcash_voting::ObservationRecord = serde_json::from_value(serde_json::json!({
            "id": 0, "parent_id": null, "stage": "helper.http.wake_to_poll",
            "attribution": {"bundle_index": 2, "proposal_id": 1, "share_index": 0},
            "started_after_us": 0, "elapsed_us": 100, "outcome": "succeeded",
            "error_kind": null, "http_status": null, "endpoint_index": 0, "attempt": 1
        }))
        .unwrap();
        snapshot.records = vec![record; 32000];
        let directory = tempfile::tempdir().unwrap();
        let started = std::time::Instant::now();
        let path = save_snapshot(directory.path(), &snapshot).unwrap();
        eprintln!("buffered 32000-record export: {:?}", started.elapsed());
        let saved: OperationObservability =
            serde_json::from_reader(std::io::BufReader::new(std::fs::File::open(&path).unwrap()))
                .unwrap();
        assert!(!path.with_extension("json.partial").exists());
        assert_eq!(saved, snapshot);
    }

    #[test]
    fn saved_snapshot_preserves_detailed_timing_and_uses_unique_files() {
        let directory = tempfile::tempdir().unwrap();
        let snapshot: OperationObservability = serde_json::from_value(serde_json::json!({
            "operation": "test", "started_at_unix_us": 123, "round_id": null,
            "elapsed_us": 42, "outcome": "failed", "records": [], "summaries": [],
            "records_dropped": 0, "summary_updates_dropped": 0, "active_stages_dropped": 0
        }))
        .unwrap();
        let first = save_snapshot(directory.path(), &snapshot).unwrap();
        let second = save_snapshot(directory.path(), &snapshot).unwrap();
        assert_ne!(first, second);
        let saved: OperationObservability =
            serde_json::from_slice(&std::fs::read(&first).unwrap()).unwrap();
        assert_eq!(saved, snapshot);
        assert!(save_snapshot(&first, &snapshot).is_err());
    }

    /// Options are what every call site passes, so they must follow the switch
    /// rather than being decided independently anywhere.
    #[test]
    fn options_follow_the_single_switch() {
        assert_eq!(options().is_some(), VOTING_OBSERVABILITY_ENABLED);
    }

    /// The result must survive the unwrap untouched, including on the error
    /// path — the one these reports exist to explain.
    ///
    /// The observer hand-over is deliberately not covered: the SDK's
    /// `OperationObservability` is `#[non_exhaustive]` with no constructor, so
    /// a host cannot build one to emit. Restoring that test needs a fixture
    /// constructor from the SDK's `test-fixtures` feature.
    #[test]
    fn report_returns_the_result_unchanged() {
        let ok = OperationReport {
            result: Ok::<u32, &str>(7),
            observability: None,
        };
        assert_eq!(report("test", ok), Ok(7));

        let failed = OperationReport {
            result: Err::<u32, &str>("boom"),
            observability: None,
        };
        assert_eq!(report("test", failed), Err("boom"));
    }
}
