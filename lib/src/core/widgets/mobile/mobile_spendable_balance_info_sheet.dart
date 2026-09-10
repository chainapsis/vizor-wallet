import 'package:flutter/widgets.dart';

import '../../layout/mobile/app_mobile_sheet.dart';
import '../../theme/app_theme.dart';
import '../app_button.dart';
import '../spendable_balance_copy.dart';

/// Bottom sheet behind the `?` next to the spendable balance on the mobile
/// amount step. Mirrors the desktop "Use Max" tooltip.
Future<void> showMobileSpendableBalanceInfoSheet(
  BuildContext context, {
  required bool ledger,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      final bodyStyle = AppTypography.bodyMedium.copyWith(
        color: colors.text.primary,
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.base,
          AppSpacing.sm,
          AppSpacing.base,
        ),
        child: Column(
          key: const ValueKey('mobile_spendable_balance_info_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Spendable balance',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$kSpendableBalanceInfoTitle $kSpendableBalanceInfoBody',
              style: bodyStyle,
            ),
            if (ledger) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(kSpendableBalanceLedgerNote, style: bodyStyle),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}
