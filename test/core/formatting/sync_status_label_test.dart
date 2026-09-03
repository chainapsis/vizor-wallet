import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
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
      SyncState(isSyncing: true, percentage: 0.5),
      displayWholePercentage: 99,
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

  test('a bootstrapping Tor route reads as connecting, not as synced', () {
    final status = SyncStatusLabel.from(
      SyncState(percentage: 1.0, isSyncing: false),
      networkPrivacy: _tor(NetworkPrivacyConnectionStatus.connecting),
    );
    expect(status.kind, SyncStatusKind.syncing);
    expect(status.label, kSyncStatusConnectingToTorLabel);
    expect(status.semanticsLabel, kSyncStatusConnectingToTorSemanticsLabel);
  });

  test('a bootstrapping Tor route outranks a stale failure', () {
    final status = SyncStatusLabel.from(
      SyncState(failure: _networkFailure('Tor connection failed')),
      networkPrivacy: _tor(NetworkPrivacyConnectionStatus.connecting),
    );
    expect(status.kind, SyncStatusKind.syncing);
    expect(status.label, kSyncStatusConnectingToTorLabel);
  });

  test('preflight over a connected Tor route still reads as connecting', () {
    final status = SyncStatusLabel.from(
      SyncState(isSyncing: true, percentage: 0.01, phase: kSyncPhasePreflight),
      displayWholePercentage: 1,
      networkPrivacy: _tor(NetworkPrivacyConnectionStatus.connected),
    );
    expect(status.kind, SyncStatusKind.syncing);
    expect(status.label, kSyncStatusConnectingToTorLabel);
  });

  test('progress over Tor shows the percentage once scanning has begun', () {
    final status = SyncStatusLabel.from(
      SyncState(isSyncing: true, percentage: 0.4, phase: 'scan'),
      displayWholePercentage: 40,
      networkPrivacy: _tor(NetworkPrivacyConnectionStatus.connected),
    );
    expect(status.label, '40% Syncing...');
  });

  test('direct-route preflight keeps the percentage label', () {
    final status = SyncStatusLabel.from(
      SyncState(isSyncing: true, percentage: 0.01, phase: kSyncPhasePreflight),
      displayWholePercentage: 1,
      networkPrivacy: const NetworkPrivacyState.off(),
    );
    expect(status.label, '1% Syncing...');
  });

  test('a failed enable with Tor still off leaves the sync state alone', () {
    final status = SyncStatusLabel.from(
      SyncState(percentage: 1.0, isSyncing: false),
      networkPrivacy: const NetworkPrivacyState(
        torEnabled: false,
        status: NetworkPrivacyConnectionStatus.failed,
      ),
    );
    expect(status.kind, SyncStatusKind.synced);
    expect(status.label, 'Vizor is synced');
  });

  test('an enable that never reached the runtime is not a Tor failure', () {
    final status = SyncStatusLabel.from(
      SyncState(isSyncing: true, percentage: 0.4, phase: 'scan'),
      displayWholePercentage: 40,
      networkPrivacy: const NetworkPrivacyState(
        torEnabled: false,
        status: NetworkPrivacyConnectionStatus.failed,
        targetTorEnabled: true,
      ),
    );
    expect(status.kind, SyncStatusKind.syncing);
    expect(status.label, '40% Syncing...');
  });

  test('turning Tor off does not read as connecting to it', () {
    final status = SyncStatusLabel.from(
      SyncState(percentage: 1.0, isSyncing: false),
      networkPrivacy: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
        targetTorEnabled: false,
      ),
    );
    expect(status.kind, SyncStatusKind.synced);
    expect(status.label, 'Vizor is synced');
  });

  test('a disable that failed to quiesce is not a Tor connection failure', () {
    final status = SyncStatusLabel.from(
      SyncState(isSyncing: true, percentage: 0.4, phase: 'scan'),
      displayWholePercentage: 40,
      networkPrivacy: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.failed,
        targetTorEnabled: false,
      ),
    );
    expect(status.kind, SyncStatusKind.syncing);
    expect(status.label, '40% Syncing...');
  });

  test('an enable in flight reads as connecting to Tor', () {
    final status = SyncStatusLabel.from(
      SyncState(percentage: 1.0, isSyncing: false),
      networkPrivacy: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
        targetTorEnabled: true,
      ),
    );
    expect(status.label, kSyncStatusConnectingToTorLabel);
  });

  test('a failed Tor route is a paused state that outranks sync state', () {
    final status = SyncStatusLabel.from(
      SyncState(percentage: 1.0, isSyncing: false),
      networkPrivacy: _tor(NetworkPrivacyConnectionStatus.failed),
    );
    expect(status.kind, SyncStatusKind.failed);
    expect(status.label, kSyncStatusTorFailedLabel);
    expect(status.semanticsLabel, kSyncStatusTorFailedSemanticsLabel);
  });
}

NetworkPrivacyState _tor(NetworkPrivacyConnectionStatus status) =>
    NetworkPrivacyState(torEnabled: true, status: status);

SyncFailure _networkFailure(String raw) => SyncFailure(
  kind: SyncFailureKind.network,
  rawMessage: raw,
  userMessage: 'Network error',
  showSettingsAction: false,
);
