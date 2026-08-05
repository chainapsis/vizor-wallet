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

        final funded = await PaymentLinkFundingRecovery(store).fund(
          link: link,
          sourceAccountUuid: 'source-account',
          broadcast: () async {
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
        );

        expect(funded.state, PaymentLinkRecoveryState.funded);
        expect(funded.fundingTxids, 'funding-txid');
        final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
        expect(restartedRecords.single.state, PaymentLinkRecoveryState.funded);
        expect(restartedRecords.single.fundingTxids, 'funding-txid');
      },
    );

    test(
      'broadcast failure leaves the draft recoverable after restart',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final link = _link();

        await expectLater(
          PaymentLinkFundingRecovery(PaymentLinkRecoveryStore(storage)).fund(
            link: link,
            sourceAccountUuid: 'source-account',
            broadcast: () => throw StateError('broadcast failed'),
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
            broadcast: () async => 'funding-txid',
          ),
          throwsStateError,
        );

        final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
        expect(restartedRecords.single.state, PaymentLinkRecoveryState.draft);
        expect(restartedRecords.single.link.mnemonic, link.mnemonic);
      },
    );

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

    test('reclaim broadcast keeps the secret and records its txids', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();

      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markFunded(
        address: link.address,
        fundingTxids: 'funding-txid',
      );
      await store.markShared(address: link.address);

      final txids = await PaymentLinkReclaimRecovery(
        store,
      ).reclaim(address: link.address, broadcast: () async => 'reclaim-txid');

      expect(txids, 'reclaim-txid');
      final restarted = await PaymentLinkRecoveryStore(storage).load();
      expect(restarted.single.state, PaymentLinkRecoveryState.reclaiming);
      expect(restarted.single.reclaimTxids, 'reclaim-txid');
      expect(restarted.single.link.mnemonic, link.mnemonic);
    });

    test(
      'reclaim metadata failure leaves the shared secret recoverable',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage(failOnWrite: 4);
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();

        await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
        await store.markFunded(
          address: link.address,
          fundingTxids: 'funding-txid',
        );
        await store.markShared(address: link.address);

        await expectLater(
          PaymentLinkReclaimRecovery(store).reclaim(
            address: link.address,
            broadcast: () async => 'reclaim-txid',
          ),
          throwsStateError,
        );

        final restarted = await PaymentLinkRecoveryStore(storage).load();
        expect(restarted.single.state, PaymentLinkRecoveryState.shared);
        expect(restarted.single.reclaimTxids, isNull);
        expect(restarted.single.link.mnemonic, link.mnemonic);
      },
    );

    test('reclaiming records cannot regress to funded or shared', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();

      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markFunded(
        address: link.address,
        fundingTxids: 'funding-txid',
      );
      await store.markShared(address: link.address);
      await store.markReclaiming(
        address: link.address,
        reclaimTxids: 'reclaim-txid',
      );

      await expectLater(
        store.markFunded(
          address: link.address,
          fundingTxids: 'other-funding-txid',
        ),
        throwsStateError,
      );
      await expectLater(
        store.markShared(address: link.address),
        throwsStateError,
      );

      final restarted = await PaymentLinkRecoveryStore(storage).load();
      expect(restarted.single.state, PaymentLinkRecoveryState.reclaiming);
      expect(restarted.single.reclaimTxids, 'reclaim-txid');
      expect(restarted.single.link.mnemonic, link.mnemonic);
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
