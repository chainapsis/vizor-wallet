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

class _IosLiquidTabBar extends StatelessWidget {
  const _IosLiquidTabBar({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<AppMobileTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // AppTheme is authoritative even when the user's choice differs from the
    // OS appearance. Scope this to the bar; no global package configuration.
    final brightness = context.appTheme == AppThemeData.dark
        ? Brightness.dark
        : Brightness.light;
    final settings = brightness == Brightness.dark
        ? LiquidGlassSettings.ios26Dark
        : LiquidGlassSettings.ios26Light;

    return GlassTheme(
      data: GlassThemeData.ios26(brightness: brightness),
      child: GlassTabBar.bottom(
        tabs: [
          for (final item in items)
            GlassTab(
              icon: AppIcon(item.iconName, size: AppMobileTabBar._iconSize),
              semanticLabel: item.label,
            ),
        ],
        selectedIndex: currentIndex,
        onTabSelected: (index) {
          unawaited(AppHaptics.auxiliaryKey());
          onSelect(index);
        },
        // The shell already owns the outer margins and home-indicator inset.
        horizontalPadding: 0,
        verticalPadding: 0,
        barHeight: kMobileTabBarHeight,
        barBorderRadius: kMobileTabBarHeight / 2,
        tabPadding: const EdgeInsets.all(AppSpacing.xxs),
        iconSize: AppMobileTabBar._iconSize,
        selectedIconColor: colors.navPanel.activeIcon,
        unselectedIconColor: colors.icon.muted,
        indicatorColor: colors.navPanel.activeBg,
        settings: settings.copyWith(glassColor: colors.macosUtility.navPanel),
        quality: GlassQuality.premium,
        // Keep the lens and press response restrained around the existing UI.
        magnification: 1.05,
        pressScale: 1.02,
        indicatorExpansion: const EdgeInsets.all(AppSpacing.xxs),
        interactionGlowColor: colors.navPanel.activeIcon,
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
