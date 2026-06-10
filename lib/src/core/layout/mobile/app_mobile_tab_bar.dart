import 'dart:ui';

import 'package:flutter/widgets.dart';

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
class AppMobileTabBar extends StatelessWidget {
  const AppMobileTabBar({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    super.key,
  });

  final List<AppMobileTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const _blur = 17.5;
  static const _itemHeight = 56.0;
  static const _iconSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadii.full);

    return SizedBox(
      height: kMobileTabBarHeight,
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
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _TabBarItem(
                          item: items[i],
                          active: i == currentIndex,
                          onTap: () => onSelect(i),
                        ),
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

class _TabBarItem extends StatelessWidget {
  const _TabBarItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppMobileTabItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: item.label,
      button: true,
      selected: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: AppMobileTabBar._itemHeight,
          decoration: BoxDecoration(
            color: active ? colors.navPanel.activeBg : null,
            borderRadius: BorderRadius.circular(AppRadii.full),
            border: Border.all(
              color: active
                  ? colors.border.subtleOpacity
                  : const Color(0x00000000),
            ),
          ),
          child: Center(
            child: AppIcon(
              item.iconName,
              size: AppMobileTabBar._iconSize,
              color: active ? colors.navPanel.activeIcon : colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}
