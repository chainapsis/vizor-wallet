import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

/// The voting stall detector resets its no-progress budget whenever this
/// signal changes, so the signal must move only past its high-water marks.
/// A crash-looping sync replays previously seen values (Dart resets the
/// percentage on every restart and the engine's pre-batch events re-emit a
/// percentage computed from persisted state before any new commit); if those
/// replays ticked the signal, the submission job could never report a stall.
void main() {
  test('sync progress signal ticks only past its high-water marks', () async {
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
    expect(afterRise, isNot(equals(initial)), reason: 'a new high ticks');
    expect(signal(), afterRise, reason: 'unchanged sample does not tick');

    // Restart churn: percentage resets to zero, then the wedged attempt
    // replays its pre-batch percentage without committing new work. The
    // replayed value never exceeds the high-water mark, so no tick.
    notifier.setProgress(percentage: 0.0, scannedHeight: 100);
    expect(signal(), afterRise, reason: 'a restart drop does not tick');
    notifier.setProgress(percentage: 0.3, scannedHeight: 100);
    expect(
      signal(),
      afterRise,
      reason: 'a replayed pre-batch percentage does not tick',
    );

    // Committed new work pushes past the mark and counts again.
    notifier.setProgress(percentage: 0.35, scannedHeight: 100);
    expect(signal(), isNot(equals(afterRise)));

    // Scanned-height movement past its own mark also counts as progress; a
    // drop or a replay of an already-seen height does not.
    final beforeHeight = signal();
    notifier.setProgress(percentage: 0.35, scannedHeight: 150);
    final afterHeightRise = signal();
    expect(afterHeightRise, isNot(equals(beforeHeight)));
    notifier.setProgress(percentage: 0.35, scannedHeight: 40);
    expect(signal(), afterHeightRise, reason: 'height drop does not tick');
    notifier.setProgress(percentage: 0.35, scannedHeight: 150);
    expect(signal(), afterHeightRise, reason: 'replayed height does not tick');
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
