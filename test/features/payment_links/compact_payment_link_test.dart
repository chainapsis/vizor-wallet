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

const _fundingTxid =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
const _message = "It's a great day to shield your ZEC 🛡️";
const _golden24 =
    'WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNywiSXQncyBhIGdyZWF0IGRheSB0byBzaGllbGQgeW91ciBaRUMg8J-boe-4jyJd';
const _legacyGolden24 =
    'WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNzQ3LCJJdCdzIGEgZ3JlYXQgZGF5IHRvIHNoaWVsZCB5b3VyIFpFQyDwn5uh77iPIl0';
const _legacyGolden12 =
    'WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNzQ3LCJJdCdzIGEgZ3JlYXQgZGF5IHRvIHNoaWVsZCB5b3VyIFpFQyDwn5uh77iPIl0';
String phrase(int bytes) =>
    '${List.filled(bytes == 32 ? 23 : 11, 'abandon').join(' ')} ${bytes == 32 ? 'art' : 'about'}';

VizorPaymentLink card({
  int entropyBytes = 16,
  String? mnemonic,
  String label = 'Payment link',
  PaymentLinkPresentation? presentation,
  BigInt? amount,
  int height = 3483141,
  String network = 'main',
  int? fundingHeight,
  String? fundingTxid,
}) => VizorPaymentLink(
  network: network,
  address: 'locally-verified-address',
  amountZatoshi: amount ?? BigInt.from(1000000),
  mnemonic: mnemonic ?? phrase(entropyBytes),
  birthdayHeight: height,
  label: label,
  createdAt: DateTime.utc(2026, 9, 14),
  presentation: presentation,
  fundingHeight: fundingHeight,
  fundingTxid: fundingTxid,
);
const decorated = PaymentLinkPresentation(
  artworkId: 'knightMagic',
  message: _message,
  fiatSnapshot: PaymentLinkFiatSnapshot(amount: 11.17),
);
String wire(VizorPaymentLink card) => card.toShareUri().toString();
String withJson(Object? payload) =>
    withJsonBytes(utf8.encode(jsonEncode(payload)));
String withJsonBytes(List<int> bytes, {int version = 3}) => card()
    .toShareUri()
    .replace(
      fragment: 'v$version=${base64UrlEncode(bytes).replaceAll('=', '')}',
    )
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
    api.failEntropy = false;
    api.validatedMnemonics.clear();
    api.decodingCalls = 0;
    api.addressValidationGate = null;
  });

  group('binary gift v4', () {
    List<int> bytesOf(Uri uri) =>
        base64Url.decode(base64Url.normalize(uri.fragment.substring(3)));
    String withBytes(List<int> bytes) => Uri(
      scheme: 'https',
      host: 'link.vizor.cash',
      path: '/gift',
      fragment: 'v4=${base64UrlEncode(bytes).replaceAll('=', '')}',
    ).toString();

    test('round trips all locator modes with minimal amount ULEB128', () {
      final sources = [
        card(height: 3483141),
        card(fundingHeight: 4000000),
        card(fundingTxid: _fundingTxid),
      ];
      for (var index = 0; index < sources.length; index++) {
        final source = sources[index];
        final shared = source.toShareUri();
        final bytes = bytesOf(shared);
        expect(shared.path, '/gift');
        expect(shared.fragment, startsWith('v4='));
        expect(bytes.first, index);
        expect(bytes.sublist(1, 17), everyElement(0));
        // 1,000,000 is c0 84 3d in canonical unsigned LEB128.
        expect(bytes.sublist(17, 20), [0xc0, 0x84, 0x3d]);
        final restored = VizorPaymentLink.parse(shared.toString());
        expect(restored.locatorKind, source.locatorKind);
        expect(restored.amountZatoshi, source.amountZatoshi);
        expect(restored.mnemonic, source.mnemonic);
        expect(restored.fundingHeight, source.fundingHeight);
        expect(restored.fundingTxid, source.fundingTxid?.toLowerCase());
        expect(restored.toShareUri(), shared);
      }
      expect(bytesOf(sources[0].toShareUri()).sublist(20, 24), [0, 53, 38, 5]);
      expect(bytesOf(sources[1].toShareUri()).sublist(20, 24), [0, 61, 9, 0]);
      expect(
        bytesOf(sources[2].toShareUri()).sublist(20, 52),
        List<int>.generate(32, (index) => index + 1),
      );
    });

    test('preserves known display TLVs and omits unknown artwork on write', () {
      final source = card(fundingHeight: 4000000, presentation: decorated);
      final restored = VizorPaymentLink.parse(wire(source));
      expect(restored.presentation!.artworkId, 'knightMagic');
      expect(restored.presentation!.fiatSnapshot!.amount, 11.1747);
      expect(restored.presentation!.message, _message);
      expect(restored.toShareUri(), source.toShareUri());

      final unknownArtwork = card(
        presentation: const PaymentLinkPresentation(artworkId: 'future_card'),
      );
      expect(VizorPaymentLink.parse(wire(unknownArtwork)).presentation, isNull);
    });

    test(
      'skips unknown TLVs and stops safely at a malformed display suffix',
      () {
        final raw = bytesOf(
          card(
            presentation: const PaymentLinkPresentation(
              artworkId: 'knightMagic',
            ),
          ).toShareUri(),
        );
        final withUnknown = [...raw, 99, 3, 1, 2, 3, 3, 2, 104, 105];
        final parsedUnknown = VizorPaymentLink.parse(withBytes(withUnknown));
        expect(parsedUnknown.presentation!.artworkId, 'knightMagic');
        expect(parsedUnknown.presentation!.message, 'hi');

        for (final malformed in [
          [...raw, 3],
          [...raw, 3, 0x80],
          [...raw, 3, 5, 104, 105],
          [...raw, 3, 0x82, 0, 104, 105],
          [...raw, 3, 1, 0xff],
        ]) {
          final parsed = VizorPaymentLink.parse(withBytes(malformed));
          expect(parsed.presentation!.artworkId, 'knightMagic');
          expect(parsed.presentation!.message, isNull);
          // Re-encoding drops the malformed tail and retains canonical options.
          expect(
            parsed.toShareUri(),
            card(
              presentation: const PaymentLinkPresentation(
                artworkId: 'knightMagic',
              ),
            ).toShareUri(),
          );
        }
      },
    );

    test('fails closed on malformed core before mnemonic reconstruction', () {
      final raw = bytesOf(card(fundingTxid: _fundingTxid).toShareUri());
      final invalid = <List<int>>[
        [],
        for (var length = 1; length < 52; length++) raw.sublist(0, length),
        [...raw]..[0] = 3,
        [...raw]..setRange(17, 20, [0x80, 0x80, 0]),
        [...raw]..setRange(17, 20, [0, 0, 0]),
      ];
      for (final bytes in invalid) {
        expect(
          () => VizorPaymentLink.parse(withBytes(bytes)),
          throwsFormatException,
        );
      }
      expect(api.decodingCalls, 0);
    });

    test('bounds amount including claim reserve and rejects dual locators', () {
      final maximum = BigInt.from(2100000000000000 - 10000);
      expect(
        VizorPaymentLink.parse(wire(card(amount: maximum))).amountZatoshi,
        maximum,
      );
      for (final amount in [BigInt.zero, maximum + BigInt.one]) {
        expect(() => wire(card(amount: amount)), throwsFormatException);
      }
      expect(
        () => card(fundingHeight: 4000000, fundingTxid: _fundingTxid),
        throwsArgumentError,
      );
      final recovery = card(fundingHeight: 4000000).toRecoveryUri();
      final payload =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(recovery.fragment.substring(3)),
                  ),
                ),
              )
              as Map<String, dynamic>;
      payload['fundingTxid'] = _fundingTxid;
      final invalidRecovery = recovery.replace(
        fragment: 'v2=${base64UrlEncode(utf8.encode(jsonEncode(payload)))}',
      );
      expect(
        () => VizorPaymentLink.parse(invalidRecovery.toString()),
        throwsFormatException,
      );
    });

    test('keeps 24-word legacy cards on v3', () {
      final legacy = card(entropyBytes: 32, presentation: decorated);
      expect(legacy.toShareUri().path, '/payment-links/open');
      expect(legacy.toShareUri().fragment, startsWith('v3='));
      expect(VizorPaymentLink.parse(wire(legacy)).mnemonic, legacy.mnemonic);
    });

    test('keeps ordinary non-main cards on v3 and rejects direct v4', () {
      final ordinary = card(network: 'regtest');
      if (kPaymentLinkRegtestEnabled) {
        expect(ordinary.toShareUri().fragment, startsWith('v3='));
        expect(ordinary.toShareUri().path, '/payment-links/open');
      } else {
        expect(ordinary.toShareUri, throwsFormatException);
      }
      expect(
        () => card(network: 'regtest', fundingHeight: 100).toShareUri(),
        throwsFormatException,
      );
    });

    test('keeps local creation metadata and locator in v2 recovery', () {
      final source = VizorPaymentLink(
        network: 'main',
        address: 'locally-verified-address',
        amountZatoshi: BigInt.from(1000000),
        mnemonic: phrase(16),
        birthdayHeight: 3483141,
        label: 'Local label',
        createdAt: DateTime.utc(2026, 9, 14),
        isCreatedAtProvisional: true,
        fundingHeight: 4000000,
      );
      final shared = source.toShareUri();
      expect(shared.fragment, startsWith('v4='));
      expect(source.address, 'locally-verified-address');
      expect(source.createdAt, DateTime.utc(2026, 9, 14));
      expect(source.isCreatedAtProvisional, isTrue);
      final restored = VizorPaymentLink.parse(
        source.toRecoveryUri().toString(),
      );
      expect(restored.knownAddress, isNull);
      expect(restored.knownCreatedAt, isNull);
      expect(restored.isCreatedAtProvisional, isFalse);
      expect(restored.fundingHeight, 4000000);
      expect(restored.fundingTxid, isNull);
    });
  });

  test('matches independently encoded JSON vectors and exact size targets', () {
    for (final entry in {32: _golden24}.entries) {
      final source = card(entropyBytes: entry.key, presentation: decorated);
      final uri = source.toShareUri();
      expect(uri.fragment, 'v3=${entry.value}');
      expect(uri.toString().length, entry.key == 32 ? 230 : 202);
      expect(uri.path, '/payment-links/open');
      expect(uri.query, isEmpty);
      final restored = VizorPaymentLink.parse(uri.toString());
      expect(restored.mnemonic, source.mnemonic);
      expect(
        restored.mnemonic.split(' '),
        hasLength(entry.key == 16 ? 12 : 24),
      );
      expect(fieldsOf(uri.toString())[1], 'A' * (entry.key == 16 ? 22 : 43));
      expect(restored.hasSameCanonicalPayload(source), isTrue);
      expect(restored.knownAddress, isNull);
      expect(restored.knownCreatedAt, isNull);
      expect(restored.presentation!.message, _message);
      expect(restored.toShareUri(), uri);
    }
    for (final n in [32]) {
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
        141 + extra,
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
        828 + extra,
      );
    }
  });

  test('rounds shared USD snapshots to cents without changing recovery', () {
    for (final entry in <double, double>{
      0: 0,
      0.0049: 0,
      0.0051: 0.01,
      11.1747: 11.17,
      11.176: 11.18,
      11.999: 12,
      142.4: 142.4,
      1e308: 1e308,
    }.entries) {
      final source = card(
        presentation: PaymentLinkPresentation(
          fiatSnapshot: PaymentLinkFiatSnapshot(amount: entry.key),
        ),
      );
      final recovery = source.toRecoveryUri();
      final shared = wire(source);
      expect(fieldsOf(shared)[5], entry.value);
      final decoded = VizorPaymentLink.parse(shared);
      expect(decoded.presentation!.fiatSnapshot!.amount, entry.value);
      expect(decoded.mnemonic, source.mnemonic);
      expect(decoded.birthdayHeight, source.birthdayHeight);
      expect(decoded.amountZatoshi, source.amountZatoshi);
      expect(wire(decoded), shared);
      expect(source.presentation!.fiatSnapshot!.amount, entry.key);
      expect(source.toRecoveryUri(), recovery);
      expect(
        VizorPaymentLink.parse(
          recovery.toString(),
        ).presentation!.fiatSnapshot!.amount,
        entry.key,
      );
    }
  });

  test('decodes existing full-precision v1, v2 and v3 USD snapshots', () {
    for (final entry in {16: _legacyGolden12, 32: _legacyGolden24}.entries) {
      final source = card(
        entropyBytes: entry.key,
        presentation: const PaymentLinkPresentation(
          artworkId: 'knightMagic',
          message: _message,
          fiatSnapshot: PaymentLinkFiatSnapshot(amount: 11.1747),
        ),
      );
      for (final uri in [
        legacyPaymentLinkUri(source),
        source.toRecoveryUri(),
        source.toShareUri().replace(fragment: 'v3=${entry.value}'),
      ]) {
        final decoded = VizorPaymentLink.parse(uri.toString());
        expect(decoded.presentation!.fiatSnapshot!.amount, 11.1747);
        expect(decoded.hasSameCanonicalPayload(source), isTrue);
        expect(decoded.toRecoveryUri(), source.toRecoveryUri());
        expect(decoded.presentation!.message, _message);
        expect(decoded.presentation!.artworkId, 'knightMagic');
        expect(fieldsOf(wire(decoded))[5], 11.17);
      }
    }
  });

  test(
    'v1, v2 and v3 have identical payload identity and stable v2 recovery',
    () {
      final source = card(entropyBytes: 32, presentation: decorated);
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
      expect(source.toShareUri().fragment, startsWith('v3='));
      expect(
        v3.hasSameCanonicalPayload(
          card(
            entropyBytes: 32,
            presentation: const PaymentLinkPresentation(message: 'Changed'),
          ),
        ),
        isFalse,
      );
      expect(
        v3.hasSameCanonicalPayload(card(entropyBytes: 32, amount: BigInt.one)),
        isFalse,
      );
    },
  );

  test(
    'v3 persists as v2 and retains funding and pending-claim evidence on restart',
    () async {
      final source = card(entropyBytes: 32, presentation: decorated);
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
    for (final entropyBytes in [32]) {
      final oversized = card(entropyBytes: entropyBytes, label: '"' * 6050);
      final compact = wire(oversized);
      expect(compact.length, lessThan(VizorPaymentLink.maxEncodedLength));
      expect(() => oversized.toRecoveryUri(), throwsFormatException);
      expect(() => VizorPaymentLink.parse(compact), throwsFormatException);

      // Long labels remain supported when their escaped recovery payload fits.
      for (final label in ['a' * 8000, '"' * 4000]) {
        final source = card(entropyBytes: entropyBytes, label: label);
        final decoded = VizorPaymentLink.parse(wire(source))
            .withResolvedMetadata(
              address: source.address,
              createdAt: source.createdAt,
            );
        final receiver = PaymentLinkReceivedStore(_MemoryStorage());
        await receiver.saveReady(decoded);
        expect((await receiver.load()).single.claimLink!.label, label);
      }
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
          final source = card(
            entropyBytes: 32,
            label: label,
            presentation: presentation,
          );
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
      await preparePaymentLinkShareUri(source);
      api.failAddress = true;
      await expectLater(
        preparePaymentLinkShareUri(source),
        throwsFormatException,
      );
      expect(source.toRecoveryUri(), saved);
    },
  );

  test(
    'legacy whitespace shares v2 without changing the secret or cache',
    () async {
      for (final separator in ['  ', '\t', '\n']) {
        final original = card(mnemonic: phrase(32).replaceAll(' ', separator));
        for (final uri in [
          legacyPaymentLinkUri(original),
          original.toRecoveryUri(),
        ]) {
          final legacy = VizorPaymentLink.parse(uri.toString())
              .withResolvedMetadata(
                address: original.address,
                createdAt: original.createdAt,
              );
          final shared = await preparePaymentLinkShareUri(legacy);
          expect(shared.fragment, startsWith('v2='));
          expect(shared, original.toRecoveryUri());
          final restored = VizorPaymentLink.parse(shared.toString());
          expect(restored.mnemonic, original.mnemonic);
          expect(restored.hasSameCanonicalPayload(original), isTrue);
          expect(
            paymentLinkClaimWalletDirectoryName(restored),
            paymentLinkClaimWalletDirectoryName(original),
          );
          expect(api.validatedMnemonics.last, original.mnemonic);
          expect(() => legacy.toShareUri(), throwsFormatException);
        }
      }
    },
  );

  test(
    'legacy whitespace never bypasses address or payload validation',
    () async {
      final legacy = card(mnemonic: phrase(32).replaceAll(' ', '  '));
      final saved = legacy.toRecoveryUri();
      api.failAddress = true;
      await expectLater(
        preparePaymentLinkShareUri(legacy),
        throwsFormatException,
      );
      api.failAddress = false;
      final unresolved = VizorPaymentLink.parse(saved.toString());
      await expectLater(
        preparePaymentLinkShareUri(unresolved),
        throwsFormatException,
      );
      for (final invalid in [
        card(mnemonic: 'invalid  phrase'),
        card(mnemonic: legacy.mnemonic, amount: BigInt.zero),
        card(mnemonic: legacy.mnemonic, height: 0x100000000),
        card(mnemonic: legacy.mnemonic, label: 'a' * 20000),
        card(
          mnemonic: legacy.mnemonic,
          presentation: PaymentLinkPresentation(message: 'a' * 129),
        ),
      ]) {
        await expectLater(
          preparePaymentLinkShareUri(invalid),
          throwsFormatException,
        );
      }
      api.failEntropy = true;
      await expectLater(
        preparePaymentLinkShareUri(legacy),
        throwsFormatException,
      );
      await expectLater(
        preparePaymentLinkShareUri(card()),
        throwsFormatException,
      );
      expect(legacy.toRecoveryUri(), saved);
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
    );
  }

  test(
    'rejects truncation, malformed JSON and noncanonical Base64 before FFI',
    () {
      final valid = wire(card(entropyBytes: 32, presentation: decorated));
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
    final plain = fieldsOf(wire(card(entropyBytes: 32)));
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
      entropyBytes: 32,
      presentation: const PaymentLinkPresentation(message: 'Hello'),
    );
    expect(fieldsOf(wire(source)).sublist(4), [null, null, 'Hello']);
    final plain = card(entropyBytes: 32);
    final fields = [...fieldsOf(wire(plain)), null, null, null, null];
    final pretty = withJsonBytes(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(fields)),
    );
    expect(VizorPaymentLink.parse(pretty).toShareUri(), plain.toShareUri());
  });

  test('bounds numbers, messages and labels on write', () {
    for (final source in [
      card(entropyBytes: 32, amount: BigInt.zero),
      card(entropyBytes: 32, amount: BigInt.from(2100000000000001)),
      card(entropyBytes: 32, height: 0),
      card(entropyBytes: 32, height: 0x100000000),
      card(entropyBytes: 32, label: 'a' * 20000),
      card(
        entropyBytes: 32,
        presentation: PaymentLinkPresentation(message: 'a' * 129),
      ),
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
    );
  }

  for (final pending in ['validation', 'failed validation', 'clipboard']) {
    testWidgets('compact copy handles navigation while awaiting $pending', (
      tester,
    ) async {
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
    });
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
  bool failEntropy = false;
  final validatedMnemonics = <String>[];
  int decodingCalls = 0;
  Completer<void>? addressValidationGate;
  @override
  Uint8List crateApiWalletGiftMnemonicToEntropy({required String mnemonic}) {
    if (failEntropy) throw const FormatException('Conversion failed');
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
    validatedMnemonics.add(mnemonic);
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
