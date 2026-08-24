import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

/// The voting stall detector resets its no-progress budget whenever the
/// tracker reports progress, so the tracker decides whether a wedged sync is
/// caught and whether a healthy one is left alone.
void main() {
  VotingWalletSyncProgressSample sample(double percentage, int scannedHeight) {
    return VotingWalletSyncProgressSample(
      percentage: percentage,
      scannedHeight: scannedHeight,
    );
  }

  test('replayed values after a restart do not count as progress', () {
    final tracker = VotingWalletSyncProgressTracker();

    expect(tracker.observe(sample(0.3, 100)), isFalse, reason: 'priming');
    expect(tracker.observe(sample(0.3, 100)), isFalse, reason: 'flat');
    expect(tracker.observe(sample(0.35, 100)), isTrue, reason: 'new high');

    // A restart drops the percentage to zero, then the wedged attempt
    // replays its pre-batch percentage without committing new work.
    expect(tracker.observe(sample(0.0, 100)), isFalse);
    expect(tracker.observe(sample(0.35, 100)), isFalse, reason: 'replay');
    expect(tracker.observe(sample(0.2, 100)), isFalse, reason: 'below mark');

    // Genuinely new work still registers.
    expect(tracker.observe(sample(0.36, 100)), isTrue);
    expect(tracker.observe(sample(0.36, 140)), isTrue, reason: 'height rose');
  });

  test('a lower scan height rebases onto the new scan epoch', () {
    final tracker = VotingWalletSyncProgressTracker();

    // A sync runs to completion: marks sit at 1.0 and the chain tip.
    expect(tracker.observe(sample(1.0, 900)), isFalse, reason: 'priming');
    expect(tracker.observe(sample(1.0, 900)), isFalse);

    // A new scan epoch starts well below those marks (an account added with
    // an older birthday, a reorg rewind, a reimport, a tail-repair pass).
    // Without rebasing, every later sample would be unsatisfiable and a
    // healthy backfill would be failed as stalled.
    expect(tracker.observe(sample(0.0, 100)), isTrue, reason: 'rewind');
    expect(tracker.observe(sample(0.1, 200)), isTrue);
    expect(tracker.observe(sample(0.2, 300)), isTrue);

    // Wedge protection still holds inside the new epoch.
    expect(tracker.observe(sample(0.2, 300)), isFalse);
    expect(tracker.observe(sample(0.0, 300)), isFalse, reason: 'restart');
    expect(tracker.observe(sample(0.2, 300)), isFalse, reason: 'replay');
  });

  test('a null sample is not progress', () {
    final tracker = VotingWalletSyncProgressTracker();

    expect(tracker.observe(null), isFalse);
    expect(tracker.observe(sample(0.5, 500)), isFalse, reason: 'priming');
    expect(tracker.observe(null), isFalse);
    expect(tracker.observe(sample(0.6, 500)), isTrue);
  });
}
