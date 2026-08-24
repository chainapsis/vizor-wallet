import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

/// The voting stall detector resets its no-progress budget whenever this
/// signal changes, so the signal must move only on commit-backed forward
/// progress. A crash-looping sync drops its percentage to zero on every
/// restart; counting those oscillations as progress would keep the
/// submission job from ever reporting a stall.
void main() {
  test('sync progress signal ticks only on forward movement', () async {
    final container = ProviderContainer(
      overrides: [syncProvider.overrideWith(_MutableSyncNotifier.new)],
    );
    addTearDown(container.dispose);
    await container.read(syncProvider.future);
    final notifier =
        container.read(syncProvider.notifier) as _MutableSyncNotifier;
    final signal = container.read(votingWalletSyncProgressSignalProvider);

    final initial = signal();
    expect(signal(), initial, reason: 'flat samples do not tick');

    notifier.setProgress(percentage: 0.3, scannedHeight: 100);
    final afterRise = signal();
    expect(afterRise, isNot(equals(initial)), reason: 'a rise ticks');
    expect(signal(), afterRise, reason: 'unchanged sample does not tick');

    // Restart churn: percentage resets to zero, then sits flat because a
    // wedged attempt commits nothing and so emits no progress events.
    notifier.setProgress(percentage: 0.0, scannedHeight: 100);
    expect(signal(), afterRise, reason: 'a restart drop does not tick');
    notifier.setProgress(percentage: 0.0, scannedHeight: 100);
    expect(signal(), afterRise, reason: 'flat after a restart does not tick');

    // A rise after a restart is commit-backed (progress events fire only
    // when a scan batch commits), so it counts again.
    notifier.setProgress(percentage: 0.05, scannedHeight: 100);
    expect(signal(), isNot(equals(afterRise)));

    // Scanned-height movement alone also counts as progress; a height drop
    // (restart) does not.
    final beforeHeight = signal();
    notifier.setProgress(percentage: 0.05, scannedHeight: 150);
    final afterHeightRise = signal();
    expect(afterHeightRise, isNot(equals(beforeHeight)));
    notifier.setProgress(percentage: 0.05, scannedHeight: 0);
    expect(signal(), afterHeightRise, reason: 'height drop does not tick');
  });
}

class _MutableSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async {
    return SyncState();
  }

  void setProgress({required double percentage, required int scannedHeight}) {
    state = AsyncData(
      SyncState(percentage: percentage, scannedHeight: scannedHeight),
    );
  }
}
