import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/providers/voting/voting_participation_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zcash_wallet/src/providers/voting/voting_home_entry_provider.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_discovery_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_endpoint_mapper.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_participation_client.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as voting_rust;

String votingRegtestRuntimeValue(String key, String manualValue) {
  final manifest = installedE2eRuntimeCaseManifest;
  if (manifest == null) return manualValue;
  if (!const {
        'flutter.macos.voting',
        'flutter.macos.voting-slow-helper',
      }.contains(manifest.scenarioId) ||
      Platform.environment['VIZOR_E2E_VOTING_PHASE'] != 'vote') {
    throw StateError('Voting runtime requires the original voting case/phase.');
  }
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw StateError('The original voting runtime is missing $key.');
  }
  return value;
}

String get _gateway => votingRegtestRuntimeValue(
  'ZCASH_E2E_VOTING_GATEWAY_URL',
  const String.fromEnvironment('ZCASH_E2E_VOTING_GATEWAY_URL'),
);

String get _source => votingRegtestRuntimeValue(
  'ZCASH_E2E_VOTING_STATIC_CONFIG_URL',
  kE2eStaticVotingConfigSource,
);

Future<void> prepareVotingRegtestConfigSource() async {
  if (installedE2eRuntimeCaseManifest == null) return;
  await voting_rust.configureRegtestVotingParticipation(
    chainId: votingRegtestRuntimeValue('ZCASH_E2E_VOTE_CHAIN_ID', ''),
    validatorHash: votingRegtestRuntimeValue(
      'ZCASH_E2E_VOTE_VALIDATOR_HASH',
      '',
    ),
  );
  // Use the real namespace-scoped store and production authenticated loader.
  // Only the test entry point supplies the parent's checksum-pinned source.
  await AppSecureStoreVotingConfigSourceStore(
    AppSecureStore.instance,
  ).writeSourceUrl(_source);
}

// Route only the disposable regtest source to the local lambda-compatible API.
// Keep the production HTTP client, revision checks and authenticated refresh.
List<Override> votingDiscoveryRegtestOverrides() => [
  votingDiscoveryScopeResolverProvider.overrideWithValue(
    (network, source) => network == 'regtest' && source == _source
        ? VotingDiscoveryScope.prod
        : votingDiscoveryScopeForSource(network, source),
  ),
  votingDiscoveryEndpointProvider.overrideWithValue(
    '$_gateway/v1/voting/discovery/prod',
  ),
  if (installedE2eRuntimeCaseManifest != null)
    votingEndpointMapperProvider.overrideWithValue(
      VotingEndpointMapper(isRegtest: true, gatewayUrl: _gateway),
    ),
  if (installedE2eRuntimeCaseManifest != null)
    votingParticipationSourceSupportedProvider.overrideWithValue(
      (network, source) => network == 'regtest' && source == _source,
    ),
  if (installedE2eRuntimeCaseManifest != null)
    votingParticipationClientProvider.overrideWith((ref) {
      final http = DartIoVotingHttpClient();
      ref.onDispose(() => http.close(force: true));
      return VotingParticipationClient(
        http,
        const VotingParticipationBridge(),
        cache: ref.read(votingFileCacheProvider),
        regtestEndpoint: Uri.parse(_gateway),
      );
    }),
];

Future<void> expectRegtestDiscoveryPersisted(
  ProviderContainer container,
) async {
  final key = votingHomeListKey('regtest', _source);
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
