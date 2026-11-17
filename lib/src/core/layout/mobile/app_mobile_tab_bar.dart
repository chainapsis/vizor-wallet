import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../feedback/app_haptics.dart';
import '../../theme/app_theme.dart';
import 'mobile_tab_bar_icon.dart';

/// Height of [AppMobileTabBar]: 52px items inside 4px padding, a step under
/// Figma `Mobile Nav` (node 4394:88550), which uses 56px items.
const double kMobileTabBarHeight = 60;

/// One destination in the floating mobile tab bar.
class AppMobileTabItem {
  const AppMobileTabItem({required this.iconName, required this.label});

  /// `AppIcons` name rendered at 24px.
  final String iconName;

  /// Accessibility label; the bar itself is icon-only.
  final String label;
}

/// Floating pill-shaped bottom tab bar — Figma `Mobile Nav`
/// (node 4394:88550).
///
/// Shares the glass recipe of the desktop sidebar (17.5px backdrop blur
/// over `macosUtility.navPanel`, thin hairline shadow ring). Items are
/// equal-width; the active one sits on a borderless near-black pill
/// (`navPanel.tabBarActiveBg`) with the crimson active icon
/// (`navPanel.tabBarActiveIcon`). Figma gives
/// the active item a slightly wider fixed width (100px vs flex) — equal
/// widths keep the widget tree shape constant across selection changes
/// and read the same at this size.
///
/// Only transitions move. One shared highlight pill slides between items
/// (instead of fading out/in per item), the icon tint crossfades on the
/// same curve, the newly active icon does a one-shot pop plus its own
/// flourish ([MobileTabBarIcon]), and pressing an item scales its icon
/// down with a light haptic. All of it collapses to instant switches
/// under reduced motion.
class AppMobileTabBar extends StatefulWidget {
  const AppMobileTabBar({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    this.axis = Axis.horizontal,
    super.key,
  });

  final Axis axis;
  final List<AppMobileTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const _blur = 17.5;
  static const _itemHeight = 52.0;
  static const _iconSize = AppIconSize.large;

  /// Horizontal items keep a fixed width, so the bar hugs its tabs instead
  /// of spanning the screen.
  static const _itemWidth = 72.0;

  /// Selection transition — shared by the sliding pill and the icon
  /// tint so they read as one move. The curve is easeOutBack
  /// (cubic(0.34, 1.56, 0.64, 1)) with its back overshoot halved by
  /// lowering the second control point: ~5% past the target instead of
  /// the stock ~10%, which read as too springy.
  static const selectDuration = Duration(milliseconds: 240);
  static const _touchDuration = Duration(milliseconds: 100);
  static const _selectCurve = Cubic(0.34, 1.40, 0.64, 1.0);

  /// Settle after a drag: strong ease-out with no overshoot, so the pill
  /// carries on from the finger and lands without swinging back.
  static const _releaseCurve = Cubic(0.23, 1, 0.32, 1);

  @visibleForTesting
  static const activePillKey = ValueKey('mobile_tab_bar_active_pill');

  @override
  State<AppMobileTabBar> createState() => _AppMobileTabBarState();
}

/// A horizontal touch previews its tab before dragging from that location.
/// Dragging ticks a strong haptic as it crosses into each tab, and
/// on release it projects the flick's momentum, snaps to the nearest tab and
/// selects it. The settle reuses the selection transition, starting from
/// wherever the finger let go.
class _AppMobileTabBarState extends State<AppMobileTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _horizontalPill;
  late double _pillTarget;
  final _interactionKey = GlobalKey();
  // Outlives an invalidated preview until that finger actually lifts.
  int? _activePointer;
  _TabBarTouch? _touch;

  /// Pill position in tab units while a drag is in progress.
  double? _dragPosition;
  double _dragOrigin = 0;
  double _pointerOrigin = 0;
  int _hoveredIndex = 0;

  /// The tab a drag landed on, shown until the caller's selection catches up.
  int? _releasedIndex;

  /// Whether the pill's latest move came from a drag, which settles on
  /// [AppMobileTabBar._releaseCurve] instead of the select curve.
  bool _settlingFromDrag = false;

  bool get _vertical => widget.axis == Axis.vertical;

  double get _itemExtent => _vertical
      ? AppMobileTabBar._itemHeight
      : (_interactionKey.currentContext?.size?.width ??
                AppMobileTabBar._itemWidth * widget.items.length) /
            widget.items.length;

  int get _selectedIndex => _releasedIndex ?? widget.currentIndex;

  double _along(Offset position) => _vertical ? position.dy : position.dx;

  bool get _motion => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  double get _horizontalPosition {
    final touch = _touch;
    final position = _horizontalPill.value + (touch?.delta ?? 0);
    return touch == null
        ? position
        : position.clamp(0.0, widget.items.length - 1.0);
  }

  void _animatePill() => setState(() {});

  void _movePill(double target, Duration duration, Curve curve) {
    _pillTarget = target;
    if (_motion) {
      unawaited(
        _horizontalPill.animateTo(target, duration: duration, curve: curve),
      );
    } else {
      _horizontalPill.value = target;
    }
  }

  @override
  void initState() {
    super.initState();
    _pillTarget = widget.currentIndex.toDouble();
    _horizontalPill = AnimationController.unbounded(
      vsync: this,
      value: _pillTarget,
    )..addListener(_animatePill);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motion && _horizontalPill.isAnimating) {
      _horizontalPill.value = _pillTarget;
    }
  }

  @override
  void dispose() {
    _horizontalPill.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppMobileTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The caller has answered the drop: follow its selection from here on.
    final releasedIndex = _releasedIndex;
    _releasedIndex = null;
    final destinationsChanged =
        oldWidget.axis != widget.axis ||
        oldWidget.items.length != widget.items.length ||
        List.generate(widget.items.length, (i) => i).any(
          (i) =>
              oldWidget.items[i].iconName != widget.items[i].iconName ||
              oldWidget.items[i].label != widget.items[i].label,
        );
    if (destinationsChanged ||
        (_touch != null && oldWidget.currentIndex != widget.currentIndex)) {
      final position = _horizontalPosition;
      _touch = null;
      _dragPosition = null;
      _horizontalPill.value = position;
    }
    if (!_vertical &&
        (destinationsChanged ||
            (oldWidget.currentIndex != widget.currentIndex &&
                widget.currentIndex != releasedIndex) ||
            (releasedIndex != null && widget.currentIndex != releasedIndex))) {
      _movePill(
        widget.currentIndex.toDouble(),
        AppMobileTabBar.selectDuration,
        _settlingFromDrag
            ? AppMobileTabBar._releaseCurve
            : AppMobileTabBar._selectCurve,
      );
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null ||
        widget.items.isEmpty ||
        event.buttons != kPrimaryButton) {
      return;
    }
    final index = (event.localPosition.dx / _itemExtent).floor().clamp(
      0,
      widget.items.length - 1,
    );
    _beginTouch(event.pointer, index);
  }

  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    if (_activePointer != null || widget.items.isEmpty) return;
    // Trackpads have no pressed destination: preserve their selected-tab
    // origin while sharing release, momentum and cancellation handling.
    _beginTouch(event.pointer, _selectedIndex);
  }

  void _beginTouch(int pointer, int index) {
    final position = _horizontalPosition;
    _horizontalPill.stop();
    _horizontalPill.value = position;
    setState(() {
      _activePointer = pointer;
      _touch = _TabBarTouch(index);
    });
    _movePill(
      index.toDouble(),
      AppMobileTabBar._touchDuration,
      AppMobileTabBar._releaseCurve,
    );
  }

  void _cancelTouch() {
    if (_touch == null) return;
    final position = _horizontalPosition;
    setState(() => _touch = null);
    _horizontalPill.value = position;
    _movePill(
      widget.currentIndex.toDouble(),
      AppMobileTabBar.selectDuration,
      AppMobileTabBar._releaseCurve,
    );
  }

  void _cancelUnclaimedTouch(_TabBarTouch? touch) {
    // Tap cancellation also happens when the drag wins. Let the arena finish
    // dispatching before deciding whether neither recognizer owns this touch.
    scheduleMicrotask(() {
      if (mounted &&
          touch != null &&
          identical(_touch, touch) &&
          !touch.dragging) {
        _cancelTouch();
      }
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    _endPointer(event.pointer);
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    _endPointer(event.pointer);
  }

  void _endPointer(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    _cancelUnclaimedTouch(_touch);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _cancelTouch();
  }

  void _handleTap(int index, {bool semantics = false}) {
    if (!_vertical) {
      final touch = _touch;
      if (!semantics &&
          (touch == null || touch.index != index || touch.dragging)) {
        return;
      }
      final position = _horizontalPosition;
      setState(() {
        _touch = null;
        _releasedIndex = index;
        _settlingFromDrag = false;
      });
      // A quick tap completes the already-running 100ms arrival. Restarting
      // the normal 240ms selection here would make that arrival feel slow.
      if (semantics) {
        _horizontalPill.value = position;
        _movePill(
          index.toDouble(),
          AppMobileTabBar.selectDuration,
          AppMobileTabBar._selectCurve,
        );
      }
    } else {
      setState(() => _settlingFromDrag = false);
    }
    unawaited(AppHaptics.tabSwitch());
    widget.onSelect(index);
  }

  void _handleDragStart(DragStartDetails details) {
    if (widget.items.length < 2) return;
    if (!_vertical) {
      final touch = _touch;
      if (touch == null) return;
      touch.dragging = true;
      if (touch.index != widget.currentIndex) unawaited(AppHaptics.tabSwitch());
      return;
    }
    _pointerOrigin = _along(details.localPosition);
    _hoveredIndex = _selectedIndex;
    setState(() {
      _dragOrigin = _selectedIndex.toDouble();
      _dragPosition = _dragOrigin;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_vertical) {
      final touch = _touch;
      if (touch == null || !touch.dragging) return;
      // Delta is a vector for both touch and trackpad events; pan-zoom
      // localPosition can include a translated pan origin.
      touch.delta += details.delta.dx / _itemExtent;
      final hovered = (touch.index + touch.delta)
          .clamp(0.0, widget.items.length - 1.0)
          .round();
      if (hovered != touch.hoveredIndex) {
        touch.hoveredIndex = hovered;
        unawaited(AppHaptics.tabSwitch());
      }
      setState(() {});
      return;
    }
    if (_dragPosition == null) return;
    final position =
        (_dragOrigin +
                (_along(details.localPosition) - _pointerOrigin) / _itemExtent)
            .clamp(0.0, widget.items.length - 1.0);
    final hovered = position.round();
    if (hovered != _hoveredIndex) {
      _hoveredIndex = hovered;
      unawaited(AppHaptics.tabSwitch());
    }
    setState(() => _dragPosition = position);
  }

  void _handleDragEnd(DragEndDetails details) {
    final touch = _touch;
    final position = _vertical
        ? _dragPosition
        : touch == null || !touch.dragging
        ? null
        : (touch.index + touch.delta).clamp(0.0, widget.items.length - 1.0);
    if (position == null) return;
    // Apple's momentum projection (deceleration rate 0.99): where a flick
    // would come to rest, so a quick throw carries the pill a tab further.
    final velocity = details.primaryVelocity ?? 0;
    final projected =
        position + velocity / 1000 * 0.99 / (1 - 0.99) / _itemExtent;
    final target = projected.round().clamp(0, widget.items.length - 1);
    if (target != (touch?.hoveredIndex ?? _hoveredIndex)) {
      unawaited(AppHaptics.tabSwitch());
    }
    final displayedPosition = _horizontalPosition;
    setState(() {
      _touch = null;
      _dragPosition = null;
      _releasedIndex = target;
      _settlingFromDrag = true;
    });
    if (!_vertical) {
      _horizontalPill.value = displayedPosition;
      _movePill(
        target.toDouble(),
        AppMobileTabBar.selectDuration,
        AppMobileTabBar._releaseCurve,
      );
    }
    if (target != widget.currentIndex) widget.onSelect(target);
  }

  /// How much of the pill at [pillPosition] covers item [index], eased so
  /// an icon tints as the pill arrives rather than at the halfway point.
  static double _pillCoverage(double pillPosition, int index) {
    final t = (1 - (pillPosition - index).abs()).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  void _handleDragCancel() {
    if (!_vertical) {
      if (_touch?.dragging ?? false) {
        _cancelTouch();
      } else {
        _cancelUnclaimedTouch(_touch);
      }
      return;
    }
    if (_dragPosition == null) return;
    setState(() => _dragPosition = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadii.full);
    final motion = _motion;
    final vertical = _vertical;
    final items = widget.items;
    final selectedIndex = _selectedIndex;
    final dragging = _dragPosition != null;
    final pillPosition = vertical
        ? _dragPosition ?? selectedIndex.toDouble()
        : _horizontalPosition;
    final selection = items.length > 1
        ? -1 + 2 * pillPosition / (items.length - 1)
        : 0.0;
    final pillAlignment = Alignment(
      vertical ? 0 : selection,
      vertical ? selection : 0,
    );

    final bar = SizedBox(
      height: vertical
          ? AppMobileTabBar._itemHeight * items.length + 8
          : kMobileTabBarHeight,
      width: vertical
          ? kMobileTabBarHeight
          : AppMobileTabBar._itemWidth * items.length + AppSpacing.xxs * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: colors.macosUtility.thinBorder,
              blurRadius: 0,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.05),
              offset: const Offset(0, 25),
              blurRadius: 25,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: AppMobileTabBar._blur,
              sigmaY: AppMobileTabBar._blur,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.macosUtility.navPanel,
                borderRadius: radius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: Listener(
                  key: _interactionKey,
                  onPointerDown: vertical ? null : _handlePointerDown,
                  onPointerUp: vertical ? null : _handlePointerUp,
                  onPointerCancel: vertical ? null : _handlePointerCancel,
                  onPointerPanZoomStart: vertical ? null : _handlePanZoomStart,
                  onPointerPanZoomEnd: vertical ? null : _handlePanZoomEnd,
                  child: RawGestureDetector(
                    gestures: {
                      if (!vertical)
                        _SinglePointerHorizontalDragRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              _SinglePointerHorizontalDragRecognizer
                            >(
                              () => _SinglePointerHorizontalDragRecognizer(),
                              (instance) => instance
                                ..dragStartBehavior = DragStartBehavior.down
                                ..onStart = _handleDragStart
                                ..onUpdate = _handleDragUpdate
                                ..onEnd = _handleDragEnd
                                ..onCancel = _handleDragCancel,
                            ),
                    },
                    child: GestureDetector(
                      // Count from touch-down so the pill stays under the
                      // finger instead of trailing it by the drag slop.
                      dragStartBehavior: DragStartBehavior.down,
                      onVerticalDragStart: vertical ? _handleDragStart : null,
                      onVerticalDragUpdate: vertical ? _handleDragUpdate : null,
                      onVerticalDragEnd: vertical ? _handleDragEnd : null,
                      onVerticalDragCancel: vertical ? _handleDragCancel : null,
                      child: Stack(
                        children: [
                          AnimatedAlign(
                            key: AppMobileTabBar.activePillKey,
                            // The pill tracks a drag 1:1, then settles on release.
                            duration: vertical && motion && !dragging
                                ? AppMobileTabBar.selectDuration
                                : Duration.zero,
                            curve: _settlingFromDrag
                                ? AppMobileTabBar._releaseCurve
                                : AppMobileTabBar._selectCurve,
                            alignment: pillAlignment,
                            child: FractionallySizedBox(
                              widthFactor: vertical ? 1 : 1 / items.length,
                              heightFactor: vertical ? 1 / items.length : null,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.navPanel.tabBarActiveBg,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.full,
                                  ),
                                ),
                                child: SizedBox(
                                  height: vertical
                                      ? double.infinity
                                      : AppMobileTabBar._itemHeight,
                                ),
                              ),
                            ),
                          ),
                          Flex(
                            direction: widget.axis,
                            children: [
                              for (var i = 0; i < items.length; i++)
                                Expanded(
                                  child: _TabBarItem(
                                    item: items[i],
                                    active: i == selectedIndex,
                                    motion: motion,
                                    highlight: dragging || !vertical
                                        ? _pillCoverage(pillPosition, i)
                                        : null,
                                    onTap: () => _handleTap(i),
                                    onSemanticsTap: () =>
                                        _handleTap(i, semantics: true),
                                    onTapCancel: () {
                                      if (!vertical && _touch?.index == i) {
                                        _cancelUnclaimedTouch(_touch);
                                      }
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The shell hands the bar the full width; centre it at its own width.
    return vertical ? bar : Center(heightFactor: 1, child: bar);
  }
}

class _TabBarTouch {
  _TabBarTouch(this.index) : hoveredIndex = index;

  final int index;
  double delta = 0;
  bool dragging = false;
  int hoveredIndex;
}

/// A second finger must not take over the first finger's position or velocity.
class _SinglePointerHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  int? _pointer;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      _pointer == null && super.isPointerAllowed(event);

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      _pointer == null && super.isPointerPanZoomAllowed(event);

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    // OneSequenceGestureRecognizer's default rejects every tracked pointer.
    // Ignoring a second finger must leave the first finger's arena intact.
    if (_pointer == null) super.handleNonAllowedPointer(event);
  }

  @override
  void handleNonAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (_pointer == null) super.handleNonAllowedPointerPanZoom(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointer = event.pointer;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _pointer = event.pointer;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    _pointer = null;
  }
}

class _TabBarItem extends StatefulWidget {
  const _TabBarItem({
    required this.item,
    required this.active,
    required this.motion,
    required this.onTap,
    required this.onSemanticsTap,
    required this.onTapCancel,
    this.highlight,
  });

  final AppMobileTabItem item;
  final bool active;
  final bool motion;
  final VoidCallback onTap;
  final VoidCallback onSemanticsTap;
  final VoidCallback onTapCancel;

  /// While the pill is dragged, how much of it covers this item (0 → 1);
  /// the icon tint follows it directly. Null when nothing is dragged.
  final double? highlight;

  @override
  State<_TabBarItem> createState() => _TabBarItemState();
}

class _TabBarItemState extends State<_TabBarItem>
    with TickerProviderStateMixin {
  /// One-shot, subtle lift when this item becomes the active one, timed
  /// to land with the arriving pill.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.04,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.04,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 55,
    ),
  ]).animate(_pop);

  /// The icon's own flourish (see [MobileTabBarIcon]), played with the pop.
  late final AnimationController _flourish = AnimationController(
    vsync: this,
    duration: MobileTabBarIcon.durationFor(widget.item.iconName),
  );

  var _pressed = false;

  @override
  void didUpdateWidget(covariant _TabBarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && widget.motion) {
      _pop.forward(from: 0);
      // A tab re-selected mid-flourish lets it finish rather than jump back.
      if (!_flourish.isAnimating) _flourish.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    _flourish.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (!widget.motion || _pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Inactive items use the muted decorative tint per the Figma nav
    // (grey, not the max-contrast accent).
    final highlight = widget.highlight;
    final iconColor = highlight != null
        ? Color.lerp(
            colors.icon.muted,
            colors.navPanel.tabBarActiveIcon,
            highlight,
          )!
        : widget.active
        ? colors.navPanel.tabBarActiveIcon
        : colors.icon.muted;

    return Semantics(
      label: widget.item.label,
      button: true,
      selected: widget.active,
      onTap: widget.onSemanticsTap,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () {
          _setPressed(false);
          widget.onTapCancel();
        },
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          widget.onTap();
        },
        child: SizedBox(
          height: AppMobileTabBar._itemHeight,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.96 : 1.0,
              duration: Duration(milliseconds: _pressed ? 100 : 160),
              curve: Curves.easeOut,
              child: ScaleTransition(
                scale: _popScale,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: iconColor),
                  // A dragged pill drives the tint directly; otherwise it
                  // crossfades with the sliding pill.
                  duration: widget.motion && highlight == null
                      ? AppMobileTabBar.selectDuration
                      : Duration.zero,
                  builder: (_, color, _) => MobileTabBarIcon(
                    iconName: widget.item.iconName,
                    size: AppMobileTabBar._iconSize,
                    color: color ?? iconColor,
                    progress: _flourish,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
