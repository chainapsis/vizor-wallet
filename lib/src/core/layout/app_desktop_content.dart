import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_desktop_shell.dart';

/// Metrics for the desktop trailing-pane content column.
///
/// Figma's content-area token ([AppWindowSizing.contentAreaMaxWidth]) is
/// the column width at the 1080×720 design window. Extra pane width
/// beyond that design is given to the column so a maximized window is
/// not a 420px strip in empty space. At the design size the column stays
/// 420px, preserving Figma layout.
abstract final class AppDesktopContentMetrics {
  /// Trailing pane width at [AppWindowSizing.minWidth]:
  /// window − left pad − sidebar − gap − right pad.
  static const double designPaneWidth =
      AppWindowSizing.minWidth -
      AppSpacing.xs * 3 -
      AppDesktopShell.defaultSidebarWidth;

  /// Horizontal inset from the 420px content column to the inner 396px
  /// surface used by activity cards and send fields.
  static const double surfaceInset = AppSpacing.s;

  /// Content column width for a trailing pane of [paneWidth].
  static double widthForPane(double paneWidth) {
    if (!paneWidth.isFinite || paneWidth <= 0) {
      return AppWindowSizing.contentAreaMaxWidth;
    }
    if (paneWidth <= designPaneWidth) {
      return math.min(paneWidth, AppWindowSizing.contentAreaMaxWidth);
    }
    return paneWidth - (designPaneWidth - AppWindowSizing.contentAreaMaxWidth);
  }

  /// Inner surface width (content column minus the 12px side inset
  /// on each side).
  static double surfaceWidthForPane(double paneWidth) {
    return math.max(0.0, widthForPane(paneWidth) - surfaceInset * 2);
  }
}

/// Centers a child in the trailing pane at [AppDesktopContentMetrics.widthForPane].
class AppDesktopContentColumn extends StatelessWidget {
  const AppDesktopContentColumn({
    required this.child,
    this.padding,
    this.alignment = Alignment.topCenter,
    this.contentKey,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = AppDesktopContentMetrics.widthForPane(
          constraints.maxWidth,
        );
        final padding = this.padding;
        return Align(
          alignment: alignment,
          child: SizedBox(
            key: contentKey,
            width: width,
            child: padding == null
                ? child
                : Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}

/// Sliver counterpart of [AppDesktopContentColumn].
class AppDesktopContentSliver extends StatelessWidget {
  const AppDesktopContentSliver({
    required this.child,
    this.padding,
    this.contentKey,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Key? contentKey;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = AppDesktopContentMetrics.widthForPane(
          constraints.crossAxisExtent,
        );
        final padding = this.padding;
        return SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: contentKey,
              width: width,
              child: padding == null
                  ? child
                  : Padding(padding: padding, child: child),
            ),
          ),
        );
      },
    );
  }
}
