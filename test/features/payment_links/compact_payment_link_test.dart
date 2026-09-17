import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_sharing.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_qr_share_card.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../support/payment_links_screen_support.dart';
import '../../support/legacy_payment_link.dart';

const _message = "It's a great day to shield your ZEC 🛡️";
const _golden24 =
    'WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNzQ3LCJJdCdzIGEgZ3JlYXQgZGF5IHRvIHNoaWVsZCB5b3VyIFpFQyDwn5uh77iPIl0';
const _golden12 =
    'WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNzQ3LCJJdCdzIGEgZ3JlYXQgZGF5IHRvIHNoaWVsZCB5b3VyIFpFQyDwn5uh77iPIl0';
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
String withJson(Object? payload) =>
    withJsonBytes(utf8.encode(jsonEncode(payload)));
String withJsonBytes(List<int> bytes) => card()
    .toShareUri(compact: true)
    .replace(fragment: 'v3=${base64UrlEncode(bytes).replaceAll('=', '')}')
    .toString();
List<Object?> fieldsOf(String link) =>
    jsonDecode(
          utf8.decode(
            base64Url.decode(
              base64Url.normalize(Uri.parse(link).fragment.substring(3)),
            ),
          ),
        )
        as List<Object?>;

void main() {
  final api = _MnemonicVectors();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.failAddress = false;
    api.decodingCalls = 0;
    api.addressValidationGate = null;
  });

  test('matches independently encoded JSON vectors and exact size targets', () {
    for (final entry in {16: _golden12, 32: _golden24}.entries) {
      final source = card(entropyBytes: entry.key, presentation: decorated);
      final uri = source.toShareUri(compact: true);
      expect(uri.fragment, 'v3=${entry.value}');
      expect(uri.toString().length, entry.key == 32 ? 233 : 205);
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
      final extra = n == 32 ? 28 : 0;
      expect(wire(card(entropyBytes: n)).length, 114 + extra);
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
        144 + extra,
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
        830 + extra,
      );
    }
  });

  test(
    'v1, v2 and v3 have identical payload identity and stable v2 recovery',
    () {
      final source = card(presentation: decorated);
      final v1 = VizorPaymentLink.parse(
        legacyPaymentLinkUri(source).toString(),
      );
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
        VizorPaymentLink.parse(legacyPaymentLinkUri(source).toString()),
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
    final oversized = card(label: '"' * 6000);
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
    'rejects an address mismatch without replacing the recovery record',
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
    },
  );

  for (final action in ['copy', 'qr']) {
    testWidgets(
      'failed compact $action preserves the card and can be retried',
      (tester) async {
        final source = card();
        final saved = source.toRecoveryUri();
        final record = PaymentLinkRecoveryRecord(
          link: source,
          sourceAccountUuid: 'account-1',
          claimFeeReserveZatoshi: BigInt.from(10000),
          state: PaymentLinkRecoveryState.funded,
          updatedAt: DateTime.utc(2026, 9, 14),
          fundingTxids: '01' * 32,
        );
        final clipboard = FakePaymentLinkClipboard();
        final operations = FakePaymentLinkOperations(records: [record]);
        api.failAddress = true;
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          clipboard: clipboard,
        );
        final button = find.byKey(
          ValueKey('payment_link_card_${action}_action'),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.text(
            action == 'copy'
                ? 'Gift link could not be copied.'
                : 'Gift link could not be shared.',
          ),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(clipboard.copiedSecrets, isEmpty);
        expect(operations.sharedLinks, isEmpty);
        expect(
          (await operations.loadCreatedLinkRecoveries()).single.link
              .toRecoveryUri(),
          saved,
        );

        api.failAddress = false;
        await tester.tap(button);
        await tester.pumpAndSettle();
        if (action == 'copy') {
          expect(clipboard.copiedSecrets.single, wire(source));
          expect(operations.sharedLinks, hasLength(1));
        } else {
          expect(find.byType(PaymentLinkQrShareCard), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
      skip: !kPaymentLinkCompactSharing,
    );
  }

  test(
    'rejects truncation, malformed JSON and noncanonical Base64 before FFI',
    () {
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
      for (final malformed in [
        <int>[0xff],
        utf8.encode('not JSON'),
        utf8.encode('{"network":"main"}'),
        utf8.encode('${utf8.decode(bytes)} trailing'),
      ]) {
        expect(
          () => VizorPaymentLink.parse(withJsonBytes(malformed)),
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
    },
  );

  test('validates positional JSON fields before mnemonic conversion', () {
    final plain = fieldsOf(wire(card()));
    for (final invalid in <Object?>[
      null,
      {},
      [],
      plain.take(3).toList(),
      [...plain, null, null, null, null, null],
      for (final network in [null, 0, 'test']) [...plain]..[0] = network,
      for (final entropy in [
        null,
        0,
        '',
        'not-base64!',
        'AA==',
        base64UrlEncode(List.filled(15, 0)).replaceAll('=', ''),
        base64UrlEncode(List.filled(33, 0)).replaceAll('=', ''),
      ])
        [...plain]..[1] = entropy,
      for (final height in [0, -1, 0x100000000, 1.5, '3483141'])
        [...plain]..[2] = height,
      for (final amount in [
        0,
        1000000,
        '0',
        '-1',
        '01',
        '1e6',
        '2100000000000001',
      ])
        [...plain]..[3] = amount,
      [...plain, 123],
      [...plain, 'invalid!'],
      [...plain, null, -1],
      [...plain, null, '11.1747'],
      [...plain, null, null, 123],
      [...plain, null, null, 'a' * 129],
      [...plain, null, null, null, {}],
    ]) {
      expect(
        () => VizorPaymentLink.parse(withJson(invalid)),
        throwsFormatException,
      );
    }
    expect(api.decodingCalls, 0);
  });

  test('uses JSON null placeholders and accepts ordinary JSON whitespace', () {
    final source = card(
      presentation: const PaymentLinkPresentation(message: 'Hello'),
    );
    expect(fieldsOf(wire(source)).sublist(4), [null, null, 'Hello']);
    final plain = card();
    final fields = [...fieldsOf(wire(plain)), null, null, null, null];
    final pretty = withJsonBytes(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(fields)),
    );
    expect(
      VizorPaymentLink.parse(pretty).toShareUri(compact: true),
      plain.toShareUri(compact: true),
    );
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

  for (final startAnotherCard in [false, true]) {
    testWidgets(
      'compact QR respects desktop navigation after validation ($startAnotherCard)',
      (tester) async {
        final record = PaymentLinkRecoveryRecord(
          link: card(),
          sourceAccountUuid: 'account-1',
          claimFeeReserveZatoshi: BigInt.from(10000),
          state: PaymentLinkRecoveryState.funded,
          updatedAt: DateTime.utc(2026, 9, 14),
          fundingTxids: '01' * 32,
        );
        final gate = Completer<void>();
        api.addressValidationGate = gate;
        await pumpPaymentLinksScreen(
          tester,
          operations: FakePaymentLinkOperations(records: [record]),
        );
        await tester.tap(find.bySemanticsLabel('Show gift card QR code'));
        await tester.pump();
        expect(find.byType(PaymentLinkQrShareCard), findsNothing);

        final editor = find.byKey(const ValueKey('payment_link_amount_editor'));
        if (startAnotherCard) {
          await tester.tap(
            find.byKey(const ValueKey('payment_link_create_card_button')),
          );
          await tester.pumpAndSettle();
          await tester.enterText(editor, '0.25');
        }
        gate.complete();
        await tester.pumpAndSettle();

        expect(
          find.byType(PaymentLinkQrShareCard),
          startAnotherCard ? findsNothing : findsOneWidget,
        );
        if (startAnotherCard) {
          final editable = find.descendant(
            of: editor,
            matching: find.byType(EditableText),
            matchRoot: true,
          );
          expect(tester.widget<EditableText>(editable).controller.text, '0.25');
        }
        expect(tester.takeException(), isNull);
      },
      skip: !kPaymentLinkCompactSharing,
    );
  }

  for (final pending in ['validation', 'failed validation', 'clipboard']) {
    testWidgets(
      'compact copy handles navigation while awaiting $pending',
      (tester) async {
        final record = PaymentLinkRecoveryRecord(
          link: card(),
          sourceAccountUuid: 'account-1',
          claimFeeReserveZatoshi: BigInt.from(10000),
          state: PaymentLinkRecoveryState.funded,
          updatedAt: DateTime.utc(2026, 9, 14),
          fundingTxids: '01' * 32,
        );
        final validationGate = Completer<void>();
        final copyGate = Completer<void>();
        api.addressValidationGate = validationGate;
        api.failAddress = pending == 'failed validation';
        final clipboard = FakePaymentLinkClipboard(copyCompleter: copyGate);
        final operations = FakePaymentLinkOperations(records: [record]);
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          clipboard: clipboard,
        );
        await tester.tap(
          find.byKey(const ValueKey('payment_link_card_copy_action')),
        );
        await tester.pump();
        expect(clipboard.copiedSecrets, isEmpty);
        if (pending == 'clipboard') {
          validationGate.complete();
          await tester.pump();
          expect(clipboard.copiedSecrets, hasLength(1));
        }
        expect(operations.sharedLinks, isEmpty);

        await tester.tap(
          find.byKey(const ValueKey('payment_link_create_card_button')),
        );
        await tester.pumpAndSettle();
        final editor = find.byKey(const ValueKey('payment_link_amount_editor'));
        await tester.enterText(editor, '0.25');
        if (!validationGate.isCompleted) validationGate.complete();
        copyGate.complete();
        await tester.pumpAndSettle();

        // A successful clipboard write still needs its shared-state update.
        final copies = pending == 'clipboard' ? 1 : 0;
        expect(clipboard.copiedSecrets, hasLength(copies));
        expect(operations.sharedLinks, hasLength(copies));
        expect(find.byType(AlertDialog), findsNothing);
        final editable = find.descendant(
          of: editor,
          matching: find.byType(EditableText),
          matchRoot: true,
        );
        expect(tester.widget<EditableText>(editable).controller.text, '0.25');
        expect(tester.takeException(), isNull);
      },
      skip: !kPaymentLinkCompactSharing,
    );
  }

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
  Completer<void>? addressValidationGate;
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
    await addressValidationGate?.future;
    if (failAddress) throw StateError('Mismatch');
  }

  @override
  Future<BigInt> crateApiWalletGetLatestBlockHeight({
    required String lightwalletdUrl,
    required String network,
  }) async => BigInt.from(3500000);

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
