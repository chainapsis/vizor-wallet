import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
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
          title: 'Software updates unavailable over Tor',
          message:
              'Vizor kept direct requests blocked. Retry updates in Settings, '
              'or turn off Tor and try the download again.',
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
          title: 'Software updates unavailable',
          message:
              'Tor is off, but software updates are still unavailable. Retry '
              'updates in Settings before downloading.',
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
    title: "Couldn't start the update",
    message: result.message,
  );
}

Future<void> _showTorDisableError(BuildContext context) {
  return _showUpdateError(
    context,
    title: "Couldn't turn off Tor",
    message:
        'Tor remains on, so Vizor kept the update blocked. Try again, or turn '
        'off Tor in Settings before downloading.',
  );
}

Future<void> _showUpdateError(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WindowsUpdateErrorDialog(title: title, message: message),
  );
}

class _WindowsUpdatePrivacyChoiceDialog extends StatelessWidget {
  const _WindowsUpdatePrivacyChoiceDialog();

  @override
  Widget build(BuildContext context) {
    return _WindowsUpdateDialogFrame(
      iconName: AppIcons.shieldKeyholeOutline,
      title: 'Use Tor for this update?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Updating over Tor may take longer. Turning Tor off switches '
            'all Vizor network requests to a direct connection.',
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            expand: true,
            onPressed: () =>
                Navigator.of(context).pop(_WindowsUpdatePrivacyChoice.tor),
            child: const Text('Continue with Tor'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            expand: true,
            variant: AppButtonVariant.secondary,
            onPressed: () =>
                Navigator.of(context).pop(_WindowsUpdatePrivacyChoice.direct),
            child: const Text('Turn off Tor and update'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            expand: true,
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _WindowsUpdateErrorDialog extends StatelessWidget {
  const _WindowsUpdateErrorDialog({required this.title, required this.message});

  final String title;
  final String message;

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
          const SizedBox(height: AppSpacing.md),
          AppButton(
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
