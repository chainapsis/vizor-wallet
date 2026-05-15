import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../app_bootstrap.dart';
import '../../../core/config/network_config.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      return SwapZecStagingAddressService(
        loadWalletDbPath: getWalletDbPath,
        readNetwork: () {
          final network = ref.read(appBootstrapProvider).network;
          return network.isEmpty ? kZcashDefaultNetworkName : network;
        },
        reserveExchangeTransparentAddress:
            rust_wallet.reserveExchangeTransparentAddress,
        releaseExchangeTransparentAddress:
            rust_wallet.releaseExchangeTransparentAddress,
        releaseUnusedExchangeTransparentAddresses:
            rust_wallet.releaseUnusedExchangeTransparentAddresses,
      );
    });

typedef LoadWalletDbPath = Future<String> Function();

typedef ReadNetwork = String Function();

typedef ReserveExchangeTransparentAddress =
    Future<rust_wallet.ExchangeTransparentAddressResult> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });

typedef ReleaseExchangeTransparentAddress =
    Future<bool> Function({
      required String dbPath,
      required String accountUuid,
      required String address,
    });

typedef ReleaseUnusedExchangeTransparentAddresses =
    Future<int> Function({required String dbPath, required String accountUuid});

class SwapZecStagingAddress {
  const SwapZecStagingAddress({
    required this.address,
    required this.stagingAddressPolicy,
    required this.shieldingPolicy,
    this.transparentChildIndex,
    this.exposedAtHeight,
  });

  final String address;
  final SwapZecStagingAddressPolicy stagingAddressPolicy;
  final SwapZecShieldingPolicy shieldingPolicy;
  final int? transparentChildIndex;
  final BigInt? exposedAtHeight;

  SwapAddressPlan toAddressPlan({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required String userExternalAddress,
  }) {
    return SwapAddressPlan.fromUserInput(
      direction: direction,
      externalAsset: externalAsset,
      userExternalAddress: userExternalAddress,
      walletTransparentAddress: address,
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
    return 'Could not reserve a fresh wallet t-address. '
        'Retry after wallet sync or close older pending swaps before requesting a new quote.';
  }
}

class SwapZecStagingAddressService {
  const SwapZecStagingAddressService({
    required LoadWalletDbPath loadWalletDbPath,
    required ReadNetwork readNetwork,
    required ReserveExchangeTransparentAddress
    reserveExchangeTransparentAddress,
    required ReleaseExchangeTransparentAddress
    releaseExchangeTransparentAddress,
    required ReleaseUnusedExchangeTransparentAddresses
    releaseUnusedExchangeTransparentAddresses,
  }) : _loadWalletDbPath = loadWalletDbPath,
       _readNetwork = readNetwork,
       _reserveExchangeTransparentAddress = reserveExchangeTransparentAddress,
       _releaseExchangeTransparentAddress = releaseExchangeTransparentAddress,
       _releaseUnusedExchangeTransparentAddresses =
           releaseUnusedExchangeTransparentAddresses;

  final LoadWalletDbPath _loadWalletDbPath;
  final ReadNetwork _readNetwork;
  final ReserveExchangeTransparentAddress _reserveExchangeTransparentAddress;
  final ReleaseExchangeTransparentAddress _releaseExchangeTransparentAddress;
  final ReleaseUnusedExchangeTransparentAddresses
  _releaseUnusedExchangeTransparentAddresses;

  Future<SwapZecStagingAddress> prepareForQuote({
    required String accountUuid,
  }) async {
    try {
      final reserved = await _reserveExchangeTransparentAddress(
        dbPath: await _loadWalletDbPath(),
        network: _readNetwork(),
        accountUuid: accountUuid,
      );
      return SwapZecStagingAddress(
        address: reserved.address,
        stagingAddressPolicy:
            SwapZecStagingAddressPolicy.rotatingWalletTransparentAddress,
        shieldingPolicy: SwapZecShieldingPolicy.promptAfterArrival,
        transparentChildIndex: reserved.transparentChildIndex,
        exposedAtHeight: reserved.exposedAtHeight,
      );
    } catch (e) {
      final recovered = await _releaseUnusedReservations(accountUuid);
      if (recovered > 0) {
        try {
          final reserved = await _reserveExchangeTransparentAddress(
            dbPath: await _loadWalletDbPath(),
            network: _readNetwork(),
            accountUuid: accountUuid,
          );
          log(
            'SwapZecStagingAddressService: released $recovered unused '
            'exchange t-address reservation(s) and retried quote preparation',
          );
          return SwapZecStagingAddress(
            address: reserved.address,
            stagingAddressPolicy:
                SwapZecStagingAddressPolicy.rotatingWalletTransparentAddress,
            shieldingPolicy: SwapZecShieldingPolicy.promptAfterArrival,
            transparentChildIndex: reserved.transparentChildIndex,
            exposedAtHeight: reserved.exposedAtHeight,
          );
        } catch (retryError) {
          log(
            'SwapZecStagingAddressService: exchange t-address reservation '
            'retry failed after cleanup: $retryError',
          );
        }
      }
      log(
        'SwapZecStagingAddressService: exchange t-address reservation '
        'failed; blocking quote to avoid transparent address reuse: $e',
      );
      throw SwapZecStagingAddressUnavailableException(e);
    }
  }

  Future<bool> releaseReservation({
    required String accountUuid,
    required String address,
  }) async {
    try {
      return await _releaseExchangeTransparentAddress(
        dbPath: await _loadWalletDbPath(),
        accountUuid: accountUuid,
        address: address,
      );
    } catch (e) {
      log(
        'SwapZecStagingAddressService: failed to release exchange '
        't-address reservation: $e',
      );
      return false;
    }
  }

  Future<int> _releaseUnusedReservations(String accountUuid) async {
    try {
      return await _releaseUnusedExchangeTransparentAddresses(
        dbPath: await _loadWalletDbPath(),
        accountUuid: accountUuid,
      );
    } catch (e) {
      log(
        'SwapZecStagingAddressService: failed to release unused exchange '
        't-address reservations: $e',
      );
      return 0;
    }
  }
}
