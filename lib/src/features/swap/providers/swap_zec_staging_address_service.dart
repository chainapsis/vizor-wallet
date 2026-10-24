import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/receive_address_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import 'swap_receive_reservation_service.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
      final reservations = ref.read(swapReceiveReservationServiceProvider);
      return SwapZecStagingAddressService(
        usesSwapAddress: (accountUuid) =>
            ref.read(nearSwapPrivacyProvider) &&
            !ref.read(accountProvider.notifier).isHardwareAccount(accountUuid),
        reserveSwapAddress: ({required accountUuid, required direction}) async {
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

/// Whether quotes on `accountUuid` use a private swap address.
typedef UsesSwapAddress = bool Function(String accountUuid);

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

  /// Whether this is a private swap address, holding a reserved key, rather
  /// than an ordinary one.
  bool get isPrivate => refundIndex != null || reservationIndex != null;

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
  const SwapZecStagingAddressUnavailableException(
    this.cause, {
    this.privateAddress = false,
  });

  final Object cause;

  /// Whether reserving a private swap address failed. Its text leaves out
  /// closing older swaps, which frees no private address. Running out of them
  /// has its own wallet error.
  final bool privateAddress;

  /// The quote error shown for this failure, worded as before private swaps
  /// for an ordinary address.
  @override
  String toString() {
    if (privateAddress) {
      return 'Could not prepare a fresh wallet receive address. '
          'Try again after wallet sync.';
    }
    return 'Could not prepare a fresh wallet receive address. '
        'Retry after wallet sync or close older pending swaps before requesting a new quote.';
  }
}

class SwapZecStagingAddressService {
  const SwapZecStagingAddressService({
    required ReserveOrchardAddress reserveFreshOrchardAddress,
    ReserveSwapAddress? reserveSwapAddress,
    UsesSwapAddress? usesSwapAddress,
    SwapReceiveReservationService? reservations,
  }) : _reserveFreshOrchardAddress = reserveFreshOrchardAddress,
       _reserveSwapAddress = reserveSwapAddress,
       _usesSwapAddress = usesSwapAddress,
       _reservations = reservations;

  final ReserveOrchardAddress _reserveFreshOrchardAddress;
  final ReserveSwapAddress? _reserveSwapAddress;
  final UsesSwapAddress? _usesSwapAddress;
  final SwapReceiveReservationService? _reservations;

  /// Whether [prepareForQuote] tries a private swap address for `accountUuid`
  /// rather than going straight to an ordinary one. Without a
  /// `usesSwapAddress` check, it does whenever it can reserve one.
  bool usesSwapAddress(String accountUuid) =>
      _reserveSwapAddress != null &&
      (_usesSwapAddress?.call(accountUuid) ?? true);

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
    var privateAddress = true;
    try {
      // With NEAR swap privacy on, a software account fails closed on reservation
      // errors. Hardware accounts get no swap address and use an ordinary one.
      final swapAddress = usesSwapAddress(accountUuid)
          ? await _reserveSwapAddress?.call(
              accountUuid: accountUuid,
              direction: direction,
            )
          : null;
      if (swapAddress != null) return swapAddress;
      privateAddress = false;
      final address = await _reserveFreshOrchardAddress(
        accountUuid: accountUuid,
      );
      return SwapZecStagingAddress(address: address);
    } catch (e) {
      log(
        'SwapZecStagingAddressService: Orchard receive address preparation '
        'failed; blocking quote: $e',
      );
      throw SwapZecStagingAddressUnavailableException(
        e,
        privateAddress: privateAddress,
      );
    }
  }
}
