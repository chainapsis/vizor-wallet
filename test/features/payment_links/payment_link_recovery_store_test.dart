import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';

void main() {
  group('PaymentLinkRecoveryStore', () {
    test(
      'persists the secret before broadcast and records funding success',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();

        final fundingTxid = await PaymentLinkFundingRecovery(store).fund(
          link: link,
          sourceAccountUuid: 'source-account',
          createTransaction: () async {
            final restartedRecords = await PaymentLinkRecoveryStore(
              storage,
            ).load();
            expect(restartedRecords, hasLength(1));
            expect(
              restartedRecords.single.state,
              PaymentLinkRecoveryState.draft,
            );
            expect(restartedRecords.single.link.mnemonic, link.mnemonic);
            return 'funding-txid';
          },
          fundingTxids: (txid) => txid,
        );

        expect(fundingTxid, 'funding-txid');
        final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
        expect(restartedRecords.single.state, PaymentLinkRecoveryState.funded);
        expect(restartedRecords.single.fundingTxids, 'funding-txid');
      },
    );

    test(
      'transaction failure leaves the draft recoverable after restart',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final link = _link();

        await expectLater(
          PaymentLinkFundingRecovery(
            PaymentLinkRecoveryStore(storage),
          ).fund<String>(
            link: link,
            sourceAccountUuid: 'source-account',
            createTransaction: () => throw StateError('transaction failed'),
            fundingTxids: (txid) => txid,
          ),
          throwsStateError,
        );

        final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
        expect(restartedRecords, hasLength(1));
        expect(restartedRecords.single.state, PaymentLinkRecoveryState.draft);
        expect(restartedRecords.single.link.encode(), link.encode());
      },
    );

    test(
      'funding metadata failure still preserves the earlier draft',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage(failOnWrite: 2);
        final link = _link();

        await expectLater(
          PaymentLinkFundingRecovery(PaymentLinkRecoveryStore(storage)).fund(
            link: link,
            sourceAccountUuid: 'source-account',
            createTransaction: () async => 'funding-txid',
            fundingTxids: (txid) => txid,
          ),
          throwsStateError,
        );

        final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
        expect(restartedRecords.single.state, PaymentLinkRecoveryState.draft);
        expect(restartedRecords.single.link.mnemonic, link.mnemonic);
      },
    );

    test('records pending transaction ids before status handling', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();

      final result = await PaymentLinkFundingRecovery(store).fund(
        link: link,
        sourceAccountUuid: 'source-account',
        createTransaction: () async =>
            (txids: 'pending-funding-txid', status: 'pending_broadcast'),
        fundingTxids: (result) => result.txids,
      );

      expect(result.status, 'pending_broadcast');
      final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
      expect(restartedRecords.single.state, PaymentLinkRecoveryState.funded);
      expect(restartedRecords.single.fundingTxids, 'pending-funding-txid');
    });

    test('archiving a shared record keeps its recovery secret', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();

      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markFunded(
        address: link.address,
        fundingTxids: 'funding-txid',
      );
      await store.markShared(address: link.address);
      await store.setArchived(address: link.address, archived: true);

      final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
      expect(restartedRecords.single.state, PaymentLinkRecoveryState.shared);
      expect(restartedRecords.single.fundingTxids, 'funding-txid');
      expect(restartedRecords.single.isArchived, isTrue);
      expect(restartedRecords.single.archivedAt, isNotNull);
      expect(restartedRecords.single.link.mnemonic, link.mnemonic);

      await PaymentLinkRecoveryStore(
        storage,
      ).setArchived(address: link.address, archived: false);
      final restored = await PaymentLinkRecoveryStore(storage).load();
      expect(restored.single.isArchived, isFalse);
      expect(restored.single.archivedAt, isNull);
      expect(restored.single.link.mnemonic, link.mnemonic);
    });

    test('rejects recovery states outside the v1 schema', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': link.encode(),
              'sourceAccountUuid': 'source-account',
              'state': 'unsupported',
              'fundingTxids': 'funding-txid',
              'archivedAt': null,
              'updatedAt': DateTime.utc(2026, 8, 5).toIso8601String(),
            },
          ],
        });

      await expectLater(
        PaymentLinkRecoveryStore(storage).load(),
        throwsA(isA<PaymentLinkRecoveryStoreFormatException>()),
      );
    });

    test('fails loud instead of hiding corrupted recovery data', () async {
      final storage = _FakePaymentLinkRecoveryStorage()..value = '{not-json';

      await expectLater(
        PaymentLinkRecoveryStore(storage).load(),
        throwsA(isA<PaymentLinkRecoveryStoreFormatException>()),
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
  );
}

class _FakePaymentLinkRecoveryStorage implements PaymentLinkRecoveryStorage {
  _FakePaymentLinkRecoveryStorage({this.failOnWrite});

  final int? failOnWrite;
  String? value;
  int _writeCount = 0;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async {
    _writeCount += 1;
    if (_writeCount == failOnWrite) {
      throw StateError('storage write failed');
    }
    value = nextValue;
  }
}
