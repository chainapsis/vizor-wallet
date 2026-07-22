const kIronwoodMigrationReadyPhase = 'ready_to_prepare';
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
  kIronwoodMigrationWaitingDenomConfirmationsPhase,
  kIronwoodMigrationReadyToMigratePhase,
  kIronwoodMigrationBroadcastScheduledPhase,
  kIronwoodMigrationBroadcastingPhase,
  kIronwoodMigrationWaitingConfirmationsPhase,
  kIronwoodMigrationPausedPhase,
  kIronwoodMigrationFailedRecoverablePhase,
};

bool isIronwoodMigrationInProgressPhase(String phase) {
  return kIronwoodMigrationContinuePhases.contains(phase);
}
