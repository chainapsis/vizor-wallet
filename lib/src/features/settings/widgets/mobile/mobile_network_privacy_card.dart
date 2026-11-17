import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/mobile/mobile_section.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../near_swap_privacy_info.dart';
import '../settings_sub_option.dart';
import 'mobile_tor_control.dart';
import 'mobile_private_queries_control.dart';
export 'mobile_tor_control.dart' show MobilePrivacyToggle;

const _rowHeight = 44.0;
const _rowIconSize = 20.0;

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
    // Titled above its card like the Settings list groups.
    return MobileSection(
      title: context.l10n.settingsPrivacyTitle,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MobileTorControl(),
          const MobilePrivateQueriesControl(divided: true),
          if (nearSwapPrivacy != null) ...[
            const SizedBox(height: AppSpacing.md),
            // An option of Private queries: its icon sits under the label
            // above, and the hook starts under that row's icon.
            SettingsSubOption(
              key: const ValueKey(
                'mobile_settings_near_swap_privacy_sub_option',
              ),
              indent: _rowIconSize + AppSpacing.s,
              lineX: _rowIconSize / 2,
              rowCenter: _rowHeight / 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MobileToggleRow(
                    label: context.l10n.settingsNearSwapPrivacyLabel,
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
                      transition.message(context.l10n),
                      key: const ValueKey(
                        'mobile_settings_near_swap_privacy_transition',
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    nearSwapPrivacy.description.text(context.l10n),
                    key: const ValueKey(
                      'mobile_settings_near_swap_privacy_description',
                    ),
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
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
        // A floor, not a fixed height, as for the Private queries row.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _rowHeight),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.xxs),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: AppIcon(
                    AppIcons.eye,
                    size: _rowIconSize,
                    color: colors.icon.accent,
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
                          semanticLabel: context.l10n.commonWhatsThis,
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
                        enabled
                            ? context.l10n.settingsStatusOn
                            : context.l10n.settingsStatusOff,
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
