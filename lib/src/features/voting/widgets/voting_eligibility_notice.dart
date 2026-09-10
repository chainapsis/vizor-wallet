import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../voting_eligibility_explanation.dart';

/// Variation A: a persistent on-page explainer for ineligible funds.
///
/// Shows the snapshot cutoff first, then the exclusion reason, so the
/// reported "I moved after the snapshot but I was in Ironwood" case is
/// visible without opening a dialog.
class VotingEligibilityInlineNotice extends StatelessWidget {
  const VotingEligibilityInlineNotice({
    required this.explanation,
    super.key,
  });

  final VotingEligibilityExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final blockLabel = explanation.snapshotBlockLabel;
    return DecoratedBox(
      key: const ValueKey('voting_eligibility_inline_notice'),
      decoration: BoxDecoration(
        color: colors.background.utilityDestructiveSubtle,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(
                  AppIcons.warning,
                  size: 20,
                  color: colors.text.destructive,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    explanation.reasonTitle,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Snapshot',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              explanation.snapshotValue,
              key: const ValueKey('voting_eligibility_snapshot_value'),
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (blockLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                blockLabel,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            Text(
              explanation.reasonBody,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Variation B: labeled snapshot + reason rows inside the ineligible sheet.
class VotingEligibilitySheetBody extends StatelessWidget {
  const VotingEligibilitySheetBody({
    required this.explanation,
    super.key,
  });

  final VotingEligibilityExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final blockLabel = explanation.snapshotBlockLabel;
    return Column(
      key: const ValueKey('voting_eligibility_sheet_body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetFact(
          label: 'Snapshot',
          value: explanation.snapshotValue,
          detail: blockLabel,
        ),
        const SizedBox(height: AppSpacing.sm),
        Divider(height: 1, color: colors.border.subtle),
        const SizedBox(height: AppSpacing.sm),
        _SheetFact(
          label: 'Why these funds do not count',
          value: explanation.reasonTitle,
          detail: explanation.reasonBody,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          kVotingEligibilityGuidance,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
}

class _SheetFact extends StatelessWidget {
  const _SheetFact({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detail = this.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: AppTypography.bodyLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            detail,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ],
      ],
    );
  }
}
