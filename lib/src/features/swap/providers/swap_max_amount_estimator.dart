import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/receive_address_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/legacy_v5_pczt_mode.dart';

final swapMaxAmountEstimatorProvider = Provider<SwapMaxAmountEstimator>((ref) {
  return RustSwapMaxAmountEstimator(ref);
});

abstract interface class SwapMaxAmountEstimator {
  Future<BigInt> estimateMaxZecSellAmount({required String accountUuid});
}

class RustSwapMaxAmountEstimator implements SwapMaxAmountEstimator {
  const RustSwapMaxAmountEstimator(this._ref);

  final Ref _ref;

  @override
  Future<BigInt> estimateMaxZecSellAmount({required String accountUuid}) async {
    final dbPath = await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointProvider);
    final sync = (_ref.read(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    final spendableZatoshi = sync.spendableBalance;
    final estimateAddress = await _ref
        .read(receiveAddressServiceProvider)
        .loadTransparentReceiveAddress(accountUuid: accountUuid);
    final legacyV5Pczt = shouldAllowLegacyV5PcztFallbackForAccount(
      accountUuid: accountUuid,
      isHardwareAccount: _ref.read(accountProvider.notifier).isHardwareAccount,
    );

    log(
      'SwapMaxAmount: estimate begin account=$accountUuid '
      'estimateAddress=${_shortSwapValue(estimateAddress)} '
      'spendable=$spendableZatoshi legacyV5Pczt=$legacyV5Pczt',
    );
    final estimate = await rust_sync.estimateSendMax(
      dbPath: dbPath,
      network: endpoint.walletNetworkName,
      accountUuid: accountUuid,
      toAddress: estimateAddress,
      memo: null,
      legacyV5Pczt: legacyV5Pczt,
    );
    final amountZatoshi = estimate.amountZatoshi;
    log('SwapMaxAmount: estimate complete amount=$amountZatoshi');
    return amountZatoshi;
  }
}

String _shortSwapValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '-';
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 7)}...${trimmed.substring(trimmed.length - 6)}';
}
