import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Mirrors the app's desktop asset directory convention, independently of
/// pubspec platform declarations. Package dependencies keep their own assets.
bool isDesktopOnlyTestAsset(String key) {
  const selfPackagePrefix = 'packages/zcash_wallet/';
  final appKey = key.startsWith(selfPackagePrefix)
      ? key.substring(selfPackagePrefix.length)
      : key;
  return appKey.startsWith('assets/') && appKey.split('/').contains('desktop');
}

/// Restricts the existing test bundle without copying or decoding image files.
/// The original engine supplies permitted bytes; only the small manifest is
/// filtered in memory. Keep all variant metadata when retaining an asset.
class MobileTestAssets {
  MobileTestAssets({
    required ByteData manifest,
    required Future<ByteData?>? Function(ByteData? message) originalLoad,
  }) : _originalLoad = originalLoad,
       _manifest = _filterManifest(manifest);

  final Future<ByteData?>? Function(ByteData? message) _originalLoad;
  final ByteData _manifest;
  final Set<String> blockedRequests = {};

  Future<ByteData?>? handle(
    ByteData? message, {
    Future<ByteData?>? Function(ByteData? message)? originalLoad,
  }) {
    if (message == null) return SynchronousFuture(null);
    final key = Uri.decodeFull(utf8.decode(Uint8List.sublistView(message)));
    if (isDesktopOnlyTestAsset(key)) {
      blockedRequests.add(key);
      return SynchronousFuture(null);
    }
    if (key == 'AssetManifest.bin') return SynchronousFuture(_manifest);
    return (originalLoad ?? _originalLoad)(message);
  }

  static ByteData _filterManifest(ByteData bytes) {
    const codec = StandardMessageCodec();
    final original = codec.decodeMessage(bytes) as Map<Object?, Object?>;
    final filtered = <Object?, Object?>{};
    for (final entry in original.entries) {
      if (isDesktopOnlyTestAsset(entry.key as String)) continue;
      final variants = (entry.value as List<Object?>).where((variant) {
        final metadata = variant as Map<Object?, Object?>;
        return !isDesktopOnlyTestAsset(metadata['asset'] as String);
      }).toList();
      if (variants.isNotEmpty) filtered[entry.key] = variants;
    }
    return codec.encodeMessage(filtered)!;
  }
}
