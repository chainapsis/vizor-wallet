import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/receive_address_provider.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      return SwapZecStagingAddressService(
        loadShieldedAddress: ({required accountUuid}) {
          return _loadSwapShieldedRecipientAddress(
            ref,
            accountUuid: accountUuid,
          );
        },
      );
    });

typedef LoadShieldedAddress =
    Future<String> Function({required String accountUuid});

Future<String> _loadSwapShieldedRecipientAddress(
  Ref ref, {
  required String accountUuid,
}) async {
  final receiveAddressService = ref.read(receiveAddressServiceProvider);
  if (ref.read(accountProvider.notifier).isHardwareAccount(accountUuid)) {
    return receiveAddressService.loadShieldedAddress(accountUuid: accountUuid);
  }

  try {
    return await receiveAddressService.renewShieldedAddress(
      accountUuid: accountUuid,
    );
  } catch (e) {
    if (!_isSaplingReceiverUnsupported(e)) rethrow;
    log(
      'SwapZecStagingAddressService: diversified Sapling+Orchard UA '
      'generation is unavailable; using current shielded UA: $e',
    );
    return receiveAddressService.loadShieldedAddress(accountUuid: accountUuid);
  }
}

bool _isSaplingReceiverUnsupported(Object error) {
  return error.toString().contains(
    'Unified Address generation does not yet support receivers of type Sapling',
  );
}

class SwapZecStagingAddress {
  const SwapZecStagingAddress({
    required this.address,
    required this.stagingAddressPolicy,
    required this.shieldingPolicy,
  });

  final String address;
  final SwapZecStagingAddressPolicy stagingAddressPolicy;
  final SwapZecShieldingPolicy shieldingPolicy;

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
      zecStagingAddressPolicy: stagingAddressPolicy,
      zecShieldingPolicy: shieldingPolicy,
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
    required LoadShieldedAddress loadShieldedAddress,
  }) : _loadShieldedAddress = loadShieldedAddress;

  final LoadShieldedAddress _loadShieldedAddress;

  Future<SwapZecStagingAddress> prepareForQuote({
    required String accountUuid,
  }) async {
    return _prepareShieldedRecipient(accountUuid);
  }

  Future<SwapZecStagingAddress> _prepareShieldedRecipient(
    String accountUuid,
  ) async {
    try {
      final address = await _loadShieldedAddress(accountUuid: accountUuid);
      return SwapZecStagingAddress(
        address: address,
        stagingAddressPolicy:
            SwapZecStagingAddressPolicy.rotatingWalletUnifiedAddress,
        shieldingPolicy: SwapZecShieldingPolicy.notRequired,
      );
    } catch (e) {
      log(
        'SwapZecStagingAddressService: shielded receive address preparation '
        'failed; blocking quote: $e',
      );
      throw SwapZecStagingAddressUnavailableException(e);
    }
  }
}
