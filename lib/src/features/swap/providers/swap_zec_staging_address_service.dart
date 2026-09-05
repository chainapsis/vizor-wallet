import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/receive_address_provider.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      return SwapZecStagingAddressService(
        loadOrchardAddress: ({required accountUuid}) {
          return ref
              .read(receiveAddressServiceProvider)
              .loadOrchardAddress(accountUuid: accountUuid);
        },
      );
    });

typedef LoadOrchardAddress =
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
    return 'Could not prepare the wallet receive address. Try again.';
  }
}

class SwapZecStagingAddressService {
  const SwapZecStagingAddressService({
    required LoadOrchardAddress loadOrchardAddress,
  }) : _loadOrchardAddress = loadOrchardAddress;

  final LoadOrchardAddress _loadOrchardAddress;

  Future<SwapZecStagingAddress> prepareForQuote({
    required String accountUuid,
  }) async {
    try {
      final address = await _loadOrchardAddress(accountUuid: accountUuid);
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
