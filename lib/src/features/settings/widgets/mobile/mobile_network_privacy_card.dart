import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/private_transparent_recovery_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../near_swap_privacy_info.dart';
import '../private_queries_turn_off.dart';
import '../settings_sub_option.dart';
import 'mobile_tor_control.dart';
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
    final enhancePirEnabled = ref.watch(privateQueriesControlEnabledProvider);
    // New swap addresses follow the private queries setting itself, which
    // the NEAR swap privacy switch also checks.
    final privateQueriesOn = ref.watch(enhancePirProvider);
    final nearSwapPrivacy = ref.watch(nearSwapPrivacyProvider);
    final enhancePirServiceAvailable = ref.watch(enhancePirAvailableProvider);
    final hardwareAccount =
        ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false;
    final enhancePirAvailable = enhancePirServiceAvailable || enhancePirEnabled;
    final recoveryTransition = ref.watch(enhancePirTransitionProvider);
    final changingRecovery = recoveryTransition == kEnhancePirChangingMessage;
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
          if (enhancePirAvailable) const SizedBox(height: AppSpacing.md),
          if (enhancePirAvailable)
            _MobilePrivateQueriesControl(
              label: 'Private queries',
              keyPrefix: 'mobile_settings_enhance_pir',
              enabled: enhancePirEnabled,
              onToggle: changingRecovery
                  ? null
                  : () => unawaited(togglePrivateQueries(context, ref)),
            ),
          // Feedback for the user's own toggle only; recovery queue counts are
          // deliberately not surfaced — see _EnhancePirPrivacyControl.
          if (enhancePirAvailable && recoveryTransition != null)
            Text(
              recoveryTransition,
              key: const ValueKey('mobile_settings_enhance_pir_transition'),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          if (enhancePirAvailable) const SizedBox(height: AppSpacing.sm),
          if (enhancePirAvailable)
            Text(
              // iOS background migration tracking cannot run privately, so
              // it stays off while this is on; say where confirmations happen.
              privateQueriesMobileSettingsCopy(defaultTargetPlatform),
              key: const ValueKey('mobile_settings_enhance_pir_description'),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          if (enhancePirServiceAvailable) ...[
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
                  _MobilePrivateQueriesControl(
                    label: 'NEAR swap privacy',
                    keyPrefix: 'mobile_settings_near_swap_privacy',
                    enabled: nearSwapPrivacy,
                    onToggle: changingRecovery || !privateQueriesOn
                        ? null
                        : () => unawaited(
                            ref.read(nearSwapPrivacyProvider.notifier).toggle(),
                          ),
                    onInfo: () => unawaited(showNearSwapPrivacyInfo(context)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Text(
                      nearSwapPrivacyDescription(
                        hardwareAccount: hardwareAccount,
                        privateQueriesOn: privateQueriesOn,
                      ),
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

class _MobilePrivateQueriesControl extends StatelessWidget {
  const _MobilePrivateQueriesControl({
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
