import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_picture.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';

/// Stands in for the Rust decoder: opaque white pixels, or a refusal.
class FakeDelegatePictureDecoder implements DelegatePictureDecoder {
  /// Picture keys decoded, in order.
  final calls = <String>[];

  /// While set, every decode is refused with this reason, as Rust refuses
  /// a picture.
  String? failure;

  /// Edge of the pixels returned.
  int edge = kDelegatePictureEdge;

  @override
  Future<DelegatePicturePixels> decode(ProxyDelegatePicture picture) async {
    calls.add(picture.key);
    final failure = this.failure;
    if (failure != null) throw StateError(failure);
    final length = edge * edge * 4;
    return (
      width: edge,
      height: edge,
      rgba: Uint8List(length)..fillRange(0, length, 0xFF),
    );
  }
}

/// Lets pictures that began decoding while pumping finish: the engine draws
/// pixels outside fake time.
Future<void> settleDelegatePictures(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
