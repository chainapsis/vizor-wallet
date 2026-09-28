import 'dart:async';

import 'package:flutter/services.dart';

/// Optional iOS geometry. An unavailable channel must never block a modal.
abstract final class NativeModalCorners {
  static const channel = MethodChannel('com.zcash.wallet/modal_corners');
  // Debug preview counters are never updated in release builds.
  static int debugCacheHits = 0;
  static int debugCalculations = 0;
  static const timeout = Duration(milliseconds: 300);

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
