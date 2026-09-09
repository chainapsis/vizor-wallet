import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/receive_address_provider.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      return SwapZecStagingAddressService(
        reserveFreshOrchardAddress: ({required accountUuid}) {
          return ref
              .read(receiveAddressServiceProvider)
              .reserveOrchardAddress(accountUuid: accountUuid);
        },
      );
    });

typedef ReserveOrchardAddress =
    Future<String> Function({required String accountUuid});

class SwapZecStagingAddress {
  const SwapZecStagingAddress({required this.address});

  final String address;

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
  }) : _reserveFreshOrchardAddress = reserveFreshOrchardAddress;

  final ReserveOrchardAddress _reserveFreshOrchardAddress;

  Future<SwapZecStagingAddress> prepareForQuote({
    required String accountUuid,
  }) async {
    try {
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
