import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_mirror_integrity_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_config_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh commits resolution and updates refresh baseline', () async {
    final initial = _resolution(
      'initial',
      rust_config.ConfigSwitchKind.initialLoad,
    );
    final refreshedOnce = _resolution(
      'switched',
      rust_config.ConfigSwitchKind.newChainOrRound,
    );
    final refreshedTwice = _resolution(
      'refreshed',
      rust_config.ConfigSwitchKind.unchanged,
    );

    final loader = _RecordingVotingConfigLoader([
      initial,
      refreshedOnce,
      refreshedTwice,
    ]);
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(
          _InMemorySourceStore(),
        ),
        votingConfigLoaderProvider.overrideWithValue(loader),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingConfigProvider.future);
    expect(container.read(votingConfigProvider).value, initial.config);
    expect(loader.previousByCall, [null]);

    await container.read(votingConfigProvider.notifier).refresh();
    expect(container.read(votingConfigProvider).value, refreshedOnce.config);
    expect(loader.previousByCall, [null, initial.config]);

    await container.read(votingConfigProvider.notifier).refresh();
    expect(loader.previousByCall, [null, initial.config, refreshedOnce.config]);
    expect(container.read(votingConfigProvider).value, refreshedTwice.config);
    expect(container.read(votingConfigRefreshFailureProvider), isNull);
  });

  test(
    'failed refresh preserves active mirror evidence until a clean commit',
    () async {
      final initial = _resolution(
        'initial',
        rust_config.ConfigSwitchKind.initialLoad,
      );
      final recovered = _resolution(
        'recovered',
        rust_config.ConfigSwitchKind.sameChainServiceUpdate,
      );
      final activeIntegrityFailure = _mirrorFailure(
        'https://active-primary.example/static.json',
        VotingConfigMirrorFailureKind.integrity,
      );
      final failedRefreshTransport = _mirrorFailure(
        'https://failed-refresh.example/static.json',
        VotingConfigMirrorFailureKind.transport,
      );
      final loader = _RecordingVotingConfigLoader([
        _QueuedConfigLoad(initial, [activeIntegrityFailure]),
        _QueuedConfigLoad(TimeoutException('refresh timeout 1'), [
          failedRefreshTransport,
        ]),
        _QueuedConfigLoad(TimeoutException('refresh timeout 2'), [
          failedRefreshTransport,
        ]),
        _QueuedConfigLoad(TimeoutException('refresh timeout 3'), [
          failedRefreshTransport,
        ]),
        recovered,
      ]);
      final container = ProviderContainer(
        overrides: [
          votingConfigSourceStoreProvider.overrideWithValue(
            _InMemorySourceStore(),
          ),
          votingConfigLoaderProvider.overrideWithValue(loader),
        ],
      );
      addTearDown(container.dispose);

      await container.read(votingConfigProvider.future);
      expect(container.read(votingConfigProvider).value, initial.config);
      expect(container.read(votingConfigMirrorIntegrityProvider), [
        activeIntegrityFailure,
      ]);

      await container.read(votingConfigProvider.notifier).refresh();
      final failure = container.read(votingConfigRefreshFailureProvider);
      expect(failure, isNotNull);
      expect(failure!.error, isA<TimeoutException>());
      expect(container.read(votingConfigProvider).hasError, isFalse);
      expect(container.read(votingConfigProvider).value, initial.config);
      expect(container.read(votingConfigMirrorIntegrityProvider), [
        activeIntegrityFailure,
      ]);

      await container.read(votingConfigProvider.notifier).refresh();
      expect(container.read(votingConfigProvider).value, recovered.config);
      expect(container.read(votingConfigRefreshFailureProvider), isNull);
      expect(container.read(votingConfigMirrorIntegrityProvider), isEmpty);
    },
  );

  test('stale load cannot replace current mirror evidence', () async {
    final initial = _resolution(
      'initial',
      rust_config.ConfigSwitchKind.initialLoad,
    );
    final stale = _resolution('stale', rust_config.ConfigSwitchKind.unchanged);
    final current = _resolution(
      'current',
      rust_config.ConfigSwitchKind.unchanged,
    );
    final staleFailure = _mirrorFailure(
      'https://stale.example/static.json',
      VotingConfigMirrorFailureKind.integrity,
    );
    final currentFailure = _mirrorFailure(
      'https://current.example/static.json',
      VotingConfigMirrorFailureKind.integrity,
    );
    final loader = _ConcurrentVotingConfigLoader(
      initial: initial,
      stale: stale,
      current: current,
      staleFailure: staleFailure,
      currentFailure: currentFailure,
    );
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(
          _InMemorySourceStore(),
        ),
        votingConfigLoaderProvider.overrideWithValue(loader),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingConfigProvider.future);
    final staleRefresh = container
        .read(votingConfigProvider.notifier)
        .refresh();
    await loader.staleStarted.future;

    await container.read(votingConfigProvider.notifier).refresh();
    expect(container.read(votingConfigProvider).value, current.config);
    expect(container.read(votingConfigMirrorIntegrityProvider), [
      currentFailure,
    ]);

    loader.releaseStale.complete();
    await staleRefresh;
    expect(container.read(votingConfigProvider).value, current.config);
    expect(container.read(votingConfigMirrorIntegrityProvider), [
      currentFailure,
    ]);
  });

  test('refresh keeps explicit AsyncError on non-retryable failure', () async {
    final initial = _resolution(
      'initial',
      rust_config.ConfigSwitchKind.initialLoad,
    );
    final fatal = StateError('bad config payload');
    final loader = _RecordingVotingConfigLoader([initial, fatal]);
    final container = ProviderContainer(
      overrides: [
        votingConfigSourceStoreProvider.overrideWithValue(
          _InMemorySourceStore(),
        ),
        votingConfigLoaderProvider.overrideWithValue(loader),
      ],
    );
    addTearDown(container.dispose);

    await container.read(votingConfigProvider.future);
    await container.read(votingConfigProvider.notifier).refresh();

    final state = container.read(votingConfigProvider);
    final failure = container.read(votingConfigRefreshFailureProvider);
    expect(state.hasError, isTrue);
    expect(state.error, same(fatal));
    expect(failure, isNotNull);
    expect(failure!.error, same(fatal));
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
  _RecordingVotingConfigLoader(Iterable<Object> responses)
    : _responses = Queue.of(responses),
      super(
        httpClient: const _NoopVotingHttpClient(),
        sourceUrl: kDefaultStaticVotingConfigSource,
      );

  final Queue<Object> _responses;
  final List<rust_config.ResolvedVotingConfig?> previousByCall = [];

  @override
  Future<rust_config_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
    void Function(VotingConfigMirrorFailure failure)? mirrorFailureObserver,
  }) async {
    previousByCall.add(previous);
    if (_responses.isEmpty) {
      throw StateError('No config responses queued.');
    }
    final queued = _responses.removeFirst();
    final next = queued is _QueuedConfigLoad ? queued.result : queued;
    if (queued is _QueuedConfigLoad) {
      for (final failure in queued.failures) {
        mirrorFailureObserver?.call(failure);
      }
    }
    if (next is rust_config_api.VotingConfigResolution) return next;
    if (next is Error) throw next;
    if (next is Exception) throw next;
    throw StateError('Unsupported queued loader response: $next');
  }
}

class _QueuedConfigLoad {
  const _QueuedConfigLoad(this.result, this.failures);

  final Object result;
  final List<VotingConfigMirrorFailure> failures;
}

class _ConcurrentVotingConfigLoader extends VotingConfigLoader {
  _ConcurrentVotingConfigLoader({
    required this.initial,
    required this.stale,
    required this.current,
    required this.staleFailure,
    required this.currentFailure,
  }) : super(httpClient: const _NoopVotingHttpClient());

  final rust_config_api.VotingConfigResolution initial;
  final rust_config_api.VotingConfigResolution stale;
  final rust_config_api.VotingConfigResolution current;
  final VotingConfigMirrorFailure staleFailure;
  final VotingConfigMirrorFailure currentFailure;
  final Completer<void> staleStarted = Completer<void>();
  final Completer<void> releaseStale = Completer<void>();
  var _calls = 0;

  @override
  Future<rust_config_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
    void Function(VotingConfigMirrorFailure failure)? mirrorFailureObserver,
  }) async {
    _calls++;
    if (_calls == 1) return initial;
    if (_calls == 2) {
      staleStarted.complete();
      await releaseStale.future;
      mirrorFailureObserver?.call(staleFailure);
      return stale;
    }
    if (_calls == 3) {
      mirrorFailureObserver?.call(currentFailure);
      return current;
    }
    throw StateError('Unexpected config load call $_calls.');
  }
}

class _NoopVotingHttpClient implements VotingHttpClient {
  const _NoopVotingHttpClient();

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
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
      pirLayout: const rust_config.PirLayout(
        pirDepth: 19,
        tier0Layers: 12,
        tier1Layers: 7,
        polyLen: 4096,
      ),
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
    skippedMirrors: const [],
  );
}

VotingConfigMirrorFailure _mirrorFailure(
  String url,
  VotingConfigMirrorFailureKind kind,
) {
  return VotingConfigMirrorFailure(
    stage: VotingConfigMirrorStage.staticAnchor,
    url: url,
    kind: kind,
    error: StateError('${kind.name} failure at $url'),
  );
}
