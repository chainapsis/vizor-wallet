import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../shared/account_discovery_incomplete_copy.dart';

/// Warns that account discovery stopped before checking every account, before
/// anything is imported. Resolves `true` only when the user explicitly
/// continues with the available accounts.
Future<bool> showMobileImportAccountDiscoveryIncompleteSheet({
  required BuildContext context,
  required rust_wallet.SoftwareAccountDiscoveryStatus status,
}) async {
  final confirmed = await showAppMobileSheet<bool>(
    context: context,
    builder: (sheetContext) => MobileImportAccountDiscoveryIncompleteSheet(
      status: status,
      onContinue: () => Navigator.of(sheetContext).pop(true),
      onCancel: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  return confirmed == true;
}

class MobileImportAccountDiscoveryIncompleteSheet extends StatelessWidget {
  const MobileImportAccountDiscoveryIncompleteSheet({
    required this.status,
    required this.onContinue,
    required this.onCancel,
    super.key,
  });

  final rust_wallet.SoftwareAccountDiscoveryStatus status;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MobileModalScaffold(
      key: const ValueKey('mobile_import_account_discovery_incomplete_sheet'),
      title: AccountDiscoveryIncompleteCopy.title,
      titleMaxLines: 2,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colors.background.neutralSubtleOpacity,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AppIcon(
            AppIcons.warning,
            size: AppIconSize.medium,
            color: colors.icon.regular,
          ),
        ),
      ),
      onClose: onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AccountDiscoveryIncompleteCopy.reason(status),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AccountDiscoveryIncompleteCopy.notEvidence,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey(
              'mobile_import_account_discovery_incomplete_continue',
            ),
            expand: true,
            onPressed: onContinue,
            child: const Text(AccountDiscoveryIncompleteCopy.continueLabel),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey(
              'mobile_import_account_discovery_incomplete_back',
            ),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: onCancel,
            child: const Text(AccountDiscoveryIncompleteCopy.backLabel),
          ),
        ],
      ),
    );
  }
}
