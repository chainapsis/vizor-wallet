import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/enhance_pir_provider.dart';
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
    final enhancePirEnabled = ref.watch(enhancePirProvider);
    final nearSwapPrivacy = ref.watch(nearSwapPrivacyProvider);
    final enhancePirAvailable = ref.watch(enhancePirAvailableProvider);
    final recoveryTransition = ref.watch(enhancePirTransitionProvider);
    final changingRecovery = recoveryTransition == 'Changing setting…';
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
                  : () => unawaited(
                      ref.read(enhancePirProvider.notifier).toggle(),
                    ),
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
              // iOS background migration tracking cannot run privately, so it
              // stays off while this is on; say where confirmations happen.
              defaultTargetPlatform == TargetPlatform.iOS
                  ? 'Experimental. Queries and enhances transaction data without revealing their IDs to servers. NEAR address recovery always uses private queries, even when this is off. While on, migration confirmations are checked only when Vizor is open.'
                  : 'Experimental. Queries and enhances transaction data without revealing their IDs to servers. NEAR address recovery always uses private queries, even when this is off.',
              key: const ValueKey('mobile_settings_enhance_pir_description'),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          if (enhancePirAvailable) ...[
            const SizedBox(height: AppSpacing.md),
            _MobilePrivateQueriesControl(
              label: 'NEAR swap privacy',
              keyPrefix: 'mobile_settings_near_swap_privacy',
              enabled: nearSwapPrivacy,
              onToggle: changingRecovery || !enhancePirEnabled
                  ? null
                  : () => unawaited(
                      ref.read(nearSwapPrivacyProvider.notifier).toggle(),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              enhancePirEnabled
                  ? 'Uses a separate receiving key for each swap. Recovery always uses private queries.'
                  : 'Turn on Private queries to create private swap addresses.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
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
  });
  final String label;
  final String keyPrefix;
  final bool enabled;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      toggled: enabled,
      enabled: onToggle != null,
      label: label,
      onTap: onToggle,
      excludeSemantics: true,
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
                SizedBox.square(
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
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    label,
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
        ),
      ),
    );
  }
}
