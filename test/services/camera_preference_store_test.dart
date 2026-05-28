import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/camera_preference_store.dart';

void main() {
  test('returns null when no QR camera preference has been saved', () async {
    final dir = await Directory.systemTemp.createTemp('camera-preferences-');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final store = CameraPreferenceStore(supportDirectory: () async => dir);

    expect(await store.readLastQrCameraId(), isNull);
  });

  test('persists the last QR camera id', () async {
    final dir = await Directory.systemTemp.createTemp('camera-preferences-');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final store = CameraPreferenceStore(supportDirectory: () async => dir);

    await store.writeLastQrCameraId(' camera-2 ');

    expect(await store.readLastQrCameraId(), 'camera-2');
  });
}
