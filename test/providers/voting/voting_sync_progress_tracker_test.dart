import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

VotingWalletSyncProgressSample _sample({
  double percentage = 0,
  int scannedHeight = 0,
  bool isSyncing = true,
  String phase = '',
  int phaseCompletedUnits = 0,
  int phaseTotalUnits = 0,
}) => VotingWalletSyncProgressSample(
  percentage: percentage,
  scannedHeight: scannedHeight,
  isSyncing: isSyncing,
  phase: phase,
  phaseCompletedUnits: phaseCompletedUnits,
  phaseTotalUnits: phaseTotalUnits,
);

void main() {
  test('the first sample only seeds the marks', () {
    final tracker = VotingWalletSyncProgressTracker();

    expect(tracker.observe(_sample(percentage: 0.5, scannedHeight: 100)), false);
  });

  test('a null sample is not progress', () {
    final tracker = VotingWalletSyncProgressTracker();

    expect(tracker.observe(null), false);
  });

  test('a rising percentage counts even while the frontier is pinned', () {
    // Tip-priority ranges scan first, so the contiguous frontier stays put
    // during a healthy catch-up. The engine percentage is the real signal.
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(_sample(percentage: 0.5, scannedHeight: 100));

    expect(
      tracker.observe(_sample(percentage: 0.6, scannedHeight: 100)),
      true,
    );
  });

  test('a rising frontier counts even while the percentage is pinned', () {
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(_sample(percentage: 0.5, scannedHeight: 100));

    expect(
      tracker.observe(_sample(percentage: 0.5, scannedHeight: 120)),
      true,
    );
  });

  test('repeating an already-reached value is not progress', () {
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(_sample(percentage: 0.5, scannedHeight: 100));

    expect(tracker.observe(_sample(percentage: 0.5, scannedHeight: 100)), false);
  });

  test('a replayed re-rise to an already-reached value is not progress', () {
    // startSync resets the Dart percentage to zero and pre-batch events
    // re-emit a percentage computed from persisted state. Counting the
    // re-rise would let a wedged sync reset the stall budget forever.
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(_sample(percentage: 0.5, scannedHeight: 100));
    tracker.observe(_sample(percentage: 0, scannedHeight: 100));

    expect(tracker.observe(_sample(percentage: 0.5, scannedHeight: 100)), false);
  });

  test('advancing preparation units count while scan progress is pinned', () {
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(
      _sample(
        scannedHeight: 100,
        phase: kSyncPhaseActiveUtxo,
        phaseCompletedUnits: 1,
        phaseTotalUnits: 10,
      ),
    );

    expect(
      tracker.observe(
        _sample(
          scannedHeight: 100,
          phase: kSyncPhaseActiveUtxo,
          phaseCompletedUnits: 2,
          phaseTotalUnits: 10,
        ),
      ),
      true,
    );
  });

  test('preparation counter resets and replays are not progress', () {
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(
      _sample(
        scannedHeight: 100,
        phase: kSyncPhaseActiveUtxo,
        phaseCompletedUnits: 2,
        phaseTotalUnits: 10,
      ),
    );

    expect(
      tracker.observe(
        _sample(
          scannedHeight: 100,
          phase: kSyncPhaseActiveUtxo,
          phaseCompletedUnits: 0,
          phaseTotalUnits: 10,
        ),
      ),
      false,
    );
    expect(
      tracker.observe(
        _sample(
          scannedHeight: 100,
          phase: kSyncPhaseActiveUtxo,
          phaseCompletedUnits: 2,
          phaseTotalUnits: 10,
        ),
      ),
      false,
    );
  });

  test('idle preparation counters are not progress', () {
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(
      _sample(
        scannedHeight: 100,
        phase: kSyncPhaseActiveUtxo,
        phaseCompletedUnits: 1,
        phaseTotalUnits: 10,
      ),
    );

    expect(
      tracker.observe(
        _sample(
          scannedHeight: 100,
          isSyncing: false,
          phase: kSyncPhaseActiveUtxo,
          phaseCompletedUnits: 2,
          phaseTotalUnits: 10,
        ),
      ),
      false,
    );
  });

  test('a running engine rewinding the frontier rebases onto the new epoch', () {
    // A lower height from a running engine is a new scan epoch: a rescan
    // from an older birthday, a reorg rewind, or a tail-repair pass.
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(_sample(percentage: 0.9, scannedHeight: 900));

    expect(tracker.observe(_sample(percentage: 0.1, scannedHeight: 100)), true);
    expect(tracker.observe(_sample(percentage: 0.2, scannedHeight: 110)), true);
  });

  test('an idle engine reporting a lower height neither counts nor rebases', () {
    // Locking the wallet republishes zeroed sync state while sync is
    // cancelled. Rebasing onto it would count the lock as progress and lower
    // the marks, letting a later replay of an already-reached value read as
    // progress and reset the stall budget forever.
    final tracker = VotingWalletSyncProgressTracker();
    tracker.observe(_sample(percentage: 0.9, scannedHeight: 900));

    expect(
      tracker.observe(
        _sample(percentage: 0, scannedHeight: 0, isSyncing: false),
      ),
      false,
    );
    expect(
      tracker.observe(_sample(percentage: 0.9, scannedHeight: 900)),
      false,
    );
  });
}
