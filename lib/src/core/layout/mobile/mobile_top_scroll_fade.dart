import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Soft top edge for tab-root scroll areas (VZR-74): a window-colored
/// gradient overlay that dissolves content under the top nav instead of
/// the scroll viewport's hard clip.
///
/// Scroll-aware — fully transparent at rest so resting content keeps
/// its crisp edge, eased in over the first [AppSpacing.md] of scroll.
/// The gradient samples a smoothstep curve rather than the default
/// two-stop linear ramp, so the dissolve reads as a slow fade.
class MobileTopScrollFade extends StatefulWidget {
  const MobileTopScrollFade({
    required this.child,
    this.height = 40,
    super.key,
  });

  /// The scrollable content the fade overlays.
  final Widget child;

  /// Height of the fade band below the top edge.
  final double height;

  @override
  State<MobileTopScrollFade> createState() => _MobileTopScrollFadeState();
}

class _MobileTopScrollFadeState extends State<MobileTopScrollFade> {
  double _opacity = 0;

  // Smoothstep 3t² − 2t³ sampled at six points — an eased dissolve
  // from fully window-colored at the clip edge to transparent.
  static const _stops = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
  static const _alphas = [1.0, 0.896, 0.648, 0.352, 0.104, 0.0];

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final next = (notification.metrics.extentBefore / AppSpacing.md).clamp(
      0.0,
      1.0,
    );
    if (next != _opacity) setState(() => _opacity = next);
    return false; // Observe only — let the notification bubble on.
  }

  @override
  Widget build(BuildContext context) {
    final window = context.colors.background.window;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: widget.height,
            child: IgnorePointer(
              child: Opacity(
                opacity: _opacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: _stops,
                      colors: [
                        for (var i = 0; i < _stops.length; i++)
                          window.withValues(alpha: _alphas[i]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
