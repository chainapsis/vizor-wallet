use std::{
    panic,
    sync::atomic::{AtomicBool, Ordering},
};

use flutter_rust_bridge::frb;

use crate::{
    frb_generated::StreamSink,
    wallet::{keys, spendability_pir},
};

static STARTUP_PIR_RUNNING: AtomicBool = AtomicBool::new(false);
static STARTUP_PIR_CANCEL: AtomicBool = AtomicBool::new(false);

pub struct ApiPirProgressEvent {
    pub phase: String,
    pub completed: u32,
    pub total: u32,
    pub witnesses_inserted: u32,
    pub skipped_reason: Option<String>,
}

pub fn run_startup_pir(
    db_path: String,
    network: String,
    spend_server_url_override: Option<String>,
    witness_server_url_override: Option<String>,
    sink: StreamSink<ApiPirProgressEvent>,
) -> Result<(), String> {
    if STARTUP_PIR_RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err("Startup PIR already running".to_string());
    }
    STARTUP_PIR_CANCEL.store(false, Ordering::Relaxed);

    let result = catch(panic::AssertUnwindSafe(|| {
        let network = keys::parse_network(&network)?;
        let urls = spendability_pir::server_urls_for(
            network,
            spend_server_url_override.as_deref(),
            witness_server_url_override.as_deref(),
        );
        log::info!(
            "PIR: starting startup spendability pass (spend={}, witness={})",
            urls.spend_url,
            urls.witness_url
        );

        let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {e}"))?;
        let outcome = rt.block_on(spendability_pir::run_startup_pir(
            &db_path,
            network,
            &urls,
            &STARTUP_PIR_CANCEL,
            |progress| {
                if sink
                    .add(ApiPirProgressEvent {
                        phase: phase_name(progress.phase).to_string(),
                        completed: progress.completed,
                        total: progress.total,
                        witnesses_inserted: progress.witnesses_inserted,
                        skipped_reason: progress.skipped_reason,
                    })
                    .is_err()
                {
                    log::warn!("PIR: StreamSink closed, progress not delivered");
                }
            },
        ));

        match outcome.skipped_reason() {
            Some(reason) => log::info!("PIR: startup pass skipped ({reason})"),
            None => log::info!(
                "PIR: startup pass complete, inserted {} witnesses",
                outcome.witnesses_inserted()
            ),
        }
        Ok(())
    }));

    STARTUP_PIR_RUNNING.store(false, Ordering::SeqCst);
    result
}

#[frb(sync)]
pub fn cancel_startup_pir() {
    STARTUP_PIR_CANCEL.store(true, Ordering::Relaxed);
}

#[frb(sync)]
pub fn is_startup_pir_running() -> bool {
    STARTUP_PIR_RUNNING.load(Ordering::SeqCst)
}

fn phase_name(phase: spendability_pir::PirProgressPhase) -> &'static str {
    match phase {
        spendability_pir::PirProgressPhase::Nullifier => "nullifier",
        spendability_pir::PirProgressPhase::Witness => "witness",
        spendability_pir::PirProgressPhase::Done => "done",
        spendability_pir::PirProgressPhase::Skipped => "skipped",
    }
}

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(format!("Rust panic: {msg}"))
        }
    }
}
