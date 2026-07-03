import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Bottom action bar pinned over a pane's scroll content, with a gradient
/// band that fades the content scrolling beneath it into the window
/// background. The shared form of the settings-endpoint / contacts /
/// accounts floating bars.
///
/// The bar's height is measured each frame and handed to [builder] as the
/// scroll reserve (bottom padding) that keeps the last scrolled item clear
/// of the overlay: the shared minimum while the bar is at its minimum
/// height, or the measured height plus a breathing gap once the bar grows
/// past it (wrapped error text, stacked content). While [visible] is false
/// the overlay is absent and the reserve is 0.
class AppPaneFloatingBar extends StatefulWidget {
  const AppPaneFloatingBar({
    required this.bar,
    required this.builder,
    this.visible = true,
    this.overlayWidth,
    super.key,
  });

  /// Minimum height of the overlay band (Figma: a min-96 gradient band with
  /// 16px vertical padding around the 36px action).
  static const double minOverlayHeight = 96;

  /// Breathing room between the last scrolled item and the overlay once the
  /// bar grows past its minimum height.
  static const double scrollGap = 12;

  /// Bottom-centered overlay content (typically a single action button).
  final Widget bar;

  /// Builds the scrollable pane content; `bottomReserve` is the bottom
  /// padding that keeps the last item clear of the overlay.
  final Widget Function(BuildContext context, double bottomReserve) builder;

  final bool visible;

  /// Width of the gradient band + bar. Null spans the full pane width;
  /// a value centers the overlay in a fixed-width column (the settings
  /// endpoint scrim box).
  final double? overlayWidth;

  @override
  State<AppPaneFloatingBar> createState() => _AppPaneFloatingBarState();
}

class _AppPaneFloatingBarState extends State<AppPaneFloatingBar> {
  final _barKey = GlobalKey();

  /// Latest measured overlay height (gradient band + bar content).
  double _measuredHeight = AppPaneFloatingBar.minOverlayHeight;

  void _measureBar() {
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    final measured = box?.hasSize == true ? box!.size.height : null;
    if (measured == null) return;
    // Only rebuild when the value actually moves to avoid a layout feedback
    // loop.
    if ((measured - _measuredHeight).abs() < 0.5) return;
    setState(() {
      _measuredHeight = measured;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _measureBar();
      });
    }

    final bottomReserve = !widget.visible
        ? 0.0
        : (_measuredHeight <= AppPaneFloatingBar.minOverlayHeight
              ? AppPaneFloatingBar.minOverlayHeight
              : _measuredHeight + AppPaneFloatingBar.scrollGap);

    Widget overlay = Stack(
      children: [
        // Bottom fade so list content scrolling beneath the bar dissolves
        // into the window background (Figma: window-transparent -> window
        // gradient band).
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.colors.macosUtility.windowTransparent,
                    context.colors.macosUtility.window,
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          key: _barKey,
          constraints: const BoxConstraints(
            minHeight: AppPaneFloatingBar.minOverlayHeight,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          alignment: Alignment.bottomCenter,
          child: widget.bar,
        ),
      ],
    );
    final overlayWidth = widget.overlayWidth;
    if (overlayWidth != null) {
      overlay = Center(
        child: SizedBox(width: overlayWidth, child: overlay),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.builder(context, bottomReserve),
        if (widget.visible)
          Positioned(left: 0, right: 0, bottom: 0, child: overlay),
      ],
    );
  }
}
