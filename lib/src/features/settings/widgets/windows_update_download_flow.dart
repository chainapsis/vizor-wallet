import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/untranslated_details.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../../providers/windows_update_provider.dart';

enum _WindowsUpdatePrivacyChoice { tor, direct }

Future<void> startWindowsUpdateDownload({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  var privacy = ref.read(networkPrivacyProvider);
  if (privacy.torEnabled) {
    final choice = await showDialog<_WindowsUpdatePrivacyChoice>(
      context: context,
      builder: (_) => const _WindowsUpdatePrivacyChoiceDialog(),
    );
    if (!context.mounted || choice == null) return;

    if (choice == _WindowsUpdatePrivacyChoice.tor) {
      privacy = ref.read(networkPrivacyProvider);
      if (!privacy.torEnabled ||
          privacy.status != NetworkPrivacyConnectionStatus.connected ||
          !privacy.softwareUpdatesAvailable) {
        await _showUpdateError(
          context,
          title: context.l10n.settingsWinUpdateTorBlockedTitle,
          message: context.l10n.settingsWinUpdateTorBlockedBody,
        );
        return;
      }
    } else {
      try {
        await ref.read(networkPrivacyProvider.notifier).setTorEnabled(false);
      } catch (_) {
        if (!context.mounted) return;
        await _showTorDisableError(context);
        return;
      }
      if (!context.mounted) return;

      privacy = ref.read(networkPrivacyProvider);
      if (privacy.torEnabled ||
          privacy.status != NetworkPrivacyConnectionStatus.off) {
        await _showTorDisableError(context);
        return;
      }
      if (!privacy.softwareUpdatesAvailable) {
        await _showUpdateError(
          context,
          title: context.l10n.settingsWinUpdateUnavailableTitle,
          message: context.l10n.settingsWinUpdateUnavailableBody,
        );
        return;
      }
    }
  }

  final result = await ref
      .read(windowsUpdateProvider.notifier)
      .downloadUpdate();
  if (!context.mounted || result.started) return;
  await _showUpdateError(
    context,
    title: context.l10n.settingsWinUpdateStartFailedTitle,
    message: result.message(context.l10n),
    details: result.details,
  );
}

Future<void> _showTorDisableError(BuildContext context) {
  return _showUpdateError(
    context,
    title: context.l10n.settingsWinUpdateTorOffFailedTitle,
    message: context.l10n.settingsWinUpdateTorOffFailedBody,
  );
}

Future<void> _showUpdateError(
  BuildContext context, {
  required String title,
  required String message,
  String? details,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WindowsUpdateErrorDialog(
      title: title,
      message: message,
      details: details,
    ),
  );
}

class _WindowsUpdatePrivacyChoiceDialog extends StatelessWidget {
  const _WindowsUpdatePrivacyChoiceDialog();

  @override
  Widget build(BuildContext context) {
    return _WindowsUpdateDialogFrame(
      iconName: AppIcons.shieldKeyholeOutline,
      title: context.l10n.settingsWinUpdateTorChoiceTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.settingsWinUpdateTorChoiceBody,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            expand: true,
            onPressed: () =>
                Navigator.of(context).pop(_WindowsUpdatePrivacyChoice.tor),
            child: Text(context.l10n.settingsWinUpdateContinueTor),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            expand: true,
            variant: AppButtonVariant.secondary,
            onPressed: () =>
                Navigator.of(context).pop(_WindowsUpdatePrivacyChoice.direct),
            child: Text(context.l10n.settingsWinUpdateTurnOffTorAndUpdate),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            expand: true,
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
        ],
      ),
    );
  }
}

class _WindowsUpdateErrorDialog extends StatelessWidget {
  const _WindowsUpdateErrorDialog({
    required this.title,
    required this.message,
    this.details,
  });

  final String title;
  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return _WindowsUpdateDialogFrame(
      iconName: AppIcons.warning,
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          ...untranslatedDetailsButton(
            details,
            alignment: AlignmentDirectional.centerStart,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }
}

class _WindowsUpdateDialogFrame extends StatelessWidget {
  const _WindowsUpdateDialogFrame({
    required this.iconName,
    required this.title,
    required this.child,
  });

  final String iconName;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 424),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
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
                        iconName,
                        size: AppIconSize.medium,
                        color: colors.icon.regular,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
