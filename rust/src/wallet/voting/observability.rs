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
    VOTING_OBSERVABILITY_ENABLED.then(ObservabilityOptions::default)
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
/// already inside the snapshot. Reporting happens before the caller applies
/// `?`, so a failed operation still describes the stages that preceded the
/// failure — the case these reports exist for.
pub fn report<T>(context: &str, report: OperationReport<T>) -> T {
    let (result, observability) = report.into_parts();
    if let Some(observability) = observability {
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
    result
}

#[cfg(test)]
mod tests {
    use super::*;

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
