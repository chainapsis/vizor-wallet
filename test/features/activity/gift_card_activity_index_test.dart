import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_lifecycle_revision.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test(
    'only submitted claims get a row before wallet detection, scoped by account',
    () {
      final record = PaymentLinkReceivedRecord(
        network: 'main',
        address: 'pending-card',
        amountZatoshi: BigInt.from(100000),
        createdAt: DateTime.utc(2026, 9, 7),
        artworkId: 'ruby',
        status: PaymentLinkReceivedStatus.receiving,
        claimLink: _link('pending-card'),
        destinationAccountUuid: 'account-1',
        claimTxids: 'claim-txid',
        updatedAt: DateTime.utc(2026, 9, 7),
        claimSubmittedAt: DateTime.utc(2026, 9, 7, 10),
        claimDestinationPool: 'orchard',
      );
      GiftCardActivityIndex indexFor(
        String account,
        List<PaymentLinkReceivedRecord> records,
      ) => GiftCardActivityIndex.forAccount(
        accountUuid: account,
        createdRecords: [],
        receivedRecords: records,
      );
      final index = indexFor('account-1', [record]);
      final pending = index.withPendingClaims([]).single;
      expect(pending.txidHex, 'claim-txid');
      expect(pending.minedHeight, BigInt.zero);
      expect(pending.createdTime, BigInt.from(1788775200));
      expect(pending.displayPool, 'orchard');
      expect(index.metadataFor(pending)!.isClaimInFlight, isTrue);
      expect(indexFor('account-2', [record]).withPendingClaims([]), isEmpty);
      expect(
        indexFor('account-1', [
          PaymentLinkReceivedRecord.fromLink(_link('preview')),
        ]).withPendingClaims([]),
        isEmpty,
      );
      final actual = _transaction(txidHex: 'claim-txid', txKind: 'received');
      expect(index.withPendingClaims([actual]), [actual]);
      // A sender row for the same transaction does not replace the receive leg.
      final sent = _transaction(txidHex: 'claim-txid', txKind: 'sent');
      expect(index.withPendingClaims([sent]), hasLength(2));
    },
  );

  test('keeps one stable Gift Card row when a claim has multiple legs', () {
    final firstTxid = List.filled(32, 'ab').join();
    final secondTxid = List.filled(32, 'cd').join();
    final record = PaymentLinkReceivedRecord(
      network: 'main',
      address: 'multi-leg-card',
      amountZatoshi: BigInt.from(100000000),
      createdAt: DateTime.utc(2026, 8, 28),
      artworkId: 'ruby',
      status: PaymentLinkReceivedStatus.received,
      claimLink: null,
      destinationAccountUuid: 'account-1',
      claimTxids: '$firstTxid,$secondTxid',
      updatedAt: DateTime.utc(2026, 8, 28, 12),
      claimSubmittedAt: DateTime.utc(2026, 8, 28, 11),
      claimDestinationPool: 'ironwood',
    );
    final index = GiftCardActivityIndex.forAccount(
      accountUuid: 'account-1',
      createdRecords: const [],
      receivedRecords: [record],
    );
    final rows = index.withPendingClaims([
      _transaction(txidHex: firstTxid, txKind: 'received'),
      _transaction(txidHex: secondTxid, txKind: 'received'),
    ]);

    expect(rows, hasLength(1));
    final metadata = index.metadataFor(rows.single);
    expect(metadata?.stableId, 'gift-card:multi-leg-card');
    expect(metadata?.activityTimestamp, DateTime.utc(2026, 8, 28, 11));
    expect(metadata?.displayPool, 'ironwood');
    expect(metadata?.amountZatoshi, BigInt.from(100000000));
  });

  test('matches created and redeemed transactions for the active account', () {
    final createdTxid = List.filled(32, '12').join();
    final redeemedTxid = List.filled(32, '34').join();
    final index = GiftCardActivityIndex.forAccount(
      accountUuid: 'account-1',
      createdRecords: [
        PaymentLinkRecoveryRecord(
          link: _link('created-address'),
          claimFeeReserveZatoshi: BigInt.from(20000),
          sourceAccountUuid: 'account-1',
          state: PaymentLinkRecoveryState.shared,
          updatedAt: DateTime.utc(2026, 8, 28),
          fundingTxids: createdTxid,
        ),
        PaymentLinkRecoveryRecord(
          link: _link('other-created-address'),
          sourceAccountUuid: 'account-2',
          state: PaymentLinkRecoveryState.shared,
          updatedAt: DateTime.utc(2026, 8, 28),
          fundingTxids: List.filled(32, '56').join(),
        ),
      ],
      receivedRecords: [
        PaymentLinkReceivedRecord(
          network: 'main',
          address: 'redeemed-address',
          fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 142.23),
          amountZatoshi: BigInt.from(100000000),
          createdAt: DateTime.utc(2026, 8, 28),
          artworkId: null,
          status: PaymentLinkReceivedStatus.received,
          claimLink: null,
          destinationAccountUuid: 'account-1',
          claimTxids: redeemedTxid,
          updatedAt: DateTime.utc(2026, 8, 28),
        ),
      ],
    );

    expect(
      index.kindFor(_transaction(txidHex: createdTxid, txKind: 'sent')),
      GiftCardActivityKind.created,
    );
    expect(
      index.kindFor(
        _transaction(
          txidHex: _reverseHexBytes(redeemedTxid),
          txKind: 'received',
        ),
      ),
      GiftCardActivityKind.redeemed,
    );
    expect(
      index.kindFor(_transaction(txidHex: createdTxid, txKind: 'received')),
      isNull,
    );
    final createdMetadata = index.metadataFor(
      _transaction(txidHex: createdTxid, txKind: 'sent'),
    );

    expect(
      createdMetadata!.detailFeeZatoshi(BigInt.from(15000)),
      BigInt.from(35000),
    );
    expect(createdMetadata.kind, GiftCardActivityKind.created);
    expect(createdMetadata.amountZatoshi, BigInt.from(100000000));
    expect(createdMetadata.artworkId, 'ruby');
    expect(createdMetadata.message, 'Happy birthday!');
    final redeemedMetadata = index.metadataFor(
      _transaction(txidHex: _reverseHexBytes(redeemedTxid), txKind: 'received'),
    );

    expect(redeemedMetadata!.fiatSnapshot!.amount, 142.23);
    expect(
      redeemedMetadata.detailFeeZatoshi(BigInt.from(15000)),
      BigInt.from(15000),
    );
    expect(redeemedMetadata.kind, GiftCardActivityKind.redeemed);
    expect(redeemedMetadata.amountZatoshi, BigInt.from(100000000));
  });

  test('refreshes its completed future after lifecycle writes', () async {
    final recoveryStore = PaymentLinkRecoveryStore(_MemoryRecoveryStorage());
    final receivedStore = PaymentLinkReceivedStore(_MemoryReceivedStorage());
    final container = ProviderContainer(
      overrides: [
        paymentLinkRecoveryStoreProvider.overrideWithValue(recoveryStore),
        paymentLinkReceivedStoreProvider.overrideWithValue(receivedStore),
      ],
    );
    addTearDown(container.dispose);
    final provider = giftCardActivityIndexProvider('account-1');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final initialIndex = await container.read(provider.future);
    expect(initialIndex.createdTxids, isEmpty);
    expect(initialIndex.redeemedTxids, isEmpty);

    final createdLink = _link('created-revision-address');
    await recoveryStore.saveDraft(
      link: createdLink,
      sourceAccountUuid: 'account-1',
    );
    await recoveryStore.markFunded(
      address: createdLink.address,
      fundingTxids: 'created-revision-txid',
    );
    container.read(paymentLinkLifecycleRevisionProvider.notifier).bump();

    final createdIndex = await container.read(provider.future);
    expect(createdIndex.createdTxids, {'created-revision-txid'});

    final receivedLink = _link('received-revision-address');
    await receivedStore.saveReady(receivedLink);
    await receivedStore.markReceiving(
      address: receivedLink.address,
      destinationAccountUuid: 'account-1',
      claimTxids: 'received-revision-txid',
    );
    container.read(paymentLinkLifecycleRevisionProvider.notifier).bump();

    final receivedIndex = await container.read(provider.future);
    expect(receivedIndex.redeemedTxids, {'received-revision-txid'});
  });
}

VizorPaymentLink _link(String address) {
  return VizorPaymentLink(
    network: 'main',
    address: address,
    amountZatoshi: BigInt.from(100000000),
    mnemonic:
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
    birthdayHeight: 1,
    label: 'Gift Card',
    createdAt: DateTime.utc(2026, 8, 28),
    presentation: const PaymentLinkPresentation(
      artworkId: 'ruby',
      message: 'Happy birthday!',
    ),
  );
}

rust_sync.TransactionInfo _transaction({
  required String txidHex,
  required String txKind,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.one,
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: txKind,
    displayAmount: BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

String _reverseHexBytes(String value) {
  final reversed = StringBuffer();
  for (var index = value.length; index > 0; index -= 2) {
    reversed.write(value.substring(index - 2, index));
  }
  return reversed.toString();
}

class _MemoryRecoveryStorage implements PaymentLinkRecoveryStorage {
  String? value;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _MemoryReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
