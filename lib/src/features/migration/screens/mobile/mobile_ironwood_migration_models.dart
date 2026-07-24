part of 'mobile_ironwood_migration_flow_screen.dart';

enum MobileIronwoodMigrationStep {
  intro,
  howItWorks,
  options,
  notifications,
  privateStart,
  fastReview,
  preparing,
  migrating,
}

/// Static-first states for reviewing the mobile migration redesign without
/// coupling Widgetbook to notification permissions, native background work,
/// wallet sync, or Rust migration state.
enum MobileIronwoodMigrationPreviewSurface {
  notificationsPrompt,
  notificationsConfirmation,
  preparationActive,
  preparationPaused,
  preparationPausedKeystone,
  preparationSyncing,
  syncing,
  preparationCompleteModal,
  migrationWaitingNotificationsOn,
  migrationWaitingNotificationsOff,
  migrationNeedsInput,
  migrationKeystoneSignAll,
  migrationBroadcasting,
  migrationComplete,
  homeAttention,
  homeAttentionModal,
  keystoneScanHelp,
}

const _migrationProgress = 60 / 196;
const _migrationAnalysisEaseOut = Cubic(0.23, 1, 0.32, 1);
