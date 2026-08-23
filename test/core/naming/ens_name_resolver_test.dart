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
  _FakeTransport(this._results, {List<Object> ccipResults = const []})
      : _ccipResults = List.of(ccipResults);

  /// Ordered results/errors, one per expected `ethCall` invocation. Each
  /// entry is either a 0x-hex success string or an [EnsRpcException] to
  /// throw.
  final List<Object> _results;
  final List<String> calls = [];
  final List<String> toAddresses = [];

  /// Ordered results/errors, one per expected `ccipFetch` invocation (in the
  /// order the resolver iterates gateway URLs). Each entry is either a
  /// 0x-hex success string or an [Exception] to throw.
  final List<Object> _ccipResults;
  final List<String> ccipCalls = [];

  @override
  Future<String> ethCall({required String to, required String data}) async {
    calls.add(data);
    toAddresses.add(to);
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
  }) async {
    ccipCalls.add(url);
    final index = ccipCalls.length - 1;
    if (index >= _ccipResults.length) {
      throw StateError('Unexpected extra ccipFetch #$index');
    }
    final result = _ccipResults[index];
    if (result is Exception) throw result;
    return result as String;
  }
}

List<int> _addressWord(List<int> addr20) => [...List.filled(12, 0), ...addr20];

List<int> _encodeBytes(List<int> b) =>
    [..._word(b.length), ..._padRight32(b)];

List<int> _encodeStringArray(List<String> items) {
  final utf8Items = items.map((s) => s.codeUnits).toList();
  final count = utf8Items.length;
  final headWords = <int>[];
  final tailWords = <int>[];
  var runningOffset = count * 32;
  for (final bytes in utf8Items) {
    headWords.addAll(_word(runningOffset));
    final elemTail = [..._word(bytes.length), ..._padRight32(bytes)];
    tailWords.addAll(elemTail);
    runningOffset += elemTail.length;
  }
  return [..._word(count), ...headWords, ...tailWords];
}

/// Hand-encodes an EIP-3668 `OffchainLookup` revert: selector(4) +
/// `(address sender, string[] urls, bytes callData, bytes4 callbackFunction, bytes extraData)`.
String _encodeOffchainLookupRevert({
  required List<int> sender,
  required List<String> urls,
  required List<int> callData,
  required List<int> callbackSelector,
  required List<int> extraData,
}) {
  final urlsBytes = _encodeStringArray(urls);
  final callDataBytes = _encodeBytes(callData);
  final extraDataBytes = _encodeBytes(extraData);

  const headSize = 5 * 32;
  final urlsOffset = headSize;
  final callDataOffset = urlsOffset + urlsBytes.length;
  final extraDataOffset = callDataOffset + callDataBytes.length;

  final tuple = [
    ..._addressWord(sender),
    ..._word(urlsOffset),
    ..._word(callDataOffset),
    ..._padRight32(callbackSelector),
    ..._word(extraDataOffset),
    ...urlsBytes,
    ...callDataBytes,
    ...extraDataBytes,
  ];
  return hexEncode([...hexDecode('556f1830'), ...tuple]);
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

    test(
      'throws noRecord (not RangeError) for a malformed record shorter than '
      '20 bytes',
      () async {
        // A non-empty resolver payload of only 10 bytes would make
        // decodeAddressWord throw a RangeError (word.sublist(word.length - 20))
        // if left unguarded, escaping the typed EnsResolutionException catch
        // and wedging swap in `resolving`.
        final shortPayload = List<int>.generate(10, (i) => i + 1);
        final transport = _FakeTransport([_resolveResultHex(shortPayload)]);
        final resolver = EnsNameResolver(transport);

        await expectLater(
          resolver.resolveEvmAddress('vitalik.eth', chainId: 1),
          throwsA(
            isA<EnsResolutionException>().having(
              (e) => e.kind,
              'kind',
              EnsResolutionFailure.noRecord,
            ),
          ),
        );
      },
    );

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

  group('EnsNameResolver CCIP-Read (EIP-3668)', () {
    final offchainSender = List<int>.generate(20, (i) => 0x50 + i);
    final expectedSenderAddress = decodeAddressWord(_addressWord(offchainSender));

    String buildRevert({List<String> urls = const [
      'https://gateway.example/{sender}/{data}.json',
    ]}) =>
        _encodeOffchainLookupRevert(
          sender: offchainSender,
          urls: urls,
          callData: hexDecode('aabbcc'),
          callbackSelector: hexDecode('b4a85801'),
          extraData: hexDecode('deadbeef'),
        );

    test('resolves via a single CCIP-Read hop', () async {
      final payload = List<int>.generate(20, (i) => i + 1);
      final transport = _FakeTransport(
        [
          EnsRpcException('reverted', revertData: buildRevert()),
          _resolveResultHex(payload),
        ],
        ccipResults: ['0x1122'],
      );
      final resolver = EnsNameResolver(transport);

      final result = await resolver.resolveEvmAddress(
        'offchain.eth',
        chainId: 1,
      );

      expect(result, startsWith('0x'));
      expect(result.length, 42);
      expect(transport.calls, hasLength(2));
      expect(transport.ccipCalls, hasLength(1));
      expect(transport.toAddresses[1], expectedSenderAddress);
    });

    test('falls through to the next gateway when one fails', () async {
      final payload = List<int>.generate(20, (i) => i + 1);
      final transport = _FakeTransport(
        [
          EnsRpcException(
            'reverted',
            revertData: buildRevert(
              urls: [
                'https://gateway1.example/{sender}/{data}.json',
                'https://gateway2.example/{sender}/{data}.json',
              ],
            ),
          ),
          _resolveResultHex(payload),
        ],
        ccipResults: [Exception('gateway1 down'), '0x1122'],
      );
      final resolver = EnsNameResolver(transport);

      final result = await resolver.resolveEvmAddress(
        'offchain.eth',
        chainId: 1,
      );

      expect(result, startsWith('0x'));
      expect(transport.ccipCalls, hasLength(2));
    });

    test('throws network when all gateways fail', () async {
      final transport = _FakeTransport(
        [
          EnsRpcException(
            'reverted',
            revertData: buildRevert(
              urls: [
                'https://gateway1.example/{sender}/{data}.json',
                'https://gateway2.example/{sender}/{data}.json',
              ],
            ),
          ),
        ],
        ccipResults: [Exception('down1'), Exception('down2')],
      );
      final resolver = EnsNameResolver(transport);

      await expectLater(
        resolver.resolveEvmAddress('offchain.eth', chainId: 1),
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
      'throws network when redirect hops are exhausted (5 hops > budget of 4)',
      () async {
        final revert = buildRevert();
        // Every ethCall (initial + each callback) reverts with the same
        // OffchainLookup, and every gateway fetch succeeds, so this only
        // terminates via hop-budget exhaustion.
        final transport = _FakeTransport(
          List<Object>.generate(
            5,
            (_) => EnsRpcException('reverted', revertData: revert),
          ),
          ccipResults: List<Object>.generate(4, (_) => '0x1122'),
        );
        final resolver = EnsNameResolver(transport);

        await expectLater(
          resolver.resolveEvmAddress('offchain.eth', chainId: 1),
          throwsA(
            isA<EnsResolutionException>().having(
              (e) => e.kind,
              'kind',
              EnsResolutionFailure.network,
            ),
          ),
        );
        // Initial call + 4 redirect hops = 5 ethCalls before giving up, and
        // no gateway fetch on the 5th (hop budget exhausted before fetching).
        expect(transport.calls, hasLength(5));
        expect(transport.ccipCalls, hasLength(4));
      },
    );
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

    test(
      'throws noRecord (fail-closed) for valid UTF-8 text that is not a '
      'valid Zcash address',
      () async {
        final payload = 'not a zcash address'.codeUnits;
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
      },
    );

    test(
      'throws invalidName for a non-.eth input without calling transport',
      () async {
        final transport = _FakeTransport([]);
        final resolver = EnsNameResolver(transport);

        await expectLater(
          resolver.resolveZcashAddress('not a name'),
          throwsA(
            isA<EnsResolutionException>().having(
              (e) => e.kind,
              'kind',
              EnsResolutionFailure.invalidName,
            ),
          ),
        );
        expect(transport.calls, isEmpty);
      },
    );
  });
}
