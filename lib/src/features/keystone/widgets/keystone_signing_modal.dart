import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal_card.dart'
    show AppModalActions, appModalShadow;
import 'keystone_pczt_qr_stage.dart';

enum KeystoneSigningModalPhase { preparing, ready, failed }

const _desktopPcztQrSize = 264.0;

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
      // Figma: 24 top / 16 sides / 16 bottom (render-measured).
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appModalShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
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
                  size: _desktopPcztQrSize,
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
                if (phase == KeystoneSigningModalPhase.ready &&
                    urParts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    onPressed: () =>
                        showKeystoneFullscreenQr(context, urParts: urParts),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.mediumLarge,
                    minWidth: 280,
                    child: const Text('Full screen QR'),
                  ),
                ],
              ],
            ),
          ),
          if (primaryLabel != null && secondaryLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            // Figma: the shared 36px modal button set — ghost cancel left,
            // primary action right, equal widths.
            AppModalActions(
              onCancel: onSecondary,
              cancelLabel: secondaryLabel,
              actionLabel: primaryLabel,
              onAction: onPrimary,
            ),
          ] else if (primaryLabel != null || secondaryLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              onPressed: primaryLabel != null ? onPrimary : onSecondary,
              variant: primaryLabel != null
                  ? AppButtonVariant.primary
                  : AppButtonVariant.ghost,
              size: AppButtonSize.mediumLarge,
              minWidth: 280,
              child: Text(primaryLabel ?? secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
