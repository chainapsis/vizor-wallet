import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_context_menu.dart' show appContextMenuShadow;

/// Which edge of an [AppPopoverSurface] carries its tail.
enum AppPopoverTailEdge { top, bottom, left }

/// A raised card with a tail pointing at what opened it.
///
/// Shared by the Send waiting-funds popover and the sidebar balance popover,
/// so both read as the same surface.
class AppPopoverSurface extends StatelessWidget {
  const AppPopoverSurface({
    required this.width,
    required this.tailEdge,
    required this.tailInset,
    required this.child,
    this.surfaceKey,
    super.key,
  });

  static const tailSize = 10.0;

  final double width;
  final AppPopoverTailEdge tailEdge;

  /// The tail's center from the trailing edge on [AppPopoverTailEdge.top] and
  /// [AppPopoverTailEdge.bottom], and from the top on
  /// [AppPopoverTailEdge.left]. Keep it past the rounded corner.
  final double tailInset;

  /// Key of the card itself, for tests that measure the surface.
  final Key? surfaceKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final edge = BorderSide(color: colors.border.subtleOpacity);
    const outside = -tailSize / 2;
    final along = tailInset - tailSize / 2;
    // Merged, not replaced: the ambient style carries the locale's fonts.
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: surfaceKey,
            width: width,
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.background.raised,
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: colors.border.subtleOpacity),
              boxShadow: appContextMenuShadow,
            ),
            child: child,
          ),
          Positioned(
            left: tailEdge == AppPopoverTailEdge.left ? outside : null,
            right: tailEdge == AppPopoverTailEdge.left ? null : along,
            top: switch (tailEdge) {
              AppPopoverTailEdge.top => outside,
              AppPopoverTailEdge.bottom => null,
              AppPopoverTailEdge.left => along,
            },
            bottom: tailEdge == AppPopoverTailEdge.bottom ? outside : null,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: tailSize,
                height: tailSize,
                decoration: BoxDecoration(
                  color: colors.background.raised,
                  // The two sides of the rotated square that face outward.
                  border: switch (tailEdge) {
                    AppPopoverTailEdge.top => Border(left: edge, top: edge),
                    AppPopoverTailEdge.bottom => Border(
                      right: edge,
                      bottom: edge,
                    ),
                    AppPopoverTailEdge.left => Border(left: edge, bottom: edge),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
