import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'mobile_bottom_safe_area.dart';
import 'mobile_navigation_scope.dart';

/// Mobile counterpart of `AppDesktopShell`: a full-bleed body with the
/// floating tab bar overlaid at the bottom.
///
/// Layout from the Figma mobile frames (e.g. `Home Default`, node
/// 4394:88353): the tab bar floats 16px from the horizontal edges and
/// page content scrolls underneath it (`extendBody`). Below the bar,
/// Android keeps the Figma 12px gap above the navigation-bar inset; on
/// iOS the home indicator floats inside the gap instead, which is
/// widened to 16px so all three margins around the bar match (see
/// [MobileBottomSafeArea]).
class AppMobileShell extends StatelessWidget {
  const AppMobileShell({required this.body, required this.tabBar, super.key});

  final Widget body;
  final Widget tabBar;

  @override
  Widget build(BuildContext context) {
    final bottomGap = defaultTargetPlatform == TargetPlatform.iOS
        ? AppSpacing.sm
        : AppSpacing.s;
    final navigation = MobileNavigationScope.maybeOf(context);
    final mode = navigation?.mode ?? MobileNavigationMode.bottomTabs;
    final rail = navigation?.railRect;
    return Scaffold(
      backgroundColor: context.colors.background.window,
      extendBody: true,
      // Desktop hosts toasts inside AppDesktopPane; the mobile shell is
      // the equivalent surface, so it hosts them for all tab content.
      body: AppToastHost(
        overlayBounds: mode == MobileNavigationMode.sidebar
            ? navigation?.contentRect
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            body,
            if (mode == MobileNavigationMode.systemSideTabs && rail != null)
              Positioned.fromRect(
                rect: rail,
                child: SingleChildScrollView(child: tabBar),
              ),
          ],
        ),
      ),
      bottomNavigationBar: mode != MobileNavigationMode.bottomTabs
          ? null
          : MobileBottomSafeArea(
              bottomPadding: bottomGap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  0,
                  AppSpacing.sm,
                  bottomGap,
                ),
                child: tabBar,
              ),
            ),
    );
  }
}
