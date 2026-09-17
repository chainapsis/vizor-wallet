import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_sharing.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _message = "It's a great day to shield your ZEC 🛡️";
const _golden24 =
    'EAcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUmNQBAQg8AAAAAAAHvOEVHclkmQCsASXQncyBhIGdyZWF0IGRheSB0byBzaGllbGQgeW91ciBaRUMg8J-boe-4jz32S0A';
const _golden12 =
    'AAcAAAAAAAAAAAAAAAAAAAAABSY1AEBCDwAAAAAAAe84RUdyWSZAKwBJdCdzIGEgZ3JlYXQgZGF5IHRvIHNoaWVsZCB5b3VyIFpFQyDwn5uh77iPRb2-IQ';
String phrase(int bytes) =>
    '${List.filled(bytes == 32 ? 23 : 11, 'abandon').join(' ')} ${bytes == 32 ? 'art' : 'about'}';

VizorPaymentLink card({
  int entropyBytes = 32,
  String label = 'Payment link',
  PaymentLinkPresentation? presentation,
  BigInt? amount,
  int height = 3483141,
}) => VizorPaymentLink(
  network: 'main',
  address: 'locally-verified-address',
  amountZatoshi: amount ?? BigInt.from(1000000),
  mnemonic: phrase(entropyBytes),
  birthdayHeight: height,
  label: label,
  createdAt: DateTime.utc(2026, 9, 14),
  presentation: presentation,
);
const decorated = PaymentLinkPresentation(
  artworkId: 'knightMagic',
  message: _message,
  fiatSnapshot: PaymentLinkFiatSnapshot(amount: 11.1747),
);
String wire(VizorPaymentLink card) => card.toShareUri(compact: true).toString();
String withBody(List<int> body) {
  final checksum = sha256
      .convert([...utf8.encode('VizorPaymentLink/v3\u0000'), ...body])
      .bytes
      .take(4);
  return card()
      .toShareUri(compact: true)
      .replace(
        fragment:
            'v3=${base64UrlEncode([...body, ...checksum]).replaceAll('=', '')}',
      )
      .toString();
}

List<int> bodyOf(String link) {
  final token = Uri.parse(link).fragment.substring(3);
  final bytes = base64Url.decode(base64Url.normalize(token));
  return bytes.sublist(0, bytes.length - 4);
}

void main() {
  final api = _MnemonicVectors();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.failAddress = false;
    api.decodingCalls = 0;
  });

  test(
    'matches independently packed golden vectors and exact size targets',
    () {
      for (final entry in {16: _golden12, 32: _golden24}.entries) {
        final source = card(entropyBytes: entry.key, presentation: decorated);
        final uri = source.toShareUri(compact: true);
        expect(uri.fragment, 'v3=${entry.value}');
        expect(uri.toString().length, entry.key == 32 ? 185 : 164);
        expect(uri.path, '/payment-links/open');
        expect(uri.query, isEmpty);
        final restored = VizorPaymentLink.parse(uri.toString());
        expect(restored.mnemonic, source.mnemonic);
        expect(restored.hasSameCanonicalPayload(source), isTrue);
        expect(restored.knownAddress, isNull);
        expect(restored.knownCreatedAt, isNull);
        expect(restored.presentation!.message, _message);
        expect(restored.toShareUri(compact: true), uri);
      }
      for (final n in [16, 32]) {
        final extra = n == 32 ? 21 : 0;
        expect(wire(card(entropyBytes: n)).length, 92 + extra);
        expect(
          wire(
            card(
              entropyBytes: n,
              presentation: const PaymentLinkPresentation(
                artworkId: 'knightMagic',
                fiatSnapshot: PaymentLinkFiatSnapshot(amount: 11.1747),
              ),
            ),
          ).length,
          104 + extra,
        );
        expect(
          wire(
            card(
              entropyBytes: n,
              presentation: PaymentLinkPresentation(
                artworkId: 'knightMagic',
                message: List.filled(128, '🎉').join(),
                fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 11.1747),
              ),
            ),
          ).length,
          789 + extra,
        );
      }
    },
  );

  test(
    'v1, v2 and v3 have identical payload identity and stable v2 recovery',
    () {
      final source = card(presentation: decorated);
      final v1 = VizorPaymentLink.parse(source.toCompatibilityUri().toString());
      final v2 = VizorPaymentLink.parse(source.toRecoveryUri().toString());
      final v3 = VizorPaymentLink.parse(wire(source));
      for (final item in [v1, v2, v3]) {
        expect(item.hasSameCanonicalPayload(source), isTrue);
        expect(item.toRecoveryUri(), source.toRecoveryUri());
        expect(item.toRecoveryUri().fragment, startsWith('v2='));
        expect(
          paymentLinkClaimWalletDirectoryName(item),
          paymentLinkClaimWalletDirectoryName(source),
        );
      }
      expect(v1.address, source.address);
      expect(v1.createdAt, source.createdAt);
      expect(() => v3.toCompatibilityUri(), throwsFormatException);
      expect(source.toShareUri(compact: false), source.toRecoveryUri());
      expect(
        v3.hasSameCanonicalPayload(
          card(presentation: const PaymentLinkPresentation(message: 'Changed')),
        ),
        isFalse,
      );
      expect(v3.hasSameCanonicalPayload(card(amount: BigInt.one)), isFalse);
    },
  );

  test(
    'v3 persists as v2 and retains funding and pending-claim evidence on restart',
    () async {
      final source = card(presentation: decorated);
      final decoded = VizorPaymentLink.parse(wire(source)).withResolvedMetadata(
        address: source.address,
        createdAt: source.createdAt,
      );
      final senderStorage = _MemoryStorage();
      final sender = PaymentLinkRecoveryStore(senderStorage);
      await sender.saveDraft(
        link: decoded,
        sourceAccountUuid: 'sender',
        claimFeeReserveZatoshi: BigInt.from(10000),
      );
      await sender.markFunded(
        address: decoded.address,
        fundingTxids: 'funding-txid',
      );
      final senderJson =
          jsonDecode(senderStorage.value!) as Map<String, dynamic>;
      expect(
        Uri.parse(
          (senderJson['records'] as List).single['link'] as String,
        ).fragment,
        startsWith('v2='),
      );
      final restoredSender = (await PaymentLinkRecoveryStore(
        senderStorage,
      ).load()).single;
      expect(restoredSender.link.toRecoveryUri(), source.toRecoveryUri());
      expect(restoredSender.fundingTxids, 'funding-txid');
      expect(restoredSender.state, PaymentLinkRecoveryState.funded);
      final receiverStorage = _MemoryStorage();
      var receiver = PaymentLinkReceivedStore(receiverStorage);
      await receiver.saveReady(decoded);
      await receiver.markClaimStarted(
        address: decoded.address,
        destinationAccountUuid: 'receiver',
        priorTxids: ['prior-txid'],
      );
      await receiver.markReceiving(
        address: decoded.address,
        destinationAccountUuid: 'receiver',
        claimTxids: 'claim-txid',
      );
      final receiverJson =
          jsonDecode(receiverStorage.value!) as Map<String, dynamic>;
      expect(
        Uri.parse(
          (receiverJson['records'] as List).single['claimLink'] as String,
        ).fragment,
        startsWith('v2='),
      );
      receiver = PaymentLinkReceivedStore(receiverStorage);
      await receiver.saveReady(
        VizorPaymentLink.parse(source.toCompatibilityUri().toString()),
      );
      final restoredReceiver = (await receiver.load()).single;
      expect(restoredReceiver.status, PaymentLinkReceivedStatus.receiving);
      expect(restoredReceiver.claimTxids, 'claim-txid');
      expect(restoredReceiver.destinationAccountUuid, 'receiver');
      expect(restoredReceiver.claimPriorTxids, ['prior-txid']);
      expect(
        restoredReceiver.claimLink!.toRecoveryUri(),
        source.toRecoveryUri(),
      );
    },
  );

  test('rejects v3 labels that exceed the v2 recovery limit', () async {
    final oversized = card(label: '"' * 8000);
    final compact = wire(oversized);
    expect(compact.length, lessThan(VizorPaymentLink.maxEncodedLength));
    expect(() => oversized.toRecoveryUri(), throwsFormatException);
    expect(() => VizorPaymentLink.parse(compact), throwsFormatException);

    // Long labels remain supported when their escaped recovery payload fits.
    for (final label in ['a' * 8000, '"' * 4000]) {
      final source = card(label: label);
      final decoded = VizorPaymentLink.parse(wire(source)).withResolvedMetadata(
        address: source.address,
        createdAt: source.createdAt,
      );
      final receiver = PaymentLinkReceivedStore(_MemoryStorage());
      await receiver.saveReady(decoded);
      expect((await receiver.load()).single.claimLink!.label, label);
    }
  });

  test(
    'preserves optional custom labels, unknown artwork, fiat and Unicode',
    () {
      for (final presentation in [
        null,
        const PaymentLinkPresentation(),
        const PaymentLinkPresentation(artworkId: 'future_card-42'),
        const PaymentLinkPresentation(message: '한 🎉 é'),
        const PaymentLinkPresentation(
          fiatSnapshot: PaymentLinkFiatSnapshot(amount: 0),
        ),
        decorated,
      ]) {
        for (final label in ['Payment link', '', 'Birthday 🎉']) {
          final source = card(label: label, presentation: presentation);
          final decoded = VizorPaymentLink.parse(wire(source));
          expect(decoded.hasSameCanonicalPayload(source), isTrue);
          expect(wire(decoded), wire(source));
        }
      }
    },
  );

  test(
    'fails safely on address mismatch without replacing the original link',
    () async {
      final source = card();
      final saved = source.toRecoveryUri();
      await preparePaymentLinkShareUri(source, compact: true);
      api.failAddress = true;
      await expectLater(
        preparePaymentLinkShareUri(source, compact: true),
        throwsFormatException,
      );
      expect(source.toRecoveryUri(), saved);
      expect(
        await preparePaymentLinkShareUri(source, compatibility: true),
        source.toCompatibilityUri(),
      );
    },
  );

  test('rejects truncation, corruption and noncanonical Base64 before FFI', () {
    final valid = wire(card(presentation: decorated));
    final uri = Uri.parse(valid);
    final token = uri.fragment.substring(3);
    final bytes = base64Url.decode(base64Url.normalize(token));
    for (var length = 0; length < bytes.length; length++) {
      final truncated = base64UrlEncode(
        bytes.take(length).toList(),
      ).replaceAll('=', '');
      expect(
        () => VizorPaymentLink.parse(
          uri.replace(fragment: 'v3=$truncated').toString(),
        ),
        throwsFormatException,
      );
    }
    for (var i = 0; i < bytes.length; i++) {
      final corrupt = bytes.toList();
      corrupt[i] ^= 1;
      expect(
        () => VizorPaymentLink.parse(
          uri
              .replace(
                fragment: 'v3=${base64UrlEncode(corrupt).replaceAll('=', '')}',
              )
              .toString(),
        ),
        throwsFormatException,
      );
    }
    for (final malformed in [
      '$token=',
      '$token&x=secret',
      '+$token',
      '%41${token.substring(1)}',
      '${token.substring(0, token.length - 1)}B',
    ]) {
      expect(
        () => VizorPaymentLink.parse(
          '${uri.replace(fragment: '')}#v3=$malformed',
        ),
        throwsFormatException,
      );
    }
    expect(api.decodingCalls, 0);
  });

  test('rejects checksum-valid unsupported fields, bad lengths and text', () {
    final plain = bodyOf(wire(card()));
    for (final header in [3, 20, 32, 255]) {
      final body = plain.toList()..[0] = header;
      expect(
        () => VizorPaymentLink.parse(withBody(body)),
        throwsFormatException,
      );
    }
    for (final body in [
      plain.toList()..[1] = 16,
      plain.toList()..fillRange(34, 38, 0),
      plain.toList()..fillRange(38, 46, 0),
      plain.toList()..fillRange(38, 46, 255),
      [...plain, 1],
      [...plain.toList()..[1] = 4, 1, 0, 255],
      [...plain.toList()..[1] = 4, 0, 2],
      [...plain.toList()..[1] = 1, 0],
      [...plain.toList()..[1] = 1, 255, 4, ...utf8.encode('new ')],
      [...plain.toList()..[1] = 2, ...List.filled(8, 255)],
    ]) {
      expect(
        () => VizorPaymentLink.parse(withBody(body)),
        throwsFormatException,
      );
    }
    expect(api.decodingCalls, 0);
  });

  test('bounds numbers, messages and labels on write', () {
    for (final source in [
      card(amount: BigInt.zero),
      card(amount: BigInt.from(2100000000000001)),
      card(height: 0),
      card(height: 0x100000000),
      card(label: 'a' * 20000),
      card(presentation: PaymentLinkPresentation(message: 'a' * 129)),
    ]) {
      expect(() => wire(source), throwsFormatException);
    }
  });

  test('bounded random input never exposes its payload in an error', () {
    final random = Random(741);
    for (var n = 0; n < 200; n++) {
      final payload = List.generate(
        random.nextInt(1024),
        (_) => random.nextInt(256),
      );
      final token = base64UrlEncode(payload).replaceAll('=', '');
      try {
        VizorPaymentLink.parse(
          'https://link.vizor.cash/payment-links/open#v3=$token',
        );
        fail('Random payload unexpectedly accepted');
      } on FormatException catch (error) {
        expect(error.source, isNull);
        if (token.isNotEmpty) expect(error.message, isNot(contains(token)));
      }
    }
  });
}

// Public BIP-39 vectors only. Rust tests verify the real conversion and derived
// addresses; integration tests exercise these calls through the native bridge.
class _MnemonicVectors implements RustLibApi {
  bool failAddress = false;
  int decodingCalls = 0;
  @override
  Uint8List crateApiWalletGiftMnemonicToEntropy({required String mnemonic}) {
    for (final length in [16, 32]) {
      if (mnemonic == phrase(length)) return Uint8List(length);
    }
    throw const FormatException('Invalid test mnemonic');
  }

  @override
  String crateApiWalletGiftMnemonicFromEntropy({required List<int> entropy}) {
    decodingCalls++;
    if (entropy.any((b) => b != 0) || ![16, 32].contains(entropy.length)) {
      throw StateError('Unknown vector');
    }
    return phrase(entropy.length);
  }

  @override
  Future<void> crateApiWalletValidateGiftAddress({
    required String mnemonic,
    required String network,
    required String address,
  }) async {
    if (failAddress) throw StateError('Mismatch');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStorage
    implements PaymentLinkRecoveryStorage, PaymentLinkReceivedStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}
