import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';

void main() {
  group('PaymentLinkReceivedStore', () {
    test(
      'restores a claim secret and in-flight transaction after restart',
      () async {
        final storage = _FakePaymentLinkReceivedStorage();
        final link = _link();
        final store = PaymentLinkReceivedStore(storage);

        await store.saveReady(link);
        await store.markReceiving(
          address: link.address,
          destinationAccountUuid: 'receiver-account',
          claimTxids: 'claim-txid',
        );

        final restored = await PaymentLinkReceivedStore(storage).load();
        expect(restored, hasLength(1));
        expect(restored.single.status, PaymentLinkReceivedStatus.receiving);
        expect(restored.single.destinationAccountUuid, 'receiver-account');
        expect(restored.single.claimTxids, 'claim-txid');
        expect(restored.single.claimLink?.encode(), link.encode());
      },
    );

    test('clears the bearer secret only after the claim is mined', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);
      await store.markReceiving(
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      await store.markReceived(address: link.address);

      final restored = await PaymentLinkReceivedStore(storage).load();
      expect(restored.single.status, PaymentLinkReceivedStatus.received);
      expect(restored.single.claimLink, isNull);
      expect(restored.single.claimTxids, 'claim-txid');
      expect(restored.single.artworkId, 'ruby');
      expect(restored.single.amountZatoshi, link.amountZatoshi);
      expect(storage.value, isNot(contains(link.mnemonic)));
    });

    test('returns an expired claim to an actionable persisted state', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);
      await store.markReceiving(
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      await store.markReadyToClaim(address: link.address);

      final restored = await PaymentLinkReceivedStore(storage).load();
      expect(restored.single.status, PaymentLinkReceivedStatus.readyToClaim);
      expect(restored.single.destinationAccountUuid, isNull);
      expect(restored.single.claimTxids, isNull);
      expect(restored.single.claimLink?.encode(), link.encode());
    });

    test('never persists Receiving without a claim transaction id', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);

      await expectLater(
        store.markReceiving(
          address: link.address,
          destinationAccountUuid: 'receiver-account',
          claimTxids: '   ',
        ),
        throwsArgumentError,
      );
      final restored = await PaymentLinkReceivedStore(storage).load();
      expect(restored.single.status, PaymentLinkReceivedStatus.readyToClaim);
    });

    test(
      'does not reintroduce a secret for an already received card',
      () async {
        final storage = _FakePaymentLinkReceivedStorage();
        final link = _link();
        final store = PaymentLinkReceivedStore(storage);

        await store.saveReady(link);
        await store.markReceiving(
          address: link.address,
          destinationAccountUuid: 'receiver-account',
          claimTxids: 'claim-txid',
        );
        await store.markReceived(address: link.address);
        await store.saveReady(link);

        final restored = await PaymentLinkReceivedStore(storage).load();
        expect(restored.single.status, PaymentLinkReceivedStatus.received);
        expect(restored.single.claimLink, isNull);
      },
    );

    test('fails loud instead of hiding corrupted received-card data', () async {
      final storage =
          _FakePaymentLinkReceivedStorage()
            ..value = jsonEncode({
              'version': 1,
              'records': [
                {
                  'network': 'main',
                  'address': 'u1paymentlinkaddress',
                  'amountZatoshi': '100000',
                  'createdAt': DateTime.utc(2026, 8, 5).toIso8601String(),
                  'artworkId': 'ruby',
                  'status': 'unknown',
                  'claimLink': _link().encode(),
                  'destinationAccountUuid': null,
                  'claimTxids': null,
                  'updatedAt': DateTime.utc(2026, 8, 5).toIso8601String(),
                },
              ],
            });

      await expectLater(
        PaymentLinkReceivedStore(storage).load(),
        throwsA(isA<PaymentLinkReceivedStoreFormatException>()),
      );
    });
  });
}

VizorPaymentLink _link() {
  return VizorPaymentLink(
    network: 'main',
    address: 'u1paymentlinkaddress',
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 3_456_789,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 5, 12),
    presentation: const PaymentLinkPresentation(artworkId: 'ruby'),
  );
}

class _FakePaymentLinkReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async {
    value = nextValue;
  }
}
