import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/owned_regtest_control.dart';

void main() {
  group('ownedRegtestRpc', () {
    final first = 'ab' * 32;
    final last = 'cd' * 32;

    test(
      'routes exact mining and proof requests through owned controls',
      () async {
        final requests = <Object?>[];
        Future<Map<String, Object?>> post(
          String path,
          Map<String, Object?> body,
        ) async {
          requests.add([path, body]);
          if (path == '/mine') {
            return {
              'hashes': [first, last],
              'tip': {'height': 502, 'hash': last},
            };
          }
          return {'txid': first, 'confirmations': 2, 'blockhash': first};
        }

        expect(await ownedRegtestRpc('generate', [2], post: post), [
          first,
          last,
        ]);
        expect(
          await ownedRegtestRpc('getrawtransaction', [first, 1], post: post),
          {'txid': first, 'confirmations': 2, 'blockhash': first},
        );
        expect(requests, [
          [
            '/mine',
            {'blocks': 2},
          ],
          [
            '/raw-transaction',
            {'txid': first},
          ],
        ]);
      },
    );

    test('reads the current original chain height without mutation', () async {
      expect(
        await ownedRegtestRpc(
          'getblockcount',
          [],
          get: (path) async {
            expect(path, '/status');
            return {'zcashdHeight': 500};
          },
        ),
        500,
      );
      await expectLater(
        ownedRegtestRpc(
          'getblockcount',
          [],
          get: (_) async => {'zcashdHeight': true},
        ),
        throwsStateError,
      );
    });

    test(
      'returns exact signed bytes for the native outbox raw lookup',
      () async {
        final requests = <Object?>[];
        const signedHex = '00aB01ff';
        final result = await ownedRegtestRpc(
          'getrawtransaction',
          [first, 0],
          post: (path, body) async {
            requests.add([path, body]);
            return {'txid': first, 'hex': signedHex, 'confirmations': 0};
          },
        );
        expect(result, signedHex);
        expect(requests, [
          [
            '/raw-transaction',
            {'txid': first},
          ],
        ]);
      },
    );

    test('rejects missing or malformed raw signed bytes', () async {
      for (final result in <Map<String, Object?>>[
        {'txid': first},
        {'hex': null},
        {'hex': true},
        {'hex': ''},
        {'hex': 'abc'},
        {'hex': '00zz'},
      ]) {
        await expectLater(
          ownedRegtestRpc('getrawtransaction', [
            first,
            0,
          ], post: (_, _) async => result),
          throwsStateError,
        );
      }
    });

    test('preserves the original raw lookup failure', () async {
      final failure = StateError('original transaction not found');
      await expectLater(
        ownedRegtestRpc('getrawtransaction', [
          first,
          0,
        ], post: (_, _) async => throw failure),
        throwsA(same(failure)),
      );
    });

    test(
      'rejects unsupported requests before any controller operation',
      () async {
        var requests = 0;
        for (final request in <(String, List<Object?>)>[
          ('generate', []),
          ('generate', [0]),
          ('generate', [true]),
          ('generate', [1001]),
          ('generate', [1, 2]),
          ('getblockcount', [1]),
          ('getrawtransaction', [first, true]),
          ('getrawtransaction', [first, 2]),
          ('getrawtransaction', [first, '0']),
          ('getrawtransaction', ['bad', 1]),
          ('sendrawtransaction', ['bytes']),
        ]) {
          await expectLater(
            ownedRegtestRpc(
              request.$1,
              request.$2,
              post: (_, _) async {
                requests++;
                return {};
              },
              get: (_) async {
                requests++;
                return {};
              },
            ),
            throwsArgumentError,
          );
        }
        expect(requests, 0);
      },
    );

    test(
      'refuses duplicate, fabricated or mismatched generated block receipts',
      () async {
        for (final result in <Map<String, Object?>>[
          {
            'hashes': [first, first],
            'tip': {'height': 502, 'hash': first},
          },
          {
            'hashes': [first],
            'tip': {'height': 502, 'hash': first},
          },
          {
            'hashes': [first, 'bad'],
            'tip': {'height': 502, 'hash': 'bad'},
          },
          {
            'hashes': [first, last],
            'tip': {'height': 502, 'hash': first},
          },
          {
            'hashes': [first, last],
            'tip': {'height': true, 'hash': last},
          },
        ]) {
          await expectLater(
            ownedRegtestRpc('generate', [2], post: (_, _) async => result),
            throwsStateError,
          );
        }
      },
    );

    test(
      'does not turn an original control failure into an RPC success',
      () async {
        final failure = StateError('original mining failed');
        await expectLater(
          ownedRegtestRpc('generate', [1], post: (_, _) async => throw failure),
          throwsA(same(failure)),
        );
      },
    );
  });

  group('withNativeClipboard', () {
    test('protects only the copy/read and returns its actual result', () async {
      final events = <String>[];
      final value = await withNativeClipboard(
        () async {
          events.add('copy/read');
          return 'copied address';
        },
        acquireLease: () async => events.add('acquire'),
        releaseLease: () async => events.add('release'),
      );
      expect(value, 'copied address');
      expect(events, ['acquire', 'copy/read', 'release']);
    });

    test(
      'failed actions preserve the error and retain the lease for host stop',
      () async {
        final original = StateError('copy assertion failed');
        var held = false;
        await expectLater(
          withNativeClipboard<void>(
            () async => throw original,
            acquireLease: () async => held = true,
            releaseLease: () async => held = false,
          ),
          throwsA(same(original)),
        );
        expect(held, isTrue);
      },
    );

    test('acquisition failure starts neither action nor release', () async {
      final events = <String>[];
      await expectLater(
        withNativeClipboard<void>(
          () async => events.add('action'),
          acquireLease: () async => throw StateError('cancelled while queued'),
          releaseLease: () async => events.add('release'),
        ),
        throwsStateError,
      );
      expect(events, isEmpty);
    });

    test(
      'unproven release remains a failure rather than returning success',
      () async {
        await expectLater(
          withNativeClipboard(
            () async => 'copied address',
            acquireLease: () async {},
            releaseLease: () async => throw StateError('release unproven'),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'a deployed manual runner outside the cohort does not request a lease',
      () async {
        expect(
          await withNativeClipboard(() async => 'manual copy'),
          'manual copy',
        );
      },
    );

    test(
      'rejects incomplete test callbacks before starting an action',
      () async {
        var started = false;
        await expectLater(
          withNativeClipboard<void>(
            () async => started = true,
            acquireLease: () async {},
          ),
          throwsArgumentError,
        );
        expect(started, isFalse);
      },
    );
  });
}
