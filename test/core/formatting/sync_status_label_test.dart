import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  test('synced state when complete and idle', () {
    final status = SyncStatusLabel.from(
      SyncState(percentage: 1.0, isSyncing: false),
    );
    expect(status.kind, SyncStatusKind.synced);
    expect(status.label, 'Vizor is synced');
  });

  test('syncing state carries whole-percent progress capped below 100', () {
    final status = SyncStatusLabel.from(
      SyncState(isSyncing: true, percentage: 0.5, displayPercentage: 0.997),
    );
    expect(status.kind, SyncStatusKind.syncing);
    expect(status.label, '99% Syncing...');
  });

  test('failed state names the failure reason', () {
    final status = SyncStatusLabel.from(
      SyncState(
        failure: const SyncFailure(
          kind: SyncFailureKind.network,
          rawMessage: 'connection refused',
          userMessage: 'Network error',
          showSettingsAction: false,
        ),
      ),
    );
    expect(status.kind, SyncStatusKind.failed);
    expect(status.label, 'Syncing failed. Network error...');
  });
}
