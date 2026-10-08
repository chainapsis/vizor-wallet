import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/incoming_link_dispatch.dart';
import 'package:zcash_wallet/src/features/payment_links/models/payment_link_scan_payload.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_claim_import_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_gift_link_rust_api.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: FakeGiftLinkRustApi()));
  tearDownAll(RustLib.dispose);

  test(
    'explicit paste and QR accept native cards; external intake stays closed',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      for (final raw in [zodlTestLink, '$zodlTestLink&amount=0.001']) {
        final link = VizorPaymentLink.parseForRedemption(raw);
        expect(link.isZodl, isTrue);
        expect(link.toRecoveryUri().toString(), raw);
        expect(decodePaymentLinkQr(raw, networkName: 'main').isZodl, isTrue);
        expect(
          () => decodePaymentLinkQr(raw, networkName: 'regtest'),
          throwsFormatException,
        );
        expect(() => VizorPaymentLink.parse(raw), throwsFormatException);
        expect(classifyIncomingLink(raw), isA<IncomingLinkUnknown>());
        expect(
          container.read(paymentLinkIntakeProvider.notifier).receive(raw),
          PaymentLinkIntakeResult.ignored,
        );
        expect(container.read(paymentLinkIntakeProvider).pendingLinks, isEmpty);
      }
    },
  );

  test('stated amount is optional and never caps the actual claim', () {
    final unknown = VizorPaymentLink.parseForRedemption(zodlTestLink);
    expect(unknown.statedAmountZatoshi, isNull);
    expect(unknown.amountZatoshi, BigInt.zero);
    expect(unknown.verifiedAmountZatoshi, isNull);
    expect(unknown.displayAmountZatoshi, isNull);
    final stated = VizorPaymentLink.parseForRedemption(
      '$zodlTestLink&amount=0.001',
    );
    expect(stated.amountZatoshi, BigInt.zero);
    expect(stated.verifiedAmountZatoshi, isNull);
    expect(stated.displayAmountZatoshi, BigInt.from(100000));
    for (final max in [BigInt.from(50000), BigInt.from(200000)]) {
      expect(stated.claimableAmountFromMax(max), max);
      final resolved = stated.withResolvedMetadata(amountZatoshi: max);
      expect(resolved.amountZatoshi, max);
      expect(resolved.verifiedAmountZatoshi, max);
      expect(resolved.displayAmountZatoshi, max);
      expect(resolved.statedAmountZatoshi, BigInt.from(100000));
      expect(resolved.toRecoveryUri(), stated.toRecoveryUri());
      expect(resolved.hasSameCanonicalPayload(stated), isTrue);
    }
  });

  test(
    'received storage restores sweep policy and verified amount after restart',
    () async {
      final storage = _ReceivedStorage();
      final store = PaymentLinkReceivedStore(storage);
      final link =
          VizorPaymentLink.parseForRedemption(
            '$zodlTestLink&amount=0.001',
          ).withResolvedMetadata(
            address: 'card-address',
            createdAt: DateTime.utc(2026, 10, 8),
            amountZatoshi: BigInt.from(190000),
          );
      await store.saveReady(link);
      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'recipient',
        priorTxids: [],
      );
      final restored = (await PaymentLinkReceivedStore(storage).load()).single;
      expect(restored.amountZatoshi, BigInt.from(190000));
      expect(restored.claimLink!.amountZatoshi, restored.amountZatoshi);
      expect(restored.claimLink!.statedAmountZatoshi, BigInt.from(100000));
      expect(restored.claimLink!.isZodl, isTrue);
      expect(restored.claimLink!.claimConfirmationTarget, 6);
      expect(restored.status, PaymentLinkReceivedStatus.submitting);
    },
  );

  for (final setupAccountUuid in [null, 'recipient']) {
    test(
      'a refilled native card journals a new attempt, setup $setupAccountUuid',
      () async {
        final storage = _ReceivedStorage();
        final store = PaymentLinkReceivedStore(storage);
        final original =
            VizorPaymentLink.parseForRedemption(
              '$zodlTestLink&amount=0.001',
            ).withResolvedMetadata(
              address: 'card-address',
              createdAt: DateTime.utc(2026, 10, 7),
              amountZatoshi: BigInt.from(90000),
            );
        await store.saveReady(original, setupAccountUuid: setupAccountUuid);
        await store.markClaimStarted(
          address: original.address,
          destinationAccountUuid: 'recipient',
          updatedAt: DateTime.utc(2026, 10, 7),
        );
        await store.markReceiving(
          address: original.address,
          destinationAccountUuid: 'recipient',
          claimTxids: 'old-tx',
          claimDestinationPool: 'sapling',
        );
        final oldReceipt = await store.markReceived(address: original.address);
        final refilled = original.withResolvedMetadata(
          amountZatoshi: BigInt.from(190000),
        );
        final before = storage.value;
        await expectLater(
          store.markClaimStarted(
            address: original.address,
            destinationAccountUuid: 'recipient',
            link: refilled,
          ),
          throwsStateError,
        );
        expect(storage.value, before);

        await store.markClaimRecoveryConfirmed(oldReceipt);
        await store.clearConfirmedClaimSecret(address: original.address);
        // Merely opening a new preview must not restore the old secret.
        await store.saveReady(refilled);
        expect((await store.find(original.address))!.claimLink, isNull);
        if (setupAccountUuid != null) {
          await expectLater(
            store.markClaimStarted(
              address: original.address,
              destinationAccountUuid: 'other-recipient',
              link: refilled,
            ),
            throwsStateError,
          );
        }
        final newTime = DateTime.utc(2026, 10, 8);
        final started = await store.markClaimStarted(
          address: original.address,
          destinationAccountUuid: 'recipient',
          link: refilled,
          priorTxids: ['existing-tx', 'old-tx'],
          updatedAt: newTime,
        );
        expect(started.status, PaymentLinkReceivedStatus.submitting);
        expect(started.claimTxids, isNull);
        expect(started.claimDestinationPool, isNull);
        expect(started.claimSubmittedAt, newTime);
        expect(started.claimRecoveryConfirmed, isFalse);
        expect(started.claimPriorTxids, ['existing-tx', 'old-tx']);
        expect(started.setupAccountUuid, setupAccountUuid);
        await expectLater(
          store.markClaimRecoveryConfirmed(oldReceipt),
          throwsStateError,
        );
        await store.markReadyToClaim(
          address: original.address,
          expected: oldReceipt,
        );
        final restarted = PaymentLinkReceivedStore(storage);
        final restored = (await restarted.load()).single;
        expect(restored.status, PaymentLinkReceivedStatus.submitting);
        expect(restored.amountZatoshi, BigInt.from(190000));
        expect(restored.claimLink!.amountZatoshi, BigInt.from(190000));
        expect(restored.claimLink!.statedAmountZatoshi, BigInt.from(100000));
        final receiving = await restarted.markReceiving(
          address: original.address,
          destinationAccountUuid: 'recipient',
          claimTxids: 'new-tx',
          expected: restored,
        );
        expect(receiving.claimTxids, 'new-tx');
        expect(receiving.claimSubmittedAt, newTime);
      },
    );
  }

  test(
    'amount-free pending card and setup handoff remain recoverable',
    () async {
      final link = VizorPaymentLink.parseForRedemption(zodlTestLink)
          .withResolvedMetadata(
            address: 'card-address',
            createdAt: DateTime.utc(2026, 10, 8),
            isCreatedAtProvisional: true,
          );
      final storage = _ReceivedStorage();
      await PaymentLinkReceivedStore(
        storage,
      ).saveReady(link, setupAccountUuid: 'recipient');
      expect(
        (await PaymentLinkReceivedStore(
          storage,
        ).load()).single.claimLink!.isZodl,
        isTrue,
      );
      await expectLater(
        PaymentLinkReceivedStore(storage).markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'recipient',
        ),
        throwsStateError,
      );
      final importStorage = _ImportStorage();
      final verified = link.withResolvedMetadata(
        amountZatoshi: BigInt.from(90000),
      );
      await GiftClaimImportStore(storage: importStorage).save(
        GiftClaimImportHandoff(
          link: verified,
          accountUuidsBeforeSetup: {'existing'},
        ),
      );
      final restored = (await GiftClaimImportStore(
        storage: importStorage,
      ).load())!;
      expect(restored.link.isZodl, isTrue);
      expect(restored.link.amountZatoshi, BigInt.from(90000));
      expect(restored.link.statedAmountZatoshi, isNull);
    },
  );
}

class _ReceivedStorage implements PaymentLinkReceivedStorage {
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

class _ImportStorage implements GiftClaimImportStorage {
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
