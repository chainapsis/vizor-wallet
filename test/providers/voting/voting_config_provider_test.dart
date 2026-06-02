import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/api/voting_config.dart' as rust_config_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setLoadedConfig commits resolution and updates refresh baseline', () async {
    final initial = _resolution('initial', rust_config.ConfigSwitchKind.initialLoad);
    final switched = _resolution(
      'switched',
      rust_config.ConfigSwitchKind.newChainOrRound,
    );
    final refreshed = _resolution(
      'refreshed',
      rust_config.ConfigSwitchKind.unchanged,
    );

    final loader = _RecordingVotingConfigLoader([initial, refreshed]);
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(_InMemorySourceStore()),
        votingConfigLoaderProvider.overrideWithValue(loader),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingConfigProvider.future);
    container.read(votingConfigProvider.notifier).setLoadedConfig(switched);

    expect(container.read(votingConfigProvider).value, switched.config);

    await container.read(votingConfigProvider.notifier).refresh();

    expect(loader.lastPrevious, switched.config);
    expect(container.read(votingConfigProvider).value, refreshed.config);
  });
}

class _InMemorySourceStore implements VotingConfigSourceStore {
  String? _sourceUrl;
  String? _savedSourcesJson;

  @override
  Future<String?> readSavedSourcesJson() async => _savedSourcesJson;

  @override
  Future<String?> readSourceUrl() async => _sourceUrl;

  @override
  Future<void> resetSourceUrl() async {
    _sourceUrl = null;
  }

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) async {
    _savedSourcesJson = savedSourcesJson;
  }

  @override
  Future<void> writeSourceUrl(String sourceUrl) async {
    _sourceUrl = sourceUrl;
  }
}

class _RecordingVotingConfigLoader extends VotingConfigLoader {
  _RecordingVotingConfigLoader(Iterable<rust_config_api.VotingConfigResolution> configs)
    : _configs = Queue.of(configs),
      super(
        httpClient: const _NoopVotingHttpClient(),
        sourceUrl: kDefaultStaticVotingConfigSource,
      );

  final Queue<rust_config_api.VotingConfigResolution> _configs;
  rust_config.ResolvedVotingConfig? lastPrevious;

  @override
  Future<rust_config_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
  }) async {
    lastPrevious = previous;
    if (_configs.isEmpty) {
      throw StateError('No config responses queued.');
    }
    return _configs.removeFirst();
  }
}

class _NoopVotingHttpClient implements VotingHttpClient {
  const _NoopVotingHttpClient();

  @override
  Future<VotingHttpResponse> get(Uri uri, {Duration? timeout}) async {
    throw UnimplementedError('HTTP should not be used in this test.');
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    throw UnimplementedError('HTTP should not be used in this test.');
  }
}

rust_config_api.VotingConfigResolution _resolution(
  String seed,
  rust_config.ConfigSwitchKind switchKind,
) {
  return rust_config_api.VotingConfigResolution(
    config: rust_config.ResolvedVotingConfig(
      sourceFingerprint: 'source-$seed',
      trustedKeyFingerprint: 'trusted-$seed',
      dynamicConfigFingerprint: 'dynamic-$seed',
      voteServers: [
        rust_config.ServiceEndpoint(
          url: 'https://vote-$seed.example',
          label: 'vote-$seed',
        ),
      ],
      pirEndpoints: [
        rust_config.ServiceEndpoint(
          url: 'https://pir-$seed.example',
          label: 'pir-$seed',
        ),
      ],
      supportedVersions: const rust_config.SupportedVersions(
        pir: ['1'],
        voteProtocol: '1',
        tally: '1',
        voteServer: '1',
      ),
      authenticatedRounds: [
        rust_config.AuthenticatedRound(
          roundId: 'round-$seed',
          eaPk: Uint8List.fromList(List<int>.filled(32, 1)),
        ),
      ],
      skippedRoundIds: const [],
      conditions: const [],
    ),
    switchKind: switchKind,
  );
}
