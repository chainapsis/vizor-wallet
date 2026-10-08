import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64, PlatformInt64Util;

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/dynamic_ivk.dart' as api;
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../domain/swap_contract.dart';
import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../models/swap_intent.dart';

final swapReceiveReservationServiceProvider = Provider((ref) {
  return SwapReceiveReservationService(
    supportsAccount: (uuid) =>
        ref
            .read(accountProvider)
            .value
            ?.accounts
            .any((a) => a.uuid == uuid && !a.isHardware) ??
        false,
    lifecycle: ref.read(ledgerOperationLifecycleProvider),
    store: (account) async {
      void validate() {
        if (ref.read(appSecurityProvider).requiresUnlock ||
            !(ref
                    .read(accountProvider)
                    .value
                    ?.accounts
                    .any((a) => a.uuid == account) ??
                false)) {
          throw StateError(
            'Unlock this account before preparing a receive address.',
          );
        }
      }

      validate();
      final path = await getWalletDbPath();
      validate();
      return RustReceiveReservationStore(
        path,
        ref.read(rpcEndpointFailoverProvider).current.networkName,
        account,
      );
    },
  );
});

/// `time` in Unix seconds, as the Rust swap APIs take it.
PlatformInt64 unixSeconds(DateTime time) =>
    PlatformInt64Util.from(time.millisecondsSinceEpoch ~/ 1000);

/// The quote's deposit deadline, which swap address records require.
DateTime requireDepositDeadline(SwapQuote quote) =>
    quote.depositInstruction.deadline ??
    (throw StateError('Provider omitted the deposit deadline.'));

/// One account's private swap address records, for the quote flow and the existing
/// status refresh loop.
abstract interface class ReceiveReservationStore {
  /// Reserves an incoming address, or else a refund address. `tip` is the chain tip
  /// the quote flow fetched.
  Future<api.SwapAddress> reserve({
    required bool incoming,
    required BigInt tip,
  });

  /// Returns the request's identity.
  Future<String> begin(BigInt reservation, DateTime deadline);

  /// Records the request's accepted quote, or, given none, its definitive rejection.
  Future<void> finish(String request, SwapQuote? accepted);

  /// Returns the deposit instructions the UI may show.
  Future<api.ReceiveDeposit> start(String request);

  /// Binds a refund quote's deposit address to its reserved refund key.
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote);

  /// Records a provider status, fetched at `checkedAt`, on the swap operations with
  /// this deposit address and memo.
  Future<void> observe({
    required bool incoming,
    required String depositAddress,
    required String? memo,
    required SwapIntentSnapshot snapshot,
    required DateTime checkedAt,
  });
}

/// The fields of `snapshot` that decide when a swap key stops scanning.
api.SwapProviderStatus _providerStatus(SwapIntentSnapshot snapshot) =>
    api.SwapProviderStatus(
      status: snapshot.providerStatusRaw ?? 'UNKNOWN',
      swapType: snapshot.providerSwapType,
      refundedAmount: snapshot.refundedAmountBaseUnits,
      amountOut: snapshot.amountOutBaseUnits,
      deadlineSeconds: switch (snapshot.depositInstruction.deadline) {
        final deadline? => unixSeconds(deadline),
        null => null,
      },
    );

class RustReceiveReservationStore implements ReceiveReservationStore {
  const RustReceiveReservationStore(this.path, this.network, this.account);
  final String path;
  final String network;
  final String account;

  @override
  Future<api.SwapAddress> reserve({
    required bool incoming,
    required BigInt tip,
  }) => api.reserveSwapAddress(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    incoming: incoming,
    liveTip: tip,
  );
  @override
  Future<String> begin(BigInt reservation, DateTime deadline) =>
      api.beginReceiveQuote(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        reservationIndex: reservation,
        deadlineSeconds: unixSeconds(deadline),
      );
  @override
  Future<void> finish(String request, SwapQuote? accepted) =>
      api.finishReceiveQuote(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        requestId: request,
        accepted: switch (accepted) {
          final quote? => api.ReceiveDeposit(
            address: quote.depositInstruction.address,
            memo: quote.depositInstruction.memo,
            deadlineSeconds: unixSeconds(requireDepositDeadline(quote)),
          ),
          null => null,
        },
      );
  @override
  Future<api.ReceiveDeposit> start(String request) => api.startReceiveQuote(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    requestId: request,
  );
  @override
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote) =>
      api.recordSwapRefundQuote(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        refundIndex: refundIndex,
        depositAddress: quote.depositInstruction.address,
        deadlineSeconds: unixSeconds(requireDepositDeadline(quote)),
      );
  @override
  Future<void> observe({
    required bool incoming,
    required String depositAddress,
    required String? memo,
    required SwapIntentSnapshot snapshot,
    required DateTime checkedAt,
  }) => api.observeSwapStatus(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    incoming: incoming,
    depositAddress: depositAddress,
    depositMemo: memo,
    status: _providerStatus(snapshot),
    funded: swapHasProviderObservedDepositEvidence(
      status: snapshot.status,
      originChainTxHash: snapshot.originChainTxHash,
      depositedAmountText: snapshot.providerRefundInfo?.depositedAmountText,
    ),
    checkedAtSeconds: unixSeconds(checkedAt),
  );
}

/// Private swap address records for both swap directions. Every call that writes
/// the wallet runs inside [lifecycle], so wallet deletion waits for it.
class SwapReceiveReservationService {
  SwapReceiveReservationService({
    required this.store,
    this.lifecycle,
    this.supportsAccount = _allAccounts,
  });
  static bool _allAccounts(String _) => true;
  final bool Function(String) supportsAccount;
  final Future<ReceiveReservationStore> Function(String account) store;
  final LedgerOperationLifecycle? lifecycle;

  Future<T> _run<T>(Future<T> Function() action) =>
      lifecycle?.run(action) ?? action();

  /// Reserves the swap address `direction` quotes with: an incoming address when
  /// it pays ZEC to the wallet, else a refund address.
  Future<api.SwapAddress> reserve(
    String account,
    SwapDirection direction,
    BigInt tip,
  ) => _run(
    () async =>
        (await store(account)).reserve(incoming: !direction.sendsZec, tip: tip),
  );

  /// Quotes incoming `reservation`. A successful quote is persisted even when its UI
  /// generation was superseded. `fetch` must put the hook on its request, so the
  /// unknown outcome is saved only when the request is about to leave the device.
  Future<SwapQuote> quote(
    String account,
    BigInt reservation,
    Future<SwapQuote> Function(SwapQuoteSendHook beforeSend) fetch,
  ) => _run(() async {
    final backend = await store(account);
    String? request;
    late final SwapQuote result;
    try {
      result = await fetch((deadline) async {
        request = await backend.begin(reservation, deadline);
      });
    } catch (error) {
      // Only an explicit quote validation rejection establishes that no deposit
      // instructions were returned. Timeouts and malformed successes stay unknown.
      final sent = request;
      if (sent != null &&
          error is OneClickApiException &&
          error.operation == 'quote' &&
          (error.statusCode == 400 || error.statusCode == 422)) {
        await backend.finish(sent, null);
      }
      rethrow;
    }
    final sent = request;
    if (sent == null) {
      throw StateError('The quote request skipped its receive reservation.');
    }
    await backend.finish(sent, result);
    return SwapQuote.withLocalIdentity(result, receiveRequestId: sent);
  });

  /// Quotes with the refund key at `refundIndex`, and records the quote before it is
  /// returned, because funding requires that record. The quote must be address-only:
  /// the funding transaction's only transparent output is the deposit.
  Future<SwapQuote> quoteRefund(
    String account,
    BigInt refundIndex,
    Future<SwapQuote> Function() fetch,
  ) => _run(() async {
    final backend = await store(account);
    final quote = await fetch();
    if (quote.depositInstruction.memo?.isNotEmpty ?? false) {
      throw StateError('Swap receiving requires an address-only ZEC deposit');
    }
    await backend.recordRefund(refundIndex, quote);
    return SwapQuote.withLocalIdentity(quote, swapRefundIndex: refundIndex);
  });

  /// Locks the quote's reservation before its deposit instructions are shown, and
  /// checks that they are the ones the wallet saved.
  Future<void> start(String account, SwapQuote quote) async {
    // Only incoming quotes from supported accounts reserve a request.
    final request = quote.receiveRequestId;
    if (request == null) return;
    await _run(() async {
      final deposit = await (await store(account)).start(request);
      if (deposit.address != quote.depositInstruction.address ||
          deposit.memo != quote.depositInstruction.memo) {
        throw StateError('These deposit instructions were not saved.');
      }
    });
  }

  /// Shares a successful activity poll, fetched at `checkedAt`, with the wallet,
  /// which records it on the swap's private address, if it has one, and reclaims
  /// what that makes reclaimable. It makes no provider requests of its own.
  Future<void> observeStatus(
    String account, {
    required SwapDirection direction,
    required String depositAddress,
    required String? memo,
    required SwapIntentSnapshot snapshot,
    required DateTime checkedAt,
  }) async {
    if (!supportsAccount(account)) return;
    await _run(
      () async => (await store(account)).observe(
        incoming: !direction.sendsZec,
        depositAddress: depositAddress,
        memo: memo,
        snapshot: snapshot,
        checkedAt: checkedAt,
      ),
    );
  }
}
