import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';

/// Optional iOS geometry. An unavailable channel must never block a modal.
abstract final class NativeModalCorners {
  static const channel = MethodChannel('com.zcash.wallet/modal_corners');
  // Debug preview counters are never updated in release builds.
  static int debugCacheHits = 0;
  static int debugCalculations = 0;
  static BorderRadius? debugLastSidebarRadii;
  static const timeout = Duration(milliseconds: 300);

  /// Actual panel geometry, unlike the modal's height-independent reference.
  static Future<BorderRadius?> resolveSidebar({
    required Rect rect,
    required Size viewSize,
    required double scale,
  }) async {
    try {
      final raw = await channel
          .invokeMethod<Object?>('resolveSidebar', {
            'x': rect.left,
            'y': rect.top,
            'width': rect.width,
            'height': rect.height,
            'viewWidth': viewSize.width,
            'viewHeight': viewSize.height,
            'scale': scale,
          })
          .timeout(timeout);
      if (raw is! Map) return null;
      const names = ['topLeft', 'topRight', 'bottomLeft', 'bottomRight'];
      final values = <double>[];
      for (final name in names) {
        final value = raw[name];
        if (value is! num ||
            !value.isFinite ||
            value < 24 ||
            value > viewSize.shortestSide / 2) {
          return null;
        }
        values.add(value.toDouble());
      }
      if (values[0] + values[1] > rect.width ||
          values[2] + values[3] > rect.width ||
          values[0] + values[2] > rect.height ||
          values[1] + values[3] > rect.height) {
        return null;
      }
      final radius = BorderRadius.only(
        topLeft: Radius.circular(values[0]),
        topRight: Radius.circular(values[1]),
        bottomLeft: Radius.circular(values[2]),
        bottomRight: Radius.circular(values[3]),
      );
      assert(() {
        debugLastSidebarRadii = radius;
        return true;
      }());
      return radius;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static Future<({double left, double right})?> resolve({
    required Rect rect,
    required Size viewSize,
    required double scale,
  }) async {
    try {
      final raw = await channel
          .invokeMethod<Object?>('resolve', {
            'x': rect.left,
            'y': rect.top,
            'width': rect.width,
            'height': rect.height,
            'viewWidth': viewSize.width,
            'viewHeight': viewSize.height,
            'scale': scale,
          })
          .timeout(timeout);
      if (raw is! Map) return null;
      assert(() {
        if (raw['cacheHit'] == true) debugCacheHits++;
        if (raw['cacheHit'] == false) debugCalculations++;
        return true;
      }());
      final left = raw['bottomLeft'];
      final right = raw['bottomRight'];
      final limit = viewSize.shortestSide / 2;
      if (left is! num ||
          right is! num ||
          !left.isFinite ||
          !right.isFinite ||
          left < 0 ||
          right < 0 ||
          left > limit ||
          right > limit) {
        return null;
      }
      return (left: left.toDouble(), right: right.toDouble());
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
