import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/account_provider.dart';
import '../../ledger_device_label.dart';
import '../../services/ledger_mobile_ble_service.dart';
import 'mobile_ledger_sheet_content.dart';

/// Mobile presentation of the shared operation status, independent of the
/// desktop signing card and its nested status/prompt panels.
class MobileLedgerSigningContent extends StatelessWidget {
  const MobileLedgerSigningContent({
    required this.title,
    required this.message,
    required this.status,
    required this.active,
    required this.failed,
    required this.onClose,
    required this.onAction,
    this.actionLabel,
    this.account,
    super.key,
  });
  final String title;
  final String message;
  final String status;
  final bool active;
  final bool failed;
  final AccountInfo? account;
  final String? actionLabel;
  final VoidCallback? onClose;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => MobileLedgerSheetContent(
    title: title,
    onClose: onClose,
    children: [
      MobileLedgerMessage(message),
      if (!failed && account?.ledgerDeviceId != null)
        MobileLedgerIdentity(
          ledgerDeviceLabel(
            LedgerBleDevice(
              id: account!.ledgerDeviceId!,
              name: account!.ledgerDeviceName ?? '',
              model: account!.ledgerDeviceModel ?? '',
            ),
          ),
        ),
      if (!failed) MobileLedgerStatus(status, active: active),
      if (failed && status != 'Action needed') ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          status,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: context.colors.text.accent,
          ),
        ),
      ],
      if (failed && actionLabel != null)
        MobileLedgerAction(actionLabel!, onPressed: onAction),
      if (failed && actionLabel == null && onClose == null) ...[
        const SizedBox(height: AppSpacing.sm),
        const MobileLedgerMessage('Keep Vizor open.'),
      ],
    ],
  );
}
