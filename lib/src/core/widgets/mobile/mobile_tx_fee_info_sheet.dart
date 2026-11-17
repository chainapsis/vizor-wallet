import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../../layout/mobile/app_mobile_sheet.dart';
import '../../theme/app_theme.dart';
import '../app_button.dart';

/// Bottom sheet explaining the (ZIP-317) network fee. The copy is
/// context-agnostic — it describes what the fee is, not a send-specific
/// moment — so it is shared by the send review composer and the transaction
/// status detail cards.
Future<void> showMobileTxFeeInfoSheet(
  BuildContext context, {
  String? title,
  String? description,
}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      void close() => Navigator.of(sheetContext).pop();
      return MobileModalScaffold(
        title: title ?? sheetContext.l10n.txFeeInfoTitle,
        titleMaxLines: 3,
        onClose: close,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              description ?? sheetContext.l10n.txFeeInfoDescription,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: close,
              child: Text(sheetContext.l10n.commonClose),
            ),
          ],
        ),
      );
    },
  );
}
