import 'dart:async';

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
    final presentation = _presentationFor(state);

    final content = Padding(
      padding:
          showSurface
              ? const EdgeInsets.all(AppSpacing.sm)
              : const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      state.torEnabled
                          ? colors.background.brandCrimsonSubtle
                          : colors.background.raised,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.shieldKeyholeOutline,
                  size: 20,
                  color:
                      state.torEnabled
                          ? colors.icon.brandCrimson
                          : colors.icon.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        if (presentation.iconName != null) ...[
                          AppIcon(
                            presentation.iconName!,
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
                            style: AppTypography.bodySmall.copyWith(
                              color: presentation.statusColor(colors),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              _NetworkPrivacyToggle(
                key: const ValueKey('network_privacy_toggle'),
                enabled: state.torEnabled,
                busy: state.isBusy,
                onToggle:
                    state.isBusy
                        ? null
                        : () => unawaited(
                          ref
                              .read(networkPrivacyProvider.notifier)
                              .setTorEnabled(!state.torEnabled),
                        ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            child: Text(
              presentation.description,
              key: ValueKey(
                'network_privacy_description_${state.status.name}_${state.torEnabled}',
              ),
              style: AppTypography.bodySmall.copyWith(
                color:
                    state.status == NetworkPrivacyConnectionStatus.failed
                        ? colors.text.destructive
                        : colors.text.secondary,
              ),
            ),
          ),
          if (state.status == NetworkPrivacyConnectionStatus.failed) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                onPressed:
                    () => unawaited(
                      ref
                          .read(networkPrivacyProvider.notifier)
                          .setTorEnabled(state.torEnabled),
                    ),
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.small,
                leading: const AppIcon(AppIcons.renew),
                child: Text(
                  state.torEnabled ? 'Try again' : 'Try direct connection',
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (!showSurface) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: content,
    );
  }
}

class _NetworkPrivacyToggle extends StatefulWidget {
  const _NetworkPrivacyToggle({
    required this.enabled,
    required this.busy,
    required this.onToggle,
    super.key,
  });

  final bool enabled;
  final bool busy;
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
      width: 48,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color:
            widget.enabled
                ? colors.background.brandCrimsonStrong
                : colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(
          color:
              widget.enabled
                  ? colors.border.brandCrimsonStrong
                  : colors.border.regular,
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment:
            widget.enabled ? Alignment.centerRight : Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: const SizedBox.square(dimension: 18),
        ),
      ),
    );

    final control = Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(opacity: widget.busy ? 0.65 : 1, child: track),
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
      label: 'Use Tor',
      excludeSemantics: true,
      child: MouseRegion(
        cursor:
            interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: FocusableActionDetector(
          enabled: interactive,
          mouseCursor:
              interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
              width: 48,
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
    this.iconName,
  });

  final String statusLabel;
  final String description;
  final String? iconName;
  final Color Function(AppColors colors) statusColor;
}

_NetworkPrivacyPresentation _presentationFor(NetworkPrivacyState state) {
  return switch ((state.status, state.torEnabled)) {
    (NetworkPrivacyConnectionStatus.off, _) => _NetworkPrivacyPresentation(
      statusLabel: 'Direct',
      description:
          'Tor is off. Requests to the Zcash network and in-app services connect directly.',
      statusColor: (colors) => colors.text.secondary,
    ),
    (NetworkPrivacyConnectionStatus.connecting, true) =>
      _NetworkPrivacyPresentation(
        statusLabel: 'Connecting…',
        description: 'New requests wait until the Tor connection is ready.',
        iconName: AppIcons.loader,
        statusColor: (colors) => colors.text.brandCrimson,
      ),
    (NetworkPrivacyConnectionStatus.connecting, false) =>
      _NetworkPrivacyPresentation(
        statusLabel: 'Switching to direct…',
        description:
            'Active Tor requests finish before Vizor returns to a direct connection.',
        iconName: AppIcons.loader,
        statusColor: (colors) => colors.text.secondary,
      ),
    (NetworkPrivacyConnectionStatus.connected, _) => _NetworkPrivacyPresentation(
      statusLabel: 'Connected',
      description:
          'Requests to the Zcash network and in-app services use Tor. Update checks pause, and some services may not work.',
      iconName: AppIcons.checkCircle,
      statusColor: (colors) => colors.text.positiveStrong,
    ),
    (NetworkPrivacyConnectionStatus.failed, true) =>
      _NetworkPrivacyPresentation(
        statusLabel: 'Connection failed',
        description:
            'Direct requests remain blocked. Try again or turn off Tor.',
        iconName: AppIcons.warning,
        statusColor: (colors) => colors.text.destructive,
      ),
    (NetworkPrivacyConnectionStatus.failed, false) =>
      _NetworkPrivacyPresentation(
        statusLabel: 'Switch failed',
        description:
            'Vizor could not switch to a direct connection. Try again.',
        iconName: AppIcons.warning,
        statusColor: (colors) => colors.text.destructive,
      ),
  };
}
