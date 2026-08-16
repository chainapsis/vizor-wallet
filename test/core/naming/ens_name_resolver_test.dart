import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_codec.dart';
import 'package:zcash_wallet/src/core/naming/ens_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';

/// Builds the canned `eth_call` result blob UniversalResolver.resolve would
/// return for a successful `addr(bytes32,uint256)` lookup whose return value
/// is [payload] (a raw address or record byte string).
///
/// Layout (all words are 32 bytes, big-endian):
///   innerBytes = [offset=0x20][len(payload)][payload padded to 32]
///   outerBlob  = [offset=0x40][resolver-address][len(innerBytes)][innerBytes padded]
String _resolveResultHex(List<int> payload) {
  final innerBytes = [
    ..._word(0x20),
    ..._word(payload.length),
    ..._padRight32(payload),
  ];
  final outerBlob = [
    ..._word(0x40),
    ..._word(0), // resolver address (unused by the resolver under test)
    ..._word(innerBytes.length),
    ..._padRight32(innerBytes),
  ];
  return hexEncode(outerBlob);
}

List<int> _word(int v) {
  final out = List<int>.filled(32, 0);
  var x = BigInt.from(v);
  for (var i = 31; i >= 0 && x > BigInt.zero; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

List<int> _padRight32(List<int> b) =>
    [...b, ...List.filled((32 - b.length % 32) % 32, 0)];

class _FakeTransport implements EnsRpcTransport {
  _FakeTransport(this._results);

  /// Ordered results/errors, one per expected `ethCall` invocation. Each
  /// entry is either a 0x-hex success string or an [EnsRpcException] to
  /// throw.
  final List<Object> _results;
  final List<String> calls = [];

  @override
  Future<String> ethCall({required String to, required String data}) async {
    calls.add(data);
    final index = calls.length - 1;
    if (index >= _results.length) {
      throw StateError('Unexpected extra ethCall #$index');
    }
    final result = _results[index];
    if (result is EnsRpcException) throw result;
    return result as String;
  }

  @override
  Future<String> ccipFetch({
    required String url,
    required String sender,
    required String data,
  }) => throw UnimplementedError('not used in Task 5');
}

void main() {
  group('EnsNameResolver.resolveEvmAddress', () {
    test('resolves a chain-specific record to a checksummed address', () async {
      final payload = List<int>.generate(20, (i) => i + 1);
      final transport = _FakeTransport([_resolveResultHex(payload)]);
      final resolver = EnsNameResolver(transport);

      final result = await resolver.resolveEvmAddress(
        'vitalik.eth',
        chainId: 8453,
      );

      expect(result, startsWith('0x'));
      expect(result.length, 42);
      expect(transport.calls, hasLength(1));
    });

    test(
      'falls back to the ETH (coin 60) record when the chain record is empty',
      () async {
        final zero = List<int>.filled(20, 0);
        final payload = List<int>.generate(20, (i) => 0xA0 + i);
        final transport = _FakeTransport([
          _resolveResultHex(zero),
          _resolveResultHex(payload),
        ]);
        final resolver = EnsNameResolver(transport);

        final result = await resolver.resolveEvmAddress(
          'vitalik.eth',
          chainId: 8453,
        );

        expect(result, startsWith('0x'));
        expect(transport.calls, hasLength(2));
        expect(transport.calls[0], isNot(equals(transport.calls[1])));
      },
    );

    test('throws noRecord when both chain and ETH records are empty', () async {
      final zero = List<int>.filled(20, 0);
      final transport = _FakeTransport([
        _resolveResultHex(zero),
        _resolveResultHex(zero),
      ]);
      final resolver = EnsNameResolver(transport);

      await expectLater(
        resolver.resolveEvmAddress('vitalik.eth', chainId: 8453),
        throwsA(
          isA<EnsResolutionException>().having(
            (e) => e.kind,
            'kind',
            EnsResolutionFailure.noRecord,
          ),
        ),
      );
    });

    test('maps a null-revertData EnsRpcException to network', () async {
      final transport = _FakeTransport([
        const EnsRpcException('boom'),
      ]);
      final resolver = EnsNameResolver(transport);

      await expectLater(
        resolver.resolveEvmAddress('vitalik.eth', chainId: 1),
        throwsA(
          isA<EnsResolutionException>().having(
            (e) => e.kind,
            'kind',
            EnsResolutionFailure.network,
          ),
        ),
      );
    });

    test(
      'maps a non-OffchainLookup revert to notRegistered',
      () async {
        final transport = _FakeTransport([
          const EnsRpcException('reverted', revertData: '0xdeadbeef'),
        ]);
        final resolver = EnsNameResolver(transport);

        await expectLater(
          resolver.resolveEvmAddress('doesnotexist12345.eth', chainId: 1),
          throwsA(
            isA<EnsResolutionException>().having(
              (e) => e.kind,
              'kind',
              EnsResolutionFailure.notRegistered,
            ),
          ),
        );
      },
    );

    test('throws invalidName for a non-.eth input without calling transport', () async {
      final transport = _FakeTransport([]);
      final resolver = EnsNameResolver(transport);

      await expectLater(
        resolver.resolveEvmAddress('not a name', chainId: 1),
        throwsA(
          isA<EnsResolutionException>().having(
            (e) => e.kind,
            'kind',
            EnsResolutionFailure.invalidName,
          ),
        ),
      );
      expect(transport.calls, isEmpty);
    });
  });

  group('EnsNameResolver.resolveZcashAddress', () {
    test('returns a valid UTF-8 Zcash address record verbatim', () async {
      const zcashAddress = 't1HsdDMzmJfq4vc7T17XYjEkLMLvbgM1fCi';
      final payload = zcashAddress.codeUnits;
      final transport = _FakeTransport([_resolveResultHex(payload)]);
      final resolver = EnsNameResolver(transport);

      final result = await resolver.resolveZcashAddress('vitalik.eth');

      expect(result, zcashAddress);
      expect(transport.calls, hasLength(1));
    });

    test('throws noRecord for garbage ZEC record bytes', () async {
      final payload = List<int>.generate(20, (i) => 0xFF - i);
      final transport = _FakeTransport([_resolveResultHex(payload)]);
      final resolver = EnsNameResolver(transport);

      await expectLater(
        resolver.resolveZcashAddress('vitalik.eth'),
        throwsA(
          isA<EnsResolutionException>().having(
            (e) => e.kind,
            'kind',
            EnsResolutionFailure.noRecord,
          ),
        ),
      );
    });

    test('throws noRecord when the ZEC record is empty (no fallback)', () async {
      final transport = _FakeTransport([_resolveResultHex(const [])]);
      final resolver = EnsNameResolver(transport);

      await expectLater(
        resolver.resolveZcashAddress('vitalik.eth'),
        throwsA(
          isA<EnsResolutionException>().having(
            (e) => e.kind,
            'kind',
            EnsResolutionFailure.noRecord,
          ),
        ),
      );
      expect(transport.calls, hasLength(1));
    });
  });
}
