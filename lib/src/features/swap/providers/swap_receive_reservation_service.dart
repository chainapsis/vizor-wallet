import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64, PlatformInt64Util;

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/swap_receive.dart' as api;
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../domain/swap_contract.dart';
import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../models/swap_intent.dart';
import 'swap_provider_config.dart';

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
    provider: ref.read(swapIntentProvider),
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

/// Persistence boundary used by the quote flow and the existing status refresh loop.
abstract interface class ReceiveReservationStore {
  Future<api.ReceiveReservation> prepare(BigInt tip);

  /// Returns the request's identity.
  Future<String> begin(PlatformInt64 reservation, DateTime deadline);
  Future<void> record(String request, SwapQuote quote);
  Future<void> reject(String request);

  /// Returns the deposit instructions the UI may show.
  Future<api.ReceiveDepositInstruction> start(String request);
  Future<List<api.ReceiveQuoteStatusRequest>> due();
  Future<void> observe(
    String request,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  );

  /// Records a refund quote's provider status on the refund key behind
  /// `refundAddress`.
  Future<void> observeRefund(
    String operation,
    String refundAddress,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  );
  Future<void> reap();
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
  Future<api.ReceiveReservation> prepare(BigInt tip) =>
      api.prepareReceiveReservation(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        liveTip: tip,
      );
  @override
  Future<String> begin(PlatformInt64 reservation, DateTime deadline) =>
      api.beginReceiveQuote(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        reservationId: reservation,
        deadlineSeconds: unixSeconds(deadline),
      );
  @override
  Future<void> record(String request, SwapQuote quote) =>
      api.recordReceiveQuote(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        requestId: request,
        operationId: quote.depositInstruction.address,
        depositMemo: quote.depositInstruction.memo,
        deadlineSeconds: unixSeconds(requireDepositDeadline(quote)),
      );

  @override
  Future<void> reject(String request) => api.rejectReceiveQuote(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    requestId: request,
  );
  @override
  Future<api.ReceiveDepositInstruction> start(String request) =>
      api.startReceiveQuote(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        requestId: request,
      );
  @override
  Future<List<api.ReceiveQuoteStatusRequest>> due() => api.receiveQuotesDue(
    dbPath: path,
    networkName: network,
    accountUuid: account,
  );
  @override
  Future<void> observe(
    String request,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) => api.observeReceiveQuote(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    requestId: request,
    status: _providerStatus(snapshot),
    funded: swapHasProviderObservedDepositEvidence(
      status: snapshot.status,
      originChainTxHash: snapshot.originChainTxHash,
      depositedAmountText: snapshot.providerRefundInfo?.depositedAmountText,
    ),
    checkedAtSeconds: unixSeconds(checkedAt),
  );
  @override
  Future<void> observeRefund(
    String operation,
    String refundAddress,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) => api.observeSwapRefundQuote(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    operationId: operation,
    refundAddress: refundAddress,
    status: _providerStatus(snapshot),
    observedAtSeconds: unixSeconds(checkedAt),
  );
  @override
  Future<void> reap() => api.reapReceiveReservations(
    dbPath: path,
    networkName: network,
    accountUuid: account,
  );
}

class SwapReceiveReservationService {
  SwapReceiveReservationService({
    required this.store,
    required this.provider,
    this.lifecycle,
    this.supportsAccount = _allAccounts,
  });
  static bool _allAccounts(String _) => true;
  final bool Function(String) supportsAccount;
  final Future<ReceiveReservationStore> Function(String account) store;
  final SwapProvider provider;
  final LedgerOperationLifecycle? lifecycle;
  final Map<String, Future<void>> _refreshing = {};

  Future<T> _run<T>(Future<T> Function() action) =>
      lifecycle?.run(action) ?? action();

  Future<api.ReceiveReservation> prepare(String account, BigInt tip) =>
      _run(() async {
        await reconcile(account);
        return (await store(account)).prepare(tip);
      });

  /// A successful quote is persisted even when its UI generation was superseded.
  /// `fetch` must put the hook on its request, so the unknown outcome is saved
  /// only when the request is about to leave the device.
  Future<SwapQuote> quote(
    String account,
    PlatformInt64 reservation,
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
        await backend.reject(sent);
      }
      rethrow;
    }
    final sent = request;
    if (sent == null) {
      throw StateError('The quote request skipped its receive reservation.');
    }
    await backend.record(sent, result);
    return SwapQuote.withLocalIdentity(result, receiveRequestId: sent);
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

  /// Shares successful activity polls with reservation bookkeeping.
  Future<void> observeStatus(
    String account,
    String operation,
    String? memo,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) async {
    if (!supportsAccount(account)) return;
    await _run(() async {
      final backend = await store(account);
      for (final request in await backend.due()) {
        if (request.operationId == operation && request.depositMemo == memo) {
          await backend.observe(request.requestId, snapshot, checkedAt);
        }
      }
    });
  }

  /// Records a refund quote's provider status on its refund key, as it is fetched.
  Future<void> observeRefundStatus(
    String account,
    String operation,
    String refundAddress,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) async {
    if (!supportsAccount(account)) return;
    await _run(
      () async => (await store(
        account,
      )).observeRefund(operation, refundAddress, snapshot, checkedAt),
    );
  }

  /// Reconciles provider records even when the activity UI considers them expired.
  Future<void> reconcile(String account) {
    if (!supportsAccount(account)) return Future.value();
    return _refreshing[account] ??=
        _run(() async {
          final backend = await store(account);
          for (final request in await backend.due()) {
            final checkedAt = DateTime.now().toUtc();
            try {
              final snapshot = await provider.getStatus(
                request.operationId,
                depositMemo: request.depositMemo,
              );
              await backend.observe(request.requestId, snapshot, checkedAt);
            } catch (error) {
              log('Swap receive reconciliation deferred: $error');
            }
          }
          await backend.reap();
        }).whenComplete(() {
          _refreshing.remove(account);
        });
  }
}
