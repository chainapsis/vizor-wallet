import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Ongoing work is a status, not a disabled action.
class LedgerProgressStatus extends StatelessWidget {
  const LedgerProgressStatus({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: context.colors.background.neutralSubtleOpacity,
            ),
          ),
        ),
        child: Row(
          children: [
            AppIcon(
              AppIcons.loader,
              size: 20,
              color: context.colors.icon.regular,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
