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

        final funding = await PaymentLinkFundingRecovery(store).fund(
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

        expect(funding.transaction, 'funding-txid');
        expect(funding.recoveryError, isNull);
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
        expect(restartedRecords.single.link.toUri(), link.toUri());
      },
    );

    test('definitive pre-submission failure removes its inert draft', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final link = _link();
      final failure = StateError('insufficient balance');

      await expectLater(
        PaymentLinkFundingRecovery(
          PaymentLinkRecoveryStore(storage),
        ).fund<String>(
          link: link,
          sourceAccountUuid: 'source-account',
          createTransaction: () =>
              throw PaymentLinkFundingNotSubmittedException(
                failure,
                StackTrace.current,
              ),
          fundingTxids: (txid) => txid,
        ),
        throwsA(same(failure)),
      );

      expect(await PaymentLinkRecoveryStore(storage).load(), isEmpty);
    });

    test('notifies listeners after a lifecycle write', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      var revisions = 0;
      final store = PaymentLinkRecoveryStore(
        storage,
        onRecordsChanged: () => revisions += 1,
      );

      await store.saveDraft(link: _link(), sourceAccountUuid: 'source-account');

      expect(revisions, 1);
    });

    test('retries a transient funding metadata write failure', () async {
      final storage = _FakePaymentLinkRecoveryStorage(failOnWrites: {2});
      final link = _link();

      final funding =
          await PaymentLinkFundingRecovery(
            PaymentLinkRecoveryStore(storage),
          ).fund(
            link: link,
            sourceAccountUuid: 'source-account',
            createTransaction: () async => 'funding-txid',
            fundingTxids: (txid) => txid,
          );

      expect(funding.transaction, 'funding-txid');
      expect(funding.recoveryError, isNull);
      final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
      expect(restartedRecords.single.state, PaymentLinkRecoveryState.funded);
      expect(restartedRecords.single.fundingTxids, 'funding-txid');
    });

    test(
      'returns the broadcast result when funding metadata cannot be updated',
      () async {
        // Writes: 1 saveDraft, 2 markSubmitted, 3+4 the two markFunded
        // attempts. A storage outage spanning all of them is the one case that
        // still loses the transaction id.
        final storage = _FakePaymentLinkRecoveryStorage(
          failOnWrites: {2, 3, 4},
        );
        final link = _link();
        var transactionCount = 0;

        final funding =
            await PaymentLinkFundingRecovery(
              PaymentLinkRecoveryStore(storage),
            ).fund(
              link: link,
              sourceAccountUuid: 'source-account',
              createTransaction: () async {
                transactionCount += 1;
                return 'funding-txid';
              },
              fundingTxids: (txid) => txid,
            );

        expect(funding.transaction, 'funding-txid');
        expect(funding.recoveryError, isA<StateError>());
        expect(funding.recoveryStackTrace, isNotNull);
        expect(transactionCount, 1);
        final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
        expect(restartedRecords.single.state, PaymentLinkRecoveryState.draft);
        expect(restartedRecords.single.fundingTxids, isNull);
        expect(restartedRecords.single.link.mnemonic, link.mnemonic);
      },
    );

    test('persists the prepared hardware txid before broadcast', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();

      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markPrepared(
        address: link.address,
        fundingTxid: 'prepared-hardware-txid',
        expiryHeight: 3_456_829,
      );

      final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
      expect(restartedRecords.single.state, PaymentLinkRecoveryState.draft);
      expect(restartedRecords.single.fundingTxids, 'prepared-hardware-txid');
      expect(restartedRecords.single.preparedExpiryHeight, 3_456_829);
      expect(await store.countUnsharedFundedForAccount('source-account'), 1);
    });

    test('removes a definitely canceled hardware draft', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markPrepared(
        address: link.address,
        fundingTxid: 'prepared-hardware-txid',
        expiryHeight: 3_456_829,
      );

      await store.removeUnbroadcastDraft(address: link.address);

      expect(await store.load(), isEmpty);
      expect(await store.countUnsharedFundedForAccount('source-account'), 0);
    });

    test(
      'keeps the prepared txid when post-broadcast metadata retries fail',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage(failOnWrites: {3, 4});
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();
        await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
        await store.markPrepared(
          address: link.address,
          fundingTxid: 'prepared-hardware-txid',
          expiryHeight: 3_456_829,
        );

        final funding = await PaymentLinkFundingRecovery(store).complete(
          transaction: 'accepted-broadcast',
          address: link.address,
          fundingTxids: (_) => 'prepared-hardware-txid',
        );

        expect(funding.transaction, 'accepted-broadcast');
        expect(funding.fundingMetadataSaved, isFalse);
        final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
        expect(restartedRecords.single.state, PaymentLinkRecoveryState.draft);
        expect(restartedRecords.single.fundingTxids, 'prepared-hardware-txid');
        expect(restartedRecords.single.preparedExpiryHeight, 3_456_829);
        expect(await store.countUnsharedFundedForAccount('source-account'), 1);
      },
    );

    test('rejects a broadcast result for a different prepared txid', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markPrepared(
        address: link.address,
        fundingTxid: 'prepared-hardware-txid',
        expiryHeight: 3_456_829,
      );

      await expectLater(
        store.markFunded(
          address: link.address,
          fundingTxids: 'different-hardware-txid',
        ),
        throwsStateError,
      );
    });

    test('records pending transaction ids before status handling', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();

      final funding = await PaymentLinkFundingRecovery(store).fund(
        link: link,
        sourceAccountUuid: 'source-account',
        createTransaction: () async =>
            (txids: 'pending-funding-txid', status: 'pending_broadcast'),
        fundingTxids: (result) => result.txids,
      );

      expect(funding.transaction.status, 'pending_broadcast');
      expect(funding.recoveryError, isNull);
      final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
      expect(restartedRecords.single.state, PaymentLinkRecoveryState.funded);
      expect(restartedRecords.single.fundingTxids, 'pending-funding-txid');
    });

    test('counts only funded links that have not been shared', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final first = _link();
      final second = VizorPaymentLink(
        network: first.network,
        address: 'u1secondpaymentlinkaddress',
        amountZatoshi: first.amountZatoshi,
        mnemonic: first.mnemonic,
        birthdayHeight: first.birthdayHeight,
        label: first.label,
        createdAt: first.createdAt,
      );

      await store.saveDraft(link: first, sourceAccountUuid: 'source-account');
      await store.markFunded(
        address: first.address,
        fundingTxids: 'funding-txid',
      );
      await store.saveDraft(link: second, sourceAccountUuid: 'source-account');
      await store.markFunded(
        address: second.address,
        fundingTxids: 'second-funding-txid',
      );
      await store.markShared(address: second.address);

      expect(await store.countUnsharedFundedForAccount('source-account'), 1);
      expect(await store.countUnsharedFundedForAccount('other-account'), 0);
    });

    test('removes only matching unshared funding after it expires', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markFunded(
        address: link.address,
        fundingTxids: 'funding-txid',
      );

      await expectLater(
        store.removeUnsharedExpiredFunding(
          address: link.address,
          fundingTxids: 'different-txid',
        ),
        throwsStateError,
      );
      expect(await store.load(), hasLength(1));

      await store.removeUnsharedExpiredFunding(
        address: link.address,
        fundingTxids: 'funding-txid',
      );
      expect(await store.load(), isEmpty);
    });

    test('never removes a shared funding recovery', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markFunded(
        address: link.address,
        fundingTxids: 'funding-txid',
      );
      await store.markShared(address: link.address);

      await expectLater(
        store.removeUnsharedExpiredFunding(
          address: link.address,
          fundingTxids: 'funding-txid',
        ),
        throwsStateError,
      );

      expect(
        (await store.load()).single.state,
        PaymentLinkRecoveryState.shared,
      );
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
              'link': link.toUri().toString(),
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

    test('rejects an expiry height with no funding transaction', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': link.toUri().toString(),
              'sourceAccountUuid': 'source-account',
              'state': 'draft',
              'fundingTxids': null,
              'preparedExpiryHeight': 120,
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

    test('reads a software draft that carries only its funding txid', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': link.toUri().toString(),
              'sourceAccountUuid': 'source-account',
              'state': 'draft',
              'fundingTxids': 'submitted-software-txid',
              'preparedExpiryHeight': null,
              'archivedAt': null,
              'updatedAt': DateTime.utc(2026, 8, 5).toIso8601String(),
            },
          ],
        });

      final record = (await PaymentLinkRecoveryStore(storage).load()).single;

      expect(record.state, PaymentLinkRecoveryState.draft);
      expect(record.fundingTxids, 'submitted-software-txid');
      expect(record.preparedExpiryHeight, isNull);
    });

    test(
      'a software draft whose markFunded never landed keeps its funding txid',
      () async {
        // Writes: 1 saveDraft, 2 markSubmitted, 3+4 the two markFunded
        // attempts. Only the promotion fails, so the broadcast transaction has
        // to survive on the draft.
        final storage = _FakePaymentLinkRecoveryStorage(
          failOnWrites: const {3, 4},
        );
        final link = _link();

        final funding =
            await PaymentLinkFundingRecovery(
              PaymentLinkRecoveryStore(storage),
            ).fund(
              link: link,
              sourceAccountUuid: 'source-account',
              createTransaction: () async => 'funding-txid',
              fundingTxids: (txid) => txid,
            );

        expect(funding.fundingMetadataSaved, isFalse);

        final restarted = PaymentLinkRecoveryStore(storage);
        final record = (await restarted.load()).single;
        expect(record.state, PaymentLinkRecoveryState.draft);
        expect(record.fundingTxids, 'funding-txid');
        expect(record.preparedExpiryHeight, isNull);
        // The account-deletion guard must still see the funded ZEC.
        expect(
          await restarted.countUnsharedFundedForAccount('source-account'),
          1,
        );
      },
    );

    test('an inert software draft is still removable', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');

      await store.removeUnsubmittedDraft(address: link.address);

      expect(await store.load(), isEmpty);
    });

    test('a submitted software draft cannot be removed as inert', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(link: link, sourceAccountUuid: 'source-account');
      await store.markSubmitted(
        address: link.address,
        fundingTxids: 'funding-txid',
      );

      await expectLater(
        store.removeUnsubmittedDraft(address: link.address),
        throwsStateError,
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
  _FakePaymentLinkRecoveryStorage({this.failOnWrites = const {}});

  final Set<int> failOnWrites;
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
    if (failOnWrites.contains(_writeCount)) {
      throw StateError('storage write failed');
    }
    value = nextValue;
  }
}
