import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;

import '../../../../main.dart' show log;
import '../../../providers/receive_address_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/swap_receiving/receive.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import 'swap_receive_reservation_service.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      return SwapZecStagingAddressService(
        reserveSwapAddress: ({required accountUuid, required direction}) async {
          if (!rust_sync.nearSwapPrivacyEnabled()) return null;
          final accounts = ref.read(accountProvider).value?.accounts;
          if (accounts?.any(
                (account) => account.uuid == accountUuid && account.isHardware,
              ) ??
              false) {
            return null;
          }
          final liveTip = await ref
              .read(rpcEndpointFailoverProvider.notifier)
              .getLatestBlockHeight();
          final dbPath = await getWalletDbPath();
          final network = ref
              .read(rpcEndpointFailoverProvider)
              .current
              .networkName;
          if (!direction.sendsZec) {
            final address = await ref
                .read(swapReceiveReservationServiceProvider)
                .prepare(accountUuid, liveTip);
            return SwapZecStagingAddress(
              address: address.address,
              receivingIndex: address.index,
              reservationId: address.id,
            );
          }
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
        quoteWithReservation: (account, address, fetch) =>
            address.reservationId == null
            ? fetch()
            : ref
                  .read(swapReceiveReservationServiceProvider)
                  .quote(account, address.reservationId!, fetch),
        startQuote: (account, quote) => ref
            .read(swapReceiveReservationServiceProvider)
            .start(account, quote),
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
  const SwapZecStagingAddress({
    required this.address,
    this.receivingIndex,
    this.reservationId,
  });

  final String address;
  final BigInt? receivingIndex;
  final PlatformInt64? reservationId;

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
    if (cause is ReceiveError) return (cause as ReceiveError).message;
    return 'Could not prepare a fresh wallet receive address. '
        'Try again after wallet sync.';
  }
}

class SwapZecStagingAddressService {
  const SwapZecStagingAddressService({
    required ReserveOrchardAddress reserveFreshOrchardAddress,
    ReserveSwapAddress? reserveSwapAddress,
    Future<SwapQuote> Function(
      String,
      SwapZecStagingAddress,
      Future<SwapQuote> Function(),
    )?
    quoteWithReservation,
    Future<void> Function(String, SwapQuote)? startQuote,
  }) : _reserveFreshOrchardAddress = reserveFreshOrchardAddress,
       _reserveSwapAddress = reserveSwapAddress,
       _quoteWithReservation = quoteWithReservation,
       _startQuote = startQuote;

  final ReserveOrchardAddress _reserveFreshOrchardAddress;
  final ReserveSwapAddress? _reserveSwapAddress;
  final Future<SwapQuote> Function(
    String,
    SwapZecStagingAddress,
    Future<SwapQuote> Function(),
  )?
  _quoteWithReservation;
  final Future<void> Function(String, SwapQuote)? _startQuote;

  Future<SwapQuote> quote(
    String account,
    SwapZecStagingAddress address,
    Future<SwapQuote> Function() fetch,
  ) => _quoteWithReservation?.call(account, address, fetch) ?? fetch();

  Future<void> startQuote(String account, SwapQuote quote) async {
    await _startQuote?.call(account, quote);
  }

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
