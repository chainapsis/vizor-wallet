import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;

import '../../../../main.dart' show log;
import '../../../providers/receive_address_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/swap_receive.dart' as rust_swap;
import '../../../rust/wallet/swap_receiving/receive.dart';
import '../domain/swap_address_plan.dart';
import '../domain/swap_contract.dart';
import 'swap_receive_reservation_service.dart';

final swapZecStagingAddressServiceProvider =
    Provider<SwapZecStagingAddressService>((ref) {
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
          if (!direction.sendsZec) {
            final address = await ref
                .read(swapReceiveReservationServiceProvider)
                .prepare(accountUuid, liveTip);
            return SwapZecStagingAddress(
              address: address.address,
              reservationId: address.id,
            );
          }
          final address = await rust_swap.reserveSwapReceivingAddress(
            dbPath: await getWalletDbPath(),
            networkName: ref
                .read(rpcEndpointFailoverProvider)
                .current
                .networkName,
            accountUuid: accountUuid,
            liveTip: liveTip,
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
        reservations: ref.read(swapReceiveReservationServiceProvider),
        recordRefundQuote: (account, refundIndex, quote) async {
          final deadline = requireDepositDeadline(quote);
          await rust_swap.recordSwapRefundQuote(
            dbPath: await getWalletDbPath(),
            networkName: ref
                .read(rpcEndpointFailoverProvider)
                .current
                .networkName,
            accountUuid: account,
            refundIndex: refundIndex,
            depositAddress: quote.depositInstruction.address,
            deadlineSeconds: unixSeconds(deadline),
          );
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

/// Builds and sends a quote request, putting `beforeSend` on it when given.
typedef FetchSwapQuote =
    Future<SwapQuote> Function(SwapQuoteSendHook? beforeSend);

/// Binds a refund quote's deposit address to its reserved refund key.
typedef RecordRefundQuote =
    Future<void> Function(String account, BigInt refundIndex, SwapQuote quote);

class SwapZecStagingAddress {
  const SwapZecStagingAddress({
    required this.address,
    this.receivingIndex,
    this.reservationId,
  });

  final String address;

  /// The reserved refund key's index. Set only for refund addresses.
  final BigInt? receivingIndex;

  /// The incoming draft reservation. Set only for incoming addresses.
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
    SwapReceiveReservationService? reservations,
    RecordRefundQuote? recordRefundQuote,
  }) : _reserveFreshOrchardAddress = reserveFreshOrchardAddress,
       _reserveSwapAddress = reserveSwapAddress,
       _reservations = reservations,
       _recordRefundQuote = recordRefundQuote;

  final ReserveOrchardAddress _reserveFreshOrchardAddress;
  final ReserveSwapAddress? _reserveSwapAddress;
  final SwapReceiveReservationService? _reservations;
  final RecordRefundQuote? _recordRefundQuote;

  /// Quotes with `address`, carrying its local key identity. An incoming quote is
  /// saved with its reservation. A refund quote for a reserved refund key is
  /// recorded before it is returned, because funding requires that record, and
  /// must be address-only: the funding transaction's only transparent output is the
  /// deposit.
  Future<SwapQuote> quote(
    String account,
    SwapZecStagingAddress address,
    FetchSwapQuote fetch,
  ) async {
    final reservation = address.reservationId;
    final reservations = _reservations;
    if (reservation != null && reservations != null) {
      return reservations.quote(account, reservation, fetch);
    }
    final quote = await fetch(null);
    final refundIndex = address.receivingIndex;
    if (refundIndex == null) return quote;
    if (quote.depositInstruction.memo?.isNotEmpty ?? false) {
      throw StateError('Swap receiving requires an address-only ZEC deposit');
    }
    await _recordRefundQuote?.call(account, refundIndex, quote);
    return SwapQuote.withLocalIdentity(quote, swapRefundIndex: refundIndex);
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
