import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';

const _title = 'This Gift Card may take a while';
const _body =
    'Vizor needs to scan more history than usual before it can verify the '
    'balance. This is safe, but it may take a long time.';
const _supporting = 'You can go back without starting the scan.';

class PaymentLinkLongSyncWarningModal extends StatelessWidget {
  const PaymentLinkLongSyncWarningModal({
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
                _WarningIcon(color: colors.icon.regular),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _title,
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
                    _body,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _supporting,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('payment_link_long_sync_confirm_button'),
              onPressed: onConfirm,
              minWidth: 280,
              child: const Text('Check Gift Card'),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              key: const ValueKey('payment_link_long_sync_cancel_button'),
              onPressed: onCancel,
              variant: AppButtonVariant.ghost,
              minWidth: 280,
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showPaymentLinkLongSyncWarningSheet(BuildContext context) async {
  final confirmed = await showAppMobileSheet<bool>(
    context: context,
    builder: (sheetContext) => PaymentLinkLongSyncWarningSheet(
      onConfirm: () => Navigator.of(sheetContext).pop(true),
      onCancel: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  return confirmed == true;
}

class PaymentLinkLongSyncWarningSheet extends StatelessWidget {
  const PaymentLinkLongSyncWarningSheet({
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MobileModalScaffold(
      key: const ValueKey('payment_link_long_sync_warning_sheet'),
      title: _title,
      titleMaxLines: 2,
      leading: _WarningIcon(color: colors.icon.regular),
      onClose: onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _body,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _supporting,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('payment_link_long_sync_sheet_confirm_button'),
            expand: true,
            onPressed: onConfirm,
            child: const Text('Check Gift Card'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('payment_link_long_sync_sheet_cancel_button'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: onCancel,
            child: const Text('Go back'),
          ),
        ],
      ),
    );
  }
}

class _WarningIcon extends StatelessWidget {
  const _WarningIcon({required this.color});

  final Color color;

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
          AppIcons.warning,
          size: AppIconSize.medium,
          color: color,
        ),
      ),
    );
  }
}
