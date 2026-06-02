import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_layout.dart';

EdgeInsets get appWindowPanePadding {
  if (isDesktopLayoutPlatform) {
    return const EdgeInsets.all(AppSpacing.xs);
  }
  return EdgeInsets.zero;
}

class AppPaneScaffold extends StatelessWidget {
  const AppPaneScaffold({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(padding: appWindowPanePadding, child: child),
      ),
    );
  }
}
