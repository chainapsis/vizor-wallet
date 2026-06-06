use std::sync::{atomic::AtomicBool, Arc};

use futures::StreamExt;
use spend_client::SpendClient;
use witness_client::WitnessClient;

use crate::wallet::{
    db::{
        open_wallet_db_for_read_with_timeout, open_wallet_db_with_timeout,
        with_wallet_db_write_lock, READ_DB_BUSY_TIMEOUT, WALLET_DB_BUSY_TIMEOUT,
    },
    network::WalletNetwork,
};

#[derive(Debug, Clone)]
pub struct PirServerUrls {
    pub spend_url: String,
    pub witness_url: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PirProgressPhase {
    Nullifier,
    Witness,
    Done,
    Skipped,
}

#[derive(Debug, Clone)]
pub struct PirProgress {
    pub phase: PirProgressPhase,
    pub completed: u32,
    pub total: u32,
    pub witnesses_inserted: u32,
    pub skipped_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PirSkipReason {
    Cancelled,
    NoNotes,
    AnySpent,
    ServerUnavailable,
    DbError,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PirOutcome {
    Completed { witnesses_inserted: u32 },
    Skipped { reason: PirSkipReason },
}

impl PirSkipReason {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Cancelled => "cancelled",
            Self::NoNotes => "no_notes",
            Self::AnySpent => "any_spent",
            Self::ServerUnavailable => "server_unavailable",
            Self::DbError => "db_error",
        }
    }
}

impl PirOutcome {
    pub fn witnesses_inserted(&self) -> u32 {
        match self {
            Self::Completed { witnesses_inserted } => *witnesses_inserted,
            Self::Skipped { .. } => 0,
        }
    }

    pub fn skipped_reason(&self) -> Option<&'static str> {
        match self {
            Self::Completed { .. } => None,
            Self::Skipped { reason } => Some(reason.as_str()),
        }
    }
}

pub fn server_urls_for(
    network: WalletNetwork,
    spend_override: Option<&str>,
    witness_override: Option<&str>,
) -> PirServerUrls {
    let (default_spend, default_witness) = match network {
        WalletNetwork::Main => (
            "https://159-65-205-52.sslip.io/nullifier",
            "https://159-65-205-52.sslip.io/witness",
        ),
        WalletNetwork::Test => (
            "https://pir-test.valargroup.com/nullifier",
            "https://pir-test.valargroup.com/witness",
        ),
        WalletNetwork::Regtest => (
            "http://localhost:8080/nullifier",
            "http://localhost:8080/witness",
        ),
    };

    PirServerUrls {
        spend_url: non_empty_override(spend_override)
            .unwrap_or(default_spend)
            .to_string(),
        witness_url: non_empty_override(witness_override)
            .unwrap_or(default_witness)
            .to_string(),
    }
}

fn non_empty_override(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

pub async fn run_startup_pir<F>(
    db_path: &str,
    network: WalletNetwork,
    server_urls: &PirServerUrls,
    cancel: &AtomicBool,
    mut on_progress: F,
) -> PirOutcome
where
    F: FnMut(PirProgress),
{
    let notes = match open_wallet_db_for_read_with_timeout(db_path, network, READ_DB_BUSY_TIMEOUT)
        .and_then(|db| {
            db.get_unspent_orchard_notes_for_pir()
                .map_err(|e| format!("failed to read Orchard nullifiers for PIR: {e}"))
        }) {
        Ok(notes) => notes,
        Err(e) => {
            log::warn!("PIR: startup gate read failed: {e}");
            return emit_skipped(&mut on_progress, PirSkipReason::DbError);
        }
    };

    if notes.is_empty() {
        log::info!("PIR: no unspent Orchard notes with nullifiers; skipping");
        return emit_skipped(&mut on_progress, PirSkipReason::NoNotes);
    }

    if cancel.load(std::sync::atomic::Ordering::Relaxed) {
        return emit_skipped(&mut on_progress, PirSkipReason::Cancelled);
    }

    let spend_client = match SpendClient::connect(&server_urls.spend_url).await {
        Ok(client) => client,
        Err(e) => {
            log::warn!("PIR: spend server unavailable: {e}");
            return emit_skipped(&mut on_progress, PirSkipReason::ServerUnavailable);
        }
    };
    let spend_client = Arc::new(spend_client);

    const NULLIFIER_CHECK_CONCURRENCY: usize = 8;
    let total = notes.len() as u32;
    let mut completed_nullifier_checks = 0u32;
    let mut completed_witness_queries = 0u32;
    let mut witnesses_inserted = 0u32;
    let db_path = db_path.to_string();
    let witness_url = server_urls.witness_url.clone();
    let witness_client = Arc::new(tokio::sync::OnceCell::<WitnessClient>::new());

    enum NotePipelineResult {
        Spent,
        WitnessNotNeeded,
        WitnessQueryFailed {
            note_id: i64,
            position: u64,
            error: String,
        },
        WitnessFetched {
            note_id: i64,
            position: u64,
            siblings: [[u8; 32]; 32],
            anchor_height: u64,
            anchor_root: [u8; 32],
        },
    }

    let mut note_checks = futures::stream::iter(notes.iter())
        .map(|note| {
            let spend_client = Arc::clone(&spend_client);
            let witness_client = Arc::clone(&witness_client);
            let db_path = db_path.clone();
            let witness_url = witness_url.clone();
            async move {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                return Err::<NotePipelineResult, PirSkipReason>(PirSkipReason::Cancelled);
            }

            let spent = spend_client
                .is_spent(&note.nf)
                .await
                .map_err(|e| {
                    log::warn!("PIR: nullifier query failed: {e}");
                    PirSkipReason::ServerUnavailable
                })?
                .is_some();
            if spent {
                return Ok(NotePipelineResult::Spent);
            }

            let note_id = note.id;
            let maybe_position = tokio::task::spawn_blocking(move || {
                open_wallet_db_for_read_with_timeout(&db_path, network, READ_DB_BUSY_TIMEOUT)
                    .and_then(|db| {
                        db.note_needs_pir_witness(note_id).map_err(|e| {
                            format!("failed to check note {note_id} PIR witness eligibility: {e}")
                        })
                    })
            })
            .await
            .map_err(|e| {
                log::warn!("PIR: witness eligibility task join failed for note {note_id}: {e}");
                PirSkipReason::DbError
            })?
            .map_err(|e| {
                log::warn!("PIR: witness eligibility read failed for note {note_id}: {e}");
                PirSkipReason::DbError
            })?;

            let position = match maybe_position {
                Some(position) => position,
                None => return Ok(NotePipelineResult::WitnessNotNeeded),
            };

            let client = witness_client
                .get_or_try_init(|| async {
                    WitnessClient::connect(&witness_url).await.map_err(|e| {
                        log::warn!("PIR: witness server unavailable: {e}");
                        PirSkipReason::ServerUnavailable
                    })
                })
                .await?;

            let witness = match client.get_witness(position).await {
                Ok(witness) => witness,
                Err(e) => {
                    return Ok(NotePipelineResult::WitnessQueryFailed {
                        note_id,
                        position,
                        error: e.to_string(),
                    });
                }
            };

            Ok(NotePipelineResult::WitnessFetched {
                note_id,
                position,
                siblings: witness.siblings,
                anchor_height: witness.anchor_height,
                anchor_root: witness.anchor_root,
            })
            }
        })
        .buffer_unordered(NULLIFIER_CHECK_CONCURRENCY);

    while let Some(result) = note_checks.next().await {
        if cancel.load(std::sync::atomic::Ordering::Relaxed) {
            return emit_skipped(&mut on_progress, PirSkipReason::Cancelled);
        }

        let result = match result {
            Ok(result) => result,
            Err(reason) => return emit_skipped(&mut on_progress, reason),
        };

        completed_nullifier_checks += 1;
        on_progress(PirProgress {
            phase: PirProgressPhase::Nullifier,
            completed: completed_nullifier_checks,
            total,
            witnesses_inserted: 0,
            skipped_reason: None,
        });

        match result {
            NotePipelineResult::Spent => {
                log::info!("PIR: at least one note was spent; skipping witness PIR");
                return emit_skipped(&mut on_progress, PirSkipReason::AnySpent);
            }
            NotePipelineResult::WitnessNotNeeded => {}
            NotePipelineResult::WitnessQueryFailed {
                note_id,
                position,
                error,
            } => {
                log::warn!(
                    "PIR: witness query skipped for note {} at position {}: {e}",
                    note_id,
                    position,
                    e = error
                );
                completed_witness_queries += 1;
                on_progress(PirProgress {
                    phase: PirProgressPhase::Witness,
                    completed: completed_witness_queries,
                    total,
                    witnesses_inserted,
                    skipped_reason: None,
                });
            }
            NotePipelineResult::WitnessFetched {
                note_id,
                position,
                siblings,
                anchor_height,
                anchor_root,
            } => {
                let inserted = with_wallet_db_write_lock("pir.insert_witness", || {
                    let db = open_wallet_db_with_timeout(&db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
                    let validation = db
                        .validate_pir_orchard_witness(
                            note_id,
                            &siblings,
                            &anchor_root,
                        )
                        .map_err(|e| format!("PIR witness validation failed: {e}"))?;
                    if !validation.witness_root_matches_anchor() {
                        return Ok::<bool, String>(false);
                    }
                    db.insert_pir_witness(note_id, &siblings, anchor_height, &anchor_root)
                        .map_err(|e| format!("PIR witness insert failed: {e}"))?;
                    Ok(true)
                });

                match inserted {
                    Ok(true) => {
                        witnesses_inserted += 1;
                    }
                    Ok(false) => {
                        log::warn!(
                            "PIR: rejected invalid witness for note {} at position {}",
                            note_id,
                            position
                        );
                    }
                    Err(e) => {
                        log::warn!(
                            "PIR: failed to validate/insert witness for note {} at position {}: {e}",
                            note_id,
                            position
                        );
                    }
                }

                completed_witness_queries += 1;
                on_progress(PirProgress {
                    phase: PirProgressPhase::Witness,
                    completed: completed_witness_queries,
                    total,
                    witnesses_inserted,
                    skipped_reason: None,
                });
            }
        };
    }

    emit_done(&mut on_progress, witnesses_inserted)
}

fn emit_skipped<F>(on_progress: &mut F, reason: PirSkipReason) -> PirOutcome
where
    F: FnMut(PirProgress),
{
    on_progress(PirProgress {
        phase: PirProgressPhase::Skipped,
        completed: 0,
        total: 0,
        witnesses_inserted: 0,
        skipped_reason: Some(reason.as_str().to_string()),
    });
    PirOutcome::Skipped { reason }
}

fn emit_done<F>(on_progress: &mut F, witnesses_inserted: u32) -> PirOutcome
where
    F: FnMut(PirProgress),
{
    on_progress(PirProgress {
        phase: PirProgressPhase::Done,
        completed: 0,
        total: 0,
        witnesses_inserted,
        skipped_reason: None,
    });
    PirOutcome::Completed { witnesses_inserted }
}
