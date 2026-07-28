import 'package:flutter/material.dart' show Dialog;
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../rust/api/sync.dart' as rust_sync;

/// Whether an active migration still uses the legacy three-hour spacing that
/// the user can replace with the shorter policy.
bool canShortenIronwoodMigrationTiming(rust_sync.MigrationStatus status) =>
    status.activeRunId != null && status.scheduleMeanDelayBlocks == 144;

/// Confirmation shown before Vizor pauses delivery and redraws the remaining
/// migration transfer times.
class IronwoodMigrationRetimeDialog extends StatelessWidget {
  const IronwoodMigrationRetimeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Use shorter timing?',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Vizor will pause automatic migration and redraw the '
                  'remaining transfer times with a 90-minute mean and '
                  '12-hour maximum. Transfers already submitted stay '
                  'unchanged. A transfer that moves into a new expiry window '
                  'will need a fresh signature.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  key: const ValueKey(
                    'ironwood_migration_confirm_shorter_timing',
                  ),
                  expand: true,
                  constrainContent: true,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Use shorter timing'),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppButton(
                  expand: true,
                  constrainContent: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Keep current timing'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
