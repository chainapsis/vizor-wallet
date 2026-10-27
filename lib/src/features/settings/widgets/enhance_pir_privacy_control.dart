import 'package:flutter/widgets.dart';

import '../../../core/config/private_transparent_recovery_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'network_privacy_control.dart';
import 'wallet_pir_server_popup.dart';

class EnhancePirPrivacyControl extends StatelessWidget {
  const EnhancePirPrivacyControl({
    required this.enabled,
    required this.onToggle,
    required this.transition,
    this.label = 'Private queries',
    this.keyPrefix = 'settings_enhance_pir',
    this.description = kPrivateQueriesSettingsCopy,
    this.serverSettings = true,
    this.iconName = AppIcons.eye,
    this.unavailableLabel,
    this.footer = const [],
    super.key,
  });

  final String label;
  final String keyPrefix;
  final String description;
  final bool enabled;
  final VoidCallback? onToggle;

  final String iconName;

  /// Shown in place of On/Off, with no switch, where the setting doesn't
  /// apply.
  final String? unavailableLabel;

  /// Lines under the description, on its left edge, such as progress and a
  /// "Learn more" button.
  final List<Widget> footer;

  /// Shows the private query server picker after the label. Only the Private
  /// queries row owns the server choice.
  final bool serverSettings;

  /// Feedback for the user's own toggle only. Recovery queue counts are
  /// deliberately not surfaced here: they are dominated by obligations that
  /// can never complete (dummy actions, outputs the wallet cannot open), so
  /// they read as failures the user is expected to act on.
  final String? transition;

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
                      iconName,
                      size: 20,
                      color: enabled && unavailableLabel == null
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
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                          ),
                          if (serverSettings) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            WalletPirServerSettingsButton(
                              enabled: enabled && onToggle != null,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        unavailableLabel ?? (enabled ? 'On' : 'Off'),
                        key: ValueKey('${keyPrefix}_status'),
                        style: AppTypography.labelLarge.copyWith(
                          color: enabled && unavailableLabel == null
                              ? colors.text.brandCrimson
                              : colors.text.secondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unavailableLabel == null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  PrivacyToggle(
                    key: ValueKey('${keyPrefix}_toggle'),
                    trackKey: ValueKey('${keyPrefix}_toggle_track'),
                    enabled: enabled,
                    semanticsLabel: label,
                    onToggle: onToggle,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (transition != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            transition!,
            key: ValueKey('${keyPrefix}_transition'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            description,
            key: ValueKey('${keyPrefix}_description'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        for (final line in footer) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(alignment: AlignmentDirectional.centerStart, child: line),
        ],
      ],
    );
  }
}
