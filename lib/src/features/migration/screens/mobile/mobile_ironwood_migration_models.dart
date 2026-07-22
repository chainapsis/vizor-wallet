part of 'mobile_ironwood_migration_flow_screen.dart';

enum MobileIronwoodMigrationStep {
  intro,
  howItWorks,
  options,
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

const _migrationProgress = 60 / 196;
const _migrationAnalysisPreviewProgress = 72 / 196;
const _migrationAnalysisProgressDuration = Duration(milliseconds: 2745);
const _migrationAnalysisCompletionDuration = Duration(milliseconds: 575);
const _migrationAnalysisTransitionDuration = Duration(milliseconds: 420);
const _migrationAnalysisEaseOut = Cubic(0.23, 1, 0.32, 1);

Future<void> _showMobileMigrationTimingSheet(BuildContext context) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.base,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'About migration timing',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Vizor spaces private transfers across privacy checkpoints. '
              'The estimate updates as blocks arrive and transactions are '
              'confirmed.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}

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
