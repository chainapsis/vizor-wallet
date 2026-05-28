import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

void main() {
  group('preferredQrScannerCamera', () {
    test('returns the preferred camera when it is present', () {
      final cameras = [
        _camera('first'),
        _camera('saved'),
        _camera('default', isDefault: true),
      ];

      final camera = preferredQrScannerCamera(
        cameras,
        preferredCameraId: 'saved',
      );

      expect(camera?.id, 'saved');
    });

    test('falls back to the platform default camera', () {
      final cameras = [_camera('first'), _camera('default', isDefault: true)];

      final camera = preferredQrScannerCamera(
        cameras,
        preferredCameraId: 'missing',
      );

      expect(camera?.id, 'default');
    });

    test('falls back to the first camera when there is no default', () {
      final cameras = [_camera('first'), _camera('second')];

      final camera = preferredQrScannerCamera(cameras);

      expect(camera?.id, 'first');
    });
  });
}

MobileScannerCameraInfo _camera(String id, {bool isDefault = false}) {
  return MobileScannerCameraInfo(
    id: id,
    name: 'Camera $id',
    facing: CameraFacing.external,
    lensType: CameraLensType.any,
    isDefault: isDefault,
    isExternal: true,
  );
}
