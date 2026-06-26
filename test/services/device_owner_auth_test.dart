import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/device_owner_auth.dart';

/// Exercises the real [DeviceOwnerAuth.verify] channel mapping via a mock
/// MethodChannel. The widget tests replace `verify` wholesale with a fake, so
/// this is the only coverage of the fail-closed logic the reset gate relies on:
/// anything other than an explicit platform `true` must NOT verify.
///
/// The unsupported-platform guard is not covered here: `_platformSupported`
/// reads `dart:io` `Platform`, which the host test always reports as supported.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/device_owner_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  DeviceOwnerAuth build() => DeviceOwnerAuth(channel: channel);

  void mockResult(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('verify fail-closed mapping', () {
    test('returns true only on an explicit platform success', () async {
      mockResult((_) => true);
      expect(await build().verify(reason: 'r'), isTrue);
    });

    test('returns false when the platform reports failure', () async {
      mockResult((_) => false);
      expect(await build().verify(reason: 'r'), isFalse);
    });

    test('returns false when the platform returns null', () async {
      mockResult((_) => null);
      expect(await build().verify(reason: 'r'), isFalse);
    });

    test('user cancellation returns false, not an exception', () async {
      mockResult((_) => throw PlatformException(code: 'cancelled'));
      expect(await build().verify(reason: 'r'), isFalse);
    });

    test('"unavailable" platform error throws unavailable', () async {
      mockResult(
        (_) => throw PlatformException(code: 'unavailable', message: 'nope'),
      );
      await expectLater(
        build().verify(reason: 'r'),
        throwsA(
          isA<DeviceOwnerAuthException>().having(
            (e) => e.kind,
            'kind',
            DeviceOwnerAuthErrorKind.unavailable,
          ),
        ),
      );
    });

    test(
      '"no_local_credential" platform error throws noLocalCredential',
      () async {
        mockResult((_) => throw PlatformException(code: 'no_local_credential'));
        await expectLater(
          build().verify(reason: 'r'),
          throwsA(
            isA<DeviceOwnerAuthException>().having(
              (e) => e.kind,
              'kind',
              DeviceOwnerAuthErrorKind.noLocalCredential,
            ),
          ),
        );
      },
    );

    test('any other platform error throws failed', () async {
      mockResult((_) => throw PlatformException(code: 'boom'));
      await expectLater(
        build().verify(reason: 'r'),
        throwsA(
          isA<DeviceOwnerAuthException>().having(
            (e) => e.kind,
            'kind',
            DeviceOwnerAuthErrorKind.failed,
          ),
        ),
      );
    });

    test('a native reply that never arrives times out as unavailable', () async {
      // Simulates the Android < 30 lost-result hang: the handler never replies.
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final auth = DeviceOwnerAuth(
        channel: channel,
        verifyTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        auth.verify(reason: 'r'),
        throwsA(
          isA<DeviceOwnerAuthException>().having(
            (e) => e.kind,
            'kind',
            DeviceOwnerAuthErrorKind.unavailable,
          ),
        ),
      );
    });

    test('a missing platform handler throws unavailable', () async {
      // No mock handler registered -> MissingPluginException.
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        build().verify(reason: 'r'),
        throwsA(
          isA<DeviceOwnerAuthException>().having(
            (e) => e.kind,
            'kind',
            DeviceOwnerAuthErrorKind.unavailable,
          ),
        ),
      );
    });
  });

  group('verify argument contract', () {
    test('sends only the reason to the platform channel', () async {
      MethodCall? captured;
      mockResult((call) {
        captured = call;
        return true;
      });
      await build().verify(reason: 'why');
      expect(captured!.method, 'verify');
      final args = captured!.arguments as Map;
      expect(args['reason'], 'why');
      expect(args.containsKey('password'), isFalse);
    });
  });
}
