import 'package:flutter_test/flutter_test.dart';
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
      ),
      accountDetail: const SwapActivityAccountDetail(
        name: 'Shielded account',
        profilePictureId: 'profile-1',
      ),
    );

    expect(presentation.title, 'Swapping ...');
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
    expect(_detailValue(presentation.details, 'Account'), 'Shielded account');
    expect(
      _detailValue(presentation.details, 'USDC recipient'),
      contains('0x'),
    );
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

    expect(swapActivityShowDepositControls(SwapIntentStatus.processing), true);
    expect(
      swapActivityShowDepositControls(SwapIntentStatus.providerStatusUnknown),
      false,
    );
    expect(canRefreshSwapIntentStatus(SwapIntentStatus.complete), false);
    expect(canRefreshSwapIntentStatus(SwapIntentStatus.failed), true);
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
  String? totalFeesText,
  String? realisedSlippageText,
  String? oneClickRecipient,
  String? oneClickRefundTo,
  String? providerStatusRaw,
  String? nextAction,
  SwapProviderRefundInfo? providerRefundInfo,
  SwapFiatValueBasis? fiatValueBasis,
  DateTime? depositDeadline,
  DateTime? completedAt,
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
    oneClickRecipient: oneClickRecipient,
    oneClickRefundTo: oneClickRefundTo,
    providerStatusRaw: providerStatusRaw,
    providerRefundInfo: providerRefundInfo,
    fiatValueBasis: fiatValueBasis,
    depositDeadline: depositDeadline,
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
