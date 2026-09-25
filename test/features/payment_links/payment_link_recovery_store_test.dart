import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';

import '../../support/legacy_payment_link.dart';

void main() {
  test(
    'rejects an unreleased record without its saved claim fee reserve',
    () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      await store.saveDraft(
        link: _link(),
        sourceAccountUuid: 'source-account',
        claimFeeReserveZatoshi: BigInt.from(20000),
      );
      final payload = jsonDecode(storage.value!) as Map<String, dynamic>;
      (payload['records'] as List).single.remove('claimFeeReserveZatoshi');
      storage.value = jsonEncode(payload);
      await expectLater(
        store.load(),
        throwsA(isA<PaymentLinkRecoveryStoreFormatException>()),
      );
    },
  );

  group('PaymentLinkRecoveryStore', () {
    test(
      'records the funding time once and keeps it across later updates',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();
        await store.saveDraft(
          link: link,
          sourceAccountUuid: 'source-account',
          claimFeeReserveZatoshi: BigInt.from(20000),
        );
        final fundedAt = DateTime.utc(2026, 1, 1, 12);
        await store.markFunded(
          address: link.address,
          fundingTxids: 'funding-txid',
          updatedAt: fundedAt,
        );
        await store.markFunded(
          address: link.address,
          fundingTxids: 'funding-txid',
          updatedAt: fundedAt.add(const Duration(minutes: 1)),
        );
        await store.markShared(
          address: link.address,
          updatedAt: fundedAt.add(const Duration(hours: 1)),
        );
        await store.markShared(
          address: link.address,
          updatedAt: fundedAt.add(const Duration(days: 1)),
        );

        final record = (await PaymentLinkRecoveryStore(storage).load()).single;
        expect(record.fundedAt, fundedAt);
        expect(record.updatedAt, fundedAt.add(const Duration(days: 1)));
      },
    );

    test(
      'persists the secret before broadcast and records funding success',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();

        final funding = await PaymentLinkFundingRecovery(store).fund(
          link: link,
          sourceAccountUuid: 'source-account',
          claimFeeReserveZatoshi: BigInt.from(20000),
          currentChainHeight: () async => _submissionHeight,
          createTransaction: (_) async {
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
        expect(
          restartedRecords.single.claimFeeReserveZatoshi,
          BigInt.from(20000),
        );
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
            claimFeeReserveZatoshi: BigInt.from(10000),
            link: link,
            sourceAccountUuid: 'source-account',
            currentChainHeight: () async => _submissionHeight,
            createTransaction: (_) => throw StateError('transaction failed'),
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
          claimFeeReserveZatoshi: BigInt.from(10000),
          link: link,
          sourceAccountUuid: 'source-account',
          currentChainHeight: () async => _submissionHeight,
          createTransaction: (_) =>
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

      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: _link(),
        sourceAccountUuid: 'source-account',
      );

      expect(revisions, 1);
    });

    test('retries a transient funding metadata write failure', () async {
      final storage = _FakePaymentLinkRecoveryStorage(failOnWrites: {2});
      final link = _link();

      final funding =
          await PaymentLinkFundingRecovery(
            PaymentLinkRecoveryStore(storage),
          ).fund(
            claimFeeReserveZatoshi: BigInt.from(10000),
            link: link,
            sourceAccountUuid: 'source-account',
            currentChainHeight: () async => _submissionHeight,
            createTransaction: (_) async => 'funding-txid',
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
              claimFeeReserveZatoshi: BigInt.from(10000),
              link: link,
              sourceAccountUuid: 'source-account',
              currentChainHeight: () async => _submissionHeight,
              createTransaction: (_) async {
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

      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
      await store.markPrepared(
        address: link.address,
        fundingTxid: 'prepared-hardware-txid',
        expiryHeight: 3_456_829,
      );

      final restartedRecords = await PaymentLinkRecoveryStore(storage).load();
      expect(restartedRecords.single.state, PaymentLinkRecoveryState.draft);
      expect(restartedRecords.single.fundingTxids, 'prepared-hardware-txid');
      expect(restartedRecords.single.preparedExpiryHeight, 3_456_829);
      // Never handed to the network, so it does not block account deletion.
      expect(await store.countUnsharedFundedForAccount('source-account'), 0);
    });

    test('a prepared hardware draft records the broadcast boundary without '
        'becoming ambiguous', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
      await store.markPrepared(
        address: link.address,
        fundingTxid: 'prepared-hardware-txid',
        expiryHeight: 3_456_829,
      );

      await store.markSubmissionStarted(
        address: link.address,
        chainHeight: _submissionHeight,
      );

      final record = (await PaymentLinkRecoveryStore(storage).load()).single;
      expect(record.submittedAtHeight, _submissionHeight);
      expect(record.fundingTxids, 'prepared-hardware-txid');
      expect(record.isAmbiguousSubmission, isFalse);
      expect(await store.countUnsharedFundedForAccount('source-account'), 1);
      await expectLater(
        store.removeUnsubmittedPreparedDraft(address: link.address),
        throwsStateError,
      );
    });

    test('only a draft past its broadcast boundary blocks deletion', () {
      final link = _link();
      PaymentLinkRecoveryRecord record(
        PaymentLinkRecoveryState state, {
        String sourceAccountUuid = 'source-account',
        String? fundingTxids,
        int? preparedExpiryHeight,
        int? submittedAtHeight,
      }) => PaymentLinkRecoveryRecord(
        link: link,
        sourceAccountUuid: sourceAccountUuid,
        state: state,
        updatedAt: DateTime.utc(2026, 9, 1),
        fundingTxids: fundingTxids,
        preparedExpiryHeight: preparedExpiryHeight,
        submittedAtHeight: submittedAtHeight,
        claimFeeReserveZatoshi: BigInt.from(10000),
      );
      const draft = PaymentLinkRecoveryState.draft;
      final cases = <String, (PaymentLinkRecoveryRecord, bool)>{
        'inert draft': (record(draft), false),
        'prepared only': (
          record(draft, fundingTxids: 'txid', preparedExpiryHeight: 120),
          false,
        ),
        'prepared, broadcast started': (
          record(
            draft,
            fundingTxids: 'txid',
            preparedExpiryHeight: 120,
            submittedAtHeight: 100,
          ),
          true,
        ),
        'ambiguous submission': (record(draft, submittedAtHeight: 0), true),
        'software txid recorded': (
          record(draft, fundingTxids: 'txid', submittedAtHeight: 100),
          true,
        ),
        'funded': (
          record(PaymentLinkRecoveryState.funded, fundingTxids: 'txid'),
          true,
        ),
        'shared': (
          record(PaymentLinkRecoveryState.shared, fundingTxids: 'txid'),
          false,
        ),
        'other account': (
          record(
            PaymentLinkRecoveryState.funded,
            sourceAccountUuid: 'other-account',
            fundingTxids: 'txid',
          ),
          false,
        ),
      };
      for (final MapEntry(key: name, value: (record, blocks))
          in cases.entries) {
        expect(
          countUnsharedFundedPaymentLinks([
            record,
          ], sourceAccountUuid: 'source-account'),
          blocks ? 1 : 0,
          reason: name,
        );
      }
    });

    test(
      'drops only the deleted account drafts that never reached the network',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final store = PaymentLinkRecoveryStore(storage);
        VizorPaymentLink linkAt(String address) => VizorPaymentLink(
          network: 'main',
          address: address,
          amountZatoshi: BigInt.from(100000),
          mnemonic: _link().mnemonic,
          birthdayHeight: 3_456_789,
          label: 'Payment link',
          createdAt: DateTime.utc(2026, 8, 5, 12),
        );
        Future<void> save(String address, String account) => store.saveDraft(
          claimFeeReserveZatoshi: BigInt.from(10000),
          link: linkAt(address),
          sourceAccountUuid: account,
        );
        await save('u1inert', 'source-account');
        await save('u1prepared', 'source-account');
        await store.markPrepared(
          address: 'u1prepared',
          fundingTxid: 'prepared-txid',
          expiryHeight: 120,
        );
        await save('u1submitted', 'source-account');
        await store.markPrepared(
          address: 'u1submitted',
          fundingTxid: 'submitted-txid',
          expiryHeight: 120,
        );
        await store.markSubmissionStarted(
          address: 'u1submitted',
          chainHeight: 100,
        );
        await save('u1funded', 'source-account');
        await store.markFunded(address: 'u1funded', fundingTxids: 'funded');
        await save('u1other', 'other-account');

        expect(
          await store.removeUnsubmittedDraftsForAccount('source-account'),
          2,
        );

        expect(
          [for (final record in await store.load()) record.link.address],
          ['u1submitted', 'u1funded', 'u1other'],
        );
      },
    );

    test('removes a definitely canceled hardware draft', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
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
        // Writes: 1 saveDraft, 2 markPrepared, 3 the broadcast marker, 4+5 the
        // two markFunded attempts.
        final storage = _FakePaymentLinkRecoveryStorage(failOnWrites: {4, 5});
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();
        await store.saveDraft(
          claimFeeReserveZatoshi: BigInt.from(10000),
          link: link,
          sourceAccountUuid: 'source-account',
        );
        await store.markPrepared(
          address: link.address,
          fundingTxid: 'prepared-hardware-txid',
          expiryHeight: 3_456_829,
        );
        await store.markSubmissionStarted(
          address: link.address,
          chainHeight: _submissionHeight,
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
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
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
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
        currentChainHeight: () async => _submissionHeight,
        createTransaction: (_) async =>
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

      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: first,
        sourceAccountUuid: 'source-account',
      );
      await store.markFunded(
        address: first.address,
        fundingTxids: 'funding-txid',
      );
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: second,
        sourceAccountUuid: 'source-account',
      );
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
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
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
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
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

    test('ignores record fields outside the v1 schema', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': link.toUri().toString(),
              'address': link.address,
              'createdAt': link.createdAt.toIso8601String(),
              'sourceAccountUuid': 'source-account',
              'claimFeeReserveZatoshi': '10000',
              'state': 'shared',
              'fundingTxids': 'funding-txid',
              'archivedAt': '2026-08-05T00:00:00.000Z',
              'updatedAt': DateTime.utc(2026, 8, 5).toIso8601String(),
            },
          ],
        });

      final record = (await PaymentLinkRecoveryStore(storage).load()).single;

      expect(record.state, PaymentLinkRecoveryState.shared);
      expect(record.fundingTxids, 'funding-txid');
      expect(record.link.mnemonic, link.mnemonic);
    });

    test('loads local metadata from a legacy v1 link', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': legacyPaymentLinkUri(link).toString(),
              'sourceAccountUuid': 'source-account',
              'claimFeeReserveZatoshi': '10000',
              'state': 'shared',
              'fundingTxids': 'funding-txid',
              'updatedAt': DateTime.utc(2026, 8, 5).toIso8601String(),
            },
          ],
        });

      final record = (await PaymentLinkRecoveryStore(storage).load()).single;

      expect(record.link.address, link.address);
      expect(record.link.createdAt, link.createdAt);
    });

    test('rejects recovery states outside the v1 schema', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': link.toUri().toString(),
              'address': link.address,
              'createdAt': link.createdAt.toIso8601String(),
              'sourceAccountUuid': 'source-account',
              'claimFeeReserveZatoshi': '10000',
              'state': 'unsupported',
              'fundingTxids': 'funding-txid',
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
              'address': link.address,
              'createdAt': link.createdAt.toIso8601String(),
              'sourceAccountUuid': 'source-account',
              'claimFeeReserveZatoshi': '10000',
              'state': 'draft',
              'fundingTxids': null,
              'preparedExpiryHeight': 120,
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
              'address': link.address,
              'createdAt': link.createdAt.toIso8601String(),
              'sourceAccountUuid': 'source-account',
              'claimFeeReserveZatoshi': '10000',
              'state': 'draft',
              'fundingTxids': 'submitted-software-txid',
              'preparedExpiryHeight': null,
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
              claimFeeReserveZatoshi: BigInt.from(10000),
              link: link,
              sourceAccountUuid: 'source-account',
              currentChainHeight: () async => _submissionHeight,
              createTransaction: (_) async => 'funding-txid',
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
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );

      await store.removeUnsubmittedDraft(address: link.address);

      expect(await store.load(), isEmpty);
    });

    test('a submitted software draft cannot be removed as inert', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
      await store.markSubmitted(
        address: link.address,
        fundingTxids: 'funding-txid',
      );

      await expectLater(
        store.removeUnsubmittedDraft(address: link.address),
        throwsStateError,
      );
    });

    test('records the chain height a software broadcast started at', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );

      await store.markSubmissionStarted(
        address: link.address,
        chainHeight: _submissionHeight,
      );
      // A retry must not move the marker forward: the earlier height is the
      // one the transaction could have been mined at.
      await store.markSubmissionStarted(
        address: link.address,
        chainHeight: _submissionHeight + 10,
      );

      final record = (await PaymentLinkRecoveryStore(storage).load()).single;
      expect(record.state, PaymentLinkRecoveryState.draft);
      expect(record.submittedAtHeight, _submissionHeight);
      expect(record.fundingTxids, isNull);
      expect(record.isAmbiguousSubmission, isTrue);
    });

    test(
      'a recorded broadcast txid fills in a missing submission marker',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();
        await store.saveDraft(
          claimFeeReserveZatoshi: BigInt.from(10000),
          link: link,
          sourceAccountUuid: 'source-account',
        );
        await store.markSubmitted(
          address: link.address,
          fundingTxids: 'funding-txid',
        );
        // An existing marker is the earlier, safer height and is kept.
        await store.markSubmissionStarted(
          address: link.address,
          chainHeight: _submissionHeight,
        );

        final record = (await PaymentLinkRecoveryStore(storage).load()).single;
        expect(record.submittedAtHeight, 0);
        expect(record.fundingTxids, 'funding-txid');
        expect(record.isAmbiguousSubmission, isFalse);
      },
    );

    test('marks a Ledger broadcast only when its draft still exists', () async {
      final store = PaymentLinkRecoveryStore(_FakePaymentLinkRecoveryStorage());

      expect(
        await store.markSubmissionStartedIfPresent(
          address: _link().address,
          chainHeight: _submissionHeight,
        ),
        isNull,
      );
      await expectLater(
        store.markSubmissionStarted(
          address: _link().address,
          chainHeight: _submissionHeight,
        ),
        throwsStateError,
      );
    });

    test('an ambiguous submission cannot be removed as inert', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      await store.saveDraft(
        claimFeeReserveZatoshi: BigInt.from(10000),
        link: link,
        sourceAccountUuid: 'source-account',
      );
      await store.markSubmissionStarted(
        address: link.address,
        chainHeight: _submissionHeight,
      );

      await expectLater(
        store.removeUnsubmittedDraft(address: link.address),
        throwsStateError,
      );
      // The account-deletion guard must see it too: it may hold funds.
      expect(await store.countUnsharedFundedForAccount('source-account'), 1);
    });

    test(
      'automatic draft removal preserves an ambiguous submission and its secret',
      () async {
        final storage = _FakePaymentLinkRecoveryStorage();
        final store = PaymentLinkRecoveryStore(storage);
        final link = _link();
        await store.saveDraft(
          link: link,
          sourceAccountUuid: 'source-account',
          claimFeeReserveZatoshi: BigInt.from(10000),
        );
        await store.markSubmissionStarted(
          address: link.address,
          chainHeight: 100,
        );
        await expectLater(
          store.removeUnbroadcastDraft(address: link.address),
          throwsStateError,
        );
        expect(await store.countUnsharedFundedForAccount('source-account'), 1);
        expect(
          (await PaymentLinkRecoveryStore(storage).load()).single.link.toUri(),
          link.toUri(),
        );
      },
    );

    test('a lost broadcast result leaves an ambiguous submission', () async {
      final storage = _FakePaymentLinkRecoveryStorage();
      final store = PaymentLinkRecoveryStore(storage);
      final link = _link();
      final failure = StateError('broadcast result unavailable');

      await expectLater(
        PaymentLinkFundingRecovery(store).fund<String>(
          claimFeeReserveZatoshi: BigInt.from(10000),
          link: link,
          sourceAccountUuid: 'source-account',
          currentChainHeight: () async => _submissionHeight,
          // What the send path does: mark the submission, cross the broadcast
          // boundary, then lose the result.
          createTransaction: (markSubmissionStarted) async {
            await markSubmissionStarted();
            throw failure;
          },
          fundingTxids: (txid) => txid,
        ),
        throwsA(same(failure)),
      );

      final record = (await PaymentLinkRecoveryStore(storage).load()).single;
      expect(record.state, PaymentLinkRecoveryState.draft);
      expect(record.fundingTxids, isNull);
      expect(record.submittedAtHeight, _submissionHeight);
      expect(record.isAmbiguousSubmission, isTrue);
      expect(record.link.mnemonic, link.mnemonic);
    });

    test('reads a submission height back from stored records', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': link.toUri().toString(),
              'address': link.address,
              'createdAt': link.createdAt.toIso8601String(),
              'sourceAccountUuid': 'source-account',
              'claimFeeReserveZatoshi': '10000',
              'state': 'draft',
              'fundingTxids': null,
              'preparedExpiryHeight': null,
              'submittedAtHeight': _submissionHeight,
              'updatedAt': DateTime.utc(2026, 8, 5).toIso8601String(),
            },
          ],
        });

      final record = (await PaymentLinkRecoveryStore(storage).load()).single;

      expect(record.submittedAtHeight, _submissionHeight);
      expect(record.isAmbiguousSubmission, isTrue);
      expect(
        countUnsharedFundedPaymentLinks([
          record,
        ], sourceAccountUuid: 'source-account'),
        1,
      );
    });

    test('rejects a negative submission height', () async {
      final link = _link();
      final storage = _FakePaymentLinkRecoveryStorage()
        ..value = jsonEncode({
          'version': 1,
          'records': [
            {
              'link': link.toUri().toString(),
              'sourceAccountUuid': 'source-account',
              'claimFeeReserveZatoshi': '10000',
              'state': 'draft',
              'submittedAtHeight': -1,
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

const _submissionHeight = 3_456_800;

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
