import 'package:flutter/widgets.dart';

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
              'Not available yet',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message ?? 'This feature is still in progress.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    },
  );
}
