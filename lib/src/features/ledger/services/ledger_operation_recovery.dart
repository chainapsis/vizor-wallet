import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../swap/models/swap_hardware_broadcast_result.dart';
import '../../swap/models/swap_models.dart';
import '../../swap/providers/swap_activity_tracker.dart';
import '../../swap/providers/swap_state_provider.dart';
import '../ledger_capability.dart';
import 'ledger_signed_operation_service.dart';

typedef LedgerDepositRecovery =
    Future<void> Function({
      required LedgerSignedOperationMetadata operation,
      required LedgerSignedOperationBroadcastResult result,
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

final ledgerOperationRecoveryCoordinatorProvider =
    Provider<LedgerOperationRecoveryCoordinator>(
      LedgerOperationRecoveryCoordinator.new,
    );

class LedgerOperationRecoveryCoordinator {
  LedgerOperationRecoveryCoordinator(this._ref);

  final Ref _ref;
  Future<void>? _inFlight;

  Future<void> recover() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final recovery = _recover().whenComplete(() => _inFlight = null);
    _inFlight = recovery;
    return recovery;
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
              log(
                'LedgerRecovery: ${operation.kind.wireName} result needs '
                'manual reconciliation operation=${operation.operationId} '
                'status=${result.status}',
              );
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

    if (!eligible) {
      _scheduledForCurrentUnlock = false;
    } else if (!_scheduledForCurrentUnlock) {
      _scheduledForCurrentUnlock = true;
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
