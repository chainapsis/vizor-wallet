import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';

/// walletSnapshotSyncProgress drives the percentage in the voting catch-up
/// copy. Its numerator and baseline are both wallet-wide scan values.
void main() {
  VotingSessionState stateWith({
    required int? scanned,
    required int? snapshot,
    required int? birthday,
  }) {
    return VotingSessionState(
      roundId: 'round-1',
      walletScannedHeight: scanned,
      walletSnapshotHeight: snapshot,
      walletBirthdayHeight: birthday,
    );
  }

  test('reports the fraction scanned since the wallet birthday', () {
    final state = stateWith(scanned: 1_050, snapshot: 1_100, birthday: 1_000);

    expect(state.walletSnapshotSyncProgress, closeTo(0.5, 1e-9));
  });

  test('is unknown while the wallet frontier trails the wallet birthday', () {
    // A rewind can temporarily put the frontier below the retained birthday.
    // Reporting 0% here would pin the copy at zero and then jump.
    final state = stateWith(
      scanned: 2_100_000,
      snapshot: 2_950_000,
      birthday: 2_900_000,
    );

    expect(state.walletSnapshotSyncProgress, isNull);
  });

  test('is unknown for a wallet whose birthday is after the snapshot', () {
    final state = stateWith(scanned: 3_000, snapshot: 1_000, birthday: 2_000);

    expect(state.walletSnapshotSyncProgress, isNull);
    expect(state.walletBirthdayAfterSnapshot, isTrue);
  });

  test('is unknown until every height is known', () {
    expect(
      stateWith(
        scanned: null,
        snapshot: 1_100,
        birthday: 1_000,
      ).walletSnapshotSyncProgress,
      isNull,
    );
    expect(
      stateWith(
        scanned: 1_050,
        snapshot: null,
        birthday: 1_000,
      ).walletSnapshotSyncProgress,
      isNull,
    );
    expect(
      stateWith(
        scanned: 1_050,
        snapshot: 1_100,
        birthday: null,
      ).walletSnapshotSyncProgress,
      isNull,
    );
  });

  test('reports complete when the frontier reached the snapshot', () {
    final state = stateWith(scanned: 1_100, snapshot: 1_100, birthday: 1_100);

    expect(state.walletSnapshotSyncProgress, 1);
  });
}
