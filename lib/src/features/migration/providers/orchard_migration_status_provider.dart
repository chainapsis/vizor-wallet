import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/migration_view_state.dart';

const migrationProgressTransactionHistoryLimit = 1000;

/// Fingerprint of the settled sync inputs that can change the no-run
/// migration phase. Null while a scan is running: mid-scan wallet summaries
/// flap between spendable and pending, so they must not drive a status read.
int? settledSyncFingerprint(SyncState? sync) {
  if (sync == null || sync.isSyncing) return null;
  return Object.hash(
    sync.accountUuid,
    sync.scannedHeight,
    sync.orchardBalance,
    sync.orchardPendingBalance,
    sync.ironwoodBalance,
    sync.ironwoodPendingBalance,
  );
}

/// Holds the most recent settled fingerprint. While a scan runs this state
/// never changes, so watchers are not rebuilt at all — not even at scan
/// start. Each settled sync cycle (or idle balance change) updates the
/// fingerprint exactly once.
class MigrationStatusSyncGate extends Notifier<int> {
  @override
  int build() {
    ref.listen(syncProvider, (_, next) {
      final fingerprint = settledSyncFingerprint(next.value);
      if (fingerprint != null && fingerprint != state) state = fingerprint;
    });
    return settledSyncFingerprint(ref.read(syncProvider).value) ?? 0;
  }
}

final migrationStatusSyncGateProvider =
    NotifierProvider<MigrationStatusSyncGate, int>(MigrationStatusSyncGate.new);

final activeOrchardMigrationStatusProvider =
    FutureProvider<rust_sync.MigrationStatus?>((ref) async {
      final accountState = ref.watch(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      if (account == null || accountUuid == null) {
        return null;
      }

      final endpoint = ref.watch(rpcEndpointProvider);

      // Rust is still the source of truth; this watch only chooses when to
      // ask it again. Mid-scan answers flap between waiting and ready, so we
      // only re-ask when a sync cycle has settled (see
      // MigrationStatusSyncGate). Explicit ref.invalidate still works.
      ref.watch(migrationStatusSyncGateProvider);

      final dbPath = await getWalletDbPath();
      return rust_sync.getOrchardMigrationStatus(
        dbPath: dbPath,
        network: endpoint.walletNetworkName,
        accountUuid: accountUuid,
      );
    });

final hasActiveOrchardMigrationRunProvider = Provider<bool>((ref) {
  final status = ref.watch(activeOrchardMigrationStatusProvider).value;
  final viewState = migrationViewStateFromRustPhase(status?.phase);
  return viewState?.hasActiveRun ?? false;
});

/// Pure decision for blocking sends. Uses the preserved previous value
/// during reloads so the send screen does not flicker every time the status
/// provider re-queries.
bool migrationBlocksSend(AsyncValue<rust_sync.MigrationStatus?> statusAsync) {
  if (statusAsync.hasError) return true;
  final status = statusAsync.value;
  if (status == null) return statusAsync.isLoading;
  final viewState = migrationViewStateFromRustPhase(status.phase);
  return viewState?.hasActiveRun ?? false;
}

final migrationBlocksSendProvider = Provider<bool>((ref) {
  return migrationBlocksSend(ref.watch(activeOrchardMigrationStatusProvider));
});
