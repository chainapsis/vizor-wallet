import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/hide_balance_on_unlock_provider.dart';
import 'network_privacy_control.dart' show PrivacyToggle;

class HideBalanceOnUnlockControl extends ConsumerWidget {
  const HideBalanceOnUnlockControl({super.key});

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    try {
      await ref.read(hideBalanceOnUnlockProvider.notifier).set(!enabled);
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        context.l10n.settingsHideBalanceOnUnlockUpdateFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(hideBalanceOnUnlockProvider);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(AppIcons.eyeClosed, size: 20, color: colors.icon.accent),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                context.l10n.settingsHideBalanceOnUnlock,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            PrivacyToggle(
              enabled: enabled,
              trackKey: const ValueKey('settings_hide_on_unlock_toggle'),
              semanticsLabel: context.l10n.settingsHideBalanceOnUnlock,
              onToggle: () => unawaited(_toggle(context, ref, enabled)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.l10n.settingsHideBalanceOnUnlockDescription,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}
