import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_confirm_modal.dart';

const _title = 'This gift card may take a while';
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
    return PaymentLinkConfirmModal(
      iconName: AppIcons.warning,
      title: _title,
      body: _body,
      supporting: _supporting,
      confirmLabel: 'Check gift card',
      cancelLabel: 'Go back',
      onConfirm: onConfirm,
      onCancel: onCancel,
      confirmKey: const ValueKey('payment_link_long_sync_confirm_button'),
      cancelKey: const ValueKey('payment_link_long_sync_cancel_button'),
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
      leading: const PaymentLinkModalIcon(AppIcons.warning),
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
            child: const Text('Check gift card'),
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
