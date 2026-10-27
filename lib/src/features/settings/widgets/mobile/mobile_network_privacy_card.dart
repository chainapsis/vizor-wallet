import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../near_swap_privacy_info.dart';
import '../near_swap_privacy_turn_off.dart';
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
                  _MobileSubOptionRow(
                    iconName: AppIcons.linkOff,
                    label: 'NEAR swap privacy',
                    keyPrefix: 'mobile_settings_near_swap_privacy',
                    enabled: nearSwapPrivacy.enabled,
                    unavailableLabel: nearSwapPrivacy.available
                        ? null
                        : kNearSwapPrivacyUnavailableLabel,
                    onToggle: nearSwapPrivacy.available
                        ? () => unawaited(toggleNearSwapPrivacy(context, ref))
                        : null,
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
                  if (nearSwapPrivacy.checkingPastSwaps) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: AppSpacing.xxs,
                      ),
                      child: NearSwapPrivacyCheckingPastSwaps(),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  const NearSwapPrivacyLearnMore(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A sub-option row: the icon under the parent's label as on desktop, the
/// label with its status under it, and the switch at the end. At 320px with
/// large text the label wraps to three lines rather than truncating.
class _MobileSubOptionRow extends StatelessWidget {
  const _MobileSubOptionRow({
    required this.iconName,
    required this.label,
    required this.keyPrefix,
    required this.enabled,
    required this.onToggle,
    this.unavailableLabel,
  });
  final String iconName;
  final String label;
  final String keyPrefix;
  final bool enabled;
  final VoidCallback? onToggle;

  /// Shown in place of On/Off, with no switch, where the setting doesn't
  /// apply.
  final String? unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unavailable = unavailableLabel != null;
    return Semantics(
      container: true,
      button: !unavailable,
      toggled: unavailable ? null : enabled,
      enabled: onToggle != null,
      label: unavailable ? '$label, $unavailableLabel' : label,
      onTap: onToggle,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('${keyPrefix}_row'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _rowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Row(
              children: [
                AppIcon(
                  iconName,
                  size: 20,
                  color: enabled && !unavailable
                      ? colors.icon.brandCrimson
                      : colors.icon.muted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      Text(
                        unavailableLabel ?? (enabled ? 'On' : 'Off'),
                        key: ValueKey('${keyPrefix}_status'),
                        style: AppTypography.labelLarge.copyWith(
                          color: enabled && !unavailable
                              ? colors.text.brandCrimson
                              : colors.text.secondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!unavailable) ...[
                  const SizedBox(width: AppSpacing.xs),
                  MobilePrivacyToggle(
                    key: ValueKey('${keyPrefix}_toggle'),
                    enabled: enabled,
                    interactive: onToggle != null,
                    thumbKey: ValueKey('${keyPrefix}_toggle_thumb'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
