import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/network_privacy_provider.dart';
// The widget is deliberately not shared; the decision behind it is, because
// both form factors drive one provider and the escape hatch has to exist on
// both.
import '../network_privacy_control.dart'
    show NetworkPrivacyToggleActionX, networkPrivacyToggleAction;

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
    final presentation = _presentationFor(
      state,
      platform: defaultTargetPlatform,
    );
    final toggleAction = networkPrivacyToggleAction(state);
    final onToggle = toggleAction.isInteractive
        ? () => unawaited(
            notifier.setTorEnabled(toggleAction.requestedTorEnabled),
          )
        : null;
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
            enabled: toggleAction.isInteractive,
            label: toggleAction.semanticsLabel,
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
                        interactive: toggleAction.isInteractive,
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
              enabled: onRetry != null,
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

_MobileTorPresentation _presentationFor(
  NetworkPrivacyState state, {
  required TargetPlatform platform,
}) {
  final targetTorEnabled = state.targetTorEnabled ?? state.torEnabled;
  return switch ((state.status, targetTorEnabled)) {
    (NetworkPrivacyConnectionStatus.connecting, true) => _MobileTorPresentation(
      statusLabel: 'Connecting…',
      // Names the way out. On a network that blocks Tor the wait runs to the
      // bootstrap deadline with every request failing closed, and relaunching
      // the app only starts the same wait again, so the escape has to be stated
      // where the user is looking.
      description:
          'New requests wait until the Tor connection is ready. Turn Tor '
          'off to stop connecting and use a direct connection.',
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
      // iOS can continue Ironwood private migration through its native
      // background task after Vizor closes. That task is pinned direct, so
      // name the exception instead of weakening the foreground guarantee with
      // "most". Android has no corresponding background migration lane.
      description: platform == TargetPlatform.iOS
          ? 'Vizor’s network requests go through Tor. Ironwood private '
                'migration uses a direct connection while Vizor is closed. '
                'Links opened in other apps use those apps’ network settings.'
          : 'Vizor’s network requests go through Tor. Links opened in other '
                'apps use those apps’ network settings.',
      statusColor: (colors) => colors.text.brandCrimson,
      iconColor: (colors) => colors.icon.brandCrimson,
    ),
    // A failed enable has two shapes with opposite request behaviour, so the
    // route decides which is described. A bootstrap failure left the process
    // fail-closed; a save failure aborted the toggle before anything changed.
    (NetworkPrivacyConnectionStatus.failed, true) =>
      state.torEnabled
          ? _MobileTorPresentation(
              statusLabel: 'Failed',
              description:
                  'Vizor could not connect to Tor. Requests stay blocked '
                  'until it connects or you turn Tor off.',
              statusColor: (colors) => colors.text.brandCrimson,
              iconColor: (colors) => colors.icon.brandCrimson,
            )
          // Saying "requests stay blocked" here would describe the opposite
          // of what is happening: nothing was enabled, and requests keep
          // flowing directly.
          : _MobileTorPresentation(
              statusLabel: 'Setting not saved',
              description:
                  'Vizor could not save the change, so Tor was not turned '
                  'on. Requests keep using a direct connection.',
              statusColor: (colors) => colors.text.brandCrimson,
              iconColor: (colors) => colors.icon.brandCrimson,
            ),
    // A failed disable has two shapes, and they carry opposite privacy
    // guarantees, so the route decides which is described rather than the
    // target. Neither may reuse the blocked-requests copy above.
    (NetworkPrivacyConnectionStatus.failed, false) =>
      state.torEnabled
          // The transport never switched. Tor is still up and still carrying
          // traffic.
          ? _MobileTorPresentation(
              statusLabel: 'Switch failed',
              description:
                  'Vizor could not switch to a direct connection. Tor is '
                  'still on and requests keep going through it.',
              statusColor: (colors) => colors.text.brandCrimson,
              iconColor: (colors) => colors.icon.brandCrimson,
            )
          // The transport did switch and only the setting could not be saved.
          // Requests are direct from here, and the saved route is still Tor —
          // the stricter half, so the next launch comes back on Tor rather
          // than silently staying direct. Saying "Tor is still on" here would
          // promise the user the opposite of what is actually carrying their
          // traffic.
          : _MobileTorPresentation(
              statusLabel: 'Setting not saved',
              description:
                  'Requests now use a direct connection, but Vizor could not '
                  'save the change. Tor turns back on the next time you open '
                  'the app.',
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
    required this.interactive,
    super.key,
  });

  final bool enabled;

  /// Dimming says the route is not effective yet. A transition the user can
  /// still leave is not dimmed: the control has to look like something they may
  /// act on, because acting on it is the way out of the wait.
  final bool interactive;

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
      opacity: interactive ? 1 : 0.65,
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
