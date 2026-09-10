import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_lifecycle_revision.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';

void main() {
  for (final status in PaymentLinkReceivedStatus.values) {
    for (final explicitNull in [false, true]) {
      test(
        'legacy $status with ${explicitNull ? 'null' : 'missing'} fields survives writes',
        () async {
          final storage = _FakePaymentLinkReceivedStorage();
          final store = PaymentLinkReceivedStore(storage);
          final link = _link();
          await store.saveReady(link);
          if (status != PaymentLinkReceivedStatus.readyToClaim) {
            await store.markClaimStarted(
              address: link.address,
              destinationAccountUuid: 'receiver',
            );
          }
          if (status == PaymentLinkReceivedStatus.receiving ||
              status == PaymentLinkReceivedStatus.received) {
            await store.markReceiving(
              address: link.address,
              destinationAccountUuid: 'receiver',
              claimTxids: 'claim',
            );
          }
          if (status == PaymentLinkReceivedStatus.received) {
            await store.markReceived(address: link.address);
          }
          final payload = jsonDecode(storage.value!) as Map<String, dynamic>;
          final row =
              (payload['records'] as List).single as Map<String, dynamic>;
          for (final field in ['availability', 'archived', 'claimPriorTxids']) {
            if (explicitNull) {
              row[field] = null;
            } else {
              row.remove(field);
            }
          }
          storage.value = jsonEncode(payload);
          final restored = (await store.load()).single;
          expect(restored.status, status);
          expect(restored.archived, isFalse);
          expect(restored.claimPriorTxids, isNull);
          expect(restored.availability, switch (status) {
            PaymentLinkReceivedStatus.readyToClaim =>
              PaymentLinkAvailability.unchecked,
            PaymentLinkReceivedStatus.submitting =>
              PaymentLinkAvailability.checking,
            _ => PaymentLinkAvailability.available,
          });
          expect(restored.copyWith(archived: false).claimPriorTxids, isNull);
          await store.saveReady(
            link,
          ); // Must not manufacture an empty baseline.
          await store.setArchived(link.address, false);
          final reopened = (await PaymentLinkReceivedStore(
            storage,
          ).load()).single;
          expect(reopened.claimPriorTxids, isNull);
          expect(reopened.status, status);
          expect(reopened.claimTxids, restored.claimTxids);
          expect(reopened.claimSubmittedAt, restored.claimSubmittedAt);
          expect(reopened.claimLink!.toUri(), link.toUri());
          expect(
            await store.countReceivingForAccount('receiver'),
            restored.isClaimInFlight ? 1 : 0,
          );
        },
      );
    }
  }

  test(
    'mixed old and new records preserve new fields and capture a fresh baseline',
    () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final store = PaymentLinkReceivedStore(storage);
      final oldLink = _link();
      final newLink = _link(address: 'u1newcard');
      await store.saveReady(oldLink);
      await store.saveReady(newLink);
      await store.setAvailability(
        newLink.address,
        PaymentLinkAvailability.failed,
      );
      await store.setArchived(newLink.address, true);
      final payload = jsonDecode(storage.value!) as Map<String, dynamic>;
      final old = (payload['records'] as List).first as Map<String, dynamic>;
      for (final field in ['availability', 'archived', 'claimPriorTxids']) {
        old.remove(field);
      }
      storage.value = jsonEncode(payload);
      final records = await store.load();
      expect(records.first.claimPriorTxids, isNull);
      expect(records.last.claimPriorTxids, isEmpty);
      expect(records.last.archived, isTrue);
      expect(records.last.availability, PaymentLinkAvailability.failed);
      await store.markClaimStarted(
        address: oldLink.address,
        destinationAccountUuid: 'receiver',
        priorTxids: ['previous'],
      );
      expect((await store.find(oldLink.address))!.claimPriorTxids, [
        'previous',
      ]);
      expect((await store.find(newLink.address))!.archived, isTrue);
    },
  );

  for (final invalid in <(String, Object)>[
    ('availability', 1),
    ('availability', 'unknown'),
    ('archived', 'false'),
    ('claimPriorTxids', 'not-a-list'),
    ('claimPriorTxids', [1]),
  ]) {
    test(
      'optional ${invalid.$1} still rejects malformed ${invalid.$2}',
      () async {
        final storage = _FakePaymentLinkReceivedStorage();
        final store = PaymentLinkReceivedStore(storage);
        await store.saveReady(_link());
        final payload = jsonDecode(storage.value!) as Map<String, dynamic>;
        (payload['records'] as List).single[invalid.$1] = invalid.$2;
        storage.value = jsonEncode(payload);
        final original = storage.value;
        await expectLater(
          store.load(),
          throwsA(isA<PaymentLinkReceivedStoreFormatException>()),
        );
        expect(storage.value, original);
      },
    );
  }

  test('an old outcome cannot settle a newer submission', () async {
    final store = PaymentLinkReceivedStore(_FakePaymentLinkReceivedStorage());
    final link = _link();
    await store.saveReady(link);
    final old = await store.markClaimStarted(
      address: link.address,
      destinationAccountUuid: 'a',
    );
    await store.markReadyToClaim(address: link.address, expected: old);
    await store.markClaimStarted(
      address: link.address,
      destinationAccountUuid: 'b',
    );
    await store.markReadyToClaim(
      address: link.address,
      expected: old,
      availability: PaymentLinkAvailability.claimedElsewhere,
    );
    final current = (await store.load()).single;
    expect(current.status, PaymentLinkReceivedStatus.submitting);
    expect(current.destinationAccountUuid, 'b');
    expect(await store.countReceivingForAccount('b'), 1);
  });

  test(
    'archive preserves the secret and outcome across restart and restore',
    () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final store = PaymentLinkReceivedStore(storage);
      final link = _link();
      await store.saveReady(link);
      await store.setAvailability(
        link.address,
        PaymentLinkAvailability.claimedElsewhere,
      );
      await store.setArchived(link.address, true);
      final reopened = PaymentLinkReceivedStore(storage);
      var record = (await reopened.load()).single;
      expect(record.archived, isTrue);
      expect(record.availability, PaymentLinkAvailability.claimedElsewhere);
      expect(record.claimLink!.toUri(), link.toUri());
      await reopened.setArchived(link.address, false);
      record = (await reopened.load()).single;
      expect(record.archived, isFalse);
      expect(record.claimLink!.toUri(), link.toUri());
    },
  );

  test('late empty preview cannot settle or hide an in-flight claim', () async {
    final store = PaymentLinkReceivedStore(_FakePaymentLinkReceivedStorage());
    final link = _link();
    await store.saveReady(link);
    await store.markClaimStarted(
      address: link.address,
      destinationAccountUuid: 'receiver',
    );
    await store.setAvailability(
      link.address,
      PaymentLinkAvailability.noBalance,
    );
    await expectLater(store.setArchived(link.address, true), throwsStateError);
    expect(await store.countReceivingForAccount('receiver'), 1);
    expect(
      (await store.load()).single.availability,
      PaymentLinkAvailability.checking,
    );
    await store.markReadyToClaim(address: link.address);
    await store.setAvailability(
      link.address,
      PaymentLinkAvailability.claimedElsewhere,
    );
    expect(await store.countReceivingForAccount('receiver'), 0);
    expect((await store.load()).single.claimLink!.toUri(), link.toUri());
  });

  test(
    'retains fiat after submission, completion, and restart without bearer data',
    () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final store = PaymentLinkReceivedStore(storage);
      final link = _link();
      await store.saveReady(link);
      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver',
      );
      await store.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'receiver',
        claimTxids: 'claim-tx',
      );
      await store.markReceived(address: link.address);
      await store.clearConfirmedClaimSecret(address: link.address);
      final record = (await PaymentLinkReceivedStore(storage).load()).single;
      expect(record.claimLink, isNull);
      expect(record.fiatSnapshot!.amount, 142.23);
      expect(record.fiatSnapshot!.currency, 'USD');
    },
  );

  for (final received in [false, true]) {
    test(
      'pool enrichment preserves claim lifecycle when received=$received',
      () async {
        final storage = _FakePaymentLinkReceivedStorage();
        final store = PaymentLinkReceivedStore(storage);
        final link = _link();
        final submittedAt = DateTime.utc(2026, 9, 7);
        await store.saveReady(link);
        await store.markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'receiver',
        );
        await store.markReceiving(
          address: link.address,
          destinationAccountUuid: 'receiver',
          claimTxids: 'a,b',
          claimSubmittedAt: submittedAt,
        );
        if (received) await store.markReceived(address: link.address);
        final before = (await store.load()).single;
        await store.updateClaimDestinationPool(
          address: link.address,
          claimDestinationPool: 'ironwood',
        );
        final after = (await PaymentLinkReceivedStore(storage).load()).single;
        expect(after.status, before.status);
        expect(after.isClaimInFlight, !received);
        expect(after.claimDestinationPool, 'ironwood');
        expect(after.claimTxids, 'a,b');
        expect(after.destinationAccountUuid, 'receiver');
        expect(after.claimSubmittedAt, before.claimSubmittedAt);
        expect(after.updatedAt, before.updatedAt);
        expect(after.claimLink!.mnemonic, before.claimLink!.mnemonic);
        expect(after.fiatSnapshot!.amount, before.fiatSnapshot!.amount);
      },
    );
  }

  test('rejects a submitted record without its original claim time', () async {
    final storage = _FakePaymentLinkReceivedStorage();
    final store = PaymentLinkReceivedStore(storage);
    final link = _link();
    await store.saveReady(link);
    await store.markClaimStarted(
      address: link.address,
      destinationAccountUuid: 'receiver-account',
      updatedAt: DateTime.utc(2026, 8, 28),
    );
    final payload = jsonDecode(storage.value!) as Map<String, dynamic>;
    (payload['records'] as List).single.remove('claimSubmittedAt');
    storage.value = jsonEncode(payload);
    await expectLater(
      store.load(),
      throwsA(isA<PaymentLinkReceivedStoreFormatException>()),
    );
  });

  test('receiving preserves submission time across reconciliation', () async {
    final storage = _FakePaymentLinkReceivedStorage();
    final store = PaymentLinkReceivedStore(storage);
    final link = _link();
    final submittedAt = DateTime.utc(2026, 8, 28, 10);
    await store.saveReady(link);
    await store.markClaimStarted(
      address: link.address,
      destinationAccountUuid: 'receiver-account',
      updatedAt: submittedAt,
    );
    await store.markReceiving(
      address: link.address,
      destinationAccountUuid: 'receiver-account',
      claimTxids: 'claim-tx',
      updatedAt: submittedAt.add(const Duration(minutes: 5)),
    );
    final record = (await store.load()).single;
    expect(record.claimSubmittedAt, submittedAt);
    expect(record.updatedAt, submittedAt.add(const Duration(minutes: 5)));
  });

  group('PaymentLinkReceivedStore', () {
    test('notifies listeners after a lifecycle write', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      var revisions = 0;
      final store = PaymentLinkReceivedStore(
        storage,
        onRecordsChanged: () => revisions += 1,
      );

      await store.saveReady(_link());

      expect(revisions, 1);
    });

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
          claimSubmittedAt: DateTime.utc(2026, 8, 5, 12, 1),
          claimDestinationPool: 'orchard',
        );

        final restored = await PaymentLinkReceivedStore(storage).load();
        expect(restored, hasLength(1));
        expect(restored.single.status, PaymentLinkReceivedStatus.receiving);
        expect(restored.single.destinationAccountUuid, 'receiver-account');
        expect(restored.single.claimTxids, 'claim-txid');
        expect(
          restored.single.claimSubmittedAt,
          DateTime.utc(2026, 8, 5, 12, 1),
        );
        expect(restored.single.claimDestinationPool, 'orchard');
        expect(
          restored.single.claimLink?.toUri().toString(),
          link.toUri().toString(),
        );
      },
    );

    test('clears the bearer secret only after the claim is mined', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);
      await store.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      await store.markReceived(address: link.address);
      await store.clearConfirmedClaimSecret(address: link.address);

      final restored = await PaymentLinkReceivedStore(storage).load();
      expect(restored.single.status, PaymentLinkReceivedStatus.received);
      expect(restored.single.claimLink, isNull);
      expect(restored.single.claimTxids, 'claim-txid');
      expect(restored.single.artworkId, 'ruby');
      expect(restored.single.message, 'Enjoy your gift!');
      expect(restored.single.amountZatoshi, link.amountZatoshi);
      expect(storage.value, isNot(contains(link.mnemonic)));
    });

    test('counts only in-flight claims for the destination account', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);
      expect(await store.countReceivingForAccount('receiver-account'), 0);

      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver-account',
      );
      expect(await store.countReceivingForAccount('receiver-account'), 1);

      await store.markReadyToClaim(address: link.address);
      expect(await store.countReceivingForAccount('receiver-account'), 0);

      await store.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      expect(await store.countReceivingForAccount('receiver-account'), 1);
      expect(await store.countReceivingForAccount('other-account'), 0);

      await store.markReceived(address: link.address);
      expect((await store.load()).single.needsClaimRecovery, isTrue);
      expect(await store.countReceivingForAccount('receiver-account'), 0);
      expect(await store.countClaimsInFlight(), 0);
      await store.clearConfirmedClaimSecret(address: link.address);
      expect(await store.countReceivingForAccount('receiver-account'), 0);
    });

    test('reports the in-flight count while the wallet is locked', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final mirror = _FakeClaimCountMirror();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage, countMirror: mirror);

      await store.saveReady(link);
      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver-account',
      );
      expect(mirror.count, 1);

      // The lost-password and forgot-passcode surfaces run locked.
      storage.locked = true;
      expect(await store.countClaimsInFlight(), 1);

      storage.locked = false;
      await store.markReceived(address: link.address);
      expect((await store.load()).single.needsClaimRecovery, isTrue);
      expect(mirror.count, 0);
      storage.locked = true;
      expect(await store.countClaimsInFlight(), 0);
      storage.locked = false;
      await store.clearConfirmedClaimSecret(address: link.address);
      expect(mirror.count, 0);
      storage.locked = true;
      expect(await store.countClaimsInFlight(), 0);
    });

    test(
      'restores a submitting claim before its transaction id is saved',
      () async {
        final storage = _FakePaymentLinkReceivedStorage();
        final link = _link();
        final store = PaymentLinkReceivedStore(storage);

        await store.saveReady(link);
        await store.markClaimStarted(
          address: link.address,
          destinationAccountUuid: 'receiver-account',
        );

        final restored = await PaymentLinkReceivedStore(storage).load();
        expect(restored.single.status, PaymentLinkReceivedStatus.submitting);
        expect(restored.single.destinationAccountUuid, 'receiver-account');
        expect(restored.single.claimTxids, isNull);
        expect(restored.single.isClaimInFlight, isTrue);
        expect(restored.single.needsClaimMetadataRecovery, isTrue);
        expect(restored.single.claimSubmittedAt, isNotNull);
        expect((await store.find(link.address))?.isClaimInFlight, isTrue);
        expect(await store.find('u1missinggiftcard'), isNull);
      },
    );

    test('counts in-flight claims across every account', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);
      expect(await store.countClaimsInFlight(), 0);

      await store.markClaimStarted(
        address: link.address,
        destinationAccountUuid: 'receiver-account',
      );
      expect(await store.countClaimsInFlight(), 1);

      await store.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      expect(await store.countClaimsInFlight(), 1);

      await store.markReceived(address: link.address);
      await store.clearConfirmedClaimSecret(address: link.address);
      expect(await store.countClaimsInFlight(), 0);
    });

    test(
      'refreshes the in-flight claim count after lifecycle writes',
      () async {
        final store = _CountingReceivedStore();
        final container = ProviderContainer(
          overrides: [
            paymentLinkReceivedStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(container.dispose);

        expect(
          await container.read(paymentLinkClaimsInFlightProvider.future),
          1,
        );

        store.inFlightCount = 0;
        container.read(paymentLinkLifecycleRevisionProvider.notifier).bump();

        expect(
          await container.read(paymentLinkClaimsInFlightProvider.future),
          0,
        );
      },
    );

    test(
      'refreshes the cached receiving count after lifecycle writes',
      () async {
        final store = _CountingReceivedStore();
        final container = ProviderContainer(
          overrides: [
            paymentLinkReceivedStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(container.dispose);

        expect(
          await container.read(
            paymentLinkReceivingCountProvider('receiver-account').future,
          ),
          1,
        );

        store.count = 0;
        container.read(paymentLinkLifecycleRevisionProvider.notifier).bump();

        expect(
          await container.read(
            paymentLinkReceivingCountProvider('receiver-account').future,
          ),
          0,
        );
      },
    );

    test('returns an expired claim to an actionable persisted state', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);
      await store.markReceiving(
        claimSubmittedAt: DateTime.utc(2026, 8, 28),
        address: link.address,
        destinationAccountUuid: 'receiver-account',
        claimTxids: 'claim-txid',
      );
      await store.markReadyToClaim(address: link.address);

      final restored = await PaymentLinkReceivedStore(storage).load();
      expect(restored.single.status, PaymentLinkReceivedStatus.readyToClaim);
      expect(restored.single.destinationAccountUuid, isNull);
      expect(restored.single.claimTxids, isNull);
      expect(
        restored.single.claimLink?.toUri().toString(),
        link.toUri().toString(),
      );
      expect(restored.single.claimSubmittedAt, isNull);
      expect(restored.single.claimDestinationPool, isNull);
    });

    test('never persists Receiving without a claim transaction id', () async {
      final storage = _FakePaymentLinkReceivedStorage();
      final link = _link();
      final store = PaymentLinkReceivedStore(storage);

      await store.saveReady(link);

      await expectLater(
        store.markReceiving(
          claimSubmittedAt: DateTime.utc(2026, 8, 28),
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
          claimSubmittedAt: DateTime.utc(2026, 8, 28),
          address: link.address,
          destinationAccountUuid: 'receiver-account',
          claimTxids: 'claim-txid',
        );
        await store.markReceived(address: link.address);
        await store.clearConfirmedClaimSecret(address: link.address);
        await store.saveReady(link);

        final restored = await PaymentLinkReceivedStore(storage).load();
        expect(restored.single.status, PaymentLinkReceivedStatus.received);
        expect(restored.single.claimLink, isNull);
      },
    );

    test('fails loud instead of hiding corrupted received-card data', () async {
      final storage = _FakePaymentLinkReceivedStorage()
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
              'claimLink': _link().toUri().toString(),
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

VizorPaymentLink _link({String address = 'u1paymentlinkaddress'}) {
  return VizorPaymentLink(
    network: 'main',
    address: address,
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 3_456_789,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 5, 12),
    presentation: const PaymentLinkPresentation(
      artworkId: 'ruby',
      fiatSnapshot: PaymentLinkFiatSnapshot(amount: 142.23),
      message: 'Enjoy your gift!',
    ),
  );
}

class _FakePaymentLinkReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;

  /// A locked wallet reads its secrets as null.
  bool locked = false;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<String?> read() async => locked ? null : value;

  @override
  Future<void> write(String nextValue) async {
    value = nextValue;
  }
}

class _FakeClaimCountMirror implements PaymentLinkClaimCountMirror {
  int? count;

  @override
  Future<int?> read() async => count;

  @override
  Future<void> write(int next) async {
    count = next;
  }
}

class _CountingReceivedStore extends PaymentLinkReceivedStore {
  _CountingReceivedStore() : super(_FakePaymentLinkReceivedStorage());

  int count = 1;
  int inFlightCount = 1;

  @override
  Future<int> countReceivingForAccount(String destinationAccountUuid) async {
    return count;
  }

  @override
  Future<int> countClaimsInFlight() async => inFlightCount;
}
