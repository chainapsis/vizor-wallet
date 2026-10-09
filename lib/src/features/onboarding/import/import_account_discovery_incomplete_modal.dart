import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../shared/account_discovery_incomplete_copy.dart';

/// Warns that account discovery stopped before checking every account, before
/// anything is imported. Continuing imports the primary account plus any
/// found accounts the user then selects; cancelling stays on the birthday step.
class ImportAccountDiscoveryIncompleteModal extends StatelessWidget {
  const ImportAccountDiscoveryIncompleteModal({
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

    return AppPaneModalOverlay(
      borderRadius: BorderRadius.circular(AppDesktopSidebarSurface.glassRadius),
      onDismiss: onCancel,
      child: Container(
        key: const ValueKey('import_account_discovery_incomplete_modal'),
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
                    AccountDiscoveryIncompleteCopy.title,
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
                    AccountDiscoveryIncompleteCopy.reason(status),
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    AccountDiscoveryIncompleteCopy.notEvidence,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey(
                'import_account_discovery_incomplete_continue',
              ),
              onPressed: onContinue,
              minWidth: 280,
              child: const Text(AccountDiscoveryIncompleteCopy.continueLabel),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              key: const ValueKey('import_account_discovery_incomplete_back'),
              onPressed: onCancel,
              variant: AppButtonVariant.ghost,
              minWidth: 280,
              child: const Text(AccountDiscoveryIncompleteCopy.backLabel),
            ),
          ],
        ),
      ),
    );
  }
}
