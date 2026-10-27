import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/settings/widgets/near_swap_privacy_turn_off.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

final _now = DateTime.utc(2026, 10, 27, 12);
const _payoutTx =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

SwapIntent _swap({
  required SwapDirection direction,
  required SwapIntentStatus status,
  bool privateAddress = true,
  bool startPending = false,
  DateTime? completedAt,
}) => SwapIntent(
  id: 'swap',
  pair: 'USDC -> ZEC',
  sellAmount: '100 USDC',
  receiveEstimate: '2 ZEC',
  provider: 'NEAR Intents',
  status: status,
  nextAction: 'Next action',
  direction: direction,
  externalAsset: SwapAsset.usdc,
  destinationChainTxHash: _payoutTx,
  privateAddress: privateAddress,
  startPending: startPending,
  completedAt: completedAt,
);

rust_sync.TransactionInfo _tx(String txidHex) => rust_sync.TransactionInfo(
  txidHex: txidHex,
  minedHeight: BigInt.one,
  expiredUnmined: false,
  accountBalanceDelta: 0,
  fee: BigInt.zero,
  feeState: rust_sync.TransactionFeeState.notApplicable,
  detailsComplete: true,
  provisional: false,
  amountIncludesFee: false,
  blockTime: BigInt.from(1800000000),
  isTransparent: false,
  txKind: 'received',
  displayAmount: BigInt.one,
  displayPool: 'shielded',
  createdTime: BigInt.from(1800000000),
);

Future<NearSwapPrivacyPendingSwaps> _pending(
  List<SwapIntent> swaps, {
  bool payoutFound = false,
}) => nearSwapPrivacyPendingSwapsIn(
  [for (final swap in swaps) ('account', swap)],
  loadTransaction: ({required accountUuid, required walletTxid}) async =>
      payoutFound ? _tx(walletTxid) : null,
  now: _now,
);

void main() {
  test('an unfinished private payout or refund is pending', () async {
    expect(
      await _pending([
        _swap(
          direction: SwapDirection.externalToZec,
          status: SwapIntentStatus.processing,
        ),
      ]),
      (payout: true, refund: false),
    );
    expect(
      await _pending([
        _swap(
          direction: SwapDirection.zecToExternal,
          status: SwapIntentStatus.awaitingDeposit,
        ),
      ]),
      (payout: false, refund: true),
    );
  });

  test('a completed payout is pending until the wallet finds it', () async {
    final completed = _swap(
      direction: SwapDirection.externalToZec,
      status: SwapIntentStatus.complete,
      completedAt: _now.subtract(const Duration(hours: 1)),
    );
    expect(await _pending([completed]), (payout: true, refund: false));
    expect(await _pending([completed], payoutFound: true), (
      payout: false,
      refund: false,
    ));
  });

  test('ordinary, unstarted, finished and old swaps are not pending', () async {
    expect(
      await _pending([
        _swap(
          direction: SwapDirection.externalToZec,
          status: SwapIntentStatus.processing,
          privateAddress: false,
        ),
        _swap(
          direction: SwapDirection.externalToZec,
          status: SwapIntentStatus.processing,
          startPending: true,
        ),
        _swap(
          direction: SwapDirection.zecToExternal,
          status: SwapIntentStatus.refunded,
        ),
        _swap(
          direction: SwapDirection.externalToZec,
          status: SwapIntentStatus.complete,
          completedAt: _now.subtract(const Duration(days: 8)),
        ),
      ]),
      (payout: false, refund: false),
    );
  });

  test('the warning names each pending kind and that nothing is lost', () {
    expect(nearSwapPrivacyTurnOffLines((payout: false, refund: false)), isNull);
    expect(nearSwapPrivacyTurnOffLines((payout: true, refund: true)), [
      kNearSwapPrivacyTurnOffPayoutCopy,
      kNearSwapPrivacyTurnOffRefundCopy,
      kNearSwapPrivacyTurnOffKeptCopy,
    ]);
  });
}
