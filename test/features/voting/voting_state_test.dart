import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

void main() {
  test('session state carries the privacy trim through copyWith', () {
    final state = VotingSessionState(roundId: 'round-1');
    expect(state.privacyTrimDroppedValueZatoshi, isNull);

    final withTrim = state.copyWith(
      privacyTrimDroppedValueZatoshi: BigInt.from(19000000),
    );
    expect(withTrim.privacyTrimDroppedValueZatoshi, BigInt.from(19000000));

    // A later report of zero must be able to clear a stale warning: the
    // authoritative bundle layout supersedes the pre-delegation preview.
    final cleared = withTrim.copyWith(
      privacyTrimDroppedValueZatoshi: BigInt.zero,
    );
    expect(cleared.privacyTrimDroppedValueZatoshi, BigInt.zero);

    // An unrelated update must leave it alone.
    expect(
      cleared
          .copyWith(eligibleWeightZatoshi: BigInt.one)
          .privacyTrimDroppedValueZatoshi,
      BigInt.zero,
    );
  });

  test('round details reject fractional snapshot heights', () {
    final status = VotingRoundStatus(
      roundId: 'round-1',
      status: 'active',
      rawJson: _roundJson(snapshotHeight: 100.5),
    );

    expect(
      () => VotingRoundDetails.fromStatus(status),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'snapshot_height must be an integer',
        ),
      ),
    );
  });

  test('round details require 32-byte round parameter fields', () {
    for (final entry in const {
      'ea_pk': 31,
      'nc_root': 33,
      'nullifier_imt_root': 1,
    }.entries) {
      final status = VotingRoundStatus(
        roundId: 'round-1',
        status: 'active',
        rawJson: _roundJsonWithField(entry.key, _b64(entry.value)),
      );

      expect(
        () => VotingRoundDetails.fromStatus(status),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '${entry.key} must decode to 32 bytes',
          ),
        ),
      );
    }
  });
}

Map<String, dynamic> _roundJsonWithField(String key, String value) {
  return _roundJson()..[key] = value;
}

Map<String, dynamic> _roundJson({
  Object snapshotHeight = 100,
  String? eaPk,
  String? ncRoot,
  String? nullifierImtRoot,
}) {
  return {
    'snapshot_height': snapshotHeight,
    'ea_pk': eaPk ?? _b64(32),
    'nc_root': ncRoot ?? _b64(32),
    'nullifier_imt_root': nullifierImtRoot ?? _b64(32),
  };
}

String _b64(int byteLength) => base64Encode(List.filled(byteLength, 1));
