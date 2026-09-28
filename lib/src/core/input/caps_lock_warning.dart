import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/app_form_factor.dart';
import '../theme/app_theme.dart';
import '../widgets/app_tooltip.dart';
import 'caps_lock_monitor.dart';

/// Enables warnings only for app-password fields, including revealed passwords.
/// The text field places the warning around its input shell, below its label.
class CapsLockWarningScope extends InheritedWidget {
  const CapsLockWarningScope({
    required super.child,
    this.onDarkCard = false,
    super.key,
  });

  final bool onDarkCard;

  static CapsLockWarningScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CapsLockWarningScope>();

  @override
  bool updateShouldNotify(CapsLockWarningScope oldWidget) =>
      onDarkCard != oldWidget.onDarkCard;
}

/// Persistent, non-interactive tooltip for the focused app-password field.
class CapsLockWarning extends ConsumerStatefulWidget {
  const CapsLockWarning({
    required this.child,
    this.hasLabel = false,
    this.onDarkCard = false,
    super.key,
  });
  final bool hasLabel;
  final bool onDarkCard;
  final Widget child;

  @override
  ConsumerState<CapsLockWarning> createState() => _CapsLockWarningState();
}

class _CapsLockWarningState extends ConsumerState<CapsLockWarning> {
  final _overlay = OverlayPortalController();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Keep the portal available; its contents are empty while the warning is
    // hidden. This avoids changing overlay state during a provider rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && kAppFormFactor == AppFormFactor.desktop) _overlay.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor != AppFormFactor.desktop) return widget.child;
    final useLightSurface =
        widget.onDarkCard && context.appTheme == AppThemeData.light;
    final monitor = _focused ? ref.watch(capsLockMonitorProvider) : null;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _overlay,
        overlayChildBuilder: (context, info) {
          if (monitor == null) return const SizedBox.shrink();
          final target = MatrixUtils.transformRect(
            info.childPaintTransform,
            Offset.zero & info.childSize,
          );
          return ListenableBuilder(
            listenable: monitor,
            builder: (context, _) {
              if (monitor.value != true) return const SizedBox.shrink();
              return IgnorePointer(
                child: CustomSingleChildLayout(
                  delegate: _WarningPosition(target, widget.hasLabel),
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: useLightSurface
                          ? AppTooltip.decorationOf(
                              context,
                            ).copyWith(color: context.colors.background.ground)
                          : AppTooltip.decorationOf(context),
                      child: Text(
                        'Caps Lock is on',
                        style: useLightSurface
                            ? AppTooltip.textStyleOf(
                                context,
                              ).copyWith(color: context.colors.text.accent)
                            : AppTooltip.textStyleOf(context),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _WarningPosition extends SingleChildLayoutDelegate {
  const _WarningPosition(this.target, this.hasLabel);
  final bool hasLabel;
  final Rect target;
  static const _gap = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(340, math.max(0, constraints.maxWidth - 16)),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Keep the label on the left and anchor the warning to the input's
    // trailing edge. Unlabelled fields keep a centered warning.
    final x =
        (hasLabel
                ? target.right - childSize.width
                : target.center.dx - childSize.width / 2)
            .clamp(0.0, math.max(0.0, size.width - childSize.width));
    final above = target.top - _gap - childSize.height;
    final y = (above >= 0 ? above : target.bottom + _gap).clamp(
      0.0,
      math.max(0.0, size.height - childSize.height),
    );
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  bool shouldRelayout(_WarningPosition oldDelegate) =>
      target != oldDelegate.target || hasLabel != oldDelegate.hasLabel;
}
