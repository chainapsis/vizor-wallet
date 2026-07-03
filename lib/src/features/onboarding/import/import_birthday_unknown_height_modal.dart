import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../../l10n/app_localizations.dart';

class ImportBirthdayUnknownHeightModal extends StatelessWidget {
  const ImportBirthdayUnknownHeightModal({
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppPaneModalOverlay(
      borderRadius: BorderRadius.circular(AppDesktopSidebarSurface.glassRadius),
      onDismiss: onCancel,
      child: Container(
        width: 312,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
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
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).onbUnknownHeightTitle,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(context).onbUnknownHeightBody,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    AppLocalizations.of(context).onbUnknownHeightHint,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('unknown_birthday_confirm_button'),
              onPressed: onConfirm,
              minWidth: 280,
              child: Text(AppLocalizations.of(context).onbContinueAnyway),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              key: const ValueKey('unknown_birthday_cancel_button'),
              onPressed: onCancel,
              variant: AppButtonVariant.ghost,
              minWidth: 280,
              child: Text(AppLocalizations.of(context).onbGoBack),
            ),
          ],
        ),
      ),
    );
  }
}
