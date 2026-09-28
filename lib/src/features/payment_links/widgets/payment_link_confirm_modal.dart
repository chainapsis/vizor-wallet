import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';

/// Desktop pane modal that asks for one confirmation before an action.
class PaymentLinkConfirmModal extends StatelessWidget {
  const PaymentLinkConfirmModal({
    required this.iconName,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
    this.supporting,
    this.confirmKey,
    this.cancelKey,
    super.key,
  });

  final String iconName;
  final String title;
  final String body;
  final String? supporting;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final supporting = this.supporting;

    return AppPaneModalOverlay(
      borderRadius: BorderRadius.circular(AppDesktopSidebarSurface.glassRadius),
      onDismiss: onCancel,
      child: Container(
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PaymentLinkModalIcon(iconName),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    body,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  if (supporting != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      supporting,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: confirmKey,
              onPressed: onConfirm,
              minWidth: 280,
              child: Text(confirmLabel),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              key: cancelKey,
              onPressed: onCancel,
              variant: AppButtonVariant.ghost,
              minWidth: 280,
              child: Text(cancelLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon in a subtle circle that leads a gift card modal title.
class PaymentLinkModalIcon extends StatelessWidget {
  const PaymentLinkModalIcon(this.iconName, {super.key});

  final String iconName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          iconName,
          size: AppIconSize.medium,
          color: context.colors.icon.regular,
        ),
      ),
    );
  }
}
