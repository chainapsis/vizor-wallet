import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/network_privacy_provider.dart';

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
    final state = ref.watch(networkPrivacyProvider);
    final notifier = ref.read(networkPrivacyProvider.notifier);
    final presentation = _presentationFor(state);
    final onToggle = state.isBusy
        ? null
        : () => unawaited(notifier.setTorEnabled(!state.torEnabled));
    // `retry()` re-runs the desired route, which is the direct connection when
    // it was the disable that failed.
    final retryLabel = (state.targetTorEnabled ?? state.torEnabled)
        ? 'Try again'
        : 'Try direct connection';
    final onRetry = state.isBusy ? null : () => unawaited(notifier.retry());

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
              'Network',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Semantics(
            button: true,
            toggled: state.torEnabled,
            enabled: !state.isBusy,
            label: 'Use Tor',
            // The excluded subtree holds the status text, and four of the five
            // states report `toggled: true`, so the status has to ride on the
            // node itself to reach assistive technology at all.
            value: presentation.statusLabel,
            onTap: onToggle,
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('mobile_settings_tor_row'),
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: SizedBox(
                height: _rowHeight,
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
                            AppIcons.tor,
                            size: 20,
                            color: presentation.iconColor(colors),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          'Use Tor',
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      Text(
                        presentation.statusLabel,
                        style: AppTypography.labelLarge.copyWith(
                          color: presentation.statusColor(colors),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      _MobileTorToggle(
                        key: const ValueKey('mobile_settings_tor_toggle'),
                        enabled: state.torEnabled,
                        busy: state.isBusy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            presentation.description,
            key: const ValueKey('mobile_settings_tor_description'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (state.status == NetworkPrivacyConnectionStatus.failed)
            // No gap token in front: the touch-sized row already carries the
            // whitespace that separates it from the description.
            Semantics(
              button: true,
              enabled: !state.isBusy,
              label: retryLabel,
              onTap: onRetry,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('mobile_settings_tor_retry'),
                behavior: HitTestBehavior.opaque,
                onTap: onRetry,
                child: SizedBox(
                  height: _rowHeight,
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      retryLabel,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.brandCrimson,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MobileTorPresentation {
  const _MobileTorPresentation({
    required this.statusLabel,
    required this.description,
    required this.statusColor,
    required this.iconColor,
  });

  final String statusLabel;
  final String description;
  final Color Function(AppColors colors) statusColor;
  final Color Function(AppColors colors) iconColor;
}

_MobileTorPresentation _presentationFor(NetworkPrivacyState state) {
  final targetTorEnabled = state.targetTorEnabled ?? state.torEnabled;
  return switch ((state.status, targetTorEnabled)) {
    (NetworkPrivacyConnectionStatus.connecting, true) => _MobileTorPresentation(
      statusLabel: 'Connecting…',
      description: 'New requests wait until the Tor connection is ready.',
      statusColor: (colors) => colors.text.secondary,
      iconColor: (colors) => colors.icon.muted,
    ),
    (NetworkPrivacyConnectionStatus.connecting, false) =>
      _MobileTorPresentation(
        statusLabel: 'Switching…',
        description:
            'Vizor is switching network requests to a direct '
            'connection.',
        statusColor: (colors) => colors.text.secondary,
        iconColor: (colors) => colors.icon.muted,
      ),
    (NetworkPrivacyConnectionStatus.connected, _) => _MobileTorPresentation(
      statusLabel: 'Connected',
      // The closing sentence states the background gate, not a guarantee: a
      // cold Tor bootstrap costs 8.45 MB and 23.7 s and an idle client keeps
      // padding its guard connection, which is only acceptable on a charger
      // over an unmetered link. Off the charger or on a metered link the
      // background pass does nothing and the foreground has to do the work.
      description:
          'Wallet sync and most in-app requests go through Tor. Some '
          'services may be unavailable over Tor, and links you open leave the '
          'app. A migration in progress advances in the background only while '
          'charging on an unmetered network.',
      statusColor: (colors) => colors.text.brandCrimson,
      iconColor: (colors) => colors.icon.brandCrimson,
    ),
    (NetworkPrivacyConnectionStatus.failed, true) => _MobileTorPresentation(
      statusLabel: 'Failed',
      description:
          'Vizor could not connect to Tor. Requests stay blocked '
          'until it connects or you turn Tor off.',
      statusColor: (colors) => colors.text.brandCrimson,
      iconColor: (colors) => colors.icon.brandCrimson,
    ),
    // A failed disable leaves Tor connected and carrying traffic, so this
    // must not reuse the blocked-requests copy above.
    (NetworkPrivacyConnectionStatus.failed, false) => _MobileTorPresentation(
      statusLabel: 'Switch failed',
      description:
          'Vizor could not switch to a direct connection. Tor is '
          'still on and requests keep going through it.',
      statusColor: (colors) => colors.text.brandCrimson,
      iconColor: (colors) => colors.icon.brandCrimson,
    ),
    (NetworkPrivacyConnectionStatus.off, _) => _MobileTorPresentation(
      statusLabel: 'Off',
      description:
          'Wallet sync and in-app requests connect directly. Turn Tor '
          'on to hide your IP address from the servers Vizor talks to.',
      statusColor: (colors) => colors.text.secondary,
      iconColor: (colors) => colors.icon.muted,
    ),
  };
}

class _MobileTorToggle extends StatelessWidget {
  const _MobileTorToggle({
    required this.enabled,
    required this.busy,
    super.key,
  });

  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trackColor = enabled
        ? colors.background.brandCrimsonStrong
        : colors.background.raised;
    final borderColor = enabled
        ? colors.border.brandCrimsonStrong
        : colors.border.regular;
    return Opacity(
      opacity: busy ? 0.65 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        width: 64,
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(AppRadii.full),
          border: Border.all(color: borderColor),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
          child: DecoratedBox(
            key: const ValueKey('mobile_settings_tor_toggle_thumb'),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            // Same pill as the keep-awake toggle directly above this card.
            child: const SizedBox(width: 40, height: 24),
          ),
        ),
      ),
    );
  }
}
