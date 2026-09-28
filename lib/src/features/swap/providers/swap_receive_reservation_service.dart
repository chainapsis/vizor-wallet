import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64, PlatformInt64Util;

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/swap_receive.dart' as api;
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../domain/swap_contract.dart';
import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import '../models/swap_intent.dart';
import 'swap_provider_config.dart';

final swapReceiveReservationServiceProvider = Provider((ref) {
  return SwapReceiveReservationService(
    enabled: () => true,
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
        if (ref.read(networkPrivacyProvider).torEnabled) {
          throw StateError(
            'Private swap recovery does not support Tor in this test build.',
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
        ref.read(rpcEndpointFailoverProvider).current.lightwalletdUrl,
      );
    },
  );
});

/// Persistence boundary used by the quote flow and the existing status refresh loop.
abstract interface class ReceiveReservationStore {
  Future<api.ReceiveReservation> prepare(BigInt tip);
  Future<void> begin(PlatformInt64 reservation, String request);
  Future<void> record(String request, SwapQuote quote);
  Future<void> reject(String request);
  Future<void> start(String operation);
  Future<List<api.ReceiveQuoteStatusRequest>> due();
  Future<void> observe(
    String request,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  );
  Future<void> reap();
}

class RustReceiveReservationStore implements ReceiveReservationStore {
  const RustReceiveReservationStore(
    this.path,
    this.network,
    this.account,
    this.lightwalletdUrl,
  );
  final String path;
  final String network;
  final String account;
  final String lightwalletdUrl;

  @override
  Future<api.ReceiveReservation> prepare(BigInt tip) =>
      api.prepareReceiveReservation(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        liveTip: tip,
        lightwalletdUrl: lightwalletdUrl,
      );
  @override
  Future<void> begin(PlatformInt64 reservation, String request) =>
      api.beginReceiveQuote(
        dbPath: path,
        networkName: network,
        accountUuid: account,
        reservationId: reservation,
        requestId: request,
      );
  @override
  Future<void> record(String request, SwapQuote quote) {
    final deadline = quote.depositInstruction.deadline;
    if (deadline == null) {
      throw StateError('Provider omitted the deposit deadline.');
    }
    return api.recordReceiveQuote(
      dbPath: path,
      networkName: network,
      accountUuid: account,
      requestId: request,
      operationId: quote.depositInstruction.address,
      depositMemo: quote.depositInstruction.memo,
      deadlineSeconds: PlatformInt64Util.from(
        deadline.millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }

  @override
  Future<void> reject(String request) => api.rejectReceiveQuote(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    requestId: request,
  );
  @override
  Future<void> start(String operation) => api.startReceiveQuote(
    dbPath: path,
    networkName: network,
    accountUuid: account,
    operationId: operation,
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
    status: snapshot.providerStatusRaw ?? 'UNKNOWN',
    funded: swapHasProviderObservedDepositEvidence(
      status: snapshot.status,
      originChainTxHash: snapshot.originChainTxHash,
      depositedAmountText: snapshot.providerRefundInfo?.depositedAmountText,
    ),
    checkedAtSeconds: PlatformInt64Util.from(
      checkedAt.millisecondsSinceEpoch ~/ 1000,
    ),
  );
  @override
  Future<void> reap() async {
    await api.reapReceiveReservations(
      lightwalletdUrl: lightwalletdUrl,
      dbPath: path,
      networkName: network,
      accountUuid: account,
    );
  }
}

class SwapReceiveReservationService {
  SwapReceiveReservationService({
    required this.enabled,
    required this.store,
    required this.provider,
    this.lifecycle,
    this.supportsAccount = _allAccounts,
  });
  static bool _allAccounts(String _) => true;
  final bool Function(String) supportsAccount;
  final bool Function() enabled;
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
  Future<SwapQuote> quote(
    String account,
    PlatformInt64 reservation,
    Future<SwapQuote> Function() fetch,
  ) => _run(() async {
    final backend = await store(account);
    final random = Random.secure();
    final request = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await backend.begin(reservation, request);
    late final SwapQuote result;
    try {
      result = await fetch();
    } catch (error) {
      // Only an explicit quote validation rejection establishes that no deposit
      // instructions were returned. Timeouts and malformed successes stay unknown.
      if (error is OneClickApiException &&
          error.operation == 'quote' &&
          (error.statusCode == 400 || error.statusCode == 422)) {
        await backend.reject(request);
      }
      rethrow;
    }
    await backend.record(request, result);
    return result;
  });

  Future<void> start(String account, SwapQuote quote) async {
    if (!enabled() || !supportsAccount(account) || quote.direction.sendsZec) {
      return;
    }
    await _run(
      () async =>
          (await store(account)).start(quote.depositInstruction.address),
    );
  }

  /// Shares successful activity polls with reservation bookkeeping.
  Future<void> observeStatus(
    String account,
    String operation,
    String? memo,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) async {
    if (!enabled() || !supportsAccount(account)) return;
    await _run(() async {
      final backend = await store(account);
      for (final request in await backend.due()) {
        if (request.operationId == operation && request.depositMemo == memo) {
          await backend.observe(request.requestId, snapshot, checkedAt);
        }
      }
    });
  }

  /// Reconciles provider records even when the activity UI considers them expired.
  Future<void> reconcile(String account) {
    if (!enabled() || !supportsAccount(account)) return Future.value();
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
