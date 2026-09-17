import 'swap_deposit_broadcast_result.dart';

class SwapHardwareBroadcastResult extends SwapDepositBroadcastResult {
  const SwapHardwareBroadcastResult({
    required super.txHash,
    required super.status,
    super.message,
  });
}
