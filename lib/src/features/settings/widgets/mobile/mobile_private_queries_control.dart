import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/private_transparent_recovery_config.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../private_queries_turn_off.dart';
import '../wallet_pir_server_popup.dart';
import '../../../../core/widgets/mobile/mobile_section.dart';
import 'mobile_tor_control.dart';

/// Private queries row and explanation shared by mobile Settings and Welcome.
/// Includes the spacing separating it from the preceding Tor control.
class MobilePrivateQueriesControl extends ConsumerWidget {
  const MobilePrivateQueriesControl({
    this.enabled = true,
    this.onRequest,
    this.divided = false,
    super.key,
  });

  final bool enabled;
  final Future<void> Function()? onRequest;

  /// Draws a hairline above the row, as Settings splits its items. The
  /// control draws it, not the caller, so it goes with the control when
  /// private queries are unavailable.
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final enhancePirEnabled = ref.watch(privateQueriesControlEnabledProvider);
    if (!ref.watch(enhancePirAvailableProvider) && !enhancePirEnabled) {
      return const SizedBox.shrink();
    }
    final recoveryTransition = ref.watch(enhancePirTransitionProvider);
    final interactive =
        enabled && recoveryTransition != EnhancePirTransition.changing;
    void onToggle() =>
        unawaited(onRequest?.call() ?? togglePrivateQueries(context, ref));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        if (divided) ...[
          const MobileSectionDivider(),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                enabled: interactive,
                toggled: enhancePirEnabled,
                label: context.l10n.settingsPrivateQueriesLabel,
                onTap: !interactive ? null : onToggle,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_settings_enhance_pir_row'),
                  behavior: HitTestBehavior.opaque,
                  onTap: !interactive ? null : onToggle,
                  // A floor, not a fixed height, so a two-line label at large
                  // text sizes is not clipped.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    // Same icon and label edges as the Settings chevron rows.
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          // Like the other Settings row icons; the status
                          // and the toggle carry the state.
                          AppIcon(
                            AppIcons.eye,
                            size: 20,
                            color: colors.icon.accent,
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(
                            child: Text(
                              context.l10n.settingsPrivateQueriesLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            enhancePirEnabled
                                ? context.l10n.settingsStatusOn
                                : context.l10n.settingsStatusOff,
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
          ],
        ),
        // Feedback for the user's own toggle only; recovery queue counts are
        // deliberately not surfaced — see _EnhancePirPrivacyControl.
        if (recoveryTransition != null)
          Text(
            recoveryTransition.message(context.l10n),
            key: const ValueKey('mobile_settings_enhance_pir_transition'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          // iOS background migration tracking cannot run privately, so
          // it stays off while this is on; say where confirmations happen.
          privateQueriesMobileSettingsCopy(context.l10n, defaultTargetPlatform),
          key: const ValueKey('mobile_settings_enhance_pir_description'),
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        // The server settings matter only while private queries are on, or
        // while swap recovery queries the server without them.
        if (enhancePirEnabled ||
            ref.watch(swapRecoveryUsesServerProvider).value == true) ...[
          const SizedBox(height: AppSpacing.sm),
          const MobileSectionDivider(),
          WalletPirServerSettingsRow(enabled: interactive),
        ],
      ],
    );
  }
}
