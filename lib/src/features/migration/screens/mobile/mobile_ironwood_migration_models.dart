part of 'mobile_ironwood_migration_flow_screen.dart';

enum MobileIronwoodMigrationStep {
  intro,
  howItWorks,
  options,
  notifications,
  privateReview,
  fastReview,
  preparing,
  migrating,
}

enum MobileIronwoodMigrationReviewPreviewStage {
  analyzing,
  animatedAnalyzing,
  review,
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
  migrationBroadcasting,
  migrationComplete,
  homeAttention,
  homeAttentionModal,
  keystoneScanHelp,
}

const _migrationProgress = 60 / 196;
const _migrationAnalysisPreviewProgress = 72 / 196;
const _migrationAnalysisProgressDuration = Duration(milliseconds: 2745);
const _migrationAnalysisCompletionDuration = Duration(milliseconds: 575);
const _migrationAnalysisTransitionDuration = Duration(milliseconds: 420);
const _migrationAnalysisEaseOut = Cubic(0.23, 1, 0.32, 1);

class _MigrationAnalysisProgressStep {
  const _MigrationAnalysisProgressStep({
    required this.target,
    required this.rampMilliseconds,
    required this.pauseMilliseconds,
  });

  final double target;
  final int rampMilliseconds;
  final int pauseMilliseconds;
}

const _migrationAnalysisProgressSteps = [
  _MigrationAnalysisProgressStep(
    target: 0.15,
    rampMilliseconds: 300,
    pauseMilliseconds: 75,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.40,
    rampMilliseconds: 285,
    pauseMilliseconds: 45,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.47,
    rampMilliseconds: 165,
    pauseMilliseconds: 225,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.63,
    rampMilliseconds: 315,
    pauseMilliseconds: 90,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.71,
    rampMilliseconds: 150,
    pauseMilliseconds: 255,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.86,
    rampMilliseconds: 270,
    pauseMilliseconds: 120,
  ),
  _MigrationAnalysisProgressStep(
    target: 0.97,
    rampMilliseconds: 285,
    pauseMilliseconds: 165,
  ),
];
