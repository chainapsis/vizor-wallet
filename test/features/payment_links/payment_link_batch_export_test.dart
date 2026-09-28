import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_batch_export.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_sharing.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_gift_link_rust_api.dart';
import '../../support/payment_links_screen_support.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: FakeGiftLinkRustApi()));
  tearDownAll(RustLib.dispose);

  test('CSV has one ordered validated link per funded card', () async {
    final records = [_member(secondBatchLink, 2), _member(incomingLink, 1)];
    final csv = await preparePaymentLinkBatchCsv(records);
    final firstUri = await preparePaymentLinkShareUri(incomingLink);
    final secondUri = await preparePaymentLinkShareUri(secondBatchLink);
    expect(
      csv,
      'card_number,amount_zec,link\r\n'
      '1,"4.45","$firstUri"\r\n'
      '2,"4.45","$secondUri"\r\n',
    );
    expect(records.first.batchIndex, 2); // Export never mutates storage order.
  });

  test('incomplete or unfunded batch cannot yield CSV bytes', () async {
    await expectLater(
      preparePaymentLinkBatchCsv([_member(incomingLink, 1)]),
      throwsStateError,
    );
    await expectLater(
      preparePaymentLinkBatchCsv([
        _member(incomingLink, 1),
        _member(secondBatchLink, 2, state: PaymentLinkRecoveryState.draft),
      ]),
      throwsStateError,
    );
    await expectLater(
      preparePaymentLinkBatchCsv([
        _member(incomingLink, 1),
        _member(secondIncomingLink, 2),
      ]),
      throwsStateError,
    );
  });
}

final secondBatchLink = VizorPaymentLink(
  network: secondIncomingLink.network,
  address: secondIncomingLink.address,
  amountZatoshi: incomingLink.amountZatoshi,
  mnemonic: secondIncomingLink.mnemonic,
  birthdayHeight: secondIncomingLink.birthdayHeight,
  label: secondIncomingLink.label,
  createdAt: secondIncomingLink.createdAt,
  presentation: incomingLink.presentation,
);

PaymentLinkRecoveryRecord _member(
  VizorPaymentLink link,
  int index, {
  PaymentLinkRecoveryState state = PaymentLinkRecoveryState.funded,
}) => PaymentLinkRecoveryRecord(
  link: link,
  sourceAccountUuid: 'account-1',
  state: state,
  updatedAt: DateTime.utc(2026, 8, 6),
  claimFeeReserveZatoshi: BigInt.from(10000),
  fundingTxids: 'txid',
  batchId: 'batch-1',
  batchIndex: index,
  batchCount: 2,
);
