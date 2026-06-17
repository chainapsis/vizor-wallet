import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Soft top edge for tab-root scroll areas (VZR-74): a window-colored
/// gradient overlay that dissolves content under the top nav instead of
/// the scroll viewport's hard clip.
///
/// Scroll-aware — fully transparent at rest so resting content keeps its
/// crisp edge, then grows across the first [AppSpacing.md] of scroll. The
/// gradient samples a smoothstep curve rather than the default two-stop linear
/// ramp, so the dissolve reads as a slow fade while the top edge remains fully
/// window-colored.
class MobileTopScrollFade extends StatefulWidget {
  const MobileTopScrollFade({
    required this.child,
    this.height = AppSpacing.base,
    super.key,
  });

  /// The scrollable content the fade overlays.
  final Widget child;

  /// Maximum height of the fade band below the top edge.
  final double height;

  @override
  State<MobileTopScrollFade> createState() => _MobileTopScrollFadeState();
}

class _MobileTopScrollFadeState extends State<MobileTopScrollFade> {
  double _progress = 0;

  static const _activationDistance = AppSpacing.md;

  // Smoothstep 3t² − 2t³ sampled at fifteen points — an eased dissolve
  // from a fully window-colored clip edge to transparent.
  static const _stops = [
    0.0,
    0.071,
    0.143,
    0.214,
    0.286,
    0.357,
    0.429,
    0.5,
    0.571,
    0.643,
    0.714,
    0.786,
    0.857,
    0.929,
    1.0,
  ];
  static const _alphas = [
    1.0,
    0.985,
    0.945,
    0.882,
    0.802,
    0.708,
    0.606,
    0.5,
    0.394,
    0.292,
    0.198,
    0.118,
    0.055,
    0.015,
    0.0,
  ];

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final progress = (notification.metrics.extentBefore / _activationDistance)
        .clamp(0.0, 1.0);
    final next = _smoothstep(progress);
    if (next != _progress) setState(() => _progress = next);
    return false; // Observe only — let the notification bubble on.
  }

  static double _smoothstep(double value) => value * value * (3 - 2 * value);

  @override
  Widget build(BuildContext context) {
    final window = context.colors.background.window;
    final fadeHeight = widget.height * _progress;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: fadeHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: _stops,
                    colors: [
                      for (var i = 0; i < _stops.length; i++)
                        window.withValues(alpha: _gradientAlpha(i)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _gradientAlpha(int stopIndex) =>
      stopIndex == 0 ? _alphas[stopIndex] : _alphas[stopIndex] * _progress;
}
