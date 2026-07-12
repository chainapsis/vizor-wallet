import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_detail_tooltips.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_status_page_content.dart';

void main() {
  test('maps in-progress status page data from the saved swap intent', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(indicativeExternalPerZec: {SwapAsset.usdc: 70}),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: '2.0000 ZEC',
        receiveEstimate: '140.00 USDC',
        depositAddress: 't1deposit-address',
        oneClickRecipient: '0xrecipient-address',
        oneClickRefundTo: 'u1refund-address',
        createdAt: DateTime.utc(2026, 5, 20, 13, 20),
      ),
      accountDetail: const SwapActivityAccountDetail(
        name: 'Shielded account',
        profilePictureId: 'profile-1',
      ),
    );

    expect(presentation.title, 'Swap in progress...');
    expect(presentation.payAsset, SwapAsset.zec);
    expect(presentation.receiveAsset, SwapAsset.usdc);
    expect(presentation.payFiatText, r'$--');
    expect(presentation.receiveFiatText, r'$--');
    expect(presentation.badgeKind, SwapStatusBadgeKind.liveQuote);
    expect(presentation.progressIndex, 2);
    expect(presentation.showTabs, isTrue);
    expect(presentation.steps.map((step) => step.title), [
      'ZEC',
      'Deposit confirmation',
      'Swap',
      'Deliver USDC',
    ]);
    // The redesigned summary carries the counterparty address line instead
    // of a details Account row.
    expect(presentation.receiveDetailText, contains('To: '));
    expect(presentation.receiveDetailText, contains('on Ethereum'));
    expect(presentation.receiveDetailCopyText, '0xrecipient-address');
    expect(presentation.payDetailCopyText, isNull);
    expect(presentation.details.any((row) => row.label == 'Account'), isFalse);
    expect(
      _detailValue(presentation.details, 'USDC recipient'),
      contains('0x'),
    );
    expect(_detailRow(presentation.details, 'Timestamp').value, isNotEmpty);
    expect(
      _detailValue(presentation.details, 'Deposit ZEC to'),
      contains('t1'),
    );
    expect(
      _detailValue(presentation.details, 'Guaranteed minimum'),
      '140.00 USDC',
    );
    expect(
      _detailRow(presentation.details, 'Swap fee').helpTooltip,
      swapFeeTooltip,
    );
    expect(
      _detailRow(presentation.details, 'Guaranteed minimum').helpTooltip,
      swapMinimumReceiveTooltip('USDC'),
    );
    expect(
      _detailRow(presentation.details, 'ZEC refund address').copyable,
      isTrue,
    );
    expect(
      _detailRow(presentation.details, 'ZEC refund address').copyText,
      'u1refund-address',
    );
  });

  test('maps completed pay activity to the Figma status presentation', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.complete,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: '4.0000 ZEC',
        receiveEstimate: '100.00 USDC',
        depositAddress: 't1bufatsuYMEZJ8watyV52rsNZ4CvaAzeBo',
        depositTxHash: 'zec-shielded-spend-txid',
        nearIntentHash: 'near-intent-hash-123',
        destinationChainTxHash: '0xusdc-delivery-txid',
        oneClickRecipient: '0xrecipient-address',
        totalFeesText: '0.1800 ZEC',
        completedAt: DateTime(2026, 5, 25, 13, 30),
        payMode: true,
      ),
    );

    expect(presentation.title, 'Payment complete');
    expect(presentation.statusLabel, 'Complete');
    expect(presentation.payLabel, 'You paid');
    expect(presentation.receiveLabel, 'Recipient received');
    expect(presentation.payDetailText, 'Privately, from shielded balance');
    expect(presentation.progressTabLabel, 'Payment progress');
    expect(presentation.paymentMode, isTrue);
    expect(presentation.showTabs, isFalse);
    expect(presentation.payStatus, isNotNull);
    expect(presentation.payStatus!.title, 'Paid successfully');
    expect(presentation.payStatus!.statusLabel, 'Completed');
    expect(presentation.payStatus!.phase, PayActivityStatusPhase.completed);
    expect(presentation.payStatus!.timestampText, '25 May, 13:30');
    expect(presentation.payStatus!.txIdText, 't1bufats...CvaAzeBo');
    expect(
      presentation.payStatus!.txIdUri,
      Uri.parse(
        'https://explorer.near-intents.org/transactions/'
        't1bufatsuYMEZJ8watyV52rsNZ4CvaAzeBo',
      ),
    );
    expect(presentation.payStatus!.convertedFromText, '4.0000 ZEC');
    // totalFeesText is an app/provider fee, not the network transaction fee.
    expect(presentation.payStatus!.transactionFeeText, 'Not reported');
    expect(presentation.steps.map((step) => step.title), [
      'Spend ZEC',
      'Convert',
      'Deliver USDC',
      'Recipient receives',
    ]);

    expect(presentation.details.map((detail) => detail.label), [
      'You paid',
      'Rate',
      'Fees',
      'ZEC tx (shielded)',
      'USDC delivery tx',
    ]);
    expect(_detailValue(presentation.details, 'You paid'), '4.0000 ZEC');
    expect(_detailValue(presentation.details, 'Rate'), '1 ZEC = 25 USDC');
    expect(
      _detailRow(presentation.details, 'ZEC tx (shielded)').copyText,
      'zec-shielded-spend-txid',
    );
    expect(
      _detailRow(presentation.details, 'USDC delivery tx').copyText,
      '0xusdc-delivery-txid',
    );
    expect(_detailValue(presentation.details, 'Fees'), '0.1800 ZEC');
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Timestamp')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('USDC recipient')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Deposit ZEC to')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Realized slippage')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Total fees')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Slippage tolerance')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Guaranteed minimum')),
    );
  });

  test('maps in-progress pay activity without invented tx fees', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: '4.0000 ZEC',
        receiveEstimate: '100.00 USDC',
        oneClickRecipient: '0xrecipient-address',
        createdAt: DateTime(2026, 5, 25, 13, 30),
        payMode: true,
      ),
    );

    expect(presentation.title, 'Payment in progress');
    expect(presentation.statusLabel, 'Processing');
    expect(presentation.paymentMode, isTrue);
    expect(presentation.showTabs, isTrue);
    expect(presentation.payStatus, isNotNull);
    expect(presentation.payStatus!.title, 'Pay in progress...');
    expect(presentation.payStatus!.statusLabel, 'In progress');
    expect(presentation.payStatus!.phase, PayActivityStatusPhase.inProgress);
    expect(presentation.payStatus!.timestampText, '25 May, 13:30');
    expect(presentation.payStatus!.txIdText, 'Not reported');
    expect(presentation.payStatus!.txIdUri, isNull);
    expect(presentation.payStatus!.convertedFromText, '4.0000 ZEC');
    expect(presentation.payStatus!.transactionFeeText, 'Not reported');
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Fees')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Network + conversion fees')),
    );
    expect(
      presentation.details.map((detail) => detail.value),
      isNot(contains('Included')),
    );
    expect(
      presentation.details.map((detail) => detail.value),
      isNot(contains('Included in shown rate')),
    );
    expect(
      presentation.steps.map((step) => step.lastCheckedLabel),
      everyElement(isNull),
    );
  });

  test('reserves Recipient received for completed Pay activity', () {
    for (final status in const [
      SwapIntentStatus.failed,
      SwapIntentStatus.refunded,
      SwapIntentStatus.expired,
    ]) {
      final presentation = swapActivityStatusPresentationForIntent(
        _state(),
        _intent(
          status: status,
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: '4.0000 ZEC',
          receiveEstimate: '100.00 USDC',
          oneClickRecipient: '0xrecipient-address',
          payMode: true,
        ),
      );

      expect(
        presentation.receiveLabel,
        'Recipient gets',
        reason: status.name,
      );
    }
  });

  test('uses paid copy only when a terminal Pay moved funds', () {
    SwapActivityStatusPresentation presentation({String? depositTxHash}) {
      return swapActivityStatusPresentationForIntent(
        _state(),
        _intent(
          status: SwapIntentStatus.expired,
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: '4.0000 ZEC',
          receiveEstimate: '100.00 USDC',
          depositTxHash: depositTxHash,
          oneClickRecipient: '0xrecipient-address',
          payMode: true,
        ),
      );
    }

    final undeposited = presentation();
    expect(undeposited.payLabel, 'You pay');
    expect(undeposited.details.map((row) => row.label), contains('You pay'));
    expect(
      undeposited.details.map((row) => row.label),
      isNot(contains('You paid')),
    );

    final deposited = presentation(depositTxHash: 'zec-deposit-txid');
    expect(deposited.payLabel, 'You paid');
    expect(deposited.details.map((row) => row.label), contains('You paid'));
  });

  test('failed Pay copy requires provider-observed deposit evidence', () {
    SwapActivityStatusPresentation presentation({
      String? depositTxHash,
      String? originChainTxHash,
      String? depositedAmountText,
    }) {
      return swapActivityStatusPresentationForIntent(
        _state(),
        _intent(
          status: SwapIntentStatus.failed,
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: '4.0000 ZEC',
          receiveEstimate: '100.00 USDC',
          depositTxHash: depositTxHash,
          originChainTxHash: originChainTxHash,
          providerRefundInfo: depositedAmountText == null
              ? null
              : SwapProviderRefundInfo(
                  depositedAmountText: depositedAmountText,
                ),
          oneClickRecipient: '0xrecipient-address',
          payMode: true,
        ),
      );
    }

    expect(
      presentation(depositTxHash: 'local-broadcast-txid').payLabel,
      'You pay',
    );
    expect(
      presentation(originChainTxHash: 'provider-origin-txid').payLabel,
      'You paid',
    );
    expect(
      presentation(depositedAmountText: '0.7500 ZEC').payLabel,
      'You paid',
    );
    expect(presentation(depositedAmountText: '0 ZEC').payLabel, 'You pay');
  });

  test('provider deposit statuses use paid copy without a tx hash', () {
    SwapActivityStatusPresentation presentation(SwapIntentStatus status) {
      return swapActivityStatusPresentationForIntent(
        _state(),
        _intent(
          status: status,
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: '4.0000 ZEC',
          receiveEstimate: '100.00 USDC',
          oneClickRecipient: '0xrecipient-address',
          payMode: true,
        ),
      );
    }

    for (final status in [
      SwapIntentStatus.depositObserved,
      SwapIntentStatus.processing,
      SwapIntentStatus.incompleteDeposit,
      SwapIntentStatus.refunded,
    ]) {
      final result = presentation(status);
      expect(result.payLabel, 'You paid', reason: status.name);
      expect(
        result.details.map((row) => row.label),
        contains('You paid'),
        reason: status.name,
      );
    }
  });

  test('omits the tx id detail row on desktop', () {
    // The "Tx ID" row is a mobile-only addition; desktop keeps the original
    // detail set. Mobile-lane coverage of the row lives in
    // mobile_swap_activity_tx_id_test.dart.
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1provider-deposit',
        nearIntentHash: 'intent-hash-123',
        originChainTxHash: 'zec-origin-txid',
      ),
    );

    expect(presentation.details.where((row) => row.label == 'Tx ID'), isEmpty);
  });

  test('adds address book labels to matching address detail rows', () {
    const recipientAddress = '0x52908400098527886E0F7030069857D2E4169EE7';
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit-address',
        oneClickRecipient: recipientAddress,
        oneClickRefundTo: 'u1refund-address',
      ),
      addressBookContacts: [
        _contact(
          label: 'Treasury',
          network: AddressBookNetwork.ethereum,
          address: recipientAddress.toLowerCase(),
        ),
        _contact(
          label: 'Refund safe',
          network: AddressBookNetwork.zcash,
          address: 'u1refund-address',
        ),
      ],
    );

    final recipient = _detailRow(presentation.details, 'USDC recipient');
    expect(recipient.value, contains('0x'));
    expect(recipient.copyText, recipientAddress);
    expect(recipient.addressBookLabel, 'Treasury');
    expect(recipient.addressNetwork, AddressBookNetwork.ethereum);

    final refund = _detailRow(presentation.details, 'ZEC refund address');
    expect(refund.value, contains('u1'));
    expect(refund.copyText, 'u1refund-address');
    expect(refund.addressBookLabel, 'Refund safe');
    expect(refund.addressNetwork, AddressBookNetwork.zcash);

    final deposit = _detailRow(presentation.details, 'Deposit ZEC to');
    expect(deposit.value, contains('t1'));
    expect(deposit.copyText, 't1deposit-address');
    expect(deposit.addressBookLabel, isNull);

    // The nickname is folded into the address row, not emitted as a separate
    // empty-label row.
    expect(presentation.details.where((row) => row.label.isEmpty), isEmpty);
  });

  test('adds a labeled recipient row to terminal swap details', () {
    const recipientAddress = '0x52908400098527886e0f7030069857d2e4169ee7';
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.complete,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit-address',
        oneClickRecipient: recipientAddress,
        completedAt: DateTime.utc(2026, 5, 25, 13, 30),
      ),
      addressBookContacts: [
        _contact(
          label: 'Treasury',
          network: AddressBookNetwork.ethereum,
          address: recipientAddress,
        ),
      ],
    );

    // Terminal details follow the completed layout: the recipient lives in
    // the summary's address line, and the deposit tx row links out to the
    // NEAR Intents explorer.
    expect(presentation.receiveDetailText, contains('To: '));
    expect(presentation.receiveDetailCopyText, recipientAddress);
    expect(presentation.statusLabel, isNotEmpty);
    expect(
      presentation.details.any((row) => row.label == 'USDC recipient'),
      isFalse,
    );
    expect(_detailRow(presentation.details, 'Timestamp').value, isNotEmpty);
    final fees = _detailRow(presentation.details, 'Total fees');
    expect(fees.helpTooltip, swapTotalFeesTooltip);
    expect(presentation.details.last.label, 'Total fees');
  });

  test('summary header lines carry the matched contact name', () {
    const recipientAddress = '0x52908400098527886e0f7030069857d2e4169ee7';
    final sending = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        oneClickRecipient: recipientAddress,
      ),
      addressBookContacts: [
        _contact(
          label: 'Treasury',
          network: AddressBookNetwork.ethereum,
          address: recipientAddress,
        ),
      ],
    );
    expect(sending.receiveDetailText, startsWith('To: Treasury ('));
    expect(sending.receiveDetailText, contains('on Ethereum'));
    expect(sending.receiveDetailCopyText, recipientAddress);

    final depositing = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.awaitingExternalDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        oneClickRefundTo: recipientAddress,
      ),
      addressBookContacts: [
        _contact(
          label: 'Treasury',
          network: AddressBookNetwork.ethereum,
          address: recipientAddress,
        ),
      ],
    );
    expect(depositing.payDetailText, startsWith('Refund to: Treasury ('));
    expect(depositing.payDetailCopyText, recipientAddress);
  });

  test('EVM contact saved on another chain labels the address row', () {
    const recipientAddress = '0x52908400098527886e0f7030069857d2e4169ee7';
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        oneClickRecipient: recipientAddress,
      ),
      addressBookContacts: [
        _contact(
          label: 'Polygon Treasury',
          network: AddressBookNetwork.polygon,
          address: recipientAddress,
        ),
      ],
    );

    final recipient = _detailRow(presentation.details, 'USDC recipient');
    expect(recipient.addressBookLabel, 'Polygon Treasury');
    expect(
      presentation.receiveDetailText,
      startsWith('To: Polygon Treasury ('),
    );
  });

  test('terminal deposit tx row links to the NEAR Intents explorer', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.complete,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        pair: 'USDC -> ZEC',
        depositAddress: '0xdeposit-address',
        originChainTxHash: '0xdeadbeefdeadbeefdeadbeef',
      ),
    );

    final txRow = _detailRow(presentation.details, 'USDC deposit tx');
    expect(txRow.copyText, '0xdeadbeefdeadbeefdeadbeef');
    expect(txRow.linkUri, isNotNull);
    expect(txRow.linkUri!.host, 'explorer.near-intents.org');
    expect(txRow.linkUri!.pathSegments, ['transactions', '0xdeposit-address']);
  });

  test(
    'uses captured fiat basis instead of current pricing for status summary',
    () {
      final presentation = swapActivityStatusPresentationForIntent(
        _state(indicativeExternalPerZec: {SwapAsset.usdc: 200}),
        _intent(
          status: SwapIntentStatus.complete,
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          sellAmount: '2.0000 ZEC',
          receiveEstimate: '123.45 USDC',
          fiatValueBasis: SwapFiatValueBasis(
            sellUsdUnitPrice: 70,
            receiveUsdUnitPrice: 1,
            capturedAt: DateTime.utc(2026, 5, 7, 10),
          ),
        ),
      );

      expect(presentation.payFiatText, r'$140.00');
      expect(presentation.receiveFiatText, r'$123.45');
    },
  );

  test('does not recalculate missing captured fiat sides with live prices', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(indicativeExternalPerZec: {SwapAsset.usdc: 200}),
      _intent(
        status: SwapIntentStatus.complete,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: '2.0000 ZEC',
        receiveEstimate: '123.45 USDC',
        fiatValueBasis: SwapFiatValueBasis(
          sellUsdUnitPrice: 70,
          capturedAt: DateTime.utc(2026, 5, 7, 10),
        ),
      ),
    );

    expect(presentation.payFiatText, r'$140.00');
    expect(presentation.receiveFiatText, r'$--');
  });

  test('keeps terminal failure details compact and final', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.failed,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        totalFeesText: '0.00002 ZEC',
        realisedSlippageText: '0.01 USDC (0.01%)',
        oneClickRefundTo: 'u1refund-address',
        completedAt: DateTime(2026, 5, 7, 10, 30),
      ),
    );

    expect(presentation.title, 'Swap failed');
    expect(presentation.badgeKind, SwapStatusBadgeKind.failed);
    expect(presentation.progressIndex, 3);
    expect(presentation.showTabs, isFalse);
    expect(_detailValue(presentation.details, 'Total fees'), '0.00002 ZEC');
    expect(
      _detailRow(presentation.details, 'Total fees').helpTooltip,
      swapTotalFeesTooltip,
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Realized slippage')),
    );
    expect(
      _detailValue(presentation.details, 'ZEC refunded to'),
      contains('u1'),
    );
    expect(
      _detailRow(presentation.details, 'ZEC refunded to').copyable,
      isTrue,
    );
    expect(
      _detailRow(presentation.details, 'ZEC refunded to').copyText,
      'u1refund-address',
    );
    expect(
      _detailValue(presentation.details, 'Timestamp'),
      'May 7, 2026 10:30',
    );
  });

  test('marks external source refund addresses copyable', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(indicativeExternalPerZec: {SwapAsset.usdc: 70}),
      _intent(
        status: SwapIntentStatus.awaitingExternalDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        pair: 'USDC -> ZEC',
        depositAddress: '0xdeposit-address',
        oneClickRefundTo: '0xrefund-address',
      ),
    );

    final row = _detailRow(presentation.details, 'USDC refund address');
    expect(row.value, contains('0x'));
    expect(row.copyable, isTrue);
    expect(row.copyText, '0xrefund-address');
  });

  test('separates incomplete deposits from terminal failures', () {
    final deadline = DateTime(2026, 5, 7, 12);
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.incompleteDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        pair: 'USDC -> ZEC',
        sellAmount: '100.00 USDC',
        receiveEstimate: '1.4250 ZEC',
        depositAddress: '0xdeposit-address',
        depositMemo: 'memo-7',
        oneClickRecipient: 'u1recipient-address',
        oneClickRefundTo: '0xrefund-address',
        providerRefundInfo: const SwapProviderRefundInfo(
          depositedAmountText: '60.00 USDC',
          refundFeeText: '0.25 USDC',
        ),
        depositDeadline: deadline,
        nextAction: 'Deposit is below the quoted amount',
      ),
    );

    expect(presentation.title, 'Incomplete deposit');
    expect(presentation.badgeKind, SwapStatusBadgeKind.warning);
    expect(presentation.showTabs, isTrue);
    expect(
      _detailValue(presentation.details, 'Required deposit'),
      '100.00 USDC',
    );
    expect(
      _detailValue(presentation.details, 'Detected deposit'),
      '60.00 USDC',
    );
    expect(_detailValue(presentation.details, 'Missing deposit'), '40 USDC');
    expect(_detailValue(presentation.details, 'Memo'), 'memo-7');
    expect(
      _detailValue(presentation.details, 'Deposit USDC to'),
      '0xdeposit-address',
    );
    expect(_detailValue(presentation.details, 'Refund fee'), '0.25 USDC');
    expect(
      _detailValue(presentation.details, 'Deposit deadline'),
      'May 7, 2026 12:00',
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Guaranteed minimum')),
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Swap fee')),
    );
  });

  test('uses provider minimum deposit for flex-input incomplete deposits', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.incompleteDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        pair: 'USDC -> ZEC',
        sellAmount: '140.35 USDC',
        receiveEstimate: '2 ZEC',
        depositAddress: '0xdeposit-address',
        oneClickRecipient: 'u1recipient-address',
        oneClickRefundTo: '0xrefund-address',
        providerRefundInfo: const SwapProviderRefundInfo(
          minimumDepositText: '139.65 USDC',
          depositedAmountText: '139.00 USDC',
        ),
        nextAction: 'Deposit is below the minimum amount',
      ),
    );

    expect(
      _detailValue(presentation.details, 'Required deposit'),
      '139.65 USDC',
    );
    expect(
      _detailValue(presentation.details, 'Detected deposit'),
      '139.00 USDC',
    );
    expect(_detailValue(presentation.details, 'Missing deposit'), '0.65 USDC');
  });

  test('maps deposit instructions by swap direction', () {
    final zecInstruction = SwapActivityDepositInstruction.fromIntent(
      _intent(
        status: SwapIntentStatus.awaitingDeposit,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit-address',
        depositMemo: 'memo-1',
      ),
    );

    expect(zecInstruction?.sendLabel, 'Send ZEC');
    expect(zecInstruction?.depositSymbol, 'ZEC');
    expect(zecInstruction?.depositAddressLabel, 'ZEC deposit');
    expect(zecInstruction?.memo, 'memo-1');
    expect(zecInstruction?.qr, isNull);

    final externalInstruction = SwapActivityDepositInstruction.fromIntent(
      _intent(
        status: SwapIntentStatus.awaitingExternalDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        depositAddress: '0xdeposit-address',
      ),
    );

    expect(externalInstruction?.sendLabel, 'Send USDC from source chain');
    expect(externalInstruction?.depositSymbol, 'USDC');
    expect(externalInstruction?.depositAddressLabel, 'USDC source deposit');
    expect(externalInstruction?.qr?.railLabel, 'Ethereum USDC');
    expect(externalInstruction?.qr?.reuseWarning, 'Do not reuse this address');
    expect(externalInstruction?.txHashLabel, 'USDC deposit tx hash');
    expect(externalInstruction?.qr, isNotNull);
  });

  test('maps deposit page and refresh predicates', () {
    final externalAwaiting = _intent(
      status: SwapIntentStatus.awaitingExternalDeposit,
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      depositAddress: '0xdeposit-address',
    );
    expect(swapActivityShowsExternalDepositPage(externalAwaiting), isTrue);
    expect(
      swapActivityShowsDepositPage(externalAwaiting, intentIsHardware: false),
      isTrue,
    );

    final hardwareAwaiting = _intent(
      status: SwapIntentStatus.awaitingDeposit,
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositAddress: 't1deposit-address',
    );
    expect(
      swapActivityShowsHardwareZecDepositPage(
        hardwareAwaiting,
        intentIsHardware: true,
      ),
      isTrue,
    );
    expect(
      swapActivityShowsHardwareZecDepositPage(
        hardwareAwaiting,
        intentIsHardware: false,
      ),
      isFalse,
    );

    final broadcasted = _intent(
      status: SwapIntentStatus.awaitingDeposit,
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositAddress: 't1deposit-address',
      depositTxHash: 'zec-deposit-txid',
    );
    expect(
      swapActivityShowsHardwareZecDepositPage(
        broadcasted,
        intentIsHardware: true,
      ),
      isFalse,
    );

    final expired = _intent(
      status: SwapIntentStatus.expired,
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
    );
    expect(SwapActivityDepositInstruction.fromIntent(expired), isNull);
    expect(
      swapActivityShowsDepositPage(expired, intentIsHardware: false),
      isTrue,
    );

    expect(canRefreshSwapIntentStatus(SwapIntentStatus.complete), false);
    expect(canRefreshSwapIntentStatus(SwapIntentStatus.failed), true);
  });

  test(
    'swapActivityShowsExternalDepositPage returns false once depositClaimedAt is set',
    () {
      final base = _intent(
        status: SwapIntentStatus.awaitingExternalDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        depositAddress: '0xdeposit-address',
      );
      expect(swapActivityShowsExternalDepositPage(base), isTrue);

      final claimed = base.copyWith(
        depositClaimedAt: DateTime.utc(2026, 5, 29, 12),
      );
      expect(swapActivityShowsExternalDepositPage(claimed), isFalse);
    },
  );

  test(
    'claimed external deposit advances progress to the confirmation step',
    () {
      final awaiting = _intent(
        status: SwapIntentStatus.awaitingExternalDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        depositAddress: '0xdeposit-address',
      );
      expect(
        swapActivityStatusPresentationForIntent(
          _state(),
          awaiting,
        ).progressIndex,
        0,
      );

      final claimed = awaiting.copyWith(
        depositClaimedAt: DateTime.utc(2026, 5, 29, 12),
      );
      expect(
        swapActivityStatusPresentationForIntent(
          _state(),
          claimed,
        ).progressIndex,
        1,
      );
    },
  );

  test('status details keep the deposit memo reachable after a claim', () {
    final claimed = _intent(
      status: SwapIntentStatus.awaitingExternalDeposit,
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      pair: 'USDC -> ZEC',
      depositAddress: '0xdeposit-address',
      depositMemo: 'required-memo-123',
    ).copyWith(depositClaimedAt: DateTime.utc(2026, 5, 29, 12));
    final memo = _detailRow(
      swapActivityStatusPresentationForIntent(_state(), claimed).details,
      'Memo',
    );
    expect(memo.value, 'required-memo-123');
    expect(memo.copyable, isTrue);
    expect(memo.copyText, 'required-memo-123');
  });
}

SwapState _state({Map<SwapAsset, double> indicativeExternalPerZec = const {}}) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    indicativeExternalPerZec: indicativeExternalPerZec,
  );
}

SwapIntent _intent({
  required SwapIntentStatus status,
  required SwapDirection direction,
  required SwapAsset externalAsset,
  String pair = 'ZEC -> USDC',
  String sellAmount = '2.0000 ZEC',
  String receiveEstimate = '140.00 USDC',
  String? depositAddress,
  String? depositMemo,
  String? depositTxHash,
  String? nearIntentHash,
  String? originChainTxHash,
  String? destinationChainTxHash,
  String? totalFeesText,
  String? realisedSlippageText,
  String? oneClickRecipient,
  String? oneClickRefundTo,
  String? providerStatusRaw,
  String? nextAction,
  SwapProviderRefundInfo? providerRefundInfo,
  SwapFiatValueBasis? fiatValueBasis,
  DateTime? depositDeadline,
  DateTime? createdAt,
  DateTime? completedAt,
  bool payMode = false,
}) {
  return SwapIntent(
    id: 'swap-activity',
    pair: pair,
    sellAmount: sellAmount,
    receiveEstimate: receiveEstimate,
    provider: 'NEAR Intents',
    status: status,
    nextAction: nextAction ?? 'Next action',
    direction: direction,
    externalAsset: externalAsset,
    depositAddress: depositAddress,
    depositMemo: depositMemo,
    depositTxHash: depositTxHash,
    totalFeesText: totalFeesText,
    realisedSlippageText: realisedSlippageText,
    minimumReceiveText: receiveEstimate,
    nearIntentHash: nearIntentHash,
    originChainTxHash: originChainTxHash,
    destinationChainTxHash: destinationChainTxHash,
    oneClickRecipient: oneClickRecipient,
    oneClickRefundTo: oneClickRefundTo,
    providerStatusRaw: providerStatusRaw,
    providerRefundInfo: providerRefundInfo,
    fiatValueBasis: fiatValueBasis,
    depositDeadline: depositDeadline,
    payMode: payMode,
    createdAt: createdAt,
    completedAt: completedAt,
  );
}

String _detailValue(List<SwapStatusDetailRowData> rows, String label) {
  return _detailRow(rows, label).value;
}

SwapStatusDetailRowData _detailRow(
  List<SwapStatusDetailRowData> rows,
  String label,
) {
  return rows.singleWhere((row) => row.label == label);
}

AddressBookContact _contact({
  required String label,
  required AddressBookNetwork network,
  required String address,
}) {
  return AddressBookContact(
    id: 'contact_$label',
    label: label,
    network: network,
    address: address,
    profilePictureId: 'pfp-01',
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}
