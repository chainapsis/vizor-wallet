import 'package:flutter/widgets.dart';

import '../../../../l10n/app_localizations.dart';
import '../../layout/mobile/app_mobile_sheet.dart';
import '../../theme/app_theme.dart';
import '../app_button.dart';

/// Small TODO sheet for features whose mobile implementation hasn't
/// shipped yet (Keystone connect, biometric unlock, ...). Keeps the
/// real UI in place while making the gap explicit.
Future<void> showUnsupportedSheet(BuildContext context, {String? message}) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      final l10n = AppLocalizations.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.sheetNotAvailableTitle,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message ?? l10n.sheetNotAvailableBody,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(l10n.commonOk),
            ),
          ],
        ),
      );
    },
  );
}
