import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/network_privacy_provider.dart';

const _toggleShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

/// What activating a Tor control does from the state it is showing.
///
/// Shared by both form factors because the state machine behind them is one
/// provider, and because the case that matters is the one a control is most
/// tempted to disable itself for.
enum NetworkPrivacyToggleAction {
  enable,
  disable,

  /// A Tor connection is still being established and the user wants out of it.
  ///
  /// The bootstrap has a three-minute deadline and every policy-aware request
  /// fails closed until it resolves, so a control that goes inert for the
  /// duration strands the user on a network that blocks Tor — and force-quitting
  /// does not help, because the saved route is Tor and the next launch starts
  /// the same bootstrap. Switching to direct is what ends it, so this stays
  /// available for exactly as long as the wait does.
  cancelPendingTor,

  /// A switch to the direct route is already under way. There is nothing to
  /// cancel toward, and re-entering Tor mid-switch is a transition rather than
  /// an escape.
  none,
}

NetworkPrivacyToggleAction networkPrivacyToggleAction(
  NetworkPrivacyState state,
) {
  if (!state.isBusy) {
    return state.torEnabled
        ? NetworkPrivacyToggleAction.disable
        : NetworkPrivacyToggleAction.enable;
  }
  return (state.targetTorEnabled ?? state.torEnabled)
      ? NetworkPrivacyToggleAction.cancelPendingTor
      : NetworkPrivacyToggleAction.none;
}

extension NetworkPrivacyToggleActionX on NetworkPrivacyToggleAction {
  bool get isInteractive => this != NetworkPrivacyToggleAction.none;

  /// The route the action asks for. Cancelling a pending Tor connection asks
  /// for the direct route, which is what supersedes the bootstrap.
  bool get requestedTorEnabled => this == NetworkPrivacyToggleAction.enable;

  /// Assistive-technology label. Turning "Use Tor" off mid-connect is an escape
  /// from a wait, not a second transition, so it does not announce itself as
  /// one.
  String get semanticsLabel => this == NetworkPrivacyToggleAction.cancelPendingTor
      ? 'Stop connecting to Tor'
      : 'Use Tor';
}

/// Shared desktop Tor control used both before wallet creation and in Settings.
///
/// The control presents the desired route separately from its connection
/// status: Tor remains visually on while a failed connection is fail-closed,
/// and the recovery action retries the same desired route.
class NetworkPrivacyControl extends ConsumerWidget {
  const NetworkPrivacyControl({this.showSurface = true, super.key});

  final bool showSurface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state = ref.watch(networkPrivacyProvider);
    final toggleAction = networkPrivacyToggleAction(state);
    final presentation = _presentationFor(
      state,
      platform: defaultTargetPlatform,
    );

    final assetList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: Center(
                    child: AppIcon(
                      AppIcons.tor,
                      key: const ValueKey('network_privacy_tor_icon'),
                      size: 20,
                      color: presentation.iconColor(colors),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Use Tor',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          if (presentation.statusIconName != null) ...[
                            AppIcon(
                              presentation.statusIconName!,
                              key: const ValueKey(
                                'network_privacy_status_icon',
                              ),
                              size: 14,
                              color: presentation.statusColor(colors),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                          ],
                          Flexible(
                            child: Text(
                              presentation.statusLabel,
                              key: ValueKey(
                                'network_privacy_status_${state.status.name}_${state.torEnabled}',
                              ),
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: presentation.statusColor(colors),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _NetworkPrivacyToggle(
                  key: const ValueKey('network_privacy_toggle'),
                  enabled: state.torEnabled,
                  action: toggleAction,
                  onToggle: toggleAction.isInteractive
                      ? () => unawaited(
                          ref
                              .read(networkPrivacyProvider.notifier)
                              .setTorEnabled(toggleAction.requestedTorEnabled),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            child: Text(
              presentation.description,
              key: ValueKey(
                'network_privacy_description_${state.status.name}_${state.torEnabled}',
              ),
              style: AppTypography.bodyMedium.copyWith(
                color: presentation.descriptionColor(colors),
              ),
            ),
          ),
        ),
        if (!state.softwareUpdatesAvailable &&
            (state.status == NetworkPrivacyConnectionStatus.connected ||
                state.status == NetworkPrivacyConnectionStatus.off)) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              onPressed: () => unawaited(
                ref
                    .read(networkPrivacyProvider.notifier)
                    .retrySoftwareUpdates(),
              ),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              leading: const AppIcon(AppIcons.renew),
              child: const Text('Retry updates'),
            ),
          ),
        ] else if (state.status == NetworkPrivacyConnectionStatus.failed) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              onPressed: () => unawaited(
                ref
                    .read(networkPrivacyProvider.notifier)
                    .setTorEnabled(state.targetTorEnabled ?? state.torEnabled),
              ),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              leading: const AppIcon(AppIcons.renew),
              child: Text(
                (state.targetTorEnabled ?? state.torEnabled)
                    ? 'Try again'
                    : 'Try direct connection',
              ),
            ),
          ),
        ],
      ],
    );

    if (!showSurface) return assetList;
    return DecoratedBox(
      key: const ValueKey('network_privacy_surface'),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: Text(
                'Privacy',
                key: const ValueKey('network_privacy_surface_title'),
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            assetList,
          ],
        ),
      ),
    );
  }
}

class _NetworkPrivacyToggle extends StatefulWidget {
  const _NetworkPrivacyToggle({
    required this.enabled,
    required this.action,
    required this.onToggle,
    super.key,
  });

  final bool enabled;

  final NetworkPrivacyToggleAction action;

  final VoidCallback? onToggle;

  @override
  State<_NetworkPrivacyToggle> createState() => _NetworkPrivacyToggleState();
}

class _NetworkPrivacyToggleState extends State<_NetworkPrivacyToggle> {
  bool _focused = false;

  void _activate() => widget.onToggle?.call();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final interactive = widget.onToggle != null;
    final track = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      key: const ValueKey('network_privacy_toggle_track'),
      width: 44,
      height: 20,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: widget.enabled
            ? colors.background.brandCrimsonStrong
            : colors.background.overlay,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: widget.enabled
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: const SizedBox(width: 28, height: 16),
        ),
      ),
    );

    final control = Stack(
      clipBehavior: Clip.none,
      children: [
        // The knob moves to the desired route as soon as a transition starts,
        // so dimming is the only signal that the route is not effective yet.
        // A transition the user can still leave is not dimmed: the control has
        // to look like something they may act on, because acting on it is the
        // way out of the wait.
        Opacity(opacity: interactive ? 1 : 0.65, child: track),
        if (_focused)
          Positioned(
            left: -3,
            top: -3,
            right: -3,
            bottom: -3,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.state.focusRing, width: 2),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      enabled: interactive,
      toggled: widget.enabled,
      label: widget.action.semanticsLabel,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: FocusableActionDetector(
          enabled: interactive,
          mouseCursor: interactive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (focused) {
            if (_focused == focused) return;
            setState(() => _focused = focused);
          },
          shortcuts: _toggleShortcuts,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggle,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: control),
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkPrivacyPresentation {
  const _NetworkPrivacyPresentation({
    required this.statusLabel,
    required this.description,
    required this.statusColor,
    required this.iconColor,
    required this.descriptionColor,
    this.statusIconName,
  });

  final String statusLabel;
  final String description;
  final String? statusIconName;
  final Color Function(AppColors colors) statusColor;
  final Color Function(AppColors colors) iconColor;
  final Color Function(AppColors colors) descriptionColor;
}

_NetworkPrivacyPresentation _presentationFor(
  NetworkPrivacyState state, {
  required TargetPlatform platform,
}) {
  if (!state.softwareUpdatesAvailable &&
      state.status == NetworkPrivacyConnectionStatus.connected) {
    return _NetworkPrivacyPresentation(
      statusLabel: 'Connected',
      description:
          'Wallet sync and most in-app requests go through Tor. Software updates are unavailable.',
      statusColor: (colors) => colors.text.destructive,
      iconColor: (colors) => colors.icon.brandCrimson,
      descriptionColor: (colors) => colors.text.destructive,
    );
  }
  if (!state.softwareUpdatesAvailable &&
      state.status == NetworkPrivacyConnectionStatus.off) {
    return _NetworkPrivacyPresentation(
      statusLabel: 'Direct',
      description:
          'Network requests connect directly. Software updates are unavailable.',
      statusColor: (colors) => colors.text.destructive,
      iconColor: (colors) => colors.icon.muted,
      descriptionColor: (colors) => colors.text.destructive,
    );
  }
  final targetTorEnabled = state.targetTorEnabled ?? state.torEnabled;
  final isLinux = platform == TargetPlatform.linux;
  return switch ((state.status, targetTorEnabled)) {
    (NetworkPrivacyConnectionStatus.off, _) => _NetworkPrivacyPresentation(
      statusLabel: 'Direct',
      description: isLinux
          ? 'Tor is off. Vizor requests, including software update checks, '
                'connect directly. Update pages and downloads open in another app.'
          : 'Tor is off. Requests to the Zcash network, in-app services, and software updates connect directly.',
      statusColor: (colors) => colors.text.secondary,
      iconColor: (colors) => colors.icon.muted,
      descriptionColor: (colors) => colors.text.accent,
    ),
    (NetworkPrivacyConnectionStatus.connecting, true) =>
      _NetworkPrivacyPresentation(
        statusLabel: 'Connecting…',
        // Names the way out. On a network that blocks Tor the wait runs to the
        // bootstrap deadline with every request failing closed, and restarting
        // the app only starts the same wait again, so the escape has to be
        // stated where the user is looking.
        description: isLinux
            ? 'New requests wait until the Tor connection is ready. Turn Tor '
                  'off to stop connecting and use a direct connection. Update '
                  'pages and downloads opened in another app use that '
                  'app’s connection.'
            : 'New requests wait until the Tor connection is ready. Turn Tor '
                  'off to stop connecting and use a direct connection.',
        statusIconName: AppIcons.loader,
        statusColor: (colors) => colors.text.secondary,
        iconColor: (colors) => colors.icon.muted,
        descriptionColor: (colors) => colors.text.accent,
      ),
    (NetworkPrivacyConnectionStatus.connecting, false) =>
      _NetworkPrivacyPresentation(
        statusLabel: 'Switching to direct…',
        description: isLinux
            ? 'Vizor is switching its requests, including software update '
                  'checks, to a direct connection.'
            : 'Vizor is switching network requests and software updates to a direct connection.',
        statusIconName: AppIcons.loader,
        statusColor: (colors) => colors.text.secondary,
        iconColor: (colors) => colors.icon.brandCrimson,
        descriptionColor: (colors) => colors.text.accent,
      ),
    (NetworkPrivacyConnectionStatus.connected, _) => _NetworkPrivacyPresentation(
      statusLabel: 'Connected',
      description: isLinux
          ? 'Wallet sync, most in-app requests, and software update checks go '
                'through Tor. Update pages and downloads opened in another app '
                'use that app’s connection.'
          : 'Wallet sync, most in-app requests, and software updates go through Tor. Some services may be unavailable over Tor.',
      statusColor: (colors) => colors.text.brandCrimson,
      iconColor: (colors) => colors.icon.brandCrimson,
      descriptionColor: (colors) => colors.text.accent,
    ),
    // Two failure shapes with opposite request behaviour: a bootstrap that
    // failed after the process went fail-closed, and a save that aborted the
    // toggle before anything changed.
    (NetworkPrivacyConnectionStatus.failed, true) =>
      state.torEnabled
          ? _NetworkPrivacyPresentation(
              statusLabel: 'Connection failed',
              description:
                  'Direct requests remain blocked. Try again or turn off Tor.',
              statusColor: (colors) => colors.text.destructive,
              iconColor: (colors) => colors.icon.destructive,
              descriptionColor: (colors) => colors.text.destructive,
            )
          : _NetworkPrivacyPresentation(
              statusLabel: 'Setting not saved',
              description:
                  'Vizor could not save the change, so Tor was not turned '
                  'on. Requests keep using a direct connection.',
              statusColor: (colors) => colors.text.destructive,
              iconColor: (colors) => colors.icon.destructive,
              descriptionColor: (colors) => colors.text.destructive,
            ),
    (NetworkPrivacyConnectionStatus.failed, false) =>
      _NetworkPrivacyPresentation(
        statusLabel: 'Switch failed',
        description:
            'Vizor could not switch to a direct connection. Try again.',
        statusColor: (colors) => colors.text.destructive,
        iconColor: (colors) => colors.icon.destructive,
        descriptionColor: (colors) => colors.text.destructive,
      ),
  };
}
