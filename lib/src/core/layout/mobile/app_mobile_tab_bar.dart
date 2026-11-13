import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../feedback/app_haptics.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon.dart';

/// Height of [AppMobileTabBar] — Figma `Mobile Nav` (node 4394:88550):
/// 56px items inside 4px padding.
const double kMobileTabBarHeight = 64;

/// One destination in the floating mobile tab bar.
class AppMobileTabItem {
  const AppMobileTabItem({required this.iconName, required this.label});

  /// `AppIcons` name rendered at 28px.
  final String iconName;

  /// Accessibility label; the bar itself is icon-only.
  final String label;
}

/// Floating pill-shaped bottom tab bar — Figma `Mobile Nav`
/// (node 4394:88550).
///
/// Shares the glass recipe of the desktop sidebar (17.5px backdrop blur
/// over `macosUtility.navPanel`, thin hairline shadow ring). Items are
/// equal-width; the active one is tinted with the nav panel active
/// tokens. Figma gives the active item a slightly wider fixed width
/// (100px vs flex) — equal widths keep the widget tree shape constant
/// across selection changes and read the same at this size.
///
/// The resting states match the Figma frame exactly; only transitions
/// move. One shared highlight pill slides between items (instead of
/// fading out/in per item), the icon tint crossfades on the same curve,
/// the newly active icon does a one-shot pop, and pressing an item
/// scales its icon down with a light haptic. All of it collapses to
/// instant switches under reduced motion.
///
/// On iOS, horizontal bottom tabs use Liquid Glass with the same geometry,
/// assets and semantic color tokens. Side tabs and other platforms retain the
/// original surface. Reduced motion also retains the instant-switch surface,
/// avoiding the package's draggable indicator springs.
/// Liquid Glass touch interactions preview the lens locally and select the
/// destination only on release; cancellation keeps the original destination.
class AppMobileTabBar extends StatelessWidget {
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
  static const _itemHeight = 56.0;
  static const _iconSize = 28.0;

  /// Selection transition — shared by the sliding pill and the icon
  /// tint so they read as one move. The curve is easeOutBack
  /// (cubic(0.34, 1.56, 0.64, 1)) with its back overshoot halved by
  /// lowering the second control point: ~5% past the target instead of
  /// the stock ~10%, which read as too springy.
  static const selectDuration = Duration(milliseconds: 240);
  static const _selectCurve = Cubic(0.34, 1.40, 0.64, 1.0);

  @visibleForTesting
  static const activePillKey = ValueKey('mobile_tab_bar_active_pill');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadii.full);
    final vertical = axis == Axis.vertical;
    final iosBottomTabs =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !vertical;
    final motion =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        !(iosBottomTabs &&
            View.of(
              context,
            ).platformDispatcher.accessibilityFeatures.reduceMotion);
    if (iosBottomTabs && motion) {
      return _IosLiquidTabBar(
        items: items,
        currentIndex: currentIndex,
        onSelect: onSelect,
      );
    }
    final selection = items.length > 1
        ? -1 + 2 * currentIndex / (items.length - 1)
        : 0.0;
    final pillAlignment = Alignment(
      vertical ? 0 : selection,
      vertical ? selection : 0,
    );

    return SizedBox(
      height: vertical ? _itemHeight * items.length + 8 : kMobileTabBarHeight,
      width: vertical ? kMobileTabBarHeight : null,
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
            filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.macosUtility.navPanel,
                borderRadius: radius,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: Stack(
                  children: [
                    AnimatedAlign(
                      key: activePillKey,
                      duration: motion ? selectDuration : Duration.zero,
                      curve: _selectCurve,
                      alignment: pillAlignment,
                      child: FractionallySizedBox(
                        widthFactor: vertical ? 1 : 1 / items.length,
                        heightFactor: vertical ? 1 / items.length : null,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.navPanel.activeBg,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                            border: Border.all(
                              color: colors.border.subtleOpacity,
                            ),
                          ),
                          child: SizedBox(
                            height: vertical ? double.infinity : _itemHeight,
                          ),
                        ),
                      ),
                    ),
                    Flex(
                      direction: axis,
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: _TabBarItem(
                              item: items[i],
                              active: i == currentIndex,
                              motion: motion,
                              onTap: () => onSelect(i),
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
    );
  }
}

class _IosLiquidTabBar extends StatefulWidget {
  const _IosLiquidTabBar({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<AppMobileTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  State<_IosLiquidTabBar> createState() => _IosLiquidTabBarState();
}

class _IosLiquidTabBarState extends State<_IosLiquidTabBar> {
  final _touches = <int>{};
  int? _pointer;
  int? _previewIndex;
  int? _lastNotifiedIndex;
  var _finishing = false;
  var _interactionId = 0;
  var _rendererGeneration = 0;

  @override
  void didUpdateWidget(covariant _IosLiquidTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    var destinationsChanged = oldWidget.items.length != widget.items.length;
    if (!destinationsChanged) {
      for (var i = 0; i < widget.items.length; i++) {
        if (oldWidget.items[i].iconName != widget.items[i].iconName ||
            oldWidget.items[i].label != widget.items[i].label) {
          destinationsChanged = true;
          break;
        }
      }
    }
    final indexChanged = oldWidget.currentIndex != widget.currentIndex;
    if (destinationsChanged ||
        (indexChanged && widget.currentIndex != _lastNotifiedIndex)) {
      _resetInteraction();
    }
    if (indexChanged) _lastNotifiedIndex = null;
  }

  void _resetInteraction() {
    _pointer = null;
    _previewIndex = null;
    _finishing = false;
    _interactionId++;
    // Dispose the package's recognizer on cancellation. Its drag-cancel and
    // recovery callbacks can otherwise select a tab after the touch was lost.
    _rendererGeneration++;
  }

  void _onPointerDown(PointerDownEvent event) {
    _touches.add(event.pointer);
    if (_touches.length > 1) {
      setState(_resetInteraction);
      return;
    }
    // A second tap can begin before the preceding release's frame completes.
    // Its final callback has already run, so finish it before starting anew.
    _finishSelection();
    setState(() {
      _pointer = event.pointer;
      _interactionId++;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _touches.remove(event.pointer);
    if (event.pointer != _pointer) return;
    setState(() {
      _pointer = null;
      _finishing = true;
    });
    unawaited(_finishAfterFrame(_interactionId));
  }

  Future<void> _finishAfterFrame(int interactionId) async {
    // Raw pointer-up precedes the package's tap/drag-end callbacks. Its
    // recovery can also run post-frame; collect the final target before routing.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || interactionId != _interactionId) return;
    _finishSelection();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _touches.remove(event.pointer);
    if (event.pointer == _pointer) setState(_resetInteraction);
  }

  void _onTabSelected(int generation, int index) {
    if (generation != _rendererGeneration) return;
    if (_pointer != null || _finishing) {
      setState(() => _previewIndex = index);
    } else if (_touches.isEmpty) {
      // VoiceOver and keyboard activation have no pointer lifecycle to await.
      _select(index);
    }
  }

  void _finishSelection() {
    if (!_finishing) return;
    final index = _previewIndex;
    setState(() {
      _previewIndex = null;
      _finishing = false;
      _interactionId++;
    });
    if (index != null) _select(index);
  }

  void _select(int index) {
    _lastNotifiedIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only recognize an immediate parent echo. A declined selection must not
      // make an unrelated later navigation look like our own confirmation.
      if (mounted && _lastNotifiedIndex == index) _lastNotifiedIndex = null;
    });
    unawaited(AppHaptics.auxiliaryKey());
    widget.onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // AppTheme is authoritative even when the user's choice differs from the
    // OS appearance. Scope this to the bar; no global package configuration.
    final brightness = context.appTheme == AppThemeData.dark
        ? Brightness.dark
        : Brightness.light;
    final settings = brightness == Brightness.dark
        ? LiquidGlassSettings.ios27Dark
        : LiquidGlassSettings.ios27Light;

    final generation = _rendererGeneration;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GlassTheme(
        data: GlassThemeData.ios27(brightness: brightness),
        child: GlassTabBar.bottom(
          key: ValueKey(generation),
          tabs: [
            for (final item in widget.items)
              GlassTab(
                icon: AppIcon(item.iconName, size: AppMobileTabBar._iconSize),
                semanticLabel: item.label,
              ),
          ],
          selectedIndex: _previewIndex ?? widget.currentIndex,
          onTabSelected: (index) => _onTabSelected(generation, index),
          // The shell already owns the outer margins and home-indicator inset.
          horizontalPadding: 0,
          verticalPadding: 0,
          barHeight: kMobileTabBarHeight,
          barBorderRadius: kMobileTabBarHeight / 2,
          // Keep a capsule even as the spring expands the lens past its
          // resting height; the bar's fixed radius would leave square corners.
          indicatorBorderRadius: GlassDefaults.capsuleRadius,
          tabPadding: const EdgeInsets.all(AppSpacing.xxs),
          iconSize: AppMobileTabBar._iconSize,
          selectedIconColor: colors.navPanel.activeIcon,
          unselectedIconColor: colors.icon.muted,
          indicatorColor: colors.navPanel.activeBg,
          settings: settings.copyWith(
            glassColor: colors.macosUtility.navPanel,
            // Soften background detail with a denser frost while retaining the
            // rim's refraction as content scrolls under the bar.
            blur: 1.2,
            frost: 24,
            frostOpacity: brightness == Brightness.dark ? 0.90 : 0.85,
            thickness: 36,
            refractiveIndex: 1.30,
            chromaticAberration: 0.15,
          ),
          // Make the moving lens's dispersion stronger than the iOS 27 shader's
          // pinch-driven baseline, retaining its unblurred icon layer.
          indicatorSettings: LiquidGlassSettings.ios27Indicator.copyWith(
            chromaticAberration: 0.45,
          ),
          quality: GlassQuality.premium,
          // Keep icon magnification and whole-bar inflation subtle; let the
          // selection lens bloom more visibly through the package's spring.
          magnification: 1.05,
          pressScale: 1.02,
          indicatorExpansion: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          interactionBehavior: GlassInteractionBehavior.scaleOnly,
        ),
      ),
    );
  }
}

class _TabBarItem extends StatefulWidget {
  const _TabBarItem({
    required this.item,
    required this.active,
    required this.motion,
    required this.onTap,
  });

  final AppMobileTabItem item;
  final bool active;
  final bool motion;
  final VoidCallback onTap;

  @override
  State<_TabBarItem> createState() => _TabBarItemState();
}

class _TabBarItemState extends State<_TabBarItem>
    with SingleTickerProviderStateMixin {
  /// One-shot pop when this item becomes the active one — a small
  /// bounce timed to land with the arriving pill.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.12,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 55,
    ),
  ]).animate(_pop);

  var _pressed = false;

  @override
  void didUpdateWidget(covariant _TabBarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && widget.motion) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
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
    final iconColor = widget.active
        ? colors.navPanel.activeIcon
        : colors.icon.muted;

    return Semantics(
      label: widget.item.label,
      button: true,
      selected: widget.active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () {
          unawaited(AppHaptics.auxiliaryKey());
          widget.onTap();
        },
        child: SizedBox(
          height: AppMobileTabBar._itemHeight,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.9 : 1.0,
              duration: Duration(milliseconds: _pressed ? 90 : 180),
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: ScaleTransition(
                scale: _popScale,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: iconColor),
                  duration: widget.motion
                      ? AppMobileTabBar.selectDuration
                      : Duration.zero,
                  builder: (_, color, _) => AppIcon(
                    widget.item.iconName,
                    size: AppMobileTabBar._iconSize,
                    color: color ?? iconColor,
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
