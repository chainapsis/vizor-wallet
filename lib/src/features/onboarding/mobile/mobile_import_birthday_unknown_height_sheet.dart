import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

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
      title: context.l10n.onboardingUnknownHeightTitle,
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
            context.l10n.onboardingUnknownHeightBody,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.onboardingUnknownHeightHint,
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
            child: Text(context.l10n.onboardingContinueAnywayMobile),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('mobile_import_birthday_unknown_height_cancel'),
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
