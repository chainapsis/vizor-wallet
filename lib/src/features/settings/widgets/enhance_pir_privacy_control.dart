import 'package:flutter/widgets.dart';

import '../../../core/config/private_transparent_recovery_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'network_privacy_control.dart';
import 'wallet_pir_server_popup.dart';
import '../../../providers/enhance_pir_provider.dart';

class EnhancePirPrivacyControl extends StatelessWidget {
  const EnhancePirPrivacyControl({
    required this.enabled,
    required this.onToggle,
    required this.transition,
    super.key,
  });

  final bool enabled;
  final VoidCallback? onToggle;

  /// Feedback for the user's own toggle only. Recovery queue counts are
  /// deliberately not surfaced here: they are dominated by obligations that
  /// can never complete (dummy actions, outputs the wallet cannot open), so
  /// they read as failures the user is expected to act on.
  final EnhancePirTransition? transition;

  /// Whether this build's private queries also recover transparent funds.

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                      AppIcons.eye,
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              context.l10n.settingsPrivateQueriesLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          WalletPirServerSettingsButton(
                            enabled: enabled && onToggle != null,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        enabled
                            ? context.l10n.settingsStatusOn
                            : context.l10n.settingsStatusOff,
                        key: const ValueKey('settings_enhance_pir_status'),
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
                  key: const ValueKey('settings_enhance_pir_toggle'),
                  trackKey: const ValueKey('settings_enhance_pir_toggle_track'),
                  enabled: enabled,
                  semanticsLabel: context.l10n.settingsPrivateQueriesLabel,
                  onToggle: onToggle,
                ),
              ],
            ),
          ),
        ),
        if (transition != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            transition!.message(context.l10n),
            key: const ValueKey('settings_enhance_pir_transition'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            privateQueriesSettingsCopy(context.l10n),
            key: const ValueKey('settings_enhance_pir_description'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}
