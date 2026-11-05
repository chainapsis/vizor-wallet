import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_confirm_modal.dart';
import '../../../core/l10n/l10n.dart';

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
      title: context.l10n.paymentLinkLongSyncTitle,
      body: context.l10n.paymentLinkLongSyncBody,
      supporting: context.l10n.paymentLinkLongSyncSupporting,
      confirmLabel: context.l10n.paymentLinkLongSyncConfirm,
      cancelLabel: context.l10n.commonGoBack,
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
      title: context.l10n.paymentLinkLongSyncTitle,
      titleMaxLines: 2,
      leading: const PaymentLinkModalIcon(AppIcons.warning),
      onClose: onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.paymentLinkLongSyncBody,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.paymentLinkLongSyncSupporting,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('payment_link_long_sync_sheet_confirm_button'),
            expand: true,
            onPressed: onConfirm,
            child: Text(context.l10n.paymentLinkLongSyncConfirm),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('payment_link_long_sync_sheet_cancel_button'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: onCancel,
            child: Text(context.l10n.commonGoBack),
          ),
        ],
      ),
    );
  }
}
