import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/receive_address_provider.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      return SwapZecStagingAddressService(
        reserveSwapAddress: ({required accountUuid, required direction}) async {
          if (!rust_sync.swapReceivingPocEnabled()) return null;
          final liveTip = await ref
              .read(rpcEndpointFailoverProvider.notifier)
              .getLatestBlockHeight();
          final dbPath = await getWalletDbPath();
          final network = ref
              .read(rpcEndpointFailoverProvider)
              .current
              .networkName;
          final address = await rust_sync.reserveSwapReceivingAddress(
            dbPath: dbPath,
            network: network,
            liveTip: liveTip,
            accountUuid: accountUuid,
            refund: direction.sendsZec,
          );
          return SwapZecStagingAddress(
            address: address.address,
            receivingIndex: address.index,
          );
        },
        reserveFreshOrchardAddress: ({required accountUuid}) {
          return ref
              .read(receiveAddressServiceProvider)
              .reserveOrchardAddress(accountUuid: accountUuid);
        },
      );
    });

typedef ReserveOrchardAddress =
    Future<String> Function({required String accountUuid});

typedef ReserveSwapAddress =
    Future<SwapZecStagingAddress?> Function({
      required String accountUuid,
      required SwapDirection direction,
    });

class SwapZecStagingAddress {
  const SwapZecStagingAddress({required this.address, this.receivingIndex});

  final String address;
  final BigInt? receivingIndex;

  SwapAddressPlan toAddressPlan({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required String userExternalAddress,
  }) {
    return SwapAddressPlan.fromUserInput(
      direction: direction,
      externalAsset: externalAsset,
      userExternalAddress: userExternalAddress,
      walletZecAddress: address,
    );
  }
}

class SwapZecStagingAddressUnavailableException implements Exception {
  const SwapZecStagingAddressUnavailableException(this.cause);

  final Object cause;

  @override
  String toString() {
    return 'Could not prepare a fresh wallet receive address. '
        'Retry after wallet sync or close older pending swaps before requesting a new quote.';
  }
}

class SwapZecStagingAddressService {
  const SwapZecStagingAddressService({
    required ReserveOrchardAddress reserveFreshOrchardAddress,
    ReserveSwapAddress? reserveSwapAddress,
  }) : _reserveFreshOrchardAddress = reserveFreshOrchardAddress,
       _reserveSwapAddress = reserveSwapAddress;

  final ReserveOrchardAddress _reserveFreshOrchardAddress;
  final ReserveSwapAddress? _reserveSwapAddress;

  Future<SwapZecStagingAddress> prepareForQuote({
    required String accountUuid,
    SwapDirection direction = SwapDirection.zecToExternal,
  }) async {
    try {
      // An enabled POC fails closed on reservation errors, including hardware accounts.
      final swapAddress = await _reserveSwapAddress?.call(
        accountUuid: accountUuid,
        direction: direction,
      );
      if (swapAddress != null) return swapAddress;
      final address = await _reserveFreshOrchardAddress(
        accountUuid: accountUuid,
      );
      return SwapZecStagingAddress(address: address);
    } catch (e) {
      log(
        'SwapZecStagingAddressService: Orchard receive address preparation '
        'failed; blocking quote: $e',
      );
      throw SwapZecStagingAddressUnavailableException(e);
    }
  }
}
