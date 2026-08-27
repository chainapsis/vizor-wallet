import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../providers/private_state_sync_provider.dart';

const _toggleShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

const _description =
    'Sync finalized activity and voting completion state across your devices. '
    'Data is encrypted before upload. When off, Vizor makes no private sync '
    'requests.';

class PrivateStateSyncControl extends ConsumerWidget {
  const PrivateStateSyncControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(privateStateSyncSettingsProvider);
    return _PrivateStateSyncContent(state: state, mobile: false);
  }
}

class MobilePrivateStateSyncCard extends ConsumerWidget {
  const MobilePrivateStateSyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(privateStateSyncSettingsProvider);
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
              'Private sync',
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          _PrivateStateSyncContent(state: state, mobile: true),
        ],
      ),
    );
  }
}

class _PrivateStateSyncContent extends ConsumerWidget {
  const _PrivateStateSyncContent({required this.state, required this.mobile});

  final PrivateStateSyncSettings state;
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = state.displayedEnabled;
    final onToggle = state.isSaving
        ? null
        : () => unawaited(_setPrivateStateSyncEnabled(ref, enabled: !enabled));
    final prefix = mobile ? 'mobile_settings' : 'settings';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrivateStateSyncRow(
          key: ValueKey('${prefix}_private_state_sync_row'),
          enabled: enabled,
          isSaving: state.isSaving,
          mobile: mobile,
          onToggle: onToggle,
        ),
        SizedBox(height: mobile ? AppSpacing.sm : AppSpacing.xs),
        Text(
          _description,
          key: ValueKey('${prefix}_private_state_sync_description'),
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            "Couldn't save the private sync setting.",
            key: ValueKey('${prefix}_private_state_sync_error'),
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _setPrivateStateSyncEnabled(
  WidgetRef ref, {
  required bool enabled,
}) async {
  try {
    await ref
        .read(privateStateSyncSettingsProvider.notifier)
        .setEnabled(enabled);
  } catch (_) {
    // The notifier keeps the error in state for both form factors to render.
  }
}

class _PrivateStateSyncRow extends StatefulWidget {
  const _PrivateStateSyncRow({
    required this.enabled,
    required this.isSaving,
    required this.mobile,
    required this.onToggle,
    super.key,
  });

  final bool enabled;
  final bool isSaving;
  final bool mobile;
  final VoidCallback? onToggle;

  @override
  State<_PrivateStateSyncRow> createState() => _PrivateStateSyncRowState();
}

class _PrivateStateSyncRowState extends State<_PrivateStateSyncRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final interactive = widget.onToggle != null;

    return Semantics(
      button: true,
      toggled: widget.enabled,
      enabled: interactive,
      label: 'Private state sync',
      value: widget.isSaving ? 'Saving' : (widget.enabled ? 'On' : 'Off'),
      onTap: widget.onToggle,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: interactive,
        mouseCursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: _toggleShortcuts,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (_) {
              widget.onToggle?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (focused) {
          if (_focused == focused) return;
          setState(() => _focused = focused);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: widget.mobile ? 32 : 20,
                    child: Center(
                      child: AppIcon(
                        AppIcons.shieldKeyholeOutline,
                        size: 20,
                        color: widget.enabled
                            ? colors.icon.brandCrimson
                            : colors.icon.muted,
                      ),
                    ),
                  ),
                  SizedBox(width: widget.mobile ? AppSpacing.s : AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Private state sync',
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                  if (!widget.mobile) ...[
                    Text(
                      widget.isSaving
                          ? 'Saving…'
                          : (widget.enabled ? 'On' : 'Off'),
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  _PrivateStateSyncToggle(
                    enabled: widget.enabled,
                    mobile: widget.mobile,
                    focused: _focused,
                    interactive: interactive,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivateStateSyncToggle extends StatelessWidget {
  const _PrivateStateSyncToggle({
    required this.enabled,
    required this.mobile,
    required this.focused,
    required this.interactive,
  });

  final bool enabled;
  final bool mobile;
  final bool focused;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = mobile ? 64.0 : 44.0;
    final height = mobile ? 28.0 : 20.0;
    final thumbWidth = mobile ? 40.0 : 28.0;
    final thumbHeight = mobile ? 24.0 : 16.0;

    return Opacity(
      opacity: interactive ? 1 : 0.65,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            key: ValueKey(
              mobile
                  ? 'mobile_settings_private_state_sync_toggle'
                  : 'settings_private_state_sync_toggle',
            ),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: width,
            height: height,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: enabled
                  ? colors.background.brandCrimsonStrong
                  : colors.background.overlay,
              borderRadius: BorderRadius.circular(AppRadii.full),
              border: mobile && !enabled
                  ? Border.all(color: colors.border.regular)
                  : null,
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: SizedBox(width: thumbWidth, height: thumbHeight),
              ),
            ),
          ),
          if (focused)
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
      ),
    );
  }
}
