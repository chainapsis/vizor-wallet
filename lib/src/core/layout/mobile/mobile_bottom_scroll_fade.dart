import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Soft bottom edge for a scroll area: a window-colored gradient over the
/// last rows while more content waits below, as on the mobile Endpoints list.
///
/// Scroll-aware — it fades out across the final [AppSpacing.md] of scroll, so
/// the last row rests uncovered and a list that fits shows no fade at all.
class MobileBottomScrollFade extends StatefulWidget {
  const MobileBottomScrollFade({
    required this.child,
    this.height = AppSpacing.xl,
    super.key,
  });

  /// The scrollable content the fade overlays.
  final Widget child;

  /// Height of the fade band above the bottom edge.
  final double height;

  @override
  State<MobileBottomScrollFade> createState() => _MobileBottomScrollFadeState();
}

class _MobileBottomScrollFadeState extends State<MobileBottomScrollFade> {
  double _progress = 0;

  static const _activationDistance = AppSpacing.md;

  // Metrics notifications cover the first layout and resizes, which a list
  // that already overflows at rest never reports as a scroll.
  bool _onMetrics(int depth, ScrollMetrics metrics) {
    if (depth != 0) return false;
    final t = (metrics.extentAfter / _activationDistance).clamp(0.0, 1.0);
    final next = t * t * (3 - 2 * t);
    if (next != _progress) setState(() => _progress = next);
    return false; // Observe only — let the notification bubble on.
  }

  @override
  Widget build(BuildContext context) {
    final window = context.colors.background.window;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.depth, n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.depth, n.metrics),
        child: Stack(
          children: [
            widget.child,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: widget.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('mobile_bottom_scroll_fade_layer'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        window.withValues(alpha: 0),
                        window.withValues(alpha: _progress),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
