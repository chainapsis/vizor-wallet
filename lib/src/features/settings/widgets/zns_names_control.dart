import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/naming/zns_names_setting.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import 'network_privacy_control.dart';

/// Turns Zcash Name Service names on or off. Names are off by default.
class ZnsNamesControl extends ConsumerWidget {
  const ZnsNamesControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final setting = ref.watch(znsNamesEnabledProvider);
    final enabled = setting.value ?? false;
    final loaded = setting.hasValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: Center(
                    child: AppIcon(
                      AppIcons.book,
                      size: 20,
                      color: enabled
                          ? colors.icon.brandCrimson
                          : colors.icon.muted,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Zcash names',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        enabled ? 'On' : 'Off',
                        key: const ValueKey('settings_zns_names_status'),
                        style: AppTypography.labelLarge.copyWith(
                          color: enabled
                              ? colors.text.brandCrimson
                              : colors.text.secondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                PrivacyToggle(
                  key: const ValueKey('settings_zns_names_toggle'),
                  trackKey: const ValueKey('settings_zns_names_toggle_track'),
                  enabled: enabled,
                  semanticsLabel: 'Zcash names',
                  onToggle: loaded
                      ? () => toggleZnsNames(context, ref, !enabled)
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            kZnsNamesSettingsCopy,
            key: const ValueKey('settings_zns_names_description'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Saves the Zcash names setting, telling the user when it could not be
/// saved. Shared by desktop and mobile Settings.
Future<void> toggleZnsNames(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  try {
    await ref.read(znsNamesEnabledProvider.notifier).setEnabled(enabled);
  } catch (error) {
    debugPrint('[zcash] ZNS: failed to save the names setting: $error');
    if (context.mounted) {
      showAppToast(context, "Couldn't save the Zcash names setting");
    }
  }
}
