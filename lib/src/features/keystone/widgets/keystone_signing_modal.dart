import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'keystone_pczt_qr_stage.dart';

enum KeystoneSigningModalPhase { preparing, ready, failed }

class KeystoneSigningModal extends StatelessWidget {
  const KeystoneSigningModal({
    required this.phase,
    required this.urParts,
    required this.error,
    required this.title,
    required this.subtitle,
    required this.instruction,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    super.key,
  });

  final KeystoneSigningModalPhase phase;
  final List<String> urParts;
  final String? error;
  final String title;
  final String subtitle;
  final String? instruction;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final instruction = this.instruction;
    final primaryLabel = this.primaryLabel;
    final secondaryLabel = this.secondaryLabel;

    return Container(
      width: 312,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.background.neutralSubtleOpacity,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.qr,
                    size: AppIconSize.medium,
                    color: colors.icon.regular,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              children: [
                KeystonePcztQrStage(
                  phase: switch (phase) {
                    KeystoneSigningModalPhase.preparing =>
                      KeystonePcztQrStagePhase.preparing,
                    KeystoneSigningModalPhase.ready =>
                      KeystonePcztQrStagePhase.ready,
                    KeystoneSigningModalPhase.failed =>
                      KeystonePcztQrStagePhase.failed,
                  },
                  urParts: urParts,
                  error: error,
                ),
                if (instruction != null && instruction.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    instruction,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (primaryLabel != null || secondaryLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            if (primaryLabel != null) ...[
              AppButton(
                onPressed: onPrimary,
                minWidth: 280,
                trailing: const AppIcon(AppIcons.chevronForward),
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null) const SizedBox(height: AppSpacing.s),
            ],
            if (secondaryLabel != null)
              AppButton(
                onPressed: onSecondary,
                variant: AppButtonVariant.ghost,
                minWidth: 280,
                child: Text(secondaryLabel),
              ),
          ],
        ],
      ),
    );
  }
}
