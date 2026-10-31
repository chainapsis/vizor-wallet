import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../near_swap_privacy_info.dart';
import '../settings_sub_option.dart';
import 'mobile_tor_control.dart';
import 'mobile_private_queries_control.dart';
export 'mobile_tor_control.dart' show MobilePrivacyToggle;

const _rowHeight = 44.0;

/// Mobile Tor control.
///
/// Deliberately not the desktop [NetworkPrivacyControl]: that widget's copy is
/// mostly about desktop software updates, which mobile gets from the app
/// stores, and its toggle geometry belongs to a settings page rather than a
/// grouped card. The state machine behind both is the same provider.
class MobileNetworkPrivacyCard extends ConsumerWidget {
  const MobileNetworkPrivacyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final nearSwapPrivacy = ref.watch(nearSwapPrivacySettingProvider);
    return MobileSurfaceCard(
      cornerRadius: AppRadii.large,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              'Privacy',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          const MobileTorControl(),
          const MobilePrivateQueriesControl(),
          if (nearSwapPrivacy != null) ...[
            const SizedBox(height: AppSpacing.md),
            // An option of Private queries: its icon sits under the label
            // above, and the hook starts under that row's icon.
            SettingsSubOption(
              key: const ValueKey(
                'mobile_settings_near_swap_privacy_sub_option',
              ),
              indent: 32 + AppSpacing.s,
              lineX: AppSpacing.xxs + 16,
              rowCenter: _rowHeight / 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MobileToggleRow(
                    label: 'NEAR swap privacy',
                    keyPrefix: 'mobile_settings_near_swap_privacy',
                    enabled: nearSwapPrivacy.enabled,
                    onToggle: () => unawaited(
                      ref.read(nearSwapPrivacyProvider.notifier).toggle(),
                    ),
                    onInfo: () => unawaited(showNearSwapPrivacyInfo(context)),
                  ),
                  // Feedback for this toggle only, as under Private queries.
                  if (nearSwapPrivacy.transition case final transition?)
                    Text(
                      transition,
                      key: const ValueKey(
                        'mobile_settings_near_swap_privacy_transition',
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Text(
                      nearSwapPrivacy.description,
                      key: const ValueKey(
                        'mobile_settings_near_swap_privacy_description',
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileToggleRow extends StatelessWidget {
  const _MobileToggleRow({
    required this.label,
    required this.keyPrefix,
    required this.enabled,
    required this.onToggle,
    this.onInfo,
  });
  final String label;
  final String keyPrefix;
  final bool enabled;
  final VoidCallback? onToggle;

  /// Shows an explanation of the setting from an info icon after the label.
  final VoidCallback? onInfo;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Only the info icon keeps its own semantics; the rest reads as the toggle.
    return Semantics(
      container: true,
      button: true,
      toggled: enabled,
      enabled: onToggle != null,
      label: label,
      onTap: onToggle,
      child: GestureDetector(
        key: ValueKey('${keyPrefix}_row'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: SizedBox(
          height: _rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 32,
                    child: Center(
                      child: AppIcon(
                        AppIcons.eye,
                        size: 20,
                        color: enabled
                            ? colors.icon.brandCrimson
                            : colors.icon.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: ExcludeSemantics(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                      ),
                      if (onInfo case final onInfo?) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        AppIconHoverButton(
                          key: ValueKey('${keyPrefix}_info'),
                          icon: AppIcons.help,
                          semanticLabel: "What's this?",
                          size: 32,
                          iconSize: 16,
                          iconColor: colors.icon.muted,
                          onTap: onInfo,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        enabled ? 'On' : 'Off',
                        key: ValueKey('${keyPrefix}_status'),
                        style: AppTypography.labelLarge.copyWith(
                          color: enabled
                              ? colors.text.brandCrimson
                              : colors.text.secondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      MobilePrivacyToggle(
                        key: ValueKey('${keyPrefix}_toggle'),
                        enabled: enabled,
                        interactive: onToggle != null,
                        thumbKey: ValueKey('${keyPrefix}_toggle_thumb'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
