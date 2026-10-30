import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/private_transparent_recovery_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../private_queries_turn_off.dart';
import '../wallet_pir_server_popup.dart';
import 'mobile_tor_control.dart';

/// Private queries row and explanation shared by mobile Settings and Welcome.
/// Includes the spacing separating it from the preceding Tor control.
class MobilePrivateQueriesControl extends ConsumerWidget {
  const MobilePrivateQueriesControl({
    this.enabled = true,
    this.onRequest,
    super.key,
  });

  final bool enabled;
  final Future<void> Function()? onRequest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final enhancePirEnabled = ref.watch(privateQueriesControlEnabledProvider);
    if (!ref.watch(enhancePirAvailableProvider) && !enhancePirEnabled) {
      return const SizedBox.shrink();
    }
    final recoveryTransition = ref.watch(enhancePirTransitionProvider);
    final interactive =
        enabled && recoveryTransition != kEnhancePirChangingMessage;
    void onToggle() =>
        unawaited(onRequest?.call() ?? togglePrivateQueries(context, ref));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                enabled: interactive,
                toggled: enhancePirEnabled,
                label: 'Private queries',
                onTap: !interactive ? null : onToggle,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_settings_enhance_pir_row'),
                  behavior: HitTestBehavior.opaque,
                  onTap: !interactive ? null : onToggle,
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 32,
                            child: Center(
                              child: AppIcon(
                                AppIcons.eye,
                                size: 20,
                                color: enhancePirEnabled
                                    ? colors.icon.brandCrimson
                                    : colors.icon.muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(
                            child: Text(
                              'Private queries',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            enhancePirEnabled ? 'On' : 'Off',
                            key: const ValueKey(
                              'mobile_settings_enhance_pir_status',
                            ),
                            style: AppTypography.labelLarge.copyWith(
                              color: enhancePirEnabled
                                  ? colors.text.brandCrimson
                                  : colors.text.secondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          MobilePrivacyToggle(
                            key: const ValueKey(
                              'mobile_settings_enhance_pir_toggle',
                            ),
                            enabled: enhancePirEnabled,
                            interactive: interactive,
                            thumbKey: const ValueKey(
                              'mobile_settings_enhance_pir_toggle_thumb',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            WalletPirServerSettingsButton(
              enabled: enhancePirEnabled && interactive,
            ),
          ],
        ),
        // Feedback for the user's own toggle only; recovery queue counts are
        // deliberately not surfaced — see _EnhancePirPrivacyControl.
        if (recoveryTransition != null)
          Text(
            recoveryTransition,
            key: const ValueKey('mobile_settings_enhance_pir_transition'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          // iOS background migration tracking cannot run privately, so
          // it stays off while this is on; say where confirmations happen.
          privateQueriesMobileSettingsCopy(defaultTargetPlatform),
          key: const ValueKey('mobile_settings_enhance_pir_description'),
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}
