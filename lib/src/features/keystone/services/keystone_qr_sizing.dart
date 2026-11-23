import 'dart:convert';
import 'dart:math' as math;

import 'keystone_qr_encoder.dart';

/// The camera-facing renderer reserves this many modules on every side.
const keystoneQrQuietZoneModules = 4;

/// Sizing uses the actual QR versions, including UR headers and encoding mode.
/// Cache this per request rather than encoding frames during layout or playback.
class KeystoneQrSizing {
  KeystoneQrSizing.fromParts(List<String> parts) {
    // Capacity depends on length and encoding mode, not the mask/content.
    // A request normally has hundreds of frames but only a few such pairs.
    final samples = <(int, bool), String>{};
    for (final part in parts) {
      final alpha = keystoneQrUsesAlphanumeric(part);
      samples[(alpha ? part.length : utf8.encode(part).length, alpha)] = part;
    }
    _moduleCounts = {
      for (final part in samples.values)
        encodeKeystoneQrImage(part).moduleCount,
    }.toList();
  }

  late final List<int> _moduleCounts;

  /// Round the pitch up before reserving the border, so switching to an
  /// integer grid does not silently shrink the requested data-pattern size.
  double sizeForPattern(double minimumPatternSize, double pixelRatio) {
    if (_moduleCounts.isEmpty) return minimumPatternSize;
    return _moduleCounts.fold(0.0, (size, count) {
      final pitch = (minimumPatternSize * pixelRatio / count).ceil();
      return math.max(
        size,
        (count + 2 * keystoneQrQuietZoneModules) * pitch / pixelRatio,
      );
    });
  }

  double minimumSize(double pixelRatio, {required int pixelsPerModule}) =>
      _moduleCounts.fold(
        0.0,
        (size, count) => math.max(
          size,
          (count + 2 * keystoneQrQuietZoneModules) *
              pixelsPerModule /
              pixelRatio,
        ),
      );

  /// Preserve the old PrettyQr surface's data pattern when layout has room.
  /// PrettyQr measures its three-module border against the unpadded surface,
  /// then scales the entire matrix into the remaining area.
  double sizePreservingPattern(double previousSurfaceSize, double pixelRatio) =>
      _moduleCounts.fold(previousSurfaceSize, (size, count) {
        final previousPitch =
            previousSurfaceSize * (count - 6) / (count * count);
        final pitch = (previousPitch * pixelRatio).ceil();
        return math.max(
          size,
          (count + 2 * keystoneQrQuietZoneModules) * pitch / pixelRatio,
        );
      });

  /// Avoid unused white space when a bounded focus view cannot reach its
  /// preferred size. Different QR versions have no common surface grid.
  double fitWithin(double maximumSize, double pixelRatio) {
    if (_moduleCounts.length != 1) return maximumSize;
    final span = _moduleCounts.single + 2 * keystoneQrQuietZoneModules;
    final pitch = (maximumSize * pixelRatio / span + 1e-9).floor();
    return pitch < 1 ? maximumSize : span * pitch / pixelRatio;
  }
}
