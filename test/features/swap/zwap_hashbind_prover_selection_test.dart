import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/integrations/zwap/zwap_hashbind_native.dart';
import 'package:zcash_wallet/src/features/swap/integrations/zwap/zwap_swap_config.dart';

// Prover selection policy:
// production default proves on-device; the ZWAP_HASHBIND_PROVER_URL define
// keeps the regtest HTTP helper in dev builds only; a release build with the
// define set fails closed before the scalar could leave the device.
void main() {
  const kBeHex =
      '000000000000000000000000000000000000000c523556789abcdef23456543c';

  Future<List<int>> native(String hex) async => [1];
  Future<List<int>> http(String hex) async => [2];

  group('selectZwapHashbindProver', () {
    test('no URL selects the native on-device prover (any mode)', () async {
      for (final release in [false, true]) {
        final prover = selectZwapHashbindProver(
          releaseMode: release,
          httpProverUrl: '',
          native: native,
          http: http,
        );
        expect(await prover(kBeHex), [1]);
      }
    });

    test('URL in debug/profile selects the HTTP regtest helper', () async {
      final prover = selectZwapHashbindProver(
        releaseMode: false,
        httpProverUrl: 'http://localhost:8790/prove',
        native: native,
        http: http,
      );
      expect(await prover(kBeHex), [2]);
    });

    test('URL in release fails closed without calling either prover',
        () async {
      var called = false;
      final prover = selectZwapHashbindProver(
        releaseMode: true,
        httpProverUrl: 'http://localhost:8790/prove',
        native: (_) async {
          called = true;
          return [1];
        },
        http: (_) async {
          called = true;
          return [2];
        },
      );
      await expectLater(
        prover(kBeHex),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('refusing to send the spend-auth scalar off-device'))),
      );
      expect(called, isFalse);
    });
  });

  group('ZwapNativeHashbindProver.prove input validation', () {
    test('rejects non-32-byte hex before touching the native library',
        () async {
      // Wrong length and non-hex both fail validation ahead of prover init —
      // no isolate, no FFI (safe to assert in a host test where the native
      // library is not linked).
      await expectLater(
        ZwapNativeHashbindProver.instance.prove('abcd'),
        throwsArgumentError,
      );
      await expectLater(
        ZwapNativeHashbindProver.instance.prove('zz' * 32),
        throwsArgumentError,
      );
    });
  });
}
