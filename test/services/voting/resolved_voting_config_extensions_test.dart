import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/services/voting/resolved_voting_config_extensions.dart';

void main() {
  test('assertRoundAuthenticated accepts authenticated round ids', () {
    final config = _resolvedConfig(
      authenticatedRoundIds: const [
        '0000000000000000000000000000000000000000000000000000000000000001',
      ],
    );

    expect(
      () => config.assertRoundAuthenticated(
        '0000000000000000000000000000000000000000000000000000000000000001',
      ),
      returnsNormally,
    );
  });

  test('assertRoundAuthenticated throws skipped-round reason', () {
    final config = _resolvedConfig(
      authenticatedRoundIds: const [],
      skippedRoundIds: const [
        '0000000000000000000000000000000000000000000000000000000000000002',
      ],
    );

    expect(
      () => config.assertRoundAuthenticated(
        '0000000000000000000000000000000000000000000000000000000000000002',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('failed dynamic-config authentication'),
        ),
      ),
    );
  });

  test('assertRoundAuthenticated throws absent-round reason', () {
    final config = _resolvedConfig(
      authenticatedRoundIds: const [],
      skippedRoundIds: const [],
    );

    expect(
      () => config.assertRoundAuthenticated(
        '0000000000000000000000000000000000000000000000000000000000000003',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('absent from the authenticated round set'),
        ),
      ),
    );
  });
}

rust_config.ResolvedVotingConfig _resolvedConfig({
  required List<String> authenticatedRoundIds,
  List<String> skippedRoundIds = const [],
}) {
  return rust_config.ResolvedVotingConfig(
    sourceFingerprint: 'source-fp',
    trustedKeyFingerprint: 'key-fp',
    dynamicConfigFingerprint: 'dynamic-fp',
    voteServers: const [
      rust_config.ServiceEndpoint(url: 'https://voting.example', label: 'vote'),
    ],
    pirEndpoints: const [
      rust_config.ServiceEndpoint(url: 'https://pir.example', label: 'pir'),
    ],
    supportedVersions: const rust_config.SupportedVersions(
      pir: ['v0'],
      voteProtocol: 'v0',
      tally: 'v0',
      voteServer: 'v1',
    ),
    authenticatedRounds: authenticatedRoundIds
        .map(
          (roundId) => rust_config.AuthenticatedRound(
            roundId: roundId,
            eaPk: Uint8List.fromList(List.filled(32, 1)),
          ),
        )
        .toList(growable: false),
    skippedRoundIds: skippedRoundIds,
    conditions: const [
      rust_config.ConfigCondition(
        kind: rust_config.ConfigConditionKind.dynamicSignaturesVerified,
        status: true,
        message: 'dynamic round signatures verified',
      ),
    ],
  );
}
