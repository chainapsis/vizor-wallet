import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../../l10n/app_localizations.dart';

Future<bool> showMobileImportBirthdayUnknownHeightSheet(
  BuildContext context,
) async {
  final confirmed = await showAppMobileSheet<bool>(
    context: context,
    builder: (sheetContext) => MobileImportBirthdayUnknownHeightSheet(
      onConfirm: () => Navigator.of(sheetContext).pop(true),
      onCancel: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  return confirmed == true;
}

class MobileImportBirthdayUnknownHeightSheet extends StatelessWidget {
  const MobileImportBirthdayUnknownHeightSheet({
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
      key: const ValueKey('mobile_import_birthday_unknown_height_sheet'),
      title: AppLocalizations.of(context).onbUnknownHeightTitle,
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
            AppLocalizations.of(context).onbUnknownHeightBody,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.of(context).onbUnknownHeightHint,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey(
              'mobile_import_birthday_unknown_height_confirm',
            ),
            expand: true,
            onPressed: onConfirm,
            child: Text(AppLocalizations.of(context).onbContinueAnywayLower),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('mobile_import_birthday_unknown_height_cancel'),
            variant: AppButtonVariant.ghost,
            expand: true,
            onPressed: onCancel,
            child: Text(AppLocalizations.of(context).onbGoBackLower),
          ),
        ],
      ),
    );
  }
}
