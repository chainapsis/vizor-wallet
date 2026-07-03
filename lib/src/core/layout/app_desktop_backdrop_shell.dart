import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';

import 'app_desktop_shell.dart';

/// Desktop screen scaffold with a full-window background layer.
///
/// The background paints behind the glass sidebar, the 8pt window
/// margins, and the (transparent) trailing pane, so artwork bleeds
/// edge-to-edge like the home screen. Screens own the background
/// widget (asset, fade mask, theme gating) and the pane content.
class AppDesktopBackdropShell extends StatelessWidget {
  const AppDesktopBackdropShell({
    required this.background,
    required this.sidebar,
    required this.pane,
    super.key,
  });

  /// Full-window layer painted behind the shell.
  final Widget background;

  final Widget sidebar;

  /// Content of the (transparent, padding-less) trailing pane.
  final Widget pane;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: background),
        AppDesktopShell(
          backgroundColor: Colors.transparent,
          sidebar: sidebar,
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            child: pane,
          ),
        ),
      ],
    );
  }
}
