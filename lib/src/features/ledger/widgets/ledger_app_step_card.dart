import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

enum LedgerAppStepState { pending, active, done, failed }

/// The device app line of the signing modal: the Zcash app has to be open
/// before the device can show anything to approve, so this card says where
/// that stands while the status card below carries the request itself.
class LedgerAppStepCard extends StatelessWidget {
  const LedgerAppStepCard({
    required this.appName,
    required this.hint,
    required this.state,
    super.key,
  });

  final String appName;
  final String hint;
  final LedgerAppStepState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failed = state == LedgerAppStepState.failed;
    final pending = state == LedgerAppStepState.pending;
    final trailing = switch (state) {
      LedgerAppStepState.active => AppIcon(
        AppIcons.loader,
        size: 16,
        color: colors.icon.regular,
        animated: true,
      ),
      LedgerAppStepState.done => AppIcon(
        AppIcons.check,
        size: 16,
        color: colors.icon.success,
      ),
      LedgerAppStepState.failed => AppIcon(
        AppIcons.warningCircle,
        size: 18,
        color: colors.icon.destructive,
      ),
      LedgerAppStepState.pending => null,
    };
    return Semantics(
      label: '$appName app: $hint',
      child: ExcludeSemantics(
        child: Container(
          key: ValueKey('ledger_signing_step_app_${state.name}'),
          padding: const EdgeInsets.all(AppSpacing.s),
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            border: Border.all(
              color: state == LedgerAppStepState.active
                  ? colors.border.medium
                  : colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.background.base,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  border: Border.all(color: colors.border.subtle),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.zcash,
                    size: 22,
                    color: pending ? colors.icon.muted : colors.icon.regular,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$appName app',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: failed
                            ? colors.text.destructive
                            : pending
                            ? colors.text.muted
                            : colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: failed
                            ? colors.text.destructive
                            : pending
                            ? colors.text.muted
                            : colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.xs),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
