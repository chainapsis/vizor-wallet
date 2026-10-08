import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/receive_address_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/dynamic_ivk.dart' show ReceiveError;
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import 'swap_receive_reservation_service.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      final reservations = ref.read(swapReceiveReservationServiceProvider);
      return SwapZecStagingAddressService(
        reserveSwapAddress: ({required accountUuid, required direction}) async {
          if (!ref.read(nearSwapPrivacyProvider) ||
              ref
                  .read(accountProvider.notifier)
                  .isHardwareAccount(accountUuid)) {
            return null;
          }
          final liveTip = await ref
              .read(rpcEndpointFailoverProvider.notifier)
              .getLatestBlockHeight();
          final address = await reservations.reserve(
            accountUuid,
            direction,
            liveTip,
          );
          return SwapZecStagingAddress(
            address: address.address,
            refundIndex: address.refundIndex,
            reservationIndex: address.reservationIndex,
          );
        },
        reserveFreshOrchardAddress: ({required accountUuid}) {
          return ref
              .read(receiveAddressServiceProvider)
              .reserveOrchardAddress(accountUuid: accountUuid);
        },
        reservations: reservations,
      );
    });

typedef ReserveOrchardAddress =
    Future<String> Function({required String accountUuid});

typedef ReserveSwapAddress =
    Future<SwapZecStagingAddress?> Function({
      required String accountUuid,
      required SwapDirection direction,
    });

/// Builds and sends a quote request, putting `beforeSend` on it when given.
typedef FetchSwapQuote =
    Future<SwapQuote> Function(SwapQuoteSendHook? beforeSend);

class SwapZecStagingAddress {
  const SwapZecStagingAddress({
    required this.address,
    this.refundIndex,
    this.reservationIndex,
  });

  final String address;

  /// The reserved refund key's index. Set only for refund addresses.
  final BigInt? refundIndex;

  /// The incoming draft reservation's index. Set only for incoming addresses.
  final BigInt? reservationIndex;

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
    SwapReceiveReservationService? reservations,
  }) : _reserveFreshOrchardAddress = reserveFreshOrchardAddress,
       _reserveSwapAddress = reserveSwapAddress,
       _reservations = reservations;

  final ReserveOrchardAddress _reserveFreshOrchardAddress;
  final ReserveSwapAddress? _reserveSwapAddress;
  final SwapReceiveReservationService? _reservations;

  /// Quotes with `address`, carrying its local key identity: an incoming quote is
  /// saved with its reservation, and a refund quote recorded on its refund key (see
  /// [SwapReceiveReservationService]).
  Future<SwapQuote> quote(
    String account,
    SwapZecStagingAddress address,
    FetchSwapQuote fetch,
  ) {
    final reservations = _reservations;
    if (reservations != null) {
      if (address.reservationIndex case final reservation?) {
        return reservations.quote(account, reservation, fetch);
      }
      if (address.refundIndex case final refundIndex?) {
        return reservations.quoteRefund(
          account,
          refundIndex,
          () => fetch(null),
        );
      }
    }
    return fetch(null);
  }

  Future<void> startQuote(String account, SwapQuote quote) async {
    await _reservations?.start(account, quote);
  }

  Future<SwapZecStagingAddress> prepareForQuote({
    required String accountUuid,
    SwapDirection direction = SwapDirection.zecToExternal,
  }) async {
    try {
      // With NEAR swap privacy on, a software account fails closed on reservation
      // errors. Hardware accounts get no swap address and use an ordinary one.
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
