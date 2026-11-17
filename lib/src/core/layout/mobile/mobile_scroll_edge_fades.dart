import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// The standard soft edges for mobile scroll areas: below this widget, every
/// vertical scroll view dissolves its content into [color] at the edge where
/// it is cut, instead of clipping rows flat.
///
/// It works through the [ScrollBehavior], so each scroll view fades at its
/// own edges with no wrapper of its own, and one that fits shows nothing:
/// a fade rises over the first [AppSpacing.md] of content hidden past that
/// edge. Every mobile page ([MobilePageViewport], window color) and sheet
/// ([MobileModalCard], sheet surface) installs it, so new screens get it by
/// default.
///
/// Text fields keep their own scrolling untouched. A scroll area that draws
/// a tuned fade of its own at one edge ([MobileTopScrollFade],
/// [MobileBottomScrollFade]) turns that edge off below it and keeps the other;
/// [MobileScrollEdgeFades.off] turns both off.
class MobileScrollEdgeFades extends StatelessWidget {
  /// Each value left null is inherited from the nearest [MobileScrollEdgeFades]
  /// above (the band heights default to [AppSpacing.base]). With no [color]
  /// given or inherited, there are no fades.
  const MobileScrollEdgeFades({
    required this.child,
    this.color,
    this.topHeight,
    this.bottomHeight,
    super.key,
  }) : _off = false;

  /// No standard fades below this point, for a region that draws its own.
  const MobileScrollEdgeFades.off({required this.child, super.key})
    : color = null,
      topHeight = null,
      bottomHeight = null,
      _off = true;

  /// The surface behind the scroll areas, which the content fades into.
  final Color? color;

  /// Height of the band at the top edge; 0 turns that edge off.
  final double? topHeight;

  /// Height of the band at the bottom edge; 0 turns that edge off.
  final double? bottomHeight;

  final Widget child;
  final bool _off;

  @override
  Widget build(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_EdgeFadesScope>()
        ?.style;
    final color = this.color ?? inherited?.color;
    final scope = _EdgeFadesScope(
      style: _off || color == null
          ? null
          : (
              color: color,
              top: topHeight ?? inherited?.top ?? AppSpacing.base,
              bottom: bottomHeight ?? inherited?.bottom ?? AppSpacing.base,
            ),
      child: child,
    );
    // The fades read the nearest scope, so an off switch or a new color
    // holds even below a scroll view that re-wraps the inherited behavior
    // (`ScrollConfiguration.of(context).copyWith(...)`). The behavior itself
    // goes in once, under the outermost scope.
    if (context.getInheritedWidgetOfExactType<_EdgeFadesScope>() != null) {
      return scope;
    }
    return ScrollConfiguration(
      behavior: _EdgeFadeScrollBehavior(base: ScrollConfiguration.of(context)),
      child: scope,
    );
  }
}

typedef _FadeStyle = ({Color color, double top, double bottom});

class _EdgeFadesScope extends InheritedWidget {
  const _EdgeFadesScope({required this.style, required super.child});

  /// Null turns the fades off.
  final _FadeStyle? style;

  @override
  bool updateShouldNotify(_EdgeFadesScope oldWidget) =>
      style != oldWidget.style;
}

/// Everything as the inherited behavior does it, plus the edge fades around
/// each vertical scroll view's viewport.
class _EdgeFadeScrollBehavior extends ScrollBehavior {
  const _EdgeFadeScrollBehavior({required this.base});

  final ScrollBehavior base;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final indicator = base.buildOverscrollIndicator(context, child, details);
    final style = context
        .dependOnInheritedWidgetOfExactType<_EdgeFadesScope>()
        ?.style;
    if (style == null ||
        axisDirectionToAxis(details.direction) != Axis.vertical) {
      return indicator;
    }
    return _ScrollEdgeFade(
      style: style,
      reversed: details.direction == AxisDirection.up,
      child: indicator,
    );
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => base.buildScrollbar(context, child, details);

  @override
  TargetPlatform getPlatform(BuildContext context) => base.getPlatform(context);

  @override
  Set<PointerDeviceKind> get dragDevices => base.dragDevices;

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      base.getMultitouchDragStrategy(context);

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers => base.pointerAxisModifiers;

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      base.velocityTrackerBuilder(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      base.getScrollPhysics(context);

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => base.getKeyboardDismissBehavior(context);

  @override
  bool shouldNotify(_EdgeFadeScrollBehavior oldDelegate) =>
      base.runtimeType != oldDelegate.base.runtimeType ||
      base.shouldNotify(oldDelegate.base);
}

class _ScrollEdgeFade extends StatefulWidget {
  const _ScrollEdgeFade({
    required this.style,
    required this.reversed,
    required this.child,
  });

  final _FadeStyle style;

  /// A reversed list grows upward, so its leading edge is the bottom one.
  final bool reversed;
  final Widget child;

  @override
  State<_ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<_ScrollEdgeFade> {
  double _top = 0;
  double _bottom = 0;

  static const _activationDistance = AppSpacing.md;

  // Smoothstep 3t² − 2t³ sampled at nine points: an eased dissolve from the
  // surface color at the cut edge to clear.
  static const _stops = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0];
  static const _alphas = [
    1.0,
    0.957,
    0.844,
    0.684,
    0.5,
    0.316,
    0.156,
    0.043,
    0.0,
  ];

  static double _ease(double extent) {
    final t = (extent / _activationDistance).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  // Metrics notifications cover the first layout and resizes, which content
  // that already overflows at rest never reports as a scroll.
  bool _onMetrics(int depth, ScrollMetrics metrics) {
    if (depth != 0 || metrics.axis != Axis.vertical) return false;
    final before = _ease(metrics.extentBefore);
    final after = _ease(metrics.extentAfter);
    _set(widget.reversed ? after : before, widget.reversed ? before : after);
    return false; // Observe only; let the notification bubble on.
  }

  void _set(double top, double bottom) {
    if (top == _top && bottom == _bottom) return;
    // A position re-settling after its content changed size notifies
    // mid-layout, when no rebuild may be scheduled; apply those after the
    // frame instead.
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (!mounted || (top == _top && bottom == _bottom)) return;
        setState(() {
          _top = top;
          _bottom = bottom;
        });
      });
      return;
    }
    setState(() {
      _top = top;
      _bottom = bottom;
    });
  }

  Widget _band({required bool atTop, required double progress}) {
    final color = widget.style.color;
    return IgnorePointer(
      child: DecoratedBox(
        key: ValueKey(
          atTop
              ? 'mobile_scroll_edge_fade_top'
              : 'mobile_scroll_edge_fade_bottom',
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
            stops: _stops,
            colors: [
              for (final alpha in _alphas)
                color.withValues(alpha: color.a * alpha * progress),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.depth, n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.depth, n.metrics),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_top > 0 && style.top > 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: style.top,
                child: _band(atTop: true, progress: _top),
              ),
            if (_bottom > 0 && style.bottom > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: style.bottom,
                child: _band(atTop: false, progress: _bottom),
              ),
          ],
        ),
      ),
    );
  }
}
