import 'package:zcash_wallet/src/services/voting/voting_file_cache.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';

import 'package:zcash_wallet/src/providers/voting/voting_share_tracking_registry_provider.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_entry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart';
import 'package:zcash_wallet/src/services/voting/voting_api_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import 'package:zcash_wallet/src/services/voting/voting_discovery_client.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import '../../services/voting/fake_voting_http.dart';
import '../../fakes/memory_voting_home_cache_store.dart';

const roundId =
    '0000000000000000000000000000000000000000000000000000000000000001';
VotingRoundSummary round() => VotingRoundSummary.fromJson({
  'vote_round_id': roundId,
  'title': 'Vote',
  'status': '1',
});

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _Source extends VotingConfigSourceNotifier {
  _Source([this.initial = 'source']);
  final String initial;
  void select(String source) => state = AsyncData(
    VotingConfigSourceState(sourceUrl: source, isDefault: false),
  );
  @override
  Future<VotingConfigSourceState> build() async =>
      VotingConfigSourceState(sourceUrl: initial, isDefault: false);
}

class _Config extends VotingConfigNotifier {
  _Config(this.roundIds);
  final List<String> roundIds;
  int loads = 0;
  bool fail = false;
  @override
  Future<ResolvedVotingConfig> build() async {
    loads++;
    return _value;
  }

  @override
  Future<void> refresh() async {
    loads++;
    if (fail) throw StateError('offline');
    state = AsyncData(_value);
  }

  ResolvedVotingConfig get _value => ResolvedVotingConfig(
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
      for (final id in roundIds)
        AuthenticatedRound(roundId: id, eaPk: Uint8List(32)),
    ],
    skippedRoundIds: const [],
    conditions: const [],
  );
}

class _Api extends VotingApiClient {
  _Api()
    : super(
        baseUrl: Uri.parse('https://vote.example'),
        httpClient: FakeVotingHttpClient(responses: {}),
      );
  int calls = 0;
  String status = '1';
  Completer<void>? gate;
  @override
  Future<List<VotingRoundSummary>> listRounds() async {
    calls++;
    await gate?.future;
    return [
      VotingRoundSummary.fromJson({...round().rawJson, 'status': status}),
    ];
  }
}

class _Rpc extends RpcEndpointNotifier {
  _Rpc(this.network);
  final String network;
  @override
  RpcEndpointConfig build() => RpcEndpointConfig(
    networkName: network,
    lightwalletdUrl: 'https://rpc.example:443',
  );
  void select(String network) => state = state.copyWith(networkName: network);
}

class _Discovery extends VotingDiscoveryClient {
  _Discovery() : super(FakeVotingHttpClient());
  int calls = 0;
  final scopes = <VotingDiscoveryScope>[];
  final endpoints = <Uri>[];
  String revision = 'sha256:${'a' * 64}';
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<VotingDiscoverySnapshot> fetch(
    Uri endpoint,
    DateTime Function() now, {
    VotingDiscoveryScope scope = VotingDiscoveryScope.prod,
  }) async {
    calls++;
    scopes.add(scope);
    endpoints.add(endpoint);
    await gate?.future;
    if (fail) throw StateError('discovery offline');
    return VotingDiscoverySnapshot(revision: revision, checkedAt: now());
  }
}

void main() {
  late ProviderContainer container;
  late MemoryVotingHomeCacheStore store;
  late _Api api;
  late _Config config;
  late DateTime now;
  late _Discovery discovery;
  late _CleanupCache files;
  var endpoint = votingDiscoveryUrl;
  void setup(List<String> ids, {bool prod = false, bool stage = false}) {
    now = DateTime.utc(2026, 9, 10);
    store = MemoryVotingHomeCacheStore();
    api = _Api();
    files = _CleanupCache();
    config = _Config(ids);
    discovery = _Discovery();
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        appSecurityProvider.overrideWith(_Security.new),
        rpcEndpointProvider.overrideWith(() => _Rpc(stage ? 'test' : 'main')),
        votingConfigSourceProvider.overrideWith(
          () => _Source(
            stage
                ? kStageStaticVotingConfigSource
                : prod
                ? kProductionStaticVotingConfigSource
                : 'source',
          ),
        ),
        votingDiscoveryClientProvider.overrideWithValue(discovery),
        votingDiscoveryEndpointProvider.overrideWith((ref) => endpoint),
        votingConfigProvider.overrideWith(() => config),
        votingHomeCacheStoreProvider.overrideWithValue(store),
        votingFileCacheProvider.overrideWithValue(files),
        votingHomeClockProvider.overrideWithValue(() => now),
        votingApiClientProvider.overrideWith((ref, servers) => api),
        // Any accidental Home eligibility or recovery dependency fails the test.
        votingRustApiProvider.overrideWith(
          (_) => throw StateError('Home must not use Rust wallet queries'),
        ),
        votingRecoveryServiceProvider.overrideWith(
          (_) => throw StateError('Home must not load recovery'),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  for (final status in [
    '2',
    '3',
    'tallying',
    'closed',
    'finalized',
    'completed',
    'ended',
    'pending',
    ' CLOSED ',
    '1',
    'active',
    'unknown',
  ]) {
    test('round cleanup normalizes status $status', () async {
      setup([roundId]);
      api.status = status;
      await container.read(votingHomeRefreshProvider).refresh();
      expect(
        files.removed,
        ['1', 'active', 'unknown'].contains(status) ? [] : ['main|$roundId'],
      );
    });
  }

  test(
    'empty authenticated config skips the vote server for six hours',
    () async {
      setup([]);
      final refresh = container.read(votingHomeRefreshProvider);
      await refresh.refresh();
      await refresh.refresh();
      expect(config.loads, 1);
      expect(api.calls, 0);
      now = now.add(const Duration(hours: 6));
      await refresh.refresh();
      expect(config.loads, 2);
      expect(api.calls, 0);
    },
  );

  test(
    'concurrent Home triggers share one list request and honor durable TTL',
    () async {
      setup([roundId]);
      api.gate = Completer<void>();
      final refresh = container.read(votingHomeRefreshProvider);
      final first = refresh.refresh();
      final second = refresh.refresh();
      await Future<void>.delayed(Duration.zero);
      api.gate!.complete();
      await Future.wait([first, second]);
      expect(api.calls, 1);
      expect(config.loads, 1);
      // Recreate the coordinator and cache, as happens on process restart.
      container.invalidate(votingHomeRefreshProvider);
      container.invalidate(votingHomeCacheProvider);
      await container.read(votingHomeRefreshProvider).refresh();
      expect(api.calls, 1);
      expect(config.loads, 1);
      now = now.add(const Duration(hours: 6));
      await container.read(votingHomeRefreshProvider).refresh();
      expect(api.calls, 2);
      expect(config.loads, 2);
    },
  );

  test(
    'source change during list fetch cannot stamp either source fresh',
    () async {
      setup([roundId]);
      api.gate = Completer<void>();
      final loading = container.read(votingHomeRefreshProvider).refresh();
      while (api.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      (container.read(votingConfigSourceProvider.notifier) as _Source).select(
        'other-source',
      );
      api.gate!.complete();
      await loading;
      final cache = container.read(votingHomeCacheProvider.notifier);
      expect(cache.list(votingHomeListKey('main', 'source')), null);
      expect(cache.list(votingHomeListKey('main', 'other-source')), null);
      await container.read(votingHomeRefreshProvider).refresh();
      expect(api.calls, 2);
    },
  );

  test(
    'reset drains in-flight discovery and prevents its cache write',
    () async {
      setup([roundId]);
      api.gate = Completer<void>();
      final loading = container.read(votingHomeRefreshProvider).refresh();
      while (api.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final registry = container.read(votingShareTrackingRegistryProvider);
      var drained = false;
      final draining = registry.quiesceAndDrain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, false);
      api.gate!.complete();
      await loading;
      await draining;
      expect(store.value, null);
      registry.resume();
    },
  );

  test(
    'failure preserves the last snapshot without extending success TTL',
    () async {
      setup([roundId]);
      final refresh = container.read(votingHomeRefreshProvider);
      await refresh.refresh();
      final stored = store.value;
      now = now.add(const Duration(hours: 6));
      config.fail = true;
      await refresh.refresh();
      await refresh.refresh();
      expect(config.loads, 2);
      expect(store.value, stored);
      now = now.add(const Duration(minutes: 5));
      config.fail = false;
      await refresh.refresh();
      expect(config.loads, 3);
      expect(api.calls, 2);
    },
  );
  test(
    'prod entry probes once and unchanged revision survives restart without full queries',
    () async {
      setup([roundId], prod: true);
      final refresh = container.read(votingHomeRefreshProvider);
      await refresh.refresh();
      expect(discovery.calls, 1);
      expect(config.loads, 1);
      expect(api.calls, 1);
      final stored = store.value;
      container.invalidate(votingHomeRefreshProvider);
      container.invalidate(votingHomeCacheProvider);
      now = now.add(const Duration(hours: 1));
      await container.read(votingHomeRefreshProvider).refresh();
      expect(discovery.calls, 2);
      expect(config.loads, 1);
      expect(api.calls, 1);
      expect(store.value, stored); // Probe must not extend full-refresh TTL.
      now = now.add(const Duration(hours: 5));
      await container.read(votingHomeRefreshProvider).refresh();
      expect(discovery.calls, 3);
      expect(api.calls, 2);
    },
  );

  test(
    'changed revision is only applied after full refresh succeeds',
    () async {
      setup([roundId], prod: true);
      final refresh = container.read(votingHomeRefreshProvider);
      await refresh.refresh();
      final saved = store.value;
      discovery.revision = 'sha256:${'b' * 64}';
      config.fail = true;
      await refresh.refresh();
      expect(store.value, saved);
      config.fail = false;
      now = now.add(const Duration(minutes: 5));
      await refresh.refresh();
      expect(api.calls, 2);
      expect(store.value, contains(discovery.revision));
      await refresh.refresh();
      expect(api.calls, 2);
    },
  );

  test(
    'failed probe preserves fresh list, backs off, and falls back when six hours pass',
    () async {
      setup([roundId], prod: true);
      final refresh = container.read(votingHomeRefreshProvider);
      await refresh.refresh();
      final saved = store.value;
      discovery.fail = true;
      await refresh.refresh();
      await refresh.refresh();
      expect(discovery.calls, 2);
      expect(api.calls, 1);
      expect(store.value, saved);
      now = now.add(const Duration(hours: 6));
      await refresh.refresh();
      expect(api.calls, 2);
    },
  );

  test(
    'first visit can discover directly while the probe is unavailable',
    () async {
      setup([roundId], prod: true);
      discovery.fail = true;
      await container.read(votingHomeRefreshProvider).refresh();
      expect(api.calls, 1);
      expect(store.value, isNotNull);
    },
  );

  test(
    'concurrent prod triggers share the probe and source changes discard it',
    () async {
      setup([roundId], prod: true);
      discovery.gate = Completer<void>();
      final refresh = container.read(votingHomeRefreshProvider);
      final first = refresh.refresh();
      final second = refresh.refresh();
      while (discovery.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(discovery.calls, 1);
      (container.read(votingConfigSourceProvider.notifier) as _Source).select(
        'custom',
      );
      discovery.gate!.complete();
      await Future.wait([first, second]);
      expect(store.value, null);
      expect(api.calls, 0);
    },
  );

  test(
    'endpoint replacement does not reuse another endpoints applied revision',
    () async {
      setup([roundId], prod: true);
      final refresh = container.read(votingHomeRefreshProvider);
      await refresh.refresh();
      endpoint = 'https://other.example/discovery';
      container.invalidate(votingDiscoveryEndpointProvider);
      await refresh.refresh();
      expect(api.calls, 2);
    },
  );

  test('custom source never contacts production discovery', () async {
    setup([roundId]);
    await container.read(votingHomeRefreshProvider).refresh();
    expect(discovery.calls, 0);
  });
  test(
    'new source trigger during a probe runs after the obsolete request drains',
    () async {
      setup([roundId], prod: true);
      discovery.gate = Completer<void>();
      final refresh = container.read(votingHomeRefreshProvider);
      final first = refresh.refresh();
      while (discovery.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      (container.read(votingConfigSourceProvider.notifier) as _Source).select(
        'custom',
      );
      final next = refresh.refresh();
      discovery.gate!.complete();
      await Future.wait([first, next]);
      expect(discovery.calls, 1);
      expect(api.calls, 1);
      expect(
        container
            .read(votingHomeCacheProvider.notifier)
            .list(votingHomeListKey('main', 'custom')),
        isNotNull,
      );
    },
  );

  test(
    'reset drains the lightweight probe and prevents later cache writes',
    () async {
      setup([roundId], prod: true);
      discovery.gate = Completer<void>();
      final first = container.read(votingHomeRefreshProvider).refresh();
      while (discovery.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final registry = container.read(votingShareTrackingRegistryProvider);
      var drained = false;
      final drain = registry.quiesceAndDrain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, false);
      discovery.gate!.complete();
      await Future.wait([first, drain]);
      expect(store.value, null);
      registry.resume();
    },
  );
  test(
    'legacy fresh list gains discovery metadata without losing account facts',
    () async {
      setup([roundId], prod: true);
      final key = votingHomeListKey(
        'main',
        kProductionStaticVotingConfigSource,
      );
      final cache = container.read(votingHomeCacheProvider.notifier);
      await cache.recordList(
        key,
        VotingHomeRoundList(
          checkedAt: now,
          fingerprint: 'fingerprint',
          rounds: [round()],
        ),
      );
      await cache.recordEligibility('account-fact', false, 100);
      await container.read(votingHomeRefreshProvider).refresh();
      expect(api.calls, 1);
      expect(cache.list(key)?.discoveryRevision, discovery.revision);
      expect(
        cache.fact('account-fact').eligibility,
        VotingHomeEligibility.ineligible,
      );
      // A normal voting screen refresh cannot discard the last applied revision.
      await cache.recordList(
        key,
        VotingHomeRoundList(
          checkedAt: now,
          fingerprint: 'fingerprint',
          rounds: [round()],
        ),
      );
      container.invalidate(votingHomeCacheProvider);
      await container.read(votingHomeRefreshProvider).refresh();
      expect(api.calls, 1);
    },
  );
  test(
    'testnet stage probes its own endpoint and reuses its revision',
    () async {
      setup([roundId], stage: true);
      final refresh = container.read(votingHomeRefreshProvider);
      await refresh.refresh();
      await refresh.refresh();
      expect(discovery.scopes, [
        VotingDiscoveryScope.stage,
        VotingDiscoveryScope.stage,
      ]);
      expect(discovery.endpoints.toSet(), {Uri.parse(votingDiscoveryStageUrl)});
      expect(api.calls, 1);
      final cache = container.read(votingHomeCacheProvider.notifier);
      expect(
        cache
            .list(votingHomeListKey('test', kStageStaticVotingConfigSource))
            ?.discoveryRevision,
        discovery.revision,
      );
      expect(
        cache.list(
          votingHomeListKey('main', kProductionStaticVotingConfigSource),
        ),
        null,
      );
    },
  );

  test(
    'network and source switch during prod request only applies stage result',
    () async {
      setup([roundId], prod: true);
      discovery.gate = Completer<void>();
      final refresh = container.read(votingHomeRefreshProvider);
      final first = refresh.refresh();
      while (discovery.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      (container.read(rpcEndpointProvider.notifier) as _Rpc).select('test');
      (container.read(votingConfigSourceProvider.notifier) as _Source).select(
        kStageStaticVotingConfigSource,
      );
      final second = refresh.refresh();
      discovery.gate!.complete();
      await Future.wait([first, second]);
      expect(discovery.scopes, [
        VotingDiscoveryScope.prod,
        VotingDiscoveryScope.stage,
      ]);
      expect(api.calls, 1);
      expect(
        container
            .read(votingHomeCacheProvider.notifier)
            .list(
              votingHomeListKey('main', kProductionStaticVotingConfigSource),
            ),
        null,
      );
    },
  );

  test(
    'mismatched network/source and custom configs never opt into discovery',
    () {
      expect(
        votingDiscoveryScopeForSource('main', kStageStaticVotingConfigSource),
        null,
      );
      expect(
        votingDiscoveryScopeForSource(
          'test',
          kProductionStaticVotingConfigSource,
        ),
        null,
      );
      expect(votingDiscoveryScopeForSource('test', 'custom'), null);
      expect(
        votingDiscoveryScopeForSource(
          'regtest',
          kStageStaticVotingConfigSource,
        ),
        null,
      );
      expect(
        votingDiscoveryScopeForSource('test', kStageStaticVotingConfigMirror),
        VotingDiscoveryScope.stage,
      );
    },
  );
}

class _CleanupCache extends VotingFileCache {
  final removed = <String>[];
  @override
  Future<void> removeRound(String network, String round) async {
    removed.add('$network|$round');
  }
}
