import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  test('builds the support bundle for an expired external deposit', () {
    final info = swapDepositRecoveryInfoFor(
      _intent(
        direction: SwapDirection.externalToZec,
        depositAddress: '0xdeposit',
        depositMemo: 'memo 1',
        depositTxHash: '0xtx',
        depositDeadline: DateTime.utc(2026, 5, 20, 13, 20),
      ),
    );

    expect(info, isNotNull);
    expect(info!.asset, SwapAsset.usdc);
    expect(info.amountText, '150 USDC');
    // Support compares against chain time, so the zone is explicit.
    expect(info.expiredAtText, 'May 20, 2026 13:20 UTC');
    expect(
      info.bundleText.split('\n'),
      [
        'Vizor swap recovery request',
        'Network: Ethereum',
        'Asset: USDC',
        'Amount: 150 USDC',
        'One-time deposit address: 0xdeposit',
        'Memo: memo 1',
        'Deposit tx: 0xtx',
        'Deposit deadline: May 20, 2026 13:20 UTC',
      ],
    );
  });

  test('omits memo and tx lines the intent does not have', () {
    final info = swapDepositRecoveryInfoFor(
      _intent(
        direction: SwapDirection.externalToZec,
        depositAddress: '0xdeposit',
        depositDeadline: DateTime.utc(2026, 5, 20, 13, 20),
      ),
    );

    expect(info!.bundleText, isNot(contains('Memo:')));
    expect(info.bundleText, isNot(contains('Deposit tx:')));
  });

  test('has nothing to recover for ZEC-side or address-less deposits', () {
    // The app made the ZEC deposit itself; NEAR holds nothing to return.
    expect(
      swapDepositRecoveryInfoFor(
        _intent(
          direction: SwapDirection.zecToExternal,
          depositAddress: 't1deposit',
          depositDeadline: DateTime.utc(2026, 5, 20, 13, 20),
        ),
      ),
      isNull,
    );
    // No one-time address means the user never had anything to send.
    expect(
      swapDepositRecoveryInfoFor(
        _intent(
          direction: SwapDirection.externalToZec,
          depositDeadline: DateTime.utc(2026, 5, 20, 13, 20),
        ),
      ),
      isNull,
    );
  });
}

SwapIntent _intent({
  required SwapDirection direction,
  String? depositAddress,
  String? depositMemo,
  String? depositTxHash,
  DateTime? depositDeadline,
}) {
  return SwapIntent(
    id: 'swap-recovery',
    pair: 'USDC -> ZEC',
    sellAmount: '150 USDC',
    receiveEstimate: '2.137 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.expired,
    nextAction: 'Start a fresh quote',
    direction: direction,
    externalAsset: SwapAsset.usdc,
    depositAddress: depositAddress,
    depositMemo: depositMemo,
    depositTxHash: depositTxHash,
    depositDeadline: depositDeadline,
    minimumReceiveText: '2.137 ZEC',
  );
}
