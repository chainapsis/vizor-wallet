import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';

void main() {
  test('accepts exactly one matching 64-byte Ironwood signature', () {
    final signature = LedgerVotingSignature(
      pool: 1,
      actionIndex: 7,
      signature: List<int>.filled(64, 9),
    );

    expect(
      requireMatchingLedgerVotingSignature(
        signatures: [signature],
        actionIndex: 7,
      ),
      same(signature),
    );
  });

  test('fails closed on signature count, pool, action, or length mismatch', () {
    LedgerVotingSignature signature({
      int pool = 1,
      int actionIndex = 7,
      int length = 64,
    }) => LedgerVotingSignature(
      pool: pool,
      actionIndex: actionIndex,
      signature: List<int>.filled(length, 9),
    );

    for (final candidate in <List<LedgerVotingSignature>>[
      const [],
      [signature(), signature()],
      [signature(pool: 0)],
      [signature(actionIndex: 8)],
      [signature(length: 63)],
    ]) {
      expect(
        () => requireMatchingLedgerVotingSignature(
          signatures: candidate,
          actionIndex: 7,
        ),
        throwsStateError,
      );
    }
  });
}
