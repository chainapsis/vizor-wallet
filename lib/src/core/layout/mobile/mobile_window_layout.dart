import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/widgets.dart';

import '../../../services/native_mobile_navigation_geometry.dart';
import 'mobile_navigation_scope.dart';
import 'mobile_window_policy.dart';

/// Geometry in root-view coordinates, sharing [MobileWindowPolicy] with entry
/// pages. Native exclusions can prevent panes from fitting a wide window.
class MobileWindowLayout {
  const MobileWindowLayout({
    required this.mode,
    required this.body,
    required this.windowPolicy,
    this.sidebar,
    this.rail,
    this.contentSafeRect,
    this.availableContentRect,
    this.navigationViewport,
  });
  final MobileNavigationMode mode;
  final Rect body;
  final MobileWindowPolicy windowPolicy;
  final Rect? sidebar;
  final Rect? rail;

  /// Foreground safety remains pane-local while wide surfaces reach the bottom.
  final Rect? contentSafeRect;

  /// Contiguous foreground space before the default 440-point page cap.
  /// Individual routes may opt into more width without crossing obstructions.
  final Rect? availableContentRect;
  final Rect? navigationViewport;

  /// Page transitions include the surrounding space; content keeps [body].
  Rect get viewport => navigationViewport ?? body;

  static MobileWindowLayout resolve({
    required MediaQueryData media,
    MobileNavigationGeometry? native,
    bool wallet = true,
    int navigationItemCount = 4,
  }) {
    final full = Offset.zero & media.size;
    final windowPolicy = MobileWindowPolicy.resolve(media);
    native = native?.matches(media.size) == true ? native : null;
    final safe = windowPolicy.safeRect.intersect(native?.safeRect ?? full);
    final divisions = <Rect>[
      ...?native?.divisions,
      for (final feature in media.displayFeatures)
        if (feature.type == DisplayFeatureType.hinge ||
            feature.state == DisplayFeatureState.postureHalfOpened)
          feature.bounds,
    ];
    final blocked = [...divisions, ...?native?.occlusions];
    if (wallet && windowPolicy.usesWideLayout) {
      const sidebarMinimum = MobileWindowPolicy.minimumSidebarWidth;
      const contentMinimum = MobileWindowPolicy.minimumContentWidth;
      const gap = MobileWindowPolicy.paneSpacing;
      final preferredWidth = math.min(
        256.0,
        safe.width - contentMinimum - gap * 3,
      );
      for (final sidebarWidth in {preferredWidth, sidebarMinimum}) {
        final sidebarCandidates = _freeRects(
          Rect.fromLTWH(
            safe.left + 16,
            safe.top + 16,
            sidebarWidth,
            math.max(0, full.bottom - 16 - (safe.top + 16)),
          ),
          blocked,
        );
        final sidebar = _largest(
          sidebarCandidates,
          minWidth: sidebarMinimum,
          minHeight: 96,
        );
        if (sidebar != null) {
          final rightPane = Rect.fromLTRB(
            sidebar.right + 16,
            safe.top,
            safe.right - 16,
            full.bottom,
          );
          final bodyArea = _largest(
            _freeRects(rightPane, blocked),
            minWidth: contentMinimum,
            minHeight: MobileWindowPolicy.minimumWideHeight,
          );
          if (bodyArea != null) {
            final width = math.min(440.0, bodyArea.width);
            final viewport = _largest(
              _freeRects(
                Rect.fromLTRB(sidebar.right + 16, 0, full.right, full.bottom),
                divisions,
              ).where((rect) => rect.intersect(bodyArea) == bodyArea).toList(),
            )!;
            return MobileWindowLayout(
              mode: MobileNavigationMode.sidebar,
              windowPolicy: windowPolicy,
              sidebar: sidebar,
              contentSafeRect: safe,
              availableContentRect: bodyArea,
              navigationViewport: viewport,
              body: Rect.fromLTWH(
                bodyArea.center.dx - width / 2,
                bodyArea.top,
                width,
                bodyArea.height,
              ),
            );
          }
        }
      }
    }
    // A separating hinge must never pass through the content, even when no
    // pair of usable panes can accommodate the expanded shell.
    final body = divisions.isEmpty
        ? full
        : _largest(_freeRects(full, divisions)) ?? full;
    if (wallet &&
        native != null &&
        native.edge != MobileNavigationEdge.none &&
        body == full) {
      final left = native.edge == MobileNavigationEdge.left;
      final strip = Rect.fromLTRB(
        left ? 0 : safe.right,
        0,
        left ? safe.left : media.size.width,
        media.size.height,
      );
      final suggested = native.barRect;
      final lane =
          suggested != null &&
              suggested.width >= 52 &&
              suggested.center.dx >= strip.left &&
              suggested.center.dx <= strip.right
          ? suggested.intersect(strip)
          : strip;
      Rect? fit(Rect area) {
        final horizontalGap = ((area.width - 64) / 2).clamp(0.0, 8.0);
        final verticalGap = ((area.height - 52) / 2).clamp(0.0, 8.0);
        return _largest(
          _freeRects(
            Rect.fromLTRB(
              area.left + horizontalGap,
              area.top + verticalGap,
              area.right - horizontalGap,
              area.bottom - verticalGap,
            ),
            blocked,
          ),
          minWidth: 52,
          minHeight: 52,
        );
      }

      // Keyboard fitting may shorten the rail, but cannot change the system's
      // placement choice. Retain its stable lane when the keyboard covers it.
      final keyboardTop = media.size.height - media.viewInsets.bottom;
      final available =
          fit(
            lane.intersect(Rect.fromLTRB(0, 0, media.size.width, keyboardTop)),
          ) ??
          fit(lane) ??
          fit(strip);
      if (available != null) {
        final width = math.min(64.0, available.width);
        final height = math.min(
          56.0 * navigationItemCount + 8,
          available.height,
        );
        return MobileWindowLayout(
          mode: MobileNavigationMode.systemSideTabs,
          windowPolicy: windowPolicy,
          body: body,
          rail: Rect.fromLTWH(
            available.center.dx - width / 2,
            available.bottom - height,
            width,
            height,
          ),
        );
      }
    }
    return MobileWindowLayout(
      mode: MobileNavigationMode.bottomTabs,
      windowPolicy: windowPolicy,
      body: body,
    );
  }
}

Rect? _largest(List<Rect> rects, {double minWidth = 1, double minHeight = 1}) {
  final usable =
      rects.where((r) => r.width >= minWidth && r.height >= minHeight).toList()
        ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
  return usable.firstOrNull;
}

/// Keep maximal rectangles on either side of each obstruction. Overlapping
/// candidates are intentional: choose a usable pane, not fragmented tiles.
List<Rect> _freeRects(Rect original, List<Rect> blocked) {
  var rects = original.isEmpty ? <Rect>[] : [original];
  for (var obstacle in blocked) {
    // A zero-width half-open fold still separates two interactive panes.
    if (obstacle.width == 0 || obstacle.height == 0) {
      obstacle = obstacle.inflate(0.5);
    }
    final next = <Rect>[];
    for (final rect in rects) {
      if (!rect.overlaps(obstacle)) {
        next.add(rect);
        continue;
      }
      final cut = rect.intersect(obstacle);
      next.addAll(
        [
          Rect.fromLTRB(rect.left, rect.top, cut.left, rect.bottom),
          Rect.fromLTRB(cut.right, rect.top, rect.right, rect.bottom),
          Rect.fromLTRB(rect.left, rect.top, rect.right, cut.top),
          Rect.fromLTRB(rect.left, cut.bottom, rect.right, rect.bottom),
        ].where((r) => !r.isEmpty),
      );
    }
    rects = next;
  }
  return rects;
}

/// The Navigator receives pane-local metrics; view/window metrics stay intact
/// above the frame for native bridges and app-level security/overlay hosts.
MediaQueryData mobilePaneMedia(
  MediaQueryData media,
  Rect pane, {
  Rect? safeRect,
}) {
  if (safeRect != null) {
    // The native safe area may be stricter than Flutter's insets. Preserve it
    // as foreground padding instead of shortening the painted viewport.
    final safe = safeRect.intersect(Offset.zero & media.size);
    final insets = EdgeInsets.fromLTRB(
      math.max(media.viewPadding.left, safe.left),
      math.max(media.viewPadding.top, safe.top),
      math.max(media.viewPadding.right, media.size.width - safe.right),
      math.max(media.viewPadding.bottom, media.size.height - safe.bottom),
    );
    media = media.copyWith(
      viewPadding: insets,
      padding: EdgeInsets.fromLTRB(
        math.max(media.padding.left, insets.left - media.viewInsets.left),
        math.max(media.padding.top, insets.top - media.viewInsets.top),
        math.max(media.padding.right, insets.right - media.viewInsets.right),
        math.max(media.padding.bottom, insets.bottom - media.viewInsets.bottom),
      ),
    );
  }
  EdgeInsets project(EdgeInsets inset) => EdgeInsets.fromLTRB(
    math.max(0.0, inset.left - pane.left).clamp(0.0, pane.width),
    math.max(0.0, inset.top - pane.top).clamp(0.0, pane.height),
    math
        .max(0.0, inset.right - (media.size.width - pane.right))
        .clamp(0.0, pane.width),
    math
        .max(0.0, inset.bottom - (media.size.height - pane.bottom))
        .clamp(0.0, pane.height),
  );
  return media.copyWith(
    size: pane.size,
    padding: project(media.padding),
    viewPadding: project(media.viewPadding),
    viewInsets: project(media.viewInsets),
    systemGestureInsets: project(media.systemGestureInsets),
    displayFeatures: [
      for (final feature in media.displayFeatures)
        if (feature.bounds.overlaps(pane))
          DisplayFeature(
            bounds: feature.bounds.intersect(pane).shift(-pane.topLeft),
            type: feature.type,
            state: feature.state,
          ),
    ],
  );
}
