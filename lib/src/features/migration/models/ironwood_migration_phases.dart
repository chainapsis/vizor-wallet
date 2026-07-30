const kIronwoodMigrationReadyPhase = 'ready_to_prepare';
const kIronwoodMigrationAwaitingPreparationPhase = 'awaiting_preparation';
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
