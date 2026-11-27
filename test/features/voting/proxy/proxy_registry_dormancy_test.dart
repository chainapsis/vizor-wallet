import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_registry_store.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_config_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_file_cache.dart';

import '../../../services/voting/fake_voting_http.dart';
import 'support/proxy_registry_fakes.dart';
import 'support/proxy_rust_fake.dart';

void main() {
  useProxyRustFake();
  setUp(() => proxyRust.registry = FakeProxyRegistryRust());
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('proxy-registry-dormancy-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// A container whose registry state lives under [root], with the dormant
  /// flag [enabled].
  ProviderContainer container({required bool enabled}) {
    final container = ProviderContainer(
      overrides: [
        proxyDelegationFeatureEnabledProvider.overrideWithValue(enabled),
        proxyRegistryStoreProvider.overrideWithValue(
          ProxyRegistryStore(VotingFileCache(directory: () async => root)),
        ),
        proxyRegistryNetworkProvider.overrideWithValue('main'),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('with the flag off the config loader carries no proxy hook, so a '
      'load fetches and stores nothing new', () {
    final off = container(enabled: false);
    expect(off.read(proxyDynamicConfigObserverProvider), isNull);
    expect(off.read(votingConfigLoaderProvider).onDynamicConfigFetched, isNull);
  });

  test('a full config load makes the same two requests and stores nothing, '
      'with the flag off or on', () async {
    const staticUrl = 'https://voting.example/static.json';
    const dynamicUrl = 'https://voting.example/dynamic.json';
    for (final enabled in [false, true]) {
      final http = FakeVotingHttpClient(
        responses: {
          staticUrl: '{"static":true}',
          dynamicUrl: utf8.decode(fakeDynamicConfig()),
        },
      );
      await VotingConfigLoader(
        httpClient: http,
        sourceUrl: staticUrl,
        onDynamicConfigFetched: container(
          enabled: enabled,
        ).read(proxyDynamicConfigObserverProvider),
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async => [dynamicUrl],
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async => rust_config_api.VotingConfigResolution(
              config: _configWithRound(kRegistryTestRoundId),
              switchKind: rust_config.ConfigSwitchKind.initialLoad,
              skippedMirrors: const [],
            ),
      ).load();

      expect(http.requests.map((request) => request.uri.toString()), [
        staticUrl,
        dynamicUrl,
      ]);
      final stored = root
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.substring(root.path.length));
      expect(stored, isEmpty, reason: 'flag ${enabled ? 'on' : 'off'}');
    }
  });

  test('with the flag on each load names the proxy service URLs', () async {
    final on = container(enabled: true);
    final hook = on.read(votingConfigLoaderProvider).onDynamicConfigFetched;
    expect(hook, isNotNull);

    await hook!(
      fakeConfigFetch([
        fakeDynamicConfig(proofRpcUrls: ['https://rpc.example']),
      ]),
    );

    expect(on.read(proxyServiceSourcesProvider).of('main')?.proofRpcUrls, [
      'https://rpc.example',
    ]);
  });

  test('deletion clears the stored state and the sources only while the '
      'flag is on', () async {
    final stored = File(
      '${root.path}/$kProxyRegistryCacheFolder/main/wallet-list.json',
    );
    await stored.parent.create(recursive: true);
    await stored.writeAsString('');

    final off = container(enabled: false);
    await off.read(proxyRegistryDeletionProvider)();
    expect(await stored.exists(), isTrue);

    final on = container(enabled: true);
    await on.read(proxyDynamicConfigObserverProvider)!(
      fakeConfigFetch([fakeDynamicConfig()]),
    );
    expect(on.read(proxyServiceSourcesProvider).of('main'), isNotNull);
    await on.read(proxyRegistryDeletionProvider)();
    expect(
      Directory('${root.path}/$kProxyRegistryCacheFolder').existsSync(),
      isFalse,
    );
    expect(on.read(proxyServiceSourcesProvider).of('main'), isNull);
  });

  test(
    'wallet reset wipes the registry state with the voting caches',
    () async {
      final stored = File(
        '${root.path}/zcash_wallet.db.voting-cache/'
        '$kProxyRegistryCacheFolder/main/wallet-list.json',
      );
      await stored.parent.create(recursive: true);
      await stored.writeAsString('');
      await clearVotingCachesForReset(
        resolveSupportDirectory: () async => root,
      );
      expect(await stored.exists(), isFalse);
    },
  );
}

/// A resolved voting config that authenticates [roundId] alone.
rust_config.ResolvedVotingConfig _configWithRound(String roundId) =>
    rust_config.ResolvedVotingConfig(
      sourceFingerprint: 'source-fp',
      trustedKeyFingerprint: 'key-fp',
      dynamicConfigFingerprint: 'dynamic-fp',
      voteServers: const [
        rust_config.ServiceEndpoint(
          url: 'https://voting.example',
          label: 'vote',
        ),
      ],
      pirEndpoints: const [],
      pirLayout: const rust_config.PirLayout(
        pirDepth: 19,
        tier0Layers: 12,
        tier1Layers: 7,
        polyLen: 4096,
      ),
      supportedVersions: const rust_config.SupportedVersions(
        pir: ['v0'],
        voteProtocol: 'v0',
        tally: 'v0',
        voteServer: 'v1',
      ),
      authenticatedRounds: [
        rust_config.AuthenticatedRound(
          roundId: roundId,
          eaPk: Uint8List.fromList(List.filled(32, 1)),
        ),
      ],
      skippedRoundIds: const [],
      conditions: const [],
    );
