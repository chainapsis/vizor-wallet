import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../swap/models/swap_hardware_broadcast_result.dart';
import '../../swap/models/swap_models.dart';
import '../../swap/providers/swap_activity_tracker.dart';
import '../../swap/providers/swap_state_provider.dart';
import '../ledger_capability.dart';
import 'ledger_signing_service.dart' show ledgerWalletDbPathProvider;
import 'ledger_signed_operation_service.dart';

typedef LedgerDepositRecovery =
    Future<void> Function({
      required LedgerSignedOperationMetadata operation,
      required LedgerSignedOperationBroadcastResult result,
    });

typedef LedgerStandaloneResultRecovery =
    Future<bool> Function({
      required LedgerSignedOperationMetadata operation,
      required LedgerSignedOperationBroadcastResult result,
    });

bool ledgerStandaloneResultIsRecovered({
  required String status,
  required String resultTxids,
  required Iterable<String> walletTxids,
}) {
  final normalizedStatus = status.trim();
  if (normalizedStatus == 'expired') return true;

  final txids = resultTxids
      .split(',')
      .map((txid) => txid.trim().toLowerCase())
      .where((txid) => txid.isNotEmpty)
      .toSet();
  if (txids.isEmpty) return false;
  final recoveredTxids = {
    for (final txid in walletTxids) txid.trim().toLowerCase(),
  };

  if (normalizedStatus == 'broadcasted_storage_failed') {
    return txids.every(recoveredTxids.contains);
  }
  return txids.any(recoveredTxids.contains);
}

final ledgerDepositRecoveryProvider = Provider<LedgerDepositRecovery>((ref) {
  return ({required operation, required result}) async {
    final intentId = operation.externalRef?.trim();
    if (intentId == null || intentId.isEmpty) {
      throw StateError(
        'Ledger ${operation.kind.wireName} operation has no provider intent.',
      );
    }
    final intents = await ref
        .read(swapActivityTrackerProvider)
        .loadIntents(accountUuid: operation.accountUuid);
    final intent = intents.swapIntentById(intentId);
    if (intent == null) {
      throw StateError('Saved swap/pay intent $intentId was not found.');
    }
    await ref
        .read(swapStateProvider.notifier)
        .recordHardwareDepositBroadcast(
          intent: intent,
          broadcast: SwapHardwareBroadcastResult(
            txHash: result.txid,
            status: result.status,
            message: result.message,
          ),
        );
  };
});

/// Returns whether ordinary wallet recovery now owns a standalone send or
/// shield result, so the Ledger-only checkpoint can be removed safely.
///
/// Keystone and mnemonic sends stop carrying a hardware handoff once their
/// accepted-or-ambiguous transaction is in wallet history. Ledger keeps its
/// signed checkpoint across a crash, then follows the same boundary here.
final ledgerStandaloneResultRecoveryProvider =
    Provider<LedgerStandaloneResultRecovery>((ref) {
      return ({required operation, required result}) async {
        final status = result.status.trim();
        if (status == 'expired') return true;

        final dbPath = await ref.read(ledgerWalletDbPathProvider)();
        final endpoint = ref.read(rpcEndpointProvider);
        final history = await rust_sync.getTransactionHistory(
          dbPath: dbPath,
          network: endpoint.networkName,
          limit: 200,
          accountUuid: operation.accountUuid,
        );
        // A storage failure after a fully accepted batch is reconciled only
        // after every tx is visible. Partial/unknown batches persist the
        // network-touched prefix atomically, so one matching tx proves that
        // the normal wallet retry/sync path owns that prefix.
        return ledgerStandaloneResultIsRecovered(
          status: status,
          resultTxids: result.txid,
          walletTxids: history.map((transaction) => transaction.txidHex),
        );
      };
    });

final ledgerOperationRecoveryCoordinatorProvider =
    Provider<LedgerOperationRecoveryCoordinator>(
      LedgerOperationRecoveryCoordinator.new,
    );

class LedgerOperationRecoveryCoordinator {
  LedgerOperationRecoveryCoordinator(this._ref);

  final Ref _ref;
  Future<void>? _inFlight;
  bool _rerunRequested = false;

  Future<void> recover() {
    final existing = _inFlight;
    if (existing != null) {
      _rerunRequested = true;
      return existing;
    }
    final recovery = _recoverUntilIdle().whenComplete(() => _inFlight = null);
    _inFlight = recovery;
    return recovery;
  }

  Future<void> _recoverUntilIdle() async {
    do {
      _rerunRequested = false;
      await _recover();
    } while (_rerunRequested);
  }

  Future<void> _recover() async {
    if (!_ref.read(ledgerStaticCapabilityProvider).supported ||
        !_ref.read(appSecurityProvider).isUnlocked ||
        !(_ref.read(walletProvider).value?.hasWallet ?? false)) {
      return;
    }

    final operationService = _ref.read(ledgerSignedOperationServiceProvider);
    final operations = await operationService.list();
    var broadcastedAny = false;

    for (final operation in operations) {
      LedgerSignedOperationBroadcastResult? result;
      try {
        if (operation.state == 'signed_pending_broadcast') {
          result = await operationService.broadcast(
            operationId: operation.operationId,
          );
          broadcastedAny = true;
        } else if (operation.state == 'result_pending_ack') {
          final txid = operation.txid?.trim() ?? '';
          final status = operation.status?.trim() ?? '';
          if (txid.isEmpty || status.isEmpty) {
            log(
              'LedgerRecovery: incomplete result '
              'operation=${operation.operationId}',
            );
            continue;
          }
          result = LedgerSignedOperationBroadcastResult(
            operationId: operation.operationId,
            txid: txid,
            status: status,
            message: operation.message,
            requiresAck: true,
          );
        }

        if (result == null) continue;
        switch (operation.kind) {
          case LedgerSignedOperationKind.swapDeposit:
          case LedgerSignedOperationKind.payDeposit:
            await _ref.read(ledgerDepositRecoveryProvider)(
              operation: operation,
              result: result,
            );
            await operationService.acknowledge(operation.operationId);
          case LedgerSignedOperationKind.send:
          case LedgerSignedOperationKind.shield:
            if (result.requiresAck) {
              final recovered = await _ref.read(
                ledgerStandaloneResultRecoveryProvider,
              )(operation: operation, result: result);
              if (recovered) {
                await operationService.acknowledge(operation.operationId);
              } else {
                log(
                  'LedgerRecovery: ${operation.kind.wireName} result awaits '
                  'wallet sync operation=${operation.operationId} '
                  'status=${result.status}',
                );
              }
            }
        }
      } catch (error, stackTrace) {
        log(
          'LedgerRecovery: operation=${operation.operationId} failed: '
          '$error\n$stackTrace',
        );
      }
    }

    if (broadcastedAny) {
      try {
        await _ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (error) {
        log('LedgerRecovery: refreshAfterSend failed: $error');
      }
    }
  }
}

class LedgerOperationRecoveryHost extends ConsumerStatefulWidget {
  const LedgerOperationRecoveryHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LedgerOperationRecoveryHost> createState() =>
      _LedgerOperationRecoveryHostState();
}

class _LedgerOperationRecoveryHostState
    extends ConsumerState<LedgerOperationRecoveryHost> {
  bool _scheduledForCurrentUnlock = false;
  String? _scheduledSyncRevision;

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(ledgerStaticCapabilityProvider).supported;
    final unlocked = ref.watch(appSecurityProvider).isUnlocked;
    final hasWallet = ref.watch(walletProvider).value?.hasWallet ?? false;
    final hasLedgerAccount =
        ref
            .watch(accountProvider)
            .value
            ?.accounts
            .any(
              (account) =>
                  account.hardwareSignerKind == HardwareSignerKind.ledger,
            ) ??
        false;
    final eligible = supported && unlocked && hasWallet && hasLedgerAccount;
    final syncRevision = ref.watch(
      syncProvider.select((value) {
        final sync = value.value;
        if (sync == null) return null;
        final txids =
            sync.recentTransactions
                .map((transaction) => transaction.txidHex)
                .toList()
              ..sort();
        return '${sync.accountUuid}|'
            '${sync.lastSyncCompletedAt?.microsecondsSinceEpoch}|'
            '${txids.join(',')}';
      }),
    );

    if (!eligible) {
      _scheduledForCurrentUnlock = false;
      _scheduledSyncRevision = null;
    } else if (!_scheduledForCurrentUnlock ||
        _scheduledSyncRevision != syncRevision) {
      _scheduledForCurrentUnlock = true;
      _scheduledSyncRevision = syncRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          ref.read(ledgerOperationRecoveryCoordinatorProvider).recover(),
        );
      });
    }

    return widget.child;
  }
}
