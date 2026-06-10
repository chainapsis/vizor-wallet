import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

/// Mobile counterpart of `AppDesktopShell`: a full-bleed body with the
/// floating tab bar overlaid at the bottom.
///
/// Layout from the Figma mobile frames (e.g. `Home Default`, node
/// 4394:88353): the tab bar floats 16px from the horizontal edges and
/// 12px above the bottom safe-area inset, and page content scrolls
/// underneath it (`extendBody`).
class AppMobileShell extends StatelessWidget {
  const AppMobileShell({required this.body, required this.tabBar, super.key});

  final Widget body;
  final Widget tabBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background.window,
      extendBody: true,
      // Desktop hosts toasts inside AppDesktopPane; the mobile shell is
      // the equivalent surface, so it hosts them for all tab content.
      body: AppToastHost(child: body),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.s,
          ),
          child: tabBar,
        ),
      ),
    );
  }
}
