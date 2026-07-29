import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/sync_provider.dart';
import '../../migration/providers/ironwood_migration_announcement_provider.dart';
import '../../../providers/receive_address_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

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
    return _ref
        .read(syncProvider.notifier)
        .runWithAuthoritativeSpendable(
          accountUuid: accountUuid,
          operation: () async {
            final dbPath = await getWalletDbPath();
            final endpoint = _ref.read(rpcEndpointProvider);
            final spendableZatoshi = _ref.read(
              ironwoodMigrationAwareDisplaySpendableProvider(accountUuid),
            );
            final estimateAddress = await _ref
                .read(receiveAddressServiceProvider)
                .loadTransparentReceiveAddress(accountUuid: accountUuid);

            log(
              'SwapMaxAmount: estimate begin account=$accountUuid '
              'estimateAddress=${_shortSwapValue(estimateAddress)} '
              'spendable=$spendableZatoshi',
            );
            final amountZatoshi = await findMaxZecAmountByFeeProbe(
              spendableZatoshi: spendableZatoshi,
              canSend: (amountZatoshi) async {
                try {
                  await rust_sync.estimateFee(
                    dbPath: dbPath,
                    network: endpoint.networkName,
                    accountUuid: accountUuid,
                    toAddress: estimateAddress,
                    amountZatoshi: amountZatoshi,
                    memo: null,
                  );
                  return true;
                } catch (e) {
                  if (_isInsufficientFundsError(e)) return false;
                  rethrow;
                }
              },
            );
            log('SwapMaxAmount: estimate complete amount=$amountZatoshi');
            return amountZatoshi;
          },
        );
  }
}

@visibleForTesting
Future<BigInt> findMaxZecAmountByFeeProbe({
  required BigInt spendableZatoshi,
  required Future<bool> Function(BigInt amountZatoshi) canSend,
}) async {
  if (spendableZatoshi <= BigInt.zero) return BigInt.zero;

  var low = BigInt.zero;
  var high = spendableZatoshi;
  while (low < high) {
    final mid = (low + high + BigInt.one) ~/ BigInt.from(2);
    if (await canSend(mid)) {
      low = mid;
    } else {
      high = mid - BigInt.one;
    }
  }
  return low;
}

bool _isInsufficientFundsError(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('insufficient balance') ||
      msg.contains('insufficient funds');
}

String _shortSwapValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '-';
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 7)}...${trimmed.substring(trimmed.length - 6)}';
}
