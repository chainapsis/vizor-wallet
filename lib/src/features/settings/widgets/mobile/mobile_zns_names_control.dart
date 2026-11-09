import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/naming/zns_names_setting.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../zns_names_control.dart' show toggleZnsNames;
import 'mobile_tor_control.dart';

/// Zcash names row and explanation in the mobile Privacy card. Includes the
/// spacing separating it from the preceding control.
class MobileZnsNamesControl extends ConsumerWidget {
  const MobileZnsNamesControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final setting = ref.watch(znsNamesEnabledProvider);
    final enabled = setting.value ?? false;
    final interactive = setting.hasValue;
    void onToggle() => unawaited(toggleZnsNames(context, ref, !enabled));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Semantics(
          button: true,
          enabled: interactive,
          toggled: enabled,
          label: 'Zcash names',
          onTap: interactive ? onToggle : null,
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('mobile_settings_zns_names_row'),
            behavior: HitTestBehavior.opaque,
            onTap: interactive ? onToggle : null,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 32,
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
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Text(
                        'Zcash names',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      enabled ? 'On' : 'Off',
                      key: const ValueKey('mobile_settings_zns_names_status'),
                      style: AppTypography.labelLarge.copyWith(
                        color: enabled
                            ? colors.text.brandCrimson
                            : colors.text.secondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    MobilePrivacyToggle(
                      key: const ValueKey('mobile_settings_zns_names_toggle'),
                      enabled: enabled,
                      interactive: interactive,
                      thumbKey: const ValueKey(
                        'mobile_settings_zns_names_toggle_thumb',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          kZnsNamesSettingsCopy,
          key: const ValueKey('mobile_settings_zns_names_description'),
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}
