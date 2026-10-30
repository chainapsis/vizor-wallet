import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MobileNavigationEdge { none, left, right }

/// All coordinates are local to the engine's root view, in logical points.
/// This snapshot is invalid as soon as the Flutter view changes size.
@immutable
class MobileNavigationGeometry {
  const MobileNavigationGeometry({
    required this.edge,
    required this.viewSize,
    required this.safeRect,
    required this.occlusions,
    this.divisions = const [],
    this.barRect,
  });

  final MobileNavigationEdge edge;
  final Size viewSize;
  final Rect safeRect;
  final List<Rect> occlusions;
  final List<Rect> divisions;
  final Rect? barRect;

  static MobileNavigationGeometry? fromNative(Object? value) {
    if (value is! Map) return null;
    final bounds = _rect(value['bounds']);
    final safe = _rect(value['safeRect']);
    final regions = value['occlusions'];
    if (bounds == null || bounds.isEmpty || safe == null || regions is! List) {
      return null;
    }
    final rects = <Rect>[];
    for (final region in regions) {
      final rect = _rect(region);
      if (rect == null) return null;
      rects.add(rect.shift(-bounds.topLeft));
    }
    final normalizedSafe = safe.shift(-bounds.topLeft);
    if (normalizedSafe.isEmpty ||
        !(Offset.zero & bounds.size)
            .inflate(1)
            .contains(normalizedSafe.topLeft) ||
        !(Offset.zero & bounds.size)
            .inflate(1)
            .contains(normalizedSafe.bottomRight)) {
      return null;
    }
    final divisions = <Rect>[];
    final nativeDivisions = value['divisions'];
    if (nativeDivisions is List) {
      for (final region in nativeDivisions) {
        final rect = _rect(region);
        if (rect == null) return null;
        divisions.add(rect.shift(-bounds.topLeft));
      }
    }
    final bar = _rect(value['barRect']);
    return MobileNavigationGeometry(
      divisions: List.unmodifiable(divisions),
      barRect: bar?.shift(-bounds.topLeft),
      edge: value['supported'] != true
          ? MobileNavigationEdge.none
          : switch (value['edge']) {
              'left' => MobileNavigationEdge.left,
              'right' => MobileNavigationEdge.right,
              _ => MobileNavigationEdge.none,
            },
      viewSize: bounds.size,
      safeRect: normalizedSafe,
      occlusions: List.unmodifiable(rects),
    );
  }

  static Rect? _rect(Object? value) {
    if (value is! Map) return null;
    final numbers = [value['x'], value['y'], value['width'], value['height']];
    if (numbers.any((n) => n is! num || !n.isFinite)) return null;
    final values = numbers.cast<num>().map((n) => n.toDouble()).toList();
    if (values[2] < 0 || values[3] < 0) return null;
    return Rect.fromLTWH(values[0], values[1], values[2], values[3]);
  }

  bool matches(Size size) =>
      (size.width - viewSize.width).abs() < 1 &&
      (size.height - viewSize.height).abs() < 1;
}

final mobileNavigationGeometryServiceProvider =
    Provider<NativeMobileNavigationGeometry>(
      (ref) => const NativeMobileNavigationGeometry(),
    );

class NativeMobileNavigationGeometry {
  const NativeMobileNavigationGeometry();
  static const _method = MethodChannel(
    'com.zcash.wallet/mobile_navigation_geometry',
  );
  static const _events = EventChannel(
    'com.zcash.wallet/mobile_navigation_geometry/events',
  );

  bool get supportedHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<MobileNavigationGeometry?> read() async {
    if (!supportedHost) return null;
    try {
      return MobileNavigationGeometry.fromNative(
        await _method.invokeMethod<Object?>('getGeometry'),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Stream<MobileNavigationGeometry?> get changes =>
      _events.receiveBroadcastStream().map(MobileNavigationGeometry.fromNative);
}
