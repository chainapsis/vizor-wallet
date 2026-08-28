import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('matches created and redeemed transactions for the active account', () {
    final createdTxid = List.filled(32, '12').join();
    final redeemedTxid = List.filled(32, '34').join();
    final index = GiftCardActivityIndex.forAccount(
      accountUuid: 'account-1',
      createdRecords: [
        PaymentLinkRecoveryRecord(
          link: _link('created-address'),
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
