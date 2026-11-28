import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/delegate_mode_host.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_round_visibility_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import '../../services/voting/fake_voting_http.dart';

/// A proxy round that reads.
final _good = '0a' * 32;

/// A round whose status lookup fails.
final _down = '0b' * 32;

/// A config naming [_good] and [_down].
class _Config extends VotingConfigNotifier {
  @override
  Future<ResolvedVotingConfig> build() async => ResolvedVotingConfig(
    sourceFingerprint: 'fingerprint',
    trustedKeyFingerprint: 'keys',
    dynamicConfigFingerprint: 'dynamic',
    voteServers: const [
      ServiceEndpoint(url: 'https://vote.example', label: ''),
    ],
    pirEndpoints: const [],
    pirLayout: const PirLayout(
      pirDepth: 19,
      tier0Layers: 12,
      tier1Layers: 7,
      polyLen: 4096,
    ),
    supportedVersions: const SupportedVersions(
      pir: ['v0'],
      voteProtocol: 'v0',
      tally: 'v0',
      voteServer: 'v1',
    ),
    authenticatedRounds: [
      for (final id in [_down, _good])
        AuthenticatedRound(roundId: id, eaPk: Uint8List(32)),
    ],
    skippedRoundIds: const [],
    conditions: const [],
  );
}

/// A vote server that answers [_good]'s status and not [_down]'s.
class _Api extends VotingApiClient {
  _Api()
    : super(
        baseUrl: Uri.parse('https://vote.example'),
        httpClient: FakeVotingHttpClient(responses: {}),
      );

  @override
  Future<VotingRoundStatus> getRoundStatus(String roundId) async {
    if (roundId == _down) throw const SocketException('reset');
    return VotingRoundStatus.fromJson({
      'vote_round_id': roundId,
      'status': '1',
      'title': 'Q4 funding',
      'snapshot_height': 100,
      'ea_pk': base64Encode(Uint8List(32)),
      'nc_root': base64Encode(Uint8List(32)),
      'nullifier_imt_root': base64Encode(Uint8List(32)),
      'vote_end_time': 1790000000,
      'proposals': const [],
      'proxy_delegation': {'enabled': true},
    });
  }
}

/// Shows test rounds.
class _ShowTestRounds extends ShowTestVotingRoundsNotifier {
  @override
  Future<bool> build() async => true;
}

void main() {
  test('a round whose lookup fails leaves the others, and says the list is '
      'incomplete', () async {
    final container = ProviderContainer(
      overrides: [
        votingConfigProvider.overrideWith(_Config.new),
        votingApiClientProvider.overrideWith((ref, servers) => _Api()),
        showTestVotingRoundsProvider.overrideWith(_ShowTestRounds.new),
      ],
    );
    addTearDown(container.dispose);
    final host = container.read(Provider(AppDelegateModeHost.new));

    final read = await host.rounds();
    expect([for (final round in read.rounds) round.roundId], [_good]);
    expect(read.rounds.single.active, isTrue);
    expect(read.complete, isFalse);
  });
}
