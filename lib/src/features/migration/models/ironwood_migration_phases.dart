const kIronwoodMigrationReadyPhase = 'ready_to_prepare';
const kIronwoodMigrationAwaitingPreparationPhase = 'awaiting_preparation';

/// Unreachable phase, kept only so a durable run can never be orphaned by an
/// unrecognized string.
///
/// Verified 2026-07-30 against `rust/src/wallet/sync/migration.rs`: every
/// production use of `PHASE_AWAITING_DENOMINATION_SIGNATURE` is a read or a
/// `matches!` / `WHERE phase IN (...)` predicate. No `INSERT` value, no
/// `UPDATE ... SET phase`, and no `mark_run_phase` call ever supplies it, in
/// this revision or in any commit since the constant was introduced
/// (`811b992b3`, where it was already read-only). A hardware denomination
/// draft is stored as `awaiting_preparation` instead, which is why the mobile
/// status screen offers the Keystone CTA from that phase.
///
/// Treat any UI that only triggers on this phase as dead code. Do not build
/// new behavior behind it.
const kIronwoodMigrationAwaitingDenominationSignaturePhase =
    'awaiting_denomination_signature';
const kIronwoodMigrationNoOrchardFundsPhase = 'no_orchard_funds';
const kIronwoodMigrationWaitingForSpendableOrchardPhase =
    'waiting_for_spendable_orchard';
const kIronwoodMigrationWaitingForIronwoodSpendabilityPhase =
    'waiting_for_ironwood_spendability';
const kIronwoodMigrationWaitingDenomConfirmationsPhase =
    'waiting_denom_confirmations';
const kIronwoodMigrationReadyToMigratePhase = 'ready_to_migrate';
const kIronwoodMigrationBroadcastScheduledPhase = 'broadcast_scheduled';
const kIronwoodMigrationBroadcastingPhase = 'broadcasting';
const kIronwoodMigrationWaitingConfirmationsPhase =
    'waiting_migration_confirmations';
const kIronwoodMigrationCompletePhase = 'complete';

/// Unreachable phase, kept only so a durable run can never be orphaned by an
/// unrecognized string.
///
/// Verified 2026-07-30 against `rust/src/wallet/sync/migration.rs`: `PHASE_PAUSED`
/// appears in exactly three production sites, all reads — the anchor-retention
/// `WHERE phase IN (...)` filter, the `matches!` that decides which retained
/// anchors stay locked, and the background-migration `decide()` match arm. It
/// has never been written in any commit that introduced or touched it
/// (`127be72cd`, `7eebef344`, `1cc4e94b9`, `f8946699a`); the only writes live in
/// `#[cfg(test)]` fixtures. A background task that stops mid-run leaves the
/// phase untouched instead of pausing it.
///
/// Treat any UI that only triggers on this phase — a Resume button, a paused
/// headline — as dead code. Do not build new behavior behind it.
const kIronwoodMigrationPausedPhase = 'paused';
const kIronwoodMigrationFailedRecoverablePhase = 'failed_recoverable';
const kIronwoodMigrationFailedTerminalPhase = 'failed_terminal';
const kIronwoodMigrationAbandonedPhase = 'abandoned';
const kIronwoodMigrationReleaseNotesUrl =
    'https://tachyon.z.cash/blog/auditing-orchard-supply/';
const kIronwoodMigrationLateGraceBlocks = 96;

const kIronwoodMigrationStartPhases = {
  kIronwoodMigrationWaitingForSpendableOrchardPhase,
  kIronwoodMigrationReadyPhase,
};

/// Phases that mean "a durable run still exists, keep it reachable".
///
/// Deliberately over-inclusive. `awaiting_denomination_signature` and `paused`
/// are unreachable (see their declarations), but every consumer of this set is a
/// fail-safe gate — routing a run to its status screen, holding the privacy
/// lock, blocking account deletion, keeping the announcement live. Dropping an
/// unreachable phase here would convert a hypothetical Rust change into a
/// user-visible dead end (bounced to home, lock released mid-run), so the
/// entries stay. Only the phase-specific *presentation* branches are dead code.
const kIronwoodMigrationContinuePhases = {
  kIronwoodMigrationAwaitingPreparationPhase,
  kIronwoodMigrationAwaitingDenominationSignaturePhase,
  kIronwoodMigrationWaitingDenomConfirmationsPhase,
  kIronwoodMigrationReadyToMigratePhase,
  kIronwoodMigrationBroadcastScheduledPhase,
  kIronwoodMigrationBroadcastingPhase,
  kIronwoodMigrationWaitingConfirmationsPhase,
  kIronwoodMigrationPausedPhase,
  kIronwoodMigrationFailedRecoverablePhase,
};

/// Phases where the wallet is still shaping the balance into the parts a
/// migration will move. `ready_to_migrate` is deliberately absent: preparation
/// has finished by then, and the run is waiting for its next proof window, so
/// calling it preparation contradicts the batch progress the status screen
/// shows for the same run.
///
/// `awaiting_denomination_signature` is unreachable and kept for the same
/// fail-safe reason as in [kIronwoodMigrationContinuePhases].
const kIronwoodMigrationPreparationPhases = {
  kIronwoodMigrationAwaitingPreparationPhase,
  kIronwoodMigrationAwaitingDenominationSignaturePhase,
  kIronwoodMigrationWaitingDenomConfirmationsPhase,
};

bool isIronwoodMigrationInProgressPhase(String phase) {
  return kIronwoodMigrationContinuePhases.contains(phase);
}

bool isIronwoodMigrationPreparingPhase(String? phase) {
  return kIronwoodMigrationPreparationPhases.contains(phase);
}
