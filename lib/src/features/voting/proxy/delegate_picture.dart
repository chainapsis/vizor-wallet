import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/proxy_delegation.dart' as rust;
import 'proxy_delegation_repository.dart';

/// Edge, in pixels, of every delegate picture: config CI admits only 128 px
/// pictures to a wallet list, and Rust refuses any other size.
const kDelegatePictureEdge = 128;

/// Decoded pixels: rows top to bottom, RGBA with premultiplied alpha.
typedef DelegatePicturePixels = ({int width, int height, Uint8List rgba});

/// Turns a wallet list picture into pixels. Throws when the picture is
/// refused.
abstract interface class DelegatePictureDecoder {
  /// Decodes [picture].
  Future<DelegatePicturePixels> decode(ProxyDelegatePicture picture);
}

/// Decodes in Rust (`decode_delegate_picture`), never with a platform image
/// decoder.
class RustDelegatePictureDecoder implements DelegatePictureDecoder {
  /// Creates the decoder.
  const RustDelegatePictureDecoder();

  @override
  Future<DelegatePicturePixels> decode(ProxyDelegatePicture picture) async {
    final decoded = await rust.decodeDelegatePicture(webp: picture.webp);
    return (width: decoded.width, height: decoded.height, rgba: decoded.rgba);
  }
}

/// Decoded delegate pictures, drawn from pixels with `decodeImageFromPixels`
/// and kept by their bytes' hash, at most [capacity] of them.
///
/// Callers get their own handle to each image and dispose it when done; the
/// cache disposes its handles on eviction and in [clear].
class DelegatePictureCache {
  /// Creates a cache over [decoder].
  DelegatePictureCache(this._decoder, {this.capacity = 32});

  /// Turns pictures into pixels.
  final DelegatePictureDecoder _decoder;

  /// Most decoded pictures kept at once.
  final int capacity;

  /// Decoded images by picture key, least recently used first.
  final _images = <String, ui.Image>{};

  /// Decodes in flight, by picture key, so concurrent callers share one.
  final _pending = <String, Future<ui.Image?>>{};

  /// A new handle to [picture]'s image when it is already decoded.
  ui.Image? cached(ProxyDelegatePicture picture) {
    final image = _images.remove(picture.key);
    if (image == null) return null;
    _images[picture.key] = image;
    return image.clone();
  }

  /// A new handle to [picture]'s image, decoding it first if needed, or null
  /// when the picture is refused or cannot be drawn. Never throws.
  Future<ui.Image?> load(ProxyDelegatePicture picture) async {
    final cached = this.cached(picture);
    if (cached != null) return cached;
    final key = picture.key;
    final image = await (_pending[key] ??= _decode(picture).whenComplete(() {
      // A block body: returning the removed future would await itself.
      _pending.remove(key);
    }));
    try {
      return image?.clone();
    } catch (_) {
      // Cleared while this caller waited.
      return null;
    }
  }

  /// Drops every decoded image.
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }

  /// Decodes [picture] and keeps the result, or null on any failure.
  Future<ui.Image?> _decode(ProxyDelegatePicture picture) async {
    try {
      final pixels = await _decoder.decode(picture);
      if (pixels.width != kDelegatePictureEdge ||
          pixels.height != kDelegatePictureEdge ||
          pixels.rgba.length != pixels.width * pixels.height * 4) {
        return null;
      }
      final drawn = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels.rgba,
        pixels.width,
        pixels.height,
        ui.PixelFormat.rgba8888,
        drawn.complete,
      );
      final image = await drawn.future;
      _images[picture.key] = image;
      while (_images.length > capacity) {
        final oldest = _images.keys.first;
        _images.remove(oldest)!.dispose();
      }
      return image;
    } catch (_) {
      return null;
    }
  }
}

/// Decodes delegate pictures; tests replace it.
final delegatePictureDecoderProvider = Provider<DelegatePictureDecoder>(
  (_) => const RustDelegatePictureDecoder(),
);

/// The app's decoded delegate pictures.
final delegatePictureCacheProvider = Provider<DelegatePictureCache>((ref) {
  final cache = DelegatePictureCache(ref.watch(delegatePictureDecoderProvider));
  ref.onDispose(cache.clear);
  return cache;
});
