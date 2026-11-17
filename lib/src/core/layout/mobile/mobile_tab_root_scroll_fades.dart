import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import 'app_mobile_tab_bar.dart';
import 'mobile_bottom_scroll_fade.dart';
import 'mobile_navigation_scope.dart';
import 'mobile_top_scroll_fade.dart';

/// Soft scroll edges shared by every tab root (Home, Swap, Activity,
/// Settings): content dissolves under the top nav across a 64px band and
/// fades as it passes under the floating tab bar. Wrap the tab's scroll view
/// in this so the four tabs read the same.
class MobileTabRootScrollFades extends StatelessWidget {
  const MobileTabRootScrollFades({required this.child, super.key});

  /// The tab's scroll view.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MobileTopScrollFade(
      height: AppSpacing.xl,
      child: MobileBottomScrollFade(
        // Covers the bar and the inset below it, then dissolves rows over a
        // further 32px above the bar. Sidebar layouts have no bottom bar and
        // fade only across the inset.
        height: MobileNavigationScope.bottomClearanceOf(
          context,
          kMobileTabBarHeight +
              MediaQuery.viewPaddingOf(context).bottom +
              AppSpacing.base,
        ),
        child: child,
      ),
    );
  }
}
