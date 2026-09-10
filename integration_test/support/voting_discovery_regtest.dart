import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zcash_wallet/src/providers/voting/voting_home_entry_provider.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_discovery_client.dart';

// Route only the disposable regtest source to the local lambda-compatible API.
// Keep the production HTTP client, revision checks and authenticated refresh.
List<Override> votingDiscoveryRegtestOverrides() => [
  votingDiscoveryScopeResolverProvider.overrideWithValue(
    (network, source) =>
        network == 'regtest' && source == kE2eStaticVotingConfigSource
        ? VotingDiscoveryScope.prod
        : votingDiscoveryScopeForSource(network, source),
  ),
  votingDiscoveryEndpointProvider.overrideWithValue(
    '${const String.fromEnvironment('ZCASH_E2E_VOTING_GATEWAY_URL')}/v1/voting/discovery/prod',
  ),
];

Future<void> expectRegtestDiscoveryPersisted(
  ProviderContainer container,
) async {
  final key = votingHomeListKey('regtest', kE2eStaticVotingConfigSource);
  final list = container.read(votingHomeCacheProvider.notifier).list(key)!;
  expect(list.discoveryRevision, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
  expect(
    list.discoveryEndpoint,
    container.read(votingDiscoveryEndpointProvider),
  );
  final raw = await container
      .read(votingFileCacheProvider)
      .read(votingHomeCacheKey);
  expect(raw, isNotNull);
  final saved = ((jsonDecode(raw!) as Map)['lists'] as Map)[key] as Map;
  expect(saved['discoveryRevision'], list.discoveryRevision);
}
