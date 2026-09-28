import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/services/camera_permission_settings.dart';

const _channel = MethodChannel('com.zcash.wallet/camera_permission');

const _denied = MobileScannerException(
  errorCode: MobileScannerErrorCode.permissionDenied,
);

/// Answers `authorizationStatus` with [status] and counts the lookups.
int Function() _mockAuthorization(String? Function() status) {
  var calls = 0;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (call.method != 'authorizationStatus') return null;
        calls++;
        final value = status();
        if (value == null) {
          throw PlatformException(code: 'unavailable');
        }
        return value;
      });
  return () => calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('off iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('isRestricted never asks the native channel', () async {
      final calls = _mockAuthorization(() => 'restricted');

      expect(await CameraPermissionSettings.isRestricted(), isFalse);
      expect(calls(), 0);
    });

    test('probe classifies denials as plain denials immediately', () async {
      final calls = _mockAuthorization(() => 'restricted');
      final controller = MobileScannerController(autoStart: false);
      final probe = CameraRestrictionProbe(controller);
      addTearDown(() async {
        probe.dispose();
        await controller.dispose();
      });

      expect(probe.restricted, isFalse);
      controller.value = controller.value.copyWith(error: _denied);
      await pumpEventQueue();

      expect(probe.restricted, isFalse);
      expect(calls(), 0);
    });
  });

  group('on iOS', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('isRestricted is true only for the restricted status', () async {
      String? status = 'restricted';
      _mockAuthorization(() => status);
      expect(await CameraPermissionSettings.isRestricted(), isTrue);

      status = 'denied';
      expect(await CameraPermissionSettings.isRestricted(), isFalse);

      status = null;
      expect(await CameraPermissionSettings.isRestricted(), isFalse);
    });

    test('isRestricted falls back to false without a native handler', () async {
      expect(await CameraPermissionSettings.isRestricted(), isFalse);
    });

    test('probe looks up every new denial', () async {
      var status = 'restricted';
      final calls = _mockAuthorization(() => status);
      final controller = MobileScannerController(autoStart: false);
      final probe = CameraRestrictionProbe(controller);
      addTearDown(() async {
        probe.dispose();
        await controller.dispose();
      });

      // The up-front lookup answers before any denial arrives.
      await pumpEventQueue();
      expect(probe.restricted, isTrue);
      expect(calls(), 1);

      controller.value = controller.value.copyWith(error: _denied);
      await pumpEventQueue();
      expect(probe.restricted, isTrue);
      expect(calls(), 2);

      // A retry clears the error; the next denial is classified afresh.
      status = 'denied';
      controller.value = controller.value.copyWith(isStarting: true);
      controller.value = controller.value.copyWith(error: _denied);
      await pumpEventQueue();
      expect(probe.restricted, isFalse);
      expect(calls(), 3);
    });
  });
}
