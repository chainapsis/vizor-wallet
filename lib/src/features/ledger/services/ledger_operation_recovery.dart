import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
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

/// A terminal outcome recovery found while the user was away: the signed
/// request can no longer be sent, and Rust has already dropped it.
class LedgerRecoveryNotice {
  const LedgerRecoveryNotice({
    required this.operationId,
    required this.message,
  });

  final String operationId;
  final String message;
}

class LedgerRecoveryNoticeController extends Notifier<LedgerRecoveryNotice?> {
  @override
  LedgerRecoveryNotice? build() => null;

  void publish(LedgerRecoveryNotice notice) => state = notice;

  void clear() => state = null;
}

final ledgerRecoveryNoticeProvider =
    NotifierProvider<LedgerRecoveryNoticeController, LedgerRecoveryNotice?>(
      LedgerRecoveryNoticeController.new,
    );

String ledgerRecoveryTerminalMessage({
  required LedgerSignedOperationKind kind,
  required Object error,
}) {
  final expired = error.toString().toLowerCase().contains('expired');
  final subject = switch (kind) {
    LedgerSignedOperationKind.send => 'transaction',
    LedgerSignedOperationKind.shield => 'shielding transaction',
    LedgerSignedOperationKind.swapDeposit => 'swap deposit',
    LedgerSignedOperationKind.payDeposit => 'payment',
  };
  final reason = expired
      ? 'expired before it could be sent'
      : 'was rejected by the network';
  final consequence = switch (kind) {
    LedgerSignedOperationKind.swapDeposit => 'The swap was not funded.',
    LedgerSignedOperationKind.payDeposit => 'The payment was not made.',
    LedgerSignedOperationKind.send ||
    LedgerSignedOperationKind.shield => 'Nothing was sent.',
  };
  return 'A Ledger-signed $subject $reason. $consequence '
      'Create a new request when ready.';
}

/// Whether a swap or pay deposit may still be broadcast.
enum LedgerDepositBroadcastGate { broadcast, intentMissing, deadlinePassed }

typedef LedgerDepositBroadcastGateCheck =
    Future<LedgerDepositBroadcastGate> Function(
      LedgerSignedOperationMetadata operation,
    );

bool ledgerDepositDeadlinePassed({
  required DateTime? deadline,
  required DateTime now,
}) {
  return deadline != null && !now.toUtc().isBefore(deadline.toUtc());
}

/// A signed deposit is only worth sending while its provider intent exists and
/// its deposit window is open; a late deposit strands funds with the provider.
final ledgerDepositBroadcastGateProvider =
    Provider<LedgerDepositBroadcastGateCheck>((ref) {
      return (operation) async {
        final intentId = operation.externalRef?.trim();
        if (intentId == null || intentId.isEmpty) {
          return LedgerDepositBroadcastGate.intentMissing;
        }
        final intents = await ref
            .read(swapActivityTrackerProvider)
            .loadIntents(accountUuid: operation.accountUuid);
        final intent = intents.swapIntentById(intentId);
        if (intent == null) return LedgerDepositBroadcastGate.intentMissing;
        return ledgerDepositDeadlinePassed(
              deadline: intent.depositDeadline,
              now: DateTime.now(),
            )
            ? LedgerDepositBroadcastGate.deadlinePassed
            : LedgerDepositBroadcastGate.broadcast;
      };
    });

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
          if (operation.kind == LedgerSignedOperationKind.swapDeposit ||
              operation.kind == LedgerSignedOperationKind.payDeposit) {
            final gate = await _ref.read(ledgerDepositBroadcastGateProvider)(
              operation,
            );
            if (gate != LedgerDepositBroadcastGate.broadcast) {
              await operationService.discard(operation.operationId);
              log(
                'LedgerRecovery: discarded ${operation.kind.wireName} '
                'operation=${operation.operationId} reason=${gate.name}',
              );
              continue;
            }
          }
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
        if (operation.state == 'signed_pending_broadcast' &&
            isTerminalLedgerSignedOperationError(error)) {
          // Rust has dropped the checkpoint; only this notice tells the user
          // that a request they approved on the device was never sent.
          _ref
              .read(ledgerRecoveryNoticeProvider.notifier)
              .publish(
                LedgerRecoveryNotice(
                  operationId: operation.operationId,
                  message: ledgerRecoveryTerminalMessage(
                    kind: operation.kind,
                    error: error,
                  ),
                ),
              );
        }
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
  void initState() {
    super.initState();
    ref.listenManual<LedgerRecoveryNotice?>(ledgerRecoveryNoticeProvider, (
      previous,
      next,
    ) {
      if (next == null || identical(previous, next)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAppToast(
          context,
          next.message,
          duration: const Duration(seconds: 6),
          iconName: AppIcons.warningCircle,
          tone: AppToastTone.destructive,
        );
        ref.read(ledgerRecoveryNoticeProvider.notifier).clear();
      });
    });
  }

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
