import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../../ledger/services/ledger_signed_operation_service.dart';
import '../models/swap_hardware_broadcast_result.dart';
import '../models/swap_models.dart';
import 'swap_state_provider.dart';

typedef LedgerDepositResultPersistence =
    Future<void> Function(
      SwapIntent intent,
      SwapHardwareBroadcastResult broadcast,
    );

final ledgerDepositResultPersistenceProvider =
    Provider<LedgerDepositResultPersistence>(
      (ref) =>
          (intent, broadcast) => ref
              .read(swapStateProvider.notifier)
              .recordHardwareDepositBroadcast(
                intent: intent,
                broadcast: broadcast,
              ),
    );

final swapLedgerCompletionServiceProvider =
    Provider<SwapLedgerCompletionService>((ref) {
      return SwapLedgerCompletionService(
        lifecycle: ref.watch(ledgerOperationLifecycleProvider),
        operations: ref.watch(ledgerSignedOperationServiceProvider),
        persist: ref.watch(ledgerDepositResultPersistenceProvider),
        accountExists: (uuid) =>
            ref
                .read(accountProvider)
                .value
                ?.accounts
                .any((account) => account.uuid == uuid) ??
            false,
      );
    });

/// UI callbacks are notifications only. Storage and acknowledgement stay in
/// this lease even when the initiating route or Activity panel is gone.
class SwapLedgerCompletionService {
  const SwapLedgerCompletionService({
    required this.lifecycle,
    required this.operations,
    required this.persist,
    required this.accountExists,
  });

  final LedgerOperationLifecycle lifecycle;
  final LedgerSignedOperationService operations;
  final LedgerDepositResultPersistence persist;
  final bool Function(String? uuid) accountExists;

  Future<void> complete(
    SwapIntent intent,
    LedgerSignedOperationBroadcastResult result,
  ) => lifecycle.run(() async {
    if (!accountExists(intent.accountUuid)) {
      throw StateError('The Ledger account is no longer available.');
    }
    await persist(
      intent,
      SwapHardwareBroadcastResult(
        txHash: result.txid,
        status: result.status,
        message: result.message,
      ),
    );
    if (result.requiresAck) await operations.acknowledge(result.operationId);
  });
}
